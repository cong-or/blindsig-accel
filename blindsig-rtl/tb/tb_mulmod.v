// tb_mulmod.v — unit testbench for the constant-time modular multiplier.
//
// Checks (a*b) mod m against a 64-bit reference for a range of inputs, and
// asserts that every multiplication takes the SAME number of cycles — the
// observable evidence of the constant-time property.

`timescale 1ns / 1ps

module tb_mulmod;

    localparam WIDTH = 32;

    reg              clk;
    reg              rst_n;
    reg              start;
    reg  [WIDTH-1:0] a, b, m;
    wire [WIDTH-1:0] result;
    wire             done;
    wire             busy;

    integer pass_count;
    integer fail_count;
    integer test_num;
    integer ref_cycles;   // cycle count of the first test, for constant-time check

    mulmod #(.WIDTH(WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .a(a), .b(b), .m(m),
        .result(result), .done(done), .busy(busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Run one (a*b) mod m, measure latency, compare to a 64-bit reference.
    task run_test;
        input [WIDTH-1:0] ta, tb_, tm;
        reg   [63:0]      expected;
        integer           cycles;
        begin
            test_num = test_num + 1;
            expected = ({32'b0, ta} * {32'b0, tb_}) % {32'b0, tm};

            @(negedge clk);
            a = ta; b = tb_; m = tm;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            cycles = 0;
            while (!done) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            // record / check constant-time latency
            if (test_num == 1)
                ref_cycles = cycles;

            if (result !== expected[WIDTH-1:0]) begin
                $display("  TEST %0d FAIL: %0d * %0d mod %0d = %0d, expected %0d",
                         test_num, ta, tb_, tm, result, expected[WIDTH-1:0]);
                fail_count = fail_count + 1;
            end else if (cycles !== ref_cycles) begin
                $display("  TEST %0d FAIL: non-constant latency (%0d cycles vs %0d)",
                         test_num, cycles, ref_cycles);
                fail_count = fail_count + 1;
            end else begin
                $display("  TEST %0d PASS: %0d * %0d mod %0d = %0d  (%0d cycles)",
                         test_num, ta, tb_, tm, result, cycles);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("mulmod.vcd");
        $dumpvars(0, tb_mulmod);

        pass_count = 0; fail_count = 0; test_num = 0;

        rst_n = 0; start = 0; a = 0; b = 0; m = 0;
        #20; rst_n = 1; #10;

        $display("=== mulmod testbench ===");
        $display("");

        // small values
        run_test(3, 3, 7);           // 9 mod 7 = 2
        run_test(6, 6, 7);           // 36 mod 7 = 1
        run_test(2, 4, 7);           // 8 mod 7 = 1
        run_test(0, 5, 7);           // 0
        run_test(5, 0, 7);           // 0
        run_test(1, 1, 2);           // 1

        // mid values (all reduced: a,b < m)
        run_test(123, 456, 789);     // 56088 mod 789 = 69
        run_test(1000, 1000, 1009);  // 1000000 mod 1009 = ...
        run_test(65535, 65534, 65537); // near 16-bit prime

        // large 32-bit stress: (m-1)*(m-1) mod m == 1
        run_test(32'hFFFFFFFE, 32'hFFFFFFFE, 32'hFFFFFFFF);
        // large with big prime-ish modulus
        run_test(32'h9ABCDEF0, 32'h12345678, 32'hFFFFFFFB);
        run_test(32'h7FFFFFFF, 32'h7FFFFFFE, 32'h80000000);

        $display("");
        $display("=== RESULTS: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL MULMOD TESTS PASSED (constant %0d-cycle latency)", ref_cycles);
        else
            $display("SOME MULMOD TESTS FAILED");
        $display("");

        #20; $finish;
    end

    // safety net: never hang
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
