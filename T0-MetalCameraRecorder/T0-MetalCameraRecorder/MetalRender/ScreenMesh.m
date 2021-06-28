//
//  ScreenMesh.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/24.
//

#import "ScreenMesh.h"
#import "ScreenShaderType.h"

@implementation ScreenMesh


-(instancetype) initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    
    if (self)
    {
        static const ScreenVertex vertices[] =
        {
            { .position = { -1.0, -1.0, 0, 1 }, .uv = { 0.0, 1.0 } },
            { .position = { -1.0,  1.0, 0, 1 }, .uv = { 0.0, 0.0 } },
            { .position = {  1.0, -1.0, 0, 1 }, .uv = { 1.0, 1.0 } },
            { .position = {  1.0,  1.0, 0, 1 }, .uv = { 1.0, 0.0 } }
        };
        //  1 3
        //  0 2
        
        // 如果是 MTLResourceStorageModePrivate 那么不能从Cpu给数据??  如下崩溃
        // error 'Buffer Validation
        // storageModePrivate incompatible with ...WithBytes variant of newBuffer
        _vertexBuffer = [device newBufferWithBytes:vertices length:sizeof(vertices) options:MTLResourceStorageModeShared]; //  顶点buffer cpu端不修改
        _vertexBufferIndex = 0 ;
        _vertexBufferOffset = 0 ;
        
        static int32_t indices[] =
        {
            0, 2, 1, // 顶点id 0 1 2 3 4 5 
            1, 2, 3
        };
        
        
        _indexBuffer = [device newBufferWithBytes:indices length:sizeof(indices) options:MTLResourceStorageModeShared];
        _indexCount = sizeof(indices) / sizeof(indices[0]) ;
        _indexBufferOffset = 0 ;
        _indexType =  MTLIndexTypeUInt32 ;
        
        _primitiveType = MTLPrimitiveTypeTriangle ;
        
        
        _textures = nil ;
    }
    else
    {
        NSLog(@"ScreenMesh super init fail");
    }
    
    return self ;
}

@end
