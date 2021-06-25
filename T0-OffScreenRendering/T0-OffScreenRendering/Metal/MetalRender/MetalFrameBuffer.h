//
//  MetalFrameBuffer.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h> // CGSize

NS_ASSUME_NONNULL_BEGIN

@interface MetalFrameBuffer : NSObject

-(instancetype) init NS_UNAVAILABLE ;

-(instancetype) initWithDevice:(id<MTLDevice>)gpu WithSize:(CGSize)size  NS_DESIGNATED_INITIALIZER ; // 指定构造函数

@property (strong, nonnull, nonatomic, readonly) MTLRenderPassDescriptor* renderPassDescriptor;

@end

NS_ASSUME_NONNULL_END
