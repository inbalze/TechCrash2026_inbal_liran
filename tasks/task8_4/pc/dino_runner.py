import pygame
import threading
import serial
import sys
import random
import math
import os
import scores_io

# Screen dimensions
SCREEN_W = 800
SCREEN_H = 400
FPS      = 60
GROUND_Y = 320

# Colors (Retro Synthwave / Cyberpunk Neon Palette)
BLACK  = (10, 10, 18)
WHITE  = (240, 240, 250)
GREEN  = (50, 255, 150)   # Cacti neon
CYAN   = (0, 255, 255)    # Shield & HUD highlight
PURPLE = (200, 80, 255)   # Pterodactyls & Mountain outline
YELLOW = (255, 230, 0)    # Milestones & Stars
RED    = (255, 50, 100)    # Game Over red & explosions
GREY   = (90, 90, 110)    # Dust particles / details
DARK_PURPLE = (20, 10, 35) # Mountain fill

# Hardware interface mapping
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

# Helper drawers
def draw_cactus(surface, x, y, w, h, color):
    # Main vertical trunk
    cx = x + w // 2
    pygame.draw.rect(surface, color, (cx - 3, y, 6, h), border_radius=2)
    # Left branch
    branch_h = h * 0.55
    by1 = y + h * 0.28
    pygame.draw.line(surface, color, (cx - 3, by1), (cx - 9, by1), 3)
    pygame.draw.line(surface, color, (cx - 9, by1), (cx - 9, by1 - branch_h + 8), 3)
    # Right branch
    by2 = y + h * 0.38
    pygame.draw.line(surface, color, (cx + 3, by2), (cx + 9, by2), 3)
    pygame.draw.line(surface, color, (cx + 9, by2), (cx + 9, by2 - branch_h + 6), 3)

def draw_ptero(surface, x, y, w, h, anim_frame, color):
    # Body
    pygame.draw.polygon(surface, color, [
        (x, y + h//2),
        (x + w//2, y + h//4),
        (x + w, y + h//2),
        (x + w//2, y + h*3//4)
    ])
    pygame.draw.polygon(surface, WHITE, [
        (x, y + h//2),
        (x + w//2, y + h//4),
        (x + w, y + h//2),
        (x + w//2, y + h*3//4)
    ], 1)
    
    # Eye
    pygame.draw.circle(surface, WHITE, (int(x + w*3//4), int(y + h//2 - 2)), 2)
    
    # Wings flapping
    if anim_frame == 0:
        # Wings up
        pygame.draw.polygon(surface, color, [
            (x + w//3, y + h//3),
            (x + w//2, y - 4),
            (x + w*2//3, y + h//3)
        ])
        pygame.draw.polygon(surface, WHITE, [
            (x + w//3, y + h//3),
            (x + w//2, y - 4),
            (x + w*2//3, y + h//3)
        ], 1)
    else:
        # Wings down
        pygame.draw.polygon(surface, color, [
            (x + w//3, y + h*2//3),
            (x + w//2, y + h + 4),
            (x + w*2//3, y + h*2//3)
        ])
        pygame.draw.polygon(surface, WHITE, [
            (x + w//3, y + h*2//3),
            (x + w//2, y + h + 4),
            (x + w*2//3, y + h*2//3)
        ], 1)

# Game Entities
class Dino:
    def __init__(self, x, ground_y):
        self.x = x
        self.ground_y = ground_y
        self.width = 40
        self.height = 50
        self.y = ground_y - self.height
        self.vy = 0.0
        self.state = 'running' # 'running', 'jumping', 'ducking'
        self.anim_tick = 0

    def update(self, key0, key1):
        self.anim_tick += 1
        
        if self.state == 'jumping':
            # Hold KEY0/Space for longer jump (less gravity)
            gravity = 0.32 if key0 else 0.68
            
            # Active drop if ducking (KEY1) in mid-air
            down_force = 1.6 if key1 else 0.0
            
            self.vy += gravity + down_force
            self.y += self.vy
            
            # Landing check
            if self.y >= self.ground_y - 50:
                self.y = self.ground_y - 50
                self.vy = 0.0
                if key1:
                    self.state = 'ducking'
                    self.height = 26
                else:
                    self.state = 'running'
                    self.height = 50
        else:
            # Check jump trigger
            if key0:
                self.vy = -12.2
                self.state = 'jumping'
            elif key1:
                self.state = 'ducking'
                self.height = 26
            else:
                self.state = 'running'
                self.height = 50
                
        # Constrain absolute Y position based on state
        if self.state != 'jumping':
            self.y = self.ground_y - self.height

    def draw(self, surface, color, trail_color=None, has_trail=False, trail_history=None):
        anim_frame = (self.anim_tick // 6) % 2
        
        # 1. Draw motion trail if turbo active
        if has_trail and trail_history:
            for idx, (tx, ty, tstate) in enumerate(trail_history):
                # Fade factor
                alpha = int(90 * (idx + 1) / len(trail_history))
                trail_surface = pygame.Surface((self.width + 20, self.height + 20), pygame.SRCALPHA)
                
                # Draw local outline dino to trail_surface
                color_with_alpha = (*trail_color, alpha)
                white_with_alpha = (255, 255, 255, alpha)
                
                if tstate == 'ducking':
                    pts = [(p[0] - tx, p[1] - ty) for p in [
                        (tx, ty + 15), (tx + 15, ty + 10), (tx + 40, ty + 10),
                        (tx + 55, ty + 10), (tx + 55, ty + 18), (tx + 45, ty + 18),
                        (tx + 35, ty + 26), (tx + 15, ty + 26)
                    ]]
                    pygame.draw.polygon(trail_surface, color_with_alpha, pts)
                    pygame.draw.polygon(trail_surface, white_with_alpha, pts, 1)
                else:
                    pts = [(p[0] - tx, p[1] - ty) for p in [
                        (tx + 5, ty + 25), (tx + 15, ty + 15), (tx + 20, ty + 0),
                        (tx + 40, ty + 0), (tx + 40, ty + 12), (tx + 30, ty + 12),
                        (tx + 28, ty + 20), (tx + 28, ty + 35), (tx + 15, ty + 38),
                        (tx + 8, ty + 38)
                    ]]
                    pygame.draw.polygon(trail_surface, color_with_alpha, pts)
                    pygame.draw.polygon(trail_surface, white_with_alpha, pts, 1)
                
                surface.blit(trail_surface, (tx, ty))

        # 2. Draw active dino
        x, y = self.x, self.y
        if self.state == 'ducking':
            pts = [
                (x, y + 15), # Tail tip
                (x + 15, y + 10), # Back
                (x + 40, y + 10), # Head start
                (x + 55, y + 10), # Snout top
                (x + 55, y + 18), # Snout bottom
                (x + 45, y + 18), # Neck
                (x + 35, y + 26), # Body bottom
                (x + 15, y + 26), # Tail bottom
            ]
            pygame.draw.polygon(surface, color, pts)
            pygame.draw.polygon(surface, WHITE, pts, 1)
            pygame.draw.circle(surface, BLACK, (int(x + 45), int(y + 13)), 2)
            
            # Legs
            leg_y = y + 26
            if anim_frame == 0:
                pygame.draw.line(surface, color, (x + 22, leg_y), (x + 18, leg_y + 6), 3)
                pygame.draw.line(surface, color, (x + 30, leg_y), (x + 32, leg_y + 6), 3)
            else:
                pygame.draw.line(surface, color, (x + 22, leg_y), (x + 26, leg_y + 6), 3)
                pygame.draw.line(surface, color, (x + 30, leg_y), (x + 26, leg_y + 6), 3)
        else:
            # Running/Jumping
            pts = [
                (x + 5, y + 25),   # Tail tip
                (x + 15, y + 15),  # Back
                (x + 20, y + 0),   # Head top-left
                (x + 40, y + 0),   # Snout top-right
                (x + 40, y + 12),  # Snout bottom-right
                (x + 30, y + 12),  # Jaw
                (x + 28, y + 20),  # Neck
                (x + 28, y + 35),  # Chest
                (x + 15, y + 38),  # Belly
                (x + 8, y + 38),   # Under-tail
            ]
            pygame.draw.polygon(surface, color, pts)
            pygame.draw.polygon(surface, WHITE, pts, 1)
            pygame.draw.circle(surface, BLACK, (int(x + 32), int(y + 4)), 2)
            pygame.draw.line(surface, color, (x + 28, y + 20), (x + 33, y + 23), 2)
            
            # Legs
            leg_y = y + 38
            if self.state == 'jumping':
                pygame.draw.line(surface, color, (x + 14, leg_y), (x + 14, leg_y + 10), 3)
                pygame.draw.line(surface, color, (x + 22, leg_y), (x + 22, leg_y + 10), 3)
            else:
                if anim_frame == 0:
                    pygame.draw.line(surface, color, (x + 12, leg_y), (x + 8, leg_y + 10), 3)
                    pygame.draw.line(surface, color, (x + 20, leg_y), (x + 24, leg_y + 10), 3)
                else:
                    pygame.draw.line(surface, color, (x + 12, leg_y), (x + 16, leg_y + 10), 3)
                    pygame.draw.line(surface, color, (x + 20, leg_y), (x + 16, leg_y + 10), 3)

class Obstacle:
    def __init__(self, x, y, width, height, color):
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color

    def update(self, speed):
        self.x -= speed

    def is_out_of_screen(self):
        return self.x < -self.width

class Cactus(Obstacle):
    def __init__(self, x, ground_y):
        self.type = random.choice([1, 2, 3])
        cactus_w = 20
        spacing = 10
        width = cactus_w * self.type + spacing * (self.type - 1)
        height = random.randint(35, 52)
        y = ground_y - height
        super().__init__(x, y, width, height, GREEN)
        self.heights = [random.randint(height - 8, height) for _ in range(self.type)]

    def draw(self, surface):
        cactus_w = 20
        spacing = 10
        for i in range(self.type):
            cx = self.x + i * (cactus_w + spacing)
            ch = self.heights[i]
            cy = self.y + (self.height - ch)
            draw_cactus(surface, cx, cy, cactus_w, ch, self.color)

class Pterodactyl(Obstacle):
    def __init__(self, x, ground_y):
        width = 36
        height = 28
        h_type = random.choice(['low', 'low', 'medium', 'high'])
        if h_type == 'low':
            y = ground_y - 25
        elif h_type == 'medium':
            y = ground_y - 52
        else:
            y = ground_y - 82
            
        super().__init__(x, y, width, height, PURPLE)
        self.anim_tick = random.randint(0, 100)

    def draw(self, surface):
        self.anim_tick += 1
        anim_frame = (self.anim_tick // 10) % 2
        draw_ptero(surface, self.x, self.y, self.width, self.height, anim_frame, self.color)


ORANGE = (255, 140, 0)
LASER  = (255, 60, 60)

class LaserBeam(Obstacle):
    """Horizontal laser at dino body height — must duck to pass under."""
    def __init__(self, x, ground_y):
        width  = random.randint(80, 140)
        height = 14
        y = ground_y - 48   # hits standing dino body, clears ducking dino
        super().__init__(x, y, width, height, LASER)
        self.tick = 0

    def draw(self, surface):
        self.tick += 1
        pulse = abs(math.sin(self.tick * 0.18))
        glow_col = (255, int(60 + 80 * pulse), int(60 * pulse))
        # Glow outer
        pygame.draw.rect(surface, glow_col, (self.x - 2, self.y - 2, self.width + 4, self.height + 4), border_radius=4)
        # Core beam
        pygame.draw.rect(surface, LASER, (self.x, self.y, self.width, self.height), border_radius=3)
        # Bright centre line
        pygame.draw.rect(surface, (255, 220, 220), (self.x + 4, self.y + 4, self.width - 8, 4), border_radius=2)
        # End caps
        for cx in (self.x - 4, self.x + self.width):
            pygame.draw.circle(surface, ORANGE, (cx, self.y + self.height // 2), 7)
            pygame.draw.circle(surface, LASER,  (cx, self.y + self.height // 2), 4)


class DoubleBarrier(Obstacle):
    """Two stacked boxes at body height — must duck under the gap."""
    def __init__(self, x, ground_y):
        width  = 22
        height = 60
        y = ground_y - height
        super().__init__(x, y, width, height, ORANGE)
        self.ground_y = ground_y

    def draw(self, surface):
        # Lower box (on ground)
        lower_h = 20
        lower_y = self.ground_y - lower_h
        pygame.draw.rect(surface, ORANGE, (self.x, lower_y, self.width, lower_h), border_radius=3)
        pygame.draw.rect(surface, (255, 200, 80), (self.x, lower_y, self.width, lower_h), 2, border_radius=3)
        # Upper box (floating — duck goes under it)
        upper_h = 22
        upper_y = self.ground_y - lower_h - 18 - upper_h  # 18-px gap = duck clearance
        pygame.draw.rect(surface, ORANGE, (self.x, upper_y, self.width, upper_h), border_radius=3)
        pygame.draw.rect(surface, (255, 200, 80), (self.x, upper_y, self.width, upper_h), 2, border_radius=3)

class Particle:
    def __init__(self, x, y, vx, vy, color, size, life):
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.color = color
        self.size = size
        self.life = life
        self.max_life = life

    def update(self):
        self.x += self.vx
        self.y += self.vy
        self.life -= 1

    def draw(self, surface):
        alpha = int(255 * (self.life / self.max_life))
        r, g, b = self.color
        # Surface with alpha support
        p_surf = pygame.Surface((self.size * 2, self.size * 2), pygame.SRCALPHA)
        pygame.draw.circle(p_surf, (r, g, b, alpha), (self.size, self.size), self.size)
        surface.blit(p_surf, (self.x - self.size, self.y - self.size))

class DinoRunner:
    def __init__(self, port):
        pygame.init()
        self.screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
        pygame.display.set_caption("NEON DINO RUNNER")
        self.clock = pygame.time.Clock()
        self.fnt_s = pygame.font.SysFont(None, 24)
        self.fnt_l = pygame.font.SysFont(None, 64)
        
        self.serial = SerialThread(port)
        self.serial.start()
        
        self.high_score = self._load_high_score()
        import time as _t; _t.sleep(0.4)
        with hw_lock:
            self.sw9_prev = hw_state['SW9']
        self._reset()

    def _load_high_score(self):
        h_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dino_high_score.txt')
        try:
            if os.path.exists(h_file):
                with open(h_file, 'r') as f:
                    return int(f.read().strip())
        except Exception:
            pass
        return 0

    def _save_high_score(self):
        h_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dino_high_score.txt')
        try:
            with open(h_file, 'w') as f:
                f.write(str(self.high_score))
        except Exception:
            pass
        scores_io.save('dino', self.high_score)

    def _reset(self):
        self.state = 'playing'
        self.score = 0.0
        self.prev_score = 0.0
        self.battery = 100.0
        self.paused = False
        
        self.dino = Dino(80, GROUND_Y)
        self.obstacles = []
        self.particles = []
        
        # Parallax environment
        self.stars = [{'x': random.randint(0, SCREEN_W), 'y': random.randint(15, 160), 'speed': random.uniform(0.1, 0.4), 'size': random.randint(1, 2)} for _ in range(25)]
        self.clouds = [{'x': random.randint(0, SCREEN_W), 'y': random.randint(25, 90), 'speed': random.uniform(0.3, 0.7), 'width': random.randint(45, 80)} for _ in range(4)]
        self.mountain_peaks = [
            (50, 60), (180, 95), (320, 50), (450, 80), (600, 40), 
            (750, 70), (900, 55), (1050, 90), (1200, 45)
        ]
        self.mountain_scroll = 0.0
        self.ground_scroll = 0.0
        
        self.next_spawn_dist = random.randint(320, 500)
        self.screen_shake = 0
        self.flash_timer = 0
        self.milestone_timer = 0
        self.trail_history = []
        
        # Background lerp state
        self.bg_color = (25, 25, 35)

    def _hw(self):
        with hw_lock:
            hw = dict(hw_state)
            
        # Keyboard inputs fallback for testing
        k = pygame.key.get_pressed()
        if k[pygame.K_SPACE] or k[pygame.K_UP]:
            hw['KEY0'] = 1
        if k[pygame.K_DOWN]:
            hw['KEY1'] = 1
            
        return hw

    def _trigger_shield_burst(self, x, y):
        for _ in range(16):
            angle = random.uniform(0, 2 * math.pi)
            speed = random.uniform(2.0, 5.0)
            vx = math.cos(angle) * speed
            vy = math.sin(angle) * speed
            self.particles.append(Particle(x, y, vx, vy, CYAN, random.randint(3, 5), random.randint(20, 30)))

    def _trigger_death_explosion(self):
        for _ in range(35):
            vx = random.uniform(-4.0, 4.0)
            vy = random.uniform(-6.0, 2.0)
            self.particles.append(Particle(self.dino.x + 20, self.dino.y + 25, vx, vy, RED, random.randint(3, 6), random.randint(25, 40)))

    def update(self):
        hw = self._hw()
        
        # 1. Update Game Speed
        # Speed slowly scales with score.
        base_speed = 5.5 + (self.score * 0.001)
        if base_speed > 11.5:
            base_speed = 11.5
            
        # SW0 activates Turbo Mode (1.6x speed, double points)
        turbo_active = hw['SW0'] == 1
        game_speed = base_speed * 1.6 if turbo_active else base_speed
        
        # 2. Update environment scrolls
        self.mountain_scroll += game_speed * 0.12
        self.ground_scroll = (self.ground_scroll - game_speed) % 50
        
        for star in self.stars:
            star['x'] = (star['x'] - star['speed'] * game_speed * 0.1) % SCREEN_W
            
        for cloud in self.clouds:
            cloud['x'] = (cloud['x'] - cloud['speed'] * game_speed * 0.15) % SCREEN_W

        # 3. Update Dino position & physics
        self.dino.update(hw['KEY0'], hw['KEY1'])
        
        # Track motion trail for Turbo mode
        if turbo_active and self.dino.state != 'dead':
            self.trail_history.append((self.dino.x, self.dino.y, self.dino.state))
            if len(self.trail_history) > 6:
                self.trail_history.pop(0)
        else:
            self.trail_history.clear()

        # 4. Spawning particles (dust/trail)
        if self.dino.state in ('running', 'ducking') and random.random() < 0.25:
            # Feet dust
            dust_x = self.dino.x + (10 if self.dino.state == 'running' else 15)
            self.particles.append(Particle(
                dust_x, GROUND_Y - 2,
                random.uniform(-2.5, -0.5) - game_speed * 0.15,
                random.uniform(-1.0, 0.0),
                GREY, random.randint(2, 4), random.randint(15, 30)
            ))
            
        if turbo_active and random.random() < 0.4:
            # Trail particles
            self.particles.append(Particle(
                random.uniform(self.dino.x, self.dino.x + self.dino.width),
                random.uniform(self.dino.y, self.dino.y + self.dino.height),
                -1.5, random.uniform(-0.5, 0.5),
                CYAN, random.randint(2, 3), 12
            ))

        # 5. Update particles
        for p in self.particles[:]:
            p.update()
            if p.life <= 0:
                self.particles.remove(p)

        # 6. Obstacle Spawning & movement
        # Update current obstacles
        for obs in self.obstacles[:]:
            obs.update(game_speed)
            if obs.is_out_of_screen():
                self.obstacles.remove(obs)

        # Check Spawning using pixel distance
        if not self.obstacles:
            self._spawn_obstacle()
        else:
            last_obs = self.obstacles[-1]
            if (SCREEN_W - last_obs.x) > self.next_spawn_dist:
                self._spawn_obstacle()

        # 7. Energy Shield (SW2)
        shield_active = hw['SW2'] == 1 and self.battery > 0
        if hw['SW2']:
            if self.battery > 0:
                self.battery = max(0.0, self.battery - 0.35)
        else:
            self.battery = min(100.0, self.battery + 0.08)

        # 8. Collisions with Obstacles
        # Forgiving hitbox adjustments
        dino_rect = pygame.Rect(self.dino.x + 4, self.dino.y + 4, self.dino.width - 8, self.dino.height - 8)
        
        for obs in self.obstacles[:]:
            obs_rect = pygame.Rect(obs.x + 3, obs.y + 3, obs.width - 6, obs.height - 6)
            if dino_rect.colliderect(obs_rect):
                if shield_active:
                    # Absorb obstacle
                    self._trigger_shield_burst(obs.x + obs.width//2, obs.y + obs.height//2)
                    self.battery = max(0.0, self.battery - 18.0)
                    self.obstacles.remove(obs)
                    self.screen_shake = 10
                else:
                    # Game Over
                    self.state = 'game_over'
                    self.dino.state = 'dead'
                    self._trigger_death_explosion()
                    if int(self.score) > self.high_score:
                        self.high_score = int(self.score)
                        self._save_high_score()
                    break

        # 9. Scoring and Milestones
        self.prev_score = self.score
        score_increment = 0.25 if turbo_active else 0.12
        self.score += score_increment
        
        # 100-point milestones
        if int(self.score) // 100 > int(self.prev_score) // 100:
            self.flash_timer = 8
            self.milestone_timer = 60
            self.screen_shake = 6

        # 10. Background Color Lerp (Day / Night cycle every 700 pts)
        cycle = int(self.score) // 700
        progress = (self.score % 700) / 700.0
        
        transition_zone = 120.0 / 700.0
        if progress < transition_zone:
            t = progress / transition_zone
            prev_is_day = ((cycle - 1) % 2 == 0) if cycle > 0 else True
            curr_is_day = (cycle % 2 == 0)
        else:
            t = 1.0
            curr_is_day = (cycle % 2 == 0)
            prev_is_day = curr_is_day
            
        day_color = (25, 25, 35)      # Deep grey day
        night_color = (8, 6, 16)       # Synthwave night
        
        if prev_is_day != curr_is_day:
            c_start = day_color if prev_is_day else night_color
            c_end = day_color if curr_is_day else night_color
            r = int(c_start[0] + (c_end[0] - c_start[0]) * t)
            g = int(c_start[1] + (c_end[1] - c_start[1]) * t)
            b = int(c_start[2] + (c_end[2] - c_start[2]) * t)
            self.bg_color = (r, g, b)
        else:
            self.bg_color = day_color if curr_is_day else night_color

        # Damp timers
        if self.screen_shake > 0:
            self.screen_shake -= 1
        if self.flash_timer > 0:
            self.flash_timer -= 1
        if self.milestone_timer > 0:
            self.milestone_timer -= 1

    def _spawn_obstacle(self):
        spawn_x = SCREEN_W + 50
        roll = random.random()

        if self.score >= 80 and roll < 0.22:
            self.obstacles.append(LaserBeam(spawn_x, GROUND_Y))
        elif self.score >= 120 and roll < 0.38:
            self.obstacles.append(DoubleBarrier(spawn_x, GROUND_Y))
        elif self.score >= 150 and roll < 0.58:
            self.obstacles.append(Pterodactyl(spawn_x, GROUND_Y))
        else:
            self.obstacles.append(Cactus(spawn_x, GROUND_Y))

        self.next_spawn_dist = random.randint(300, 500)

    def draw(self):
        shake_x = 0
        shake_y = 0
        if self.screen_shake > 0:
            shake_x = random.randint(-self.screen_shake, self.screen_shake)
            shake_y = random.randint(-self.screen_shake, self.screen_shake)

        # Clear Screen with day/night lerped background
        self.screen.fill(self.bg_color)
        
        # Day/Night star alpha fading
        cycle = int(self.score) // 700
        progress = (self.score % 700) / 700.0
        transition_zone = 120.0 / 700.0
        if progress < transition_zone:
            t = progress / transition_zone
            prev_is_day = ((cycle - 1) % 2 == 0) if cycle > 0 else True
            curr_is_day = (cycle % 2 == 0)
        else:
            t = 1.0
            curr_is_day = (cycle % 2 == 0)
            prev_is_day = curr_is_day
            
        if curr_is_day:
            night_factor = 1.0 - t if prev_is_day != curr_is_day else 0.0
        else:
            night_factor = t if prev_is_day != curr_is_day else 1.0

        # Draw stars
        if night_factor > 0:
            for star in self.stars:
                s_color = int(120 + 135 * night_factor)
                pygame.draw.circle(
                    self.screen, (s_color, s_color, int(s_color * 0.8)),
                    (int(star['x'] + shake_x), int(star['y'] + shake_y)),
                    star['size']
                )

        # Draw clouds
        for cloud in self.clouds:
            cx, cy, cw = cloud['x'] + shake_x, cloud['y'] + shake_y, cloud['width']
            pygame.draw.rect(self.screen, (100, 100, 120, 100), (cx, cy, cw, 10), border_radius=5)

        # Draw mountains (parallax background)
        for mx, mh in self.mountain_peaks:
            # Map peak X coordinates
            rx = int((mx - self.mountain_scroll) % 1350 - 100) + shake_x
            # Mountain triangle points
            pts = [
                (rx - 70, GROUND_Y + shake_y),
                (rx, GROUND_Y - mh + shake_y),
                (rx + 70, GROUND_Y + shake_y)
            ]
            pygame.draw.polygon(self.screen, DARK_PURPLE, pts)
            pygame.draw.polygon(self.screen, PURPLE, pts, 1)

        # Draw ground line and notches
        pygame.draw.line(self.screen, CYAN, (0, GROUND_Y + shake_y), (SCREEN_W, GROUND_Y + shake_y), 2)
        
        # Ground notches
        for gx in range(-50, SCREEN_W + 50, 50):
            rx = int(gx + self.ground_scroll) + shake_x
            pygame.draw.line(self.screen, CYAN, (rx, GROUND_Y + 4 + shake_y), (rx + 12, GROUND_Y + 4 + shake_y), 2)

        # Draw obstacles
        for obs in self.obstacles:
            # Adjust offset for drawing
            obs_x_orig = obs.x
            obs.x += shake_x
            obs.y += shake_y
            obs.draw(self.screen)
            obs.x = obs_x_orig
            obs.y -= shake_y

        # Draw particles
        for p in self.particles:
            p.draw(self.screen)

        # Draw Dino
        if self.state == 'playing':
            hw = self._hw()
            # Determine color theme: Neon pink/magenta normally, yellow under Turbo
            dino_color = YELLOW if hw['SW0'] else RED
            self.dino.draw(self.screen, dino_color, CYAN, hw['SW0'], self.trail_history)
            
            # Shield effect
            if hw['SW2'] and self.battery > 0:
                dx, dy = self.dino.x + self.dino.width//2 + shake_x, self.dino.y + self.dino.height//2 + shake_y
                radius = max(self.dino.width, self.dino.height)//2 + 8
                
                # Glowing outer border
                pygame.draw.circle(self.screen, CYAN, (int(dx), int(dy)), radius, 2)
                # Glassmorphic inner fill
                shield_surface = pygame.Surface((radius * 2, radius * 2), pygame.SRCALPHA)
                pygame.draw.circle(shield_surface, (0, 255, 255, 25), (radius, radius), radius)
                self.screen.blit(shield_surface, (dx - radius, dy - radius))

        # 10. HUD / UI Status Bar (bottom)
        pygame.draw.rect(self.screen, (15, 15, 25), (0, GROUND_Y + 18, SCREEN_W, SCREEN_H - GROUND_Y - 18))
        pygame.draw.line(self.screen, GREY, (0, GROUND_Y + 18), (SCREEN_W, GROUND_Y + 18), 1)

        # Score & High Score
        score_str = f"{int(self.score):05d}"
        hi_str = f"{self.high_score:05d}"
        
        # Display milestone alert flash
        score_color = YELLOW if self.milestone_timer > 0 and (self.milestone_timer // 5) % 2 == 0 else WHITE
        self.screen.blit(self.fnt_s.render(f"SCORE  {score_str}", True, score_color), (24, GROUND_Y + 36))
        self.screen.blit(self.fnt_s.render(f"HI  {hi_str}", True, GREY), (170, GROUND_Y + 36))
        
        if self.milestone_timer > 0:
            self.screen.blit(self.fnt_s.render("+100 SCORE!", True, YELLOW), (280, GROUND_Y + 36))

        # Battery / Shield status bar
        bx, by = SCREEN_W - 200, GROUND_Y + 36
        pygame.draw.rect(self.screen, (40, 40, 50), (bx, by, 120, 14))
        bw = int(120 * self.battery / 100)
        bc = CYAN if self.battery > 50 else YELLOW if self.battery > 20 else RED
        pygame.draw.rect(self.screen, bc, (bx, by, bw, 14))
        pygame.draw.rect(self.screen, WHITE, (bx, by, 120, 14), 1)
        self.screen.blit(self.fnt_s.render("SHIELD", True, CYAN), (bx - 70, by - 1))

        # Draw SW0 "TURBO" status indicator
        hw = self._hw()
        if hw['SW0']:
            pygame.draw.rect(self.screen, YELLOW, (420, GROUND_Y + 33, 70, 20), border_radius=4)
            self.screen.blit(self.fnt_s.render("TURBO", True, BLACK), (430, GROUND_Y + 35))

        # 11. Overlays
        if self.paused:
            dim = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            dim.fill((0, 0, 0, 150))
            self.screen.blit(dim, (0, 0))
            lbl = self.fnt_l.render("PAUSED", True, YELLOW)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
            sub = self.fnt_s.render("flip SW1 DOWN to resume", True, WHITE)
            self.screen.blit(sub, (SCREEN_W//2 - sub.get_width()//2, SCREEN_H//2 + 20))
        elif self.state == 'game_over':
            dim = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            dim.fill((0, 0, 0, 180))
            self.screen.blit(dim, (0, 0))
            lbl = self.fnt_l.render("GAME OVER", True, RED)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 45))
            sub = self.fnt_s.render("flip SW9 UP to restart", True, WHITE)
            self.screen.blit(sub, (SCREEN_W//2 - sub.get_width()//2, SCREEN_H//2 + 15))

        # 12. Full-screen flash logic (for milestone)
        if self.flash_timer > 0:
            flash_surf = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
            flash_surf.fill((255, 255, 255, int(130 * (self.flash_timer / 8))))
            self.screen.blit(flash_surf, (0, 0))

        pygame.display.flip()

    def run(self):
        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.serial.stop()
                    pygame.quit()
                    sys.exit()
                elif ev.type == pygame.KEYDOWN:
                    if ev.key == pygame.K_1:
                        with hw_lock:
                            hw_state['SW0'] = 1 - hw_state['SW0']
                    elif ev.key == pygame.K_2:
                        with hw_lock:
                            hw_state['SW1'] = 1 - hw_state['SW1']
                    elif ev.key == pygame.K_3:
                        with hw_lock:
                            hw_state['SW2'] = 1 - hw_state['SW2']
                    elif ev.key in (pygame.K_r, pygame.K_9):
                        with hw_lock:
                            hw_state['SW9'] = 1
                elif ev.type == pygame.KEYUP:
                    if ev.key in (pygame.K_r, pygame.K_9):
                        with hw_lock:
                            hw_state['SW9'] = 0

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
    DinoRunner(port).run()
