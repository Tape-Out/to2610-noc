OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  flash (rx) : ORIGIN = 0x20100000, LENGTH = 64K
  ram (rw) : ORIGIN = 0x805fe000, LENGTH = 4K
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
  .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > ram
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
