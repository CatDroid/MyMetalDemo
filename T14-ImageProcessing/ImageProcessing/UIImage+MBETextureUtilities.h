@import UIKit;

@protocol MTLTexture;

@interface UIImage (MBETextureUtilities) // objc 分类Category 给原有类添加方法

+ (UIImage *)imageWithMTLTexture:(id<MTLTexture>)texture;

@end

