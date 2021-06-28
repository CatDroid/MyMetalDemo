//
//  ViewController.m
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/27.
//

#import "ViewController.h"
#import "MetalViewDelegateRender.h"

@interface ViewController ()
{
    MetalViewDelegateRender* render ;
}


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    MetalView* view = (MetalView*)self.view;
    view.device = MTLCreateSystemDefaultDevice();
    
    render = [[MetalViewDelegateRender alloc] initWithMetalView:view];
    view.delegate = render ;
    
}

- (IBAction)SwitchCamera:(id)sender
{
    BOOL state = [sender isOn];
    if (state)
    {
        BOOL ok = [render switchCamera];
        if (!ok) {
            [sender setOn:NO];
        }
    }
    else
    {
        [render switchCamera];
    }
}

 


- (IBAction)SwtichRecord:(id)sender {
    
    BOOL state = [sender isOn];
    if (state)
    {
        [render switchRecord];
    }
    else
    {
        [render switchRecord];
    }
}

@end
