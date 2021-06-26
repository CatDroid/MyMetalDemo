//
//  MetalFrameBuffer.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/23.
//

#import "MetalFrameBuffer.h"

@implementation MetalFrameBuffer
{
    
}

-(instancetype) initWithDevice:(id<MTLDevice>)gpu WithSize:(CGSize)size
{
   
    
    self = [super init];
    if (self)
    {
        
        // 目前固定写死格式
        // 颜色:BGRA+sRGB
        // 深度模板:Depth32+Stencil8
        
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat =  MTLPixelFormatBGRA8Unorm_sRGB;
        textureDescriptor.textureType = MTLTextureType2D;
        textureDescriptor.width = size.width;
        textureDescriptor.height = size.height;
        /*
         MTLTextureUsageShaderRead  这个会给纹理设置属性 access::read and access::sample 在shader中调用 read() or sample()
         MTLTextureUsageShaderWrite 纹理可读可写 access::read_write attribute. 在shader中会调用write()
         MTLTextureUsageRenderTarget 纹理作为render pass中的颜色 深度 模板等目标
         */
        textureDescriptor.usage = MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;
        id<MTLTexture> colorTexture = [gpu newTextureWithDescriptor:textureDescriptor];
        
        
        textureDescriptor.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        id<MTLTexture> depthTexture = [gpu newTextureWithDescriptor:textureDescriptor];
        
        
        _renderPassDescriptor = [[MTLRenderPassDescriptor alloc] init];
        _renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0); // 灰色
        _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _renderPassDescriptor.colorAttachments[0].texture = colorTexture ;
        
        _renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        _renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare; // 这个不用store ??
        _renderPassDescriptor.depthAttachment.clearDepth = 1.0;
        _renderPassDescriptor.depthAttachment.texture = depthTexture;
     
        _renderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionClear;
        _renderPassDescriptor.stencilAttachment.storeAction = MTLStoreActionDontCare;
        _renderPassDescriptor.stencilAttachment.clearStencil = 0.0 ;
        _renderPassDescriptor.stencilAttachment.texture = depthTexture;
        
    }
    
    return self ;
    
}


@end
