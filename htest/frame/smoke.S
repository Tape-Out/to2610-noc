# mpc-frame 两个测试台用的程序：读控制页的标识寄存器，对了从串口发 N（0x4e），不对发 X（0x58）。
# 只有 0 号核在跑，另外三个核不放开
# expect: 4e
.section .text
.global _start
_start:
    li t0, 0x1000000c
    li t1, 16
    sw t1, 0(t0)
    li t0, 0x40040000
    lw t2, 0(t0)
    li t3, 0x4e4f4334
    li t1, 0x4e
    beq t2, t3, 1f
    li t1, 0x58
1:  li t0, 0x10000000
    sw t1, 0(t0)
2:  j 2b
