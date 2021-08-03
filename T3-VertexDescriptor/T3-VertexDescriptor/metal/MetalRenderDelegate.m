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
    id<MTLBuffer>           _uniformBuffer ;
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
    
    // vertexAttributes 只有在顶点着色器使用 [[stage_in]]  attribute[0]  attribute[1] 这样标记 才会有 vertexAttributes
    // 如果使用argument table的方式， vertexfunction.vertexAttributes 就是空数组
    NSUInteger count = myVertexFunction.vertexAttributes.count ;
    NSLog(@"vertexAttributes.count = %lu ",  count);
   
    for (int i = 0 ; i < count; i++ )
    {
        NSLog(@"myVertexFunction.vertexAttributes %@", myVertexFunction.vertexAttributes[i].name); // 是变量的名字
    }
    

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
    NSLog(@"(uint8_t)&(((MyVertex*)0)->tangle) = %d", (uint8_t)&(((MyVertex*)0)->tangle));
    NSLog(@"sizeof(MyVertex) = %lu", sizeof(MyVertex));
    
    // pos
    vertexDesc.attributes[0].format = MTLVertexFormatFloat2 ;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0 ;
    // uv
    vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[1].offset = (uint8_t)&(((MyVertex*)0)->uv); // 8;
    vertexDesc.attributes[1].bufferIndex = 0 ;
    // tangle
    vertexDesc.attributes[2].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[2].offset = (uint8_t)&(((MyVertex*)0)->tangle); // 16;
    vertexDesc.attributes[2].bufferIndex = 0 ;
    
    // layout
    // 在渲染片元的时候 告诉vs(顶点着色器)如何提取数据 (!!片元着色器是没有的!!)
    // 这样设置完成之后，setVertexBuffer 给到 bufferIndex=0  的 buffer 就要满足这个布局
    vertexDesc.layouts[0].stride = sizeof(MyVertex); // 32
    vertexDesc.layouts[0].stepRate = 1;
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    // 由于是连续定义在同一个buffer中所以这里只配置了一个layouts[0]
    // stride属性表示每次去取一个顶点数据的数据跨度，这里每个顶点数据占16字节，所以stride设置为16
    
    /*
     MTLVertexDescriptor 应该按照 MTLBuffer.contents 中数据的格式定义(cpu端)
     比如 cpu 端数据结构是
     
     typedef struct
     {
        vector_float2 pos ; // 在 MTLBuffer cpu端数据   vertexDesc.attributes[0].offset = 0
        vector_float2 uv ;  //                        vertexDesc.attributes[1].offset = 8
        float tangle[3];    //                        vertexDesc.attributes[2].offset = 16
     }
     MyVertex;               //  每个顶点 按照  vertexDesc.layouts[0].stride = sizeof(MyVertex); = 16 跳跃 ，
                             //                 把MTLBuffer中offset=0的 赋给[attribute(0)]
                             //                 把MTLBuffer中offset=8的 赋给[attribute(1)]
                             //                 把MTLBuffer中offset=16的 赋给[attribute(2)]
     
     msl端数据结构是
     
     typedef struct {
        vector_float2 pos     [[attribute(0)]];
        vector_float2 uv      [[attribute(1)]];
        vector_float3 tangle  [[attribute(2)]]; // 由于 MTLVertexDescriptor 没有提及这个 所以 attribute(2) attribute(3) 都没有赋值
        vector_float3 normal  [[attribute(3)]];
         
     }
     VertexAttribute;
     
     
     
     */
    
    
    // Instance rendering(实例渲染)和Tessellating(曲面细分)等技术
    
    //AOS（Array Of Structure） 同一个顶点的所有属性在同一个buffer依次排列存储，
    //                          然后继续排列存储下一个顶点数据，
    //                          如此类推，这样的好处是符合面向对象的布局思路
    
    // SOA（Structure Of Array）是AOS的一个变换，不同于之前一些属性结构的集合组成的结构数组，
    //                          现在我们有一个结构来包含多个数组，每个数组只包含一个属性，
    //                          这样GPU可以使用同一个index索引去读取每个数组中的属性，
    //                          GPU读取比较整齐，这种方法对于某一些3D文件格式尤其合适
    
 
     
//     // 改成 position数据放到第一个buffer，uv放到第二个buffer上
//
//    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
//
//     // Positions.
//     vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
//     vertexDescriptor.attributes[0].offset = 0;
//     vertexDescriptor.attributes[0].bufferIndex = 0;
//
//     // Texture coordinates.
//     vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
//     vertexDescriptor.attributes[1].offset = 0;
//     vertexDescriptor.attributes[1].bufferIndex = 1; // ??? 应该是1  ??? 两个buffer shader怎么改？？
//
//     // Position Buffer Layout
//     vertexDescriptor.layouts[0].stride = 8;
//     vertexDescriptor.layouts[0].stepRate = 1;
//     vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
//
//     vertexDescriptor.layouts[1].stride = 8;  // layouts[1] 对应的是 bufefrIndex=1 第1个buffer??
//     vertexDescriptor.layouts[1].stepRate = 1;
//     vertexDescriptor.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
//
     
    renderPipelineDesc.vertexDescriptor = vertexDesc ; // 一个RenderPileLineState 只能对应一个vertexDescriptor
    
    NSError* error ;
    MTLRenderPipelineReflection* reflection = NULL; // 获取反射信息

    // option = MTLPipelineOptionBufferTypeInfo | MTLPipelineOptionArgumentInfo;
    // options: MTLPipelineOptionBufferTypeInfo 获取 [[buffer(n)]] 'buffer' argument table 信息
    
    _renderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDesc options:MTLPipelineOptionBufferTypeInfo reflection:&reflection error:&error];
    if (_renderPipelineState == nil)
    {
        NSLog(@"newRenderPipelineStateWithDescriptor fail with %@", error);
    }
    
    
    [self processArgument:reflection];
 
    
    _uniformBuffer = [device newBufferWithLength:sizeof(MyUniform) options:MTLResourceStorageModeShared];
    
    MyUniform* uniform = (MyUniform*)_uniformBuffer.contents ;
    
    for (int ii = 0 ; ii < sizeof(uniform->myArray)/sizeof(uniform->myArray[0]); ii++)
    {
        uniform->myArray[ii] = ii ;
    }
    
    uniform->addMore = (vector_float4){1.0, 2.0, 3.0, 4.0};

    MTLDepthStencilDescriptor* depthStencilDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDesc.depthWriteEnabled = YES ;
    depthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
    _depthStencilState = [device newDepthStencilStateWithDescriptor:depthStencilDesc];
    
    
    _commandQueue = [device newCommandQueue];
}

-(void) processArgument:(MTLRenderPipelineReflection*) reflection
{
    
    NSLog(@"sizeof(MyUniform) = %lu ", sizeof(MyUniform) ); // 416   cpu端也是16个字节对齐
    
    // https://developer.apple.com/forums/thread/64057
    // typedef __attribute__((__ext_vector_type__(2),__aligned__(4))) float simd_packed_float2; // 4字节对齐，而不是8字节对齐(vector_float2)
    // typedef simd_packed_float2 packed_float2; // packed_float2 已经不用 改成 simd_packed_float2
    NSLog(@"sizeof(simd_packed_float2) = %lu ", sizeof(packed_float2)); // = 8 simd_packed_float2 == packed_float2  =
    NSLog(@"sizeof(vector_float2) = %lu ", sizeof(simd_float2)); // = 8 vector_float2 == simd_float2
    
    typedef struct
    {
        float first ;
        packed_float2 offset ;
    }
    MyAlignPacked;
    
    typedef struct
    {
        float first ;
        simd_float2 offset ;
    }
    MyAlignSIMD;
    
    
    NSLog(@"对齐 MyAlignPacked %lu offset %lu offset %lu", sizeof(MyAlignPacked),
          (unsigned long)&(((MyAlignPacked*)0)->first),
          (unsigned long)&(((MyAlignPacked*)0)->offset) // Align 12 offset 0 offset 4
          );
    
    NSLog(@"对齐 MyAlignSIMD %lu offset %lu offset %lu", sizeof(MyAlignSIMD),
          (unsigned long)&(((MyAlignSIMD*)0)->first),
          (unsigned long)&(((MyAlignSIMD*)0)->offset)  //  SIMD 16 offset 0 offset 8
          );
    
    
    typedef struct
    {
        float one ;         // offset 0         size = 1*4 = 4
        simd_float2 two ;   // offset 2*4 = 8   size = 2*4 = 8
        simd_float4 three ; // offset 16        size = 16
        simd_float2 four ;  // offset 32        size = 8
        simd_float2 five[5];// offset 40        size = 2 * 4 * 5 = 40  total = 80 
    }
    MyAlignMultiSIMD;
    
    NSLog(@"对齐 MyAlignMultiSIMD %lu one %lu two %lu three %lu four %lu five %lu",
          sizeof(MyAlignMultiSIMD),
          (unsigned long)&(((MyAlignMultiSIMD*)0)->one),
          (unsigned long)&(((MyAlignMultiSIMD*)0)->two),
          (unsigned long)&(((MyAlignMultiSIMD*)0)->three),
          (unsigned long)&(((MyAlignMultiSIMD*)0)->four),
          (unsigned long)&(((MyAlignMultiSIMD*)0)->five)
          );
    
    
    typedef struct
    {
        float buffer[98];
        float size ;
    }
    MyAlignmentStructure1 ;
    
    NSLog(@"对齐 MyAlignmentStructure %lu offset %lu offset %lu", sizeof(MyAlignmentStructure1), // 98 * 4 + 1 * 4  = 396
          (unsigned long)&(((MyAlignmentStructure1*)0)->buffer), // 0
          (unsigned long)&(((MyAlignmentStructure1*)0)->size)    // 392
          ); // 这个按照float 1个字节对齐
    
    
    typedef struct
    {
        float buffer[98];
        vector_float3 size ; // 结构体中最大成员长度作为对齐字节数目
    }
    MyAlignmentStructure2 ; // 这个按照16个字节对齐
    
    NSLog(@"对齐 MyAlignmentStructure2 %lu offset %lu offset %lu", sizeof(MyAlignmentStructure2), // 98 * 4 + 1 * 4  = 416
          (unsigned long)&(((MyAlignmentStructure2*)0)->buffer), // 0
          (unsigned long)&(((MyAlignmentStructure2*)0)->size)    // 400
          );
    
    // typedef simd_float3 vector_float3;
    // typedef float __attribute__((ext_vector_type(3))) simd_float3;   //  实际是这个类型 float __attribute__((ext_vector_type(3)))
    
    // ??  https://stackoverflow.com/questions/38750994/what-is-ext-vector-type-and-simd
    // ??  it's a way to let the compiler know you only care about the value of the first 3 elements of a 4 element SIMD register.
    
    NSLog(@"sizeof(simd_char1) = %lu ", sizeof(simd_char1));   // 1
    NSLog(@"sizeof(simd_float1) = %lu ", sizeof(simd_float1)); // 4
  
    // NSLog("sizeof(vector_float1 = %lu ", sizeof(vector_float1)); // 没有 vector_float1 但是有 simd_float1
    NSLog(@"sizeof(vector_float2 = %lu ", sizeof(vector_float2)); // 8   这个就不是16字节对齐的了
    NSLog(@"sizeof(vector_float3 = %lu ", sizeof(vector_float3)); // 16  但是这个是16字节对齐
    NSLog(@"sizeof(vector_float4 = %lu ", sizeof(vector_float4)); // 16
    
    NSLog(@"sizeof(matrix_float3x3) = %lu ", sizeof(matrix_float3x3)); // 48
    NSLog(@"sizeof(matrix_float4x4) = %lu ", sizeof(matrix_float4x4)); // 64 typedef simd_float4x4 matrix_float4x4;
   
    NSLog(@"matrix_float3x3 %lu",   (unsigned long)&((matrix_float3x3*)0)->columns[0] ); // 0  列主
    NSLog(@"matrix_float3x3 %lu",   (unsigned long)&((matrix_float3x3*)0)->columns[1] ); // 16 16个字节对齐  因为 simd_float3 是16字节对齐
    NSLog(@"matrix_float3x3 %lu",   (unsigned long)&((matrix_float3x3*)0)->columns[2] ); // 32
    
    
    // typedef struct
    // {
    //    simd_float3 columns[3];   // 3*3的矩阵 其实是个结构体 有一个元素 columns  是个  simd_float3[3] 数组
    // }
    // simd_float3x3;
    
    /*! @abstract A vector of three 32-bit floating-point numbers.            三个32位浮点数向量
     *  @description In C++ and Metal, this type is also available as            在C++和metal 这类型 等价于  simd::float3
     *  simd::float3. Note that vectors of this type are padded to have the same  这个类型的大小和对齐 跟  simd_float4 一样
     *  size and alignment as simd_float4.                                        */
    
    // typedef   __attribute__((__ext_vector_type__(3))) float    simd_float3;

    /*! @abstract A vector of two 32-bit floating-point numbers.                两个32位浮点数向量
     *  @description In C++ and Metal, this type is also available as               在C++和metal 这类型 等价于  simd::float2
     *  simd::float2. The alignment of this type is greater than the alignment   这个类型的对齐大于float  --> 实际是 4*4 = 16个字节对齐
     *  of float; if you need to operate on data buffers that may not be
     *  suitably aligned, you should access them using simd_packed_float2  如果需要对可能未适当对齐的数据缓冲区进行操作 ??? ，则应改用 simd_packed_float2 访问它们
     *  instead.                                                                  */
    // typedef   __attribute__((__ext_vector_type__(2))) float      simd_float2;
    
    
    // 总结 在simd的类型中 float3 或者 float3x3 的对齐是跟float4一样的  并且float3x3中每个colomn也是16字节((3+1)*4)对齐的
    
    
    // Argument Table的 主要四种类型
    //
    // MTLArgumentTypeBuffer = 0,               // buffer 数组      -------- [[buffer(n)]]
    // MTLArgumentTypeThreadgroupMemory= 1,     // thread group 数组
    // MTLArgumentTypeTexture = 2,              // texture 数组
    // MTLArgumentTypeSampler = 3,              // sampler 数组
     
    // reflection.vertexArguments
    // reflection.fragmentArguments
    
    for (MTLArgument * arg in reflection.vertexArguments)
    {
        
        if ( arg.active )
        {
            if (arg.type == MTLArgumentTypeBuffer) // 这个是 Argument Table 类型, 见上面的 Argument Table 主要四种类型
            {
                if (arg.bufferStructType != nil &&  arg.bufferDataType == MTLDataTypeStruct)
                {
                    // buffer中数据类型 是struct array 或者 float4 ...
                    // 可通过 arg.bufferPointerType != nil 判断是否指针
                    //
                    // 在buffer数据类型是 结构体 的情形下
                    // 如果是 形参类型是指针    arg.bufferPointerType 不为空
                    // 否则
                    // 应该是 形参类型是结构体  arg.bufferStructType 不为空
                    
                    
                    NSLog(@"vertex Argument %@ (%lu) is structure ", arg.name, arg.index);
                    // argument table index 0 , 1 ...
 
                    NSLog(@"vertex Argument %@ arg.bufferDataSize  = %lu", arg.name, arg.bufferDataSize);
                    // arg.bufferDataSize  = 416   400+4*4 = 400 + 16 = 416
                    NSLog(@"vertex Argument %@ arg.bufferAlignment = %lu", arg.name, arg.bufferAlignment);
                    // arg.bufferAlignment = 16    按照结构体成员中最大的对齐数目
                    
                    // !! MTLBuffer 存放的uniform数据, 应该以 bufferAlignment 这个为对齐地址偏移的 !!
                    // 不过这里一个MTLBuffer存放一个uniform所以没有问题, bgfx使用同一个MTLBuffer存放所有render item的uniform，所以需要使用这个偏移
                    
                    // min alignment of starting offset in the buffer 在buffer中开始偏移的最小对齐
                    // 缓冲区数据 在内存中 所需的字节对齐方式。
                    
                    for (MTLStructMember* structMember in arg.bufferStructType.members ) // MTLStructMember 如果是结构体 这个是结构体的成员
                    {
                        // MTLStructMember 无法判断是否active 只有 MTLArgument 
                        
                        // MTLDataType
                        //      MTLDataTypeStruct = 1,
                        //      MTLDataTypeArray  = 2,
                        //      MTLDataTypeFloat  = 3,
                        //      MTLDataTypeFloat4 = 6,
                        
                        NSLog(@"struct element : %@ argumentIndex : %lu type : %lu offset : %lu", structMember.name, structMember.argumentIndex, structMember.dataType, structMember.offset);
                        
                        
                        
                        MTLDataType dataType = structMember.dataType;
                        
                        // 对于，结构体成员，成员类型，
                        // 如果是指针类型，那么会通过 MTLStructMember.pointerType 继续描述
                        // 如果不是指针类型，那么
                        //      结构体类型      MTLStructMember.structType
                        //      数组类型        MTLStructMember.arrayType
                        //
   
                        if (dataType == MTLDataTypeArray) // 数组类型
                        {
                            NSLog(@"struct element : %@ is array, element type : %lu, array size : %lu, ",
                                  structMember.name,
                                  structMember.arrayType.elementType,
                                  structMember.arrayType.arrayLength
                                  );
                            //  floatArray is array, element type is 3, array size is 100, offset = 0
                        }
                         
                        // struct element : myArray type : 2 offset : 0
                        // struct element : myArray is array, element type : 3, array size : 98,
                        // struct element : addMore type : 6 offset : 400
                        
                    }
                        
                }
                else
                {
                    
                    NSLog(@"vertex Argument %@ (%lu) is not 'direct' structure or not structure ", arg.name, arg.index); // 不是结构体或者不是‘直接’结构体
                    NSLog(@"vertex Argument %@ arg.bufferDataSize  = %lu", arg.name, arg.bufferDataSize);
                    NSLog(@"vertex Argument %@ arg.bufferAlignment = %lu", arg.name, arg.bufferAlignment);
                    
                    
                    // 第一个参数   VertexAttribute in [[stage_in]]  实际来自于 buffer argument table
                    
                    // 其实是 constant VertexAttribute* vertexBuffer.0  [[buffer(0)]]; // 是个指针类型
                    
                    if (arg.bufferDataType == MTLDataTypeStruct) // && arg.bufferStructType == nil   走到这里代表buffer是结构体类型 但是变量是指针
                    {
                       
                        
                        NSLog(@"vertex Argument %@ (%lu) is structure , but %s pointer ", arg.name, arg.index, arg.bufferPointerType!=nil ? "is" : "not");
                        
                        if (arg.bufferPointerType != nil)
                        {
                            NSLog(@"vertex Argument %@ (%lu) is pointer with type %lu alignment %lu, dataSize %lu",
                                  arg.name,
                                  arg.index,
                                  arg.bufferPointerType.elementType,
                                  arg.bufferPointerType.alignment,
                                  arg.bufferPointerType.dataSize
                                  );
                            // vertex Argument vertexBuffer.0 (0) is pointer with type 1 alignment 4, dataSize 16  这个就是MyVertex结构体的大小和对齐方式
                            
                            if (arg.bufferPointerType.elementType == MTLDataTypeStruct) // buffer是个 结构体类型数组
                            {

                                NSLog(@"vertex Argument %@ point to structure, elementArrayType %@ elementStructType %@ elementIsArgumentBuffer %s",
                                      arg.name,
                                      arg.bufferPointerType.elementArrayType,
                                      arg.bufferPointerType.elementStructType,
                                      arg.bufferPointerType.elementIsArgumentBuffer ? "YES":"NO");
                                
                                // vertex Argument vertexBuffer.0 point to structure, elementArrayType (null) elementStructType (null) elementIsArgumentBuffer NO
                                
                                // 如果是个pointer结构体类型, 不能通过 bufferPointerType.elementStructType 获取结构体元素信息
                                
                                MTLStructType* pointerToStructe = arg.bufferPointerType.elementStructType;
                                for (MTLStructMember* member in pointerToStructe.members)
                                {
                                    NSLog(@"vertex Argument %@ point to structure, structure element name %@ offset %lu argumentIndex %lu dataType %lu",
                                          arg.name,
                                          member.name,
                                          member.offset,
                                          member.argumentIndex,
                                          member.dataType);
                                }
                                
                            }
                            else
                            {
                                NSLog(@"vertex Argument %@ (%lu) point to dataType %lu", arg.name, arg.index,  arg.bufferPointerType.elementType );
                            }
                        }
                        else
                        {
                            NSAssert(false, @"Structure type but not point and struct");
                        }
                        
                        
                    }
                    else
                    {
                        NSLog(@"vertex Argument %@ (%lu) not structure , but is %lu ", arg.name, arg.index, arg.bufferDataType);
                    }
                   
                }
            }
            else
            {
                NSLog(@"vertex Argument %@ not buffer  ", arg.name); // 如果参数没有使用过的话，active为false
            }
        }
        else
        {
            NSLog(@"vertex Argument %@ not active  ", arg.name);
        }
    }
    
   
    for (MTLArgument* fragArg in reflection.fragmentArguments)
    {
        if (fragArg.type == MTLArgumentTypeBuffer )
        {
            // 只有 buffer argument table 才能访问 bufferDataType bufferAlignment bufferDataSize等属性
            // 'Querying buffer data type on an argument that is not a buffer'
            
            NSLog(@"fragArg %@(%lu) is [[buffer(0)]] argument , active:%s type:%lu, bufferDataType %lu, bufferAlignment %lu bufferDataSize %lu",
                  fragArg.name,
                  fragArg.index,
                  fragArg.active ? "YES":"NO" ,
                  fragArg.type,
                  fragArg.bufferDataType, // 'Querying buffer data type on an argument that is not a buffer'
                  fragArg.bufferAlignment,
                  fragArg.bufferDataSize
                  );
            
        }
        else if (fragArg.type == MTLArgumentTypeTexture)
        {
            NSLog(@"fragArg %@(%lu) is [[texture(n)]] argument , active:%s type:%lu, textureType %lu, textureDataType %lu isDepthTexture %s arrayLength %lu",
                  fragArg.name,
                  fragArg.index,
                  fragArg.active ? "YES":"NO" ,
                  fragArg.type,
                  fragArg.textureType,          // texture1D, texture2D...
                  fragArg.textureDataType,      // half, float, int, or uint.
                  fragArg.isDepthTexture ? "YES":"NO",
                  fragArg.arrayLength
                  );
            
            // Fragment Shader 第0个参数是[[stage_in]] 顶点着色器的输出 但是 不计入 MTLArugment.index
            
            // fragArg texture(0) is [[texture(n)]] argument , active:YES type:2, textureType 2, textureDataType 16 isDepthTexture NO arrayLength 1
            
        }
        else if (fragArg.type == MTLArgumentTypeSampler)
        {
            
            NSLog(@"fragArg %@(%lu) is [[sampler(n)]] argument , active:%s type:%lu",
                  fragArg.name,
                  fragArg.index,
                  fragArg.active ? "YES":"NO" ,
                  fragArg.type);
        }
        
 
        
    }
   
}

-(void) setupAssets:(id<MTLDevice>) device
{
    static MyVertex vertex[] = {
        { {0.0,  1.0},  {0.5, 0} , 1, 2, 3 },
        { {1.0, -1.0},  {1,   1} , 1, 2, 3 },
        { {-1.0, -1.0}, {0,   1} , 1, 2, 3 },
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
    [encoder setVertexBuffer:_uniformBuffer offset:0 atIndex:1];
    // [encoder setVertexTexture:(nullable id<MTLTexture>) atIndex:] // 顶点着色器也可以有纹理
    [encoder setFragmentTexture:_texture atIndex:0];
    
    MTLViewport port = { 100, 200, 300, 400, 0.0, 1.0}; // 0,0 是左上角 
    [encoder setViewport:port]; // view port 默认 zNear是0 zFar是1.0
    
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
