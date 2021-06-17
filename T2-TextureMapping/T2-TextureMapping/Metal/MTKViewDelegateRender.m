//
//  MTKViewDelegateRender.m
//  T2-TextureMapping
//
//  Created by hehanlong on 2021/6/17.
//

#import "MTKViewDelegateRender.h"
#import "ShaderType.h"

@implementation MTKViewDelegateRender
{
    id <MTLCommandQueue> _commandQueue;
    
    id<MTLDepthStencilState> _depthStencilState ;
    id<MTLRenderPipelineState> _renderPipelineState ;
    
    id<MTLBuffer> _vertexBuffer ;
    id<MTLTexture> _texture ;
    
}

-(instancetype) initWithMTKView:(MTKView*) view
{
    self = [super init];
    if (self) {
        [self setupView:view];
        [self setupRenderPipe:view];
        [self loadAssets:view.device];
        
    } else {
        NSLog(@"initWithMTKView super init nil");
    }
    return self ;
}

#pragma mark - STKView
-(void) setupView:(MTKView*) view
{
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0); // 清屏颜色是黄色。
    view.clearDepth = 1.0;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ; //  GL_DEPTH24_STENCIL8
    // A 40-bit combined depth and stencil pixel format 40位结合深度32bit和模板8bit HDR??
    view.sampleCount = 1; // 默认就是1
    
}

-(void) setupRenderPipe:(MTKView*) view
{
    // 用描述符生成的都不是协议 而是State对象
    // 不是用描述符创建的 一般都是协议 id<MTLLibrary>
    // 大部分对象都是通过 MTLDevice生成的 方法都以newXXXX开头
    
    id<MTLLibrary> library = [view.device newDefaultLibrary];
    
   
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"MyVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"MyFragmentShader"];
    
    MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    
    renderPipelineDesc.vertexFunction = vertexFunction ;
    renderPipelineDesc.fragmentFunction = fragmentFunction ;
    
    renderPipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat ;
    renderPipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat; // 为什么要一样的???
    // renderPipelineDesc.colorAttachments[0].sourceRGBBlendFactor
    // renderPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor
    // renderPipelineDesc.colorAttachments[0].destinationRGBBlendFactor
    // renderPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor  // 混合因子
    //renderPipeLineDesc.colorAttachments[0].rgbBlendOperation
    //renderpipeLineDesc.colorAttachments[0].alphaBlendOperation           // 混合公式
    renderPipelineDesc.colorAttachments[0].blendingEnabled = true ;
    renderPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat; // 为什么要一样
    
    renderPipelineDesc.label = @"MyRenderPipelineDesc"; // 啥作用??
    renderPipelineDesc.sampleCount = 1 ; // ?? 什么作用  ???  要跟view一样   ???
    
    NSError* error ;
    _renderPipelineState = [view.device newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
    if (_renderPipelineState == nil) {
        NSLog(@"newRenderPipelineStateWithDescriptor fail with %@", _renderPipelineState);
    }
    
    
    
    MTLDepthStencilDescriptor* depthStencilDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDesc.label = @"MyDepthStencilDesc";
    // depthStencilDesc.backFaceStencil  // 背面图元的测试方法 如果不设置 就是不做模版测试
    // depthStencilDesc.frontFaceStencil // 正面图元的测试方法
    depthStencilDesc.depthWriteEnabled = YES;
    depthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
  
    _depthStencilState = [view.device newDepthStencilStateWithDescriptor:depthStencilDesc];
    
    
    _commandQueue = [view.device newCommandQueue];
}

-(void) loadAssets:(id<MTLDevice>) device
{
    // 加载顶点属性
    static MyVertex vertex[] = {
        { {0,   1},  {0.5, 0}   }, // Metal中纹理空间的坐标系如下，左上角为原点(不同于OpenGL纹理坐标空间原点在左下角)
        { {1,  -1},  {1.0, 1.0} },
        { {-1, -1},  {0, 1.0}   }
    };
    _vertexBuffer = [device newBufferWithBytes:vertex length:sizeof(vertex) options:MTLResourceStorageModeShared];
    // ?? MTLResourceStorageModeShared 作用
    
    // storgeMode来控制贴图在内存中的存储方式
    
    // 加载贴图 使用MetalKit提供的方法 可以省去解码
    NSError *error;
    MTKTextureLoader* textureloader = [[MTKTextureLoader alloc] initWithDevice:device];
    
    NSDictionary* textureLoaderOptions = @{
        MTKTextureLoaderOptionTextureUsage: @(MTLTextureUsageShaderRead), // An option for reading or sampling from the texture in a shader.
        MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModePrivate) // The resource can be accessed only by the GPU.
    };
    
    
    // Synchronously loads image data and creates a Metal texture from the named texture asset in an asset catalog.
    // 同步加载图片(不用自己解码) 和 创建metal纹理  资源要在asset目录
    //_texture = [textureloader newTextureWithName:@"texture01.jpg" scaleFactor:1.0 bundle:nil options:textureLoaderOptions error:&error];
    // 纹理放在bundle或者assets  或者 newTextureWithContentsOfURL:url  路径
    NSURL* path = [[NSBundle mainBundle] URLForResource:@"texture01" withExtension:@".jpg"];
    _texture = [textureloader newTextureWithContentsOfURL:path options:textureLoaderOptions error:&error];
    if (_texture == nil)
    {
        NSLog(@"MTKTextureLoader  newTextureWithName fail %@", error);
    }
    
    // 通过MTLDevice和描述符 来获取 Texture 需要自己解码
//    MTLTextureDescriptor* textureDesc = [[MTLTextureDescriptor alloc] init];
//    textureDesc.pixelFormat = MTLPixelFormatBGRA8Unorm ; // B G R A ??? uint_8 normalize
//    textureDesc.width = 1920;
//    textureDesc.height = 1080;
//    textureDesc.mipmapLevelCount = 0 ; // 生成Mip贴图的数量
//    id<MTLTexture> texture1 = [device newTextureWithDescriptor:textureDesc];
    
    
    // 在CPU上代码中创建sampler对象传递给着色器使用
    MTLSamplerDescriptor* sampleDesc = [[MTLSamplerDescriptor alloc] init];
    sampleDesc.magFilter = MTLSamplerMinMagFilterLinear;
    // MTLSamplerMipFilterNearest // The nearest mipmap level is selected.
    // MTLSamplerMinMagFilterNearest
    sampleDesc.minFilter = MTLSamplerMinMagFilterLinear;
    sampleDesc.rAddressMode = MTLSamplerAddressModeClampToEdge;
    sampleDesc.sAddressMode = MTLSamplerAddressModeMirrorRepeat; // outside -1.0 and 1.0, the image is repeated.
    id <MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:sampleDesc];
    (void) sampler ;
    
    // 根据屏幕绘制分辨率需求来伸缩纹理贴图，改变纹理贴图数据规模的过程就叫"纹理过滤"
    
}

#pragma mark - RenderPipe


#pragma mark - MTKViewDelegate
-(void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    
}

-(void) drawInMTKView:(MTKView *)view
{
    MTLRenderPassDescriptor* renderPassDesc = view.currentRenderPassDescriptor ; // 为啥view有这个东西
    
    // queue -- commandbuffer --- commandEncode(需要renderpassDescriptor) -- 把渲染的东西放进去
    
    //MTLCommandBufferDescriptor* commandBufferDesc ;
    //id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBufferWithDescriptor:commandBufferDesc];
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer]; // 可以不用描述符
    
    MTLRenderPassDescriptor* renderPassDescForEncoder = renderPassDesc;
    
    id <MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescForEncoder];
    
    commandEncoder.label = @"MyRenderPass";
    // 往encoder推送渲染的东西。作为一个render pass ??
    [commandEncoder pushDebugGroup:@"MyRenderPassDebugGroup"];
    
    [commandEncoder setRenderPipelineState:_renderPipelineState];
    [commandEncoder setDepthStencilState:_depthStencilState];
    
    [commandEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0]; // vbo
    [commandEncoder setFragmentTexture:_texture atIndex:0];            // 设置第0个纹理
    // 注意index要和片段着色器参数的 "语义绑定" 相对应
    // 将贴图资源传入片段着色器的textrure buffer中
    
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    
    
    [commandEncoder popDebugGroup];
    
    [commandEncoder endEncoding]; // 编码结束
    
    
    // [commandBuffer presentDrawable:(nonnull id<MTLDrawable>) atTime:(CFTimeInterval)]
   
    // NSLog(@"MTKView drawable size width=%f, height=%f",  view.drawableSize.width, view.drawableSize.height);
    // iphoneXR MTKView drawable size width=828.000000, height=1792.000000
    
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
    
    
}


@end
