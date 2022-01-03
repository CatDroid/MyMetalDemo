/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/
@import simd;
@import MetalKit;

#import "AAPLRenderer.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "AAPLShaderTypes.h"

// The max number of frames in flight
static const NSUInteger AAPLMaxFramesInFlight = 3;

// Main class performing the rendering
@implementation AAPLRenderer
{
    dispatch_semaphore_t _inFlightSemaphore;

    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;

    
    // Array of Metal buffers storing vertex data for each rendered object
    id<MTLBuffer> _vertexBuffer[AAPLNumObjects];    // 每个网格各自一个MTLBuffer存放顶点数据 vertex Buffer(MTLBuffer用在vertex函数)
    // The Metal buffer storing per object parameters for each rendered object
    id<MTLBuffer> _objectParameters;                // 所有网格的参数 放到一个MTLBuffer中, 数组类型, 对应每个元素是各个网格的参数
    // The Metal buffers storing per frame uniform data
    id<MTLBuffer> _frameStateBuffer[AAPLMaxFramesInFlight];  // 所有网格共同的参数 存放到一个MTLBuffer vertex Buffer
    

    // Render pipeline executinng indirect command buffer
    id<MTLRenderPipelineState> _renderPipelineState;

    // When using an indirect command buffer encoded by the CPU, buffer updated by the CPU must be
    // blit into a seperate buffer that is set in the indirect command buffer.
    id<MTLBuffer> _indirectFrameStateBuffer;

    // Index into per frame uniforms to use for the current frame
    NSUInteger _inFlightIndex;

    // Number of frames rendered
    NSUInteger _frameNumber;

    // The indirect command buffer encoded and executed
    id<MTLIndirectCommandBuffer> _indirectCommandBuffer;

    vector_float2 _aspectScale;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device.  We'll also use this
/// mtkView object to set the pixel format and other properties of our drawable
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView // 传入MTKView是因为需要 设置其输出格式(RenderPass) 和 PSO 保持一致
{
    self = [super init];

    if(self)
    {
        mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.5, 1.0f);

        _device = mtkView.device;

        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxFramesInFlight);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];

        // Load the shaders from default library
        id <MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float; // 设置view需要深度buffer
        mtkView.sampleCount = 1;

        // Create a reusable pipeline state
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"MyPipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
        // Needed for this pipeline state to be used in indirect command buffers.
        pipelineStateDescriptor.supportIndirectCommandBuffers = TRUE;

        NSError *error = nil;
        _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];

        NSAssert(_renderPipelineState, @"Failed to create pipeline state: %@", error);

        
        
        
        
        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++) //  AAPLNumObjects = 15
        {
            // Choose parameters to generate a mesh(网格) for this object so that each mesh is unique(每个网格都是独一无二的)
            // and looks diffent than the mesh it's next to in the grid drawn(看起来跟绘制网格中(grid drawn)它旁边的网格(mesh)不同）
            uint32_t numTeeth = (objectIdx < 8) ? objectIdx + 3 : objectIdx * 3;

            // Create a vertex buffer, and initialize it with a unique 2D gear mesh
            _vertexBuffer[objectIdx] = [self newGearMeshWithNumTeeth:numTeeth];

            _vertexBuffer[objectIdx].label = [[NSString alloc] initWithFormat:@"Object %i Buffer", objectIdx];
        }

        /// Create and fill array containing parameters for each object 每个对象 都对应一个AAPLObjectPerameters 全部15个放到一个MTLBuffer

        NSUInteger objectParameterArraySize = AAPLNumObjects * sizeof(AAPLObjectPerameters);

        _objectParameters = [_device newBufferWithLength:objectParameterArraySize options:0];

        _objectParameters.label = @"Object Parameters Array";

        AAPLObjectPerameters *params = _objectParameters.contents;

        static const vector_float2 gridDimensions = { AAPLGridWidth, AAPLGridHeight };

        const vector_float2 offset = (AAPLObjecDistance / 2.0) * (gridDimensions-1);

        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
        {
            // Calculate position of each object such that each occupies a space in a grid
            vector_float2 gridPos = (vector_float2){objectIdx % AAPLGridWidth, objectIdx / AAPLGridWidth};
            vector_float2 position = -offset + gridPos * AAPLObjecDistance;

            // Write the position of each object to the object parameter buffer
            params[objectIdx].position = position;
        }

        // 运行时候 每帧不一样的参数，用三个缓冲交换
        for(int i = 0; i < AAPLMaxFramesInFlight; i++)
        {
            _frameStateBuffer[i] = [_device newBufferWithLength:sizeof(AAPLFrameState)
                                                        options:MTLResourceStorageModeShared];

            _frameStateBuffer[i].label = [NSString stringWithFormat:@"Frame state buffer %d", i];
        }

        // 要更新数据到GPU，通常会循环访问一组缓冲区(FIFO)，以便CPU更新一个缓冲区，而GPU读取另一个缓冲区
        // 但是，您不能将这种模式从字面上应用到 ICB，
        // 因为在对 ICB 的命令进行编码后，无法更新 "ICB的缓冲区集"(ICB’s buffer set)，*****
        // 但可以按照两步过程从CPU进行blit数据更新。
        // 首先，更新CPU上动态缓冲区数组(dynamic buffer array,FIFO数组)中的单个缓冲区：
        // 然后，blit CPU端缓冲区设置为ICB可访问的位置(ICBs中编码了这个buffer，也就是_indirectFrameStateBuffer在"ICB的缓冲区集")
        // When encoding commands with the CPU, the app sets this indirect frame state buffer dynamically in the indirect command buffer.
        // Each frame data will be blit from the _frameStateBuffer that has just been updated by the CPU to this buffer.
        // This allow a synchronous update of values set by the CPU.
        // 当cpu编码ICBs时候，app会设置_indirectFrameStateBuffer这个到ICB
        // 每一帧都会从 _frameStateBuffer[i](已从cpu更新) blit到--> _indirectFrameStateBuffer
        _indirectFrameStateBuffer = [_device newBufferWithLength:sizeof(AAPLFrameState)
                                                         options:MTLResourceStorageModePrivate];  // GPU私有的MTLBuffer

        _indirectFrameStateBuffer.label = @"Indirect Frame State Buffer";

        
        
        
        MTLIndirectCommandBufferDescriptor* icbDescriptor = [MTLIndirectCommandBufferDescriptor new];

        // Indicate that the only draw commands will be standard (non-indexed) draw commands.
        // MTLIndirectCommandTypeDraw  非索引的draw
        // MTLIndirectCommandTypeDrawIndexed 索引的draw
        // MTLIndirectCommandTypeConcurrentDispatch 用于compute shader的dispatch命令
        icbDescriptor.commandTypes = MTLIndirectCommandTypeDraw; // 限制 只能是 非索引的draw命令

        // Indicate that buffers will be set for each command IN the indirect command buffer. ??ICB不使用继承encoder的??
        icbDescriptor.inheritBuffers = NO;

        // Indicate that a max of 3 buffers will be set for each command.
        icbDescriptor.maxVertexBufferBindCount = 3;    // vertex function的buffer arguments tables的最大长度
        icbDescriptor.maxFragmentBufferBindCount = 0;  // fragment function的buffer arguments tables的最大长度

#if defined TARGET_MACOS || defined(__IPHONE_13_0)
        // Indicate that the render pipeline state object will be set in the render command encoder (not by the indirect command buffer).
        // On iOS, this property only exists on iOS 13 and later.  It defaults to YES in earlier versions
        //
        // 在iOS 13之前, ICBs只能继承Encoder设置的PSO(ICBs中的所有draw shader都一样)
        if (@available(iOS 13.0, *)) {
            icbDescriptor.inheritPipelineState = YES;
        }
#endif
        // 创建间接命令缓冲区(ICB, Indirect Command Buffer)
        _indirectCommandBuffer = [_device newIndirectCommandBufferWithDescriptor:icbDescriptor
                                                                 maxCommandCount:AAPLNumObjects // 最大数目的命令,方便预留空间编码MTLIndirectCommandBuffer
                                                                         options:0];
        _indirectCommandBuffer.label = @"Scene ICB";

        
        
        
        //  Encode an Indirect Command Buffer with the CPU (在CPU端编码ICB), 使用 MTLIndirectRenderCommand，将重复绘制及其数据缓冲区移动到 MTLIndirectCommandBuffer
        //
        //  ICB 有效的一个例子是游戏的平视显示器/抬头显示器/状态拦 (head-up display HUD ): a. 每帧都要渲染 b. HUD外观在帧间通常不变
        //  ICB 还可用于渲染典型 3D场景中 的 静态对象(static objects )
        //  此示例演示如何设置 ICB, 以重复渲染一系列形状(repeatedly render a series of shapes)
        //  虽然通过在GPU上编码ICB,可以获得更多指令并行性(instruction-parallelism)，但为了简单起见，本示例在CPU上编码了ICB。
        //
        //  ICBs继承Encoder编码器:
        //      ICBs将从 父级编码器(parent encoder) 继承Encoder的PSO(render pipeline state) 也就是所有object都用同一个shader来处理  (ios13+ 可以override)
        //      ICBs“无法编码到其中的渲染状态: 剔除模式(setCullMode)和渲染通道(render pass)的深度或模板状态(setDepthStencilState)。
        //
        //  当使用ICBs, 通过调用 MTLRenderCommandEncoder 的 executeCommandsInBuffer:withRange: 来编码它的单个执行。
        //
        //  Encode a draw command for each object drawn in the indirect command buffer.
        //  在一个间接编码缓冲区上 为每个渲染的对象 编码渲染指令, 类似 MTLRenderCommandEncoder, 这里从DirectCommandBuffer获取MTLIndirectRenderCommand做编码
        //
        for (int objIndex = 0; objIndex < AAPLNumObjects; objIndex++)
        {
            id<MTLIndirectRenderCommand> ICBCommand =
                [_indirectCommandBuffer indirectRenderCommandAtIndex:objIndex]; // 获取第objIndex的命令去编码

            // ICBCommand setRenderPipelineState:    vvv ICBs可以使用自己的RenderPipeState，但是没有: !!!
            // [renderEncoder setCullMode            xxx 剔除模式
            // [renderEncoder setDepthStencilState:  xxx 深度或模板状态
            // [renderEncoder setVertexTexture:   ]  xxx  纹理
            // [renderEncoder setVertexSamplerState:(nullable id<MTLSamplerState>) atIndex:(NSUInteger)]  xxx 采样器
            // [renderEncoder setViewport:           xxx  视口
             
             
            [ICBCommand setVertexBuffer:_vertexBuffer[objIndex]
                                 offset:0
                                atIndex:AAPLVertexBufferIndexVertices];     // different vertex data,

            [ICBCommand setVertexBuffer:_indirectFrameStateBuffer           // !! 编码完成 就无法修改 这个draw编码 会固定依赖这个 _indirectFrameStateBuffer
                                 offset:0
                                atIndex:AAPLVertexBufferIndexFrameState];   // _uniformBuffers

            [ICBCommand setVertexBuffer:_objectParameters
                                 offset:0
                                atIndex:AAPLVertexBufferIndexObjectParams];
            
            
   
        
           

            const NSUInteger vertexCount = _vertexBuffer[objIndex].length/sizeof(AAPLVertex);

            // MTLIndirectRenderCommand 所有的draw 都带有 baseInstance??
            [ICBCommand drawPrimitives:MTLPrimitiveTypeTriangle
                           vertexStart:0
                           vertexCount:vertexCount
                         instanceCount:1            // 只会值一个实例??  这个instance不只是一个图元，是整个网格??
                         baseInstance:objIndex];   // 实例的开始是ojbIndex ？？ --- 只绘制 第ojbIndex个实例
                         // baseInstance:1]; // 这样效果就错了
        }
    }

    return self;
}

/// Updates non-Metal state for the current frame including updates to uniforms used in shaders
- (void)updateState
{
    _frameNumber++;

    _inFlightIndex = _frameNumber % AAPLMaxFramesInFlight;

    AAPLFrameState * frameState = _frameStateBuffer[_inFlightIndex].contents;

    frameState->aspectScale = _aspectScale; // 1个CPU资源对应3个GPU资源
}


/// Called whenever the view needs to render
- (void) drawInMTKView:(nonnull MTKView *)view
{
    
    // Wait to ensure only AAPLMaxFramesInFlight are getting processed by any stage in the Metal
    //   pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    [self updateState];

    // Create a new command buffer for each render pass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Frame Command Buffer";

    // Add completion hander which signals _inFlightSemaphore when Metal and the GPU has fully
    // finished processing the commands encoded this frame.  This indicates when the dynamic
    // _frameStateBuffer, that written by the CPU in this frame, has been read by Metal and the GPU
    // meaning we can change the buffer contents without corrupting the rendering
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_sema);
     }];

    
    
    
    // 从 _frameStateBuffer[_inFlightIndex]  blit拷贝到 _indirectFrameStateBuffer, 因为_indirectFrameStateBuffer是在ICBs中编码好的,ICBs缓冲集中的
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder copyFromBuffer:_frameStateBuffer[_inFlightIndex] sourceOffset:0
                       toBuffer:_indirectFrameStateBuffer destinationOffset:0
                           size:_indirectFrameStateBuffer.length];
    [blitEncoder endEncoding];
    
    
    

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    // If we've gotten a renderPassDescriptor we can render to the drawable, otherwise we'll skip
    //   any rendering this frame because we have no drawable to draw to
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Main Render Encoder";
        [renderEncoder setCullMode:MTLCullModeBack];

       
        
        // ICBs不包含PSO, 也就是所有object都用同一个shader来处理,
        // PSO还是通过Encoder来设置，Encoder调用executeCommandsInBuffer所有IBCs的draw都用同一个shader
        // "继承"
        // _indirectCommandBuffer 从其父编码器 renderEncoder 继承渲染管道状态。
        // _indirectCommandBuffer 隐式继承任何“无法编码到其中的渲染状态”，例如剔除模式(setCullMode)和渲染通道(render pass)的深度或模板状态(setDepthStencilState)。
        [renderEncoder setRenderPipelineState:_renderPipelineState];
       
        
        
        
        // 要访问间接命令缓冲区(indirect command buffer)所引用的单个缓冲区(individual buffers)需要使用useResource:usage:接口
        // ICBs需要的所有MTLBuffer都要调用一下Encoder.useResource，表示GPU可以访问间接命令缓冲区中的资源 ??为什么这样设计??
        // Make a useResource call for each buffer needed by the indirect command buffer.
        for (int i = 0; i < AAPLNumObjects; i++)
        {
            [renderEncoder useResource:_vertexBuffer[i] usage:MTLResourceUsageRead];
        }
        [renderEncoder useResource:_objectParameters usage:MTLResourceUsageRead];
        [renderEncoder useResource:_indirectFrameStateBuffer usage:MTLResourceUsageRead];

    
        
        // 渲染在ICB中的全部渲染(通过withRange限制渲染哪些编码指令)
        // 使用 executeCommandsInBuffer:withRange: 代替原来的 drawPrimitives:vertexStart:vertexCount:
        // Draw everything in the indirect command buffer.
        [renderEncoder executeCommandsInBuffer:_indirectCommandBuffer withRange:NSMakeRange(0, AAPLNumObjects)];

        
        
        
        // We're done encoding commands
        [renderEncoder endEncoding];
        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}



/// Create a Metal buffer containing a 2D "gear" mesh   生成网格 运行时生成顶点 三角心等信息
- (id<MTLBuffer>)newGearMeshWithNumTeeth:(uint32_t)numTeeth
{
    NSAssert(numTeeth >= 3, @"Can only build a gear with at least 3 teeth");

    static const float innerRatio = 0.8;
    static const float toothWidth = 0.25;
    static const float toothSlope = 0.2;

    // For each tooth, this function generates 2 triangles for tooth itself, 1 triangle to fill
    // the inner portion of the gear from bottom of the tooth to the center of the gear,
    // and 1 triangle to fill the inner portion of the gear below the groove beside the tooth.
    // Hence, the buffer needs 4 triangles or 12 vertices for each tooth.
    uint32_t numVertices = numTeeth * 12;
    uint32_t bufferSize = sizeof(AAPLVertex) * numVertices;
    id<MTLBuffer> metalBuffer = [_device newBufferWithLength:bufferSize options:0];
    metalBuffer.label = [[NSString alloc] initWithFormat:@"%d Toothed Cog Vertices", numTeeth];

    AAPLVertex *meshVertices = (AAPLVertex *)metalBuffer.contents;

    const double angle = 2.0*M_PI/(double)numTeeth;
    static const packed_float2 origin = (packed_float2){0.0, 0.0};
    int vtx = 0;

    // Build triangles for teeth of gear
    for(int tooth = 0; tooth < numTeeth; tooth++)
    {
        // Calculate angles for tooth and groove
        const float toothStartAngle = tooth * angle;
        const float toothTip1Angle  = (tooth+toothSlope) * angle;
        const float toothTip2Angle  = (tooth+toothSlope+toothWidth) * angle;;
        const float toothEndAngle   = (tooth+2*toothSlope+toothWidth) * angle;
        const float nextToothAngle  = (tooth+1.0) * angle;

        // Calculate positions of vertices needed for the tooth
        const packed_float2 groove1    = { sin(toothStartAngle)*innerRatio, cos(toothStartAngle)*innerRatio };
        const packed_float2 tip1       = { sin(toothTip1Angle), cos(toothTip1Angle) };
        const packed_float2 tip2       = { sin(toothTip2Angle), cos(toothTip2Angle) };
        const packed_float2 groove2    = { sin(toothEndAngle)*innerRatio, cos(toothEndAngle)*innerRatio };
        const packed_float2 nextGroove = { sin(nextToothAngle)*innerRatio, cos(nextToothAngle)*innerRatio };

        // Right top triangle of tooth
        meshVertices[vtx].position = groove1;
        meshVertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = tip1;
        meshVertices[vtx].texcoord = (tip1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = tip2;
        meshVertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;

        // Left bottom triangle of tooth
        meshVertices[vtx].position = groove1;
        meshVertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = tip2;
        meshVertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove2;
        meshVertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        // Slice of circle from bottom of tooth to center of gear
        meshVertices[vtx].position = origin;
        meshVertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove1;
        meshVertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove2;
        meshVertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        // Slice of circle from the groove to the center of gear
        meshVertices[vtx].position = origin;
        meshVertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove2;
        meshVertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = nextGroove;
        meshVertices[vtx].texcoord = (nextGroove + 1.0) / 2.0;
        vtx++;
    }

    return metalBuffer;
}

/// Called whenever view changes orientation or layout is changed
- (void) mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Calculate scale for quads so that they are always square when working with the default
    // viewport and sending down clip space corrdinates.

    _aspectScale.x = (float)size.height / (float)size.width;
    _aspectScale.y = 1.0;
}


@end
