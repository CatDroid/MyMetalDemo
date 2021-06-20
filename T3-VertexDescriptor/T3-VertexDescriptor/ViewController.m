//
//  ViewController.m
//  T3-VertexDescriptor
//
//  Created by hehanlong on 2021/6/17.
//

#import "ViewController.h"
#import <MetalKit/MetalKit.h>
#import "MetalRenderDelegate.h"

@interface ViewController ()
{
    id<MTKViewDelegate> render ;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    id<MTLDevice> gpu = MTLCreateSystemDefaultDevice();
    
    MTKView* view = (MTKView*)self.view;
    view.backgroundColor = [UIColor greenColor];
    view.device = gpu;
    
    
    render = [[MetalRenderDelegate alloc] initWithMTKView:view];
    
    view.delegate = render;
    
    
    
}


@end
