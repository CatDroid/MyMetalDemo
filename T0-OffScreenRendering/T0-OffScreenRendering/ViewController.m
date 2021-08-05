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

#import <objc/runtime.h>


static NSString* mBtnRecordStr      = @"mBtnRecord";
static NSString* mBtnViewResizeStr  = @"mBtnViewResize";

@interface MetalView (MyMetalView) // 类的扩展 分类
// 分类中能不能定义实例变量
//
// 如果拖动button到View中 只能绑定方法; 拖动到Contorller可以绑定对象

// 属性不能自动生成setter/getter 和 实例变量。类布局已经确定
//@property (nonatomic,weak) UIButton* mBtnRecord;
//@property (nonatomic,weak) UIButton* mBtnViewResize;
//@property (nonatomic,weak) UIButton* mBtnWaitForUse ;

@end


@implementation MetalView (MyMetalView)
 
- (UIButton*) mBtnRecord
{
    id (^block)(void) = objc_getAssociatedObject(self, (__bridge void*)mBtnRecordStr);
    return block ? block() : NULL ;
}

- (void)setMBtnRecord:(UIButton *) btn
{
    __weak id weakObj = btn ;
    
    id (^block)(void) = ^{ return weakObj; };
    
    //关联对象 源对象，关联时的用来标记是哪一个属性的key（因为你可能要添加很多属性），关联的对象和一个关联策略
    objc_setAssociatedObject(self, (__bridge void*)mBtnRecordStr, block, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    /*
     关联策略是个枚举值
     enum {
         OBJC_ASSOCIATION_ASSIGN = 0,           // 关联对象的属性是弱引用
         OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1, // 关联对象的属性是强引用并且关联对象不使用原子性
         OBJC_ASSOCIATION_COPY_NONATOMIC = 3,   // 关联对象的属性是copy并且关联对象不使用原子性
         OBJC_ASSOCIATION_RETAIN = 01401,       // 关联对象的属性是copy并且关联对象使用原子性
         OBJC_ASSOCIATION_COPY = 01403          // 关联对象的属性是copy并且关联对象使用原子性
     };
     */
}


- (UIButton*) mBtnViewResize
{
    id (^block)(void) = objc_getAssociatedObject(self, (__bridge void*)mBtnViewResizeStr);
    return block ? block() : NULL ;
}

- (void) setMBtnViewResize:(UIButton *) btn
{
    __weak id weakObj = btn ;
    id (^block)(void) = ^{ return weakObj; };
    objc_setAssociatedObject(self, (__bridge void*)mBtnViewResizeStr, block, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}


- (UIView *) hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = [super hitTest:point withEvent:event];
    
    CGPoint tempPoint = [self.mBtnRecord convertPoint:point fromView:self];
    
    if ([self.mBtnRecord pointInside:tempPoint withEvent:event])
    {
        return self.mBtnRecord;
    }
    
    tempPoint = [self.mBtnViewResize convertPoint:point fromView:self];
    
    if ([self.mBtnViewResize pointInside:tempPoint withEvent:event])
    {
        return self.mBtnViewResize;
    }
    
    // 这个方法会查找view自身的tag、子view的tag、子view的子view的tag
    // 兄弟之间应该没有顺序
    //
    //
    // Tag是用来标记控件（view）的。通过UIView的tag值，它可以帮助你寻找它的子视图。
    // 比如你有一个UIView，这个UIView含有一个Button，而创建Button时用的是临时变量，你没有这个Button的引用，
    // 在这种情况下，你如果想访问这个UIView的Button，你就可以给这个Button一个Tag
  
    UIButton* btnWaitForUse = [self viewWithTag:1314];
    if (btnWaitForUse)
    {
        tempPoint = [btnWaitForUse convertPoint:point fromView:self];
        if ([btnWaitForUse pointInside:tempPoint withEvent:event])
        {
            return btnWaitForUse;
        }
    }
    return view;
}
@end


@interface ViewController ()
{
    MetalViewDelegateRender* render ;
    
    int mViewSizeSwitch ;
    
    CGRect  mOriginFrame ;
    CGFloat mNativeScale ;

    __weak IBOutlet UIButton *mBtnRecord;
    __weak IBOutlet UIButton *mBtnViewResize;
    
}

@end


@implementation ViewController
 

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSLog(@"viewDidLoad before");
    
    MetalView* view = (MetalView*)self.view;
    view.device = MTLCreateSystemDefaultDevice();
    
    render = [[MetalViewDelegateRender alloc] initWithMetalView:view];
    
    view.delegate = render;
    
    mOriginFrame = view.frame; // 单位是point 需要乘以NativeScale才是像素
    
    mNativeScale = [UIScreen mainScreen].nativeScale ;
    
    NSLog(@"viewDidLoad done "); // ViewContorler:viewDidLoad 返回后才是  View:didMoveToWindow
    
    
    { // 避免View缩小的导致按钮不能响应
        view.mBtnRecord     = mBtnRecord ;
        view.mBtnViewResize = mBtnViewResize ;
    
    }
}


- (IBAction)onRecord:(id)sender
{
    [render switchRecord];
}

- (IBAction)onTouchDownToChangeViewSize:(id)sender
{
    switch (mViewSizeSwitch)
    {
        case 0: // 按屏幕比例缩放
        {
            CGSize size = [UIScreen mainScreen].bounds.size;
            [self.view setFrame:CGRectMake(0, 0, size.width * 0.4 , size.height * 0.4)]; // setFrame单位是Point
            
        } break;
        case 1:  // 固定为 600*800 竖方向
        {
            [self.view setFrame:CGRectMake(0, 0, 600/mNativeScale, 800/mNativeScale)];
            
        } break;
        case 2: // 固定为 800*600 竖方向
        {
            [self.view setFrame:CGRectMake(0, 0, 800/mNativeScale, 600/mNativeScale)];
           
        } break;
        case 3: // 屏幕尺寸
        {
            //CGFloat scale = [UIScreen mainScreen].nativeScale;
            CGSize size = [UIScreen mainScreen].bounds.size;
            [self.view setFrame:CGRectMake(0, 0, size.width, size.height)];
            
        } break;
        default:
        {
            
        } break;
    }
    
    mViewSizeSwitch =  mViewSizeSwitch + 1;
    
    mViewSizeSwitch = mViewSizeSwitch % 4 ;
    
}


- (IBAction)onTouchDownToWaitForUse:(id)sender
{
    NSLog(@"wait for use touch down");

}


@end
