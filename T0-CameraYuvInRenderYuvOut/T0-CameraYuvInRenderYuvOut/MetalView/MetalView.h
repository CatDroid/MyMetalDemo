//
//  MetalView.h
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#ifndef MetalView_h
#define MetalView_h

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>


@protocol MetalViewDelegate;


// CALayerDelegate的父协议是 <NSObject>
// CALayerDelegate的实现类有 MTKView UIView
// NS_ASSUME_NONNULL_BEGIN
// NS_ASSUME_NONNULL_END 不用每个指针类型前进都加 nonnull

/*
 * -------------------------------- 类似MTKView类 ----------------------------------
 */
@interface MetalView : UIView <CALayerDelegate>

@property (nonatomic, readonly, strong, nonnull) CAMetalLayer* metalLayer ;


@property (nonatomic, readwrite, weak,  nullable) id<MetalViewDelegate> delegate ;
@property (nonatomic, readwrite, strong, nonnull) id<MTLDevice> device;

@property (nonatomic, readonly, nullable) id <CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly, nullable) MTLRenderPassDescriptor *currentRenderPassDescriptor;

@property (nonatomic) MTLPixelFormat colorPixelFormat;
//@property (nonatomic) MTLPixelFormat depthStencilPixelFormat;
//@property (nonatomic) NSUInteger    sampleCount;


@property (nonatomic) MTLClearColor clearColor; // (0.0, 0.0, 0.0, 1.0)
//@property (nonatomic) double   clearDepth;   // 1.0
//@property (nonatomic) uint32_t clearStencil; // 0.0
//@property (nonatomic, readonly, nullable) id <MTLTexture> depthStencilTexture; // nil


-(nonnull instancetype) init NS_UNAVAILABLE;
-(nonnull instancetype) initWithCoder:(nonnull NSCoder *)coder;
-(nonnull instancetype) initWithFrame:(CGRect)frame;


@end



/*
 * -------------------------------- 类似MTKViewDelegate代理 ----------------------------------
 */
@protocol MetalViewDelegate <NSObject>

-(void) OnDrawableSizeChange:(CGSize)size WithView:(nonnull MetalView*)  view;

-(void) OnDrawFrame:(nonnull CAMetalLayer*) layer WithView:(nonnull MetalView*) view;

@end


#endif /* MetalView_h */
