//
//  ViewController.m
//  T4_1_MTKTextLoader
//
//  Created by hehanlong on 2021/6/20.
//

#import "ViewController.h"
#import "MetalKit/MetalKit.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    id<MTLDevice> gpu = MTLCreateSystemDefaultDevice();
    
    MTKTextureLoader* loader = [[MTKTextureLoader alloc]initWithDevice:gpu];
    
    NSDictionary<MTKTextureLoaderOption, id>* option = @{
        MTKTextureLoaderOptionTextureStorageMode:@(MTLStorageModePrivate),
        MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionSRGB:@(NO),
        //MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft, 左上角 应该是默认的
    };
    
    // MTKTextureLoaderOriginTopLeft  确保左上角为原点
    // The texture will be flipped vertically if metadata in the file being loaded indicates that the source data starts with the bottom-left corner of the texture.
    // 纹理会上下翻转 如果文件的metadata暗示图像数据从左下脚角始
    
    // MTKTextureLoaderOriginBottomLeft 确保右下角为原点
    // MTKTextureLoaderOriginFlippedVertically 不管怎么样都翻转一下
    
    NSURL* path = [[NSBundle mainBundle] URLForResource:@"FoliageBaseColor" withExtension:@"png"];
    
    {
        NSError* error ;
        NSAssert([path checkResourceIsReachableAndReturnError:&error], @"file not found %@", error);
    }

    NSError* error = nil;
    id<MTLTexture> textureUrl = [loader newTextureWithContentsOfURL:path
                                                            options:option
                                                              error:&error];
    (void)textureUrl; // 没有flip
    
    
    // xcassets XCode assets
    // 右键 AR and SenseKit ---- Texture set ---- 可以设置原点方向(Top Left或者Bottom Left) 是否预乘premulti
    
  
    error = nil;
    id<MTLTexture> textureXCAsset = [loader newTextureWithName:@"FoliageBaseColorTexture"   // 不用png后缀
                                                   scaleFactor:1.0
                                                        bundle:nil
                                                       options:option
                                                         error:&error];
    // name: texture asset或者image asset的名字
    // option: MTKTextureLoaderOptions配置选项
    //          如下选项在加载texture asset会被忽略 但是可用在image asset
    //          MTKTextureLoaderOptionGenerateMipmaps
    //          MTKTextureLoaderOptionSRGB
    //          MTKTextureLoaderOptionCubeFromVerticalTexture
    //          MTKTextureLoaderOptionOrigin                   << 面板可以选择
    // 如果无法在texture asset中创建纹理，就会从image asset中创建纹理
    // 从asset catelog中加载图片, 可以更加符合设备特征
    
    (void)textureXCAsset; // flip
    
    
    error = nil;
    id<MTLTexture> textureImageAsset = [loader newTextureWithName:@"FoliageBaseColorImage"
                                                      scaleFactor:1.0
                                                           bundle:nil
                                                          options:option
                                                            error:&error];
    
    
    (void)textureImageAsset; // 没有flip
 

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *resourcePath = [bundle resourcePath];
    NSLog(@"NSBundle path is %@", resourcePath);
    
    // /private/var/containers/Bundle/Application/734692A6-6289-4053-9816-A8670CCD60D2/T4_1_MTKTextLoader.app
    
    // imageName
    //              加载到内存中后，占据内存空间较大;
    //              相同的图片，图片不会重复加载;
    //              加载内存当中之后，会一直停留在内存当中，不会随着对象的销毁而销毁, 加载进去图片之后，占用的内存归系统管理，我们无法管理
    // imageWithContentsofFile
    //              加载到内存当中后，占据内存空间较小;
    //              相同的图片会被重复加载内存当中
    //              对象销毁的时候，加载到内存中图片会随着一起销毁
    
    //UIImage* image = [UIImage imageWithContentsOfFile:@"FoliageBaseColor"]; // nil
    
    NSURL* urlPath = [bundle URLForResource:@"FoliageBaseColor" withExtension:@"png"];
    UIImage* image = [UIImage imageWithData:[NSData dataWithContentsOfURL:urlPath]];
    
    
    image = [UIImage imageNamed:@"FoliageBaseColor"]; // ok 图片可以不在asset catelogy中
    
    (void) image;
    
    //-----------------------------------------------------------------------------------------------------------------------
    
    // 在iOS 11之后另外支持了HEIC（即使用了HEVC编码的HEIF格式）
    // 在Core Graphics中坐标系的坐标原点在屏幕左下角，沿y轴正方向是向上的， CGContextRef context = UIGraphicsGetCurrentContext();
    // 在UIKit中坐标原点在屏幕左上角，沿y轴正方向向下
    
    // CG_EXTERN CGContextRef __nullable CGBitmapContextCreate(void * __nullable data,size_t width, size_t height, size_t bitsPerComponent, size_t bytesPerRow,CGColorSpaceRef cg_nullable space, uint32_t bitmapInfo)CG_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);

    // 从一个URL（支持网络图的HTTP URL，或者是文件系统的fileURL）创建ImageSource
    // CGImageSourceRef source = CGImageSourceCreateWithURL()
    
    // NSData is toll-free bridged with its Core Foundation counterpart, CFDataRef.
    
    
    NSData* fileContent = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"FoliageBaseColor" withExtension:@"png"]];
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)fileContent, nil);
    
    CFStringRef fileType = CGImageSourceGetType(source);
    size_t imageCount = CGImageSourceGetCount(source);// git动图 图片数量
    CFRelease(fileType);
    NSLog(@"Source Type = %@ %lu", fileType, imageCount ); // Source Type = public.png 1
    
    // Image/IO的解码，支持了常见的图像格式，包括PNG（包括APNG）、JPEG、GIF、BMP、TIFF
    // (具体的，可以通过CGImageSourceCopyTypeIdentifiers来打印出来，不同平台不完全一致）
    // 在iOS 11之后另外支持了HEIC（即使用了HEVC编码的HEIF格式）
    
    // CGImageSourceCopyTypeIdentifiers 返回 Uniform Type Identifiers (UTIs) 的数组          Image IO 作为数据源支持
    // CGImageDestinationCopyTypeIdentifiers 返回一个Uniform Type Identifiers (UTIs) 数组     Image IO 作为图片目标
    //
    CFArrayRef supports =  CGImageSourceCopyTypeIdentifiers();
    NSLog(@"Image I/O support image encode list %lu ", CFArrayGetCount(supports)); // 53 iphoneXR 14.1
    CFShow(supports); // 使用CFShow函数将数组打印到Xcode中的控制台   "public.heif",
    CFRelease(supports);
    //for (int i = 0 ; i < CFArrayGetCount(supports) ; i++ )
    //{
    //     CFArrayGetValueAtIndex(supports, i);
    //     NSLog(@"image type = %d", CFShow(CFTypeRef obj));
    // }
    
    
    CFDictionaryRef imageMetaData = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL); // 获取图片meta信息
    NSDictionary *metaDataInfo    = CFBridgingRelease(imageMetaData);
    
    // NSDictionary is NSDictionary is “toll-free bridged” with its Core Foundation counterpart, CFDictionaryRef
    //
    // CFIndex CFGetRetainCount(CFTypeRef cf);  CFTypeRef 一个指向Core Foundation对象的通用指针
    // 从Core到Cocoa 对象所有权桥接给ARC
    // 将非Objective-C对象转换为Objective-C对象，同时将对象的管理权交给ARC，开发者无需手动管理内存。
    
    NSLog(@"CFBridgingRelease后 引用数目 %lu", CFGetRetainCount(imageMetaData) ); // = 1
    
    [metaDataInfo enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSLog(@"png meta %@:%@", key, obj);
    }];
    // png meta ColorModel:RGB
    // png meta ProfileName:Generic RGB Profile
    // png meta PixelHeight:1024
    // png meta PixelWidth:1024
    // png meta Depth:8
    // png meta DPIHeight:72
    // png meta DPIWidth:72
    
    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    
    size_t witdh = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    size_t bitsPerComponent = CGImageGetBitsPerComponent(cgImage);
    size_t bitsPerPixel = CGImageGetBitsPerPixel(cgImage);
    // const CGFloat *  CGImageGetDecode(cgImage);
    CGBitmapInfo info = CGImageGetBitmapInfo(cgImage);
    
    CFDataRef rawData = CGDataProviderCopyData(CGImageGetDataProvider(cgImage)); // 从数据源获取直接解码的数据
    
    NSData* rawData1 = CFBridgingRelease(rawData);
    
    
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

    NSString *filePath = [cachePath stringByAppendingPathComponent:@"raw.rgb"];
    
    BOOL success = [rawData1 writeToFile:filePath atomically:YES];
    if (success) {
        NSLog(@"write to file done! witdh=%lu =height%lu bitsPerComponent=%lu bitsPerPixel=%lu ",
              witdh, height, bitsPerComponent, bitsPerPixel);
    }
    
    //-----------------------------------------------------------------------------------------------------------------------
    
    
}



@end
