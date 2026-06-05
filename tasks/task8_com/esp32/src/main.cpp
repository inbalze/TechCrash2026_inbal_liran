#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

HardwareSerial fpga_uart(2); // RX=17, TX disabled

static constexpr uint8_t OLED_W = 128;
static constexpr uint8_t OLED_H = 64;
static constexpr int OLED_RST = -1;
static constexpr uint8_t OLED_ADDR = 0x3C;

static constexpr int I2C_SDA_PIN = 27;
static constexpr int I2C_SCL_PIN = 26;

Adafruit_SSD1306 display(OLED_W, OLED_H, &Wire, OLED_RST);

static uint32_t raw_rx_count = 0;
static uint32_t frame_count = 0;
static uint32_t bad_header_count = 0;
static uint16_t last_payload = 0;
static bool has_payload = false;
static unsigned long last_ui_ms = 0;
static int last_key0 = 0;
static int last_key1 = 0;
static uint16_t last_sw = 0;

void draw_status() {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    display.println("FPGA UART -> OLED");

    display.setCursor(0, 12);
    display.print("raw=");
    display.print(raw_rx_count);
    display.print(" ok=");
    display.print(frame_count);

    display.setCursor(0, 22);
    display.print("bad=");
    display.print(bad_header_count);

    display.setCursor(0, 34);
    if (has_payload) {
        display.print("p=0x");
        display.print(last_payload, HEX);
        display.print(" k0=");
        display.print(last_key0);
        display.print(" k1=");
        display.print(last_key1);

        display.setCursor(0, 46);
        display.print("sw=");
        for (int i = 9; i >= 0; --i) {
            display.print((last_sw >> i) & 0x1);
        }
    } else {
        display.print("waiting frame...");
    }

    display.display();
}

void setup() {
    Serial.begin(9600);
    // TX disabled (-1) to avoid driving FPGA TX line by mistake.
    fpga_uart.begin(9600, SERIAL_8N1, 17, -1);

    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
        Serial.println("OLED init failed");
    }
    draw_status();
}

void loop() {
    static int have_prev = 0;
    static uint8_t prev_b = 0;

    while (fpga_uart.available() > 0) {
        uint8_t b = static_cast<uint8_t>(fpga_uart.read());
        raw_rx_count++;
        Serial.write(b);

        if (!have_prev) {
            prev_b = b;
            have_prev = 1;
            continue;
        }

        uint16_t payload = static_cast<uint16_t>(prev_b << 8) | b;
        prev_b = b;

        if ((payload & 0xF000) == 0xA000) {
            frame_count++;
            has_payload = true;
            last_payload = payload;

            uint16_t data12 = payload & 0x0FFF;
            last_key0 = (data12 & 0x0001) ? 1 : 0;
            last_key1 = (data12 & 0x0002) ? 1 : 0;
            last_sw = static_cast<uint16_t>((data12 >> 2) & 0x03FF);
        } else {
            bad_header_count++;
        }
    }

    unsigned long now = millis();
    if (now - last_ui_ms >= 200UL) {
        last_ui_ms = now;
        draw_status();
    }
}
