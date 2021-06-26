//
//  ParallelTriangleRender.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import "ParallelTriangleRender.h"
#import "ShaderType.h"
#import "ParallelTriangleMesh.h"

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
        
        pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8; //view.depthStencilPixelFormat ;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;  //view.depthStencilPixelFormat ;
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
        
        MTLDepthStencilDescriptor * depthStencilStateDesc = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilStateDesc.depthCompareFunction = MTLCompareFunctionLess ;   // 深度测试函数 glDepthFunc(GL_LESS)
        depthStencilStateDesc.depthWriteEnabled = YES;                          // 深度可写 glEnable(GL_DEPTH_TEST)
        _depthState = [gpu newDepthStencilStateWithDescriptor:depthStencilStateDesc];
        
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
 
    id <MTLParallelRenderCommandEncoder> parallelRCE = [commandBuffer parallelRenderCommandEncoderWithDescriptor:renderPass];
    parallelRCE.label = @"ParallelTriangle";
    

    id <MTLRenderCommandEncoder> rCE1 = [parallelRCE renderCommandEncoder];
    {
        rCE1.label = @"rCE1";
        [rCE1 pushDebugGroup:@"rCE1Dbg"];
        
        // Metal API Validation Enabled
        // Product -- Scheme -- Edit Scheme -- Run --- Diagnositics --- Metal API Validation 还有 Metal Shader Validation
        
        // failed assertion `Framebuffer With Render Pipeline State Validation
        // For color attachment 0, the render pipeline's pixelFormat (MTLPixelFormatBGRA8Unorm_sRGB) does not match the framebuffer's pixelFormat (MTLPixelFormatBGRA8Unorm).
        // For depth attachment, the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set.
        // For stencil attachment, the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set.
        
        // RenderPipelineState的pixelFormat 跟 Framebuffer(RenderPassDescriptor)的pixelFormat 不一样的  会出现asset
        
        [rCE1 setRenderPipelineState:_pipelineState];
        [rCE1 setDepthStencilState:_depthState];
        [rCE1 setVertexBuffer:_mesh.vertexBuffer offset:_mesh.vertexBufferOffset atIndex:0]; // _mesh.vertexBufferIndex
        [rCE1 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
        [rCE1 popDebugGroup];
    }
    
     
    id <MTLRenderCommandEncoder> rCE2 = [parallelRCE renderCommandEncoder];
    {
        rCE2.label = @"rCE2";
        [rCE2 pushDebugGroup:@"rCE2Dbg"];
        
        [rCE2 setRenderPipelineState:_pipelineState];
        [rCE2 setDepthStencilState:_depthState];
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
