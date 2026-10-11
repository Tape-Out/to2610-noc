/* 裸机工具链不带 C 库的头，FreeRTOS 的源码却照例包含它们；它用得到的只有 size_t */
#ifndef RTOS_STDLIB_H
#define RTOS_STDLIB_H
#include <stddef.h>
#endif
