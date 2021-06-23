/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Customized view for iOS & tvOS
*/

#import "AAPLUIView.h"
#import "AAPLConfig.h"

@implementation AAPLUIView
{
    CADisplayLink *_displayLink;

#if !RENDER_ON_MAIN_THREAD
    // Secondary thread containing the render loop
    NSThread *_renderThread;

    // Flag to indcate rendering should cease on the main thread
    BOOL _continueRunLoop;
#endif
}

///////////////////////////////////////
#pragma mark - Initialization and Setup
///////////////////////////////////////

/*
    UIKit的所有View都是 层(Layer) 实现的(backed)
    为了设置视图层的类型，UIView视图 实现了 layerClass 类方法。
    如果要设置View要由CAMetalLayer实现，必须返回CAMetalLayer类类型
 
    layerClass属性
        仅当您希望视图使用不同的CoreAnimation层(Core Animation layer) 作为 后备存储(backing store)使用时候
        例如，如果您的视图使用平铺来显示大的可滚动区域，您可能需要将该属性设置为 CATiledLayer 类
 
    AppKit 需要设置视图NSView的WantsLayer属性来支持视图层，并实现 - (CALayer *)makeBackingLayer 返回 “层”实例
 */
+ (Class) layerClass
{
    return [CAMetalLayer class];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];

#if ANIMATION_RENDERING  // 如果配置了动画效果 需要创建CADisplayLink
    if(self.window == nil)
    {
        // If moving off of a window destroy the display link.
        [_displayLink invalidate];
        _displayLink = nil;
        return;
    }

    /*
     需要在指定的UIScreen上创建CADisplayLink
     
     可以在 UIKit调用视图的 didMoveToWindow 方法时创建
     UIKit 在“第一次”将视图“添加到窗口”以及将 “视图”移动到“另一个屏幕”时调用此方法。
     
     */
    [self setupCADisplayLinkForScreen:self.window.screen];
    
    // 后面
    //      如果是在单独线程上执行渲染的话，会放到 NSThread start的线程函数上
    //      如果是在主线程上渲染，就会直接 add 到 [NSRunLoop currentRunLoop]

#if RENDER_ON_MAIN_THREAD

    // didMoveToWindow 总是在主渲染线程中执行
    // CADisplayLink 回调在 NSRunLoop 线程傻姑娘
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    /*
     
     NSDefaultRunLoopMode（kCFRunLoopDefaultMode     默认，空闲状态
     UITrackingRunLoopMode：                         ScrollView滑动时
     UIInitializationRunLoopMode：                   启动时
     NSRunLoopCommonModes（kCFRunLoopCommonModes）   Mode集合
     
     RunLoop只能运行在一种mode下，如果要换mode，当前的loop也需要停下重启成新的
     
     利用这个机制，ScrollView滚动过程中NSDefaultRunLoopMode（kCFRunLoopDefaultMode）的mode
     会切换到UITrackingRunLoopMode来保证ScrollView的流畅滑动：
     只有在NSDefaultRunLoopMode模式下处理的事件会影响scrllView的滑动
     
     */

#else // IF !RENDER_ON_MAIN_THREAD

    // 使用 `@synchronized` 块保护 _continueRunLoop ，因为它会被单独的动画线程访问(accessed by the seperate  animation thread)
    @synchronized(self)
    {
        // Stop animation loop allowing the loop to complete if it's in progress.
        _continueRunLoop = NO;
    }
    

    // Create and start a secondary NSThread which will have another run runloop.  The NSThread
    // class will call the 'runThread' method at the start of the secondary thread's execution.
    _renderThread =  [[NSThread alloc] initWithTarget:self selector:@selector(runThread) object:nil];
    _continueRunLoop = YES;
    [_renderThread start];

#endif // END !RENDER_ON_MAIN_THREAD
#endif // ANIMATION_RENDERING

    // Perform any actions which need to know the size and scale of the drawable.  When UIKit calls
    // didMoveToWindow after the view initialization, this is the first opportunity to notify
    // components of the drawable's size
#if AUTOMATICALLY_RESIZE
    [self resizeDrawable:self.window.screen.nativeScale];
#else
    // Notify delegate of default drawable size when it can be calculated
    // 当尺寸可以被计算时候, 通知委托 其默认可绘制大小
    /*
        bounds
            此属性中的矩形始终与应用程序的界面方向相匹配。
            对于支持所有界面方向的应用程序，当用户在纵向和横向模式之间旋转设备时，此属性中的值可能会更改。
        
        CALayer.contentsScale
            单元格中内容比例因子  ?????
        
     */
    CGSize defaultDrawableSize = self.bounds.size;
    
    defaultDrawableSize.width *= self.layer.contentsScale;
    defaultDrawableSize.height *= self.layer.contentsScale;
    
    [self.delegate drawableResize:defaultDrawableSize];
#endif
}

//////////////////////////////////
#pragma mark - Render Loop Control
//////////////////////////////////

#if ANIMATION_RENDERING

- (void)setPaused:(BOOL)paused
{
    super.paused = paused;

    _displayLink.paused = paused;
}

- (void)setupCADisplayLinkForScreen:(UIScreen*)screen
{
    [self stopRenderLoop]; // 把CADisplayLink invalidate

    /*
     返回与给定UISreen相关的CADisplayLink
     CADisplayLink对象会持有target目标
     线程安全
     当切换屏幕的时候 需要重建CADisplayLink（macos是CVDisplayLink i）
     */
    _displayLink = [screen displayLinkWithTarget:self selector:@selector(render)];

    /*
     是否挂起 CADisplayLink显示链接对象到目标target对象的通知
     */
    _displayLink.paused = self.paused;

     /*
      指定首选帧速率，会根据硬件功能和您的游戏或应用程序可能正在执行的其他任务，以尽可能接近给定的速率
      选择的实际帧率，通常是屏幕最大刷新率的一个因素，以提供稳定的帧率。
      例如，如果屏幕的最大刷新率是每秒60帧，那么这也是CADisplayLink可设置的最高帧率，作为实际帧率。
      但是，如果您要求较低的帧速率，则CADisplayLink可能会选择每秒 30、20 或 15 帧或其他速率作为实际帧速率
      
      选择您的应用可以始终保持的帧速率
      */
    _displayLink.preferredFramesPerSecond = 60;
}

- (void)didEnterBackground:(NSNotification*)notification
{
    self.paused = YES;
}

- (void)willEnterForeground:(NSNotification*)notification
{
    self.paused = NO;
}

- (void)stopRenderLoop
{
    /*
        从任何的run loop mode中移除，所以所有的run loop都会释放这个CADisplayLink
        并且CADisplayLink也会释放对target的持有
     */
    [_displayLink invalidate];
}

#if !RENDER_ON_MAIN_THREAD
- (void)runThread
{
    // Set the display link to the run loop of this thread so its call back occurs on this thread
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [_displayLink addToRunLoop:runLoop forMode:@"AAPLDisplayLinkMode"];

    // The '_continueRunLoop' ivar is set outside this thread, so it must be synchronized.  Create a
    // 'continueRunLoop' local var that can be set from the _continueRunLoop ivar in a @synchronized block
    BOOL continueRunLoop = YES;

    // Begin the run loop
    while (continueRunLoop)
    {
        // Create autorelease pool for the current iteration of loop.
        @autoreleasepool
        {
            /*
             
             runMode 可以是自定义的模式 或者 使用 Run Loop Modes 中列出的模式之一: kCFRunLoopDefaultMode UITrackingRunLoopMode NSRunLoopCommonModes
             
             NSRunLoopMode 为字符串类型，定义：typedef NSString * NSRunLoopMode
             
             /// 这里使用非主线程，主要考虑如果一直处于customMode模式，则主线瘫痪
             - (void)runLoopModeTest {
             
                 dispatch_async(dispatch_get_global_queue(0, 0), ^{
             
                     NSTimer *tickTimer = [[NSTimer alloc] initWithFireDate:[NSDate date] interval:2 target:self selector:@selector(modeTestTimer) userInfo:nil repeats:YES];
             
                     [[NSRunLoop currentRunLoop] addTimer:tickTimer forMode:@"customMode"];
                     [[NSRunLoop currentRunLoop] runMode:@"customMode"  beforeDate:[NSDate distantFuture]];
             
                 });
             }
             
             */
 
            // Run the loop once accepting input only from the display link.
            // 这里循环  运行在 AAPLDisplayLinkMode 模式
            [runLoop runMode:@"AAPLDisplayLinkMode" beforeDate:[NSDate distantFuture]]; // [NSDate distantFuture]] 表示未来的某个不可达到的事件点
        }

        // Synchronize this with the _continueRunLoop ivar which is set on another thread
        @synchronized(self)
        {
            // 在线程外访问的任何东西，比如_continueRunLoop实例变量，读取都在synchronized块中访问，确保它是完全/原子写的
            // Anything accessed outside the thread such as the '_continueRunLoop' ivar
            // is read inside the synchronized block to ensure it is fully/atomically written
            continueRunLoop = _continueRunLoop;
        }
    }
}
#endif // END !RENDER_ON_MAIN_THREAD

#endif // END ANIMATION_RENDERING

///////////////////////
#pragma mark - Resizing
///////////////////////

#if AUTOMATICALLY_RESIZE

// Override all methods which indicate the view's size has changed

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor
{
    [super setContentScaleFactor:contentScaleFactor];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];
    [self resizeDrawable:self.window.screen.nativeScale];
}

#endif // END AUTOMATICALLY_RESIZE

@end
