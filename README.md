# QIX (1981 Arcade) - Native R36S & Desktop Port

A faithful, high-performance native port of the seminal 1981 Taito arcade classic **QIX**, tailored specifically for the **R36S retro handheld console (RK3326 ARM64)** and macOS/desktop via the **LÖVE 2D engine**.

Features authentic chaotic multi-line vector physics with additive glow, dual drawing speeds (Fast vs Slow 2X double points), the sizzling idle Fuse, patrolling perimeter Sparx, countdown mutation to Super Sparx, dynamic background artwork uncovering, floating score popups, and toggleable CRT scanlines locked at 60 FPS in 640x480 resolution.

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
├── web-legacy/                   # Archived HTML5 / Web Prototype
│   ├── index.html
│   ├── css/
│   └── js/
│
├── Qix.app                       # Standalone macOS application bundle
├── Preview.command               # Double-clickable macOS Finder launcher
├── preview_mac.sh                # Command-line preview script (instant live reload)
└── build_package.sh              # Automated release packager
```

---

## Development & Preview (macOS)

### Instant Live Preview (Recommended)
Edit files directly inside `src/` and run:
```bash
./preview_mac.sh
```
or double-click **`Preview.command`** in Finder. It runs the live source directory directly with zero build steps.

### Standalone App
You can also launch **`Qix.app`** directly from Finder.

### Mac Controls:
- **Move:** `Arrow Keys` or `W`, `A`, `S`, `D`
- **Fast Draw (1X Points):** `Space` or `Z`
- **Slow Draw (2X Points):** `X`, `Shift`, or `C`
- **Pause & Options:** `Escape` or `P`
- **Mute Audio:** `M`
- **Gamepad:** Plugged-in USB/Bluetooth controllers (D-Pad + `A`/`B`)

---

## Building the R36S PortMaster Package

Whenever you modify game code or add new background images:
```bash
./build_package.sh
```

This automated pipeline:
1. Packages `src/` into `qix.love`.
2. Syncs `Qix.app` for macOS testing.
3. Builds **`dist/qix.zip`** (self-contained standalone PortMaster release with ARM64 runtime).

---

## Installing on R36S (ArkOS / PortMaster)

1. Connect your R36S MicroSD card to your computer (or use SFTP / Samba).
2. Unzip **`dist/qix.zip`** into your ports directory:
   ```
   /roms/ports/
   ├── Qix.sh
   └── qix/
       ├── qix.love
       ├── love
       ├── libs/
       └── ...
   ```
3. Insert the card into your R36S, go to **Ports**, and launch **Qix**!

---

## Custom Background Artwork

Drop any `.jpg`, `.jpeg`, or `.png` images into `src/art/`.
The game's dynamic Art Deck scanner will automatically rotate through your photos across rounds with proportional, aspect-ratio-preserving centering!
