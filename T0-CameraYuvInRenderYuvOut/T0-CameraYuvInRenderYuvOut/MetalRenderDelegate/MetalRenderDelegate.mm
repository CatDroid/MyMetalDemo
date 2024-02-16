//
//  MetalRenderDelegate.m
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#import "MetalRenderDelegate.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CVMetalTextureCache.h>
#import <AVFoundation/AVFoundation.h>

#import <os/lock.h>
#import <queue>

#import "MetalView.h"
#import "CameraDevice.h"


 
static int kMtlTextureQueueSize = 3;

// 匿名分类 类扩展 不想外面知道内部实现的协议
@interface MetalRenderDelegate() <CameraMetalFrameDelegate>

@end


@implementation MetalRenderDelegate
{
    id<MTLDevice>           _globalDevice ;
    id <MTLCommandQueue>    _commandQueue ;
    CVMetalTextureCacheRef  _textureCache ;
    
    id <MTLRenderPipelineState> _pipelineStateYuv2Rgb ;
    id <MTLRenderPipelineState> _pipelineStateScreen  ;
    id <MTLRenderPipelineState> _pipelineStateRgb2Yuv ;
    
    
    id <MTLBuffer>          _attributeBuffer;
    id <MTLBuffer>          _uniformBuffer  ;
    id <MTLBuffer>          _uniformBufferYuv2Rgb;
    id <MTLTexture>         _rgbaTexture    ;
    id <MTLTexture>         _yuv420pTexture ;
    id <MTLSamplerState>    _samplerState   ;

    // 相机
    CameraDevice* _cameraDevice ;
    
    
    // 相机输出缓冲队列
    std::queue<CVPixelBufferRef> _mtlTextureRefQueue;
    os_unfair_lock spinLock;
    
    // 统计
    int frameCount;
    UInt64 lastTime;

    
}

static const int kWidth  = 720 ;
static const int kHeight = 1280;


#pragma mark - shader type 共同部分
typedef struct
{
    vector_float3 a_position ;
    vector_float2 a_uv ;
} MyVertex;


#pragma mark - yuv2rgb

static const char* sYuv2RgbShader = R"(

#include <simd/simd.h>
#include <metal_stdlib>
using namespace metal;

typedef struct
{
    vector_float3 a_position ;
    vector_float2 a_uv ;
} MyVertex;

typedef struct
{
    float4 pos [[position]];
    float2 texCoord;
} VertexOut ;


vertex VertexOut vertexStage(
                                uint vid [[vertex_id]],
                                constant MyVertex *vertexArr [[buffer(0)]]     // 第0个Buffer
                                //, constant float&    _flipY    [[buffer(1)]]   // 第1个Buffer
                                )
{
    float3 a_position = vertexArr[vid].a_position;
    float2 a_uv = vertexArr[vid].a_uv;

    VertexOut out ;
    out.pos      = vector_float4(a_position, 1.0);
    out.texCoord = vector_float2(a_uv.x,  a_uv.y);
    
    return out ;
}

// 直接改了纹理坐标
// v_texCord.x = 1.0 - v_texCord.x ; // metal .y


constant float3x3 bt601_fullrange = float3x3(1.0, 1.0, 1.0,     0.0, - 0.344, 1.77,     1.403, - 0.714, 0.0);

constant float3x3 bt709_videorange = float3x3(1.164, 1.164, 1.164,    0.0, -0.213, 2.114,     1.792, -0.534, 0.0);

fragment float4 fragmentStage(
                                 const VertexOut in [[stage_in]],
                                 texture2d<float, access::sample> yTex  [[texture(0)]],
                                 texture2d<float, access::sample> vuTex [[texture(1)]],
                                 sampler samplr [[sampler(0)]]
                                 )
{

    float y   = yTex.sample(samplr, in.texCoord).r - 0.0625; // 16/256=0.0625   128/256=0.5
    float2 uv = vuTex.sample(samplr, in.texCoord).rg - vector_float2(0.5); // metal .ar
    float3 yuvNv21   = vector_float3(y, uv);
    float4 fragColor = vector_float4(bt709_videorange * yuvNv21, 1.0);
    return fragColor;
}

)";


#pragma mark -- rgb to screen

static const char* sRgbToScreen = R"(

#include <metal_stdlib>
using namespace metal;

#include <simd/simd.h>


typedef struct
{
    vector_float3 a_position ;
    vector_float2 a_uv ;
} MyVertex;

typedef struct
{
    float4 pos [[position]];
    float2 texCoord;
} VertexOut ;


vertex VertexOut vertexStage(  constant MyVertex* vertexes [[buffer(0)]],
                               metal::uint32_t vid [[vertex_id]]
                            )
{
    VertexOut out;
    MyVertex attr = vertexes[vid];
    out.pos = float4(attr.a_position, 1.0);
    out.texCoord = attr.a_uv ;
    return out ;
}
 
fragment float4 fragmentStage(
                                     VertexOut in [[stage_in]],
                                     texture2d<float,access::sample> colorTex [[texture(0)]],
                                     sampler samplr [[sampler(0)]]
                                     )
{
    float4 color = colorTex.sample(samplr, in.texCoord);
    return color ;
}

)";

#pragma mark -- rgb to yuv


typedef struct
{
    vector_float2 uv_Offset; //偏移量 1.0/Srcwidth, 1.0/Srcheight, isFlip?1.0:0.0
    float rotateMode;
    float isFullRange;
} UniformBuffer ;



static const char* sRgbToYuv = R"(

#include <simd/simd.h>
#include <metal_stdlib>
using namespace metal;

//这里的转换公式是 601 full-range, 需要和上屏的时候的yuv->rgb对应
constant static float3 COEF_full_Y = float3( 0.299f,  0.587f,  0.114f);
constant static float3 COEF_full_U = float3(-0.169f, -0.331f,  0.5f);
constant static float3 COEF_full_V = float3( 0.5f, -0.419f, -0.08100f);

//这里的转换公式是 709 video-range, 需要和上屏的时候的yuv->rgb对应
constant static float3 COEF_video_Y = float3( 0.183f,  0.614f,  0.062f);
constant static float3 COEF_video_U = float3(-0.101f, -0.339f,  0.439f);
constant static float3 COEF_video_V = float3( 0.439f, -0.399f, -0.040f);
constant static float U_DIVIDE_LINE = 2.0f / 3.0f;
constant static float V_DIVIDE_LINE = 5.0f / 6.0f;
constant static float3 CONDITION_ = float3(U_DIVIDE_LINE, V_DIVIDE_LINE, 0.5);


typedef struct
{
    vector_float3 a_position ;
    vector_float2 a_uv ;
} MyVertex;

typedef struct
{
    float4 pos [[position]];
    float2 texCoord;
} VertexOut ;

typedef struct
{
    vector_float2 uv_Offset; //偏移量 1.0/Srcwidth, 1.0/Srcheight, isFlip?1.0:0.0
    float rotateMode;
    float isFullRange;
} UniformBuffer ;

vertex VertexOut vertexStage(
                                    constant MyVertex* vertexes [[buffer(0)]],
                                    metal::uint32_t vid [[vertex_id]]
                              
                                    )
{
    VertexOut out;
    MyVertex attr = vertexes[vid];
    out.pos = float4(attr.a_position, 1.0);
    out.texCoord = attr.a_uv ;
    return out ;
}
 
fragment float4 fragmentStage(
                                     VertexOut in [[stage_in]],
                                     texture2d<float,access::sample> colorTex [[texture(0)]],
                                     constant UniformBuffer* uniformbuffer [[buffer(0)]],
                                     sampler samplr [[sampler(0)]]
                                     )
{

    float2 uv_Offset  = uniformbuffer->uv_Offset;
    float rotateMode  = uniformbuffer->rotateMode;
    float isFullRange = uniformbuffer->isFullRange;

    float2 v_texCoord = in.texCoord;

    float3 _condition = step(CONDITION_, v_texCoord.yyx);

    float isY = _condition.x; // true 0, false 1
    float isU = isY * _condition.y;
    float isLeft = _condition.z;

    float2 _texCoord;

    float isVertical = rotateMode == 270 ? 1.0 : (rotateMode == 90.0 ? 1.0 : 0.0);//1是竖屏， 0是横屏

    float2 uv_OffsetNew = isVertical * uv_Offset.yx + (1.0 - isVertical) * uv_Offset;

    float _DIVIDE_LINE = (1.0 - isU) * U_DIVIDE_LINE + isU * V_DIVIDE_LINE;
    float offsetY = 1.0 / 3.0 * uv_OffsetNew.y;
    _texCoord.y = (1.0 - isY) * (v_texCoord.y * 3.0 / 2.0) + isY * (((v_texCoord.y - _DIVIDE_LINE) * 2.0 + isLeft * offsetY) * 3.0);
    _texCoord.x = v_texCoord.x * (1.0 + isY) - isY * isLeft;

    float2 _offset = float2((1.0 + isY) * uv_OffsetNew.x, 0.0);


    //竖屏如果是270度，说明需要顺时针旋转90恢复和输入一样的；90就顺时针旋转270
    float2 _texCoordVer = rotateMode == 270.0 ? float2(_texCoord.y, abs(1.0 - _texCoord.x)) : float2(abs(1.0 - _texCoord.y), _texCoord.x);
    float2 _offsetVer = rotateMode == 270.0 ? float2(_offset.y, (0.0 - _offset.x)) : _offset.yx;

    //横屏如果是180度，说明需要顺时针旋转180恢复和输入一样的；0就不用转了
    float2 _texCoordHon = rotateMode == 180.0 ? float2(abs(1.0 - _texCoord.x), abs(1.0 - _texCoord.y)) : _texCoord.xy;
    float2 _offsetHon = rotateMode == 180.0 ? float2(0.0 - _offset.x, 0.0 - _offset.y) : _offset;

    float2 _texCoordFinal = isVertical * _texCoordVer + (1.0 - isVertical) * _texCoordHon;
    float2 _offsetFinal = isVertical * _offsetVer + (1.0 - isVertical) * _offsetHon;

    float4 color0 = colorTex.sample(samplr, _texCoordFinal.xy);
    float4 color1 = colorTex.sample(samplr, _texCoordFinal.xy +  _offsetFinal);
    float4 color2 = colorTex.sample(samplr, _texCoordFinal.xy +  2.0 * _offsetFinal);
    float4 color3 = colorTex.sample(samplr, _texCoordFinal.xy +  3.0 * _offsetFinal);

    float3 _COEF_full = (1.0 - isY) * COEF_full_Y + isY * ((1.0 - isU) * COEF_full_U + isU * COEF_full_V);
    float3 _COEF_video = (1.0 - isY) * COEF_video_Y + isY * ((1.0 - isU) * COEF_video_U + isU * COEF_video_V);
    float3 _COEF = isFullRange == 1.0 ? _COEF_full : _COEF_video;

    float y0 = dot(color0.rgb, _COEF);
    float y1 = dot(color1.rgb, _COEF);
    float y2 = dot(color2.rgb, _COEF);
    float y3 = dot(color3.rgb, _COEF);
    float4 mainColor = float4(y0, y1, y2, y3) + isY * 0.5 + (1.0 - isFullRange) * (1.0 - isY) * 0.0625; // 16/256=0.0625
    return mainColor ;

}

)";

#pragma mark - 构造函数

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
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm; //MTLPixelFormatBGRA8Unorm_sRGB ; // 摄像头出来的数据是sRGB  所以不用设置输出的纹理是SRGB(不用硬件做线性RGB到sRGB的转换)
 
    view.clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
    
    
    _textureCache = NULL;
    CVReturn result = CVMetalTextureCacheCreate(nil, nil, view.device, nil, &_textureCache);
    NSAssert(result == kCVReturnSuccess, @"CVMetalTextureCacheCreate fail");
    

    _commandQueue = [_globalDevice newCommandQueue];
}


-(void) _setupRender:(id<MTLDevice>) device WithView:(MetalView*)view
{

    
    // yuv2rgb
    {
        NSError *errors;
        NSString* shaderString = [NSString stringWithUTF8String:sYuv2RgbShader];
        
        id <MTLLibrary> library = [device newLibraryWithSource:shaderString options:nil error:&errors];
        NSAssert(library != nil ,@"Compile Error %s", [[errors description] UTF8String]);
      
        
        id<MTLFunction> vertextFunction =  [library newFunctionWithName:@"vertexStage"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragmentStage"];
        NSAssert (vertextFunction != nil && fragmentFunction != nil, @"yuv2rgb Function not found");
         
        MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.vertexFunction   = vertextFunction ;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
        
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; //MTLPixelFormatRGBA8Unorm; // 对应_rgbaTexture格式
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = NO ;                  //  不用混合
        pipelineStateDescriptor.depthAttachmentPixelFormat   = MTLPixelFormatInvalid ;      //  不需要-深度附件
        pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatInvalid ;      //  不需要-模版附件
        pipelineStateDescriptor.rasterSampleCount  = 1 ;                                    //  sampleCount is deprecate

        
        errors = NULL;
        _pipelineStateYuv2Rgb = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&errors];
        NSAssert(_pipelineStateYuv2Rgb != nil , @"%s: _pipelineState yuv2rgb %@", __FUNCTION__, errors);
    }
  
    // screen
    {
        NSError *errors;
        NSString* shaderString = [NSString stringWithUTF8String:sRgbToScreen];
        
        id <MTLLibrary> library = [device newLibraryWithSource:shaderString options:nil error:&errors];
        NSAssert(library != nil ,@"Compile Error %s", [[errors description] UTF8String]);
        
        id<MTLFunction> vertexFunction =  [library newFunctionWithName:@"vertexStage"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragmentStage"];
        
        MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.vertexFunction = vertexFunction ;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
        
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;  // 这个应该跟view/framebuffer格式一样
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = NO;
        pipelineStateDescriptor.rasterSampleCount = 1 ;
        
        errors = NULL;
        _pipelineStateScreen = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&errors];
        NSAssert(_pipelineStateScreen != nil , @"%s: _pipelineState screen %@", __FUNCTION__, errors);
    }
    
    // rgb2yuv
    {
        NSError *errors;
        NSString* shaderString = [NSString stringWithUTF8String:sRgbToYuv];
        
        id <MTLLibrary> library = [device newLibraryWithSource:shaderString options:nil error:&errors];
        NSAssert(library != nil ,@"Compile Error %s", [[errors description] UTF8String]);
        
        id<MTLFunction> vertexFunction   = [library newFunctionWithName:@"vertexStage"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragmentStage"];
        
        MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.vertexFunction = vertexFunction ;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
        
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;  // rgb转到yuv 使用线性bgra
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = NO;
        pipelineStateDescriptor.rasterSampleCount = 1 ;
        
        errors = NULL;
        _pipelineStateRgb2Yuv = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&errors];
        NSAssert(_pipelineStateRgb2Yuv != nil , @"%s: _pipelineState rgb2yuv %@", __FUNCTION__, errors);
    }
    
    // sampler
    {
        MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
        samplerDesc.magFilter = MTLSamplerMinMagFilterNearest; // 都不使用插值 直接计算坐标
        samplerDesc.minFilter = MTLSamplerMinMagFilterNearest;
        //samplerDesc.mipFilter = MTLSamplerMipFilterNotMipmapped ;
        samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        _samplerState = [device newSamplerStateWithDescriptor:samplerDesc];
    }
    // attribute buffer
    {
        MyVertex vertexData[] = {
            {{1.0f,  1.0f,  0.0f},  {1.0f, 0.0f}},
            {{1.0f, -1.0f,  0.0f},  {1.0f, 1.0f}},
            {{-1.0f,  1.0f, 0.0f},  {0.0f, 0.0f}},
            {{ 1.0f, -1.0f, 0.0f},  {1.0f, 1.0f}},
            {{-1.0f, -1.0f, 0.0f},  {0.0f, 1.0f}},
            {{-1.0f,  1.0f, 0.0f},  {0.0f, 0.0f}},
        };
        
        // MTLResourceCPUCacheModeWriteCombined 写组合CPU缓存模式，针对CPU写入但从不读取的资源进行了优化
        // MTLResourceStorageModeShared         资源存储在系统内存中，CPU 和 GPU 都可以访问。
        _attributeBuffer = [device newBufferWithBytes:vertexData 
                                               length:sizeof(vertexData)
                                              options:MTLResourceStorageModeShared|MTLResourceCPUCacheModeWriteCombined];
     
    }
    
    // uniform buffer // 写死参数 不旋转
    {
        UniformBuffer rgbToYuvUniformBuffer ;
        rgbToYuvUniformBuffer.isFullRange = 0;
        rgbToYuvUniformBuffer.rotateMode  = 0;
        rgbToYuvUniformBuffer.uv_Offset = simd_make_float2(1.0/kWidth, 1.0/kHeight) ;
        _uniformBuffer = [device newBufferWithBytes:&rgbToYuvUniformBuffer
                                             length:sizeof(rgbToYuvUniformBuffer)
                                            options:MTLResourceStorageModeShared|MTLResourceCPUCacheModeWriteCombined];
    }
    
    {
        float flipLoc = -1.0 ;
        _uniformBufferYuv2Rgb = [device newBufferWithBytes:&flipLoc 
                                                    length:sizeof(flipLoc)
                                                   options:MTLResourceStorageModeShared|MTLResourceCPUCacheModeWriteCombined] ;
        // float* _flipLoc = (float*)_uniformBuffer.contents;
        // *_flipLoc = flipLoc;
        
    }
    
    // off-screen rgb texture 写死参数 不旋转
    {
        
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat =  MTLPixelFormatBGRA8Unorm;
        textureDescriptor.textureType = MTLTextureType2D;
        textureDescriptor.width =  kWidth;
        textureDescriptor.height = kHeight;
        textureDescriptor.usage = MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
        _rgbaTexture = [device newTextureWithDescriptor:textureDescriptor];
    }
    
    // _yuv420p Texture 写死参数 不旋转
    {
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat =  MTLPixelFormatBGRA8Unorm; // MTLPixelFormatBGRA8Unorm_sRGB yuv转成rgb 直接当做是线性rgb来处理
        textureDescriptor.textureType = MTLTextureType2D;
        textureDescriptor.width =  kWidth / 4;
        textureDescriptor.height = int(kHeight  * 1.5) ;
        textureDescriptor.usage = MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
        textureDescriptor.storageMode = MTLStorageModeShared;
        _yuv420pTexture = [device newTextureWithDescriptor:textureDescriptor];
    }
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
    CVPixelBufferRef pixelBuffer = NULL;
    os_unfair_lock_lock(&spinLock);
    if (!_mtlTextureRefQueue.empty()) {
        pixelBuffer = _mtlTextureRefQueue.front();
        _mtlTextureRefQueue.pop();
    }
    os_unfair_lock_unlock(&spinLock);
    
    if (pixelBuffer == NULL) {
        NSLog(@"skip ref is null on render thread");
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
    
    // 覆盖原来摄像头数据
    if (FALSE) {
        
        NSAssert( CVPixelBufferGetPlaneCount(pixelBuffer) == 2, @"Plane Count != 2" );
        
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        uint8_t* yBase  = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        uint8_t* uvBase = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        int imageWidth  = (int)CVPixelBufferGetWidth(pixelBuffer); // 720
        int imageHeight = (int)CVPixelBufferGetHeight(pixelBuffer);// 1280
        
        int y_stride  = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0); // 768 -- 64字节对齐
        int uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1); // 768
       
        int y_width   = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 0); // 720
        int y_height  = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0); // 1280
        int uv_width  = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 1); // 360
        int uv_height = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 1); // 640
        
       
        //NSAssert(y_stride  == imageWidth, @"y_stride %d != imageWidth %d", y_stride, imageWidth);
        //NSAssert(uv_stride == imageWidth, @"uv_stride %d != imageWidth %d", uv_stride, imageWidth);
        static bool logOnce1 = false;
        if (logOnce1) {
            logOnce1 = false ;
            
            int R = 220; //100;
            int G = 50;  // 150;
            int B = 10; // 200
            float Y  = 16 + 0.183 * R + 0.614 * G + 0.062 * B;
            float Cb =128 - 0.101 * R - 0.339 * G + 0.439 * B;
            float Cr =128 + 0.439 * R - 0.399 * G - 0.040 * B;
            
//            int Y1  = (int)Y;
//            int Cb1 = (int)Cb;
//            int Cr1 = (int)Cr;
            
//            float Y1  = Y;
//            float Cb1 = Cb;
//            float Cr1 = Cr;
                
            int Y1  = roundf(Y);
            int Cb1 = roundf(Cb);
            int Cr1 = roundf(Cr); 
            // roundf > float > int
            // roundf  之后  转换成RGB 直接int或者roundf 都是对的
            // float 直接计算 转换成RGB 直接int是有-1误差 roundf是对的
            // int   截断之后 转换成RGB 有比较大误差 -4
 
            NSLog(@"Y:%f(%d), Cb:%f(%d), Cr:%f(%d)", 
                  Y , Y1 ,
                  Cb, Cb1,
                  Cr, Cr1
                  );
            
            float R1 = 1.164 * (Y1 - 16)                       + 1.792 * (Cr1 - 128);
            float G1 = 1.164 * (Y1 - 16) - 0.213 * (Cb1 - 128) - 0.534 * (Cr1 - 128);
            float B1 = 1.164 * (Y1 - 16) + 2.114 * (Cb1 - 128);
            
            NSLog(@"R:%d,G:%d,B:%d -> %d,%d,%d(float=%f,%f,%f)(roundf=%d %d %d)",
                  R, G, B,
                  (int)R1, (int)G1, (int)B1,
                  R1, G1, B1,
                  (int)roundf(R1), (int)roundf(G1), (int)roundf(B1)
                  );
            
        }
        
        int R = 211;
        int G = 240;
        int B = 235;
        float Y  = 16 + 0.183 * R + 0.614 * G + 0.062 * B;
        float Cb =128 - 0.101 * R - 0.339 * G + 0.439 * B;
        float Cr =128 + 0.439 * R - 0.399 * G - 0.040 * B;
        NSAssert( (Y >= 0 && Y <= 255)
                 && (Cb >= 0 && Cb <= 255)
                 && (Cr >= 0 && Cr <= 255),
                 @"out of range %f %f %f", Y, Cb, Cr);
        
        uint8_t overrideY  = (uint32_t)Y;//87u;//138u; // metal shader按照除以255归一化 119/255 = 0.4666..
        uint8_t overrideCb = (uint32_t)Cb;//93u;//154u; // (Y:119,Cb:34,Cr:51)可能不是有效的YCbCr组合,转换成RGB会得到某些分量是负数(R和G是负数 截断成0)
        uint8_t overrideCr = (uint32_t)Cr;//204u;//104u;
        
        // override y :
        memset(yBase, overrideY, y_stride * y_height);

        // override uv:
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  ios是小端（低字节在低位/低地址)  从低地址--高地址: YYYYY--CbCrCbCr  Cr是高地址
        uint16_t uv = ((uint16_t)overrideCr << 8) + (uint16_t)overrideCb;
        uint16_t* uvBase16 = (uint16_t*)uvBase;
        for (int j = 0; j < uv_height; j++)
        {
            for (int i = 0; i < uv_stride / 2; i++ ) // uv_width = 360  uv_stride/2 = 768/2 = 384  多了24个像素  每个像素2个字节(分别存放u和v)
            {
                *(uvBase16++) = uv;
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }

    
    size_t width  = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    static bool logOnce = true ;
    if (logOnce) {
        logOnce = false ;
        
        CFStringRef colorAttachments = (CFStringRef)CVBufferCopyAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
        if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo) {
            NSLog(@"BT.601 颜色空间");
        } else if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_709_2, 0) == kCFCompareEqualTo) {
            NSLog(@"BT.709 颜色空间");
        } else if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_2020, 0) == kCFCompareEqualTo) {
            NSLog(@"BT.2020 颜色空间");
        //} else if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_DCI_P3, 0) == kCFCompareEqualTo) {
        //    NSLog(@"DCI_P3 颜色空间");
        //} else if (CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_P3_D65, 0) == kCFCompareEqualTo) {
        //    NSLog(@"P3_D65 颜色空间");
        } else {
            const char* cString = CFStringGetCStringPtr((CFStringRef)colorAttachments , kCFStringEncodingUTF8);
            NSLog(@"? 颜色空间是 %s", cString );
        }
        CFRelease(colorAttachments);
    }

     
    CVMetalTextureRef yMetalTextureRef  = NULL;
    CVReturn yResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, NULL,
                                                                 MTLPixelFormatR8Unorm,  width,  height, 0,  &yMetalTextureRef);
    NSAssert(yResult == kCVReturnSuccess ,@"create y texture fail");
     
 
    CVMetalTextureRef uvMetalTextureRef = NULL;
    CVReturn uvResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,  _textureCache, pixelBuffer, NULL, 
                                                                  MTLPixelFormatRG8Unorm, width/2, height/2, 1, &uvMetalTextureRef);
    NSAssert(uvResult == kCVReturnSuccess ,@"create uv texture fail");
    
    
    //CVBufferRelease(pixelBuffer);
    
    id<MTLTexture> yTexture  = CVMetalTextureGetTexture(yMetalTextureRef);
    id<MTLTexture> uvTexture = CVMetalTextureGetTexture(uvMetalTextureRef);
    
    // YUV to RGB
    {
        MTLRenderPassDescriptor*  renderPass = [[MTLRenderPassDescriptor alloc] init];
        renderPass.colorAttachments[0].clearColor  = MTLClearColorMake(0.5, 0.5, 0.5, 1.0); // 灰色
        renderPass.colorAttachments[0].loadAction  = MTLLoadActionClear;
        renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        renderPass.colorAttachments[0].texture = _rgbaTexture ;
        
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
        encoder.label = @"nv2rgb";
        [encoder setRenderPipelineState:_pipelineStateYuv2Rgb];
        [encoder setVertexBuffer:_attributeBuffer offset:0 atIndex:0];
        //[encoder setVertexBuffer:_uniformBufferYuv2Rgb offset:0 atIndex:1];
        [encoder setFragmentSamplerState:_samplerState atIndex:0];
        [encoder setFragmentTexture:yTexture  atIndex:0];
        [encoder setFragmentTexture:uvTexture atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [encoder endEncoding];
        
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
            CVBufferRelease(yMetalTextureRef);
            CVBufferRelease(uvMetalTextureRef);
        }];
        
        [commandBuffer commit];
    }

    std::vector<uint8_t> yuv420p(width*height*3/2, 0);
    // RGB to YUV
    {
        MTLRenderPassDescriptor* renderPass = [[MTLRenderPassDescriptor alloc] init];
        renderPass.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0); // 灰色
        renderPass.colorAttachments[0].loadAction  = MTLLoadActionClear;
        renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        renderPass.colorAttachments[0].texture = _yuv420pTexture ;
        
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
        encoder.label = @"rgb2yuv420p";
        [encoder setRenderPipelineState:_pipelineStateRgb2Yuv];
        [encoder setVertexBuffer:_attributeBuffer offset:0 atIndex:0];
        [encoder setFragmentBuffer:_uniformBuffer offset:0 atIndex:0];
        [encoder setFragmentSamplerState:_samplerState atIndex:0];
        [encoder setFragmentTexture:_rgbaTexture  atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [encoder endEncoding];
        
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        
        // 读取 yuv420p
        [_yuv420pTexture getBytes:yuv420p.data()  
                      bytesPerRow:_yuv420pTexture.width * 4 // 必须乘以4 rgba
                       fromRegion:MTLRegionMake2D(0, 0, _yuv420pTexture.width, _yuv420pTexture.height)
                      mipmapLevel:0];
    }
    
    // 比较 yuv 是否一致
    {
        
        int imageWidth  = (int)CVPixelBufferGetWidth(pixelBuffer);
        int imageHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        int y_stride  = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        int uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
       
        int y_width   = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 0);
        int y_height  = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
        int uv_width  = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 1);
        int uv_height = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
        
        if (FALSE) {
            NSLog(@"buffer width=%d, height=%d, y_stride=%d, uv_stride=%d, y_width=%d, y_height=%d, uv_width=%d, uv_height=%d",
                  imageWidth, imageHeight,
                  y_stride, uv_stride,
                  y_width, y_height,
                  uv_width, uv_height);
        }

        // 原来的nv21
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        uint8_t* yDestPlane  = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        uint8_t* uvDestPlane = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        NSAssert(yDestPlane != nullptr && uvDestPlane != nullptr, @"CVPixelBufferGetBaseAddressOfPlane fail %p, %p", yDestPlane, uvDestPlane);
        

        // 读取渲染后的yuv420p
        uint8_t* bufferYuv420p = yuv420p.data();
        
        if (TRUE) {
            NSLog(@"nv21:y:%u, u:%u, v:%u", *yDestPlane,
                                        *(uvDestPlane),
                                        *(uvDestPlane+1));
            NSLog(@"yuv420:y:%u, u:%u, v:%u", *bufferYuv420p,
                                        *(bufferYuv420p + imageWidth*imageHeight),
                                        *(bufferYuv420p + imageWidth*imageHeight*5/4));
        }
        
        
        
        uint8_t* srcItor = bufferYuv420p;
        uint8_t* dstItor = yDestPlane;
        int maxValue = 0 ;
        int k = 0;
        for( ; srcItor < bufferYuv420p + imageWidth * imageHeight  ; srcItor++,  dstItor++, k++) // 要考虑对齐
        {
            int diff = abs( (int)(*srcItor) - (int)(*dstItor)   );
            if (diff > maxValue) {
                maxValue = diff ;
            }
        }
        NSLog(@"%s: maxValue = %d", __FUNCTION__, maxValue);
        
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        
        CVBufferRelease(pixelBuffer);
        
    }
    
    // RGB to Screen
    {
        MTLRenderPassDescriptor* renderPass = view.currentRenderPassDescriptor;
        
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
        encoder.label = @"rgb2screen";
        [encoder setRenderPipelineState:_pipelineStateScreen];
        [encoder setVertexBuffer:_attributeBuffer offset:0 atIndex:0];
        [encoder setFragmentSamplerState:_samplerState atIndex:0];
        [encoder setFragmentTexture:_rgbaTexture atIndex:0];
        [encoder setCullMode:MTLCullModeNone]; // MTLCullModeBack
        //[encoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [encoder endEncoding];
     
        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer commit];
    }
    
}



-(void) OnDrawableSizeChange:(CGSize)size WithView:(MetalView*) view
{
 
}


-(void) switchRecord
{
 
}

-(BOOL) switchCamera
{
    if (_cameraDevice == nil)
    {
        _cameraDevice = [[CameraDevice alloc] init];
        
        // 检查权限
        BOOL result = [_cameraDevice checkPermission];
        if (!result)
        {
            _cameraDevice = nil;
            return false ;
        }
        _cameraDevice.delegate = self ;
        [_cameraDevice openCamera:_globalDevice];
        // [_cameraDevice setFrameRate:5.0f];
        
    }
    else
    {
        [_cameraDevice closeCamera];
        _cameraDevice = nil;
    }
    return true ;
}
 

-(void) onPreviewFrame:(CVPixelBufferRef) pixelBuffer
{
    // 摄像头来一帧 先cache 然后渲染线程再处理
    os_unfair_lock_lock(&spinLock);
    if ( _mtlTextureRefQueue.size() < kMtlTextureQueueSize) {
        CVBufferRetain(pixelBuffer);
        _mtlTextureRefQueue.push(pixelBuffer);
    } else {
        CVPixelBufferRef older = _mtlTextureRefQueue.front();
        _mtlTextureRefQueue.pop();
        CVBufferRelease(older);
        CVBufferRetain(pixelBuffer);
        _mtlTextureRefQueue.push(pixelBuffer);
    }
    os_unfair_lock_unlock(&spinLock);
}

@end



