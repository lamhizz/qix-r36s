# QIX - Classic 1981 Arcade Game

A faithful, modern web recreation of the seminal 1981 Taito arcade classic **QIX**, featuring authentic multi-line vector physics, dual drawing speeds, the sizzling Fuse, patrolling Sparx and Super Sparx, dual Qix splitting on Level 3+, procedural 8-bit Web Audio sound effects, and a neon arcade cabinet presentation with toggleable CRT scanlines.

## How to Run

To run the game locally:

```bash
# Using Python 3 built-in HTTP server:
python3 -m http.server 3000

# Or using Node.js:
npx serve .
```

Then open [http://localhost:3000](http://localhost:3000) in your web browser.

## Controls

- **Movement**: Arrow Keys or `W`, `A`, `S`, `D`
- **Fast Draw**: `Space` or `J` (faster movement, cyan trail, normal points)
- **Slow Draw**: `Shift` or `K` (half speed, red/orange trail, **DOUBLE POINTS**)
- **Pause**: `P`
- **Toggle Sound**: `M`
- **Touch / Mobile**: Use the on-screen virtual D-pad, swipe gestures, and `FAST` / `SLOW` buttons
- **Install as PWA**: Tap the **📲 INSTALL** button in the header (or "Add to Home Screen" on iOS Safari / Chrome) to install QIX as a native offline app.

## Progressive Web App (PWA)

QIX is a full Progressive Web App:
- **Offline Support**: The Service Worker pre-caches all core gameplay engines, retro procedural sounds, icons, screenshots, and default level art so you can play anywhere without an internet connection.
- **Installable**: Install directly on iOS, Android, macOS, Windows, and ChromeOS as a standalone, distraction-free arcade cabinet. Supports Chrome rich install dialogs with high-definition gameplay screenshots.
- **App Shortcuts**: Quick launch actions from your home screen or dock directly into "Start New Game" or "High Scores".
- **Arcade Offline Indicator**: Automatic real-time detection and retro HUD toast notifications for offline and reconnected states.
- **Mobile First**: Features high-resolution adaptive app icons (192px, 512px, maskable, SVG), iOS install walkthrough modal, and safe-area inset adaptation for edge-to-edge screens.

## Game Rules

1. **Objective**: Claim the required percentage of the playfield (starts at **65%** on Level 1 and scales up to **80%** on master levels) to clear each stage.
2. **Hidden Background Artwork**: Each level loads a random background image from the `level-images/` directory. As you enclose territory, the captured areas **uncover and reveal the hidden background art**! Clearing the level reveals the full image in celebration.
3. **Adding Custom Images**: Drop any `.jpg`, `.jpeg`, or `.png` files into the `level-images/` folder and add their filename to `level-images/manifest.json`.
4. **The Qix**: The chaotic multi-line vector entity bounces unpredictably. You are safe on borders, but if the Qix hits you or your uncompleted Stix line, you lose a life.
5. **The Fuse**: If you pause while drawing a Stix, warning sparks ignite at 0.4s. If you remain idle past 0.75s, a burning fuse sparks at the origin and crawls along your line toward you! Resume moving to survive.
6. **Sparx & Super Sparx**: Sparx patrol active borders. Level 1 starts with 1 Sparx and a generous 45s timer; higher levels increase pressure. When the countdown timer expires, an extra Sparx enters and all Sparx mutate into **Super Sparx**, which can pursue you down uncompleted Stix lines!
7. **Secret Dual Qix Split (Level 3+)**: Two Qixes roam the field. If you draw a line separating the two Qixes into isolated compartments, the level is immediately cleared with a permanent **Score Multiplier** (up to 9x)!
8. **Bold Cut Multipliers**: Slow Draw awards double points, and bold cuts enclosing 10%+ or 20%+ of the board award special **2x and 3x Combo Multipliers**!
9. **Milestone Extra Lives**: Bonus lives are awarded at 50,000 pts, 125,000 pts, and for achieving 90%+ territory claims.
