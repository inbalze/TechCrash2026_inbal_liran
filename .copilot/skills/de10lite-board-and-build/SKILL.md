---
name: De10Lite Board And Build
description: >
  Quick-start arcade game template for DE10-Lite. DE10-Lite board
  overview, pinout, and hardware specs. FPGA design patterns cookbook
  for DE10-Lite projects. Digital clock project — FSM, BCD, and
  7-segment display. Hack CPU on DE10-Lite (nand2tetris system).
  Pipeline accumulator — single-adder FSM design pattern. Quartus build,
  program, and simulation flow for DE10-Lite. Reusable IP blocks and
  library modules for DE10-Lite.
---

# De10Lite Board And Build

---

## CrashTech VLSI-2026 — FPGA BKM (Verified Reference)

> Authoritative reference for all FPGA projects in this repo.  
> All commands, pin assignments, and flows verified working on the actual CrashTech DE10-Lite kit (May 2026).

### Board Identity

| Field | Value |
|-------|-------|
| Board | DE10-Lite |
| Device | Intel MAX 10 — `10M50DAF484C7G` |
| Clock | 50 MHz on `MAX10_CLK1_50` (PIN_P11) |
| Toolchain | Quartus Prime Lite 17.1 |
| Programmer | USB-Blaster (detected as `USB-Blaster [USB-0]`) |
| Driver path | `C:\intelFPGA_lite\17.1\quartus\drivers\usb-blaster` |

### Project File Templates

**Minimal `.qpf`:**
```
QUARTUS_VERSION = "17.1"
DATE = "2026.05.04"
PROJECT_REVISION = "my_project"
```

**Minimal `.qsf` header** (copy and extend):
```tcl
set_global_assignment -name FAMILY "MAX 10"
set_global_assignment -name DEVICE 10M50DAF484C7G
set_global_assignment -name TOP_LEVEL_ENTITY my_top
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name SYSTEMVERILOG_FILE src/my_top.sv
set_global_assignment -name LAST_QUARTUS_VERSION "17.1.0 Lite Edition"
```

### Full DE10-Lite Pin Assignments (Copy-Paste Ready)

```tcl
# ---- Clock ----
set_location_assignment PIN_P11 -to MAX10_CLK1_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MAX10_CLK1_50

# ---- Switches SW[9:0] ----
set_location_assignment PIN_C10 -to SW[0]
set_location_assignment PIN_C11 -to SW[1]
set_location_assignment PIN_D12 -to SW[2]
set_location_assignment PIN_C12 -to SW[3]
set_location_assignment PIN_A12 -to SW[4]
set_location_assignment PIN_B12 -to SW[5]
set_location_assignment PIN_A13 -to SW[6]
set_location_assignment PIN_A14 -to SW[7]
set_location_assignment PIN_B14 -to SW[8]
set_location_assignment PIN_F15 -to SW[9]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[*]

# ---- Keys KEY[1:0] (active-low) ----
set_location_assignment PIN_B8 -to KEY[0]
set_location_assignment PIN_A7 -to KEY[1]
set_instance_assignment -name IO_STANDARD "3.3 V SCHMITT TRIGGER" -to KEY[*]

# ---- Red LEDs LEDR[9:0] ----
set_location_assignment PIN_A8  -to LEDR[0]
set_location_assignment PIN_A9  -to LEDR[1]
set_location_assignment PIN_A10 -to LEDR[2]
set_location_assignment PIN_B10 -to LEDR[3]
set_location_assignment PIN_D13 -to LEDR[4]
set_location_assignment PIN_C13 -to LEDR[5]
set_location_assignment PIN_E14 -to LEDR[6]
set_location_assignment PIN_D14 -to LEDR[7]
set_location_assignment PIN_A11 -to LEDR[8]
set_location_assignment PIN_B11 -to LEDR[9]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDR[*]

# ---- 7-Segment HEX0..HEX5 (active-low, [7]=dp) ----
set_location_assignment PIN_C14 -to HEX0[0]
set_location_assignment PIN_E15 -to HEX0[1]
set_location_assignment PIN_C15 -to HEX0[2]
set_location_assignment PIN_C16 -to HEX0[3]
set_location_assignment PIN_E16 -to HEX0[4]
set_location_assignment PIN_D17 -to HEX0[5]
set_location_assignment PIN_C17 -to HEX0[6]
set_location_assignment PIN_D15 -to HEX0[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX0[*]

set_location_assignment PIN_C18 -to HEX1[0]
set_location_assignment PIN_D18 -to HEX1[1]
set_location_assignment PIN_E18 -to HEX1[2]
set_location_assignment PIN_B16 -to HEX1[3]
set_location_assignment PIN_A17 -to HEX1[4]
set_location_assignment PIN_A18 -to HEX1[5]
set_location_assignment PIN_B17 -to HEX1[6]
set_location_assignment PIN_A16 -to HEX1[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX1[*]

set_location_assignment PIN_B20 -to HEX2[0]
set_location_assignment PIN_A20 -to HEX2[1]
set_location_assignment PIN_B19 -to HEX2[2]
set_location_assignment PIN_A21 -to HEX2[3]
set_location_assignment PIN_B21 -to HEX2[4]
set_location_assignment PIN_C22 -to HEX2[5]
set_location_assignment PIN_B22 -to HEX2[6]
set_location_assignment PIN_A19 -to HEX2[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX2[*]

set_location_assignment PIN_F21 -to HEX3[0]
set_location_assignment PIN_E22 -to HEX3[1]
set_location_assignment PIN_E21 -to HEX3[2]
set_location_assignment PIN_C19 -to HEX3[3]
set_location_assignment PIN_C20 -to HEX3[4]
set_location_assignment PIN_D19 -to HEX3[5]
set_location_assignment PIN_E17 -to HEX3[6]
set_location_assignment PIN_D22 -to HEX3[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX3[*]

set_location_assignment PIN_F18 -to HEX4[0]
set_location_assignment PIN_E20 -to HEX4[1]
set_location_assignment PIN_E19 -to HEX4[2]
set_location_assignment PIN_J18 -to HEX4[3]
set_location_assignment PIN_H19 -to HEX4[4]
set_location_assignment PIN_F19 -to HEX4[5]
set_location_assignment PIN_F20 -to HEX4[6]
set_location_assignment PIN_F17 -to HEX4[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX4[*]

set_location_assignment PIN_J20 -to HEX5[0]
set_location_assignment PIN_K20 -to HEX5[1]
set_location_assignment PIN_L18 -to HEX5[2]
set_location_assignment PIN_N18 -to HEX5[3]
set_location_assignment PIN_M20 -to HEX5[4]
set_location_assignment PIN_N19 -to HEX5[5]
set_location_assignment PIN_N20 -to HEX5[6]
set_location_assignment PIN_L19 -to HEX5[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX5[*]

# ---- Arduino Header — ARDUINO_IO[15:0] ----
# ARDUINO_IO[0] — CrashTech: UART RX from ESP32 (GPIO16)
# ARDUINO_IO[1] — CrashTech: UART TX to ESP32 (GPIO17)
# GND pin on Arduino header — connect ESP32 GND here
set_location_assignment PIN_AB5  -to ARDUINO_IO[0]
set_location_assignment PIN_AB6  -to ARDUINO_IO[1]
set_location_assignment PIN_AB7  -to ARDUINO_IO[2]
set_location_assignment PIN_AB8  -to ARDUINO_IO[3]
set_location_assignment PIN_AB9  -to ARDUINO_IO[4]
set_location_assignment PIN_Y10  -to ARDUINO_IO[5]
set_location_assignment PIN_AA11 -to ARDUINO_IO[6]
set_location_assignment PIN_AA12 -to ARDUINO_IO[7]
set_location_assignment PIN_AB17 -to ARDUINO_IO[8]
set_location_assignment PIN_AA17 -to ARDUINO_IO[9]
set_location_assignment PIN_AB19 -to ARDUINO_IO[10]
set_location_assignment PIN_AA19 -to ARDUINO_IO[11]
set_location_assignment PIN_Y19  -to ARDUINO_IO[12]
set_location_assignment PIN_AB20 -to ARDUINO_IO[13]
set_location_assignment PIN_AB21 -to ARDUINO_IO[14]
set_location_assignment PIN_AA20 -to ARDUINO_IO[15]
set_location_assignment PIN_F16  -to ARDUINO_RESET_N
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_IO[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ARDUINO_RESET_N
```

### 7-Segment Encoding (Active-Low)

Bit order: `[7]=dp [6]=g [5]=f [4]=e [3]=d [2]=c [1]=b [0]=a`  
Set `1` = segment OFF, `0` = segment ON.

| Char | 8'b value | Hex |
|------|-----------|-----|
| 0 | `8'b1100_0000` | C0 |
| 1 | `8'b1111_1001` | F9 |
| 2 | `8'b1010_0100` | A4 |
| 3 | `8'b1011_0000` | B0 |
| 4 | `8'b1001_1001` | 99 |
| 5 | `8'b1001_0010` | 92 |
| 6 | `8'b1000_0010` | 82 |
| 7 | `8'b1111_1000` | F8 |
| 8 | `8'b1000_0000` | 80 |
| 9 | `8'b1001_0000` | 90 |
| A | `8'b1000_1000` | 88 |
| b | `8'b1000_0011` | 83 |
| C | `8'b1100_0110` | C6 |
| d | `8'b1010_0001` | A1 |
| E | `8'b1000_0110` | 86 |
| F | `8'b1000_1110` | 8E |
| H | `8'b1000_1001` | 89 |
| i | `8'b1100_1111` | CF |
| L | `8'b1100_0111` | C7 |
| n | `8'b1010_1011` | AB |
| o | `8'b1010_0011` | A3 |
| P | `8'b1000_1100` | 8C |
| r | `8'b1010_1111` | AF |
| U | `8'b1100_0001` | C1 |
| blank | `8'b1111_1111` | FF |
| `-` | `8'b1011_1111` | BF |

### CLI Compile & Program (PowerShell — Verified)

```powershell
# Compile (from project folder containing .qsf/.qpf)
cd c:\Projects\TechCrash2026\demos\alive_test\fpga
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe" --flow compile alive_test

# Check .sof was produced
Test-Path "output_files\alive_test.sof"

# List available programmers (should show "USB-Blaster [USB-0]")
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" --list

# Program (volatile SRAM — fast, lost on power-off)
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" -c "USB-Blaster [USB-0]" -m JTAG -o "P;output_files\alive_test.sof"
```

> **Note on cable name**: Always use `"USB-Blaster [USB-0]"` (with the `[USB-0]` suffix). Using just `"USB-Blaster"` returns error 87.

### UART in RTL — Verified Pattern (9600 baud, 50 MHz)

```systemverilog
// CLKS_PER_BIT = 50_000_000 / 9600 = 5208
// ARDUINO_IO[0] = input  (RX from ESP32)
// ARDUINO_IO[1] = output (TX to ESP32)

assign ARDUINO_IO[0]  = 1'bz;            // input mode
assign uart_rx_in     = ARDUINO_IO[0];
assign ARDUINO_IO[1]  = uart_tx_out;
assign ARDUINO_IO[15:2] = 14'bz;         // unused = high-Z

// Double-flop sync on RX input (mandatory for async inputs)
always @(posedge clk) begin
    rx_d1 <= uart_rx_in;
    rx_d2 <= rx_d1;
end
```

### Verified Status (May 2026)

| Feature | Status | Notes |
|---------|--------|-------|
| Compile via CLI (`quartus_sh`) | ✅ Working | `--flow compile <project>` |
| Program via CLI (`quartus_pgm`) | ✅ Working | Cable name = `"USB-Blaster [USB-0]"` |
| `LEDR[9:0]` | ✅ Working | Sweep pattern |
| `HEX5..HEX0` | ✅ Working | "ALivE " verified on hardware |
| `SW[9:0]` | ✅ Working | |
| `KEY[1:0]` | ✅ Working | Active-low reset |
| `GPIO[0]/[1]` | ✅ Working | UART TX/RX to ESP32 via Arduino header (ARDUINO_IO[0]/[1]) |

### Reference Demo

See `demos/alive_test/fpga/` — canonical working project with full QSF.

---

## Quartus Prime Lite 17.1 — Complete Installation Guide

Everything you need to design, compile, simulate, and program the DE10-Lite FPGA. Follow these steps exactly.

---

### Step 1: Download Quartus Prime Lite 17.1

1. Go to: **https://www.intel.com/content/www/us/en/software-kit/669444/intel-quartus-prime-lite-edition-design-software-version-17-1-for-windows.html**
2. If the direct link doesn't work, go to https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime/resource.html and select **Version 17.1** under "Quartus Prime Lite"
3. Download the **Combined Files** tab option (single ~5 GB installer that includes Quartus + ModelSim + device support), OR download individually:
   - **Quartus Prime Lite Edition** (main IDE)
   - **ModelSim-Intel FPGA Edition** (simulation)
   - **MAX 10 device support** (required for the DE10-Lite board)

> **Why version 17.1?** It is the last version that bundles ModelSim-Altera for free and has proven stability with the DE10-Lite (MAX 10) device. Newer versions work but require separate ModelSim licensing.

### Step 2: Install Quartus Prime Lite 17.1

1. Run the downloaded installer (`QuartusLiteSetup-17.1.0.590-windows.exe` or similar)
2. Choose installation directory: **`C:\intelFPGA_lite\17.1\`** (default — keep it)
3. Select components:
   - [x] Quartus Prime Lite Edition
   - [x] ModelSim-Intel FPGA Edition (simulation)
   - [x] MAX 10 FPGA device support (**required**)
   - [ ] Other device families — not needed, skip to save space
4. Click Install and wait (~10–20 minutes depending on your system)
5. When done, verify these paths exist:

| Tool | Path |
|------|------|
| Quartus IDE | `C:\intelFPGA_lite\17.1\quartus\bin64\quartus.exe` |
| Quartus Shell (CLI) | `C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe` |
| Quartus Programmer | `C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe` |
| ModelSim | `C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem\vsim.exe` |

### Step 3: Install the USB-Blaster Driver

The USB-Blaster driver lets your PC communicate with the DE10-Lite over USB for programming. **Without it, you cannot load designs onto the FPGA.**

1. Connect the DE10-Lite to your PC via the USB cable
2. Windows may show "Unknown device" or "USB-Blaster" in Device Manager — either way, proceed:
3. Open **Device Manager** (right-click Start → Device Manager)
4. Find the unrecognized device — it will be under "Other devices" or "Universal Serial Bus controllers"
5. Right-click → **Update driver** → **Browse my computer for drivers**
6. Browse to: **`C:\intelFPGA_lite\17.1\quartus\drivers\usb-blaster`**
7. Click Next → Windows will install the driver
8. Verify: Device Manager should now show **"Altera USB-Blaster"** under "Universal Serial Bus controllers"

**Alternative (auto-detect):** Open Quartus → Tools → Programmer → Hardware Setup → click "Auto Detect". If it finds the USB-Blaster, the driver is working.

**Troubleshooting driver issues:**
- If Windows refuses the unsigned driver: temporarily disable "Driver Signature Enforcement" in Windows advanced startup options
- If the device doesn't appear: try a different USB port (use USB 2.0 if available, avoid USB hubs)
- If using Windows 11: the driver from 17.1 works — just point to the same folder above

### Step 4: Verify the Full Toolchain

Run these checks to confirm everything is installed:

```powershell
# Check Quartus
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe" --version

# Check ModelSim
& "C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem\vsim.exe" -version

# Check Programmer can see the board (board must be connected)
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" --auto
```

Expected output from `quartus_sh --version`:
```
Quartus Prime Shell
Version 17.1.0 Build 590  ...
```

### Step 5: Quick Smoke Test — LED Blink

Verify the entire flow (design → compile → program) with a minimal project:

1. Create a folder: `C:\FPGA\led_test\`
2. Create file **`led_test.sv`**:

```systemverilog
module led_test (
    input        MAX10_CLK1_50,
    input  [9:0] SW,
    output [9:0] LEDR
);
    // Switches directly control LEDs
    assign LEDR = SW;
endmodule
```

3. Create file **`led_test.qpf`**:
```tcl
QUARTUS_VERSION = "17.1"
PROJECT_REVISION = "led_test"
```

4. Create file **`led_test.qsf`**:
```tcl
set_global_assignment -name FAMILY "MAX 10 FPGA"
set_global_assignment -name DEVICE 10M50DAF484C7G
set_global_assignment -name TOP_LEVEL_ENTITY led_test
set_global_assignment -name SYSTEMVERILOG_FILE led_test.sv
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85

# Clock
set_location_assignment PIN_P11 -to MAX10_CLK1_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MAX10_CLK1_50

# Switches
set_location_assignment PIN_C10 -to SW[0]
set_location_assignment PIN_C11 -to SW[1]
set_location_assignment PIN_D12 -to SW[2]
set_location_assignment PIN_C12 -to SW[3]
set_location_assignment PIN_A12 -to SW[4]
set_location_assignment PIN_B12 -to SW[5]
set_location_assignment PIN_A13 -to SW[6]
set_location_assignment PIN_A14 -to SW[7]
set_location_assignment PIN_B14 -to SW[8]
set_location_assignment PIN_F15 -to SW[9]

# LEDs
set_location_assignment PIN_A8  -to LEDR[0]
set_location_assignment PIN_A9  -to LEDR[1]
set_location_assignment PIN_A10 -to LEDR[2]
set_location_assignment PIN_B10 -to LEDR[3]
set_location_assignment PIN_D13 -to LEDR[4]
set_location_assignment PIN_C13 -to LEDR[5]
set_location_assignment PIN_E14 -to LEDR[6]
set_location_assignment PIN_D14 -to LEDR[7]
set_location_assignment PIN_A11 -to LEDR[8]
set_location_assignment PIN_B11 -to LEDR[9]

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDR[*]
```

5. Compile:
```powershell
cd C:\FPGA\led_test
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe" --flow compile led_test
```

6. Program the board:
```powershell
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" -m jtag -o "P;output_files/led_test.sof@1"
```

7. **Test:** Flip the slide switches on the DE10-Lite — the corresponding LEDs should light up. If they do, your entire toolchain is working end-to-end.

---

## DE10-Lite Board Overview & Pin Mapping

**For Future Projects**: Complete reference for the Intel DE10-Lite (MAX 10 FPGA) board — pin assignments, peripherals, and golden top module pattern.

---

## Board Hardware

| Resource | Details |
|----------|---------|
| **FPGA** | Intel MAX 10 (10M50DAF484C7G) |
| **Clock** | 50 MHz oscillator (`MAX10_CLK1_50`) |
| **Switches** | 10× slide switches `SW[9:0]` (active-high, 3.3V LVTTL) |
| **Keys** | 2× push-buttons `KEY[0]`, `KEY[1]` (active-low, Schmitt trigger) |
| **LEDs** | 10× red LEDs `LEDR[9:0]` |
| **7-Segment** | 6× displays `HEX[5:0]`, each 8 bits (active-low, includes DP) |
| **VGA** | 4-bit per channel: `VGA_R[3:0]`, `VGA_G[3:0]`, `VGA_B[3:0]`, `VGA_HS`, `VGA_VS` |
| **Arduino Header** | 16 I/O: `ARDUINO_IO[15:0]`, active-low reset: `ARDUINO_RESET_N` |
| **GPIO** | 36 pins: `GPIO[35:0]` |
| **ADC** | 6 analog channels (12-bit, onboard MAX 10 ADC) |
| **SDRAM** | 64MB (optional usage, 16-bit bus) |
| **Accelerometer** | Onboard ADXL345 via SPI |

## Golden Top Module Pattern

All DE10-Lite projects use the same port declaration:

```systemverilog
module top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output  [3:0]   VGA_R, VGA_G, VGA_B,
    output          VGA_HS, VGA_VS,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

From working projects:
- `SW[9]` → `resetN` (active-low reset via slide switch)
- `SW[8:7]` → `cfg[1:0]` (display mode selection)
- `SW[6]` → CPU reset / secondary function
- `SW[0]` → Manual start / debug trigger

## Common Instantiation Hierarchy

```
top_module
├── pll25          (50→25/50/100 MHz)
├── vga_ctrl       (VGA display hub)
│   ├── vga_controller  (sync gen)
│   ├── text_screen     (80×60 chars)
│   ├── game_unit       (sprite engine)
│   └── pattern_gen     (test bars)
├── lcd_ctrl       (addon PCB LCD mirror)
├── analog_input   (6-ch ADC FSM)
├── periphery_control   (joystick/buttons)
├── seven_segment  (hex decoder ×6)
└── one_sec        (1-second timer)
```

## Quartus Project Setup

- **Tool**: Intel Quartus Prime Lite 17.1 (`C:\intelFPGA_lite\17.1\`)
- **Project files**: `.qpf` (project), `.qsf` (settings + pin assignments), `.qar` (archive)
- **IP cores**: Generated via Qsys (Platform Designer)
- **Compilation**: Full compilation flow: Analysis → Fitter → Assembler → Timing

---

## DE10-Lite Quartus Build, Program & Simulation Flow

**For Future Projects**: Complete step-by-step guide for compiling, programming (burning), and simulating DE10-Lite FPGA projects using Quartus Prime Lite and ModelSim.

---

## Toolchain Paths

| Tool | Path |
|------|------|
| **Quartus Prime Lite 17.1** | `C:\intelFPGA_lite\17.1\quartus\bin64\` |
| **ModelSim-Altera** | `C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem\` |
| **Quartus Shell** | `quartus_sh.exe` (command-line compilation) |
| **Quartus Programmer** | `quartus_pgm.exe` (JTAG programming) |
| **Quartus CPF** | `quartus_cpf.exe` (file conversion SOF↔POF) |
| **Platform Designer** | `qsys-edit.exe` (IP core generation) |

## Project File Structure

Every Quartus project needs at minimum:

```
project_dir/
├── top.qpf                    # Project file (names the project)
├── top.qsf                    # Settings: device, pins, source files
├── DE10_LITE_Golden_Top.v     # Top-level module
├── src/                       # RTL source files
├── output_files/              # Compilation output (auto-generated)
│   ├── top.sof                # SRAM Object File (volatile)
│   ├── top.pof                # Programmer Object File (persistent)
│   └── top.fit.summary        # Fitter report
├── sim/                       # Simulation scripts
│   ├── run_sim.do             # ModelSim .do script
│   └── run_tests.bat          # Batch launcher
└── db/                        # Quartus database (auto-generated)
```

### QPF File (Minimal)

```tcl
QUARTUS_VERSION = "17.1"
PROJECT_REVISION = "top"
```

The `PROJECT_REVISION` must match the `.qsf` filename (e.g., `top.qsf` → `"top"`).

### QSF File Key Assignments

```tcl
# Device
set_global_assignment -name FAMILY "MAX 10 FPGA"
set_global_assignment -name DEVICE 10M50DAF484C6GES
set_global_assignment -name TOP_LEVEL_ENTITY DE10_LITE_Golden_Top

# Source files (one per RTL file)
set_global_assignment -name VERILOG_FILE DE10_LITE_Golden_Top.v
set_global_assignment -name VERILOG_FILE src/my_module.v
set_global_assignment -name SYSTEMVERILOG_FILE src/my_module.sv

# Qsys IP cores (reference the .qip file)
set_global_assignment -name QIP_FILE pll25.qip
set_global_assignment -name QIP_FILE adc/synthesis/adc.qip
set_global_assignment -name QIP_FILE font_rom.qip

# Output directory
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files

# Timing / thermal
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"

# Pin assignments — see bkm-de10lite-board-overview for full list
# Example:
set_location_assignment PIN_P11 -to MAX10_CLK1_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to MAX10_CLK1_50
```

### Multiple QSF Revisions

You can maintain multiple `.qsf` files in the same project directory as named snapshots:

| Convention | Purpose |
|------------|---------|
| `rev5-initial_working.qsf` | Known-good baseline |
| `lcd-working.qsf` | After LCD addon integration |
| `lcd_connect.qsf` | LCD pin connection variant |
| `CPU_added.qsf` | After Hack CPU integration |
| `my_cpu.qsf` | Active development revision |

Switch active revision in the `.qpf`:
```tcl
PROJECT_REVISION = "lcd-working"
```

---

## Compilation (Full Flow)

### Command-Line Compilation

```bat
@echo off
set QUARTUS_PATH="C:\intelFPGA_lite\17.1\quartus\bin64"

REM Full flow: Analysis → Fitter → Assembler → Timing Analyzer
%QUARTUS_PATH%\quartus_sh --flow compile top
```

The `--flow compile` argument runs all four stages:
1. **Analysis & Synthesis** (`quartus_map`) — parses RTL, infers logic
2. **Fitter** (`quartus_fit`) — place & route onto the MAX 10 device
3. **Assembler** (`quartus_asm`) — generates `.sof` programming file
4. **Timing Analyzer** (`quartus_sta`) — static timing analysis

You can also run stages individually:
```bat
%QUARTUS_PATH%\quartus_map --read_settings_files=on top
%QUARTUS_PATH%\quartus_fit --read_settings_files=on top
%QUARTUS_PATH%\quartus_asm top
%QUARTUS_PATH%\quartus_sta top
```

### run.bat Template (Proven Pattern)

```bat
@echo off
echo Starting Quartus compilation for DE10_LITE_Golden_Top project...
echo Target Device: MAX 10 FPGA (10M50DAF484C6GES)
echo Top Level Entity: DE10_LITE_Golden_Top
echo.

REM Optional: clean previous outputs
if exist output_files (
    echo Cleaning previous output files...
    rmdir /s /q output_files
)

set QUARTUS_PATH="C:\intelFPGA_lite\17.1\quartus\bin64"

echo Starting full compilation flow...
%QUARTUS_PATH%\quartus_sh --flow compile top

if %ERRORLEVEL% EQU 0 (
    echo.
    echo   COMPILATION COMPLETED SUCCESSFULLY
    echo   Programming file: output_files/top.sof
) else (
    echo.
    echo   COMPILATION FAILED WITH ERRORS
    echo   Check compilation reports in output_files/
    exit /b %ERRORLEVEL%
)
```

---

## Programming the Board ("Burning")

### Prerequisites

- USB-Blaster driver installed (comes with Quartus)
- DE10-Lite connected via USB cable
- Board powered on (USB provides power)

### Volatile Programming (SRAM — lost on power-off)

```bat
set QUARTUS_PATH="C:\intelFPGA_lite\17.1\quartus\bin64"
%QUARTUS_PATH%\quartus_pgm -m jtag -o "P;output_files/top.sof@1"
```

| Flag | Meaning |
|------|---------|
| `-m jtag` | Use JTAG interface (USB-Blaster) |
| `-o "P;..."` | Program operation |
| `@1` | Device index 1 on the JTAG chain |

This is the **fast** method — takes seconds. Use during development.

### Persistent Programming (Flash — survives power cycles)

```bat
REM Step 1: Convert SOF to POF
%QUARTUS_PATH%\quartus_cpf -c output_files/top.sof output_files/top.pof

REM Step 2: Program the flash
%QUARTUS_PATH%\quartus_pgm -m jtag -o "P;output_files/top.pof@1"
```

Use this for **final deployment** when the board should boot with your design.

### program.bat Template

```bat
@echo off
set QUARTUS_PATH="C:\intelFPGA_lite\17.1\quartus\bin64"

if not exist output_files\top.sof (
    echo ERROR: No .sof file found. Run compilation first.
    exit /b 1
)

echo Programming DE10-Lite via USB-Blaster (JTAG)...
%QUARTUS_PATH%\quartus_pgm -m jtag -o "P;output_files/top.sof@1"

if %ERRORLEVEL% EQU 0 (
    echo   PROGRAMMING SUCCESSFUL
) else (
    echo   PROGRAMMING FAILED
    echo   Check: USB cable connected? Driver installed? Board powered?
    exit /b %ERRORLEVEL%
)
```

### Compile + Program Combined

```bat
@echo off
set QUARTUS_PATH="C:\intelFPGA_lite\17.1\quartus\bin64"

echo === COMPILE ===
%QUARTUS_PATH%\quartus_sh --flow compile top
if %ERRORLEVEL% NEQ 0 ( echo COMPILE FAILED & exit /b 1 )

echo === PROGRAM ===
%QUARTUS_PATH%\quartus_pgm -m jtag -o "P;output_files/top.sof@1"
if %ERRORLEVEL% NEQ 0 ( echo PROGRAM FAILED & exit /b 1 )

echo === DONE ===
```

---

## Simulation (ModelSim)

### ModelSim Path

```
C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem\vsim.exe
```

### ModelSim .do Script Template (Proven Pattern)

```tcl
# Quit any running simulation
quit -sim

# Create/reset work library
if {[file exists work]} { vdel -all -lib work }
vlib work

# Compile RTL
vlog -work work +acc ../src/my_module.sv

# Compile Testbench
vlog -work work +acc ../testbench/tb_my_module.sv

# Load simulation
vsim -novopt work.tb_my_module

# Add waves
add wave -divider "Clock & Reset"
add wave -hex /tb_my_module/clk
add wave -hex /tb_my_module/rst_n

add wave -divider "I/O"
add wave -hex /tb_my_module/dut/*

# Run
run -all
```

### Batch Simulation (No GUI)

```bat
set MODELSIM_PATH="C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem"
%MODELSIM_PATH%\vsim -c -do run_sim.do
```

The `-c` flag runs in console mode (no GUI). Useful for CI or batch regression.

### PowerShell Test Runner Pattern

From CoCode_clock — scan for ModelSim in common paths:

```powershell
$ModelSimPaths = @(
    "C:\intelFPGA\17.1\modelsim_ase\win32aloem\vsim.exe",
    "C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem\vsim.exe",
    "C:\ModelSim\win32aloem\vsim.exe"
)
foreach ($Path in $ModelSimPaths) {
    if (Test-Path $Path) { $VsimPath = $Path; break }
}
```

---

## MIF-Based ROM Programming (Software → Hardware)

For projects with a CPU (Hack, RISC-V), the code is loaded via `.mif` files:

1. Write assembly program (`.s` or `.asm`)
2. Assemble to `.mif` (Memory Initialization File)
3. Place `.mif` in project root (referenced by Qsys ROM IP)
4. Recompile Quartus project
5. Program the board

```bat
REM Example: assemble_for_fpga.bat
python assembler.py program.s -o program_rom.mif -s 1024
copy program_rom.mif ..\..\project_dir\program_rom.mif
```

The ROM IP core in Qsys references the `.mif` file. Changing the `.mif` requires **recompilation** — the data is baked into the bitstream.

---

## Qsys IP Core Generation

IP cores (PLL, RAM, ROM, ADC) are created in Platform Designer (Qsys):

1. Open Quartus → Tools → Platform Designer
2. Add component (e.g., ALTPLL, RAM: 2-PORT, ADC)
3. Configure parameters
4. Generate HDL → produces `.qip` file
5. Add `.qip` to project: `set_global_assignment -name QIP_FILE pll25.qip`

### Common IP Cores Used

| IP Core | QIP File | Purpose |
|---------|----------|---------|
| **ALTPLL** | `pll25.qip` | 50→25/50/100 MHz clock generation |
| **ADC** | `adc/synthesis/adc.qip` | MAX 10 onboard ADC controller |
| **RAM: 2-PORT** | `text_ram_a.qip` | Dual-port RAM (text screen, etc.) |
| **ROM: 1-PORT** | `font_rom.qip` | Font bitmap ROM |
| **ROM: 1-PORT** | `cpu_rom.qip` | CPU program ROM (.mif) |
| **RAM: 1-PORT** | `cpu_ram.qip` | CPU data RAM |
| **ROM: 1-PORT** | `lcd_cmd.qip` | LCD init command sequence |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `quartus_pgm` fails: "No device found" | Check USB cable, install USB-Blaster driver, try different USB port |
| `quartus_pgm` fails: "JTAG chain broken" | Power-cycle the board, ensure no other Quartus instance has the programmer open |
| Compilation fails: "can't find module" | Check all source files listed in `.qsf` with correct paths |
| Compilation fails: "multiple drivers" | Check for conflicting `assign` statements or multiple `always` blocks driving same signal |
| Timing violations (setup/hold) | Check `output_files/top.sta.summary` — may need to reduce clock frequency or add pipeline stages |
| `.mif` changes not reflected | Must recompile — `.mif` is baked into the SRAM bitstream |
| Pin assignment mismatch | Compare `.qsf` pin assignments against DE10-Lite manual / golden top module |
| Qsys IP "file not found" | Regenerate IP → re-generate HDL, ensure `.qip` path in `.qsf` is correct |

---

## Quick Reference: New Project Checklist

1. Copy `DE10_LITE_Golden_Top.v` (or `.sv`) from a working project
2. Copy `top.qpf` — edit `PROJECT_REVISION` if needed
3. Copy `top.qsf` — has all 400+ pin assignments already set
4. Add your source files to `.qsf`: `set_global_assignment -name SYSTEMVERILOG_FILE src/myfile.sv`
5. Generate any needed IP cores in Platform Designer → add `.qip` references
6. Write your logic modules in `src/`
7. Instantiate everything in `DE10_LITE_Golden_Top`
8. `run.bat` → compile
9. `program.bat` → burn to board
10. Test on hardware

---

## FPGA Design Patterns Cookbook (DE10-Lite)

**For Future Projects**: Cross-cutting design patterns observed across all DE10-Lite FPGA projects — timing, resets, FSMs, and common pitfalls.

---

## 1. Asynchronous Active-Low Reset

**Used in**: Every single module across all projects.

```systemverilog
always @(posedge clk or negedge resetN) begin
    if (!resetN) begin
        // Reset state
    end else begin
        // Normal operation
    end
end
```

- **DE10-Lite convention**: `SW[9]` is the system reset (active-low via slide switch)
- **KEY buttons** are also active-low with Schmitt trigger
- ALL flip-flops must have consistent reset polarity

## 2. Counter-Based Timing

Divide 50 MHz clock for slower operations:

| Desired Rate | Counter Max | Bits Needed |
|-------------|-------------|-------------|
| 1 Hz | 49,999,999 | 26 bits |
| 2 Hz | 24,999,999 | 25 bits |
| 60 Hz (frame) | 833,332 | 20 bits |
| 1 kHz | 49,999 | 16 bits |
| ~50 Hz debounce | 999,999 (~20ms) | 20 bits |

**Pattern**: Counter + pulse (single-cycle) or toggle (clock output).

## 3. Edge Detection (CDC Safe)

Sample slow signal in fast clock domain:

```systemverilog
reg signal_d;
always @(posedge clk) signal_d <= signal;
wire rising_edge  = signal && !signal_d;
wire falling_edge = !signal && signal_d;
```

**Used for**: v_sync → start_of_frame, clk_1hz in 50 MHz domain, debounced button edges.

## 4. FSM Encoding Styles

### Localparam (most common)
```systemverilog
localparam IDLE = 2'd0, RUNNING = 2'd1, DONE = 2'd2;
reg [1:0] state;
```

### One-Hot (analog_input.sv)
```systemverilog
localparam IDLE    = 12'b000000000001;
localparam WRITE_0 = 12'b000000000010;
// Faster decode, more FFs, common in FPGA
```

### Enum (lcd_ctrl.sv — Altera recommended)
```systemverilog
enum logic [3:0] {ST_IDLE, ST_INIT, ST_STREAM, ST_DONE} state;
// Best for readability, Quartus optimizes encoding
```

## 5. Pipeline Delay Buffering

When reading RAM/ROM takes N cycles, buffer the address/control signals:

```systemverilog
// 3-stage pipeline example (text_screen)
reg [9:0] pxl_x_d1, pxl_x_d2;
always @(posedge clk) begin
    pxl_x_d1 <= pxl_x;      // Delay 1: RAM read
    pxl_x_d2 <= pxl_x_d1;   // Delay 2: ROM read
end
// Use pxl_x_d2 for bit-select in cycle 3
```

## 6. Memory-Mapped I/O

Address decode pattern for CPU-attached peripherals:

```systemverilog
// Write routing
assign ram_we = we && (addr < 16'h4000);
assign vga_we = we && (addr >= 16'h4000) && (addr < 16'h6000);

// Read mux
always @(*) begin
    casez (addr)
        16'b00??????????????: data_out = ram_data;
        16'b010?????????????: data_out = vga_data;  // text screen
        16'h6000:             data_out = keyboard;
        16'h6001:             data_out = {8'b0, switches};
        default:              data_out = 16'h0000;
    endcase
end
```

## 7. Signed vs Unsigned Sprite Math

Use `signed` for sprite positions (allow negative for off-screen):

```systemverilog
input signed [31:0] topLeft_x;  // Can be negative!
wire signed [31:0] rightX = topLeft_x + WIDTH;

// This correctly handles sprites partially off-screen
assign drawingRequest = (pxl_x >= topLeft_x) && (pxl_x < rightX);
```

## 8. Combinational Boundary Clamping

Prevent sprite from going off-screen:

```systemverilog
// Clamp to valid range in one expression
assign safe_x = (raw_x < 0) ? 0 :
                (raw_x > 640-WIDTH) ? 640-WIDTH : raw_x;
```

## 9. Dual-Port RAM Pattern

For CPU-write + VGA-read scenarios:

```
Port A (read): VGA scan address → character/pixel data
Port B (write): CPU address + data + write_enable
```

Always separate read and write concerns to different ports.

## 10. I/O Assignment Conventions

| Resource | Typical Assignment |
|----------|-------------------|
| `SW[9]` | System resetN |
| `SW[8:7]` | Display mode selection |
| `SW[6]` | CPU/subsystem reset |
| `SW[0]` | Manual start trigger |
| `KEY[0]` | Mode button |
| `KEY[1]` | Increment button |
| `LEDR[7:0]` | Input state indicators |
| `LEDR[9]` | Heartbeat (1-second blink) |
| `HEX[5:4]` | Hours / high value |
| `HEX[3:2]` | Minutes / mid value |
| `HEX[1:0]` | Seconds / low value |

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Combinational loop | Ensure all paths through `always @(*)` assign to output |
| Missing reset | Every `always @(posedge clk)` needs reset branch |
| Multi-driven net | Only one `always` block can drive a signal |
| Clock domain crossing | Sample slow clock in fast domain with edge detect |
| RAM read latency | Buffer address/control to match pipeline delay |
| Unsigned overflow | Use `signed` for sprite positions, boundary checks |

---

## Reusable IP Blocks for DE10-Lite Projects

**For Future Projects**: Catalog of proven, reusable SystemVerilog/Verilog modules used across multiple DE10-Lite projects.

---

## 1. Seven-Segment Decoder

Hex digit (4-bit) to active-low 7-segment display:

```systemverilog
module seven_segment (
    input  [3:0] data,
    output reg [7:0] seg   // Active-low: {DP, G, F, E, D, C, B, A}
);
always @(*) begin
    case (data)
        4'h0: seg = 8'b11000000;  4'h1: seg = 8'b11111001;
        4'h2: seg = 8'b10100100;  4'h3: seg = 8'b10110000;
        4'h4: seg = 8'b10011001;  4'h5: seg = 8'b10010010;
        4'h6: seg = 8'b10000010;  4'h7: seg = 8'b11111000;
        4'h8: seg = 8'b10000000;  4'h9: seg = 8'b10010000;
        4'hA: seg = 8'b10001000;  4'hB: seg = 8'b10000011;
        4'hC: seg = 8'b11000110;  4'hD: seg = 8'b10100001;
        4'hE: seg = 8'b10000110;  4'hF: seg = 8'b10001110;
        default: seg = 8'b11111111;  // All off
    endcase
end
endmodule
```

**Blanking variant** (CoCode_clock): Add `blink_enable` input — when LOW, output `8'hFF` (all off).

## 2. One-Second Timer

Generates 1-second pulses from 50 MHz clock:

```systemverilog
module one_sec (
    input        clk,      // 50 MHz
    input        resetN,
    output reg   pulse,    // Single-cycle pulse every 1 second
    output reg [3:0] counter  // 0-15 rolling counter
);
localparam DIVISOR = 50_000_000;
reg [25:0] count;

always @(posedge clk or negedge resetN) begin
    if (!resetN) begin
        count <= 0; pulse <= 0; counter <= 0;
    end else begin
        pulse <= 0;
        if (count == DIVISOR - 1) begin
            count <= 0;
            pulse <= 1;
            counter <= counter + 1;
        end else
            count <= count + 1;
    end
end
endmodule
```

## 3. Clock Divider (Parameterized)

Generate arbitrary frequency from 50 MHz:

```systemverilog
module clock_divider #(
    parameter COUNT_MAX = 25_000_000 - 1  // 1 Hz default
)(
    input      clk_50mhz,
    input      reset_n,
    output reg clk_out
);
reg [25:0] counter;
always @(posedge clk_50mhz or negedge reset_n) begin
    if (!reset_n) begin counter <= 0; clk_out <= 0; end
    else if (counter == COUNT_MAX) begin counter <= 0; clk_out <= ~clk_out; end
    else counter <= counter + 1;
end
endmodule
```

## 4. Button Debounce with Edge Detection

Clean single-cycle pulse from noisy pushbutton:

```systemverilog
module button_debounce (
    input      clk,       // 50 MHz
    input      reset_n,
    input      btn_raw,   // Active-low raw button
    output reg btn_pulse  // Single-cycle clean pulse
);
reg [19:0] counter;      // ~20 ms debounce @ 50 MHz
reg stable, prev;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin counter <= 0; stable <= 1; prev <= 1; btn_pulse <= 0; end
    else begin
        btn_pulse <= 0;
        if (btn_raw != stable) begin
            if (counter == 20'hFFFFF) begin
                stable <= btn_raw;
                counter <= 0;
            end else
                counter <= counter + 1;
        end else
            counter <= 0;
        prev <= stable;
        if (prev && !stable)  // Falling edge = button press
            btn_pulse <= 1;
    end
end
endmodule
```

## 5. PLL25 (Quartus IP)

Generate 25/50/100 MHz from 50 MHz input:

| Output | Frequency | Use |
|--------|-----------|-----|
| `c0` | 25 MHz | VGA pixel clock |
| `c1` | 50 MHz | System clock (pass-through) |
| `c2` | 100 MHz | LCD controller fast clock |

**Setup**: Quartus → IP Catalog → ALTPLL → 50 MHz input → configure 3 outputs.

## 6. Obj_Rect (Parameterized Bounds Checker)

Reusable sprite bounds test with signed coordinates:

```systemverilog
module obj_rect #(
    parameter OBJECT_WIDTH_X = 32,
    parameter OBJECT_HEIGHT_Y = 16
)(
    input  signed [31:0] pxl_x, pxl_y,
    input  signed [31:0] topLeft_x, topLeft_y,
    output [10:0] offsetX, offsetY,
    output drawingRequest
);
// Supports negative topLeft (sprite partially off-screen)
```

## 7. Sync Gen (Simple VGA)

All-in-one sync generator with built-in 50→25 MHz divider:

```systemverilog
module sync_gen (
    input        clk_50,    // 50 MHz input
    input        resetN,
    output       vga_h_sync, vga_v_sync,
    output       disp_ena,
    output [9:0] pixel_x, pixel_y
);
// Internal: divides 50→25 MHz, counts 800×525
```

## Cross-Reference: Which Module Where

| Module | nand2tetris | Arcade Template | CoCode_clock |
|--------|:-----------:|:---------------:|:------------:|
| seven_segment | ✓ | — | ✓ |
| one_sec | ✓ | — | — |
| clock_divider | — | — | ✓ |
| button_debounce | — | — | ✓ |
| pll25 | ✓ | ✓ | — |
| obj_rect | ✓ | — | — |
| vga_controller | ✓ | ✓ | — |
| analog_input | ✓ | ✓ | — |
| lcd_ctrl | ✓ | ✓ | — |

---

## DE10-Lite Arcade Game Template (Quick-Start)

**For Future Projects**: Complete starter template for building arcade-style games on the DE10-Lite with VGA, LCD, joystick, buttons, and sprites.

---

## Template File Structure

```
Project/
├── Top_template.sv          ← Top-level: wires everything together
├── Screens_dispaly.sv       ← VGA + LCD display manager
├── periphery_control.sv     ← Joystick/button decoder (analog→boolean)
├── Drawing_priority.sv      ← Sprite priority compositor
├── Intel_unit.sv            ← Player sprite (Move + Draw)
│   ├── Move_Intel.sv        ← Player movement logic
│   └── Draw_Intel.sv        ← Player pixel renderer (128×64 bitmap)
├── Ghost_unit.sv            ← Enemy sprite (Move + Draw)
│   ├── Move_Ghost.sv        ← Autonomous bounce movement
│   └── Draw_Ghost.sv        ← Enemy pixel renderer (64×64 bitmap)
├── vga_controller.v         ← Parameterized VGA sync generator
├── lcd_ctrl.sv              ← LCD mirror controller
├── analog_input.sv          ← ADC FSM for 6 channels
├── adc/ (Qsys-generated)    ← ADC IP block
└── pll25/ (Qsys-generated)  ← PLL IP block (50→25/50/100 MHz)
```

## Top-Level Wiring Pattern

```systemverilog
module Top_template (
    input  MAX10_CLK1_50,
    input  [9:0] SW, [1:0] KEY,
    output [9:0] LEDR,
    output [7:0] HEX0..HEX5,
    output [3:0] VGA_R, VGA_G, VGA_B,
    output VGA_HS, VGA_VS,
    inout  [15:0] ARDUINO_IO, ARDUINO_RESET_N
);

// Clock generation
pll25 pll_inst (.inclk0(MAX10_CLK1_50), .c0(clk_25), .c1(clk_50), .c2(clk_100));

// Display output (VGA + LCD mirror)
Screens_display display_inst (
    .clk_25, .clk_100, .resetN(SW[9]),
    .Red_level, .Green_level, .Blue_level,
    .pxl_x, .pxl_y,
    .VGA_R, .VGA_G, .VGA_B, .VGA_HS, .VGA_VS,
    .ARDUINO_IO
);

// Input controls
periphery_control controls_inst (
    .clk(clk_25), .resetN(SW[9]),
    .A, .B, .Select, .Start,
    .Right, .Left, .Up, .Down, .Wheel,
    .ARDUINO_IO
);

// Player sprite
Intel_unit player_inst (
    .clk(clk_25), .resetN(SW[9]),
    .pxl_x, .pxl_y,
    .Wheel, .Up, .Down,
    .Red(player_R), .Green(player_G), .Blue(player_B), .Draw(player_draw)
);

// Enemy sprite
Ghost_unit enemy_inst (
    .clk(clk_25), .resetN(SW[9]),
    .pxl_x, .pxl_y,
    .collision(1'b0),  // Wire to collision detection
    .Red(enemy_R), .Green(enemy_G), .Blue(enemy_B), .Draw(enemy_draw)
);

// Priority compositor (player > enemy > background)
Drawing_priority compositor_inst (
    .clk(clk_25), .resetN(SW[9]),
    .RGB_1({player_R, player_G, player_B}), .draw_1(player_draw),
    .RGB_2({enemy_R, enemy_G, enemy_B}),   .draw_2(enemy_draw),
    .RGB_bg(12'hFFF),   // White background
    .Red_level, .Green_level, .Blue_level
);
```

## How to Customize

### Add a New Sprite
1. Copy `Intel_unit.sv` → `My_unit.sv`
2. Replace bitmap in `Draw_Intel.sv` with your sprite image
3. Modify `Move_Intel.sv` for your movement logic
4. Add to `Drawing_priority.sv` chain (wire new `draw_N` / `RGB_N`)
5. Instantiate in top module

### Add Background
Replace `RGB_bg(12'hFFF)` with a background module:
```systemverilog
// Tiled background, scrolling, etc.
bg_unit bg_inst (.pxl_x, .pxl_y, .bg_select(SW[2:0]), .RGB(bg_RGB));
```

### Add Collision Detection
```systemverilog
// Simple overlap check
wire collision = player_draw && enemy_draw;
// Feed back to enemy to trigger bounce
```

### Add Scoring / Game State
Use text_screen module for score display, or seven-segment for simple counters.

## LED Debug Mapping

```systemverilog
assign LEDR[0] = A;          // Button A pressed
assign LEDR[1] = B;          // Button B pressed
assign LEDR[2] = Select;     // Select pressed
assign LEDR[3] = Start;      // Start pressed
assign LEDR[4] = Right;      // Joystick right
assign LEDR[5] = Left;       // Joystick left
assign LEDR[6] = Up;         // Joystick up
assign LEDR[7] = Down;       // Joystick down
```

## Source Project

Designed by: Mor (Mordechai) Dahan, Sep. 2022 (Technion IIT course).
Reference implementation lives outside this repo.

---

## Pipeline Accumulator — Single-Adder FSM Design (ADDER_PIPE)

**For Future Projects**: Demonstrates constrained datapath design — accumulating N inputs using exactly one adder, controlled by a 3-state FSM.

---

## Design Constraint

**Use exactly one physical adder** to accumulate 1–16 unsigned 32-bit inputs streamed one per clock.

## Interface

```systemverilog
module pipeline_accumulator (
    input              clk,
    input              resetN,
    input              start,        // Single-cycle trigger
    input       [3:0]  num_inputs,   // N-1 (0→1 input, 15→16 inputs)
    input       [31:0] data_in,      // Streamed input (one per cycle)
    output reg  [31:0] data_out,     // Accumulated sum
    output reg         valid_out     // Single-cycle result pulse
);
```

## FSM States

```
IDLE ──(start)──► ACCUMULATING ──(counter==0)──► DONE ──► IDLE
```

| State | Duration | Action |
|-------|----------|--------|
| `IDLE` | Until start | Wait for start pulse |
| `ACCUMULATING` | N cycles | Add `data_in` to accumulator each cycle |
| `DONE` | 1 cycle | Assert `valid_out`, output final sum |

## Key Pattern: Single-Resource Datapath

```systemverilog
// THE ONLY ADDER in the design
wire [31:0] adder_a = clear_acc ? 32'b0 : accumulator;
wire [31:0] adder_b = data_in;
assign adder_sum = adder_a + adder_b;

// Accumulator register with conditional enable
always @(posedge clk or negedge resetN) begin
    if (!resetN)        accumulator <= 32'b0;
    else if (enable_acc) accumulator <= adder_sum;
end
```

**How it works:**
- `clear_acc = 1` (first cycle): `adder_a = 0`, so `sum = 0 + data_in[0]`
- `clear_acc = 0` (subsequent): `adder_a = accumulator`, so `sum = running_total + data_in[n]`

## 2-Process FSM Pattern (Textbook)

```systemverilog
// Process 1: State register
always @(posedge clk or negedge resetN) begin
    if (!resetN) state <= IDLE;
    else         state <= next_state;
end

// Process 2: Next-state + output logic (combinational)
always @(*) begin
    next_state = state;  // Default: stay
    enable_acc = 0; clear_acc = 0; valid_out = 0;
    
    case (state)
        IDLE: begin
            if (start) begin
                next_state = ACCUMULATING;
                enable_acc = 1;
                clear_acc = 1;  // First add: 0 + data_in
            end
        end
        ACCUMULATING: begin
            enable_acc = 1;
            if (counter == 0) next_state = DONE;
        end
        DONE: begin
            valid_out = 1;
            next_state = IDLE;
        end
    endcase
end
```

## Timing Diagram

```
clk:       _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
start:     ___|‾‾‾|___________________
data_in:   XX| A  | B  | C  | D  |XXX
state:     IDLE|ACM |ACM |ACM |DONE|IDLE
accum:     0   | A  |A+B |A+B+C|sum|0
valid_out: ______________________|‾‾‾|___
data_out:  XXXXXXXXXXXXXXXXXXXXX|sum |XXX
```

For `num_inputs = 3` (4 inputs): Latency = 4+1 = 5 cycles.

## Design Lessons

1. **Resource sharing**: One adder shared across N additions via temporal multiplexing
2. **Clear + enable pattern**: `clear_acc` initializes accumulator without separate state
3. **Down-counter**: Simpler than up-counter for "remaining inputs" tracking
4. **Single-cycle result**: `valid_out` is exactly 1 cycle — safe for downstream handshake
5. **2-process FSM**: Clean separation of state register (sequential) and logic (combinational)

## Source Location

Reference module: `pipeline_accumulator.sv` (external reference design,
not bundled in this repo).

---

## Digital Clock Project — FSM + BCD + 7-Segment (CoCode_clock)

**For Future Projects**: Modular digital clock design on DE10-Lite showing clean FSM-based time counter with mode setting, BCD display, and button debounce.

---

## Architecture

```
clk_50mhz ──► clock_divider ──► clk_1hz (counting)
                               ──► clk_2hz (blink)

KEY[0] ──► button_controller ──► mode_pulse ──┐
KEY[1] ──►                   ──► inc_pulse  ──┤
                                               ▼
                                time_counter
                                  │ hours[4:0]     (0-23)
                                  │ minutes[5:0]   (0-59)
                                  │ seconds[5:0]   (0-59)
                                  │ setting_mode[1:0]
                                  ▼
                            display_controller
                                  │ digit[5:0][3:0]   (BCD)
                                  │ blink_enable[5:0]
                                  ▼
                            seven_segment_decoder ×6 ──► HEX[5:0]
```

## Mode FSM (time_counter.sv)

```
MODE_NORMAL ──(mode_pulse)──► MODE_SET_HOURS ──(mode_pulse)──► MODE_SET_MINUTES ──(mode_pulse)──► MODE_NORMAL
```

| Mode | Behavior | inc_pulse Action |
|------|----------|------------------|
| `MODE_NORMAL` (0) | Clock runs normally | (ignored) |
| `MODE_SET_HOURS` (1) | Clock paused, hours blink | Increment hours (0-23 wrap) |
| `MODE_SET_MINUTES` (2) | Clock paused, minutes blink | Increment minutes (0-59 wrap) |

## Key Patterns Demonstrated

### 1. Clock Domain Crossing (CDC)

1 Hz and 2 Hz signals sampled in 50 MHz domain:

```verilog
reg clk_1hz_prev;
always @(posedge clk_50mhz) begin
    clk_1hz_prev <= clk_1hz;
    if (clk_1hz && !clk_1hz_prev)  // Rising edge in 50 MHz domain
        // ... do 1-second action
end
```

### 2. Cascaded Rollover Counters

```verilog
// seconds → minutes → hours cascade
if (seconds == 59) begin
    seconds <= 0;
    if (minutes == 59) begin
        minutes <= 0;
        if (hours == 23) hours <= 0;
        else hours <= hours + 1;
    end else minutes <= minutes + 1;
end else seconds <= seconds + 1;
```

### 3. Binary to BCD Conversion

```verilog
function [3:0] tens; input [5:0] val; tens = val / 10; endfunction
function [3:0] ones; input [5:0] val; ones = val % 10; endfunction

// HEX5:HEX4 = hours, HEX3:HEX2 = minutes, HEX1:HEX0 = seconds
digit[5] = tens(hours);   digit[4] = ones(hours);
digit[3] = tens(minutes); digit[2] = ones(minutes);
digit[1] = tens(seconds); digit[0] = ones(seconds);
```

### 4. Selective Digit Blink

```verilog
// blink_enable: 1=show, 0=blank
case (setting_mode)
    MODE_NORMAL:      blink_enable = 6'b111111;       // All visible
    MODE_SET_HOURS:   blink_enable = {blink_state, blink_state, 4'b1111};
    MODE_SET_MINUTES: blink_enable = {2'b11, blink_state, blink_state, 2'b11};
endcase
```

`blink_state` toggles at 2 Hz, making the active digit pair flash.

## Test Infrastructure

The CoCode_clock project includes comprehensive test scripts:

| Script | Purpose |
|--------|---------|
| `run_simple_test.ps1` | Basic functional test |
| `run_enhanced_test.ps1` | Extended test coverage |
| `run_final_test.ps1` | Full regression |
| `run_system_test.ps1` | System-level integration |
| `run.bat` | Quick compilation + program |

## Documentation

| File | Contents |
|------|----------|
| `ARCHITECTURE_SPEC.md` | High-level system architecture |
| `MICROARCHITECTURE_SPEC.md` | Module-level detail |
| `IMPLEMENTATION_SUMMARY.md` | Feature status and notes |
| `HARDWARE_TEST_CHECKLIST.md` | Manual test procedures |
| `TEST_STRATEGY.md` | Test methodology |

## Source Location

Reference project: `CoCode_clock` (external reference design,
not bundled in this repo).

---

## Hack CPU on DE10-Lite (nand2tetris System)

**For Future Projects**: Complete nand2tetris Hack computer implementation on DE10-Lite — CPU, memory arbiter, ALU, and memory-mapped I/O.

---

## System Architecture

```
cpu_rom (32K×16) ──► hack_cpu ──► mem_space_arbiter ──┬── cpu_ram (16K×16)
                        │                              ├── text_screen (8K)
                        │                              ├── keyboard (addr 0x6000)
                  alu ──┘                              └── switches (addr 0x6001)
```

## Hack CPU (hack_cpu.sv)

| Feature | Specification |
|---------|--------------|
| **Word size** | 16 bits |
| **Architecture** | Harvard (separate instruction/data ROM) |
| **Cycles** | Dual-cycle: Fetch (stage=0) → Execute (stage=1) |
| **Registers** | A (16-bit address/data), D (16-bit data), PC (14-bit) |
| **ROM** | 16K × 16 instruction ROM |

### Instruction Format

```
A-instruction:  0vvv_vvvv_vvvv_vvvv   (load 15-bit value into A)
C-instruction:  111a_cccc_ccdd_djjj
                    │ │       │  └── jump condition (3 bits)
                    │ │       └───── destination (3 bits)
                    │ └───────────── computation (6 bits)
                    └─────────────── a=0: use A, a=1: use M[A]
```

### Destination Decode

| d2 d1 d0 | Destination |
|-----------|-------------|
| 000 | null (no store) |
| 001 | M (RAM[A]) |
| 010 | D register |
| 011 | M and D |
| 100 | A register |
| 101 | A and M |
| 110 | A and D |
| 111 | A, M, and D |

### Jump Conditions

| j2 j1 j0 | Mnemonic | Condition |
|-----------|----------|-----------|
| 000 | (none) | No jump |
| 001 | JGT | out > 0 |
| 010 | JEQ | out == 0 |
| 011 | JGE | out >= 0 |
| 100 | JLT | out < 0 |
| 101 | JNE | out != 0 |
| 110 | JLE | out <= 0 |
| 111 | JMP | Always |

## ALU Operations (alu.sv)

18 operations selected by 6-bit `comp` code:

| comp[5:0] | Operation | Description |
|-----------|-----------|-------------|
| 101010 | 0 | Zero |
| 111111 | 1 | One |
| 111010 | -1 | Minus one |
| 001100 | D | D register |
| 110000 | A (or M) | A register (or memory) |
| 001101 | !D | Bitwise NOT D |
| 110001 | !A | Bitwise NOT A |
| 001111 | -D | Negate D |
| 110011 | -A | Negate A |
| 011111 | D+1 | Increment D |
| 110111 | A+1 | Increment A |
| 001110 | D-1 | Decrement D |
| 110010 | A-1 | Decrement A |
| 000010 | D+A | Add |
| 010011 | D-A | Subtract |
| 000111 | A-D | Reverse subtract |
| 000000 | D&A | Bitwise AND |
| 010101 | D\|A | Bitwise OR |

## Memory Space Arbiter (mem_space_arbiter.sv)

| Address Range | Size | Target | Description |
|---------------|------|--------|-------------|
| `0x0000–0x3FFF` | 16K | cpu_ram | General-purpose RAM |
| `0x4000–0x5FFF` | 8K | text_screen | Character display RAM |
| `0x6000` | 1 | keyboard | Keyboard input (returns 0) |
| `0x6001` | 1 | switches | `SW[7:0]` (8-bit input) |

### Write Routing

```systemverilog
assign ram_we      = we && (addr < 16'h4000);
assign vga_text_wr = we && (addr >= 16'h4000) && (addr < 16'h6000);
```

### Read Mux

```systemverilog
always @(*) begin
    if (addr < 16'h4000) data_out = ram_data;
    else if (addr == 16'h6000) data_out = keyboard_data;
    else if (addr == 16'h6001) data_out = {8'b0, SW[7:0]};
    else data_out = 16'h0000;
end
```

## Integration on DE10-Lite

```systemverilog
// CPU instance
hack_cpu cpu_inst (
    .clk(clk_25), .resetN(resetN),
    .instruction(rom_data),
    .mem_in(arbiter_data_out),
    .mem_out(cpu_data), .mem_addr(cpu_addr),
    .mem_we(cpu_we), .pc(cpu_pc)
);

// Instruction ROM (pre-loaded with .mif file)
cpu_rom rom_inst (.address(cpu_pc), .clock(clk_25), .q(rom_data));

// Memory arbiter
mem_space_arbiter arb_inst (
    .clk(clk_25), .addr(cpu_addr), .data_in(cpu_data),
    .we(cpu_we), .SW(SW[7:0]),
    .data_out(arbiter_data_out),
    .vga_text_wr(vga_text_wr)
);
```

## Programming the CPU

1. Write Hack assembly (`.asm`) or Jack high-level language
2. Compile to `.hack` binary using nand2tetris tools
3. Convert to Quartus `.mif` (Memory Initialization File)
4. Load as init file for `cpu_rom` IP block
5. Recompile Quartus project → program FPGA
