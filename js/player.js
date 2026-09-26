/**
 * Qix Player Marker Engine
 * Diamond marker, Fast & Slow Stix drawing, Fuse sizzle mechanics, and lives tracking.
 */

const STATE_BORDER = 0;
const STATE_DRAWING = 1;
const STATE_DEAD = 2;

class Player {
  constructor(grid) {
    this.grid = grid;
    this.reset();
  }

  reset() {
    // Start at bottom edge center
    this.x = Math.floor(this.grid.width / 2);
    this.y = this.grid.height - 1;
    this.state = STATE_BORDER;

    this.isSlow = false;
    this.stixPath = []; // Array of {x, y}
    this.drawOrigin = null;

    // Fuse state
    this.idleTimer = 0;
    this.fuseWarning = false;
    this.fuseActive = false;
    this.fuseIndex = 0;
    this.fuseWarningDelay = 0.60; // seconds idle before warning sparks (dynamically tuned by difficulty)
    this.fuseDelay = 1.10; // seconds idle before lethal fuse begins burning (fair for touch/turns)
    this.fuseBurnSpeed = 70; // points per second

    // Respawn Invulnerability Shield
    this.shieldTimer = 0;
    this.shieldDuration = 2.5; // 2.5s safe window on respawn

    // Movement accumulator for smooth fractional speeds
    this.moveAccumulator = 0;
    this.lastDir = { dx: 0, dy: 0 };
    this.drawSoundActive = false;
  }

  setDifficultyConfig(config = {}) {
    if (config.fuseWarningDelay !== undefined) this.fuseWarningDelay = config.fuseWarningDelay;
    if (config.fuseDelay !== undefined) this.fuseDelay = config.fuseDelay;
    if (config.fuseBurnSpeed !== undefined) this.fuseBurnSpeed = config.fuseBurnSpeed;
    if (config.shieldDuration !== undefined) this.shieldDuration = config.shieldDuration;
  }

  isShielded() {
    return this.shieldTimer > 0;
  }

  respawn() {
    // Clear any abandoned Stix cells
    if (this.stixPath.length > 0) {
      this.grid.clearStix(this.stixPath);
      this.stixPath = [];
    }

    this.stopSounds();

    // Find a safe border cell near bottom or top
    this.x = Math.floor(this.grid.width / 2);
    this.y = this.grid.height - 1;
    if (!this.grid.isBorder(this.x, this.y)) {
      // Find nearest active border
      let found = false;
      for (let y = this.grid.height - 1; y >= 0 && !found; y--) {
        for (let x = 0; x < this.grid.width; x++) {
          if (this.grid.isActiveBorder(x, y)) {
            this.x = x;
            this.y = y;
            found = true;
            break;
          }
        }
      }
    }

    this.state = STATE_BORDER;
    this.isSlow = false;
    this.idleTimer = 0;
    this.fuseWarning = false;
    this.fuseActive = false;
    this.fuseIndex = 0;

    // Grant generous grace period shield on respawn
    this.shieldTimer = this.shieldDuration;
  }

  isDrawing() {
    return this.state === STATE_DRAWING;
  }

  stopSounds() {
    if (window.soundEngine) {
      window.soundEngine.stopDraw();
      window.soundEngine.stopFuse();
    }
    this.drawSoundActive = false;
  }

  update(dt, input, qixList, onAreaCaptured, onDeath) {
    if (this.state === STATE_DEAD) return;

    // Grace period shield countdown
    if (this.shieldTimer > 0) {
      this.shieldTimer = Math.max(0, this.shieldTimer - dt);
    }

    // Movement input: { dx, dy, fastDraw, slowDraw }
    const wantsDraw = input.fastDraw || input.slowDraw;
    const hasMoveInput = input.dx !== 0 || input.dy !== 0;

    // Calculate movement speed in grid cells per second
    let speed;
    if (this.state === STATE_BORDER) {
      speed = 200; // Fast border traversal on wider grid
    } else {
      // Drawing speed: Fast draw is ~2x Slow draw
      speed = this.isSlow ? 60 : 120;
    }

    if (hasMoveInput) {
      this.idleTimer = 0;
      this.fuseWarning = false;
      if (this.fuseActive) {
        this.fuseActive = false;
        if (window.soundEngine) window.soundEngine.stopFuse();
      }

      this.moveAccumulator += speed * dt;
      while (this.moveAccumulator >= 1.0) {
        this.moveAccumulator -= 1.0;
        const result = this.step(input.dx, input.dy, wantsDraw, input.slowDraw, qixList);

        if (result && result.captured) {
          onAreaCaptured(result.captureResult);
          return;
        }
        if (result && result.died) {
          onDeath(result.reason);
          return;
        }
      }
    } else {
      this.moveAccumulator = 0;
      // Idle while drawing triggers Fuse warning and then burning!
      if (this.state === STATE_DRAWING) {
        this.idleTimer += dt;
        if (this.idleTimer >= this.fuseWarningDelay && this.idleTimer < this.fuseDelay) {
          this.fuseWarning = true;
        } else if (this.idleTimer >= this.fuseDelay) {
          this.fuseWarning = false;
          if (!this.fuseActive) {
            this.fuseActive = true;
            this.fuseIndex = 0;
            if (window.soundEngine) window.soundEngine.startFuse();
          }

          // Advance fuse along Stix path
          this.fuseIndex += this.fuseBurnSpeed * dt;
          if (this.fuseIndex >= this.stixPath.length - 1) {
            // Fuse reached player marker!
            this.stopSounds();
            onDeath('fuse');
            return;
          }
        }
      }
    }
  }

  step(dx, dy, wantsDraw, isSlowKey, qixList) {
    // Only cardinal 4-direction movement allowed
    if (dx !== 0 && dy !== 0) {
      // Prefer the larger or most recent axis
      dy = 0;
    }

    const nx = this.x + dx;
    const ny = this.y + dy;

    if (!this.grid.inBounds(nx, ny)) {
      return null;
    }

    const nextCell = this.grid.get(nx, ny);

    // ==========================================
    // CASE 1: Currently on BORDER
    // ==========================================
    if (this.state === STATE_BORDER) {
      // If moving to another BORDER cell: safe border navigation
      if (nextCell === CELL_BORDER) {
        this.x = nx;
        this.y = ny;
        this.lastDir = { dx, dy };
        if (window.soundEngine) window.soundEngine.playTick();
        return null;
      }

      // If moving into EMPTY cell: ONLY allowed if holding Fast or Slow Draw!
      if (nextCell === CELL_EMPTY && wantsDraw) {
        this.state = STATE_DRAWING;
        this.isSlow = isSlowKey;
        this.shieldTimer = 0; // Drawing into the void ends respawn protection
        this.drawOrigin = { x: this.x, y: this.y };
        this.stixPath = [{ x: this.x, y: this.y }];

        // Move to the new cell
        this.x = nx;
        this.y = ny;
        this.lastDir = { dx, dy };
        this.grid.set(nx, ny, CELL_STIX);
        this.stixPath.push({ x: nx, y: ny });

        if (window.soundEngine) {
          window.soundEngine.startDraw(this.isSlow);
        }
        return null;
      }

      return null;
    }

    // ==========================================
    // CASE 2: Currently DRAWING Stix
    // ==========================================
    if (this.state === STATE_DRAWING) {
      // Cannot 180 backtrack into immediate previous position
      if (this.stixPath.length >= 2) {
        const prev = this.stixPath[this.stixPath.length - 2];
        if (nx === prev.x && ny === prev.y) {
          return null;
        }
      }

      // Cannot cross own active Stix (self-intersection)
      if (nextCell === CELL_STIX) {
        return null;
      }

      // Reaching another BORDER cell: STIX COMPLETED!
      if (nextCell === CELL_BORDER) {
        this.x = nx;
        this.y = ny;
        this.stixPath.push({ x: nx, y: ny });
        this.stopSounds();

        // Perform capture
        const captureResult = this.grid.completeStix(this.stixPath, this.isSlow, qixList);
        this.state = STATE_BORDER;
        this.stixPath = [];
        this.drawOrigin = null;
        this.fuseActive = false;

        return { captured: true, captureResult };
      }

      // Moving into another EMPTY cell
      if (nextCell === CELL_EMPTY) {
        this.x = nx;
        this.y = ny;
        this.lastDir = { dx, dy };
        this.grid.set(nx, ny, CELL_STIX);
        this.stixPath.push({ x: nx, y: ny });
        return null;
      }

      return null;
    }

    return null;
  }

  render(ctx, scaleX = 1, scaleY = 1) {
    ctx.save();

    // 1. Render active Stix line if drawing
    if (this.state === STATE_DRAWING && this.stixPath.length > 0) {
      const stixColor = this.isSlow ? '#ff4422' : '#00e5ff';
      const glowColor = this.isSlow ? '#ff2200' : '#00aaff';

      ctx.strokeStyle = stixColor;
      ctx.shadowColor = glowColor;
      ctx.shadowBlur = 8;
      ctx.lineWidth = 2.0;

      ctx.beginPath();
      ctx.moveTo(this.stixPath[0].x * scaleX, this.stixPath[0].y * scaleY);
      for (let i = 1; i < this.stixPath.length; i++) {
        ctx.lineTo(this.stixPath[i].x * scaleX, this.stixPath[i].y * scaleY);
      }
      ctx.stroke();

      // 2. Render Fuse spark crawling along Stix if active, or warning spark if imminent
      if (this.fuseActive) {
        const fi = Math.min(Math.floor(this.fuseIndex), this.stixPath.length - 1);
        const fusePt = this.stixPath[fi];

        if (fusePt) {
          const fx = fusePt.x * scaleX;
          const fy = fusePt.y * scaleY;

          // Sizzling lethal spark particles
          ctx.strokeStyle = '#ffffff';
          ctx.fillStyle = '#ff2200';
          ctx.shadowColor = '#ff5500';
          ctx.shadowBlur = 16;

          ctx.beginPath();
          ctx.arc(fx, fy, 4.5, 0, Math.PI * 2);
          ctx.fill();

          // Crackle spikes
          for (let s = 0; s < 5; s++) {
            const angle = Math.random() * Math.PI * 2;
            const len = 4 + Math.random() * 8;
            ctx.beginPath();
            ctx.moveTo(fx, fy);
            ctx.lineTo(fx + Math.cos(angle) * len, fy + Math.sin(angle) * len);
            ctx.stroke();
          }
        }
      } else if (this.fuseWarning && this.stixPath.length > 0) {
        // Warning spark at origin: pulsing warning amber/yellow
        const origin = this.stixPath[0];
        const ox = origin.x * scaleX;
        const oy = origin.y * scaleY;

        ctx.strokeStyle = '#ffea00';
        ctx.fillStyle = '#ffaa00';
        ctx.shadowColor = '#ffea00';
        ctx.shadowBlur = 10;

        ctx.beginPath();
        ctx.arc(ox, oy, 3, 0, Math.PI * 2);
        ctx.fill();

        for (let s = 0; s < 3; s++) {
          const angle = Math.random() * Math.PI * 2;
          const len = 3 + Math.random() * 4;
          ctx.beginPath();
          ctx.moveTo(ox, oy);
          ctx.lineTo(ox + Math.cos(angle) * len, oy + Math.sin(angle) * len);
          ctx.stroke();
        }
      }
    }

    // 3. Render high-visibility diamond marker
    const px = this.x * scaleX;
    const py = this.y * scaleY;
    const dSize = 11.0; // Significantly enlarged for clear visibility on all displays

    ctx.translate(px, py);

    // High-contrast dark backdrop disc so player never blends into bright artwork or borders
    ctx.fillStyle = 'rgba(3, 6, 12, 0.92)';
    ctx.beginPath();
    ctx.arc(0, 0, dSize * 1.35, 0, Math.PI * 2);
    ctx.fill();

    let markerColor = '#00f0ff';
    let glowColor = '#00f0ff';
    let coreColor = '#ffffff';

    if (this.state === STATE_DRAWING) {
      markerColor = this.isSlow ? '#ff4400' : '#00ffff';
      glowColor = this.isSlow ? '#ff2200' : '#0088ff';
    } else {
      // Border state: bright electric cyan / green
      markerColor = '#00ffcc';
      glowColor = '#00ff88';
    }

    // Outer neon glow diamond
    ctx.strokeStyle = markerColor;
    ctx.fillStyle = markerColor;
    ctx.shadowColor = glowColor;
    ctx.shadowBlur = 14;
    ctx.lineWidth = 2.8;

    ctx.beginPath();
    ctx.moveTo(0, -dSize);
    ctx.lineTo(dSize, 0);
    ctx.lineTo(0, dSize);
    ctx.lineTo(-dSize, 0);
    ctx.closePath();
    ctx.stroke();

    // Inner bright diamond accent for crisp visibility
    ctx.strokeStyle = '#ffffff';
    ctx.shadowBlur = 4;
    ctx.lineWidth = 1.4;
    const innerSize = dSize * 0.55;
    ctx.beginPath();
    ctx.moveTo(0, -innerSize);
    ctx.lineTo(innerSize, 0);
    ctx.lineTo(0, innerSize);
    ctx.lineTo(-innerSize, 0);
    ctx.closePath();
    ctx.stroke();

    // Center pulsating beacon core
    const pulseR = 3.2 + Math.sin(Date.now() * 0.008) * 0.8;
    ctx.fillStyle = coreColor;
    ctx.shadowColor = '#ffffff';
    ctx.shadowBlur = 10;
    ctx.beginPath();
    ctx.arc(0, 0, pulseR, 0, Math.PI * 2);
    ctx.fill();

    // 4. Render Invulnerability Respawn Shield
    if (this.isShielded()) {
      const shieldTime = Date.now() * 0.006;
      const shieldPulse = Math.sin(shieldTime * 3);
      const shieldRadius = dSize * 1.9 + shieldPulse * 2.0;

      // Rotating hexagonal shield barrier
      ctx.save();
      ctx.rotate(shieldTime * 0.8);
      ctx.strokeStyle = '#00f0ff';
      ctx.fillStyle = 'rgba(0, 240, 255, 0.12)';
      ctx.shadowColor = '#00f0ff';
      ctx.shadowBlur = 16;
      ctx.lineWidth = 2.2;

      ctx.beginPath();
      for (let i = 0; i < 6; i++) {
        const a = (i * Math.PI) / 3;
        const sx = Math.cos(a) * shieldRadius;
        const sy = Math.sin(a) * shieldRadius;
        if (i === 0) ctx.moveTo(sx, sy);
        else ctx.lineTo(sx, sy);
      }
      ctx.closePath();
      ctx.stroke();
      ctx.fill();

      // Outer sparkle nodes
      for (let i = 0; i < 6; i++) {
        const a = (i * Math.PI) / 3;
        ctx.fillStyle = '#ffffff';
        ctx.beginPath();
        ctx.arc(Math.cos(a) * shieldRadius, Math.sin(a) * shieldRadius, 2.0, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();

      // Small floating shield tag
      ctx.save();
      ctx.font = 'bold 7px "Press Start 2P", monospace, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = '#00ffff';
      ctx.shadowColor = '#00f0ff';
      ctx.shadowBlur = 8;
      ctx.fillText('SHIELD', 0, -shieldRadius - 5);
      ctx.restore();
    }

    ctx.restore();
  }
}

window.Player = Player;
window.STATE_BORDER = STATE_BORDER;
window.STATE_DRAWING = STATE_DRAWING;
window.STATE_DEAD = STATE_DEAD;
