//
//  MetalViewDelegateRender.m
//  T0-MyMetalViewSimple
//
//  Created by hehanlong on 2021/9/24.
//

#import "MetalViewDelegateRender.h"
#import "ScreenShaderType.h"

@interface MetalViewDelegateRender ()

@property (nonatomic, readonly, nonnull) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly) NSUInteger vertexBufferIndex;
@property (nonatomic, readonly) NSUInteger vertexBufferOffset;

@property (nonatomic, readonly) NSUInteger indexCount;
@property (nonatomic, readonly) MTLIndexType indexType;
@property (nonatomic, readonly, nonnull) id<MTLBuffer> indexBuffer;
@property (nonatomic, readonly) NSUInteger indexBufferOffset;

@property (nonatomic, readonly) MTLPrimitiveType primitiveType;


@end

@implementation MetalViewDelegateRender
{
	bool 				 isSetup;
	id<MTLDevice> 		 _gpu ;
	id <MTLCommandQueue> _commandQueue ;
	
	
	id<MTLRenderPipelineState>  _renderPipeLineState ;
 	id<MTLDepthStencilState>    _depthStencilState ;
 	id<MTLSamplerState>         _samplerState0 ;
	
	
	id<MTLTexture> 				_testTex ;
	
}


-(instancetype) initWithDevice:(id<MTLDevice>) gpu
{
	self = [super init];
	_gpu = gpu ;
	return self ;
}

#pragma mark Delegate protocol接口

-(void) OnDrawableSizeChange:(CGSize)size WithView:(MyMetalView*) view
{
	
	
}

-(void) OnDrawFrame:(CAMetalLayer*) layer WithView:(MyMetalView*) view
{
	if (!isSetup)
	{
		isSetup = true ;
		[self _setup];
	}
	[self _draw:view];
}

-(void) setTestTexture:(id<MTLTexture>) tex
{
	_testTex = tex ;
}



#pragma mark 内部函数

-(void) _setup
{
	//------------ mesh
	const ScreenVertex vertices[] =
	{
		{ .position = { -1.0, -1.0, 0, 1 }, .uv = { 0.0, 1.0 } },
		{ .position = { -1.0,  1.0, 0, 1 }, .uv = { 0.0, 0.0 } },
		{ .position = {  1.0, -1.0, 0, 1 }, .uv = { 1.0, 1.0 } },
		{ .position = {  1.0,  1.0, 0, 1 }, .uv = { 1.0, 0.0 } }
	};
	
	_vertexBuffer = [_gpu newBufferWithBytes:vertices length:sizeof(vertices) options:MTLResourceStorageModeShared]; //  顶点buffer cpu端不修改
	_vertexBufferIndex = 0 ;
	_vertexBufferOffset = 0 ;
	
	
	static int32_t indices[] =
	{
		0, 2, 1, // 顶点id 0 1 2 3 4 5
		1, 2, 3
	};
	
	_indexBuffer = [_gpu newBufferWithBytes:indices length:sizeof(indices) options:MTLResourceStorageModeShared];
	
	_indexCount = sizeof(indices) / sizeof(indices[0]) ;
	_indexBufferOffset = 0 ;
	_indexType =  MTLIndexTypeUInt32 ;
	
	_primitiveType = MTLPrimitiveTypeTriangle ;
	
	
	//------------
	id<MTLLibrary> library = [_gpu newDefaultLibrary];
	id<MTLFunction> vertexFunction =  [library newFunctionWithName:@"ScreenVertexShader"];
	id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"ScreenFragmentShader"];
	
	
	MTLRenderPipelineDescriptor* renderPipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
	renderPipelineDesc.vertexFunction   = vertexFunction ;
	renderPipelineDesc.fragmentFunction = fragmentFunction ; // 这个材质的shader
	renderPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;// 这个材质需要renderpass的color tex的格式
	renderPipelineDesc.colorAttachments[0].blendingEnabled = YES; //启用混合 默认是不混合
	renderPipelineDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
	renderPipelineDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
	renderPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	renderPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
	renderPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	renderPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	
	renderPipelineDesc.depthAttachmentPixelFormat   = MTLPixelFormatInvalid; // renderpass可以没有深度模板纹理
	renderPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
	
	
	MTLPipelineBufferDescriptorArray* vertexbufferArgumentTable = renderPipelineDesc.vertexBuffers;   // 顶点和片元shader都各自有 buffer argument table
	MTLPipelineBufferDescriptor * buffer0Descriptor = vertexbufferArgumentTable[0]; buffer0Descriptor.mutability = MTLMutabilityImmutable ;
	MTLPipelineBufferDescriptor * buffer1Descriptor = vertexbufferArgumentTable[1]; buffer1Descriptor.mutability = MTLMutabilityImmutable ;
	
	// MTLPipelineBufferDescriptorArray* fragbufferArgumentTable = renderPipelineDesc.fragmentBuffers;

	NSError* error ;
	_renderPipeLineState = [_gpu newRenderPipelineStateWithDescriptor:renderPipelineDesc error:&error];
	
	
	//------------
	MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
	samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
	samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
	samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
	samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
	samplerDesc.mipFilter = MTLSamplerMipFilterNotMipmapped; // 不使用mipmap  mipFilter选项用来混合两个mipmap级别的像素
	_samplerState0 = [_gpu newSamplerStateWithDescriptor:samplerDesc];
	
	//-------------
	
	_commandQueue = [_gpu newCommandQueue];
	
	
}

-(void) _draw:(MyMetalView*)view
{
	 
	
	id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
	commandBuffer.label = @"OnDrawFrame";
	
	//---------------------------------------
	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
	encoder.label = @"ScreenRender";
	
	[encoder pushDebugGroup:@"ScreenRenderDbg"];
	[encoder setCullMode:MTLCullModeBack];
	[encoder setFrontFacingWinding:MTLWindingCounterClockwise]; // CCW为正 这个是OpenGL的方式
	
	[encoder setRenderPipelineState:_renderPipeLineState];
	//[encoder setDepthStoreAction:(MTLStoreAction)]
	[encoder setFragmentSamplerState:_samplerState0 atIndex:0];
	
	if (_testTex != nil)
	{
		[encoder setFragmentTexture:_testTex atIndex:0];
	}
	
	[encoder setVertexBuffer:_vertexBuffer 	offset:_vertexBufferOffset 		atIndex:_vertexBufferIndex]; // 这样只有一个buffer argument table ??
	//[encoder setVertexBuffer:_indexBuffer	offset:_mesh.indexBufferOffset 	atIndex:1]; // index buffer在drawIndexedPrimitives传入

	[encoder drawIndexedPrimitives:_primitiveType
						indexCount:_indexCount
						 indexType:_indexType 			// index buffer的数据类型  MTLIndexTypeUInt32
					   indexBuffer:_indexBuffer 		// index buffer 指针
				 indexBufferOffset:_indexBufferOffset	// index buffer 偏移
	 ];
	
	
	[encoder popDebugGroup];
	
	[encoder endEncoding];
	
	//---------------------------------------
	[commandBuffer presentDrawable:view.currentDrawable];
	[commandBuffer commit];
	
}



@end
