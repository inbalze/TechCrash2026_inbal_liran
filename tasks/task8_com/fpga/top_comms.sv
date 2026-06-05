module top_comms (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

    wire rst_n = 1'b1;

    reg [31:0] frame_counter;
    reg [15:0] packet;
    reg [7:0]  tx_data;
    reg        tx_start;
    reg [1:0]  tx_state;
    wire       tx_busy;
    wire       tx_line;

    localparam [31:0] FRAME_PERIOD = 32'd833333;

    uart_tx u_uart_tx (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .data_in(tx_data),
        .tx_start(tx_start),
        .tx(tx_line),
        .busy(tx_busy)
    );

    // Diagnostic fan-out: drive TX on both D1 and D0 Arduino pins.
    assign ARDUINO_IO[1] = tx_line;
    assign ARDUINO_IO[0] = tx_line;
    assign ARDUINO_IO[15:2] = 14'hzzzz;
    assign ARDUINO_RESET_N = 1'bz;

    assign LEDR = 10'b0;
    assign HEX0 = 8'hFF;
    assign HEX1 = 8'hFF;
    assign HEX2 = 8'hFF;
    assign HEX3 = 8'hFF;
    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            frame_counter <= 32'd0;
            packet <= 16'd0;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
            tx_state <= 2'd0;
        end else begin
            tx_start <= 1'b0;

            if (frame_counter == FRAME_PERIOD - 32'd1) begin
                frame_counter <= 32'd0;
                // 0xA header in bits [15:12] lets the PC ignore boot/log bytes.
                packet <= {4'hA, SW[9:0], ~KEY[1], ~KEY[0]};
                tx_state <= 2'd1;
            end else begin
                frame_counter <= frame_counter + 32'd1;
            end

            case (tx_state)
                2'd1: begin
                    if (!tx_busy) begin
                        tx_data <= packet[15:8];
                        tx_start <= 1'b1;
                        tx_state <= 2'd2;
                    end
                end
                2'd2: begin
                    if (!tx_busy) begin
                        tx_data <= packet[7:0];
                        tx_start <= 1'b1;
                        tx_state <= 2'd0;
                    end
                end
                default: begin
                    tx_state <= 2'd0;
                end
            endcase
        end
    end

endmodule
