//
//  ViewController.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#import "ViewController.h"

#import <Metal/Metal.h>

#import "MetalView.h"
#import "MetalViewDelegateRender.h"

@interface ViewController ()
{
    MetalViewDelegateRender* render ;

}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"viewDidLoad before");
    
    MetalView* view = (MetalView*)self.view;
    view.device = MTLCreateSystemDefaultDevice();
    
    render = [[MetalViewDelegateRender alloc] initWithMetalView:view];
    
    view.delegate = render;
    
    NSLog(@"viewDidLoad done "); // ViewContorler:viewDidLoad 返回后才是  View:didMoveToWindow
}



- (IBAction)onRecord:(id)sender
{
    [render switchRecord];
}


@end
