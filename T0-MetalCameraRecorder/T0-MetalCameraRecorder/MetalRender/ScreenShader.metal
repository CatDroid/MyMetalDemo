//
//  ScreenShader.metal
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/24.
//

#include <metal_stdlib>
using namespace metal;

#include <simd/simd.h>

#include "ScreenShaderType.h"

typedef struct
{
    float4 pos [[position]];
    float2 texCoord ;
    
} VertexOut ;


vertex VertexOut ScreenVertexShader(
                                    constant ScreenVertex* vertexes [[buffer(0)]],
                                    //constant metal::int32_t* indices [[buffer(1)]],
                                    metal::uint32_t vid [[vertex_id]],
                                    metal::uint32_t iid [[instance_id]] // 目前没有成功使用这种方式。
                                    //ScreenVertex vertexAttr [[stage_in]]
                                    )
{
    VertexOut out;
    
    //metal::uint32_t which = iid * 3 + vid; //一个instance 3个顶点 三角形
    
    //metal::uint32_t vertexBufferIndox = indices[which];
    
    //ScreenVertex attr = vertexes[vertexBufferIndox];
    
    ScreenVertex attr = vertexes[vid];
    
    out.pos = attr.position ;
    out.texCoord = attr.uv ;
    
    
    return out ;
}
 
fragment float4 ScreenFragmentShader(
                                     VertexOut in [[stage_in]],
                                     texture2d<float,access::sample> colorTex [[texture(0)]],
                                     sampler samplr [[sampler(0)]] // 通过CPU端配置的shader
                                     )
{
    // constexpr sampler samplr {min_filter::linear, mag_filter::linear, s_address::repeat, t_address::repeat }
    float4 color = colorTex.sample(samplr, in.texCoord);
    
    return color ;
    
}


