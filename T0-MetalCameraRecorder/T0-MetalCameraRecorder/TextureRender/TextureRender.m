//
//  TextureRender.m
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2024/1/31.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h> //  MTKTextureLoader 的头文件

#import "TextureRender.h"
#import "TextureRenderShaderType.h" // metal与c代码 接口 结构体

@interface TextureRender()
// @property (nonatomic, assign) int private_property ; // 类的扩展--私有属性 Extension  对已有类的增加属性要用'分类'(Category)或者子类
@end

@implementation TextureRender
{
    // 成员变量
    id<MTLRenderPipelineState> _renderPipelineState ;
    id<MTLBuffer> _vertexBuffer ;
    id<MTLTexture> _texture;
    int picOrder ;
    id <MTLDevice> _device;
}

#pragma  public function

-(nonnull instancetype) initWithDevice: (nonnull id <MTLDevice>) device
{
    self = [super init];
    if (self)
    {
        _device = device;
        _texture = nil;
        [self _setupMetal:device];
        [self loadAssets:device];
    }
    else
    {
        NSLog(@"CameraRender init fail");
    }
    return self ;
}

-(void) encodeToCommandBuffer: (nonnull id <MTLCommandBuffer>) commandBuffer
                sourceTexture: (nullable id <MTLTexture>) _no_in_used
           destinationTexture: (nonnull id <MTLTexture>) destinationTexture
{
    MTLRenderPassDescriptor* renderPass = [[MTLRenderPassDescriptor alloc] init];
    renderPass.colorAttachments[0].loadAction = MTLLoadActionLoad ; // MTLLoadActionClear 不清除原来fbo color纹理上的数据
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore ;
    renderPass.colorAttachments[0].texture = destinationTexture;
    
    // 更新一下纹理
    picOrder = 0;
    id<MTLTexture> texture1 = [self updateTextureByCG];
    
    id<MTLRenderCommandEncoder> encoder  = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    encoder.label = @"TextureMapEncode";
    [encoder pushDebugGroup:@"TextureMapEncodeGroup"];
    [encoder setRenderPipelineState:_renderPipelineState];
    
    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [encoder setFragmentTexture:texture1 atIndex:0];
 
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    
    [encoder popDebugGroup];
    
    // 更新一下纹理 (对于Metal来说, 左右两边 都是画了同一个图 对于GLES来说 一个纹理在两次draw中间修改了图像,两次draw的纹理对应图像是不同的)
    picOrder = 1;
    id<MTLTexture> texture2 =  [self updateTextureByCG];
    
    NSAssert(texture1 == texture2, @"MTLTexture should be same");
    
    [encoder pushDebugGroup:@"TextureMapEncodeGroup2"];
    [encoder setRenderPipelineState:_renderPipelineState];
    
    [encoder setVertexBuffer:_vertexBuffer offset:_vertexBuffer.length/2 atIndex:0]; // 从vertexBuffer下半部分开始
    [encoder setFragmentTexture:texture2 atIndex:0];
 
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    
    [encoder popDebugGroup];
    
    
    [encoder endEncoding];
    
    
}


#pragma private function

-(void) _setupMetal:(id<MTLDevice>) device
{
    
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"TextureRenderVertex"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"TextureRenderFragment"];
    
    
    MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    renderPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; // 附着的颜色附件必须是RGBA8+sRGB 因为encodeToCommandBuffer传入的destinationTexture是MetalFrameBuffer 
    renderPipelineDesc.colorAttachments[0].blendingEnabled = NO ; // 不用混合
    
    renderPipelineDesc.depthAttachmentPixelFormat   = MTLPixelFormatInvalid;
    renderPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
    
    renderPipelineDesc.vertexFunction   = vertexFunction;
    renderPipelineDesc.fragmentFunction = fragmentFunction;
    
    renderPipelineDesc.sampleCount = 1 ;
    renderPipelineDesc.label = @"TextureRender";
    
    NSError* error ;
    _renderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
    NSAssert(_renderPipelineState != nil, @"newRenderPipelineStateWithDescriptor fail %@", error);
    
}


const NSString* kPictures[] = {
   @"cat1",
   @"cat2",
   @"cat3",
};

const NSString*  kPicturesPost[] = {
   @"jpg",
   @"jpg",
   @"jpg",
};


-(void) loadAssets:(id<MTLDevice>) device
{
    // 加载顶点属性 // Metal中纹理空间的坐标系如下，左上角为原点(不同于OpenGL纹理坐标空间原点在左下角)
    static MyVertex vertex[] = {
        { {-0.5,   0},  {0.5,  0}  },
        { {0,     -1},  {1.0, 1.0} },
        { {-1,    -1},  {0,   1.0} },
        
        { {0.5,   0},   {0.5,  0}  },
        { {1,     -1},  {1.0, 1.0} },
        { {0,    -1},   {0,   1.0} }
        
    };
    _vertexBuffer = [device newBufferWithBytes:vertex length:sizeof(vertex) options:MTLResourceStorageModeShared];
 
}

-(id<MTLTexture>) updateTextureByCG
{
    

    NSURL* path = [[NSBundle mainBundle] URLForResource:kPictures[picOrder]  withExtension:kPicturesPost[picOrder]];
    CGImageSourceRef sourceRef = CGImageSourceCreateWithURL((__bridge CFURLRef)path, NULL); // 图像源
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(sourceRef, 0, NULL); // 解码图像 typedef struct CGImage* CGImageRef
    
    
    size_t width  = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    size_t stride = CGImageGetBytesPerRow(imageRef);
    {
        size_t bitsPerPixel = CGImageGetBitsPerPixel(imageRef);
        size_t bitsPerComp  = CGImageGetBitsPerComponent(imageRef);
        //NSLog(@"width %d height %d strite %d bitsPerPixel %d bitsPerComp %d", width, height, stride, bitsPerPixel, bitsPerComp);
        // width 640 height 480 strite 2560 bitsPerPixel 32 bitsPerComp 8
    }
    {
        CGImagePixelFormatInfo pixelFormat = CGImageGetPixelFormatInfo(imageRef);
        //NSLog(@"pixelFormat %d", pixelFormat);
        // pixelFormat 0
    }
    {
        CGColorSpaceRef space = CGImageGetColorSpace(imageRef);
        CFStringRef name = CGColorSpaceGetName(space); //  @"kCGColorSpaceSRGB"
        CGColorSpaceModel model = CGColorSpaceGetModel(space); // kCGColorSpaceModelRGB 使用RGB颜色空间
    }
    {
        CGImageAlphaInfo alphaInfo =  CGImageGetAlphaInfo(imageRef);
        // kCGImageALphaFirst alpha分量存储在每个像素最高位 非预乘ARGB
        // kCGImageALphaLast  RGBA
        // kCGImageAlphaNone  没有alpha通道 RGB
        // kCGImageAlphaNoneSkipFirst  没有alpha通道 ?如果总大小大于颜色色量 忽略最高位 RGBX
        // kCGImageAlphaNoneSkipLast   没有alpha通道 填充了?最低位  XRGB
        // kCGImageAlphaOnly 没有颜色数据 只有一个alpha通道
        // kCGImageAlphaPremultipiledFirst ARGB  颜色分量已经预乘
        // kCGImageAlpahPremultipliedLast  RGBA
        if (alphaInfo == kCGImageAlphaNone || alphaInfo == kCGImageAlphaNoneSkipLast || alphaInfo == kCGImageAlphaNoneSkipFirst) {
            //NSLog(@"图像是RGB %d", alphaInfo); // 图像是RGB 5
        } else {
            NSLog(@"图像是RGAB %d", alphaInfo);
        }
    }

     
    
    CGDataProviderRef provider =  CGImageGetDataProvider(imageRef);
    CFDataRef rawData = CGDataProviderCopyData(provider);
    
    const uint8_t* buffer = CFDataGetBytePtr(rawData);
    const int32_t length  = CFDataGetLength(rawData);
    
    
    
    if (_texture == nil) {
        MTLTextureDescriptor* des = [[MTLTextureDescriptor alloc] init];
        des.pixelFormat = MTLPixelFormatRGBA8Unorm_sRGB;
        des.width  = width;
        des.height = height;
        _texture = [_device newTextureWithDescriptor:des];
    }
    
    [_texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:buffer bytesPerRow:stride];
    
    CFRelease(rawData);
    
    CGImageRelease(imageRef);
    CFRelease(sourceRef);
    
    
    picOrder++;
    picOrder = picOrder % (sizeof(kPictures)/sizeof(kPictures[0]));
    
    return _texture;
    
}

-(void) loadTextureByMTK:(id<MTLDevice>) device useSrgb:(BOOL)isSRGB
{
    NSError *error;
    MTKTextureLoader* textureloader = [[MTKTextureLoader alloc] initWithDevice:device];
    
    NSDictionary* textureLoaderOptions = @{
        MTKTextureLoaderOptionTextureUsage: @(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode: @(MTLStorageModePrivate)
        ,MTKTextureLoaderOptionSRGB:@(isSRGB)
    };
    // 如果是NO,那么图片数据会作为linearRGB; 如果是YES,那么图片数据作为sRGB 如果不配置, 如果不配置并且加载时候做了伽马纠正,只会使用sRGB信息??
    // !!!如果是linearRGB的图片 作为sRGB图片来对待 那么就会变暗!!!
    
    if (!isSRGB)
    {
        picOrder++;
        picOrder = picOrder % (sizeof(kPictures)/sizeof(kPictures[0]));
    }
    
    NSURL* path = [[NSBundle mainBundle] URLForResource:kPictures[picOrder]  withExtension:kPicturesPost[picOrder]]; // 默认是sRGB 会显示比较暗
    _texture = [textureloader newTextureWithContentsOfURL:path options:textureLoaderOptions error:&error];
    if (_texture == nil)
    {
        NSLog(@"MTKTextureLoader  newTextureWithName fail %@", error);
    }
    
    NSLog(@" _texture 引用计数 %lu ", CFGetRetainCount((__bridge CFTypeRef)(_texture))); // 这个就是 2 ;
    NSLog(@"MTLTextureLoader is RGB? RGBA? %lu", (unsigned long)_texture.pixelFormat);
}



@end

