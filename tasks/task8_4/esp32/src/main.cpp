#include <Arduino.h>

void setup() {
    Serial.begin(115200);
    Serial2.begin(9600, SERIAL_8N1, 16, 17);
}

void loop() {
    while (Serial2.available()) {
        Serial.write(Serial2.read());
    }
}
