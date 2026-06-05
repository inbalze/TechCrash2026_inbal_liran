module top_game_controller (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

    wire rst_n = 1'b1;
    wire tx_uart;
    
    uart_tx uart_inst (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .data_in(data_byte),
        .tx_start(tx_trigger),
        .tx(tx_uart),
        .busy(uart_busy)
    );

    assign ARDUINO_IO[1] = tx_uart;
    assign ARDUINO_IO[15:2] = 14'hzzzz;
    assign ARDUINO_IO[0] = 1'bz;
    assign ARDUINO_RESET_N = 1'bz;
    
    assign LEDR = 10'b0;
    assign HEX0 = 8'b11111111;
    assign HEX1 = 8'b11111111;
    assign HEX2 = 8'b11111111;
    assign HEX3 = 8'b11111111;
    assign HEX4 = 8'b11111111;
    assign HEX5 = 8'b11111111;
    
    reg [31:0] frame_counter;
    reg [15:0] packet_data;
    reg [1:0]  tx_state;
    reg uart_busy;
    reg tx_trigger;
    reg [7:0]  data_byte;
    
    localparam [31:0] FRAME_PERIOD = 32'd833333;
    
    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            frame_counter <= 32'b0;
            tx_state <= 2'b0;
            tx_trigger <= 1'b0;
            data_byte <= 8'b0;
            packet_data <= 16'b0;
        end
        else begin
            packet_data <= {4'b0, SW[9:0], ~KEY[1], ~KEY[0]};
            
            if (frame_counter == FRAME_PERIOD - 32'd1) begin
                frame_counter <= 32'b0;
                tx_state <= 2'd1;
            end
            else begin
                frame_counter <= frame_counter + 32'd1;
            end
            
            tx_trigger <= 1'b0;
            
            case (tx_state)
                2'd1: begin
                    if (!uart_busy) begin
                        data_byte <= packet_data[15:8];
                        tx_trigger <= 1'b1;
                        tx_state <= 2'd2;
                    end
                end
                2'd2: begin
                    if (!uart_busy) begin
                        data_byte <= packet_data[7:0];
                        tx_trigger <= 1'b1;
                        tx_state <= 2'd0;
                    end
                end
                default: tx_state <= 2'd0;
            endcase
        end
    end

endmodule
