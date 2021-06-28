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
 

@implementation BackedCVPixelBufferMetalRecoder
{
    // Core Video 提供的metal纹理缓冲池
    CVMetalTextureCacheRef _textureCache;
    
}


-(instancetype) init
{
    self = [super init];
    
    // 创建CVMetalTextureCacheRef _textureCache，这是Core Video的Metal纹理缓存
    CVReturn result = CVMetalTextureCacheCreate(NULL, NULL, MTLCreateSystemDefaultDevice(), NULL, &_textureCache);
    
    NSAssert(result==kCVReturnSuccess, @"fail to CVMetalTextureCacheCreate");


    return self ;
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
        texture = CVMetalTextureGetTexture(metalTextureRef);
        
        // CVBufferRelease(metalTextureRef); // ??
    }
    
     
    return texture;
    
}

@end
