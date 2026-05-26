---
name: De10Lite Addon Peripherals
description: >
  Addon PCB analog controls — joystick, buttons, wheel. Addon PCB — LCD
  screen via Arduino header.
---

# De10Lite Addon Peripherals

## Addon PCB — Analog Input Controls (Joystick, Buttons, Wheel)

**For Future Projects**: Reading joystick, buttons, and potentiometer from the addon PCB via the DE10-Lite onboard ADC.

---

## ADC Channel Mapping

The addon PCB's controls are connected to the MAX 10 onboard ADC channels:

| ADC Channel | Control | Signal Type | Threshold Logic |
|-------------|---------|-------------|-----------------|
| `a0` | Joystick Left/Right | Analog | Left: `>0xCFF`, Right: `0x5FF–0xCFF` |
| `a1` | Joystick Up/Down | Analog | Up: `>0xCFF`, Down: `0x5FF–0xCFF` |
| `a2` | Select / Start | Shared analog | Select: `>0xCFF`, Start: `0x5FF–0xCFF` |
| `a3` | Button A | Digital-like | Pressed: `<2048` (0x800) |
| `a4` | Button B | Digital-like | Pressed: `<2048` (0x800) |
| `a5` | Wheel (Potentiometer) | Continuous analog | Raw 12-bit value (0–4095) |

## ADC FSM (analog_input.sv)

Reads all 6 channels sequentially via the Qsys ADC IP block:

```systemverilog
// One-hot encoded FSM states
localparam IDLE    = 12'b000000000001;
localparam WRITE_0 = 12'b000000000010;
localparam WRITE_1 = 12'b000000000100;
localparam READ_0  = 12'b000000001000;
localparam READ_1  = 12'b000000010000;
// ... through READ_5

// Avalon-MM interface to Qsys ADC IP
always @(posedge clk or negedge resetN) begin
    if (!resetN) state <= IDLE;
    else if (!adc_wait_request)  // Respect Avalon wait
        state <= next_state;
end
```

**Key**: Always handle `adc_wait_request` — the Avalon bus may stall.

### Qsys ADC IP Setup

1. Open Platform Designer (Qsys)
2. Add: Modular ADC Core
3. Configure: 6 channels, sequential mode
4. Generate: Creates `adc.v` wrapper with Avalon-MM interface
5. Instantiate: `adc u0 (.CLOCK(clk), .RESET(!resetN), ...)` in analog_input.sv

## Clean Periphery Control Wrapper

The `periphery_control.sv` module wraps `analog_input` and converts raw ADC to named boolean signals:

```systemverilog
module periphery_control (
    input       clk, resetN,
    output reg  A, B, Select, Start,
    output reg  Right, Left, Up, Down,
    output reg [11:0] Wheel
);

// Joystick thresholds
assign Left  = (a0 > 12'hCFF);
assign Right = (a0 > 12'h5FF) && (a0 <= 12'hCFF);
assign Up    = (a1 > 12'hCFF);
assign Down  = (a1 > 12'h5FF) && (a1 <= 12'hCFF);

// Buttons (active when voltage drops below threshold)
assign A      = (a3 < 12'h800);
assign B      = (a4 < 12'h800);
assign Select = (a2 > 12'hCFF);
assign Start  = (a2 > 12'h5FF) && (a2 <= 12'hCFF);

// Wheel is raw 12-bit
assign Wheel  = a5;
```

## LED Indicators for Debug

Map button states to LEDs for visual feedback:

```systemverilog
assign LEDR[0] = A;
assign LEDR[1] = B;
assign LEDR[2] = Select;
assign LEDR[3] = Start;
assign LEDR[4] = Right;
assign LEDR[5] = Left;
assign LEDR[6] = Up;
assign LEDR[7] = Down;
```

## Using Wheel as Position Control

The wheel (potentiometer) on `a5` maps naturally to sprite X-position:

```systemverilog
// Map 12-bit wheel (0-4095) to screen X (0-512)
// Division by 6 with boundary clamping:
wire [31:0] wheel_x = (Wheel/6 < 640-SPRITE_W) ? Wheel/6 : 640-SPRITE_W;
assign topLeft_x = wheel_x;
```

## Seven-Segment Wheel Display

Display raw wheel value on 7-segment displays:

```systemverilog
seven_segment hex0_inst (.data(Wheel[3:0]),  .seg(HEX0));
seven_segment hex1_inst (.data(Wheel[7:4]),  .seg(HEX1));
seven_segment hex2_inst (.data(Wheel[11:8]), .seg(HEX2));
```

## Integration Checklist

1. Add Qsys ADC IP to Quartus project
2. Regenerate Qsys system
3. Instantiate `analog_input` with proper clock and reset
4. Wrap with `periphery_control` for clean named signals
5. Wire LED indicators for debug
6. Test each channel independently with seven-segment display

---

## Addon PCB — LCD Screen via Arduino Header

**For Future Projects**: Connecting and driving a 480×800 LCD module through the DE10-Lite Arduino header, mirroring VGA output.

---

## Hardware Connection

The addon PCB connects to the DE10-Lite via the **Arduino header** (`ARDUINO_IO[15:0]`):

| Arduino Pin | Signal | Direction | Description |
|-------------|--------|-----------|-------------|
| `IO[7:0]` | `lcd_db[7:0]` | Out | 8-bit parallel data bus |
| `IO[8]` | `lcd_reset` | Out | LCD reset (active-low) |
| `IO[9]` | `lcd_wr` | Out | Write strobe (active-low pulse) |
| `IO[10]` | `lcd_d_c` | Out | Data/Command select (1=data, 0=command) |
| `IO[11]` | `lcd_rd` | Out | Read strobe (always HIGH — write-only) |
| `IO[12]` | `lcd_buzzer` | Out | Piezo buzzer output |
| `IO[13]` | `lcd_status_led` | Out | Status LED |

## LCD Specifications

| Parameter | Value |
|-----------|-------|
| **Resolution** | 480 × 800 pixels |
| **Interface** | 8-bit parallel (Intel 8080 style) |
| **Color depth** | 16-bit (RGB565), sent as 2 bytes per pixel |
| **Controller IC** | ILI9488 or similar |
| **Operation** | Write-only (lcd_rd always HIGH) |

## RGB Packing (VGA 4-bit → LCD 16-bit)

VGA produces 4 bits per channel; LCD needs 16-bit RGB565 packed into 2 bytes:

```systemverilog
// Byte 1 (sent first): RRRR_0_GGG
wire [7:0] lcd_byte1 = {VGA_R[3:0], 1'b0, VGA_G[3:1]};

// Byte 2 (sent second): G_00_BBBB_0
wire [7:0] lcd_byte2 = {VGA_G[0], 2'b00, VGA_B[3:0], 1'b0};
```

## LCD Controller Architecture

The lcd_ctrl module uses a **FSM-based** design:

```
IDLE → INIT_SEQUENCE → WAIT_FRAME → STREAM_PIXELS → WAIT_FRAME ...
```

### Initialization Sequence
1. Hardware reset: Pull `lcd_reset` low for >10ms, then high
2. Wait >120ms after reset
3. Send initialization commands (sleep out, display on, pixel format, orientation)
4. Each command: set `lcd_d_c=0`, write command byte, then `lcd_d_c=1` for data bytes

### Pixel Streaming
1. Detect start-of-frame from VGA v_sync
2. Set column/row window to full screen
3. Begin memory write command (0x2C)
4. For each VGA pixel: send `lcd_byte1`, then `lcd_byte2`
5. Toggle `lcd_wr` low then high for each byte (write strobe)

## Integration

```systemverilog
lcd_ctrl lcd_inst (
    .clk(clk_100),           // Use 100 MHz for fast LCD writes
    .resetN(resetN),
    .start(lcd_start),        // Manual or auto start
    // VGA capture inputs
    .Red(VGA_R), .Green(VGA_G), .Blue(VGA_B),
    .h_sync(VGA_HS), .v_sync(VGA_VS),
    .disp_ena(disp_ena),
    .column(column), .row(row),
    // LCD output pins
    .lcd_db(ARDUINO_IO[7:0]),
    .lcd_reset(ARDUINO_IO[8]),
    .lcd_wr(ARDUINO_IO[9]),
    .lcd_d_c(ARDUINO_IO[10]),
    .lcd_rd(ARDUINO_IO[11])
);
```

## Key Design Notes

- Use **100 MHz clock** for LCD — faster writes needed to keep up with VGA frame rate
- LCD FSM uses **Altera recommended enum-based state machine** encoding
- `lcd_rd` is always HIGH (write-only operation)
- LCD init requires precise timing delays (use counter-based waits, NOT blocking loops)
- Manual start recommended: tie to `SW[0]` so LCD init only runs after VGA is stable
