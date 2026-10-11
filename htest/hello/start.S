# 程序就地在 Flash 里跑，没有 .data 与 .bss；栈放在私有那段 SDRAM 的第一兆
.section .text.start
.global _start
_start:
    li sp, 0x80100000
    call main
1:  j 1b

# a0 是地址：读得到回 0，访问出错回 1
.global probe
probe:
    la t0, 1f
    csrw mtvec, t0
    li t1, 0
    lw t2, 0(a0)
    j 2f
.balign 4
1:  li t1, 1
    la t0, 2f
    csrw mepc, t0
    mret
2:  mv a0, t1
    ret
