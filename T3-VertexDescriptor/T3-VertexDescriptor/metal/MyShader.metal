//
//  MyShader.metal
//  T3-VertexDescriptor
//
//  Created by hehanlong on 2021/6/17.
//

#include <metal_stdlib>
using namespace metal;
#include "ShaderType.h"

typedef struct {
    float4 pos [[position]];
    float2 texCoord;
} VertexOut ;

// 使用 VertexDescriptor 方式 就不用ShaderType.h的MyVertex
typedef struct {
    float2 pos [[attribute(0)]]; // VertexDescriptor 语义绑定
    float2 uv  [[attribute(1)]];
    float4 tangle  [[attribute(2)]];
    float4 normal  [[attribute(3)]];
    
} VertexAttribute;


//vertex VertexOut MyVertexShader(uint vid [[vertex_id]],
//                                constant MyVertex* vertexAttr [[buffer(0)]]
vertex VertexOut MyVertexShader(VertexAttribute in [[stage_in]],
                                constant MyUniform* in2 [[buffer(1)]]) // VertexDescriptor义
{
    // [[stage_in]]是自动接收来自buffer(0)的顶点数据的，因此这种方式下CPU中要将顶点数据传给buffer(0)
    // [[stage_in]]语义绑定 接收我们使用MTLVertexDescriptor配置的顶点数据流
    // !!! 这里传进来的就是当前顶点的数据，不再是完整的顶点数组 !!!
    
    VertexOut out ;
    
    float sum = 0 ;
    for(unsigned long ii = 0 ; ii < sizeof(in2->myArray)/sizeof(in2->myArray[0]); ii++ )
    {
        sum += in2->myArray[ii];
    }

    float4 result = float4(sum) + in2->addMore;
    
    float size = sizeof(in2->myArray)/sizeof(in2->myArray[0]);

    float x = (0 + size - 1) * size / 2.0 + in2->addMore.x;
    
    if ( abs(x - result.x) > 0.000001 )
    {
        // float4 position = float4(vertexAttr[vid].pos, 0, 1);
        float4 position = float4(in.pos, 0, 1);
        out.pos = position;
        //out.texCoord = vertexAttr[vid].uv ;
        out.texCoord = in.uv ;
    }
    else
    {
        out.pos = float4(0.0, 0.0, 0.0,1.0);
        out.texCoord = float2(0.0, 0.0);
        // 如果else分支 代码注释掉 不设置out的话，就会用if分支计算出来的值
    }
   

    
    return out ;
}


fragment half4 MyFragmentShader(VertexOut in [[stage_in]],
                                texture2d<half> texture [[texture(0)]] // 纹理的类型是  texture2d<half>
                                
                                )
{
 
    // mag_filter min_filter 都是枚举类 enum class
    constexpr sampler textureSampler {mag_filter::linear, min_filter::linear};
    
    const half4 color = texture.sample(textureSampler, in.texCoord);
    
    return color ;
    
}
