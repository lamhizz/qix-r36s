/**
 * Qix Progression, Achievements & Settings Engine
 * Handles difficulty tuning, achievements unlock tracking, themes, and persistence.
 */

const DIFFICULTY_CONFIGS = {
  beginner: {
    id: 'beginner',
    name: 'BEGINNER',
    badge: 'CASUAL',
    initialLives: 4,
    targetPercents: [55, 60, 65, 70, 75],
    qixSpeed: 0.82,
    fuseWarningDelay: 1.5,
    fuseDelay: 2.2,
    fuseBurnSpeed: 45,
    shieldDuration: 3.5,
    sparxL1Timer: 60,
    description: 'Forgiving fuse timing, slower enemies, and generous 55% start goal.'
  },
  normal: {
    id: 'normal',
    name: 'ARCADE',
    badge: '1981 AUTHENTIC',
    initialLives: 3,
    targetPercents: [65, 70, 75, 78, 80],
    qixSpeed: 1.0,
    fuseWarningDelay: 0.6,
    fuseDelay: 1.1,
    fuseBurnSpeed: 70,
    shieldDuration: 2.5,
    sparxL1Timer: 50,
    description: 'The authentic Taito 1981 arcade challenge curve.'
  },
  master: {
    id: 'master',
    name: 'MASTER',
    badge: 'HARDCORE',
    initialLives: 2,
    targetPercents: [70, 75, 80, 82, 85],
    qixSpeed: 1.25,
    fuseWarningDelay: 0.35,
    fuseDelay: 0.65,
    fuseBurnSpeed: 95,
    shieldDuration: 1.8,
    sparxL1Timer: 34,
    description: 'Relentless enemies, aggressive fuse, and high claim requirements.'
  }
};

const ACHIEVEMENTS = [
  {
    id: 'FIRST_CONTACT',
    title: 'FIRST CONTACT',
    desc: 'Clear your first round and uncover the hidden art.',
    icon: '🔰',
    secret: false
  },
  {
    id: 'DEEP_CUT',
    title: 'DEEP CUT',
    desc: 'Claim 20%+ playfield in a single daring slow-draw cut.',
    icon: '⚡',
    secret: false
  },
  {
    id: 'DUAL_SPLITTER',
    title: 'DIVIDE & CONQUER',
    desc: 'Trap and split the dual Qix into separate chambers on Level 3+.',
    icon: '⚔️',
    secret: false
  },
  {
    id: 'CENTURY_CLUB',
    title: 'CENTURY CLUB',
    desc: 'Score 100,000 or more points in a single session.',
    icon: '💯',
    secret: false
  },
  {
    id: 'PERFECTIONIST',
    title: 'MASTER ARTIST',
    desc: 'Claim 90% or more of the screen in any single round.',
    icon: '👑',
    secret: false
  },
  {
    id: 'SURVIVOR',
    title: 'VETERAN ARCADE',
    desc: 'Survive and reach Level 5.',
    icon: '🛡️',
    secret: false
  },
  {
    id: 'GALLERY_MASTER',
    title: 'ART CONNOISSEUR',
    desc: 'Successfully unveil 5 different background artworks.',
    icon: '🎨',
    secret: false
  }
];

class ProgressionManager {
  constructor() {
    this.difficulty = this.loadDifficulty();
    this.theme = this.loadTheme();
    this.unlockedAchievements = this.loadAchievements();
    this.unveiledImages = this.loadUnveiledImages();
    this.applyTheme(this.theme);
  }

  loadDifficulty() {
    const saved = localStorage.getItem('qix_difficulty');
    return DIFFICULTY_CONFIGS[saved] ? saved : 'normal';
  }

  setDifficulty(diffId) {
    if (DIFFICULTY_CONFIGS[diffId]) {
      this.difficulty = diffId;
      localStorage.setItem('qix_difficulty', diffId);
      this.syncDifficultyUI();
    }
  }

  getDifficultyConfig() {
    return DIFFICULTY_CONFIGS[this.difficulty] || DIFFICULTY_CONFIGS.normal;
  }

  loadTheme() {
    return localStorage.getItem('qix_theme') || 'classic';
  }

  setTheme(themeId) {
    this.theme = themeId;
    localStorage.setItem('qix_theme', themeId);
    this.applyTheme(themeId);
    this.syncThemeUI();
  }

  applyTheme(themeId) {
    document.body.classList.remove('theme-amber', 'theme-matrix');
    if (themeId === 'amber') {
      document.body.classList.add('theme-amber');
    } else if (themeId === 'matrix') {
      document.body.classList.add('theme-matrix');
    }
  }

  loadAchievements() {
    try {
      const saved = localStorage.getItem('qix_achievements');
      return saved ? JSON.parse(saved) : {};
    } catch (e) {
      return {};
    }
  }

  saveAchievements() {
    try {
      localStorage.setItem('qix_achievements', JSON.stringify(this.unlockedAchievements));
    } catch (e) {}
  }

  loadUnveiledImages() {
    try {
      const saved = localStorage.getItem('qix_unveiled_images');
      return saved ? JSON.parse(saved) : [];
    } catch (e) {
      return [];
    }
  }

  recordUnveiledImage(imageName) {
    if (!imageName) return;
    if (!this.unveiledImages.includes(imageName)) {
      this.unveiledImages.push(imageName);
      try {
        localStorage.setItem('qix_unveiled_images', JSON.stringify(this.unveiledImages));
      } catch (e) {}

      if (this.unveiledImages.length >= 5) {
        this.unlockAchievement('GALLERY_MASTER');
      }
    }
  }

  isUnlocked(id) {
    return !!this.unlockedAchievements[id];
  }

  unlockAchievement(id) {
    if (this.isUnlocked(id)) return;

    const ach = ACHIEVEMENTS.find(a => a.id === id);
    if (!ach) return;

    this.unlockedAchievements[id] = {
      unlockedAt: new Date().toISOString()
    };
    this.saveAchievements();

    // Trigger celebratory sound & toast
    if (window.soundEngine) {
      window.soundEngine.playAchievement();
    }
    this.showAchievementToast(ach);
  }

  showAchievementToast(ach) {
    const toast = document.getElementById('achievement-toast');
    if (!toast) return;

    const iconEl = document.getElementById('ach-toast-icon');
    const titleEl = document.getElementById('ach-toast-title');
    const descEl = document.getElementById('ach-toast-desc');

    if (iconEl) iconEl.textContent = ach.icon;
    if (titleEl) titleEl.textContent = ach.title;
    if (descEl) descEl.textContent = ach.desc;

    toast.classList.remove('hidden');
    toast.classList.add('animate-in');

    clearTimeout(this.toastTimeout);
    this.toastTimeout = setTimeout(() => {
      toast.classList.remove('animate-in');
      toast.classList.add('hidden');
    }, 4200);
  }

  renderAchievementsModal() {
    const listEl = document.getElementById('achievements-list');
    if (!listEl) return;

    listEl.innerHTML = '';
    const total = ACHIEVEMENTS.length;
    let unlockedCount = 0;

    ACHIEVEMENTS.forEach(ach => {
      const unlocked = this.isUnlocked(ach.id);
      if (unlocked) unlockedCount++;

      const card = document.createElement('div');
      card.className = `achievement-item ${unlocked ? 'unlocked' : 'locked'}`;

      const dateStr = unlocked
        ? new Date(this.unlockedAchievements[ach.id].unlockedAt).toLocaleDateString()
        : 'LOCKED';

      card.innerHTML = `
        <div class="ach-icon-box">${ach.icon}</div>
        <div class="ach-details">
          <div class="ach-header-line">
            <span class="ach-title">${ach.title}</span>
            <span class="ach-status-badge">${unlocked ? 'UNLOCKED' : 'LOCKED'}</span>
          </div>
          <p class="ach-description">${ach.desc}</p>
          <span class="ach-date">${unlocked ? `Unlocked: ${dateStr}` : 'Complete objective to unlock'}</span>
        </div>
      `;
      listEl.appendChild(card);
    });

    const progressEl = document.getElementById('achievements-progress-count');
    if (progressEl) {
      progressEl.textContent = `${unlockedCount} / ${total}`;
    }

    const progressFill = document.getElementById('achievements-progress-bar');
    if (progressFill) {
      progressFill.style.width = `${(unlockedCount / total) * 100}%`;
    }
  }

  syncDifficultyUI() {
    const diffBtns = document.querySelectorAll('.diff-select-btn');
    diffBtns.forEach(btn => {
      const d = btn.getAttribute('data-diff');
      btn.classList.toggle('active', d === this.difficulty);
    });

    const label = document.getElementById('current-diff-label');
    if (label) {
      const cfg = this.getDifficultyConfig();
      label.textContent = cfg.name;
    }
  }

  syncThemeUI() {
    const themeBtns = document.querySelectorAll('.theme-select-btn');
    themeBtns.forEach(btn => {
      const t = btn.getAttribute('data-theme');
      btn.classList.toggle('active', t === this.theme);
    });
  }
}

window.ProgressionManager = new ProgressionManager();
