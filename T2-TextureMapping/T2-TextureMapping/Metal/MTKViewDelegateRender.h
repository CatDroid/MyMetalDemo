//
//  MTKViewDelegateRender.h
//  T2-TextureMapping
//
//  Created by hehanlong on 2021/6/17.
//

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

// Objective-C不支持多继承，由于消息机制名字查找发生在运行时而非编译时，很难解决多个基类可能导致的二义性问题
@interface MTKViewDelegateRender:NSObject <MTKViewDelegate>

-(instancetype) initWithMTKView:(MTKView*) view;

@end

NS_ASSUME_NONNULL_END
