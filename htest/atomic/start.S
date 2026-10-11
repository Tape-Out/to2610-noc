# 四个核从同一处起步，程序就地在 Flash 里跑；栈各放在自己那段 SDRAM 的第一兆，地址相同、落点不同
.section .text.start
.global _start
_start:
    li sp, 0x80100000
    call main
1:  j 1b

# a0 是地址，a1 是空转的圈数，a2 是要写的数：预留、空转（不碰存储）、条件写。写成回 0
.global lr_wait_sc
lr_wait_sc:
    lr.w t0, (a0)
1:  addi a1, a1, -1
    bnez a1, 1b
    sc.w a0, a2, (a0)
    ret

# 开机器态计时器中断，入口指到下面的 trap
.global arm_timer
arm_timer:
    la t0, trap
    csrw mtvec, t0
    li t0, 0x80
    csrs mie, t0
    csrsi mstatus, 8
    ret

.balign 4
trap:
    addi sp, sp, -64
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw a0, 16(sp)
    sw a1, 20(sp)
    sw a2, 24(sp)
    sw a3, 28(sp)
    sw a4, 32(sp)
    sw a5, 36(sp)
    sw a6, 40(sp)
    sw a7, 44(sp)
    sw t3, 48(sp)
    sw t4, 52(sp)
    sw t5, 56(sp)
    sw t6, 60(sp)
    call on_irq
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw a0, 16(sp)
    lw a1, 20(sp)
    lw a2, 24(sp)
    lw a3, 28(sp)
    lw a4, 32(sp)
    lw a5, 36(sp)
    lw a6, 40(sp)
    lw a7, 44(sp)
    lw t3, 48(sp)
    lw t4, 52(sp)
    lw t5, 56(sp)
    lw t6, 60(sp)
    addi sp, sp, 64
    mret
