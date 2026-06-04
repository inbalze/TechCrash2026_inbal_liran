module top_voltmeter (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);
    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[1];

    // ARDUINO_IO[0] = UART RX from ESP32 (read only, not driven by FPGA)
    assign ARDUINO_IO[15:1] = 15'bz;
    assign ARDUINO_RESET_N  = 1'bz;

    wire [15:0] mv_rx;
    wire        mv_valid;

    uart_rx #(.CLKS_PER_BIT(5208)) u_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (ARDUINO_IO[0]),
        .data  (mv_rx),
        .valid (mv_valid)
    );

    // Latch millivolt value on each valid packet; clamp to 3300
    logic [15:0] mv;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)        mv <= '0;
        else if (mv_valid) mv <= (mv_rx > 16'd3300) ? 16'd3300 : mv_rx;
    end

    // BCD digit extraction: display shows "X.XX" (Volts, tenths, hundredths)
    logic [15:0] d_v_w, d_t_w, d_h_w;
    always_comb begin
        d_v_w = (mv / 16'd1000) % 16'd10;
        d_t_w = (mv / 16'd100)  % 16'd10;
        d_h_w = (mv / 16'd10)   % 16'd10;
    end

    wire [7:0] seg_v, seg_t, seg_h;
    seven_segment u_hex2 (.digit(d_v_w[3:0]), .seg(seg_v));
    seven_segment u_hex1 (.digit(d_t_w[3:0]), .seg(seg_t));
    seven_segment u_hex0 (.digit(d_h_w[3:0]), .seg(seg_h));

    // HEX2 = volts digit with decimal point ON (bit 7 forced low = active-low DP on)
    assign HEX2 = {1'b0, seg_v[6:0]};
    assign HEX1 = seg_t;
    assign HEX0 = seg_h;
    assign HEX3 = 8'hFF;
    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    // 10-stage thermometer: one LED per 330 mV
    assign LEDR[0] = (mv >= 16'd330);
    assign LEDR[1] = (mv >= 16'd660);
    assign LEDR[2] = (mv >= 16'd990);
    assign LEDR[3] = (mv >= 16'd1320);
    assign LEDR[4] = (mv >= 16'd1650);
    assign LEDR[5] = (mv >= 16'd1980);
    assign LEDR[6] = (mv >= 16'd2310);
    assign LEDR[7] = (mv >= 16'd2640);
    assign LEDR[8] = (mv >= 16'd2970);
    assign LEDR[9] = (mv >= 16'd3300);

endmodule
