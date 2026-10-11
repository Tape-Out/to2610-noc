OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 1M }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : ALIGN(4) { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ram
  . = ALIGN(16);
  . += 4096;
  __stack_top = .;
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
