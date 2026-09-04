// blindsig_accel.v — MMIO blind signature accelerator peripheral
//
// Register map (matches firmware driver in blindsig-fw/src/lib.rs):
//   0x00  CTRL     W   [0] START  [1] RESET  [2] LOAD_OP  [3] LOAD_MOD
//   0x04  STATUS   R   [0] BUSY   [1] DONE   [2] ERROR
//   0x08  OPERAND  W   [31:0]
//   0x0C  RESULT   R   [31:0]
//   0x10  MODULUS  W   [31:0]
//
// Operation: operand^2 mod modulus (single-word, 64-bit intermediate)
// State machine: IDLE -> COMPUTING (4 cycles) -> DONE

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

    // State machine
    localparam S_IDLE      = 2'd0;
    localparam S_COMPUTING = 2'd1;
    localparam S_DONE      = 2'd2;

    reg [1:0]  state;
    reg [2:0]  cycle_count;   // counts computation cycles
    reg [31:0] operand;
    reg [31:0] modulus;
    reg [31:0] result;
    reg        flag_busy;
    reg        flag_done;
    reg        flag_error;
    reg        load_op_armed;  // CTRL_LOAD_OP was written
    reg        load_mod_armed; // CTRL_LOAD_MOD was written

    // 64-bit intermediate for operand^2
    wire [63:0] square;
    assign square = {32'b0, operand} * {32'b0, operand};

    // Combinational read mux
    always @(*) begin
        case (addr)
            ADDR_STATUS: rdata = {29'b0, flag_error, flag_done, flag_busy};
            ADDR_RESULT: rdata = result;
            default:     rdata = 32'h0;
        endcase
    end

    // Main sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            cycle_count   <= 3'd0;
            operand       <= 32'd0;
            modulus       <= 32'd0;
            result        <= 32'd0;
            flag_busy     <= 1'b0;
            flag_done     <= 1'b0;
            flag_error    <= 1'b0;
            load_op_armed <= 1'b0;
            load_mod_armed <= 1'b0;
        end else begin
            // Handle CTRL writes (action register — each write is a one-shot command)
            if (wen && addr == ADDR_CTRL) begin
                if (wdata[CTRL_RESET]) begin
                    // RESET: clear everything
                    state         <= S_IDLE;
                    cycle_count   <= 3'd0;
                    operand       <= 32'd0;
                    modulus       <= 32'd0;
                    result        <= 32'd0;
                    flag_busy     <= 1'b0;
                    flag_done     <= 1'b0;
                    flag_error    <= 1'b0;
                    load_op_armed <= 1'b0;
                    load_mod_armed <= 1'b0;
                end else if (wdata[CTRL_START] && state == S_IDLE) begin
                    // START: begin computation (only from IDLE)
                    if (modulus == 32'd0) begin
                        // Division by zero — error immediately
                        flag_error <= 1'b1;
                        flag_done  <= 1'b1;
                        flag_busy  <= 1'b0;
                        state      <= S_DONE;
                    end else begin
                        flag_busy  <= 1'b1;
                        flag_done  <= 1'b0;
                        flag_error <= 1'b0;
                        state      <= S_COMPUTING;
                        cycle_count <= 3'd0;
                    end
                    load_op_armed  <= 1'b0;
                    load_mod_armed <= 1'b0;
                end else if (wdata[CTRL_LOAD_OP]) begin
                    load_op_armed <= 1'b1;
                end else if (wdata[CTRL_LOAD_MOD]) begin
                    load_mod_armed <= 1'b1;
                end
            end

            // Handle data register writes (gated by armed flags)
            if (wen && addr == ADDR_OPERAND && load_op_armed) begin
                operand       <= wdata;
                load_op_armed <= 1'b0;
            end
            if (wen && addr == ADDR_MODULUS && load_mod_armed) begin
                modulus        <= wdata;
                load_mod_armed <= 1'b0;
            end

            // State machine
            case (state)
                S_COMPUTING: begin
                    if (cycle_count == 3'd3) begin
                        // Computation complete
                        result    <= square % {32'b0, modulus};
                        flag_busy <= 1'b0;
                        flag_done <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        cycle_count <= cycle_count + 3'd1;
                    end
                end
                // S_IDLE, S_DONE: wait for CTRL commands
                default: ;
            endcase
        end
    end

endmodule
