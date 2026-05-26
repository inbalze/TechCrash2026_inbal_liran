// Internet Clock Top Module -- DE10-Lite
// Receives "HH:MM:SS\r\n" via UART from ESP32 and displays on 6x 7-segment.
// UART input: ARDUINO_IO[0] via Arduino header (9600 baud)
// Display: HEX5:HEX4 = hours, HEX3:HEX2 = minutes, HEX1:HEX0 = seconds
// Reset: SW[9] active-low

module internet_clock_top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO
);

    // ---- Wiring ----
    wire clk   = MAX10_CLK1_50;
    wire rst_n = SW[9];
    wire uart_rx_pin;

    // ARDUINO_IO[0] is our UART RX input from ESP32 (Arduino header IO0)
    // ARDUINO_IO[1] available for UART TX to ESP32 (Arduino header IO1) -- unused in this project
    // Drive unused pins as high-Z
    assign ARDUINO_IO[15:2] = 14'bz;
    assign ARDUINO_IO[1]    = 1'bz;  // Reserved for TX (unused)
    assign ARDUINO_IO[0]    = 1'bz;  // Input mode
    assign uart_rx_pin = ARDUINO_IO[0];

    // Unused LEDs off
    assign LEDR = 10'b0;

    // ---- UART Receiver ----
    wire [7:0] rx_byte;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ(50_000_000),
        .BAUD(9600)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (uart_rx_pin),
        .rx_data  (rx_byte),
        .rx_valid (rx_valid)
    );

    // ---- ASCII Time Parser ----
    // Expects "HH:MM:SS" followed by \r or \n
    // ASCII '0' = 0x30, so digit = byte - 0x30
    // Character positions: H1 H0 : M1 M0 : S1 S0
    //                      0  1  2 3  4  5 6  7

    reg [3:0] digit [0:5];   // digit[5]=H tens ... digit[0]=S ones
    reg [3:0] char_idx;
    reg       time_valid;

    // Temp buffer for incoming digits
    reg [3:0] tmp_digit [0:5];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            char_idx   <= 0;
            time_valid <= 0;
            digit[0] <= 0; digit[1] <= 0; digit[2] <= 0;
            digit[3] <= 0; digit[4] <= 0; digit[5] <= 0;
            tmp_digit[0] <= 0; tmp_digit[1] <= 0; tmp_digit[2] <= 0;
            tmp_digit[3] <= 0; tmp_digit[4] <= 0; tmp_digit[5] <= 0;
        end else if (rx_valid) begin
            if (rx_byte == 8'h0A || rx_byte == 8'h0D) begin
                // End of line -- commit if we got 8 characters
                if (char_idx == 8) begin
                    digit[5] <= tmp_digit[5];  // H tens
                    digit[4] <= tmp_digit[4];  // H ones
                    digit[3] <= tmp_digit[3];  // M tens
                    digit[2] <= tmp_digit[2];  // M ones
                    digit[1] <= tmp_digit[1];  // S tens
                    digit[0] <= tmp_digit[0];  // S ones
                    time_valid <= 1;
                end
                char_idx <= 0;
            end else begin
                case (char_idx)
                    0: tmp_digit[5] <= rx_byte[3:0]; // H tens (ASCII - 0x30 = lower nibble)
                    1: tmp_digit[4] <= rx_byte[3:0]; // H ones
                    // 2: colon -- skip
                    3: tmp_digit[3] <= rx_byte[3:0]; // M tens
                    4: tmp_digit[2] <= rx_byte[3:0]; // M ones
                    // 5: colon -- skip
                    6: tmp_digit[1] <= rx_byte[3:0]; // S tens
                    7: tmp_digit[0] <= rx_byte[3:0]; // S ones
                endcase
                char_idx <= char_idx + 1;
            end
        end
    end

    // ---- 7-Segment Display Drivers ----
    seven_segment seg5 (.data(digit[5]), .blank(~time_valid), .seg(HEX5));  // H tens
    seven_segment seg4 (.data(digit[4]), .blank(~time_valid), .seg(HEX4));  // H ones
    seven_segment seg3 (.data(digit[3]), .blank(~time_valid), .seg(HEX3));  // M tens
    seven_segment seg2 (.data(digit[2]), .blank(~time_valid), .seg(HEX2));  // M ones
    seven_segment seg1 (.data(digit[1]), .blank(~time_valid), .seg(HEX1));  // S tens
    seven_segment seg0 (.data(digit[0]), .blank(~time_valid), .seg(HEX0));  // S ones

endmodule
