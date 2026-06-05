module uart_tx (
    input           clk,
    input           rst_n,
    input   [7:0]   data_in,
    input           send,
    output  reg     tx,
    output  reg     ready
);

    localparam CYCLES_PER_BIT = 5208;

    reg [12:0] baud_counter;
    reg [3:0]  bit_counter;
    reg [9:0]  shift_reg;
    reg        sending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1;
            ready <= 1;
            baud_counter <= 0;
            bit_counter <= 0;
            shift_reg <= 0;
            sending <= 0;
        end else begin
            if (sending) begin
                if (baud_counter == CYCLES_PER_BIT - 1) begin
                    baud_counter <= 0;
                    tx <= shift_reg[0];
                    shift_reg <= shift_reg >> 1;
                    if (bit_counter == 9) begin
                        sending <= 0;
                        ready <= 1;
                    end else begin
                        bit_counter <= bit_counter + 1;
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end else begin
                tx <= 1;
                if (send && ready) begin
                    ready <= 0;
                    sending <= 1;
                    baud_counter <= 0;
                    bit_counter <= 0;
                    shift_reg <= {1'b1, data_in, 1'b0};
                end
            end
        end
    end

endmodule
