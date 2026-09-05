// blindsig_accel.v — MMIO blind signature accelerator peripheral
//
// Register map (matches firmware driver in blindsig-fw/src/lib.rs):
//   0x00  CTRL     W   [0] START  [1] RESET  [2] LOAD_OP  [3] LOAD_MOD
//   0x04  STATUS   R   [0] BUSY   [1] DONE   [2] ERROR
//   0x08  OPERAND  W   [31:0]
//   0x0C  RESULT   R   [31:0]
//   0x10  MODULUS  W   [31:0]
//
// Operation: operand^2 mod modulus (single word).
//
// The modular arithmetic is performed by two constant-time datapaths, NOT by
// Verilog's behavioural `*`/`%` operators:
//   1. redmod  reduces the operand into range:  a = operand mod modulus
//   2. mulmod  squares it modulo the modulus:   result = (a * a) mod modulus
// Both run in a fixed number of cycles independent of the operand values, so
// the peripheral is constant-time end to end. The operation is a modular
// squaring — the inner step of square-and-multiply modular exponentiation.
// mulmod reduces by conditional subtraction; the funded full-width core keeps
// this constant-time, formally-verified structure but replaces the reduction
// with Montgomery reduction and chains it into a modexp pipeline. The register
// interface and the redmod/mulmod primitives generalise directly.

module blindsig_accel (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        wen,
    input  wire        ren
);

    // Register offsets
    localparam ADDR_CTRL    = 5'h00;
    localparam ADDR_STATUS  = 5'h04;
    localparam ADDR_OPERAND = 5'h08;
    localparam ADDR_RESULT  = 5'h0C;
    localparam ADDR_MODULUS = 5'h10;

    // CTRL bits
    localparam CTRL_START    = 0;
    localparam CTRL_RESET    = 1;
    localparam CTRL_LOAD_OP  = 2;
    localparam CTRL_LOAD_MOD = 3;

    // Compute pipeline state
    localparam C_IDLE   = 2'd0;
    localparam C_REDUCE = 2'd1;
    localparam C_MUL    = 2'd2;
    localparam C_DONE   = 2'd3;

    reg [1:0]  cstate;
    reg [31:0] operand;
    reg [31:0] modulus;
    reg [31:0] result;
    reg [31:0] a_reduced;       // operand mod modulus
    reg        flag_busy;
    reg        flag_done;
    reg        flag_error;
    reg        load_op_armed;
    reg        load_mod_armed;

    // Start pulses to the arithmetic datapaths
    reg          redmod_start;
    reg          mulmod_start;
    wire [31:0]  redmod_out;
    wire [31:0]  mulmod_out;
    wire         redmod_done, mulmod_done;
    wire         redmod_busy, mulmod_busy;

    // a = operand mod modulus
    redmod #(.WIDTH(32)) u_redmod (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (redmod_start),
        .x      (operand),
        .m      (modulus),
        .result (redmod_out),
        .done   (redmod_done),
        .busy   (redmod_busy)
    );

    // result = (a * a) mod modulus
    mulmod #(.WIDTH(32)) u_mulmod (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (mulmod_start),
        .a      (a_reduced),
        .b      (a_reduced),
        .m      (modulus),
        .result (mulmod_out),
        .done   (mulmod_done),
        .busy   (mulmod_busy)
    );

    // Combinational read mux
    always @(*) begin
        case (addr)
            ADDR_STATUS: rdata = {29'b0, flag_error, flag_done, flag_busy};
            ADDR_RESULT: rdata = result;
            default:     rdata = 32'h0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cstate         <= C_IDLE;
            operand        <= 32'd0;
            modulus        <= 32'd0;
            result         <= 32'd0;
            a_reduced      <= 32'd0;
            flag_busy      <= 1'b0;
            flag_done      <= 1'b0;
            flag_error     <= 1'b0;
            load_op_armed  <= 1'b0;
            load_mod_armed <= 1'b0;
            redmod_start   <= 1'b0;
            mulmod_start   <= 1'b0;
        end else begin
            // start signals are one-cycle pulses
            redmod_start <= 1'b0;
            mulmod_start <= 1'b0;

            // ---- CTRL command register (each write is a one-shot command) ----
            if (wen && addr == ADDR_CTRL) begin
                if (wdata[CTRL_RESET]) begin
                    cstate         <= C_IDLE;
                    operand        <= 32'd0;
                    modulus        <= 32'd0;
                    result         <= 32'd0;
                    a_reduced      <= 32'd0;
                    flag_busy      <= 1'b0;
                    flag_done      <= 1'b0;
                    flag_error     <= 1'b0;
                    load_op_armed  <= 1'b0;
                    load_mod_armed <= 1'b0;
                end else if (wdata[CTRL_START] && cstate == C_IDLE) begin
                    if (modulus == 32'd0) begin
                        // division by zero — error immediately
                        flag_error <= 1'b1;
                        flag_done  <= 1'b1;
                        flag_busy  <= 1'b0;
                    end else begin
                        // kick off reduce -> multiply pipeline
                        flag_busy    <= 1'b1;
                        flag_done    <= 1'b0;
                        flag_error   <= 1'b0;
                        redmod_start <= 1'b1;
                        cstate       <= C_REDUCE;
                    end
                    load_op_armed  <= 1'b0;
                    load_mod_armed <= 1'b0;
                end else if (wdata[CTRL_LOAD_OP]) begin
                    load_op_armed <= 1'b1;
                end else if (wdata[CTRL_LOAD_MOD]) begin
                    load_mod_armed <= 1'b1;
                end
            end

            // ---- data register writes (gated by armed flags) ----
            if (wen && addr == ADDR_OPERAND && load_op_armed) begin
                operand       <= wdata;
                load_op_armed <= 1'b0;
            end
            if (wen && addr == ADDR_MODULUS && load_mod_armed) begin
                modulus        <= wdata;
                load_mod_armed <= 1'b0;
            end

            // ---- reduce -> multiply pipeline ----
            case (cstate)
                C_REDUCE: begin
                    if (redmod_done) begin
                        a_reduced    <= redmod_out;
                        mulmod_start <= 1'b1;
                        cstate       <= C_MUL;
                    end
                end
                C_MUL: begin
                    if (mulmod_done) begin
                        result    <= mulmod_out;
                        flag_busy <= 1'b0;
                        flag_done <= 1'b1;
                        cstate    <= C_DONE;
                    end
                end
                default: ; // C_IDLE, C_DONE: wait for CTRL commands
            endcase
        end
    end

endmodule
