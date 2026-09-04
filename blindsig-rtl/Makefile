# blindsig-rtl Makefile

ACCEL_SRC = rtl/blindsig_accel.v rtl/redmod.v rtl/mulmod.v
ACCEL_TB  = tb/tb_blindsig.v

MUL_SRC   = rtl/mulmod.v
MUL_TB    = tb/tb_mulmod.v

.PHONY: all sim mulmod waves clean

all: mulmod sim

# End-to-end accelerator: operand^2 mod modulus via redmod + mulmod
sim: $(ACCEL_SRC) $(ACCEL_TB)
	iverilog -o blindsig_tb $(ACCEL_TB) $(ACCEL_SRC)
	vvp blindsig_tb

# Unit test for the constant-time modular multiplier
mulmod: $(MUL_SRC) $(MUL_TB)
	iverilog -o mulmod_tb $(MUL_TB) $(MUL_SRC)
	vvp mulmod_tb

waves: blindsig.vcd
	gtkwave blindsig.vcd &

clean:
	rm -f blindsig_tb mulmod_tb blindsig.vcd mulmod.vcd
