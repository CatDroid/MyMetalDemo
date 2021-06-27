//
//  MetalVideoRecorder.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import "MetalVideoRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>

@interface MetalVideoRecorder ()

@property (atomic) BOOL isRecording ;

@end

@implementation MetalVideoRecorder
{
    AVAssetWriter* assetWriter ;
    AVAssetWriterInput* assetWriterVideoInput ;
    AVAssetWriterInputPixelBufferAdaptor* assetWriterPixelBufferInput;
    NSTimeInterval recordingStartTime ;
}

-(instancetype) init:(CGSize) size
{
    self = [super init];
    
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* path = paths.firstObject;
    path = [path stringByAppendingPathComponent:@"test.mp4"];
    
    NSFileManager *fm=[NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path])
    {
        NSLog(@"remove old file");
        [fm removeItemAtPath:path error:nil];
    }
  

    NSURL* url = [[NSURL alloc] initFileURLWithPath:path];
    NSLog(@"url is %@", url);
    
    NSError* error ;
    assetWriter = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&error];
 
    NSAssert(assetWriter != nil, @"AVAssetWriter create fail %@", error);
    
    NSDictionary* outputSettings = @{
        AVVideoCodecKey:AVVideoCodecTypeH264,
        AVVideoWidthKey: @(size.width),
        AVVideoHeightKey: @(size.height),
    };
    
    assetWriterVideoInput = [[AVAssetWriterInput alloc]initWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    assetWriterVideoInput.expectsMediaDataInRealTime = true ;
    
    
    NSDictionary* attributes = @{
                               (__bridge NSString*)(kCVPixelBufferPixelFormatTypeKey):@(kCVPixelFormatType_32BGRA), // 为什么这么喜欢BGRA
                               (__bridge NSString*)(kCVPixelBufferWidthKey):@(size.width),
                               (__bridge NSString*)(kCVPixelBufferHeightKey):@(size.height),
    };
    
    assetWriterPixelBufferInput = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:assetWriterVideoInput sourcePixelBufferAttributes:attributes];
    
    [assetWriter addInput:assetWriterVideoInput];
    
    
    return self ;
}

-(void) startRecording
{
    if (self.isRecording)
    {
        NSLog(@"recording twice");
        return  ;
    }
    [assetWriter startWriting];
    [assetWriter startSessionAtSourceTime:kCMTimeZero];
    recordingStartTime = CACurrentMediaTime();
    self.isRecording = true ;
}

-(void) endRecording
{
    if (!self.isRecording)
    {
        NSLog(@"recording stopped y");
        return  ;
    }
    self.isRecording = false ;
    [assetWriterVideoInput markAsFinished]; // 视频编码输入标记结束
    [assetWriter finishWritingWithCompletionHandler:^{
        NSLog(@"Stop Video Capture");
    }]; // 关闭文件编码 
}

-(void) writeFrame:(id<MTLTexture>) texture OnCommand:(id<MTLCommandBuffer>) command
{
    if (!self.isRecording)
    {
        return ;
    }
    
    while (!assetWriterVideoInput.isReadyForMoreMediaData)
    {
        NSLog(@"not ready for video input");
    }
    
    __weak typeof(self) WeakSelf = self ;
    
#if ISMAC
    if let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder() {
        blitCommandEncoder.synchronize(resource: drawable.texture)
        blitCommandEncoder.endEncoding()
    }
 #endif
                
    [command addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
            
        __strong typeof(WeakSelf) StrongSelf = WeakSelf;
        if (StrongSelf)
        {
            [StrongSelf writeFrame:texture];
        }
        // MTLCommandBufferStatusCompleted = 4
        // NSLog(@"MTLCommandBuffer status = %lu", [buffer status] );
    }];
    
}

-(void) writeFrame:(id<MTLTexture>) texture
{
    if (!self.isRecording)
    {
        return ;
    }
    
    while (!assetWriterVideoInput.isReadyForMoreMediaData)
    {
        NSLog(@"not ready for video input");
    }
    
    // 从 adaptor中获取一个pixelBuffer
    // AVAssetWriterInputPixelBufferAdaptor
    //
    CVPixelBufferPoolRef cvPixelBufferPool = assetWriterPixelBufferInput.pixelBufferPool;
    if (cvPixelBufferPool == nil)
    {
        NSLog(@"Adaptor did not have a pixel buffer pool available; cannot retrieve frame");
        return ;
    }
    
    CVPixelBufferRef pixelBufferOut;
    CVReturn status = CVPixelBufferPoolCreatePixelBuffer(nil, cvPixelBufferPool , &pixelBufferOut);
    if (status != kCVReturnSuccess)
    {
        NSLog(@"CVPixelBufferPool Could not get pixel buffer from asset writer input; dropping frame...");
        return ;
    }
    
    
    
    
    // 当使用GPU访问像素数据(accessing pixel data)时，锁定不是必需的，并且会影响性能
    // 当使用CPU访问像素数据之前， 必须调用CVPixelBufferLockBaseAddress函数
    CVPixelBufferLockBaseAddress(pixelBufferOut,0);
    
    void* bufferAddress = CVPixelBufferGetBaseAddress(pixelBufferOut);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBufferOut);
    
    MTLRegion region =  MTLRegionMake2D(0, 0, texture.width, texture.height);
    
    //[texture getBytes:pixelBufferOut bytesPerRow:bytesPerRow fromRegion:region mipmapLevel:0];
    [texture getBytes:bufferAddress bytesPerRow:bytesPerRow fromRegion:region mipmapLevel:0];
    // Returns the current absolute time, in seconds.
    CFTimeInterval timestampInSecond = CACurrentMediaTime() - recordingStartTime;
    CMTime presentationTimeInSecond = CMTimeMakeWithSeconds(timestampInSecond  , 240); // 时间戳*240
    
    // CM = Core Media
    [assetWriterPixelBufferInput appendPixelBuffer:pixelBufferOut withPresentationTime:presentationTimeInSecond];
    
    CVPixelBufferUnlockBaseAddress(pixelBufferOut, 0); // Either kCVPixelBufferLock_ReadOnly or 0;
    
    CVBufferRelease(pixelBufferOut);
}


-(void) dealloc
{
    NSLog(@"MetalVideoRecorder is dealloc");
}

@end
