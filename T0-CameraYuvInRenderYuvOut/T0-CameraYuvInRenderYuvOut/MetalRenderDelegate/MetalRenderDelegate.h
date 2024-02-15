//
//  MetalRenderDelegate.h
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#ifndef MetalRenderDelegate_h
#define MetalRenderDelegate_h


#import <Foundation/Foundation.h>

#import "MetalView.h"

NS_ASSUME_NONNULL_BEGIN
 
@interface MetalRenderDelegate : NSObject <MetalViewDelegate>

-(nonnull instancetype) initWithMetalView:(nonnull MetalView*) mtkView;

-(void) switchRecord;

-(BOOL) switchCamera;

@end

NS_ASSUME_NONNULL_END


#endif /* MetalRenderDelegate_h */
