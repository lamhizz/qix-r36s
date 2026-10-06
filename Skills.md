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
    2. **Enable core dumps**: `sysctl -w kernel.core_pattern="$GAMEDIR/core"` and `ulimit -c unlimited`.
    3. **Isolate run-time kernel logs**: Record `DMESG_LINES_BEFORE=$(dmesg | wc -l)` before starting the game. On exit with non-zero status, print only `dmesg | tail -n +$((DMESG_LINES_BEFORE + 1))` to avoid boot spam.
    4. **In-game Breadcrumbs**: Maintain a lightweight in-memory ring buffer (`Logger.breadcrumb(...)`) tracking the last 60 engine actions (states, entity updates, draw frames) to trace the exact line of execution preceding any native fault.
