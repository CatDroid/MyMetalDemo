//
//  MemoryScribble.cpp
//  T1-Triangle
//
//  Created by hehanlong on 2021/11/27.
//

#include "MemoryScribble.hpp"

/*
 
 内存诊断
 Product –> Sheme –> edit scheme –> Run -> Diagnostics
 
 Enable Malloc Scribble 内存涂鸦
 申请内存后在申请的内存上填0xAA，内存释放后在释放的内存上填0x55；再就是说如果内存未被初始化就被访问，或者释放后被访问，就会引发异常，这样就可以使问题尽快暴漏出来
 Scribble其实是malloc库libsystem_malloc.dylib自身提供的调试方案

 Enable Malloc Guard Edges
 申请大片内存的时候在前后page上加保护，详见保护模式。

 Enable Guard Mallocs
 使用libgmalloc捕获常见的内存问题，比如越界、释放之后继续使用。
 由于libgmalloc在真机上不存在，因此这个功能只能在模拟器上使用.

 Enable Zombie Objects
 Zombie的原理是用生成僵尸对象来替换dealloc的实现，当对象引用计数为0的时候，将需要dealloc的对象转化为僵尸对象。
 如果之后再给这个僵尸对象发消息，则抛出异常，并打印出相应的信息，调试者可以很轻松的找到异常发生位置。
 
 HHL: 在app中使用，消耗内存比较大，容易OOM崩溃
 

 Enable Address Sanitizer (Xcode7 +)
 AddressSanitizer的原理是当程序创建变量分配一段内存时，将此内存后面的一段内存也冻结住，标识为中毒内存。
 当程序访问到中毒内存时（越界访问），就会抛出异常，并打印出相应log信息。
 调试者可以根据中断位置和的log信息，识别bug。
 如果变量释放了，变量所占的内存也会标识为中毒内存，这时候访问这段内存同样会抛出异常（访问已经释放的对象）。
 

 OS X 的LibC库高度可配置，malloc( ) 的手册页记录了可以控制内存分配行为的环境变量，如下表
  
    MallocCheckHeapStart
    MallocCheckHeapEach
    MallocCheckHeapSleep/Abort
 
        在MallocCheckHeapStart 次分配后，每隔MallocCheckHeapEach 次分配之后检查堆的一致性。
        如果发现堆不一致的情况，要么进入睡眠（允许调试），要么调用abort( )（通过SIGABRT 崩溃）
  
  
    MallocGuardEdges
    MallocDoNotProtectPrelude
    MallocDoNotProtectPostlude
  
        在分配的大内存块之前（如果没有设置MallocDoNotProtectPrelude）和之后（如果没有设置MallocDoNotProtectPostlude）添加守护页
  
    MallocStackLogging
    MallocStackLoggingNoCompact
    MallocStackLoggingDirectory
 
        将malloc操作时所用的栈跟踪记录到/tmp(或 MallocStackLoggingDirectory 指定的目录)中。
        然后可以调用 leaks( ) 和 malloc_history( ) 之类的程序，后者要求设置MallocStackLoggingNoCompact

    MallocScribble
 
        在分配的内存中填满0xAA，在释放的内存中填满0x55
  
    MallocErrorAbort
    MallocCorruptionAbort
 
        发送任何错误时调用abort( )（即发送 SIGABRT 信号），或只有内存破坏时调用abort( )
 
    MallocLogFile
        设置malloc调试日志文件
 
 
 打开功能后，启动日志会有
 
 malloc: adding guard pages for large allocator blocks
 malloc: enabling scribbling to detect mods to free blocks
 malloc: checks heap after operation #1 and each 1 operations
 malloc: will sleep for 100 seconds on heap corruption
 
 
 */
 
#import "fishhook.h"
//#include <malloc/malloc.h>



//static void* (*orig_malloc)(size_t);
//static void (*orig_free)(void*);
//static void* (*orig_calloc)(size_t, size_t);
//static void* (*orig_realloc)(void *, size_t);
//static void* (*orig_valloc)(size_t);
//static void* (*orig_new)(size_t);
//
//void* new_valloc(size_t size)
//{
//    /*
//        void type has no size, and thus the pointed address can not be added to,
//        although gcc and other compilers will perform byte arithmetic on void* as a non-standard extension,
//        treating it as if it were char *.
//        void类型没有大小 但是对于void* 很多编译器都作为char*
//     */
//    void *ptr = orig_valloc(size);
//    return ptr ;
//}
//
//void* new_malloc(size_t size)
//{
//    void *ptr = orig_malloc(size);
//    memset(ptr, 0x22, size );
//
//    //printf("new_malloc %p %zd %zd\n", ptr, size, malloc_good_size(size));
//
//    // orig_malloc(size + sizeof(size_t)); 不能分配多一个size_t存放大小。因为一进程开始的时候 malloc了部分内存,没有这个header
//
//    return ptr;
//}
//
//void new_free(void* ptr)
//{
//    size_t size = malloc_size(ptr); // 这个大小跟 malloc_good_size一样
//    memset(ptr, 0x33, size);
//
//    //printf("new_free %p %zd\n", ptr, size);
//
//    orig_free(ptr);
//}
//
//void *new_calloc(size_t n,size_t size)
//{
//    printf("new_calloc \n");
//    void *ptr = orig_calloc(n,size);
//    return ptr;
//}
//
//void *new_realloc(void *old_ptr, size_t size)
//{
//    printf("new_realloc \n");
//    void *ptr = orig_realloc(old_ptr, size);
//    return ptr;
//}
//
//
//
//void* operator new(size_t size)
//{
//    //printf("new called %zd \n", size);
//    void *p = (void*) malloc(size);
//    return p;
//}
//
////void operator delete(void *p)
////{
////    // printf("delete called %p \n", p);
////    free(p);
////}
//
////void * operator new[](size_t size)
////{
////    printf("new[] called\n ");
////    void *p = malloc(size);
////    return p;
////}
//
////void operator delete[](void *p)
////{
////    printf("delete[] called\n ");
////    free(p);
////}





MemoryScribble::MemoryScribble()
{
    printf(M_TAG " MemoryScribble construct ");
    
//#if HOOK
//    orig_malloc  = malloc ;
//    orig_valloc  = valloc ;
//    orig_realloc = realloc;
//    orig_calloc  = calloc ;
//    orig_free    = free   ;
//
//
//    struct rebinding func[] =
//    {
//        {"realloc",(void*)new_realloc,(void**)&orig_realloc},
//        {"free",   (void*)new_free,   (void**)&orig_free},
//        {"calloc", (void*)new_calloc, (void**)&orig_calloc},
//        {"malloc", (void*)new_malloc, (void**)&orig_malloc},
//        {"valloc", (void*)new_valloc, (void**)&orig_valloc},
//        //{"operator new", (void*)new_new, (void**)&orig_new }, // 不能重新绑定operator new
//    };
//
//    rebind_symbols(func, sizeof(func)/sizeof(func[0]));
//
//    //
//    // 当new方法分配内存失败之后, 回调new_p  typedef void (*new_handler)();
//    // std::new_handler set_new_handler( std::new_handler new_p )
//    //
//#endif
}

MemoryScribble::~MemoryScribble()
{
    printf(M_TAG " MemoryScribble ~destructor ");
}

void MemoryScribble::Update()
{
    printf("Update -1-\n");
    /*
     explicit vector( size_type count,
                      const T& value = T(),
                      const Allocator& alloc = Allocator());
     
     // c++11 initializer list syntax:
     vector( std::initializer_list<T> init,
             const Allocator& alloc = Allocator() );
     
     使用花括号初始化语法将强烈地偏向于调用带std::initializer_list参数的函数。
     强烈意味着，当使用花括号初始化语法时，编译器只要有任何机会能调用带std::initializer_list参数的构造函数，编译器就会采用这种解释

     空的花括号意味着没有参数，不是一个空的std::initializer_list
     --- Widget w2{};    //也调用默认构造函数
     --- Widget w4({});  //使用空的list调用 std::initializer_list构造函数
     
     Widget w2();    //最令人恼火的解析！“声明”一个名字是w2返回Widget的函数(没有函数体/定义的函数声明)
     
     */
    std::vector<uint8_t>* p = new std::vector<uint8_t>(5000,0x77); // {128,0} 这样是用初始化列表构造函数 只有两个元素
    // 默认vector初始化为0
    // 内部用new char[] 而不是 malloc分配内存
    
    auto* buffer = p->data();
    
    //printf("memory buffer size %zu\n", p->size());

    printf("memory buffer check 1 is = 0x%x,0x%x,0x%x,0x%x %p\n",  buffer[0],  buffer[50],  buffer[100],  buffer[127], buffer);
    
    delete p;
    
    // 默认情况下 这里打印 0x80,0x77,0x77,0x77 / 0x0,0x77,0x77,0x77 比较随意
    // Enable Malloc Scribble 内存涂污 打开后  0x55,0x55,0x55,0x55 固定  但是第一个字节会是0x0 可能已经被重复使用？？
    // Adress Sanitazer打开会会检测到这里“读取”异常
    printf("memory buffer check 2 is = 0x%x,0x%x,0x%x,0x%x\n",  buffer[0],  buffer[50],  buffer[100],  buffer[127] );
    

    // Enable Guard Mallocs 越界、释放之后继续使用检查 检测到堆损坏，空闲列表已损坏
    //
    // malloc: Heap corruption detected, free list is damaged at 0x281388d80
    // *** Incorrect guard value: 268584129170841
    // malloc: *** set a breakpoint in malloc_error_break to debug
    //
    buffer[0] = 0x11; // 如果只读,不会检查到错误; 如果写入,会出现崩溃，但不是在这里崩溃??(延后了??到下一个函数调用)
    // T1-Triangle(390,0x16feb7000) malloc: Incorrect checksum for freed object 0x15a812200: probably modified after being freed.
    // Corrupt value: 0x11
    // T1-Triangle(390,0x16feb7000) malloc: *** set a breakpoint in malloc_error_break to debug
 
    //printf("---1---\n");
    //char* mp = (char*)malloc(128);// new class() 不会没次都调用malloc ？？
    //printf("0x%x 0x%x 0x%x 0x%x\n", mp[50], mp[89], mp[100], mp[127]);
    //free(mp);
    //printf("---2---\n");
    
    //printf("---11---\n");
    //std::vector<uint8_t>* ppp = new std::vector<uint8_t>(128,0x33);
    //delete ppp;
    //printf("---22---\n");
    
    printf("Update -2-\n");
}
