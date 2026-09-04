// mulmod.v — constant-time bit-serial modular multiplier
//
// result = (a * b) mod m, processing one bit of b per clock, MSB first,
// using the classic shift/add-and-reduce recurrence:
//
//     acc = 0
//     for i = WIDTH-1 downto 0:
//         acc = 2*acc mod m            // double and reduce
//         if b[i]: acc = (acc + a) mod m
//     result = acc
//
// Preconditions: a < m, b < m, m > 0.
// Latency: exactly WIDTH clocks after `start`, independent of a, b, m.
//
// Constant-time by construction — this is the whole point of moving the
// operation into a fixed-function datapath:
//   * every iteration performs the SAME work (one doubling, one add, two
//     conditional subtracts) regardless of operand values;
//   * each "if >= m then subtract" and the "if b[i] then add" is resolved
//     with a multiplexer, never a branch or a variable-length loop;
//   * the iteration count depends only on WIDTH.
// A software modmul on a general-purpose CPU cannot guarantee this: the
// compiler and microarchitecture reintroduce data-dependent timing. A
// fixed-cycle datapath removes that class of side channel by design.

module mulmod #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,      // 1-cycle pulse to begin
    input  wire [WIDTH-1:0] a,          // multiplicand, must be < m
    input  wire [WIDTH-1:0] b,          // multiplier,  must be < m
    input  wire [WIDTH-1:0] m,          // modulus,     must be > 0
    output reg  [WIDTH-1:0] result,     // (a*b) mod m, valid when `done`
    output reg              done,       // 1-cycle pulse when result is valid
    output wire             busy
);
    localparam CW = $clog2(WIDTH) + 1;  // iteration-counter width

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;

    reg             state;
    reg [WIDTH-1:0] a_reg;
    reg [WIDTH-1:0] m_reg;
    reg [WIDTH-1:0] b_reg;   // shifted left each cycle; MSB is the active bit
    reg [WIDTH:0]   acc;     // running accumulator, always < m (1 bit headroom)
    reg [CW-1:0]    cnt;

    assign busy = (state == S_RUN);

    // --- one constant-time step (combinational) ---
    wire [WIDTH:0] m_ext   = {1'b0, m_reg};

    // 1) acc = 2*acc mod m   (acc < m  =>  2*acc < 2m  =>  one subtract suffices)
    wire [WIDTH:0] dbl     = {acc[WIDTH-1:0], 1'b0};
    wire [WIDTH:0] dbl_sub = dbl - m_ext;
    wire [WIDTH:0] red1    = (dbl >= m_ext) ? dbl_sub : dbl;

    // 2) candidate for a set bit: acc = (acc + a) mod m   (both < m => sum < 2m)
    wire [WIDTH:0] add     = red1 + {1'b0, a_reg};
    wire [WIDTH:0] add_sub = add - m_ext;
    wire [WIDTH:0] red2    = (add >= m_ext) ? add_sub : add;

    // 3) select on the active b bit — a mux, not a branch (constant-time)
    wire [WIDTH:0] step    = b_reg[WIDTH-1] ? red2 : red1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            acc    <= {(WIDTH+1){1'b0}};
            a_reg  <= {WIDTH{1'b0}};
            b_reg  <= {WIDTH{1'b0}};
            m_reg  <= {WIDTH{1'b0}};
            cnt    <= {CW{1'b0}};
            result <= {WIDTH{1'b0}};
            done   <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        a_reg <= a;
                        b_reg <= b;
                        m_reg <= m;
                        acc   <= {(WIDTH+1){1'b0}};
                        cnt   <= WIDTH;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    acc   <= step;
                    b_reg <= {b_reg[WIDTH-2:0], 1'b0};
                    cnt   <= cnt - 1'b1;
                    if (cnt == 1) begin
                        result <= step[WIDTH-1:0];
                        done   <= 1'b1;
                        state  <= S_IDLE;
                    end
                end
            endcase
        end
    end

`ifdef FORMAL
    // ---- formal verification harness (inert for synthesis and simulation) ----
    // Proven with SymbiYosys — see formal/mulmod.sby, run via `make formal`.

    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    // Begin every trace with a reset cycle, then hold reset deasserted, so the
    // proof starts from the known reset state rather than an arbitrary one.
    always @(*) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end

    // Shadow the operands of the in-flight operation: b_reg shifts during the
    // run, so capture the originals when the operation starts.
    reg [WIDTH-1:0] f_a, f_b, f_m;
    reg             f_running;

    always @(posedge clk) begin
        if (!rst_n) begin
            f_running <= 1'b0;
        end else if (state == S_IDLE && start) begin
            // preconditions of the operation about to run
            assume (m > 0);
            assume (a < m);
            f_a       <= a;
            f_b       <= b;
            f_m       <= m;
            f_running <= 1'b1;
        end else if (done) begin
            f_running <= 1'b0;
        end
    end

    // Reduction invariant: throughout the run the accumulator stays in range.
    // Proven unbounded by k-induction (the two operand facts are the auxiliary
    // invariants that make `acc < m` inductive).
    always @(posedge clk)
        if (f_past_valid && rst_n && state == S_RUN) begin
            assert (m_reg != 0);
            assert (a_reg <  m_reg);
            assert (acc   < {1'b0, m_reg});
        end

`ifdef FORMAL_EQUIV
    // End-to-end correctness, checked by BMC at a reduced WIDTH where the input
    // space is exhaustively searchable: the result is reduced and equals
    // (a*b) mod m computed by an independent reference.
    always @(posedge clk)
        if (f_past_valid && rst_n && done && f_running) begin
            assert (result < f_m);
            assert ( {{WIDTH{1'b0}}, result} ==
                     (({{WIDTH{1'b0}}, f_a} * {{WIDTH{1'b0}}, f_b}) % {{WIDTH{1'b0}}, f_m}) );
        end
`endif
`endif

endmodule
