//
//  ShaderType.h
//  T5-UniformBuffer
//
//  Created by hehanlong on 2021/6/20.
//

#ifndef ShaderType_h
#define ShaderType_h


#import <simd/simd.h>

#ifdef __METAL_VERSION__
#define NSInteger metal::int32_t;
#define NS_ENUM(_type, _name) enum _name: _type _name; enum _name:_type
#else
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
// 不能import到msl中 会导致xcode编译错误提示:
// Pointer type must have explicit address space qualifier
// Architecture not supported


#endif

#ifdef __METAL_VERSION__
#define ATTRIBUTE(index)  [[attribute(index)]]
#else
#define ATTRIBUTE(index)
#endif

typedef struct {
    vector_float3 pos ATTRIBUTE(0);
    vector_float2 uv  ATTRIBUTE(1);
} MyVertex ;



typedef struct {
    matrix_float4x4 modelViewMatrix ;
    matrix_float4x4 projectionMatrix;
} MyUniform;


#endif /* ShaderType_h */
