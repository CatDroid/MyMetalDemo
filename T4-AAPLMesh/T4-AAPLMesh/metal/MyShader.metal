//
//  MyShader.metal
//  T4-AAPLMesh
//
//  Created by hehanlong on 2021/6/18.
//

#include <metal_stdlib>
using namespace metal;


// 顶点的数据结构与要和VertexDescriptor中描述的一致
typedef struct
{
    float3 pos [[attribute(0)]];
    float2 uv  [[attribute(1)]];
} Vertex;

typedef struct
{
    float4 pos [[position]]; // 顶点着色器的输出 需要使用绑定语义 来告诉渲染管线 顶点坐标
    float2 texCoord ;
} VertexOut;


vertex VertexOut MyVertexShader(
                                Vertex in [[stage_in]]  // 使用VertexDescriptor描述的 这里要使用绑定语义
                                                        // 使用ArgumentTable方式就要使用[[buffer(0)]]语义绑定顶点属性数组
                                )
{
    VertexOut out ;
    
    // float4 pos = float4(in.pos, 1.0);
    
    // 顶点着色器中我们强行对顶点坐标做了调整，让模型显示到屏幕内。
    // 因为这里我们还没有对模型坐标进行坐标系变换，顶点数据是定义在模型空间的，
    // 下个教程我们会使用UniformBuffer传进坐标变换矩阵，将模型坐标变换到投影空间。
    float4 pos = vector_float4(in.pos/500.0f + float3(0,-0.3,0), 1.0);
   
    out.pos = pos;
    
 
    out.texCoord = in.uv;
    
    return out ;
}

// half是16位浮点数
fragment half4 MyFragmentShader(
                               VertexOut in [[stage_in]],
                               texture2d<half, access::sample> texture [[texture(0)]]
                               )
{
    // C++14 只要保证返回值和参数是字面值就可以
    // constexpr 告诉编译器 可以做编译期优化 这是能够得到常量值的表达式
    constexpr sampler linearSampler {mip_filter::linear, mag_filter::linear, s_address::repeat, t_address::repeat};
    
    half4 color = texture.sample(linearSampler, in.texCoord);
    
    return color ;
    
}
