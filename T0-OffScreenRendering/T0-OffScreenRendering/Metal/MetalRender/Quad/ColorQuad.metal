//
//  ColorQuad.metal
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/26.
//

#include <metal_stdlib>
using namespace metal;

#import "QuadShaderType.h"


typedef struct
{
    float4 clipSpacePosition [[position]];
    float3 color ;
} VertexOut ;



vertex VertexOut ColorMeshVertexShader(
                                       constant QuadVertexColor* vertexes [[buffer(kQuadVertexColorBufferIndex)]],
                                       constant ViewPortScaler& vpScaler  [[buffer(kViewPortScalerUniformBufferIndex)]],
                                       uint vid [[vertex_id]]
                                       )
{
    VertexOut out ;
    
//    QuadVertexColor* vert = vertexes[vid];      // 错误 指针类型必须声明地址空间
//    QuadVertexColor& vert = vertexes[vid];      // 错误 引用类型必须声明地址空间
    QuadVertexColor vert = vertexes[vid];
    
    //vert.pos.x * vpScaler.viewport ;
    out.clipSpacePosition.xy = vpScaler.viewport * vpScaler.scaler * vert.pos.xy ;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;
    
 
    out.color = vert.color;
   
    
    return out ;
}


fragment float4 ColorMeshFragmentShader(
                                        VertexOut in [[stage_in]]
                                        )
{
    float4 color = float4(in.color, 1.0) ;
    return color ;
}
