// tb_blindsig.v — Testbench for blindsig_accel
//
// Mirrors the firmware driver's exact call sequence:
//   RESET -> LOAD_MOD -> write modulus -> LOAD_OP -> write operand -> START -> poll -> read

`timescale 1ns / 1ps

module tb_blindsig;

    reg         clk;
    reg         rst_n;
    reg  [4:0]  addr;
    reg  [31:0] wdata;
    wire [31:0] rdata;
    reg         wen;
    reg         ren;

    // Register offsets
    localparam ADDR_CTRL    = 5'h00;
    localparam ADDR_STATUS  = 5'h04;
    localparam ADDR_OPERAND = 5'h08;
    localparam ADDR_RESULT  = 5'h0C;
    localparam ADDR_MODULUS = 5'h10;

    // CTRL bits
    localparam CTRL_START    = 32'h1;
    localparam CTRL_RESET    = 32'h2;
    localparam CTRL_LOAD_OP  = 32'h4;
    localparam CTRL_LOAD_MOD = 32'h8;

    // STATUS bits
    localparam STATUS_BUSY  = 32'h1;
    localparam STATUS_DONE  = 32'h2;
    localparam STATUS_ERROR = 32'h4;

    // Test counters
    integer pass_count;
    integer fail_count;
    integer test_num;

    // DUT
    blindsig_accel dut (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata),
        .wen   (wen),
        .ren   (ren)
    );

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Bus transaction tasks — drive on negedge, sampled by DUT on posedge
    // ---------------------------------------------------------------
    task bus_write;
        input [4:0]  a;
        input [31:0] d;
        begin
            @(negedge clk);
            addr  = a;
            wdata = d;
            wen   = 1'b1;
            ren   = 1'b0;
            @(negedge clk);
            wen   = 1'b0;
        end
    endtask

    task bus_read;
        input  [4:0]  a;
        output [31:0] d;
        begin
            @(negedge clk);
            addr = a;
            wen  = 1'b0;
            ren  = 1'b1;
            #1;  // let combinational rdata settle
            d    = rdata;
            @(negedge clk);
            ren  = 1'b0;
        end
    endtask

    // ---------------------------------------------------------------
    // Firmware-equivalent compute sequence
    // ---------------------------------------------------------------
    task fw_compute;
        input  [31:0] mod_val;
        input  [31:0] op_val;
        output [31:0] result_val;
        output        error_flag;
        reg    [31:0] status;
        begin
            // reset()
            bus_write(ADDR_CTRL, CTRL_RESET);

            // load_modulus_word: CTRL_LOAD_MOD then write modulus
            bus_write(ADDR_CTRL, CTRL_LOAD_MOD);
            bus_write(ADDR_MODULUS, mod_val);

            // load_operand_word: CTRL_LOAD_OP then write operand
            bus_write(ADDR_CTRL, CTRL_LOAD_OP);
            bus_write(ADDR_OPERAND, op_val);

            // start()
            bus_write(ADDR_CTRL, CTRL_START);

            // wait_and_read_result: poll BUSY
            status = STATUS_BUSY;
            while (status & STATUS_BUSY) begin
                bus_read(ADDR_STATUS, status);
            end

            // Check error
            if (status & STATUS_ERROR) begin
                error_flag = 1'b1;
                result_val = 32'h0;
            end else begin
                error_flag = 1'b0;
                bus_read(ADDR_RESULT, result_val);
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Check helper
    // ---------------------------------------------------------------
    task check_result;
        input [31:0] got;
        input [31:0] expected;
        input        got_error;
        input        expect_error;
        begin
            if (expect_error) begin
                if (got_error) begin
                    $display("  TEST %0d: PASS (got expected ERROR)", test_num);
                    pass_count = pass_count + 1;
                end else begin
                    $display("  TEST %0d: FAIL — expected ERROR, got result=%0d", test_num, got);
                    fail_count = fail_count + 1;
                end
            end else begin
                if (got_error) begin
                    $display("  TEST %0d: FAIL — unexpected ERROR", test_num);
                    fail_count = fail_count + 1;
                end else if (got == expected) begin
                    $display("  TEST %0d: PASS (result=%0d)", test_num, got);
                    pass_count = pass_count + 1;
                end else begin
                    $display("  TEST %0d: FAIL — expected %0d, got %0d", test_num, expected, got);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    reg [31:0] res;
    reg        err;

    initial begin
        $dumpfile("blindsig.vcd");
        $dumpvars(0, tb_blindsig);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        // Initial reset
        rst_n = 0;
        addr  = 0;
        wdata = 0;
        wen   = 0;
        ren   = 0;
        #20;
        rst_n = 1;
        #10;

        $display("=== blindsig_accel testbench ===");
        $display("");

        // ----------------------------------------------------------
        // Test 1: Basic operation — 10^2 mod 7 = 100 mod 7 = 2
        // ----------------------------------------------------------
        test_num = 1;
        $display("Test %0d: operand=10, modulus=7, expect=2", test_num);
        fw_compute(32'd7, 32'd10, res, err);
        check_result(res, 32'd2, err, 1'b0);
        $display("");

        // ----------------------------------------------------------
        // Test 2: Division by zero — modulus=0 should ERROR
        // ----------------------------------------------------------
        test_num = 2;
        $display("Test %0d: operand=10, modulus=0, expect ERROR", test_num);
        fw_compute(32'd0, 32'd10, res, err);
        check_result(res, 32'd0, err, 1'b1);
        $display("");

        // ----------------------------------------------------------
        // Test 3: Different values — 15^2 mod 13 = 225 mod 13 = 4
        // ----------------------------------------------------------
        test_num = 3;
        $display("Test %0d: operand=15, modulus=13, expect=4", test_num);
        fw_compute(32'd13, 32'd15, res, err);
        check_result(res, 32'd4, err, 1'b0);
        $display("");

        // ----------------------------------------------------------
        // Test 4: 64-bit overflow — 70000^2 = 4_900_000_000 > 2^32
        //         70000^2 mod 17 = 4900000000 mod 17 = 2
        // ----------------------------------------------------------
        test_num = 4;
        $display("Test %0d: operand=70000, modulus=17, expect=2 (64-bit overflow)", test_num);
        fw_compute(32'd17, 32'd70000, res, err);
        check_result(res, 32'd2, err, 1'b0);
        $display("");

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        $display("=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("");

        #20;
        $finish;
    end

endmodule
