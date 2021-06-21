//
//  MTKViewRenderDelegate.m
//  T4-AAPLMesh
//
//  Created by hehanlong on 2021/6/18.
//

#import "MTKViewRenderDelegate.h"

#import "ShaderType.h"
#import "AAPLMesh.h"

@implementation MTKViewRenderDelegate
{
    id<MTLCommandQueue> _commandQueue ;
    
    id<MTLRenderPipelineState> _renderPipelineState ;
    id<MTLDepthStencilState> _depthStencilState;
    id<MTLBuffer> _vertexBuffer ;
    id<MTLTexture> _texture ;
    
    NSArray<AAPLMesh*> * _meshes;
}


-(instancetype) initWithMTKView:(MTKView*)view
{
    self = [super init];
    if (self) {
        [self setupView:view];
        MTLVertexDescriptor* mtlVertxDesc = [self loadAssets:view.device];
        [self setupRender:view withVertexDesc:mtlVertxDesc];
       
    } else {
        NSLog(@"initWithMTKView fail? no memory");
    }
    return self ;
}

#pragma mark - Setup View
-(void) setupView:(MTKView*)view
{
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
    view.clearDepth = 1.0;
    view.clearStencil = 0.0;
    
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    view.sampleCount = 1;
}


#pragma mark - Setup Render


-(void) setupRender:(MTKView*)view withVertexDesc:(MTLVertexDescriptor*) mtlVertxDesc
{
    id<MTLDevice> device = view.device ;
    
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"MyVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"MyFragmentShader"];
    
    MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    
    renderPipelineDesc.vertexFunction = vertexFunction;
    renderPipelineDesc.fragmentFunction = fragmentFunction;
    
    renderPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    
    renderPipelineDesc.sampleCount = 1 ;
    
    renderPipelineDesc.vertexDescriptor = mtlVertxDesc;
    
    
    NSError* error;
    _renderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
    if (_renderPipelineState == nil)
    {
        NSLog(@" newRenderPipelineStateWithDescriptor fail %@", error);
        return ;
    }
    
    
    MTLDepthStencilDescriptor* depthStencilDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDesc.depthWriteEnabled = YES;
    
    _depthStencilState = [device newDepthStencilStateWithDescriptor:depthStencilDesc];
    

    _commandQueue = [view.device newCommandQueue];
}

-(MTLVertexDescriptor*) loadAssets:(id<MTLDevice>) device
{
    static MyVertex vertex[] = {
        { {0.0,  1.0}, {0.5, 0} },
        { {1.0, -1.0}, {1.0, 1.0} },
        { {-1.0,-1.0}, {0,   1.0} },
    };
    
    _vertexBuffer = [device newBufferWithBytes:vertex length:sizeof(vertex) options:MTLResourceStorageModeShared];
    
    MTKTextureLoader* loader =[[MTKTextureLoader alloc] initWithDevice:device];
    
    NSURL* path = [[NSBundle mainBundle] URLForResource:@"StructureSpecular" withExtension:@"png"];
    
    NSDictionary<MTKTextureLoaderOption, id>* options = @{
        // Specifying Resource Options
        MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode:@(MTLStorageModePrivate),
    };
    
    NSError* error ;
    _texture = [loader newTextureWithContentsOfURL:path options:options error:&error];
    
    // OBJ是一种模型的数据格式，存储了模型的顶点、法线、uv等顶点buffer的数据，以及模型组织的索引数据、图元数据等
    // 另外描述了对应.mtl文件中的贴图资源路径、光照参数数据等
    
    // Metal中保存mesh数据的容器是MDLMesh类
    
    // 每个MDLMesh可能包含多个MDLSubmesh
    
    // 每个MDLSubmesh中保存了模型顶点的index buffer数据(描述如何组织mesh顶点的绘制)
    // 另外还保存了模型的材质贴图信息，用于对应的模型纹理贴图
    
    // AAPLAMesh是官方demo中使用的一个模型加载工具类，用于加载demo中的OBJ模型
    // 实际开发中模型的设置规范要和美术制作统一，顶点buffer的数据格式，数据组织等可能改变 ?? 用3dmax到处
    // MDLMesh和MDLSubMesh 分别对应 --AAPLMesh 和 AAPLESubMesh
    
    // “模型数据” --> MDLVertexDescriptor描述类 --> 解析 -->  MDLMesh
    // MDLVertexDescriptor 配置顶点的属性结构、格式和数据布局等, 从而将mesh数据读取到顶点bufer中
    //
    
    MTLVertexDescriptor* vertexDesc = [[MTLVertexDescriptor alloc] init];
    // typedef enum MTLVertexFormat : NSUInteger
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3; // 改成3*float
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    
    vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[1].offset = 12;// (uint32_t)&((MyVertex*)0)->uv; // = 16
    vertexDesc.attributes[1].bufferIndex = 0;

    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex; // 几种的区别??
    vertexDesc.layouts[0].stepRate = 1;
    vertexDesc.layouts[0].stride = 44; // sizeof(MyVertex); // = 48  // GPU从buffer中读取每个顶点数据的固定跨度
    
    NSLog(@"uv offset = %u", (uint32_t)&((MyVertex*)0)->uv); // 16
    NSLog(@" sizeof(MyVertex) = %lu", sizeof(MyVertex)); // 48
    
    // 上面定义读取到cpu和gpu数据的格式
    // 下面定义要读取的内容
    
    // MDLVertexDescriptor 定义在 Model I/O Framework 用来描述从模型文件中读取什么数据
    
    // 这里暂时只读取顶点位置属性和uv坐标属性，还有法线和切线数据在在之后的光照计算中才会用到，暂时不读取
    MDLVertexDescriptor* modelDesc = MTKModelIOVertexDescriptorFromMetal(vertexDesc);
    modelDesc.attributes[0].name = MDLVertexAttributePosition; //
    modelDesc.attributes[1].name = MDLVertexAttributeTextureCoordinate;
    // modelDesc.attributes[2].name = MDLVertexAttributeNormal; // 法线
    // modelDesc.attributes[3].name = MDLVertexAttributeTangent; // 正切
    // modelDesc.attributes[3].name = MDLVertexAttributeBitangent;// 副法
    
   
    // OBJ模型加载到我们的_meshes保存
    // AAPLMesh的newMeshesFromURL函数来加载模型数据，这样我们的mesh数据就保存到了工程内的_meshes中，
    // 里面包含了 1.顶点buffer数据 2.索引buffer数据 3.模型贴图的引用
    NSURL* modelFileURL = [[NSBundle mainBundle] URLForResource:@"Temple.obj" withExtension:nil]; // obj文件中会指定材质文件 mtllib Temple.mtl
    NSAssert(modelFileURL, @"Could not find model (%@) file in bundle", modelFileURL.absoluteString);
    NSError* errorOfModel ;
    _meshes = [AAPLMesh newMeshesFromURL:modelFileURL
                 modelIOVertexDescriptor:modelDesc
                             metalDevice:device
                                   error:&errorOfModel];
    NSAssert(_meshes, @"Could not load model with %@", error);
 
    [self _testNSNull];
    return vertexDesc;

}


-(void) _testNSNull
{
//    NSArray* array = @[
//        [[NSObject alloc] init],
//        [NSNull null],
//        @"StringElemnt",
//        nil, // 用 @[]指令的方式 会出现 Collection element of type 'void *' is not an Objective-C object
//        [[NSObject alloc] init],
//        [[NSObject alloc] init],
//        nil
//    ];
        
   
    NSArray* array = [NSArray arrayWithObjects:
                      [[NSObject alloc] init],
                      [NSNull null], // 这个并非结束
                      @"StringElemnt",
                      nil, // 以这个为结束
                      [[NSObject alloc] init],
                      [[NSObject alloc] init],
                      nil];
    NSLog(@"[NSNull null] 的作用 %lu", array.count); // 只有3个
    
    int i = 0 ;
    for (__unsafe_unretained id obj in array)
    {
        NSLog(@"带有[NSNull null]数组元素的数组 %d is %@", i , obj); // 1 is <null>
        i++;
    } // for in 不会剔除 NSNull null对象
 

//    NSMutableDictionary *mutableDictionary = [[NSMutableDictionary alloc] init];
//    [mutableDictionary setObject:nil forKey:@"Key-nil"]; // 会引起Crash  warning: Null passed to a callee that requires a non-null argument
//    [mutableDictionary setObject:[NSNull null] forKey:@"Key-nil"]; // 不会引起Crash
//    //所以在使用时，如下方法是比较安全的
//    [mutableDictionary setObject:(nil == value ? [NSNull null] : value)forKey:@"Key"];
    
}

// drawMeshes函数中，我们遍历mesh数组数据，依次将
// 顶点buffer传递给顶点着色器，
// 贴图数据传送给片段着色器，
// 并调用draw call绘制模型
-(void) drawMeshes:(id<MTLRenderCommandEncoder>) encoder
{
    // __unsafe_unretained和__weak一样，表示的是对象的一种弱引用关系，
    // 唯一的区别是：
    // __weak修饰的对象被释放后，指向对象的指针会置空，也就是指向nil,不会产生野指针；
    // 而__unsafe_unretained修饰的对象被释放后，指针不会置空，而是变成一个野指针 抛出BAD_ACCESS的异常
    
    // _weak对性能会有一定的消耗，使用__weak,需要检查对象是否被释放，在追踪是否被释放的时候当然需要追踪一些信息，
    // 那么此时__unsafe_unretained比__weak快，
    // 而且一个对象有大量的__weak引用对象的时候，当对象被废弃，那么此时就要遍历weak表，把表里所有的指针置空，消耗cpu资源
    
    // 当A拥有B对象，A消亡B也消亡，这样当B存在，A也一定会存在的时候，此时B要调用A的接口，就可以通过__unsafe_unretained 保持对A的引用关系
    // 比如 MyViewController 拥有 MyView, MyView 需要调用 MyViewController 的接口。MyView 中就可以通过 __unsafe_unretained 保持对MyViewController的引用
    // __unsafe_unretained MyViewController * myVC;
    for (__unsafe_unretained AAPLMesh* mesh in _meshes)
    {
        __unsafe_unretained MTKMesh* mtkMesh = mesh.metalKitMesh; // 包含顶点buffer
        //NSLog(@"%@ has vertex count %lu buffer %lu", mtkMesh, mtkMesh.vertexCount,  mtkMesh.vertexBuffers.count);
        // vertexCount 21527 buffer 1
    
        // 设置顶点buffer(mesh中可能有多个)
        __unsafe_unretained NSArray<MTKMeshBuffer*>* mtkMeshBuffers =  mtkMesh.vertexBuffers ;
        for (int bufferIndex = 0; bufferIndex < mtkMeshBuffers.count; bufferIndex++)
        {
            /*
             nil：指向一个对象的空指针,对objective c id 对象赋空值                    NSString *str = nil;

             Nil：指向一个类的空指针,表示对类进行赋空值.                               Class Class1 = Nil;    Clsss Class2 = [NSURL class];

             NULL：指向其他类型（如：基本类型、C类型）的空指针, 用于对非对象指针赋空值.      char *charC     = NULL;

             NSNull：在集合对象中，表示空值的对象 NSNull有 +(NSNull*)null; 单例方法.   [NSNull null]; 返回的是单例
             */
            __unsafe_unretained MTKMeshBuffer* mtkBuffer = mtkMeshBuffers[bufferIndex];
            // if (buffer != nil) { // 数组元素 不能这样判断NULL
            if ((NSNull*)mtkBuffer != [NSNull null]) {
                // MTKMeshBuffer.MTLBuffer buffer 支持所有顶点和索引数据的 Metal 缓冲区
                [encoder setVertexBuffer:mtkBuffer.buffer offset:0 atIndex:bufferIndex];
            }
        }
        
        // 上面设置 这个AAPLMesh的 顶点属性buffer
        // 下面绘制 每个AAPLSubMesh的所有图元, 给定每个图元的顶点索引
        
        // 设置纹理图 以及渲染mesh的submesh
        for(__unsafe_unretained AAPLSubmesh* submesh in mesh.submeshes)
        {
            //NSLog(@"%@ has %lu textures ", submesh, submesh.textures.count); // 3
            [encoder setFragmentTexture:submesh.textures[0] atIndex:0];
            [encoder setFragmentTexture:submesh.textures[1] atIndex:1];
            [encoder setFragmentTexture:submesh.textures[2] atIndex:2];
            
            // metalKitSubmmesh A MetalKit submesh 包含了图元类型 索引buffer和索引buffer数目
            MTKSubmesh* metalKitSubmesh = submesh.metalKitSubmmesh;
            
            [encoder drawIndexedPrimitives:metalKitSubmesh.primitiveType
                                indexCount:metalKitSubmesh.indexCount
                                 indexType:metalKitSubmesh.indexType // MDLIndexBitDepthUInt32 每个索引使用32bit
                               indexBuffer:metalKitSubmesh.indexBuffer.buffer
                         indexBufferOffset:metalKitSubmesh.indexBuffer.offset];
            
        }
        
      
    }
 

}

#pragma mark - MTKView delegate
-(void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    
}

-(void) drawInMTKView:(MTKView *)view
{
    id <MTLCommandBuffer> cmdBuffer = [_commandQueue commandBuffer];
    cmdBuffer.label = @"MyCommandBuffer";
    
    id <MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    
    encoder.label = @"MyCommandEncoder";
    
    [encoder pushDebugGroup:@"RenderPass"];
    
    // 面剔除(Face culling)
    
    // 指定图元的正面绘制时顺时针方向处理 (MTLWindingClockwise) 还是逆时针方向处理 (MTLWindingCounterClockwise) ，
    // 默认值是 MTLWindingClockwise  !! 顺时针
    
    // OpenGL允许检查所有正面朝向（Front facing）观察者的面，并渲染它们，而丢弃所有背面朝向（Back facing）的面
    // 默认情况下，逆时针的顶点连接顺序被定义为三角形的正面
    
    [encoder setCullMode:MTLCullModeBack]; // 背面图元裁剪 Culls back-facing primitives.
    //[encoder setFrontFacingWinding:MTLWindingClockwise];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    
    [encoder setRenderPipelineState:_renderPipelineState];
    [encoder setDepthStencilState:_depthStencilState];
    
    // texture和buffer等ArgumentTable 以及draw图元 改成用AAPLMesh中的
    
    //[encoder setFragmentTexture:_texture atIndex:0];
    //[encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    //[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    // 不调用 setFragmentTexture/setVertexBuffer 而直接调用 drawPrimitives 会有崩溃
    // validateFunctionArguments:3714:
    // failed assertion `Vertex Function(MyVertexShader): missing buffer binding at index 0 for vertexBuffer.0[0].'
    
    [self drawMeshes:encoder];
    
    
    [encoder popDebugGroup];
    
    [encoder endEncoding]; // 调用了这个之后 就不能在使用这个encoder了
    
    [cmdBuffer presentDrawable:view.currentDrawable];
    
    [cmdBuffer commit];

}



@end
