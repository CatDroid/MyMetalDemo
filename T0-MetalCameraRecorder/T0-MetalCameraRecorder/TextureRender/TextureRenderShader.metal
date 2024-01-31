//
//  TextureRenderShader.metal
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2024/1/31.
//

#include <metal_stdlib>
using namespace metal;

// Include header shared between this Metal shader code and the C code executing Metal API commands.
#include "TextureRenderShaderType.h"


typedef struct
{
    float4 pos [[position]];
    float2 texCoord;
} VertexOut ;


vertex VertexOut TextureRenderVertex(
                                uint vid [[vertex_id]],
                                constant MyVertex *vertexArr [[buffer(0)]]  // 第0个Buffer
                                )
{
    VertexOut out ;
    
    float4 postion = vector_float4(vertexArr[vid].pos , 0.0, 1.0);
    out.pos = postion ;
    out.texCoord = vertexArr[vid].uv ;
    
    return out ;
}


fragment half4 TextureRenderFragment(
                                 VertexOut in [[stage_in]], // stage_in 上个阶段传入
                                 texture2d<half> mtlTexture0 [[texture(0)]] // 第0个纹理
                                 )
{
    constexpr sampler textureSampler {mag_filter::linear, min_filter::linear}; // shader中定义sampler 而不是使用C代码指定的
    
    const half4 color = mtlTexture0.sample(textureSampler, in.texCoord);
    
    return color;
    
}
