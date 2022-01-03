@import Foundation;

@protocol MTLTexture;

@protocol MBETextureProvider <NSObject>

// 必须实现的方法或必须使用的属性可以不用@required说明，只有遇到可选的属性和方法时再使用@optional
// 必须实现的属性/方法列表（这里只有一个属性）

@property (nonatomic, readonly) id<MTLTexture> texture; // 协议里面只有一个属性

@end
