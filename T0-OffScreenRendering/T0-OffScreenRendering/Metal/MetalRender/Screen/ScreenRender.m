//
//  ScreenRender.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/24.
//

#import "ScreenRender.h"

#include <Metal/Metal.h>
#import "MetalFrameBuffer.h"
#import "ScreenMesh.h"


@implementation ScreenRender
{
    id<MTLRenderPipelineState>  _renderPipeLineState ;
    id<MTLDepthStencilState>    _depthStencilState ;
    id<MTLSamplerState>         _samplerState0 ;
    
    ScreenMesh* _mesh ; // 应该作为材质的输入
}

// 初始化这个材质:
// 使用的shader,启用混合,关闭深度检测,输出framebufer颜色附件要求sRGB,
// (不包含定义正面和面剔除, 顶点bffer和面剔除都在encoder给定)
-(instancetype) initWithDevice:(id<MTLDevice>) gpu WithView:(MetalView*)view
{
    self = [super init];
    if (self)
    {
        //------------
        id<MTLLibrary> library = [gpu newDefaultLibrary];
        id<MTLFunction> vertexFunction =  [library newFunctionWithName:@"ScreenVertexShader"];
        id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"ScreenFragmentShader"];
        
        MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDesc.vertexFunction = vertexFunction ;
        renderPipelineDesc.fragmentFunction = fragmentFunction ;
        
        // 这个应该跟view/framebuffer格式一样
        renderPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
        
        renderPipelineDesc.colorAttachments[0].blendingEnabled = YES; //启用混合
        renderPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        renderPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        renderPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        renderPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        renderPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        renderPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
         
        
        //renderPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatInvalid ; // ???? 为啥需要
        //renderPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatInvalid ; // 这个材质不需要深度和模板附件
        
        renderPipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
        renderPipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
        
        /*
            此属性返回一个 MTLPipelineBufferDescriptor 对象数组
            每个数组索引对应于"渲染管道顶点函数(render pipeline's vertex function)"的 "缓冲区参数表"( argument table ) 中的相同索引
         */
        MTLPipelineBufferDescriptorArray* bufferArgumentTable = renderPipelineDesc.vertexBuffers;  // readonly
        // MTLPipelineBufferDescriptorArray* fBufferArgumentTable = renderPipelineDesc.fragmentBuffers;
        MTLPipelineBufferDescriptor * buffer0Descriptor = bufferArgumentTable[0];
        MTLPipelineBufferDescriptor * buffer1Descriptor = bufferArgumentTable[1];
        /*
            确定，是否可以在相关命令使用缓冲区之前，更新缓冲区的内容。
            默认值是 MTLMutabilityDefault
            如果 没有明确声明可变性，Metal 使用以下默认行为：
            Regular buffers are mutable by default, and Metal treats MTLMutabilityDefault as if it were MTLMutabilityMutable.
            Argument buffers are immutable by default, and Metal treats MTLMutabilityDefault as if it were MTLMutabilityImmutable.
         
            如果 设置buffer到encoder的argument table  和相关 命令缓冲区(command buffer) 完成执行之间, // ？？ 怎么知道完成了 cpu端完成???
            声明不会修改缓冲区的内容，Metal可以提高性能
         
            在此时间间隔内，CPU 或 GPU 都无法更新缓冲区
            为了获得更好的性能，请尽可能使用不可变缓冲区。
         */
        buffer0Descriptor.mutability = MTLMutabilityImmutable;
        buffer1Descriptor.mutability = MTLMutabilityImmutable;
        /*
            描述在 顶点着色器函数的传递参数中 每顶点输入结构体 的布局
         */
        renderPipelineDesc.vertexDescriptor = nil ;
        
        renderPipelineDesc.sampleCount = 1 ;
        
        NSError* error ;
        _renderPipeLineState = [gpu newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
        
        //------------

        MTLDepthStencilDescriptor* depthStenclDesc = [[MTLDepthStencilDescriptor alloc] init];
        depthStenclDesc.depthWriteEnabled = false ; // 只是关闭深度写入 但是允许深度测试
        depthStenclDesc.depthCompareFunction = MTLCompareFunctionLess ;
        MTLStencilDescriptor* stencil = [[MTLStencilDescriptor alloc] init];
        stencil.stencilCompareFunction = MTLCompareFunctionAlways;
        stencil.depthFailureOperation = MTLStencilOperationKeep;
        depthStenclDesc.frontFaceStencil = stencil;
        depthStenclDesc.backFaceStencil = stencil;  // 关闭深度测试 模板测试总是成功并保持模板附件原始值
        
        _depthStencilState = [gpu newDepthStencilStateWithDescriptor:depthStenclDesc];
        
        //------------
        
        MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
        samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.mipFilter = MTLSamplerMipFilterNotMipmapped; // 不使用mipmap  mipFilter选项用来混合两个mipmap级别的像素
       
        _samplerState0 = [gpu newSamplerStateWithDescriptor:samplerDesc];
        //------------
        
        _mesh = [[ScreenMesh alloc] initWithDevice:gpu]; // 创建模型文件
    }
    else
    {
        NSLog(@"initWithDevice super init fail");
    }
    
    return self ;
}


-(BOOL) renderOnPass:(MTLRenderPassDescriptor*) renderPass
     OnCommandBuffer:(id<MTLCommandBuffer>) buffer
    WithInputTexture:(id<MTLTexture>) input
            WithMesh:(nullable ScreenMesh*) mesh
{
    // 参数不应该是直接传入encoder 因为材质可能使用 并行渲染
    
    // id<MTLParallelRenderCommandEncoder> parallel = [buffer parallelRenderCommandEncoderWithDescriptor:renderPass];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:renderPass];
    
    // 需要在创建另外一个编码器的时候 结束当前编码器的 编程过程
    // signal SIGABRT failed assertion `encoding in progress'
    // id<MTLRenderCommandEncoder> encoder2 = [buffer renderCommandEncoderWithDescriptor:renderPass];
   
    
    encoder.label = @"ScreenRender";
    
    [encoder pushDebugGroup:@"ScreenRenderDbg"];
    
    [encoder setCullMode:MTLCullModeBack];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise]; // 逆时针 是否应该根据模型文件来配置? 比如工具导出三角形卷绕是逆时针
    
    // failed assertion `Framebuffer With Render Pipeline State Validation
    // For color attachment 0, the render pipeline's pixelFormat(MTLPixelFormatRGBA8Unorm_sRGB)
    //  does not match the framebuffer's pixelFormat (MTLPixelFormatBGRA8Unorm_sRGB).
    
    [encoder setRenderPipelineState:_renderPipeLineState]; // ????? 为啥framebuffer有深度附件 但是renderpass为Invalid的话，也会崩溃 ?????
    //[encoder setDepthStencilState:_depthStencilState]; // 主要非nil就是要深度测试
    [encoder setFragmentSamplerState:_samplerState0 atIndex:0];
    
    [encoder setFragmentTexture:input atIndex:0];
    
    [self drawMesh:encoder];
    
    // AAPLMesh 这个是把 顶点属性, 索引buffer, 纹理贴纸, 绘制方式(好像都是使用index)等都封装起来，
    // 然后在设置给encoder或者调用encoder的draw
    
    [encoder popDebugGroup];
    
    // failed assertion `Command encoder released without endEncoding'
    // 如果没有endEncoding MTLRenderCommandEncoder在析构的时候会崩溃
    [encoder endEncoding];
    
    return true ;
}


-(BOOL) renderOnFrameBuffer:(MetalFrameBuffer*) framebuffer
            OnCommandBuffer:(id<MTLCommandBuffer>) buffer
           WithInputTexture:(id<MTLTexture>) input
                   WithMesh:(nullable ScreenMesh*) mesh
{
    [self renderOnPass:framebuffer.renderPassDescriptor OnCommandBuffer:buffer WithInputTexture:input WithMesh:mesh];
    return true ;
}


-(BOOL) drawMesh:(id<MTLRenderCommandEncoder>) encoder
{
    // 材质本身没有提供纹理 由外部提供
//    for (int i = 0 ; i < _mesh.textures.count ; i++)
//    {
//        [encoder setFragmentTexture:_mesh.textures[i] atIndex:i];
//    }
    
    [encoder setVertexBuffer:_mesh.vertexBuffer offset:_mesh.vertexBufferOffset atIndex:_mesh.vertexBufferIndex];
    //[encoder setVertexBuffer:_mesh.indexBuffer  offset:_mesh.indexBufferOffset atIndex:1];

    [encoder drawIndexedPrimitives:_mesh.primitiveType
                        indexCount:_mesh.indexCount
                         indexType:_mesh.indexType
                       indexBuffer:_mesh.indexBuffer
                 indexBufferOffset:_mesh.indexBufferOffset];
    
    return true ;
}

@end
