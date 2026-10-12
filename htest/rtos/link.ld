OUTPUT_ARCH("riscv")
ENTRY(_start)
/* 链接时只按最小的那种私有段（4 MiB）把关；真有多大，程序起来后从内存大小寄存器读 */
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 4M }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : ALIGN(4) { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ram
  /* 启动用的栈紧跟在各段后面。_stack 是段与堆的分界：往上到这个结点私有段的段顶都是堆，镜像多大都一样 */
  . = ALIGN(16);
  . += 4096;
  _stack = .;
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
