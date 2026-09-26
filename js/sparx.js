/**
 * Sparx & Super Sparx Enemy Engine
 * Autonomous perimeter-patrolling sparks that follow borders and chase Stix lines.
 */

class Sparx {
  constructor(grid, x, y, isClockwise = true, isSuper = false) {
    this.grid = grid;
    this.x = x;
    this.y = y;
    this.isClockwise = isClockwise;
    this.isSuper = isSuper;

    // Movement direction: 0: Right, 1: Down, 2: Left, 3: Up
    this.dir = isClockwise ? 0 : 2;
    this.stepAccumulator = 0;
    this.sparkAngle = 0;

    // Stix chase state for Super Sparx
    this.chasingStix = false;
    this.stixIndex = 0;
  }

  // Set to Super Sparx
  mutateToSuper() {
    this.isSuper = true;
  }

  update(player) {
    this.sparkAngle += 0.25;

    // Speed: Super Sparx is significantly faster
    const stepsPerFrame = this.isSuper ? 1.9 : 1.2;
    this.stepAccumulator += stepsPerFrame;

    while (this.stepAccumulator >= 1.0) {
      this.stepAccumulator -= 1.0;
      this.step(player);
    }
  }

  step(player) {
    // Check if Super Sparx should chase active Stix
    if (this.isSuper && player && player.isDrawing() && player.stixPath.length > 0) {
      // If close to Stix origin or on Stix
      if (!this.chasingStix) {
        const origin = player.stixPath[0];
        if (Math.hypot(this.x - origin.x, this.y - origin.y) <= 2.0) {
          this.chasingStix = true;
          this.stixIndex = 0;
        }
      }

      if (this.chasingStix) {
        if (this.stixIndex < player.stixPath.length) {
          const pt = player.stixPath[this.stixIndex];
          this.x = pt.x;
          this.y = pt.y;
          this.stixIndex++;
          return;
        } else {
          // Reached current head of Stix
          this.x = player.x;
          this.y = player.y;
          return;
        }
      }
    } else {
      this.chasingStix = false;
    }

    // Normal border navigation using wall-following rule
    const dxList = [1, 0, -1, 0];
    const dyList = [0, 1, 0, -1];

    // Direction priority order
    let dirOffsets;
    if (this.isClockwise) {
      dirOffsets = [1, 0, 3, 2]; // Right turn, straight, Left turn, 180 reverse
    } else {
      dirOffsets = [3, 0, 1, 2]; // Left turn, straight, Right turn, 180 reverse
    }

    let moved = false;
    for (const offset of dirOffsets) {
      const testDir = (this.dir + offset + 4) % 4;
      const nx = this.x + dxList[testDir];
      const ny = this.y + dyList[testDir];

      if (this.grid.isBorder(nx, ny)) {
        this.x = nx;
        this.y = ny;
        this.dir = testDir;
        moved = true;
        break;
      }
    }

    // Fallback: If trapped in obsolete internal border, snap to nearest active border
    if (!moved) {
      const active = this.findNearestActiveBorder();
      if (active) {
        this.x = active.x;
        this.y = active.y;
      }
    }
  }

  findNearestActiveBorder() {
    for (let r = 1; r < 10; r++) {
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          const nx = this.x + dx;
          const ny = this.y + dy;
          if (this.grid.isActiveBorder(nx, ny)) {
            return { x: nx, y: ny };
          }
        }
      }
    }
    return null;
  }

  checkCollision(player) {
    const dist = Math.hypot(this.x - player.x, this.y - player.y);
    return dist < 2.5;
  }

  render(ctx, scaleX = 1, scaleY = 1) {
    ctx.save();
    const cx = this.x * scaleX;
    const cy = this.y * scaleY;

    ctx.translate(cx, cy);
    ctx.rotate(this.sparkAngle);

    // High-visibility sizes
    const size = this.isSuper ? 14 : 10;

    // 1. High-contrast dark backdrop disc so Sparx is vividly visible on all backgrounds & borders
    ctx.fillStyle = 'rgba(5, 7, 13, 0.90)';
    ctx.beginPath();
    ctx.arc(0, 0, size * 1.35, 0, Math.PI * 2);
    ctx.fill();

    if (this.isSuper) {
      // Pulsing Super Sparx: intense electric cyan / magenta / white
      const pulse = Math.sin(this.sparkAngle * 4);
      const primaryColor = pulse > 0 ? '#ff0077' : '#00f0ff';
      const secondaryColor = pulse > 0 ? '#00f0ff' : '#ffea00';

      // Outer electric star
      ctx.strokeStyle = primaryColor;
      ctx.shadowColor = primaryColor;
      ctx.shadowBlur = 16;
      ctx.lineWidth = 2.8;

      ctx.beginPath();
      for (let i = 0; i < 8; i++) {
        const a = (i * Math.PI) / 4;
        const r = i % 2 === 0 ? size * 1.4 : size * 0.65;
        const px = Math.cos(a) * r;
        const py = Math.sin(a) * r;
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
      ctx.stroke();

      // Sizzling electric sparks
      ctx.strokeStyle = secondaryColor;
      ctx.lineWidth = 1.6;
      for (let i = 0; i < 4; i++) {
        const a = (i * Math.PI) / 2 + Math.PI / 4;
        const r1 = size * 0.7;
        const r2 = size * 1.6;
        ctx.beginPath();
        ctx.moveTo(Math.cos(a) * r1, Math.sin(a) * r1);
        ctx.lineTo(Math.cos(a) * r2, Math.sin(a) * r2);
        ctx.stroke();
      }

      // Bright white energetic core
      ctx.fillStyle = '#ffffff';
      ctx.shadowColor = '#ffffff';
      ctx.shadowBlur = 10;
      ctx.beginPath();
      ctx.arc(0, 0, 4.0, 0, Math.PI * 2);
      ctx.fill();
    } else {
      // Normal Sparx: bright fiery solar flare
      ctx.strokeStyle = '#ffcc00';
      ctx.shadowColor = '#ff4400';
      ctx.shadowBlur = 14;
      ctx.lineWidth = 2.6;

      // 4-point primary spark cross
      ctx.beginPath();
      ctx.moveTo(-size * 1.3, 0);
      ctx.lineTo(size * 1.3, 0);
      ctx.moveTo(0, -size * 1.3);
      ctx.lineTo(0, size * 1.3);
      ctx.stroke();

      // 4-point secondary diagonal sparks
      ctx.lineWidth = 1.8;
      ctx.strokeStyle = '#ff6600';
      const diag = size * 0.75;
      ctx.beginPath();
      ctx.moveTo(-diag, -diag);
      ctx.lineTo(diag, diag);
      ctx.moveTo(-diag, diag);
      ctx.lineTo(diag, -diag);
      ctx.stroke();

      // Fiery inner core
      ctx.fillStyle = '#ff2200';
      ctx.beginPath();
      ctx.arc(0, 0, 4.5, 0, Math.PI * 2);
      ctx.fill();

      // White-hot center beacon
      ctx.fillStyle = '#ffffff';
      ctx.shadowColor = '#ffffff';
      ctx.shadowBlur = 8;
      ctx.beginPath();
      ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.restore();
  }
}

class SparxManager {
  constructor(grid) {
    this.grid = grid;
    this.sparxList = [];
    this.sparxTimerMax = 35; // seconds until Super Sparx & additional spawn
    this.timer = this.sparxTimerMax;
    this.hasMutated = false;
  }

  reset(level = 1, difficulty = 'normal') {
    this.sparxList = [];

    // Scale timer and initial count smoothly across levels & difficulty
    let baseL1Timer = 50;
    let baseL2Timer = 38;
    let baseL3Timer = 32;

    if (difficulty === 'beginner') {
      baseL1Timer = 60;
      baseL2Timer = 48;
      baseL3Timer = 40;
    } else if (difficulty === 'master' || difficulty === 'hard') {
      baseL1Timer = 34;
      baseL2Timer = 26;
      baseL3Timer = 22;
    }

    if (level === 1) {
      this.sparxTimerMax = baseL1Timer; // Generous timer on level 1
      this.timer = this.sparxTimerMax;
      this.hasMutated = false;
      // Start with 1 Sparx on level 1 for accessible on-boarding
      this.sparxList.push(new Sparx(this.grid, this.grid.width - 1, 0, false, false));
    } else if (level === 2) {
      this.sparxTimerMax = baseL2Timer;
      this.timer = this.sparxTimerMax;
      this.hasMutated = false;
      // 2 Sparx on level 2
      this.sparxList.push(new Sparx(this.grid, 0, 0, true, false));
      this.sparxList.push(new Sparx(this.grid, this.grid.width - 1, 0, false, false));
    } else {
      // Level 3+ (Dual Qix challenge)
      this.sparxTimerMax = Math.max(difficulty === 'beginner' ? 24 : 18, baseL3Timer - (level - 3) * 3);
      this.timer = this.sparxTimerMax;
      this.hasMutated = false;
      this.sparxList.push(new Sparx(this.grid, 0, 0, true, false));
      this.sparxList.push(new Sparx(this.grid, this.grid.width - 1, 0, false, false));
    }
  }

  update(dt, player) {
    if (this.timer > 0) {
      this.timer -= dt;
      if (this.timer <= 0) {
        this.timer = 0;
        this.triggerSuperSparx();
      }
    }

    for (const s of this.sparxList) {
      s.update(player);
    }
  }

  triggerSuperSparx() {
    if (!this.hasMutated) {
      this.hasMutated = true;
      if (window.soundEngine) {
        window.soundEngine.playSuperSparxAlert();
      }
    }

    // Mutate existing Sparx to Super Sparx
    for (const s of this.sparxList) {
      s.mutateToSuper();
    }

    // Spawn an additional Super Sparx
    this.sparxList.push(new Sparx(this.grid, 0, this.grid.height - 1, true, true));
  }

  checkCollision(player) {
    // Invulnerability respawn shield check
    if (player && player.isShielded && player.isShielded()) {
      return false;
    }

    for (const s of this.sparxList) {
      if (s.checkCollision(player)) {
        return true;
      }
    }
    return false;
  }

  render(ctx, scaleX = 1, scaleY = 1) {
    for (const s of this.sparxList) {
      s.render(ctx, scaleX, scaleY);
    }
  }
}

window.Sparx = Sparx;
window.SparxManager = SparxManager;
