//
//  ViewController.m
//  T0-MyMetalViewSimple
//
//  Created by hehanlong on 2021/9/23.
//

#import "ViewController.h"
#import <Metal/Metal.h>
#import "metal/MyMetalView.h"
#import "metal/MetalViewDelegateRender.h"

@interface ViewController ()

@end

@implementation ViewController
{
	MetalViewDelegateRender* render ;
}

- (void)viewDidLoad
{
	
	[super viewDidLoad];
	
	NSLog(@"[ViewConroller][viewDidLoad] begin --------------- ");
	
	
	MyMetalView* view = (MyMetalView*)self.view;
	view.device = MTLCreateSystemDefaultDevice();
	
	
	render = [[MetalViewDelegateRender alloc] initWithDevice: view.device];
	view.delegate = render;
	

	NSLog(@"[ViewConroller][viewDidLoad] end   --------------- ");
}


- (IBAction)onClickDownAddTex:(id)sender
{
	MyMetalView* view = (MyMetalView*)self.view;
	[view generateTexture];
}


- (IBAction)onClickDownDelTex:(id)sender
{
	MyMetalView* view = (MyMetalView*)self.view;
	[view deleteTexture];
}

@end
