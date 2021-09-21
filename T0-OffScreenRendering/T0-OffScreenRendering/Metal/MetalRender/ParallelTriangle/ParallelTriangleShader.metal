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
    
    float4 pos = float4(vertexes[vid].pos, 0.1, 1.0); // 深度buffer默认是1.0 0.0是最前 深度buffer从0到1 0是接近观察者/摄像机
    
    out.pos = pos ;
    
    return out ;
}


fragment half4 MyFragmentShader()
{
    return half4(1.0, 0, 0, 0.8) ;
    // alpha = 0.8 先跟MetalFrameBuffer的灰色混合--红色(0.8)+灰色(0.2) 两个三角形部分近红色 alpha部分 0.8*0.8 + 1.0*0.2 = 0.84 其余部分alpha=1.0
    // 然后跟 MetalView的FrameBuffer clearColor(黄色)混合 三角形部分会再混合(接近红色0.84+黄色0.2)，其他部分直接用上面的还是灰色(alpha=1.0)
}


