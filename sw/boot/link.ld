OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  flash (rx) : ORIGIN = 0x20100000, LENGTH = 64K
}
SECTIONS {
  .text : {
    *(.text.start) *(.text*) *(.rodata*) *(.srodata*)
    . = ALIGN(4);
    __reloc_start = .;
    *(.reloc)
    . = ALIGN(4);
    __reloc_end = .;
  } > flash
  /* 载荷从段底往上放，那时引导程序还在跑：它在内存里只用段顶的 8 KiB（栈与拷贝例程），不放变量 */
  .bss (NOLOAD) : { *(.data*) *(.sdata*) *(.bss*) *(.sbss*) *(COMMON) }
  ASSERT(SIZEOF(.bss) == 0, "the boot loader must not have variables in memory")
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
