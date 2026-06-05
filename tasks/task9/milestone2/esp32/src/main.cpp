// =============================================================================
// Task 9 — Milestone 2: Flappy Bird Neuroevolution
// Features: 30-bird swarm | GA with elitism | Pause | Solo-best-bird view
// UART Protocol:
//   0xFE = Pause / Resume toggle  (KEY[0] on DE10-Lite)
//   0xFD = Solo mode ON           (SW[9] = 1)
//   0xFC = Solo mode OFF          (SW[9] = 0)
//   0x00-0x0F = Difficulty (user override via SW[3:0])
// =============================================================================
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "NeuralNetwork.h"

// ─── Authorised pins only ─────────────────────────────────────────────────────
#define SDA_PIN        26
#define SCL_PIN        27
#define UART_RX_PIN    35
#define UART_TX_DUMMY  12

// ─── OLED ─────────────────────────────────────────────────────────────────────
#define SCREEN_WIDTH   128
#define SCREEN_HEIGHT  64
#define OLED_RESET     -1
#define OLED_ADDR      0x3C

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
HardwareSerial    FpgaSerial(2);

// ─── Simulation constants ─────────────────────────────────────────────────────
#define POP_SIZE       30
#define ELITE_COUNT    4
#define MUTATION_STD   0.12f
#define PIPE_WIDTH     10
#define GRAVITY        0.22f
#define JUMP_IMPULSE  -2.6f
#define BIRD_X         20
#define BIRD_W         8        // 8x6 bird size matches sprite
#define BIRD_H         6
#define FRAME_MS       20       // ~50 FPS

// ─── World (shared / deterministic for all birds) ────────────────────────────
struct Pipe { float x; int gap_y; };
static Pipe pipes[2];

// ─── Dynamic Difficulty Parameters ────────────────────────────────────────────
static float pipe_speed = 1.4f;
static int   gap_size   = 26;
static uint8_t current_difficulty = 0x00;
static bool user_override_difficulty = false;

static void update_difficulty_params() {
    // Speed ranges from 1.4 (diff 0) to 3.2 (diff 15)
    pipe_speed = 1.4f + (current_difficulty * 0.12f);
    // Gap size ranges from 26 (diff 0) to 14 (diff 15)
    gap_size = 26 - current_difficulty;
}

// ─── Per-bird state ───────────────────────────────────────────────────────────
struct Bird {
    float y, vy;
    bool  alive;
    int   fitness;       // frames survived for GA selection
    int   pipes_passed;  // score (obstacles passed)
    NeuralNetwork nn;
};
static Bird birds[POP_SIZE];

// ─── Global sim state ─────────────────────────────────────────────────────────
static int  alive_count = POP_SIZE;
static int  generation  = 1;
static int  best_ever   = 0;       // tracks best obstacles passed
static int  world_score = 0;       // tracks current generation obstacles passed
static bool sim_paused  = false;
static bool solo_mode   = false;   // show only the current best bird

// ─── Sorted rank buffer ───────────────────────────────────────────────────────
static int rank[POP_SIZE];

// ─── Clamp helper ─────────────────────────────────────────────────────────────
static inline float clamp(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// ─── Find the best alive bird index (-1 if none) ─────────────────────────────
static int best_alive_idx() {
    int best = -1;
    for (int i = 0; i < POP_SIZE; i++) {
        if (!birds[i].alive) continue;
        if (best == -1 || birds[i].fitness > birds[best].fitness) best = i;
    }
    return best;
}

static uint32_t generation_seed = 0;

// ─── World helpers ────────────────────────────────────────────────────────────
static int next_gap_y() {
    return 14 + random(0, 37);
}

static void init_world() {
    randomSeed(generation_seed);
    pipes[0].x = 140.0f;         pipes[0].gap_y = next_gap_y();
    pipes[1].x = 140.0f + 70.0f; pipes[1].gap_y = next_gap_y();
}

static const Pipe* nearest_pipe() {
    const Pipe* best = &pipes[0];
    for (int p = 1; p < 2; p++) {
        float dx_b = pipes[p == 0 ? 1 : 0].x - (BIRD_X + BIRD_W);
        float dx_c = pipes[p].x - (BIRD_X + BIRD_W);
        if (dx_c >= -(float)PIPE_WIDTH && (dx_b < -(float)PIPE_WIDTH || dx_c < dx_b))
            best = &pipes[p];
    }
    return best;
}

static void advance_pipes() {
    for (int p = 0; p < 2; p++) {
        float old_x = pipes[p].x;
        pipes[p].x -= pipe_speed;
        
        // Check if pipe's trailing edge has passed the bird's x position
        if (old_x + PIPE_WIDTH >= BIRD_X && pipes[p].x + PIPE_WIDTH < BIRD_X) {
            world_score++;
        }
        
        if (pipes[p].x < -(float)PIPE_WIDTH) {
            pipes[p].x = 128.0f + 50.0f;
            pipes[p].gap_y = next_gap_y();
        }
    }
}

static bool collides(const Bird& b) {
    if (b.y < 0 || b.y + BIRD_H > SCREEN_HEIGHT) return true;
    int bx1 = BIRD_X, bx2 = BIRD_X + BIRD_W;
    int by1 = (int)b.y, by2 = (int)b.y + BIRD_H;
    for (int p = 0; p < 2; p++) {
        int px1 = (int)pipes[p].x, px2 = px1 + PIPE_WIDTH;
        int top = pipes[p].gap_y - gap_size / 2;
        int bot = pipes[p].gap_y + gap_size / 2;
        if (bx2 > px1 && bx1 < px2) {
            if (by1 < top || by2 > bot) return true;
        }
    }
    return false;
}

// ─── GA epoch ─────────────────────────────────────────────────────────────────
static void sort_by_fitness() {
    for (int i = 0; i < POP_SIZE; i++) rank[i] = i;
    for (int i = 1; i < POP_SIZE; i++) {
        int key = rank[i], j = i - 1;
        while (j >= 0 && birds[rank[j]].fitness < birds[key].fitness) {
            rank[j + 1] = rank[j]; j--;
        }
        rank[j + 1] = key;
    }
}

static void run_epoch() {
    // Record best score (obstacles passed)
    for (int i = 0; i < POP_SIZE; i++) {
        if (birds[i].pipes_passed > best_ever) best_ever = birds[i].pipes_passed;
    }

    sort_by_fitness();

    static NeuralNetwork next_gen[POP_SIZE];
    for (int i = 0; i < ELITE_COUNT && i < POP_SIZE; i++)
        next_gen[i].copyFrom(birds[rank[i]].nn);
    for (int i = ELITE_COUNT; i < POP_SIZE; i++) {
        next_gen[i].copyFrom(birds[rank[i % ELITE_COUNT]].nn);
        next_gen[i].mutate(MUTATION_STD);
    }

    generation++;
    generation_seed = esp_random();
    
    // Cycle difficulty if there is no manual user override
    if (!user_override_difficulty) {
        current_difficulty = (generation - 1) % 16;
    }
    update_difficulty_params();

    init_world();
    world_score = 0;

    for (int i = 0; i < POP_SIZE; i++) {
        birds[i].nn.copyFrom(next_gen[i]);
        birds[i].y = 28.0f; birds[i].vy = 0.0f;
        birds[i].alive = true; birds[i].fitness = 0; birds[i].pipes_passed = 0;
    }
    alive_count = POP_SIZE;
}

// ─── Custom Bird Drawing ──────────────────────────────────────────────────────
void draw_flappy_bird(int x, int y, bool is_black = false) {
    uint16_t color = is_black ? SSD1306_BLACK : SSD1306_WHITE;
    // Main body
    display.fillRoundRect(x + 1, y + 1, 6, 5, 2, color);
    // Beak
    display.fillRect(x + 5, y + 2, 3, 2, color);
    // Eye
    display.drawPixel(x + 4, y + 2, is_black ? SSD1306_WHITE : SSD1306_BLACK);
    // Wing
    display.fillRect(x, y + 2, 2, 2, color);
}

// ─── OLED rendering ───────────────────────────────────────────────────────────
static void draw_sim() {
    display.clearDisplay();

    int best_idx = best_alive_idx();

    // ── Pipes ────────────────────────────────────────────────────────────────
    for (int p = 0; p < 2; p++) {
        int px  = (int)pipes[p].x;
        int top = pipes[p].gap_y - gap_size / 2;
        int bot = pipes[p].gap_y + gap_size / 2;
        // Reserve top row for HUD — clip pipes to start at row 9
        int clip_top = max(top, 9);
        if (clip_top > 9)
            display.fillRect(px, 9, PIPE_WIDTH, clip_top - 9, SSD1306_WHITE);
        else if (top <= 9 && bot > 9) {
            // gap starts inside HUD zone — just draw bottom pipe
        } else {
            display.fillRect(px, 9, PIPE_WIDTH, top - 9, SSD1306_WHITE);
        }
        if (bot < SCREEN_HEIGHT)
            display.fillRect(px, bot, PIPE_WIDTH, SCREEN_HEIGHT - bot, SSD1306_WHITE);
    }

    // ── Birds ─────────────────────────────────────────────────────────────────
    if (solo_mode) {
        // Show ONLY the current best bird — styled like a bird
        if (best_idx >= 0) {
            int by = (int)birds[best_idx].y;
            draw_flappy_bird(BIRD_X, by);
        }
    } else {
        for (int i = 0; i < POP_SIZE; i++) {
            if (!birds[i].alive) continue;
            int by = (int)birds[i].y;
            if (i == best_idx) {
                // Best bird: styled like a bird
                draw_flappy_bird(BIRD_X, by);
            } else {
                // Other birds: 2x2 pixel dot (fast, low visual noise)
                display.drawPixel(BIRD_X + BIRD_W / 2,     by + BIRD_H / 2,     SSD1306_WHITE);
                display.drawPixel(BIRD_X + BIRD_W / 2 + 1, by + BIRD_H / 2,     SSD1306_WHITE);
                display.drawPixel(BIRD_X + BIRD_W / 2,     by + BIRD_H / 2 + 1, SSD1306_WHITE);
                display.drawPixel(BIRD_X + BIRD_W / 2 + 1, by + BIRD_H / 2 + 1, SSD1306_WHITE);
            }
        }
    }

    // ── HUD bar (top 8 rows, inverted) ───────────────────────────────────────
    display.fillRect(0, 0, SCREEN_WIDTH, 8, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);   // black text on white bar
    display.setTextSize(1);
    display.setCursor(1, 0);

    if (solo_mode && !sim_paused)
        display.printf("G:%d A:%d B:%d D:%d [SOLO]", generation, alive_count, best_ever, current_difficulty);
    else if (sim_paused)
        display.printf("G:%d A:%d B:%d D:%d [PAUSED]", generation, alive_count, best_ever, current_difficulty);
    else
        display.printf("G:%d A:%d B:%d D:%d", generation, alive_count, best_ever, current_difficulty);

    display.display();
}

static void draw_epoch_screen() {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(5, 8);
    display.printf("Gen %d complete", generation);
    display.setCursor(5, 20);
    display.printf("Best: %d obstacles", best_ever);
    display.setCursor(5, 32);
    display.println("Evolving...");
    display.setCursor(5, 44);
    display.printf("Pop: %d  Elite: %d", POP_SIZE, ELITE_COUNT);
    display.display();
}

void reset_simulation() {
    generation  = 1;
    best_ever   = 0;
    world_score = 0;
    alive_count = POP_SIZE;
    generation_seed = esp_random();
    if (!user_override_difficulty) {
        current_difficulty = 0x00;
    }
    update_difficulty_params();
    init_world();

    for (int i = 0; i < POP_SIZE; i++) {
        birds[i].nn.randomise();
        birds[i].y = 28.0f; birds[i].vy = 0.0f;
        birds[i].alive = true; birds[i].fitness = 0; birds[i].pipes_passed = 0;
    }
}

// ─── Setup ────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Wire.begin(SDA_PIN, SCL_PIN, 400000);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) { for (;;); }

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(2);
    display.setCursor(2, 4);
    display.println("NEURO");
    display.println("EVOLUTION");
    display.setTextSize(1);
    display.setCursor(5, 46);
    display.printf("%d birds  |  4-4-1 NN", POP_SIZE);
    display.display();
    delay(1800);

    FpgaSerial.begin(115200, SERIAL_8N1, UART_RX_PIN, UART_TX_DUMMY);

    randomSeed(esp_random());
    reset_simulation();
}

// ─── Main loop ────────────────────────────────────────────────────────────────
void loop() {
    uint32_t frame_start = millis();

    // ── 1. Process UART commands from FPGA ───────────────────────────────────
    while (FpgaSerial.available()) {
        uint8_t cmd = FpgaSerial.read();
        switch (cmd) {
            case 0xFE:                          // KEY[0] — pause / resume
                sim_paused = !sim_paused;
                break;
            case 0xFB:                          // KEY[1] — Reset simulation back to Gen 1
                reset_simulation();
                break;
            case 0xFD:                          // SW[9] HIGH — solo mode ON
                solo_mode = true;
                break;
            case 0xFC:                          // SW[9] LOW  — solo mode OFF
                solo_mode = false;
                break;
            default:                            // 0x00-0x0F difficulty (user override via SW[3:0])
                if (cmd <= 0x0F) {
                    current_difficulty = cmd;
                    user_override_difficulty = true;
                    update_difficulty_params();
                }
                break;
        }
    }

    // ── 2. Skip physics when paused ──────────────────────────────────────────
    if (sim_paused) {
        draw_sim();
        uint32_t e = millis() - frame_start;
        if (e < FRAME_MS) delay(FRAME_MS - e);
        return;
    }

    // ── 3. Advance world ─────────────────────────────────────────────────────
    advance_pipes();

    // ── 4. Per-bird NN inference + physics ───────────────────────────────────
    const Pipe* np   = nearest_pipe();
    float dx_raw     = np->x - (float)(BIRD_X + BIRD_W);
    float dy_raw     = (float)np->gap_y;

    for (int i = 0; i < POP_SIZE; i++) {
        if (!birds[i].alive) continue;

        float in_y  = clamp(birds[i].y / (float)SCREEN_HEIGHT,    0.0f,  1.0f);
        float in_vy = clamp(birds[i].vy / 6.0f,                  -1.0f,  1.0f);
        float in_dx = clamp(dx_raw / (float)SCREEN_WIDTH,          0.0f,  1.0f);
        float in_dy = clamp((birds[i].y - dy_raw) / (float)SCREEN_HEIGHT, -1.0f, 1.0f);

        if (birds[i].nn.forward(in_y, in_vy, in_dx, in_dy))
            birds[i].vy = JUMP_IMPULSE;

        birds[i].vy += GRAVITY;
        birds[i].y  += birds[i].vy;

        if (collides(birds[i])) {
            birds[i].alive = false;
            alive_count--;
        } else {
            birds[i].fitness++;
            birds[i].pipes_passed = world_score;
        }
    }

    // ── 5. Epoch boundary ────────────────────────────────────────────────────
    if (alive_count <= 0) {
        draw_sim();
        draw_epoch_screen();
        delay(2500); // Wait longer so users can read stats
        run_epoch();
        return;
    }

    // ── 6. Render ─────────────────────────────────────────────────────────────
    draw_sim();

    // ── 7. Frame pacing ───────────────────────────────────────────────────────
    uint32_t elapsed = millis() - frame_start;
    if (elapsed < FRAME_MS) delay(FRAME_MS - elapsed);
}
