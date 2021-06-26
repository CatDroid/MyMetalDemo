//
//  ParallelTriangleRender.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import "ParallelTriangleRender.h"
#import "ShaderType.h"
#import "ParallelTriangleMesh.h"

// 使用帧捕捉器：
//      查看每个render encoder的 所有附件(attachmensts)
//      当前指令之后该encoder绑定的资源(bound resources)
//      该指令后所有绑定资源(all resources)
//
//  目前发现
//      在并行编码器ParallelRenderCommandEncoder下查看Attachments会看不到
//      在渲染编码器RenderComandEncoder下 就可以看到所有Attachments


// 打开这个 会发现 renderEncoderx下的Attachments只有了color一个附件
// 这样如果当前pipeline state没有定义深度模板格式 但是原来的render pass/framebuffer设置了深度模板格式 copy一个render pass清除掉深度和模板纹理就可以
#define DONT_USE_DEPTH_STENCIL 1

@implementation ParallelTriangleRender
{
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    
    ParallelTriangleMesh* _mesh ;
}


-(instancetype) initWithDevice:(id<MTLDevice>) gpu
{
    self = [super init];
    if (self) {
        
        MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        
        id<MTLLibrary> library = [gpu newDefaultLibrary];
        id<MTLFunction> vertextFunction =  [library newFunctionWithName:@"MyVertexShader"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"MyFragmentShader"];
        
        pipelineStateDescriptor.vertexFunction = vertextFunction ;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
        
        // 这些代表这个 RenderPipeLineState (shader)期望要有的附件
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; //view.colorPixelFormat;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES; //启用混合
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        
#if DONT_USE_DEPTH_STENCIL
        pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatInvalid ;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatInvalid ;
#else
        pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8; //view.depthStencilPixelFormat ;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;  //view.depthStencilPixelFormat ;
#endif
        pipelineStateDescriptor.sampleCount = 1 ; // view.sampleCount ;
        
        
        pipelineStateDescriptor.label = @"MyPipeline" ;
        
        
        // 这里根据描述符 MTLRenderPipelineDescriptor 创建 MTLRenderPipelineState
        NSError* error = NULL;
        _pipelineState = [gpu newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!_pipelineState)
        {
            NSLog(@"Failed to created pipeline state, error %@", error);
            // FIXME(hhl) 处理
        }
        
#if DONT_USE_DEPTH_STENCIL
#else
        MTLDepthStencilDescriptor * depthStencilStateDesc = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilStateDesc.depthCompareFunction = MTLCompareFunctionLess ;   // 深度测试函数 glDepthFunc(GL_LESS)
        depthStencilStateDesc.depthWriteEnabled = YES;                          // 深度可写 glEnable(GL_DEPTH_TEST)
        _depthState = [gpu newDepthStencilStateWithDescriptor:depthStencilStateDesc];
#endif
        
        _mesh = [[ParallelTriangleMesh alloc] initWithDevice:gpu];
        
        
    } else {
        NSLog(@"initWithDevice super init fail");
    }
    return self;
}

-(BOOL) renderOnFrameBuffer:(MetalFrameBuffer*) framebuffer
            OnCommandBuffer:(id<MTLCommandBuffer>) buffer
           WithInputTexture:(nullable id<MTLTexture>) input
                   WithMesh:(nullable ParallelTriangleMesh*) mesh
{
    return [self renderOnPass:framebuffer.renderPassDescriptor
              OnCommandBuffer:buffer
             WithInputTexture:input
                     WithMesh:mesh];
}

-(BOOL) renderOnPass:(MTLRenderPassDescriptor*) renderPass
     OnCommandBuffer:(id<MTLCommandBuffer>) commandBuffer
    WithInputTexture:(nullable id<MTLTexture>) input
            WithMesh:(nullable ParallelTriangleMesh*) mesh
{
 
#if DONT_USE_DEPTH_STENCIL
    MTLRenderPassDescriptor* rp = [renderPass copy];
    rp.depthAttachment.texture = nil ;
    rp.stencilAttachment.texture = nil;
    renderPass = rp ;
#endif
    
    
    id <MTLParallelRenderCommandEncoder> parallelRCE = [commandBuffer parallelRenderCommandEncoderWithDescriptor:renderPass];
    parallelRCE.label = @"ParallelTriangle";
    

    id <MTLRenderCommandEncoder> rCE1 = [parallelRCE renderCommandEncoder];
    {
        rCE1.label = @"rCE1";
        [rCE1 pushDebugGroup:@"rCE1Dbg"];
        
        /*
            Metal API Validation Enabled  metal api诊断开关配置
                Product -- Scheme -- Edit Scheme -- Run --- Diagnositics --- Metal API Validation 还有 Metal Shader Validation
         
            如果 render pass(创建纹理格式) 和 pipeline state的格式不一样，就会触发Validaton Assert
                failed assertion `Framebuffer With Render Pipeline State Validation
         
                For color attachment 0, the render pipeline's pixelFormat (MTLPixelFormatBGRA8Unorm_sRGB)
                        does not match the framebuffer's pixelFormat (MTLPixelFormatBGRA8Unorm).
                For depth attachment, the render pipeline's pixelFormat (MTLPixelFormatInvalid)
                        does not match the framebuffer's pixelFormat (MTLPixelFormatDepth32Float_Stencil8).
                For stencil attachment, the render pipeline's pixelFormat (MTLPixelFormatInvalid)
                        does not match the framebuffer's pixelFormat (MTLPixelFormatDepth32Float_Stencil8).
         
            格式一定要设置一样，但是深度检测可以不配置，也就是不设置 setDepthStencilState 不会做深度测试和深度写入
         
            如果 render pass没有设置纹理(相当于renderpass格式是Invalid) 那么 pipeline state 必须是 MTLPixelFormatInvalid 
                For depth attachment, the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set.
                For stencil attachment, the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set.
         
           
                
            
         */
 
        [rCE1 setRenderPipelineState:_pipelineState];
#if DONT_USE_DEPTH_STENCIL
#else
        [rCE1 setDepthStencilState:_depthState];
#endif
        [rCE1 setVertexBuffer:_mesh.vertexBuffer offset:_mesh.vertexBufferOffset atIndex:0]; // _mesh.vertexBufferIndex
        [rCE1 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
        [rCE1 popDebugGroup];
    }
    
     
    id <MTLRenderCommandEncoder> rCE2 = [parallelRCE renderCommandEncoder];
    {
        rCE2.label = @"rCE2";
        [rCE2 pushDebugGroup:@"rCE2Dbg"];
        
        [rCE2 setRenderPipelineState:_pipelineState];
#if DONT_USE_DEPTH_STENCIL
#else
        [rCE2 setDepthStencilState:_depthState]; // 调用这个api参数不能是nil, // failed assertion `depthStencilState must not be nil.'
#endif
        [rCE2 setVertexBuffer:_mesh.vertexBuffer2 offset:_mesh.vertexBuffer2Offset atIndex:0]; // _mesh.vertexBuffer2Index
        [rCE2 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
        [rCE2 popDebugGroup];
    }
    
    // 跟结束的位置没有关系 跟创建的位置有关系
    [rCE2 endEncoding];
    [rCE1 endEncoding];
    
    // 不调用的会出现崩溃 failed assertion `encoding in progress'
    [parallelRCE endEncoding];
    
    return true ;
}



@end
