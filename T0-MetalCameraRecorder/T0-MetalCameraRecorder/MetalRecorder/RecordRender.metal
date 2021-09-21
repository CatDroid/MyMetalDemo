//
//  RecordRender.metal
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/28.
//

#include <metal_stdlib>
using namespace metal;


#include <metal_stdlib>
using namespace metal;

#include "RecordShaderType.h"

typedef struct
{
    float4 pos [[position]];
    float2 texCoord ;
} VertexOut ;


vertex VertexOut RecordVertexShader(
                                    constant RecordVertex* vertexes [[buffer(0)]],
                                    uint vid [[vertex_id]]
                                    )
{
    VertexOut out ;
    
    RecordVertex vert = vertexes[vid];
    out.pos = float4(vert.pos, 0.0, 1.0);
    out.texCoord = vert.uv ;
    
    return out ;
}


fragment float4 RecordFragmentShader(
                                     VertexOut in [[stage_in]],
                                     texture2d<float, access::sample> colorTex [[texture(0)]],
                                     sampler samplr [[sampler(0)]]
                                     )
{
    
    float4 color = colorTex.sample(samplr, in.texCoord);
    return color ;

}
