/**
 * QIX Arcade Game - Security Clearance Manager
 * Cryptographic SHA-256 authentication gate & lock screen terminal.
 * Prevents unauthorized access and locks arcade gameplay.
 */

(function () {
  const SALT = 'qix-cyber-salt-1981';
  // Default Master Pass: "QIX1981"
  const DEFAULT_HASH = '70f0b794202bad43ddc7c3067913c568e99c5e73dfd3b953fca7b2b5da7ca366';
  const MAX_ATTEMPTS = 5;
  const LOCKOUT_MS = 30000;

  class SecurityManager {
    constructor() {
      this.authorized = false;
      this.failedAttempts = 0;
      this.lockoutUntil = 0;
      this.lockoutTimer = null;
      this.currentInput = '';

      this.checkExistingAuth();
    }

    // SHA-256 computation via Web Crypto API
    async computeHash(text) {
      const msg = `${SALT}:${text.trim().toUpperCase()}`;
      const encoder = new TextEncoder();
      const data = encoder.encode(msg);
      const hashBuf = await crypto.subtle.digest('SHA-256', data);
      const hashArr = Array.from(new Uint8Array(hashBuf));
      return hashArr.map(b => b.toString(16).padStart(2, '0')).join('');
    }

    getTargetHash() {
      return localStorage.getItem('qix_custom_pass_hash') || DEFAULT_HASH;
    }

    checkExistingAuth() {
      const sessionToken = sessionStorage.getItem('qix_auth_token');
      const persistentToken = localStorage.getItem('qix_auth_remember');

      if (sessionToken === 'GRANTED' || persistentToken === 'GRANTED') {
        this.authorized = true;
      } else {
        this.authorized = false;
      }
    }

    isAuthorized() {
      return this.authorized;
    }

    async verifyPasscode(passcode, remember = false) {
      // Check lockout status
      const now = Date.now();
      if (this.lockoutUntil > now) {
        const remainingSec = Math.ceil((this.lockoutUntil - now) / 1000);
        return { success: false, reason: 'LOCKOUT', remainingSec };
      }

      if (!passcode || passcode.trim().length === 0) {
        return { success: false, reason: 'EMPTY' };
      }

      const inputHash = await this.computeHash(passcode);
      const targetHash = this.getTargetHash();

      if (inputHash === targetHash) {
        this.authorized = true;
        this.failedAttempts = 0;
        this.lockoutUntil = 0;

        sessionStorage.setItem('qix_auth_token', 'GRANTED');
        if (remember) {
          localStorage.setItem('qix_auth_remember', 'GRANTED');
        } else {
          localStorage.removeItem('qix_auth_remember');
        }

        window.dispatchEvent(new CustomEvent('qix-unlocked'));
        return { success: true };
      } else {
        this.failedAttempts++;
        if (this.failedAttempts >= MAX_ATTEMPTS) {
          this.lockoutUntil = Date.now() + LOCKOUT_MS;
          return { success: false, reason: 'MAX_ATTEMPTS', remainingSec: Math.ceil(LOCKOUT_MS / 1000) };
        }
        return { success: false, reason: 'INVALID', attemptsLeft: MAX_ATTEMPTS - this.failedAttempts };
      }
    }

    async changePasscode(currentPass, newPass) {
      if (!this.authorized) return { success: false, error: 'Unauthorized' };
      if (!newPass || newPass.trim().length < 4) {
        return { success: false, error: 'Passcode must be at least 4 characters.' };
      }

      const currentHash = await this.computeHash(currentPass);
      if (currentHash !== this.getTargetHash()) {
        return { success: false, error: 'Current passcode is incorrect.' };
      }

      const newHash = await this.computeHash(newPass);
      localStorage.setItem('qix_custom_pass_hash', newHash);
      return { success: true };
    }

    resetToDefaultPasscode(currentPass) {
      return this.changePasscode(currentPass, 'QIX1981');
    }

    lock() {
      this.authorized = false;
      sessionStorage.removeItem('qix_auth_token');
      localStorage.removeItem('qix_auth_remember');
      this.currentInput = '';

      window.dispatchEvent(new CustomEvent('qix-locked'));
    }

    // Synthesize retro cyber sounds for lock screen
    playAudioFeedback(type) {
      try {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (!AudioContext) return;
        const ctx = new AudioContext();

        if (type === 'key') {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(800, ctx.currentTime);
          osc.frequency.exponentialRampToValueAtTime(400, ctx.currentTime + 0.05);
          gain.gain.setValueAtTime(0.1, ctx.currentTime);
          gain.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.05);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start();
          osc.stop(ctx.currentTime + 0.05);
        } else if (type === 'denied') {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sawtooth';
          osc.frequency.setValueAtTime(140, ctx.currentTime);
          osc.frequency.linearRampToValueAtTime(90, ctx.currentTime + 0.25);
          gain.gain.setValueAtTime(0.2, ctx.currentTime);
          gain.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.25);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start();
          osc.stop(ctx.currentTime + 0.25);
        } else if (type === 'granted') {
          [523.25, 659.25, 783.99, 1046.50].forEach((freq, i) => {
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();
            osc.type = 'triangle';
            osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.07);
            gain.gain.setValueAtTime(0.15, ctx.currentTime + i * 0.07);
            gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + i * 0.07 + 0.2);
            osc.connect(gain);
            gain.connect(ctx.destination);
            osc.start(ctx.currentTime + i * 0.07);
            osc.stop(ctx.currentTime + i * 0.07 + 0.2);
          });
        }
      } catch (e) {
        // AudioContext not allowed before user gesture
      }
    }
  }

  window.SecurityManager = new SecurityManager();
})();
