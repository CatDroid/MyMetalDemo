//
//  CameraDevice.m
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#import "CameraDevice.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

typedef NS_ENUM(NSInteger, AuthorizationState)
{
    A_NON,
    A_FAIL,
    A_OK,
};

@interface CameraDevice()  <AVCaptureDataOutputSynchronizerDelegate, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
{

    AVCaptureSession* _captureSession ;
    AVCaptureDeviceInput* _inputDevice ;
    AVCaptureVideoDataOutput* _videoDataOutput ;
    AVCaptureDepthDataOutput* _depthDataOutput;
    
    dispatch_queue_t _captureQueue ;
    
    BOOL _needDepthOutput ;
    
    AuthorizationState _authorStatus;
    
    
    // 统计
    int frameCount;
    UInt64 lastTime;
    
}

// 类的扩展--属性
@property (atomic) BOOL isOpen;

// 类的扩展--方法
//- (void) setCamera:(AVCaptureDevice*)device withFrameRate:(int)fps;

@end


@implementation CameraDevice



-(instancetype) init
{
    self = [super init];
    if (self)
    {
        _authorStatus = A_NON;
        _isOpen = false ;
        frameCount = -1;
        lastTime = 0;
    }
    return self ;
}

-(BOOL) checkPermission
{
    if (_authorStatus == A_NON)
    {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        switch(status)
        {
            case AVAuthorizationStatusNotDetermined:
            {
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                    if (granted)
                    {
                        self->_authorStatus = A_OK;
                    }
                    else
                    {
                        self->_authorStatus = A_FAIL;
                    }
                }];
            } break;
            case AVAuthorizationStatusAuthorized:
                _authorStatus = A_OK ;
                break;
            case AVAuthorizationStatusRestricted:
            case AVAuthorizationStatusDenied:
            default:
                _authorStatus = A_FAIL;
                break;
                
        }
    }

    return _authorStatus == A_OK ;
}



-(BOOL) openCamera:(id<MTLDevice>) device
{
 
    // 创建AVCaptureSession、AVCaptureDeviceInput和AVCaptureVideoDataOutput，
    // 注意在创建AVCaptureVideoDataOutput时，需要指定内容格式； 同时需要设定采集的方向，否则图像会出现旋转
    
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
 
    
    // 数据回调到 单独的 串行队列
    _captureQueue = dispatch_queue_create("preview queue", DISPATCH_QUEUE_SERIAL);
    
    // This app has crashed because it attempted to access privacy-sensitive data without a usage description.
    // The app's Info.plist must contain an NSCameraUsageDescription key with a string value explaining to the user how the app uses this data.
    // 在target-info 增加 NSCameraUsageDescription (下拉菜单) Privacy - Camera Usage Description 访问相机
     
  
    AVCaptureDevice* inputCamera = nil;
    if (TRUE) {
        // 通过搜索 获取指定设备  AVCaptureDeviceDiscoverySession
        AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]   // 广角相机
                                                               mediaType:AVMediaTypeVideo                               // 视频媒体类型
                                                                position: AVCaptureDevicePositionUnspecified];          // 设备位置任意
        // 这里传入 AVCaptureDevicePositionUnspecified 就可以搜索到所有的摄像头
        NSArray<AVCaptureDevice*>* captureDevices = [captureDeviceDiscoverySession devices];
        
        for (AVCaptureDevice* camera in captureDevices)
        {
            if (camera.position == AVCaptureDevicePositionFront)
            //if (camera.position == AVCaptureDevicePositionBack)   // 这里修改前后摄像头
            {
                inputCamera = camera;
                break;
            }
        }
        
    } else {
        // 直接获取 给定类型的默认设备
        inputCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                           mediaType:AVMediaTypeVideo
                                           position:AVCaptureDevicePositionBack];
    }
    
    
    NSAssert(inputCamera != nil, @"Find Camera Fail");
    
 
    if (FALSE) {
        // iOS 摄像头采集; 420v（VideoRange）和420f（FullRange）的区别: 亮度和色差取值范围不一样 video只有 Y 16~235 UV 16~240
        // iOS 没有使用传统的 YUV，而是使用 YCbCr; YUV 和 YCbCr 的差异点，两者数据的标准不一样，YCbCr 有 ITU - R BT.601 & ITU - R BT.709 两个标准
        //
        // 对于420f支持 sRGB/P3  对于420v只支持 sRGB 色域 !! RGB 也可以设置sRGB(内部从yuv转换成rgb?)
        //
        NSArray<AVCaptureDeviceFormat *>* formats = [inputCamera formats]  ;
        [formats enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull format, NSUInteger idx, BOOL * _Nonnull stop) {
            NSLog(@"support AVCaptureDeviceFormat Description %@ mediaType %@ colorspaces = %@",
                  format.formatDescription , // 不同分辨率  不同420v/f
                  format.mediaType,
                  format.supportedColorSpaces); // 支持的颜色空间sRGB P3 HLG
            /*
             AVCaptureColorSpace_sRGB       = 0,
             AVCaptureColorSpace_P3_D65     = 1, // P3 色域  10bit P3
             AVCaptureColorSpace_HLG_BT2020 API_AVAILABLE(ios(14.1), macCatalyst(14.1), tvos(17.0)) API_UNAVAILABLE(macos, visionos) = 2,
             AVCaptureColorSpace_AppleLog API_AVAILABLE(ios(17.0), macCatalyst(17.0), tvos(17.0)) API_UNAVAILABLE(macos, visionos) = 3,
             
             所有设备都支持sRGB颜色空间 有些设备和格式支持P3颜色空间--具有更广的色域
             
             */
        }];
    }
 
    
    
    // 打开设备
    NSError* error ;
    _inputDevice = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:&error];
    NSAssert(_inputDevice != nil, @"AVCaptureDeviceInput alloc fail %@", error);
    
    // 输入设备加入到对话
    if ([_captureSession canAddInput:_inputDevice])
    {
        [_captureSession addInput:_inputDevice];
    }
    else
    {
        NSAssert(false, @"fail to add input to session");
    }
    
    // 数据输出
    _videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];

    if (FALSE) {
        NSArray<NSNumber*>* videoOutputFormats = [_videoDataOutput availableVideoCVPixelFormatTypes];
        [videoOutputFormats enumerateObjectsUsingBlock:^(NSNumber * _Nonnull num, NSUInteger idx, BOOL * _Nonnull stop) {
                OSType type = num.unsignedIntValue;
                uint8_t* fourcc = (uint8_t*) &type ;
                if (type == kCVPixelFormatType_32BGRA ||
                    type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                    type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                    NSLog(@"视频输出 只能RGBA或者Full/VideoRange的NV12 %c%c%c%c",fourcc[3],fourcc[2],fourcc[1],fourcc[0]);
                } else {
                    NSLog(@"视频输出其他格式 %c%c%c%c",fourcc[3],fourcc[2],fourcc[1],fourcc[0]);
                }
        }];
    }
 
    // YES 当调度队列处理已存在帧并卡在captureOutput:didOutputSampleBuffer:fromConnection:deleget方法时候 立刻丢弃当前捕捉的视频帧
    // NO  在丢弃新帧之前，会给委托提供更多时间来处理旧帧，但应用程序内存使用量可能因此显着增加。
    // 默认是YES
    [_videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    
    // 当捕获新的视频样本缓冲区时，
    // 它会使用 captureOutput:didOutputSampleBuffer:fromConnection: 发送到 sampleBufferDelegate
    // 所有委托方法都在指定的调度队列上调用。
    [_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
    
 
    
    // 输出pixel buffer的属性配置 (摄像头输出的CVPixelBuffer要兼容Metal 在MacOS上正常 ios上有warning)
    // https://stackoverflow.com/questions/46549906/cvmetaltexturecachecreatetexturefromimage-returns-6660-on-macos-10-13
    // iphone xr 14.01 会报警告  videoSettings dictionary contains one or more unsupported (ignored) keys: MetalCompatibility
    NSDictionary* options = @{
        // kCVPixelFormatType_32BGRA
        // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange  // BT.601 full  range
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // BT.709 video range
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey :  @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @(YES),
    };
    [_videoDataOutput setVideoSettings:options];
     
    
    // 数据输出加入到session
    if ([_captureSession canAddOutput:_videoDataOutput])
    {
        [_captureSession addOutput:_videoDataOutput];
    }
    else
    {
        NSAssert(false, @"fail to add output to session");
    }
    
    // 输入与输出链接
    // 返回具有指定媒体类型(specified media type)的输入端口(input port)的连接数组(connections array) 中的第一个连接(first connection)
    AVCaptureConnection* connection = [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    // 设置方向 设置视频方向 不用自己处理图像旋转 (前摄像头要 顺时帧 旋转90为正  )
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    if (inputCamera.position == AVCaptureDevicePositionFront)
    {
        // 对于back和front都会改为竖的方向 但是front不会设置为左右镜像(ios不加这个不会左右镜像)
        [connection setVideoMirrored:YES];
    }
    
   
    
    // 这样才能设置为P3色域
    if (FALSE) {
        [_captureSession setAutomaticallyConfiguresCaptureDeviceForWideColor:false]; // 必须取消自动配置,再设置色域
        [inputCamera lockForConfiguration:NULL];
        inputCamera.activeColorSpace = AVCaptureColorSpace_P3_D65; // 要是yuv420f 才支持 P3_D65
        //inputCamera.activeColorSpace = AVCaptureColorSpace_sRGB;
        [inputCamera unlockForConfiguration];
        NSLog(@"自动选择更广的P3颜色空间 %s", _captureSession.automaticallyConfiguresCaptureDeviceForWideColor?"YES":"NO");
    }
    
    // 开始预览
    [_captureSession startRunning];
    
    // 控制摄像头的帧率
    [self setFrameRate:15];

    NSLog(@"开始预览, 格式为 %@ 颜色空间为 %ld", [inputCamera activeFormat], (long)[inputCamera activeColorSpace]); // 默认情况是colorSpace=sRGB ??? 没有选P3
 
    return YES;
}

-(BOOL) closeCamera
{
    // TODO dataOutput和device需要单独关闭 ???
    
    [_captureSession stopRunning];
    _captureSession = nil;
    return YES;
}

- (void)setExposurePoint: (CGPoint) pos
{
    if (_inputDevice != NULL)
    {
        NSError *error = nil;
        AVCaptureDevice* device =   _inputDevice.device;
        BOOL locked = [device lockForConfiguration:&error]; // 设置摄像头参数前先lock 注意这个是AVCaptureDevice 不是input或者output
        if (locked)
        {
            [device setExposurePointOfInterest:pos];
            [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            [device unlockForConfiguration];
        }
   
    }

}

// 对于<=30帧 可以这样控制摄像头帧率,
- (void) setFrameRate:(float) frameRate
{
    if (_inputDevice != NULL)
    {
        NSError *error = nil;
        AVCaptureDevice* device =  _inputDevice.device;
        BOOL locked = [device lockForConfiguration:&error];
        if (locked)
        {
            // CMTimeMake(value, timescale)  value / timeScale 得到是总时间长度
            // value        帧数目
            // timeScale    帧率
            [device setActiveVideoMinFrameDuration:CMTimeMake(1, frameRate)]; // 设置帧间隔
            [device setActiveVideoMaxFrameDuration:CMTimeMake(1, frameRate)];
            [device unlockForConfiguration];
        }
    }
}


-(void) dealloc
{
    NSLog(@"MetalCameraDevice ~dealloc");
}


static UInt64 getTime()
{
    UInt64 timestamp = [[NSDate date] timeIntervalSince1970]*1000;
    return timestamp;
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate -

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
{
    
    // 帧率统计  ------
    if (frameCount == -1) {
        lastTime   = getTime();
        frameCount = 0;
    } else {
        frameCount++;
        if (frameCount >= 180) {
           
            UInt64 now = getTime();
            UInt64 duration = now - lastTime;
            NSLog(@"camera fps = %f", frameCount * 1000.0f / duration); // 可以通过setFrameRate控制摄像头帧率(预览之后也可以)
            frameCount = 0 ;
            lastTime = getTime();
        }
    }
    // --------------
    

    // !!!!! 非常重要 !!!!! 'CVMetalTextureRef' (aka 'struct __CVBuffer *') 是个 结构体指针 变量 !!! 所以赋值这个类型的变量 不影响内部的引用计数
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); // 调用者并不持有返回的buffer,如需显式持有
    CVPixelBufferRef pixelBuffer = imageBuffer;
    
    [self.delegate onPreviewFrame:pixelBuffer];
 

}


// 丢帧 每次丢帧都会提示
- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer // typedef struct opaqueCMSampleBuffer CMSampleBufferRef;
       fromConnection:(AVCaptureConnection *)connection //API_AVAILABLE(ios(6.0))
{
    NSLog(@"drop frame");
    // 如果没有可用的IOSurface/CVPixelBuffer 这里会丢帧
}


#pragma mark - AVCaptureDataOutputSynchronizerDelegate
-(void) dataOutputSynchronizer:(AVCaptureDataOutputSynchronizer *)synchronizer didOutputSynchronizedDataCollection:(AVCaptureSynchronizedDataCollection *)synchronizedDataCollection
{
    CVPixelBufferRef videoImageBuffer = NULL, depthImageBuffer = NULL ;
    
    // 从数据输出对象中拿到 同步对象
    // 视频是 SampleBufferData
    // 深度是 DepthData
    AVCaptureSynchronizedData* videoData = [synchronizedDataCollection synchronizedDataForCaptureOutput:_videoDataOutput];
    AVCaptureSynchronizedSampleBufferData* videoDataBuffer = (AVCaptureSynchronizedSampleBufferData*)videoData;
    if(!videoDataBuffer.sampleBufferWasDropped)
    {
        CMSampleBufferRef sampleBuffer = videoDataBuffer.sampleBuffer;
        videoImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); // 从CMSampleBuffer获取到PixelBuffer
    }
    else
    {
        NSLog(@"sync point,sample is drop");
    }
    
    
    AVCaptureSynchronizedData* depthData = [synchronizedDataCollection synchronizedDataForCaptureOutput:_depthDataOutput];
    AVCaptureSynchronizedDepthData* depthDataBuffer = (AVCaptureSynchronizedDepthData*) depthData;
    
    if (!depthDataBuffer.depthDataWasDropped)
    {
        // ????
        // 指示在捕获和处理之间是否丢弃了深度数据。
        // 如果此值为 YES，则已为此同步点,捕获深度数据但无法传送。
        // 这种情况与没有发生同步时间戳的深度数据捕获的情况不同。后一种情况，传递给委托方法的 AVCaptureSynchronizedDataCollection 对象中不存在 AVCaptureSynchronizedDepthData 对象。
        AVDepthData* data = depthDataBuffer.depthData; // 深度图
        depthImageBuffer = [data depthDataMap];
    }
    else
    {
        NSLog(@"sync point, depth is drop");
    }
    
    if (videoImageBuffer != NULL &&  depthImageBuffer!= NULL)
    {
        // [self.delegate onPreviewFrame:videoImageBuffer withDepth:depthImageBuffer ]
    }
    
}


@end
