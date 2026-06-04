// =============================================================
// CrashTech VLSI-2026 — Challenge 6: Frequency Detector
// freq_detector_top.sv  — FPGA Top-Level Module
//
// Architecture:
//   ESP32 transmits 256-sample signed 8-bit sine bursts at
//   115200 baud, separated by a ≥20ms idle gap.
//
//   FPGA:
//     1. Receives bytes via UART RX on ARDUINO_IO[0].
//     2. Idle-timeout synchronizer: line idle > 2ms (100,000
//        clock cycles) → sets gap_detected, which realigns the
//        256-sample frame counter on the next arriving byte.
//     3. Zero-crossing counter: examines sign bit (rx_data[7])
//        of each sample. Counts bit-7 transitions per 256-sample
//        frame (254 comparisons: samples 1..255 vs predecessor).
//     4. Frequency calculation:
//          F = crossings × 8000 / 512  (integer, no divider HDL)
//        Implemented as: F = (crossings × 8000) >> 9
//        Max crossings = 128 → max product = 1,024,000 < 2^21 ✓
//     5. BCD display on HEX3..0 (e.g., "1085" for 1085 Hz).
//        SW[9] = debug mode: show raw crossing count instead.
//     6. Proportional LED bar graph on LEDR[9:0]:
//          LEDR[n] ON when freq_hz ≥ (n+1) × 200 Hz.
//
// Wiring:
//   ARDUINO_IO[0]  PIN_AB5   ← ESP32 GPIO32 TX  (UART RX)
//   All other ARDUINO_IO pins → tri-state
//
// Reset: KEY[0] (active-low)
// Debug: SW[9]  (high = show zero-crossing count on display)
// =============================================================

module freq_detector_top (
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

    // ---- Arduino header: all tri-state (RX is an input net) ----
    assign ARDUINO_IO[15:0] = 16'bz;
    assign ARDUINO_RESET_N  = 1'bz;

    // ==============================================================
    // 1. UART RX — 115200 baud, 8N1
    //    rx_valid pulses for one clock cycle each time a byte is
    //    fully received and the stop bit is validated.
    // ==============================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ(50_000_000),
        .BAUD    (115_200)
    ) u_rx (
        .clk    (clk),
        .rst_n  (rst_n),
        .rx_in  (ARDUINO_IO[0]),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // ==============================================================
    // 2. Idle-timeout frame synchronizer
    //
    //    idle_cnt: increments every clock cycle when no byte is
    //    being received.  Saturates at IDLE_TIMEOUT (2 ms).
    //    When saturated: gap_detected is set → next incoming byte
    //    resets the 256-sample frame and re-initialises the
    //    zero-crossing state.
    //
    //    UART inter-byte gap within a burst:
    //      ≈ 87 µs (one bit period at 115200) ≪ 2 ms → no false trigger.
    //    ESP32 inter-burst gap:
    //      20 ms (flush + delay) ≫ 2 ms → always triggers. ✓
    // ==============================================================
    localparam IDLE_TIMEOUT = 100_000;          // 2 ms @ 50 MHz

    logic [16:0] idle_cnt;                      // 0..100_000 (17 bits)
    logic        gap_detected;

    // ==============================================================
    // 3. Zero-crossing FSM
    //
    //    frame_cnt:  number of samples received in current frame.
    //                Counts 0 → 256.  Reset to 1 on first byte after
    //                a gap (sample 0 initialises prev_sign only).
    //    xing_cnt:   live crossing count for the current frame.
    //    xing_latch: latched at completion of each 256-sample frame.
    //    freq_hz:    computed result, displayed on HEX.
    // ==============================================================
    logic [8:0]  frame_cnt;
    logic [7:0]  xing_cnt;
    logic [7:0]  xing_latch;
    logic        prev_sign;
    logic [11:0] freq_hz;

    // ---- Combinational helpers (evaluated from registered state) ----
    wire         cur_sign     = rx_data[7];
    wire         cur_crossing = cur_sign ^ prev_sign;           // 1 = sign changed
    wire [7:0]   new_xing     = xing_cnt + {7'b0, cur_crossing};

    // Frequency:  F = new_xing × 8000 / 512 = new_xing × 8000 >> 9
    //   {13'b0, new_xing} gives a 21-bit zero-extended operand.
    //   21'd8000 is a 21-bit constant.
    //   Product fits in 21 bits: max = 255 × 8000 = 2,040,000 < 2^21.
    wire [20:0] freq_product = {13'b0, new_xing} * 21'd8000;
    wire [11:0] freq_calc    = freq_product[20:9];              // >> 9 = / 512

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_cnt     <= '0;
            gap_detected <= 1'b1;   // treat power-on as post-gap
            frame_cnt    <= '0;
            xing_cnt     <= '0;
            xing_latch   <= '0;
            prev_sign    <= 1'b0;
            freq_hz      <= '0;
        end else begin

            // ----------------------------------------------------------
            // Idle counter — runs every cycle, independent of FSM
            // ----------------------------------------------------------
            if (rx_valid) begin
                idle_cnt <= '0;                     // byte arrived → reset
            end else if (idle_cnt < IDLE_TIMEOUT - 1) begin
                idle_cnt <= idle_cnt + 17'd1;
            end else begin
                gap_detected <= 1'b1;               // saturated = gap detected
            end

            // ----------------------------------------------------------
            // Sample ingestion — fires only on rx_valid
            // ----------------------------------------------------------
            if (rx_valid) begin

                if (gap_detected) begin
                    // ---- First sample of new frame (index 0) ----
                    // Initialise state; do NOT count a crossing here
                    // because there is no valid prev_sign yet.
                    gap_detected <= 1'b0;
                    frame_cnt    <= 9'd1;       // next byte = sample 1
                    xing_cnt     <= 8'd0;
                    prev_sign    <= cur_sign;

                end else if (frame_cnt < 9'd256) begin
                    // ---- Samples 1..255 ----
                    xing_cnt  <= new_xing;      // accumulate crossing
                    prev_sign <= cur_sign;
                    frame_cnt <= frame_cnt + 9'd1;

                    if (frame_cnt == 9'd255) begin
                        // Last sample of frame: latch final result
                        xing_latch <= new_xing;
                        freq_hz    <= freq_calc;
                        // frame_cnt becomes 256; next bytes are discarded
                        // until gap_detected fires and realigns the frame.
                    end

                end
                // frame_cnt == 256: extra bytes before the gap → discard

            end // rx_valid

        end
    end

    // ==============================================================
    // 4. BCD conversion + 7-segment display
    //
    //    Normal mode (SW[9]=0): display freq_hz  (0–2000 Hz)
    //    Debug  mode (SW[9]=1): display xing_latch (0–128)
    //
    //    disp_num is 12-bit (max 2000 for normal, 128 for debug).
    //    Quartus synthesises constant-divisor divisions as LUTs —
    //    acceptable here because the display update rate is ~24 Hz.
    // ==============================================================
    wire [11:0] disp_num = SW[9] ? {4'b0, xing_latch} : freq_hz;

    wire [3:0] d3 =  disp_num                   / 12'd1000;
    wire [3:0] d2 = (disp_num % 12'd1000)        / 12'd100;
    wire [3:0] d1 = (disp_num % 12'd100)         / 12'd10;
    wire [3:0] d0 =  disp_num                    % 12'd10;

    seven_segment u_seg3(.digit(d3), .seg(HEX3));
    seven_segment u_seg2(.digit(d2), .seg(HEX2));
    seven_segment u_seg1(.digit(d1), .seg(HEX1));
    seven_segment u_seg0(.digit(d0), .seg(HEX0));

    assign HEX4 = 8'hFF;    // blank
    assign HEX5 = 8'hFF;    // blank

    // ==============================================================
    // 5. LED bar graph — proportional to detected frequency
    //    LED[n] lights when freq_hz ≥ (n+1) × 200 Hz
    //    Thresholds: 200, 400, 600, … 2000 Hz  (200 Hz per step)
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
