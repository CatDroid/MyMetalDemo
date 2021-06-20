//
//  ViewController.m
//  T4-AAPLMesh
//
//  Created by hehanlong on 2021/6/18.
//

#import "ViewController.h"
#import <MetalKit/MetalKit.h>

#import "metal/MTKViewRenderDelegate.h"

@interface ViewController ()
{
    id<MTKViewDelegate> _render ;
}


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
   
    MTKView* view = (MTKView*)self.view;
    view.backgroundColor = [UIColor greenColor];
    view.device = MTLCreateSystemDefaultDevice();
    
    if (view.device == nil)
    {
        NSLog(@"device not support metal");
        self.view = [[UIView alloc] initWithFrame: self.view.frame];
        return ;
    }
    
    _render = [[MTKViewRenderDelegate alloc] initWithMTKView:view];
    view.delegate = _render ;
    
}


@end
