//
//  MTKViewDelegateRender.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "MetalViewDelegateRender.h"

#import <Metal/Metal.h>
#import <os/lock.h>

#import "MetalView.h"

#import "MetalFrameBuffer.h"

#import "ScreenRender.h"
#import "CameraRender.h"
#import "MetalCameraDevice.h"

#import "BackedCVPixelBufferMetalRecoder.h"

// 匿名分类 类扩展 不想外面知道内部实现的协议
@interface MetalViewDelegateRender() <CameraMetalFrameDelegate>

@end


@implementation MetalViewDelegateRender
{
    id<MTLDevice> _globalDevice ;
     
    id <MTLCommandQueue> _commandQueue ;
    
    MetalFrameBuffer* _offscreenFramebuffer ;
    
    MetalCameraDevice* _cameraDevice ;
    CameraRender* _cameraRender ;
    ScreenRender* _onscreenRender ;
    
    BackedCVPixelBufferMetalRecoder* recorder ;
    
    CGSize _drawableSize ;
    
    id<MTLTexture> _readyCameraTexture;
    
    os_unfair_lock spinLock;
    
}

#pragma mark - Constructor

/*
 
 用AVFoundation采集摄像头数据得到CMSampleBufferRef
 用CoreVideo提供的方法将图像数据CMSampleBufferRef 转为 Metal的纹理
 再用MetalPerformanceShaders的高斯模糊滤镜对图像进行处理，结果展示到屏幕上

  
 */
-(nonnull instancetype) initWithMetalView:(MetalView *) view
{
    self = [super init];
    if (self)
    {
        spinLock = OS_UNFAIR_LOCK_INIT;
        
        _globalDevice = view.device;
        [self _setupContext:view];
        [self _setupRender:view.device WithView:view];
    }
    else
    {
        NSLog(@"initWithMetalKitView super init fail");
    }
    return self ;
}

- (void) _setupContext:(MetalView*) view
{
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB ;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8 ;
    view.sampleCount = 1 ;
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
    
    _drawableSize = view.metalLayer.drawableSize ;

    _commandQueue = [_globalDevice newCommandQueue];
}


-(void) _setupRender:(id<MTLDevice>) gpu WithView:(MetalView*)view
{
    _onscreenRender = [[ScreenRender alloc] initWithDevice:gpu WithView:view];
    _cameraRender = [[CameraRender alloc] initWithDevice:gpu];
    _offscreenFramebuffer = [[MetalFrameBuffer alloc] initWithDevice:gpu WithSize:_drawableSize];
    
}

// !!! 摄像头和渲染是两个单独的线程 !!!

//- (void) drawInMTKView:(nonnull MTKView *)view
-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MetalView*) view
{
    id<MTLTexture> cameraTexture = nil;
    os_unfair_lock_lock(&spinLock);
    cameraTexture = _readyCameraTexture;
    _readyCameraTexture = nil;
    os_unfair_lock_unlock(&spinLock);
    
    if (cameraTexture == nil)
    {
        // !! 没有调用 commandbuffer.presentDrawable 应该不会上屏
        //NSLog(@"render lost frame");
        return ;
    }

    //[NSThread sleepForTimeInterval:0.05];
    
    
    // 整个渲染只有一个commandbuffer, 但是有多个encoder：一个并行encoder(可以有两个子encoder单独编码) 一个普通 encoder(可以有多个draw)
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"OnDrawFrame";
    // 摄像头 离屏渲染到一个framebuffer
    
    [_cameraRender encodeToCommandBuffer:commandBuffer
                           sourceTexture:cameraTexture
                      destinationTexture:_offscreenFramebuffer.renderPassDescriptor.colorAttachments[0].texture];
    

    // 上屏
    MTLRenderPassDescriptor* framebuffer = view.currentRenderPassDescriptor;
    [_onscreenRender renderOnPass:framebuffer
                  OnCommandBuffer:commandBuffer
                 WithInputTexture:_offscreenFramebuffer.renderPassDescriptor.colorAttachments[0].texture
                         WithMesh:nil];
    
    // 录制
    if (recorder)
    {
        [recorder drawToRecorder:_offscreenFramebuffer.renderPassDescriptor.colorAttachments[0].texture
                       OnCommand:commandBuffer ];
    }
    
 
    [commandBuffer presentDrawable:view.currentDrawable];
 
    [commandBuffer commit];
    

    
    // 如果GPU没有来得及渲染这一帧 然后CPU下一帧又来，修改uniformbuffer会怎么样?
    // 这个文章使用ring buffer 由3个缓冲 通过信号量来同步 并注册command buffer的完成回调 commandBuffer addCompletedHandler
    // https://developer.apple.com/library/archive/samplecode/MetalVideoCapture/Listings/MetalVideoCapture_AAPLRenderer_mm.html#//apple_ref/doc/uid/TP40015131-MetalVideoCapture_AAPLRenderer_mm-DontLinkElementID_8
    //

    // NSLog(@"draw done  %p", cameraTexture);
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
        recorder = [[BackedCVPixelBufferMetalRecoder alloc] init:_drawableSize WithDevice: _globalDevice];
        [recorder startRecording];
    }
    else
    {
        [recorder endRecording];
        recorder = nil;
    }
}

-(BOOL) switchCamera
{
    if (_cameraDevice == nil)
    {
        _cameraDevice = [[MetalCameraDevice alloc] init];
        
        BOOL result = [_cameraDevice checkPermission];
        if (!result)
        {
            _cameraDevice = nil;
            return false ;
        }
        _cameraDevice.delegate = self ;
        [_cameraDevice openCamera:_globalDevice];
        // [_cameraDevice setFrameRate:5.0f];
        
        // 用来查找内存泄漏
        // Leaks和Memory Graph都可以
        // debug 要勾选 dwarf with dsym 
    }
    else
    {
        [_cameraDevice closeCamera];
        _cameraDevice = nil;
    }
    return true ;
}
 

-(void) onPreviewFrame:(id<MTLTexture>)texture WithSize:(CGSize) size
{
    // 摄像头来一帧 先cache 然后渲染线程再处理
    os_unfair_lock_lock(&spinLock);
    _readyCameraTexture = texture ;
    os_unfair_lock_unlock(&spinLock);
}

@end
