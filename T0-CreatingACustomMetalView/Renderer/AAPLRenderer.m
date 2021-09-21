/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per-frame rendering
*/
#import "AAPLRenderer.h"
#import "AAPLShaderTypes.h"
#import "AAPLConfig.h"

#if CREATE_DEPTH_BUFFER
static const MTLPixelFormat AAPLDepthPixelFormat = MTLPixelFormatDepth32Float; // 没有模板测试buffer只有深度测试的buffer
// MTLPixelFormatDepth24Unorm_Stencil8
// MTLPixelFormatDepth32Float_Stencil8
#endif

@implementation AAPLRenderer
{
    // renderer global ivars
    id <MTLDevice>              _device;
    id <MTLCommandQueue>        _commandQueue;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLBuffer>              _vertices;
    id <MTLTexture>             _depthTarget;

    // Render pass descriptor which creates a render command encoder to draw to the drawable
    // textures
    MTLRenderPassDescriptor *_drawableRenderDescriptor;

    vector_uint2 _viewportSize;
    
    NSUInteger _frameNum;
}

- (nonnull instancetype)initWithMetalDevice:(nonnull id<MTLDevice>)device
                        drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat
{
    self = [super init];
    if (self)
    {
        _frameNum = 0;

        _device = device;

        _commandQueue = [_device newCommandQueue];
        
        
        /*
         要渲染到视图，创建一个 MTLRenderPassDescriptor 对象， 该对象以 “图层(CAMetalLayer)提供的纹理(layer.texture)” 为目标
        
         ------------------------------------------------------------------------------------------
         MTLRenderPassDescriptor对象有点像OpenGl的framebuffer 需要设置期颜色和深度附件
         每次渲染时候创建RenderCommandEncoder, 都需要先给定RenderPassDescriptor, 相当于 给定 渲染目标
         然后就可以往这个Encoder 设置渲染的命令 比如
            RenderPipeLineState (shader,期望颜色/深度测试附件的像素格式,每个颜色附件的混合方式)
            DepthStenclState    (是否需要深度测试 深度测试方式)
            setVertexBuffer     (设置uniform或者attribute顶点属性)
            drawPrimitives      (绘制图元)
         ------------------------------------------------------------------------------------------
         
         AAPLRender把RenderPass作为实例变量_drawableRenderPassDescriptor
         初始化渲染器AAPLRender时，此描述符的大多数属性会自动设置，比如两个Action
         loadAction
            renderPass加载后 清除纹理的内容
            此附件会执行的操作 在一个render encoder的render pass开始的时候
         
            如果您的应用程序为给定帧渲染渲染目标的“所有像素”，请使用 MTLLoadActionDontCare 操作，它允许 GPU 避免加载纹理的现有内容。
            否则，使用 MTLLoadActionClear 操作清除呈现目标的先前内容
            或使用 MTLLoadActionLoad 操作保留它们 ?? load 和 dontcare区别 就是 是否加载纹理  读修改写 还是 直接写 ??
         
            MTLLoadActionClear 操作也避免了加载现有纹理内容的成本，但它仍然会产生用 clear color.填充目标的成本。
         
            对于颜色渲染目标，   默认值为 MTLLoadActionDontCare
            对于深度或模板渲染目标，默认值为 MTLLoadActionClear
         
         storeAction
            renderPass完成时 将任何渲染的内容存储到纹理
            由附件执行，在一个render encoder的render pass结束之后
         
            如果您的应用在完成渲染过程后不需要纹理中的数据，请使用 MTLStoreActionDontCare 操作。
            否则，如果纹理是直接存储的，则使用 MTLStoreActionStore 操作
            如果纹理是多采样纹理，则使用 MTLStoreActionMultisampleResolve 操作
            在某些功能集中，您可以使用 MTLStoreActionStoreAndMultisampleResolve 操作在单个渲染过程中存储和解析纹理。 ???
            
            当storeAction 是 MTLStoreActionMultisampleResolve 或 MTLStoreActionStoreAndMultisampleResolve 时，
            resolveTexture 属性必须设置为纹理以用作解析操作的目标. 使用 resolveLevel、resolveSlice 和 resolveDepthPlane 属性分别指定解析纹理的 mipmap 级别、立方体切片和深度平面。
         
            对于颜色渲染目标，默认值为 MTLStoreActionStore。
            对于深度或模板渲染目标，默认值为 MTLStoreActionDontCare。
         
         */

        _drawableRenderDescriptor = [MTLRenderPassDescriptor new];
        _drawableRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _drawableRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _drawableRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);
        // _drawableRenderDescriptor.colorAttachments[0].resolveTexture // 解析纹理 ??
        // _drawableRenderDescriptor.colorAttachments[0].resolveLevel
        // _drawableRenderDescriptor.colorAttachments[0].resolveSlice
        // _drawableRenderDescriptor.colorAttachments[0].resolveDepthPlane
        
#if CREATE_DEPTH_BUFFER
        _drawableRenderDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        _drawableRenderDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
        _drawableRenderDescriptor.depthAttachment.clearDepth = 1.0;
#endif

        {

            //-------------------------------------------------------------------------------------------------------------------
            
            // Set up a simple MTLBuffer with the vertices, including position and texture coordinates
            static const AAPLVertex quadVertices[] =
            {
                // Pixel positions, Color coordinates
                { {  250,  -250 },  { 1.f, 0.f, 0.f } },
                { { -250,  -250 },  { 0.f, 1.f, 0.f } },
                { { -250,   250 },  { 0.f, 0.f, 1.f } },

                { {  250,  -250 },  { 1.f, 0.f, 0.f } },
                { { -250,   250 },  { 0.f, 0.f, 1.f } },
                { {  250,   250 },  { 1.f, 0.f, 1.f } },
            };

            // Create a vertex buffer, and initialize it with the vertex data.
            _vertices = [_device newBufferWithBytes:quadVertices
                                             length:sizeof(quadVertices)
                                            options:MTLResourceStorageModeShared];

            _vertices.label = @"Quad";

            //-------------------------------------------------------------------------------------------------------------------
            
            id<MTLLibrary> shaderLib = [_device newDefaultLibrary];
            if(!shaderLib)
            {
                NSLog(@" ERROR: Couldnt create a default shader library");
                // assert here because if the shader libary isn't loading, nothing good will happen
                return nil;
            }

            id <MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"vertexShader"];
            if(!vertexProgram)
            {
                NSLog(@">> ERROR: Couldn't load vertex function from default library");
                return nil;
            }

            id <MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"fragmentShader"];
            if(!fragmentProgram)
            {
                NSLog(@" ERROR: Couldn't load fragment function from default library");
                return nil;
            }
            
            // Create a pipeline state descriptor to create a compiled pipeline state object
            MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];

            pipelineDescriptor.label                           = @"MyPipeline";
            pipelineDescriptor.vertexFunction                  = vertexProgram;
            pipelineDescriptor.fragmentFunction                = fragmentProgram;
            pipelineDescriptor.colorAttachments[0].pixelFormat = drawabklePixelFormat;
            /*
                存储深度数据的附件 他的像素格式，默认是MTLPixelFormatInvalid
             */
            // pipelineDescriptor.depthAttachmentPixelFormat
            
            /*
                默认值为 NO，表示禁用混合且像素值不受混合影响。
                禁用混合实际上与 MTLBlendOperationAdd 混合操作相同，对于 RGB 和 alpha，源混合因子为 1.0，目标混合因子为 0.0。
             
                如果值为 YES，则启用混合，并且 blend descriptor属性，用于确定源颜色值和目标颜色值的组合方式。
             */
            //pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
            //pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
            //pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
            //pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            //pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorZero;
           

#if CREATE_DEPTH_BUFFER
            pipelineDescriptor.depthAttachmentPixelFormat      = AAPLDepthPixelFormat;
#endif

            NSError *error;
            _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                                     error:&error];
            if(!_pipelineState)
            {
                NSLog(@"ERROR: Failed aquiring pipeline state: %@", error);
                return nil;
            }
            
            //-------------------------------------------------------------------------------------------------------------------
            /*
             MTLDepthStencilDescriptor 对象用于定义 一个渲染管道(rendering pipeline) 的 深度和模板阶段的配置。
             depthWriteEnabled
                要启用将深度值写入深度附件，请将 depthWriteEnabled 属性设置为 true。
             depthCompareFunction
                指定深度测试的执行方式。
                如果片段的深度值未通过深度测试，则丢弃该片段(discarded)
                MTLCompareFunction.less 是 depthCompareFunction 的常用值，因为离观察者比像素深度值（之前写入的片段）更远的片段值无法通过深度测试，并被认为被较早的深度值遮挡。
                默认值是 MTLCompareFunctionAlways 表示深度测试始终通过，“片段fragment” 仍然是替换指定位置数据的“候选candidate”。
             frontFaceStencil 和 backFaceStencil
                定义了两个独立的模板描述符/MTLStencilDescriptor, 一个用于正面图元，另一个用于背面图元
                这两个属性都可以设置为同一个 MTLStencilDescriptor 对象。
             
             */
            MTLDepthStencilDescriptor* desc = [[MTLDepthStencilDescriptor alloc] init];
            desc.depthCompareFunction = MTLCompareFunctionLess;
            desc.depthWriteEnabled = true ;
            MTLStencilDescriptor* stenilDesc = [[MTLStencilDescriptor alloc]init];
            /*
             stencilCompareFunction
             
                在“屏蔽参考值”和“模板附件中的屏蔽值”之间执行的比较方式
             
                例如，如果 stencilCompareFunction 是 MTLCompareFunctionLess，那么如果"屏蔽参考值"小于"屏蔽存储模板值"，则模板测试通过。
             
                默认值为 MTLCompareFunctionAlways，表示模板测试始终通过。
             
                在比较发生之前，通过对 readMask 值执行“逻辑与运算”来屏蔽"存储的模板值"和"参考值"
             */
            stenilDesc.stencilCompareFunction = MTLCompareFunctionAlways; // alawy pass
            stenilDesc.readMask = 0xFF; // 对比时使用，默认全1，即不修改原值
            /*
                writeMask 用于对将作为"模板操作的结果" 写入模板附件的值进行"逻辑与运算"
                使用写掩码的最低有效位。???
                默认值为全1。 使用默认writeMask进行逻辑与运算，不会更改该值。
             */
            stenilDesc.writeMask = 0xFF;
            /*
                默认值是 MTLStencilOperationKeep，它不会改变当前的模板值。
                当像素的"模板测试失败"时，其"传入的颜色、深度或模板值"将被丢弃。
             */
            stenilDesc.stencilFailureOperation = MTLStencilOperationKeep;
            /*
                depthFailureOperation
                当模板测试通过,但深度测试失败时,为更新“模板附件”中的值而执行的操作
                (渲染管线先模板后深度测试)
             */
            stenilDesc.depthFailureOperation = MTLStencilOperationKeep ;
            /*
                当模板测试和深度测试都通过时，为更新模板附件中的值而执行的操作。
             */
            stenilDesc.depthStencilPassOperation =  MTLStencilOperationKeep ;
           
            desc.frontFaceStencil = stenilDesc;
            desc.backFaceStencil  = stenilDesc;
            id<MTLDepthStencilState> _depthStencilState = [_device newDepthStencilStateWithDescriptor:desc];
            //(__bridge void*) _depthStencilState;
            
        }
    }
    return self;
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer*)metalLayer
{
    _frameNum++;

    // Create a new command buffer for each render pass to the current drawable.
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    // 从CAMetalLayer中获取CAMetalDrawable CAMetalDrawable提供纹理  给 Core Animation 渲染到屏上
    id<CAMetalDrawable> currentDrawable = [metalLayer nextDrawable];

    // If the current drawable is nil, skip rendering this frame
    if(!currentDrawable)
    {
        return;
    }

    _drawableRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    
    id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_drawableRenderDescriptor];


    /*
     MTLDepthStencilState/深度和模板状态 必须与 RenderPass 指定的附件配置兼容
     如果启用深度测试或深度写入，则 RenderPass/MTLRenderPassDescriptor 必须包含深度附件
     如果启用模板测试或模板写入，则 RenderPass/MTLRenderPassDescriptor 必须包含模板附件
     默认值为nil  MTLDepthStencilDescriptor的默认属性值决定了行为。
     */
    //[renderEncoder setDepthStencilState:nil];
    [renderEncoder setRenderPipelineState:_pipelineState];

    [renderEncoder setVertexBuffer:_vertices
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices ];

    {
        AAPLUniforms uniforms;

#if ANIMATION_RENDERING
        uniforms.scale = 0.5 + (1.0 + 0.5 * sin(_frameNum * 0.1));
#else
        uniforms.scale = 1.0;
#endif
        uniforms.viewportSize = _viewportSize;

        [renderEncoder setVertexBytes:&uniforms
                               length:sizeof(uniforms)
                              atIndex:AAPLVertexInputIndexUniforms ];
    }

    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    

    [renderEncoder endEncoding];

    [commandBuffer presentDrawable:currentDrawable];

    [commandBuffer commit];
}

- (void)drawableResize:(CGSize)drawableSize
{
    _viewportSize.x = drawableSize.width;
    _viewportSize.y = drawableSize.height;
    
#if CREATE_DEPTH_BUFFER
    MTLTextureDescriptor *depthTargetDescriptor = [MTLTextureDescriptor new];
    depthTargetDescriptor.width       = drawableSize.width;
    depthTargetDescriptor.height      = drawableSize.height;
    depthTargetDescriptor.pixelFormat = AAPLDepthPixelFormat;
    depthTargetDescriptor.storageMode = MTLStorageModePrivate;
    depthTargetDescriptor.usage       = MTLTextureUsageRenderTarget;

    _depthTarget = [_device newTextureWithDescriptor:depthTargetDescriptor];

    /*
        在这里创建了一个深度附件纹理，作为深度测试，给到render pass
        但是颜色附件纹理，每次都从CAMetalLayer中得到CADrawable.texture, 给到render pass
        也就是说，
        用来生成RenderEncoder的RenderPass每次都更新颜色附件纹理，但是深度附件纹理不修改
     */
    _drawableRenderDescriptor.depthAttachment.texture = _depthTarget;

    
#endif
}

@end
