//
//  CVPixelBufferPoolReader.m
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/8/26.
//

#import "CVPixelBufferPoolReader.h"

#import <CoreVideo/CoreVideo.h>
#include <fcntl.h>

#include "RecordRender.h"


@interface CVPixelBufferPoolReader()

@property (atomic) BOOL isRecording ;

//-(CVPixelBufferRef)createCVPixelBufferRefFromNV12buffer:(unsigned char *)buffer width:(int)w height:(int)h ;

@end

@implementation CVPixelBufferPoolReader
{
	CVMetalTextureCacheRef 	_textureCache ;
	CVPixelBufferRef 		_onePixelBuffer ;
	id<MTLTexture> 			_mtlTexture ;
	RecordRender* 			_recorderRender ;
	int 					_readfirst ;
	CGSize					_size ;
    // 测试
    CVPixelBufferPoolRef    _yuvPixelBufferPool;
    int                     _width4test;
    int                     _height4test;
}
 
-(instancetype) init:(CGSize) size WithDevice:(id<MTLDevice>)device
{
	
	self = [super init];
	
	CVReturn result = CVMetalTextureCacheCreate(NULL, NULL, MTLCreateSystemDefaultDevice(), NULL, &_textureCache);
	
	NSAssert(result==kCVReturnSuccess, @"fail to CVMetalTextureCacheCreate");
	
	
	const void *keys[] =
	{
		kCVPixelBufferMetalCompatibilityKey,
		kCVPixelBufferIOSurfacePropertiesKey, // 注意这个 !! IOSurface是进程间内存共享的机制
	};

	const void *values[] =
	{
		(__bridge const void *)([NSNumber numberWithBool:YES]),
		(__bridge const void *)([NSDictionary dictionary])
	};
	
 
	CFDictionaryRef optionsDictionary = CFDictionaryCreate(NULL, keys, values, 2, NULL, NULL);
	
    // CVPixelBufferRef pixelBuffer = NULL;
	// CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferBool, &pixelBuffer) 这样可以从 CVPixelBufferPool创建一个CVPixelBuffer
	CVPixelBufferCreate(kCFAllocatorDefault,
						size.width,
						size.height,
						kCVPixelFormatType_32BGRA, // CVPixelBuffer 并不关系 sRGB还是RGB ??
						optionsDictionary,
						&_onePixelBuffer);
	
	CFRelease(optionsDictionary);
    
    {
        int retainCount = CFGetRetainCount(_onePixelBuffer);
        IOSurfaceRef ioSurfaceRef = CVPixelBufferGetIOSurface(_onePixelBuffer);
        int useCount = IOSurfaceGetUseCount(ioSurfaceRef);
        NSLog(@"[%d] CVPixelBuffer %d with IOSurface backend(use count %d)",  __LINE__, retainCount,  useCount);
        // CVPixelBuffer 1 with IOSurface backend(use count 1)
    }
    
	
	
	CVMetalTextureRef tmpTexture = NULL;
	result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
													_textureCache,
													_onePixelBuffer, // 不会增加CVPixelBuffer引用计数,当会增加使用计数
													NULL,
                                                    MTLPixelFormatBGRA8Unorm_sRGB,
													size.width,
													size.height,
													0,
													&tmpTexture);
    
    {
        int retainCount = CFGetRetainCount(_onePixelBuffer);
        IOSurfaceRef ioSurfaceRef = CVPixelBufferGetIOSurface(_onePixelBuffer);
        int useCount = IOSurfaceGetUseCount(ioSurfaceRef);
        NSLog(@"[%d] CVPixelBuffer %d with IOSurface backend(use count %d)",  __LINE__, retainCount,  useCount);
        // CVPixelBuffer 1 with IOSurface backend(use count 2)
    }
    
	if (kCVReturnSuccess != result)
	{
		NSLog(@"[%s] CVMetalTextureCacheCrea teTextureFromImage return error : %d \n", __FUNCTION__, result);
	}
	else
	{
		_mtlTexture = CVMetalTextureGetTexture(tmpTexture);
		
	}
	//CFRelease(tmpTexture);
    CVBufferRelease(tmpTexture);// 建议用CVBufferRelease对应CVPixelBufferRef CVBufferRetain
    

    {
        int retainCount = CFGetRetainCount(_onePixelBuffer);
        IOSurfaceRef ioSurfaceRef = CVPixelBufferGetIOSurface(_onePixelBuffer);
        int useCount = IOSurfaceGetUseCount(ioSurfaceRef);
        NSLog(@"[%d] CVPixelBuffer %d with IOSurface backend(use count %d)",  __LINE__, retainCount,  useCount);
        // CVPixelBuffer 1 with IOSurface backend(use count 1)
        
        // 只要 CVPixelBufferRef 或者 CVMetalTextureRef 其中一个有强引用, IOSurface就不会回收到CVPixelBufferPool
        // CVPixelBufferRef 和 CVMetalTextureRef 都有一个(或者多个强引用), IOSurfce的使用计数就是2 (不管CVPixelBuffer有多于1个引用)
        
    }
    
    // __FILE__ 这个是完整路径/全路径
   
	_recorderRender = [[RecordRender alloc] initWithDevice:device];
	
	_size = size ;
	
    
    // 测试+++
    // 从pool生成nv21的,不支持IOSurface的CVPixelBuffer
    {
        // #import <CoreVideo/CoreVideo.h>
        _width4test  = 736 ; // size.width;
        _height4test = 1080 ; // size.height;
        
        // 辅助属性
        // kCVPixelBufferPoolAllocationThresholdKey 如果pool持有一定数量的buffer 就不分配新的buffer 这个不会影响已分配buffer的回收; CVPixelBufferPoolCreatePixelBufferWithAuxAttributes
        
        // 缓冲池属性(pool attribute)
        // kCVPixelBufferPoolMaximumBufferAgeKey  pool中buffer的最大年龄  {kCVPIxelBufferPoolMaximumBufferAgeKey:1.0} 1.0秒
        // kCVPixelBufferPoolMinimuBufferCountKey pool中最少buffer的个数
        
        
        
        // pixelBufferAttributes 这个属性 在CVPixelBufferCreate也会有的
        NSDictionary *pixelBufferAttributes = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                                                ,(NSString*)kCVPixelBufferWidthKey:  @(_width4test) // Boxing 封装成 NSNumber对象
                                                ,(NSString*)kCVPixelBufferHeightKey: @(_height4test)
                                                
                                                // 如果需要CoreVideo使用IOSurface框架, 提供这个key的value; 传入value是空字典,使用默认IOSurface配置
                                                // 不设置这个key, 返回的CVPixelBuffer的 CVPixelBufferGetIOSurface(pixelBuffer) 是没有IOSurfaceRef
                                                //,(NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{}
                                                 
                                                // 兼容Metal
                                                // ,(__bridge NSString*)(kCVPixelBufferMetalCompatibilityKey):@(YES)
                                                
                                                // 对齐
                                                //, (NSString*)kCVPixelBufferBytesPerRowAlignmentKey:@(16) // y_stride不影响 ?? 736还是768
                                                //,(NSString*)kCVPixelBufferPlaneAlignmentKey: @(16) // 默认是64字节对齐 ??
       
                                                };

        // 对于ARC环境(自动引用计数), __bridge将OC对象 转换成Core Foundation对象, 不需要调用CFRelease释放, 对象依然是由Object-C的ARC环境管理
        // 但是 __bridge_retained/CFBridgingReation 会将所有权 转移到 CoreFounadation, 就要CFRelease释放 （并且应该避免之后再使用这个OC对象）
        CVReturn result = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)(pixelBufferAttributes), &_yuvPixelBufferPool);
        assert(result == kCVReturnSuccess);
    }
    // 测试---
    
	return self;
	
}

-(CVPixelBufferRef)createCVPixelBufferRefFromNV12buffer:(unsigned char *)buffer width:(int)w height:(int)h 
{
    
    CVPixelBufferRef pixelBuffer = NULL;
    
    // 直接创建 CVPixelBuffer 需要每次传入 pixelAttributes 以及 宽高
    // 从CVPixelBufferPool 获取 就不需要 每次配置这些参数 获取的CVPixelBuffer都是同样宽高
    // NSDictionary *pixelAttributes = @{(NSString*)kCVPixelBufferIOSurfacePropertiesKey:@{}};
    // CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, (__bridge CFDictionaryRef)(pixelAttributes), &pixelBuffer);
    
    CVReturn result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _yuvPixelBufferPool, &pixelBuffer);
    
    {
        IOSurfaceRef ioSurfaceRef = CVPixelBufferGetIOSurface(pixelBuffer);
        if (ioSurfaceRef != NULL) { // 需要配置CVPixelBufferPool的kCVPixelBufferIOSurfacePropertiesKey为true
            int useCount = IOSurfaceGetUseCount(ioSurfaceRef);
            int refCount = CFGetRetainCount(pixelBuffer);
            NSLog(@"createCVPixelBufferRefFromNV12buffer, CVPixelBuffer (reference count %d) with IOSurface backend(use count %d)", refCount, useCount);
            //  CVPixelBuffer (reference count 1) with IOSurface backend(use count 1)
        } else {
            NSLog(@"createCVPixelBufferRefFromNV12buffer, CVPixelBuffer no IOSUrface backend");
        }
    }

    CVPixelBufferLockBaseAddress(pixelBuffer,0);
    
    int bufferWidth  = (int)CVPixelBufferGetWidth(pixelBuffer);
    int bufferHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    assert(w == bufferWidth && h == bufferHeight);
    
    int planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    NSAssert(planeCount == 2, @"CVPixelBufferGetPlaneCount(%d) > 2 ", planeCount);
    
    
    int y_stride  = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    int uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
   
    int y_width   = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 0);
    int y_height  = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    int uv_width  = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 1);
    int uv_height = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    
   
    
    NSLog(@"buffer width=%d, height=%d, y_stride=%d, uv_stride=%d, y_width=%d, y_height=%d, uv_width=%d, uv_height=%d",
          bufferWidth, bufferHeight,
          y_stride, uv_stride,
          y_width, y_height, uv_width, uv_height);
    // buffer width=123,   height=420,  y_stride=128,  uv_stride=128,  y_width=123,  y_height=420,  uv_width=62,  uv_height=210
    // buffer width=1920, height=1080,  y_stride=1920, uv_stride=1920, y_width=1920, y_height=1080, uv_width=960, uv_height=540
    // buffer width=641,  height=1080,  y_stride=704,  uv_stride=704,  y_width=641,  y_height=1080, uv_width=321, uv_height=540 // 宽不是偶数, uv平面的宽都是多了一个像素的, 所以uv_width不是width//2; y_width都是等于width
    // buffer width=640,  height=1080,  y_stride=640,  uv_stride=640,  y_width=640,  y_height=1080, uv_width=320, uv_height=540
    // buffer width=736,  height=1080,  y_stride=768,  uv_stride=768,  y_width=736,  y_height=1080, uv_width=368, uv_height=540 // 使用64字节数对齐 (736->768 641->704)
    
    unsigned char *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    unsigned char *y_ch0 = buffer;
    if (buffer != NULL) {
        memcpy(yDestPlane, y_ch0, w * h);
    } else {
        memset(yDestPlane, 0x55, w * h);
    }
    
    unsigned char *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    unsigned char *y_ch1 = buffer + w * h;
    if (buffer != NULL) {
        memcpy(uvDestPlane, y_ch1, w * h/2);
    } else {
        memset(uvDestPlane, 0x55, w * h/2);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    assert(result == kCVReturnSuccess);
    if (result != kCVReturnSuccess)
    {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
    }
    return pixelBuffer;
}

-(void) startRecording
{
	if (self.isRecording)
	{
		NSLog(@"recording twice");
		return  ;
	}
	self.isRecording  = true ;
}

-(void) endRecording
{
	if (!self.isRecording)
	{
		NSLog(@"recording stopped yet");
		return  ;
	}
	self.isRecording = false ;
}


#define DIRECT_GL_READ_PIXEL 1

-(void) drawToRecorder:(id<MTLTexture>) texture  OnCommand:(id<MTLCommandBuffer>) command
{
	if (!self.isRecording)
	{
		return ;
	}
	
	[_recorderRender encodeToCommandBuffer:command sourceTexture:texture destinationTexture:_mtlTexture];
	
	//if (_readfirst == 0)
	{
		_readfirst = 1 ; // 两种方案都会存在第一帧是黑帧的情况
		
#if DIRECT_GL_READ_PIXEL

		MTLRegion region =  MTLRegionMake2D(0, 0, texture.width, texture.height);
		
		size_t stride = _size.width * 4;
		
		char* cpuBuffer = (char*)malloc(stride * _size.height);
		
		[_mtlTexture getBytes:cpuBuffer bytesPerRow:stride fromRegion:region mipmapLevel:0];
	 
		/*
		 
			MTLTexture getBytes  HHL: 不会等待完成 因为command都还没有发出去
		 
		 	https://developer.apple.com/documentation/metal/mtltexture/1516318-getbytes?language=objc
		 
		 	这个方法运行在cpu 并且立刻拷贝纹理数据到cpu端内存; 他不会同步GPU;
		 
		 	比如 你有一个命令缓冲包含渲染或者写入这个纹理, 你必须确保这个操作执行完 然后再读取纹理
		 	你可以使用 addCompletedHandler waitUntilCompleted 或者自定义的同步信号量 来确认命令缓冲已经执行完毕
		 

			如果一个纹理是private的存储方式 不用直接使用getByte, 需要使用  MTLBlitCommandEncoder 从private的纹理
		 	拷贝到 not private的纹理，然后再从这个not private的纹理读取
		 
		 	如果是PVRTC压缩纹理 需要读取整个纹理
		 
		 */
        
        
        {
            int width  = _width4test;
            int height = _height4test;
            CVPixelBufferRef nv12buffer = [self createCVPixelBufferRefFromNV12buffer:(unsigned char *)NULL width:width height:height];
            [command addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
                CVBufferRelease(nv12buffer);
            }];
        }

#else
        // 把CVPixelBuffer的内存 映射 到 本进程的VMA中 ?  可能不同步, GPU没有渲染完成
		CVPixelBufferLockBaseAddress(_onePixelBuffer , 0);
		unsigned char* ptr = (unsigned char*)CVPixelBufferGetBaseAddress(_onePixelBuffer);

		size_t stride = CVPixelBufferGetBytesPerRow(_onePixelBuffer);
		
		size_t actual = _size.width * 4;
		//assert(stride == _size.width * 4, "stride is not match ");
		

		char* cpuBuffer = (char*)malloc(stride * _size.height);
		char* dst = cpuBuffer;
		for(int i=0; i < _size.height; ++i)
		{
			memcpy(dst, ptr, actual);
			ptr += stride;
			dst += actual;
		}
		
		CVPixelBufferUnlockBaseAddress(_onePixelBuffer, 0);
		
#endif
		
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *docPath = paths.firstObject;
		NSString *fullPath = [docPath stringByAppendingPathComponent:@"temp.rgba"];
		const char * path = [fullPath UTF8String];
		
		int fd = open(path, O_CREAT|O_TRUNC|O_WRONLY, 0755);
		int wrote = write(fd, cpuBuffer, _size.width * _size.height * 4);
		if (wrote == _size.width * _size.height * 4) {
			if (_readfirst - 1 == 0) NSLog(@"write done");
        } else {
            NSLog(@"[%s][%d] write error ", __FILE__, __LINE__);
        }
		close(fd);
			
		
		free(cpuBuffer);
		
	}
	
}

-(void) dealloc
{
    if (_onePixelBuffer != NULL)
    {
        CVBufferRelease(_onePixelBuffer);
        _onePixelBuffer = NULL;
    }
	NSLog(@"CVPixelBuferPoolReader ~~ release ~~");
}


@end
