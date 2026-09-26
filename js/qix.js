/**
 * Qix Entity & Chaotic Vector Physics
 * Recreates the multi-segment vector line behavior, ribbon trail, and collision detection.
 */

// Helper for line segment intersection
function lineSegmentsIntersect(p1, p2, p3, p4) {
  function ccw(A, B, C) {
    return (C.y - A.y) * (B.x - A.x) > (B.y - A.y) * (C.x - A.x);
  }
  return (ccw(p1, p3, p4) !== ccw(p2, p3, p4)) && (ccw(p1, p2, p3) !== ccw(p1, p2, p4));
}

// Distance from point to line segment
function distToSegment(p, v, w) {
  function dist2(a, b) { return (a.x - b.x) ** 2 + (a.y - b.y) ** 2; }
  const l2 = dist2(v, w);
  if (l2 === 0) return Math.sqrt(dist2(p, v));
  let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.sqrt(dist2(p, { x: v.x + t * (w.x - v.x), y: v.y + t * (w.y - v.y) }));
}

class Qix {
  constructor(grid, startX, startY, speedMultiplier = 1.0) {
    this.grid = grid;
    this.speedMultiplier = speedMultiplier;

    // Initial endpoints
    const len = 25;
    this.p1 = { x: startX || grid.width / 2, y: startY || grid.height / 2 };
    this.p2 = { x: this.p1.x + len, y: this.p1.y };

    const speed = 1.8 * this.speedMultiplier;
    const angle1 = Math.random() * Math.PI * 2;
    const angle2 = Math.random() * Math.PI * 2;
    this.v1 = { x: Math.cos(angle1) * speed, y: Math.sin(angle1) * speed };
    this.v2 = { x: Math.cos(angle2) * speed, y: Math.sin(angle2) * speed };

    this.minLen = 22;
    this.maxLen = 65;

    // Ribbon trail history (array of segment pairs)
    this.trailLength = 24;
    this.trail = [];

    this.tumbleTimer = 0;
    this.baseHue = Math.random() * 360;
  }

  getCenter() {
    return {
      x: (this.p1.x + this.p2.x) / 2,
      y: (this.p1.y + this.p2.y) / 2
    };
  }

  // Check if coordinates collide with grid border or claimed area
  isBlocked(x, y) {
    const gx = Math.round(x);
    const gy = Math.round(y);
    if (!this.grid.inBounds(gx, gy)) return true;
    const cell = this.grid.get(gx, gy);
    return cell === CELL_BORDER || cell === CELL_CLAIMED_SLOW || cell === CELL_CLAIMED_FAST;
  }

  update() {
    // 1. Random graceful perturbation / steering
    this.tumbleTimer++;
    if (this.tumbleTimer > 15) {
      this.tumbleTimer = 0;
      const dAngle1 = (Math.random() - 0.5) * 0.7;
      const dAngle2 = (Math.random() - 0.5) * 0.7;

      const spd1 = Math.hypot(this.v1.x, this.v1.y);
      const spd2 = Math.hypot(this.v2.x, this.v2.y);

      const a1 = Math.atan2(this.v1.y, this.v1.x) + dAngle1;
      const a2 = Math.atan2(this.v2.y, this.v2.x) + dAngle2;

      this.v1.x = Math.cos(a1) * spd1;
      this.v1.y = Math.sin(a1) * spd1;
      this.v2.x = Math.cos(a2) * spd2;
      this.v2.y = Math.sin(a2) * spd2;
    }

    // 2. Predict next positions
    const next1 = { x: this.p1.x + this.v1.x, y: this.p1.y + this.v1.y };
    const next2 = { x: this.p2.x + this.v2.x, y: this.p2.y + this.v2.y };

    // Check collision with border/claimed cells for p1
    if (this.isBlocked(next1.x, next1.y) || this.isBlocked(next1.x, this.p1.y)) {
      this.v1.x = -this.v1.x + (Math.random() - 0.5) * 0.4;
    }
    if (this.isBlocked(next1.x, next1.y) || this.isBlocked(this.p1.x, next1.y)) {
      this.v1.y = -this.v1.y + (Math.random() - 0.5) * 0.4;
    }

    // Check collision for p2
    if (this.isBlocked(next2.x, next2.y) || this.isBlocked(next2.x, this.p2.y)) {
      this.v2.x = -this.v2.x + (Math.random() - 0.5) * 0.4;
    }
    if (this.isBlocked(next2.x, next2.y) || this.isBlocked(this.p2.x, next2.y)) {
      this.v2.y = -this.v2.y + (Math.random() - 0.5) * 0.4;
    }

    // Clamp speed
    const maxSpd = 2.8 * this.speedMultiplier;
    const minSpd = 1.1 * this.speedMultiplier;
    const curSpd1 = Math.hypot(this.v1.x, this.v1.y);
    const curSpd2 = Math.hypot(this.v2.x, this.v2.y);

    if (curSpd1 > maxSpd) { this.v1.x = (this.v1.x / curSpd1) * maxSpd; this.v1.y = (this.v1.y / curSpd1) * maxSpd; }
    if (curSpd1 < minSpd) { this.v1.x = (this.v1.x / curSpd1) * minSpd; this.v1.y = (this.v1.y / curSpd1) * minSpd; }
    if (curSpd2 > maxSpd) { this.v2.x = (this.v2.x / curSpd2) * maxSpd; this.v2.y = (this.v2.y / curSpd2) * maxSpd; }
    if (curSpd2 < minSpd) { this.v2.x = (this.v2.x / curSpd2) * minSpd; this.v2.y = (this.v2.y / curSpd2) * minSpd; }

    // Apply movement if not permanently blocked
    if (!this.isBlocked(this.p1.x + this.v1.x, this.p1.y + this.v1.y)) {
      this.p1.x += this.v1.x;
      this.p1.y += this.v1.y;
    }
    if (!this.isBlocked(this.p2.x + this.v2.x, this.p2.y + this.v2.y)) {
      this.p2.x += this.v2.x;
      this.p2.y += this.v2.y;
    }

    // 3. Maintain segment length within bounds
    const dx = this.p2.x - this.p1.x;
    const dy = this.p2.y - this.p1.y;
    const dist = Math.hypot(dx, dy);

    if (dist > this.maxLen) {
      const diff = (dist - this.maxLen) / 2;
      const nx = dx / dist;
      const ny = dy / dist;
      this.p1.x += nx * diff;
      this.p1.y += ny * diff;
      this.p2.x -= nx * diff;
      this.p2.y -= ny * diff;
    } else if (dist < this.minLen && dist > 0.001) {
      const diff = (this.minLen - dist) / 2;
      const nx = dx / dist;
      const ny = dy / dist;
      this.p1.x -= nx * diff;
      this.p1.y -= ny * diff;
      this.p2.x += nx * diff;
      this.p2.y += ny * diff;
    }

    // 4. Update ribbon trail
    this.trail.push({
      p1: { x: this.p1.x, y: this.p1.y },
      p2: { x: this.p2.x, y: this.p2.y }
    });

    if (this.trail.length > this.trailLength) {
      this.trail.shift();
    }

    this.baseHue = (this.baseHue + 2.5) % 360;
  }

  // Check collision with player marker or active Stix
  checkCollision(player) {
    if (!player.isDrawing()) return false;

    // Check collision with player marker itself
    const playerPos = { x: player.x, y: player.y };
    if (distToSegment(playerPos, this.p1, this.p2) < 3.0) {
      return true;
    }

    // Check recent ribbon trails and current lead segment against active Stix line
    const stix = player.stixPath;
    if (!stix || stix.length < 2) return false;

    // We check lead segment and the top 10 most recent ribbon lines
    const checkSegments = [{ p1: this.p1, p2: this.p2 }];
    const recentCount = Math.min(10, this.trail.length);
    for (let i = this.trail.length - 1; i >= this.trail.length - recentCount; i--) {
      checkSegments.push(this.trail[i]);
    }

    // Subsample Stix segments for efficiency
    const step = 2;
    for (let i = 0; i < stix.length - 1; i += step) {
      const sp1 = stix[i];
      const sp2 = stix[Math.min(stix.length - 1, i + step)];

      for (const qSeg of checkSegments) {
        if (lineSegmentsIntersect(sp1, sp2, qSeg.p1, qSeg.p2)) {
          return true;
        }
      }
    }

    return false;
  }

  render(ctx, scaleX = 1, scaleY = 1) {
    ctx.save();
    ctx.lineCap = 'round';

    // Draw historical trails with fading rainbow neon lines
    for (let i = 0; i < this.trail.length; i++) {
      const seg = this.trail[i];
      const alpha = (i + 1) / this.trail.length;
      const hue = (this.baseHue + i * 8) % 360;

      ctx.strokeStyle = `hsla(${hue}, 100%, 65%, ${alpha * 0.9})`;
      ctx.lineWidth = 1.8;
      ctx.shadowColor = `hsl(${hue}, 100%, 60%)`;
      ctx.shadowBlur = i === this.trail.length - 1 ? 10 : 3;

      ctx.beginPath();
      ctx.moveTo(seg.p1.x * scaleX, seg.p1.y * scaleY);
      ctx.lineTo(seg.p2.x * scaleX, seg.p2.y * scaleY);
      ctx.stroke();
    }

    // Draw leading main segment with bright white core
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2.2;
    ctx.shadowColor = `hsl(${this.baseHue}, 100%, 75%)`;
    ctx.shadowBlur = 12;

    ctx.beginPath();
    ctx.moveTo(this.p1.x * scaleX, this.p1.y * scaleY);
    ctx.lineTo(this.p2.x * scaleX, this.p2.y * scaleY);
    ctx.stroke();

    ctx.restore();
  }
}

window.Qix = Qix;
