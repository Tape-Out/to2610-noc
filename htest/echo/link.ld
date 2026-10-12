OUTPUT_ARCH("riscv")
ENTRY(_start)
/* 链接时只按最小的那种私有段（4 MiB）把关 */
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 4M }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : ALIGN(4) { *(.bss*) *(.sbss*) *(COMMON) } > ram
  /* 栈紧跟在各段后面，_stack 往上到段顶是空着的 */
  . = ALIGN(16);
  . += 4096;
  _stack = .;
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
