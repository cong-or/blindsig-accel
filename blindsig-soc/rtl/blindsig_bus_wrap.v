// blindsig_bus_wrap.v — PicoRV32 bus → blindsig_accel adapter
//
// In plain terms: a small translator so the CPU's memory bus can talk to the
// accelerator — it turns the CPU's read/write handshake into the simple
// enable pulses the accelerator expects, and reports back when the access is done.
//
// Translates the PicoRV32 valid/ready handshake into single-cycle
// wen/ren pulses for the accelerator, then asserts ready one cycle later.

module blindsig_bus_wrap (
    input  wire        clk,
    input  wire        rst_n,

    // PicoRV32 bus interface (active when sel_accel is asserted)
    input  wire        bus_valid,
    input  wire [4:0]  bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire [3:0]  bus_wstrb,
    output reg         bus_ready,
    output wire [31:0] bus_rdata
);

    // Generate single-cycle wen/ren pulses on the first cycle of a transaction
    wire accel_wen = bus_valid && !bus_ready && |bus_wstrb;
    wire accel_ren = bus_valid && !bus_ready && ~|bus_wstrb;

    // Ready asserts one cycle after valid (registered)
    always @(posedge clk) begin
        if (!rst_n)
            bus_ready <= 1'b0;
        else
            bus_ready <= bus_valid && !bus_ready;
    end

    // Accelerator instance
    blindsig_accel accel (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (bus_addr),
        .wdata (bus_wdata),
        .rdata (bus_rdata),
        .wen   (accel_wen),
        .ren   (accel_ren)
    );

endmodule
