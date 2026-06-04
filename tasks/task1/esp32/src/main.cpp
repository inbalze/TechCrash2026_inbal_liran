// =============================================================
// CrashTech VLSI-2026 — Task 1: Voltmeter (ESP32 side)
//
// Reads GPIO34 ADC, displays "X.XXV" on SSD1306 OLED,
// and streams millivolts to FPGA over UART2 (TX=GPIO32).
//
// Pin overrides (differ from pin_config.h defaults):
//   I2C SDA = GPIO26, SCL = GPIO27
//   UART2 TX = GPIO32  → FPGA ARDUINO_IO[0] (D0)
//
// Protocol: 2-byte binary frame, high byte first, then low byte.
// =============================================================

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "../../../../projects/common/esp32/pin_config.h"

static Adafruit_SSD1306 oled(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
static HardwareSerial   FpgaSerial(2);

void setup() {
    Serial.begin(115200);

    analogReadResolution(12);
    analogSetAttenuation(ADC_11db);

    Wire.begin(26, 27);   // SDA=GPIO26, SCL=GPIO27
    oled.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR);
    oled.clearDisplay();
    oled.display();

    // TX only — FPGA does not send back in this task
    FpgaSerial.begin(FPGA_BAUD, SERIAL_8N1, -1, 32);  // TX=GPIO32 → ARDUINO_IO[0]
}

void loop() {
    // analogReadMilliVolts uses built-in ADC calibration (Arduino Core 3.x)
    uint32_t mv = analogReadMilliVolts(PIN_ANALOG_IN);
    if (mv > 3300) mv = 3300;

    float v = (float)mv / 1000.0f;
    char buf[8];
    snprintf(buf, sizeof(buf), "%.2fV", v);

    // OLED: "X.XXV" centred, textSize 3 (18 px/char, 5 chars = 90 px wide)
    oled.clearDisplay();
    oled.setTextColor(SSD1306_WHITE);
    oled.setTextSize(3);
    oled.setCursor(19, 20);
    oled.print(buf);
    oled.display();

    // Send high byte first, then low byte
    FpgaSerial.write((uint8_t)(mv >> 8));
    FpgaSerial.write((uint8_t)(mv & 0xFF));

    delay(100);
}
