//
//  ParallelTriangleRender.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#import "MetalFrameBuffer.h"
#import "ParallelTriangleMesh.h"

NS_ASSUME_NONNULL_BEGIN

@interface ParallelTriangleRender : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) initWithDevice:(id<MTLDevice>) gpu NS_DESIGNATED_INITIALIZER;

-(BOOL) renderOnFrameBuffer:(MetalFrameBuffer*) framebuffer
            OnCommandBuffer:(id<MTLCommandBuffer>) buffer
           WithInputTexture:(nullable id<MTLTexture>) input
                   WithMesh:(nullable ParallelTriangleMesh*) mesh ;

-(BOOL) renderOnPass:(MTLRenderPassDescriptor*) renderPass
     OnCommandBuffer:(id<MTLCommandBuffer>) buffer
    WithInputTexture:(nullable id<MTLTexture>) input
            WithMesh:(nullable ParallelTriangleMesh*) mesh;

@end

NS_ASSUME_NONNULL_END
