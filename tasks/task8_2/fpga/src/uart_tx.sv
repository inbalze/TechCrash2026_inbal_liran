module uart_tx (
    input           clk,
    input           rst_n,
    input   [7:0]   data_in,
    input           tx_start,
    output  reg     tx,
    output  reg     busy
);

    localparam [12:0] BIT_PERIOD = 13'd5208;
    
    reg [12:0] bit_counter;
    reg [3:0]  bit_index;
    reg [9:0]  frame_bits;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1'b1;
            busy <= 1'b0;
            bit_counter <= 13'b0;
            bit_index <= 4'b0;
            frame_bits <= 10'b1111111111;
        end
        else if (!busy && tx_start) begin
            busy <= 1'b1;
            bit_counter <= 13'b0;
            bit_index <= 4'b0;
            frame_bits <= {1'b1, data_in, 1'b0};
            tx <= 1'b0;
        end
        else if (busy) begin
            if (bit_counter == BIT_PERIOD - 13'd1) begin
                bit_counter <= 13'b0;
                if (bit_index == 4'd9) begin
                    busy <= 1'b0;
                    tx <= 1'b1;
                end
                else begin
                    bit_index <= bit_index + 4'd1;
                    tx <= frame_bits[bit_index + 4'd1];
                end
            end
            else begin
                bit_counter <= bit_counter + 13'd1;
            end
        end
    end

endmodule
