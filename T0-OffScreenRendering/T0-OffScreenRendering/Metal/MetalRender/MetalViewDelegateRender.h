//
//  MTKViewDelegateRender.h
//  T1-Triangle
//
//  Created by hehanlong on 2021/6/16.
//

#import <Foundation/Foundation.h>
#import "MetalView.h"

NS_ASSUME_NONNULL_BEGIN
 
@interface MetalViewDelegateRender : NSObject <MetalViewDelegate>

-(nonnull instancetype) initWithMetalView:(nonnull MetalView*) mtkView;

@end

NS_ASSUME_NONNULL_END
