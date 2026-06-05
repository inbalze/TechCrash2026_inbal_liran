// =============================================================================
// flappy_top.sv — Task 9 Milestone 3: Neural Flappy Bird + FPGA Inference
//
// Milestone 3 additions over Milestone 2:
//   • UART RX from ESP32 (dedicated UART_RX input port / PIN_AB5)
//   • Weight-loading state machine: receives 0xA5 header + 50 weight bytes
//   • Inference engine: receives 0xBB header + 4 telemetry bytes,
//     runs fixed-point 4-4-1 NN, replies 0x01 (FLAP) or 0x00 (NO FLAP)
//   • SW[9] transitions still send 0xFD / 0xFC to ESP32 (repurposed in ESP32
//     firmware as INFERENCE MODE ON / OFF)
//   • All Milestone 1/2 logic preserved: SW[3:0] difficulty, HEX0 display,
//     KEY[0] pause, KEY[1] reset, debouncing
//
// UART Wire Protocol:
//
//   WEIGHT STREAM  (ESP32 → FPGA, triggered once when SW[9] goes HIGH)
//     Byte  0    : 0xA5              sync header
//     Bytes 1-2  : w0[0]  Q7.8 MSB-first  (int16_t = round(float × 256))
//     Bytes 3-4  : w0[1]  Q7.8  ...  row-major [hidden][input]
//     Bytes 5-50 : w0[2..15], b0[0..3], w1[0..3], b1[0]  all Q7.8
//     Total: 51 bytes
//
//   TELEMETRY FRAME  (ESP32 → FPGA, once per game frame in inference mode)
//     Byte 0: 0xBB              sync header
//     Byte 1: bird_y_norm       signed 8-bit Q0.7  (int8_t = round(float × 128))
//     Byte 2: bird_vy_norm      signed 8-bit Q0.7
//     Byte 3: dx_norm           signed 8-bit Q0.7
//     Byte 4: dy_norm           signed 8-bit Q0.7
//     Total: 5 bytes
//
//   INFERENCE RESPONSE  (FPGA → ESP32, immediately after telemetry received)
//     Byte 0: 0x01  FLAP
//          or 0x00  NO FLAP
// =============================================================================
module flappy_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,
    input  logic [9:0]  SW,
    output logic [6:0]  HEX0,
    output logic        UART_TX,    // FPGA → ESP32  (PIN_AB6)
    input  logic        UART_RX,    // ESP32 → FPGA  (PIN_AB5)  NEW M3
    inout  [15:0]       ARDUINO_IO,
    inout               ARDUINO_RESET_N
);
    wire clk   = MAX10_CLK1_50;
    wire rst_n = 1'b1;

    // ── ARDUINO_IO: all high-Z (UART handled via dedicated UART_TX/RX ports) ─
    assign ARDUINO_IO      = 16'bz;
    assign ARDUINO_RESET_N = 1'bz;

    // =========================================================================
    // MILESTONE 1/2 LOGIC — PRESERVED UNCHANGED
    // =========================================================================

    // ── Debounce KEY[0] → pause toggle ───────────────────────────────────────
    logic key0_debounced, pause_pulse;
    debouncer #(.CLK_FREQ(50000000), .DEBOUNCE_TIME_MS(20)) deb_key0 (
        .clk(clk), .rst_n(rst_n), .in(KEY[0]), .out(key0_debounced)
    );
    edge_detector edge_key0 (
        .clk(clk), .rst_n(rst_n), .in(key0_debounced), .falling_edge(pause_pulse)
    );

    // ── Debounce KEY[1] → sim reset ───────────────────────────────────────────
    logic key1_debounced, sim_reset_pulse;
    debouncer #(.CLK_FREQ(50000000), .DEBOUNCE_TIME_MS(20)) deb_key1 (
        .clk(clk), .rst_n(rst_n), .in(KEY[1]), .out(key1_debounced)
    );
    edge_detector edge_key1 (
        .clk(clk), .rst_n(rst_n), .in(key1_debounced), .falling_edge(sim_reset_pulse)
    );

    // ── SW[9] state-change → solo/inference mode command ─────────────────────
    logic       solo_changed;
    logic [3:0] solo_val_reg;
    state_change_detector solo_det (
        .clk(clk), .rst_n(rst_n),
        .val({3'b000, SW[9]}),
        .changed(solo_changed),
        .registered_val(solo_val_reg)
    );

    // ── SW[3:0] difficulty state-change ──────────────────────────────────────
    logic       diff_changed;
    logic [3:0] diff_val;
    state_change_detector diff_det (
        .clk(clk), .rst_n(rst_n),
        .val(SW[3:0]),
        .changed(diff_changed),
        .registered_val(diff_val)
    );

    // ── HEX0: display current difficulty (SW[3:0]) ───────────────────────────
    seg7_hex hex_inst (.hex_val(SW[3:0]), .seg(HEX0));

    // =========================================================================
    // UART TX (FPGA → ESP32)
    // =========================================================================
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_active;
    logic       tx_serial;
    logic       tx_done;

    uart_tx #(.CLK_FREQ(50000000), .BAUD_RATE(115200)) uart_tx_inst (
        .clk      (clk),      .rst_n    (rst_n),
        .tx_start (tx_start), .tx_data  (tx_data),
        .tx_active(tx_active),.tx_serial(tx_serial),
        .tx_done  (tx_done)
    );
    assign UART_TX = tx_serial;

    // =========================================================================
    // UART RX (ESP32 → FPGA)  — NEW IN MILESTONE 3
    // =========================================================================
    logic [7:0] rx_byte;
    logic       rx_done;

    uart_rx #(.CLK_FREQ(50000000), .BAUD_RATE(115200)) uart_rx_inst (
        .clk      (clk),     .rst_n    (rst_n),
        .rx_serial(UART_RX), .rx_data  (rx_byte),
        .rx_done  (rx_done)
    );

    // =========================================================================
    // WEIGHT-LOADING STATE MACHINE  — NEW IN MILESTONE 3
    //
    // Protocol: 0xA5 header + 50 bytes (25 × 16-bit Q7.8, MSB first).
    // Writes each 16-bit word into nn_accelerator weight registers.
    // =========================================================================
    logic [5:0]  wload_cnt;       // counts bytes received after header (0..49)
    logic [4:0]  wload_addr;      // destination weight register (0..24)
    logic [7:0]  wload_msb;       // holds high byte while waiting for low byte
    logic        wload_active;    // 1 while weight stream is in progress
    logic        weight_wr_en;
    logic [4:0]  weight_wr_addr;
    logic [15:0] weight_wr_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wload_cnt      <= 6'd0;
            wload_addr     <= 5'd0;
            wload_msb      <= 8'd0;
            wload_active   <= 1'b0;
            weight_wr_en   <= 1'b0;
            weight_wr_addr <= 5'd0;
            weight_wr_data <= 16'd0;
        end else begin
            weight_wr_en <= 1'b0;  // default: no write this cycle

            if (!wload_active) begin
                if (rx_done && rx_byte == 8'hA5) begin
                    wload_active <= 1'b1;
                    wload_cnt    <= 6'd0;
                    wload_addr   <= 5'd0;
                end
            end else begin
                if (rx_done) begin
                    if (wload_cnt[0] == 1'b0) begin
                        // Even byte index → MSB
                        wload_msb <= rx_byte;
                        wload_cnt <= wload_cnt + 1'b1;
                    end else begin
                        // Odd byte index → LSB; write the complete 16-bit word
                        weight_wr_en   <= 1'b1;
                        weight_wr_addr <= wload_addr;
                        weight_wr_data <= {wload_msb, rx_byte};
                        wload_addr     <= wload_addr + 1'b1;
                        wload_cnt      <= wload_cnt  + 1'b1;
                        if (wload_cnt == 6'd49)
                            wload_active <= 1'b0;
                    end
                end
            end
        end
    end

    // =========================================================================
    // FIXED-POINT NEURAL NETWORK ACCELERATOR  — NEW IN MILESTONE 3
    // =========================================================================
    logic signed [7:0] nn_in0, nn_in1, nn_in2, nn_in3;
    logic              nn_decision;
    logic              nn_weights_loaded;  // guard against zero-weight FLAP

    nn_accelerator nn_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .weight_wr_en   (weight_wr_en),
        .weight_addr    (weight_wr_addr),
        .weight_data    (weight_wr_data),
        .in0            (nn_in0),
        .in1            (nn_in1),
        .in2            (nn_in2),
        .in3            (nn_in3),
        .decision       (nn_decision),
        .weights_loaded (nn_weights_loaded)
    );

    // =========================================================================
    // INFERENCE-REQUEST STATE MACHINE  — NEW IN MILESTONE 3
    //
    // Waits for 0xBB header, collects 4 signed telemetry bytes, then asserts
    // inf_reply_pulse for one clock cycle so the TX arbiter can latch it.
    // Weight loading takes priority: 0xBB ignored while wload_active.
    // =========================================================================
    typedef enum logic [2:0] {
        INF_IDLE  = 3'd0,
        INF_B0    = 3'd1,   // bird_y_norm
        INF_B1    = 3'd2,   // bird_vy_norm
        INF_B2    = 3'd3,   // dx_norm
        INF_B3    = 3'd4,   // dy_norm
        INF_WAIT  = 3'd5,   // one-cycle pipeline bubble: let combinational chain settle
        INF_FIRE  = 3'd6    // pulse inf_reply_pulse for 1 cycle
    } inf_state_t;

    inf_state_t  inf_state;
    logic        inf_reply_pulse;   // one-cycle strobe when NN result is ready
    logic [7:0]  inf_reply_byte;    // 0x01 = FLAP, 0x00 = NO FLAP

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inf_state       <= INF_IDLE;
            nn_in0          <= 8'sd0;
            nn_in1          <= 8'sd0;
            nn_in2          <= 8'sd0;
            nn_in3          <= 8'sd0;
            inf_reply_pulse <= 1'b0;
            inf_reply_byte  <= 8'h00;
        end else begin
            inf_reply_pulse <= 1'b0;  // default deasserted

            case (inf_state)
                INF_IDLE: begin
                    if (rx_done && rx_byte == 8'hBB && !wload_active)
                        inf_state <= INF_B0;
                end

                INF_B0: if (rx_done) begin
                    nn_in0    <= $signed(rx_byte);
                    inf_state <= INF_B1;
                end

                INF_B1: if (rx_done) begin
                    nn_in1    <= $signed(rx_byte);
                    inf_state <= INF_B2;
                end

                INF_B2: if (rx_done) begin
                    nn_in2    <= $signed(rx_byte);
                    inf_state <= INF_B3;
                end

                INF_B3: if (rx_done) begin
                    nn_in3    <= $signed(rx_byte);
                    inf_state <= INF_WAIT;
                end

                // One extra clock cycle so the combinational multiply-add chain
                // from nn_in[0..3] → nn_decision has a full 20 ns to settle
                // before we sample it.  The critical path spans 4 hidden-layer
                // multiply-accumulate units followed by 4 output-layer ones,
                // easily >20 ns on MAX 10 at 50 MHz.
                INF_WAIT: begin
                    inf_state <= INF_FIRE;
                end

                INF_FIRE: begin
                    // All four inputs are latched; combinational NN result valid.
                    // Assert the reply strobe for exactly one clock cycle.
                    inf_reply_pulse <= 1'b1;
                    inf_reply_byte  <= nn_decision ? 8'h01 : 8'h00;
                    inf_state       <= INF_IDLE;
                end

                default: inf_state <= INF_IDLE;
            endcase
        end
    end

    // =========================================================================
    // TX ARBITRATION — single always_ff owns all of tx_start / tx_data
    //
    // Priority (highest → lowest):
    //   1. Inference reply  (time-critical: ESP32 is blocked waiting)
    //   2. Sim reset (KEY[1])
    //   3. Pause toggle (KEY[0])
    //   4. Inference/solo mode change (SW[9])
    //   5. Difficulty change (SW[3:0])
    // =========================================================================
    logic       pending_inf;
    logic [7:0] pending_inf_data;
    logic       pending_reset;
    logic       pending_pause;
    logic       pending_solo;
    logic       solo_state;
    logic       pending_diff;
    logic [3:0] diff_to_send;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_inf      <= 1'b0;
            pending_inf_data <= 8'h00;
            pending_reset    <= 1'b0;
            pending_pause    <= 1'b0;
            pending_solo     <= 1'b0;
            solo_state       <= 1'b0;
            pending_diff     <= 1'b0;
            diff_to_send     <= 4'd0;
            tx_start         <= 1'b0;
            tx_data          <= 8'd0;
        end else begin
            // ── Latch incoming trigger strobes ──────────────────────────────
            if (inf_reply_pulse) begin
                pending_inf      <= 1'b1;
                pending_inf_data <= inf_reply_byte;
            end
            if (sim_reset_pulse) pending_reset <= 1'b1;
            if (pause_pulse)     pending_pause <= 1'b1;
            if (solo_changed) begin
                pending_solo <= 1'b1;
                solo_state   <= SW[9];
            end
            if (diff_changed) begin
                pending_diff <= 1'b1;
                diff_to_send <= SW[3:0];
            end

            // ── Clear TX start strobe (held for exactly 1 cycle) ────────────
            tx_start <= 1'b0;

            // ── Arbiter: fire one byte per TX idle window ────────────────────
            if (!tx_active && !tx_start) begin
                if (pending_inf) begin
                    tx_start         <= 1'b1;
                    tx_data          <= pending_inf_data;
                    pending_inf      <= 1'b0;
                end else if (pending_reset) begin
                    tx_start      <= 1'b1;
                    tx_data       <= 8'hFB;
                    pending_reset <= 1'b0;
                end else if (pending_pause) begin
                    tx_start      <= 1'b1;
                    tx_data       <= 8'hFE;
                    pending_pause <= 1'b0;
                end else if (pending_solo) begin
                    tx_start     <= 1'b1;
                    tx_data      <= solo_state ? 8'hFD : 8'hFC;
                    pending_solo <= 1'b0;
                end else if (pending_diff) begin
                    tx_start     <= 1'b1;
                    tx_data      <= {4'h0, diff_to_send};
                    pending_diff <= 1'b0;
                end
            end
        end
    end

endmodule
