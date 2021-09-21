//
//  QuadMesh.h
//  T0-OffScreenRendering
//
//  Created by hehanlong on 2021/6/26.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface QuadMesh : NSObject
 
@property (strong,readonly,nonatomic) id<MTLBuffer> vertexBuffer;
@property (readonly,nonatomic) int vertexCount ;
@property (readonly,nonatomic) MTLPrimitiveType primitiveType ;

-(instancetype) initWithDevice:(id<MTLDevice>) device;



@end

NS_ASSUME_NONNULL_END
