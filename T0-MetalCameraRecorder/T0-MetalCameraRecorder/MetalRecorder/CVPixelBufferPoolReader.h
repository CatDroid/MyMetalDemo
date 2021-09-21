//
//  CVPixelBufferPoolReader.h
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/8/26.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CGGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@interface CVPixelBufferPoolReader : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) init:(CGSize) size WithDevice:(id<MTLDevice>)device  NS_DESIGNATED_INITIALIZER;
-(void) startRecording;
-(void) endRecording;
-(void) drawToRecorder:(id<MTLTexture>) texture  OnCommand:(id<MTLCommandBuffer>) command;

-(void) dealloc;


@end

NS_ASSUME_NONNULL_END
