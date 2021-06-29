//
//  BackedCVPixelBufferMetalRecoder.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/27.
//

#import "BackedCVPixelBufferMetalRecoder.h"
#import <Metal/Metal.h>
//#import <CoreVideo/CoreVideo.h> // Core Video -- CV
#import <CoreVideo/CVPixelBuffer.h> // CVPixelBufferRef
#import <CoreVideo/CVMetalTextureCache.h>
#import <AVFoundation/AVFoundation.h>

#import "RecordRender.h"

@interface BackedCVPixelBufferMetalRecoder()

@property (atomic) BOOL isRecording ;

@end


@implementation BackedCVPixelBufferMetalRecoder
{
    // Core Video 提供的metal纹理缓冲池
    CVMetalTextureCacheRef _textureCache;
    
    AVAssetWriter* assetWriter ;
    AVAssetWriterInput* assetWriterVideoInput ;
    AVAssetWriterInputPixelBufferAdaptor* assetWriterPixelBufferInput;
    NSTimeInterval recordingStartTime ;
    
    RecordRender* recorderRender ;
}


-(instancetype) init:(CGSize) size WithDevice:(id<MTLDevice>)device
{
    self = [super init];
    
    // 创建CVMetalTextureCacheRef _textureCache，这是Core Video的Metal纹理缓存
    CVReturn result = CVMetalTextureCacheCreate(NULL, NULL, MTLCreateSystemDefaultDevice(), NULL, &_textureCache);
    
    NSAssert(result==kCVReturnSuccess, @"fail to CVMetalTextureCacheCreate");
    
    
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
    

    recorderRender = [[RecordRender alloc] initWithDevice:device];

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


-(void) drawToRecorder:(id<MTLTexture>) texture  OnCommand:(id<MTLCommandBuffer>) command
{
    if (!self.isRecording)
    {
        return ;
    }
    
    while (!assetWriterVideoInput.isReadyForMoreMediaData)
    {
        NSLog(@"not ready for video input");
    }
    
    
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
    
    
    id<MTLTexture> renderTarget = [self pixelBufferToMTLTexture:pixelBufferOut];
    
    [recorderRender encodeToCommandBuffer:command sourceTexture:texture destinationTexture:renderTarget];
    
    
    CFTimeInterval timestampInSecond = CACurrentMediaTime() - recordingStartTime;
    CMTime presentationTimeInSecond = CMTimeMakeWithSeconds(timestampInSecond  , 240); // 时间戳*240
        
    __weak typeof(self) WeakSelf = self ;

    [command addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {

        __strong typeof(WeakSelf) StrongSelf = WeakSelf;
        NSLog(@"pixelBufferOut %lu, %p ", (CFGetRetainCount(pixelBufferOut)), pixelBufferOut);
        if (StrongSelf)
        {
            [StrongSelf->assetWriterPixelBufferInput appendPixelBuffer:pixelBufferOut withPresentationTime:presentationTimeInSecond];
        }
        CVBufferRelease(pixelBufferOut);


    }];
   

    
}

-(id<MTLTexture>) pixelBufferToMTLTexture:(CVPixelBufferRef) pixelBuffer // CVPixelBufferRef是一个结构体 不能用CVPixelBuffer
{
    id<MTLTexture> texture ;
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    // A four-character code OSType identifier for the pixel format.
    // CVPixelBufferGetPixelFormatType(pixelBuffer);  返回pixelformat 是 kCVPixelFormatType_32BGRA  'BGRA'
 
 
    MTLPixelFormat format = MTLPixelFormatBGRA8Unorm_sRGB ;
    
    // typedef CVImageBufferRef CVMetalTextureRef;
    // 基于Metal纹理的 image buffer
    CVMetalTextureRef metalTextureRef;
    
    // Creates a Core Video Metal texture buffer from an existing image buffer.
    // 根据存在的 imagebuffer/pixelbuffer 来创建一个Metal texture
    CVReturn result = CVMetalTextureCacheCreateTextureFromImage(nil,
                                                                _textureCache,
                                                                pixelBuffer,
                                                                nil,
                                                                format,
                                                                width,
                                                                height,
                                                                0,
                                                                &metalTextureRef);
    if (result == kCVReturnSuccess)
    {
        // 返回这个image buffer 对应的MTLTexture
        texture = CVMetalTextureGetTexture(metalTextureRef); // 由ARC自动释放
        
        CVBufferRelease(metalTextureRef); // 必须释放 CVMetalTextureCacheCreateTextureFromImage 返回 CVMetalTextureRef 的引用
        
        /*
         ------ ------ ------ ------ ------ ------
            使用Xcode-Instruments-Leaks
            leaks -- Search a process's memory for unreferenced malloc buffers
            unreferenced malloc buffers表明这个工具的基本原理就是检测malloc的内存块是否被依然被引用
         
            非malloc出来的内存块则无能为力，比如vm_allocate出来的内存
            因为OC对象也都是通过malloc分配内存的，所以自然也可以检测
         
            leaks搜索特定应用的内存中 那些可能指向 "malloc内存块" 的值(指针)
            比如
                全局数据内存块writableglobal memory (e.g., __DATA segments),
                寄存器 a register
                on the stack 所有的栈
            如果 "malloc内存块的地址" 被直接或者间接引用，则是reachable的，反之，则是leaks
         
         
            OC对象循环引用 也是会被定位出来:
         
                因为由于两个LeakObject互相引用，
                而且未被全局数据内存块，寄存器或者任何栈持有引用，
                所以被判定为unreachable的leak对象
                (堆上两个对象相互引用?)
                
         
            ------ ------ ------ ------ ------ ------
            为什么有时候Leaks无法检测出来某些内存泄露，它们还仅仅是弱引用(纯粹是指针)
                
            Case.1 只要是全局指针 指向了这个内存块，就是有引用了，而不管这个指针是什么类型的，
            比如
                用(__bridge void*)转换成void*指针, 给到void*全局变量，这块内存就不是leak了
         
         
            Case.2
         
            
            比如
                ViewController(VC对象)中创建一个LeakObject 并被VC对象持有,同时LeakObject通过block中引用self,从而引用了VC对象
                这个本类是个leak的，
                但是如果把VC对象, presentViewController:vc 然后再 dismissViewControllerAnimated:让vc对象消失
                leaks不会提示这个错误
         
                "Debug Memory Graph" 来看看内存中对象的引用关系图
                -->  UIApplication--NSMutableArray--malloc<16> --- ViewController-- LeakObject
           
         
                "View Memory 工具"   来查看这个malloc(16)的内存区域
                0x60000001dc90是malloc(16)的起始地址，0x7fe312608780是ViewController的内存地址
                malloc(16) = 0x7fe312608780 这只是一个弱引用(存粹保存了指针)
         
            ------ ------ ------ ------ ------ ------
             Leaks 工具 （Instrument)
                File--Symbols 可以指定dSym路径
                -- 如果提示 Permisson to debug [app name] was denied.The app must be signed with a development identity 关闭xcode和leak重新打开
                -- dSym文件一般在DerivedData/Build/Products/目前下
             Allocations 工具 （Instrument)
             Debug Memory Graph 工具 (XCode左边 Show the Debug Navigator--左上角下拉菜单--View Memory Graph Hierachy) 打印窗口上的Debug Memory Graph没有反应
                    -- Product --- scheme editor -- Run/Debug --- Disgnostics -- 勾选Malloc Stack
                        如果没有勾选 Malloc Stack 在调试的时候，在右侧是看不到调用的堆栈信息。
                            1. 勾选 Malloc Stack 之后内存会相应的增高，如果不调试可以关闭该选项
                            2. 建议选择 Live Allocations Only 如果选择 All Allocations and Free History 会出现一些额外的影响因素
 
                    -- 点击后后会暂停程序
                    -- 在左侧面板内存层级树下面 点击感叹号，可以只查看内存泄漏的对象(紫色感叹号) 或者不过滤，然后会看到一些没有引用的对象(unreachable leak 自己持有自己)
         
                            左侧输入框，输入对应类名，可以很方便过滤
                            右侧第一个按钮，show only leaked blocks，只显示被判定为泄漏的对象
                            右侧第二个按钮，show only content from workspace，只显示当前工程相关
                    
             View Memory 工具 (Debug > Debug Workflow > View Memory)
         
         
         
         */
    }
    
    
    /*
     CVMetalTextureCacheCreate(
                 kCFAllocatorDefault,
                 nil,
                 device!,
                 nil,
                 &textureCache) //
     
     
     let pixelBufferAttri = [kCVPixelBufferIOSurfacePropertiesKey
     let s = CVPixelBufferCreate(
                 kCFAllocatorDefault,
                 1080,
                 1920,
                 kCVPixelFormatType_32BGRA,
                 pixelBufferAttri,
                 &offlinePixelBuffer) // 手动创建CVPixelBuffer backend要是IOSurface
     
     let result = CVMetalTextureCacheCreateTextureFromImage(
         kCFAllocatorDefault,
         textureCache!,
         offlinePixelBuffer!,
         nil,
         self.colorPixelFormat,
         1080,
         1920,
         0,
         &offlineTexture) // PixelBuffer得到纹理
     
     */
     
    return texture;
    
}

@end
