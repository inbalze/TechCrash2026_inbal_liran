// =============================================================
// CrashTech VLSI-2026 — Challenge 2: 3D Cube Tilt
// cube_tilt_top.sv  —  Top-level module
//
// Flow:
//   50 MHz clk → adxl345_spi → (data_valid pulse) → uart_tx_framed
//   The UART TX fires every time the SPI poll returns fresh data.
//
// ADXL345 SPI (onboard chip, dedicated pins, NOT Arduino header):
//   GSENSOR_CS_N  → PIN_AB16
//   GSENSOR_SCLK  → PIN_AB15
//   GSENSOR_SDO   → PIN_V11  (MOSI)
//   GSENSOR_SDI   → PIN_V12  (MISO)
//   GSENSOR_INT[0]→ PIN_Y13  (interrupt — unused here, tri-state)
//   GSENSOR_INT[1]→ PIN_AB17 (interrupt — unused here, tri-state)
//
// UART TX → ARDUINO_IO[1] (PIN_AB6) → ESP32 GPIO33
//
// LED tilt indicators (active-high):
//   LEDR[9]   = tilt LEFT   (X < -200)
//   LEDR[8]   = tilt RIGHT  (X >  200)
//   LEDR[4]   = tilt BACK   (Y < -200)
//   LEDR[3]   = tilt FRONT  (Y >  200)
//   LEDR[0]   = data heartbeat (toggles on every valid sample)
// =============================================================

module cube_tilt_top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,

    // ADXL345 dedicated pins
    output          GSENSOR_CS_N,
    output          GSENSOR_SCLK,
    output          GSENSOR_SDO,
    input           GSENSOR_SDI,
    input   [2:1]   GSENSOR_INT,

    // Arduino header (UART TX only)
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[0];

    // ---- Arduino header IO ----------------------------------------
    wire uart_tx_wire;
    assign ARDUINO_IO[0]    = 1'bz;
    assign ARDUINO_IO[1]    = uart_tx_wire;
    assign ARDUINO_IO[15:2] = 14'bz;
    assign ARDUINO_RESET_N  = 1'bz;

    // Unused GSENSOR_INT
    // (inputs, nothing to drive)

    // ---- 7-segment: blank all ---------------------------------
    assign HEX0 = 8'hFF;
    assign HEX1 = 8'hFF;
    assign HEX2 = 8'hFF;
    assign HEX3 = 8'hFF;
    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    // ---- SPI → ADXL345 ----------------------------------------
    logic signed [15:0] x_raw, y_raw, z_raw;
    logic               data_valid;

    adxl345_spi #(
        .CLK_HZ  (50_000_000),
        .SPI_HZ  (2_000_000)
    ) u_spi (
        .clk       (clk),
        .rst_n     (rst_n),
        .spi_cs_n  (GSENSOR_CS_N),
        .spi_sclk  (GSENSOR_SCLK),
        .spi_mosi  (GSENSOR_SDO),
        .spi_miso  (GSENSOR_SDI),
        .x_data    (x_raw),
        .y_data    (y_raw),
        .z_data    (z_raw),
        .data_valid(data_valid)
    );

    // ---- UART TX ----------------------------------------------
    uart_tx_framed #(
        .CLKS_PER_BIT(434)  // 50_000_000 / 115200 ≈ 434
    ) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .trigger (data_valid),
        .x_data  (x_raw),
        .y_data  (y_raw),
        .z_data  (z_raw),
        .tx      (uart_tx_wire),
        .busy    ()
    );

    // ---- LED tilt mapper --------------------------------------
    // Threshold ~200 counts ≈ ~0.39g in ±2g range (resolution 3.9 mg/LSB)
    localparam signed [15:0] THRESH = 16'sd200;

    logic heart;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) heart <= 1'b0;
        else if (data_valid) heart <= ~heart;
    end

    assign LEDR[9]   = (x_raw < -THRESH);   // tilt left
    assign LEDR[8]   = (x_raw >  THRESH);   // tilt right
    assign LEDR[7:5] = 3'b000;
    assign LEDR[4]   = (y_raw < -THRESH);   // tilt back
    assign LEDR[3]   = (y_raw >  THRESH);   // tilt front
    assign LEDR[2:1] = 2'b00;
    assign LEDR[0]   = heart;               // data heartbeat

endmodule
