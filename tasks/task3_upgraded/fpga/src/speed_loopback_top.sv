// =============================================================
// CrashTech VLSI-2026 — Challenge 3: Speed Loopback (task3_upgraded)
// speed_loopback_top.sv — 8-bit Parallel Bus variant
//
// Architecture change vs baseline (task3):
//   FPGA→ESP32 path: UART TX REPLACED with 8-bit parallel bus + WR strobe.
//   ESP32→FPGA path: UART RX KEPT at 115200 baud for 1-byte checksum return.
//
// Parallel bus timing (50 MHz clock):
//   PAR_SETUP_CYC = 2  ( 40 ns) — data stable, WR=0
//   PAR_WR_HI_CYC = 12 (240 ns) — WR=1, ESP32 ISR fires and reads data
//   PAR_WR_LO_CYC = 2  ( 40 ns) — WR=0, recovery
//   Total per byte  = 16 cycles = 320 ns
//   10,004 bytes × 320 ns ≈ 3.2 ms TX  (vs 24 ms for 4.16 Mbps UART)
//
// Arduino header wiring:
//   IO[0]  PIN_AB5  = UART RX ← ESP32 GPIO33 TX  (checksum return, 115200 baud)
//   IO[1]  PIN_AB6  = tri-state (unused)
//   IO[2]  PIN_AB7  = D0 → ESP32 GPIO12
//   IO[3]  PIN_AB8  = D1 → ESP32 GPIO13
//   IO[4]  PIN_AB9  = D2 → ESP32 GPIO14
//   IO[5]  PIN_Y10  = D3 → ESP32 GPIO25
//   IO[6]  PIN_AA11 = D4 → ESP32 GPIO26
//   IO[7]  PIN_AA12 = D5 → ESP32 GPIO27
//   IO[8]  PIN_AB17 = D6 → ESP32 GPIO34
//   IO[9]  PIN_AA17 = D7 → ESP32 GPIO35
//   IO[10] PIN_AB19 = WR → ESP32 GPIO32  (rising edge = data valid)
//   IO[15:11]       = tri-state (unused)
//
// Immutable blocks (unchanged from base): LFSR, sum, timer, state machine,
//   display mux, seven_segment instantiations, LED assignments.
// =============================================================

module speed_loopback_top (
    input         MAX10_CLK1_50,
    input  [1:0]  KEY,
    input  [9:0]  SW,
    output [9:0]  LEDR,
    output [7:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout  [15:0] ARDUINO_IO
);

    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[1];

    // ==============================================================
    // IMMUTABLE: Edge detect KEY[0] (active-low button)
    // ==============================================================
    reg key0_r, key0_rr;
    always @(posedge clk) begin
        key0_r  <= KEY[0];
        key0_rr <= key0_r;
    end
    wire start_pulse = key0_rr & ~key0_r;   // falling edge

    // ==============================================================
    // IMMUTABLE: Fixed data count: 10,000 bytes
    // ==============================================================
    wire [31:0] total_count = 32'd10_000;

    // ==============================================================
    // IMMUTABLE: LFSR-16 (x^16 + x^15 + x^13 + x^4 + 1)
    // ==============================================================
    reg [15:0] lfsr;
    wire lfsr_feedback = lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3];

    // ==============================================================
    // IMMUTABLE: Checksum accumulator
    // ==============================================================
    reg [31:0] sum;

    // ==============================================================
    // PARALLEL BUS CONTROLLER  (drop-in replacement for uart_tx)
    //
    // Interface mirrors uart_tx:
    //   par_start   ↔ tx_start  (one-cycle pulse to initiate transfer)
    //   par_busy    ↔ tx_busy   (high while transfer in progress)
    //   par_data_in ↔ tx_data   (byte to send, stable while par_busy)
    //
    // Physical outputs:
    //   par_data_reg[7:0] → ARDUINO_IO[9:2] → ESP32 GPIO 12-14, 25-27, 34-35
    //   par_wr_reg        → ARDUINO_IO[10]  → ESP32 GPIO 32 (WR strobe)
    //
    // Timing (all in 50 MHz clock cycles = 20 ns each):
    //   PAR_SETUP_CYC : data on bus, WR=0 (hold / setup time)
    //   PAR_WR_HI_CYC : WR=1; ESP32 ISR fires (latency ~150-200 ns) and
    //                   reads GPIO registers; must be > ISR latency
    //   PAR_WR_LO_CYC : WR=0 recovery before next byte
    // ==============================================================
    localparam PAR_SETUP_CYC = 2;    //  40 ns
    localparam PAR_WR_HI_CYC = 12;   // 240 ns  (> 200 ns ESP32 ISR latency)
    localparam PAR_WR_LO_CYC = 2;    //  40 ns
    // Total:  16 cycles = 320 ns per byte

    localparam PAR_IDLE  = 2'd0;
    localparam PAR_SETUP = 2'd1;
    localparam PAR_HIGH  = 2'd2;
    localparam PAR_LOW   = 2'd3;

    reg [1:0] par_state;
    reg [3:0] par_cnt;         // counter: needs 4 bits for WR_HI_CYC-1 = 11
    reg [7:0] par_data_reg;    // registered byte driving D[7:0] bus
    reg       par_wr_reg;      // registered WR output
    reg       par_busy;        // asserted while transfer in progress

    // Driven by main FSM (same role as tx_data / tx_start in base code)
    reg [7:0] par_data_in;
    reg       par_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            par_state    <= PAR_IDLE;
            par_cnt      <= 4'd0;
            par_data_reg <= 8'd0;
            par_wr_reg   <= 1'b0;
            par_busy     <= 1'b0;
        end else begin
            case (par_state)

                PAR_IDLE: begin
                    par_wr_reg <= 1'b0;
                    if (par_start) begin
                        par_data_reg <= par_data_in;            // latch byte
                        par_cnt      <= PAR_SETUP_CYC - 1;
                        par_busy     <= 1'b1;
                        par_state    <= PAR_SETUP;
                    end
                end

                PAR_SETUP: begin
                    if (par_cnt == 4'd0) begin
                        par_wr_reg <= 1'b1;                     // WR goes HIGH
                        par_cnt    <= PAR_WR_HI_CYC - 1;
                        par_state  <= PAR_HIGH;
                    end else
                        par_cnt <= par_cnt - 4'd1;
                end

                PAR_HIGH: begin
                    if (par_cnt == 4'd0) begin
                        par_wr_reg <= 1'b0;                     // WR goes LOW
                        par_cnt    <= PAR_WR_LO_CYC - 1;
                        par_state  <= PAR_LOW;
                    end else
                        par_cnt <= par_cnt - 4'd1;
                end

                PAR_LOW: begin
                    if (par_cnt == 4'd0) begin
                        par_busy  <= 1'b0;
                        par_state <= PAR_IDLE;
                    end else
                        par_cnt <= par_cnt - 4'd1;
                end

                default: par_state <= PAR_IDLE;
            endcase
        end
    end

    // ==============================================================
    // UART RX — 115200 baud, 8N1 (KEPT INTACT for checksum return)
    //   ESP32 GPIO33 TX → ARDUINO_IO[0] → here
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
    // Arduino Header IO assignments
    //   D[7:0] mapped to IO[9:2]:
    //     IO[2]=D0(GPIO12), IO[3]=D1(GPIO13), IO[4]=D2(GPIO14)
    //     IO[5]=D3(GPIO25), IO[6]=D4(GPIO26), IO[7]=D5(GPIO27)
    //     IO[8]=D6(GPIO34), IO[9]=D7(GPIO35)
    //   IO[10]=WR(GPIO32)
    // ==============================================================
    assign ARDUINO_IO[0]     = 1'bz;               // UART RX — input
    assign ARDUINO_IO[1]     = 1'bz;               // unused
    assign ARDUINO_IO[9:2]   = par_data_reg;        // D0..D7
    assign ARDUINO_IO[10]    = par_wr_reg;          // WR strobe
    assign ARDUINO_IO[15:11] = {5{1'bz}};           // unused

    // ==============================================================
    // IMMUTABLE: Millisecond timer
    // ==============================================================
    reg [31:0] timer_ms;
    reg [15:0] timer_pre;
    reg        timer_running, timer_reset;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_ms  <= 0;
            timer_pre <= 0;
        end else if (timer_reset) begin
            timer_ms  <= 0;
            timer_pre <= 0;
        end else if (timer_running) begin
            if (timer_pre == 16'd49_999) begin
                timer_pre <= 0;
                timer_ms  <= timer_ms + 1;
            end else
                timer_pre <= timer_pre + 1;
        end
    end

    // ==============================================================
    // IMMUTABLE: State machine
    //   Only change: tx_busy → par_busy, tx_start → par_start,
    //                tx_data → par_data_in
    // ==============================================================
    localparam S_IDLE = 3'd0,
               S_HDR  = 3'd1,
               S_DATA = 3'd2,
               S_WAIT = 3'd3,
               S_DONE = 3'd4;

    reg [2:0]  state;
    reg [31:0] send_count;
    reg [1:0]  hdr_idx;
    reg        pass;
    reg [7:0]  rx_checksum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            lfsr          <= 16'hACE1;
            sum           <= 0;
            send_count    <= 0;
            hdr_idx       <= 0;
            pass          <= 0;
            rx_checksum   <= 0;
            par_start     <= 0;
            par_data_in   <= 0;
            timer_running <= 0;
            timer_reset   <= 0;
        end else begin
            par_start   <= 0;       // default: one-cycle pulse
            timer_reset <= 0;

            // ---- Start / Restart ----
            if (start_pulse && (state == S_IDLE || state == S_DONE)) begin
                state         <= S_HDR;
                lfsr          <= 16'hACE1;
                sum           <= 0;
                send_count    <= 0;
                hdr_idx       <= 0;
                pass          <= 0;
                timer_reset   <= 1;
                timer_running <= 1;
            end else begin
                case (state)
                    S_IDLE: ;   // wait for start_pulse

                    // Send 4-byte header: total_count little-endian
                    S_HDR: begin
                        if (!par_busy && !par_start) begin
                            case (hdr_idx)
                                2'd0: par_data_in <= total_count[7:0];
                                2'd1: par_data_in <= total_count[15:8];
                                2'd2: par_data_in <= total_count[23:16];
                                2'd3: par_data_in <= total_count[31:24];
                            endcase
                            par_start <= 1;
                            if (hdr_idx == 2'd3)
                                state <= S_DATA;
                            hdr_idx <= hdr_idx + 1;
                        end
                    end

                    // Send N random bytes via parallel bus
                    S_DATA: begin
                        if (!par_busy && !par_start) begin
                            if (send_count < total_count) begin
                                par_data_in <= lfsr[7:0];
                                par_start   <= 1;
                                sum         <= sum + {24'd0, lfsr[7:0]};
                                lfsr        <= {lfsr[14:0], lfsr_feedback};
                                send_count  <= send_count + 1;
                            end else begin
                                state <= S_WAIT;
                            end
                        end
                    end

                    // Wait for ESP32 checksum byte over UART RX
                    S_WAIT: begin
                        if (rx_valid) begin
                            rx_checksum   <= rx_data;
                            timer_running <= 0;
                            pass          <= (rx_data == sum[7:0]);
                            state         <= S_DONE;
                        end
                    end

                    S_DONE: ;   // wait for start_pulse
                endcase
            end
        end
    end

    // ==============================================================
    // IMMUTABLE: Display mux
    // ==============================================================
    reg [23:0] disp;
    always @(*) begin
        case (state)
            S_IDLE:  disp = total_count[23:0];
            S_HDR:   disp = 24'd0;
            S_DATA:  disp = send_count[23:0];
            S_WAIT:  disp = send_count[23:0];
            S_DONE:  disp = SW[9] ? {8'd0, sum[7:0], rx_checksum}
                                  : timer_ms[23:0];
            default: disp = 24'd0;
        endcase
    end

    seven_segment seg0(.value(disp[3:0]),   .segments(HEX0));
    seven_segment seg1(.value(disp[7:4]),   .segments(HEX1));
    seven_segment seg2(.value(disp[11:8]),  .segments(HEX2));
    seven_segment seg3(.value(disp[15:12]), .segments(HEX3));
    seven_segment seg4(.value(disp[19:16]), .segments(HEX4));
    seven_segment seg5(.value(disp[23:20]), .segments(HEX5));

    // ==============================================================
    // IMMUTABLE: LEDs
    // ==============================================================
    assign LEDR[9]   = timer_running;
    assign LEDR[8]   = (state == S_DONE);
    assign LEDR[7:2] = 6'd0;
    assign LEDR[1]   = (state == S_DONE) & ~pass;
    assign LEDR[0]   = (state == S_DONE) &  pass;

endmodule
