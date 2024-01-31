//
//  TextureRender.h
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2024/1/31.
//

#ifndef TextureRender_h
#define TextureRender_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface TextureRender : NSObject

-(instancetype) init NS_UNAVAILABLE ;
-(nonnull instancetype) initWithDevice: (nonnull id <MTLDevice>) device NS_DESIGNATED_INITIALIZER;
-(void) encodeToCommandBuffer: (nonnull id <MTLCommandBuffer>) commandBuffer
                sourceTexture: (nullable id <MTLTexture>) _no_in_used
           destinationTexture: (nonnull id <MTLTexture>) destinationTexture ;

@end


#endif /* TextureRender_h */
