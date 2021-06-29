//
//  CameraDevice.h
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/28.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CameraMetalFrameDelegate ; // 提前声明

@interface MetalCameraDevice : NSObject

-(instancetype) init ;

-(BOOL) checkPermission;

-(BOOL) openCamera:(id<MTLDevice>) device;

-(void) setFrameRate:(float) frameRate;

-(BOOL) closeCamera;

-(void) dealloc;

// @property (nonatomic, unsafe_unretained) id delegate;
// Property with 'weak' attribute must be of object type
//@property (nonatomic,weak) CameraFrameDelegate* delegate ;
@property (nonatomic,weak) id<CameraMetalFrameDelegate>  delegate ; // 返回metal纹理

@end


@protocol CameraMetalFrameDelegate <NSObject>

@required
-(void) onPreviewFrame:(id<MTLTexture>)texture WithSize:(CGSize) size;

@end

NS_ASSUME_NONNULL_END
