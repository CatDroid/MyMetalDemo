//
//  ShaderTypes.h
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

//Part 1 Compiler flags
#ifdef __METAL_VERSION__  // 决定那种语言在编译
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif


#include <simd/simd.h>

////Part 2 buffer index
//typedef NS_ENUM(NSInteger, BufferIndex)
//{
//    BufferIndexMeshPositions = 0,
//    BufferIndexMeshGenerics  = 1,
//    BufferIndexUniforms      = 2
//};
//
////Part 3 vertex attribute and position
//typedef NS_ENUM(NSInteger, VertexAttribute)
//{
//    VertexAttributePosition  = 0,
//    VertexAttributeTexcoord  = 1,
//};
//
////Part 4 texture index color
//typedef NS_ENUM(NSInteger, TextureIndex)
//{
//    TextureIndexColor    = 0,
//};
//
////Part 5 uniforms
//typedef struct
//{
//    matrix_float4x4 projectionMatrix;
//    matrix_float4x4 modelViewMatrix;
//} Uniforms;

typedef struct
{
    vector_float2 pos ;
    // normal法线
    // uv纹理坐标
    // 切线
} Vertex ;


#endif /* ShaderTypes_h */
