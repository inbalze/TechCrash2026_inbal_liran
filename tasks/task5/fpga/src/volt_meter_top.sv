// =============================================================
// CrashTech VLSI-2026 — Challenge 5: FPGA Volt-Meter
// volt_meter_top.sv  —  Top-level module
//
// Flow:
//   50 MHz → Qsys Modular ADC IP (volt_adc_sys)
//           → ADC command FSM (channel 1 = ADCIN1 = Arduino A0)
//           → 12-bit raw value → millivolts (0–3297 mV)
//           → BCD digits → 7-seg (HEX2=volts+DP, HEX1=tenths, HEX0=hundredths)
//           → LED bar graph (LEDR[9:0], ~330 mV per LED)
//           → UART TX 115200 to ESP32 (ARDUINO_IO[1])
//
// IMPORTANT: volt_adc_sys must be generated from volt_adc_sys.qsys
//   using Platform Designer BEFORE compiling this project.
//
// Arduino header:
//   IO[0]  = tri-state (unused)
//   IO[1]  = UART TX → ESP32 GPIO33
//   IO[15:2] = tri-state
//
// Reset: KEY[0] (active-low)
// =============================================================

module volt_meter_top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[0];

    // ---- PLL for ADC clock ----------------------------------------
    wire adc_pll_clk;
    wire adc_pll_locked;

    adc_pll u_adc_pll (
        .inclk0 (clk),
        .c0     (adc_pll_clk),
        .locked (adc_pll_locked)
    );

    // ---- Arduino header IO ----------------------------------------
    wire uart_tx_wire;
    assign ARDUINO_IO[0]    = 1'bz;
    assign ARDUINO_IO[1]    = uart_tx_wire;
    assign ARDUINO_IO[15:2] = 14'bz;
    assign ARDUINO_RESET_N  = 1'bz;

    // ==============================================================
    // 1.  Modular ADC command interface
    //     Keep command_valid high continuously for channel 1.
    //     The standard sequencer handles the ADC clock internally.
    //     Latch response_data whenever response_valid fires.
    // ==============================================================

    // Command wires
    logic        cmd_valid;
    logic        cmd_ready;

    // Response wires
    logic        resp_valid;
    logic [11:0] resp_data;

    // Wait for PLL lock before asserting command valid to prevent sequencer lock-up
    assign cmd_valid = adc_pll_locked;

    // Instantiate Qsys-generated ADC wrapper
    volt_adc_sys u_adc_sys (
        .clk_clk                (clk),
        .reset_reset_n          (rst_n),
        .adc_pll_clock_clk      (adc_pll_clk),
        .adc_pll_locked_export  (adc_pll_locked),
        .command_valid          (cmd_valid),
        .command_ready          (cmd_ready),
        .command_channel        (5'd1),  // ADCIN1 = Arduino A0
        .command_startofpacket  (1'b1),
        .command_endofpacket    (1'b1),
        .response_valid         (resp_valid),
        .response_data          (resp_data),
        .response_channel       (),      // unused — only 1 channel configured
        .response_startofpacket (),
        .response_endofpacket   ()
    );

    // Latch raw ADC result (12-bit)
    logic [11:0] adc_raw;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)        adc_raw <= '0;
        else if (resp_valid) adc_raw <= resp_data;
    end

    // ==============================================================
    // 2.  Convert raw 12-bit → millivolts
    //     DE10-Lite has a 1:1 resistor divider (100k/100k) on each ADCIN pin,
    //     halving the input voltage before the MAX 10's 2.5 V internal reference.
    //     Recovery: mv = raw × (2500 × 2) / 4096 = raw × 5000 / 4096
    //     Max practical product (3.3 V input → raw ≈ 2703): 2703 × 5000 = 13 515 000 < 2^24.
    //     mv = product[23:12] (integer part after >>12)
    // ==============================================================
    logic [23:0] mv_product;
    logic [11:0] adc_mv;

    always_comb begin
        mv_product = {12'b0, adc_raw} * 24'd5000;
        adc_mv     = mv_product[23:12];
    end

    // ==============================================================
    // 3.  BCD digit extraction (combinational, constant denominators)
    //     Display layout: HEX2 = volts (+DP) HEX1 = tenths HEX0 = hundredths
    //     Example: 1650 mV → "1.65"
    // ==============================================================
    logic [3:0] dig_v, dig_t, dig_h;

    always_comb begin
        dig_v = adc_mv / 1000;           // volts digit   (0–3)
        dig_t = (adc_mv / 100) % 10;     // tenths digit  (0–9)
        dig_h = (adc_mv / 10)  % 10;     // hundredths    (0–9)
    end

    // 7-segment instantiation
    wire [7:0] seg_v, seg_t, seg_h;

    seven_segment u_seg_v (.digit(dig_v), .seg(seg_v));
    seven_segment u_seg_t (.digit(dig_t), .seg(seg_t));
    seven_segment u_seg_h (.digit(dig_h), .seg(seg_h));

    // HEX2 = volts with decimal point ON (bit 7 low = DP active-low)
    assign HEX2 = {1'b0, seg_v[6:0]};
    assign HEX1 = seg_t;
    assign HEX0 = seg_h;
    assign HEX3 = 8'hFF;   // blank
    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    // ==============================================================
    // 4.  LED bar graph — proportional to millivolt reading
    //     10 LEDs × 330 mV/LED = 3300 mV full-scale
    // ==============================================================
    assign LEDR[0] = (adc_mv >= 12'd330);
    assign LEDR[1] = (adc_mv >= 12'd660);
    assign LEDR[2] = (adc_mv >= 12'd990);
    assign LEDR[3] = (adc_mv >= 12'd1320);
    assign LEDR[4] = (adc_mv >= 12'd1650);
    assign LEDR[5] = (adc_mv >= 12'd1980);
    assign LEDR[6] = (adc_mv >= 12'd2310);
    assign LEDR[7] = (adc_mv >= 12'd2640);
    assign LEDR[8] = (adc_mv >= 12'd2970);
    assign LEDR[9] = (adc_mv >= 12'd3297);  // full-scale with slight correction

    // ==============================================================
    // 5.  UART TX — fire on each new ADC sample, skip if busy
    // ==============================================================
    wire uart_busy;

    // Trigger: one clock pulse when new sample arrives AND TX is free
    logic uart_trigger;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)     uart_trigger <= 1'b0;
        else            uart_trigger <= resp_valid & ~uart_busy;
    end

    uart_tx_volt #(
        .CLKS_PER_BIT(434)   // 50 000 000 / 115 200 ≈ 434
    ) u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .trigger  (uart_trigger),
        .mv_value ({4'b0, adc_mv}),  // zero-pad to 16 bits
        .tx       (uart_tx_wire),
        .busy     (uart_busy)
    );

endmodule
