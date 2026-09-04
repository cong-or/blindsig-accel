// tb_soc.v — Testbench for PicoRV32 blind signature SoC
//
// Provides clock, reset, timeout watchdog, and trap detection.
// Monitors simio_halt to know when firmware finishes.

`timescale 1ns / 1ps

module tb_soc;

    reg clk;
    reg resetn;

    // 10ns clock period (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    soc_top soc (
        .clk    (clk),
        .resetn (resetn)
    );

    // Reset: hold low for 10 cycles
    initial begin
        resetn = 0;
        repeat (10) @(posedge clk);
        resetn = 1;
    end

    // VCD dump
    initial begin
        $dumpfile("soc.vcd");
        $dumpvars(0, tb_soc);
    end

    // Cycle counter for timeout
    integer cycle_count;
    initial cycle_count = 0;

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;

        // Timeout
        if (cycle_count >= 100000) begin
            $display("\nTIMEOUT after %0d cycles", cycle_count);
            $finish;
        end

        // Halt from firmware
        if (resetn && soc.simio_halt) begin
            $display("\nSimulation halted by firmware at cycle %0d", cycle_count);
            $finish;
        end

        // CPU trap (illegal instruction, misaligned access, etc.)
        if (resetn && soc.trap) begin
            $display("\nCPU TRAP at cycle %0d, PC=0x%08x", cycle_count, soc.cpu.reg_pc);
            $finish;
        end
    end

endmodule
