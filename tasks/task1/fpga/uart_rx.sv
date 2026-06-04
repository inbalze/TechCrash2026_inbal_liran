module uart_rx #(
    parameter int CLKS_PER_BIT = 5208   // 50 MHz / 9600
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rx,
    output logic [15:0] data,
    output logic        valid
);
    // CDC: double-flop synchronizer on async RX input
    logic rx_s0, rx_s1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) {rx_s0, rx_s1} <= 2'b11;
        else        {rx_s0, rx_s1} <= {rx, rx_s0};
    end

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t      state;
    logic [12:0] baud_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  shift;
    logic        byte_sel;   // 0 = waiting for high byte, 1 = waiting for low byte
    logic [7:0]  byte0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            baud_cnt <= '0;
            bit_idx  <= '0;
            shift    <= '0;
            byte_sel <= 1'b0;
            byte0    <= '0;
            data     <= '0;
            valid    <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)

                IDLE: begin
                    if (!rx_s1) begin
                        baud_cnt <= '0;
                        state    <= START;
                    end
                end

                // Wait half a bit period to sample subsequent bits at their centre
                START: begin
                    if (baud_cnt == (CLKS_PER_BIT / 2 - 1)) begin
                        baud_cnt <= '0;
                        bit_idx  <= '0;
                        state    <= DATA;
                    end else
                        baud_cnt <= baud_cnt + 1;
                end

                DATA: begin
                    if (baud_cnt == (CLKS_PER_BIT - 1)) begin
                        baud_cnt <= '0;
                        shift    <= {rx_s1, shift[7:1]};   // LSB first → MSB ends in [7]
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state   <= STOP;
                        end else
                            bit_idx <= bit_idx + 1;
                    end else
                        baud_cnt <= baud_cnt + 1;
                end

                STOP: begin
                    if (baud_cnt == (CLKS_PER_BIT - 1)) begin
                        baud_cnt <= '0;
                        if (!byte_sel) begin
                            byte0    <= shift;      // high byte captured
                            byte_sel <= 1'b1;
                            state    <= IDLE;       // wait for low byte start bit
                        end else begin
                            data     <= {byte0, shift};   // assemble 16-bit millivolt value
                            valid    <= 1'b1;
                            byte_sel <= 1'b0;
                            state    <= IDLE;
                        end
                    end else
                        baud_cnt <= baud_cnt + 1;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
