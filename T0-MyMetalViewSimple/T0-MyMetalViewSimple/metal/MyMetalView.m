//
//  MyMetalView.m
//  T0-MyMetalViewSimple
//
//  Created by hehanlong on 2021/9/23.
//

#import "MyMetalView.h"


@implementation MyMetalView
{
	// 渲染资源
	id <MTLCommandQueue> _commandQueue ;
	
	// 线程相关
	CADisplayLink * _displayLink;
	NSThread*       _renderThread;
	BOOL _continueRunLoop;
	
	// 纹理池
	NSMutableArray<id<MTLTexture>>* _texturePool;
	uint32_t _texTextOrder ;
}

+(Class)layerClass
{
	return [CAMetalLayer class];
}

#pragma mark 构造函数

-(instancetype) init
{
	self = [super init];
	[self _setup];
	return self ;
}

-(instancetype) initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	[self _setup];
	return self;
}


-(instancetype) initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	[self _setup];
	return self;
}

-(void) _setup
{
	_colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
	_depthStencilPixelFormat = MTLPixelFormatInvalid;
	
	_clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
	_clearDepth = 1.0;
	_clearStencil = 0.0 ;
	
	_sampleCount = 1 ; // TODO
	
	_metalLayer = (CAMetalLayer*)self.layer;
	_metalLayer.delegate = self; // CALayerDelegate
	_metalLayer.framebufferOnly = YES; // 只作为RT 应该也是可以读的??
	_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; // 默认是 MTLPixelFormatBGRA8Unorm.
	
	_texturePool = [NSMutableArray array];
}


#pragma mark UIView的生命周期

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/


-(void) didMoveToWindow
{
	[super didMoveToWindow];
	NSLog(@"[MyMetalView][didMoveToWindow] begin ------");
	
	
	if (self.device == nil) // 外部提供 MTLDevice 没有的话内部兜底
	{
		self.device = MTLCreateSystemDefaultDevice();
	}
	id<MTLDevice> gpu = self.device;
	_commandQueue = [gpu newCommandQueue];
	
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
	
	
	NSLog(@"[MyMetalView][didMoveToWindow] end   ------");
	
}

#pragma mark 渲染线程
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


#pragma mark CALayerDelegate  CALayer的回调
- (id<CAAction>) actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
	// 对于事件event 在layer上 执行action操作 ??
	return [super actionForLayer:layer forKey:event];
}

- (void) layoutSublayersOfLayer:(CALayer *)layer
{
	// layer的bounds发生改变(比如frame大小改变了)，如果需要精细化空间这个layer的子layer的布局
	return [super layoutSublayersOfLayer:layer];
}


- (void) layerWillDraw:(CALayer *)layer
{
	// 这个layer即将被draw 在 drawLayer:inContext:调用之前 可以用来设置  contentsFormat和opaque
	[super layerWillDraw:layer];
}

- (void) displayLayer:(CALayer *)layer
{
	// 需要重新显示layer 比如调用了 setNeedsDisplay
	// 这个方法实现了,那么 drawLayer 不会被调用
	[super displayLayer:layer];
}

- (void) drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
	// 使用CGContextRef ctx把内容 curves and lines, or images 画到 layer上
	// 如果实现了 displayLayer: 这个不会被调用
	[self drawLayer:layer inContext:ctx];
}



#pragma mark 属性

-(void) setDevice:(id<MTLDevice>) gpu
{
	self->_metalLayer.device = gpu;
}

-(id<MTLDevice>) device
{
	return self->_metalLayer.device;
}

@synthesize colorPixelFormat = _colorPixelFormat
;
-(void) setColorPixelFormat:(MTLPixelFormat) format
{
	// MTLPixelFormatBGRA8Unorm
	// MTLPixelFormatBGRA8Unorm_sRGB.
	// MTLPixelFormatBGRA10_XR
	// MTLPixelFormatBGRA10_XR_sRGB
	// MTLPixelFormatBGR10_XR
	// MTLPixelFormatBGR10_XR_sRGB
	self->_metalLayer.pixelFormat = format ;
	self->_colorPixelFormat = format ;
}

-(MTLPixelFormat) colorPixelFormat
{
	return self->_metalLayer.pixelFormat;
}

@synthesize depthStencilPixelFormat = _depthStencilPixelFormat;

-(void) setDepthStencilPixelFormat:(MTLPixelFormat)format;
{
	self->_depthStencilPixelFormat = format ;
	// TODO change depthStencilTexture
}

-(MTLPixelFormat) depthStencilPixelFormat
{
	return self->_depthStencilPixelFormat;
}

#pragma mark - MetalView的回调 onResize/onDraw -
-(void) _notifyResizeDrawable
{
	if (_metalLayer == nil)
	{
		NSLog(@"[_notifyResizeDrawable] _metalLayer not ready ");
		// 在UIView super init的过程中 会走下面的流程, 多次间接调用本函数
		// setContentScaleFactor::
		// setFrame::
		return ;
	}
	
	CGFloat scale = [UIScreen mainScreen].scale;
	UIWindow* window = self.window;
	UIScreen* screen = window.screen;
	CGFloat nativeScale = screen.nativeScale;
	
	if (window == nil)
	{
		nativeScale = scale ;
	}
	else
	{
		NSLog(@"[_notifyResizeDrawable] UIWindow is not nil");
	}
	
	NSLog(@"[_notifyResizeDrawable] mainScreen'scale %f, UIWindow'screen'scale %f",
		  scale,
		  nativeScale);
	
	
	CGSize drawableSize = self.bounds.size; // 这个单位是point  UIView的尺寸
	drawableSize.width  = drawableSize.width  * nativeScale; // 乘以scale之后才是 像素
	drawableSize.height = drawableSize.height * nativeScale;
	if (drawableSize.width <= 0 || drawableSize.height <= 0)
	{
		NSLog(@"[_notifyResizeDrawable] newSize negative ");
		return;
	}
	
	
	@synchronized (_metalLayer)
	{
		NSLog(@"[_notifyResizeDrawable]  _metalLayer.drawableSize  = (%f, %f) to (%f, %f)",
			  _metalLayer.drawableSize.width,
			  _metalLayer.drawableSize.height,
			  drawableSize.width,
			  drawableSize.height
			   );
		
		_metalLayer.drawableSize = drawableSize;
		
		//
		// [self _resizeDepthTexture];
		//
		// 回调通知
		// [_delegate OnDrawableSizeChange:drawableSize WithView:self];
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
		
		if (self->_delegate == nil)
		{
			// MTKView 内部不会自己上屏 !! 需要_delegate自己调用presentDrawable上屏
			// 必须使用 renderCommandEncoderWithDescriptor 才能让 _currentDrawable.texture load起来得到clear
			id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
			commandBuffer.label = @"OnDrawFrame";
			id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:_currentRenderPassDescriptor];
			encoder.label = @"OnDrawFrameEncoder";
			[encoder endEncoding];
			[commandBuffer presentDrawable:_currentDrawable];
			[commandBuffer commit];
		}
		else
		{
			if ([_texturePool count] != 0)
			{
				_texTextOrder = (++_texTextOrder) % _texturePool.count;
				[self->_delegate setTestTexture:[_texturePool objectAtIndex:_texTextOrder]];
			}
			[self->_delegate OnDrawFrame:_metalLayer WithView:self];
		}
		
		
		_currentDrawable = nil;
		_currentRenderPassDescriptor = nil;
		
	}
}


/*
 MTLTextureUsageShaderRead  这个会给纹理设置属性 access::read and access::sample 在shader中调用 read() or sample()
 MTLTextureUsageShaderWrite 纹理可读可写 access::read_write attribute. 在shader中会调用write()
 MTLTextureUsageRenderTarget 纹理作为render pass中的颜色 深度 模板等目标
 */
// textureDescriptor.usage = MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;

-(void) generateTexture
{
	MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
	
	textureDescriptor.pixelFormat =  MTLPixelFormatBGRA8Unorm_sRGB;
	textureDescriptor.textureType = MTLTextureType2D;
	textureDescriptor.width = _metalLayer.drawableSize.width;
	textureDescriptor.height = _metalLayer.drawableSize.height;
	textureDescriptor.usage = MTLTextureUsageShaderRead;
	textureDescriptor.storageMode = MTLStorageModeShared;
	id<MTLTexture> colorTexture = [self.device newTextureWithDescriptor:textureDescriptor];
	
	[_texturePool addObject:colorTexture];
	
	
	//MTLRegion region =
	//{
	//	{ 0,     0,      0    },
	//	{ textureDescriptor.width, textureDescriptor.height, 0 },
	//};
	
	MTLRegion region = MTLRegionMake2D(0, 0, textureDescriptor.width, textureDescriptor.height);
	NSLog(@"region origin %lu,%lu,%lu size %lu,%lu,%lu",
		  region.origin.x, region.origin.y, region.origin.z,
		  region.size.width, region.size.height, region.size.depth
		  );
	
 
	int* pixelBytes = (int*)malloc(_metalLayer.drawableSize.width * 4 * _metalLayer.drawableSize.height);
	
	uint32_t color = 0xFF0000FF; // blue
	if (_texTextOrder % 3 == 0) {
		  color = 0xFF00FF55;
	} else if (_texTextOrder % 3 == 1) {
		  color = 0xFF5500FF;
	} else if (_texTextOrder % 3 == 2) {
		  color = 0xFFFF0055;
	}
	
	for (int i = 0 ; i < _metalLayer.drawableSize.width * _metalLayer.drawableSize.height; i++)
	{
	
		pixelBytes[i] = color; // A B G R
	}
	
	// storageMode = MTLStorageModePrivate GPU私有 是不能从cpu更新纹理的
	// `CPU access for textures with MTLResourceStorageModePrivate storage mode is disallowed.'
	
	// slice 用于cube或者纹理数组  或者cube纹理数组
	// MTLRegion 包含z坐标和depth 用于3D纹理
	[colorTexture replaceRegion:region
					mipmapLevel:0
						  slice:0
					  withBytes:pixelBytes
					bytesPerRow:textureDescriptor.width * 4
				  bytesPerImage:textureDescriptor.width * textureDescriptor.height * 4];

	free(pixelBytes);
	
	NSLog(@"add %lu %lu in pool size: %lu",
		  (unsigned long)textureDescriptor.width,
		  (unsigned long)textureDescriptor.height,
		  (unsigned long)[_texturePool count] );
	
}

-(void) deleteTexture
{
	if (_texturePool.count > 0)
	{
		[_texturePool removeLastObject];
	}
	NSLog(@"rm one in pool size: %lu", (unsigned long)[_texturePool count]);
}

@end
