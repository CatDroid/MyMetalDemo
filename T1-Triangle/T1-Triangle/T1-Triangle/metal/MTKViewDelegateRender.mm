//
//  MTKViewDelegateRender.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "MTKViewDelegateRender.h"
#import "ShaderTypes.h"

#import "MemoryScribble.hpp"
#import "MemoryGuard.hpp"

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
    
    MemoryScribble* pMemoryScribble ;
    MemoryGuard* pMemoryGuard;
}

#pragma mark - Constructor

#include <mach-o/dyld.h>

-(nonnull instancetype) initWithMetalKitView:(MTKView *) view
{
    self = [super init];
    if (self) {
        [self _setupMTKView:view];
        [self _setupRenderPass:view];
        [self _loadAssets:view.device];
        
        pMemoryScribble = new MemoryScribble{};
        
        pMemoryGuard = new MemoryGuard{};
        
        uint32_t numImages = _dyld_image_count();
        for (uint32_t i = 0; i < numImages; i++)
        {
            // 加载地址每次启动APP，都有所不同
            const struct mach_header *header = _dyld_get_image_header(i);
            const char *name = _dyld_get_image_name(i);
            const char *p = strrchr(name, '/');
            if (header->filetype == MH_EXECUTE) {
                if (p && (strcmp(p + 1, "T1-Triangle") == 0 || strcmp(p + 1, "libXxx.dylib") == 0)) {
                    NSLog(@"module=%s, address=%p\n", p + 1, header);
                    // 加载地址
                }
            }
        
        }
        
        
        int a = 2 ;
        int b = 0 ;
        int c = a / b ;
        NSLog(@"devid by zero is %d", c);
        
        
    } else {
        NSLog(@"initWithMetalKitView super init fail");
    }
    return self ;
}

#pragma mark - MTKView setup
- (void) _setupMTKView:(MTKView*) view
{
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ; // 深度缓冲用32bit 模版缓冲用8bit
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB ; // 颜色纹理/深度纹理/模版纹理
    // 颜色缓冲区
    // U unsiged
    // norm是归一化 4个8bit归一化无符号整数
    // 顺序是 BGRA
    // 颜色空间是 sRGB
    
    view.sampleCount = 1 ;
    // sampleCount指的是每个像素的颜色采样个数，正常情况每个像素只采样一个，
    // 而在某些情况下，例如需要实现MSAA等抗锯齿算法的时候，则可能将采样数设置为4或者更多
}


#pragma mark - Render setup
- (void) _setupRenderPass:(MTKView*) view
{
    id<MTLDevice> gpu = view.device; // MTLDevice MTLLibrary MTLFunction 都是协议
    
    // MTLLibrary是用来编译和管理metal shader的
    // 它包含了Metal Shading Language的编译源码, 会在程序build过程中???或者运行时编译shader文本
    //
    // MTLDevice 的 newDefaultLibrary 管理的是 xcode工程中的 .metal文件
    // 可识别工程目录下的.metal文件中的vertex函数、fragment函数和kernel函数
    
    // .metal文件中的shader代码实际上是text文本
    // 经过MTLLibrary编译后成为可执行的MTLFunction函数对象
    
    id<MTLLibrary> library = [gpu newDefaultLibrary];
    
    // 顶点着色器函数
    // 片段着色器函数
    // kernel函数     computer shader，用于GPU通用并行计算
    
    // 创建编译顶点着色器函数和片段着色器函数
    
    id<MTLFunction> vertextFunction =  [library newFunctionWithName:@"myVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"myFragmentShader"];
    
    
    // 创建管线状态对象_pipelineState，创建_pipelineState之前需要定义一个它的Descriptor，用来配置这个render pass的一些参数, 比如着色器函数 和 各个附件参数
    
    MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    
    pipelineStateDescriptor.vertexFunction = vertextFunction ;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
    
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;        //  颜色附件
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat ;     //  深度附件
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat ;   //  模版附件
    
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
    // 顶点属性数组--顶点坐标/纹理坐标
    static const Vertex vert[] = {
        // (Vertex){ (vector_float2){0, 1.0}  }
        {  {0,    1.0}  },
        {  {1.0, -1.0}  },
        {  {-1.0,-1.0}  }
    };
    
    // Metal使用MTLResource管理内存，使用MTLDevice实例创建内存（实际使用MTLBuffer表示创建的buffer，是MTLResource的子类）
    
    // 渲染模型数据
    _vertexbuffer = [device newBufferWithBytes:vert length:sizeof(vert) options:MTLResourceStorageModeShared];
}


#pragma mark - MTKViewDelegate
- (void) drawInMTKView:(nonnull MTKView *)view
{
    
    // 测试内存
    
    pMemoryScribble->Update();
    pMemoryGuard->Update();
    
    // 执行渲染相关
    
    // 通过queue创建一个命令buffer
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    
    // MTLRenderPassDescriptor是一个很重要的descriptor类
    // 它是用来设置我们 "当前pass" 的渲染目标（render target）的，这里我们使用view默认的配置，只有一个渲染默认的目标
    // 在一些其他渲染技术例如延迟渲染中，需要使用这个descriptor配置MRT
    
    MTLRenderPassDescriptor* renderPassDesc = view.currentRenderPassDescriptor; // MTKView  renderpass描述 用来从commandbuffer中获取encoder编码器
    if (renderPassDesc != nil)
    {
        // Creates an object from a descriptor to encode a rendering pass into the command buffer.
        // 创建命令编码器 用于 把一个即将要渲染的pass编码到buffer中
        // 使用view默认的renderPassDescriptor创建renderCommandEncoder，来编码我们的渲染指令
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc]; //这是一个跟view相关的 *****
        renderEncoder.label = @"MyRenderEncoder";
        
        [renderEncoder pushDebugGroup:@"DrawTriangle"];
        [renderEncoder setRenderPipelineState:_pipelineState];  // 着色器 颜色输出缓冲区格式
        [renderEncoder setDepthStencilState:_depthState];       // 深度测试方式 深度可写
        
        //[renderEncoder setVertexTexture:(nullable id<MTLTexture>) atIndex:(NSUInteger)]
        [renderEncoder setVertexBuffer:_vertexbuffer offset:0 atIndex:0];  // 设置vbo
        
        // 调用一次drawcall绘制三角形
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];// RenderObject RenderTarget
        
        // pushDebugGroup和popDebugGroup只是做一个指令阶段的标记，方便我们在截帧调试的时候观察
        [renderEncoder popDebugGroup];
        
        // 标示当前render pass指令结束
        [renderEncoder endEncoding];
        
        
        // 当前的渲染目标设置为我们MTKView的framebuffer，将渲染结果绘制到视图 ?? 渲染目标 可以不是view ??
        [commandBuffer presentDrawable:view.currentDrawable]; // view.currentDrawable 获取当前帧的可绘制对象。*****
        
        // 图元
        // MTLPrimitiveTypeTriangle 三角形
        // MTLPrimitiveTypePoint 点
        // MTLPrimitiveTypeLine 线段
        // MTLPrimitiveTypeLineStrip 线环
    }
    
    [commandBuffer commit]; // 提交commandBuffer到commandQueue，等待被GPU执行
    
}

- (void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // MTKView尺寸变化
    NSLog(@"MetalKit View Size Change To %f,%f", size.width, size.height);
}

@end
