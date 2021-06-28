//
//  CameraRender.m
//  T0-MetalCameraRecorder
//
//  Created by hehanlong on 2021/6/28.
//

#import "CameraRender.h"
#import "CameraShaderType.h"

@implementation CameraRender
{
    id<MTLRenderPipelineState> _renderPipelineState ;
    // id<MTLDepthStencilState> _depthStencilState ;
    id<MTLSamplerState> _samplerState ;
    id<MTLBuffer> _vertexBuffer ;
}

-(nonnull instancetype) initWithDevice: (nonnull id <MTLDevice>) device
{
    self = [super init];
    if (self)
    {
        [self _setupMetal:device];
    }
    else
    {
        NSLog(@"CameraRender init fail");
    }
    return self ;
}


-(void) _setupMetal:(id<MTLDevice>) device
{
    
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"CameraVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"CameraFragmentShader"];
    
    
    MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    renderPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    renderPipelineDesc.colorAttachments[0].blendingEnabled = NO ; // 不用混合
    
    renderPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatInvalid;
    renderPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
    
    renderPipelineDesc.vertexFunction   = vertexFunction;
    renderPipelineDesc.fragmentFunction = fragmentFunction;
    
    renderPipelineDesc.sampleCount = 1 ;
    
    
    NSError* error ;
    _renderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
    
    NSAssert(_renderPipelineState != nil, @"newRenderPipelineStateWithDescriptor fail %@", error);
    
    
    MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
    samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.mipFilter = MTLSamplerMipFilterNotMipmapped ; // 只会重mipmap level 0 才样
    samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    
    _samplerState = [device newSamplerStateWithDescriptor:samplerDesc];
    
    
    static CameraVertex buffer[] = {
        { { 1,-1}, {1,1} },
        { {-1, 1}, {0,0} },
        { {-1,-1}, {0,1} },
        { {-1, 1}, {0,0} },
        { { 1,-1}, {1,1} },
        { { 1, 1}, {1,0} }
    };
    /*
             |
       -1, 1 |  1, 1
     -----------------
       -1,-1 |  1,-1
             |
     
     -------------
     |  0,0    1,0
     |
     |  0,1    1,1
     |
     
     */
    
    _vertexBuffer = [device newBufferWithBytes:buffer length:sizeof(buffer) options:MTLResourceStorageModeShared];
    
}


-(void) encodeToCommandBuffer: (nonnull id <MTLCommandBuffer>) commandBuffer
                sourceTexture: (nonnull id <MTLTexture>) sourceTexture
           destinationTexture: (nonnull id <MTLTexture>) destinationTexture
{
   
    MTLRenderPassDescriptor* renderPass = [[MTLRenderPassDescriptor alloc] init];
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 1.0, 1.0, 1.0);
    renderPass.colorAttachments[0].loadAction = MTLLoadActionLoad ;
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore ;
    renderPass.colorAttachments[0].texture = destinationTexture; // 目前认为这个格式都是 BGRA888
    
    
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    encoder.label = @"CameraRender";
    
    // 设置 argument table
    // [encoder setVertexTexture:sourceTexture atIndex:0]; // 排查错误: 可在GPU帧捕捉中, 查看Bounds资源中, Vertex和Framgent分别显示绑定的资源是否有错误
    [encoder setFragmentTexture:sourceTexture atIndex:0];
    
    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [encoder setFragmentSamplerState:_samplerState atIndex:0]; // 还可以设置Vertex的
    
    [encoder setRenderPipelineState:_renderPipelineState];
    // [encoder setDepthStencilState:(nullable id<MTLDepthStencilState>)]
    
    [encoder setCullMode:MTLCullModeBack]; // 默认是不做面剔除。MTLCullModeNone.
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    
    // 调整视口
    // destinationTexture 是输出
    // sourceTexture 是输入摄像头 
    
    double dstWidth = destinationTexture.width ;
    double dstHeight = destinationTexture.height;
    
    double srcWidth  = sourceTexture.width;
    double srcHeight = sourceTexture.height;
    
    // src(1080.000000,1920.000000) -> dst(828.000000,1792.000000)
    // NSLog(@"src(%f,%f) -> dst(%f,%f)", srcWidth, srcHeight, dstWidth, dstHeight);
    
    
    double dstRatio = dstWidth / dstHeight;
    double srcRatio = srcWidth / srcHeight;
    
    double vWidth = 0;
    double vHeight = 0;
    
    if ( dstRatio > srcRatio )
    {
        // 目标更加宽
        vHeight = dstWidth;
        vWidth = srcRatio * vHeight;
    }
    else
    {
        vWidth = dstWidth;
        vHeight =  vWidth / srcRatio;
    }
    
    double originY = (dstHeight - vHeight) / 2 ;
    double originX = (dstWidth - vWidth) / 2 ;
    
    // MTLViewport是个结构体
    [encoder setViewport: (MTLViewport){originX, originY, vWidth, vHeight, 0.0, 1.0 }];
    
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    
    
    [encoder endEncoding];
    
    
}


@end
