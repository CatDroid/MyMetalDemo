//
//  ScreenRender.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/24.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#import "MetalFrameBuffer.h"
#import "ScreenMesh.h"
#import "MetalView.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScreenRender : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) initWithDevice:(id<MTLDevice>) gpu WithView:(MetalView*)view NS_DESIGNATED_INITIALIZER;


-(BOOL) renderOnFrameBuffer:(MetalFrameBuffer*) framebuffer
            OnCommandBuffer:(id<MTLCommandBuffer>) buffer
           WithInputTexture:(id<MTLTexture>) input
                   WithMesh:(nullable ScreenMesh*) mesh ;

-(BOOL) renderOnPass:(MTLRenderPassDescriptor*) renderPass
     OnCommandBuffer:(id<MTLCommandBuffer>) buffer
    WithInputTexture:(id<MTLTexture>) input
            WithMesh:(nullable ScreenMesh*) mesh;

@end

NS_ASSUME_NONNULL_END
