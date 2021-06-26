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

#import "ParallelTriangleRender.h"
#import "ScreenRender.h"
#import "QuadRender.h"

#import "MetalVideoRecorder.h"


@implementation MetalViewDelegateRender
{
    id <MTLCommandQueue> _commandQueue ;
    
 
    MetalFrameBuffer* _offscreenFramebuffer ;
    
    QuadRender* _quadRender ;
    ScreenRender* _onscreenRender ;
    ParallelTriangleRender* _triangleRender ;
    
    MetalVideoRecorder* recorder ;
    
    CGSize _drawableSize ;
    
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
    
    _drawableSize = view.metalLayer.drawableSize ;

    // 使用设备上下文创建了全局唯一的指令队列对象
    id<MTLDevice> gpu = view.device;
    _commandQueue = [gpu newCommandQueue];

}

-(void) _setupRender:(id<MTLDevice>) gpu WithView:(MetalView*)view
{
    CGSize drawableSize = view.metalLayer.drawableSize;
    
    _onscreenRender = [[ScreenRender alloc] initWithDevice:gpu WithView:view];
    
    _triangleRender = [[ParallelTriangleRender alloc] initWithDevice:gpu];
    _offscreenFramebuffer = [[MetalFrameBuffer alloc] initWithDevice:gpu WithSize:drawableSize];
    
    _quadRender = [[QuadRender alloc] initWithDevice:gpu WithSize:drawableSize];
   
    //recorder = [[MetalVideoRecorder alloc] init:_drawableSize];
    //[recorder startRecording];
}


//- (void) drawInMTKView:(nonnull MTKView *)view
-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MetalView*) view
{
         
    
    
    // 整个渲染只有一个commandbuffer, 但是有多个encoder：一个并行encoder(可以有两个子encoder单独编码) 一个普通 encoder(可以有多个draw)
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"OnDrawFrame";
    
    
    [_offscreenFramebuffer firstDrawOnEncoder];
  
    [_quadRender renderOnFrameBuffer:_offscreenFramebuffer
                     OnCommandBuffer:commandBuffer
                    WithInputTexture:nil
                            WithMesh:nil ];
    
    // 两个encoder都会重新加载framebuffer 并调用clear, 并且由于上一个深度buffer没有store 会导致不会影响后面这个encoder
    // 这里比较难看 就是重写了内部的LoadAction
    // 如果这里不重新load 颜色/深度/模板 附件。那么会出现严重的锯齿
    [_offscreenFramebuffer lastDrawEncoder];
    
    [_triangleRender renderOnFrameBuffer:_offscreenFramebuffer
                         OnCommandBuffer:commandBuffer
                        WithInputTexture:nil
                                WithMesh:nil ];
    
   
    // 上屏
    MTLRenderPassDescriptor* framebuffer = view.currentRenderPassDescriptor;
    [_onscreenRender renderOnPass:framebuffer
                  OnCommandBuffer:commandBuffer
                 WithInputTexture:_offscreenFramebuffer.renderPassDescriptor.colorAttachments[0].texture
                         WithMesh:nil];
    
    if (recorder)
    {
        [recorder writeFrame:view.currentDrawable.texture OnCommand:commandBuffer];
    }
    
    [commandBuffer presentDrawable:view.currentDrawable];
    // That present call is merely telling Metal to schedule a call to present your frame to the screen once the GPU has finished rendering.
    // 当前调用只是告诉Metal在GPU完成渲染后 调用一下把这这帧 呈现到屏幕上
    [commandBuffer commit];
    
}



// - (void) mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
-(void) OnDrawableSizeChange:(CGSize)size WithView:(MetalView*) view
{
    NSLog(@"View Size Change To %f,%f", size.width, size.height);
    _drawableSize = size ;
    // TODO
}


-(void) switchRecord
{
    if (recorder == nil)
    {
        recorder = [[MetalVideoRecorder alloc] init:_drawableSize];
        [recorder startRecording];
    }
    else
    {
        [recorder endRecording];
        recorder = nil;
    }
}

@end
