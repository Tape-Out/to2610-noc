# 由引导程序搬进 SDRAM 后从 0x8000_0000 起：栈在各段后面（_stack），清 .bss，装上 FreeRTOS 的陷入入口，进 main
.section .text.start
.global _start
_start:
    la sp, _stack
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  la t0, freertos_risc_v_trap_handler
    csrw mtvec, t0
    call main
3:  j 3b
