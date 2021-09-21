//
//  RecordRender.h
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/28.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface RecordRender : NSObject

-(instancetype) init NS_UNAVAILABLE ;

-(nonnull instancetype) initWithDevice: (nonnull id <MTLDevice>) device NS_DESIGNATED_INITIALIZER;

// 类似 MetalPerformanceShaders @ MPSImageKernel.h 的接口设计
-(void) encodeToCommandBuffer: (nonnull id <MTLCommandBuffer>) commandBuffer
                sourceTexture: (nonnull id <MTLTexture>) sourceTexture
           destinationTexture: (nonnull id <MTLTexture>) destinationTexture ;



@end

NS_ASSUME_NONNULL_END
