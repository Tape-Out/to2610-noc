O ?= build
CROSS ?= riscv64-unknown-elf-
FLAGS = -mabi=ilp32 -Os -ffreestanding -nostdlib

all: $(O)/echo.bin $(O)/master.bin $(O)/pico.bin

# 载荷，由引导程序搬进各结点私有的 SDRAM：echo 给 Hazard3，master 给 0 号结点
$(O)/%.bin: %.c start.S link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr $(FLAGS) -mno-relax -Wl,-T,link.ld -o $(O)/$*.elf start.S $<
	$(CROSS)objcopy -O binary $(O)/$*.elf $@

# PicoRV32 的回声就地在 Flash 里跑
$(O)/pico.bin: echo.c ../pico/start.S ../pico/link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32imac $(FLAGS) -Wl,-T,../pico/link.ld -o $(O)/pico.elf ../pico/start.S echo.c
	$(CROSS)objcopy -O binary $(O)/pico.elf $@
