O ?= build
CROSS ?= riscv64-unknown-elf-

$(O)/atomic.bin: start.S atomic.c link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32imac_zicsr -mabi=ilp32 -Os -ffreestanding -nostdlib -Wl,-T,link.ld -o $(O)/atomic.elf start.S atomic.c
	$(CROSS)objcopy -O binary $(O)/atomic.elf $@
