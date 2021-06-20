//
//  MyShader.metal
//  T2-TextureMapping
//
//  Created by hehanlong on 2021/6/17.
//

#include <metal_stdlib>

using namespace metal;

#include <simd/simd.h>

#include "ShaderType.h"

typedef struct {
    //vector_float4 pos [[position]]; // vector_float4 也是正常的
    //vector_float2 texCoord ;
    float4 pos [[position]];
    float2 texCoord;
} VertexOut ;

vertex VertexOut MyVertexShader(
                                uint vid [[vertex_id]],
                                constant MyVertex *vertexArr [[buffer(0)]] // 第0个vertextbuffer
                                )
{
    VertexOut out ;
    
    float4 postion = vector_float4(vertexArr[vid].pos , 0.0, 1.0); // vector_float4 复制给 float4
    out.pos = postion ;
    out.texCoord = vertexArr[vid].uv ;
    
    return out ;
}

// float4 half4
fragment half4 MyFragmentShader(
                                 VertexOut in [[stage_in]], // stage_in 上个阶段传入
                                 texture2d<half> mtlTexture0 [[texture(0)]] // 第0个纹理
                                 )
{

    // 光栅化阶段光栅器会在顶点之间进行一系列的插值计算，包括纹理(??坐标)的插值计算
    
    // 采样器是一个配置纹理采样 的对象
    // 采样器是 控制纹理采样期间 一些插值细节操作 的对象
    // 滤波模式     Metal中提供了两种纹理过滤的模式：linear 和 nearest
    // 寻址模式有：  repeat、mirrored_repeat、clamp_to_edge、clamp_to_zero、clamp_to_border
    // mipmaping   预处理过滤的多个规模精度不同的子贴图 每张子贴图是之前贴图精度的一半 
    constexpr sampler textureSampler {mag_filter::linear, min_filter::linear};
    
    const half4 color = mtlTexture0.sample(textureSampler, in.texCoord);
    
    return color;
    
}
