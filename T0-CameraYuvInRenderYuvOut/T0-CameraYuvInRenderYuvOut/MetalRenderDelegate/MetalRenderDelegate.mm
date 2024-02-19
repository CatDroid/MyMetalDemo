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
    float y1   = yTex.sample(samplr, in.texCoord).r;  // 方便debug
    float2 uv1 = vuTex.sample(samplr, in.texCoord).rg;
    float  y   = y1  - 16.0/255.0 ;                         // 16/256=0.0625   128/256=0.5
    float2 uv  = uv1 - vector_float2(128.0/255.0);          // metal .ar
    float3 yuvNv21   = vector_float3(y, uv);

    float4 fragColor = vector_float4(bt709_videorange * yuvNv21, 1.0);

#if 0
    // (225, 121, 134) diff abs:(0, 1, 0)    --> rgb: (254.028000, 241.563004, 228.477997) rgb在正常区间 yuv也在正确区间 但是还相差1,
    //                                           精度原因(不能存浮点 只能是整数uint8)
    //                                           如果转换之后用截断方式 (254, 241, 228) diff就是0; 四舍五入 (254, 242, 228) diff有1
    // (224, 118,134)  diff abs:(0, 0, 0)    --> (252.863998, 241.037994, 220.972000)
    //                                           精度原因 四舍五入diff为0 直接截断diff为1

    fragColor.r = ( (int)  (fragColor.r * 255.0)  )/ 255.0 ;
    fragColor.b = ( (int)  (fragColor.b * 255.0)  )/ 255.0 ;
    fragColor.g = ( (int)  (fragColor.g * 255.0)  )/ 255.0 ;

#endif

#if 0
    if ( (fragColor.r < -0.003 || fragColor.g <  -0.003 || fragColor.b <  -0.003)
         && (y1 >= 16.0/255.0 && y1 <= 235.0/255.0) // y1在[16,235] rgb会出现负数 (y,cb,cv都在正确范围内,但是(y,cb,cr)这个组合可能是不对的)
        )
    {
        return float4(1.0, 0.0, 0.0, 1.0);
    }
    else
    {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
#else
    return fragColor;
#endif
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
    vector_float2 u_Offset;
    vector_float2 u_ImgSize;
    vector_float2 u_TargetSize;
} UniformBuffer ;

// 参考公式: https://blog.csdn.net/m18612362926/article/details/127667954
// 参考wiki: https://cloud.tencent.com/developer/article/1903469

static const char* sRgbToYuv = R"(

#include <simd/simd.h>
#include <metal_stdlib>
using namespace metal;

//这里的转换公式是 709 video-range, 需要和上屏的时候的yuv->rgb对应
constant static float3 COEF_Y = float3( 0.183f,  0.614f,  0.062f);
constant static float3 COEF_U = float3(-0.101f, -0.339f,  0.439f);
constant static float3 COEF_V = float3( 0.439f, -0.399f, -0.040f);
constant static float U_DIVIDE_LINE = 2.0f / 3.0f;
constant static float V_DIVIDE_LINE = 5.0f / 6.0f;

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
    vector_float2 u_Offset;
    vector_float2 u_ImgSize;
    vector_float2 u_TargetSize;
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
 
// 片元坐标:90.5 FBO宽 180  归一化坐标 90.5/180=0.502 777 7778 但是metal debug看到值是0.502 777 7553
// 导致了减去 0.5/180 = 0.002 777 7778
// 0.502 777 7553 - 0.002 777 7778 != 0.5 (应该是 0.502 777 7778 - 0.002 777 7778)
fragment float4 fragmentStage(
                                     VertexOut in [[stage_in]],
                                     texture2d<float,access::sample> colorTex [[texture(0)]],
                                     constant UniformBuffer& uniformbuffer [[buffer(0)]],
                                     sampler samplr [[sampler(0)]]
                                     )
{
    // uniform
    float  u_Offset  = uniformbuffer.u_Offset.x; // 纹理-每个纹素-归一化后的大小
    float2 u_ImgSize = uniformbuffer.u_ImgSize;  // 纹理-分辨率

    float2 halfTagetSizeR = (uniformbuffer.u_TargetSize / 2.0); // fbo分辨率  0.5像素 归一化后的大小
    float2 halfSrcSizeR   = (uniformbuffer.u_Offset     / 2.0); // 纹理纹素   0.5像素 归一化后的大小
    
    // metal 输出float 0~1.0 到RGBA整数 是四舍五入 比如 0.92156*255=234.9978 读取纹理是235
    // metal每个片元 插值坐标是 片元的中心点，不是左上角(OpenGL)
    // varying
    float2 v_texCoord = in.texCoord - halfTagetSizeR;

    // begin..
    float2 texelOffset = float2(u_Offset, 0.0);

    float4 outColor;

    if (v_texCoord.y < U_DIVIDE_LINE) {
        //在纹理坐标 y < (2/3) 范围，需要完成一次对整个纹理的采样，
        //一次采样（加三次偏移采样）4 个 RGBA 像素（R,G,B,A）生成 1 个（Y0,Y1,Y2,Y3），整个范围采样结束时填充好 width*height 大小的缓冲区；

        float2 texCoord = float2(v_texCoord.x, v_texCoord.y * 3.0 / 2.0);
       
        texCoord += halfSrcSizeR; // 改为采样纹素的中心点

        float4 color0 = colorTex.sample(samplr, texCoord);
        float4 color1 = colorTex.sample(samplr, texCoord + texelOffset);
        float4 color2 = colorTex.sample(samplr, texCoord + texelOffset * 2.0);
        float4 color3 = colorTex.sample(samplr, texCoord + texelOffset * 3.0);

        float y0 = dot(color0.rgb, COEF_Y) + 16.0/255.0 ; // bt.709 video-range  16.0/256.0=0.0625
        float y1 = dot(color1.rgb, COEF_Y) + 16.0/255.0 ;
        float y2 = dot(color2.rgb, COEF_Y) + 16.0/255.0;
        float y3 = dot(color3.rgb, COEF_Y) + 16.0/255.0 ;
        outColor = float4(y0, y1, y2, y3);
    }
    else if (v_texCoord.y < V_DIVIDE_LINE) {

        //当纹理坐标 y > (2/3) 且 y < (5/6) 范围，一次采样（加三次偏移采样）8 个 RGBA 像素（R,G,B,A）生成（U0,U1,U2,U3），
        //又因为 U plane 缓冲区的宽高均为原图的 1/2 ，U plane 在垂直方向和水平方向的采样都是隔行进行，整个范围采样结束时填充好 width*height/4 大小的缓冲区。

        float offsetY = 1.0 / 3.0 / u_ImgSize.y;
        float2 texCoord;
        if(v_texCoord.x < 0.5 - halfTagetSizeR.x ) { // 相当于直接用in.texCoord来判断 当前位置是否<0.5
            texCoord = float2(v_texCoord.x * 2.0,         (v_texCoord.y - U_DIVIDE_LINE) * 2.0 * 3.0);
        }
        else {
            //texCoord = float2((v_texCoord.x - 0.5) * 2.0, ((v_texCoord.y - U_DIVIDE_LINE) * 2.0 + offsetY) * 3.0);
            //texCoord = float2((v_texCoord.x - 0.5) * 2.0, ((v_texCoord.y - U_DIVIDE_LINE) + offsetY) * 3.0 * 2.0 );
            texCoord = float2(2.0 * v_texCoord.x - 1.0 , ((1.5 * v_texCoord.y - 1.0) * 2.0 + 1.0 / u_ImgSize.y) * 2.0 );
        }

        texCoord += halfSrcSizeR; // 改为采样纹素的中心点

        float4 color0 = colorTex.sample(samplr, texCoord);
        float4 color1 = colorTex.sample(samplr, texCoord + texelOffset * 2.0);
        float4 color2 = colorTex.sample(samplr, texCoord + texelOffset * 4.0);
        float4 color3 = colorTex.sample(samplr, texCoord + texelOffset * 6.0);

        float u0 = dot(color0.rgb, COEF_U) + 128.0/255.0;
        float u1 = dot(color1.rgb, COEF_U) + 128.0/255.0;
        float u2 = dot(color2.rgb, COEF_U) + 128.0/255.0;
        float u3 = dot(color3.rgb, COEF_U) + 128.0/255.0;
        outColor = float4(u0, u1, u2, u3);
    }
    else {
        //当纹理坐标 y > (5/6) 范围，一次采样（加三次偏移采样）8 个 RGBA 像素（R,G,B,A）生成（V0,V1,V2,V3），
        //同理，因为 V plane 缓冲区的宽高均为原图的 1/2 ，垂直方向和水平方向都是隔行采样，整个范围采样结束时填充好 width*height/4 大小的缓冲区。

        float offsetY = 1.0 / 3.0 / u_ImgSize.y;
        float2 texCoord;
        if(v_texCoord.x < 0.5  - halfTagetSizeR.x ) {
            texCoord = float2(v_texCoord.x * 2.0, (v_texCoord.y - V_DIVIDE_LINE) * 2.0 * 3.0);
        }
        else {
            //texCoord = float2((v_texCoord.x - 0.5) * 2.0, ((v_texCoord.y - V_DIVIDE_LINE) * 2.0 + offsetY) * 3.0);
            texCoord = float2(2.0 * v_texCoord.x - 1.0 , ((1.5 * v_texCoord.y - 1.25) * 2.0 + 1.0 / u_ImgSize.y) * 2.0 );
        }

        texCoord += halfSrcSizeR; // 改为采样纹素的中心点
        
        float4 color0 = colorTex.sample(samplr, texCoord);
        float4 color1 = colorTex.sample(samplr, texCoord + texelOffset * 2.0);
        float4 color2 = colorTex.sample(samplr, texCoord + texelOffset * 4.0);
        float4 color3 = colorTex.sample(samplr, texCoord + texelOffset * 6.0);

        float v0 = dot(color0.rgb, COEF_V) + 128.0/255.0;
        float v1 = dot(color1.rgb, COEF_V) + 128.0/255.0;
        float v2 = dot(color2.rgb, COEF_V) + 128.0/255.0;
        float v3 = dot(color3.rgb, COEF_V) + 128.0/255.0;
        outColor = float4(v0, v1, v2, v3);
    }

    return outColor;
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

    
    // yuv2rgb pipeline
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
  
    // screen pipeline
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
    
    // rgb2yuv pipeline
    {
        NSError *errors;
        NSString* shaderString = [NSString stringWithUTF8String:sRgbToYuv];
        
        // https://developer.apple.com/documentation/metal/mtlcompileoptions/1515914-fastmathenabled?language=objc
        // fastMathEnabled 一个布尔值，指示编译器是否可以对可能违反 IEEE 754 标准的浮点算术执行优化。
        // 默认值为“YES”。 YES 值还启用 单精度浮点标量和向量类型的 数学函数的高精度变体(high-precision variant)。
        
        //MTLCompileOptions* options = [MTLCompileOptions new];
        //options.fastMathEnabled = NO;
        MTLCompileOptions* options =  nil;
        
        id <MTLLibrary> library = [device newLibraryWithSource:shaderString options:options error:&errors];
        NSAssert(library != nil ,@"Compile Error %s", [[errors description] UTF8String]);
        
        id<MTLFunction> vertexFunction   = [library newFunctionWithName:@"vertexStage"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragmentStage"];
        
        MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.vertexFunction = vertexFunction ;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction ;
        
        // rgb转到yuv 使用线性rgba(不管原来的rgb是否sRGB, 都不使用硬件自动转换成SRGB)
        // 注意shader的顺序 是 rg ba (y通道:第一个像素 第二个像素 第三个像素 第四个像素)
     
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
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
        rgbToYuvUniformBuffer.u_ImgSize    = simd_make_float2( kWidth,         kHeight) ;
        rgbToYuvUniformBuffer.u_Offset     = simd_make_float2( 1.0/kWidth,     1.0/kHeight);
        rgbToYuvUniformBuffer.u_TargetSize = simd_make_float2( 1.0/(kWidth/4), 1.0/(kHeight*3/2) );
        _uniformBuffer = [device newBufferWithBytes:&rgbToYuvUniformBuffer
                                             length:sizeof(rgbToYuvUniformBuffer)
                                            options:MTLResourceStorageModeShared|MTLResourceCPUCacheModeWriteCombined];
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
        textureDescriptor.pixelFormat =  MTLPixelFormatRGBA8Unorm; // MTLPixelFormatRGBA8Unorm_sRGB yuv转成rgb 直接当做是线性rgb来处理 顺序要跟shader
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
    
    // 打印颜色空间
    static bool logOnce = true ;
    if (logOnce) {
        logOnce = false ;
        
        OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
        NSString *formatString = [NSString stringWithFormat:@"%c%c%c%c",
          (char)((format >> 24) & 0xFF),
          (char)((format >> 16) & 0xFF),
          (char)((format >> 8) & 0xFF),
          (char)(format & 0xFF)];
        
        switch (format) {
          case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
          //case kCVPixelFormatType_420YpCbCr8PlanarVideoRange:
          case kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange:
          //case kCVPixelFormatType_422YpCbCr8PlanarVideoRange:
          case kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange:
          //case kCVPixelFormatType_444YpCbCr8PlanarVideoRange:
            NSLog(@"The pixel buffer is video range. %@" , formatString); // 420v
            break;

          case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
          case kCVPixelFormatType_420YpCbCr8PlanarFullRange:  // 只有这个是Planar YUV格式其他都是Bi-Planar交错平面
          case kCVPixelFormatType_422YpCbCr8BiPlanarFullRange:
          //case kCVPixelFormatType_422YpCbCr8PlanarFullRange:
          case kCVPixelFormatType_444YpCbCr8BiPlanarFullRange:
          //case kCVPixelFormatType_444YpCbCr8PlanarFullRange: // 没有定义

            NSLog(@"The pixel buffer is full range. %@" , formatString);
            break;

          default:
            NSLog(@"The pixel buffer format is unknown. %@" , formatString);
            break;
        }
        

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

    
    
    // 检查摄像头输出的YUV 是否超过范围  --- 420v Y通道会超过范围 但是CbCr通道不会
    if (FALSE) {
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        uint8_t* yBase  = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        uint8_t* uvBase = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        int imageWidth  = (int)CVPixelBufferGetWidth(pixelBuffer); // 720
        int imageHeight = (int)CVPixelBufferGetHeight(pixelBuffer);// 1280
        
        int y_width   = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 0); // 720
        int y_height  = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0); // 1280
        int uv_width  = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 1); // 360
        int uv_height = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 1); // 640
        
        int y_stride  = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0); // 768 -- 64字节对齐
        int uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1); // 768
         

        // 检查-y平面
        if (FALSE) {
            for(int i = 0 ; i < imageHeight ; i++) {
                for(int j = 0; j < imageWidth ; j++) {
                    uint8_t nv12pixel   = *(yBase    + y_stride * i + j ); // 要考虑对齐
                    if (nv12pixel < 16 || nv12pixel > 235) {
                    //if (nv12pixel < 10 || nv12pixel > 250) {
                        NSLog(@"%s: y panel out of range, coord (x:%d, y:%d), h-coord (x:%d, y:%d) ; nv12 %u "
                              ,__FUNCTION__
                              ,j ,i  // 注意这里 先'列x'后‘行y’
                              ,j/2, i/2
                              ,nv12pixel );
                    }
                }
            }
        }

        // 检查-uv平面
        if (TRUE) {
            for(int i = 0 ; i < imageHeight/2 ; i++) // u和v平面的宽高只有原来的一半
            {
                for(int j = 0; j < imageWidth/2 ; j++)
                {
                   
                    uint8_t nv12_u    = *(uvBase + i * uv_stride + j * 2) ;
                    uint8_t nv12_v    = *(uvBase + i * uv_stride + j * 2 + 1) ;
                    if (nv12_u < 16 || nv12_u > 240) {
                        NSLog(@"%s: cb panel out of range, coord (x:%d, y:%d), h-coord (x:%d, y:%d) ; nv12 %u "
                              ,__FUNCTION__
                              ,j*2 ,i*2  // 注意这里 先'列x'后‘行y’
                              ,j, i
                              ,nv12_u );
                    }
                    
                    if (nv12_v < 16 || nv12_v > 240) {
                        NSLog(@"%s: cr panel out of range, coord (x:%d, y:%d), h-coord (x:%d, y:%d) ; nv12 %u "
                              ,__FUNCTION__
                              ,j*2 ,i*2  // 注意这里 先'列x'后‘行y’
                              ,j, i
                              ,nv12_v );
                    }
                }
            }
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
    
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
            
            // RGB                 YCbCr
            // 230  90  50    ---  116 96 191
            // 211 240  235   ---  216 128 115
            
        }
        
#define CASE 2  // 选择不同的override方案

        
#if CASE == 0 // 替换成单独颜色 RGB转成NV12 (bt.709 video range)
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
        
        

        
        static const uint8_t Y1  = 216u ;// 0.847 058 8// 4个像素 不同的亮度(Y)
        static const uint8_t Y2  = 210u ;// 0.823 529 4
        static const uint8_t Y3  = 213u ;// 0.835 294 1
        static const uint8_t Y4  = 209u ;// 0.819 607 8
        
        static const uint8_t U1  = 128u ;// 0.501 960 7
        static const uint8_t U2  = 119u ;// 0.466 666 6
        static const uint8_t U3  = 125u ;// 0.490 196 0
        static const uint8_t U4  = 120u ;// 0.470 588 2
        
        static const uint8_t V1  = 115u ;// 0.450 980 3
        static const uint8_t V2  = 109u ;// 0.427 450 9
        static const uint8_t V3  = 118u ;// 0.462 745 0
        static const uint8_t V4  = 100u ;// 0.392 156 8
        
        typedef struct {
            uint8_t Y;
            uint8_t Cb;
            uint8_t Cr;
        } YUVData;
        
        static const YUVData yuvTestArray[] = {
            {Y1,  U1,  V1},
            {Y1,  U2,  V2},
            {Y1,  U3,  V3},
            {Y1,  U4,  V4},
            
            {Y2,  U1,  V1},
            {Y2,  U2,  V2},
            {Y2,  U3,  V3},
            {Y2,  U4,  V4},
            
            {Y3,  U1,  V1},
            {Y3,  U2,  V2},
            {Y3,  U3,  V3},
            {Y3,  U4,  V4},
            
            {Y4,  U1,  V1},
            {Y4,  U2,  V2},
            {Y4,  U3,  V3},
            {Y4,  U4,  V4},
        };
        
        static int sIndex = 0;
        
        const YUVData& data = yuvTestArray[sIndex];
        
        sIndex = (++sIndex) % (sizeof(yuvTestArray)/sizeof(yuvTestArray[0]));
       
        overrideY  = data.Y ;
        overrideCb = data.Cb;
        overrideCr = data.Cr;
        
        NSLog(@"override %u,%u,%u", overrideY, overrideCb, overrideCr);

        
        // override y :
        memset(yBase, overrideY, y_stride * y_height);
        
        // override uv:
        uint16_t uv  = ((uint16_t)overrideCr << 8)  + (uint16_t)overrideCb; // YpCbCr--Cb在低地址--ios小端
        uint16_t* uvBase16 = (uint16_t*)uvBase;
        for (int j = 0; j < uv_height; j++)
        {
            // 考虑64字节对齐
            // uv_width = 360  uv_stride/2 = 768/2 = 384  多了24个像素  每个像素2个字节(分别存放u和v)
            for (int i = 0; i < uv_stride / 2; i++ )
            {
                *(uvBase16++) = uv;
 
            }
        }
#elif CASE == 1
        // Y1 Y1 Y2 Y2   Y1 Y1 Y2 Y2
        // Y1 Y1 Y2 Y2   Y1 Y1 Y2 Y2
        // U1    V1      U2    V2
        // Y1 Y1 Y2 Y2   Y1 Y1 Y2 Y2
        // Y1 Y1 Y2 Y2   Y1 Y1 Y2 Y2
        // U1    V1      U2    V2
        
        // 两种颜色 (Y1 U1 V1)   (Y2 U2 V2)
        
        uint8_t Y1 = 216u; //Y  0.847 058 216.0/255.0=0.847058(这里除255而不是256, 截断后面而不是四舍五入)
        uint8_t U1 = 128u; //Cb 0.501 960
        uint8_t V1 = 115u; //Cr 0.450 980
    

        uint8_t Y2 =  116u; //Y  0.454 901
        uint8_t U2 =  96u;  //Cb 0.376 470
        uint8_t V2 = 191u;  //Cr 0.749 019
        
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  ios是小端（低字节在低位/低地址)  从低地址--高地址: YYYYY--CbCrCbCr  Cr是高地址
        uint16_t y   = ((uint16_t)Y1 << 8)   + (uint16_t)Y1;
        uint16_t y2  = ((uint16_t)Y2 << 8)  + (uint16_t)Y2;
        uint16_t uv  = ((uint16_t)V1 << 8)  + (uint16_t)U1;
        uint16_t uv2 = ((uint16_t)V2 << 8) + (uint16_t)U2;
        
        
        NSLog(@"override  %u %u %u - %u %u %u ",
              Y1, U1, V1,
              Y2, U2, V2
              );
        

        uint8_t* yBase8 = (uint8_t*)yBase;
        for (int j = 0 ; j < y_height; j++)
        {
            for (int i = 0; i < y_stride / 2; i++ )
            {
                *(uint16_t*)(yBase8 + j * y_stride + i * 2 ) = i % 2 == 0 ? y : y2;
            }
        }
 
        // override uv:
        uint8_t* uvBase8 = (uint8_t*)uvBase;
        for (int j = 0; j < uv_height; j++)
        {
            for (int i = 0; i < uv_stride / 2; i++ ) // uv_width = 360  uv_stride/2 = 768/2 = 384  多了24个像素  每个像素2个字节(分别存放u和v)
            {
                *(uint16_t*)(uvBase8 + j * uv_stride + i * 2) = i % 2 == 0 ? uv : uv2;
            }
        }
        
#elif CASE == 2
        
        // Y1 Y2 Y1 Y2   Y1 Y2 Y1 Y2
        // Y3 Y4 Y3 Y4   Y3 Y4 Y3 Y4
        // U1 V1 U2 V2   U1 V1 U2 V2
        
        // Y1 Y2 Y1 Y2   Y1 Y2 Y1 Y2
        // Y3 Y4 Y3 Y4   Y3 Y4 Y3 Y4
        // U3 V3 U4 V4   U3 V3 U4 V4
        uint8_t Y1  = 216u; // 4个像素 不同的亮度(Y)
        uint8_t Y2  = 210u ;
        uint8_t Y3  = 213u ;
        uint8_t Y4  = 209u ;
        
        uint8_t U1  = 128u;
        uint8_t U2  = 119u ;
        uint8_t U3  = 125u ;
        uint8_t U4  = 120u ;
        
        uint8_t V1  = 115u;
        uint8_t V2  = 109u ;
        uint8_t V3  = 118u ;
        uint8_t V4  = 100u ;
        
        
        uint32_t y1  = ((uint32_t)Y2 << 24) + ((uint32_t)Y1 << 16) + ((uint32_t)Y2 << 8) + (uint32_t)Y1;
        uint32_t y2  = ((uint32_t)Y4 << 24) + ((uint32_t)Y3 << 16) + ((uint32_t)Y4 << 8) + (uint32_t)Y3;
        uint32_t uv  = ((uint32_t)V2 << 24) + ((uint32_t)U2 << 16) + ((uint32_t)V1 << 8) + (uint32_t)U1;
        uint32_t uv2 = ((uint32_t)V4 << 24) + ((uint32_t)U4 << 16) + ((uint32_t)V3 << 8) + (uint32_t)U3;
        
        uint8_t* yBase8 = (uint8_t*)yBase;
        for (int j = 0 ; j < y_height; j++)
        {
            for (int i = 0; i < y_stride / 4; i++ )
            {
                *(uint32_t*)(yBase8 + j * y_stride + i * 4) = (j % 2 == 0 ? y1 : y2);
            }
        }
 
        // override uv:
        uint8_t* uvBase8 = (uint8_t*)uvBase;
        for (int j = 0; j < uv_height; j++)
        {
            for (int i = 0; i < uv_stride / 4; i++ )
            {
 
                *(uint32_t*)(uvBase8 + j * uv_stride + i * 4 ) = (j % 2 == 0 ? uv : uv2);
            }
        }
 
#endif

        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }

    
    size_t width  = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
   
    CVMetalTextureRef yMetalTextureRef  = NULL;
    CVReturn yResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, NULL,
                                                                 MTLPixelFormatR8Unorm,  width,  height, 0,  &yMetalTextureRef);
    NSAssert(yResult == kCVReturnSuccess ,@"create y texture fail");
     
 
    CVMetalTextureRef uvMetalTextureRef = NULL;
    CVReturn uvResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,  _textureCache, pixelBuffer, NULL, 
                                                                  MTLPixelFormatRG8Unorm, width/2, height/2, 1, &uvMetalTextureRef);
    NSAssert(uvResult == kCVReturnSuccess ,@"create uv texture fail");
    
    // 因为后面还要使用CVPixelBuffer做检查 所以这里先不释放
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
    if (FALSE) {
        
        int imageWidth  = (int)CVPixelBufferGetWidth(pixelBuffer);
        int imageHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        int y_stride  = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        int uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
       
        int y_width   = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 0);
        int y_height  = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
        int uv_width  = (int)CVPixelBufferGetWidthOfPlane (pixelBuffer, 1);
        int uv_height = (int)CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
        
        // 原来的nv21
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        uint8_t* yDestPlane  = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        uint8_t* uvDestPlane = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        NSAssert(yDestPlane != nullptr && uvDestPlane != nullptr, @"CVPixelBufferGetBaseAddressOfPlane fail %p, %p", yDestPlane, uvDestPlane);
        
        if (FALSE) {
            NSLog(@"buffer width=%d, height=%d, y_stride=%d, uv_stride=%d, y_width=%d, y_height=%d, uv_width=%d, uv_height=%d",
                  imageWidth, imageHeight,
                  y_stride, uv_stride,
                  y_width, y_height,
                  uv_width, uv_height);
        }
        

        // 读取渲染后的yuv420p
        uint8_t* bufferYuv420p  = yuv420p.data();
 
        
        // 比较 Y平面 前面4个像素 和 UV平面 前面4个像素(对应原图4*(2*2)个像素)
        if (FALSE) {
            
            uint8_t* yuv420p_yBase  = bufferYuv420p ;
            uint8_t* yuv420p_cbBase = bufferYuv420p + imageWidth * imageHeight ;
            uint8_t* yuv420p_crBase = bufferYuv420p + imageWidth * imageHeight * 5 / 4;
            
            NSLog(@"nv21:y:%u, u:%u, v:%u   y~%u %u %u uv~(%u %u) (%u %u) (%u %u)"
                  ,*yDestPlane
                  ,*(uvDestPlane)
                  ,*(uvDestPlane+1)
                  
                  ,*(yDestPlane+1)
                  ,*(yDestPlane+2)
                  ,*(yDestPlane+3)
                  
                  ,*(uvDestPlane+2)
                  ,*(uvDestPlane+3)
                  
                  ,*(uvDestPlane+4)
                  ,*(uvDestPlane+5)
                  
                  ,*(uvDestPlane+6)
                  ,*(uvDestPlane+7)
                  
                  );
            NSLog(@"yuv420:y:%u, u:%u, v:%u   y~%u %u %u uv~(%u %u) (%u %u) (%u %u)"
                  ,*yuv420p_yBase
                  ,*yuv420p_cbBase
                  ,*yuv420p_crBase
                  
                  ,*(yuv420p_yBase + 1)
                  ,*(yuv420p_yBase + 2)
                  ,*(yuv420p_yBase + 3)
                  
                  ,*(yuv420p_cbBase +1)
                  ,*(yuv420p_crBase +1)
                  
                  ,*(yuv420p_cbBase +2)
                  ,*(yuv420p_crBase +2)
                  
                  ,*(yuv420p_cbBase +3)
                  ,*(yuv420p_crBase +3)
                  
                  );
        }
        
        // 比较 y 平面是否一致
        // ios CVPixelBuffer对齐 会在每行最后padding 0!
        if (FALSE) {
            uint8_t* yuv420p_yBase  = bufferYuv420p;
            
            uint8_t* nv12_yBase     = yDestPlane;
            uint8_t* nv12_uvBase    = uvDestPlane;
        
            int maxValue  = 0 ;
            int diffCount = 0;
            for(int i = 0 ; i < imageHeight ; i++)
            {
                for(int j = 0; j < imageWidth ; j++)
                {
                    int uv_i = i / 2 ; // uv平面的行
                    int uv_j = j / 2 ;
                    
                    uint8_t yuv420pixel = *(yuv420p_yBase + imageWidth * i + j );
                    uint8_t nv12_y    = *(nv12_yBase    + y_stride  * i    + j ); // 要考虑对齐
                    uint8_t nv12_u    = *(nv12_uvBase   + uv_stride * uv_i + uv_j * 2) ;
                    uint8_t nv12_v    = *(nv12_uvBase   + uv_stride * uv_i + uv_j * 2 + 1) ;
                    
                    int diff = abs((int)(yuv420pixel) - (int)(nv12_y));
                    
                   
                    // yuv不在正确"区间" ----- 目前发现这样的diff可能在20以内
                    //
                    // (255, 104, 136)    --> 这个Y是255 超过了video-range的定义  rgb=(292.532013, 279.036011, 227.460007)
                    //
                    
                    // yuv在正确"区间", 但这个"组合"可能不在正确"空间" 内 ----- 目前发现这样的diff可能在10以内
                    //
                    // (30, 116, 147)    -->  rgb=(50.344002, 8.706000, -9.072000)      < 0 负数
                    // (231, 105, 136)   -->  rgb: (264.596008, 250.886993, 201.638000) > 255
                    // (226, 105, 136)   -->  rgb: (258.776001, 245.067001, 195.817993) > 255, 会被截断
                    //
                    
                    // "区间"以外, 不对比
                    if (nv12_y < 16 || nv12_y > 235) {
                        continue ;
                    }
                    
                    NSAssert((nv12_u >= 16 && nv12_u <= 240),  @"nv12_u out of range %u", nv12_u);
                    NSAssert((nv12_v >= 16 && nv12_v <= 240),  @"nv12_v out of range %u", nv12_v);
                    
                    // bt709 video-range to rgb
                    float R1 = 1.164 * (nv12_y - 16)                          + 1.792 * (nv12_v - 128);
                    float G1 = 1.164 * (nv12_y - 16) - 0.213 * (nv12_u - 128) - 0.534 * (nv12_v - 128);
                    float B1 = 1.164 * (nv12_y - 16) + 2.114 * (nv12_u - 128);
                    
                    // 不考虑 转换rgb之后 超出0到255的像素
                    if (   ( (R1<0) || (R1>255) )
                        || ( (G1<0) || (G1>255) )
                        || ( (B1<0) || (B1>255) )
                        ) {
                        continue ;
                    }
                    
                    // 1. 原始的yuv超出'区间'(主要是Y平面,CbCr平面暂时没有发现越界)
                    // 2. 原始的yuv在'区间' 但不在‘空间’
                    // 排除这两种情况, 就不会有diff了
                    
                    if (diff > 0) diffCount++;
                    if (diff > maxValue) {
                        maxValue = diff ;
                        
                        NSLog(@"%s: maxValue up to %d; coord (x:%d, y:%d), h-coord (x:%d, y:%d) ; yuv420p %u nv12 (y:%u cb:%u cr:%u)"
                              ,__FUNCTION__
                              ,maxValue
                              ,j ,i  // 注意这里 先'列x'后‘行y’
                              ,j/2, i/2
                              ,yuv420pixel 
                              ,nv12_y, nv12_u, nv12_v);
                    }
                }
            }
            NSLog(@"%s: y-maxValue = %d diffCount = %d total = %d"
                  , __FUNCTION__
                  , maxValue
                  , diffCount
                  , imageHeight*imageWidth
                  );
        }

        // 比较 uv 平面是否一致
        if (TRUE) {
            
            uint8_t* yuv420p_cbBase = bufferYuv420p + imageWidth * imageHeight ;
            uint8_t* yuv420p_crBase = bufferYuv420p + imageWidth * imageHeight * 5 / 4;
            
            uint8_t* nv12_yBase    = yDestPlane;
            uint8_t* nv12_uvBase   = uvDestPlane;
            int      nv12_Stride   = uv_stride;
            
            int uMaxValue = 0 ;
            int vMaxValue = 0 ;
            int uDiffCount = 0;
            int vDiffCount = 0;
            
            for(int i = 0 ; i < imageHeight/2 ; i++) // u和v平面的宽高只有原来的一半
            {
                for(int j = 0; j < imageWidth/2 ; j++)
                {
                    int y_i = i * 2 ; // y平面的坐标
                    int y_j = j * 2 ; // 由于uv对应4个y像素, 这里只取左上角的一个
                    
                    
                    uint8_t yuv420p_u = *(yuv420p_cbBase + i*imageWidth/2 + j) ;
                    uint8_t yuv420p_v = *(yuv420p_crBase + i*imageWidth/2 + j) ;
                    
                    uint8_t nv12_y    = *(nv12_yBase  + y_stride * y_i  + y_j );
                    uint8_t nv12_u    = *(nv12_uvBase + nv12_Stride * i + j * 2) ;
                    uint8_t nv12_v    = *(nv12_uvBase + nv12_Stride * i + j * 2 + 1) ;
                    
                   // 检查Y是否在正确'区间'
                    if (nv12_y < 16 || nv12_y > 235) {
                        continue ;
                    }
                    
                    // Cb, Cr 目前发现 都在 正确‘区间’
                    NSAssert((nv12_u >= 16 && nv12_u <= 240),  @"nv12_u out of range %u", nv12_u);
                    NSAssert((nv12_v >= 16 && nv12_v <= 240),  @"nv12_v out of range %u", nv12_v);
                    
                    
                    // bt709 video-range to rgb
                    float R1 = 1.164 * (nv12_y - 16)                          + 1.792 * (nv12_v - 128);
                    float G1 = 1.164 * (nv12_y - 16) - 0.213 * (nv12_u - 128) - 0.534 * (nv12_v - 128);
                    float B1 = 1.164 * (nv12_y - 16) + 2.114 * (nv12_u - 128);
                    
                    // 不考虑 转换rgb之后 超出0到255的像素
                    if (   ( (R1<0) || (R1>255) )
                        || ( (G1<0) || (G1>255) )
                        || ( (B1<0) || (B1>255) )
                        ) {
                        continue ;
                    }
                    
 
                    // (225, 121, 134) diff abs:(0, 1, 0)
                    //   --> rgb: (254.028000, 241.563004, 228.477997)
                    //       rgb在正常区间, yuv也在正确区间, 但是还相差1
                    //       精度原因
                    //       转换之后, 截断方式 (254, 241, 228) diff是0
                    //       转换之后, 四舍五入 (254, 242, 228) diff是1
                    int diff = abs((int)(yuv420p_u) - (int)(nv12_u));
                    if (diff > 0) uDiffCount++;
                    if (diff > uMaxValue) {
                        uMaxValue = diff ;
                        NSLog(@"%s: uMaxValue up to %d; coord (x:%d, y:%d) h-coord (x:%d, y:%d) ; yuv420p‘cb = %u nv12 (y:%u cb:%u cr:%u)"
                              ,__FUNCTION__
                              ,uMaxValue
                              ,j ,i  // 注意这里 先'列x'后‘行y’
                              ,j/2, i/2
                              ,yuv420p_u
                              ,nv12_y, nv12_u, nv12_v);
                    }
                    
                    diff = abs((int)(yuv420p_v) - (int)(nv12_v));
                    if (diff > 0) vDiffCount++;
                    if (diff > vMaxValue) {
                        vMaxValue = diff;
                        vDiffCount++;
                        NSLog(@"%s: vMaxValue up to %d; coord (x:%d, y:%d) h-coord (x:%d, y:%d) ; yuv420p'cr = %u nv12 (y:%u cb:%u cr:%u)"
                              ,__FUNCTION__
                              ,vMaxValue
                              ,j ,i  // 注意这里 先'列x'后‘行y’
                              ,j/2, i/2
                              ,yuv420p_v 
                              ,nv12_y, nv12_u, nv12_v);
                    }
                }
            }
            
            NSLog(@"%s: u max = %d diff = %d -- v max = %d diff = %d -- total = %d "
                  , __FUNCTION__
                  , uMaxValue
                  , uDiffCount
                  , vMaxValue
                  , vDiffCount
                  , imageHeight/2 * imageWidth/2
                  );
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        
    }
    
    // 延迟释放CVPixelBuffer
    CVBufferRelease(pixelBuffer);
    
    
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



