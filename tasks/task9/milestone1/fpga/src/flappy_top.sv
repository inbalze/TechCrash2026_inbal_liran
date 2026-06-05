module flappy_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,
    input  logic [9:0]  SW,
    output logic [6:0]  HEX0,
    output logic        UART_TX,
    inout  [15:0]       ARDUINO_IO,
    inout               ARDUINO_RESET_N
);
    wire clk  = MAX10_CLK1_50;
    wire rst_n = KEY[1]; // KEY[1] = active-low reset (released = 1 = running)

    // ── Debounce KEY[0] ───────────────────────────────────────────────────
    logic key0_debounced;
    debouncer #(
        .CLK_FREQ(50000000),
        .DEBOUNCE_TIME_MS(20)
    ) deb_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .in    (KEY[0]),
        .out   (key0_debounced)
    );

    // ── Falling-edge detector (KEY[0] active-low → press = falling edge) ──
    // In Milestone 1: KEY[0] press sends 0xFF (FLAP command)
    logic flap_pulse;
    edge_detector edge_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .in           (key0_debounced),
        .falling_edge (flap_pulse)
    );

    // ── SW[3:0] state-change detector (difficulty) ─────────────────────────
    logic        diff_changed;
    logic [3:0]  diff_val;
    state_change_detector diff_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .val            (SW[3:0]),
        .changed        (diff_changed),
        .registered_val (diff_val)
    );

    // ── 7-segment display (HEX0 shows SW[3:0] hex digit) ──────────────────
    seg7_hex hex_inst (
        .hex_val (SW[3:0]),
        .seg     (HEX0)
    );

    // ── UART transmitter ───────────────────────────────────────────────────
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

    // ── TX arbitration (priority: flap > difficulty) ───────────────────────
    logic       pending_flap;
    logic       pending_diff;
    logic [3:0] diff_to_send;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_flap <= 1'b0;
            pending_diff <= 1'b0;
            diff_to_send <= 4'd0;
            tx_start     <= 1'b0;
            tx_data      <= 8'd0;
        end else begin
            if (flap_pulse)   pending_flap <= 1'b1;
            if (diff_changed) begin
                pending_diff <= 1'b1;
                diff_to_send <= SW[3:0];
            end

            tx_start <= 1'b0;

            if (!tx_active && !tx_start) begin
                if (pending_flap) begin
                    tx_start     <= 1'b1;
                    tx_data      <= 8'hFF;   // FLAP command
                    pending_flap <= 1'b0;
                end else if (pending_diff) begin
                    tx_start     <= 1'b1;
                    tx_data      <= {4'h0, diff_to_send};
                    pending_diff <= 1'b0;
                end
            end
        end
    end
endmodule
