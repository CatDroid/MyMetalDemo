//
//  BackedCVPixelBufferMetalRecoder.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/27.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h> // CGSize

NS_ASSUME_NONNULL_BEGIN

@interface BackedCVPixelBufferMetalRecoder : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) init:(CGSize) size WithDevice:(id<MTLDevice>)device  NS_DESIGNATED_INITIALIZER;
-(void) startRecording;
-(void) endRecording;
-(void) drawToRecorder:(id<MTLTexture>) texture  OnCommand:(id<MTLCommandBuffer>) command;

-(void) dealloc;



@end

NS_ASSUME_NONNULL_END
