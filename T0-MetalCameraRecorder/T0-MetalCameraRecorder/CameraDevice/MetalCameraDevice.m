//
//  CameraDevice.m
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/28.
//

#import "MetalCameraDevice.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CVMetalTextureCache.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, AuthorizationState)
{
    A_NON,
    A_FAIL,
    A_OK,
};

@interface MetalCameraDevice()  <AVCaptureDataOutputSynchronizerDelegate, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
{
    CVMetalTextureCacheRef _textureCache;
    
    AVCaptureSession* _captureSession ;
    AVCaptureDeviceInput* _inputDevice ;
    AVCaptureVideoDataOutput* _videoDataOutput ;
    AVCaptureDepthDataOutput* _depthDataOutput;
    
    dispatch_queue_t _captureQueue ;
    
    BOOL _needDepthOutput ;
    
    AuthorizationState _authorStatus;
}

@property (atomic) BOOL isOpen;

@end


@implementation MetalCameraDevice



-(instancetype) init
{
    self = [super init];
    if (self)
    {
        _authorStatus = A_NON;
        _isOpen = false ;
        _textureCache = NULL;
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
    // 创建Core Video的Metal纹理缓存
    // cacheAttributes nil
    // textureAttributes nil
    CVReturn result = CVMetalTextureCacheCreate(nil, nil, device, nil, &_textureCache);
    NSAssert(result == kCVReturnSuccess, @"CVMetalTextureCacheCreate fail");
    
    // 创建AVCaptureSession、AVCaptureDeviceInput和AVCaptureVideoDataOutput，
    
    // 注意在创建AVCaptureVideoDataOutput时，需要指定内容格式，这里使用的是BGRA的格式； 同时需要设定采集的方向，否则图像会出现旋转
    
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;// 使用preset预置。1920x1080的配置。1920是长边
	//_captureSession.sessionPreset =  AVCaptureSessionPresetPhoto;
	
    // 串行队列
    _captureQueue = dispatch_queue_create("preview queue", DISPATCH_QUEUE_SERIAL);
    
    // This app has crashed because it attempted to access privacy-sensitive data without a usage description.
    // The app's Info.plist must contain an NSCameraUsageDescription key with a string value explaining to the user how the app uses this data.
    // 在target-info 增加 NSCameraUsageDescription (下拉菜单) Privacy - Camera Usage Description 访问相机
     
    
    // 搜索设备  AVCaptureDeviceDiscoverySession
    AVCaptureDevice* inputCamera = nil;
    
    // 'devicesWithMediaType:' is deprecated:
//    NSArray<AVCaptureDevice*>* cameras = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
//    for (AVCaptureDevice* camera in cameras)
//    {
//        // camera.exposureMode
//        // camera.ISO
//        // camera.focusMode
//        if (camera.position == AVCaptureDevicePositionBack)
//        {
//            inputCamera = camera;
//            break;
//        }
//    }
   
    // AVCaptureDeviceTypeBuiltInWideAngleCamera 内置广角摄像头
    // AVCaptureDeviceTypeBuiltInUltraWideCamera 超广角摄像头 焦距比广角相机短的内置相机设备
    // AVCaptureDeviceTypeBuiltInTelephotoCamera 长焦相机    焦距比广角相机长的内置相机设备
    // AVCaptureDeviceTypeBuiltInDualCamera     内置双摄像头  广角wide-angle和长焦telephoto相机的组合，可创建捕获设备
    // AVCaptureDeviceTypeBuiltInDualWideCamera 内置双广角   由两个固定焦距、一个超广角和一个广角的摄像头组成的设备。
    // AVCaptureDeviceTypeBuiltInTripleCamera   内置三摄像头 由三个固定焦距、一个超广角、一个广角和一个长焦的摄像头组成的设备。
    // AVCaptureDeviceTypeBuiltInTrueDepthCamera 深度相机   相机和其他传感器的组合，创建了一个能够进行照片、视频和深度捕捉的捕捉设备。
    // AVCaptureDeviceTypeBuiltInMicrophone     内置麦克风
    
    
    AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession =
    [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]   // 广角相机
                                                           mediaType:AVMediaTypeVideo                               // 视频媒体类型
                                                            position: AVCaptureDevicePositionUnspecified];          // 设备位置任意
    // 这里传入 AVCaptureDevicePositionUnspecified 就可以搜索到所有的摄像头
    NSArray<AVCaptureDevice*>* captureDevices = [captureDeviceDiscoverySession devices];
    for (AVCaptureDevice* camera in captureDevices)
    {
        //if (camera.position == AVCaptureDevicePositionFront)
        if (camera.position == AVCaptureDevicePositionBack)
        {
            inputCamera = camera;
            break;
        }
    }
    
    // 这样直接获给定类型的默认设备
//    [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
//                                       mediaType:AVMediaTypeVideo
//                                        position:AVCaptureDevicePositionBack];
    
    NSAssert(inputCamera != nil, @"Find Camera Fail");
	
	
	// NSGenericException
	// [AVCaptureDevice setActiveColorSpace:]
	// 在第一次 通过lockForConfiguration 成功地 获取 排他性控制权 之前 不能被调用
	// inputCamera.activeColorSpace = AVCaptureColorSpace_sRGB;
	//

	// iOS 摄像头采集; 420v（VideoRange）和420f（FullRange）的区别: 亮度和色差取值范围不一样 video只有 Y 16~235 UV 16~240
	// iOS 没有使用传统的 YUV，而是使用 YCbCr; YUV 和 YCbCr 的差异点，两者数据的标准不一样，YCbCr 有 ITU - R BT.601 & ITU - R BT.709 两个标准
	//
	// 对于420f支持 sRGB/P3
	// 对于420v只支持 sRGB
	// NSArray<AVCaptureDeviceFormat *>* formats = [inputCamera formats]  ;
	//[formats enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull format, NSUInteger idx, BOOL * _Nonnull stop) {
	//		NSLog(@"support AVCaptureDeviceFormat mediaType %@ colorspaces = %@", format.mediaType, format.supportedColorSpaces); // 支持的颜色空间sRGB P3 HLG
	//}];
	
	// AVCaptureColorSpace_sRGB
	// AVCaptureColorSpace_P3_D65 // P3 色域  10bit P3
	// AVCaptureColorSpace_HLG_BT2020
	//
	// 所有设备都支持sRGB颜色空间 有些设备和格式支持P3颜色空间 具有更广的色域
    
    
    // 打开设备
    NSError* error ;
    _inputDevice = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:&error];
    NSAssert(_inputDevice != nil, @"AVCaptureDeviceInput alloc fail %@", error);
    
    // 输入设备加入到对话
    // AVCaptureInput * input 是否能够加入Session  AVCaptureDeviceInput的父类是AVCaptureInput
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
    // AVCaptureAudioDataOutput
    // AVCaptureDepthDataOutput // 摄像头输出场景深度信息
	
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
	
    /*
     YES 当调度队列处理已存在帧并卡在captureOutput:didOutputSampleBuffer:fromConnection:deleget方法时候 立刻丢弃当前捕捉的视频帧
     NO  在丢弃新帧之前，会给委托提供更多时间来处理旧帧，但应用程序内存使用量可能因此显着增加。
     默认是YES
     */
    [_videoDataOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    /*
        当捕获新的视频样本缓冲区时，
        它会使用 captureOutput:didOutputSampleBuffer:fromConnection: 发送到 sampleBufferDelegate
        所有委托方法都在指定的调度队列上调用。
     */
    //设置视频捕捉输出代理方法
    [_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
    
	// 输出pixel buffer的属性配置 (摄像头输出的CVPixelBuffer要兼容Metal 在MacOS上正常 ios上有warning)
	// https://stackoverflow.com/questions/46549906/cvmetaltexturecachecreatetexturefromimage-returns-6660-on-macos-10-13
	// iphone xr 14.01 会报警告  videoSettings dictionary contains one or more unsupported (ignored) keys: MetalCompatibility
    NSDictionary* options = @{
       // kCVPixelFormatType_ARGB2101010LEPacked A 2 R 10 G 10 B 10
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey :  @(kCVPixelFormatType_32BGRA),// 没有sRGB的选择这里
		(__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @(YES), // 没有这个也是ok的??  当配置AVCaptureVideoDataOutput时候 请求Metal兼容
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
    
    // 设置方向 设置视频方向 不用自己处理图像旋转
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    if (inputCamera.position == AVCaptureDevicePositionFront)
    {
        // 对于back和front都会改为竖的方向 但是front不会设置为左右镜像
        [connection setVideoMirrored:YES];
    }
    
    
    // 如果需要深度输出的话, 还会创建同步对象  摄像头图像/深度/同步对象 都在同一个同步queue上处理
    if (_needDepthOutput)
    {
        _depthDataOutput = [[AVCaptureDepthDataOutput alloc] init];
        if ([_captureSession canAddOutput:_depthDataOutput])
        {
            [_captureSession addOutput:_depthDataOutput];
        }
        [_depthDataOutput setDelegate:self callbackQueue:_captureQueue];
        [_depthDataOutput setFilteringEnabled:NO];
        [_depthDataOutput setAlwaysDiscardsLateDepthData:NO]; // 跟摄像头图像帧一样 可以设置丢帧策略
        
        // 在DataOutput加入到Capture Session之后, 这里吧输出数据和输入建立链接, 并通过链接设置参数
        AVCaptureConnection* depthConnect = [_depthDataOutput connectionWithMediaType:AVMediaTypeDepthData];
        [depthConnect setVideoMirrored:YES];
        [depthConnect setVideoOrientation:AVCaptureVideoOrientationPortrait]; // 竖向 并且 镜像 (前摄像头)
        
        
        /* 同步对象
            使用了多个数据输出DataOutput
            AVCaptureMetadataOutput
            AVCaptureDepthDataOutput
            AVCaptureAudioDataOutput
            AVCaptureVideoDataOutput
            并使用AVCaptureDataOutputSynchronizer对其进行了组合
            代理要实现协议 id<AVCaptureDataOutputSynchronizerDelegate>
        */
        AVCaptureDataOutputSynchronizer* sync = [[AVCaptureDataOutputSynchronizer alloc] initWithDataOutputs:@[_videoDataOutput, _depthDataOutput]];
        [sync setDelegate:self queue:self->_captureQueue];
        
    }
    
	NSLog(@"自动选择更广的P3颜色空间 %s", _captureSession.automaticallyConfiguresCaptureDeviceForWideColor?"YES":"NO");
	
	
	// 这样才能设置为P3色域
	// [_captureSession setAutomaticallyConfiguresCaptureDeviceForWideColor:false];
	// [inputCamera lockForConfiguration:NULL];
	// inputCamera.activeColorSpace = AVCaptureColorSpace_P3_D65;
	// [inputCamera unlockForConfiguration];
	
	
    // 到这里 Capture会话的输入(设备 back)和输出(格式 bgra32)都已经设置好
    [_captureSession startRunning]; // 开始预览
    
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

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate -

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
{
    
    
    // 摄像头回传CMSampleBufferRef数据，找到CVPixelBufferRef
    // typedef CVBufferRef CVImageBufferRef;
    // typedef CVImageBufferRef CVPixelBufferRef;
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); // 调用者并不持有返回的buffer,如需显式持有
    CVPixelBufferRef pixelBuffer = imageBuffer;
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
	
   
    // 创建CoreVideo的Metal纹理缓存
    CVMetalTextureRef tmpTexture = NULL;
    // 从 imagebuffer 获取 Core Video Metal texture buffer
    // 创建一个缓冲的CoreView Metal纹理对象 映射到imagebuffer(由IOSurface buffer实现)，并绑定底层的MTLTexture对象和imageBuffer
    // 这个函数会增加imagebuffer的使用计数 但是不会增加IOSurface Buffer的使用计数
    // Core Video Metal纹理对象 持有这个IOSruface Buffer
    // 因此在渲染完成之前 必须保持对imagebuffer或者metal纹理的强引用
    CVReturn result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                _textureCache,
                                                                pixelBuffer, // 会增加引用计数
                                                                nil,
                                                                MTLPixelFormatBGRA8Unorm_sRGB,
																//MTLPixelFormatBGRA8Unorm, // 这个会偏白色 摄像头输出一般是sRGB 或者P3??(广域10bits) sRGB是gamma0.45把暗的部分扩大(曲线是上凸) 导致直接当做线性来看 就会变白了
                                                                width,
                                                                height,
                                                                0,
                                                                &tmpTexture);
    
    // 目前来说可以通过这种方法 把pixelbuffer转换成MTLTexture
    
    // ???
    // 为了确保我们正在使用同一份物理内存（避免拷贝发生），我们需要使用 IOSurface 作为后备存储（Backing Store）
    // IOSurface 是一个共享的支持硬件加速的 Image Buffer，
    // 通过使用 GPU 驻留追踪（GPU residency tracking），它还支持跨进程、跨框架间的访问。
    // 如果此时 Pixel Buffer 由 IOSurface 后备存储，可以零成本创建一个映射向 Pixel Buffer 的 Metal Texture
    //
    if (result == kCVReturnSuccess)
    {
        //NSLog(@"CFGetRetainCount---CVMetalTextureRef counter %ld", CFGetRetainCount(tmpTexture)); // 1
        
        // 从image buffer获取MTLTexture
        id<MTLTexture> texture = CVMetalTextureGetTexture(tmpTexture);
        
        // NSLog(@"CFGetRetainCount---id<MTLTexture> counter %ld texture %p", CFGetRetainCount((__bridge CFTypeRef)texture), texture); // 2
        
        // NSLog(@"CVMetalTextureGetTexture texture:%@ class:%@", texture, [texture class]);
        // class   是 CaptureMTLTexture
        // texture 是 <CaptureMTLTexture: 0x281a9e400> -> <AGXA12FamilyTexture: 0x108906f90>
        
    
        // CFRelease(CFTypeRef cf) // CFTypeRef  这个可以传入null  都是减少引用计数 计数为0的话销毁对象
        CVBufferRelease(tmpTexture); // CVBufferRef  这个不能传入null
        // 如果不调用这个 就会一直返回不同的id<MTLTexture>
        // 最后没有buffer 只会 captureOutput:didDropSampleBuffer:
        // 官方的demo MetalVideoCapture 就是在转换成id<MTLMetal>之后就释放
        // Apple的Demo
        // https://developer.apple.com/library/archive/navigation/
        
        [self.delegate onPreviewFrame:texture WithSize:CGSizeMake(width,height)];
        
 
    
    }
    else
    {
        NSAssert(false, @"fail to create CVMetalTexture from CVPixelBuffer");
    }
    
    
}


// 丢帧 每次丢帧都会提示
- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer // typedef struct opaqueCMSampleBuffer CMSampleBufferRef;
       fromConnection:(AVCaptureConnection *)connection //API_AVAILABLE(ios(6.0))
{
    NSLog(@"drop frame");
    
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
