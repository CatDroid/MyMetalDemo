//
//  MyShader.metal
//  T5-UniformBuffer
//
//  Created by hehanlong on 2021/6/20.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderType.h"

// 语义绑定 --- 变量名字没关系 但是变量类型要是期望的 比如[[position]]要是float4

typedef struct {
    float4 pos [[position]]; // 有这个语义绑定的话 数据类型必须是float4
                             //  否则错误提示: Type 'float3' (vector of 3 'float' values) is not valid for attribute 'position'
    float2 texCoord ;        // 如果作为顶点着色器返回值 但是没有[[position]]语义 xcode编译报告: Invalid return type 'VertexOut' for vertex function
    float4 posInViewSpace ;
} VertexOut ;

// Pointer type must have explicit address space qualifier

// constant MyVertex* vertexes [[buffer(0)]]
vertex VertexOut MyVertexShader(MyVertex in [[stage_in]],
                                constant MyUniform& transform [[buffer(1)]]
                                // ?? 引用类型!!
                                )
{
    VertexOut out ;
    
    // 列主矩阵
    float4 position = float4(in.pos, 1.0);
    float4 pos = transform.projectionMatrix * transform.modelViewMatrix * position;
    out.pos = pos ;
    out.texCoord = in.uv;
    out.posInViewSpace = transform.modelViewMatrix * position; // 用来测试view坐标系下z值
    
    return out ;
}


fragment half4 MyFragmentShader(
                                // texture2d<typename T, access a, typename _Enable>
                                texture2d<half, access::sample> baseColorMap [[texture(0)]],
                                // 不是  half4。       是half
                                // 不是。access::read。是access::sample
                                VertexOut in [[stage_in]]
                            
                                )
{
    
    constexpr sampler linearSampler {
        min_filter::linear,
        mag_filter::linear,
        s_address::repeat,
        t_address::repeat };
    
    
    half4 color = baseColorMap.sample(linearSampler, in.texCoord);
    
    return color ;
    
    //if (in.posInViewSpace.z > 0.0) {
    //    return half4(0.0, 1.0, 0.0, 1.0); // z坐标都大于0 ??
    //} else {
    //    return half4(1.0, 0.0, 0.0, 1.0);
    //}
    
}
