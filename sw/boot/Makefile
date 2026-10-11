O ?= build
CROSS ?= riscv64-unknown-elf-

# -mno-relax：不设 gp，链接器就别把取地址松弛成相对 gp 的
$(O)/boot.bin: start.S boot.c link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32imac_zicsr -mabi=ilp32 -Os -ffreestanding -nostdlib -mno-relax -Wl,-T,link.ld -o $(O)/boot.elf start.S boot.c
	$(CROSS)objcopy -O binary -j .text $(O)/boot.elf $@
