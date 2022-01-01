//
//  MetalAdder.h
//  BasicMetalCompute
//
//  Created by hehanlong on 2022/1/1.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MetalAdder : NSObject

-(instancetype) init;
-(void) prepareData;
-(void) doComputeCommand;

@end

NS_ASSUME_NONNULL_END
