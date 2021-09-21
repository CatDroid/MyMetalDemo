//
//  MetalView.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

// CALayerDelegate的父协议是 <NSObject>
// CALayerDelegate的实现类有 MTKView UIView
// NSObject 有一个是类NSObject，一个是协议<NSObject>

@protocol MetalViewDelegate; // 不能是提前 @interface MetalView

@interface MetalView : UIView <CALayerDelegate>
{
 
}

@property (nonatomic, readonly, strong, nonnull) CAMetalLayer* metalLayer ; // 不应该作为属性 ??

/*
 * -------------------------------- 类似MTKView导出的属性 ----------------------------------
 */
 
@property (nonatomic, readwrite, weak,  nullable) id<MetalViewDelegate> delegate ;
@property (nonatomic, readwrite, strong, nonnull) id<MTLDevice> device;

@property (nonatomic, readonly, nullable) id <CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly, nullable) MTLRenderPassDescriptor *currentRenderPassDescriptor;

/*
    drawable's texture的pixelformat
 */
@property (nonatomic) MTLPixelFormat colorPixelFormat;

/*
    用来创建 depthStencilTexture
 */
@property (nonatomic) MTLPixelFormat depthStencilPixelFormat;

/*
    用来创建 multisampleColorTexture
    大于1的话 a multisampled color texture 会被创建
    
    currentDrawable's texture 会被设置为 currentRenderPassDescriptor.resolve texture
    
    store action 会被设置为 MTLStoreActionMultisampleResolve
    
 */
@property (nonatomic) NSUInteger    sampleCount; // 暂时没有实现

/*
 下面的属性 用来创建 MTLRenderPassDescriptor
 depthStencilTexture 只读的，只会在 depthStencilPixelFormat不是 MTLPixelFormatInvalid 才返回非nil
 */
@property (nonatomic) MTLClearColor clearColor; // (0.0, 0.0, 0.0, 1.0)
@property (nonatomic) double clearDepth; // 1.0
@property (nonatomic) uint32_t clearStencil; // 0.0
@property (nonatomic, readonly, nullable) id <MTLTexture> depthStencilTexture; // nil


/*
 渲染控制相关
 */
// Controls whether the view responds to setNeedsDisplay.
// Setting enableSetNeedsDisplay to true will also pause the MTKView's internal render loop and updates will instead be event driven.
// The default value is false.

@property (nonatomic) BOOL enableSetNeedsDisplay;

// If NO,
// the delegate will receive drawInMTKView: messages or the subclass will receive drawRect: messages
// at a rate of preferredFramesPerSecond based on an internal timer.
// The default value is false.
// paused = NO   enableSetNeedsDisplay = NO  渲染由内部的定时器驱动 (默认模式)
// paused = YES  enableSetNeedsDisplay = NO  这个由主动调用MTKView 的draw方法
// paused = YES  enableSetNeedsDisplay = YES 由view的渲染通知驱动，比如调用setNeedsDisplay
@property (nonatomic, getter=isPaused) BOOL paused;




/*
 * -------------------------------- 类似MTKView导出的方法 ----------------------------------
 */
-(instancetype) init NS_UNAVAILABLE;
-(instancetype) initWithCoder:(NSCoder *)coder; // 也可以不在这里声明 直接 @implementation 中定义
-(instancetype) initWithFrame:(CGRect)frame;



@end


/*
 * -------------------------------- 类似MTKViewDelegate代理 ----------------------------------
 */

@protocol MetalViewDelegate <NSObject>

-(void) OnDrawableSizeChange:(CGSize)size WithView:(MetalView*) view;

-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MetalView*) view;

@end


NS_ASSUME_NONNULL_END
