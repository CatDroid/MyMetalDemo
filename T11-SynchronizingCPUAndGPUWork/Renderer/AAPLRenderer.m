/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation for a renderer class that performs Metal setup and per-frame rendering.
*/

@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLTriangle.h"
#import "AAPLShaderTypes.h"

/*
 Core Animation 提供优化的可显示资源(optimized displayable resources) 通常称为可绘制资源drawable, 用来 渲染内容并将其显示在屏幕上
 
 Drawable是高效但昂贵的系统资源，因此 Core Animation 限制了 可以在应用程序中同时使用的 drawable 的数量。默认限制为 3
 
 但可以使用 maximumDrawableCount 属性将其设置为 2（2 和 3 是唯一支持的值）
 
 由于可绘制对象的最大数量为 3，因此此示例创建了 3 个缓冲区实例。所以也不需要创建比可用的最大可绘制数量更多的缓冲区实例。
 
 id<CAMetalDrawable> currentDrawable = [metalLayer nextDrawable];
  _drawableRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
 通过layer获取drawable，drawable中包含texture，可以设置到 DrawableRenderDescriptor(创建编码器需要)
 
 
 */

// The maximum number of frames in flight.  最大帧数。
static const NSUInteger MaxFramesInFlight = 3;

// The number of triangles in the scene, determined to fit the screen.
static const NSUInteger NumTriangles = 50;

// The main class performing the rendering.
@implementation AAPLRenderer
{
    // A semaphore used to ensure that buffers read by the GPU are not simultaneously written by the CPU.
    dispatch_semaphore_t _inFlightSemaphore;

    // A series of buffers containing dynamically-updated vertices.
    id<MTLBuffer> _vertexBuffers[MaxFramesInFlight];

    // The index of the Metal buffer in _vertexBuffers to write to for the current frame.
    NSUInteger _currentBuffer;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;

    id<MTLRenderPipelineState> _pipelineState;

    vector_uint2 _viewportSize;

    NSArray<AAPLTriangle*> *_triangles;

    NSUInteger _totalVertexCount;

    float _wavePosition;
}

/// Initializes the renderer with the MetalKit view from which you obtain the Metal device.
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;

        // 初始化的信号量为3 因为只有三个缓冲区 只要缓冲区还有资源 那么就会继续draw编码渲染指令
        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);

        // Load all the shader files with a metal file extension in the project.
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        // Load the vertex shader.
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

        // Load the fragment shader.
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Create a reusable pipeline state object.
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"MyPipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat; // 对于颜色附件的要求 直接用输出的View的
        pipelineStateDescriptor.vertexBuffers[AAPLVertexInputIndexVertices].mutability = MTLMutabilityImmutable;

        NSError *error;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        
        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);
        
        // Create the command queue.
        _commandQueue = [_device newCommandQueue];

        // Generate the triangles rendered by the app. 生成NumTriangles=64个三角形及各自顶点信息
        [self generateTriangles];

        // Calculate vertex data and allocate vertex buffers.
        const NSUInteger triangleVertexCount = [AAPLTriangle vertexCount]; // 一个图案/这里是三角形的顶点数目
        _totalVertexCount = triangleVertexCount * _triangles.count;       // 所有三角形合计的顶点数目
        
        // 顶点buffer需要的总内存，
        // 每个顶点信息用AAPLVertex表示
        // 一个三角形 AAPLTriangle 有 三个顶点，也就是有三个 AAPLVertex
        const NSUInteger triangleVertexBufferSize = _totalVertexCount * sizeof(AAPLVertex);


        // 生成同一个资源的三个实例 一个CPU资源对应3个GPU资源 (using multiple instances of a resource)
        for(NSUInteger bufferIndex = 0; bufferIndex < MaxFramesInFlight; bufferIndex++) //  最大帧数 = 3 就是3缓冲
        {
            _vertexBuffers[bufferIndex] = [_device newBufferWithLength:triangleVertexBufferSize
                                                               options:MTLResourceStorageModeShared];
            _vertexBuffers[bufferIndex].label = [NSString stringWithFormat:@"Vertex Buffer #%lu", (unsigned long)bufferIndex];
        }
    }
    return self;
}

/// Generates an array of triangles, initializing each and inserting it into `_triangles`.
- (void)generateTriangles
{
    // Array of colors.
    const vector_float4 Colors[] =
    {
        { 1.0, 0.0, 0.0, 1.0 },  // Red
        { 0.0, 1.0, 0.0, 1.0 },  // Green
        { 0.0, 0.0, 1.0, 1.0 },  // Blue
        { 1.0, 0.0, 1.0, 1.0 },  // Magenta
        { 0.0, 1.0, 1.0, 1.0 },  // Cyan
        { 1.0, 1.0, 0.0, 1.0 },  // Yellow
    };

    const NSUInteger NumColors = sizeof(Colors) / sizeof(vector_float4);

    // Horizontal spacing between each triangle.
    const float horizontalSpacing = 16;  // 三角形的高和低边长是64

    NSMutableArray *triangles = [[NSMutableArray alloc] initWithCapacity:NumTriangles]; // 生成 NumTriangles=50 个三角形
    
    // Initialize each triangle.
    for(NSUInteger t = 0; t < NumTriangles; t++) // 50个
    {
        vector_float2 trianglePosition;

        // 就是-1到1的区间 分成NumTriangles个三角形。每个三角形的距离是 horizontalSpacing
        // -((float)NumTriangles) / 2.0) -1处, 也就是最左边的三角形序号
        
        // Determine the starting position of the triangle in a horizontal line.
        trianglePosition.x = ((-((float)NumTriangles) / 2.0) + t) * horizontalSpacing;
        trianglePosition.y = 0.0;

        // Create the triangle, set its properties, and add it to the array.
        AAPLTriangle * triangle = [AAPLTriangle new];
        triangle.position = trianglePosition;
        triangle.color = Colors[t % NumColors];
        [triangles addObject:triangle];
    }
    _triangles = triangles;
}

/// Updates the position of each triangle and also updates the vertices for each triangle in the current buffer.
- (void)updateState
{
    // Simplified wave properties.
    const float waveMagnitude = 128.0;  // Vertical displacement.
    const float waveSpeed     = 0.05;   // Displacement change from the previous frame.

    // Increment wave position from the previous frame
    _wavePosition += waveSpeed; // 每次更新

    // Vertex data for a single default triangle.
    const AAPLVertex *triangleVertices = [AAPLTriangle vertices];
    const NSUInteger triangleVertexCount = [AAPLTriangle vertexCount];

    // 只更新这个MTLBuffer.content
    // 没有直接基于上一个MTLBuffer.content来更新当前MTLBuffer.content
    // cpu保存_triangles的状态，每次更新之后保存起来，并且更新到当前的MTLBuffer
    //
    // Vertex data for the current triangles.
    AAPLVertex *currentTriangleVertices = _vertexBuffers[_currentBuffer].contents;

    // Update each triangle.
    for(NSUInteger triangle = 0; triangle < NumTriangles; triangle++)
    {
        vector_float2 trianglePosition = _triangles[triangle].position;

        // Displace the y-position of the triangle using a sine wave.
        //trianglePosition.y = (sin(trianglePosition.x/waveMagnitude + _wavePosition) * waveMagnitude);
        trianglePosition.y = (sin(trianglePosition.x/100 + _wavePosition) * waveMagnitude); // waveMagnitude=128 NumTriangles=50 space=16 50/2*16=400
        // A sin(wt + θ)  = waveMagnitude * sin( _wavePosition +  trianglePosition.x/100 )    100 改成更加大的数 会导致每个点的初相都很接近 所以就看不到一个完整周期了
        
        // Update the position of the triangle.
        _triangles[triangle].position = trianglePosition; // 更新之后保存起来

        // Update the vertices of the current vertex buffer with the triangle's new position.
        for(NSUInteger vertex = 0; vertex < triangleVertexCount; vertex++)
        {
            NSUInteger currentVertex = vertex + (triangle * triangleVertexCount);
            currentTriangleVertices[currentVertex].position = triangleVertices[vertex].position + _triangles[triangle].position;
            currentTriangleVertices[currentVertex].color = _triangles[triangle].color;
        }
    }
}

#pragma mark - MetalKit View Delegate

/// Handles view orientation or size changes.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Regenerate the triangles.
    [self generateTriangles];

    // Save the size of the drawable as you'll pass these
    // values to the vertex shader when you render.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Handles view rendering for a new frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // 等待, 以确保"Metal管道中的任何阶段"(CPU、GPU、Metal、驱动程序等)，仅处理“MaxFramesInFlight=3”数量的帧
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    // 遍历缓冲区，并在写入最后一个缓冲区后循环回到第一个缓冲区。
    // Iterate through the Metal buffers, and cycle back to the first when you've written to the last.
    _currentBuffer = (_currentBuffer + 1) % MaxFramesInFlight;

    // Update buffer data.
    [self updateState];

    // Create a new command buffer for each rendering pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommandBuffer";

    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor; // renderPass来创建encoder
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder to encode the rendering pass.
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set render command encoder state.
        [renderEncoder setRenderPipelineState:_pipelineState];

        // Set the current vertex buffer.
        [renderEncoder setVertexBuffer:_vertexBuffers[_currentBuffer]
                                offset:0
                               atIndex:AAPLVertexInputIndexVertices];

        // 参数组(argument tables) buffer参数组/texture参数组/sampler参数组
        
        // setVertexBytes 与 setVertexBuffer的区别:
        //
        // 1.这个会移除掉绑定点atIndex的MTLBuffer，内部会拷贝
        // 2.使用这个方法相当于从指定的数据创建一个新的 MTLBuffer 对象，然后将它绑定到顶点着色器，使用 setVertexBuffer:offset:atIndex: 方法。
        //   但是，这种方法避免了创建缓冲区来存储数据的开销； 相反，Metal 管理数据。
        //
        // 3. 对小于 4 KB 的一次性数据使用此方法。 如果您的数据长度超过 4 KB 或持续多次使用，则创建一个 MTLBuffer 对象。
        //
        //
        // Set the viewport size.
        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];

        
        // 在OpenGlES中，图元装配有9中，在Metal中，图元装配只有五种
        // MTLPrimitiveTypePoint = 0, 点
        // MTLPrimitiveTypeLine = 1, 线段
        // MTLPrimitiveTypeLineStrip = 2, 线环
        // MTLPrimitiveTypeTriangle = 3,  三角形
        // MTLPrimitiveTypeTriangleStrip = 4, 三角型扇

        // Draw the triangle vertices.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle // 图元类型和图元装配方式
                          vertexStart:0
                          vertexCount:_totalVertexCount];
        
        // 没有索引buffer的draw:
        // drawPrimitives:vertexStart:vertexCount:
        // drawPrimitives:vertexStart:vertexCount:instanceCount: 编码命令去渲染 instanceCount个图元实例(instances of primitives),顶点数据在一个了连续数组元素
        // drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance: (只更新部分图元实例?)渲染instanceCount个图元实例,从第baseInstance个实例开始渲染
        
        // 索引buffer的draw
        // drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:
                                                                // 从给定的索引缓冲indexBuffer的偏移indexBufferOffset(必须4字节对齐)获取顶点做图元装配
                                                                // 索引缓冲的数据类型是indexType 16bit或者32bit
                                                                // 索引总数是 indexCount
                                                                // 需要装配的图元实例的总数是 instanceCount
        // drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:
        
        // 使用indriectBuffer // indirect command buffers (ICB)
        // drawPrimitives:indirectBuffer:indirectBufferOffset:
        // drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:
        
        // 特殊的索引值 0xFFFF 0xFFFFFFFF 图元重启功能 ???
        // Primitive restart functionality is enabled with the largest unsigned integer index value,
        // relative to indexType (0xFFFF for MTLIndexTypeUInt16 or 0xFFFFFFFF for MTLIndexTypeUInt32).
        // This feature finishes drawing the current primitive at the specified index and starts drawing a new one with the next index.
        // 这个功能会停止当前图元的绘制,并从下一个index开始绘制新的图
        
        // Finalize encoding.
        [renderEncoder endEncoding];
        // 当绘制命令(draw command)被编码了，对先前在编码器上“设置的渲染状态”或“资源的任何必要引用” 都将记录为命令的一部分。
        // 在对命令编码完成后，可以安全地更改编码状态，以设置对“其他命令”进行编码 所需的参数。
        

        // Schedule a drawable's presentation after the rendering pass is complete.
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // 必须在commit CommandBuffer之前加入handler
    // Add a completion handler that signals `_inFlightSemaphore` when Metal and the GPU have fully
    // finished processing the commands that were encoded for this frame.
    // This completion indicates that the dynamic buffers that were written-to in this frame, are no
    // longer needed by Metal and the GPU; therefore, the CPU can overwrite the buffer contents
    // without corrupting any rendering operations.
    __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         // 丢弃一个使用过的缓冲区实例, 并为每一帧创建一个新的实例是昂贵且浪费的。
         // 循环使用 缓冲区实例 的 先进先出 (FIFO) 队列、
         // 同一个commandqueue的commandbuffer 是按照先后顺序执行的
         dispatch_semaphore_signal(block_semaphore);
     }];

    // Finalize CPU work and submit the command buffer to the GPU.
    [commandBuffer commit];
}

@end
