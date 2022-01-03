#import "MBEViewController.h"
#import "MBEContext.h"
#import "MBEImageFilter.h"
#import "MBESaturationAdjustmentFilter.h"
#import "MBEGaussianBlur2DFilter.h"
#import "UIImage+MBETextureUtilities.h"
#import "MBEMainBundleTextureProvider.h"

@interface MBEViewController ()

@property (nonatomic, strong) MBEContext *context;
@property (nonatomic, strong) id<MBETextureProvider> imageProvider;
@property (nonatomic, strong) MBESaturationAdjustmentFilter *desaturateFilter;
@property (nonatomic, strong) MBEGaussianBlur2DFilter *blurFilter;

@property (nonatomic, strong) dispatch_queue_t renderingQueue;
@property (atomic, assign) uint64_t jobIndex;

@end

@implementation MBEViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.renderingQueue = dispatch_queue_create("Rendering", DISPATCH_QUEUE_SERIAL);

    [self buildFilterGraph];
    [self updateImage];
}

- (void)buildFilterGraph
{
    self.context = [MBEContext newContext];
    
    self.imageProvider = [MBEMainBundleTextureProvider textureProviderWithImageNamed:@"mandrill"
                                                                             context:self.context];
    
    self.desaturateFilter = [MBESaturationAdjustmentFilter filterWithSaturationFactor:self.saturationSlider.value
                                                                              context:self.context];
    self.desaturateFilter.provider = self.imageProvider; // 链式反应
    
    self.blurFilter = [MBEGaussianBlur2DFilter filterWithRadius:self.blurRadiusSlider.value
                                                        context:self.context];
    self.blurFilter.provider = self.desaturateFilter;
    // 链式反应 读取 self.blurFilter.texture 会导致先读取provider的texture 递归下去 并进行渲染/计算
}

- (void)updateImage
{
    ++self.jobIndex;
    uint64_t currentJobIndex = self.jobIndex;

    // Grab these values while we're still on the main thread, since we could
    // conceivably get incomplete values by reading them in the background.
    float blurRadius = self.blurRadiusSlider.value;
    float saturation = self.saturationSlider.value; // 读取UI控件的进度条的值
    
    dispatch_async(self.renderingQueue, ^{
        if (currentJobIndex != self.jobIndex) // 如果再次更新就不执行旧的任务了
            return;

        self.blurFilter.radius = blurRadius;
        self.desaturateFilter.saturationFactor = saturation;

        id<MTLTexture> texture = self.blurFilter.texture; // 获取的时候会进行处理
        UIImage *image = [UIImage imageWithMTLTexture:texture];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.image = image; // UI控件上显示出来
        });
    });
}

- (IBAction)blurRadiusDidChange:(id)sender
{
    [self updateImage];
}

- (IBAction)saturationDidChange:(id)sender
{
    [self updateImage];
}

@end
