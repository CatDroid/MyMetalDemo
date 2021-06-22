//
//  ViewController.m
//  T0-MyMetalView
//
//  Created by hehanlong on 2021/6/21.
//

#import "ViewController.h"

#import <MetalKit/MetalKit.h> // MTK = MetalKit MTKView
#import "MTKViewDelegateRender.h"
 

@interface ViewController ()
{
    MTKViewDelegateRender* _render ;
    
    CAMetalLayer* renderLayer;
    CADisplayLink *displayLink;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
   
    [self setupLayer];
    
    
    // MTKView 类提供了Metal-aware视图的默认实现，您可以使用它来使用Metal渲染图形并在屏幕上显示它们
    // 类似Android的GLSurfaceView
    // MTKView使用CAMetalLayer来管理metal可渲染对象
    // MTKView需要MTLDevice来管理Metal对象, 并且必须在渲染前, 设置设备属性 以及可选地设置view的属性
    
    // 默认背景色: 灰色
    self.view.backgroundColor = [UIColor grayColor];
 
    
    //MTKView* _view = (MTKView*)self.view ; // storyboard's view custom class is MTKView
    
    
    _render = [[MTKViewDelegateRender alloc] initWithCALayer:renderLayer];
    
    

}

// 创建自定义的Metal View /Creating a Custom Metal View
// https://developer.apple.com/documentation/metal/drawable_objects/creating_a_custom_metal_view?language=objc


-(void) setupLayer
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    
    
    renderLayer = [CAMetalLayer layer];
    renderLayer.device = device;
    renderLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB; // ??? sRGB和非sRGB区别 
    
    // CAMetalLayer 分配 他的MTLTexture 只带有MTLTextureUsageRenderTarget这个usage flag
    // Core Animation 可以优化纹理以用于显示目的。
    // 但是不能 sampling 和  pixel read/write 要支持这些操作的话 设置为NO
    renderLayer.framebufferOnly = YES;

    // 这个layer在父layer坐标系下的位置和大小(frame rectangle)
    // 对于图层，帧矩形框 是 从边界、锚点和位置属性中的值派生的计算属性。 bounds, anchorPoint, position
    // 当您为此属性分配新值时，图层会更改其位置和边界属性以匹配您指定的帧矩形框
    // 帧矩形框中每个坐标的值以“点”为单位进行测量。
    // 如果 transform 属性应用的旋转变换不是 90 度的倍数，则不要设置框架
    renderLayer.frame = self.view.layer.frame;

    // 默认情况下，图层创建的纹理大小与其内容相匹配
    // 也就是说，此属性的值是图层的 边界大小 乘以 其内容比例因子
    
    const CGSize boundSize = self.view.bounds.size;
    const float kScale = [UIScreen mainScreen].scale;
    renderLayer.drawableSize = CGSizeMake(boundSize.width * kScale, boundSize.height * kScale);
     
    [self.view.layer addSublayer: renderLayer];
    
    /*
     该属性 告诉 绘图系统 应该如何处理视图
     如果设置为 YES，绘图系统会将视图视为完全不透明，这允许绘图系统优化某些绘图操作并提高性能。
     如果设置为 NO，绘图系统通常会将视图与其他内容合成。 此属性的默认值为 YES。
     
     一个不透明的视图应该用完全不透明的内容来填充它的边界
     也就是说，内容的 alpha 值应该是 1.0。
     
     如果视图不透明并且未填充其边界或包含完全或部分透明的内容，则结果是不可预测的。
     如果视图完全或部分透明，则应始终将此属性的值设置为 NO。
     
     您只需要在 UIView 的子类中为 opaque 属性设置一个值，这些子类使用 drawRect: 方法绘制自己的内容。
     opaque 属性在系统提供的类中不起作用，例如 UIButton、UILabel、UITableViewCell 等。
     */
    self.view.opaque = YES;
    
    /*
     比例因子决定了 视图中的内容 如何从 逻辑坐标空间（以点为单位）映射到 设备坐标空间（以像素为单位）。
     
     该值通常为 1.0 或 2.0。
     
     较高的比例因子表示视图中的每个点都由底层中的多个像素表示。
     
     例如，如果比例因子为 2.0 且视图帧大小为 50 x 50 点，则用于呈现该内容的位图大小为 100 x 100 像素
     
     此属性的默认值是与 当前显示视图的屏幕关联 的比例因子。
     
     如果您的自定义视图实现了自定义 drawRect: 方法并与窗口关联，
     或者如果您使用 GLKView 类绘制 OpenGL ES 内容，
     您的视图将以屏幕的全分辨率绘制。
     
     对于系统视图，即使在高分辨率屏幕上，该属性的值也可能是1.0。 ？？？？？？？？？
     
     通常，您不需要修改此属性中的值。
     但是，如果您的应用程序使用 OpenGL ES 进行绘制，您可能需要更改比例因子以换取图像质量以换取渲染性能。？？？？？？？
     
     有关如何调整 OpenGL ES 渲染环境的更多信息，请参阅 OpenGL ES 编程指南中的支持高分辨率显示。
     */
    self.view.contentScaleFactor = kScale; // ？？？
    
    
    // CADisplayLink 这些跟CAMetalLayer和UIView没有直接关系
    displayLink = [CADisplayLink displayLinkWithTarget:self  selector: @selector(render)];
    [displayLink addToRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
    
}

// CADisplayLink 在 NSRunLoop currentRunLoop 中回调
-(void) render
{
    [_render drawWithLayer:renderLayer];
    
}

// 复写dealloc函数的时候加上［super dealloc］；会出现错误
// 析构函数 默认会从从子到父执行 不用自己调用
-(void) dealloc
{
    [displayLink invalidate];
}

@end
