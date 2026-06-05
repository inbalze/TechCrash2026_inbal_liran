import pygame
import threading
import serial
import sys
import random
import math
import array as _arr
import time as _time
import scores_io

PORT = sys.argv[1] if len(sys.argv) > 1 else 'COM5'

SCREEN_W = 600
SCREEN_H = 580
FPS      = 60
HUD_H    = 80

# Colours
BLACK  = (10,  10,  18)
WHITE  = (240, 240, 250)
CYAN   = (0,   220, 255)
YELLOW = (255, 230,   0)
GREY   = (70,   70,  90)

# 4 Simon buttons: mapped to SW0-SW3
BUTTONS = [
    {'sw': 'SW0', 'label': 'RED',    'bright': (220,  50,  50), 'dim': (55, 15, 15), 'freq': 196},
    {'sw': 'SW1', 'label': 'BLUE',   'bright': ( 50, 110, 230), 'dim': (15, 28, 65), 'freq': 262},
    {'sw': 'SW2', 'label': 'GREEN',  'bright': ( 50, 205,  80), 'dim': (15, 55, 22), 'freq': 330},
    {'sw': 'SW3', 'label': 'YELLOW', 'bright': (230, 210,  50), 'dim': (62, 58, 15), 'freq': 392},
]

# ── hardware state ────────────────────────────────────────────────────────────
hw_lock  = threading.Lock()
hw_state = {k: 0 for k in ('KEY0', 'KEY1', 'SW0', 'SW1', 'SW2', 'SW3', 'SW9')}


class SerialThread(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.running = True
        try:
            self.ser = serial.Serial(port, 115200, timeout=0.1)
        except Exception as e:
            print(f'[serial] {e}')
            self.ser = None

    def run(self):
        if not self.ser:
            return
        while self.running:
            try:
                b = self.ser.read(1)
                if not b:
                    continue
                hi = b[0]
                if hi & 0xF0:
                    continue
                lo = self.ser.read(1)
                if not lo:
                    continue
                v = (hi << 8) | lo[0]
                with hw_lock:
                    hw_state['KEY0'] = v & 1
                    hw_state['KEY1'] = (v >> 1) & 1
                    hw_state['SW0']  = (v >> 2) & 1
                    hw_state['SW1']  = (v >> 3) & 1
                    hw_state['SW2']  = (v >> 4) & 1
                    hw_state['SW3']  = (v >> 5) & 1
                    hw_state['SW9']  = (v >> 11) & 1
            except Exception:
                pass

    def stop(self):
        self.running = False
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass


# ── tone generation ───────────────────────────────────────────────────────────
def make_tone(freq, duration=0.45):
    sr   = 44100
    n    = int(sr * duration)
    fade = int(sr * 0.04)
    buf  = _arr.array('h')
    for i in range(n):
        v = math.sin(2 * math.pi * freq * i / sr)
        if i < fade:
            v *= i / fade
        elif i > n - fade:
            v *= (n - i) / fade
        buf.append(int(v * 28000))
    return pygame.mixer.Sound(buffer=buf)


def make_buzz(duration=0.35):
    """Low error buzz for wrong input."""
    sr   = 44100
    n    = int(sr * duration)
    fade = int(sr * 0.04)
    buf  = _arr.array('h')
    for i in range(n):
        # Sawtooth-ish for harsh buzz
        t = (i * 110 / sr) % 1.0
        v = (t - 0.5) * 2
        if i < fade:
            v *= i / fade
        elif i > n - fade:
            v *= (n - i) / fade
        buf.append(int(v * 20000))
    return pygame.mixer.Sound(buffer=buf)


# ── main game class ───────────────────────────────────────────────────────────
class SimonGame:
    SHOW_LIT  = 38   # frames a button stays lit while showing (~630 ms @ 60 fps)
    SHOW_GAP  = 14   # frames gap between lit buttons (~230 ms)
    INTRO_GAP = 50   # frames before sequence starts showing
    WIN_FLASH = 80   # frames for level-complete all-light flash

    def __init__(self, port):
        pygame.init()
        pygame.mixer.init(frequency=44100, size=-16, channels=1, buffer=512)
        self.screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
        pygame.display.set_caption('SIMON  [HW]')
        self.clock  = pygame.time.Clock()
        self.fnt_l  = pygame.font.SysFont(None, 64)
        self.fnt_m  = pygame.font.SysFont(None, 44)
        self.fnt_s  = pygame.font.SysFont(None, 28)

        self.sounds     = [make_tone(b['freq']) for b in BUTTONS]
        self.wrong_snd  = make_buzz()

        self.serial = SerialThread(port)
        self.serial.start()
        _time.sleep(0.4)
        with hw_lock:
            self.sw9_prev = hw_state['SW9']
        self.high_level = scores_io.load().get('simon', 0)
        self._reset()

    # ── helpers ───────────────────────────────────────────────────────────────
    def _hw(self):
        with hw_lock:
            return dict(hw_state)

    def _reset(self):
        self.sequence    = []
        self.level       = 0
        self.player_idx  = 0
        self.state       = 'showing'
        self.show_idx    = 0
        self.show_timer  = self.INTRO_GAP
        self.active_btn  = -1        # which button Simon is currently lighting
        self.flash_btn   = -1        # which button to flash after player press
        self.flash_timer = 0
        self.prev_sw     = [0, 0, 0, 0]
        self.prev_key0   = 0
        self._add_step()

    def _add_step(self):
        self.level      += 1
        self.sequence.append(random.randint(0, 3))
        self.player_idx  = 0
        self.state       = 'showing'
        self.show_idx    = 0
        self.show_timer  = self.INTRO_GAP
        self.active_btn  = -1

    def _quad_rect(self, i):
        pad    = 6
        half_w = SCREEN_W // 2
        half_h = (SCREEN_H - HUD_H) // 2
        x = (i % 2) * half_w + pad
        y = (i // 2) * half_h + pad
        return (x, y, half_w - pad * 2, half_h - pad * 2)

    # ── update ────────────────────────────────────────────────────────────────
    def update(self):
        hw    = self._hw()
        sw    = [hw[f'SW{i}'] for i in range(4)]
        key0  = hw['KEY0']
        sw9   = hw['SW9']

        # SW9: quit during active play, restart during game-over
        if sw9 == 1 and self.sw9_prev == 0:
            if self.state in ('showing', 'waiting'):
                self.serial.stop()
                pygame.quit()
                sys.exit()
            else:
                self._reset()
        self.sw9_prev = sw9

        # ── state machine ─────────────────────────────────────────────────────
        if self.state == 'showing':
            self.show_timer -= 1
            if self.show_timer <= 0:
                if self.active_btn >= 0:
                    # End of lit phase → short gap
                    self.active_btn  = -1
                    self.show_timer  = self.SHOW_GAP
                    self.show_idx   += 1
                else:
                    # End of gap → next button or hand over to player
                    if self.show_idx >= len(self.sequence):
                        self.state = 'waiting'
                    else:
                        btn = self.sequence[self.show_idx]
                        self.active_btn = btn
                        self.sounds[btn].play()
                        self.show_timer = self.SHOW_LIT

        elif self.state == 'waiting':
            # KEY0 = replay the sequence
            if key0 == 1 and self.prev_key0 == 0:
                self.state      = 'showing'
                self.show_idx   = 0
                self.show_timer = self.INTRO_GAP
                self.active_btn = -1

            # SW0–SW3 rising edge = player presses that button
            for i in range(4):
                if sw[i] == 1 and self.prev_sw[i] == 0:
                    self.sounds[i].play()
                    self.flash_btn   = i
                    self.flash_timer = 20
                    expected = self.sequence[self.player_idx]
                    if i == expected:
                        self.player_idx += 1
                        if self.player_idx >= len(self.sequence):
                            # Level complete — all buttons flash
                            self.state       = 'level_complete'
                            self.flash_timer = self.WIN_FLASH
                    else:
                        self.wrong_snd.play()
                        self.state = 'game_over'
                        scores_io.save('simon', self.level - 1)
                        self.high_level = max(self.high_level, self.level - 1)
                    break   # one input per frame

        elif self.state == 'level_complete':
            self.flash_timer -= 1
            if self.flash_timer <= 0:
                self._add_step()

        elif self.state == 'game_over':
            pass  # wait for SW9

        # Decrement flash timer for non-level_complete states
        if self.flash_timer > 0 and self.state != 'level_complete':
            self.flash_timer -= 1

        self.prev_sw   = sw
        self.prev_key0 = key0

    # ── draw ─────────────────────────────────────────────────────────────────
    def draw(self):
        self.screen.fill(BLACK)

        win_lit = (self.state == 'level_complete')

        for i, btn in enumerate(BUTTONS):
            rx, ry, rw, rh = self._quad_rect(i)

            lit = (i == self.active_btn) or \
                  (i == self.flash_btn and self.flash_timer > 0) or \
                  win_lit

            color = btn['bright'] if lit else btn['dim']
            pygame.draw.rect(self.screen, color, (rx, ry, rw, rh), border_radius=20)

            if lit:
                pygame.draw.rect(self.screen, WHITE, (rx, ry, rw, rh), 2, border_radius=20)

            cx = rx + rw // 2
            cy = ry + rh // 2
            lbl    = self.fnt_m.render(btn['label'], True, WHITE if lit else (80, 80, 80))
            sw_lbl = self.fnt_s.render(btn['sw'],    True, (200, 200, 200) if lit else (50, 50, 50))
            self.screen.blit(lbl,    (cx - lbl.get_width()    // 2, cy - 22))
            self.screen.blit(sw_lbl, (cx - sw_lbl.get_width() // 2, cy + 14))

        # Divider lines between quadrants
        mid_x = SCREEN_W // 2
        mid_y = (SCREEN_H - HUD_H) // 2
        pygame.draw.line(self.screen, BLACK, (mid_x, 0),      (mid_x, SCREEN_H - HUD_H), 8)
        pygame.draw.line(self.screen, BLACK, (0, mid_y), (SCREEN_W, mid_y),              8)

        # ── HUD ───────────────────────────────────────────────────────────────
        hud_y = SCREEN_H - HUD_H
        pygame.draw.line(self.screen, (50, 50, 90), (0, hud_y), (SCREEN_W, hud_y), 1)

        if self.state == 'showing':
            step = min(self.show_idx + 1, len(self.sequence))
            msg = f'WATCH...  LEVEL {self.level}  ({step}/{len(self.sequence)})'
            self.screen.blit(self.fnt_m.render(msg, True, CYAN), (14, hud_y + 8))
            self.screen.blit(self.fnt_s.render('KEY0 = replay   SW9 = quit', True, GREY),
                             (14, hud_y + 50))

        elif self.state == 'waiting':
            msg = f'YOUR TURN  {self.player_idx} / {len(self.sequence)}'
            self.screen.blit(self.fnt_m.render(msg, True, YELLOW), (14, hud_y + 8))
            self.screen.blit(self.fnt_s.render('KEY0 = replay sequence   SW9 = quit', True, GREY),
                             (14, hud_y + 50))

        elif self.state == 'level_complete':
            msg = f'CORRECT!  LEVEL {self.level} CLEAR!'
            self.screen.blit(self.fnt_m.render(msg, True, (60, 255, 130)), (14, hud_y + 8))

        elif self.state == 'game_over':
            msg = 'WRONG!  GAME OVER'
            self.screen.blit(self.fnt_l.render(msg, True, (255, 60, 60)), (14, hud_y + 4))
            best_txt = f'BEST LEVEL: {self.high_level}    flip SW9 UP to restart'
            self.screen.blit(self.fnt_s.render(best_txt, True, WHITE),
                             (14, hud_y + 54))

        # Level badge (top-right)
        lvl = self.fnt_s.render(f'LEVEL  {self.level}', True, (140, 140, 210))
        self.screen.blit(lvl, (SCREEN_W - lvl.get_width() - 12, hud_y + 10))

        pygame.display.flip()

    # ── main loop ─────────────────────────────────────────────────────────────
    def run(self):
        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.serial.stop()
                    pygame.quit()
                    sys.exit()
            self.update()
            self.draw()
            self.clock.tick(FPS)


if __name__ == '__main__':
    SimonGame(PORT).run()
