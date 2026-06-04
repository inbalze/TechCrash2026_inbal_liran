// =============================================================
// CrashTech VLSI-2026 — Challenge 2: 3D Cube Tilt
// adxl345_spi.sv  —  SPI Master for ADXL345
//
// Continuously polls X, Y, Z registers (addresses 0x32..0x37)
// using SPI Mode 3 (CPOL=1, CPHA=1).
//
// ADXL345 SPI wiring on DE10-Lite (onboard chip):
//   CS_N  = dedicated ADXL_CS_N output (assigned in top)
//   SCLK  = dedicated ADXL_SCLK output
//   SDO   = dedicated ADXL_SDO  output  (MOSI)
//   SDI   = dedicated ADXL_SDI  input   (MISO)
//
// The ADXL345 multi-byte read uses:
//   First byte: 0x80 | 0x40 | addr  (read | multi-byte | reg_addr)
//   Then clock 12 bytes (6 × 16-bit two's-complement, little-endian)
//
// Parameters:
//   CLK_HZ     — system clock frequency (default 50 MHz)
//   SPI_HZ     — SPI clock frequency    (default 2 MHz)
//
// Outputs:
//   x_data, y_data, z_data — signed 16-bit, updated once per poll
//   data_valid             — 1-cycle pulse when data is fresh
// =============================================================

module adxl345_spi #(
    parameter int CLK_HZ  = 50_000_000,
    parameter int SPI_HZ  = 2_000_000
)(
    input  logic        clk,
    input  logic        rst_n,

    // SPI pins
    output logic        spi_cs_n,
    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso,

    // Data out
    output logic signed [15:0] x_data,
    output logic signed [15:0] y_data,
    output logic signed [15:0] z_data,
    output logic               data_valid
);

    // ---- Timing ------------------------------------------------
    // Half-period counter value (SCLK toggle)
    localparam int HALF = CLK_HZ / (2 * SPI_HZ);  // = 12 for 50MHz/2MHz

    // Poll interval: ~10 ms  (50 MHz × 0.010 = 500 000)
    localparam int POLL_TICKS = CLK_HZ / 100;

    // ---- SPI frame parameters ----------------------------------
    // 1 cmd byte + 6 data bytes = 7 bytes = 56 bits
    localparam int FRAME_BYTES = 7;
    localparam int FRAME_BITS  = FRAME_BYTES * 8;

    // Command byte: READ | MULTI | register 0x32
    localparam logic [7:0] CMD = 8'b1100_0010;  // 0xC2 = 0x80|0x40|0x32

    // ---- State machine -----------------------------------------
    typedef enum logic [1:0] {
        WAIT,   // idle inter-poll delay
        START,  // assert CS_N, prepare
        SHIFT,  // clock bits in/out
        DONE    // latch result, deassert CS_N
    } state_t;

    state_t state;

    // ---- Registers ---------------------------------------------
    logic [19:0] wait_cnt;    // poll interval counter
    logic [11:0] half_cnt;    // SCLK half-period counter
    logic [6:0]  bit_cnt;     // current bit index (0..FRAME_BITS-1)
    logic        sclk_r;      // registered SCLK

    // Shift registers (TX = 56 bits: CMD + 6×0x00, RX = 56 bits)
    logic [FRAME_BITS-1:0] tx_shift;
    logic [FRAME_BITS-1:0] rx_shift;

    // ---- Init output logic -------------------------------------
    assign spi_sclk = sclk_r;
    assign spi_mosi = tx_shift[FRAME_BITS-1];  // MSB first

    // ---- Main FSM ----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= WAIT;
            wait_cnt   <= '0;
            half_cnt   <= '0;
            bit_cnt    <= '0;
            sclk_r     <= 1'b1;   // CPOL=1: idle HIGH
            spi_cs_n   <= 1'b1;
            tx_shift   <= '0;
            rx_shift   <= '0;
            x_data     <= '0;
            y_data     <= '0;
            z_data     <= '0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;  // default: no new data

            case (state)

                // --------------------------------------------------
                WAIT: begin
                    spi_cs_n <= 1'b1;
                    sclk_r   <= 1'b1;
                    if (wait_cnt == POLL_TICKS - 1) begin
                        wait_cnt <= '0;
                        state    <= START;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                // --------------------------------------------------
                START: begin
                    // Prepare TX: CMD byte then 48 zero bits
                    tx_shift <= {CMD, 48'b0};
                    rx_shift <= '0;
                    bit_cnt  <= '0;
                    half_cnt <= '0;
                    sclk_r   <= 1'b1;   // idle between transactions
                    spi_cs_n <= 1'b0;   // assert CS
                    state    <= SHIFT;
                end

                // --------------------------------------------------
                // CPHA=1: data sampled on trailing edge (rising),
                // shifted on leading edge (falling).
                // We toggle SCLK every HALF clocks.
                SHIFT: begin
                    if (half_cnt == HALF - 1) begin
                        half_cnt <= '0;
                        sclk_r   <= ~sclk_r;

                        if (sclk_r == 1'b1) begin
                            // Leading edge (HIGH→LOW): shift TX out
                            tx_shift <= {tx_shift[FRAME_BITS-2:0], 1'b0};
                        end else begin
                            // Trailing edge (LOW→HIGH): sample RX
                            rx_shift <= {rx_shift[FRAME_BITS-2:0], spi_miso};
                            if (bit_cnt == FRAME_BITS - 1) begin
                                state <= DONE;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    end else begin
                        half_cnt <= half_cnt + 1;
                    end
                end

                // --------------------------------------------------
                DONE: begin
                    spi_cs_n   <= 1'b1;
                    sclk_r     <= 1'b1;
                    // rx_shift layout (after discarding cmd byte echo):
                    // [55:48] = first cmd byte echo (ignore)
                    // [47:32] = X low byte, X high byte
                    // [31:16] = Y low byte, Y high byte
                    // [15:0]  = Z low byte, Z high byte
                    x_data     <= {rx_shift[39:32], rx_shift[47:40]};  // little-endian → big-endian
                    y_data     <= {rx_shift[23:16], rx_shift[31:24]};
                    z_data     <= {rx_shift[7:0],   rx_shift[15:8]};
                    data_valid <= 1'b1;
                    state      <= WAIT;
                end

                default: state <= WAIT;

            endcase
        end
    end

endmodule
