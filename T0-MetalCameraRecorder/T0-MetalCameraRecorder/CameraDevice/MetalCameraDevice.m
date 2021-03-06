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
    // ??????Core Video???Metal????????????
    // cacheAttributes nil
    // textureAttributes nil
    CVReturn result = CVMetalTextureCacheCreate(nil, nil, device, nil, &_textureCache);
    NSAssert(result == kCVReturnSuccess, @"CVMetalTextureCacheCreate fail");
    
    // ??????AVCaptureSession???AVCaptureDeviceInput???AVCaptureVideoDataOutput???
    
    // ???????????????AVCaptureVideoDataOutput???????????????????????????????????????????????????BGRA???????????? ???????????????????????????????????????????????????????????????
    
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;// ??????preset?????????1920x1080????????????1920?????????
	//_captureSession.sessionPreset =  AVCaptureSessionPresetPhoto;
	
    // ????????????
    _captureQueue = dispatch_queue_create("preview queue", DISPATCH_QUEUE_SERIAL);
    
    // This app has crashed because it attempted to access privacy-sensitive data without a usage description.
    // The app's Info.plist must contain an NSCameraUsageDescription key with a string value explaining to the user how the app uses this data.
    // ???target-info ?????? NSCameraUsageDescription (????????????) Privacy - Camera Usage Description ????????????
     
    
    // ????????????  AVCaptureDeviceDiscoverySession
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
   
    // AVCaptureDeviceTypeBuiltInWideAngleCamera ?????????????????????
    // AVCaptureDeviceTypeBuiltInUltraWideCamera ?????????????????? ?????????????????????????????????????????????
    // AVCaptureDeviceTypeBuiltInTelephotoCamera ????????????    ?????????????????????????????????????????????
    // AVCaptureDeviceTypeBuiltInDualCamera     ??????????????????  ??????wide-angle?????????telephoto???????????????????????????????????????
    // AVCaptureDeviceTypeBuiltInDualWideCamera ???????????????   ????????????????????????????????????????????????????????????????????????????????????
    // AVCaptureDeviceTypeBuiltInTripleCamera   ?????????????????? ???????????????????????????????????????????????????????????????????????????????????????????????????
    // AVCaptureDeviceTypeBuiltInTrueDepthCamera ????????????   ???????????????????????????????????????????????????????????????????????????????????????????????????????????????
    // AVCaptureDeviceTypeBuiltInMicrophone     ???????????????
    
    
    AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession =
    [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]   // ????????????
                                                           mediaType:AVMediaTypeVideo                               // ??????????????????
                                                            position: AVCaptureDevicePositionUnspecified];          // ??????????????????
    // ???????????? AVCaptureDevicePositionUnspecified ????????????????????????????????????
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
    
    // ??????????????????????????????????????????
//    [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
//                                       mediaType:AVMediaTypeVideo
//                                        position:AVCaptureDevicePositionBack];
    
    NSAssert(inputCamera != nil, @"Find Camera Fail");
	
	
	// NSGenericException
	// [AVCaptureDevice setActiveColorSpace:]
	// ???????????? ??????lockForConfiguration ????????? ?????? ?????????????????? ?????? ???????????????
	// inputCamera.activeColorSpace = AVCaptureColorSpace_sRGB;
	//

	// iOS ???????????????; 420v???VideoRange??????420f???FullRange????????????: ???????????????????????????????????? video?????? Y 16~235 UV 16~240
	// iOS ????????????????????? YUV??????????????? YCbCr; YUV ??? YCbCr ????????????????????????????????????????????????YCbCr ??? ITU - R BT.601 & ITU - R BT.709 ????????????
	//
	// ??????420f?????? sRGB/P3
	// ??????420v????????? sRGB
	// NSArray<AVCaptureDeviceFormat *>* formats = [inputCamera formats]  ;
	//[formats enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull format, NSUInteger idx, BOOL * _Nonnull stop) {
	//		NSLog(@"support AVCaptureDeviceFormat mediaType %@ colorspaces = %@", format.mediaType, format.supportedColorSpaces); // ?????????????????????sRGB P3 HLG
	//}];
	
	// AVCaptureColorSpace_sRGB
	// AVCaptureColorSpace_P3_D65 // P3 ??????  10bit P3
	// AVCaptureColorSpace_HLG_BT2020
	//
	// ?????????????????????sRGB???????????? ???????????????????????????P3???????????? ?????????????????????
    
    
    // ????????????
    NSError* error ;
    _inputDevice = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:&error];
    NSAssert(_inputDevice != nil, @"AVCaptureDeviceInput alloc fail %@", error);
    
    // ???????????????????????????
    // AVCaptureInput * input ??????????????????Session  AVCaptureDeviceInput????????????AVCaptureInput
    if ([_captureSession canAddInput:_inputDevice])
    {
        [_captureSession addInput:_inputDevice];
    }
    else
    {
        NSAssert(false, @"fail to add input to session");
    }
    
    // ????????????
    _videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    // AVCaptureAudioDataOutput
    // AVCaptureDepthDataOutput // ?????????????????????????????????
	
	NSArray<NSNumber*>* videoOutputFormats = [_videoDataOutput availableVideoCVPixelFormatTypes];
	[videoOutputFormats enumerateObjectsUsingBlock:^(NSNumber * _Nonnull num, NSUInteger idx, BOOL * _Nonnull stop) {
			OSType type = num.unsignedIntValue;
			uint8_t* fourcc = (uint8_t*) &type ;
			if (type == kCVPixelFormatType_32BGRA ||
				type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
				type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
				NSLog(@"???????????? ??????RGBA??????Full/VideoRange???NV12 %c%c%c%c",fourcc[3],fourcc[2],fourcc[1],fourcc[0]);
			} else {
				NSLog(@"???????????????????????? %c%c%c%c",fourcc[3],fourcc[2],fourcc[1],fourcc[0]);
			}
	}];
	
    /*
     YES ??????????????????????????????????????????captureOutput:didOutputSampleBuffer:fromConnection:deleget???????????? ????????????????????????????????????
     NO  ?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
     ?????????YES
     */
    [_videoDataOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    /*
        ??????????????????????????????????????????
        ???????????? captureOutput:didOutputSampleBuffer:fromConnection: ????????? sampleBufferDelegate
        ?????????????????????????????????????????????????????????
     */
    //????????????????????????????????????
    [_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
    
	// ??????pixel buffer??????????????? (??????????????????CVPixelBuffer?????????Metal ???MacOS????????? ios??????warning)
	// https://stackoverflow.com/questions/46549906/cvmetaltexturecachecreatetexturefromimage-returns-6660-on-macos-10-13
	// iphone xr 14.01 ????????????  videoSettings dictionary contains one or more unsupported (ignored) keys: MetalCompatibility
    NSDictionary* options = @{
       // kCVPixelFormatType_ARGB2101010LEPacked A 2 R 10 G 10 B 10
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey :  @(kCVPixelFormatType_32BGRA),// ??????sRGB???????????????
		(__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @(YES), // ??????????????????ok?????  ?????????AVCaptureVideoDataOutput?????? ??????Metal??????
    };
    [_videoDataOutput setVideoSettings:options];
	 
    
    // ?????????????????????session
    if ([_captureSession canAddOutput:_videoDataOutput])
    {
        [_captureSession addOutput:_videoDataOutput];
    }
    else
    {
        NSAssert(false, @"fail to add output to session");
    }
    
    // ?????????????????????
    // ??????????????????????????????(specified media type)???????????????(input port)???????????????(connections array) ?????????????????????(first connection)
    AVCaptureConnection* connection = [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    // ???????????? ?????????????????? ??????????????????????????????
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    if (inputCamera.position == AVCaptureDevicePositionFront)
    {
        // ??????back???front???????????????????????? ??????front???????????????????????????
        [connection setVideoMirrored:YES];
    }
    
    
    // ??????????????????????????????, ????????????????????????  ???????????????/??????/???????????? ?????????????????????queue?????????
    if (_needDepthOutput)
    {
        _depthDataOutput = [[AVCaptureDepthDataOutput alloc] init];
        if ([_captureSession canAddOutput:_depthDataOutput])
        {
            [_captureSession addOutput:_depthDataOutput];
        }
        [_depthDataOutput setDelegate:self callbackQueue:_captureQueue];
        [_depthDataOutput setFilteringEnabled:NO];
        [_depthDataOutput setAlwaysDiscardsLateDepthData:NO]; // ??????????????????????????? ????????????????????????
        
        // ???DataOutput?????????Capture Session??????, ??????????????????????????????????????????, ???????????????????????????
        AVCaptureConnection* depthConnect = [_depthDataOutput connectionWithMediaType:AVMediaTypeDepthData];
        [depthConnect setVideoMirrored:YES];
        [depthConnect setVideoOrientation:AVCaptureVideoOrientationPortrait]; // ?????? ?????? ?????? (????????????)
        
        
        /* ????????????
            ???????????????????????????DataOutput
            AVCaptureMetadataOutput
            AVCaptureDepthDataOutput
            AVCaptureAudioDataOutput
            AVCaptureVideoDataOutput
            ?????????AVCaptureDataOutputSynchronizer?????????????????????
            ????????????????????? id<AVCaptureDataOutputSynchronizerDelegate>
        */
        AVCaptureDataOutputSynchronizer* sync = [[AVCaptureDataOutputSynchronizer alloc] initWithDataOutputs:@[_videoDataOutput, _depthDataOutput]];
        [sync setDelegate:self queue:self->_captureQueue];
        
    }
    
	NSLog(@"?????????????????????P3???????????? %s", _captureSession.automaticallyConfiguresCaptureDeviceForWideColor?"YES":"NO");
	
	
	// ?????????????????????P3??????
	// [_captureSession setAutomaticallyConfiguresCaptureDeviceForWideColor:false];
	// [inputCamera lockForConfiguration:NULL];
	// inputCamera.activeColorSpace = AVCaptureColorSpace_P3_D65;
	// [inputCamera unlockForConfiguration];
	
	
    // ????????? Capture???????????????(?????? back)?????????(?????? bgra32)??????????????????
    [_captureSession startRunning]; // ????????????
    
	NSLog(@"????????????, ????????? %@ ??????????????? %ld", [inputCamera activeFormat], (long)[inputCamera activeColorSpace]); // ???????????????colorSpace=sRGB ??? ?????????P3
 
	
    return YES;
}

-(BOOL) closeCamera
{
    // TODO dataOutput???device?????????????????? ???
    
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
        BOOL locked = [device lockForConfiguration:&error]; // ???????????????????????????lock ???????????????AVCaptureDevice ??????input??????output
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
            // CMTimeMake(value, timescale)  value / timeScale ????????????????????????
            // value        ?????????
            // timeScale    ??????
            [device setActiveVideoMinFrameDuration:CMTimeMake(1, frameRate)]; // ???????????????
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
    
    
    // ???????????????CMSampleBufferRef???????????????CVPixelBufferRef
    // typedef CVBufferRef CVImageBufferRef;
    // typedef CVImageBufferRef CVPixelBufferRef;
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); // ??????????????????????????????buffer,??????????????????
    CVPixelBufferRef pixelBuffer = imageBuffer;
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
	
   
    // ??????CoreVideo???Metal????????????
    CVMetalTextureRef tmpTexture = NULL;
    // ??? imagebuffer ?????? Core Video Metal texture buffer
    // ?????????????????????CoreView Metal???????????? ?????????imagebuffer(???IOSurface buffer??????)?????????????????????MTLTexture?????????imageBuffer
    // ?????????????????????imagebuffer??????????????? ??????????????????IOSurface Buffer???????????????
    // Core Video Metal???????????? ????????????IOSruface Buffer
    // ??????????????????????????? ???????????????imagebuffer??????metal??????????????????
    CVReturn result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                _textureCache,
                                                                pixelBuffer, // ?????????????????????
                                                                nil,
                                                                MTLPixelFormatBGRA8Unorm_sRGB,
																//MTLPixelFormatBGRA8Unorm, // ?????????????????? ????????????????????????sRGB ??????P3??(??????10bits) sRGB???gamma0.45?????????????????????(???????????????) ?????????????????????????????? ???????????????
                                                                width,
                                                                height,
                                                                0,
                                                                &tmpTexture);
    
    // ???????????????????????????????????? ???pixelbuffer?????????MTLTexture
    
    // ???
    // ???????????????????????????????????????????????????????????????????????????????????????????????? IOSurface ?????????????????????Backing Store???
    // IOSurface ??????????????????????????????????????? Image Buffer???
    // ???????????? GPU ???????????????GPU residency tracking??????????????????????????????????????????????????????
    // ???????????? Pixel Buffer ??? IOSurface ??????????????????????????????????????????????????? Pixel Buffer ??? Metal Texture
    //
    if (result == kCVReturnSuccess)
    {
        //NSLog(@"CFGetRetainCount---CVMetalTextureRef counter %ld", CFGetRetainCount(tmpTexture)); // 1
        
        // ???image buffer??????MTLTexture
        id<MTLTexture> texture = CVMetalTextureGetTexture(tmpTexture);
        
        // NSLog(@"CFGetRetainCount---id<MTLTexture> counter %ld texture %p", CFGetRetainCount((__bridge CFTypeRef)texture), texture); // 2
        
        // NSLog(@"CVMetalTextureGetTexture texture:%@ class:%@", texture, [texture class]);
        // class   ??? CaptureMTLTexture
        // texture ??? <CaptureMTLTexture: 0x281a9e400> -> <AGXA12FamilyTexture: 0x108906f90>
        
    
        // CFRelease(CFTypeRef cf) // CFTypeRef  ??????????????????null  ???????????????????????? ?????????0??????????????????
        CVBufferRelease(tmpTexture); // CVBufferRef  ??????????????????null
        // ????????????????????? ???????????????????????????id<MTLTexture>
        // ????????????buffer ?????? captureOutput:didDropSampleBuffer:
        // ?????????demo MetalVideoCapture ??????????????????id<MTLMetal>???????????????
        // Apple???Demo
        // https://developer.apple.com/library/archive/navigation/
        
        [self.delegate onPreviewFrame:texture WithSize:CGSizeMake(width,height)];
        
 
    
    }
    else
    {
        NSAssert(false, @"fail to create CVMetalTexture from CVPixelBuffer");
    }
    
    
}


// ?????? ????????????????????????
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
    
    // ?????????????????????????????? ????????????
    // ????????? SampleBufferData
    // ????????? DepthData
    AVCaptureSynchronizedData* videoData = [synchronizedDataCollection synchronizedDataForCaptureOutput:_videoDataOutput];
    AVCaptureSynchronizedSampleBufferData* videoDataBuffer = (AVCaptureSynchronizedSampleBufferData*)videoData;
    if(!videoDataBuffer.sampleBufferWasDropped)
    {
        CMSampleBufferRef sampleBuffer = videoDataBuffer.sampleBuffer;
        videoImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); // ???CMSampleBuffer?????????PixelBuffer
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
        // ????????????????????????????????????????????????????????????
        // ??????????????? YES????????????????????????,????????????????????????????????????
        // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????? AVCaptureSynchronizedDataCollection ?????????????????? AVCaptureSynchronizedDepthData ?????????
        AVDepthData* data = depthDataBuffer.depthData; // ?????????
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
