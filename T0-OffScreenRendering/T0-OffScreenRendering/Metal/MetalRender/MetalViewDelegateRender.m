//
//  MTKViewDelegateRender.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "MetalViewDelegateRender.h"
#import <Metal/Metal.h>

#import "ShaderType.h"
#import "MetalView.h"

@implementation MetalViewDelegateRender
{
    id <MTLCommandQueue> _commandQueue ;
    
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    
    id <MTLBuffer> _vertexbuffer ;
    id <MTLBuffer> _vertexbuffer2;
}

#pragma mark - Constructor

-(nonnull instancetype) initWithMetalView:(MetalView *) view
{
    self = [super init];
    if (self) {
        [self _setupMetalView:view];
        [self _setupRenderPass:view];
        [self _loadAssets:view.device];

    } else {
        NSLog(@"initWithMetalKitView super init fail");
    }
    return self ;
}

#pragma mark - MTKView setup
- (void) _setupMetalView:(MetalView*) view
{
    // view 需要提供的 如下格式的 颜色纹理/深度纹理/模版纹理
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB ;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ; // MetalView会创建对应纹理
    view.depthStencilPixelFormat = MTLPixelFormatInvalid;

    view.sampleCount = 1 ;
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
    
    // CAMetalLayer应该处理这个 ???
}


#pragma mark - Render setup
- (void) _setupRenderPass:(MetalView*) view
{

    MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    
    id<MTLDevice> gpu = view.device;
    id<MTLLibrary> library = [gpu newDefaultLibrary];
    id<MTLFunction> vertextFunction =  [library newFunctionWithName:@"MyVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"MyFragmentShader"];
    
    pipelineStateDescriptor.vertexFunction = vertextFunction ;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
    
    // 这些代表这个 RenderPipeLineState (shader)期望要有的附件
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat ;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat ;
    pipelineStateDescriptor.sampleCount = view.sampleCount ;
    
    
    pipelineStateDescriptor.label = @"MyPipeline" ;
    
    
    // 这里根据描述符 MTLRenderPipelineDescriptor 创建 MTLRenderPipelineState
    NSError* error = NULL;
    _pipelineState = [view.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
        // FIXME(hhl) 处理
    }
    
    MTLDepthStencilDescriptor * depthStencilStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilStateDesc.depthCompareFunction = MTLCompareFunctionLess ;   // 深度测试函数 glDepthFunc(GL_LESS)
    depthStencilStateDesc.depthWriteEnabled = YES;                          // 深度可写 glEnable(GL_DEPTH_TEST)
    _depthState = [view.device newDepthStencilStateWithDescriptor:depthStencilStateDesc];
    
    // 使用设备上下文创建了全局唯一的指令队列对象
    _commandQueue = [view.device newCommandQueue];
    
}

- (void) _loadAssets:(id<MTLDevice>) device
{
    static const Vertex vert[] = {
        {  {-1.0, 1.0}  },
        {  { 0.0, 0.0}  },
        {  {-1.0, 0.0}  }
    };
    _vertexbuffer = [device newBufferWithBytes:vert length:sizeof(vert) options:MTLResourceStorageModeShared];
    
    static const Vertex vert2[] = {
        {  {1.0, 0.0}  },
        {  {0.0, -1.0}  },
        {  {1.0, -1.0 } }
    };
    _vertexbuffer2 = [device newBufferWithLength:sizeof(vert2) options:MTLResourceStorageModeShared];
    memcpy(_vertexbuffer2.contents, vert2, sizeof(vert2));
    //_vertexbuffer2 = [device newBufferWithBytes:vert2 length:sizeof(vert) options:MTLResourceStorageModeShared];
    
}


#pragma mark - MTKViewDelegate

//- (void) drawInMTKView:(nonnull MTKView *)view
-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MetalView*) view
{
         
    MTLRenderPassDescriptor* framebuffer = view.currentRenderPassDescriptor;
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    commandBuffer.label = @"ParallelCommand";

    id <MTLParallelRenderCommandEncoder> parallelRCE = [commandBuffer parallelRenderCommandEncoderWithDescriptor:framebuffer];
    
    id <MTLRenderCommandEncoder> rCE1 = [parallelRCE renderCommandEncoder];
    {
        rCE1.label = @"rCE1";
        [rCE1 pushDebugGroup:@"rCE1Dbg"];
        
        // failed assertion `Framebuffer With Render Pipeline State Validation
        // For color attachment 0, the render pipeline's pixelFormat (MTLPixelFormatBGRA8Unorm_sRGB) does not match the framebuffer's pixelFormat (MTLPixelFormatBGRA8Unorm).
        // For depth attachment, the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set.
        // For stencil attachment, the renderPipelineState pixelFormat must be MTLPixelFormatInvalid, as no texture is set.
        
        // RenderPipelineState的pixelFormat 跟 Framebuffer(RenderPassDescriptor)的pixelFormat 不一样的  会出现asset
        
        [rCE1 setRenderPipelineState:_pipelineState];
        [rCE1 setVertexBuffer:_vertexbuffer offset:0 atIndex:0];
        [rCE1 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
        [rCE1 popDebugGroup];
    }
    
     
    id <MTLRenderCommandEncoder> rCE2 = [parallelRCE renderCommandEncoder];
    {
        rCE2.label = @"rCE2";
        [rCE2 pushDebugGroup:@"rCE2Dbg"];
        
        
        [rCE2 setRenderPipelineState:_pipelineState];
        [rCE2 setVertexBuffer:_vertexbuffer2 offset:0 atIndex:0];
        [rCE2 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        
        
        [rCE2 popDebugGroup];
    }
    
    
    
    [rCE2 endEncoding]; // 跟结束的位置没有关系 跟创建的位置有关系
    [rCE1 endEncoding];
    
    [parallelRCE endEncoding];// failed assertion `encoding in progress'
    
    
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
    
    
}



// - (void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
-(void) OnDrawableSizeChange:(CGSize)size WithView:(MetalView*) view
{
    NSLog(@"View Size Change To %f,%f", size.width, size.height);
}

@end
