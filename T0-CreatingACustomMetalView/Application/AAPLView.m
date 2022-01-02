/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Custom view base class
*/

#import "AAPLView.h"

@implementation AAPLView

///////////////////////////////////////
#pragma mark - Initialization and Setup
///////////////////////////////////////

- (instancetype) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if(self)
    {
        [self initCommon];
    }
    return self;
}

- (instancetype) initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if(self)
    {
        [self initCommon];
    }
    return self;
}

- (void)initCommon
{
    _metalLayer = (CAMetalLayer*) self.layer;
    
    // 可选2或者3。最大是3 控制同时具有drawable的数量
    // Core Animation limits the number of drawables that you can use simultaneously in your app. 
    // _metalLayer.maximumDrawableCount = 2

    // id<CAMetalDrawable> currentDrawable = [metalLayer nextDrawable];
    // _drawableRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    // 通过layer获取drawable，drawable中包含texture，可以设置到 DrawableRenderDescriptor(创建编码器需要)
    
    /*
     CALayer设置代理 弱引用
     可以使用委托对象来提供图层的内容(layer’s contents)
     处理任何子图层的布局(the layout of any sublayers)
     自定义操作以响应与图层相关的更改 (layer-related changes)
     
     设置给delegate属性的代理对象, 需要实现CALayerDelegate非正式协议中一种或多种方法
     
     在iOS中，如果图层(layer)与UIView对象相关联，则必须将此属性设置为拥有图层的视图(UIView)
     */
    self.layer.delegate = self;
    
    /*
     在这个sample中,
     CALayer的代理是AAPLView(UIView)
     AAPLView(UIView)的代理是AAPLViewController(ViewController)
     
     */

}

//////////////////////////////////
#pragma mark - Render Loop Control
//////////////////////////////////

#if ANIMATION_RENDERING

- (void)stopRenderLoop
{
    // Stubbed out method.  Subclasses need to implement this method.
}

- (void)dealloc
{
    [self stopRenderLoop];
}

#else // IF !ANIMATION_RENDERING 如果是播放动画的方式 就不会使用UI触发的方式 而是使用CADisplayLink的方式

// Override methods needed to handle event-based rendering
// 事件驱动型渲染

- (void)displayLayer:(CALayer *)layer // CALayer::display 
{
    [self renderOnEvent]; // 事件触发绘制
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
    [self renderOnEvent]; // 事件触发绘制
}

- (void)drawRect:(CGRect)rect
{
    [self renderOnEvent];  // 事件触发绘制
}

- (void)renderOnEvent
{
#if RENDER_ON_MAIN_THREAD
    [self render];
#else
    /*
     
     Dispatch Queue有两种类型，
     等待执行处理的串行队列Serial Dispatch Queue和
     不等待执行处理的并发队列Concurrent Dispatch Queue
     
     Main Dispatch Queue    是在主线程执行的串行队列，用于在主线程进行UI操作的一些任务
     Global Dispatch Queue  是全局Concurrent Dispatch Queue
     有4个优先级分别是
     高优先级（high priority），
     默认优先级（default priority），
     低优先级（low priority），
     后台优先级（background priority）；
     由于Global Dispatch Queue是系统管理的，所以对其使用dispatch_release或disspatch_retain不会有变化
     通过内核管理的用于Global Dispatch Queue的线程，将各自使用Global Dispatch Queue的“执行优先级”作为“线程的优先级”使用
     GCD使用的block是系统持有的
     dispatch queue不需要的时候 需要调用dispatch_release(Queue)
     但是还没有执行的任务会持有queue，所以直到所有的任务执行完毕queue才会实际销毁
     
     实现细节（Quality of Service，服务质量) 用来代表服务的优先级
     
     NSOperation 和 NSThread 都通过threadPriority来指定优先级GCD也只能设置:
     1.DISPATCH_QUEUE_PRIORITY_HIGH
     2.DISPATCH_QUEUE_PRIORITY_LOW
     3.DISPATCH_QUEUE_PRIORITY_BAKGROUND
     4.DISPATCH_QUEUE_PRIORITY_DEFAULT

     在iOS8之后 统一为5个等级:
     1.NSQualityOfServiceUserInteractive: 最高优先级, 用于处理 UI 相关的任务
     2.NSQualityOfServiceUserInitiated: 次高优先级, 用于执行需要立即返回的任务
     3.NSQualityOfServiceUtility: 普通优先级，主要用于不需要立即返回的任务
     4.NSQualityOfServiceBackground: 后台优先级，用于处理一些用户不会感知的任务
     5.NSQualityOfServiceDefault: 默认优先级，当没有设置优先级的时候，线程默认优先级

     在GCD的则提供对应的:
     1.QOS_CLASS_USER_INTERACTIVE  用户交互user interactive等级表示任务需要被立即执行提供好的体验，用来更新UI，响应事件等。这个等级最好保持小规模。
     2.QOS_CLASS_USER_INITIATED。  user initiated等级表示任务由用户发起异步执行。适用场景是需要及时得到结果同时又可以继续交互的时候。
     3.QOS_CLASS_UTILITY           utility等级表示需要长时间运行的任务，伴有用户可见进度指示器。经常会用来做计算，I/O，网络，持续的数据填充等任务。这个任务需要节能
     4.QOS_CLASS_BACKGROUND        background等级表示用户不会察觉的任务，使用它来处理预加载，或者不需要用户交互和对时间不敏感的任务
     5.QOS_CLASS_DEFAULT
     6.QOS_CLASS_UNSPECIFIED
     
     旧的宏定义 对应 新的QOS定义
     *  - DISPATCH_QUEUE_PRIORITY_HIGH:         QOS_CLASS_USER_INITIATED。-- 高优先级
     *  - DISPATCH_QUEUE_PRIORITY_DEFAULT:      QOS_CLASS_DEFAULT
     *  - DISPATCH_QUEUE_PRIORITY_LOW:          QOS_CLASS_UTILITY
     *  - DISPATCH_QUEUE_PRIORITY_BACKGROUND:   QOS_CLASS_BACKGROUND

     */
    // Dispatch rendering on a concurrent queue
    dispatch_queue_t globalQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_async(globalQueue, ^(){
        [self render];  // 调用代理_delegate的renderToMetalLayer:_metalLayer
    });
#endif
}

#endif // END !ANIMAITON_RENDERING
///////////////////////
#pragma mark - Resizing
///////////////////////

#if AUTOMATICALLY_RESIZE

- (void)resizeDrawable:(CGFloat)scaleFactor
{
    CGSize newSize = self.bounds.size;
    newSize.width *= scaleFactor;
    newSize.height *= scaleFactor;

    if(newSize.width <= 0 || newSize.width <= 0)
    {
        return;
    }

#if RENDER_ON_MAIN_THREAD

    if(newSize.width == _metalLayer.drawableSize.width &&
       newSize.height == _metalLayer.drawableSize.height)
    {
        return;
    }

    _metalLayer.drawableSize = newSize;

    [_delegate drawableResize:newSize];
    
#else
    // All AppKit and UIKit calls which notify of a resize are called on the main thread.  Use
    // a synchronized block to ensure that resize notifications on the delegate are atomic
    @synchronized(_metalLayer)
    {
        if(newSize.width == _metalLayer.drawableSize.width &&
           newSize.height == _metalLayer.drawableSize.height)
        {
            return;
        }

        _metalLayer.drawableSize = newSize;

        [_delegate drawableResize:newSize];
    }
#endif
}

#endif

//////////////////////
#pragma mark - Drawing
//////////////////////

- (void)render
{
#if RENDER_ON_MAIN_THREAD
    [_delegate renderToMetalLayer:_metalLayer];
#else
    // Must synchronize if rendering on background thread to ensure resize operations from the
    // main thread are complete before rendering which depends on the size occurs.
    @synchronized(_metalLayer)
    {
        [_delegate renderToMetalLayer:_metalLayer];
    }
#endif
}

@end
