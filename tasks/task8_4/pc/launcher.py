import pygame
import threading
import serial
import sys
import math
import time
import subprocess
import os
import random
import scores_io

PORT = sys.argv[1] if len(sys.argv) > 1 else 'COM5'

MENU_W = 800
MENU_H = 560
FPS    = 60

BLACK  = (10,  10,  18)
WHITE  = (240, 240, 250)
CYAN   = (0,   255, 255)
YELLOW = (255, 230,   0)
PURPLE = (180,  60, 255)
GREY   = (90,   90, 110)
RED    = (255,  50, 100)
GREEN  = (50,  255, 150)

hw_lock  = threading.Lock()
hw_state = {k: 0 for k in ('KEY0', 'KEY1', 'SW0', 'SW1', 'SW2', 'SW9')}


class SerialThread(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.running = True
        try:
            self.ser = serial.Serial(port, 115200, timeout=0.1)
        except Exception as e:
            print(f"[launcher serial] {e}")
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


GAMES = [
    {
        'title':     'DINO RUNNER',
        'subtitle':  'KEY0=jump  KEY1=duck',
        'sw_hint':   'SW0=turbo  SW1=pause  SW2=shield  SW9=quit',
        'color':     GREEN,
        'icon':      'dino',
        'score_key': 'dino',
    },
    {
        'title':     'PAC-MAN',
        'subtitle':  'KEY0=turn right  KEY1=turn left',
        'sw_hint':   'SW0=speed  SW1=pause  SW2=frighten  SW9=quit',
        'color':     YELLOW,
        'icon':      'pac',
        'score_key': 'pacman',
    },
    {
        'title':     'SPACE SHOOTER',
        'subtitle':  'KEY0=move right  KEY1=move left',
        'sw_hint':   'SW0=rapid fire  SW1=pause  SW2=shield  SW9=quit',
        'color':     PURPLE,
        'icon':      'ship',
        'score_key': 'shooter',
    },
    {
        'title':     'SIMON',
        'subtitle':  'SW0=RED  SW1=BLUE  SW2=GREEN  SW3=YELLOW',
        'sw_hint':   'KEY0=replay  SW9=quit',
        'color':     CYAN,
        'icon':      'simon',
        'score_key': 'simon',
    },
]


def draw_dino_icon(surface, cx, cy, size, color, tick):
    s = size // 30
    anim = (tick // 8) % 2
    x, y = cx - size // 2, cy - size // 2
    pts = [
        (x + 5*s, y + 25*s), (x + 15*s, y + 15*s),
        (x + 20*s, y),        (x + 40*s, y),
        (x + 40*s, y + 12*s), (x + 30*s, y + 12*s),
        (x + 28*s, y + 20*s), (x + 28*s, y + 35*s),
        (x + 15*s, y + 38*s), (x + 8*s,  y + 38*s),
    ]
    pygame.draw.polygon(surface, color, pts)
    pygame.draw.polygon(surface, WHITE, pts, 1)
    leg_y = y + 38*s
    if anim == 0:
        pygame.draw.line(surface, color, (x+12*s, leg_y), (x+8*s,  leg_y+10*s), 2)
        pygame.draw.line(surface, color, (x+20*s, leg_y), (x+24*s, leg_y+10*s), 2)
    else:
        pygame.draw.line(surface, color, (x+12*s, leg_y), (x+16*s, leg_y+10*s), 2)
        pygame.draw.line(surface, color, (x+20*s, leg_y), (x+16*s, leg_y+10*s), 2)


def draw_pac_icon(surface, cx, cy, size, color, tick):
    rad = size // 2
    ma  = 28 + 22 * abs(math.sin(tick * 0.12))
    pygame.draw.circle(surface, color, (cx, cy), rad)
    pts = [(cx, cy)]
    for a in range(int(-ma), int(ma) + 1, 4):
        pts.append((int(cx + rad * math.cos(math.radians(a))),
                    int(cy + rad * math.sin(math.radians(a)))))
    if len(pts) >= 3:
        pygame.draw.polygon(surface, BLACK, pts)


def draw_ship_icon(surface, cx, cy, size, color, tick):
    s = size
    pts = [
        (cx,       cy - s),
        (cx + s//2, cy + s//2),
        (cx,       cy + s//4),
        (cx - s//2, cy + s//2),
    ]
    pygame.draw.polygon(surface, color, pts)
    pygame.draw.polygon(surface, WHITE, pts, 1)
    pulse = abs(math.sin(tick * 0.15))
    flame_col = (255, int(100 + 155*pulse), 0)
    pygame.draw.polygon(surface, flame_col, [
        (cx - s//4, cy + s//4),
        (cx,        cy + s//2 + int(s//3 * pulse)),
        (cx + s//4, cy + s//4),
    ])


def draw_simon_icon(surface, cx, cy, size, color, tick):
    sq   = size // 2 - 2
    half = sq // 2 + 1
    icon_colors = [(220, 50, 50), (50, 110, 230), (50, 205, 80), (230, 210, 50)]
    offsets = [(-half - sq, -half - sq), (half, -half - sq),
               (-half - sq,  half),      (half,  half)]
    active = (tick // 18) % 4
    for i, (ox, oy) in enumerate(offsets):
        c = icon_colors[i]
        if i == active:
            c = tuple(min(255, v + 50) for v in c)
        pygame.draw.rect(surface, c, (cx + ox, cy + oy, sq, sq), border_radius=4)


def show_splash(screen, clock):
    fnt_big  = pygame.font.SysFont(None, 110)
    fnt_med  = pygame.font.SysFont(None, 40)
    fnt_tiny = pygame.font.SysFont(None, 24)
    total    = FPS * 3  # 3 seconds
    for frame in range(total):
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                pygame.quit(); sys.exit()
            if ev.type == pygame.KEYDOWN:
                return  # skip splash on any key
        t = frame / total
        if t < 0.15:
            alpha = int(255 * t / 0.15)
        elif t > 0.80:
            alpha = int(255 * (1.0 - t) / 0.20)
        else:
            alpha = 255
        screen.fill((0, 0, 0))
        # Scanlines
        for row in range(0, MENU_H, 3):
            pygame.draw.line(screen, (0, 0, 0), (0, row), (MENU_W, row))
        pulse     = 0.70 + 0.30 * math.sin(frame * 0.12)
        glitch    = random.randint(-3, 3) if frame % 25 < 2 else 0
        glow_col  = (0, int(210 * pulse), int(255 * pulse))
        surf = pygame.Surface((MENU_W, MENU_H), pygame.SRCALPHA)
        cx   = MENU_W // 2
        t1   = fnt_big.render('TECHCRASH', True, glow_col)
        t2   = fnt_big.render('2026',      True, (255, 230, 0))
        sub  = fnt_med.render('VLSI  HACKATHON', True, (190, 190, 220))
        tag  = fnt_tiny.render('DE10-Lite  ×  ESP32', True, (100, 100, 140))
        surf.blit(t1,  (cx - t1.get_width()  // 2 + glitch, 110))
        surf.blit(t2,  (cx - t2.get_width()  // 2,           220))
        pygame.draw.line(surf, glow_col,
                         (cx - 220, 215), (cx + 220, 215), 1)
        surf.blit(sub, (cx - sub.get_width() // 2, 330))
        surf.blit(tag, (cx - tag.get_width() // 2, 385))
        surf.set_alpha(alpha)
        screen.blit(surf, (0, 0))
        pygame.display.flip()
        clock.tick(FPS)


def show_menu(screen, clock, serial_thread):
    fnt_logo1  = pygame.font.SysFont(None, 68)
    fnt_logo2  = pygame.font.SysFont(None, 68)
    fnt_sub_hd = pygame.font.SysFont(None, 24)
    fnt_game   = pygame.font.SysFont(None, 44)
    fnt_sub    = pygame.font.SysFont(None, 21)
    fnt_hint   = pygame.font.SysFont(None, 21)
    fnt_score  = pygame.font.SysFont(None, 28)

    cursor     = 0
    tick       = 0
    n          = len(GAMES)
    scores     = scores_io.load()

    # Initialise prev-states from live HW to avoid spurious edge on first frame
    time.sleep(0.3)
    with hw_lock:
        key0_prev = hw_state['KEY0']
        key1_prev = hw_state['KEY1']
        sw9_prev  = hw_state['SW9']

    while True:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                if serial_thread:
                    serial_thread.stop()
                pygame.quit()
                sys.exit()
            if ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_DOWN:
                    cursor = (cursor + 1) % n
                if ev.key == pygame.K_RETURN:
                    return cursor

        with hw_lock:
            key0 = hw_state['KEY0']
            key1 = hw_state['KEY1']
            sw9  = hw_state['SW9']

        if key0 == 1 and key0_prev == 0:
            cursor = (cursor + 1) % n
        if key1 == 1 and key1_prev == 0:
            return cursor
        if sw9 == 1 and sw9_prev == 0:
            cursor = (cursor - 1) % n
        key0_prev = key0
        key1_prev = key1
        sw9_prev  = sw9

        tick += 1
        screen.fill(BLACK)

        # Scanline overlay
        for row in range(0, MENU_H, 4):
            line_surf = pygame.Surface((MENU_W, 1), pygame.SRCALPHA)
            line_surf.fill((0, 0, 0, 30))
            screen.blit(line_surf, (0, row))

        # Logo
        pulse_logo = 0.85 + 0.15 * math.sin(tick * 0.06)
        logo_cyan  = (0, int(220 * pulse_logo), int(255 * pulse_logo))
        l1 = fnt_logo1.render('CrashTech', True, logo_cyan)
        l2 = fnt_logo2.render('2026',      True, YELLOW)
        ls = fnt_sub_hd.render('VLSI  HACKATHON  ·  DE10-Lite  ×  ESP32', True, (130, 130, 170))
        total_w = l1.get_width() + 14 + l2.get_width()
        lx = MENU_W // 2 - total_w // 2
        ly = 8
        screen.blit(l1, (lx, ly))
        screen.blit(l2, (lx + l1.get_width() + 14, ly))
        screen.blit(ls, (MENU_W // 2 - ls.get_width() // 2, ly + l1.get_height() + 2))
        pygame.draw.line(screen, (40, 40, 80), (0, 76), (MENU_W, 76), 1)

        # Game cards
        card_h = 92
        card_y_start = 82
        gap = 6
        for i, g in enumerate(GAMES):
            selected = (i == cursor)
            cy = card_y_start + i * (card_h + gap)
            border = g['color'] if selected else GREY
            alpha  = 255 if selected else 140

            # Card background
            card_surf = pygame.Surface((MENU_W - 120, card_h), pygame.SRCALPHA)
            card_surf.fill((30, 30, 45, 200 if selected else 100))
            screen.blit(card_surf, (60, cy))
            pygame.draw.rect(screen, border, (60, cy, MENU_W - 120, card_h),
                             2 if selected else 1, border_radius=6)

            # Pulsing selector arrow
            if selected:
                pulse = abs(math.sin(tick * 0.08))
                arrow_x = 70 + int(8 * pulse)
                arrow_y = cy + card_h // 2
                pygame.draw.polygon(screen, g['color'], [
                    (arrow_x,      arrow_y - 8),
                    (arrow_x + 14, arrow_y),
                    (arrow_x,      arrow_y + 8),
                ])

            # Icon
            icon_cx = 130
            icon_cy = cy + card_h // 2
            icon_sz = 44
            if g['icon'] == 'dino':
                draw_dino_icon(screen, icon_cx, icon_cy - 8, icon_sz, g['color'], tick)
            elif g['icon'] == 'pac':
                draw_pac_icon(screen, icon_cx, icon_cy, icon_sz // 2 + 4, g['color'], tick)
            elif g['icon'] == 'ship':
                draw_ship_icon(screen, icon_cx, icon_cy, icon_sz // 2, g['color'], tick)
            else:
                draw_simon_icon(screen, icon_cx, icon_cy, icon_sz, g['color'], tick)

            # Text
            col = g['color'] if selected else GREY
            screen.blit(fnt_game.render(g['title'], True, col), (175, cy + 7))
            screen.blit(fnt_sub.render(g['subtitle'], True, WHITE if selected else GREY),
                        (175, cy + 50))
            screen.blit(fnt_sub.render(g['sw_hint'], True, CYAN if selected else GREY),
                        (175, cy + 70))

            # Best score (right side of card)
            best = scores.get(g.get('score_key', ''), 0)
            if best > 0:
                bl  = fnt_sub.render('BEST', True, (140, 140, 180))
                bv  = fnt_score.render(str(best), True, g['color'] if selected else GREY)
                screen.blit(bl, (MENU_W - 118, cy + card_h // 2 - 22))
                screen.blit(bv, (MENU_W - 118, cy + card_h // 2 - 2))

        # Bottom hint
        hint = "KEY0 = scroll ↓    KEY1 = select    SW9 = scroll ↑"
        h_surf = fnt_hint.render(hint, True, GREY)
        screen.blit(h_surf, (MENU_W // 2 - h_surf.get_width() // 2, MENU_H - 30))

        pygame.draw.line(screen, GREY, (0, MENU_H - 40), (MENU_W, MENU_H - 40), 1)

        pygame.display.flip()
        clock.tick(FPS)


GAME_SCRIPTS = [
    'dino_runner.py',
    'game.py',
    'space_shooter.py',
    'simon.py',
]

# Use python.exe explicitly — launcher may run under pythonw.exe which has no console
PYTHON = os.path.join(os.path.dirname(sys.executable), 'python.exe')
if not os.path.exists(PYTHON):
    PYTHON = sys.executable


def launch_game(choice, clock):
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), GAME_SCRIPTS[choice])
    proc = subprocess.Popen([PYTHON, script, PORT])
    # Pump events while waiting so OS doesn't mark the launcher as 'Not Responding'
    while proc.poll() is None:
        pygame.event.pump()
        clock.tick(10)


def main():
    pygame.init()
    screen = pygame.display.set_mode((MENU_W, MENU_H))
    pygame.display.set_caption("GAME HUB")
    clock  = pygame.time.Clock()

    serial_thread = SerialThread(PORT)
    serial_thread.start()

    show_splash(screen, clock)

    while True:
        choice = show_menu(screen, clock, serial_thread)

        # Hide the launcher window while game runs
        pygame.display.iconify()
        pygame.event.pump()

        serial_thread.stop()
        time.sleep(0.5)

        launch_game(choice, clock)

        # Restore launcher window — wait for SW9 to be released first
        time.sleep(0.6)
        serial_thread = SerialThread(PORT)
        serial_thread.start()
        time.sleep(0.3)

        screen = pygame.display.set_mode((MENU_W, MENU_H))
        pygame.display.set_caption("GAME HUB")
        # Bring window back to front on Windows
        try:
            import ctypes
            hwnd = pygame.display.get_wm_info()['window']
            ctypes.windll.user32.ShowWindow(hwnd, 9)   # SW_RESTORE
            ctypes.windll.user32.SetForegroundWindow(hwnd)
        except Exception:
            pass
        pygame.event.clear()

        with hw_lock:
            hw_state['KEY0'] = 0
            hw_state['KEY1'] = 0
            hw_state['SW9']  = 0


if __name__ == '__main__':
    import traceback, os
    log = os.path.join(os.path.dirname(__file__), 'launcher_crash.log')
    try:
        main()
    except BaseException:
        with open(log, 'w') as f:
            traceback.print_exc(file=f)
        raise
