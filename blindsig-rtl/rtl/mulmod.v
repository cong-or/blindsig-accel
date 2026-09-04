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
endmodule
