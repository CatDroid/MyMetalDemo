//
//  MetalView.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#import "MetalView.h"

@implementation MetalView
{
    CADisplayLink * _displayLink;
    NSThread*       _renderThread;
    id<MTLTexture>  _depthTarget;
    
    BOOL _continueRunLoop;
}

#pragma mark - MetalView Class -

+(Class) layerClass
{
    return [CAMetalLayer class];
}

//-(CAMetalLayer*) metalLayer
//{
//    return (CAMetalLayer*)self._metalLayer;
//}

-(void) setDevice:(id<MTLDevice>)_device
{
    // layer将通过 _device 来创建资源，比如创建id<MTLDevice>
    self->_metalLayer.device = _device;
}

-(id<MTLDevice>) device
{
    return self->_metalLayer.device;
}



#pragma mark - Initialize -

-(instancetype) initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self)
    {
        [self initCommon];
    }
    else
    {
        NSLog(@"initWithCoder fail");
    }
    return self ;
}

-(instancetype) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self initCommon];
    }
    else
    {
        NSLog(@"initWithFrame fail");
    }
    return self ;
}

-(void) initCommon
{
    _colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _depthStencilPixelFormat = MTLPixelFormatInvalid;
    
    _clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    _clearDepth = 1.0;
    _clearStencil = 0.0 ;
    
    _sampleCount = 1 ; // 目前没有实现
    

    self->_metalLayer = (CAMetalLayer*)self.layer;
    self->_metalLayer.delegate = self ;
    self->_metalLayer.pixelFormat = _colorPixelFormat;
    self->_metalLayer.framebufferOnly = false ;
    // 如果是ture的话(默认) 在内部创建纹理的时候 MTLTextureDescriptor.usage 就只有RenderTarget 不能对纹理进行sample/读/写
    
}

-(void) setColorPixelFormat:(MTLPixelFormat) format
{
    // MTLPixelFormatBGRA8Unorm
    // MTLPixelFormatBGRA8Unorm_sRGB.
    //
    // MTLPixelFormatBGRA10_XR
    // MTLPixelFormatBGRA10_XR_sRGB
    // MTLPixelFormatBGR10_XR
    // MTLPixelFormatBGR10_XR_sRGB
    self->_metalLayer.pixelFormat = format ; // 线程安全 ??
    _colorPixelFormat = format;
}

-(void) setDepthStencilPixelFormat:(MTLPixelFormat) format
{
    // 目前要在创建后立刻设置这个 ??
    _depthStencilPixelFormat = format ;
}



#pragma mark - CALayerDelegate -
#pragma mark Providing the Layer's Content

// Override methods needed to handle event-based rendering
// 事件驱动型渲染

#ifdef RENDER_UI_EVEN_BASE

// 这个由metalayer通过_metalayer.delegate回调的，所以应该是_metalayer
-(void) displayLayer:(CALayer *)layer
{
    // 告诉委托 执行显示过程
    NSLog(@"displayLayer called");
    [self renderOnEvent:layer]; // [CALayer display] 会调用这个
}

-(void) drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
    // 告诉委托 使用图层的 CGContextRef 实现显示过程  ??? CGContextRef ????
    NSLog(@"drawLayer inContext called");
    [self renderOnEvent:layer];
}

#endif

- (void) layerWillDraw:(CALayer *)layer
{
    // 告诉委托 即将drawisplayLayer called
    NSLog(@"layerWillDraw called");
}

#pragma mark Laying Out Sublayers
-(void) layoutSublayersOfLayer:(CALayer *)layer
{
    // 告诉委托 layer的bounds已经改变
    NSLog(@"layoutSublayersOfLayer called");
}
 

#pragma mark Providing a Layer's Actions
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    // 提供layer动作??
    return [super actionForLayer:layer forKey:event];
}


#pragma mark - UIView -
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
#ifdef RENDER_UI_EVEN_BASE
#pragma mark UIView draw
- (void)drawRect:(CGRect)rect {
    NSLog(@"NSView drawRect ");
    [self renderOnEvent:_metalLayer];
}
#endif

#pragma mark UIView size change
-(void) didMoveToWindow
{
    NSLog(@"[didMoveToWindow] before"); // 在调用didMoveToWindow之前 会有多次setFrame
    
    [super didMoveToWindow];
    
    NSLog(@"[didMoveToWindow] after ");
    
    // 1. 创建 CADisplayLink对象 并设置CADisplayLink对象 回调函数
    if (self.window == nil)
    {
        [_displayLink invalidate];
        _displayLink = nil;
        return ;
    }
    
    if (_displayLink != nil)
    {
        [_displayLink invalidate];
    }
 
  
    // 在view初始化之后。这次第一次机会去通知drawable的尺寸
    [self _notifyResizeDrawable];
    
    UIWindow* window = self.window;
    UIScreen* screen = window.screen;
    
    _displayLink = [screen displayLinkWithTarget:self selector:@selector(_notifyDrawFrame)];
    _displayLink.paused = false ;
    _displayLink.preferredFramesPerSecond = 60;
    
    
    // 2. 创建渲染线程 并且设置 CADisplayLink对象的回调线程
    _continueRunLoop = YES;
    _renderThread = [[NSThread alloc]initWithTarget:self selector:@selector(renderThreadLoop) object:nil];
    [_renderThread start];
}

-(void) renderThreadLoop
{

    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    
    BOOL continueRunLoop = YES;
    @synchronized (self) {
        continueRunLoop = self->_continueRunLoop;
    }
    
    [_displayLink addToRunLoop:runLoop forMode:@"CADisplayLinkMode"];
    
    while(continueRunLoop)
    {
        // 在NSThread RunLoop之前创建 autoreleasepool
        @autoreleasepool {
            [runLoop runMode:@"CADisplayLinkMode" beforeDate:[NSDate distantFuture]];
        }
        
        
        @synchronized (self) {
            continueRunLoop = self->_continueRunLoop;
        }
        
    }
}

/*
 frame: 该view在父view坐标系统中的位置和大小。（参照点是，父亲的坐标系统）
 bounds：该view在本地坐标系统中的位置和大小。（参照点是，本地坐标系统，就相当于ViewB自己的坐标系统，以0,0点为起点）
 
 !! bounds 可以认为是这个UIView中内容绘制的地方  bound和frame之间会有空余地方
 
 */
- (void) setBounds:(CGRect)bounds
{
    NSLog(@"[setBounds] called x=%f y=%f w=%f h=%f", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
    
    [super setBounds:bounds];
    [self _notifyResizeDrawable];
}

- (void) setFrame:(CGRect)frame
{
    NSLog(@"[setFrame] called x=%f y=%f w=%f h=%f", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    
    [super setFrame:frame];
    [self _notifyResizeDrawable];
}

-(void) setContentScaleFactor:(CGFloat)contentScaleFactor
{
    NSLog(@"[setContentScaleFactor] called contentScaleFactor=%f", contentScaleFactor);
    
    [super setContentScaleFactor:contentScaleFactor];
    [self _notifyResizeDrawable];
}

- (void) layoutSubviews
{
    NSLog(@"[layoutSubviews] called ");
    [super layoutSubviews];
    [self _notifyResizeDrawable];
}

#pragma mark - render -

// Layer的回调 以及NSView的回调 都会触发这个事件回调
- (void)renderOnEvent:(CALayer*) layer
{
    if (layer != _metalLayer)
    {
        NSLog(@"renderOnEvent layer not match layer=%@,_metalayer=%@",layer, _metalLayer);
    }
    
    // typedef NSObject<OS_dispatch_queue> *dispatch_queue_t;
    // typedef NSObject<OS_dispatch_queue_global> dispatch_queue_global_t
    // <OS_dispatch_queue_global>的父协议是<OS_dispatch_queue>
    // dispatchQueue也是个NSObject
  
    dispatch_queue_global_t globalQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    
    __weak typeof(self) weakSelf = self ;
    dispatch_async(globalQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        // 在原对象释放之后，__weak对象就会变成null，防止野指针
        if (strongSelf)
        {
            [strongSelf _notifyDrawFrame];
        }
        else
        {
            NSLog(@"MetalView is dealloc while dispatch_asysnc on renderOnEvent");
        }
      
    });

}

 


#pragma mark - notify delegate -
-(void) _notifyResizeDrawable
{
    // 在第一次layout pass? 没有在视图层级树 所以直接用screen的scale  ??
    CGFloat scale = [UIScreen mainScreen].scale;
    
    // 物理屏幕的原生比例因子 ???
   
    UIWindow* window = self.window;
    UIScreen* screen = window.screen; // window是nil 这里不会崩溃
    CGFloat nativeScale = screen.nativeScale;
    
    if(window == nil)
    {
        nativeScale = scale ;
    }
    else
    {
        NSLog(@"UIWindow is not nil");
    }
   

    
    NSLog(@"_notifyResizeDrawable mainScreen'scale %f, UIWindow'screen'scale %f",
          scale,
          nativeScale);
    
    CGSize drawableSize = self.bounds.size;
    drawableSize.width = drawableSize.width * nativeScale;
    drawableSize.height = drawableSize.height * nativeScale;
    
    if (drawableSize.width <= 0 || drawableSize.height <= 0)
    {
        NSLog(@"_notifyResizeDrawable newSize negative ");
        return;
    }
    
    // AppKit and UIKit 都在会主线程上通知resize
    // 使用synchronized来确保 对_delegate的通知是原子的??
    @synchronized (_metalLayer) // 为了render和resize的同步
    {
        //if (drawableSize.width == _metalLayer.drawableSize.width &&
        //   drawableSize.height == _metalLayer.drawableSize.height)
        //{
        //    return;
        //} // viewDidMove 到这里 layer已经有drawableSize 并且相等
        
        // !!  根据view修改CAMetalLayer的drawable尺寸
        _metalLayer.drawableSize = drawableSize;
        
        [self _resizeDepthTexture];
        
        [_delegate OnDrawableSizeChange:drawableSize WithView:self];
    }
    
}

-(void) _resizeDepthTexture
{
    if (_depthStencilPixelFormat != MTLPixelFormatInvalid) // 暂时不支持在didMoveToWindow后重新设置format
    {
        CGSize drawableSize = _metalLayer.drawableSize ;
        
        MTLTextureDescriptor *depthTargetDescriptor = [MTLTextureDescriptor new];
        depthTargetDescriptor.width       = drawableSize.width;
        depthTargetDescriptor.height      = drawableSize.height;
        depthTargetDescriptor.pixelFormat = _depthStencilPixelFormat;
        depthTargetDescriptor.textureType = MTLTextureType2D ;
        /*
         CPU 和 GPU 之间的资源一致性(Resource coherency)不是必需的
         因为 CPU 无法访问资源(resource)的内容
         Metal可能会优化 私有资源(private resource) 私有资源是不能share和管理的资源(shared or managed resources.)
         */
        depthTargetDescriptor.storageMode = MTLStorageModePrivate;
        depthTargetDescriptor.usage       = MTLTextureUsageRenderTarget;

        _depthTarget = [self->_metalLayer.device newTextureWithDescriptor:depthTargetDescriptor];
    }

}

-(void) _notifyDrawFrame
{
    @synchronized (_metalLayer) // 如果同时打开 CADisplayLink和 UI-EventBase 会导致这里有竞态
    {
        _currentDrawable = [_metalLayer nextDrawable];
        if (_currentDrawable == nil)
        {
            NSLog(@"drawWithLayerParallel CAMetalLayer nextDrawable fail ");
            return ;
        }
        
        _currentRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
     
        MTLRenderPassColorAttachmentDescriptor* colorAttachmenDesc = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
        colorAttachmenDesc.clearColor = _clearColor;
        colorAttachmenDesc.texture = _currentDrawable.texture ;
        colorAttachmenDesc.loadAction = MTLLoadActionClear ;
        colorAttachmenDesc.storeAction = MTLStoreActionStore ;
        [_currentRenderPassDescriptor.colorAttachments setObject:colorAttachmenDesc atIndexedSubscript:0];
        
        if (_depthStencilPixelFormat != MTLPixelFormatInvalid) {
            
            if (_depthStencilPixelFormat == MTLPixelFormatDepth32Float_Stencil8)
            {
                _currentRenderPassDescriptor.depthAttachment.texture = _depthTarget;
                _currentRenderPassDescriptor.stencilAttachment.texture = _depthTarget;
            }
            else if (_depthStencilPixelFormat == MTLPixelFormatStencil8)
            {
                _currentRenderPassDescriptor.depthAttachment.texture = _depthTarget;
            }
            else if (_depthStencilPixelFormat == MTLPixelFormatDepth32Float ||  _depthStencilPixelFormat == MTLPixelFormatDepth16Unorm)
            {
                _currentRenderPassDescriptor.stencilAttachment.texture = _depthTarget;
            }
            else
            {
                NSAssert(false, @"unsupport pixel format %lu", _depthStencilPixelFormat);
            }
            
            _currentRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
            _currentRenderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare; // 这个不用store ?? 
            _currentRenderPassDescriptor.depthAttachment.clearDepth = 1.0;
            
        }
        
    
        // 在后台线程渲染 必须使用 @synchronized 来确保 在主线程的resize操作已经完成
        // _notifyResizeDrawable 主线程调用
        // _notifyDrawFrame 可在 主线程 或者 渲染线程 上调用 (如果渲染也在主线程 就不用 @@synchronized )
        // 所以这里的 @synchronized 保证了 渲染线程的 渲染和resize不会同时执行
        
        // _metalLayer is layer
        [_delegate OnDrawFrame:_metalLayer WithView:self];
    }
    
    _currentDrawable = nil; // CAMetalLayer持有
    _currentRenderPassDescriptor = nil;
    
}

 

@end
