//
//  MetalView.m
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#import <Foundation/Foundation.h>
#import "MetalView.h"

#pragma mark - MetalView类 -

@implementation MetalView
{
    CADisplayLink * _displayLink;
    NSThread*       _renderThread;
    id<MTLTexture>  _depthTarget;
    
    BOOL _continueRunLoop;
}

#pragma mark - 为这个类的实例创建layer -

+(Class) layerClass
{
    return [CAMetalLayer class];
}


#pragma mark - 属性 -

-(void) setDevice:(id<MTLDevice>) _device
{
    self->_metalLayer.device = _device;
}

-(id<MTLDevice>) device
{
    return self->_metalLayer.device;
}

-(void) setColorPixelFormat:(MTLPixelFormat) format
{
    self->_metalLayer.pixelFormat = format ;
    _colorPixelFormat = format;
}

-(void) setDepthStencilPixelFormat:(MTLPixelFormat) format
{
    // _depthStencilPixelFormat = format ;
}



#pragma mark - 构造函数 -
-(instancetype) initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self _initCommon];
    } else {
        
    }
    return self;
}

-(instancetype) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self _initCommon];
    } else {
      
    }
    return self ;
}



-(void) _initCommon
{
    //_colorPixelFormat        = MTLPixelFormatBGRA8Unorm_sRGB;
    _colorPixelFormat = MTLPixelFormatBGRA8Unorm; // 摄像头出来的数据就是sRGB的 不用sRGB的纹理(也就是shader写入texture不用硬件做"线性RGB"到"sRGB"的转换)

    _clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    self->_metalLayer = (CAMetalLayer*)self.layer;
    self->_metalLayer.delegate = self ;
    self->_metalLayer.pixelFormat = _colorPixelFormat;
    self->_metalLayer.framebufferOnly = true ;  // ture(默认):内部创建fbo附件纹理, MTLTextureDescriptor.usage只作为RenderTarget,不能对纹理进行sample/读/写
    
}


#pragma mark - CALayerDelegate CALayer回调函数 -

-(void) didMoveToWindow
{
    NSLog(@"[didMoveToWindow] before");
    [super didMoveToWindow];
    NSLog(@"[didMoveToWindow] after ");
    
    // 1. 创建 CADisplayLink对象 并设置CADisplayLink对象 回调函数
    if (self.window == nil) { // 父类UIView属性
        [_displayLink invalidate];
        _displayLink = nil;
        return ;
    }
    
    if (_displayLink != nil) {
        [_displayLink invalidate];
    }
    
 
    UIWindow* window = self.window;
    UIScreen* screen = window.screen;
    
    _displayLink = [screen displayLinkWithTarget:self selector:@selector(_notifyDrawFrame)];
    _displayLink.paused = false ;                   // CADisplayLink事件是否暂停
    _displayLink.preferredFramesPerSecond = 15;     // 控制UIView 回显的帧率
    
    
    // 2. 在view初始化之后。这次第一次机会去通知drawable的尺寸
    [self _notifyResizeDrawable];
    
    
    
    // 3. 创建渲染线程 并且设置 CADisplayLink对象的回调线程
    _continueRunLoop = YES;
    _renderThread = [[NSThread alloc]initWithTarget:self selector:@selector(renderThreadLoop) object:nil];
    [_renderThread start];
    
}


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


#pragma mark - 渲染线程  CADisplayLink事件触发执行 目前是15fps -

-(void) renderThreadLoop
{

    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    
    BOOL continueRunLoop = YES;
    @synchronized (self) {
        continueRunLoop = self->_continueRunLoop;
    }
    
    // CADisplayLink事件监听放入到runLoop中
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


#pragma mark - UI线程resize回调 -
-(void) _notifyResizeDrawable
{
    CGFloat scale = [UIScreen mainScreen].scale;    // 屏幕screen
    UIWindow* window = self.window;
    UIScreen* screen = window.screen;
    CGFloat nativeScale = screen.nativeScale;       // view-windows的scale
    
    if(window == nil)  {
        nativeScale = scale ;
    } else {
        NSLog(@"UIWindow is not nil");
    }
   
    NSLog(@"%s mainScreen'scale %f, UIWindow'screen'scale %f",
          __FUNCTION__,
          scale,
          nativeScale);
    
    CGSize drawableSize = self.bounds.size;
    drawableSize.width  = drawableSize.width  * nativeScale;
    drawableSize.height = drawableSize.height * nativeScale;
    
    if (drawableSize.width <= 0 || drawableSize.height <= 0) {
        NSLog(@"%s newSize negative ", __FUNCTION__);
        return;
    } else {
        NSLog(@"%s (%f, %f) ", __FUNCTION__,
              drawableSize.width,
              drawableSize.height);
    }
    
    // AppKit and UIKit 都在会主线程上通知resize
    // 使用synchronized来确保 对_delegate的通知是原子的??
    @synchronized (_metalLayer) // 为了render和resize的同步
    {
      
        // !!  根据view修改CAMetalLayer的drawable尺寸
        _metalLayer.drawableSize = drawableSize;
        
        [_delegate OnDrawableSizeChange:drawableSize WithView:self];
    }
    
}

#pragma mark - 渲染线程回调 -
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
        colorAttachmenDesc.clearColor  = _clearColor;
        colorAttachmenDesc.texture     = _currentDrawable.texture ; // MetalLayer -- 多个drawable -- 每个drawable对应一个texture
        colorAttachmenDesc.loadAction  = MTLLoadActionClear ;
        colorAttachmenDesc.storeAction = MTLStoreActionStore ;
        [_currentRenderPassDescriptor.colorAttachments setObject:colorAttachmenDesc atIndexedSubscript:0];
        
//        if (_depthStencilPixelFormat != MTLPixelFormatInvalid) {
//            
//            if (_depthStencilPixelFormat == MTLPixelFormatDepth32Float_Stencil8)
//            {
//                _currentRenderPassDescriptor.depthAttachment.texture = _depthTarget;
//                _currentRenderPassDescriptor.stencilAttachment.texture = _depthTarget;
//            }
//            else if (_depthStencilPixelFormat == MTLPixelFormatStencil8)
//            {
//                _currentRenderPassDescriptor.depthAttachment.texture = _depthTarget;
//            }
//            else if (_depthStencilPixelFormat == MTLPixelFormatDepth32Float ||  _depthStencilPixelFormat == MTLPixelFormatDepth16Unorm)
//            {
//                _currentRenderPassDescriptor.stencilAttachment.texture = _depthTarget;
//            }
//            else
//            {
//                NSAssert(false, @"unsupport pixel format %lu", _depthStencilPixelFormat);
//            }
//            _currentRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
//            _currentRenderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare; // 这个不用store ??
//            _currentRenderPassDescriptor.depthAttachment.clearDepth = 1.0;
//            
//        }
        
    
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
