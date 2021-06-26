//
//  MetalVideoRecorder.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h> // CGSize
#import <QuartzCore/CoreAnimation.h> // CAMetalDrawable


NS_ASSUME_NONNULL_BEGIN

@interface MetalVideoRecorder : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) init:(CGSize) size;
-(void) dealloc;

-(void) startRecording;
-(void) endRecording;
-(void) writeFrame:(id<MTLTexture>) texture  OnCommand:(id<MTLCommandBuffer>) command;

@end

NS_ASSUME_NONNULL_END
