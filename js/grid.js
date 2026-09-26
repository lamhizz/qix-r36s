/**
 * Qix Playfield Grid & Capture Engine
 * Manages the discrete playfield grid, flood-fill BFS, and area capture calculation.
 */

const CELL_EMPTY = 0;
const CELL_BORDER = 1;
const CELL_CLAIMED_SLOW = 2; // Red / orange (double points)
const CELL_CLAIMED_FAST = 3; // Cyan / blue (single points)
const CELL_STIX = 4;

class GameGrid {
  constructor(width = 480, height = 300) {
    this.width = width;
    this.height = height;
    this.size = width * height;
    this.cells = new Uint8Array(this.size);
    this.totalInnerCells = (width - 2) * (height - 2);
    this.claimedCount = 0;
    this.init();
  }

  getAspectRatio() {
    return this.width / this.height;
  }

  init() {
    this.cells.fill(CELL_EMPTY);
    this.claimedCount = 0;

    // Build initial perimeter borders
    for (let x = 0; x < this.width; x++) {
      this.cells[x] = CELL_BORDER; // Top edge (y = 0)
      this.cells[(this.height - 1) * this.width + x] = CELL_BORDER; // Bottom edge
    }
    for (let y = 0; y < this.height; y++) {
      this.cells[y * this.width] = CELL_BORDER; // Left edge
      this.cells[y * this.width + (this.width - 1)] = CELL_BORDER; // Right edge
    }
  }

  index(x, y) {
    return y * this.width + x;
  }

  inBounds(x, y) {
    return x >= 0 && x < this.width && y >= 0 && y < this.height;
  }

  get(x, y) {
    if (!this.inBounds(x, y)) return CELL_BORDER;
    return this.cells[y * this.width + x];
  }

  set(x, y, val) {
    if (this.inBounds(x, y)) {
      this.cells[y * this.width + x] = val;
    }
  }

  isBorder(x, y) {
    if (!this.inBounds(x, y)) return false;
    return this.cells[y * this.width + x] === CELL_BORDER;
  }

  isClaimed(x, y) {
    if (!this.inBounds(x, y)) return false;
    const c = this.cells[y * this.width + x];
    return c === CELL_CLAIMED_SLOW || c === CELL_CLAIMED_FAST;
  }

  isEmpty(x, y) {
    if (!this.inBounds(x, y)) return false;
    return this.cells[y * this.width + x] === CELL_EMPTY;
  }

  // Active border: has at least one neighboring EMPTY cell, or is outer edge
  isActiveBorder(x, y) {
    if (!this.isBorder(x, y)) return false;
    if (x === 0 || x === this.width - 1 || y === 0 || y === this.height - 1) return true;

    const dirs = [
      [0, 1], [0, -1], [1, 0], [-1, 0],
      [1, 1], [-1, -1], [1, -1], [-1, 1]
    ];
    for (const [dx, dy] of dirs) {
      const nx = x + dx;
      const ny = y + dy;
      if (this.inBounds(nx, ny) && this.cells[ny * this.width + nx] === CELL_EMPTY) {
        return true;
      }
    }
    return false;
  }

  getClaimedPercent() {
    return Math.floor((this.claimedCount / this.totalInnerCells) * 100);
  }

  // Find nearest empty cell around coordinates
  findNearestEmpty(targetX, targetY) {
    const startX = Math.max(1, Math.min(this.width - 2, Math.round(targetX)));
    const startY = Math.max(1, Math.min(this.height - 2, Math.round(targetY)));

    if (this.isEmpty(startX, startY)) {
      return { x: startX, y: startY };
    }

    // Spiral outward up to radius 15
    for (let r = 1; r <= 15; r++) {
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          if (Math.abs(dx) !== r && Math.abs(dy) !== r) continue;
          const nx = startX + dx;
          const ny = startY + dy;
          if (this.isEmpty(nx, ny)) {
            return { x: nx, y: ny };
          }
        }
      }
    }
    return null;
  }

  /**
   * Complete the Stix and capture enclosed areas.
   * Checks for Qix containment and Level 3+ dual Qix split.
   */
  completeStix(stixPath, isSlow, qixList) {
    // 1. Commit all Stix cells as BORDER
    for (let i = 0; i < stixPath.length; i++) {
      const pt = stixPath[i];
      this.cells[pt.y * this.width + pt.x] = CELL_BORDER;
    }

    const claimType = isSlow ? CELL_CLAIMED_SLOW : CELL_CLAIMED_FAST;

    // 2. Check for dual Qix split if 2 Qixes exist
    if (qixList && qixList.length >= 2) {
      const qix1Pos = this.findNearestEmpty(qixList[0].p1.x, qixList[0].p1.y);
      const qix2Pos = this.findNearestEmpty(qixList[1].p1.x, qixList[1].p1.y);

      if (qix1Pos && qix2Pos) {
        // Flood fill from Qix 1
        const visited1 = new Uint8Array(this.size);
        const queue = [qix1Pos.y * this.width + qix1Pos.x];
        visited1[queue[0]] = 1;

        let head = 0;
        const w = this.width;
        const h = this.height;

        while (head < queue.length) {
          const idx = queue[head++];
          const cy = Math.floor(idx / w);
          const cx = idx % w;

          const neighbors = [
            cx + 1 < w ? idx + 1 : -1,
            cx - 1 >= 0 ? idx - 1 : -1,
            cy + 1 < h ? idx + w : -1,
            cy - 1 >= 0 ? idx - w : -1
          ];

          for (let i = 0; i < 4; i++) {
            const nIdx = neighbors[i];
            if (nIdx !== -1 && !visited1[nIdx] && this.cells[nIdx] === CELL_EMPTY) {
              visited1[nIdx] = 1;
              queue.push(nIdx);
            }
          }
        }

        const qix2Idx = qix2Pos.y * w + qix2Pos.x;
        if (!visited1[qix2Idx]) {
          // Qix 1 and Qix 2 are separated in distinct compartments!
          return {
            isSplit: true,
            capturedCells: 0,
            percent: this.getClaimedPercent(),
            isSlow
          };
        }
      }
    }

    // 3. Normal capture: Flood-fill from all Qixes to mark reachable EMPTY cells
    const visited = new Uint8Array(this.size);
    const queue = [];
    const w = this.width;
    const h = this.height;

    for (const qix of qixList) {
      const pos = this.findNearestEmpty(qix.p1.x, qix.p1.y);
      if (pos) {
        const startIdx = pos.y * w + pos.x;
        if (!visited[startIdx]) {
          visited[startIdx] = 1;
          queue.push(startIdx);
        }
      }
    }

    let head = 0;
    while (head < queue.length) {
      const idx = queue[head++];
      const cy = Math.floor(idx / w);
      const cx = idx % w;

      const neighbors = [
        cx + 1 < w ? idx + 1 : -1,
        cx - 1 >= 0 ? idx - 1 : -1,
        cy + 1 < h ? idx + w : -1,
        cy - 1 >= 0 ? idx - w : -1
      ];

      for (let i = 0; i < 4; i++) {
        const nIdx = neighbors[i];
        if (nIdx !== -1 && !visited[nIdx] && this.cells[nIdx] === CELL_EMPTY) {
          visited[nIdx] = 1;
          queue.push(nIdx);
        }
      }
    }

    // 4. Any EMPTY cell not visited by Qix flood-fill is captured!
    let newlyCaptured = 0;
    for (let y = 1; y < h - 1; y++) {
      const rowOffset = y * w;
      for (let x = 1; x < w - 1; x++) {
        const idx = rowOffset + x;
        if (this.cells[idx] === CELL_EMPTY && !visited[idx]) {
          this.cells[idx] = claimType;
          newlyCaptured++;
        }
      }
    }

    this.claimedCount += newlyCaptured;
    const percent = this.getClaimedPercent();

    return {
      isSplit: false,
      capturedCells: newlyCaptured,
      percent,
      isSlow
    };
  }

  // Clear uncompleted Stix cells upon death
  clearStix(stixPath) {
    for (let i = 0; i < stixPath.length; i++) {
      const pt = stixPath[i];
      if (this.cells[pt.y * this.width + pt.x] === CELL_STIX) {
        this.cells[pt.y * this.width + pt.x] = CELL_EMPTY;
      }
    }
  }
}

window.GameGrid = GameGrid;
window.CELL_EMPTY = CELL_EMPTY;
window.CELL_BORDER = CELL_BORDER;
window.CELL_CLAIMED_SLOW = CELL_CLAIMED_SLOW;
window.CELL_CLAIMED_FAST = CELL_CLAIMED_FAST;
window.CELL_STIX = CELL_STIX;
