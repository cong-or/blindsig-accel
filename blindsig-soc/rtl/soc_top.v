// soc_top.v — PicoRV32 SoC with blind signature accelerator
//
// Memory map:
//   0x0000_0000 – 0x0000_3FFF  RAM (16 KB, 4096 words)
//   0x1000_0000                 Sim I/O (write byte = print, write 0xFF = halt)
//   0x2000_0000 – 0x2000_001F  BlindSig accelerator (5 registers)

module soc_top (
    input wire clk,
    input wire resetn
);

    // ---------------------------------------------------------------
    // CPU
    // ---------------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    reg  [31:0] mem_rdata;
    wire        trap;

    picorv32 #(
        .STACKADDR      (32'h 0000_4000),
        .PROGADDR_RESET  (32'h 0000_0000),
        .ENABLE_COUNTERS (0),
        .ENABLE_COUNTERS64 (0),
        .CATCH_MISALIGN  (1),
        .CATCH_ILLINSN   (1),
        .ENABLE_MUL      (0),
        .ENABLE_DIV      (0),
        .ENABLE_IRQ      (0),
        .ENABLE_TRACE    (0),
        .REGS_INIT_ZERO  (1)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),

        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),

        // Unused interfaces
        .pcpi_wr   (1'b0),
        .pcpi_rd   (32'b0),
        .pcpi_wait (1'b0),
        .pcpi_ready(1'b0),
        .irq       (32'b0)
    );

    // ---------------------------------------------------------------
    // Address decode
    // ---------------------------------------------------------------
    wire [3:0] addr_sel = mem_addr[31:28];
    wire sel_ram   = (addr_sel == 4'h0);
    wire sel_simio = (addr_sel == 4'h1);
    wire sel_accel = (addr_sel == 4'h2);

    // ---------------------------------------------------------------
    // RAM — 4096 x 32-bit = 16 KB
    // ---------------------------------------------------------------
    reg [31:0] ram [0:4095];
    initial $readmemh("firmware.hex", ram);

    wire [11:0] ram_word_addr = mem_addr[13:2];
    reg  [31:0] ram_rdata;

    always @(posedge clk) begin
        if (mem_valid && sel_ram) begin
            if (mem_wstrb[0]) ram[ram_word_addr][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) ram[ram_word_addr][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) ram[ram_word_addr][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[ram_word_addr][31:24] <= mem_wdata[31:24];
        end
        ram_rdata <= ram[ram_word_addr];
    end

    // ---------------------------------------------------------------
    // Sim I/O
    // ---------------------------------------------------------------
    reg simio_halt;

    initial simio_halt = 1'b0;

    always @(posedge clk) begin
        if (mem_valid && sel_simio && |mem_wstrb && !simio_ready_r) begin
            if (mem_wdata[7:0] == 8'hFF) begin
                simio_halt <= 1'b1;
            end else begin
                $write("%c", mem_wdata[7:0]);
                $fflush();
            end
        end
    end

    // ---------------------------------------------------------------
    // Accelerator (via bus wrapper)
    // ---------------------------------------------------------------
    wire        accel_ready;
    wire [31:0] accel_rdata;

    blindsig_bus_wrap accel_wrap (
        .clk       (clk),
        .rst_n     (resetn),
        .bus_valid (mem_valid && sel_accel),
        .bus_addr  (mem_addr[4:0]),
        .bus_wdata (mem_wdata),
        .bus_wstrb (mem_wstrb),
        .bus_ready (accel_ready),
        .bus_rdata (accel_rdata)
    );

    // ---------------------------------------------------------------
    // mem_ready / mem_rdata mux
    // ---------------------------------------------------------------
    reg ram_ready_r;

    always @(posedge clk) begin
        if (!resetn)
            ram_ready_r <= 1'b0;
        else
            ram_ready_r <= mem_valid && sel_ram && !ram_ready_r;
    end

    // Sim I/O ready: one-cycle pulse
    reg simio_ready_r;
    always @(posedge clk) begin
        if (!resetn)
            simio_ready_r <= 1'b0;
        else
            simio_ready_r <= mem_valid && sel_simio && !simio_ready_r;
    end

    always @(*) begin
        mem_ready = 1'b0;
        mem_rdata = 32'h0;

        if (sel_ram) begin
            mem_ready = ram_ready_r;
            mem_rdata = ram_rdata;
        end else if (sel_simio) begin
            mem_ready = simio_ready_r;
            mem_rdata = 32'h0;
        end else if (sel_accel) begin
            mem_ready = accel_ready;
            mem_rdata = accel_rdata;
        end
    end

endmodule
