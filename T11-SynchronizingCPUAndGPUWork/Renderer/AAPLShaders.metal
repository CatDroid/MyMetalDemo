/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal vertex and fragment shaders.
*/

#include <metal_stdlib>

using namespace metal;

// Include header shared between this Metal shader code and the C code executing Metal API commands.
#include "AAPLShaderTypes.h"

// Vertex shader outputs and fragment shader inputs.
struct RasterizerData
{
    // The [[position]] attribute qualifier of this member indicates this value is the clip space
    // position of the vertex when this structure is returned from the vertex shader.
    float4 position [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer interpolates
    // its value with values of other vertices making up the triangle and passes the interpolated
    // value to the fragment shader for each fragment in that triangle.
    float4 color;

};


// 所有着色器函数（kernel,vertex,fragment)的参数，如果是指针或是引用，都必须带有地址空间修饰符号
//  device       可读也是可写的(可以自己加const限制)  一个缓存对象可以被声明成一个标量，向量或者是用户自定义 或者是数组 比如顶点buffer
//  threadgroup  被一个线程组的所有线程共享
//  constant     注意不是const。也是设备内存池分配存储，但它是只读的
//  thread       ??这个线程的地址空间定义的变量在其他线程不可见(绘制和计算shader都可以用)

// 内建变量属性修饰符
// [[vertex_id]]:顶点id标识符        顶点buffer中的序号
// [[position]]:顶点信息（float4）    顶点着色器输出
// [[point_size]]:点的大小（float）   顶点着色器输出  绘制点精灵的大小
// [[color(m)]]:颜色，m编译前需要确定   片源着色器输出？
// [[stage_in]]  顶点和片元着色函数都是只能有一个参数被声明为使用“stage_in”修饰符;
//              片元着色函数 使用[[stage_in]]  "单个片元输入数据" 是由顶点着色函数输出然后经过"光栅化"生成的
//              顶点着色函数 使用[[stage_in]] 可以是单独一个顶点的数据, 自定义的结构体


// MTLVertexDescriptor 组织顶点数据结构
// MTLVertexDescriptor的设置时取决于我们的模型数据的，例如我们加载一个obj模型，它的顶点数据可能有position，normal，uv，tangent


// MTLVertexDescriptor并不是必须使用的，因为将顶点缓冲VB传送给vertex shader的方式
// 除了用MTLVertexDescriptor描述顶点结构然后在顶点着色函数中用[[stage_in]]属性接收
// 还可以直接通过设置顶点buffer传给顶点着色函数[[buffer(id)]]，并根据[[ vertex_id]]属性定位当前顶点的数据

// 如果顶点着色函数的参数 使用[[stage_in]] 必须给出 MTLVertexDescriptor(一个PSO只能设置一个),  并且函数参数类型(一般是结构体)的成员 必须加上 属性修饰符 [[attribute(0)]]
// 通过 MTLVertexDescriptor vertexDescriptor.attributes[] vertexDescriptor.layouts[] GPU可以知道从哪些buffer去获取哪些数据 来给到stage_in的参数 作为一个顶点数据
// 使用[[stage_in]]  GPU管线会根据MTLVertexDescriptor来拼凑(获取或收集)一个顶点的数据到一个结构体参数中
//                 (相当于由管线完成了, 根据vertex_id 从buffer argument table中, 得到struct VerInfo{pos=vb1[vertex_id]; color=vb2[vertex_id]; texCoord=vb3[vertex_id];};) // SOA


// AOS Array Of Structure  交错顶点属性
// 同一个顶点的所有属性在同一个buffer依次排列存储，然后继续排列存储下一个顶点数据 符合面向对象的布局思路

// SOA  非交错顶点属性/平面顶点属性
// 有一个结构来包含多个数组，现在我们有一个结构来包含多个数组，每个数组只包含一个属性，这样GPU可以使用同一个index索引去读取每个数组中的属性，GPU读取比较整齐，这种方法对于某一些3D文件格式尤其合适。


// Vertex shader.
vertex RasterizerData
vertexShader(const uint vertexID [[ vertex_id ]],
             const device AAPLVertex *vertices [[ buffer(AAPLVertexInputIndexVertices) ]], // device设备地址空间(const只是限制数据类型,不是地址空间)
             constant vector_uint2 *viewportSizePointer  [[ buffer(AAPLVertexInputIndexViewportSize) ]]) // constant地址空间
{
    RasterizerData out;

    // Index into the array of positions to get the current vertex.
    // Positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from the origin).
    float2 pixelSpacePosition = vertices[vertexID].position.xy;

    // Get the viewport size and cast to float.
    vector_float2 viewportSize = vector_float2(*viewportSizePointer);

    // To convert from positions in pixel space to positions in clip-space,
    // divide the pixel coordinates by half the size of the viewport.
    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = pixelSpacePosition / (viewportSize / 2.0); // x和y方向 分别除以 屏幕宽高

    // Pass the input color straight to the output color.
    out.color = vertices[vertexID].color;

    return out;
}

// Fragment shader.
fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    // Return the color you just set in the vertex shader.
    return in.color;
}

