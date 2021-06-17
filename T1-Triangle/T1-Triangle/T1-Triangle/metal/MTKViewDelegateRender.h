//
//  MTKViewDelegateRender.h
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h> // MTKViewDelegate

NS_ASSUME_NONNULL_BEGIN

// Nonnull区域设置(Audited Regions):
// 如果需要每个属性或每个方法都去指定nonnull和nullable，是一件非常繁琐的事。
// 苹果为了减轻我们的工作量，专门提供了两个宏：NS_ASSUME_NONNULL_BEGIN和NS_ASSUME_NONNULL_END
// 在这两个宏之间的代码，所有简单指针对象都被假定为nonnull，因此我们只需要去指定那些nullable的指针

// 复杂的指针类型(如id *)   id本来就是一个指针,id* 相当于void**
// 必须显示去指定是nonnull还是nullable。
// 例如，指定一个指向nullable对象的nonnull指针，可以使用”__nullable id * __nonnull”。
 
@interface MTKViewDelegateRender : NSObject <MTKViewDelegate>

-(nonnull instancetype) initWithMetalKitView:(nonnull MTKView*) mtkView;

@end

NS_ASSUME_NONNULL_END
