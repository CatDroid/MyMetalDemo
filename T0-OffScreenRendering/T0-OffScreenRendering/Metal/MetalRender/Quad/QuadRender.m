//
//  QuadRender.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/26.
//

#import "QuadRender.h"
#import "QuadShaderType.h"

@implementation QuadRender
{
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthStenilState;
    QuadMesh* _mesh ;
    id<MTLBuffer> _viewPortScalerUniformBuffer;
    int32_t _frameNumber ;
    
}

-(instancetype) initWithDevice:(id<MTLDevice>) gpu WithSize:(CGSize)size
{
    self = [super init];
    if (self)
    {
        // 如果不是同一个gpu 是否会有问题 ???
        
        id<MTLLibrary> shaderLib = [gpu newDefaultLibrary];
        if(!shaderLib)
        {
            NSLog(@" ERROR: Couldnt create a default shader library");
            // assert here because if the shader libary isn't loading, nothing good will happen
            return nil;
        }

        id <MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"ColorMeshVertexShader"];
        if(!vertexProgram)
        {
            NSLog(@">> ERROR: Couldn't load vertex function from default library");
            return nil;
        }

        id <MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"ColorMeshFragmentShader"];
        if(!fragmentProgram)
        {
            NSLog(@" ERROR: Couldn't load fragment function from default library");
            return nil;
        }
        
        MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.label                           = @"QuadPipeline";
        pipelineDescriptor.vertexFunction                  = vertexProgram;
        pipelineDescriptor.fragmentFunction                = fragmentProgram;
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        
        pipelineDescriptor.colorAttachments[0].blendingEnabled = NO; // default is no !
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        // MTLBlendFactorOne; MTLBlendFactorZero; // 默认 src factor是1  dst factor是0 相当于直接用soruce的颜色
      
        pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ;
        pipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        
        NSError *error;
        _pipelineState = [gpu newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                             error:&error];
        
        NSAssert(_pipelineState, @"ERROR: Failed aquiring pipeline state: %@", error);
     
        
        MTLDepthStencilDescriptor* desc = [[MTLDepthStencilDescriptor alloc] init];
        desc.depthCompareFunction = MTLCompareFunctionLess;
        desc.depthWriteEnabled = true ;
        MTLStencilDescriptor* stencilDesc = [[MTLStencilDescriptor alloc]init];
        stencilDesc.stencilCompareFunction = MTLCompareFunctionAlways; // alawy pass
        stencilDesc.readMask = 0xFF; // 对比时使用，默认全1，即不修改原值
        stencilDesc.writeMask = 0xFF;
        stencilDesc.stencilFailureOperation = MTLStencilOperationKeep;  // 先模板后深度测试
        stencilDesc.depthFailureOperation = MTLStencilOperationKeep ;   // 这里配置成模板和深度测试其中一个fail就不写入 模板附件
        stencilDesc.depthStencilPassOperation =  MTLStencilOperationReplace ; // 模版和深度测试通过 就替换/写入 模板附件
        desc.frontFaceStencil = stencilDesc;
        desc.backFaceStencil  = stencilDesc;
        _depthStenilState = [gpu newDepthStencilStateWithDescriptor:desc];
        
        NSAssert(_depthStenilState, @"ERROR: Failed to newDepthStencilStateWithDescriptor");
        
        _mesh = [[QuadMesh alloc] initWithDevice:gpu];
        
        _viewPortScalerUniformBuffer = [gpu newBufferWithLength:sizeof(ViewPortScaler) options:MTLResourceStorageModeShared];
        ViewPortScaler* unformBuffer = (ViewPortScaler*)_viewPortScalerUniformBuffer.contents;
        unformBuffer->scaler = 1.0;
        unformBuffer->viewport = (vector_float2){1.0, size.width/size.height};
        
    }
    return self ;
}

-(BOOL) renderOnFrameBuffer:(MetalFrameBuffer*) framebuffer
            OnCommandBuffer:(id<MTLCommandBuffer>) buffer
           WithInputTexture:(nullable id<MTLTexture>) input
                   WithMesh:(nullable QuadMesh*) mesh
{
    return [self renderOnPass:framebuffer.renderPassDescriptor
              OnCommandBuffer:buffer
             WithInputTexture:input
                     WithMesh:mesh];
}

-(BOOL) renderOnPass:(MTLRenderPassDescriptor*) renderPass
     OnCommandBuffer:(id<MTLCommandBuffer>) buffer
    WithInputTexture:(nullable id<MTLTexture>) input
            WithMesh:(nullable QuadMesh*) mesh
{

    _frameNumber = _frameNumber + 1 ;
    
    ViewPortScaler* unformBuffer = (ViewPortScaler*)_viewPortScalerUniformBuffer.contents;
    unformBuffer->scaler =  1.0 + 0.5 * sin(_frameNumber * 0.1);
    
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:renderPass];
    encoder.label = @"QuadRender";
    
    // encoder setViewport:(MTLViewport)
    // encoder setViewports:(const MTLViewport * _Nonnull) count:(NSUInteger)  // 多个viewpoints ??
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setDepthStencilState:_depthStenilState];
    [encoder setVertexBuffer:_mesh.vertexBuffer offset:0 atIndex:kQuadVertexColorBufferIndex];
    [encoder setVertexBuffer:_viewPortScalerUniformBuffer offset:0 atIndex:kViewPortScalerUniformBufferIndex];
    
    /*
     setVertexBytes 不创建 MTLVertexBuffer的方式
     
     缓冲区管理:
        使用这个方法相当于从指定的数据创建一个新的 MTLBuffer 对象， newBufferWithLength:options:
        然后将它绑定到顶点着色器，使用 setVertexBuffer:offset:atIndex: 方法。
        但是，这种方法避免了创建缓冲区来存储数据的开销；相反，Metal管理数据
     
     4KB:
        对小于 4KB 的一次性数据使用此方法
        如果您的数据长度超过 4 KB 或持续多次使用，请创建一个 MTLBuffer 对象。
     
     
    [renderEncoder setVertexBytes:&uniforms
                           length:sizeof(uniforms)
                          atIndex:kViewPortScalerUniformBufferIndex ];
     */
    
    [encoder drawPrimitives:_mesh.primitiveType vertexStart:0 vertexCount:_mesh.vertexCount];
    
    [encoder endEncoding];
    
    return true ;
}


@end
