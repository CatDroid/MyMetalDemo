//
//  MTKViewRenderDelegate.h
//  T5-UniformBuffer
//
//  Created by hehanlong on 2021/6/20.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTKViewRenderDelegate : NSObject <MTKViewDelegate>

-(instancetype) initWithMTKView:(MTKView*) view;

@end

NS_ASSUME_NONNULL_END
