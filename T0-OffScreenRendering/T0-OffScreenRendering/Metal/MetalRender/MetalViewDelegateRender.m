//
//  MTKViewDelegateRender.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "MetalViewDelegateRender.h"
#import <Metal/Metal.h>

#import "MetalView.h"

#import "MetalFrameBuffer.h"

#import "ScreenRender.h"
#import "ParallelTriangleRender.h"

@implementation MetalViewDelegateRender
{
    id <MTLCommandQueue> _commandQueue ;
    
    MetalFrameBuffer* _offscreenFramebuffer ;
    
    ScreenRender* _onscreenRender ;
    ParallelTriangleRender* _triangleRender ;
    
}

#pragma mark - Constructor

-(nonnull instancetype) initWithMetalView:(MetalView *) view
{
    self = [super init];
    if (self) {
        [self _setupContext:view];
        [self _setupRender:view.device WithView:view];
    } else {
        NSLog(@"initWithMetalKitView super init fail");
    }
    return self ;
}

- (void) _setupContext:(MetalView*) view
{
    // view 需要提供的 如下格式的 颜色纹理/深度纹理/模版纹理
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB ;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ; // MetalView会创建对应纹理
    // view.depthStencilPixelFormat = MTLPixelFormatInvalid;

    view.sampleCount = 1 ;
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);

    // 使用设备上下文创建了全局唯一的指令队列对象
    id<MTLDevice> gpu = view.device;
    _commandQueue = [gpu newCommandQueue];

}

-(void) _setupRender:(id<MTLDevice>) gpu WithView:(MetalView*)view
{
    _onscreenRender = [[ScreenRender alloc] initWithDevice:gpu WithView:view];
    _triangleRender = [[ParallelTriangleRender alloc] initWithDevice:gpu];
    _offscreenFramebuffer = [[MetalFrameBuffer alloc] initWithDevice:gpu WithSize:view.metalLayer.drawableSize];
}


//- (void) drawInMTKView:(nonnull MTKView *)view
-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MetalView*) view
{
         
    MTLRenderPassDescriptor* framebuffer = view.currentRenderPassDescriptor;
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"OnDrawFrame";
    
    // 整个渲染只有一个commandbuffer, 但是有多个encoder：一个并行encoder(可以有两个子encoder单独编码) 一个普通 encoder(可以有多个draw)

    [_triangleRender renderOnFrameBuffer:_offscreenFramebuffer
                         OnCommandBuffer:commandBuffer
                        WithInputTexture:nil
                                WithMesh:nil ];
    
   
    [_onscreenRender renderOnPass:framebuffer
                  OnCommandBuffer:commandBuffer
                 WithInputTexture:_offscreenFramebuffer.renderPassDescriptor.colorAttachments[0].texture
                         WithMesh:nil];
    
    
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
    
}



// - (void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
-(void) OnDrawableSizeChange:(CGSize)size WithView:(MetalView*) view
{
    NSLog(@"View Size Change To %f,%f", size.width, size.height);
}

@end
