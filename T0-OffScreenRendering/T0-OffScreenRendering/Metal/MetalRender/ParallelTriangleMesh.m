//
//  TriangleMesh.m
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import "ParallelTriangleMesh.h"
#import "ShaderType.h"

@implementation ParallelTriangleMesh
{
 
}

-(instancetype) initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    
    if (self)
    {
        static const Vertex vert[] = {
            {  {-1.0, 1.0}  },
            {  { 0.0, 0.0}  },
            {  {-1.0, 0.0}  }
        };
        _vertexBuffer = [device newBufferWithBytes:vert length:sizeof(vert) options:MTLResourceStorageModeShared];
        _vertexBufferOffset = 0;
        _vertexBufferIndex = 0;
        
        static const Vertex vert2[] = {
            {  {1.0, 0.0}  },
            {  {0.0, -1.0}  },
            {  {1.0, -1.0 } }
        };
        //_vertexbuffer2 = [device newBufferWithBytes:vert2 length:sizeof(vert) options:MTLResourceStorageModeShared]; // 分配MTLBuffer时候就传入数据
        _vertexBuffer2 = [device newBufferWithLength:sizeof(vert2) options:MTLResourceStorageModeShared]; // 先分配MTLBuffer 再传入数据
        memcpy(_vertexBuffer2.contents, vert2, sizeof(vert2));
        _vertexBuffer2Offset = 0;
        _vertexBuffer2Index = 1 ;
     
    }
    else
    {
        NSLog(@"ScreenMesh super init fail");
    }
    
    return self ;
}


@end
