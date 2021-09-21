//
//  QuadRender.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/26.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalFrameBuffer.h"
#import "QuadMesh.h"

NS_ASSUME_NONNULL_BEGIN

@interface QuadRender : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) initWithDevice:(id<MTLDevice>) gpu WithSize:(CGSize)size NS_DESIGNATED_INITIALIZER;


-(void) sizeChangedOnUIThread:(CGSize) size;

-(BOOL) renderOnFrameBuffer:(MetalFrameBuffer*) framebuffer
            OnCommandBuffer:(id<MTLCommandBuffer>) buffer
           WithInputTexture:(nullable id<MTLTexture>) input
                   WithMesh:(nullable QuadMesh*) mesh ;

-(BOOL) renderOnPass:(MTLRenderPassDescriptor*) renderPass
     OnCommandBuffer:(id<MTLCommandBuffer>) buffer
    WithInputTexture:(nullable id<MTLTexture>) input
            WithMesh:(nullable QuadMesh*) mesh;


@end

NS_ASSUME_NONNULL_END
