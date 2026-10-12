O ?= build
CROSS ?= riscv64-unknown-elf-
FLAGS = -mabi=ilp32 -Os -ffreestanding -nostdlib

# 同一份 C 编两遍：KianV 与 Hazard3 取公共的 rv32ima；PicoRV32 的中断是它自己的一套，另编（-DPICO）
$(O)/irq.bin: start.S irq.c ../box/link.ld ../pico/start.S ../pico/link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr $(FLAGS) -Wl,-T,../box/link.ld -o $(O)/irq.elf start.S irq.c
	$(CROSS)objcopy -O binary $(O)/irq.elf $(O)/main.bin
	$(CROSS)gcc -march=rv32imac -DPICO $(FLAGS) -Wl,-T,../pico/link.ld -o $(O)/pico.elf ../pico/start.S irq.c
	$(CROSS)objcopy -O binary $(O)/pico.elf $(O)/pico.bin
	python3 ../pico/join.py $(O)/main.bin $(O)/pico.bin $@
