# PicoRV32 那个结点的启动与中断入口，各段测试共用。它从 Flash 的 0x2018_0000 起步，中断入口固定在其后 16 字节；
# 没有标准的 CSR，开关中断、等中断、从中断返回都是它自己的指令（custom-0，funct7 分别是 3、4、2）。
# 进中断时返回地址在 q0、待处理的中断位图在 q1，寄存器要自己存；这里借被打断的那个栈
.option norvc
.section .text.start
.global _start
_start:
    li sp, 0x80100000
    call main
1:  j 1b

.balign 16
irq_entry:
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
    # 待处理的中断位图交给处理函数
    .insn r 0x0b, 0, 0, a0, x1, x0
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
    .insn r 0x0b, 0, 2, x0, x0, x0

# a0 是地址，a1 是空转的圈数，a2 是要写的数：预留、空转（不碰存储）、条件写。写成回 0
.global lr_wait_sc
lr_wait_sc:
    lr.w t0, (a0)
1:  addi a1, a1, -1
    bnez a1, 1b
    sc.w a0, a2, (a0)
    ret

# 放开 1 至 7 号中断：非法指令、总线错，CLINT 的计时器与软件中断、核间中断、信箱来包、串口。屏蔽字里 1 是关
.global arm_irq
.global arm_timer
arm_timer:
arm_irq:
    li t0, ~0xfe
    .insn r 0x0b, 0, 3, t0, t0, x0
    ret

# 等中断
.global wait_irq
wait_irq:
    .insn r 0x0b, 0, 4, a0, x0, x0
    ret
