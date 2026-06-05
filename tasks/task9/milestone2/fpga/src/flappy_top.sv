module flappy_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,
    input  logic [9:0]  SW,
    output logic [6:0]  HEX0,
    output logic        UART_TX,
    inout  [15:0]       ARDUINO_IO,
    inout               ARDUINO_RESET_N
);
    wire clk   = MAX10_CLK1_50;
    wire rst_n = 1'b1; // FPGA runs continuously, reset tied high to allow KEY[1] signaling

    // ── Debounce KEY[0] ───────────────────────────────────────────────────────
    logic key0_debounced;
    debouncer #(
        .CLK_FREQ(50000000),
        .DEBOUNCE_TIME_MS(20)
    ) deb_key0 (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (KEY[0]),
        .out   (key0_debounced)
    );

    // ── Falling-edge → KEY[0] press → PAUSE TOGGLE command (0xFE) ────────────
    logic pause_pulse;
    edge_detector edge_key0 (
        .clk          (clk),
        .rst_n        (rst_n),
        .in           (key0_debounced),
        .falling_edge (pause_pulse)
    );

    // ── Debounce KEY[1] ───────────────────────────────────────────────────────
    logic key1_debounced;
    debouncer #(
        .CLK_FREQ(50000000),
        .DEBOUNCE_TIME_MS(20)
    ) deb_key1 (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (KEY[1]),
        .out   (key1_debounced)
    );

    // ── Falling-edge → KEY[1] press → RESET SIMULATION command (0xFB) ────────
    logic sim_reset_pulse;
    edge_detector edge_key1 (
        .clk          (clk),
        .rst_n        (rst_n),
        .in           (key1_debounced),
        .falling_edge (sim_reset_pulse)
    );

    // ── SW[9] state-change detector → SOLO MODE command (0xFD / 0xFC) ────────
    logic       solo_changed;
    logic [3:0] solo_val_reg;   // bit [0] = registered SW[9] state
    state_change_detector solo_det (
        .clk            (clk),
        .rst_n          (rst_n),
        .val            ({3'b000, SW[9]}),
        .changed        (solo_changed),
        .registered_val (solo_val_reg)
    );

    // ── SW[3:0] difficulty state-change detector ─────────────────────────────
    logic       diff_changed;
    logic [3:0] diff_val;
    state_change_detector diff_det (
        .clk            (clk),
        .rst_n          (rst_n),
        .val            (SW[3:0]),
        .changed        (diff_changed),
        .registered_val (diff_val)
    );

    // ── 7-segment: show SW[3:0] on HEX0 ──────────────────────────────────────
    seg7_hex hex_inst (
        .hex_val (SW[3:0]),
        .seg     (HEX0)
    );

    // ── UART transmitter ──────────────────────────────────────────────────────
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_active;
    logic       tx_serial;
    logic       tx_done;

    uart_tx #(
        .CLK_FREQ  (50000000),
        .BAUD_RATE (115200)
    ) uart_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_active(tx_active),
        .tx_serial(tx_serial),
        .tx_done  (tx_done)
    );

    assign UART_TX         = tx_serial;
    assign ARDUINO_IO      = 16'bz;
    assign ARDUINO_RESET_N = 1'bz;

    // ── TX arbitration (priority: reset > pause > solo > difficulty) ─────────
    logic       pending_reset;
    logic       pending_pause;
    logic       pending_solo;
    logic       solo_state;     // 1 = SW[9] is now HIGH (solo ON)
    logic       pending_diff;
    logic [3:0] diff_to_send;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_reset <= 1'b0;
            pending_pause <= 1'b0;
            pending_solo  <= 1'b0;
            solo_state    <= 1'b0;
            pending_diff  <= 1'b0;
            diff_to_send  <= 4'd0;
            tx_start      <= 1'b0;
            tx_data       <= 8'd0;
        end else begin
            // ── Latch incoming triggers ─────────────────────────────────────
            if (sim_reset_pulse) begin
                pending_reset <= 1'b1;
            end
            if (pause_pulse) begin
                pending_pause <= 1'b1;
            end
            if (solo_changed) begin
                pending_solo <= 1'b1;
                solo_state   <= SW[9];
            end
            if (diff_changed) begin
                pending_diff <= 1'b1;
                diff_to_send <= SW[3:0];
            end

            // ── Clear TX start strobe after one cycle ───────────────────────
            tx_start <= 1'b0;

            // ── Arbiter: fire only when UART is idle ────────────────────────
            if (!tx_active && !tx_start) begin
                if (pending_reset) begin
                    tx_start      <= 1'b1;
                    tx_data       <= 8'hFB;   // RESET SIMULATION (KEY[1])
                    pending_reset <= 1'b0;
                end else if (pending_pause) begin
                    tx_start      <= 1'b1;
                    tx_data       <= 8'hFE;   // PAUSE / RESUME
                    pending_pause <= 1'b0;
                end else if (pending_solo) begin
                    tx_start     <= 1'b1;
                    tx_data      <= solo_state ? 8'hFD : 8'hFC; // SOLO ON / OFF
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
