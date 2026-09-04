// redmod.v — constant-time bit-serial modular reduction
//
// result = x mod m, processing one bit of x per clock, MSB first:
//
//     r = 0
//     for i = WIDTH-1 downto 0:
//         r = (2*r + x[i]) mod m       // one conditional subtract
//     result = r
//
// Precondition: m > 0.  Latency: exactly WIDTH clocks after `start`,
// independent of x and m. Same constant-time discipline as mulmod: the
// single "if >= m then subtract" is a multiplexer, and the loop length is
// fixed. Used to bring an operand into range (< m) before mulmod.

module redmod #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [WIDTH-1:0] x,
    input  wire [WIDTH-1:0] m,          // must be > 0
    output reg  [WIDTH-1:0] result,     // x mod m, valid when `done`
    output reg              done,
    output wire             busy
);
    localparam CW = $clog2(WIDTH) + 1;

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;

    reg             state;
    reg [WIDTH-1:0] x_reg;   // shifted left; MSB is the active bit
    reg [WIDTH-1:0] m_reg;
    reg [WIDTH-1:0] r;       // remainder so far, always < m
    reg [CW-1:0]    cnt;

    assign busy = (state == S_RUN);

    wire [WIDTH:0] m_ext   = {1'b0, m_reg};
    // 2*r + bit  ==  (r << 1) | bit, in WIDTH+1 bits
    wire [WIDTH:0] shifted = {r, x_reg[WIDTH-1]};
    wire [WIDTH:0] sub     = shifted - m_ext;
    wire [WIDTH:0] next_r  = (shifted >= m_ext) ? sub : shifted;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            x_reg  <= {WIDTH{1'b0}};
            m_reg  <= {WIDTH{1'b0}};
            r      <= {WIDTH{1'b0}};
            cnt    <= {CW{1'b0}};
            result <= {WIDTH{1'b0}};
            done   <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        x_reg <= x;
                        m_reg <= m;
                        r     <= {WIDTH{1'b0}};
                        cnt   <= WIDTH;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    r     <= next_r[WIDTH-1:0];
                    x_reg <= {x_reg[WIDTH-2:0], 1'b0};
                    cnt   <= cnt - 1'b1;
                    if (cnt == 1) begin
                        result <= next_r[WIDTH-1:0];
                        done   <= 1'b1;
                        state  <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
