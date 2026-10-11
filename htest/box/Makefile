O ?= build
CROSS ?= riscv64-unknown-elf-

$(O)/box.bin: start.S box.c link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32imac_zicsr -mabi=ilp32 -Os -ffreestanding -nostdlib -Wl,-T,link.ld -o $(O)/box.elf start.S box.c
	$(CROSS)objcopy -O binary $(O)/box.elf $@
