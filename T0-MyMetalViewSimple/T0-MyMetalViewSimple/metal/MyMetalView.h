//
//  MyMetalView.h
//  T0-MyMetalViewSimple
//
//  Created by hehanlong on 2021/9/23.
//

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MetalViewDelegate; // 不能提前@interface 但是可以@protocol

// MTKView
@interface MyMetalView : UIView
{
	
}

-(instancetype) init ;
-(instancetype) initWithFrame:(CGRect)frame;
-(instancetype) initWithCoder:(NSCoder *)coder;


@property (nonatomic, readonly, strong, nonnull) CAMetalLayer* metalLayer ; // 不应该作为属性 ??


/*
 * -------------------------------- 类似MTKView导出的属性 ----------------------------------
 */
@property (nonatomic, readwrite, strong, nonnull) id<MTLDevice> device;
@property (nonatomic, readwrite, weak,  nullable) id<MetalViewDelegate> delegate ;


// MyMetalView当前的回调delegate时候的状态
@property (nonatomic, readonly, nullable) id <CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly, nullable) MTLRenderPassDescriptor *currentRenderPassDescriptor;


// 用来创建 color texture
@property (nonatomic) MTLPixelFormat colorPixelFormat;

// 用来创建 depthStencilTexture

@property (nonatomic) MTLPixelFormat depthStencilPixelFormat;

// 用来创建 multisampleColorTexture   TODO(hhl)大于1的话 a multisampled color texture 会被创建
// TODO(hhl) currentDrawable's texture 会被设置为 currentRenderPassDescriptor.resolve texture
// TODO(hhl) store action 会被设置为 MTLStoreActionMultisampleResolve
@property (nonatomic) NSUInteger    sampleCount; // 暂时没有实现

// 下面的属性 用来创建 MTLRenderPassDescriptor
@property (nonatomic) MTLClearColor clearColor; // (1.0, 1.0, 0.0, 1.0)
@property (nonatomic) double clearDepth; // 1.0
@property (nonatomic) uint32_t clearStencil; // 0.0

// depthStencilTexture 只读的，只会在 depthStencilPixelFormat不是 MTLPixelFormatInvalid 才返回非nil
@property (nonatomic, readonly, nullable) id <MTLTexture> depthStencilTexture; // nil


// 测试metal、openg分配纹理内存占用
-(void) generateTexture;
-(void) deleteTexture;

@end


// 仿照 @protocol MTKViewDelegate 提供两个接口 一个是draw 一个是resize
@protocol MetalViewDelegate <NSObject>

-(void) OnDrawableSizeChange:(CGSize)size WithView:(MyMetalView*) view;

-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MyMetalView*) view;

-(void) setTestTexture:(id<MTLTexture>) tex;

@end


NS_ASSUME_NONNULL_END
