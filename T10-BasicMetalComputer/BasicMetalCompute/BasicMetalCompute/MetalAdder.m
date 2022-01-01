//
//  MetalAdder.m
//  BasicMetalCompute
//
//  Created by hehanlong on 2022/1/1.
//

#import "MetalAdder.h"
#import <Metal/Metal.h>

const unsigned int arrayLength = 1 << 24;
const unsigned int bufferSize = arrayLength * sizeof(float); // 浮点数buffer

@interface MetalAdder ()

@property id<MTLDevice> device;
@property id<MTLCommandQueue> queue;
@property id<MTLComputePipelineState> pipeline;
@property id<MTLBuffer> buffer;

@end


@implementation MetalAdder

-(instancetype) init
{
    self = [super init];
    
    if (self)
    {
        _device = MTLCreateSystemDefaultDevice();
        
        // app的default libray包含了 add.metal文件，或者说，在打包app的时候add.metal已经编译并打包到default Library
        id<MTLLibrary> lib = [_device newDefaultLibrary];
        
        // 从default library中获取
        // 是metal文件内函数的名字，而不是文件名字
        id<MTLFunction> func = [lib newFunctionWithName:@"addFtn"];
        
        // The function object is a proxy for the MSL function, but it’s not executable code.
        // You convert the function into executable code by creating a pipeline.
        // MTLFunction对象只是MSL函数的代理 不是执行的代码 需要通过创建一个pso把这个函数转换为执行代码
        //
        // 一个“pipeline”描述了 为了完成一个特定的任务 GPU需要执行的步骤 ;  在metal中“pipeline”由PSO描述
        //
        // 一个计算的管线pipeline 运行单个计算函数（compute function)
        
        // Create a compute pipeline state object.
        // 创建PSO对象的时候，MTLDevide对象 完成 这个函数 针对即将要运行的GPU上的编译
        // 由于编译需要耗时，所以要避免 在性能敏感的代码中，同步地创建PSO
        
        NSError* err;
        _pipeline = [_device newComputePipelineStateWithFunction:func error:&err];
        if (_pipeline == nil) {
            NSLog(@"newComputePipelineStateWithFunction fail %@", err);
        }
        
        _queue = [_device newCommandQueue];
        
    }
    
    return self;
}

-(void) prepareData
{
    // GPU 可以拥有自己的专用内存，也可以与操作系统共享内存。
    // Metal 和操作系统内核需要执行额外的工作，让您将数据存储在内存中，并使这些数据可供 GPU 使用。
    //
    // 资源resources 是 GPU 在运行命令时可以访问的内存分配
    // 使用 MTLDevice 为其 GPU 创建资源 resources
    //
    // 本示例中的资源是 (MTLBuffer) 对象，它们是没有预定义格式的内存分配。Metal 将每个缓冲区作为一个不透明的字节集合进行管理。(an opaque collection of bytes.)
    // 但是，在着色器中使用缓冲区时 是要指定格式。 这意味着 着色器和 应用程序 需要就来回传递的 任何数据的格式达成一致
    //
    // 当你分配一个缓冲区时，你提供了一种存储模式来 确定它的一些性能特征(performance characteristics)以及 CPU 或 GPU 是否可以访问它。
    //
  

    // input1 + input2 = sum 都用同一个buffer
    _buffer = [_device newBufferWithLength:bufferSize * 3  options:MTLResourceStorageModeShared];
    
    float* buffer = _buffer.contents;
    for (int i = 0 ; i < arrayLength ; i++)
    {
        buffer[i] =  ((float)rand() / (float)RAND_MAX);
        buffer[arrayLength + i] = ((float)rand() / (float)RAND_MAX);
        
    }
}

-(void) doComputeCommand
{
    
    // Create a command buffer to hold commands. 创建一个CommandBuffer装载命令
    id<MTLCommandBuffer> cmd = [_queue commandBuffer];
    NSLog(@"1 Command Buffer State %lu" , (unsigned long)cmd.status);

    
    // 要将命令写入命令缓冲区，需要使用特定类型的命令编码器。
    // 每个计算命令都会使 GPU 创建一个"线程网格"(a grid of threads) 以在 GPU 上执行。
    
    // Start a compute pass.  计算通道(“compute pass”) 包含 执行计算管道(execute compute pipelines) 的 命令列表。
    // 创建Computer的Encoder不需要参数 但是RenderPipe需要 RenderPass
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];
    encoder.label = @"MyBasicComputerShader";
    
    [encoder pushDebugGroup:@"BasicCSDebugGroup"];
    
    
    // 往编码器 设置 PSO  并且设置需要传入pipeline的参数
    // 编码器将所有状态变化（state changes）和命令参数写入命令缓冲区（command buffer）。
    // Encode the pipeline state object and its parameters.
    [encoder setComputePipelineState:_pipeline];
    
    
    // 创建一个buffer 存放不同的参数 并设置各自的offset
    [encoder setBuffer:_buffer offset:0 atIndex:0];
    [encoder setBuffer:_buffer offset:bufferSize atIndex:1]; // 偏移是byte单位
    [encoder setBuffer:_buffer offset:bufferSize+bufferSize atIndex:2];
    

    
    // Specify Thread Count and Organization 指定线程数目和组织
    // Metal 可以创建 1D、2D 或 3D 网格
    // add_arrays 函数使用一维数组，因此示例创建了一个大小为 (dataSize x 1 x 1) 的一维网格，Metal 从中生成了介于 0 和 dataSize-1 之间的索引。
    // ?? 计算的规模
    MTLSize gridSize = MTLSizeMake(arrayLength, 1, 1);
    
    // Metal 将网格细分为更小的网格，称为线程组。每个线程组单独计算(calculated separately)
    // Metal 可以将"线程组"分派到 GPU 上的不同处理元素(processing elements)以加快处理速度。 // ??? 单个线程组中线程越多,线程组就少了?速度会慢?
    // ?? 分组
    NSUInteger maxGroup = _pipeline.maxTotalThreadsPerThreadgroup;// 向管道状态对象询问线程组中最大可能线程数
    MTLSize groupSize = MTLSizeMake(arrayLength, 1, 1);
    if (groupSize.width > maxGroup)
    {
        // 1024 maxTotalThreadsPerThreadgroup 属性给出了线程组中允许的最大线程数，  这取决于 用于创建管道状态对象PSO 的函数MTLFuctnion的复杂性
        groupSize.width = maxGroup;
    }
    
    
    // 编码计算指令---调度线程网格
    // 当 GPU 执行此命令时，它会使用 之前设置的状态 和 命令的参数 来 "调度线程网格" 来执行计算。
    // 可以使用同一编码器，按照相同的步骤将多个“计算命令”编码到“计算通道”(compute pass)中，而无需执行任何冗余步骤。
    // 例如，只设置一次管道状态对象，然后为要处理的每个缓冲区集合，设置参数并编码命令 (调用同一个函数 但是每次传入函数参数不一样)
    // Encode the compute command.
    [encoder dispatchThreads:gridSize
                threadsPerThreadgroup:groupSize]; // 每个线程组。 最多是1024 ??  每个线程组的线程X*Y*Z最多是1024
    
    
    [encoder popDebugGroup];
    
    // End the compute pass.
    [encoder endEncoding];
    
    NSLog(@"2 Command Buffer State %lu" , (unsigned long)cmd.status); // 0
    
    // Execute the command.
    [cmd commit];
    NSLog(@"3 Command Buffer State %lu" , (unsigned long)cmd.status); // 2
    
    [cmd waitUntilCompleted];
    NSLog(@"4 Command Buffer State %lu" , (unsigned long)cmd.status); // 4
    
    // commandBuffer.status MTLCommandBufferStatus 可以查询CommandBuffer的状态，可选的状态是
    //  MTLCommandBufferStatusNotEnqueued
    //  enqueued,   进入队列
    //  committed,  以提交到GPU
    //  scheduled,  GPU执行中
    //  completed.  GPU执行完
    //  MTLCommandBufferStatusError.  执行命令被终止，因为发生错误
    
    //    MTLCommandBufferStatusNotEnqueued = 0, ///
    //    MTLCommandBufferStatusEnqueued = 1,
    //    MTLCommandBufferStatusCommitted = 2,  ////
    //    MTLCommandBufferStatusScheduled = 3,
    //    MTLCommandBufferStatusCompleted = 4, ////
    //    MTLCommandBufferStatusError = 5,
    
    
    bool differ = false ;
    float* data = _buffer.contents;
    for(int i = 0 ; i < arrayLength; i++)
    {
        float cpu = data[i] + data[i+arrayLength];
        float gpu = data[i+2*arrayLength];
        if(fabsf(cpu - gpu) > 0.000001)
        {
            differ = true ;
            NSLog(@"diff = %f", fabsf(cpu - gpu) );
        }
    }
    NSLog(@" cpu match gpu ???????????? %@", differ?@"Error":@"True");
}


@end
