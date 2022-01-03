#import "MBEContext.h"
@import Metal; // 导入模块 #include <Metal/Metal.h>


@implementation MBEContext

+ (instancetype)newContext
{
    return [[self alloc] initWithDevice:nil];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super init]))
    {
        _device = device ?: MTLCreateSystemDefaultDevice();
        _library = [_device newDefaultLibrary];  // 默认library 使用app打包的metal文件
        _commandQueue = [_device newCommandQueue]; // 一个context一个queue
    }
    return self;
}

@end
