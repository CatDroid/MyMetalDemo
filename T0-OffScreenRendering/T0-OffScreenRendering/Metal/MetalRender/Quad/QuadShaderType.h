//
//  QuadShaderType.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/26.
//

#ifndef QuadShaderType_h
#define QuadShaderType_h


#ifdef __METAL_VERSION__

#define NS_ENUM(_type,_name) enum _name:_type _name; enum _name:_type
#define NSInteger metal::int32_t

#else

#import <Foundation/Foundation.h>

#endif

#import <simd/simd.h>

typedef NS_ENUM(NSInteger, VertexInputBufferIndex)
{
    kQuadVertexColorBufferIndex,
    kViewPortScalerUniformBufferIndex
} ;


typedef struct
{
    vector_float2 pos ;
    vector_float3 color ;
    
} QuadVertexColor ;

typedef struct
{
    vector_float2 viewport ; // 宽归一化
    float scaler ;
    
} ViewPortScaler ;


#endif /* QuadShaderType_h */
