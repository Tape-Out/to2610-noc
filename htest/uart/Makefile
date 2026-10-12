O ?= build
CROSS ?= riscv64-unknown-elf-
FLAGS = -mabi=ilp32 -Os -ffreestanding -nostdlib

# 同一份 C 编两遍：KianV 与 Hazard3 取公共的 rv32ima；PicoRV32 另编
$(O)/uart.bin: uart.c ../hello/start.S ../box/link.ld ../pico/start.S ../pico/link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr $(FLAGS) -Wl,-T,../box/link.ld -o $(O)/uart.elf ../hello/start.S uart.c
	$(CROSS)objcopy -O binary $(O)/uart.elf $(O)/main.bin
	$(CROSS)gcc -march=rv32imac $(FLAGS) -Wl,-T,../pico/link.ld -o $(O)/pico.elf ../pico/start.S uart.c
	$(CROSS)objcopy -O binary $(O)/pico.elf $(O)/pico.bin
	python3 ../pico/join.py $(O)/main.bin $(O)/pico.bin $@
