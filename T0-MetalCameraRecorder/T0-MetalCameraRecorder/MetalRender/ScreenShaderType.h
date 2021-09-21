//
//  ScreenShaderType.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/24.
//

#ifndef ScreenShaderType_h
#define ScreenShaderType_h


#ifdef __METAL_VERSION__

#define NSInteger metal::int32_t
#define NS_ENUM(_type, _name) enum _name:_type _name ; enum _name:_type

#define ATTRIBUTE(x) [[attribute(x)]]

#else

#import <Foundation/Foundation.h>

#define ATTRIBUTE(x)

#endif

#include <simd/simd.h>

typedef struct
{
    vector_float4 position  ATTRIBUTE(0);
    vector_float2 uv        ATTRIBUTE(1);
    
} ScreenVertex ;


#endif /* ScreenShaderType_h */
