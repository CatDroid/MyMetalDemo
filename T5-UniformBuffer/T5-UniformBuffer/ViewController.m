//
//  ViewController.m
//  T5-UniformBuffer
//
//  Created by hehanlong on 2021/6/20.
//

#import "ViewController.h"

#import "metal/MTKViewRenderDelegate.h"

@interface ViewController ()
{
    id<MTKViewDelegate> _render ;
}
   

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
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
    view.delegate = _render;
    
    
}


@end
