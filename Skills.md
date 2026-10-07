# R36S Game Development: Core Architectural Lessons & Rules

This document records the critical lessons, failure modes, and hardware-level solutions learned during the development and optimization of **Qix (Native Love2D)** for the **R36S Handheld Console** (Rockchip RK3326 SoC, Mali-G31 MP2 GPU, 1 GB RAM, 640x480 4:3 display running PortMaster / ArkOS).

---

## 1. Hardware Constraints (The Reality of the RK3326)

| Parameter | Specification | Real-World Impact |
| :--- | :--- | :--- |
| **SoC / CPU** | Quad-core ARM Cortex-A35 @ 1.3–1.5 GHz | 64-bit ARM (`aarch64`). Limited single-core compute. |
| **GPU** | ARM Mali-G31 MP2 (OpenGL ES 3.2) | Strict vertex buffer limits; fragile GLES clipping on out-of-screen tessellations. |
| **Memory** | 1 GB DDR3L/DDR4 (Shared) | Shared between Linux OS, framebuffer, Mali GPU, and game heap. Safe budget: < 250 MB RSS. |
| **Display** | 3.5" IPS, Fixed 640x480 (4:3) | Strict 640x480 resolution. Any rendering outside 0..640 / 0..480 wastes memory and risks driver bugs. |
| **Storage / FS** | MicroSD formatted as exFAT / FAT32 | Simultaneous file descriptors to the same file lock up kernel `statx` syscalls. |
| **OS / Runtime**| ArkOS / AmberELEC / PortMaster | Native Love2D 11.4 ARM64 + LuaJIT 2.1 + OpenAL-Soft. |

---

## 2. Image Decoding & Memory Management

### The Uncompressed Bitmap Trap
* **The Problem**: A high-resolution photo (e.g. 24 MP $6000\times 4000$) might only take 3 MB on an SD card as JPEG, but upon loading (`stb_image` / `love.image.newImageData`), it decompresses into raw 32-bit RGBA:
  $$\text{Memory} = \text{Width} \times \text{Height} \times 4 \text{ bytes}$$
  A $6000\times 4000$ image requires **96 MB of raw contiguous C-heap memory**, plus decompression buffers, plus GPU texture memory. On a 1 GB shared system, this triggers Linux Out-Of-Memory (OOM) kills or GPU driver allocation crashes (Exit Code 139).
* **The Solution**:
  1. **Binary Header Pre-flight Inspector**: Read only the first 64 KB of file headers in pure Lua to extract dimensions and color channels *before* calling decoding APIs.
  2. **Strict Safety Limits**:
     * File size cap: Reject files $> 6.0\text{ MB}$.
     * Resolution cap: Reject images $> 16\text{ Megapixels}$ or single dimensions $> 4096\text{px}$.
     * Color format: Reject 4-channel CMYK JPEGs (print format) which crash Love2D.
  3. **Resilient Deck Fallback**: Wrap all image loading in a retry loop (attempting up to 8 alternative images). If all fail, fall back to procedural graphics. The game must never crash due to a bad asset.
  4. **Pre-Scale Assets**: Resize bundled backgrounds to max $1280\times 960$ and foreground skins to $710\times 530$.

---

## 3. OpenGL ES & Mali-G31 GPU Geometry Traps

### Out-Of-Bounds Rounded Line Tessellation
* **The Problem**: Calling wide outline primitives (e.g., `setLineWidth(2)`, `rectangle("line", x, y, w, h, rx, ry)`) with off-screen coordinates (e.g., starting an animation card at $y = 480$, generating child buttons at $y = 794$ to $866$ on a 480p viewport) causes the Mali-G31 driver to segfault during polygon vertex clipping and tessellation.
* **The Solution**:
  1. **Clamp Animation Coordinates**: Ensure card animation start positions are within safe screen bounds (e.g., slide from $y = 160$ to $22$, never starting far below screen height).
  2. **Isolate Overlay Draw States**: Do not draw the entire gameplay loop (entities, particle systems, HUD, border FX) underneath an overlay screen if that screen immediately covers the entire viewport. Make `GAME_OVER`, `TITLE`, and `LEVEL_CLEAR` explicit independent branches in `love.draw()`.
  3. **Wrap UI in `pcall`**: Wrap complex UI draw procedures in a protected call with a clean ASCII text fallback.

---

## 4. Typography & Font Safety

### Never Use Multi-Byte Unicode on Retro Pixel Fonts
* **The Problem**: Fonts like `Press Start 2P` (`pressstart2p.ttf`) are retro pixel fonts that strictly contain basic ASCII (0x20 to 0x7E). Using Unicode characters like `►`, `◄`, `★`, `•` causes FreeType metric lookups on ARM64 Linux to return null advances or invalid layout calculations.
* **The Solution**:
  * Use standard ASCII replacements:
    * `►` $\to$ `>`
    * `◄` $\to$ `<`
    * `★` $\to$ `*`
    * `•` $\to$ `|` or `-`

---

## 5. Storage & Linux exFAT File Contention

### Avoid Dual File Handles
* **The Problem**: In PortMaster, launcher scripts (`Qix.sh`) launch games with standard stdout/stderr redirected to `log.txt`:
  ```bash
  $LOVE_BIN "$GAMEDIR/qix.love" > "$GAMEDIR/log.txt" 2>&1
  ```
  If the game engine simultaneously calls `io.open("log.txt", "a")` from Lua and flushes on every log message, two file descriptors fight over the same file on an exFAT/FAT32 SD card, triggering kernel `statx` system call deadlocks and faults.
* **The Solution**:
  * Let standard `print(...)` and `io.stdout:flush()` handle writing to `log.txt`. Do not open separate file handles to the same destination.
  * Avoid synchronous disk writes on every single log event. Use an in-memory circular ring buffer for recent history and breadcrumbs.

---

## 6. Native Crash Diagnostics & LuaJIT Signal Safety

### LuaJIT FFI Signal Handler Panic
* **The Problem**: Trying to catch SIGSEGV/SIGBUS by casting a Lua function to a C signal handler via LuaJIT FFI (`ffi.cast("sighandler_t", ...)`) causes a secondary panic: `PANIC: unprotected error in call to Lua API (bad callback)`. LuaJIT strictly forbids calling Lua code from asynchronous OS signals.
* **The Solution**:
  * Handle crash capture at the OS / shell level in `Qix.sh`:
    1. **Enable fatal signal output**: `sysctl -w kernel.print-fatal-signals=1` (forces the kernel to print the faulting library, IP, SP, and signal reason into `dmesg`).
    2. **Enable core dumps in tmpfs**: `sysctl -w kernel.core_pattern="/tmp/core"` and `ulimit -c unlimited`. Direct dumps to `/tmp` (RAM-backed tmpfs) because exFAT/FAT32 MicroSD cards truncate core dumps to 0 bytes.
    3. **Isolate run-time kernel logs**: Record `DMESG_LINES_BEFORE=$(dmesg | wc -l)` before starting the game. On exit with non-zero status, print only `dmesg | tail -n +$((DMESG_LINES_BEFORE + 1))` to avoid boot spam.
    4. **In-game Breadcrumbs**: Maintain a lightweight in-memory ring buffer (`Logger.breadcrumb(...)`) tracking the last 60 engine actions (states, entity updates, draw frames) to trace the exact line of execution preceding any native fault.

---

## 7. Dynamic Particle Geometry & EarCut Polygon Traps

### Never Use `love.graphics.polygon("fill")` for Decaying Particle FX
* **The Problem**: When particles decay over their lifetime, their calculated size $s = \text{size} \times \alpha$ eventually approaches $0.0$. If a diamond or shard is drawn using `love.graphics.polygon("fill", {0, -s, s, 0, 0, s, -s, 0})`, all four vertices collapse into $(0,0)$. Love2D's internal polygon triangulator (EarCut / Libtess2) filters out duplicate and collinear vertices. When all vertices are filtered, the polygon linked list becomes empty (`NULL`). The triangulator then attempts to dereference the head pointer (`x0 = 0x0000000000000000`), immediately producing a native kernel **SIGSEGV 11** crash (`Exit Code 139`).
* **The Solution**:
  1. **Render Shards as Rotated Hardware Quads**: A diamond is simply a square rotated by $45^\circ$. Use:
     ```lua
     if s >= 0.6 then
         local half = s * 0.707
         love.graphics.push()
         love.graphics.translate(p.x, p.y)
         love.graphics.rotate(p.rot)
         love.graphics.rectangle("fill", -half, -half, half * 2, half * 2)
         love.graphics.pop()
     end
     ```
     This completely bypasses polygon triangulation, utilizes native GPU quad batching, and is impossible to crash with degenerate geometry.
  2. **Enforce Minimum Size Thresholds**: Always guard particle rendering with `if s >= 0.6` and `if alpha > 0.02`. Never draw sub-pixel zero-area geometry.
  3. **Explicit Circle Segments**: Never call `love.graphics.circle("fill", x, y, r)` with default segment counts (30–36 vertices) for dozens of tiny 2–3px sparks. Explicitly pass 8 segments: `love.graphics.circle("fill", x, y, r, 8)`. This cuts vertex count and GLES clipping load on Mali-G31 by over 75%.

---

## 8. OpenAL-Soft Audio & ALSA Concurrency on RK3326

### Multi-Threaded Audio Source Stopping & Race Conditions
* **The Problem**: In Linux ALSA on RK3326, iterating through audio sources and calling `s:stop()` multiple times (or calling `s:stop()` on a looping source that was already stopped in the same tick) causes race conditions between Lua main thread calls and the ALSA mixer background thread. This results in OpenAL dereferencing a detached voice/buffer (`SIGSEGV 11`).
* **The Solution**:
  1. **Atomic Global Audio Stop**: Use `love.audio.stop()` to atomically stop all playing sources across the engine instead of looping through tables calling `:stop()` on individual sources.
  2. **Check Playing State**: Before calling `s:stop()` on individual named sources, always check `if s:isPlaying() then s:stop() end`.
  3. **Defensive `pcall`**: Wrap audio start/stop calls in `pcall` so transient ALSA buffer underruns never take down the game process.

---

## 9. Entity Collision & State Re-entrancy

### Same-Frame Collision Stacking
* **The Problem**: If a player is drawing a line and collides with Qix, `game:onPlayerDeath("qix")` changes state to `DEAD`. If the subsequent loop over Sparx enemies executes in the exact same frame without checking the new state, Sparx can also collide with the player Marker at the same position, invoking `onPlayerDeath("sparx")` re-entrantly. This deducts a second life, triggers duplicate audio stops, and corrupts particle pools.
* **The Solution**:
  1. **Re-entrancy Guard**: At the top of `onPlayerDeath`:
     ```lua
     if self.state == "DEAD" or self.state == "GAME_OVER" or self.player.state == Player.STATE_DEAD then
         return
     end
     ```
  2. **Loop Guard**: Check `if game.state == "PLAYING"` before every subsequent enemy collision loop in `love.update`.

---

## 10. High-Velocity Engineering & Rapid-Iteration Architecture (10x Speedup)

Embedded retro handheld development creates a notorious bottleneck: code runs smoothly on modern desktop OSs (Metal/OpenGL, gigabytes of RAM, multi-channel sound), but crashes natively on target hardware. Manually ejecting SD cards, booting the console, and playing several minutes to reproduce bugs inflates iteration time to 15–20 minutes per cycle.

### A. Headless Simulation & Stress-Test Harness (`tools/simulate.lua`)
* **Principle**: Catch 95% of native crashes, memory over-allocations, and geometry faults on the desktop in **under 2 seconds** before writing to an SD card.
* **Standard Test Suites**:
  1. **Geometry & Particle Stressor**: Simulates 500 consecutive death bursts with edge-case inputs ($s = 0$, $\alpha = 0$, negative coords, offscreen bounds). Verifies that no polygon or line call invokes EarCut with degenerate geometry.
  2. **Audio Concurrency Stressor**: Rapidly fires interleaved `:play()`, `:stop()`, looping sound toggles, and global stops across 1,000 cycles to catch OpenAL driver race conditions.
  3. **Asset Batch Validator**: Iterates through all project image files, parses binary headers, and asserts resolution $\le 1280\times 960$ and file size $\le 6.0\text{ MB}$.
  4. **Headless Bot Loop**: Runs 3,000 virtual frames of `update(0.016)` and `draw()` exercising all game states (`TITLE` $\to$ `PLAYING` $\to$ `DEAD` $\to$ `LEVEL_CLEAR` $\to$ `GAME_OVER`).

### B. Finite State Machine (Never Write a Monolithic `main.lua`)
* **Anti-Pattern**: Writing a single 2,000+ line `main.lua` that handles rendering, input, HUD, game over, audio, level progression, and enemy logic in giant `if/elseif` trees.
* **Standard Architecture**:
  * Keep `main.lua` under 250 lines as a thin bootstrap router.
  * Deconstruct all game scenes into discrete files under `src/states/`:
    `state_title.lua`, `state_playing.lua`, `state_dead.lua`, `state_level_clear.lua`, `state_game_over.lua`.
  * Each state implements strict lifecycle callbacks: `enter()`, `update(dt)`, `draw()`, `leave()`.
  * Prevents cross-state coupling, isolates bugs to 50–80 line files, and reduces AI context latency.

### C. Desktop Handheld Emulation & Fast-Forward Debug Keybindings
* **Viewport Sandbox**: Lock desktop window to an exact 4:3 640x480 resolution with virtual button prompts matching PortMaster's physical buttons.
* **Debug Fast-Forward Keys (Desktop only)**:
  * `F1`: Jump instantly to advanced levels (e.g. Level 4) with all mechanics active (skips 3 minutes of manual play).
  * `F2`: Trigger immediate player damage/death with active entity paths.
  * `F3`: Trigger immediate level clear / win condition.
  * `F4`: Toggle god-mode / collision debug overlays.

### D. Automated Pre-Flight Verification Script (`verify.sh`)
* Single command executes:
  1. Static syntax linting (`luacheck` / bytecode compilation).
  2. Headless stress-test harness (`love tools/simulate.lua`).
  3. Binary image header validation.
  4. Packaging (`qix.love` and PortMaster `.zip`).
* Rejects the build if any check fails, guaranteeing that broken builds never reach hardware.

### E. Remote Wireless / OTG Hot-Deployment (Zero SD-Card Swapping)
* The R36S supports USB Wi-Fi dongles and USB-OTG phone/Mac tethering. ArkOS runs an active SSH daemon by default (`ark:ark` on port 22).
* Automate deployment via `deploy_remote.sh <R36S_IP>`:
  * Uses `rsync` to push the `.love` bundle directly to `/roms2/ports/<game>/` over the local network in 2 seconds.
  * Restarts the launcher process remotely via SSH and streams `log.txt` live to the host terminal.
  * Slashes human iteration time from 15 minutes down to **15 seconds**.
