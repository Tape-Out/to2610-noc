# 引导程序就地在 Flash 里跑，KianV 与 Hazard3 的结点同一份。内存大小寄存器读到的是这个结点私有段的大小：
# 段顶 4 KiB 留给搬进内存的拷贝例程，栈放在它下面。程序里没有放在内存里的变量
.section .text.start
.global _start
_start:
    li t0, 0x10000018
    lw t0, 0(t0)
    li sp, 0x80000000
    add sp, sp, t0
    li t0, 0x1000
    sub sp, sp, t0
    call main
1:  j 1b
