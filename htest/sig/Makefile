O ?= build
CROSS ?= riscv64-unknown-elf-
FLAGS = -mabi=ilp32 -Os -ffreestanding -nostdlib

$(O)/sig.bin: main.c pico.c ../hello/start.S ../box/link.ld ../pico/start.S ../pico/link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr $(FLAGS) -Wl,-T,../box/link.ld -o $(O)/sig.elf ../hello/start.S main.c
	$(CROSS)objcopy -O binary $(O)/sig.elf $(O)/main.bin
	$(CROSS)gcc -march=rv32imac $(FLAGS) -Wl,-T,../pico/link.ld -o $(O)/pico.elf ../pico/start.S pico.c
	$(CROSS)objcopy -O binary $(O)/pico.elf $(O)/pico.bin
	python3 ../pico/join.py $(O)/main.bin $(O)/pico.bin $@
