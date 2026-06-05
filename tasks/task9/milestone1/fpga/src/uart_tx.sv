module uart_tx #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  logic clk,
    input  logic rst_n,
    input  logic tx_start,
    input  logic [7:0] tx_data,
    output logic tx_active,
    output logic tx_serial,
    output logic tx_done
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [2:0] {
        IDLE   = 3'b000,
        START  = 3'b001,
        DATA   = 3'b010,
        STOP   = 3'b011,
        CLEANUP= 3'b100
    } state_t;

    state_t state;
    logic [$clog2(CLKS_PER_BIT):0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] tx_data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            clk_count   <= '0;
            bit_index   <= '0;
            tx_data_reg <= '0;
            tx_active   <= 1'b0;
            tx_serial   <= 1'b1;
            tx_done     <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;
                    tx_done   <= 1'b0;
                    clk_count <= '0;
                    bit_index <= '0;

                    if (tx_start) begin
                        tx_active   <= 1'b1;
                        tx_data_reg <= tx_data;
                        state       <= START;
                    end else begin
                        tx_active   <= 1'b0;
                    end
                end

                START: begin
                    tx_serial <= 1'b0;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        state     <= DATA;
                    end
                end

                DATA: begin
                    tx_serial <= tx_data_reg[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= '0;
                            state     <= STOP;
                        end
                    end
                end

                STOP: begin
                    tx_serial <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        tx_done   <= 1'b1;
                        clk_count <= '0;
                        state     <= CLEANUP;
                    end
                end

                CLEANUP: begin
                    tx_active <= 1'b0;
                    tx_done   <= 1'b0;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
