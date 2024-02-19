//
//  test_on_mac.c
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/19.
//

#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <math.h>
 

#define ROOT_PATH "/Volumes/MySanDisk/myproj/temp2/diff/diff/"
int test() 
//int main()
{
#if 0
     const char* p1 = ROOT_PATH "BlackFrameDet_src_1280_720_21.nv21";
     const char* p2 = ROOT_PATH "BlackFrameDet_tgr_1280_720_21.yuv420p";


     int fd1 = open(p1, O_RDONLY, 0755);
     int fd2 = open(p2, O_RDONLY, 0755);

     int size = 1280 * 720 * 3 / 2 ;

     uint8_t* buf1 = (uint8_t*) malloc(size);
     uint8_t* buf2 = (uint8_t*) malloc(size);
     int r1 = read(fd1, buf1, size);
     int r2 = read(fd2, buf2, size);
    
    int maxValue = 0;
    for(int i = 0 ; i < 720 ; i++)
    {
        for(int j = 0; j < 1280; j++)
        {
            int y1 = *(buf1 + i*720 + j);
            int y2 = *(buf2 + i*720 + j);
            
            int diff = abs(y1 - y2);
            if (diff > maxValue) {
                maxValue = diff;
            }
            if (diff > 50) {
                printf("row:%d column:%d diff:%d\n", i, j, diff );
            }
            
        }
    }

     printf("%d %d maxValue %d\n", r1, r2, maxValue);
#elif 0
    {
        // vdieo range
        // Y    16~235
        // U/V  16~240
        
        float shaderY = 0.1176470593;
        float shaderU = 0.4549019635;
        float shaderV = 0.5764706135;

        shaderY = shaderY * 255.0;
        shaderU = shaderU * 255.0;
        shaderV = shaderV * 255.0;
//
//        int Y1  = (int)round(shaderY) ;
//        int Cb1 = (int)round(shaderU) ;
//        int Cr1 = (int)round(shaderV) ;
        
        int Y1  = 224 ;
        int Cb1 = 118 ;
        int Cr1 = 134 ;
        
        // (15, 126, 130) diff abs:(1, 2, 1)
        // (15, 126, 131) diff abs:(2, 2, 1)
        // (14, 126, 131) diff abs:(3, 2, 2)
        // (16, 124, 135) diff abs:(2, 3, 1)
        
       
        // (255, 104, 136) diff abs:(22, 11, 7)  --> 这个Y是255 超过了video-range的定义 目前发现这样的diff可能在20以内 rgb=(292.532013, 279.036011, 227.460007)
        
        // (30, 116, 147)  diff abs:(1, 4, 1)    --> yuv的值虽然都在范围内 但是这个组合可能不在范围内, 目前发现这样的diff可能在10以内 rgb=(50.344002, 8.706000, -9.072000)
        // (231, 105, 136) diff abs:(2, 1, 4)    --> rgb: (264.596008, 250.886993, 201.638000)
        // (226, 105, 136) diff abs:(1, 0, 2)    --> 转换成rgb之后是 (258.776001, 245.067001, 195.817993) 超出了 255 截断之后
        
        // (225, 121, 134) diff abs:(0, 1, 0)    --> rgb: (254.028000, 241.563004, 228.477997) rgb在正常区间 yuv也在正确区间 但是还相差1,
        //                                           精度原因(不能存浮点 只能是整数uint8)
        //                                           如果转换之后用截断方式 (254, 241, 228) diff就是0; 四舍五入 (254, 242, 228) diff有1
        // (224, 118,134)  diff abs:(0, 0, 0)    --> (252.863998, 241.037994, 220.972000) 精度原因 四舍五入diff为0 直接截断diff为1
        //
        printf("origin YUV (%d, %d, %d)\n", Y1, Cb1, Cr1);


//        int Y1  = 20u;
//        int Cb1 = 125u;
//        int Cr1 = 135u;
        
        // 20u,125u,135u 这个会得到  RGB的B 是负数
        // 20u,126u,135u 这个就不会是负数
        
        // 检查Y值范围
        if (Y1 < 16 || Y1 > 235) {
            printf("!!! Y1 out of range %d\n", Y1);
        }
        
        // 检查UV值范围
        if (Cb1 < 16 || Cb1 > 240) {
            printf("!!! Cb1 out of range %d\n", Cb1);
        }
        if (Cr1 < 16 || Cr1 > 240) {
            printf("!!! Cr1 out of range %d\n", Cr1);
        }
        
        float R1 = 1.164 * (Y1 - 16)                       + 1.792 * (Cr1 - 128);
        float G1 = 1.164 * (Y1 - 16) - 0.213 * (Cb1 - 128) - 0.534 * (Cr1 - 128);
        float B1 = 1.164 * (Y1 - 16) + 2.114 * (Cb1 - 128);
        
        if (R1 < 0 || R1 > 255) {
            printf("!!! R1 out of range %f\n", R1);
        }
        
        if (G1 < 0 || G1 > 255) {
            printf("!!! G1 out of range %f\n", G1);
        }
        
        if (B1 < 0 || B1 > 255) {
            printf("!!! B1 out of range %f\n", B1);
        }
        
        
        printf("bvt.709 video_range to RGB (float): (%f, %f, %f)\n", R1, G1, B1);
        printf("bvt.709 video_range to RGB (to 1) : (%f, %f, %f)\n", R1/255.0, G1/255.0, B1/255.0);
        
        int Rint = (int)round(R1) ; // metal对浮点数四舍五入
        int Gint = (int)round(G1) ;
        int Bint = (int)round(B1) ;
        
//        int Rint = (int)R1 ;
//        int Gint = (int)G1 ;
//        int Bint = (int)B1 ;
        
        Rint = fmin(Rint, 255); Rint = fmax(Rint, 0);
        Gint = fmin(Gint, 255); Gint = fmax(Gint, 0);
        Bint = fmin(Bint, 255); Bint = fmax(Bint, 0);
        printf("clamp to 0~255: (%d, %d, %d)\n", Rint, Gint, Bint);
        
        float Y  = 16 + 0.183 * Rint + 0.614 * Gint + 0.062 * Bint;
        float Cb =128 - 0.101 * Rint - 0.339 * Gint + 0.439 * Bint;
        float Cr =128 + 0.439 * Rint - 0.399 * Gint - 0.040 * Bint;
        
        printf("bvt.709 video_range to YUV (float):(%f, %f, %f)\n", Y, Cb, Cr);
        
        int YClamp  = fmax( fmin( (int)round(Y),  255), 0);
        int CbClamp = fmax( fmin( (int)round(Cb), 255), 0);
        int CrClamp = fmax( fmin( (int)round(Cr), 255), 0);
        
        printf("clamp to 0~255: (%d, %d, %d)\n", YClamp, CbClamp, CrClamp);
        
        printf("diff abs:(%d, %d, %d)\n"
               , abs(YClamp  - Y1)
               , abs(CbClamp - Cb1)
               , abs(CrClamp - Cr1)
               );
        
    }

//    {
//        float Y1  = 20u  / 255.0;
//        float Cb1 = 125u / 255.0;
//        float Cr1 = 135u / 255.0;
//
//        float R1 = 1.164 * (Y1 - 16/256.0)                             + 1.792 * (Cr1 - 128/256.0);
//        float G1 = 1.164 * (Y1 - 16/256.0) - 0.213 * (Cb1 - 128/256.0) - 0.534 * (Cr1 - 128/256.0);
//        float B1 = 1.164 * (Y1 - 16/256.0) + 2.114 * (Cb1 - 128/256.0);
//        printf("float R1=%f G1=%f B1=%f\n", R1, G1, B1);
//    }

#else
    int Y1  = 252 ;
    int Cb1 = 102 ;
    int Cr1 = 135 ;
    
    // (225, 99, 137)  diff abs:(0, 1, 0)  精度原因
    
    printf("origin YUV (%d, %d, %d)\n", Y1, Cb1, Cr1);
    
    float R1 = Y1                        + 1.4075 * (Cr1 - 128);
    float G1 = Y1 - 0.3455 * (Cb1 - 128) - 0.7169 * (Cr1 - 128);
    float B1 = Y1 + 1.779  * (Cb1 - 128);
    
    printf("bvt.601 full_range to RGB (float): (%f, %f, %f)\n", R1, G1, B1);
    printf("bvt.601 full_range to RGB (to 1) : (%f, %f, %f)\n", R1/255.0, G1/255.0, B1/255.0);
    
    int Rint = (int)round(R1) ;
    int Gint = (int)round(G1) ;
    int Bint = (int)round(B1) ;
    
    Rint = fmin(Rint, 255); Rint = fmax(Rint, 0);
    Gint = fmin(Gint, 255); Gint = fmax(Gint, 0);
    Bint = fmin(Bint, 255); Bint = fmax(Bint, 0);
    printf("clamp to 0~255: (%d, %d, %d)\n", Rint, Gint, Bint);
    
    float Y  =      0.299 * Rint + 0.587 * Gint + 0.114 * Bint;
    float Cb =128 - 0.169 * Rint - 0.331 * Gint + 0.5   * Bint;
    float Cr =128 + 0.5   * Rint - 0.419 * Gint - 0.081 * Bint;
    
    if (R1 < 0 || R1 > 255) {
        printf("!!! R1 out of range %f\n", R1);
    }
    
    if (G1 < 0 || G1 > 255) {
        printf("!!! G1 out of range %f\n", G1);
    }
    
    if (B1 < 0 || B1 > 255) {
        printf("!!! B1 out of range %f\n", B1);
    }
    
    printf("bvt.601 full_range to YUV (float):(%f, %f, %f)\n", Y, Cb, Cr);
    
    int YClamp  = fmax( fmin( (int)round(Y),  255), 0);
    int CbClamp = fmax( fmin( (int)round(Cb), 255), 0);
    int CrClamp = fmax( fmin( (int)round(Cr), 255), 0);
    
    printf("clamp to 0~255: (%d, %d, %d)\n", YClamp, CbClamp, CrClamp);
    
    printf("diff abs:(%d, %d, %d)\n"
           , abs(YClamp  - Y1)
           , abs(CbClamp - Cb1)
           , abs(CrClamp - Cr1)
           );
    
    
#endif
     return 0;
    
}
