//
//  main.m
//  BasicMetalCompute
//
//  Created by hehanlong on 2022/1/1.
//

#import <Foundation/Foundation.h>

#include "MetalAdder.h"


int main(int argc, const char * argv[]) {
    @autoreleasepool {
      
        MetalAdder* adder = [[MetalAdder alloc] init];
        
        [adder prepareData];
        
        [adder doComputeCommand];
        
    }
    return 0;
}
