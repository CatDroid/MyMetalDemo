//
//  MyShader.metal
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderType.h"


typedef struct
{
    float4 pos [[position]];
    float2 texCoord ;
} VertexOut ;


vertex VertexOut MyVertexShader(
                                constant Vertex* vertexes [[buffer(0)]],
                                uint32_t vid [[vertex_id]]
                                )
{
    VertexOut out ;
    
    float4 pos = float4(vertexes[vid].pos, 0.0, 1.0);
    
    out.pos = pos ;
    
    return out ;
}


fragment half4 MyFragmentShader()
{
    return half4(1.0, 0, 0, 1.0) ;
}


