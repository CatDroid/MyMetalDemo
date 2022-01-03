#import "MBEImageFilter.h"
#import "MBEContext.h"
@import Metal;

@interface MBEImageFilter ()
@property (nonatomic, strong) id<MTLFunction> kernelFunction;
@property (nonatomic, strong) id<MTLTexture> texture;
@end

@implementation MBEImageFilter

@synthesize dirty=_dirty;
@synthesize provider=_provider;

// 在协议中声明的属性，一般在实现文件中下划线属性是不可用的，不会自动合成属性下划线，
// 要有下划线属性，需要手动使用@synthesize指定合成的属性，否则不手动指定也是可以的，直接使用无下划线的属性即可。


- (instancetype)initWithFunctionName:(NSString *)functionName context:(MBEContext *)context;
{
    if ((self = [super init]))
    {
        NSError *error = nil;
        _context = context;
        _kernelFunction = [_context.library newFunctionWithName:functionName];
        _pipeline = [_context.device newComputePipelineStateWithFunction:_kernelFunction error:&error];
        
        NSLog(@"GPU并发执行线程宽度 %lu",  _pipeline.threadExecutionWidth ); // ihpone XR = 32 1024
        NSLog(@"线程组最大的线程数 %lu",  _pipeline.maxTotalThreadsPerThreadgroup );
       
        if (!_pipeline)
        {
            NSLog(@"Error occurred when building compute pipeline for function %@", functionName);
            return nil;
        }
        _dirty = YES;
    }
    
    return self;
}

- (void)configureArgumentTableWithCommandEncoder:(id<MTLComputeCommandEncoder>)commandEncoder
{
}

- (void)applyFilter
{
    id<MTLTexture> inputTexture = self.provider.texture;
    
    if (!self.internalTexture ||
        [self.internalTexture width] != [inputTexture width] ||
        [self.internalTexture height] != [inputTexture height])
    {
        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:[inputTexture pixelFormat]
                                                                                                     width:[inputTexture width]
                                                                                                    height:[inputTexture height]
                                                                                                 mipmapped:NO];
        textureDescriptor.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        self.internalTexture = [self.context.device newTextureWithDescriptor:textureDescriptor];
    }
    
    // 为了并行执行(parallel)，每个工作负载(workload)必须分解成块(chunks)，
    //   称为线程组(threadgroups)，
    //      并且可以进一步划分并分配给GPU 上的线程池。
    // 为了高效运行，GPU 不会调度单个线程
    //   相反，它们是成组安排的，有时称为 warps wavefronts 尽管 Metal 文档不使用这些术语
    //      线程执行宽度表示这个执行单元的大小(thread execution width)
    //         这是实际计划在 GPU 上并发运行的线程数 ***
    //            可以使用其 threadExecutionWidth 属性从命令编码器查询此值。 它很可能是 2 的小幂，例如 32 或 64。
    //              maxTotalThreadsPerThreadgroup 线程组的最大线程数 该数字将始终是线程执行宽度的倍数。 iPhone 5S / A7, they’re 32 and 512, iPhone 6 it is 512.
    //
    // 为了最大化使用GPU, 线程组中线程数目 应该是线程执行宽度(thread execution width)的倍数 但不高于 maxTotalThreadsPerThreadgroup
    //
    // 在这里，我们有些随意地选择了 8 行 x 8 列的线程组大小，或者每个线程组总共 64 个项目。
    // 我们假设由这段代码处理的纹理的维度是8的倍数，这通常是一个安全的赌注。
    // 线程组大小是目标硬件线程执行宽度的偶数倍，并且安全地低于最大总线程数。
    MTLSize threadgroupCounts = MTLSizeMake(8, 8, 1);
    
    //
    // threadgroup在x y z方向上的数目，告诉metal到底有多少的threadgroup会被执行
    // threadgroups的数目 乘以 线程组中线程的数目  决定dispatched格子的尺寸(the size of the “grid”)
    //
    MTLSize threadgroups = MTLSizeMake([inputTexture width] / threadgroupCounts.width,
                                       [inputTexture height] / threadgroupCounts.height,
                                       1);
    
    id<MTLCommandBuffer> commandBuffer = [self.context.commandQueue commandBuffer];
    
    id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
    [commandEncoder setComputePipelineState:self.pipeline];
    
   
    
    [commandEncoder setTexture:inputTexture atIndex:0];
    [commandEncoder setTexture:self.internalTexture atIndex:1];
    
    [self configureArgumentTableWithCommandEncoder:commandEncoder];
    

    // 编码命令以在一组数据上执行内核函数(execute a kernel function on a set of data)称为调度(dispatching)。
    // dispatch !!
    [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadgroupCounts];
    [commandEncoder endEncoding];
    
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted]; // 等待计算结束
}

- (id<MTLTexture>)texture // 作为属性的get/set。获取属性的时候才调用渲染
{
    if (self.isDirty)
    {
        [self applyFilter];
    }
    
    return self.internalTexture;
}

@end
