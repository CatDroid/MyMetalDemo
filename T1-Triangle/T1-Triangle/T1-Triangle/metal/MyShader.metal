//
//  MyShader.metal
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

typedef struct
{
    float4 pos [[position]] ;   // 顶点坐标  修饰符 [[position]]  [[position]]表示的是vertex shader传递给下个阶段的顶点坐标数据
    float2 texCoord ;           // 纹理坐标
} VertexDesc ; // 顶点着色器的返回值

// [[  ]]  MSL中语义绑定

// 如果一个顶点函数的返回值不是void，那么返回值必须包含顶点位置；
// 如果返回值是float4，默认表示位置，可以不带[[ position ]]修饰符；
// 如果一个顶点函数的返回值是结构体，那么结构体必须包含“[[ position ]]”修饰的变量。


/*
 顶点函数相关的修饰符
 
 [[vertex_id]]          vertex_id是顶点shader每次处理的index，用于定位当前的顶点 用来索引buffer(n)
 [[instance_id]]        instance_id是单个实例多次渲染时，用于表明当前索引
 [[clip_distance]]      float 或者 float[n]， n必须是编译时常量
 [[point_size]]         float  点精灵尺寸
 [[position]]           float4 顶点坐标
 [[buffer(n)]]          buffer表明是缓存数据 n是索引
 */
vertex VertexDesc myVertexShader(
                                 constant Vertex* vertexAttribute0   [[buffer(0)]], // 顶点属性vertexAttribute0是个数组 通过vid来索引
                                 uint vid                           [[vertex_id]]   // 通过[[vertex_id]]语义我们获取了当前顶点的id，也即是顶点缓冲的顶点index
                                 )
{
    /*
     地址空间的修饰符
     device
     threadgroup
     constant
     thread
     
     顶点函数(vertex) 像素函数(fragment) 通用计算函数(kernel) 的指针或引用参数，都必须带有" 地址空间修饰符号 "
     
     Metal的内存访问主要有两种方式：Device模式和Constant模式，由代码中显式指定
        Device支持读写，并且没有size的限制      比较通用的访问模式，使用限制比较少
        Constant是只读，并且限定大小           为了多次读取而设计的快速访问
     
     */
 
    VertexDesc out ;
    
    float4 pos = vector_float4(vertexAttribute0[vid].pos, 0 , 1.0);
    
    out.pos = pos ;
    
    return out ;
}

/*
 像素函数相关的修饰符
 输入相关的描述符:
 [[color(m)]]           float或half等，m必须是编译时常量，表示输入值从一个颜色attachment中读取，m用于指定从哪个颜色attachment中读取
 [[front_facing]]       bool，如果像素所属片元是正面则为true；
 [[point_coord]]        float2，表示点图元的位置，取值范围是0.0到1.0；
 [[position]]           float4，表示像素对应的窗口相对坐标(x, y, z, 1/w)； ??? 已经做了透视除法 ???
 [[sample_id]]          uint，The sample number of the sample currently being processed.  当前片段序号
 [[sample_mask]]        uint，The set of samples covered by the primitive generating the fragmentduring multisample rasterization.
 输出相关描述符:
 [[color(m)]]               floatn
 [[depth(depth_qualifier)]] float
 [[sample_mask]]            uint
 
 struct FragmentOutput
 {
    // color attachment 0
    float4 color_float      [[color(0)]];
    // color attachment 1
    int4 color_int4         [[color(1)]];  ??? int4 ???
    // color attachment 2
    uint4 color_uint4       [[color(2)]];  ??? uint4 ???
 };
 
 fragment FragmentOutput fragment_shader( ... ) { ... };
 
 颜色attachment的参数设置要和像素函数的输入和输出的数据类型匹配 ???
 
 
 [[stage_in]] 代表着从顶点返回的顶点信息 它的值会是根据你的渲染的位置来插值
 
 */
fragment float4 myFragmentShader(VertexDesc                             vert                [[stage_in]]
                                 //, texture2d<float,access::sample>      inputImage          [[ texture(0) ]]
                                 //, sampler                              textureSampler      [[sampler(0)]]
                                 )
{
    return float4(1.0, 0, 0, 1.0) ; // float4(1.0,  0,  0,  0);
}




