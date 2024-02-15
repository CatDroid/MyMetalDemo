//
//  ViewController.m
//  T0-CameraYuvInRenderYuvOut
//
//  Created by hehanlong on 2024/2/15.
//

#import "ViewController.h"
#import "MetalView/MetalView.h"
#import "MetalRenderDelegate/MetalRenderDelegate.h"

@interface ViewController ()
{
    MetalRenderDelegate* render ;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    

    MetalView* view = (MetalView*)self.view;
    view.device = MTLCreateSystemDefaultDevice();
    
    render = [[MetalRenderDelegate alloc] initWithMetalView:view];
    view.delegate = render ;
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if(strongSelf) {
            BOOL ok = [strongSelf->render switchCamera];
            if (!ok) { // 弹出鉴权 等待5秒再尝试 
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                               dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                               ^{
                                    __strong typeof(weakSelf) strongSelf = weakSelf;
                                    if(strongSelf) {
                                        BOOL ok = [strongSelf->render switchCamera];
                                        NSAssert(ok, @"switchCamera on fail");
                                    }
                                }
                );
            }
            
        }
    });
  
    
    
}


@end
