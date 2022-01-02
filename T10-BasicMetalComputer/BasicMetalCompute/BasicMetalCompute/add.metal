//
//  MetalAdder.metal
//  BasicMetalCompute
//
//  Created by hehanlong on 2022/1/1.
//

#include <metal_stdlib>

using namespace metal;

// Metal automatically assigns indices for the buffer arguments in the order that the arguments appear in the function declaration in Listing 2, starting with 0.
// Metal 对于buffer参数组 会 自动分配索引, 按照函数声明参数的顺序

// 3种函数修饰符：kernel、vertex、fragment
// 使⽤kernel 修饰的函数. 其 返回值类型必须是void 类型
// 只有图形着⾊函数才可以被 vertex 和 fragment 修饰，返回值类型可以辨认出它是为 顶点做计算还是为每像素做计算
// 图形着⾊函数的返回值可以为 void , 但是这也就意味着该函数不产⽣数 据输出到绘制管线; 这是⼀个⽆意义的动作

// 返回值void
kernel void addFtn(device const float* input1 [[buffer(0)]], // 属性修饰符的声明位置应该位于参数变量名之后
                device const float* input2 [[buffer(1)]], // 通过修饰符, 设定一个缓存，纹理，采样器的位置
                device float* output [[buffer(2)]],   // 数据类型 可以是char* 也可以是float* 按照自己的定义，这里应该是float
                uint index [[thread_position_in_grid]]
                    // thread_position_in_grid 一定要是uint
                    // 当前节点在多线程网格中的位置。因为使用一维的格子 所以这里可以直接定义为标量
                )
{
    
    // 一个格子就是 [encode dispatchThreads:gridSize = {数组长度,1,1}
    // 所以这里 thread_position_in_grid 格子中的位置 就是 数组序号
    
    output[index] = input1[index] + input2[index];
    
}


