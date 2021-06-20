//
//  MetalRenderDelegate.h
//  T3-VertexDescriptor
//
//  Created by hehanlong on 2021/6/17.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface MetalRenderDelegate : NSObject <MTKViewDelegate>

-(instancetype) initWithMTKView:(MTKView*) view;

@end

NS_ASSUME_NONNULL_END
