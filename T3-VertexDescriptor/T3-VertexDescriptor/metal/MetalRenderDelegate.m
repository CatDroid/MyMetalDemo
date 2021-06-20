//
//  MetalRenderDelegate.m
//  T3-VertexDescriptor
//
//  Created by hehanlong on 2021/6/17.
//

#import "MetalRenderDelegate.h"
#import "ShaderType.h"

@implementation MetalRenderDelegate
{
    id<MTLRenderPipelineState>  _renderPipelineState;
    id<MTLDepthStencilState>    _depthStencilState ;

    id<MTLBuffer>           _vertexBuffer ;
    id<MTLTexture>          _texture ;
    
    id<MTLCommandQueue>     _commandQueue ;
}



-(instancetype) initWithMTKView:(MTKView*)view
{
    self = [super init];
    if (self) {
        [self setupView:view];
        [self setupRender:view];
        [self setupAssets:view.device];
    }
    return self;
}

#pragma mark - View Setup
-(void) setupView:(MTKView*) view
{
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
    view.clearDepth = 1.0;
    view.clearStencil = 0.0;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; // HDR ??
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    // view.depthStencilTexture
    // ??? 只读 readonly  与当前 currentDrawable对象纹理 相关的 深度模板纹理
    view.sampleCount = 1 ; // ???
    // view.currentRenderPassDescriptor 当前的renderPass ??  MTLRenderPassDescriptor
}

#pragma mark - Render Setup
-(void) setupRender:(MTKView*) view
{
    id<MTLDevice> device = view.device ;
    
    // device newDynamicLibrary:(nonnull id<MTLLibrary>) error:&error  ?? 动态library
    // device newLibraryWithData:(nonnull dispatch_data_t) error:&error ?? 通过data拿到libaray
    
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> myVertexFunction = [library newFunctionWithName:@"MyVertexShader"];
    id<MTLFunction> myFragmentFunction = [library newFunctionWithName:@"MyFragmentShader"];
    

    MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    //MTLComputePipelineDescriptor
    renderPipelineDesc.vertexFunction = myVertexFunction;
    renderPipelineDesc.fragmentFunction = myFragmentFunction;
 
    renderPipelineDesc.colorAttachments[0].blendingEnabled = true ;
    renderPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    
    // 不是必须的
    // 顶点缓冲VB传送给vertex shader:
    // 方式1. 用MTLVertexDescriptor描述顶点结构  然后在顶点着色函数中用[[stage_in]]属性接收
    // 方式2. 直接通过设置顶点buffer传给顶点着色函数[[buffer(id)]]，并根据[[ vertex_id]]属性定位当前顶点的数据
    // renderPipelineDesc.vertexDescriptor
    
    renderPipelineDesc.sampleCount = view.sampleCount ;
    
    
    // 一个pipeline state表示图形渲染管线的状态，包括shaders，混合，多采样和可见性测试
    // 对于每一个pipeline state，只会对应一个MTLVertexDescriptor对象
    
    // MTLVertexDescriptor描述给到 PipelineState对象的MTLRenderPipelineDescriptor描述中vertexDescriptor属性
    // 顶点layout组织结构就会应用于和这个pipeline相关的函数
    
    // 每个渲染管线只会设置一个MTLVertexDescriptor，来组织顶点结构
    
    // 例如我们加载一个obj模型，它的顶点数据可能有position，normal，uv，tangent等，
    // 我们需要设置与之对应的MTLVertexDescriptor结构来正确解析和接收模型数据，并将数据映射传到vertex shader中进行计算
    MTLVertexDescriptor* vertexDesc = [[MTLVertexDescriptor alloc] init];
    NSLog(@" vertexDesc.attributes class is %@",  [vertexDesc.attributes class]); // MTLVertexAttributeDescriptorArrayInternal
    NSLog(@"(uint8_t)&(((MyVertex*)0)->uv) = %d", (uint8_t)&(((MyVertex*)0)->uv));
    NSLog(@"sizeof(MyVertex) = %lu", sizeof(MyVertex));
    
    // pos
    vertexDesc.attributes[0].format = MTLVertexFormatFloat2 ;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0 ;
    // uv
    vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[1].offset = (uint8_t)&(((MyVertex*)0)->uv); // 8;
    vertexDesc.attributes[0].bufferIndex = 0 ;
    // layout
    vertexDesc.layouts[0].stride = sizeof(MyVertex); // 16
    vertexDesc.layouts[0].stepRate = 1;
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    // 由于是连续定义在同一个buffer中所以这里只配置了一个layouts[0]
    // stride属性表示每次去取一个顶点数据的数据跨度，这里每个顶点数据占16字节，所以stride设置为16
    
    // Instance rendering(实例渲染)和Tessellating(曲面细分)等技术
    
    //AOS（Array Of Structure） 同一个顶点的所有属性在同一个buffer依次排列存储，
    //                          然后继续排列存储下一个顶点数据，
    //                          如此类推，这样的好处是符合面向对象的布局思路
    
    // SOA（Structure Of Array）是AOS的一个变换，不同于之前一些属性结构的集合组成的结构数组，
    //                          现在我们有一个结构来包含多个数组，每个数组只包含一个属性，
    //                          这样GPU可以使用同一个index索引去读取每个数组中的属性，
    //                          GPU读取比较整齐，这种方法对于某一些3D文件格式尤其合适
    
    /*
     
     改成 position数据放到第一个buffer，uv放到第二个buffer上
     
     vertexDescriptor = [[MTLVertexDescriptor alloc] init];

     // Positions.
     vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
     vertexDescriptor.attributes[0].offset = 0;
     vertexDescriptor.attributes[0].bufferIndex = 0;

     // Texture coordinates.
     vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
     vertexDescriptor.attributes[1].offset = 0;
     vertexDescriptor.attributes[1].bufferIndex = 0; // ??? 应该是1  ??? 两个buffer shader怎么改？？

     // Position Buffer Layout
     vertexDescriptor.layouts[0].stride = 8;
     vertexDescriptor.layouts[0].stepRate = 1;
     vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

     vertexDescriptor.layouts[1].stride = 8;
     vertexDescriptor.layouts[1].stepRate = 1;
     vertexDescriptor.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
 
     */
    renderPipelineDesc.vertexDescriptor = vertexDesc ;
    
    NSError* error ;
    _renderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
    if (_renderPipelineState == nil)
    {
        NSLog(@"newRenderPipelineStateWithDescriptor fail with %@", error);
    }
    
  

    MTLDepthStencilDescriptor* depthStencilDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDesc.depthWriteEnabled = YES ;
    depthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
    _depthStencilState = [device newDepthStencilStateWithDescriptor:depthStencilDesc];
    
    
    _commandQueue = [device newCommandQueue];
}

-(void) setupAssets:(id<MTLDevice>) device
{
    static MyVertex vertex[] = {
        { {0.0,  1.0},  {0.5, 0} },
        { {1.0, -1.0},  {1,   1} },
        { {-1.0, -1.0}, {0,   1} },
    };
    _vertexBuffer = [device newBufferWithBytes:vertex length:sizeof(vertex) options:MTLResourceStorageModeShared];
    // 注意区分:
    // MTLStorageModeShared
    // MTLResourceStorageModeShared = MTLStorageModeShared << MTLResourceStorageModeShift

    // 先分配buffer 然后再写入数据 可以更新
    // id<MTLBuffer> reserveBuffer = [device newBufferWithLength:sizeof(vertex) options:MTLResourceStorageModeShared];
    // memcpy(reserveBuffer.contents, vertex, sizeof(vertex))
     
    
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:device];
    // 需要参数MTLDevice 因为内部需要使用MTLDevice得到MTLTexture
    
    NSURL* path = [[NSBundle mainBundle] URLForResource:@"texture01" withExtension:@"jpg"];
    
    NSDictionary<MTKTextureLoaderOption,id>* options = @{
        MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode:@(MTLStorageModePrivate)
    };
    
    NSError* error;
    _texture = [loader newTextureWithContentsOfURL:path options:options error:&error];
    if (_texture == nil) {
        NSLog(@"newTextureWithContentsOfURL fail with %@ ", error);
    }
    
     
}


#pragma mark - MTKView delegate

-(void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{

}

-(void) drawInMTKView:(MTKView *)view
{
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    // _depthStencilState
    // _renderPipelineState
    // _vertexBuffer
    // _texture
    encoder.label = @"MyEncoder";
    [encoder pushDebugGroup:@"myEncoderDebug"];
    
    [encoder setRenderPipelineState:_renderPipelineState];
    [encoder setDepthStencilState:_depthStencilState];
    // 从cpu buffer给gpu传输数据 三种方式:
    // 1. Argument Table直接setBuffer给着色函数
    // 2. 使用MTLVertexDescriptor配置走stage流程传送顶点数据
    // 3. Argument Buffer封装数据进行统一传送
    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    // [encoder setVertexTexture:(nullable id<MTLTexture>) atIndex:] // 顶点着色器也可以有纹理
    [encoder setFragmentTexture:_texture atIndex:0];
    
    /*
     
     Argument Tables就是各种资源的列表，
     每个vertex function和fragment function都对应一个这样的资源列表，通过以下函数传入
     
     setVertexBuffer
     setVertexTexture
     setFragmentBuffer  ??? 怎么知道多少 ???
     setFragmentTexture
     
     Vertex Argument Tables / Fragment Argument Tables
     Buffers   Buffer0  Buffer1     Buffer2
     Textures  Texture0 Texture1    Texture2
     Samplers  Sampler0 Sampler1    Sampler2
     
     table中buffer、texture、sampler的数量取决于硬件设备，
     但是开发中可以认为至少可以传入31个buffer和texture，和16个sampler
     
     */
    
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    
    [encoder popDebugGroup];
    
    
    [encoder endEncoding];
    
    [commandBuffer presentDrawable:view.currentDrawable];
    
    [commandBuffer commit];
}


@end
