// Internet Clock -- ESP32 NTP Time Sender
// Fetches time from NTP server and sends "HH:MM:SS\n" over UART2 to FPGA
// UART2 TX = GPIO16 -> FPGA ARDUINO_IO[0]
// Baud: 9600, 8N1

#include <Arduino.h>
#include <WiFi.h>
#include <time.h>

// ---- WiFi credentials ----
// Replace these placeholders with your local network credentials before flashing.
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// ---- NTP settings ----
const char* NTP_SERVER   = "pool.ntp.org";
const long  GMT_OFFSET   = 2 * 3600;   // Israel Standard Time UTC+2
const int   DST_OFFSET   = 3600;       // Daylight saving +1h (summer)

// UART2 to FPGA
HardwareSerial FpgaSerial(2);  // UART2
const int UART_TX_PIN = 16;
const int UART_RX_PIN = 17;    // Not used but required for begin()
const int UART_BAUD   = 9600;

// Send interval
const unsigned long SEND_INTERVAL_MS = 1000;
unsigned long lastSend = 0;

void connectWiFi() {
    Serial.print("Connecting to WiFi");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println(" connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
}

void setupNTP() {
    configTime(GMT_OFFSET, DST_OFFSET, NTP_SERVER);
    Serial.print("Waiting for NTP sync");
    struct tm timeinfo;
    while (!getLocalTime(&timeinfo)) {
        Serial.print(".");
        delay(500);
    }
    Serial.println(" synced!");
}

void setup() {
    // Debug serial (USB)
    Serial.begin(115200);
    Serial.println("\n--- Internet Clock ESP32 ---");

    // UART2 to FPGA
    FpgaSerial.begin(UART_BAUD, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);

    connectWiFi();
    setupNTP();
}

void loop() {
    unsigned long now = millis();
    if (now - lastSend < SEND_INTERVAL_MS) return;
    lastSend = now;

    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        Serial.println("Failed to get time");
        return;
    }

    // Format: "HH:MM:SS\n"
    char buf[10];
    snprintf(buf, sizeof(buf), "%02d:%02d:%02d",
             timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);

    // Send to FPGA via UART2
    FpgaSerial.println(buf);  // sends "HH:MM:SS\r\n"

    // Debug echo on USB serial
    Serial.println(buf);
}
