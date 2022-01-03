/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class that performs Metal setup and per frame rendering.
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code, which executes Metal API commands, and .metal files,
// which use these types as inputs to the shaders.
#import "AAPLShaderTypes.h"

@implementation AAPLRenderer
{
    // The device object (aka GPU) used to process images.
    id<MTLDevice> _device;

    id<MTLComputePipelineState> _computePipelineState;
    id<MTLRenderPipelineState> _renderPipelineState;

    id<MTLCommandQueue> _commandQueue;

    // Texture object that serves as the source for image processing.
    id<MTLTexture> _inputTexture;

    // Texture object that serves as the output for image processing.
    id<MTLTexture> _outputTexture;

    // The current size of the viewport, used in the render pipeline.
    vector_uint2 _viewportSize;

    // Compute kernel dispatch parameters
    MTLSize _threadgroupSize;
    MTLSize _threadgroupCount;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error = NULL;

        _device = mtkView.device;

        mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

        // Load all the shader files with a .metal file extension in the project.
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        // Load the image processing function from the library and create a pipeline from it.
        id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:@"grayscaleKernel"];
        _computePipelineState = [_device newComputePipelineStateWithFunction:kernelFunction
                                                                       error:&error];

        // Compute pipeline state creation could fail if kernelFunction failed to load from
        // the library. If the Metal API validation is enabled, you automatically get more
        // information about what went wrong. (Metal API validation is enabled by default
        // when you run a debug build from Xcode.)
        NSAssert(_computePipelineState, @"Failed to create compute pipeline state: %@", error);

        // Load the vertex and fragment functions, and use them to configure a render
        // pipeline.
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];

        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Simple Render Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

        _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
        
        

        NSAssert(_renderPipelineState, @"Failed to create render pipeline state: %@", error);

        NSURL *imageFileLocation = [[NSBundle mainBundle] URLForResource:@"Image"
                                                           withExtension:@"tga"];

        AAPLImage * image = [[AAPLImage alloc] initWithTGAFileAtLocation:imageFileLocation];

        if(!image)
        {
            return nil;
        }

        // Indicate that each pixel has a Blue, Green, Red, and Alpha channel,
        //   each in an 8-bit unnormalized value (0 maps to 0.0, while 255 maps to 1.0)
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.textureType = MTLTextureType2D;
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm; // 输出是归一化的rgba  存放的只能是0～1
        textureDescriptor.width = image.width;
        textureDescriptor.height = image.height;
        textureDescriptor.usage = MTLTextureUsageShaderRead; // kernel只读这个纹理 The image kernel only needs to read the incoming image data.
        _inputTexture = [_device newTextureWithDescriptor:textureDescriptor];

        // The output texture needs to be written by the image kernel and sampled
        // by the rendering code. 输出纹理 在 computershader中会写 rendershader中会读(sample)
        textureDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead ;
        _outputTexture = [_device newTextureWithDescriptor:textureDescriptor];

        MTLRegion region = {{ 0, 0, 0 }, {textureDescriptor.width, textureDescriptor.height, 1}};// depth就是1
        // 实际区域就是0~width-1 0~height-1 0~0

        // Calculate the size of each texel times the width of the textures.
        NSUInteger bytesPerRow = 4 * textureDescriptor.width;

        // Copy the bytes from the data object into the texture.
        [_inputTexture replaceRegion:region
                    mipmapLevel:0
                      withBytes:image.data.bytes
                    bytesPerRow:bytesPerRow];

        NSAssert(_inputTexture && !error, @"Failed to create inpute texture: %@", error);

        // 这个demo使用的网格 是 一个线程 对应一个 像素。 因此网格必须至少与 2D 图像一样大
        //
        // 为简单起见，该示例使用 16 x 16 的线程组大小，该大小足以供任何 GPU 使用
        // 然而，实际上，选择有效的线程组大小取决于数据的大小和特定设备对象的功能。 _renderPipelineState.maxTotalThreadsPerThreadgroup
        //
        // debug需要ios12.0+ ，点击‘甲壳虫’ 图标  输入thread_postion_in_grid,可计算出所在线程组序号
        //
        // Set the compute kernel's threadgroup size to 16 x 16.
        _threadgroupSize = MTLSizeMake(16, 16, 1); // 每个线程组的尺寸是16x16

        // Calculate the number of rows and columns of threadgroups given the size of the input image.
        // Ensure that the grid covers the entire image (or more). // 格子覆盖整个图片(或者更多)
        _threadgroupCount.width  = (_inputTexture.width  + _threadgroupSize.width -  1) / _threadgroupSize.width; // 向上取整 ，格子的尺寸
        _threadgroupCount.height = (_inputTexture.height + _threadgroupSize.height - 1) / _threadgroupSize.height;
        _threadgroupCount.depth = 1; // The image data is 2D, so set depth to 1.

        // Create the command queue.
        _commandQueue = [_device newCommandQueue];
    }

    return self;
}

/// The system calls this method whenever the view changes orientation or size.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable to pass to the render pipeline.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// The system calls this method whenever the view needs to render a frame.
/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    static const AAPLVertex quadVertices[] =
    {
        // Pixel positions, Texture coordinates
        { {  250,  -250 },  { 1.f, 1.f } },
        { { -250,  -250 },  { 0.f, 1.f } },
        { { -250,   250 },  { 0.f, 0.f } },

        { {  250,  -250 },  { 1.f, 1.f } },
        { { -250,   250 },  { 0.f, 0.f } },
        { {  250,   250 },  { 1.f, 0.f } },
    };

    // Create a new command buffer for each frame.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    //
    // 创建一个compute pass 和 一个 render pass (两个encoder) 在一个command buffer
    //
    
    // Process the input image.
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];

    
    [computeEncoder setComputePipelineState:_computePipelineState];

    [computeEncoder setTexture:_inputTexture
                       atIndex:AAPLTextureIndexInput];

    [computeEncoder setTexture:_outputTexture
                       atIndex:AAPLTextureIndexOutput];
    
    // 注意不一样
    // [encoder dispatchThreads:gridSize threadsPerThreadgroup:groupSize];// 各个维度上线程的数目(运算规模)。每个线程组的线程数目。 两个相除也可以得到各个维度上线程组数目
    
    [computeEncoder dispatchThreadgroups:_threadgroupCount // 格子划分x y z方向线程组数目    ??线程的数目 就是运算的规模??
                   threadsPerThreadgroup:_threadgroupSize];// 每个线程组中线程数目。

   
    [computeEncoder endEncoding];

    // Use the output image to draw to the view's drawable texture.
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor; // 这个里面包含了渲染目标 CAMetalLayer.drawable.texture

    if(renderPassDescriptor != nil)
    {
        // Create the encoder for the render pass.
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set the region of the drawable to draw into.
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 }];// 默认是 znear=0 zfar=1 可以翻转

        [renderEncoder setRenderPipelineState:_renderPipelineState];

        // Encode the vertex data.
        [renderEncoder setVertexBytes:quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];

        // Encode the viewport data.
        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];

        // 设置fragment shader使用的纹理,也就是computer shader输出的纹理
        // Encode the output texture from the previous stage.
        [renderEncoder setFragmentTexture:_outputTexture
                                  atIndex:AAPLTextureIndexOutput];

        // Draw the quad. 正方形 6个顶点
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];

        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable.
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    
    // 这个command buffer 包含了一个计算编码和一个渲染编码
    
    // Metal 自动跟踪计算和渲染过程之间的依赖关系。
    // 当app发送命令缓冲区去执行时，Metal 检测到计算通道(compute pass)写入输出纹理，渲染通道(render pass)从中读取，就会确保GPU在开始 渲染通道 之前完成 计算通道。
    
    [commandBuffer commit];
}

@end
