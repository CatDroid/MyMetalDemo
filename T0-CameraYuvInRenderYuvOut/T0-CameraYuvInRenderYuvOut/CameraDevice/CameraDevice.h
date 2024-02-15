//
//  CameraDevice.h
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#ifndef CameraDevice_h
#define CameraDevice_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>


NS_ASSUME_NONNULL_BEGIN

// 提前声明协议
@protocol CameraMetalFrameDelegate ;

@interface CameraDevice : NSObject

-(instancetype) init ;

-(BOOL) checkPermission;

-(BOOL) openCamera:(id<MTLDevice>) device;

-(void) setFrameRate:(float) frameRate;

-(BOOL) closeCamera;

-(void) dealloc;


@property (nonatomic,weak) id<CameraMetalFrameDelegate>  delegate ;

@end


@protocol CameraMetalFrameDelegate <NSObject>

@required
-(void) onPreviewFrame:(CVPixelBufferRef) ref;

@end

NS_ASSUME_NONNULL_END


#endif /* CameraDevice_h */
