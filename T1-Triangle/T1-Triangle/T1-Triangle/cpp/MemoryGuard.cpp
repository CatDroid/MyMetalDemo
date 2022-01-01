//
//  MemoryGuard.cpp
//  T1-Triangle
//
//  Created by hehanlong on 2021/11/28.
//

#include "MemoryGuard.hpp"
#include <vector>

MemoryGuard::MemoryGuard()
{
    
}

MemoryGuard::~MemoryGuard()
{
    
}

void MemoryGuard::Update()
{
//    printf("MemoryGuard Update ---- 1\n");
//    
//    auto* p = new std::vector<uint8_t>(100, 2); // 这个也会调用 operator new
//    auto* buffer = p->data();
//    buffer[55] = 0x44;
//    delete p;
//
//    printf("MemoryGuard Update ---- 2 : 0x%x\n", buffer[55] );
}
