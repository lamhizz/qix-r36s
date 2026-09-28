# QIX (1981 Arcade) - Native R36S Port (LÖVE 2D Engine)

A faithful, high-performance native port of the seminal 1981 Taito arcade classic **QIX**, built from the ground up for the **R36S retro handheld console (RK3326 ARM64)** and macOS/desktop using the **LÖVE 2D engine** (Lua 5.1 / LuaJIT).

The game runs as a **100% self-contained standalone PortMaster package**—it bundles its own ARM64 LÖVE 2D binary and shared libraries, requiring **zero external dependencies** on the handheld.

---

## Highlights & Features

- **Built Specifically for R36S:** Locked at **640×480 resolution** and rock-solid **60 FPS** on the RK3326 Mali-G31 GPU.
- **Tactical Board Scale:** High-resolution $355 \times 251$ discrete playfield grid ($1.8\times$ scale) providing a balanced playfield with ample tactical travel distances, smooth movement, and comfortable entity proportions.
- **Arcade Intro Screen:** Features a 4-layer neon glowing "QIX" centerpiece with ambient attract-mode background helix, high score ribbon, and vertically centered menu options (**"START"**, **"HOW TO"**, and **"QUIT"**).
- **In-Game "How To" Guide:** Comprehensive instructions screen detailing dual-speed scoring, fuse ignition, sparx mutation, and arcade secrets.
- **Classic 1981 Split-Qix Victory (Levels 3+):** Slice between two roaming Qixes to trap them in separate compartments—instantly clearing the round and permanently unlocking high score multipliers (2X up to 9X)!
- **Pristine Artwork Showcase in "FIT" Mode:** On level completion, the unveiled photo transitions to a 100% full-screen presentation in **FIT mode** (`math.min` scale) with clean letterbox framing so widescreen, portrait, and square photos are displayed without edge cropping.
- **Patrolling Perimeter Sparx:** Glowing 8-pointed sparkler hazards that patrol outer borders and edges of claimed areas, forcing the player to keep moving along the perimeter or draw into the void.
- **Super Sparx Pursuit (Level 2+):** In later rounds, when the level's countdown timer reaches zero, normal Sparx mutate into Super Sparx—moving faster, flashing menacing sirens, actively pursuing the Marker along newly claimed inner boundaries, and chasing onto active Stix lines!
- **Anti-Camping Fuse:** Stopping or idling while drawing an incomplete Stix ignites a flame at the origin of the line that burns down the trail toward the player. Moving again instantly puts out the Fuse, but if it reaches the Marker, the player loses a life.
- **Dynamic Photo Uncover System:** Cutting territory cuts away the dark veil to reveal custom background photography underneath (with fiery red/orange slow-draw and electric cyan fast-draw translucent glass tints).
- **2.5-Second Grace Shield:** Activates upon respawning after death and at the start of each round, granting complete immunity from Sparx enemies with pulsing dual-ring energy auras and an on-screen notification.
- **Framerate Independence:** Physics and enemy speeds are normalized to 60 FPS standard, ensuring identical gameplay speed on both 60 Hz handheld screens and 120 Hz Mac ProMotion displays.
- **Arcade Visual FX & Particle System:** Zero-allocation 60 FPS particle pool powering plasma laser cutting sparks, starburst explosions on area capture, vector diamond shard death bursts, multi-pass phosphor vector bloom on the Qix ribbon, and subtle curved CRT glass bezel shading.
- **Procedural 1981 Sound Synthesizer:** Real-time synthesized 8-bit arcade audio generated directly in code (no external sound file dependencies).

---

## Controls Reference

### R36S Handheld Console (ArkOS / PortMaster)

| Action | Handheld Control |
| :--- | :--- |
| **Move Along Perimeter / Border** | **D-Pad** or **Left Analog Stick** |
| **Fast Draw (1X Points)** | **Hold `(A)`** + D-Pad Direction |
| **Slow Draw (2X Double Points)** | **Hold `(B)`** + D-Pad Direction |
| **Pause / System Menu** | **`START`** |
| **Mute / Unmute Audio** | **`SELECT`** |
| **Advance Artwork Showcase** | **`(A)`** |

### macOS Preview & Desktop Testing

| Action | Keyboard | USB / Bluetooth Gamepad |
| :--- | :--- | :--- |
| **Move Along Border** | `Arrow Keys` or `W, A, S, D` | D-Pad / Left Stick |
| **Fast Draw (1X Points)** | **Hold `Space`** or `Z` | **Hold `(A)`** |
| **Slow Draw (2X Points)** | **Hold `X`**, `Shift`, or `C` | **Hold `(B)`** |
| **Pause / System Menu** | `Escape` or `P` | `START` |
| **Mute / Unmute Audio** | `M` | `SELECT` / `Back` |
| **Advance Artwork Showcase** | `A`, `Space`, `Enter`, or Mouse Click | `(A)` |

---

## Installing on R36S (Step-by-Step)

1. Connect your R36S MicroSD card to your computer (or transfer via Wi-Fi SFTP/Samba).
2. Download or copy **`dist/qix.zip`** from this repository.
3. Unzip **`dist/qix.zip`** into your console's ports directory:
   ```
   /roms/ports/
   ├── Qix.sh
   └── qix/
       ├── qix.love
       ├── love
       ├── libs/
       │   ├── liblove-11.4.so
       │   ├── libluajit-5.1.so.2
       │   └── libogg.so.0
       ├── art/                      # Background uncover photos
       ├── foreground-art/           # Circuit board / cover skins for playfield
       ├── fonts/
       ├── port.json
       ├── gameinfo.xml
       ├── qix.gptk
       ├── cover.png
       └── screenshot.png
   ```
4. Put the MicroSD card back into your R36S, navigate to the **Ports** menu, and select **Qix**!

---

## Testing & Preview on Mac

You can test and play the game on your Mac with zero compilation:

### Option 1: Live Source Preview (Instant Live Reload)
Run the preview script or double-click the launcher in Finder:
```bash
./preview_mac.sh
```
*(or double-click **`Preview.command`** in Finder)*. It boots directly from `src/`, allowing you to edit any Lua file and immediately test changes.

### Option 2: Standalone macOS App
Double-click **`Qix.app`** in your project folder to launch the standalone desktop app.

---

## Custom Background Photos & Foreground Skins

- **Background Photos (`src/art/` or `/roms/ports/qix/art/`):**
  Drop any `.jpg`, `.jpeg`, or `.png` images into `art/`. The game automatically detects and cycles through them round by round as you slice away territory.
- **Foreground Playfield Skin (`src/foreground-art/` or `/roms/ports/qix/foreground-art/`):**
  Drop custom skin images (such as retro arcade PCB circuit boards) into `foreground-art/`. The playfield displays this skin on all uncut areas; claiming territory peels it open to reveal the photo underneath!

---

## Building the Release Package

Whenever you update game code or add new artwork:
```bash
./build_package.sh
```

This automated pipeline:
1. Packages `src/` into `qix.love`.
2. Syncs the local `Qix.app` bundle for desktop preview.
3. Rebuilds **`dist/qix.zip`** ready to be dropped into `/roms/ports/` on your R36S.

---

## Repository Structure

```
qix-r36s/
├── src/                          # Active Game Engine Source (LÖVE 2D Lua)
│   ├── main.lua                  # Game loop, state machine, HUD, banners
│   ├── conf.lua                  # 640x480 resolution & module flags
│   ├── grid.lua                  # BFS flood-fill, territory masking & cover scaling
│   ├── player.lua                # Player marker, stix drawing, grace shield
│   ├── qix.lua                   # Chaotic vector ribbon helix with additive glow
│   ├── sparx.lua                 # Patrolling perimeter sparks & super mutation
│   ├── audio.lua                 # Procedural 1981 arcade sound synthesizer
│   ├── fonts/                    # Press Start 2P TrueType arcade fonts
│   └── art/                      # Game art deck (auto-scaled for levels)
│
├── port/                         # PortMaster Handheld Packaging Assets
│   ├── Qix.sh                    # R36S PortMaster launch script
│   ├── port.json                 # PortMaster manifest
│   ├── gameinfo.xml              # EmulationStation metadata
│   ├── qix.gptk                  # Gamepad controller mapping
│   ├── love                      # Precompiled ARM64 Love2D binary for RK3326
│   ├── libs/                     # Bundled shared libraries (liblove, luajit, libogg)
│   ├── cover.png                 # Cabinet cover art
│   └── screenshot.png            # Gameplay screenshot
│
├── dist/                         # Production Build Artifacts
│   └── qix.zip                   # Ready-to-install PortMaster release zip
│
├── art_original/                 # Master high-resolution source photos (backup)
│
├── ideas-for-improvement.md      # Roadmap of gameplay mechanics from prototype
├── Qix.app                       # Standalone macOS application bundle
├── Preview.command               # Double-clickable macOS Finder launcher
├── preview_mac.sh                # Command-line preview script
└── build_package.sh              # Automated release packager
```
