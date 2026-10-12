OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { flash (rx) : ORIGIN = 0x20180000, LENGTH = 512K }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > flash
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
