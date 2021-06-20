//
//  ShaderType.h
//  T4-AAPLMesh
//
//  Created by hehanlong on 2021/6/18.
//

#ifndef ShaderType_h
#define ShaderType_h

#ifdef __METAL_VERSION__

#typdef NSInteger metal::int32_t
#define NS_ENUM(_type,_name) enum _name:_type _name; enum _name:_type

/*
    NS_ENUM 是oc中的宏 判断编译器是否支持新式枚举 oc中几乎不使用enum 都是使用NS_ENUM和NS_OPTION
    typedef NS_ENUM(NSInteger, FlyState)
    {
        FlyStateOne,
        FlyStateTwo,
        FlyStateThree,
    };

    新式枚举展开成如下
    typedef enum FlyState:NSInteger FlyState;
    enum FlyState:NSInteger
    {
        FlyStateOne,
        FlyStateTwo,
        FlyStateThree
    };

    使用:
    FlyState state = FlyStateOne;

 */

#else
#import <Foundation/Foundation.h>
#endif

#import <simd/simd.h>

// 模型中每个顶点包含position(float3)、uv(float2)、normal(half4)、tangent(half4)、bitangent(half4)五个属性，
// 数据长度为:3x4 + 2x4 + 4x2 + 4x2 + 4x2 = 44
typedef struct // 这个结构体带代表模型中的 不用在shader中 只是用于 VertexDescriptor 
{
    vector_float3 pos ; // 3*4 = 12  typedef float __attribute__((ext_vector_type(3))) simd_float3;
    vector_float2 uv ;  // 结构体要对齐 所以这里偏移是 16
    vector_short4 normal; // no half
    vector_short4 tangent;
    vector_short4 bitangent;
    
} MyVertex ; // __attribute__ ((aligned (1)))  这个没有作用 uv偏移还是16


#endif /* ShaderType_h */
