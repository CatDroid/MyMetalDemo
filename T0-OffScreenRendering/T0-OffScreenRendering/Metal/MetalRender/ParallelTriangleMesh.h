//
//  TriangleMesh.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/25.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface ParallelTriangleMesh : NSObject

-(instancetype) init NS_UNAVAILABLE;
-(instancetype) initWithDevice:(id<MTLDevice>) device NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly, nonnull) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly) NSUInteger vertexBufferIndex;
@property (nonatomic, readonly) NSUInteger vertexBufferOffset;

@property (nonatomic, readonly, nonnull) id<MTLBuffer> vertexBuffer2;
@property (nonatomic, readonly) NSUInteger vertexBuffer2Index;
@property (nonatomic, readonly) NSUInteger vertexBuffer2Offset;

//@property (nonatomic, readonly) MTLPrimitiveType primitiveType;
//@property (nonatomic, readonly) NSUInteger indexCount;
//@property (nonatomic, readonly) MTLIndexType indexType;
//@property (nonatomic, readonly, nonnull) id<MTLBuffer> indexBuffer;
//@property (nonatomic, readonly) NSUInteger indexBufferOffset;
//@property (nonatomic, readonly, nullable) NSArray<id<MTLTexture>> *textures;


@end

NS_ASSUME_NONNULL_END
