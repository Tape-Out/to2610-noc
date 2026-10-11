/* FreeRTOS 用到的两样，实现在 main.c */
#ifndef RTOS_STRING_H
#define RTOS_STRING_H
#include <stddef.h>
void *memset(void *d, int c, size_t n);
void *memcpy(void *d, const void *s, size_t n);
#endif
