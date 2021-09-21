//
//  CameraShaderType.h
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/28.
//

#ifndef CameraShaderType_h
#define CameraShaderType_h


#ifdef __METAL_VERSION__

#define NSInteger metal::int32_t
#define NS_ENUM(_type,_name) enum _name:_type _name; enum _name:_type

#else

#import <Foundation/Foundation.h>

#endif

#include <simd/simd.h>

typedef struct
{
    vector_float2 pos ;
    vector_float2 uv ;
} CameraVertex ;


#endif /* CameraShaderType_h */
