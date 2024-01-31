//
//  MTKViewDelegateRender.m
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import "MetalViewDelegateRender.h"

#import <Metal/Metal.h>
#import <os/lock.h>

#include <queue>

#import "MetalView.h"

#import "MetalFrameBuffer.h"

#import "ScreenRender.h"
#import "CameraRender.h"
#import "TextureRender.h"
#import "MetalCameraDevice.h"

#import "BackedCVPixelBufferMetalRecoder.h"
#import "CVPixelBufferPoolReader.h"

#define SIMPLE_PIXEL_BUFFER 1

static int kMtlTextureQueueSize = 5;

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
    TextureRender* _textureRender ;
    
#if SIMPLE_PIXEL_BUFFER
	CVPixelBufferPoolReader* recorder ;
#else
    BackedCVPixelBufferMetalRecoder* recorder ;
#endif
	
	
    CGSize _drawableSize ;
    
    //id<MTLTexture> _readyCameraTexture;
    // 验证 MTLTexture不会 增加对IOSurface的使用计数
    NSMutableArray* _mtlTextureQueue ;
    std::queue<CVMetalTextureRef> _mtlTextureRefQueue;

    
    os_unfair_lock spinLock;
    
    // 统计
    int frameCount;
    UInt64 lastTime;
    

    
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
    
    frameCount = -1;
    lastTime = 0;
    _mtlTextureQueue = [[NSMutableArray alloc] init];
    
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
    _textureRender = [[TextureRender alloc] initWithDevice:gpu];
    
}

static UInt64 getTime()
{
    UInt64 timestamp = [[NSDate date] timeIntervalSince1970]*1000;
    return timestamp;
}

// !!! 摄像头和渲染是两个单独的线程 !!!

//- (void) drawInMTKView:(nonnull MTKView *)view
-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MetalView*) view
{
    id<MTLTexture> cameraTexture = nil;
    CVMetalTextureRef ref = NULL;
    os_unfair_lock_lock(&spinLock);
    
    assert([_mtlTextureQueue count] == _mtlTextureRefQueue.size());
    
    if ([_mtlTextureQueue count] > 0) {
        cameraTexture = [_mtlTextureQueue objectAtIndex:0];
        [_mtlTextureQueue removeObjectAtIndex:0];
    }
    if (!_mtlTextureRefQueue.empty()) {
        ref = _mtlTextureRefQueue.front();
        _mtlTextureRefQueue.pop();
    }
    os_unfair_lock_unlock(&spinLock);
    if (cameraTexture == NULL) {
        // NSLog(@"skip cameraTexture is null on render thread");
        // 如果没有摄像头过来的metal纹理 这里打印 
        return ;
    }
    
    // 帧率统计  ------
    // MetalView.m 中 _displayLink.preferredFramesPerSecond 可以控制回显的帧率
    if (frameCount == -1) {
        lastTime   = getTime();
        frameCount = 0;
    } else {
        frameCount++;
        if (frameCount >= 180) {
           
            UInt64 now = getTime();
            UInt64 duration = now - lastTime;
            NSLog(@"render/view fps = %f", frameCount * 1000.0f / duration);
            frameCount = 0 ;
            lastTime = getTime();
        }
    }
    // --------------
    
    //[NSThread sleepForTimeInterval:0.05];
    
    
    // 整个渲染只有一个commandbuffer, 但是有多个encoder：一个并行encoder(可以有两个子encoder单独编码) 一个普通 encoder(可以有多个draw)
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"OnDrawFrame";
    // 摄像头 离屏渲染到一个framebuffer
    
    [_cameraRender encodeToCommandBuffer:commandBuffer  // 先把三角形画到输入的MTLTexture上, 再画到离屏的texture上(_offscreenFramebuffer)
                           sourceTexture:cameraTexture  // 这个输入的MTLTexture是相机输出的CVPixelBuffer-Based MTLTexture
                      destinationTexture:_offscreenFramebuffer.renderPassDescriptor.colorAttachments[0].texture];
    
 
    
    [_textureRender encodeToCommandBuffer:commandBuffer
                            sourceTexture:nil
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
    
#if KEEP_CV_METAL_TEXTURE_REF_UNTIL_GPU_FINISED  
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
        IOSurfaceRef s_ref = cameraTexture.iosurface ;
        int useCount = IOSurfaceGetUseCount(s_ref);
        //NSLog(@"addCompletedHandler CVMetalTextureRef(ref count=%d) with backend IOSurface(use count=%d)", CFGetRetainCount(ref), useCount);
        // CVMetalTextureRef(ref count=1) with backend IOSurface(use count=1) 都是1, 也就是CVMetalTextureRef释放之后IOSurface就会换回去
        CVBufferRelease(ref);
        // 按照官网wiki, GPU使用完成之后, 才释放 CVMetalTextureRef
        // 这种情况 摄像头帧率高 渲染/上屏帧率低 就会出现drop frame了;
        // 如果直接在生成 id<MTLTexture> 之后就直接释放CVMetalTextureRef 就不会drop frame, 而且画面会跳帧
    }];
#endif
 
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
        
#if SIMPLE_PIXEL_BUFFER
		recorder = [[CVPixelBufferPoolReader alloc] init:_drawableSize WithDevice: _globalDevice];
#else
		recorder = [[BackedCVPixelBufferMetalRecoder alloc] init:_drawableSize WithDevice: _globalDevice];
#endif
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
 

-(void) onPreviewFrame:(id<MTLTexture>)texture WithCV:(CV_METAL_TEXTURE_REF) ref WithSize:(CGSize) size
{
    CVMetalTextureRef ref2 = (CVMetalTextureRef)ref; // void* -> CVMetalTextureRef(struct CVBuffer*)
    
    // 摄像头来一帧 先cache 然后渲染线程再处理
    os_unfair_lock_lock(&spinLock);
    //_readyCameraTexture = texture ;
    if ([_mtlTextureQueue count] < kMtlTextureQueueSize)
    {
        [_mtlTextureQueue addObject:texture];
        _mtlTextureRefQueue.push(ref2);
    } // 太多丢弃
    os_unfair_lock_unlock(&spinLock);
}

@end
