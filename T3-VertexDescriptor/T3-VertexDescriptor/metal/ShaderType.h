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
    vector_float2 uv ;
} MyVertex;



#endif /* ShaderType_h */
