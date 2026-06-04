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

    // Init write: 2 bytes — WRITE to 0x2D (POWER_CTL), value 0x08 (Measure bit)
    localparam int INIT_BITS  = 16;
    localparam logic [15:0] INIT_TX = 16'h2D08;  // 0x2D = reg addr (write), 0x08 = Measure

    // *** DEVID SANITY CHECK — restore to 0xF2 when done ***
    // Single-byte read of register 0x00 (DEVID): READ=1, MB=0, addr=0x00
    // Expected response byte: 0xE5 (229). Maps into x_data[7:0] on OLED.
    localparam logic [7:0] CMD = 8'b1000_0000;  // 0x80 = READ|SINGLE|0x00

    // ---- State machine -----------------------------------------
    typedef enum logic [2:0] {
        INIT_START,  // one-time: send POWER_CTL write
        INIT_SHIFT,  // clock out the 2-byte init frame
        INIT_DONE,   // deassert CS, then go to WAIT forever
        WAIT,        // idle inter-poll delay
        START,       // assert CS_N, prepare read
        SHIFT,       // clock bits in/out
        DONE         // latch result, deassert CS_N
    } state_t;

    state_t state;

    // ---- Registers ---------------------------------------------
    logic [19:0] wait_cnt;    // poll interval counter
    logic [11:0] half_cnt;    // SCLK half-period counter
    logic [6:0]  bit_cnt;     // current bit index
    logic        sclk_r;      // registered SCLK

    // Shift registers for read frame (56 bits) and init write (16 bits)
    logic [FRAME_BITS-1:0] tx_shift;
    logic [FRAME_BITS-1:0] rx_shift;
    logic [15:0]           init_shift;  // 16-bit init TX

    // ---- Init output logic -------------------------------------
    assign spi_sclk = sclk_r;
    // MOSI driven from init_shift during init states, tx_shift otherwise
    assign spi_mosi = (state == INIT_SHIFT) ? init_shift[15]
                                             : tx_shift[FRAME_BITS-1];

    // ---- Main FSM ----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= INIT_START;
            wait_cnt   <= '0;
            half_cnt   <= '0;
            bit_cnt    <= '0;
            sclk_r     <= 1'b1;
            spi_cs_n   <= 1'b1;
            tx_shift   <= '0;
            rx_shift   <= '0;
            init_shift <= '0;
            x_data     <= '0;
            y_data     <= '0;
            z_data     <= '0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            case (state)

                // --------------------------------------------------
                // One-time init: write 0x08 to POWER_CTL (0x2D)
                // --------------------------------------------------
                INIT_START: begin
                    init_shift <= INIT_TX;
                    bit_cnt    <= '0;
                    half_cnt   <= '0;
                    sclk_r     <= 1'b1;
                    spi_cs_n   <= 1'b0;
                    state      <= INIT_SHIFT;
                end

                INIT_SHIFT: begin
                    if (half_cnt == HALF - 1) begin
                        half_cnt <= '0;
                        sclk_r   <= ~sclk_r;
                        if (sclk_r == 1'b1) begin
                            // Leading edge (HIGH→LOW): SCLK falls; MOSI holds current bit
                            // (TX advances on the trailing edge so data is stable here)
                        end else begin
                            // Trailing edge (LOW→HIGH): slave captures; advance TX and count
                            init_shift <= {init_shift[14:0], 1'b0};
                            if (bit_cnt == INIT_BITS - 1) begin
                                // Last bit done. Reset half_cnt so INIT_DONE can reuse
                                // it to time the CS_N hold (t_CSH >= 100 ns).
                                half_cnt <= '0;
                                state    <= INIT_DONE;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    end else begin
                        half_cnt <= half_cnt + 1;
                    end
                end

                // Hold CS_N low for one full half-period (HALF × 20 ns = 250 ns)
                // before deasserting. ADXL345 requires t_CSH >= 100 ns.
                INIT_DONE: begin
                    sclk_r <= 1'b1;  // SCLK idles high (Mode 3)
                    if (half_cnt == HALF - 1) begin
                        // 250 ns elapsed — safe to release CS_N
                        spi_cs_n <= 1'b1;
                        wait_cnt <= '0;
                        state    <= WAIT;
                    end else begin
                        half_cnt <= half_cnt + 1;
                    end
                end

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
                // SPI Mode 3 (CPOL=1, CPHA=1):
                //   - Data is held stable on MOSI from the falling edge to the rising edge.
                //   - Slave captures MOSI on the rising edge (trailing).
                //   - Master advances TX on the rising edge so the NEXT bit is ready
                //     before the NEXT falling edge.
                //   Pre-loaded MSB (in START) is valid on MOSI before the first falling edge,
                //   captured by the slave on the first rising edge — correct Mode 3 behaviour.
                SHIFT: begin
                    if (half_cnt == HALF - 1) begin
                        half_cnt <= '0;
                        sclk_r   <= ~sclk_r;

                        if (sclk_r == 1'b1) begin
                            // Leading edge (HIGH→LOW): SCLK falls; MOSI holds current bit stable
                        end else begin
                            // Trailing edge (LOW→HIGH): sample RX and advance TX to next bit
                            rx_shift <= {rx_shift[FRAME_BITS-2:0], spi_miso};
                            tx_shift <= {tx_shift[FRAME_BITS-2:0], 1'b0};
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
                    // *** DEVID CHECK: rx_shift[47:40] = first response byte (DEVID = 0xE5 = 229)
                    // If x_data shows 229 on OLED, SPI read path is working.
                    x_data     <= {8'b0, rx_shift[47:40]};  // DEVID in low byte
                    y_data     <= '0;
                    z_data     <= '0;
                    data_valid <= 1'b1;
                    state      <= WAIT;
                end

                default: state <= INIT_START;

            endcase
        end
    end

endmodule
