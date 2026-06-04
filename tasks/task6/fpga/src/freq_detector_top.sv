// =============================================================
// CrashTech VLSI-2026 — Challenge 6: Frequency Detector
// freq_detector_top.sv  — FPGA Top-Level Module  (v2: upgraded)
//
// Upgrades vs v1:
//   1. UART RX moved from Arduino header (ARDUINO_IO[0] / PIN_AB5)
//      to JP1 40-pin GPIO header: GPIO[0] = PIN_V10.
//   2. Zero-crossing hysteresis (thresholds ±10 LSB, signed 8-bit):
//      replaces naive sign-bit comparison. A crossing is counted only
//      when the signal fully transits the ±10 dead-band, preventing
//      false counts from noise near zero.
//   3. BCD conversion replaced by a sequential Double-Dabble
//      (shift-and-add-3) state machine, eliminating the large
//      combinational divider path.
//
// Architecture:
//   ESP32 transmits 256-sample signed 8-bit sine bursts at 115200 baud
//   via JP1 pin 1 (GPIO[0]).  Bursts are separated by a ≥20 ms idle gap.
//
//   FPGA:
//     1. Receives bytes via UART RX on GPIO[0].
//     2. Idle-timeout synchronizer: idle > 2 ms → gap_detected, which
//        realigns the 256-sample frame counter on the next byte.
//     3. Hysteresis zero-crossing counter:
//          hys_state = 0: signal last below -10 (negative zone)
//          hys_state = 1: signal last above +10 (positive zone)
//          crossing counted only on zone transition
//     4. Frequency: F = crossings × 8000 >> 9 (÷ 512, integer)
//     5. Double-Dabble BCD (12 shift cycles + 1 capture = 260 ns total).
//     6. LED bar: LEDR[n] ON when freq_hz ≥ (n+1)×200 Hz.
//
// Wiring (Task 6):
//   JP1 pin 1 = GPIO[0] = PIN_V10  ← ESP32 GPIO32 TX  (UART RX, 115200 8N1)
//   All other GPIO[35:1], ARDUINO_IO[15:0], ARDUINO_RESET_N → tri-state
//
// Controls:
//   KEY[0] = active-low asynchronous reset
//   SW[9]  = debug: display raw crossing count instead of Hz
// =============================================================

module freq_detector_top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N,
    inout           GPIO_0           // JP1 pin 1 = PIN_V10 — UART RX
);

    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[0];

    // ---- Tri-state all header pins ---------------------------------
    assign ARDUINO_IO    = 16'bz;
    assign ARDUINO_RESET_N = 1'bz;
    // GPIO_0: UART RX input — inout driven to Z so ESP32 signal propagates.

    // ==============================================================
    // 1. UART RX — 115200 baud, 8N1, on JP1 GPIO[0] (PIN_V10)
    // ==============================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ(50_000_000),
        .BAUD    (115_200)
    ) u_rx (
        .clk     (clk),
        .rst_n   (rst_n),
        .rx_in   (GPIO_0),          // JP1 pin 1 ← ESP32 GPIO32 TX
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    // ==============================================================
    // 2. Idle-timeout frame synchronizer
    //    IDLE_TIMEOUT = 2 ms @ 50 MHz = 100,000 cycles.
    //    Inter-byte gap within a burst ≈ 87 µs ≪ 2 ms → no false trigger.
    //    Inter-burst gap ≥ 20 ms ≫ 2 ms → always triggers. ✓
    // ==============================================================
    localparam IDLE_TIMEOUT = 100_000;

    logic [16:0] idle_cnt;
    logic        gap_detected;

    // ==============================================================
    // 3. Hysteresis zero-crossing detector
    //
    //    rx_data is treated as a signed 8-bit integer.
    //    Positive threshold HYST_POS = +10
    //    Negative threshold HYST_NEG = -10
    //
    //    hys_state tracks the zone the signal last settled in:
    //      0 = negative zone (last confirmed below -10)
    //      1 = positive zone (last confirmed above +10)
    //
    //    Crossing counted when:
    //      cross_to_pos: hys_state==0 AND sample > +10  (NEG→POS)
    //      cross_to_neg: hys_state==1 AND sample < -10  (POS→NEG)
    //
    //    Dead band [-10, +10]: hys_state unchanged; no crossing counted.
    // ==============================================================
    localparam signed [7:0] HYST_POS =  8'sd10;
    localparam signed [7:0] HYST_NEG = -8'sd10;

    wire signed [7:0] samp_s     = $signed(rx_data);
    logic             hys_state;

    wire cross_to_pos = !hys_state & (samp_s > HYST_POS);   // NEG → POS
    wire cross_to_neg =  hys_state & (samp_s < HYST_NEG);   // POS → NEG
    wire cur_crossing = cross_to_pos | cross_to_neg;

    // ==============================================================
    // 4. Frame FSM + frequency calculation
    // ==============================================================
    logic [8:0]  frame_cnt;
    logic [7:0]  xing_cnt;
    logic [7:0]  xing_latch;
    logic [11:0] freq_hz;
    logic        bcd_start;

    wire [7:0]  new_xing     = xing_cnt + {7'b0, cur_crossing};
    wire [20:0] freq_product = {13'b0, new_xing} * 21'd8000;
    wire [11:0] freq_calc    = freq_product[20:9];   // × 8000 >> 9 = ÷ 512

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_cnt     <= '0;
            gap_detected <= 1'b1;
            frame_cnt    <= '0;
            xing_cnt     <= '0;
            xing_latch   <= '0;
            hys_state    <= 1'b0;
            freq_hz      <= '0;
            bcd_start    <= 1'b0;
        end else begin
            bcd_start <= 1'b0;

            // ---- Idle counter ----
            if (rx_valid)
                idle_cnt <= '0;
            else if (idle_cnt < IDLE_TIMEOUT - 1)
                idle_cnt <= idle_cnt + 17'd1;
            else
                gap_detected <= 1'b1;

            // ---- Sample ingestion ----
            if (rx_valid) begin

                if (gap_detected) begin
                    // ---- Sample 0: initialise, no crossing counted ----
                    gap_detected <= 1'b0;
                    frame_cnt    <= 9'd1;
                    xing_cnt     <= 8'd0;
                    hys_state    <= (samp_s > HYST_POS) ? 1'b1 : 1'b0;

                end else if (frame_cnt < 9'd256) begin
                    // ---- Samples 1..255 ----
                    xing_cnt  <= new_xing;
                    if (cross_to_pos) hys_state <= 1'b1;
                    if (cross_to_neg) hys_state <= 1'b0;
                    frame_cnt <= frame_cnt + 9'd1;

                    if (frame_cnt == 9'd255) begin
                        xing_latch <= new_xing;
                        freq_hz    <= freq_calc;
                        bcd_start  <= 1'b1;     // trigger BCD converter
                    end

                end
                // frame_cnt == 256: extra bytes before gap → discard

            end // rx_valid

        end
    end

    // ==============================================================
    // 5. Double-Dabble sequential BCD converter
    //
    //    Input : 12-bit binary (max 2000 Hz normal; max 128 debug mode).
    //    Output: bcd_d3..d0, four stable BCD digits for HEX display.
    //
    //    Triggered by bcd_start_r (bcd_start delayed 1 clock so that
    //    freq_hz and xing_latch are already settled before loading).
    //
    //    bcd_reg layout (28 bits):
    //      [27:24]=d3  [23:20]=d2  [19:16]=d1  [15:12]=d0  [11:0]=binary
    //
    //    Algorithm per BCD_CONV cycle:
    //      a) bcd_adj: any nibble ≥ 5 → add 3  (combinational from bcd_reg)
    //      b) shift bcd_reg left 1 bit (MSB out, 0 into LSB)
    //    After 12 cycles, [27:12] holds the 4-digit BCD result.
    //    BCD_DONE captures into stable bcd_d3..d0 outputs.
    //
    //    Total: 13 clock cycles = 260 ns.  Inter-frame ≈ 42 ms.  ✓
    // ==============================================================
    logic bcd_start_r;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) bcd_start_r <= 1'b0;
        else        bcd_start_r <= bcd_start;

    localparam BCD_IDLE = 2'd0;
    localparam BCD_CONV = 2'd1;
    localparam BCD_DONE = 2'd2;

    logic [1:0]  bcd_state;
    logic [3:0]  bcd_iter;
    logic [27:0] bcd_reg;
    logic [3:0]  bcd_d3, bcd_d2, bcd_d1, bcd_d0;

    // Add-3 adjustment: combinational on current bcd_reg
    wire [3:0] adj3 = (bcd_reg[27:24] >= 4'd5) ? bcd_reg[27:24] + 4'd3 : bcd_reg[27:24];
    wire [3:0] adj2 = (bcd_reg[23:20] >= 4'd5) ? bcd_reg[23:20] + 4'd3 : bcd_reg[23:20];
    wire [3:0] adj1 = (bcd_reg[19:16] >= 4'd5) ? bcd_reg[19:16] + 4'd3 : bcd_reg[19:16];
    wire [3:0] adj0 = (bcd_reg[15:12] >= 4'd5) ? bcd_reg[15:12] + 4'd3 : bcd_reg[15:12];
    wire [27:0] bcd_adj = {adj3, adj2, adj1, adj0, bcd_reg[11:0]};

    wire [11:0] bcd_input = SW[9] ? {4'b0, xing_latch} : freq_hz;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcd_state <= BCD_IDLE;
            bcd_iter  <= 4'd0;
            bcd_reg   <= 28'd0;
            bcd_d3 <= 4'd0; bcd_d2 <= 4'd0; bcd_d1 <= 4'd0; bcd_d0 <= 4'd0;
        end else begin
            case (bcd_state)
                BCD_IDLE: begin
                    if (bcd_start_r) begin
                        bcd_reg   <= {16'd0, bcd_input};
                        bcd_iter  <= 4'd0;
                        bcd_state <= BCD_CONV;
                    end
                end
                BCD_CONV: begin
                    bcd_reg  <= {bcd_adj[26:0], 1'b0};   // add-3 then shift left
                    bcd_iter <= bcd_iter + 4'd1;
                    if (bcd_iter == 4'd11) bcd_state <= BCD_DONE;
                end
                BCD_DONE: begin
                    bcd_d3    <= bcd_reg[27:24];
                    bcd_d2    <= bcd_reg[23:20];
                    bcd_d1    <= bcd_reg[19:16];
                    bcd_d0    <= bcd_reg[15:12];
                    bcd_state <= BCD_IDLE;
                end
                default: bcd_state <= BCD_IDLE;
            endcase
        end
    end

    // ==============================================================
    // 6. Seven-segment display (HEX3..0 = BCD digits; HEX4/5 blank)
    // ==============================================================
    seven_segment u_seg3(.digit(bcd_d3), .seg(HEX3));
    seven_segment u_seg2(.digit(bcd_d2), .seg(HEX2));
    seven_segment u_seg1(.digit(bcd_d1), .seg(HEX1));
    seven_segment u_seg0(.digit(bcd_d0), .seg(HEX0));

    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    // ==============================================================
    // 7. LED bar graph — proportional to detected frequency
    //    LEDR[n] ON when freq_hz ≥ (n+1) × 200 Hz
    // ==============================================================
    assign LEDR[0] = (freq_hz >= 12'd200);
    assign LEDR[1] = (freq_hz >= 12'd400);
    assign LEDR[2] = (freq_hz >= 12'd600);
    assign LEDR[3] = (freq_hz >= 12'd800);
    assign LEDR[4] = (freq_hz >= 12'd1000);
    assign LEDR[5] = (freq_hz >= 12'd1200);
    assign LEDR[6] = (freq_hz >= 12'd1400);
    assign LEDR[7] = (freq_hz >= 12'd1600);
    assign LEDR[8] = (freq_hz >= 12'd1800);
    assign LEDR[9] = (freq_hz >= 12'd2000);

endmodule
