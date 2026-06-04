// =============================================================
// CrashTech VLSI-2026 — Challenge 2: 3D Cube Tilt (ESP32 side)
//
// Pipeline:
//   UART RX (GPIO33, 115200)
//     → frame parser + CRC8 check
//     → EMA low-pass filter on X/Y/Z
//     → axis-angle rotation matrix from gravity vector
//     → project 8 cube vertices → 2D
//     → off-screen Adafruit GFX buffer → SSD1306 display
//
// Pin assignments (only 12-14, 25-27, 32-35):
//   GPIO 33  — UART RX from FPGA ARDUINO_IO[1] (115200 8N1)
//   GPIO 26  — OLED I2C SDA
//   GPIO 27  — OLED I2C SCL
//
// Frame format (9 bytes from FPGA):
//   [0x55][0xAA][X_H][X_L][Y_H][Y_L][Z_H][Z_L][CRC8]
//   CRC8 = XOR of bytes 0..7
// =============================================================

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <math.h>

// ---- Pin definitions ----------------------------------------
static constexpr int PIN_UART_RX = 33;
static constexpr int PIN_SDA     = 26;
static constexpr int PIN_SCL     = 27;

// ---- OLED ---------------------------------------------------
static constexpr int SCREEN_W  = 128;
static constexpr int SCREEN_H  = 64;
static constexpr int OLED_ADDR = 0x3C;

static Adafruit_SSD1306 oled(SCREEN_W, SCREEN_H, &Wire, -1);
static bool             oledOk = false;

// ---- UART frame state machine -------------------------------
static constexpr int  FRAME_LEN  = 9;
static constexpr uint8_t SYNC1   = 0x55;
static constexpr uint8_t SYNC2   = 0xAA;

enum class RxState : uint8_t {
    WAIT_SYNC1,
    WAIT_SYNC2,
    RECV_DATA      // collecting bytes 2..8
};

static RxState rxState   = RxState::WAIT_SYNC1;
static uint8_t rxBuf[FRAME_LEN];
static int     rxCount   = 0;   // bytes collected in RECV_DATA

// ---- EMA filter (alpha = 0.2 → τ ≈ 5 samples) -------------
// Stored as fixed-point: value = ema_fp / 256.0f
static constexpr float EMA_ALPHA = 0.2f;
static float ema_x = 0.0f;
static float ema_y = 0.0f;
static float ema_z = -256.0f;  // initialise near −1g (flat on table)

// ---- Cube geometry ------------------------------------------
// 8 vertices of a unit cube centred at origin, scale 20 px
static constexpr float CUBE_S = 20.0f;

static const float CUBE_V[8][3] = {
    {-1, -1, -1},
    { 1, -1, -1},
    { 1,  1, -1},
    {-1,  1, -1},
    {-1, -1,  1},
    { 1, -1,  1},
    { 1,  1,  1},
    {-1,  1,  1}
};

// 12 edges as index pairs
static const uint8_t CUBE_E[12][2] = {
    {0,1},{1,2},{2,3},{3,0},   // back face
    {4,5},{5,6},{6,7},{7,4},   // front face
    {0,4},{1,5},{2,6},{3,7}    // connecting edges
};

// ---- Projection parameters ----------------------------------
static constexpr float FOV_D    = 90.0f;  // "eye" distance for perspective
static constexpr int   CENTER_X = SCREEN_W / 2;
static constexpr int   CENTER_Y = SCREEN_H / 2;

// ---- Forward declarations -----------------------------------
static void onFrameReceived(const uint8_t* buf);
static void renderCube();
static void project(const float v[3], const float R[3][3],
                    int& px, int& py);
static void buildRotMatrix(float gx, float gy, float gz,
                           float R[3][3]);

// ---- Rotation matrix (updated by UART, read by render) -----
static float gR[3][3] = {
    {1,0,0},
    {0,1,0},
    {0,0,1}
};
static volatile bool newFrame = false;

// =============================================================
void setup() {
    Serial.begin(115200);
    Serial.println("[cube_tilt] boot");

    // UART2: RX-only from FPGA
    Serial2.begin(115200, SERIAL_8N1, PIN_UART_RX, -1);

    // I2C for OLED
    Wire.begin(PIN_SDA, PIN_SCL);
    Wire.setClock(400000);

    oledOk = oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
    if (!oledOk) {
        Serial.println("[!] OLED init failed");
    } else {
        oled.clearDisplay();
        oled.setTextSize(1);
        oled.setTextColor(SSD1306_WHITE);
        oled.setCursor(20, 26);
        oled.print("3D Cube Tilt");
        oled.display();
    }
}

// =============================================================
void loop() {
    // ---- Non-blocking UART ingestion -------------------------
    while (Serial2.available() > 0) {
        const uint8_t b = static_cast<uint8_t>(Serial2.read());

        switch (rxState) {
            case RxState::WAIT_SYNC1:
                if (b == SYNC1) {
                    rxBuf[0] = b;
                    rxState  = RxState::WAIT_SYNC2;
                }
                break;

            case RxState::WAIT_SYNC2:
                if (b == SYNC2) {
                    rxBuf[1] = b;
                    rxCount  = 0;
                    rxState  = RxState::RECV_DATA;
                } else {
                    // Could be a new SYNC1 — check
                    rxState = (b == SYNC1) ? RxState::WAIT_SYNC2
                                           : RxState::WAIT_SYNC1;
                    rxBuf[0] = b;
                }
                break;

            case RxState::RECV_DATA:
                rxBuf[2 + rxCount] = b;
                rxCount++;
                if (rxCount == FRAME_LEN - 2) {  // collected bytes 2..8
                    rxState = RxState::WAIT_SYNC1;
                    onFrameReceived(rxBuf);
                }
                break;
        }
    }

    // ---- Render once per fresh frame -------------------------
    if (newFrame) {
        newFrame = false;
        renderCube();
    }
}

// =============================================================
// onFrameReceived — verify CRC and update EMA + rotation matrix
// =============================================================
static void onFrameReceived(const uint8_t* buf) {
    // CRC check: XOR of bytes 0..7 must equal byte 8
    uint8_t crc = 0;
    for (int i = 0; i < 8; i++) crc ^= buf[i];
    if (crc != buf[8]) {
        Serial.printf("[UART] CRC mismatch: calc=0x%02X got=0x%02X\n",
                      crc, buf[8]);
        return;
    }

    // Reconstruct signed 16-bit values (big-endian in frame)
    const int16_t raw_x = static_cast<int16_t>((buf[2] << 8) | buf[3]);
    const int16_t raw_y = static_cast<int16_t>((buf[4] << 8) | buf[5]);
    const int16_t raw_z = static_cast<int16_t>((buf[6] << 8) | buf[7]);

    // EMA low-pass filter
    ema_x += EMA_ALPHA * (static_cast<float>(raw_x) - ema_x);
    ema_y += EMA_ALPHA * (static_cast<float>(raw_y) - ema_y);
    ema_z += EMA_ALPHA * (static_cast<float>(raw_z) - ema_z);

    // Build rotation matrix from gravity vector (no gimbal lock)
    buildRotMatrix(ema_x, ema_y, ema_z, gR);
    newFrame = true;
}

// =============================================================
// buildRotMatrix
//
// The gravity vector (gx, gy, gz) points "down" in sensor frame.
// We want the rotation that maps the world -Z axis to that vector,
// i.e. we find the rotation axis = (-Z) × g_hat and the rotation
// angle = acos(-Z · g_hat).
//
// Result R rotates cube vertices from "model space" to "tilted world".
//
// Uses Rodrigues' rotation formula:
//   R = I·cosθ + (1−cosθ)·k⊗k + sinθ·[k]×
// where k is the unit rotation axis.
// =============================================================
static void buildRotMatrix(float gx, float gy, float gz,
                           float R[3][3]) {
    // Normalise gravity vector
    const float glen = sqrtf(gx*gx + gy*gy + gz*gz);
    if (glen < 1e-6f) {
        // No meaningful tilt — identity
        R[0][0]=1; R[0][1]=0; R[0][2]=0;
        R[1][0]=0; R[1][1]=1; R[1][2]=0;
        R[2][0]=0; R[2][1]=0; R[2][2]=1;
        return;
    }
    const float nx = gx / glen;
    const float ny = gy / glen;
    const float nz = gz / glen;

    // Reference "down" direction in model space = (0, 0, -1)
    // Rotation axis k = (0,0,-1) × (nx,ny,nz)
    //   = ( 0·nz − (−1)·ny,  (−1)·nx − 0·nz,  0·ny − 0·nx )
    //   = ( ny, -nx, 0 )
    float kx = ny;
    float ky = -nx;
    float kz = 0.0f;
    const float klen = sqrtf(kx*kx + ky*ky + kz*kz);

    // cosθ = (0,0,-1)·(nx,ny,nz) = -nz
    const float cosA = -nz;

    if (klen < 1e-6f) {
        // Gravity is already along ±Z — either identity or 180° flip
        if (cosA > 0.0f) {
            R[0][0]=1; R[0][1]=0; R[0][2]=0;
            R[1][0]=0; R[1][1]=1; R[1][2]=0;
            R[2][0]=0; R[2][1]=0; R[2][2]=1;
        } else {
            // 180° rotation around X axis
            R[0][0]=1; R[0][1]= 0; R[0][2]= 0;
            R[1][0]=0; R[1][1]=-1; R[1][2]= 0;
            R[2][0]=0; R[2][1]= 0; R[2][2]=-1;
        }
        return;
    }

    kx /= klen;
    ky /= klen;
    // kz is already 0

    const float sinA  = klen;   // sinA = |k_pre_normalise| = |(ny,-nx,0)|
                                 // since |g_hat|=1 → sinA = sqrt(nx²+ny²)
    const float omcos = 1.0f - cosA;

    // Rodrigues
    R[0][0] = cosA + kx*kx*omcos;
    R[0][1] = kx*ky*omcos - kz*sinA;
    R[0][2] = kx*kz*omcos + ky*sinA;

    R[1][0] = ky*kx*omcos + kz*sinA;
    R[1][1] = cosA + ky*ky*omcos;
    R[1][2] = ky*kz*omcos - kx*sinA;

    R[2][0] = kz*kx*omcos - ky*sinA;
    R[2][1] = kz*ky*omcos + kx*sinA;
    R[2][2] = cosA + kz*kz*omcos;
}

// =============================================================
// project — apply rotation then weak perspective projection
// =============================================================
static void project(const float v[3], const float R[3][3],
                    int& px, int& py) {
    // Rotate
    const float rx = R[0][0]*v[0] + R[0][1]*v[1] + R[0][2]*v[2];
    const float ry = R[1][0]*v[0] + R[1][1]*v[1] + R[1][2]*v[2];
    const float rz = R[2][0]*v[0] + R[2][1]*v[1] + R[2][2]*v[2];

    // Perspective divide: eye at z = FOV_D
    const float denom = FOV_D + rz;
    const float scale = (denom > 1.0f) ? (FOV_D / denom) : 1.0f;

    px = CENTER_X + static_cast<int>(rx * CUBE_S * scale);
    py = CENTER_Y - static_cast<int>(ry * CUBE_S * scale);  // Y-down on display
}

// =============================================================
// renderCube — off-screen GFX buffer → display
// =============================================================
static void renderCube() {
    if (!oledOk) return;

    oled.clearDisplay();

    // Project all 8 vertices
    int px[8], py[8];
    for (int i = 0; i < 8; i++) {
        project(CUBE_V[i], gR, px[i], py[i]);
    }

    // Draw 12 edges
    for (int e = 0; e < 12; e++) {
        const int a = CUBE_E[e][0];
        const int b = CUBE_E[e][1];
        oled.drawLine(px[a], py[a], px[b], py[b], SSD1306_WHITE);
    }

    oled.display();
}
