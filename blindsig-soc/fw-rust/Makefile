# fw-rust/Makefile — Build Rust firmware for PicoRV32 SoC

CROSS  ?= riscv-none-elf-
OBJCOPY = $(CROSS)objcopy

ELF     = target/riscv32i-unknown-none-elf/release/blindsig-soc-fw
NUM_WORDS = 4096

all: firmware.hex

$(ELF): src/main.rs Cargo.toml link.ld
	cargo build --release

firmware.bin: $(ELF)
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.bin
	python3 ../fw/makehex.py $< $(NUM_WORDS) > $@

clean:
	cargo clean
	rm -f firmware.bin firmware.hex

.PHONY: all clean
