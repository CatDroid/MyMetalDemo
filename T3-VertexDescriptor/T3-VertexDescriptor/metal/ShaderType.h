//
//  ShaderType.h
//  T3-VertexDescriptor
//
//  Created by hehanlong on 2021/6/17.
//

#ifndef ShaderType_h
#define ShaderType_h


#ifdef __METAL_VERSION__

#define NS_ENUM(_name, _type)  enum _name: _type _name;    enum _name:_type 

#define NSInteger metal::int32_t

#else

#import <Foundation/Foundation.h>

#endif


#import <simd/simd.h>



typedef struct
{
    vector_float2 pos ;
    vector_float2 uv ;  // 按照 2*4 = 8 字节对齐
    float tangle[3];    // offset = 16   !!!顶点属性 对应的MTLBuffer可以通过VertexDescriptor来描述 所以buffer不用对齐 但是uniform变量,就没有VertexDescriptor 所以要对齐!!!
    
} MyVertex;  // sizeof(MyVertex) = 32 

typedef struct
{
    float myArray[98];
    vector_float4 addMore;
} MyUniform;

#endif /* ShaderType_h */
