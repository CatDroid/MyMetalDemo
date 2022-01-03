@import Foundation;

// 声明使用这些协议 
@protocol MTLDevice, MTLLibrary, MTLCommandQueue;

@interface MBEContext : NSObject

@property (strong) id<MTLDevice> device;
@property (strong) id<MTLLibrary> library;
@property (strong) id<MTLCommandQueue> commandQueue;

// 静态方法
+ (instancetype)newContext;

@end
