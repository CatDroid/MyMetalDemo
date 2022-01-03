@import Foundation;

@protocol MBETextureProvider;

@protocol MBETextureConsumer <NSObject>

@property (nonatomic, strong) id<MBETextureProvider> provider; // 协议是个属性，属性也是个协议对象，必须记录提供者 

@end
