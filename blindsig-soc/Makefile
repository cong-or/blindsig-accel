# Makefile — Top-level build for blindsig-soc
#
# Targets:
#   make sim          — Build firmware + simulate (default, C firmware)
#   make sim FW=rust  — Build + simulate with Rust firmware
#   make waves        — Open waveform viewer
#   make clean        — Remove build artifacts

FW ?= c
ACCEL_RTL = ../blindsig-rtl/rtl/blindsig_accel.v \
            ../blindsig-rtl/rtl/redmod.v \
            ../blindsig-rtl/rtl/mulmod.v

ifeq ($(FW),rust)
  FW_DIR = fw-rust
else
  FW_DIR = fw
endif

.PHONY: all sim firmware waves clean

all: sim

# Build firmware
firmware:
	$(MAKE) -C $(FW_DIR)

# Compile Verilog
soc.vvp: firmware rtl/picorv32.v rtl/soc_top.v rtl/blindsig_bus_wrap.v $(ACCEL_RTL) tb/tb_soc.v
	cp $(FW_DIR)/firmware.hex .
	iverilog -o $@ -s tb_soc \
		rtl/picorv32.v \
		rtl/soc_top.v \
		rtl/blindsig_bus_wrap.v \
		$(ACCEL_RTL) \
		tb/tb_soc.v

# Run simulation and check result
sim: soc.vvp
	@echo "=== Running SoC simulation (FW=$(FW)) ==="
	@vvp soc.vvp | tee sim.log
	@echo ""
	@echo "=== Result ==="
	@if grep -q "PASS" sim.log; then \
		echo "PASS: Integration test succeeded"; \
	elif grep -q "FAIL" sim.log; then \
		echo "FAIL: Integration test failed"; \
		exit 1; \
	elif grep -q "TRAP" sim.log; then \
		echo "FAIL: CPU trapped"; \
		exit 1; \
	elif grep -q "TIMEOUT" sim.log; then \
		echo "FAIL: Simulation timed out"; \
		exit 1; \
	else \
		echo "FAIL: No PASS/FAIL output detected"; \
		exit 1; \
	fi

# Open waveform viewer
waves: soc.vcd
	gtkwave soc.vcd &

soc.vcd: sim

clean:
	$(MAKE) -C fw clean
	$(MAKE) -C fw-rust clean
	rm -f soc.vvp soc.vcd firmware.hex sim.log
