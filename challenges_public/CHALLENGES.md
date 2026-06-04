# CrashTech VLSI-2026 - Competition Challenges

---
## Challenge 1: Volt-Meter (10 pts)
**Difficulty:** Easy
**Points:** 10 (all or nothing)
**Category:** Combined (ESP32 + FPGA)

### Description
Build a digital volt-meter that reads the potentiometer voltage and displays it on both the OLED screen and the FPGA 7-segment displays.

### Requirements
- ESP32 reads the potentiometer (GPIO34 ADC) and converts to voltage (0-3.3V)
- Voltage is displayed on the OLED screen in large text (e.g. "1.65V")
- ESP32 sends the voltage value over UART to the FPGA
- FPGA displays the voltage on the 7-segment displays as X.XX (with decimal point)
- LED bar graph on LEDR[9:0] shows voltage level proportionally

### Grading
Go / No-Go. All requirements must work for full 10 points. No partial credit.

---

## Challenge 2: Accelerometer 3D Cube (30 pts)
**Difficulty:** Medium
**Points:** 30 (all or nothing)
**Category:** Combined (FPGA + ESP32)

### Description
Read the onboard ADXL345 accelerometer on the FPGA, send the raw acceleration data over UART to the ESP32, and draw a wireframe 3D cube on the OLED that rotates in real-time as you tilt the board.

### Requirements
- FPGA reads X, Y, Z acceleration from the onboard ADXL345 via SPI
- FPGA sends raw acceleration bytes to ESP32 over UART (GPIO header)
- ESP32 receives the data and computes tilt angles (pitch and roll)
- A wireframe 3D cube is rendered on the OLED display
- The cube rotates smoothly in response to tilting the DE10-Lite board
- FPGA LEDs show tilt direction (left/right/forward/back)

### Grading
Go / No-Go. All requirements must work for full 30 points. No partial credit.

---

## Challenge 3: Speed Loopback (50 + 200/150/100 pts)
**Difficulty:** Hard
**Points:** 50 baseline + podium bonus (200 / 150 / 100)
**Category:** Combined (FPGA + ESP32)

### Description
The FPGA generates 10,000 pseudo-random bytes and sends them to the ESP32. The ESP32 must receive all bytes, compute the checksum (sum & 0xFF), and send it back. The FPGA verifies the checksum and displays the elapsed time in milliseconds on the 7-segment displays.

Base code (FPGA + ESP32) and challenge HTML page with block diagram are provided in `challenges/speed-loopback/`.

### What You Get
- Working FPGA bitstream with fixed infrastructure (LFSR, sum, timer, comparator)
- Baseline ESP32 firmware using single 9600-baud UART (~10.4 seconds)
- Full HTML page explaining the architecture, rules, and optimization ideas

### Rules
- DO NOT modify the FPGA fixed infrastructure (LFSR, sum accumulator, timer, comparator, state machine, data count)
- You MAY replace the UART TX/RX modules, change baud rates, add parallel channels, switch to SPI, or use any communication method
- You MAY fully rewrite the ESP32 firmware
- You MAY use any GPIO pins on the JP1 header or Arduino header (Arduino header is easier - male pins, use male-male jumper wires)

### Grading
- **50 points:** Achieve at least 4x improvement over baseline (complete in under 2,600 ms with correct checksum)
- **Podium bonus (top 3 fastest correct times):**
  - 1st place: +200 points
  - 2nd place: +150 points
  - 3rd place: +100 points

---

## Challenge 4: Press Right (20 pts)
**Difficulty:** Easy
**Points:** 20 (all or nothing)
**Category:** Combined (FPGA + ESP32)

### Description
A fast counter on the FPGA increments every 1/100th of a second (10ms), displayed on the 7-segment displays. Press KEY[0] to start the counter, then press KEY[0] again to stop it. The goal is to stop it exactly at 1000 (= 10.00 seconds). The stopped value is sent to the ESP32. If you stop within 1000 +/- 10 (i.e. 990 to 1010), the ESP32 plays a victory buzzer.

### Requirements
- FPGA counter increments every 10ms, shown on HEX3..0 as a 4-digit decimal number
- KEY[0] starts the counter, KEY[0] again stops it
- Stopped value is sent to ESP32 over UART
- ESP32 receives the value and plays the buzzer if within +/- 10 of 1000
- OLED shows the stopped value and whether you won or missed
- LEDs show how close you were (more LEDs = closer to 1000)

### Grading
Go / No-Go. All requirements must work for full 20 points. No partial credit.

---

## Challenge 5: FPGA Volt-Meter (20 pts)
**Difficulty:** Medium
**Points:** 20 (all or nothing)
**Category:** Combined (FPGA + ESP32)

### Description
Read an analog voltage using the FPGA's internal ADC (MAX 10 ADC), display it on the 7-segment displays, and send the value to the ESP32 to show on the OLED screen. This is the reverse direction of Challenge 1: the FPGA does the analog reading, not the ESP32.

### Requirements
- FPGA reads analog input from Arduino header pin A0 using the internal MAX 10 ADC
- Voltage (0-3.3V) is displayed on the 7-segment displays as X.XX with decimal point
- FPGA sends the voltage value over UART to the ESP32
- ESP32 displays the voltage on the OLED in large text
- LED bar graph on LEDR[9:0] shows voltage level proportionally
- Display updates live as the input voltage changes

### Grading
Go / No-Go. All requirements must work for full 20 points. No partial credit.

---

## Challenge 6: Frequency Detector (100 pts)
**Difficulty:** Medium-Hard
**Points:** 100 (all or nothing)
**Category:** Combined (FPGA + ESP32)

### Description
The ESP32 reads a potentiometer and generates a digital sine wave at the corresponding frequency (100-2000 Hz). It sends 256 raw signed samples over UART to the FPGA. The FPGA must detect the frequency of the signal and display it on the 7-segment displays.

### Requirements
- ESP32 reads potentiometer (GPIO34 ADC) and maps 0-4095 to 100-2000 Hz
- ESP32 generates 256 samples of a sine wave at 8000 Hz sample rate
- Samples are sent as raw signed 8-bit bytes over UART (115200 baud) to FPGA via GPIO header
- FPGA receives the 256-byte frame and detects the signal frequency
- Detected frequency is displayed on HEX3..0 in Hz (e.g. "1085")
- Accuracy must be within 35 Hz of the ESP32's generated frequency
- **Note:** A 50-100 Hz deviation is acceptable and expected given the 31 Hz bin resolution
- LED bar graph shows frequency band (more LEDs = higher frequency)
- SW[9] toggles debug mode (show raw detection internals)

### Hints
- Sample rate = 8000 Hz, window = 256 samples → frequency resolution ≈ 31 Hz
- Zero-crossing detection is the simplest approach (count sign changes)
- FFT is the "proper" approach but requires ROM for twiddle factors (watch out for MAX 10 configuration mode limitations)
- Frame synchronization: use a gap timeout between 256-byte bursts

### Grading
Go / No-Go. All requirements must work for full 100 points. No partial credit.

---

## Challenge 7: FP8 Adder Race (80 + 150/100/50 pts)

**Difficulty:** Hard
**Points:** 80 for a valid 2x speedup + podium bonus (150 / 100 / 50)
**Scoring model:** Performance + Correctness
**Category:** FPGA-only

### Challenge Description

You are given a fully working starter project for an FP8 E4M3 adder on the DE10-Lite. The harness is mostly locked: it feeds 4096 operand pairs from ROM, checks every result against the golden reference, and shows the total elapsed time on the 7-segment displays. The exception is the DUT clock PLL, which teams may tune.

Your job is to optimize the adder core so the board finishes faster while still passing every test.

Starter code, Quartus project, simulator testbench, reference Python model, and a full challenge explanation page are provided in `challenges/fp8-adder/`.

### Starter Kit

- A correct but intentionally slow multi-cycle reference implementation in `fpga/src/fp8_adder.v`
- An editable PLL in `fpga/src/challenge_pll.v` for the DUT/test clock
- A locked board harness that runs all 4096 tests and measures elapsed time in decimal microseconds
- Pre-generated operand and expected-result ROM contents
- A Python FP8 E4M3 reference model used to generate the vectors
- A self-checking simulation testbench matching the same vector set used on hardware

### Challenge Rules

- You may modify `fpga/src/fp8_adder.v`
- You may modify `fpga/src/challenge_pll.v`
- You may add helper modules if they are instantiated from `fp8_adder.v`
- You must keep the same DUT interface: `clk`, `rst_n`, `start`, `a`, `b`, `result`, `done`, `busy`
- You may not modify the harness, display logic, test controller, ROM wrapper, pin assignments, or test-vector files
- You may tune the PLL-driven DUT/test clock, but you may not modify the separate fixed 25 MHz measurement clock path
- Your design only counts as correct if all 4096 tests pass on the board (`LEDR[0] = 1` at the end)

### Challenge Grading

- **80 points:** achieve at least 2x speedup versus the provided starter while still passing all 4096 vectors
- **Podium bonus (fastest correct designs on the board):**
  - 1st place: +150 points
  - 2nd place: +100 points
  - 3rd place: +50 points

### Board Notes

- The 7-segment display shows total elapsed time in decimal microseconds after the run completes
- During the run, the left two digits show `EE` and the LEDs act as a progress bar
- The measurement clock is fixed, but the DUT/test clock can be changed through the editable PLL
- Small measurement edge effects are acceptable. The goal is stable real-time comparison across teams, not cycle-exact stopwatch perfection

### PLL Tuning Tips

- The shipped starter uses `CLK0_MULTIPLY_BY = 1` and `CLK0_DIVIDE_BY = 2`, which gives a 25 MHz DUT/test clock
- Edit only the PLL parameters in `fpga/src/challenge_pll.v`; do not change `fp8_top.v` or the fixed measurement clock path
- Increase frequency in small steps and recompile after every change
- A faster PLL setting is only useful if timing still closes and the board still ends with `LEDR[0] = 1`
- If timing breaks or hardware starts failing, back off the PLL first, then debug the architecture

---

## Challenge 8: PC Retro Game (100 + 250/200/150 pts)
**Difficulty:** Medium
**Points:** 100 baseline + judge ranking bonus
**Category:** Combined (FPGA + ESP32 + PC)

### Description
Build any retro-style PC game controlled by the DE10-Lite board. The FPGA must sample `KEY[0]`, `KEY[1]`, and `SW[9:0]`, send that control state to the ESP32, and the ESP32 must forward it to a Python game running on the PC.

No starter code is provided for this challenge.
Only the challenge description is given. Teams must build their own board-to-ESP32-to-PC pipeline and may choose any retro game they like.

### Requirements
- FPGA reads `KEY[0]`, `KEY[1]`, and all ten switches
- FPGA sends a live control packet to the ESP32 over UART on the JP1 header
- ESP32 bridges the packet stream to the PC over USB serial
- A Python PC game receives the packets and uses them as controls
- The final game may be any retro game, not necessarily Fluppy
- `KEY[0]` must control the main in-game action, for example flap or jump
- `KEY[1]` must be used for a secondary action, for example pause or restart
- The switches must affect gameplay, visuals, difficulty, or debug behavior in a visible way

### Grading
- **100 points:** Go / No-Go. The full chain must work live: board input, ESP32 bridge, PC game response.
- **Judge ranking bonus:**
  - 1st place: 250 points
  - 2nd place: 200 points
  - 3rd, 4th, and 5th place: 150 points

