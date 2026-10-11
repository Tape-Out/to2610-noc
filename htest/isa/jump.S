# riscv-tests 用的跳板，放在复位向量上。测的是 0 号核时直接跳进 SDRAM；
# 测别的核时，0 号核把那个核放开后原地等着，那个核从同一处起步、跳进它自己那段 SDRAM
.section .text
.global _start
_start:
#if CORE
    csrr t0, mhartid
    bnez t0, 1f
    li t1, 0x40040008
    li t2, 1 | (1 << CORE)
    sw t2, 0(t1)
0:  j 0b
1:
#endif
    lui t0, 0x80000
    jr t0
