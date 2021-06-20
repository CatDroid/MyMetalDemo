//
//  ShaderType.h
//  T2-TextureMapping
//
//  Created by hehanlong on 2021/6/17.
//

#ifndef ShaderType_h
#define ShaderType_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name:_type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif


#include <simd/simd.h>

typedef struct
{
    vector_float2 pos ;
    vector_float2 uv ;
} MyVertex;


#endif /* ShaderType_h */
