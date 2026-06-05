module top_comms (
    input         MAX10_CLK1_50,
    input  [1:0]  KEY,
    input  [9:0]  SW,
    inout  [15:0] ARDUINO_IO
);

    wire clk = MAX10_CLK1_50;
    wire rst_n = KEY[1];

    reg [19:0] timer_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_cnt <= 0;
        end else begin
            if (timer_cnt == 20'd833332) begin
                timer_cnt <= 0;
            end else begin
                timer_cnt <= timer_cnt + 1;
            end
        end
    end

    wire timer_tick = (timer_cnt == 20'd833332);

    reg [2:0] state;
    reg [15:0] packet_reg;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= 3'd0;
            packet_reg <= 16'd0;
            tx_start   <= 1'b0;
            tx_data    <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                3'd0: begin
                    if (timer_tick) begin
                        packet_reg <= {4'b0, SW[9:0], ~KEY[1], ~KEY[0]};
                        state      <= 3'd1;
                    end
                end
                3'd1: begin
                    tx_data  <= packet_reg[15:8];
                    tx_start <= 1'b1;
                    state    <= 3'd2;
                end
                3'd2: begin
                    if (tx_busy) begin
                        state <= 3'd3;
                    end
                end
                3'd3: begin
                    if (!tx_busy) begin
                        state <= 3'd4;
                    end
                end
                3'd4: begin
                    tx_data  <= packet_reg[7:0];
                    tx_start <= 1'b1;
                    state    <= 3'd5;
                end
                3'd5: begin
                    if (tx_busy) begin
                        state <= 3'd6;
                    end
                end
                3'd6: begin
                    if (!tx_busy) begin
                        state <= 3'd0;
                    end
                end
                default: state <= 3'd0;
            endcase
        end
    end

    wire tx_out;
    uart_tx #(
        .CLK_FREQ(50_000_000),
        .BAUD(9600)
    ) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_out(tx_out)
    );

    assign ARDUINO_IO[1] = tx_out;
    assign ARDUINO_IO[0] = 1'bz;
    assign ARDUINO_IO[15:2] = 14'bz;

endmodule
