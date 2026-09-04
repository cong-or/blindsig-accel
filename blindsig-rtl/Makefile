# blindsig-rtl Makefile

SIM_OUT  = blindsig_tb
VCD_FILE = blindsig.vcd

RTL_SRC  = rtl/blindsig_accel.v
TB_SRC   = tb/tb_blindsig.v

.PHONY: sim waves clean

sim: $(RTL_SRC) $(TB_SRC)
	iverilog -o $(SIM_OUT) $(TB_SRC) $(RTL_SRC)
	vvp $(SIM_OUT)

waves: $(VCD_FILE)
	gtkwave $(VCD_FILE) &

clean:
	rm -f $(SIM_OUT) $(VCD_FILE)
