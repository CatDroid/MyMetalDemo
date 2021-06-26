//
//  ShaderType.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#ifndef ShaderType_h
#define ShaderType_h

#ifdef __METAL_VERSION__

#define NSInteger metal::int32_t
#define NS_ENUM(_type, _name)  enum _name:_type _name;  enum _name:_type

#else

#import <Foundation/Foundation.h>

#endif

#include <simd/simd.h>

typedef struct
{
    vector_float2 pos ;
    // vector_float3 pos ;
    // vector_float2 uv ;
    // vector_half4 normal;
    // vector_half4 tangle;
    // vector_half4 bitangle;
    
} Vertex ;


#endif /* ShaderType_h */
