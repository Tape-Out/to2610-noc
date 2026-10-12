# riscv-tests 用的跳板。KianV 与 Hazard3 的结点从 0x2010_0000 起步，用这一份（按公共的 rv32ima 编）：
# 测的是 0 号结点时直接跳进 SDRAM；测别的结点时，0 号结点把它放开后原地等着，被放开的那个读控制页知道自己不是 0 号，
# 跳进它自己那段 SDRAM。PicoRV32 从 0x2018_0000 起步，带 -DPICO 编的那一份只有一跳
.section .text
.global _start
_start:
#ifndef PICO
#if CORE
    li t1, 0x40040000
    lw t0, 4(t1)
    bnez t0, 1f
    li t2, 1 | (1 << CORE)
    sw t2, 8(t1)
0:  j 0b
1:
#endif
#endif
    lui t0, 0x80000
    jr t0
