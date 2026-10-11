# 引导程序就地在 Flash 里跑，四个核同一份。栈放在私有那段 SDRAM 顶上往下 8 KiB 处，
# 顶上那 4 KiB 留给搬进内存的拷贝例程。boot.c 里那个记核号的变量也得在内存里：放在栈的上面一格
.section .text.start
.global _start
_start:
    li sp, 0x805fe000
    call main
1:  j 1b
