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
@end

@implementation CVPixelBufferPoolReader
{
	CVMetalTextureCacheRef 	_textureCache ;
	CVPixelBufferRef 		_onePixelBuffer ;
	id<MTLTexture> 			_mtlTexture ;
	RecordRender* 			_recorderRender ;
	int 					_readfirst ;
	CGSize					_size ;
}
 
-(instancetype) init:(CGSize) size WithDevice:(id<MTLDevice>)device
{
	
	self = [super init];
	
	CVReturn result = CVMetalTextureCacheCreate(NULL, NULL, MTLCreateSystemDefaultDevice(), NULL, &_textureCache);
	
	NSAssert(result==kCVReturnSuccess, @"fail to CVMetalTextureCacheCreate");
	
	
	const void *keys[] =
	{
		kCVPixelBufferMetalCompatibilityKey,
		kCVPixelBufferIOSurfacePropertiesKey,
	};

	const void *values[] =
	{
		(__bridge const void *)([NSNumber numberWithBool:YES]),
		(__bridge const void *)([NSDictionary dictionary])
	};
	
 
	CFDictionaryRef optionsDictionary = CFDictionaryCreate(NULL, keys, values, 2, NULL, NULL);
	
	 
	CVPixelBufferCreate(kCFAllocatorDefault,
						size.width,
						size.height,
						kCVPixelFormatType_32BGRA, // CVPixelBuffer 并不关系 sRGB还是RGB ??
						optionsDictionary,
						&_onePixelBuffer);
	
	CFRelease(optionsDictionary);
	
	
	CVMetalTextureRef tmpTexture = NULL;
	result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
													_textureCache,
													_onePixelBuffer,
													NULL,
													MTLPixelFormatBGRA8Unorm_sRGB,
													size.width,
													size.height,
													0,
													&tmpTexture);
	if (kCVReturnSuccess != result)
	{
		NSLog(@"[%s] CVMetalTextureCacheCreateTextureFromImage return error : %d \n", __FUNCTION__, result);
	}
	else
	{
		_mtlTexture = CVMetalTextureGetTexture(tmpTexture);
		
	}
	CFRelease(tmpTexture);
	
	_recorderRender = [[RecordRender alloc] initWithDevice:device];
	
	_size = size ;
	
	return self;
	
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
	
	if (_readfirst == 0)
	{
		_readfirst = 1 ; // 两种方案都会存在第一帧是黑帧的情况
		
#if DIRECT_GL_READ_PIXEL

		MTLRegion region =  MTLRegionMake2D(0, 0, texture.width, texture.height);
		
		size_t stride = _size.width * 4;
		
		char* cpuBuffer = (char*)malloc(stride * _size.height);
		
		[_mtlTexture getBytes:cpuBuffer bytesPerRow:stride fromRegion:region mipmapLevel:0];
	 
		/*
		 
			MTLTexture getBytes
		 
		 	https://developer.apple.com/documentation/metal/mtltexture/1516318-getbytes?language=objc
		 
		 	这个方法运行在cpu 并且立刻拷贝纹理数据到cpu端内存; 他不会同步GPU;
		 
		 	比如 你有一个命令缓冲包含渲染或者写入这个纹理, 你必须确保这个操作执行完 然后再读取纹理
		 	你可以使用 addCompletedHandler waitUntilCompleted 或者自定义的同步信号量 来确认命令缓冲已经执行完毕
		 

			如果一个纹理是private的存储方式 不用直接使用getByte, 需要使用  MTLBlitCommandEncoder 从private的纹理
		 	拷贝到 not private的纹理，然后再从这个not private的纹理读取
		 
		 	如果是PVRTC压缩纹理 需要读取整个纹理
		 
		 */
		
#else
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
		if (wrote == _size.width * _size.height * 4)
		{
			NSLog(@"write done");
		}
		close(fd);
			
		
		free(cpuBuffer);
		
	}
	
}

-(void) dealloc
{
	NSLog(@"CVPixelBuferPoolReader ~~ release ~~");
}


@end
