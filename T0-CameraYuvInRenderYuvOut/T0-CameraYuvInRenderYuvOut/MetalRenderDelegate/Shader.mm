//
//  Shader.m
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/19.
//

#import <Foundation/Foundation.h>
#import "MyConfig.h"


#pragma mark - yuv2rgb

#if COLOR_SPACE_CHOOSEN == YUV420_VIDEO_RANGE_BT_709

const char* sYuv2RgbShader = R"(

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

#elif COLOR_SPACE_CHOOSEN == YUV420_FULL_RANGE_BT_601


const char* sYuv2RgbShader = R"(

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


constant float3x3 bt601_fullrange  = float3x3(1.0,   1.0,   1.0,      0.0, -0.3455, 1.779,     1.4075, -0.7169,  0.0);
constant float3x3 bt709_videorange = float3x3(1.164, 1.164, 1.164,    0.0, -0.213,  2.114,     1.792,  -0.534,   0.0);

fragment float4 fragmentStage(
                                 const VertexOut in [[stage_in]],
                                 texture2d<float, access::sample> yTex  [[texture(0)]],
                                 texture2d<float, access::sample> vuTex [[texture(1)]],
                                 sampler samplr [[sampler(0)]]
                                 )
{
    float y1   = yTex.sample(samplr, in.texCoord).r;
    float2 uv1 = vuTex.sample(samplr, in.texCoord).rg;
    float  y   = y1;
    float2 uv  = uv1 - vector_float2(128.0/255.0);          // metal .ar
    float3 yuvNv21   = vector_float3(y, uv);
    float4 fragColor = vector_float4(bt601_fullrange * yuvNv21, 1.0);
    return fragColor;
 
}

)";


#endif


#pragma mark -- rgb to yuv

// 参考公式: https://blog.csdn.net/m18612362926/article/details/127667954
// 参考wiki: https://cloud.tencent.com/developer/article/1903469

#if COLOR_SPACE_CHOOSEN == YUV420_VIDEO_RANGE_BT_709

const char* sRgbToYuv = R"(

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

#elif COLOR_SPACE_CHOOSEN == YUV420_FULL_RANGE_BT_601


const char* sRgbToYuv = R"(

#include <simd/simd.h>
#include <metal_stdlib>
using namespace metal;

//这里的转换公式是 601 full-range
constant static float3 COEF_Y = float3( 0.299f,  0.587f,  0.114f);
constant static float3 COEF_U = float3(-0.169f, -0.331f,  0.5f);
constant static float3 COEF_V = float3( 0.5f,   -0.419f, -0.081f);
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
    
 
    float2 v_texCoord = in.texCoord - halfTagetSizeR; // 插值坐标是 片元的中心点，不是左上角(OpenGL)

    // begin..
    float2 texelOffset = float2(u_Offset, 0.0);

    float4 outColor;

    if (v_texCoord.y < U_DIVIDE_LINE) {
   
        float2 texCoord = float2(v_texCoord.x, v_texCoord.y * 3.0 / 2.0);
       
        texCoord += halfSrcSizeR; // 改为采样纹素的中心点

        float4 color0 = colorTex.sample(samplr, texCoord);
        float4 color1 = colorTex.sample(samplr, texCoord + texelOffset);
        float4 color2 = colorTex.sample(samplr, texCoord + texelOffset * 2.0);
        float4 color3 = colorTex.sample(samplr, texCoord + texelOffset * 3.0);

        float y0 = dot(color0.rgb, COEF_Y)  ; // bt.601 full-range
        float y1 = dot(color1.rgb, COEF_Y)  ;
        float y2 = dot(color2.rgb, COEF_Y)  ;
        float y3 = dot(color3.rgb, COEF_Y)  ;
        outColor = float4(y0, y1, y2, y3);
    }
    else if (v_texCoord.y < V_DIVIDE_LINE) {

      
        float offsetY = 1.0 / 3.0 / u_ImgSize.y;
        float2 texCoord;
        if(v_texCoord.x < 0.5 - halfTagetSizeR.x ) { // 相当于直接用in.texCoord来判断 当前位置是否<0.5
            texCoord = float2(v_texCoord.x * 2.0,         (v_texCoord.y - U_DIVIDE_LINE) * 2.0 * 3.0);
        }
        else {
            texCoord = float2(2.0 * v_texCoord.x - 1.0 , ((1.5 * v_texCoord.y - 1.0) * 2.0 + 1.0 / u_ImgSize.y) * 2.0 );
        }

        texCoord += halfSrcSizeR; // 改为采样纹素的中心点

        float4 color0 = colorTex.sample(samplr, texCoord);
        float4 color1 = colorTex.sample(samplr, texCoord + texelOffset * 2.0);
        float4 color2 = colorTex.sample(samplr, texCoord + texelOffset * 4.0);
        float4 color3 = colorTex.sample(samplr, texCoord + texelOffset * 6.0);

        float u0 = dot(color0.rgb, COEF_U) + 128.0/255.0; // bt.601 full-range
        float u1 = dot(color1.rgb, COEF_U) + 128.0/255.0;
        float u2 = dot(color2.rgb, COEF_U) + 128.0/255.0;
        float u3 = dot(color3.rgb, COEF_U) + 128.0/255.0;
        outColor = float4(u0, u1, u2, u3);
    }
    else {
      
        float offsetY = 1.0 / 3.0 / u_ImgSize.y;
        float2 texCoord;
        if(v_texCoord.x < 0.5  - halfTagetSizeR.x ) {  // 相当于直接用in.texCoord来判断 当前位置是否<0.5
            texCoord = float2(v_texCoord.x * 2.0, (v_texCoord.y - V_DIVIDE_LINE) * 2.0 * 3.0);
        }
        else {
             
            texCoord = float2(2.0 * v_texCoord.x - 1.0 , ((1.5 * v_texCoord.y - 1.25) * 2.0 + 1.0 / u_ImgSize.y) * 2.0 );
        }

        texCoord += halfSrcSizeR; // 改为采样纹素的中心点
        
        float4 color0 = colorTex.sample(samplr, texCoord);
        float4 color1 = colorTex.sample(samplr, texCoord + texelOffset * 2.0);
        float4 color2 = colorTex.sample(samplr, texCoord + texelOffset * 4.0);
        float4 color3 = colorTex.sample(samplr, texCoord + texelOffset * 6.0);

        float v0 = dot(color0.rgb, COEF_V) + 128.0/255.0; // bt.601 full-range
        float v1 = dot(color1.rgb, COEF_V) + 128.0/255.0;
        float v2 = dot(color2.rgb, COEF_V) + 128.0/255.0;
        float v3 = dot(color3.rgb, COEF_V) + 128.0/255.0;
        outColor = float4(v0, v1, v2, v3);
    }

    return outColor;
}

)";


#endif




#pragma mark -- rgb to screen

const char* sRgbToScreen = R"(

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

