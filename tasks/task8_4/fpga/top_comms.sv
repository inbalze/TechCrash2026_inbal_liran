module top_comms (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    inout   [15:0]  ARDUINO_IO
);

    reg [3:0]  por;
    wire rst_n = por[3];
    always @(posedge MAX10_CLK1_50)
        if (!por[3]) por <= por + 1;

    reg [19:0] tx_counter;
    reg [2:0]  send_state;
    wire       uart_ready;
    wire [7:0] uart_data;
    reg [7:0]  uart_data_reg;
    reg        uart_send;
    reg [15:0] packet;

    localparam STATE_IDLE             = 3'd0;
    localparam STATE_SEND_HIGH        = 3'd1;
    localparam STATE_WAIT_HIGH_BUSY  = 3'd2;
    localparam STATE_WAIT_HIGH_READY = 3'd3;
    localparam STATE_SEND_LOW         = 3'd4;
    localparam STATE_WAIT_LOW_BUSY   = 3'd5;
    localparam STATE_WAIT_LOW_READY  = 3'd6;



    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            tx_counter <= 0;
            send_state <= STATE_IDLE;
            uart_send <= 0;
            uart_data_reg <= 0;
        end else begin
            uart_send <= 0;

            case (send_state)
                STATE_IDLE: begin
                    if (tx_counter == 833332) begin
                        tx_counter <= 0;
                        packet <= {4'b0000, SW[9:0], ~KEY[1], ~KEY[0]};
                        send_state <= STATE_SEND_HIGH;
                    end else begin
                        tx_counter <= tx_counter + 1;
                    end
                end

                STATE_SEND_HIGH: begin
                    if (uart_ready) begin
                        uart_data_reg <= packet[15:8];
                        uart_send <= 1;
                        send_state <= STATE_WAIT_HIGH_BUSY;
                    end
                end

                STATE_WAIT_HIGH_BUSY: begin
                    send_state <= STATE_WAIT_HIGH_READY;
                end

                STATE_WAIT_HIGH_READY: begin
                    if (uart_ready) begin
                        send_state <= STATE_SEND_LOW;
                    end
                end

                STATE_SEND_LOW: begin
                    if (uart_ready) begin
                        uart_data_reg <= packet[7:0];
                        uart_send <= 1;
                        send_state <= STATE_WAIT_LOW_BUSY;
                    end
                end

                STATE_WAIT_LOW_BUSY: begin
                    send_state <= STATE_WAIT_LOW_READY;
                end

                STATE_WAIT_LOW_READY: begin
                    if (uart_ready) begin
                        send_state <= STATE_IDLE;
                    end
                end

                default: send_state <= STATE_IDLE;
            endcase
        end
    end

    assign uart_data = uart_data_reg;
    assign LEDR = SW;

    wire tx_wire;

    uart_tx uart_tx_inst (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .data_in(uart_data),
        .send(uart_send),
        .tx(tx_wire),
        .ready(uart_ready)
    );

    assign ARDUINO_IO[1]  = tx_wire;
    assign ARDUINO_IO[0]  = 1'bz;
    assign ARDUINO_IO[15:2] = 14'bz;

endmodule
