// =============================================================================
// uart_rx.sv — Generic UART Receiver
// Configurable CLK_FREQ / BAUD_RATE
// Output: rx_data valid for one clock cycle when rx_done pulses
// =============================================================================
module uart_rx #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx_serial,
    output logic [7:0] rx_data,
    output logic       rx_done
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        START   = 3'b001,
        DATA    = 3'b010,
        STOP    = 3'b011
    } state_t;

    state_t              state;
    logic [$clog2(CLKS_PER_BIT+1)-1:0] clk_count;
    logic [2:0]          bit_index;
    logic [7:0]          rx_data_r;
    logic                rx_s0, rx_s1;   // two-stage synchroniser

    // ── Synchronise async serial input ────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s0 <= 1'b1;
            rx_s1 <= 1'b1;
        end else begin
            rx_s0 <= rx_serial;
            rx_s1 <= rx_s0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_count <= '0;
            bit_index <= '0;
            rx_data_r <= 8'h00;
            rx_data   <= 8'h00;
            rx_done   <= 1'b0;
        end else begin
            rx_done <= 1'b0;  // default: no new byte

            case (state)
                IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;
                    if (rx_s1 == 1'b0)      // falling edge → start bit detected
                        state <= START;
                end

                START: begin
                    // Sample in the middle of the start bit
                    if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx_s1 == 1'b0) begin
                            clk_count <= '0;
                            state     <= DATA;
                        end else begin
                            state <= IDLE;  // false start, abort
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count             <= '0;
                        rx_data_r[bit_index]  <= rx_s1;
                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= '0;
                            state     <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        rx_data   <= rx_data_r;
                        rx_done   <= 1'b1;
                        clk_count <= '0;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
