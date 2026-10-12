O ?= build
CROSS ?= riscv64-unknown-elf-
FLAGS = -mabi=ilp32 -Os -ffreestanding -nostdlib

# 同一份 C 编两遍：KianV 与 Hazard3 取公共的 rv32ima；PicoRV32 是 rv32imc，A 扩展由它的协处理器补上
$(O)/atomic.bin: start.S atomic.c link.ld ../pico/start.S ../pico/link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr $(FLAGS) -Wl,-T,link.ld -o $(O)/atomic.elf start.S atomic.c
	$(CROSS)objcopy -O binary $(O)/atomic.elf $(O)/main.bin
	$(CROSS)gcc -march=rv32imac $(FLAGS) -Wl,-T,../pico/link.ld -o $(O)/pico.elf ../pico/start.S atomic.c
	$(CROSS)objcopy -O binary $(O)/pico.elf $(O)/pico.bin
	python3 ../pico/join.py $(O)/main.bin $(O)/pico.bin $@
