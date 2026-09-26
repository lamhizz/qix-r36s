# Refactoring Plan: Qix PWA to R36S PortMaster

## Objective
Migrate the existing responsive HTML5/JS Qix web game to a native-feeling R36S PortMaster game (via WebX), strictly adhering to hardware constraints (640x480, Gamepad API) while fully preserving the original visual aesthetics, game logic, and Qix territory-claiming mechanics.

## Phase 1: Environment & Dependency Pruning
* **Task 1.1:** Delete `sw.js`, `manifest.json`, `tools/update-manifest.js`, and the `icons/` directory.
* **Task 1.2:** Cleanse `index.html`. Remove all `<meta name="viewport">` tags, service worker registration scripts, and web-app manifest links. 
* **Task 1.3:** Ensure all external CDN links (if any, for fonts or libraries) are downloaded locally, as the R36S may run completely offline.

## Phase 2: Visuals & Resolution Lock (Preserving Original Look)
* **Task 2.1:** Strip responsive CSS. Remove `width: 100vw`, `height: 100vh`, and any `@media` queries from `css/style.css`.
* **Task 2.2:** Hardcode the `<canvas>` element in HTML and JS to exactly `width: 640px` and `height: 480px`. 
* **Task 2.3:** Update `js/grid.js` and `js/game.js` rendering logic. Calculate the Qix grid scale to maximize the 640x480 space while preserving the original aspect ratio (e.g., if the original grid is square, render it at 480x480 and center it horizontally with a black/themed margin).
* **Task 2.4:** Ensure original colors, line thickness, enemy (Sparx/Qix) sprites/shapes, and fill aesthetics remain completely untouched.

## Phase 3: Input Migration (Gamepad API)
* **Task 3.1:** Locate and remove all `window.addEventListener` calls for `keydown`, `keyup`, and touch events in `js/player.js` and `js/game.js`.
* **Task 3.2:** Implement a `navigator.getGamepads()` polling function at the start of the `requestAnimationFrame` loop.
* **Task 3.3:** Map D-Pad (Axes 0/1 or Buttons 12-15) to player X/Y movement. Apply a slight deadzone (e.g., `> 0.2`) if interpreting analog axes as D-Pad inputs.
* **Task 3.4:** Map Gamepad Button 0 (A) to the primary action (e.g., Fast Draw). Map Gamepad Button 1 (B) to the secondary action (e.g., Slow Draw).

## Phase 4: Audio Context Hardware Unlock
* **Task 4.1:** Refactor `js/audio.js`. Remove any `DOMContentLoaded` or click-based audio initializations.
* **Task 4.2:** Create an `audioUnlocked` boolean flag. In the Gamepad polling loop, if a button press is detected and `!audioUnlocked`, initialize/resume the Web `AudioContext`.
* **Task 4.3:** Verify that all original sound effects (drawing, enemy collision, level complete) still fire at the correct game state triggers.

## Phase 5: Storage & Performance Optimization
* **Task 5.1:** Verify `js/progression.js` uses standard synchronous `localStorage` for high scores and level unlocks.
* **Task 5.2:** Audit the `requestAnimationFrame` loop in `js/game.js` to ensure no massive arrays or objects are being instantiated every frame, preventing garbage collection stutter on the 1GB RAM hardware.