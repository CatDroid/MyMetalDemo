//
//  MTKViewDelegateRender.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "MTKViewDelegateRender.h"
#import "ShaderTypes.h"

@implementation MTKViewDelegateRender
{
    // id
    // id can hold any type of object.
    //
    // id<GAITracker> tracker
    // This means the tracker is an id type object,which can hold objects those confirms to GAITracker protocol
    //id <MTLDevice> _device ;
    id <MTLCommandQueue> _commandQueue ; // <MTLCommandQueue> 代表设置给_commandQueue的对象要实现MTLCommandQueue协议
    
    id <MTLRenderPipelineState> _pipelineState; // 片元顶点着色器 颜色深度模板缓冲区格式
    id <MTLDepthStencilState> _depthState;      // 深度测试方式和是否可写
    
    id <MTLBuffer> _vertexbuffer ; // MTLResource的子类(子协议)
    
}

#pragma mark - Constructor

-(nonnull instancetype) initWithCALayer:(CAMetalLayer*) layer
{
    self = [super init];
    if (self) {
        //[self _setupMTKView:view];
        [self _setupRenderPass:layer];
        [self _loadAssets:layer.device];
        
    } else {
        NSLog(@"initWithMetalKitView super init fail");
    }
    return self ;
}

#pragma mark - MTKView setup
- (void) _setupMTKView:(MTKView*) view
{
    /*
     格式 用于创建 depthStencilTexture 对象  drawable对象中纹理 depthStencilTexture
     默认值为 MTLPixelFormatInvalid，这意味着视图不会创建深度和模板纹理。
     如果您将其设置为不同的格式，视图会自动为您创建这些纹理，
     并把这些纹理 作为 这个视图创建的任何渲染通道(render pass) 的一部分配置
     */
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ; // 深度缓冲用32bit 模版缓冲用8bit
    /*
     默认值为 MTLPixelFormatBGRA8Unorm.
     
     MTLPixelFormatBGRA8Unorm_sRGB
     // 颜色缓冲区
     // U unsiged
     // norm是归一化 4个8bit归一化无符号整数
     // 顺序是 BGRA
     // 颜色空间是 sRGB
     */
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB ; // 颜色纹理/深度纹理/模版纹理

    /*
     对sample count的取值因设备对象而异
     调用 supportsTextureSampleCount: 方法来确定设备对象是否支持您想要的ample count
     默认值为 1。
     当您设置的值大于 1 时，视图view会创建并配置一组 多重采样纹理 的 中间集。
     像素格式与 某个指定的可绘制对象 格式相同
     
     当视图创建 render pass descriptor, 时，
     render pass 使用这些中间纹理作为颜色渲染目标，
     并通过存储操作 将这些多采样纹理解析为 可绘制对象drawable 的纹理
     (MTLStoreActionMultisampleResolve)。
     
     sampleCount指的是每个像素的颜色采样个数，正常情况每个像素只采样一个，
     而在某些情况下，例如需要实现MSAA等抗锯齿算法的时候，则可能将采样数设置为4或者更多
     */
    view.sampleCount = 1 ;
}


#pragma mark - Render setup
- (void) _setupRenderPass:(CAMetalLayer*) layer
{
    id<MTLDevice> gpu = layer.device;
    
    id<MTLLibrary> library = [gpu newDefaultLibrary];
    
 
    id<MTLFunction> vertextFunction =  [library newFunctionWithName:@"myVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"myFragmentShader"];
    
    MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    
    pipelineStateDescriptor.vertexFunction = vertextFunction ;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
    
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat;
    //pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat ;
    //pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat ;
    
    //pipelineStateDescriptor.sampleCount = view.sampleCount ;
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
    
    // 使用设备上下文创建了全局唯一的指令队列对象
    _commandQueue = [gpu newCommandQueue];
    
}

// Metal使用MTLResource管理内存，使用MTLDevice实例创建内存（实际使用MTLBuffer表示创建的buffer，是MTLResource的子类）
- (void) _loadAssets:(id<MTLDevice>) gpu
{
    static const Vertex vert[] = {
        {  {0,    1.0}  },
        {  {1.0, -1.0}  },
        {  {-1.0,-1.0}  }
    };
    _vertexbuffer = [gpu newBufferWithBytes:vert length:sizeof(vert) options:MTLResourceStorageModeShared];
}


#pragma mark - MTKViewDelegate
- (void) drawWithLayer:(nonnull CAMetalLayer *) layer
{
    id <CAMetalDrawable> drawable = nil ;
    
    int tryCount = 0 ;
    
    // 它使用 CAMetalLayer 对象来保存视图的内容
    while (!drawable) {
        drawable = [layer nextDrawable];
        tryCount ++;
        if (tryCount > 1) {
            NSLog(@"CAMetalLayer nextDrawable try %i", tryCount);
        }
    }
    
    /*
     创建默认的 render pass desc.
 
     使用 colorAttachments 属性的方法 setObject:atIndexedSubscript:设置所需的颜色附件
     分别使用 depthAttachment 和 stencilAttachment 属性设置所需的深度和模板附件
     */
    MTLRenderPassDescriptor* framebuffer = [MTLRenderPassDescriptor renderPassDescriptor];
    
    MTLRenderPassColorAttachmentDescriptor* colorAttachmenDesc = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
    colorAttachmenDesc.clearColor = MTLClearColorMake(0.0, 0.0, 1.0, 1.0);
    colorAttachmenDesc.texture = drawable.texture ; // !! 这里跟layer的drawable中的MTLTexture 关联上 !!
    colorAttachmenDesc.loadAction = MTLLoadActionClear ; // ????
    colorAttachmenDesc.storeAction = MTLStoreActionStore; // ???
    
    [framebuffer.colorAttachments setObject:colorAttachmenDesc atIndexedSubscript:0]; // render pass的颜色0号附件
    // 如果要做深度测试。这个 renderPassDesc 必须要配置 深度attachment
    
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
         
    // 创建命令编码器 用于 把一个即将要渲染的pass编码到buffer中
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:framebuffer]; //这是一个跟view相关的 *****
    renderEncoder.label = @"MyRenderEncoder";
    
    [renderEncoder pushDebugGroup:@"DrawTriangle"];
    [renderEncoder setRenderPipelineState:_pipelineState];  // 着色器 颜色输出缓冲区格式
    // [renderEncoder setDepthStencilState:_depthState];       // 深度测试方式 深度可写   ----- 如果这里配置需要深度测试 那么renderpassDesc必须配置深度附件
    
    // SIGABRT
    // validateDepthStencilState:4140: failed assertion `MTLDepthStencilDescriptor sets depth test
    // but MTLRenderPassDescriptor has a nil depthAttachment texture'
    // renderpass并没有设置深度纹理 但是encoder设置需要深度测试
    
    //[renderEncoder setVertexTexture:(nullable id<MTLTexture>) atIndex:(NSUInteger)]
    [renderEncoder setVertexBuffer:_vertexbuffer offset:0 atIndex:0];  // 设置vbo
    
    // 调用一次drawcall绘制三角形
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];// RenderObject RenderTarget
    
    // pushDebugGroup和popDebugGroup只是做一个指令阶段的标记，方便我们在截帧调试的时候观察
    [renderEncoder popDebugGroup];
    
    // 标示当前render pass指令结束
    [renderEncoder endEncoding];
    
    
    // 当前的渲染目标设置为我们MTKView的framebuffer，将渲染结果绘制到视图 ?? 渲染目标 可以不是view ??
    // view.currentDrawable 获取当前帧的可绘制对象 这个包含了 颜色 深度模板 等纹理
    [commandBuffer presentDrawable:drawable];
    
    
    // 提交commandBuffer到commandQueue，等待被GPU执行
    [commandBuffer commit];
    
}


//-(MTLRenderPassDescriptor*) currentFramebuffer
//{
//    if (!renderPass)
//    {
//        id <CAMetalDrawable>Drawable = [self currentDrawable];
//        if (Drawable)
//        {
//            renderPass = [MTLRenderPassDescriptor renderPassDescriptor];
//            renderPass.colorAttachments[0].texture = Drawable.texture;
//            renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
//            renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 1.0, 1.0);
//            renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
//        }
//    }
//
//    return renderPass;
//}

//-(id<CAMetalDrawable>) currentDrawable
//{
//    while (!drawable) {
//        drawable = [renderLayer nextDrawable];
//    }
//    return drawable;
//}
 
@end
