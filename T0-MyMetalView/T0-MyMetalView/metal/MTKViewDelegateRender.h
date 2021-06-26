//
//  MTKViewDelegateRender.h
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h> // MTKViewDelegate

NS_ASSUME_NONNULL_BEGIN

@interface MTKViewDelegateRender : NSObject

-(nonnull instancetype) initWithCALayer:(CAMetalLayer*) layer;

- (void) drawWithLayer:(nonnull CAMetalLayer *) layer;

@end

NS_ASSUME_NONNULL_END
