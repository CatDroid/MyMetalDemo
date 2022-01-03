/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our cross-platform view controller
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"

@implementation AAPLViewController
{
    MTKView *_view;

    AAPLRenderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MTKView *)self.view;

    _view.device = MTLCreateSystemDefaultDevice();
    
    NSAssert(_view.device, @"Metal is not supported on this device");

    // Indirect Buffers 间接buffer
    // 如果绘图(draw)或调度(dispatch)的调用, 所使用的参数(arguments)是由GPU动态生成的(dynamically generated), 请使用间接缓冲区(indirect buffers)
    // 间接缓冲区(Indirect Buffers)允许 发射调用，但依赖的参数 在 调用时未知的 动态的
    // 间接缓冲区(Indirect Buffers)消除了 CPU 和 GPU 之间不必要的数据传输，从而减少了处理器空闲时间。
    // 如果CPU不需要访问 draw或dispatch调用的动态参数，请使用间接缓冲区(Indirect Buffers)。
    // 参考
    // https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/IndirectBuffers.html
    //
    // indrect argument buffer
    // indrect command buffer
    //
    // 是否支持 indrect command buffer ICBs支持的GPU:
    BOOL supportICB = NO;
#if TARGET_IOS
    supportICB = [_view.device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v4];
#else
    supportICB = [_view.device supportsFeatureSet:MTLFeatureSet_macOS_GPUFamily2_v1];
#endif
    
    NSAssert(supportICB, @"Sample requires macOS_GPUFamily2_v1 or iOS_GPUFamily3_v4 for Indirect Command Buffers");
    
    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];
    
    NSAssert(_renderer, @"Renderer failed initialization");

    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];// 告知render view的尺寸

    _view.delegate = _renderer; // view回调渲染
}

@end
