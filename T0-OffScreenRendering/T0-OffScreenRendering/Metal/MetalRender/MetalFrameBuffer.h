//
//  MetalFrameBuffer.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h> // CGSize

NS_ASSUME_NONNULL_BEGIN

@interface MetalFrameBuffer : NSObject

-(instancetype) init NS_UNAVAILABLE ;

-(instancetype) initWithDevice:(id<MTLDevice>)gpu WithSize:(CGSize)size  NS_DESIGNATED_INITIALIZER ; // 指定构造函数

-(void) firstDrawOnEncoder ;

-(void) keepDrawOnAnotherEncoder ;

-(void) lastDrawEncoder ;

@property (strong, nonnull, nonatomic, readonly) MTLRenderPassDescriptor* renderPassDescriptor;

@end

NS_ASSUME_NONNULL_END
