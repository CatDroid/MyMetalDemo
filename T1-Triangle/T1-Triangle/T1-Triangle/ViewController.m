//
//  ViewController.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "ViewController.h"

#import <MetalKit/MetalKit.h> // MTK = MetalKit MTKView
#import "MTKViewDelegateRender.h"

@interface ViewController ()
{
    MTKViewDelegateRender* _render ;
}


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
   
    
    // MTKView 类提供了Metal-aware视图的默认实现，您可以使用它来使用Metal渲染图形并在屏幕上显示它们
    
    // 类似Android的GLSurfaceView
    
    // MTKView 父类是 UIView(ios)或者NSView(mac) MetalKit库中一个类 layer是CAMetalLayer
    // 当被询问时, MTKView会提供一个 MTLRenderPassDescriptor 对象, 该对象指向一个纹理, 供您将新内容渲染到其中
    // 另外, MTKView可以为您创建深度和模板纹理以及抗锯齿所需的任何中间纹理
    
    // MTKView使用CAMetalLayer来管理metal可渲染对象
    
  
    // 提供三种渲染模式。分别由两个变量控制  pause每次渲染完暂停 enableSetNeedsDisplay允许View调用setNeedDispaly触发渲染
    // 默认模式，paused 和 enableSetNeedsDisplay 都是NO，渲染由内部的定时器驱动
    // paused 和 enableSetNeedsDisplay 都是YES，由view的渲染通知驱动，比如调用setNeedsDisplay ??
    // paused 是 YES  enableSetNeedsDisplay 是 NO 这个由主动调用MTKView 的draw方法  ??
    
    // 渲染方式：
    // 子类MTKView，在drawRect:方法里实现
    // 设置MTKView的代理，在代理drawInMTKView:方法实现
    
    MTKView* _view = (MTKView*)self.view ; // storyboard's view custom class is MTKView
    
    
    // https://developer.apple.com/documentation/metalkit/mtkview?language=objc
    
    // MTKView需要MTLDevice来管理Metal对象, 并且必须在渲染前, 设置设备属性 以及可选地设置view的属性
    
    // MTLDevice:开发者使用Metal进行图形开发期间，首先要获取设备上下文device，device指的就是设备的GPU
    // 多cpu处理器的macOS设备 Macbook, 系统默认的是分离式GPU 可以选择
    _view.device = MTLCreateSystemDefaultDevice();
    
    // 默认背景色: 灰色
    _view.backgroundColor = [UIColor grayColor];
    
    
    if (!_view.device)
    {
        NSLog(@"Metal is not supported on this device, change to UIView/OpenGLES ??");
        // 在这里把View,切换为UIView, ?? 可以转换为OpenGLES ??
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return ;
    }
    
    // Render是MTKView渲染代理，实现了MTKView的渲染回调，监听这个MTKView的视口变化，从而调整渲染的屏幕尺寸
    
    // Render初始化的时候 会设置MTKView的属性
    _render = [[MTKViewDelegateRender alloc] initWithMetalKitView:_view];
    _view.delegate = _render ; // delegate是个弱引用
    
     
}


@end
