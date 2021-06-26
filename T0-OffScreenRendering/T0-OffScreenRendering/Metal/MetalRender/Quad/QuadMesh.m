//
//  QuadMesh.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/26.
//

#import "QuadMesh.h"
#import "QuadShaderType.h"

@implementation QuadMesh


-(instancetype) initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    if (self)
    {
        static const QuadVertexColor myVertex[] =
        {
            { {  1,  -1 },  { 1.f, 0.f, 0.f } },
            { { -1,  -1 },  { 0.f, 1.f, 0.f } },
            { { -1,   1 },  { 0.f, 0.f, 1.f } },

            { {  1,  -1 },  { 1.f, 0.f, 0.f } },
            { { -1,   1 },  { 0.f, 0.f, 1.f } },
            { {  1,   1 },  { 1.f, 0.f, 1.f } },
        };
        
        _vertexBuffer = [device newBufferWithBytes:myVertex length:sizeof(myVertex) options:MTLResourceStorageModeShared];
        
        _primitiveType = MTLPrimitiveTypeTriangle;
        
        _vertexCount = sizeof(myVertex) / sizeof(myVertex[0]) ;
    }
    return self ;
}

@end
