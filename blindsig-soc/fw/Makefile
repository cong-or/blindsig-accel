# fw/Makefile — Build RISC-V firmware for PicoRV32 SoC

CROSS   = /home/soze/xpack-riscv-none-elf-gcc-14.2.0-3/bin/riscv-none-elf-
CC      = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
SIZE    = $(CROSS)size

CFLAGS  = -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -Os -Wall
LDFLAGS = -T link.ld -nostdlib -march=rv32i -mabi=ilp32

# 4096 words = 16 KB RAM
NUM_WORDS = 4096

all: firmware.hex

firmware.elf: start.S test_accel.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S test_accel.c
	$(SIZE) $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.bin makehex.py
	python3 makehex.py $< $(NUM_WORDS) > $@

clean:
	rm -f firmware.elf firmware.bin firmware.hex

.PHONY: all clean
