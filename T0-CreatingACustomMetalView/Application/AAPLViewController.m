/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the cross-platform view controller
*/

#import "AAPLViewController.h"
#if TARGET_IOS || TARGET_TVOS
#import "AAPLUIView.h"
#else
#import "AAPLNSView.h"
#endif
#import "AAPLRenderer.h"

#import <QuartzCore/CAMetalLayer.h>

@implementation AAPLViewController
{
    AAPLRenderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();

    // AAPLView 重写了 类方法 layerClass 返回了CAMetalLayer 所以这个View的layer就是 metallayer
    AAPLView *view = (AAPLView *)self.view;

    // 为“图层CAMetalLayer”设置“设备MTLDevice”，以便"图层CAMetalLayer"可以创建可在此”设备上渲染“的”可绘制纹理 drawable textures“
    view.metalLayer.device = device;
    view.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; // 可以把layer改成支持HDR ??
    

    // 设置view的代理为当前的viewcontroller, 用来响应view的resize和渲染回调
    view.delegate = self;

    // 创建渲染器--传入device用来创建 MTLRenderPipeState(MTLFunction) 和 MTLDepthStencilState  MTLCommandQueue命令队列 MTLBuffer顶点属性缓存区
    _renderer = [[AAPLRenderer alloc] initWithMetalDevice:device  drawablePixelFormat:view.metalLayer.pixelFormat];
}

#pragma mark - AAPLViewDelegete

- (void)drawableResize:(CGSize)size
{
    // 渲染器--处理view大小改变
    [_renderer drawableResize:size];
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer *)layer
{
    // 渲染器--渲染到给定的layer
    [_renderer renderToMetalLayer:layer];
}

@end
