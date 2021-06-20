//
//  ViewController.m
//  T2-TextureMapping
//
//  Created by hehanlong on 2021/6/17.
//

#import "ViewController.h"
#import "MetalKit/MetalKit.h"
#import "MTKViewDelegateRender.h"

@interface ViewController ()
{
    // id <MTKViewDelegateRender> _delegate; // <> 这个一定要写协议
    id <MTKViewDelegate> _delegate ;
}


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    MTKView* view = (MTKView*)self.view ;
    
    view.backgroundColor = [UIColor yellowColor];
    
    view.device = MTLCreateSystemDefaultDevice();
    if (view.device == nil) {
        NSLog(@"Device Not Support Metal");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return ;
    }
    
    _delegate = [[MTKViewDelegateRender alloc] initWithMTKView:view];
    view.delegate = _delegate;
}


@end
