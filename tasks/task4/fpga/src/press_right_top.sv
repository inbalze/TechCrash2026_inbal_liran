// =============================================================
// CrashTech VLSI-2026 — Challenge 4: Press Right
// DE10-Lite MAX 10 FPGA top module
//
// Objective: Press KEY[0] to start a 10ms counter, press again
//            at exactly 10.00s (count = 1000) to win.
//
// KEY[0]          : game toggle IDLE ↔ RUNNING (active-low)
// KEY[1]          : asynchronous system reset (active-low)
// HEX3..HEX0      : BCD counter display (e.g. "10.00" with DP)
// HEX4, HEX5      : blanked
// LEDR[9:0]       : proximity bar — 10 = perfect, 0 = far off
// ARDUINO_IO[1]   : UART TX → ESP32 GPIO33, 9600 8N1
// ARDUINO_IO[0]   : tri-state (not driven)
// ARDUINO_IO[15:2]: tri-state
// =============================================================

module press_right_top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[1];  // KEY[1] = active-low system reset

    // ---- Arduino header IO ----------------------------------------
    wire uart_tx_wire;
    assign ARDUINO_IO[0]    = 1'bz;          // FPGA RX side — unused, tri-state
    assign ARDUINO_IO[1]    = uart_tx_wire;   // FPGA TX → ESP32
    assign ARDUINO_IO[15:2] = 14'bz;
    assign ARDUINO_RESET_N  = 1'bz;

    // ==============================================================
    // 1.  10 ms tick generator
    //     50 MHz / 500 000 = 100 Hz  →  one tick every 10 ms
    // ==============================================================
    localparam int TICK_DIV = 500_000;

    logic [18:0] tick_cnt;    // max needed: 499 999 ← fits in 19 bits
    logic        tick_10ms;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt  <= '0;
            tick_10ms <= 1'b0;
        end else begin
            if (tick_cnt == TICK_DIV - 1) begin
                tick_cnt  <= '0;
                tick_10ms <= 1'b1;
            end else begin
                tick_cnt  <= tick_cnt + 1;
                tick_10ms <= 1'b0;
            end
        end
    end

    // ==============================================================
    // 2.  Debounce KEY[0]  (active-low, Schmitt trigger input)
    //     Two-FF synchroniser → 4-sample stability filter at 10 ms
    //     → ~40 ms total debounce window
    // ==============================================================

    // -- Two-FF synchroniser -------
    logic key_s0, key_s1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) {key_s0, key_s1} <= 2'b11;
        else        {key_s0, key_s1} <= {KEY[0], key_s0};
    end

    // -- Stability counter: 4 ticks at same level → latch --
    logic [2:0] dbn_cnt;
    logic       key_dbn;   // debounced KEY[0], active-low

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbn_cnt <= '0;
            key_dbn <= 1'b1;
        end else if (tick_10ms) begin
            if (key_s1 == key_dbn) begin
                dbn_cnt <= '0;
            end else if (dbn_cnt == 3'd3) begin
                key_dbn <= key_s1;
                dbn_cnt <= '0;
            end else begin
                dbn_cnt <= dbn_cnt + 1;
            end
        end
    end

    // -- Rising/falling edge detector (single clock pulse) --------
    logic key_prev, key_fall;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_prev <= 1'b1;
            key_fall <= 1'b0;
        end else begin
            key_prev <= key_dbn;
            key_fall <= key_prev & ~key_dbn;   // 1→0 = active-low press
        end
    end

    // ==============================================================
    // 3.  Control FSM   IDLE ↔ RUNNING
    //     Falling edge on KEY[0] toggles state.
    //     On RUNNING → IDLE: pulse uart_trigger for one clock.
    // ==============================================================
    localparam IDLE    = 1'b0;
    localparam RUNNING = 1'b1;

    logic state;
    logic uart_trigger;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            uart_trigger <= 1'b0;
        end else begin
            uart_trigger <= 1'b0;
            if (key_fall) begin
                state <= ~state;
                if (state == RUNNING)  // about to transition RUNNING → IDLE
                    uart_trigger <= 1'b1;
            end
        end
    end

    // ==============================================================
    // 4.  BCD counter (0 – 9999) + mirrored 14-bit binary counter
    //     Increments on every 10 ms tick while RUNNING.
    //     Resets on IDLE → RUNNING transition.
    //     key_fall inhibits tick to capture a clean count.
    // ==============================================================
    logic [3:0]  dig0, dig1, dig2, dig3;  // ones, tens, hundreds, thousands
    logic [13:0] count_bin;               // binary copy for UART payload

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dig0 <= '0;  dig1 <= '0;  dig2 <= '0;  dig3 <= '0;
            count_bin <= '0;
        end else if (key_fall && state == IDLE) begin
            // IDLE → RUNNING: clear counter before new game
            dig0 <= '0;  dig1 <= '0;  dig2 <= '0;  dig3 <= '0;
            count_bin <= '0;
        end else if (tick_10ms && !key_fall && state == RUNNING
                     && count_bin < 14'd9999) begin
            count_bin <= count_bin + 1;
            // BCD ripple carry
            if (dig0 < 4'd9) begin
                dig0 <= dig0 + 1;
            end else begin
                dig0 <= 4'd0;
                if (dig1 < 4'd9) begin
                    dig1 <= dig1 + 1;
                end else begin
                    dig1 <= 4'd0;
                    if (dig2 < 4'd9) begin
                        dig2 <= dig2 + 1;
                    end else begin
                        dig2 <= 4'd0;
                        dig3 <= (dig3 < 4'd9) ? dig3 + 1 : dig3;
                    end
                end
            end
        end
    end

    // ==============================================================
    // 5.  LED proximity feedback
    //     delta = |count_bin - 1000|
    //     10 LEDs → perfect (delta < 100)
    //     0 LEDs  → delta ≥ 1000
    // ==============================================================
    logic [13:0] delta;
    assign delta = (count_bin >= 14'd1000) ?
                   (count_bin - 14'd1000) :
                   (14'd1000 - count_bin);

    logic [3:0] num_leds;
    always_comb begin
        if      (delta <  14'd100) num_leds = 4'd10;
        else if (delta <  14'd200) num_leds = 4'd9;
        else if (delta <  14'd300) num_leds = 4'd8;
        else if (delta <  14'd400) num_leds = 4'd7;
        else if (delta <  14'd500) num_leds = 4'd6;
        else if (delta <  14'd600) num_leds = 4'd5;
        else if (delta <  14'd700) num_leds = 4'd4;
        else if (delta <  14'd800) num_leds = 4'd3;
        else if (delta <  14'd900) num_leds = 4'd2;
        else if (delta < 14'd1000) num_leds = 4'd1;
        else                       num_leds = 4'd0;
    end

    always_comb begin
        case (num_leds)
            4'd0:    LEDR = 10'b00_0000_0000;
            4'd1:    LEDR = 10'b00_0000_0001;
            4'd2:    LEDR = 10'b00_0000_0011;
            4'd3:    LEDR = 10'b00_0000_0111;
            4'd4:    LEDR = 10'b00_0000_1111;
            4'd5:    LEDR = 10'b00_0001_1111;
            4'd6:    LEDR = 10'b00_0011_1111;
            4'd7:    LEDR = 10'b00_0111_1111;
            4'd8:    LEDR = 10'b00_1111_1111;
            4'd9:    LEDR = 10'b01_1111_1111;
            default: LEDR = 10'b11_1111_1111;  // 10 LEDs
        endcase
    end

    // ==============================================================
    // 6.  Seven-segment decoder (active-low, bit[7] = DP)
    //     HEX0 = ones, HEX1 = tens, HEX2 = hundreds (+ DP),
    //     HEX3 = thousands  →  display reads "XX.XX"
    // ==============================================================
    function [7:0] seg7;
        input [3:0] d;
        case (d)
            4'd0: seg7 = 8'b1100_0000;
            4'd1: seg7 = 8'b1111_1001;
            4'd2: seg7 = 8'b1010_0100;
            4'd3: seg7 = 8'b1011_0000;
            4'd4: seg7 = 8'b1001_1001;
            4'd5: seg7 = 8'b1001_0010;
            4'd6: seg7 = 8'b1000_0010;
            4'd7: seg7 = 8'b1111_1000;
            4'd8: seg7 = 8'b1000_0000;
            4'd9: seg7 = 8'b1001_0000;
            default: seg7 = 8'b1111_1111;  // blank
        endcase
    endfunction

    assign HEX0 = seg7(dig0);
    assign HEX1 = seg7(dig1);
    assign HEX2 = seg7(dig2) & 8'h7F;  // clear DP bit → decimal point ON between HEX3 and HEX2
    assign HEX3 = seg7(dig3);
    assign HEX4 = 8'hFF;  // blank
    assign HEX5 = 8'hFF;  // blank

    // ==============================================================
    // 7.  UART TX — 16-bit payload on RUNNING → IDLE
    //     Low byte (count_bin[7:0]) transmitted first.
    // ==============================================================
    uart_tx_16 #(
        .CLKS_PER_BIT(5208)   // 50 000 000 / 9600 ≈ 5208
    ) u_uart_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .trigger (uart_trigger),
        .data    ({2'b00, count_bin}),  // zero-pad to 16 bits
        .tx      (uart_tx_wire),
        .busy    ()
    );

endmodule
