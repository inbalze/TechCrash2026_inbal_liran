import pygame
import threading
import serial
import sys
import random
import math
import os
import scores_io

# Game constants
SCREEN_W = 504
SCREEN_H = 600
FPS      = 60

# Harmonious retro neon palette
BLACK  = (10,  10,  15)
WHITE  = (240, 240, 250)
YELLOW = (255, 230,   0)
RED    = (255,  50,  100)
GREEN  = (50,  255,  150)
CYAN   = (0,   255,  255)
PURPLE = (200,  80,  255)
GREY   = (80,   80,   90)

# Hardware interface
hw_lock  = threading.Lock()
hw_state = {k: 0 for k in ('KEY0', 'KEY1', 'SW0', 'SW1', 'SW2', 'SW9')}

class SerialThread(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.running = True
        try:
            self.ser = serial.Serial(port, 115200, timeout=0.1)
        except Exception as e:
            print(f"[serial] {e}")
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
            self.ser.close()

# Entity classes
class Laser:
    def __init__(self, x, y, dy, color, width=4, height=14):
        self.x = x
        self.y = y
        self.dy = dy
        self.color = color
        self.width = width
        self.height = height

    def update(self):
        self.y += self.dy

    def draw(self, surface):
        pygame.draw.rect(surface, self.color, (self.x - self.width//2, self.y, self.width, self.height))

class Alien:
    def __init__(self, x, y, points, color):
        self.x = x
        self.y = y
        self.width = 30
        self.height = 24
        self.points = points
        self.color = color
        self.anim_tick = random.randint(0, 100)

    def update(self, dx, dy):
        self.x += dx
        self.y += dy
        self.anim_tick += 1

    def draw(self, surface):
        # Draw a retro pixelated alien shape
        t = self.anim_tick * 0.1
        w, h = self.width, self.height
        offset = math.sin(t) * 3
        # Main body
        pygame.draw.rect(surface, self.color, (self.x - w//2, self.y - h//2, w, h - 4), border_radius=4)
        # Antennae / legs
        pygame.draw.line(surface, self.color, (self.x - w//3, self.y + h//2 - 4), (self.x - w//3 - offset, self.y + h//2 + 2), 3)
        pygame.draw.line(surface, self.color, (self.x + w//3, self.y + h//2 - 4), (self.x + w//3 + offset, self.y + h//2 + 2), 3)
        # Eyes
        pygame.draw.circle(surface, BLACK, (int(self.x - 6), int(self.y - 2)), 3)
        pygame.draw.circle(surface, BLACK, (int(self.x + 6), int(self.y - 2)), 3)

class Particle:
    def __init__(self, x, y, color):
        self.x = x
        self.y = y
        angle = random.uniform(0, 2 * math.pi)
        speed = random.uniform(1.0, 4.0)
        self.vx = math.cos(angle) * speed
        self.vy = math.sin(angle) * speed
        self.color = color
        self.life = random.randint(20, 40)
        self.max_life = self.life

    def update(self):
        self.x += self.vx
        self.y += self.vy
        self.life -= 1

    def draw(self, surface):
        alpha = int(255 * (self.life / self.max_life))
        r, g, b = self.color
        # Draw soft faded circles
        size = max(1, int(4 * (self.life / self.max_life)))
        pygame.draw.circle(surface, (r, g, b), (int(self.x), int(self.y)), size)

# Main Game class
class SpaceShooter:
    def __init__(self, port):
        pygame.init()
        self.screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
        pygame.display.set_caption("NEON SPACE INVADERS")
        self.clock = pygame.time.Clock()
        self.fnt_s = pygame.font.SysFont(None, 24)
        self.fnt_l = pygame.font.SysFont(None, 72)
        
        self.serial = SerialThread(port)
        self.serial.start()
        import time as _t; _t.sleep(0.4)
        with hw_lock:
            self.sw9_prev = hw_state['SW9']
        self.high_score = scores_io.load().get('shooter', 0)
        self._reset()

    def _reset(self):
        self.state = 'playing'
        self.score = 0
        self.lives = 3
        self.battery = 100.0
        self.paused = False
        
        # Player configuration
        self.player_x = SCREEN_W // 2
        self.player_y = SCREEN_H - 80
        self.player_w = 36
        self.player_h = 24
        self.player_speed = 4.0
        
        # Lists
        self.lasers = []
        self.aliens = []
        self.particles = []
        self.stars = [{'x': random.randint(0, SCREEN_W), 'y': random.randint(0, SCREEN_H), 'speed': random.uniform(0.5, 2.5)} for _ in range(60)]
        
        self.alien_dx = 1.0
        self.alien_dy = 0.0
        self.alien_shoot_timer = 0
        self.player_shoot_timer = 0
        self.screen_shake = 0
        self.invulnerable_timer = 0
        
        self._spawn_aliens()

    def _spawn_aliens(self):
        self.aliens = []
        rows = 4
        cols = 8
        spacing_x = 45
        spacing_y = 35
        start_x = (SCREEN_W - (cols - 1) * spacing_x) // 2
        start_y = 60
        
        colors = [RED, PURPLE, CYAN, GREEN]
        points = [40, 30, 20, 10]
        
        for r in range(rows):
            for c in range(cols):
                ax = start_x + c * spacing_x
                ay = start_y + r * spacing_y
                self.aliens.append(Alien(ax, ay, points[r], colors[r]))

    def _hw(self):
        with hw_lock:
            return dict(hw_state)

    def _trigger_explosion(self, x, y, color):
        for _ in range(15):
            self.particles.append(Particle(x, y, color))

    def update(self):
        hw = self._hw()
        
        # 1. Update stars
        for star in self.stars:
            star['y'] += star['speed']
            if star['y'] > SCREEN_H:
                star['y'] = 0
                star['x'] = random.randint(0, SCREEN_W)

        # 2. Update particles
        for p in self.particles[:]:
            p.update()
            if p.life <= 0:
                self.particles.remove(p)

        # 3. Invulnerability tick
        if self.invulnerable_timer > 0:
            self.invulnerable_timer -= 1

        # 4. Handle Player input and movement
        # KEY1 moves Left, KEY0 moves Right
        if hw['KEY1']:
            self.player_x = max(self.player_w//2, self.player_x - self.player_speed)
        if hw['KEY0']:
            self.player_x = min(SCREEN_W - self.player_w//2, self.player_x + self.player_speed)

        # 5. Handle SW2 (Shield) battery drain/charge
        shield_active = False
        if hw['SW2']:
            if self.battery > 0:
                self.battery = max(0.0, self.battery - 0.5)
                shield_active = True
        else:
            self.battery = min(100.0, self.battery + 0.1)

        # 6. Player Fire Logic
        # SW0: ON -> Big laser, less frequent. OFF -> Normal laser, standard frequency.
        is_big_laser = (hw['SW0'] == 1)
        fire_cooldown = 48 if is_big_laser else 20
        if self.player_shoot_timer > 0:
            self.player_shoot_timer -= 1
        
        if self.player_shoot_timer == 0:
            if is_big_laser:
                # Big laser: width=12, height=30, speed=-5, color=YELLOW
                self.lasers.append(Laser(self.player_x, self.player_y - 10, -5, YELLOW, width=12, height=30))
            else:
                # Normal laser: width=4, height=14, speed=-7, color=GREEN
                self.lasers.append(Laser(self.player_x, self.player_y - 10, -7, GREEN, width=4, height=14))
            self.player_shoot_timer = fire_cooldown

        # 7. Update lasers
        for l in self.lasers[:]:
            l.update()
            if l.y < 0 or l.y > SCREEN_H:
                self.lasers.remove(l)

        # 8. Alien movement logic
        shift_down = False
        # Find bounds
        for a in self.aliens:
            if self.alien_dx > 0 and a.x + a.width//2 >= SCREEN_W - 10:
                shift_down = True
                break
            elif self.alien_dx < 0 and a.x - a.width//2 <= 10:
                shift_down = True
                break

        if shift_down:
            self.alien_dx = -self.alien_dx
            dy = 12
        else:
            dy = 0

        for a in self.aliens:
            a.update(self.alien_dx, dy)
            # Check if aliens reached bottom
            if a.y + a.height//2 >= self.player_y:
                self.state = 'game_over'
                scores_io.save('shooter', self.score)
                self.high_score = max(self.high_score, self.score)

        # 9. Alien shoot logic
        if self.alien_shoot_timer > 0:
            self.alien_shoot_timer -= 1
        else:
            if self.aliens:
                shooting_alien = random.choice(self.aliens)
                self.lasers.append(Laser(shooting_alien.x, shooting_alien.y + 10, 4, RED))
                self.alien_shoot_timer = random.randint(30, 70)

        # 10. Collision Detection
        for l in self.lasers[:]:
            # Player bullet hitting Alien
            if l.dy < 0:
                lx_min = l.x - l.width // 2
                lx_max = l.x + l.width // 2
                ly_min = l.y
                ly_max = l.y + l.height
                for a in self.aliens[:]:
                    ax_min = a.x - a.width // 2
                    ax_max = a.x + a.width // 2
                    ay_min = a.y - a.height // 2
                    ay_max = a.y + a.height // 2
                    if (lx_min < ax_max and lx_max > ax_min) and (ly_min < ay_max and ly_max > ay_min):
                        self._trigger_explosion(a.x, a.y, a.color)
                        self.score += a.points
                        self.aliens.remove(a)
                        if l in self.lasers:
                            self.lasers.remove(l)
                        break
            # Alien bullet hitting Player
            else:
                py_top = self.player_y - self.player_h//2
                py_bot = self.player_y + self.player_h//2
                px_left = self.player_x - self.player_w//2
                px_right = self.player_x + self.player_w//2
                
                if (px_left < l.x < px_right) and (py_top < l.y < py_bot):
                    self.lasers.remove(l)
                    if shield_active:
                        self._trigger_explosion(l.x, l.y, CYAN)
                        # Absorbed by shield, slightly drains battery
                        self.battery = max(0.0, self.battery - 10.0)
                    elif self.invulnerable_timer == 0:
                        self._trigger_explosion(self.player_x, self.player_y, YELLOW)
                        self.lives -= 1
                        self.screen_shake = 15
                        self.invulnerable_timer = 90
                        if self.lives <= 0:
                            self.state = 'game_over'
                            scores_io.save('shooter', self.score)
                            self.high_score = max(self.high_score, self.score)
        
        # Check Win state
        if not self.aliens:
            self.state = 'win'
            scores_io.save('shooter', self.score)
            self.high_score = max(self.high_score, self.score)

        # Screen shake dampening
        if self.screen_shake > 0:
            self.screen_shake -= 1

    def draw(self):
        # Shake screen if active
        shake_x = 0
        shake_y = 0
        if self.screen_shake > 0:
            shake_x = random.randint(-self.screen_shake, self.screen_shake)
            shake_y = random.randint(-self.screen_shake, self.screen_shake)

        # Render background
        self.screen.fill(BLACK)
        
        # Draw stars
        for star in self.stars:
            pygame.draw.circle(self.screen, (150, 150, 180), (int(star['x'] + shake_x), int(star['y'] + shake_y)), 1)

        # Draw particles
        for p in self.particles:
            p.draw(self.screen)

        # Draw player
        if self.state == 'playing' and (self.invulnerable_timer == 0 or (self.invulnerable_timer // 6) % 2 == 0):
            # Slick triangle shape
            px, py = self.player_x + shake_x, self.player_y + shake_y
            pw, ph = self.player_w, self.player_h
            points = [
                (px, py - ph//2), # Nose
                (px - pw//2, py + ph//2), # Back-left
                (px + pw//2, py + ph//2)  # Back-right
            ]
            pygame.draw.polygon(self.screen, GREEN, points)
            pygame.draw.polygon(self.screen, WHITE, points, 1)

            # Draw glowing thruster
            thruster_height = 8 + random.randint(0, 6)
            pygame.draw.polygon(self.screen, RED, [
                (px - 6, py + ph//2),
                (px + 6, py + ph//2),
                (px, py + ph//2 + thruster_height)
            ])

            # Draw Shield bubble if active
            hw = self._hw()
            if hw['SW2'] and self.battery > 0:
                pygame.draw.circle(self.screen, CYAN, (int(px), int(py)), 28, 2)
                # Glassmorphic inner fill
                shield_surface = pygame.Surface((60, 60), pygame.SRCALPHA)
                pygame.draw.circle(shield_surface, (0, 255, 255, 30), (30, 30), 28)
                self.screen.blit(shield_surface, (px - 30, py - 30))

        # Draw aliens
        for a in self.aliens:
            # Temporarily offset alien coordinate for drawing if screen shake active
            ax_orig, ay_orig = a.x, a.y
            a.x += shake_x
            a.y += shake_y
            a.draw(self.screen)
            a.x, a.y = ax_orig, ay_orig

        # Draw lasers
        for l in self.lasers:
            l.draw(self.screen)

        # Status Bar / UI (bottom of screen)
        uy = SCREEN_H - 40
        pygame.draw.rect(self.screen, (20, 20, 30), (0, uy, SCREEN_W, 40))
        pygame.draw.line(self.screen, GREY, (0, uy), (SCREEN_W, uy), 1)

        # Score
        self.screen.blit(self.fnt_s.render(
            f"SCORE  {self.score}    BEST {self.high_score}", True, WHITE), (12, uy + 12))

        # Battery / Shield Bar
        bx, by = SCREEN_W // 2 - 55, uy + 12
        pygame.draw.rect(self.screen, (50, 50, 50), (bx, by, 110, 14))
        bw = int(110 * self.battery / 100)
        bc = ((0, 200, 255) if self.battery > 50 else (200, 200, 0) if self.battery > 20 else (200, 0, 0))
        pygame.draw.rect(self.screen, bc, (bx, by, bw, 14))
        pygame.draw.rect(self.screen, WHITE, (bx, by, 110, 14), 1)
        self.screen.blit(self.fnt_s.render("SHIELD", True, CYAN), (bx - 60, by - 1))

        # Lives
        for i in range(self.lives):
            lx = SCREEN_W - 20 - i * 20
            ly = uy + 20
            # Small ship shapes for lives
            pygame.draw.polygon(self.screen, GREEN, [
                (lx, ly - 6),
                (lx - 6, ly + 6),
                (lx + 6, ly + 6)
            ])

        # Overlays
        if self.paused:
            # Dim background
            dim = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            dim.fill((0, 0, 0, 150))
            self.screen.blit(dim, (0, 0))
            lbl = self.fnt_l.render("PAUSED", True, YELLOW)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
        elif self.state == 'game_over':
            # Dim background
            dim = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            dim.fill((0, 0, 0, 180))
            self.screen.blit(dim, (0, 0))
            lbl = self.fnt_l.render("GAME OVER", True, RED)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
            sub = self.fnt_s.render("flip SW9 to restart", True, WHITE)
            self.screen.blit(sub, (SCREEN_W//2 - sub.get_width()//2, SCREEN_H//2 + 32))
        elif self.state == 'win':
            dim = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            dim.fill((0, 0, 0, 150))
            self.screen.blit(dim, (0, 0))
            lbl = self.fnt_l.render("VICTORY!", True, YELLOW)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
            sub = self.fnt_s.render("flip SW9 to play again", True, WHITE)
            self.screen.blit(sub, (SCREEN_W//2 - sub.get_width()//2, SCREEN_H//2 + 32))

        pygame.display.flip()

    def run(self):
        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.serial.stop()
                    pygame.quit()
                    sys.exit()

            hw = self._hw()
            sw9 = hw['SW9']

            if sw9 == 1 and self.sw9_prev == 0:
                if self.state == 'playing':
                    self.serial.stop()
                    pygame.quit()
                    sys.exit()
                else:
                    self._reset()
            self.sw9_prev = sw9

            self.paused = (hw['SW1'] == 1)

            if not self.paused and self.state == 'playing':
                self.update()

            self.draw()
            self.clock.tick(FPS)

if __name__ == '__main__':
    port = sys.argv[1] if len(sys.argv) > 1 else 'COM5'
    SpaceShooter(port).run()
