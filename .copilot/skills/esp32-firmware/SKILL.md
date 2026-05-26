# ESP32 Firmware Development Skill

> **Purpose**: Complete guide to install tools, develop, build, flash, and debug ESP32 firmware using PlatformIO + Arduino framework. Covers installation from scratch, board bring-up, LVGL UI, peripherals, and production workflows.

---

## CrashTech VLSI-2026 — Hardware BKM (Verified Reference)

> This section is the **authoritative reference** for all ESP32 projects in this repo.  
> All pin assignments, wiring, and library choices below are **verified working** on the actual CrashTech kit (May 2026).

### Board

| Field | Value |
|-------|-------|
| Board | ESP32 DevKit V1, 38-pin |
| Chip | ESP32-D0WD-V3 rev 3.1 |
| Flash | 4MB |
| CPU | Dual-core 240 MHz |
| USB-Serial | CP2102 (COM4 on Avi's machine) |
| Framework | Arduino via PlatformIO |
| PlatformIO board ID | `esp32dev` |

### Pin Assignments (from `projects/common/esp32/pin_config.h`)

| Function | GPIO | Notes |
|----------|------|-------|
| FPGA UART TX | 16 | UART2 TX → FPGA ARDUINO_IO[0] |
| FPGA UART RX | 17 | UART2 RX ← FPGA ARDUINO_IO[1] |
| OLED SDA | 21 | I2C default Wire |
| OLED SCL | 22 | I2C default Wire |
| Servo | 18 | PWM via LEDC (50Hz, 16-bit) |
| Buzzer | 19 | PWM via `tone()` |
| LED 1 | 23 | Digital output |
| LED 2 | 2 | Digital output (also onboard LED) |
| LED 3 | 15 | Digital output (strapping pin — boot HIGH, OK after boot) |
| Switch 1 | 4 | INPUT_PULLUP, active LOW |
| Switch 2 | 0 | INPUT_PULLUP, active LOW — **boot pin, do NOT hold LOW at power-on** |
| Analog In | 34 | ADC1_CH6, input-only, works with WiFi active |

**FPGA side:** Arduino header on DE10-Lite. ARDUINO_IO[0] = RX from ESP32. ARDUINO_IO[1] = TX to ESP32. GND pin on Arduino header.  
**UART baud:** 9600 8N1.

### Wiring BKM

**OLED (SSD1306 128×64, I2C)**
- VCC → 3V3
- GND → GND
- SDA → GPIO 21
- SCL → GPIO 22
- I2C address: `0x3C`

**LEDs**
- GPIO → 330Ω resistor → LED anode → LED cathode → GND
- All 3 verified working (GPIO 23, 2, 15)

**Buzzer**
- GPIO 19 → buzzer + terminal
- Buzzer − terminal → GND
- Use `tone(PIN_BUZZER, freq)` / `noTone(PIN_BUZZER)`
- Verified: 800 Hz (SW1), 1500 Hz (SW2), 2000 Hz (both)

**Switches**
- One leg → GPIO pin
- Other leg → GND
- `pinMode(pin, INPUT_PULLUP)` — reads LOW when pressed

**Analog Input (potentiometer)**
- Pot wiper → GPIO 34
- Pot ends → 3V3 and GND
- `analogRead(34)` returns 0–4095 (12-bit ADC)
- Floating pin reads ~4095 (3.3V) — normal

**Servo (SG90 / MG90S — yellow/red/brown)**
- Brown → GND
- Red (middle) → **5V** (not 3V3!)
- Yellow (signal) → GPIO 18
- PWM: 50Hz, 16-bit LEDC. Pulse: 0.5ms=0°, 1.5ms=90°, 2.5ms=180°

```cpp
ledcAttach(PIN_SERVO, 50, 16);
uint32_t angleToDuty(int deg) {
    uint32_t us = 500 + ((uint32_t)deg * 2000 / 180);
    return (uint32_t)(us * 65536UL / 20000UL);
}
ledcWrite(PIN_SERVO, angleToDuty(90));
```

> **Do NOT use the ESP32Servo library** — it is incompatible with the new Arduino ESP32 core (v3.x). Use raw LEDC as shown above.

### `platformio.ini` Template

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
lib_deps =
    adafruit/Adafruit SSD1306@^2.5.7
    adafruit/Adafruit GFX Library@^1.11.5
```

Always include `pin_config.h`:
```cpp
#include "../../../../projects/common/esp32/pin_config.h"
// (adjust relative path from your src/ folder)
```

### Verified Status (May 2026)

| Peripheral | Status | Notes |
|-----------|--------|-------|
| OLED SSD1306 | ✅ Working | I2C 0x3C |
| LED 1 (GPIO 23) | ✅ Working | |
| LED 2 (GPIO 2) | ✅ Working | also onboard LED |
| LED 3 (GPIO 15) | ✅ Working | |
| Buzzer (GPIO 19) | ✅ Working | |
| Switch 1 (GPIO 4) | ✅ Working | |
| Switch 2 (GPIO 0) | ✅ Working | |
| Analog In (GPIO 34) | ✅ Working | |
| Servo (GPIO 18) | ⏳ Not yet tested | wiring BKM documented above |
| FPGA UART (GPIO 16/17) | ✅ Working | ARDUINO_IO[0] RX, ARDUINO_IO[1] TX |

### Reference Demo

See `demos/alive_test/esp32/src/main.cpp` — the canonical working demo for all IO.

---

## Table of Contents

0. [Complete Installation Guide](#complete-installation-guide)
1. [Workflow Checklist](#workflow-checklist)
2. [Environment & Tools](#environment--tools)
3. [PlatformIO Configuration](#platformio-configuration)
4. [Board Definitions](#board-definitions)
5. [LVGL Integration](#lvgl-integration)
6. [Display (SPI LCD)](#display-spi-lcd)
7. [Touch Input](#touch-input)
8. [IMU / I2C Sensors](#imu--i2c-sensors)
9. [Camera](#camera)
10. [WiFi & Web Server](#wifi--web-server)
11. [SD Card](#sd-card)
12. [Build & Flash Workflow](#build--flash-workflow)
13. [Serial Monitor Tips](#serial-monitor-tips)
14. [Lessons Learned](#lessons-learned)

---

## Complete Installation Guide

Everything you need to program the ESP32 from scratch. Follow these steps in order.

---

### Step 1: Install VS Code

1. Download from: **https://code.visualstudio.com/download**
2. Run the installer, accept defaults
3. Verify: open VS Code, you should see the Welcome tab

### Step 2: Install PlatformIO Extension

PlatformIO is the development environment for ESP32. It handles compilers, libraries, board definitions, and flashing — all inside VS Code.

1. Open VS Code
2. Click the **Extensions** icon in the left sidebar (or press `Ctrl+Shift+X`)
3. Search for **"PlatformIO IDE"**
4. Click **Install** (publisher: PlatformIO)
5. Wait for installation to complete — PlatformIO will download its core tools automatically (~2–5 minutes)
6. Restart VS Code when prompted
7. Verify: you should see the **PlatformIO alien icon** in the left sidebar

> **Note:** PlatformIO automatically installs Python, the ESP32 toolchain (compiler, linker), and esptool (flasher). You do NOT need to install these separately.

### Step 3: Install USB Driver for ESP32

Most ESP32 boards use one of two USB-to-serial chips. You need the correct driver for your PC to see the board as a COM port.

| Chip | Common on | Driver download |
|------|-----------|-----------------|
| **CP2102 / CP2104** | ESP32-DevKitC, many generic boards | https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers |
| **CH340 / CH9102** | ESP32-S3 boards, budget boards | https://www.wch-ic.com/downloads/CH341SER_EXE.html |

**How to know which chip your board uses:**
1. Connect the ESP32 to your PC via USB
2. Open **Device Manager** (right-click Start → Device Manager)
3. Look under **Ports (COM & LPT)**:
   - If you see "Silicon Labs CP210x" → install the CP2102 driver
   - If you see "CH340" or "CH9102" → install the CH340 driver
   - If you see "USB Serial Device" with a COM number → driver is already installed
   - If you see an unknown device with a yellow triangle → install both drivers and try again

**Install the driver:**
1. Download from the link above
2. Run the installer
3. Unplug and re-plug the ESP32
4. Check Device Manager → **Ports (COM & LPT)** — you should see a COM port (e.g., `COM3`, `COM5`)
5. **Note the COM port number** — you'll need it for flashing

### Step 4: Create Your First PlatformIO Project

1. Open VS Code
2. Click the PlatformIO icon in the left sidebar
3. Click **"New Project"** (or PlatformIO Home → New Project)
4. Fill in:
   - **Name:** `esp32_test`
   - **Board:** `Espressif ESP32 Dev Module` (or your specific board — search for it)
   - **Framework:** `Arduino`
5. Click **Finish** — PlatformIO creates the project structure
6. The project will have this structure:

```
esp32_test/
├── platformio.ini        # Build configuration
├── src/
│   └── main.cpp          # Your code goes here
├── include/              # Header files
├── lib/                  # Project-specific libraries
└── test/                 # Unit tests
```

### Step 5: Write a Smoke Test — Serial Hello + LED Blink

Replace the contents of `src/main.cpp` with:

```cpp
#include <Arduino.h>

#define LED_PIN 2   // Built-in LED on most ESP32 boards

void setup() {
    Serial.begin(115200);
    delay(2000);  // Wait for serial monitor to connect
    Serial.println("ESP32 is alive!");

    pinMode(LED_PIN, OUTPUT);
}

void loop() {
    digitalWrite(LED_PIN, HIGH);
    Serial.println("LED ON");
    delay(500);

    digitalWrite(LED_PIN, LOW);
    Serial.println("LED OFF");
    delay(500);
}
```

> **Note:** The built-in LED pin varies by board. Common values: GPIO 2 (most ESP32), GPIO 48 (ESP32-S3). If the LED doesn't blink, check your board's documentation.

### Step 6: Configure platformio.ini

Open `platformio.ini` and set it to:

```ini
[env:esp32]
platform = espressif32
board = esp32dev
framework = arduino

monitor_speed = 115200

; Set your COM port (check Device Manager)
; upload_port = COM5
; monitor_port = COM5
```

> **Tip:** If you only have one ESP32 connected, PlatformIO auto-detects the port. You can leave `upload_port` and `monitor_port` commented out.

### Step 7: Build

1. Click the **checkmark icon** (✓) in the PlatformIO toolbar at the bottom of VS Code, OR
2. Open terminal and run:

```powershell
cd path\to\esp32_test
pio run
```

The first build downloads the ESP32 platform and toolchain (~500 MB). Subsequent builds are fast.

**Expected output:**
```
SUCCESS
RAM:   [=         ]  5.1%  (used 16712 bytes from 327680 bytes)
Flash: [==        ] 15.3%  (used 200437 bytes from 1310720 bytes)
```

### Step 8: Flash (Upload to Board)

1. Make sure the ESP32 is connected via USB
2. Close any Serial Monitor that might be holding the COM port
3. Click the **right-arrow icon** (→) in the PlatformIO toolbar, OR run:

```powershell
pio run -t upload
```

**If upload fails:**
- Close the Serial Monitor first (it locks the COM port)
- Some boards require you to **hold the BOOT button** while pressing the EN/RESET button, then release BOOT after upload starts
- Check the COM port in Device Manager matches what PlatformIO is using
- Try adding `upload_port = COMx` in `platformio.ini` with your actual port number

### Step 9: Open Serial Monitor

1. Click the **plug icon** in the PlatformIO toolbar, OR run:

```powershell
pio device monitor
```

**Expected output:**
```
ESP32 is alive!
LED ON
LED OFF
LED ON
LED OFF
...
```

If you see this and the LED is blinking — **your ESP32 toolchain is fully working.**

### Step 10: Install Libraries (As Needed)

Add libraries in `platformio.ini` under `lib_deps`:

```ini
lib_deps =
    adafruit/Adafruit NeoPixel@^1.12.0
    bblanchon/ArduinoJson@^7.0.0
```

PlatformIO downloads them automatically on next build.

Or install via CLI:
```powershell
pio pkg install --library "adafruit/Adafruit NeoPixel"
```

---

### Quick Reference: Full Command Cheat Sheet

```powershell
# Build
pio run

# Upload to board
pio run -t upload

# Serial monitor
pio device monitor

# Clean build (forces full recompile)
pio run -t clean

# List connected boards
pio device list

# Build + upload in one step
pio run -t upload && pio device monitor
```

---

## Workflow Checklist

### Phase 1 — Board Bring-up
- [ ] Identify board on USB (VID/PID, COM port)
- [ ] Create PlatformIO project with correct board definition
- [ ] Flash minimal "alive" test (Serial + LED/backlight)
- [ ] Verify serial output — no boot loop
- [ ] **Gate**: Board boots and prints to serial

### Phase 2 — Display
- [ ] Init SPI bus and LCD driver (ST7789, ILI9341, etc.)
- [ ] Fill screen with solid color
- [ ] Draw text with GFX library
- [ ] **Gate**: Visual output on screen

### Phase 3 — LVGL + Touch
- [ ] Add LVGL library with `lv_conf.h`
- [ ] Create display flush callback
- [ ] Create touch read callback
- [ ] Verify touch coordinates map correctly
- [ ] **Gate**: LVGL label visible, touch events work

### Phase 4 — Peripherals
- [ ] I2C bus scan — identify devices
- [ ] Initialize sensors (IMU, touch, etc.)
- [ ] Camera init (if present)
- [ ] SD card mount (if present)
- [ ] WiFi connect
- [ ] **Gate**: All peripherals responding

### Phase 5 — Application UI
- [ ] Create tabbed UI or navigation structure
- [ ] Wire live data to UI labels
- [ ] Add interactive widgets (buttons, switches)
- [ ] **Gate**: Functional interactive UI

---

## Environment & Tools

- **PlatformIO** (VS Code extension or CLI)
- **Framework**: Arduino (simpler) or ESP-IDF (more control)
- **Platform**: `espressif32` (check version — affects Arduino core)
  - `espressif32@6.x` → Arduino core 2.x (ESP-IDF 4.x) — PSRAM OPI broken on S3 rev v0.2
  - **pioarduino** (RECOMMENDED) → Arduino core 3.3.7 + ESP-IDF 5.5.2 — PSRAM OPI works
    - `platform = https://github.com/pioarduino/platform-espressif32/releases/download/stable/platform-espressif32.zip`
    - Community fork, actively maintained, packages ESP-IDF 5.x for PlatformIO
- **Python venv**: At `env/` in workspace root — always activate for any Python work

---

## PlatformIO Configuration

### Minimal `platformio.ini` for ESP32-S3

```ini
[env:esp32s3]
platform = espressif32
board = esp32-s3-devkitc-1
framework = arduino

build_flags =
    -DARDUINO_USB_MODE=1        ; Native USB
    -DARDUINO_USB_CDC_ON_BOOT=1 ; Serial over USB
    -DBOARD_HAS_PSRAM           ; Enable PSRAM (if board has it)
    -DLV_CONF_INCLUDE_SIMPLE    ; LVGL config
    -DLV_LVGL_H_INCLUDE_SIMPLE

monitor_speed = 115200
upload_port = COM5
monitor_port = COM5

lib_deps =
    moononournation/GFX Library for Arduino@1.4.9
    lvgl/lvgl@^8.4.0
```

### Source file filtering

```ini
; Include all subdirectories
build_src_filter = +<*> +<app/*> +<ui/*> +<ui/tabs/*>

; Or compile only one file for debugging
build_src_filter = +<main.cpp>
```

**Note**: Use `build_src_filter`, NOT `src_filter` (deprecated).

---

## Board Definitions

### Waveshare ESP32-S3-Touch-LCD-2 (SKU 29667)

| Feature | Details |
|---------|---------|
| MCU | ESP32-S3R8 (dual-core LX7, 240MHz) |
| Flash | 16MB |
| PSRAM | 8MB (OPI) |
| LCD | 2" IPS 240×320, ST7789T3 (SPI) |
| Touch | CST816D capacitive (I2C, addr 0x15) |
| IMU | QMI8658 6-axis (I2C, addr 0x6B) |
| Camera | 24-pin FPC for OV2640/OV5640 (8-bit parallel) |
| SD | TF card (SPI, shared bus with LCD) |
| Battery | JST 1.25mm LiPo, ADC on GPIO5 |
| USB | USB-C (native USB OTG) |

#### Pin Map

```
LCD SPI:    SCLK=39, MOSI=38, MISO=40, DC=42, CS=45, RST=-1, BL=1
I2C Bus:    SDA=48, SCL=47 (touch + IMU shared)
SD Card:    CS=41 (shared SPI bus: SCLK=39, MOSI=38, MISO=40)
Camera:     PWDN=17, RESET=-1, XCLK=8
            SIOD=21, SIOC=16  (SEPARATE I2C from main bus!)
            Y9=2, Y8=7, Y7=10, Y6=14, Y5=11, Y4=15, Y3=13, Y2=12
            VSYNC=6, HREF=4, PCLK=9
Battery:    ADC on GPIO5
```

**Critical**: Camera SCCB (GPIO 21/16) is on a **separate I2C bus** from the main I2C (GPIO 48/47). Do NOT mix them.

#### Reference Demo

Official Waveshare demo ZIP: `https://files.waveshare.com/wiki/ESP32-S3-Touch-LCD-2/ESP32-S3-Touch-LCD-2-Demo.zip`

Contains 10 Arduino examples + libraries. Download to `$env:TEMP\ws-demo` and extract. Key files for pin reference:
- `bsp_spi.h`, `bsp_i2c.h`, `bsp_lv_port.h`, `app_camera.h`, `app_system.h`

---

## LVGL Integration

### lv_conf.h Location

Place in `include/lv_conf.h`. PlatformIO finds it via `-DLV_CONF_INCLUDE_SIMPLE`.

**IMPORTANT**: After changing `lv_conf.h`, you MUST do `pio run -t clean` then rebuild. The LVGL library caches compiled objects and won't pick up config changes without a clean build.

### Font Gotcha

The default `lv_conf.h` only enables `lv_font_montserrat_14`. If you reference `lv_font_montserrat_20` etc., you must enable them in `lv_conf.h` AND do a clean rebuild. If you get `undefined reference to lv_font_montserrat_XX`, this is why.

### LVGL Buffer Strategy

```cpp
// With PSRAM — full-frame double buffer (best performance)
lv_color_t *buf1 = (lv_color_t *)heap_caps_malloc(W * H * sizeof(lv_color_t), MALLOC_CAP_SPIRAM);
lv_color_t *buf2 = (lv_color_t *)heap_caps_malloc(W * H * sizeof(lv_color_t), MALLOC_CAP_SPIRAM);

// Without PSRAM — small internal buffer (still works, just slower)
lv_color_t *buf1 = (lv_color_t *)heap_caps_malloc(W * 40 * sizeof(lv_color_t), MALLOC_CAP_INTERNAL);
```

### LVGL Task Pattern

Run LVGL on a dedicated FreeRTOS task pinned to core 1:

```cpp
static void lvgl_task(void *param) {
    while (1) {
        uint32_t ms = lv_timer_handler();
        vTaskDelay(pdMS_TO_TICKS(ms < 5 ? 5 : ms > 500 ? 500 : ms));
    }
}
xTaskCreatePinnedToCore(lvgl_task, "lvgl", 10240, NULL, 5, NULL, 1);
```

Always protect LVGL API calls with a mutex:
```cpp
if (lvgl_lock(-1)) {
    // ... LVGL calls ...
    lvgl_unlock();
}
```

---

## Display (SPI LCD)

### Arduino_GFX pattern (GFX Library for Arduino)

```cpp
#include <Arduino_GFX_Library.h>

// Create in setup(), NOT as globals (crashes on Arduino core 2.x!)
Arduino_DataBus *bus = new Arduino_ESP32SPI(DC, CS, SCLK, MOSI, MISO);
Arduino_GFX *gfx = new Arduino_ST7789(bus, RST, ROTATION, true /*IPS*/, W, H);

gfx->begin();
gfx->fillScreen(0x0000);   // BLACK — use literal 0x0000 (GFX 1.6.x removed named constant)
pinMode(BL_PIN, OUTPUT);
digitalWrite(BL_PIN, HIGH);
```

**CRITICAL (Arduino Core 3.x):** Do NOT call `SPIClass::begin()` before `gfx->begin()`. On Core 3.x the GFX library's `Arduino_ESP32SPI` claims the FSPI bus exclusively — pre-initializing the bus causes `gfx->begin()` to deadlock. Only create the SPI mutex in `bsp_spi_init()`; let the GFX library handle actual bus initialization.

### GFX Library Version Compatibility

| GFX Version | Arduino Core | Notes |
|-------------|-------------|-------|
| 1.4.9 | 2.x (espressif32@6.x) | Stable, pin this version |
| 1.5.x+ | 3.x required | API changes, new ESP-IDF |
| 1.6.x | 3.x (pioarduino) | Works — `BLACK` constant removed, use `0x0000` |

---

## Touch Input

### CST816D (I2C capacitive touch)

Library: `bsp_cst816` (copy from Waveshare demo into `lib/`)

```cpp
#include "bsp_cst816.h"
bsp_touch_init(&Wire, rotation, width, height);  // Call after Wire.begin()
bsp_touch_read();
uint16_t x, y;
if (bsp_touch_get_coordinates(&x, &y)) {
    // Touch detected at (x, y)
}
```

---

## Build & Flash Workflow

### Proxy Setup (Intel Employees Only)

> **This section is only for Intel employees behind the corporate proxy. Students and external participants should skip this.**

PlatformIO needs internet access to download libraries and platform packages on first build. If you're on the Intel corporate network, set the proxy before running `pio`:

```powershell
# PowerShell — set for current session
$env:HTTP_PROXY  = "http://proxy-iil.intel.com:912"
$env:HTTPS_PROXY = "http://proxy-iil.intel.com:912"
```

Or run `proxy.bat` (in repo root) from `cmd.exe` before building.

Once libraries are downloaded and cached locally (in `.pio/libdeps/`), the proxy is no longer needed for subsequent builds.

### Standard Build-Flash-Monitor Cycle

```powershell
# Build
pio run *>&1 | Out-File build-result.log -Encoding ascii

# Check result
Select-String -Path build-result.log -Pattern "error:|SUCCESS|FAILED|RAM:|Flash:"

# Flash (ensure no serial monitor is holding the port!)
pio run -t upload

# Monitor
pio device monitor --filter=direct
```

### Killing Stuck Serial Monitors

Serial monitor processes hold COM port. Find and kill them before uploading:

```powershell
Get-Process python* | ForEach-Object {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
    if ($cmd -match "monitor") { Stop-Process -Id $_.Id -Force }
}
```

### Clean Build (when changing lv_conf.h or build flags)

```powershell
pio run -t clean
pio run
```

---

## Serial Monitor Tips

- Use `pio device monitor --filter=direct` for raw output
- Accumulated terminal history pollutes output — use background terminals or write to log files
- After flash, board resets automatically. Add `delay(2000)` before first `Serial.println()` to catch output
- Boot loop signature: `rst:0x3 (RTC_SW_SYS_RST)` repeating = crash before setup()

---

## Lessons Learned

### CRITICAL: No Global `new` for Hardware Objects on Arduino Core 2.x

**Problem**: Code like this crashes with a boot loop:
```cpp
// CRASHES on Arduino core 2.x — static init runs before hardware ready
Arduino_DataBus *bus = new Arduino_ESP32SPI(...);
Arduino_GFX *gfx = new Arduino_ST7789(...);
```

**Fix**: Declare as `nullptr`, construct in `setup()`:
```cpp
Arduino_DataBus *bus = nullptr;
Arduino_GFX *gfx = nullptr;

void setup() {
    bus = new Arduino_ESP32SPI(...);
    gfx = new Arduino_ST7789(bus, ...);
}
```

The Waveshare demos use global `new` because they target Arduino core 3.x. On PlatformIO espressif32@6.x (core 2.x), defer all hardware object construction to `setup()`.

### UART Audio Bridge Between Two ESP32 Boards (Breadboard)

Sending PCM audio from one ESP32 to another over UART on breadboard wires. Hard-won BKM:

**Working config:**
- **460800 baud** — 921600 causes 37-50% CRC errors on breadboard (capacitance/crosstalk)
- **Binary framed** protocol with CRC8: `[0xAA][0x55][CMD][LEN_LO][LEN_HI][PAYLOAD][CRC8]`
- **256-byte frames** with `flush()` + `delayMicroseconds(800)` between frames
- **Buffer-all-then-play** — NOT streaming. Sender transmits all data, then receiver plays from buffer
- **2:1 decimation on sender** (24kHz→12kHz) — halves data to fit in RAM-constrained receiver

**Why streaming fails at 460800:**
460800 raw throughput = 46,080 B/s. I2S at 24kHz/16-bit needs 48,000 B/s. With protocol overhead + pacing delay, effective ~39 KB/s. Ring buffer drains faster than it fills → underruns → noise/clicks even with zero CRC errors.

**Why 921600 fails on breadboard:**
Breadboard jumper wires have high capacitance and crosstalk at near-MHz signaling rates. Every test at 921600 produced 37-50% frame CRC errors. Every test at 460800 produced zero CRC errors.

**Capacity:** ~101KB buffer on ESP32-D0WD-V3 (no PSRAM) = 4.2 sec speech at 12kHz/16-bit. 12kHz speech quality is excellent (better than telephone).

**Key pattern — sender decimation:**
```cpp
// In sender's play_pcm(): take every other sample for 2:1 downsampling
const int16_t *samples = (const int16_t *)data;
for (size_t i = 0; i < total_samples; i += 2) {
    chunk_buf[pos++] = samples[i] & 0xFF;
    chunk_buf[pos++] = (uint16_t)samples[i] >> 8;
}
// Report halved sample rate to receiver: audio_start(sample_rate / 2, 16, 1)
```

### PSRAM Detection on ESP32-S3

The `esp32-s3-devkitc-1` board definition defaults to "No PSRAM". Adding `-DBOARD_HAS_PSRAM` alone isn't enough — the board's `board_build.arduino.memory_type` must be set for OPI PSRAM. This is a PlatformIO board config issue, not a code issue.

### LVGL lv_conf.h Not Propagated to Libraries

PlatformIO may not include the project's `include/` directory when compiling the LVGL library. After changing `lv_conf.h`, always do a `pio run -t clean` to force full recompilation. Look for `undefined reference to lv_font_*` as the telltale sign.

### SPI Bus Sharing (LCD + SD Card)

The LCD and SD card share SPI pins (SCLK, MOSI, MISO) with separate CS lines. Use a mutex to prevent concurrent access:
```cpp
if (bsp_spi_lock(-1)) {
    // Access LCD or SD...
    bsp_spi_unlock();
}
```

### Camera SCCB is Separate I2C

The camera's SCCB interface (GPIO 21/16) is NOT on the main I2C bus (GPIO 48/47). Do not call `Wire.begin()` on camera pins — the camera driver handles its own I2C internally.

### Terminal History Pollution

PlatformIO terminals accumulate output across multiple commands. When running builds in a shared terminal, old errors appear alongside new output. Workarounds:
- Use `*>&1 | Out-File build.log` and read the log file
- Use background terminals (`isBackground: true`) for builds
- Grep build logs for `SUCCESS|FAILED|error:` to find actual result

### Board Boots But Screen Black

If serial prints work but display is black:
1. Check backlight pin — `pinMode(BL, OUTPUT); digitalWrite(BL, HIGH);`
2. Check SPI pin assignments match the board
3. Verify GFX library version is compatible with Arduino core version
4. Confirm `gfx->begin()` returns true

### Boot Loop Diagnosis

`rst:0x3 (RTC_SW_SYS_RST)` repeating = watchdog reset from crash.
Common causes:
1. Global `new` of SPI/I2C objects (see above)
2. 16MB flash config with wrong bootloader
3. PSRAM init failure with PSRAM-dependent code
4. Stack overflow in a task

**Debug strategy**: Strip to absolute minimum `setup()`, confirm it boots, then add one thing at a time.

### pioarduino Migration (espressif32@6.x → pioarduino)

**When**: You need PSRAM OPI on ESP32-S3 rev v0.2, or want ESP-IDF 5.x features.

**Steps**:
1. Change `platform` in platformio.ini to pioarduino URL
2. Add `board_build.arduino.memory_type = dio_opi` and `board_build.flash_mode = dio`
3. Remove `esp32-camera` from lib_deps (built into ESP-IDF 5.x)
4. Unpin GFX version (1.4.9 → latest, currently 1.6.5)
5. Add `-I include` to build_flags (lv_conf.h path fix for LVGL)
6. Fix `BLACK` → `0x0000` in any `gfx->fillScreen(BLACK)` calls
7. Do `pio run -t erase` before first upload (flash layout changed)
8. Set `$env:PYTHONIOENCODING="utf-8"` before upload on Windows (esptool encoding fix)

**Result**: 8189K PSRAM available, 256K heap, all libraries compile cleanly.

### pioarduino Python Environment Issues

pioarduino's PlatformIO penv uses `uv` package manager. If dependencies break:
```powershell
cd $env:USERPROFILE\.platformio\penv
.\Scripts\uv.exe pip install platformio@https://github.com/pioarduino/platformio-core/archive/refs/heads/develop.zip
.\Scripts\uv.exe pip install littlefs-python fatfs-ng pyyaml rich-click zopfli intelhex rich "urllib3<2" "cryptography>=45.0.3" "marshmallow>=3,<4"
```

### esptool Upload Encoding Error on Windows

**Symptom**: `UnicodeEncodeError: 'charmap' codec can't encode characters` during upload.
**Fix**: Set `$env:PYTHONIOENCODING="utf-8"` in the terminal before running `pio run -t upload`.
Note: `chcp 65001` alone is NOT sufficient — the env var must be set for the Python process.

---

## Project Structure Template

```
firmware/<project-name>/
├── platformio.ini
├── include/
│   ├── pins.h          # All GPIO pin definitions
│   └── lv_conf.h       # LVGL configuration
├── src/
│   ├── main.cpp        # Entry point: setup() + loop()
│   ├── bsp_spi.cpp/h   # SPI bus init + mutex
│   ├── bsp_i2c.cpp/h   # I2C bus init + mutex
│   ├── bsp_lv_port.cpp/h  # LVGL display + touch drivers
│   ├── app/
│   │   ├── app_system.cpp/h   # System info (temp, battery, SD)
│   │   ├── app_camera.cpp/h   # Camera capture
│   │   ├── app_qmi8658.cpp/h  # IMU data
│   │   └── app_wifi.cpp/h     # WiFi + web server
│   └── ui/
│       ├── ui.c/h        # UI init (creates tabview)
│       └── tabs/
│           ├── tabview.h       # Shared tab declarations
│           ├── system_tab.c    # System info tab
│           ├── camera_tab.c    # Camera preview tab
│           ├── qmi8658_tab.c   # IMU data tab
│           └── wifi_tab.c      # WiFi config tab
└── lib/
    ├── bsp_cst816/      # Touch driver (from Waveshare demo)
    └── FastIMU/         # IMU driver (if not on PlatformIO registry)
```
