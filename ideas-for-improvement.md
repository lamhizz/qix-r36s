# QIX (R36S Handheld) — Master Roadmap & Feature Specification

This document serves as the **definitive master roadmap** for QIX on the R36S handheld console (PortMaster / LÖVE 2D). It consolidates all gameplay mechanics, design ideas, and user experience enhancements into one unified reference.

Each item is classified by status:
- **`[IMPLEMENTED]`** — Fully coded, tested, and active in the current release. Each implemented feature includes a **quote markup block** detailing exactly what is built in the game so you can compare the original idea against the current implementation.
- **`[PENDING]`** — Detailed feature proposal ready for future development, explained in descriptive, non-technical terms.

---

## 1. Gameplay & Difficulty Balance

### 1.1 Difficulty Presets (Casual, Arcade, Master) — `[IMPLEMENTED]`
- **Concept & Vision:** In the web prototype, players could choose between three distinct play feelings instead of one fixed challenge, letting newcomers enjoy artwork reveals while offering arcade purists high tension.
> **What Is Exactly Implemented in the Game:**
> - **Three Selectable Presets:**
>   - **`CASUAL`:** 4 starting lives, starting goal of 55% (+2% per level, capped at 70%), 0.82X enemy speed multiplier, 3.5-second post-respawn invulnerability shield, 0.90s fuse hesitation delay (32 px/s burn rate), and a relaxed 36s Super Sparx countdown timer.
>   - **`ARCADE` (Default):** 3 lives, starting goal of 65% (+3% per level, capped at 80%), 1.00X enemy speed multiplier, 2.5s post-respawn shield, 0.65s fuse delay (42 px/s burn rate), and 26s Super Sparx timer.
>   - **`MASTER`:** 2 lives, starting goal of 75% (+3% per level, capped at 88%), 1.22X enemy speed multiplier, 1.5s post-respawn shield, razor-thin 0.35s fuse delay (56 px/s burn rate), and 16s Super Sparx timer.
> - **Controls & Persistence:** Difficulty can be changed directly on the Title Screen with D-Pad `◄ / ►` or inside the Pause Menu (`DIFFICULTY` row). The selected preset automatically saves to `settings.txt` and is remembered across reboots.

### 1.2 The Classic "Split-Qix" Score Multiplier (Level 3+) — `[IMPLEMENTED]`
- **Concept & Vision:** Authentic 1981 Taito arcade rule where slicing cleanly between dual roaming Qixes immediately awards an escalating score multiplier (2X–9X) for all future points in that run.
> **What Is Exactly Implemented in the Game:**
> - **Dual Qix Spawning:** Beginning on Level 3, two independent Qix entities spawn simultaneously at slightly different speeds and trajectories.
> - **Compartment Partition Detection:** When the player closes a Stix loop, `grid.lua` calculates whether Qix #1 and Qix #2 are isolated into separate empty compartments.
> - **Victory & Multiplier Reward:** If split, the game awards an immediate bonus of `+25,000 pts × multiplier`, increments the permanent run score multiplier by +1 (capped at 9X), unlocks the `DIVIDE & CONQUER` medal, displays the banner `★ SPLIT-QIX! [X]X MULTIPLIER UNLOCKED! ★`, and instantly completes the round. The multiplier stays active for subsequent levels until game over.

### 1.3 In-Field Tactical Power Crystals (Level 4+) — `[IMPLEMENTED]`
- **Concept & Vision:** Progressive risk-vs-reward mechanic introducing collectible energy gems in unclaimed territory on higher sectors.
> **What Is Exactly Implemented in the Game:**
> - **Dynamic Spawning:** Starting at Level 4, tactical floating crystals spawn in random safe cells inside unclaimed space (1 crystal on Level 4; 2 crystals per level on Level 5+).
> - **Three Distinct Gem Perks:**
>   - ❄ **`CHRONO FREEZE` (Cyan):** Freezes Qixes and Sparx completely in place for **4.5 seconds** (disabling collisions and movement) while allowing the player to cut freely.
>   - ★ **`STAR CACHE` (Gold):** Awards an immediate **+5,000 bonus points** multiplied by the active run score multiplier.
>   - 🛡 **`SHIELD MATRIX` (Green):** Grants **+1 extra life** (capped at 6) and refreshes a **5.0-second invulnerability shield barrier**.
> - **Enclosure Trigger:** Crystals are collected automatically when the player's completed polygon captures the territory containing the gem's coordinate, accompanied by spark particles and a celebration banner.

### 1.4 "Danger Close" Proximity Threat Warning — `[PENDING]`
- **The Problem:** In fast-paced moments, players can misjudge the Qix's irregular trajectory and get ambushed right as they are about to complete a large polygon.
- **The Player Experience:** When the roving Qix helix crosses within a critical danger perimeter (e.g., within 35 pixels of the player's active cutting head), the game provides clear, intuitive cues:
  - A subtle pulsating red vignette glows at the screen borders.
  - The active cutting line hums and vibrates with brighter sparks.
  - A rapid warning audio ping triggers, giving players an instinctual split-second cue to either close the loop immediately or retreat.
- **Implementation Scope:** Requires a lightweight distance check between the player's current position and each Qix coordinate during active drawing mode, with a simple screen-edge red alpha overlay in `main.lua`.
- **Value & Priority:** **High Value / Low Effort.** Greatly reduces accidental "cheap deaths" and heightens arcade tension.

### 1.5 Continue / Checkpoint System — `[PENDING]`
- **The Problem:** Reaching higher sectors (Level 4–6+) requires intense focus. A sudden game over forces players all the way back to Level 1, which can feel punishing during short handheld sessions.
- **The Player Experience:** Upon losing all lives on Level 2 or higher, the player is presented with a classic arcade countdown screen: **"CONTINUE? 9... 8... 7..."**
  - Pressing **(A)** resumes the game at the start of the current sector with a reset score (or score penalty) and a fresh stock of lives.
  - Players can use up to **1 Continue per game** (or unlimited in Casual difficulty), allowing casual players to see all hidden backgrounds while keeping high-score runs authentic and competitive.
- **Implementation Scope:** Add a `CONTINUE` state between `DEAD` and `GAME_OVER` with a 10-second timer, resetting lives and keeping the current level number while marking `score = 0` or preserving it as a separate "Cleared with Continues" stat.
- **Value & Priority:** **Medium Value / Low Effort.** Ideal for handheld gamers on the go.

---

## 2. Visuals, Themes & Aesthetics

### 2.1 Dynamic Background Art & Foreground Skins — `[IMPLEMENTED]`
- **Concept & Vision:** Revealing hidden images as territory is claimed, with custom skinning for uncarved territory and full artwork showcases.
> **What Is Exactly Implemented in the Game:**
> - **Dual Directory Photo Discovery:** `scanArtDeck()` scans both the `art_original/` folder (master high-resolution photos) and `art/` from the physical SD card / PortMaster directory, plus bundled game art.
> - **Non-Repeating Randomization:** At every round start (independent of level number), a photo is picked randomly from the pool. If 2 or more photos exist, the game prevents the exact same photo from appearing two rounds in a row.
> - **FIT-Mode Unobstructed Showcase:** Clearing a level initiates a two-phase sequence: a brief scores summary card, followed by a pristine, 100% full-screen unobstructed photo view with aspect-ratio letterboxing (never cropped or distorted) that holds until pressing **(A)**.
> - **Custom Circuit Board Skinning:** `scanForegroundDeck()` loads custom PCB circuit textures from `foreground-art/` and maps them onto the unclaimed foreground mask.

### 2.2 Arcade Cabinet Visual Themes (Phosphor Color Modes) — `[PENDING]`
- **The Problem:** While the default "Neon Classic" cyan/magenta look is iconic, playing late at night or in different lighting environments benefits from customized contrast and color temperatures.
- **The Player Experience:** Players can toggle the entire cabinet visual color scheme on the fly from the Pause Menu:
  1. **Neon Classic (Default):** Vibrant cyan borders, electric pink/magenta Qix helix, deep midnight blue backdrop.
  2. **Amber CRT Terminal:** Warm 1980s amber monochrome glow (warm orange grid lines, golden territory cuts, soft amber sparx). Very gentle on the eyes for dark-room handheld play.
  3. **Matrix Green Phosphor:** High-contrast cybernetic green monitor look (lime green borders, emerald scanlines, bright neon green sparks).
  4. **High-Contrast Monolith:** Crisp stark white lines on solid pitch black with vivid primary colors, tailored for players with color vision deficiencies.
- **Implementation Scope:** Centralize the game's color palette table into a theme manager (or theme table in `main.lua`), allowing palette switching with instant canvas repainting and persistent saving in `settings.txt`.
- **Value & Priority:** **High Value / Medium Effort.** Significantly boosts visual variety and accessibility.

### 2.3 Boss Variations & Dynamic Hazard Evolutions — `[PENDING]`
- **The Problem:** Facing the exact same Qix behavior in every sector can become repetitive after Level 5.
- **The Player Experience:** Introduce unique sector hazard variants that appear in later rounds:
  - **The Twin Twin-Speed Qix:** Two Qixes where one moves slowly with high mass while the second is smaller and darts around unpredictably.
  - **The Phase/Cloaked Qix (Level 6+):** The Qix helix periodically fades into a faint outline for 3 seconds before glowing brightly, requiring players to track its momentum carefully.
  - **Gravity Well / Void Pockets:** Small static anomalies that bend the Qix's reflection angle when it bounces near them.
- **Implementation Scope:** Extend `qix.lua` with variant behavioral flags (speed oscillations, alpha fade intervals) activated conditionally based on `game.level`.
- **Value & Priority:** **Medium Value / Medium Effort.** Adds excitement and anticipation for advanced players.

### 2.4 Procedural Cyber Matrix Backgrounds — `[PENDING]`
- **The Problem:** If a player deletes or does not have any photo files on their SD card, the game falls back to a plain black background or cover art.
- **The Player Experience:** When no user photos are present in `art/`, the game automatically generates mesmerizing retro wireframe procedural landscapes (vector geometric grids, rotating 3D wireframe cubes, synthetic starry nebula fields) beneath the playfield that animate as you carve lines.
- **Implementation Scope:** A procedural vector backdrop generator in `grid.lua` using Love2D line rendering cached into a canvas.
- **Value & Priority:** **Low-to-Medium Priority.** Great fallback when no custom photos are provided.

---

## 3. Audio & Soundscape

### 3.1 Procedural 8-Bit Audio Synthesizer — `[IMPLEMENTED]`
- **Concept & Vision:** 100% standalone procedural sound synthesis mimicking 1981 arcade sound generators without bulky WAV/MP3 files.
> **What Is Exactly Implemented in the Game:**
> - **Procedural Sound Engine (`audio.lua`):** Uses raw Love2D `SoundData` to generate pure retro waveform sounds at runtime (square waves, triangle waves, and white noise with exponential decay envelopes).
> - **Sound Palette:**
>   - `tick`: 650Hz square-wave blip for border traversal.
>   - `start`: 440Hz triangle launch chime.
>   - `capture`: 523Hz crisp square-wave territory claim sound.
>   - `bonus`: 880Hz bright perk pickup chime.
>   - `fanfare`: 4-note ascending arpeggio (C5 -> E5 -> G5 -> C6) for high scores and level completions.
>   - `death`: Dual-layer noise and 80Hz low rumble explosion.
>   - Continuous loops for `drawSlow` (90Hz square), `drawFast` (190Hz square), and `fuse` (250Hz noise).
> - **In-Game Volume & Mute Controls:** Audio can be toggled mute or volume adjusted from 0% to 100% in 10% steps in the Pause Menu or via the physical Select/Back button.

### 3.2 Dynamic Ambient Qix Proximity Drone & Sparx Siren — `[PENDING]`
- **The Problem:** The current soundscape is primarily reactive (sounds play when actions happen), lacking a continuous ambient tension layer.
- **The Player Experience:**
  - **The Qix Proximity Drone:** A low, dark, oscillating synth hum plays in the background. As the Qix gets closer to your active cutting line, the drone subtly pitches up in frequency and volume, letting you *hear* the danger closing in without looking away from your cursor.
  - **Sparx Mutation Siren:** A distinct, urgent 3-second mechanical alarm siren sounds right before regular Sparx mutate into Super Sparx, giving clear audio notice before the perimeter is breached.
- **Implementation Scope:** Add two continuous procedural loop sources in `audio.lua` with real-time volume/pitch adjustments based on distance and countdown timers.
- **Value & Priority:** **High Value / Low Effort.** Drastically heightens immersion and retro arcade atmosphere.

---

## 4. Progression, Replayability & Modes

### 4.1 Achievements & Badges Gallery (7 Unlockable Medals) — `[IMPLEMENTED]`
- **Concept & Vision:** Long-term motivation tracking 7 milestone achievements with on-screen celebratory popups and a permanent trophy room.
> **What Is Exactly Implemented in the Game:**
> - **The 7 Unlockable Medals (`achievements.lua`):**
>   1. `[ROUND 1]` **FIRST CONTACT:** Clear Round 1 and unveil your first hidden artwork.
>   2. `[SLOW 20%]` **DEEP CUT:** Claim 20% or more of the screen in a single daring slow-draw slice.
>   3. `[SPLIT-QIX]` **DIVIDE & CONQUER:** Slice between and separate dual roaming Qixes (Level 3+).
>   4. `[100K PTS]` **CENTURY CLUB:** Achieve a score of 100,000 points or more in a single run.
>   5. `[90% CLAIM]` **MASTER ARTIST:** Uncover 90% or more of the playfield in any single round.
>   6. `[LEVEL 5]` **VETERAN SURVIVOR:** Survive the gauntlet and reach Level 5.
>   7. `[5 ARTWORKS]` **ART CONNOISSEUR:** Uncover and view 5 distinct background artworks.
> - **Live Celebratory Toasts:** When unlocked, an animated gold/cyan banner (`★ ACHIEVEMENT UNLOCKED! ★`) with sound effect fades in at the top of the screen.
> - **In-Game Badges Gallery:** Accessible directly from Title Menu (`BADGES`), rendering all 7 medals with unlocked/locked status, badge tags, progress percentage, and descriptions.
> - **Disk Persistence:** Unlocks and viewed artwork tracking automatically save to `achievements.txt` on the SD card.

### 4.2 Top-5 Arcade Leaderboard with 3-Letter Initial Entry — `[PENDING]`
- **The Problem:** The game currently tracks only a single all-time high score number without recording who achieved it or a history of top runs.
- **The Player Experience:**
  - When completing a high-scoring game that places in the top 5, the player is greeted by an authentic arcade **"ENTER YOUR INITIALS"** screen with an alphabet carousel (`A-Z`, numbers, punctuation) controlled via D-Pad (`▲/▼` selects letter, `►` advances, `(A)` confirms).
  - A **Hall of Fame Leaderboard** screen displays the Top 5 scores, rank medals (🥇, 🥈, 🥉), initials (`LDK`, `AAA`), difficulty mode, and sector reached.
  - Data is saved permanently to disk in `scores.txt`.
- **Implementation Scope:** A dedicated `leaderboard.lua` module tracking a sorted table of 5 records, an interactive letter-picker UI state, and persistent save/load logic.
- **Value & Priority:** **High Value / Medium Effort.** Essential for arcade authenticity and passing the handheld between friends.

### 4.3 Alternate Game Modes (Time Attack & 1-Life Survival) — `[PENDING]`
- **The Problem:** Once players master the standard arcade loop, having alternative play modes injects major replay value.
- **The Player Experience:**
  - **Speedrun / Time Attack Mode:** The goal is to clear 3 sectors as fast as humanly possible. A prominent millisecond timer counts up on HUD, and slow draws give massive time bonuses while fast draws save immediate clock time.
  - **Survival (One-Life) Gauntlet:** You start with a single life and zero shields. Can you clear 5 sectors without making a single fatal mistake? Perfect for competitive bragging rights.
- **Implementation Scope:** Add mode selection flags to `startNewGame()`, modifying victory condition timers and lives allocation.
- **Value & Priority:** **Medium Value / Medium Effort.**

### 4.4 Career Lifetime Statistics Tracker — `[PENDING]`
- **The Problem:** Players enjoy seeing their cumulative lifetime achievements over weeks and months of play.
- **The Player Experience:** A "Records & Stats" sub-screen within the Badges Gallery displaying lifetime metrics:
  - Total play sessions and total hours logged.
  - Total cumulative territory claimed (e.g. "Equivalent to 142 complete screens!").
  - Career best single cut percentage.
  - Total Sparx dodged and Split-Qix victories achieved.
- **Implementation Scope:** Simple key-value counter stored in a `stats.txt` file, updated at the end of each round and displayed in the debriefing or badges menu.
- **Value & Priority:** **Low-to-Medium Priority.**

---

## 5. Controls, User Experience & Accessibility

### 5.1 Interactive In-Game Rules Guide ("HOW TO PLAY") — `[IMPLEMENTED]`
- **Concept & Vision:** An illustrated on-device tutorial for players new to the 1981 arcade rules.
> **What Is Exactly Implemented in the Game:**
> - Accessible directly from the Title Menu by selecting **`HOW TO`**.
> - Clean modal screen explaining:
>   - **Fast Draw vs. Slow Draw:** Fast Draw (1X points) vs. Slow Draw (2X points with electric orange plasma).
>   - **The Fuse:** Warning that idling or hesitating mid-cut ignites a fuse burning along your path.
>   - **Sparx & Super Sparx:** Perimeter patrols and the mutation timer.
>   - **Split-Qix Rule:** How separating dual Qixes on Level 3+ wins the level and unlocks permanent score multipliers.

### 5.2 Full Pause Menu with On-The-Fly Settings — `[IMPLEMENTED]`
- **Concept & Vision:** Allowing players to pause anytime, adjust settings, or restart without losing their place.
> **What Is Exactly Implemented in the Game:**
> - Activated by pressing **Start** or **Escape/P** during gameplay. Stays paused until explicitly unpaused.
> - D-Pad navigation: `▲/▼` selects option row, `◄/►` adjusts setting values immediately.
> - **7 Interactive Menu Options:**
>   - `RESUME GAME`: Unpauses and resumes the action.
>   - `DIFFICULTY`: Cycles between `[ CASUAL ]`, `[ ARCADE ]`, and `[ MASTER ]` in real-time, instantly adjusting player shield and fuse timing.
>   - `CRT SCANLINES`: Toggles the authentic CRT scanline and curved corner bezel overlay ON or OFF.
>   - `AUDIO SOUND`: Toggles sound ON or MUTED.
>   - `VOLUME`: Adjusts master volume from 0% to 100% in 10% increments.
>   - `RESTART GAME`: Immediately restarts the current game run.
>   - `QUIT TO TITLE`: Cleanly exits back to the Title Screen.

### 5.3 Low-Latency Control Handling & Debouncing — `[IMPLEMENTED]`
- **Concept & Vision:** Tight, responsive arcade steering on physical handheld controls without double-clicks or input lag.
> **What Is Exactly Implemented in the Game:**
> - **Synthetic Input Debouncing:** 120ms timestamp cooldown in `navMenu()` prevents double-press glitches caused by R36S `gptokeyb` simultaneous keyboard and joystick event mapping.
> - **Cardinal Snapping:** Steers strictly on right angles (`dy = 0` if `dx ~= 0`), eliminating diagonal input slippage on physical D-Pads.
> - **Analog Deadzone:** 0.25 threshold on analog sticks to prevent unintended drift while resting fingers.
> - **Sub-Pixel Movement Accumulator:** Player movement uses float accumulator steps (`moveAccumulator`) ensuring uniform traversal speed regardless of frame rate fluctuations.

### 5.4 Screen Shake & Motion Sensitivity Toggle — `[PENDING]`
- **The Problem:** Significant cuts (>= 5%) and player deaths trigger brief tactile screen shake impacts. Some players are sensitive to screen vibration or prefer a perfectly stable screen.
- **The Player Experience:** A simple toggle in the Pause Menu: **`SCREEN SHAKE: [ ON / OFF ]`**. When disabled, screen shake is bypassed and replaced with a subtle screen border flash instead.
- **Implementation Scope:** Add a boolean `game.screenShakeEnabled` setting saved in `settings.txt`, checked before calling `love.graphics.translate` in `love.draw()`.
- **Value & Priority:** **High Accessibility Value / Very Low Effort.**

### 5.5 Button Remapping (Fast / Slow Draw Swap) — `[PENDING]`
- **The Problem:** Default controls assign Fast Draw to `(A)` and Slow Draw to `(B)`. Some players instinctively prefer holding `(B)` for fast running and `(A)` for slow, deliberate precision.
- **The Player Experience:** A setting in the Pause Menu or Title Screen: **`CONTROLS: [ A=FAST, B=SLOW / A=SLOW, B=FAST ]`**.
- **Implementation Scope:** Swap the input boolean assignment in `updateInput()` according to user preference and save in `settings.txt`.
- **Value & Priority:** **Medium Accessibility Value / Very Low Effort.**

---

## 6. Architecture & Engineering

### 6.1 Modular Component Architecture — `[IMPLEMENTED]`
- **Concept & Vision:** Avoiding monolithic single-file architecture in favor of clean, maintainable modular components.
> **What Is Exactly Implemented in the Game:**
> - The codebase is divided into 9 clean, focused Lua modules:
>   - `player.lua`: Marker movement, drawing state machine, fuse timing, shield durations.
>   - `qix.lua`: Procedural helix vector rendering, reflection physics, stix collision detection.
>   - `sparx.lua`: Perimeter wall-following algorithm, Super Sparx stix pursuit.
>   - `grid.lua`: Flood-fill territory analysis, Split-Qix detection, dynamic image reveal buffers.
>   - `crystals.lua`: In-field tactical power crystals generation and collection.
>   - `achievements.lua`: 7-medal achievement system, toast queue, file persistence.
>   - `particles.lua`: Plasma cutting sparks, territory capture bursts, death shards.
>   - `audio.lua`: 8-bit procedural waveform synthesizer.
>   - `main.lua`: Game state management, Title & Pause menus, HUD, and debriefing.

### 6.2 Automated Test Suite & Integrity Validation — `[IMPLEMENTED]`
- **Concept & Vision:** Automated testing to verify core grid logic, scoring, and UI states before releasing package updates.
> **What Is Exactly Implemented in the Game:**
> - Automated test suite (`scratch/test_suite`) verifies:
>   - Difficulty cycling across all 3 modes and correct life/speed configuration.
>   - Dual Qix spawning on Level 3.
>   - Power crystal generation on Level 4.
>   - Veteran Survivor achievement unlock on Level 5.
>   - Split-Qix victory calculation and permanent multiplier progression.
>   - Chrono Freeze activation and timer countdown.
>   - Headless rendering of Title, Badges, Pause, and Playing screens without errors.

### 6.3 Custom Challenge / Level Editor Mode — `[PENDING]`
- **The Problem:** Players want to share unique, customized challenges with specific goal percentages, enemy counts, or customized time limits.
- **The Player Experience:** A lightweight "Custom Game" configuration menu that lets players tweak starting parameters (number of Qixes, initial Sparx count, target percentage, fuse speed) to create tailor-made challenges.
- **Implementation Scope:** A custom setup menu before game start that writes to a `custom_game` configuration object.
- **Value & Priority:** **Low-to-Medium Priority.**

---

## Summary of Priority Recommendations for Next Update

| Priority | Feature | Category | Effort | Impact |
| :---: | :--- | :--- | :---: | :---: |
| **1** | **Top-5 Leaderboard (3 Initials)** | Progression & Arcade Feel | Medium | Very High |
| **2** | **"Danger Close" Threat Warning** | Gameplay & Awareness | Low | High |
| **3** | **Cabinet Visual Themes (Amber & Green)** | Visuals & Eye Comfort | Medium | High |
| **4** | **Screen Shake & Motion Toggle** | Accessibility | Very Low | High |
| **5** | **Ambient Qix Proximity Drone & Siren** | Audio Immersion | Low | High |
| **6** | **Continue / Checkpoint System** | Session Flow | Low | Medium |
| **7** | **Button Remapping (A/B Swap)** | Controls & Ergonomics | Very Low | Medium |
