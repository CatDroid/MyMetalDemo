//
//  MTKViewRenderDelegate.m
//  T5-UniformBuffer
//
//  Created by hehanlong on 2021/6/20.
//

#import "MTKViewRenderDelegate.h"
#import "AAPLMesh.h"
#import "AAPLMathUtilities.h"
#import "ShaderType.h"

@interface MTKSubmesh(MyMTKSubmesh)
-(void) dumpInfo ;
@end

@implementation MTKSubmesh(MyMTKSubmesh)

-(void) dumpInfo
{
    NSLog(@"MTKSubmesh buffer=%@ offset=%lu indexCount=%lu indexType=%lu primitiveType=%lu",
          self.indexBuffer.buffer ,// MTKMeshBuffer
          self.indexBuffer.offset ,
          self.indexCount ,
          self.indexType ,
          self.primitiveType
          );
    /*
     
     MTKSubmesh buffer=<CaptureMTLBuffer: 0x2819a7080> -> <AGXA12FamilyBuffer: 0x1036078a0>
         label = MDL_OBJ-Indices
         length = 84024
         cpuCacheMode = MTLCPUCacheModeDefaultCache
         storageMode = MTLStorageModeShared
         hazardTrackingMode = MTLHazardTrackingModeTracked
         resourceOptions = MTLResourceCPUCacheModeDefaultCache MTLResourceStorageModeShared MTLResourceHazardTrackingModeTracked
         purgeableState = MTLPurgeableStateNonVolatile
         label = MDL_OBJ-Indices offset=0 indexCount=21006 indexType=1 primitiveType=3
     
     MTKSubmesh buffer=<CaptureMTLBuffer: 0x2819a7100> -> <AGXA12FamilyBuffer: 0x1036079f0>
         label = MDL_OBJ-Indices
         length = 192
         cpuCacheMode = MTLCPUCacheModeDefaultCache
         storageMode = MTLStorageModeShared
         hazardTrackingMode = MTLHazardTrackingModeTracked
         resourceOptions = MTLResourceCPUCacheModeDefaultCache MTLResourceStorageModeShared MTLResourceHazardTrackingModeTracked
         purgeableState = MTLPurgeableStateNonVolatile
         label = MDL_OBJ-Indices offset=0 indexCount=48 indexType=1 primitiveType=3
     
    MTKSubmesh buffer=<CaptureMTLBuffer: 0x2819a6f40> -> <AGXA12FamilyBuffer: 0x103607750>
        label = MDL_OBJ-Indices
        length = 245064
        cpuCacheMode = MTLCPUCacheModeDefaultCache
        storageMode = MTLStorageModeShared
        hazardTrackingMode = MTLHazardTrackingModeTracked
        resourceOptions = MTLResourceCPUCacheModeDefaultCache MTLResourceStorageModeShared MTLResourceHazardTrackingModeTracked
        purgeableState = MTLPurgeableStateNonVolatile
        label = MDL_OBJ-Indices offset=0 indexCount=61266 indexType=1 primitiveType=3
     */
}


@end


@implementation MTKViewRenderDelegate
{
    id<MTLRenderPipelineState> _renderPipelineState ;
    id<MTLDepthStencilState> _depthStencilState ;
    id<MTLCommandQueue> _commandqueue ;
    
    id<MTLBuffer> _transformUniformBuffer ;
    id<MTLBuffer> _vertexBuffer ;
    id<MTLTexture> _colorTexture ;
    
    NSArray<AAPLMesh*>* _meshes ;
    
    matrix_float4x4 _projectionMatrix ; // 投影矩阵 只跟view比例相关
    
    float _rotation ;
}

-(instancetype) initWithMTKView:(MTKView*) view
{
    self = [super init];
    if (self)
    {
        [self setupView:view];
        MTLVertexDescriptor* desc = [self loadAsserts:view.device];
        [self setupRender:view WithVertexDesc:desc];
    }
    else
    {
        NSLog(@"initWithMTKView uper init fail ");
    }
    
    return self ;
}

#pragma mark - View
-(void) setupView:(MTKView*) view
{
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
    view.clearDepth = 1.0;
    view.clearStencil = 0.0;
    
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB ;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    view.sampleCount = 1 ;
    
}

#pragma mark - Render
-(MTLVertexDescriptor*) loadAsserts:(id<MTLDevice>) gpu
{

    MTLVertexDescriptor* desc = [[MTLVertexDescriptor alloc] init];
    desc.attributes[0].bufferIndex = 0;
    desc.attributes[0].offset = 0;
    desc.attributes[0].format = MTLVertexFormatFloat3; // MTLVertexFormatFloat3 = 30
    
    desc.attributes[1].bufferIndex = 0;
    desc.attributes[1].offset = 3 * 4; // vector_float3 是按照16个字节对齐 (4*4) MDLMesh 不用遵守对齐?? MTLVertexDescriptor描述的是提供MTLBuffer的布局信息 
    desc.attributes[1].format = MTLVertexFormatFloat2;
    
    desc.layouts[0].stepFunction = MTLStepFunctionPerVertex;
    desc.layouts[0].stepRate = 1 ;
    desc.layouts[0].stride = 3*4 + 2*4 + 4*2 + 4*2 + 4*2 ;
    // position(float3)、uv(float2)、normal(half4)、tangent(half4)、bitangent(half4)
    
    // MDLVertexDescriptor* mdlDesc = [[MDLVertexDescriptor alloc] initWithVertexDescriptor:desc];
    MDLVertexDescriptor* mdlDesc = MTKModelIOVertexDescriptorFromMetal(desc); // 使用MTK的接口  ???
    mdlDesc.attributes[0].name = MDLVertexAttributePosition;
    mdlDesc.attributes[1].name = MDLVertexAttributeTextureCoordinate;
    
    NSLog( @"MyVertex.uv offset %lu ", (unsigned long)&(((MyVertex*)0)->uv) ); // MyVertex.uv offset 16
    
    NSURL* path = [[NSBundle mainBundle] URLForResource:@"Temple" withExtension:@"obj"];
    NSError* error ;
    
    _meshes = [AAPLMesh newMeshesFromURL:path modelIOVertexDescriptor:mdlDesc metalDevice:gpu error:&error];
    
    NSAssert(_meshes, @"Temple.mtl load fail %@", error);
    
    return desc ;
    
}

-(void) setupRender:(MTKView*) view  WithVertexDesc:(MTLVertexDescriptor*) vertexDesc
{
    id<MTLDevice> gpu = view.device ;
    
    MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    
    
    id<MTLLibrary> library = [gpu newDefaultLibrary];
   
    renderPipelineDesc.vertexFunction   = [library newFunctionWithName:@"MyVertexShader"];
    renderPipelineDesc.fragmentFunction = [library newFunctionWithName:@"MyFragmentShader"];
    
    NSAssert(renderPipelineDesc.vertexFunction , @"MyVertexShader not found" );
    NSAssert(renderPipelineDesc.fragmentFunction , @"MyFragmentShader not found" );
    
    
    renderPipelineDesc.colorAttachments[0].blendingEnabled = true ;
    renderPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    renderPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    
    renderPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    
    renderPipelineDesc.sampleCount = view.sampleCount;
    
    renderPipelineDesc.vertexDescriptor = vertexDesc ;
    

    NSError* error ;
    _renderPipelineState = [gpu newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
    
    
    MTLDepthStencilDescriptor* depthStencilDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDesc.depthWriteEnabled = YES;
    
    _depthStencilState = [gpu newDepthStencilStateWithDescriptor:depthStencilDesc];
    
    _commandqueue = [gpu newCommandQueue];
    
    [self _setupTransformMatrix:view];
    
    [self _checkBOOL];
}


-(void) _setupTransformMatrix:(MTKView*) view
{
    float aspect = view.frame.size.width / view.frame.size.height ; // 宽高比
    float fov = 65.0f * (M_PI / 180.0f) ; // 垂直方向上的视角
    float nearPlane = 1.0;
    float farPlane = 1500.0;
    _projectionMatrix = matrix_perspective_left_hand(fov, aspect, nearPlane, farPlane);
    
    // 先分配MTLBuffer的大小 设置为GPU和CPU共享  后面更新内容 _transformUniformBuffer.content
    //_transformUniformBuffer = [view.device newBufferWithBytes:(nonnull const void *) length:(NSUInteger) options:MTLStorageModeShared];
    _transformUniformBuffer = [view.device newBufferWithLength:sizeof(MyUniform) options:MTLResourceStorageModeShared];
    
}

-(void) _updateTransformMatrix
{
    MyUniform* uniform = (MyUniform*)_transformUniformBuffer.contents; // (void*)
    uniform->projectionMatrix = _projectionMatrix;
    
#if 1
    matrix_float4x4 location = matrix4x4_translation(0,0,1000); // 为什么在投影前 摄像机坐标系下 z为正数 还可以显示的??
    matrix_float4x4 rotateX = matrix4x4_rotation(-0.5, 1.0, 0.0, 0.0); // (radians=-0.15,{1.0, 0.0, 0.0}) 左手坐标系 左手螺旋
    matrix_float4x4 rotateY = matrix4x4_rotation(_rotation, 0.0, 1.0, 0.0);
    matrix_float4x4 viewMatrix = matrix_multiply(location ,matrix_multiply(rotateX, rotateY));
#else
    matrix_float4x4 location = matrix4x4_translation(0,0,-1000); // ??
    matrix_float4x4 rotateX = matrix4x4_rotation(0.5, 1.0, 0.0, 0.0); // (radians=-0.15,{1.0, 0.0, 0.0}) 左手坐标系 左手螺旋
    matrix_float4x4 rotateY = matrix4x4_rotation(_rotation, 0.0, 1.0, 0.0);
    matrix_float4x4 viewMatrix = matrix_multiply(rotateY, matrix_multiply(rotateX, location));
    viewMatrix = matrix_invert(viewMatrix);
#endif
    
    matrix_float4x4 tranlation = matrix4x4_translation(0,0,0); // 没有位移
    matrix_float4x4 scale = matrix4x4_scale(1.0, 1.0, 1.0);  // scale =1
    matrix_float4x4 rotate = matrix4x4_rotation(0.0, 0.0, 1.0, 0.0); // 没有旋转
    matrix_float4x4 modelMatrix = matrix_multiply(tranlation, matrix_multiply(rotate, scale)); // T <--- R <-- S
    
    uniform->modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);
    
    _rotation += 0.002f ;
    if (_rotation >=  3.14159*2 ) { // 避免过大 导致float溢出
        _rotation = 0 ;
    }
    
}

#pragma mark - MTKView delegate
-(void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    
    
}

-(void) drawInMTKView:(MTKView *)view
{
    
    [self _updateTransformMatrix];
    
    id<MTLCommandBuffer> commandBuffer = [_commandqueue commandBuffer];
    
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    // 不是 MTLCommandEncoder

    // MTLCommandEncoder
    // 不要自己实现这个协议
    // 相反，您可以调用 MTLCommandBuffer 对象上的方法来创建 "命令编码器 MTLCommandEncoder"
    // "命令编码器对象" 是 "轻量级对象", 当每次需要 "向GPU发送命令" 时都可以重新创建这些对象
    //
    // 有许多不同种类的命令编码器，每一种都提供一组"不同的可以编码到缓冲区中的"命令
    // 命令编码器 实现MTLCommandEncoder协议和特定于正在创建的编码器类型的附加协议
    // 表 1 列出了命令编码器及其实现的协议。
    // 协议                                   编码器
    // MTLRenderCommandEncoder                  Graphics rendering
    // MTLComputeCommandEncoder                 Computation
    // MTLBlitCommandEncoder                    Memory management 内存管理 ???
    // MTLParallelRenderCommandEncoder          Multiple graphics rendering tasks encoded in parallel. 多图像渲染任务 ???
    
    
    encoder.label = @"MyCommandEncoder" ;
    
    [encoder pushDebugGroup:@"MyMeshDbgGroup"];
    
    
    [encoder setRenderPipelineState:_renderPipelineState];
    [encoder setDepthStencilState:_depthStencilState];
 
    [encoder setCullMode:MTLCullModeBack];
    [encoder setFrontFacingWinding:MTLWindingClockwise];
    
    // 面剔除(Face culling)
    
    // 指定图元的正面绘制时顺时针方向处理 (MTLWindingClockwise) 还是逆时针方向处理 (MTLWindingCounterClockwise) ，
    // 默认值是 MTLWindingClockwise  !! 顺时针
    
    // OpenGL允许检查所有正面朝向（Front facing）观察者的面，并渲染它们，而丢弃所有背面朝向（Back facing）的面
    // 默认情况下，逆时针的顶点连接顺序被定义为三角形的正面
    
    
    [encoder setVertexBuffer:_transformUniformBuffer offset:0 atIndex:1];
    
    [self _drawMeshes:view withEncoder:encoder];
  
    
    [encoder popDebugGroup];
    [encoder endEncoding]; // MTLCommandEncoder 不是再推送命令？
    

    [commandBuffer presentDrawable:view.currentDrawable];
    
    [commandBuffer commit];
    
    
}
 
-(void) _drawMeshes:(MTKView*) view withEncoder:(id<MTLRenderCommandEncoder>) encoder
{
    for (__unsafe_unretained AAPLMesh* mesh in _meshes)
    {
        
        MTKMesh* mtkMesh = mesh.metalKitMesh;
        
        // MTKMesh vertexCount = 21527  bufferCount = 1
        //NSLog(@"MTKMesh vertexCount = %lu  bufferCount = %lu", mtkMesh.vertexCount, mtkMesh.vertexBuffers.count);
        
        for(int bufferIndex = 0 ; bufferIndex < mtkMesh.vertexBuffers.count ; bufferIndex++ )
        {
            MTKMeshBuffer* mtkBuffer =  mtkMesh.vertexBuffers[bufferIndex];
            
            if ((NSNull*)mtkBuffer != [NSNull null])
            {
                id<MTLBuffer> buffer = mtkBuffer.buffer;
                
                // 从MTKMesh拿到一个或者多个MTKMeshBuffer(每个对应一个MTLBuffer)   (MTLBuffer for vertex)
                // MTKMeshBuffer还包含描述这个MTKBuffer的offset和length
                
                [encoder setVertexBuffer:buffer offset:mtkBuffer.offset atIndex:bufferIndex];
                
                //NSLog(@"bufferIndex=%i, buffer = %p, offset=%lu, length=%lu",  bufferIndex, buffer, mtkBuffer.offset, mtkBuffer.length );
                // bufferIndex=0, buffer = 0x2819a5fc0, offset=0, length=947188
                
                // bufferCount = 1 只有一个顶点buffer 顶点的数目是 mtkMesh.vertexCount= 21527
                // 每个顶点属性 包含 position(float3)、uv(float2)、normal(half4)、tangent(half4)、bitangent(half4)  == 44个字节 
            }
            else
            {
                NSLog(@"MTKMeshBuffer is null at %i ", bufferIndex);
            }
        }
      
        
        __unsafe_unretained NSArray<AAPLSubmesh*>* submeshes = mesh.submeshes;
         
        for (__unsafe_unretained AAPLSubmesh* submesh in submeshes)
        {
            
            // AAPLSubmesh 只有两个属性
            // metalKitSubmmesh     对应这个submesh 子模型用到的索引缓存 索引数目 绘制图元方式 (MTLBuffer for index)
            // textures             对应这个submesh 子模型用到的纹理
            
            NSArray<id<MTLTexture>>* arrayOfTex = submesh.textures ;
            
            // NSLog(@"arrayOfTex count is %lu ", arrayOfTex.count); // 3 ????
            
            for (int textureIndex = 0 ; textureIndex< arrayOfTex.count ; textureIndex++ )
            {
                [encoder setFragmentTexture:arrayOfTex[textureIndex] atIndex:textureIndex];
            }
            
            
            MTKSubmesh* mtkSubMesh = submesh.metalKitSubmmesh ;
            
  
            [encoder drawIndexedPrimitives:mtkSubMesh.primitiveType
                                indexCount:mtkSubMesh.indexCount
                                 indexType:mtkSubMesh.indexType
                               indexBuffer:mtkSubMesh.indexBuffer.buffer
                         indexBufferOffset:mtkSubMesh.indexBuffer.offset ];
            
            //[mtkSubMesh dumpInfo];
            
            
        }
       
    }
 
}



-(void) _checkBOOL
{
    bool boolA = 1;
    bool boolB = 0;  // 0
    bool boolC = 256;
    bool boolD = -1;
    bool boolE = 13;


    BOOL BOOLA = 1;
    BOOL BOOLB = 0; // 0
    BOOL BOOLC = 256; // 1
    BOOL BOOLD = -1;
    BOOL BOOLE = 13;


    NSLog(@"boolA = %d",boolA);
    NSLog(@"boolB = %d",boolB);
    NSLog(@"boolC = %d",boolC);
    NSLog(@"boolD = %d",boolD);
    NSLog(@"boolE = %d",boolE);

    NSLog(@"===========");

    NSLog(@"BOOLA = %d",BOOLA);
    NSLog(@"BOOLB = %d",BOOLB);
    NSLog(@"BOOLC = %d",BOOLC);
    NSLog(@"BOOLD = %d",BOOLD);
    NSLog(@"BOOLE = %d",BOOLE);
    
    // 在32bit机器上
    // OC中用一个字节，即8位来表示BOOL值，也就是取一个数的低八位
    // 对于8960这个数，它明显是非零数字 但是！它的低八位都是零，所以它是NO
    BOOL a = 8960;
    NSLog(@" BOOL a = 8960 => %d sizeof(BOOL) = %lu", a, sizeof(BOOL));// 1,1
    bool b = 8960;
    NSLog(@" bool b = 8960 => %d sizeof(bool) = %lu", b, sizeof(bool));// 1,1
    
    /*
     ObjC的BOOL为什么要用YES、NO而不建议用true、false
     --- ObjC 是自己定义了 BOOL 的类型，然后定义了对应要使用的值 YES / NO
     --- 既然 ObjC 的 BOOL 使用的不是标准 C 的定义，那么以后这个定义可能还会修改 (比如从32位到64位 数据类型从signed char 到 bool)
     --- 在某些情况下，类型不匹配会导致 warning，而 YES / NO 是带类型的，可以保证类型正确
     --- 不要写 "== YES" 和 "!= YES"  (32 bit)
     --- 避免把超过 8-bit 的数据强转成 BOOL (32 bit)
     
     在 64-bit 设备上 BOOL 实际是 bool 类型
     在 32-bit 设备上 BOOL 的实际类型是 signed char
     
     
     #if __has_feature(objc_bool)
     #define YES __objc_yes
     #define NO  __objc_no
     #else
     #define YES ((BOOL)1)
     #define NO  ((BOOL)0)
     #endif
     
     __objc_yes 和 __objc_no 在 LLVM 的文档
     The compiler implicitly converts __objc_yes and __objc_no to (BOOL)1 and (BOOL)0.
     __objc_yes 和 __objc_no 其实就是 (BOOL)1 和 (BOOL)0
     这么写的原因就是为了消除 BOOL 和整型数的歧义而已
     
     C/C++的bool
        最早的标准 C 语言里是没有 bool 类型的
        C99 标准里，新增了 _Bool 保留字，并且在 stdbool.h 里定义了 true 和 false
        只是定义了它们的值，但是却没有保证它们的类型，就是说 true / false 其实可以应用在各种数据类型上
     
        #define bool _Bool
        #define true 1
        #define false 0
     
        C++ 是自带 bool 和 true、false 的
 
     */
    
    
    // 使用Product--Preform Action-- 可以对源文件进行Compile/Analayze/Preprocess/Assemble/
    BOOL flag = TRUE;
    flag = true;
    flag = YES;
    
    /* 展开宏定义
     BOOL flag = 1;
     flag = 1;
     flag = __objc_yes;
     */
    
}


@end
