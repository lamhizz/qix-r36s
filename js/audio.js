/**
 * Qix Arcade Audio Synthesizer
 * Procedural Web Audio API sound effects recreating 1981 arcade acoustics.
 */
class SoundEngine {
  constructor() {
    this.ctx = null;
    this.isMuted = false;
    this.masterVolume = 0.6;
    this.masterGain = null;

    // Continuous sound handles
    this.drawOsc = null;
    this.drawGain = null;
    this.fuseNode = null;
    this.fuseGain = null;
    this.qixOsc = null;
    this.qixGain = null;

    this.initialized = false;
  }

  init() {
    if (this.initialized) return;
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      this.ctx = new AudioContext();
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.setValueAtTime(this.masterVolume, this.ctx.currentTime);
      this.masterGain.connect(this.ctx.destination);
      this.initialized = true;
    } catch (e) {
      console.warn('Web Audio API not supported or blocked:', e);
    }
  }

  ensureContext() {
    if (!this.initialized) {
      this.init();
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  setMuted(muted) {
    this.isMuted = muted;
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setValueAtTime(muted ? 0 : this.masterVolume, this.ctx.currentTime);
    }
  }

  toggleMute() {
    this.setMuted(!this.isMuted);
    return this.isMuted;
  }

  setVolume(val) {
    this.masterVolume = Math.max(0, Math.min(1, val));
    if (this.masterGain && this.ctx && !this.isMuted) {
      this.masterGain.gain.setValueAtTime(this.masterVolume, this.ctx.currentTime);
    }
  }

  // Border movement tick
  playTick() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(800, this.ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(300, this.ctx.currentTime + 0.03);

    gain.gain.setValueAtTime(0.08, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + 0.03);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start();
    osc.stop(this.ctx.currentTime + 0.035);
  }

  // Continuous sound when drawing Stix
  startDraw(isSlow = false) {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx || this.drawOsc) return;

    this.drawOsc = this.ctx.createOscillator();
    this.drawGain = this.ctx.createGain();

    if (isSlow) {
      // Slow draw: deeper pulsing square wave (double value/tension)
      this.drawOsc.type = 'square';
      this.drawOsc.frequency.setValueAtTime(110, this.ctx.currentTime);
      this.drawGain.gain.setValueAtTime(0.12, this.ctx.currentTime);
    } else {
      // Fast draw: higher pitched buzz
      this.drawOsc.type = 'sawtooth';
      this.drawOsc.frequency.setValueAtTime(240, this.ctx.currentTime);
      this.drawGain.gain.setValueAtTime(0.09, this.ctx.currentTime);
    }

    this.drawOsc.connect(this.drawGain);
    this.drawGain.connect(this.masterGain);
    this.drawOsc.start();
  }

  stopDraw() {
    if (this.drawOsc) {
      try {
        const t = this.ctx.currentTime;
        this.drawGain.gain.linearRampToValueAtTime(0.001, t + 0.04);
        this.drawOsc.stop(t + 0.05);
      } catch (e) {}
      this.drawOsc = null;
      this.drawGain = null;
    }
  }

  // Sizzling noise for idle fuse
  startFuse() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx || this.fuseNode) return;

    const bufferSize = this.ctx.sampleRate * 1;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      // Sputtering crackle noise
      data[i] = (Math.random() * 2 - 1) * (Math.random() > 0.4 ? 1 : 0.2);
    }

    this.fuseNode = this.ctx.createBufferSource();
    this.fuseNode.buffer = buffer;
    this.fuseNode.loop = true;

    const filter = this.ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(3200, this.ctx.currentTime);
    filter.Q.setValueAtTime(4.0, this.ctx.currentTime);

    this.fuseGain = this.ctx.createGain();
    this.fuseGain.gain.setValueAtTime(0.18, this.ctx.currentTime);

    this.fuseNode.connect(filter);
    filter.connect(this.fuseGain);
    this.fuseGain.connect(this.masterGain);

    this.fuseNode.start();
  }

  stopFuse() {
    if (this.fuseNode) {
      try {
        this.fuseNode.stop();
        this.fuseNode.disconnect();
      } catch (e) {}
      this.fuseNode = null;
      this.fuseGain = null;
    }
  }

  // Triumphant capture arpeggio
  playCapture(isSlow = false) {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const baseNotes = isSlow ? [220, 277.18, 329.63, 440, 554.37, 659.25] : [330, 392, 493.88, 587.33, 659.25];
    const now = this.ctx.currentTime;

    baseNotes.forEach((freq, idx) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = isSlow ? 'square' : 'triangle';
      osc.frequency.setValueAtTime(freq, now + idx * 0.04);

      gain.gain.setValueAtTime(0.14, now + idx * 0.04);
      gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.04 + 0.18);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(now + idx * 0.04);
      osc.stop(now + idx * 0.04 + 0.2);
    });
  }

  // Dual Qix Split Fanfare
  playSplit() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const notes = [440, 554.37, 659.25, 880, 1108.73, 1318.51, 1760];
    const now = this.ctx.currentTime;

    notes.forEach((freq, idx) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(freq, now + idx * 0.06);

      gain.gain.setValueAtTime(0.18, now + idx * 0.06);
      gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.06 + 0.35);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(now + idx * 0.06);
      osc.stop(now + idx * 0.06 + 0.38);
    });
  }

  // Player explosion / death
  playDeath() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    this.stopDraw();
    this.stopFuse();

    const now = this.ctx.currentTime;
    const dur = 0.6;
    const bufferSize = this.ctx.sampleRate * dur;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = Math.random() * 2 - 1;
    }

    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;

    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(1200, now);
    filter.frequency.exponentialRampToValueAtTime(60, now + dur);

    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(0.3, now);
    gain.gain.linearRampToValueAtTime(0.001, now + dur);

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.masterGain);

    noise.start(now);
    noise.stop(now + dur);
  }

  // Level Clear Fanfare
  playLevelClear() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const now = this.ctx.currentTime;
    const melody = [
      { f: 523.25, d: 0.1 },
      { f: 659.25, d: 0.1 },
      { f: 783.99, d: 0.1 },
      { f: 1046.50, d: 0.28 },
      { f: 880.00, d: 0.1 },
      { f: 1046.50, d: 0.4 }
    ];

    let t = now;
    melody.forEach(n => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'square';
      osc.frequency.setValueAtTime(n.f, t);

      gain.gain.setValueAtTime(0.15, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + n.d);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(t);
      osc.stop(t + n.d);
      t += n.d * 1.08;
    });
  }

  // Super Sparx warning alert
  playSuperSparxAlert() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'sawtooth';

    osc.frequency.setValueAtTime(880, now);
    osc.frequency.linearRampToValueAtTime(440, now + 0.12);
    osc.frequency.setValueAtTime(880, now + 0.15);
    osc.frequency.linearRampToValueAtTime(440, now + 0.27);

    gain.gain.setValueAtTime(0.2, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start(now);
    osc.stop(now + 0.36);
  }

  // Game over sound
  playGameOver() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const now = this.ctx.currentTime;
    const notes = [440, 415.30, 392, 349.23, 311.13, 261.63];
    notes.forEach((freq, idx) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(freq, now + idx * 0.16);

      gain.gain.setValueAtTime(0.16, now + idx * 0.16);
      gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.16 + 0.22);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(now + idx * 0.16);
      osc.stop(now + idx * 0.16 + 0.25);
    });
  }

  // Achievement unlock fanfare
  playAchievement() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const now = this.ctx.currentTime;
    const notes = [523.25, 659.25, 783.99, 1046.50]; // C5, E5, G5, C6
    notes.forEach((freq, idx) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'square';
      osc.frequency.setValueAtTime(freq, now + idx * 0.1);

      gain.gain.setValueAtTime(0.18, now + idx * 0.1);
      gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.1 + 0.28);

      osc.connect(gain);
      gain.connect(this.masterGain);

      osc.start(now + idx * 0.1);
      osc.stop(now + idx * 0.1 + 0.3);
    });
  }

  // Target threshold near alert pulse
  playTargetNear() {
    if (this.isMuted) return;
    this.ensureContext();
    if (!this.ctx) return;

    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(587.33, now); // D5
    osc.frequency.linearRampToValueAtTime(880, now + 0.12);

    gain.gain.setValueAtTime(0.12, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.18);

    osc.connect(gain);
    gain.connect(this.masterGain);

    osc.start(now);
    osc.stop(now + 0.2);
  }
}

window.soundEngine = new SoundEngine();
