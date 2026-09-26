/**
 * Qix Main Game Controller & State Machine
 * Handles game loop, levels, scoring, offscreen grid rendering, and input orchestration.
 */

const GAME_WIDTH = 480;
const GAME_HEIGHT = 339;
const HUD_HEIGHT = 28;
const CLAIM_THRESHOLD = 75; // 75% required to clear level

/**
 * Detect image alignment preference from filename prefix.
 * Default: center positioning.
 * 'left' (e.g. left-images-13.jpg) -> align left side
 * 'right' -> align right side
 * 'top' -> align top side
 * 'bottom' -> align bottom side
 */
function getImageAlignment(img, imageName) {
  let name = imageName || (img && img._imageName) || '';
  if (!name && img && img.src) {
    try {
      const urlParts = img.src.split('/');
      name = decodeURIComponent(urlParts[urlParts.length - 1]);
    } catch (e) {
      name = '';
    }
  }

  name = name.toLowerCase().trim();

  let alignX = 'center';
  let alignY = 'center';

  // Support composite prefixes (e.g. top-left-..., bottom-right-...)
  if (/^(top[-_]left|left[-_]top)/i.test(name)) {
    alignX = 'left';
    alignY = 'top';
  } else if (/^(top[-_]right|right[-_]top)/i.test(name)) {
    alignX = 'right';
    alignY = 'top';
  } else if (/^(bottom[-_]left|left[-_]bottom)/i.test(name)) {
    alignX = 'left';
    alignY = 'bottom';
  } else if (/^(bottom[-_]right|right[-_]bottom)/i.test(name)) {
    alignX = 'right';
    alignY = 'bottom';
  } else if (/^left(\b|[-_0-9])/i.test(name) || name.startsWith('left')) {
    alignX = 'left';
  } else if (/^right(\b|[-_0-9])/i.test(name) || name.startsWith('right')) {
    alignX = 'right';
  } else if (/^top(\b|[-_0-9])/i.test(name) || name.startsWith('top')) {
    alignY = 'top';
  } else if (/^bottom(\b|[-_0-9])/i.test(name) || name.startsWith('bottom')) {
    alignY = 'bottom';
  }

  return { alignX, alignY };
}

/**
 * Draw image with object-fit: cover behavior to fill target dimensions without stretching,
 * respecting positional alignment encoded in the filename ('left', 'right', 'top', 'bottom', or 'center').
 */
function drawImageCover(ctx, img, targetW, targetH, alignOptions = null) {
  if (!img || !img.naturalWidth || !img.naturalHeight) return;
  const imgW = img.naturalWidth;
  const imgH = img.naturalHeight;
  const scale = Math.max(targetW / imgW, targetH / imgH);
  const sw = targetW / scale;
  const sh = targetH / scale;

  const align = alignOptions || getImageAlignment(img);

  let sx = (imgW - sw) / 2;
  if (align.alignX === 'left') {
    sx = 0;
  } else if (align.alignX === 'right') {
    sx = Math.max(0, imgW - sw);
  }

  let sy = (imgH - sh) / 2;
  if (align.alignY === 'top') {
    sy = 0;
  } else if (align.alignY === 'bottom') {
    sy = Math.max(0, imgH - sh);
  }

  ctx.drawImage(img, sx, sy, sw, sh, 0, 0, targetW, targetH);
}

/**
 * Draw image with object-fit: contain ("fit to screen") behavior preserving aspect ratio
 */
function drawImageFit(ctx, img, targetW, targetH) {
  if (!img || !img.naturalWidth || !img.naturalHeight) return;
  const imgW = img.naturalWidth;
  const imgH = img.naturalHeight;
  const scale = Math.min(targetW / imgW, targetH / imgH);
  const dw = imgW * scale;
  const dh = imgH * scale;
  const dx = (targetW - dw) / 2;
  const dy = (targetH - dh) / 2;
  ctx.drawImage(img, 0, 0, imgW, imgH, dx, dy, dw, dh);
}

/**
 * Trigger mobile haptic vibration feedback with graceful fallback
 */
function triggerHaptic(pattern) {
  if (typeof navigator !== 'undefined' && navigator.vibrate) {
    try {
      navigator.vibrate(pattern);
    } catch (e) {}
  }
}

class QixGame {
  constructor() {
    this.canvas = document.getElementById('game-canvas');
    this.canvas.width = 640;
    this.canvas.height = 480;
    this.ctx = this.canvas.getContext('2d');

    // Discrete playfield grid
    this.grid = new GameGrid(GAME_WIDTH, GAME_HEIGHT);

    // Maximize 640x480 space below the 28px top HUD (exact 4/3 aspect ratio, square pixels)
    this.scaleX = this.canvas.width / this.grid.width;
    this.scaleY = (this.canvas.height - HUD_HEIGHT) / this.grid.height;
    this.scale = this.scaleX;
    this.offsetX = 0;
    this.offsetY = HUD_HEIGHT;
    this.pauseFocusIndex = 0;

    // Offscreen canvas for fast cached background rendering
    this.bgCanvas = document.createElement('canvas');
    this.bgCanvas.width = this.canvas.width;
    this.bgCanvas.height = this.canvas.height;
    this.bgCtx = this.bgCanvas.getContext('2d');

    // Offscreen canvases for uncovering background image
    this.maskCanvas = document.createElement('canvas');
    this.maskCanvas.width = this.canvas.width;
    this.maskCanvas.height = this.canvas.height;
    this.maskCtx = this.maskCanvas.getContext('2d');

    this.tempCanvas = document.createElement('canvas');
    this.tempCanvas.width = this.canvas.width;
    this.tempCanvas.height = this.canvas.height;
    this.tempCtx = this.tempCanvas.getContext('2d');

    // Background image uncover system - supports JPG, JPEG, PNG
    this.imageList = [
      'cyberpunk_city.jpg',
      'images.jpeg',
      'images2.jpeg',
      'synthwave_space.jpg',
      'retrowave_sunset.png'
    ];
    this.currentBgImage = null;
    this.currentImageName = '';
    this.imageDeck = [];
    this.fullyRevealed = false;

    // Core state
    this.player = new Player(this.grid);
    this.sparxMgr = new SparxManager(this.grid);
    this.qixList = [];

    this.state = 'TITLE'; // TITLE, PLAYING, PAUSED, LEVEL_CLEAR, QIX_SPLIT, GAME_OVER
    this.level = 1;
    this.targetPercent = 65; // Dynamic per level: 65% (L1) -> 70% (L2) -> 75% (L3) -> 78% (L4) -> 80% (L5+)
    this.score = 0;
    this.highScore = parseInt(localStorage.getItem('qix_high_score') || '0', 10);
    this.lives = 3;
    this.multiplier = 1;
    this.claimedPercent = 0;
    this.awardedMilestones = new Set();
    this.floatingScores = []; // Animated +points text objects
    this.nearTargetAnnounced = false;

    // Cached DOM elements for 60fps GC-free updates on RK3326
    this.screenElem = document.getElementById('screen-container');
    this.hudScoreEl = document.getElementById('hud-score');
    this.hudHighScoreEl = document.getElementById('hud-high-score');
    this.hudLevelEl = document.getElementById('hud-level');
    this.hudMultEl = document.getElementById('hud-multiplier');
    this.hudGoalEl = document.getElementById('hud-target-goal');
    this.hudPercentEl = document.getElementById('hud-percent');
    this.percentBarFill = document.getElementById('percent-bar-fill');
    this.sparxBarFill = document.getElementById('sparx-bar-fill');
    this.livesContainer = document.getElementById('hud-lives');

    // Cached last rendered HUD values to avoid redundant DOM writes
    this._lastScore = -1;
    this._lastHighScore = -1;
    this._lastLevel = -1;
    this._lastMultiplier = -1;
    this._lastTarget = -1;
    this._lastPercent = -1;
    this._lastLives = -1;
    this._lastSparxRatio = -1;
    this._lastDanger = false;

    // Transition animations
    this.bannerText = '';
    this.bannerSubtext = '';
    this.bannerTimer = 0;

    // Screen shake on death
    this.shakeDuration = 0;
    this.shakeIntensity = 0;

    // Input state
    this.input = {
      dx: 0,
      dy: 0,
      fastDraw: false,
      slowDraw: false
    };

    this.keysDown = {};
    this.prevGamepadButtons = {};
    this.initialsChars = ['A', 'A', 'A'];
    this.initialsIndex = 0;
    this.lastTime = 0;

    this.initPattern();
    this.initLeaderboard();
    this.setupInputs();
    this.updateHUD();
    this.loadManifest();
    this.loadRandomBackgroundImage(() => {
      this.redrawBackground();
    });

    // Start RAF
    requestAnimationFrame(this.loop.bind(this));
  }

  // Pre-generate retro arcade hatch patterns for claimed areas respecting active theme
  initPattern() {
    const theme = window.ProgressionManager ? window.ProgressionManager.theme : 'classic';

    let fastBg = '#0a2342';
    let fastFg = '#0088ff';
    let slowBg = '#3a0c0c';
    let slowFg = '#ff4422';

    if (theme === 'amber') {
      fastBg = '#261600';
      fastFg = '#ff9900';
      slowBg = '#400c00';
      slowFg = '#ff3300';
    } else if (theme === 'matrix') {
      fastBg = '#031f08';
      fastFg = '#00cc44';
      slowBg = '#142b03';
      slowFg = '#aaff00';
    }

    // Fast draw pattern (horizontal scan stripes)
    const fastPatCanvas = document.createElement('canvas');
    fastPatCanvas.width = 4;
    fastPatCanvas.height = 4;
    const fCtx = fastPatCanvas.getContext('2d');
    fCtx.fillStyle = fastBg;
    fCtx.fillRect(0, 0, 4, 4);
    fCtx.fillStyle = fastFg;
    fCtx.fillRect(0, 0, 4, 2);
    this.fastPattern = this.ctx.createPattern(fastPatCanvas, 'repeat');

    // Slow draw pattern (dense crosshatch)
    const slowPatCanvas = document.createElement('canvas');
    slowPatCanvas.width = 4;
    slowPatCanvas.height = 4;
    const sCtx = slowPatCanvas.getContext('2d');
    sCtx.fillStyle = slowBg;
    sCtx.fillRect(0, 0, 4, 4);
    sCtx.fillStyle = slowFg;
    sCtx.fillRect(0, 0, 2, 2);
    sCtx.fillRect(2, 2, 2, 2);
    this.slowPattern = this.ctx.createPattern(slowPatCanvas, 'repeat');
  }

  setupInputs() {
    window.addEventListener('keydown', (e) => {
      // If locked, block all gameplay keys
      if (window.SecurityManager && !window.SecurityManager.isAuthorized()) {
        return;
      }

      this.keysDown[e.code] = true;

      // Unmute Web Audio on first interaction
      if (window.soundEngine) {
        window.soundEngine.ensureContext();
      }

      if (this.isModalOpen()) {
        if (e.code === 'Escape' || e.code === 'KeyB' || e.code === 'KeyP') {
          this.closeAllModals();
          e.preventDefault();
          return;
        }
      }

      if (e.code === 'KeyP' || e.code === 'Escape') {
        this.togglePause();
        e.preventDefault();
        return;
      }

      if (this.state === 'PAUSED') {
        if (e.code === 'ArrowUp') {
          this.setPauseFocus(this.pauseFocusIndex - 1);
          e.preventDefault();
          return;
        }
        if (e.code === 'ArrowDown') {
          this.setPauseFocus(this.pauseFocusIndex + 1);
          e.preventDefault();
          return;
        }
        if (e.code === 'ArrowLeft') {
          this.handlePauseLeftRight(-1);
          e.preventDefault();
          return;
        }
        if (e.code === 'ArrowRight') {
          this.handlePauseLeftRight(1);
          e.preventDefault();
          return;
        }
        if (e.code === 'Space' || e.code === 'Enter') {
          this.activatePauseFocusedItem();
          e.preventDefault();
          return;
        }
      }

      if (this.state === 'TITLE') {
        if (e.code === 'ArrowLeft') {
          this.cycleTitleDifficulty(-1);
          e.preventDefault();
          return;
        }
        if (e.code === 'ArrowRight') {
          this.cycleTitleDifficulty(1);
          e.preventDefault();
          return;
        }
      }

      if (e.code === 'KeyM') {
        const isMuted = window.soundEngine.toggleMute();
        this.updateAudioButton(isMuted);
        e.preventDefault();
        return;
      }

      if (this.state === 'TITLE' || this.state === 'GAME_OVER') {
        if (e.code === 'Space' || e.code === 'Enter') {
          this.startNewGame();
          e.preventDefault();
          return;
        }
      }
    });

    window.addEventListener('keyup', (e) => {
      this.keysDown[e.code] = false;
    });

    // Touch & on-screen control listeners
    this.setupVirtualControls();
  }

  setupVirtualControls() {
    const bindBtn = (id, onDown, onUp) => {
      const el = document.getElementById(id);
      if (!el) return;
      const start = (e) => {
        e.preventDefault();
        if (window.SecurityManager && !window.SecurityManager.isAuthorized()) return;
        if (window.soundEngine) window.soundEngine.ensureContext();
        el.classList.add('pressed');
        onDown();
        triggerHaptic(15);
      };
      const end = (e) => {
        e.preventDefault();
        el.classList.remove('pressed');
        onUp();
      };
      el.addEventListener('touchstart', start, { passive: false });
      el.addEventListener('touchend', end, { passive: false });
      el.addEventListener('touchcancel', end, { passive: false });
      el.addEventListener('mousedown', start);
      el.addEventListener('mouseup', end);
      el.addEventListener('mouseleave', end);
    };

    // Virtual D-pad
    bindBtn('btn-up', () => { this.keysDown['ArrowUp'] = true; }, () => { this.keysDown['ArrowUp'] = false; });
    bindBtn('btn-down', () => { this.keysDown['ArrowDown'] = true; }, () => { this.keysDown['ArrowDown'] = false; });
    bindBtn('btn-left', () => { this.keysDown['ArrowLeft'] = true; }, () => { this.keysDown['ArrowLeft'] = false; });
    bindBtn('btn-right', () => { this.keysDown['ArrowRight'] = true; }, () => { this.keysDown['ArrowRight'] = false; });

    // Action buttons
    bindBtn('btn-fast', () => { this.keysDown['Space'] = true; }, () => { this.keysDown['Space'] = false; });
    bindBtn('btn-slow', () => { this.keysDown['ShiftLeft'] = true; }, () => { this.keysDown['ShiftLeft'] = false; });

    // Mobile Burger Menu Toggle
    const burgerBtn = document.getElementById('btn-burger');
    const headerActions = document.getElementById('header-actions');
    const menuBackdrop = document.getElementById('menu-backdrop');

    const toggleBurgerMenu = (e) => {
      if (e) e.stopPropagation();
      if (!headerActions || !burgerBtn) return;
      const isOpen = headerActions.classList.toggle('open');
      burgerBtn.classList.toggle('open', isOpen);
      if (menuBackdrop) {
        if (isOpen) menuBackdrop.classList.remove('hidden');
        else menuBackdrop.classList.add('hidden');
      }
    };

    const closeBurgerMenu = () => {
      if (headerActions) headerActions.classList.remove('open');
      if (burgerBtn) burgerBtn.classList.remove('open');
      if (menuBackdrop) menuBackdrop.classList.add('hidden');
    };

    if (burgerBtn) {
      burgerBtn.addEventListener('click', toggleBurgerMenu);
      burgerBtn.addEventListener('touchend', (e) => {
        e.preventDefault();
        toggleBurgerMenu(e);
      });
    }

    if (menuBackdrop) {
      menuBackdrop.addEventListener('click', closeBurgerMenu);
      menuBackdrop.addEventListener('touchend', (e) => {
        e.preventDefault();
        closeBurgerMenu();
      });
    }

    if (headerActions) {
      headerActions.addEventListener('click', (e) => {
        if (e.target.closest('button')) {
          closeBurgerMenu();
        }
      });
    }

    // UI Buttons
    const startBtn = document.getElementById('btn-start-game');
    if (startBtn) {
      const handleStart = (e) => {
        if (e) e.preventDefault();
        if (window.soundEngine) window.soundEngine.ensureContext();
        this.startNewGame();
      };
      startBtn.addEventListener('click', handleStart);
      startBtn.addEventListener('touchend', handleStart);
    }

    const restartBtn = document.getElementById('btn-restart');
    if (restartBtn) {
      const handleRestart = (e) => {
        if (e) e.preventDefault();
        if (window.soundEngine) window.soundEngine.ensureContext();
        this.startNewGame();
      };
      restartBtn.addEventListener('click', handleRestart);
      restartBtn.addEventListener('touchend', handleRestart);
    }

    // Game Over screen tap-to-restart fallback
    const gameOverScreen = document.getElementById('game-over-screen');
    if (gameOverScreen) {
      gameOverScreen.addEventListener('click', (e) => {
        if (e.target.id === 'btn-view-board' || e.target.closest('#btn-view-board')) return;
        if (window.soundEngine) window.soundEngine.ensureContext();
        this.startNewGame();
      });
    }

    const muteBtn = document.getElementById('btn-mute');
    if (muteBtn) {
      muteBtn.addEventListener('click', () => {
        const isMuted = window.soundEngine.toggleMute();
        this.updateAudioButton(isMuted);
      });
    }

    const pauseBtn = document.getElementById('btn-pause');
    if (pauseBtn) {
      pauseBtn.addEventListener('click', () => {
        this.togglePause();
      });
    }

    const lsPauseBtn = document.getElementById('btn-landscape-pause');
    if (lsPauseBtn) {
      lsPauseBtn.addEventListener('click', () => {
        this.togglePause();
      });
    }

    const crtBtn = document.getElementById('btn-crt');
    if (crtBtn) {
      crtBtn.addEventListener('click', () => {
        document.getElementById('screen-container').classList.toggle('crt-active');
        crtBtn.classList.toggle('active');
      });
    }

    // Fullscreen button
    const fsBtn = document.getElementById('btn-fullscreen');
    if (fsBtn) {
      fsBtn.addEventListener('click', () => {
        this.toggleFullscreen();
      });

      const updateFsBtn = () => {
        const isFs = !!(document.fullscreenElement || document.webkitFullscreenElement);
        fsBtn.innerHTML = isFs ? '🗗 EXIT' : '⛶ FULL';
        fsBtn.classList.toggle('active', isFs);
      };

      document.addEventListener('fullscreenchange', updateFsBtn);
      document.addEventListener('webkitfullscreenchange', updateFsBtn);
    }

    const helpBtn = document.getElementById('btn-help');
    const helpModal = document.getElementById('help-modal');
    const closeHelp = document.getElementById('btn-close-help');
    if (helpBtn && helpModal) {
      helpBtn.addEventListener('click', () => {
        helpModal.classList.remove('hidden');
      });
    }
    if (closeHelp && helpModal) {
      closeHelp.addEventListener('click', () => {
        helpModal.classList.add('hidden');
      });
    }

    // Leaderboard buttons
    const lbBtn = document.getElementById('btn-leaderboard');
    const lbModal = document.getElementById('leaderboard-modal');
    const lbClose = document.getElementById('btn-close-leaderboard');
    const lbOk = document.getElementById('btn-leaderboard-ok');
    const lbView = document.getElementById('btn-view-board');
    const lbPlayAgain = document.getElementById('btn-leaderboard-play');

    const openLeaderboard = () => {
      this.renderLeaderboard();
      if (lbModal) lbModal.classList.remove('hidden');
    };
    const closeLeaderboard = () => {
      if (lbModal) lbModal.classList.add('hidden');
      // If closing while in GAME_OVER state, ensure game-over-screen is visible so player can restart!
      if (this.state === 'GAME_OVER') {
        const goScreen = document.getElementById('game-over-screen');
        if (goScreen) goScreen.classList.remove('hidden');
      }
    };

    if (lbBtn) lbBtn.addEventListener('click', openLeaderboard);
    if (lbView) {
      lbView.addEventListener('click', () => {
        document.getElementById('game-over-screen').classList.add('hidden');
        openLeaderboard();
      });
    }
    if (lbClose) lbClose.addEventListener('click', closeLeaderboard);
    if (lbOk) lbOk.addEventListener('click', closeLeaderboard);

    if (lbPlayAgain) {
      const handleLbPlayAgain = (e) => {
        if (e) e.preventDefault();
        closeLeaderboard();
        if (window.soundEngine) window.soundEngine.ensureContext();
        this.startNewGame();
      };
      lbPlayAgain.addEventListener('click', handleLbPlayAgain);
      lbPlayAgain.addEventListener('touchend', handleLbPlayAgain);
    }

    // Achievements Modal Buttons
    const achBtn = document.getElementById('btn-achievements');
    const achModal = document.getElementById('achievements-modal');
    const closeAchBtn = document.getElementById('btn-close-achievements');
    const achOkBtn = document.getElementById('btn-achievements-ok');

    const openAchievements = () => {
      if (window.ProgressionManager) {
        window.ProgressionManager.renderAchievementsModal();
      }
      if (achModal) achModal.classList.remove('hidden');
    };

    const closeAchievements = () => {
      if (achModal) achModal.classList.add('hidden');
    };

    if (achBtn) achBtn.addEventListener('click', openAchievements);
    if (closeAchBtn) closeAchBtn.addEventListener('click', closeAchievements);
    if (achOkBtn) achOkBtn.addEventListener('click', closeAchievements);

    // Enhanced Pause Menu Controls
    const pauseResumeBtn = document.getElementById('btn-pause-resume');
    if (pauseResumeBtn) pauseResumeBtn.addEventListener('click', () => this.togglePause());

    const pauseRestartBtn = document.getElementById('btn-pause-restart');
    if (pauseRestartBtn) {
      pauseRestartBtn.addEventListener('click', () => {
        this.togglePause();
        this.startNewGame();
      });
    }

    const pauseHelpBtn = document.getElementById('btn-pause-help');
    if (pauseHelpBtn) {
      pauseHelpBtn.addEventListener('click', () => {
        const hm = document.getElementById('help-modal');
        if (hm) hm.classList.remove('hidden');
      });
    }

    const pauseAchBtn = document.getElementById('btn-pause-achievements');
    if (pauseAchBtn) {
      pauseAchBtn.addEventListener('click', () => {
        openAchievements();
      });
    }

    const pauseLbBtn = document.getElementById('btn-pause-leaderboard');
    if (pauseLbBtn) {
      pauseLbBtn.addEventListener('click', () => {
        openLeaderboard();
      });
    }

    const pauseCrtBtn = document.getElementById('btn-pause-crt');
    if (pauseCrtBtn) {
      pauseCrtBtn.addEventListener('click', () => {
        this.toggleCRT();
      });
    }

    const pauseMuteBtn = document.getElementById('btn-pause-mute');
    if (pauseMuteBtn) {
      pauseMuteBtn.addEventListener('click', () => {
        if (window.soundEngine) {
          const isMuted = window.soundEngine.toggleMute();
          this.updateAudioButton(isMuted);
        }
      });
    }

    // Difficulty selection button listeners
    document.querySelectorAll('.diff-select-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const diff = btn.getAttribute('data-diff');
        if (window.ProgressionManager) {
          window.ProgressionManager.setDifficulty(diff);
          this.targetPercent = this.getTargetPercent(this.level);
          const diffCfg = window.ProgressionManager.getDifficultyConfig();
          this.player.setDifficultyConfig(diffCfg);
          this.updateHUD();
        }
      });
    });

    // Theme selection button listeners
    document.querySelectorAll('.theme-select-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const theme = btn.getAttribute('data-theme');
        if (window.ProgressionManager) {
          window.ProgressionManager.setTheme(theme);
          this.initPattern();
          this.redrawBackground();
        }
      });
    });

    // Initials submit button & input
    const submitInitialsBtn = document.getElementById('btn-submit-initials');
    const initialsInput = document.getElementById('initials-input');
    const handleInitialsSubmit = () => {
      const name = initialsInput ? initialsInput.value : 'AAA';
      this.submitHighScore(name);
      document.getElementById('initials-entry-overlay').classList.add('hidden');
      openLeaderboard();
    };

    if (submitInitialsBtn) submitInitialsBtn.addEventListener('click', handleInitialsSubmit);
    if (initialsInput) {
      initialsInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          handleInitialsSubmit();
        }
      });
    }

    // Level Clear Next Level button & Showcase UI toggle (Minimalist bottom-right controls)
    const nextLvlBtn = document.getElementById('btn-next-level');
    const statsBtn = document.getElementById('btn-showcase-stats');
    const statsCard = document.getElementById('showcase-stats-card');
    const closeStatsBtn = document.getElementById('btn-close-stats-card');
    const lcOverlay = document.getElementById('level-clear-overlay');

    this.advanceNextLevel = () => {
      document.body.classList.remove('round-clear-showcase');
      const fullImg = document.getElementById('showcase-full-img');
      if (fullImg) fullImg.classList.add('hidden');
      if (statsCard) statsCard.classList.add('hidden');
      if (lcOverlay) lcOverlay.classList.add('hidden');
      if (this.state === 'LEVEL_CLEAR') {
        this.startLevel(this.level + 1);
      }
    };

    if (nextLvlBtn) {
      const handleNext = (e) => {
        if (e) {
          e.stopPropagation();
          e.preventDefault();
        }
        if (!this.canAdvanceLevel) return;
        this.advanceNextLevel();
      };
      nextLvlBtn.addEventListener('click', handleNext);
      nextLvlBtn.addEventListener('touchend', handleNext);
    }

    if (statsBtn && statsCard) {
      const handleStatsToggle = (e) => {
        if (e) {
          e.stopPropagation();
          e.preventDefault();
        }
        statsCard.classList.toggle('hidden');
      };
      statsBtn.addEventListener('click', handleStatsToggle);
      statsBtn.addEventListener('touchend', handleStatsToggle);
    }

    if (closeStatsBtn && statsCard) {
      const handleCloseStats = (e) => {
        if (e) {
          e.stopPropagation();
          e.preventDefault();
        }
        statsCard.classList.add('hidden');
      };
      closeStatsBtn.addEventListener('click', handleCloseStats);
      closeStatsBtn.addEventListener('touchend', handleCloseStats);
    }

    // Custom image loader (.jpg, .jpeg, .png)
    const customImgBtn = document.getElementById('btn-custom-image');
    const fileInput = document.getElementById('image-file-input');

    if (customImgBtn && fileInput) {
      customImgBtn.addEventListener('click', () => {
        fileInput.click();
      });

      fileInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;

        if (!/\.(jpe?g|png)$/i.test(file.name) && !file.type.match(/^image\/(jpeg|png)$/)) {
          alert('Please select a valid JPG, JPEG, or PNG image.');
          return;
        }

        const reader = new FileReader();
        reader.onload = (ev) => {
          const img = new Image();
          img._imageName = file.name;
          img.onload = () => {
            this.currentBgImage = img;
            this.currentImageName = file.name;
            this.redrawBackground();
            this.bannerText = 'IMAGE LOADED';
            this.bannerSubtext = file.name.toUpperCase();
            this.bannerTimer = 2.5;
          };
          img.src = ev.target.result;
        };
        reader.readAsDataURL(file);
      });
    }

    // Drag-and-drop image (.jpg, .jpeg, .png) onto canvas
    this.canvas.addEventListener('dragover', (e) => {
      e.preventDefault();
      this.canvas.style.boxShadow = '0 0 30px #00f0ff';
    });

    this.canvas.addEventListener('dragleave', () => {
      this.canvas.style.boxShadow = '';
    });

    this.canvas.addEventListener('drop', (e) => {
      e.preventDefault();
      this.canvas.style.boxShadow = '';
      if (e.dataTransfer && e.dataTransfer.files.length > 0) {
        const file = e.dataTransfer.files[0];
        if (/\.(jpe?g|png)$/i.test(file.name) || file.type.match(/^image\/(jpeg|png)$/)) {
          const reader = new FileReader();
          reader.onload = (ev) => {
            const img = new Image();
            img._imageName = file.name;
            img.onload = () => {
              this.currentBgImage = img;
              this.currentImageName = file.name;
              this.redrawBackground();
              this.bannerText = 'IMAGE LOADED';
              this.bannerSubtext = file.name.toUpperCase();
              this.bannerTimer = 2.5;
            };
            img.src = ev.target.result;
          };
          reader.readAsDataURL(file);
        }
      }
    });
  }

  isModalOpen() {
    const modals = ['help-modal', 'leaderboard-modal', 'achievements-modal'];
    return modals.some(id => {
      const el = document.getElementById(id);
      return el && !el.classList.contains('hidden');
    });
  }

  closeAllModals() {
    ['help-modal', 'leaderboard-modal', 'achievements-modal'].forEach(id => {
      document.getElementById(id)?.classList.add('hidden');
    });
  }

  syncPauseToggles() {
    const crtBtn = document.getElementById('btn-pause-crt');
    if (crtBtn) {
      const isCrt = document.getElementById('screen-container')?.classList.contains('crt-active');
      crtBtn.textContent = isCrt ? '📺 CRT FILTER: ON' : '📺 CRT FILTER: OFF';
      crtBtn.classList.toggle('active', isCrt);
    }
    const muteBtn = document.getElementById('btn-pause-mute');
    if (muteBtn && window.soundEngine) {
      const isMuted = window.soundEngine.muted;
      muteBtn.textContent = isMuted ? '🔇 AUDIO: OFF' : '🔊 AUDIO: ON';
      muteBtn.classList.toggle('active', !isMuted);
    }
  }

  toggleCRT() {
    const sc = document.getElementById('screen-container');
    if (sc) sc.classList.toggle('crt-active');
    this.syncPauseToggles();
  }

  cycleTitleDifficulty(dir) {
    const diffs = ['beginner', 'normal', 'master'];
    const currentDiff = window.ProgressionManager ? window.ProgressionManager.difficulty : 'normal';
    let idx = diffs.indexOf(currentDiff);
    idx = ((idx + dir) % diffs.length + diffs.length) % diffs.length;
    if (window.ProgressionManager) {
      window.ProgressionManager.setDifficulty(diffs[idx]);
      this.targetPercent = this.getTargetPercent(this.level);
      this.player.setDifficultyConfig(window.ProgressionManager.getDifficultyConfig());
      this.updateHUD();
    }
  }

  getPauseMenuItems() {
    return [
      document.getElementById('btn-pause-resume'),
      document.getElementById('btn-pause-restart'),
      document.querySelector('#pause-overlay .diff-buttons-group'),
      document.querySelector('#pause-overlay .theme-buttons-group'),
      document.getElementById('btn-pause-crt'),
      document.getElementById('btn-pause-mute'),
      document.getElementById('btn-pause-achievements'),
      document.getElementById('btn-pause-leaderboard'),
      document.getElementById('btn-pause-help')
    ].filter(Boolean);
  }

  setPauseFocus(index) {
    const items = this.getPauseMenuItems();
    if (!items.length) return;
    this.pauseFocusIndex = ((index % items.length) + items.length) % items.length;
    items.forEach((item, idx) => {
      const isFocused = idx === this.pauseFocusIndex;
      item.classList.toggle('gamepad-focused', isFocused);
      if (item.classList.contains('diff-buttons-group') || item.classList.contains('theme-buttons-group')) {
        const activeBtn = item.querySelector('.active') || item.firstElementChild;
        if (activeBtn) activeBtn.classList.toggle('gamepad-focused', isFocused);
      }
    });
  }

  handlePauseLeftRight(dir) {
    const items = this.getPauseMenuItems();
    const current = items[this.pauseFocusIndex];
    if (!current) return;

    if (current.classList.contains('diff-buttons-group')) {
      const diffs = ['beginner', 'normal', 'master'];
      const currentDiff = window.ProgressionManager ? window.ProgressionManager.difficulty : 'normal';
      let idx = diffs.indexOf(currentDiff);
      idx = ((idx + dir) % diffs.length + diffs.length) % diffs.length;
      if (window.ProgressionManager) {
        window.ProgressionManager.setDifficulty(diffs[idx]);
        this.targetPercent = this.getTargetPercent(this.level);
        this.player.setDifficultyConfig(window.ProgressionManager.getDifficultyConfig());
        this.updateHUD();
      }
      this.setPauseFocus(this.pauseFocusIndex);
    } else if (current.classList.contains('theme-buttons-group')) {
      const themes = ['classic', 'amber', 'matrix'];
      const currentTheme = window.ProgressionManager ? window.ProgressionManager.currentTheme : 'classic';
      let idx = themes.indexOf(currentTheme);
      idx = ((idx + dir) % themes.length + themes.length) % themes.length;
      if (window.ProgressionManager) {
        window.ProgressionManager.setTheme(themes[idx]);
        this.initPattern();
        this.redrawBackground();
      }
      this.setPauseFocus(this.pauseFocusIndex);
    }
  }

  activatePauseFocusedItem() {
    const items = this.getPauseMenuItems();
    const current = items[this.pauseFocusIndex];
    if (!current) return;

    if (current.id === 'btn-pause-resume') {
      this.togglePause();
    } else if (current.id === 'btn-pause-restart') {
      this.togglePause();
      this.startNewGame();
    } else if (current.classList.contains('diff-buttons-group')) {
      this.handlePauseLeftRight(1);
    } else if (current.classList.contains('theme-buttons-group')) {
      this.handlePauseLeftRight(1);
    } else if (current.id === 'btn-pause-crt') {
      this.toggleCRT();
    } else if (current.id === 'btn-pause-mute') {
      if (window.soundEngine) {
        const isMuted = window.soundEngine.toggleMute();
        this.updateAudioButton(isMuted);
      }
    } else if (current.id === 'btn-pause-achievements') {
      if (window.ProgressionManager) window.ProgressionManager.renderAchievementsModal();
      document.getElementById('achievements-modal')?.classList.remove('hidden');
    } else if (current.id === 'btn-pause-leaderboard') {
      this.renderLeaderboard();
      document.getElementById('leaderboard-modal')?.classList.remove('hidden');
    } else if (current.id === 'btn-pause-help') {
      document.getElementById('help-modal')?.classList.remove('hidden');
    }
  }

  updateAudioButton(isMuted) {
    const muteBtn = document.getElementById('btn-mute');
    if (muteBtn) {
      muteBtn.textContent = isMuted ? '🔇 SOUND OFF' : '🔊 SOUND ON';
      muteBtn.classList.toggle('muted', isMuted);
    }
    const pauseMuteBtn = document.getElementById('btn-pause-mute');
    if (pauseMuteBtn) {
      pauseMuteBtn.textContent = isMuted ? '🔇 AUDIO: OFF' : '🔊 AUDIO: ON';
      pauseMuteBtn.classList.toggle('active', !isMuted);
    }
  }

  get paused() {
    return this.state === 'PAUSED';
  }

  set paused(val) {
    if (val && this.state === 'PLAYING') {
      this.togglePause();
    } else if (!val && this.state === 'PAUSED') {
      this.togglePause();
    }
  }

  togglePause() {
    if (this.state === 'PLAYING') {
      this.state = 'PAUSED';
      this.player.stopSounds();
      if (window.ProgressionManager) {
        window.ProgressionManager.syncDifficultyUI();
        window.ProgressionManager.syncThemeUI();
      }
      this.syncPauseToggles();
      document.getElementById('pause-overlay').classList.remove('hidden');
      this.setPauseFocus(0);
    } else if (this.state === 'PAUSED') {
      this.closeAllModals();
      this.state = 'PLAYING';
      document.getElementById('pause-overlay').classList.add('hidden');
      this.getPauseMenuItems().forEach(item => {
        item.classList.remove('gamepad-focused');
        const activeSub = item.querySelector ? item.querySelector('.gamepad-focused') : null;
        if (activeSub) activeSub.classList.remove('gamepad-focused');
      });
    }
  }

  toggleFullscreen() {
    const elem = document.documentElement;
    if (!document.fullscreenElement && !document.webkitFullscreenElement) {
      if (elem.requestFullscreen) {
        elem.requestFullscreen().catch(err => console.warn('Fullscreen error:', err));
      } else if (elem.webkitRequestFullscreen) {
        elem.webkitRequestFullscreen();
      }
    } else {
      if (document.exitFullscreen) {
        document.exitFullscreen().catch(err => console.warn('Exit fullscreen error:', err));
      } else if (document.webkitExitFullscreen) {
        document.webkitExitFullscreen();
      }
    }
  }

  startNewGame() {
    if (window.SecurityManager && !window.SecurityManager.isAuthorized()) {
      return;
    }

    const diffCfg = window.ProgressionManager ? window.ProgressionManager.getDifficultyConfig() : null;
    this.score = 0;
    this.lives = diffCfg ? diffCfg.initialLives : 3;
    this.level = 1;
    this.multiplier = 1;
    this.awardedMilestones.clear();
    this.floatingScores = [];
    this.nearTargetAnnounced = false;

    const nearBanner = document.getElementById('near-goal-banner');
    if (nearBanner) nearBanner.classList.add('hidden');

    document.getElementById('title-screen').classList.add('hidden');
    document.getElementById('game-over-screen').classList.add('hidden');
    document.getElementById('pause-overlay').classList.add('hidden');
    document.getElementById('level-clear-overlay').classList.add('hidden');
    document.getElementById('initials-entry-overlay').classList.add('hidden');
    document.body.classList.remove('round-clear-showcase');
    const lbModal = document.getElementById('leaderboard-modal');
    if (lbModal) lbModal.classList.add('hidden');
    const achModal = document.getElementById('achievements-modal');
    if (achModal) achModal.classList.add('hidden');
    document.getElementById('screen-container').classList.remove('danger-alert');

    this.startLevel(1);
  }

  async loadManifest() {
    // Strategy 1: Dynamic Auto-Discovery from level-images/ (supports index.php & Apache AutoIndex)
    try {
      const res = await fetch('level-images/', { cache: 'no-cache' });
      if (res.ok) {
        const contentType = res.headers.get('content-type') || '';

        // Case A: Endpoint returned JSON directly (e.g. level-images/index.php)
        if (contentType.includes('application/json')) {
          const list = await res.json();
          if (Array.isArray(list) && list.length > 0) {
            const valid = list.filter(f => typeof f === 'string' && /\.(jpe?g|png|webp)$/i.test(f));
            if (valid.length > 0) {
              this.imageList = valid;
              this.imageDeck = [];
              console.log(`[Auto-Discovery] Found ${valid.length} images via server JSON.`);
              return;
            }
          }
        }

        // Case B: Endpoint returned HTML directory listing (Apache / Nginx / dev server autoindex)
        if (contentType.includes('text/html')) {
          const htmlText = await res.text();
          const doc = new DOMParser().parseFromString(htmlText, 'text/html');
          const links = Array.from(doc.querySelectorAll('a'))
            .map(a => a.getAttribute('href'))
            .filter(href => href && /\.(jpe?g|png|webp)$/i.test(href))
            .map(href => {
              const clean = href.split('?')[0].split('#')[0];
              return decodeURIComponent(clean.split('/').pop());
            })
            .filter(name => name && !name.startsWith('.') && name !== 'index.php');

          const unique = [...new Set(links)];
          if (unique.length > 0) {
            this.imageList = unique;
            this.imageDeck = [];
            console.log(`[Auto-Discovery] Auto-indexed ${unique.length} images from folder.`);
            return;
          }
        }
      }
    } catch (e) {
      // Dynamic auto-discovery not available, proceed to static manifest
    }

    // Strategy 2: Static level-images/manifest.json fallback
    try {
      const res = await fetch('level-images/manifest.json', { cache: 'no-cache' });
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list) && list.length > 0) {
          const valid = list.filter(f => typeof f === 'string' && /\.(jpe?g|png|webp)$/i.test(f));
          if (valid.length > 0) {
            this.imageList = valid;
            this.imageDeck = [];
            console.log(`[Manifest] Loaded ${valid.length} images from manifest.json.`);
            return;
          }
        }
      }
    } catch (e) {
      console.warn('Could not load level-images/manifest.json, using defaults', e);
    }
  }

  /**
   * Refill and shuffle the image deck using Fisher-Yates shuffle.
   * Guarantees every image in the folder is shown once before any image repeats,
   * completely eliminating duplicate streaks and ensuring 100% fair distribution.
   */
  refillImageDeck() {
    if (!this.imageList || this.imageList.length === 0) {
      this.imageDeck = [];
      return;
    }

    // Clone list
    const deck = [...this.imageList];

    // Fisher-Yates shuffle
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }

    // Prevent immediate repeat across deck resets
    if (deck.length > 1 && deck[deck.length - 1] === this.currentImageName) {
      const swapIdx = Math.floor(Math.random() * (deck.length - 1));
      [deck[deck.length - 1], deck[swapIdx]] = [deck[swapIdx], deck[deck.length - 1]];
    }

    this.imageDeck = deck;
  }

  getNextRandomImage() {
    if (!this.imageDeck || this.imageDeck.length === 0) {
      this.refillImageDeck();
    }
    if (this.imageDeck.length === 0) return '';
    return this.imageDeck.pop();
  }

  loadRandomBackgroundImage(callback) {
    if (!this.imageList || this.imageList.length === 0) {
      if (callback) callback();
      return;
    }

    this.currentImageName = this.getNextRandomImage();

    const img = new Image();
    img._imageName = this.currentImageName;
    img.onload = () => {
      this.currentBgImage = img;
      this.redrawBackground();
      if (callback) callback();
    };
    img.onerror = () => {
      console.warn('Failed to load image:', this.currentImageName);
      this.currentBgImage = null;
      this.redrawBackground();
      if (callback) callback();
    };
    img.src = `level-images/${this.currentImageName}`;
  }

  getTargetPercent(lvl) {
    const diffCfg = window.ProgressionManager ? window.ProgressionManager.getDifficultyConfig() : null;
    const targets = (diffCfg && diffCfg.targetPercents) ? diffCfg.targetPercents : [65, 70, 75, 78, 80];
    const idx = Math.min(lvl - 1, targets.length - 1);
    return targets[idx];
  }

  startLevel(lvl) {
    document.body.classList.remove('round-clear-showcase');
    this.level = lvl;
    this.targetPercent = this.getTargetPercent(lvl);
    this.grid.init();
    this.player.reset();

    const diffCfg = window.ProgressionManager ? window.ProgressionManager.getDifficultyConfig() : null;
    if (diffCfg) {
      this.player.setDifficultyConfig(diffCfg);
    }

    const currentDiff = window.ProgressionManager ? window.ProgressionManager.difficulty : 'normal';
    this.sparxMgr.reset(lvl, currentDiff);

    this.claimedPercent = 0;
    this.fullyRevealed = false;
    this.floatingScores = [];
    this.nearTargetAnnounced = false;

    const nearBanner = document.getElementById('near-goal-banner');
    if (nearBanner) nearBanner.classList.add('hidden');

    const lcOverlay = document.getElementById('level-clear-overlay');
    if (lcOverlay) lcOverlay.classList.add('hidden');
    const screenElem = document.getElementById('screen-container');
    if (screenElem) screenElem.classList.remove('danger-alert');

    // Load random image to uncover for this level
    this.loadRandomBackgroundImage(() => {
      this.redrawBackground();
    });

    // Qix instances: Level 1-2 have 1 Qix, Level 3+ have 2 Qixes!
    this.qixList = [];
    const baseMult = diffCfg ? diffCfg.qixSpeed : 1.0;
    const speed = (1.0 + (lvl - 1) * 0.12) * baseMult;

    if (lvl < 3) {
      this.qixList.push(new Qix(this.grid, GAME_WIDTH / 2, GAME_HEIGHT / 2, speed));
    } else {
      // 2 independent Qixes!
      this.qixList.push(new Qix(this.grid, GAME_WIDTH * 0.35, GAME_HEIGHT * 0.4, speed));
      this.qixList.push(new Qix(this.grid, GAME_WIDTH * 0.65, GAME_HEIGHT * 0.6, speed));
    }

    this.redrawBackground();
    this.updateHUD();

    this.state = 'PLAYING';
    const diffName = diffCfg ? diffCfg.name : 'ARCADE';
    this.bannerText = `LEVEL ${this.level} [${diffName}]`;
    this.bannerSubtext = lvl >= 3 ? 'DUAL QIX: SPLIT THEM FOR MULTIPLIER!' : `CLAIM ${this.targetPercent}% TO UNCOVER THE ART!`;
    this.bannerTimer = 2.2;
  }

  updateInput() {
    let dx = 0;
    let dy = 0;

    if (this.keysDown['ArrowUp'] || this.keysDown['KeyW']) dy -= 1;
    if (this.keysDown['ArrowDown'] || this.keysDown['KeyS']) dy += 1;
    if (this.keysDown['ArrowLeft'] || this.keysDown['KeyA']) dx -= 1;
    if (this.keysDown['ArrowRight'] || this.keysDown['KeyD']) dx += 1;

    this.input.dx = dx;
    this.input.dy = dy;
    this.input.fastDraw = !!(this.keysDown['Space'] || this.keysDown['KeyJ']);
    this.input.slowDraw = !!(this.keysDown['ShiftLeft'] || this.keysDown['ShiftRight'] || this.keysDown['KeyK']);
  }

  handleAreaCaptured(result) {
    if (result.isSplit) {
      // Split triggered!
      this.triggerQixSplit();
      return;
    }

    // Normal capture
    this.redrawBackground();
    this.claimedPercent = this.grid.getClaimedPercent();

    // Dynamic risk-reward for bold cuts
    const singleCutPercent = Math.round((result.capturedCells / this.grid.totalInnerCells) * 100);
    let sliceBonusMultiplier = 1;
    let sliceBonusLabel = '';

    if (result.isSlow) {
      if (singleCutPercent >= 20) {
        sliceBonusMultiplier = 3; // 3x combo (12 pts/cell total)
        sliceBonusLabel = 'MASSIVE CUT! 3X SLOW BONUS';
        if (window.ProgressionManager) {
          window.ProgressionManager.unlockAchievement('DEEP_CUT');
        }
      } else if (singleCutPercent >= 10) {
        sliceBonusMultiplier = 2; // 2x combo (8 pts/cell total)
        sliceBonusLabel = 'BOLD CUT! 2X SLOW BONUS';
      }
    }

    // Award score
    const pointsPerCell = (result.isSlow ? 4 : 2) * sliceBonusMultiplier;
    const earned = result.capturedCells * pointsPerCell * this.multiplier;
    this.addScore(earned);

    // Spawn floating score tags
    this.spawnFloatingScore(`+${earned.toLocaleString()}`, this.player.x, this.player.y, result.isSlow ? '#ff8822' : '#00e5ff');

    if (sliceBonusLabel && this.state === 'PLAYING') {
      this.bannerText = sliceBonusLabel;
      this.bannerSubtext = `+${earned.toLocaleString()} PTS! (${singleCutPercent}% CHUNK)`;
      this.bannerTimer = 1.8;
      this.spawnFloatingScore(sliceBonusLabel, this.player.x, this.player.y - 12, '#ffea00');
    }

    // Check near-completion warning alert
    const isNearGoal = (this.claimedPercent >= this.targetPercent - 5) && (this.claimedPercent < this.targetPercent);
    const nearGoalBanner = document.getElementById('near-goal-banner');
    if (nearGoalBanner) {
      nearGoalBanner.classList.toggle('hidden', !isNearGoal);
    }
    if (isNearGoal && !this.nearTargetAnnounced) {
      this.nearTargetAnnounced = true;
      if (window.soundEngine) window.soundEngine.playTargetNear();
      this.spawnFloatingScore('TARGET NEAR! CLOSE THE LOOP!', this.grid.width / 2, 28, '#ffea00');
    }

    triggerHaptic(40);

    if (window.soundEngine) {
      window.soundEngine.playCapture(result.isSlow);
    }

    this.updateHUD();

    // Check level completion against dynamic level target
    if (this.claimedPercent >= this.targetPercent) {
      this.triggerLevelClear();
    }
  }

  showRoundClearShowcase({ percent, target, bonus, mult, extraMsg }) {
    document.body.classList.add('round-clear-showcase');
    this.redrawBackground();

    // Show full-screen native image element if loaded ("fit to screen" via object-fit: contain)
    const fullImg = document.getElementById('showcase-full-img');
    if (fullImg) {
      if (this.currentBgImage && this.currentBgImage.complete && this.currentBgImage.src) {
        fullImg.src = this.currentBgImage.src;
        fullImg.classList.remove('hidden');
      } else {
        fullImg.classList.add('hidden');
      }
    }

    // Populate stats popover card
    const pEl = document.getElementById('level-clear-percent');
    const tEl = document.getElementById('level-clear-target');
    const bEl = document.getElementById('level-clear-bonus');
    const mEl = document.getElementById('level-clear-mult');
    const eEl = document.getElementById('level-clear-extra-msg');
    if (pEl) pEl.textContent = `${percent}%`;
    if (tEl) tEl.textContent = `${target}%`;
    if (bEl) bEl.textContent = `+${bonus.toLocaleString()}`;
    if (mEl) mEl.textContent = `x${mult}`;
    if (eEl) eEl.textContent = extraMsg || '';

    // Default: keep stats card closed, only show minimalist bottom-right icons
    const statsCard = document.getElementById('showcase-stats-card');
    if (statsCard) statsCard.classList.add('hidden');

    const lcOverlay = document.getElementById('level-clear-overlay');
    if (lcOverlay) lcOverlay.classList.remove('hidden');
  }

  triggerQixSplit() {
    this.state = 'LEVEL_CLEAR';
    this.player.stopSounds();
    this.fullyRevealed = true;
    this.keysDown = {};
    this.canAdvanceLevel = false;
    setTimeout(() => { this.canAdvanceLevel = true; }, 700);

    const screenElem = document.getElementById('screen-container');
    if (screenElem) screenElem.classList.remove('danger-alert');
    triggerHaptic([40, 30, 40, 30, 60]);

    this.multiplier = Math.min(this.multiplier + 1, 9);
    const splitBonus = 5000 * this.multiplier;
    this.addScore(splitBonus);
    this.spawnFloatingScore(`SPLIT BONUS! +${splitBonus.toLocaleString()}`, this.grid.width / 2, this.grid.height / 2, '#ff0077');

    if (window.soundEngine) {
      window.soundEngine.playSplit();
    }

    if (window.ProgressionManager) {
      window.ProgressionManager.unlockAchievement('DUAL_SPLITTER');
    }
    const nearBanner = document.getElementById('near-goal-banner');
    if (nearBanner) nearBanner.classList.add('hidden');

    this.showRoundClearShowcase({
      percent: this.claimedPercent,
      target: this.targetPercent,
      bonus: splitBonus,
      mult: this.multiplier,
      extraMsg: `DUAL QIX SPLIT! MULTIPLIER x${this.multiplier}!`
    });

    this.bannerText = 'QIX SPLIT!';
    this.bannerSubtext = `BONUS MULTIPLIER x${this.multiplier} AWARDS +${splitBonus} PTS!`;
    this.bannerTimer = 0; // Wait indefinitely for user to initiate next level
  }

  triggerLevelClear() {
    this.state = 'LEVEL_CLEAR';
    this.player.stopSounds();
    this.fullyRevealed = true;
    this.keysDown = {};
    this.canAdvanceLevel = false;
    setTimeout(() => { this.canAdvanceLevel = true; }, 700);

    const screenElem = document.getElementById('screen-container');
    if (screenElem) screenElem.classList.remove('danger-alert');
    triggerHaptic([40, 30, 40, 30, 60]);

    if (window.ProgressionManager) {
      window.ProgressionManager.unlockAchievement('FIRST_CONTACT');
      window.ProgressionManager.recordUnveiledImage(this.currentImageName);
      if (this.claimedPercent >= 90) {
        window.ProgressionManager.unlockAchievement('PERFECTIONIST');
      }
      if (this.level >= 5) {
        window.ProgressionManager.unlockAchievement('SURVIVOR');
      }
    }
    const nearBanner = document.getElementById('near-goal-banner');
    if (nearBanner) nearBanner.classList.add('hidden');

    // Threshold bonus: 1,000 points per 1% above target goal
    const excess = Math.max(0, this.claimedPercent - this.targetPercent);
    const bonus = excess * 1000 * this.multiplier;
    if (bonus > 0) {
      this.addScore(bonus);
    }

    // Extra life for 90%+
    let extraLifeAwarded = false;
    if (this.claimedPercent >= 90) {
      this.lives++;
      extraLifeAwarded = true;
    }

    if (window.soundEngine) {
      window.soundEngine.playLevelClear();
    }

    this.showRoundClearShowcase({
      percent: this.claimedPercent,
      target: this.targetPercent,
      bonus: bonus,
      mult: this.multiplier,
      extraMsg: extraLifeAwarded ? 'EXTRA LIFE AWARDED! ⭐' : ''
    });

    this.bannerText = 'ARTWORK 100% UNVEILED!';
    const bonusMsg = bonus > 0 ? ` +${bonus.toLocaleString()} BONUS PTS!` : '';
    const extraLifeMsg = extraLifeAwarded ? ' (EXTRA LIFE AWARDED!)' : '';
    this.bannerSubtext = `${this.claimedPercent}% CLAIMED! (GOAL ${this.targetPercent}%)${bonusMsg}${extraLifeMsg}`;
    this.bannerTimer = 0; // Wait indefinitely for player to initiate next level
  }

  handlePlayerDeath(reason = 'collision') {
    this.lives--;
    this.shakeDuration = 0.5;
    this.shakeIntensity = 8;
    const screenElem = document.getElementById('screen-container');
    if (screenElem) screenElem.classList.remove('danger-alert');
    triggerHaptic([70, 40, 80]);

    if (window.soundEngine) {
      window.soundEngine.playDeath();
    }

    this.updateHUD();

    if (this.lives <= 0) {
      this.triggerGameOver();
    } else {
      this.player.respawn();
      this.bannerText = reason === 'fuse' ? 'FUSE CAUGHT YOU!' : 'WATCH OUT!';
      this.bannerSubtext = `${this.lives} ${this.lives === 1 ? 'LIFE' : 'LIVES'} REMAINING`;
      this.bannerTimer = 1.8;
    }
  }

  triggerGameOver() {
    this.state = 'GAME_OVER';
    this.player.stopSounds();
    const screenElem = document.getElementById('screen-container');
    if (screenElem) screenElem.classList.remove('danger-alert');
    triggerHaptic([100, 60, 120]);

    if (window.soundEngine) {
      window.soundEngine.playGameOver();
    }

    if (this.score > this.highScore) {
      this.highScore = this.score;
      localStorage.setItem('qix_high_score', this.highScore.toString());
    }

    document.getElementById('final-score').textContent = this.score.toLocaleString();
    document.getElementById('final-percent').textContent = `${this.claimedPercent}%`;

    // Check if score qualifies for Top 5 leaderboard
    if (this.checkHighScoreQualify()) {
      const initialsOverlay = document.getElementById('initials-entry-overlay');
      const input = document.getElementById('initials-input');
      this.initialsChars = ['A', 'A', 'A'];
      this.initialsIndex = 0;
      if (input) input.value = 'AAA';
      if (initialsOverlay) initialsOverlay.classList.remove('hidden');
      setTimeout(() => {
        if (input) input.focus();
      }, 150);
    } else {
      document.getElementById('game-over-screen').classList.remove('hidden');
    }

    this.updateHUD();
  }

  addScore(pts) {
    const prevScore = this.score;
    this.score += pts;
    if (this.score > this.highScore) {
      this.highScore = this.score;
      localStorage.setItem('qix_high_score', this.highScore.toString());
    }

    if (this.score >= 100000 && window.ProgressionManager) {
      window.ProgressionManager.unlockAchievement('CENTURY_CLUB');
    }

    // Milestone bonus extra lives at 50,000, 125,000, 250,000, 500,000 pts
    const milestones = [50000, 125000, 250000, 500000];
    for (const m of milestones) {
      if (prevScore < m && this.score >= m && !this.awardedMilestones.has(m)) {
        this.awardedMilestones.add(m);
        this.lives++;
        if (window.soundEngine) window.soundEngine.playSplit();
        this.bannerText = 'EXTRA LIFE!';
        this.bannerSubtext = `SCORE REACHED ${m.toLocaleString()} PTS!`;
        this.bannerTimer = 2.5;
        this.updateHUD();
        break;
      }
    }
  }

  updateHUD() {
    if (this.hudScoreEl && this.score !== this._lastScore) {
      this._lastScore = this.score;
      this.hudScoreEl.textContent = this.score.toLocaleString();
    }

    if (this.hudHighScoreEl && this.highScore !== this._lastHighScore) {
      this._lastHighScore = this.highScore;
      this.hudHighScoreEl.textContent = this.highScore.toLocaleString();
    }

    if (this.hudLevelEl && this.level !== this._lastLevel) {
      this._lastLevel = this.level;
      this.hudLevelEl.textContent = this.level.toString();
    }

    if (this.hudMultEl && this.multiplier !== this._lastMultiplier) {
      this._lastMultiplier = this.multiplier;
      this.hudMultEl.textContent = `x${this.multiplier}`;
    }

    if (this.hudGoalEl && this.targetPercent !== this._lastTarget) {
      this._lastTarget = this.targetPercent;
      this.hudGoalEl.textContent = `${this.targetPercent}%`;
    }

    // Claimed gauge against dynamic level target
    if (this.hudPercentEl && this.claimedPercent !== this._lastPercent) {
      this._lastPercent = this.claimedPercent;
      this.hudPercentEl.textContent = `${this.claimedPercent}%`;

      if (this.percentBarFill) {
        const isNearGoal = (this.claimedPercent >= this.targetPercent - 5) && (this.claimedPercent < this.targetPercent);
        this.percentBarFill.style.width = `${Math.min(100, (this.claimedPercent / this.targetPercent) * 100)}%`;
        this.percentBarFill.classList.toggle('near-goal', isNearGoal);
        if (this.claimedPercent >= this.targetPercent) {
          this.percentBarFill.classList.add('threshold-met');
        } else {
          this.percentBarFill.classList.remove('threshold-met');
        }
      }
    }

    // Sparx gauge
    if (this.sparxBarFill && this.sparxMgr) {
      const ratio = Math.max(0, this.sparxMgr.timer / this.sparxMgr.sparxTimerMax);
      const roundedRatio = Math.round(ratio * 100);
      if (roundedRatio !== this._lastSparxRatio) {
        this._lastSparxRatio = roundedRatio;
        this.sparxBarFill.style.width = `${ratio * 100}%`;
        if (ratio < 0.25) {
          this.sparxBarFill.classList.add('urgent');
        } else {
          this.sparxBarFill.classList.remove('urgent');
        }
      }
    }

    // Lives display
    if (this.livesContainer && this.lives !== this._lastLives) {
      this._lastLives = this.lives;
      this.livesContainer.innerHTML = '';
      for (let i = 0; i < this.lives; i++) {
        const d = document.createElement('span');
        d.className = 'life-diamond';
        this.livesContainer.appendChild(d);
      }
    }
  }

  // Redraw static background canvas (borders & claimed territories)
  redrawBackground() {
    const ctx = this.bgCtx;
    const w = this.bgCanvas.width;
    const h = this.bgCanvas.height;

    // Deep black playfield
    ctx.fillStyle = '#05070d';
    ctx.fillRect(0, 0, w, h);

    const gw = this.grid.width;
    const gh = this.grid.height;
    const sx = this.scaleX;
    const sy = this.scaleY;
    const ox = this.offsetX;
    const oy = this.offsetY;

    const hasImage = this.currentBgImage && this.currentBgImage.complete && this.currentBgImage.naturalWidth > 0;

    if (hasImage && this.fullyRevealed) {
      // 100% full reveal on level clear - "fit to screen" preserving aspect ratio
      drawImageFit(ctx, this.currentBgImage, w, h);
    } else if (hasImage) {
      // Build mask of claimed areas
      this.maskCtx.clearRect(0, 0, w, h);
      this.maskCtx.fillStyle = '#ffffff';
      let hasClaimed = false;

      for (let y = 0; y < gh; y++) {
        const row = y * gw;
        for (let x = 0; x < gw; x++) {
          const cell = this.grid.cells[row + x];
          if (cell === CELL_CLAIMED_SLOW || cell === CELL_CLAIMED_FAST) {
            hasClaimed = true;
            this.maskCtx.fillRect(ox + x * sx, oy + y * sy, sx + 0.5, sy + 0.5);
          }
        }
      }

      if (hasClaimed) {
        // Draw background image filling screen, clipped to claimed mask
        this.tempCtx.clearRect(0, 0, w, h);
        drawImageCover(this.tempCtx, this.currentBgImage, w, h);
        this.tempCtx.globalCompositeOperation = 'destination-in';
        this.tempCtx.drawImage(this.maskCanvas, 0, 0);
        this.tempCtx.globalCompositeOperation = 'source-over';

        ctx.drawImage(this.tempCanvas, 0, 0);

        // Apply authentic arcade color tints for Fast vs Slow draw
        for (let y = 0; y < gh; y++) {
          const row = y * gw;
          for (let x = 0; x < gw; x++) {
            const cell = this.grid.cells[row + x];
            if (cell === CELL_CLAIMED_FAST) {
              ctx.fillStyle = 'rgba(0, 140, 255, 0.15)';
              ctx.fillRect(ox + x * sx, oy + y * sy, sx + 0.5, sy + 0.5);
            } else if (cell === CELL_CLAIMED_SLOW) {
              ctx.fillStyle = 'rgba(255, 80, 0, 0.12)';
              ctx.fillRect(ox + x * sx, oy + y * sy, sx + 0.5, sy + 0.5);
            }
          }
        }
      }
    } else {
      // Fallback if image not available
      for (let y = 0; y < gh; y++) {
        for (let x = 0; x < gw; x++) {
          const cell = this.grid.cells[y * gw + x];
          if (cell === CELL_CLAIMED_SLOW) {
            ctx.fillStyle = this.slowPattern;
            ctx.fillRect(ox + x * sx, oy + y * sy, sx + 0.5, sy + 0.5);
          } else if (cell === CELL_CLAIMED_FAST) {
            ctx.fillStyle = this.fastPattern;
            ctx.fillRect(ox + x * sx, oy + y * sy, sx + 0.5, sy + 0.5);
          }
        }
      }
    }

    // Draw active neon cyan borders (only during gameplay; when cleared, artwork is 100% unobstructed!)
    if (!this.fullyRevealed) {
      ctx.fillStyle = '#00ffee';
      for (let y = 0; y < gh; y++) {
        const row = y * gw;
        for (let x = 0; x < gw; x++) {
          if (this.grid.cells[row + x] === CELL_BORDER) {
            ctx.fillRect(ox + x * sx, oy + y * sy, sx + 0.5, sy + 0.5);
          }
        }
      }
    }
  }

  loop(timestamp) {
    if (!this.lastTime) this.lastTime = timestamp;
    const dt = Math.min((timestamp - this.lastTime) / 1000, 0.05); // Clamp dt
    this.lastTime = timestamp;

    if (window.SecurityManager && !window.SecurityManager.isAuthorized()) {
      requestAnimationFrame(this.loop.bind(this));
      return;
    }

    // Poll physical Gamepad controls (R36S / PortMaster WebX)
    this.pollGamepad();

    this.update(dt);
    this.render();

    requestAnimationFrame(this.loop.bind(this));
  }

  update(dt) {
    if (this.state === 'PAUSED') return;

    if (this.state === 'LEVEL_CLEAR') {
      // Space or Enter lets player advance after admiring the art, with debounce protection
      if (this.canAdvanceLevel && (this.keysDown['Space'] || this.keysDown['Enter'])) {
        this.keysDown['Space'] = false;
        this.keysDown['Enter'] = false;
        this.advanceNextLevel();
      }
      return;
    }

    if (this.bannerTimer > 0) {
      this.bannerTimer -= dt;
    }

    // Screen shake countdown
    if (this.shakeDuration > 0) {
      this.shakeDuration -= dt;
    }

    if (this.state === 'PLAYING') {
      this.updateInput();

      // Update player
      this.player.update(
        dt,
        this.input,
        this.qixList,
        this.handleAreaCaptured.bind(this),
        this.handlePlayerDeath.bind(this)
      );

      // Update Qixes
      for (const qix of this.qixList) {
        qix.update();

        // Check collision between Qix and player/Stix
        if (qix.checkCollision(this.player)) {
          this.handlePlayerDeath('qix');
          break;
        }
      }

      // Update Sparx
      this.sparxMgr.update(dt, this.player);
      if (this.sparxMgr.checkCollision(this.player)) {
        this.handlePlayerDeath('sparx');
      }

      // Update floating scores
      for (let i = this.floatingScores.length - 1; i >= 0; i--) {
        const fs = this.floatingScores[i];
        fs.y -= 28 * dt;
        fs.life -= dt;
        if (fs.life <= 0) {
          this.floatingScores.splice(i, 1);
        }
      }

      // Qix proximity danger alert vignette
      let nearDanger = false;
      if (this.player.isDrawing() && this.player.stixPath.length > 0) {
        for (const qix of this.qixList) {
          const center = qix.getCenter();
          const distToPlayer = Math.hypot(center.x - this.player.x, center.y - this.player.y);
          if (distToPlayer < 65) {
            nearDanger = true;
            break;
          }
          const checkStep = Math.max(1, Math.floor(this.player.stixPath.length / 8));
          for (let s = 0; s < this.player.stixPath.length; s += checkStep) {
            const pt = this.player.stixPath[s];
            if (Math.hypot(center.x - pt.x, center.y - pt.y) < 45) {
              nearDanger = true;
              break;
            }
          }
          if (nearDanger) break;
        }
      }
      if (this.screenElem && nearDanger !== this._lastDanger) {
        this._lastDanger = nearDanger;
        this.screenElem.classList.toggle('danger-alert', nearDanger);
      }

      this.updateHUD();
    }
  }

  render() {
    const ctx = this.ctx;
    const w = this.canvas.width;
    const h = this.canvas.height;

    ctx.save();

    // Screen shake transform
    if (this.shakeDuration > 0) {
      const ox = (Math.random() - 0.5) * this.shakeIntensity;
      const oy = (Math.random() - 0.5) * this.shakeIntensity;
      ctx.translate(ox, oy);
    }

    // 1. Draw cached background (full 100% uncovered image when fullyRevealed)
    ctx.drawImage(this.bgCanvas, 0, 0);

    // During LEVEL_CLEAR reward unveil: DO NOT draw Qix, Sparx, or player!
    // The entire artwork is displayed 100% unobstructed!
    if (this.state !== 'LEVEL_CLEAR') {
      ctx.save();
      ctx.translate(this.offsetX, this.offsetY);

      // 2. Render Qix entities (chaotic neon ribbon trails)
      for (const qix of this.qixList) {
        qix.render(ctx, this.scaleX, this.scaleY);
      }

      // 3. Render Sparx enemies
      this.sparxMgr.render(ctx, this.scaleX, this.scaleY);

      // 4. Render Player marker, active Stix, and sizzling Fuse
      this.player.render(ctx, this.scaleX, this.scaleY);

      ctx.restore();
    }

    // 5. Render floating score popups
    for (const fs of this.floatingScores) {
      const alpha = Math.max(0, fs.life / fs.maxLife);
      ctx.save();
      ctx.font = 'bold 11px "Press Start 2P", monospace, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = fs.color;
      ctx.globalAlpha = alpha;
      ctx.shadowColor = fs.color;
      ctx.shadowBlur = 10;
      ctx.fillText(fs.text, fs.x, fs.y);
      ctx.restore();
    }

    // 6. Render Banner overlay if active (during active gameplay)
    if (this.bannerTimer > 0 && this.bannerText && this.state !== 'LEVEL_CLEAR') {
      this.renderBanner(ctx, w, h);
    }

    ctx.restore();
  }

  renderRewardBanner(ctx, w, h) {
    ctx.save();
    // Sleek bottom glass bar
    const barH = 56;
    const barY = h - barH - 18;
    ctx.fillStyle = 'rgba(5, 7, 13, 0.85)';
    ctx.strokeStyle = '#ffea00';
    ctx.lineWidth = 2;
    ctx.shadowColor = '#ffea00';
    ctx.shadowBlur = 16;

    ctx.beginPath();
    if (ctx.roundRect) {
      ctx.roundRect(w * 0.08, barY, w * 0.84, barH, 12);
    } else {
      ctx.rect(w * 0.08, barY, w * 0.84, barH);
    }
    ctx.fill();
    ctx.stroke();

    ctx.textAlign = 'center';
    ctx.fillStyle = '#ffea00';
    ctx.shadowColor = '#ffea00';
    ctx.shadowBlur = 12;
    ctx.font = 'bold 16px "Press Start 2P", monospace, sans-serif';
    ctx.fillText('🏆 ARTWORK 100% UNVEILED!', w / 2, barY + 24);

    ctx.fillStyle = '#00f0ff';
    ctx.shadowColor = '#00f0ff';
    ctx.shadowBlur = 8;
    ctx.font = '10px "Press Start 2P", monospace, sans-serif';
    ctx.fillText(this.bannerSubtext || 'PRESS (A) OR START TO CONTINUE ▶', w / 2, barY + 44);

    ctx.restore();
  }

  renderBanner(ctx, w, h) {
    ctx.save();
    ctx.fillStyle = 'rgba(5, 7, 13, 0.75)';
    ctx.fillRect(0, h * 0.38, w, h * 0.24);

    ctx.textAlign = 'center';
    ctx.fillStyle = '#ffff00';
    ctx.shadowColor = '#ff8800';
    ctx.shadowBlur = 16;
    ctx.font = 'bold 22px "Press Start 2P", monospace, sans-serif';
    ctx.fillText(this.bannerText, w / 2, h * 0.48);

    if (this.bannerSubtext) {
      ctx.fillStyle = '#ffffff';
      ctx.shadowColor = '#00ffff';
      ctx.shadowBlur = 8;
      ctx.font = '12px "Press Start 2P", monospace, sans-serif';
      ctx.fillText(this.bannerSubtext, w / 2, h * 0.56);
    }

    ctx.restore();
  }

  // ==========================================
  // ARCADE LEADERBOARD SYSTEM (TOP 5)
  // ==========================================
  initLeaderboard() {
    this.renderLeaderboard();
  }

  loadLeaderboard() {
    const defaultBoard = [
      { name: 'TAI', score: 35000, level: 3 },
      { name: 'QIX', score: 25000, level: 2 },
      { name: 'RET', score: 18000, level: 2 },
      { name: 'NEO', score: 12000, level: 1 },
      { name: 'ARC', score: 8000, level: 1 }
    ];
    try {
      const data = localStorage.getItem('qix_leaderboard');
      if (data) {
        const parsed = JSON.parse(data);
        if (Array.isArray(parsed) && parsed.length > 0) return parsed;
      }
    } catch (e) {}
    return defaultBoard;
  }

  saveLeaderboard(board) {
    try {
      localStorage.setItem('qix_leaderboard', JSON.stringify(board));
    } catch (e) {}
  }

  renderLeaderboard() {
    const tbody = document.getElementById('leaderboard-body');
    if (!tbody) return;
    const board = this.loadLeaderboard();
    tbody.innerHTML = '';
    board.forEach((entry, idx) => {
      const tr = document.createElement('tr');
      tr.className = `top-${idx + 1}`;
      tr.innerHTML = `
        <td>#${idx + 1}</td>
        <td><strong>${entry.name}</strong></td>
        <td>${entry.score.toLocaleString()}</td>
        <td>LVL ${entry.level}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  checkHighScoreQualify() {
    if (this.score <= 0) return false;
    const board = this.loadLeaderboard();
    return board.length < 5 || this.score > board[board.length - 1].score;
  }

  submitHighScore(name) {
    const cleanName = (name || 'AAA').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 3).padEnd(3, 'A');
    const board = this.loadLeaderboard();
    board.push({ name: cleanName, score: this.score, level: this.level });
    board.sort((a, b) => b.score - a.score);
    const trimmed = board.slice(0, 5);
    this.saveLeaderboard(trimmed);
    this.highScore = trimmed[0].score;
    localStorage.setItem('qix_high_score', this.highScore.toString());
    this.renderLeaderboard();
    this.updateHUD();
  }

  // ==========================================
  // FLOATING SCORE POPUPS
  // ==========================================
  spawnFloatingScore(text, gx, gy, color = '#ffea00') {
    this.floatingScores.push({
      text,
      x: this.offsetX + gx * this.scaleX,
      y: this.offsetY + gy * this.scaleY,
      color,
      life: 1.2,
      maxLife: 1.2
    });
  }

  // ==========================================
  // GAMEPAD API POLLING (R36S / PortMaster WebX)
  // ==========================================
  pollGamepad() {
    if (typeof navigator === 'undefined' || !navigator.getGamepads) return;
    const gamepads = navigator.getGamepads();
    if (!gamepads) return;

    let gp = null;
    for (let i = 0; i < gamepads.length; i++) {
      if (gamepads[i] && gamepads[i].connected) {
        gp = gamepads[i];
        break;
      }
    }
    if (!gp) return;

    const isBtnPressed = (index) => {
      const b = gp.buttons && gp.buttons[index];
      return b ? (typeof b === 'object' ? b.pressed : b > 0.5) : false;
    };

    // Hardware Audio & Fullscreen Unlock on first physical button press
    if (!this.hardwareUnlocked) {
      let anyBtn = false;
      if (gp.buttons) {
        for (let i = 0; i < gp.buttons.length; i++) {
          if (isBtnPressed(i)) {
            anyBtn = true;
            break;
          }
        }
      }
      if (anyBtn) {
        this.hardwareUnlocked = true;
        if (window.soundEngine) {
          window.soundEngine.unlockAudio();
        }
        if (!document.fullscreenElement && document.documentElement.requestFullscreen) {
          document.documentElement.requestFullscreen().catch(() => {});
        }
      }
    }

    // Edge-triggered button detection (single press per actuation)
    const justPressed = (btnIndex) => {
      const pressed = isBtnPressed(btnIndex);
      const was = !!this.prevGamepadButtons[btnIndex];
      return pressed && !was;
    };

    // R36S PortMaster Standard Mapping:
    // Axes: 0 (X), 1 (Y) with deadzone 0.25
    // Buttons:
    // 0: A (Fast Draw / Confirm)
    // 1: B (Slow Draw / Cancel)
    // 2: X, 3: Y
    // 8: Select (Audio Mute Toggle)
    // 9: Start (Pause / Start Game / Advance)
    // 12: D-Pad Up, 13: D-Pad Down, 14: D-Pad Left, 15: D-Pad Right

    const axisX = gp.axes && gp.axes.length > 0 ? gp.axes[0] : 0;
    const axisY = gp.axes && gp.axes.length > 1 ? gp.axes[1] : 0;
    const deadzone = 0.25;

    const dpadUp = isBtnPressed(12) || axisY < -deadzone;
    const dpadDown = isBtnPressed(13) || axisY > deadzone;
    const dpadLeft = isBtnPressed(14) || axisX < -deadzone;
    const dpadRight = isBtnPressed(15) || axisX > deadzone;

    const btnA = isBtnPressed(0);
    const btnB = isBtnPressed(1);
    const btnStart = isBtnPressed(9);
    const btnSelect = isBtnPressed(8);

    // Map to keysDown states for transparent integration (merging gamepad with keyboard)
    if (dpadUp) this.keysDown['ArrowUp'] = true;
    if (dpadDown) this.keysDown['ArrowDown'] = true;
    if (dpadLeft) this.keysDown['ArrowLeft'] = true;
    if (dpadRight) this.keysDown['ArrowRight'] = true;
    if (btnA) this.keysDown['Space'] = true;
    if (btnB) this.keysDown['ShiftLeft'] = true;

    // Handle open modals (Achievements, Leaderboard, Help)
    if (this.isModalOpen()) {
      if (justPressed(1) || justPressed(9)) {
        this.closeAllModals();
        return;
      }
    }

    // Handle Start button (Start new game / Pause / Resume / Advance level)
    if (justPressed(9)) {
      if (this.state === 'TITLE' || this.state === 'GAME_OVER') {
        this.startNewGame();
      } else if (this.state === 'PLAYING' || this.state === 'PAUSED') {
        this.togglePause();
      } else if (this.state === 'LEVEL_CLEAR' && this.canAdvanceLevel) {
        this.advanceNextLevel();
      }
    }

    // Handle Select button (Toggle audio mute)
    if (justPressed(8)) {
      if (window.soundEngine) {
        const isMuted = window.soundEngine.toggleMute();
        this.updateAudioButton(isMuted);
      }
    }

    // Handle PAUSED state menu navigation via Gamepad D-pad & buttons
    if (this.state === 'PAUSED' && !this.isModalOpen()) {
      if (justPressed(12) || (axisY < -0.6 && !this.prevGamepadButtons['axisYUp'])) {
        this.setPauseFocus(this.pauseFocusIndex - 1);
      } else if (justPressed(13) || (axisY > 0.6 && !this.prevGamepadButtons['axisYDown'])) {
        this.setPauseFocus(this.pauseFocusIndex + 1);
      }

      if (justPressed(14) || (axisX < -0.6 && !this.prevGamepadButtons['axisXLeft'])) {
        this.handlePauseLeftRight(-1);
      } else if (justPressed(15) || (axisX > 0.6 && !this.prevGamepadButtons['axisXRight'])) {
        this.handlePauseLeftRight(1);
      }

      if (justPressed(0)) {
        this.activatePauseFocusedItem();
      } else if (justPressed(1)) {
        this.togglePause();
      }
    }

    // Handle Title Screen & Game Over with A or Start
    if (this.state === 'TITLE') {
      if (justPressed(14) || (axisX < -0.6 && !this.prevGamepadButtons['axisXLeft'])) {
        this.cycleTitleDifficulty(-1);
      } else if (justPressed(15) || (axisX > 0.6 && !this.prevGamepadButtons['axisXRight'])) {
        this.cycleTitleDifficulty(1);
      }
      if (justPressed(0)) {
        this.startNewGame();
      }
    } else if (this.state === 'GAME_OVER') {
      if (justPressed(0)) {
        this.startNewGame();
      }
    }

    // Handle Level Clear advance with A or B button
    if (this.state === 'LEVEL_CLEAR' && this.canAdvanceLevel) {
      if (justPressed(0) || justPressed(1)) {
        this.advanceNextLevel();
      }
    }

    // Handle Initials Entry via Gamepad D-pad & A/B buttons
    const initialsOverlay = document.getElementById('initials-entry-overlay');
    if (initialsOverlay && !initialsOverlay.classList.contains('hidden')) {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!? ';
      let currChar = this.initialsChars[this.initialsIndex] || 'A';
      let charIdx = chars.indexOf(currChar);
      if (charIdx === -1) charIdx = 0;

      if (justPressed(12) || (axisY < -0.6 && !this.prevGamepadButtons['axisYUp'])) {
        // Up: Cycle previous character
        charIdx = (charIdx - 1 + chars.length) % chars.length;
        this.initialsChars[this.initialsIndex] = chars[charIdx];
        this.syncInitialsInput();
      } else if (justPressed(13) || (axisY > 0.6 && !this.prevGamepadButtons['axisYDown'])) {
        // Down: Cycle next character
        charIdx = (charIdx + 1) % chars.length;
        this.initialsChars[this.initialsIndex] = chars[charIdx];
        this.syncInitialsInput();
      }

      if (justPressed(14) || (axisX < -0.6 && !this.prevGamepadButtons['axisXLeft'])) {
        // Left: Move to previous letter slot
        this.initialsIndex = Math.max(0, this.initialsIndex - 1);
      } else if (justPressed(15) || (axisX > 0.6 && !this.prevGamepadButtons['axisXRight'])) {
        // Right: Move to next letter slot
        this.initialsIndex = Math.min(2, this.initialsIndex + 1);
      }

      if (justPressed(0)) {
        // A Button: Confirm slot or submit record
        if (this.initialsIndex < 2) {
          this.initialsIndex++;
        } else {
          const finalName = this.initialsChars.join('');
          this.submitHighScore(finalName);
          initialsOverlay.classList.add('hidden');
          const lbOverlay = document.getElementById('leaderboard-overlay');
          if (lbOverlay) lbOverlay.classList.remove('hidden');
        }
      } else if (justPressed(1)) {
        // B Button: Backtrack slot
        this.initialsIndex = Math.max(0, this.initialsIndex - 1);
      }
    }

    // Cache analog stick directional states for discrete menu navigation
    this.prevGamepadButtons['axisYUp'] = axisY < -0.6;
    this.prevGamepadButtons['axisYDown'] = axisY > 0.6;
    this.prevGamepadButtons['axisXLeft'] = axisX < -0.6;
    this.prevGamepadButtons['axisXRight'] = axisX > 0.6;

    // Cache current button states for next frame
    if (gp.buttons) {
      for (let i = 0; i < gp.buttons.length; i++) {
        this.prevGamepadButtons[i] = isBtnPressed(i);
      }
    }
  }

  syncInitialsInput() {
    const input = document.getElementById('initials-input');
    if (input) {
      input.value = this.initialsChars.join('');
    }
  }
}

// Instantiate game upon window load
window.addEventListener('DOMContentLoaded', () => {
  window.qixGame = new QixGame();
  window.game = window.qixGame;
});
