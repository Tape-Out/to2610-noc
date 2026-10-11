/* FreeRTOS 在 to2610-noc 上的配置：四个核各一份，只在机器态跑，节拍用各核自己的 CLINT，任务切换走 ecall。 */
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* mtime 每微秒走一格，与主频无关 */
#define configCPU_CLOCK_HZ 1000000
#define configTICK_RATE_HZ 1000
#define configMTIME_BASE_ADDRESS 0x0200bff8
#define configMTIMECMP_BASE_ADDRESS 0x02004000
#define configISR_STACK_SIZE_WORDS 256

/* 「优化的任务选择」要 libgcc 的 __clzsi2，这里不带 libgcc；用通用的那一种 */
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configUSE_PREEMPTION 1
#define configUSE_TIME_SLICING 1
#define configUSE_IDLE_HOOK 0
#define configUSE_TICK_HOOK 0
#define configMAX_PRIORITIES 4
#define configMINIMAL_STACK_SIZE 256
#define configTOTAL_HEAP_SIZE (32 * 1024)
#define configMAX_TASK_NAME_LEN 8
#define configTICK_TYPE_WIDTH_IN_BITS TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD 1
#define configUSE_MUTEXES 0
#define configUSE_TIMERS 0
#define configUSE_CO_ROUTINES 0
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configSUPPORT_STATIC_ALLOCATION 0
#define configCHECK_FOR_STACK_OVERFLOW 0
#define configUSE_MALLOC_FAILED_HOOK 0

#define INCLUDE_vTaskDelay 1
#define INCLUDE_vTaskDelete 0
#define INCLUDE_vTaskSuspend 0

void rtos_assert(const char *file, int line);
#define configASSERT(x) do { if (!(x)) rtos_assert(__FILE__, __LINE__); } while (0)

#endif
