//
//  MetalViewDelegateRender.h
//  T0-MyMetalViewSimple
//
//  Created by hehanlong on 2021/9/24.
//

#import <Foundation/Foundation.h>
#import "MyMetalView.h"

NS_ASSUME_NONNULL_BEGIN

@interface MetalViewDelegateRender : NSObject<MetalViewDelegate>

-(instancetype) initWithDevice:(id<MTLDevice>) gpu;

-(void) OnDrawableSizeChange:(CGSize)size WithView:(MyMetalView*) view;

-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MyMetalView*) view;

-(void) setTestTexture:(id<MTLTexture>) tex;

@end

NS_ASSUME_NONNULL_END
