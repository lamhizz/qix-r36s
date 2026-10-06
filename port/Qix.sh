#!/bin/bash
# ==============================================================================
# QIX (1981 Arcade) - Standalone Native PortMaster Launcher for R36S (RK3326)
# ==============================================================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/qix"
cd "$GAMEDIR"

# Start logging
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "=== Starting QIX (Native Love2D) ==="
echo "GAMEDIR: $GAMEDIR"
echo "controlfolder: $controlfolder"

# Locate Love2D runner
LOVE_BIN=""

if [ -f "$GAMEDIR/love" ]; then
  echo "Using bundled Love2D ARM64 binary..."
  $ESUDO chmod +x "$GAMEDIR/love"
  export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
  LOVE_BIN="$GAMEDIR/love"
elif [ -f "$controlfolder/runtimes/love_11.5/love.txt" ]; then
  source "$controlfolder/runtimes/love_11.5/love.txt"
  LOVE_BIN="$LOVE_RUN"
elif [ -f "$controlfolder/runtimes/love_11.4/love.txt" ]; then
  source "$controlfolder/runtimes/love_11.4/love.txt"
  LOVE_BIN="$LOVE_RUN"
elif command -v love >/dev/null 2>&1; then
  LOVE_BIN="love"
elif [ -x "$controlfolder/runtimes/love_11.5/love" ]; then
  LOVE_BIN="$controlfolder/runtimes/love_11.5/love"
elif [ -x "$controlfolder/runtimes/love_11.4/love" ]; then
  LOVE_BIN="$controlfolder/runtimes/love_11.4/love"
fi

if [ -z "$LOVE_BIN" ]; then
  echo "ERROR: No Love2D binary found!"
  exit 1
fi

echo "Selected Love binary: $LOVE_BIN"

# Ensure user input permissions
$ESUDO chmod 666 /dev/uinput 2>/dev/null

export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Configure OpenAL-Soft for rock-solid ALSA playback on RK3326
# (Forces ALSA backend, disables buggy ALSA mmap, and increases buffer periods to stop broken pipe underruns)
export ALSOFT_DRIVERS="alsa"
cat << 'EOF' > "$GAMEDIR/alsoft.conf"
drivers = alsa
[alsa]
mmap = false
device = default
periods = 4
period_size = 1024
EOF
export ALSOFT_CONF="$GAMEDIR/alsoft.conf"

# Enable kernel fatal signal reporting and core dumps for crash post-mortem
$ESUDO sysctl -w kernel.print-fatal-signals=1 2>/dev/null || true
$ESUDO sysctl -w debug.exception-trace=1 2>/dev/null || true
$ESUDO sysctl -w kernel.core_pattern="$GAMEDIR/core" 2>/dev/null || true
ulimit -c unlimited 2>/dev/null || true

# Record dmesg position prior to game start to isolate run-time kernel logs
DMESG_LINES_BEFORE=$(dmesg 2>/dev/null | wc -l || echo 0)

# Clean up any stale gptokeyb instances from previous runs
$ESUDO killall -9 gptokeyb gptokeyb2 2>/dev/null || true

# Start controller mapper
$GPTOKEYB "love" -c "$GAMEDIR/qix.gptk" &

# Platform helper (guarded for older PortMaster installs)
if [[ -n "$(type -t pm_platform_helper)" ]]; then
  pm_platform_helper "$LOVE_BIN"
fi

echo "Launching Qix..."
$LOVE_BIN "$GAMEDIR/qix.love"
QIX_EXIT_CODE=$?
echo "=== Qix Process Exited with Code: $QIX_EXIT_CODE ==="

if [ $QIX_EXIT_CODE -ne 0 ]; then
  echo "WARNING: Game exited with status $QIX_EXIT_CODE! Diagnostics:"
  echo "--- System Memory Info ---"
  free -m 2>/dev/null || cat /proc/meminfo 2>/dev/null | grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree" || true

  echo "--- Kernel Messages During This Run ---"
  if [ -n "$ESUDO" ]; then
    $ESUDO dmesg -T 2>/dev/null | tail -n +$((DMESG_LINES_BEFORE + 1)) | tail -n 60 || true
  else
    dmesg -T 2>/dev/null | tail -n +$((DMESG_LINES_BEFORE + 1)) | tail -n 60 || true
  fi

  echo "--- Specific Crash / Segfault / OOM Alerts ---"
  if [ -n "$ESUDO" ]; then
    $ESUDO dmesg -T 2>/dev/null | grep -E -i "segfault|sigsegv|fatal signal|oom-killer|killed process|core dumped|unhandled level|null pointer" | tail -n 20 || true
  else
    dmesg -T 2>/dev/null | grep -E -i "segfault|sigsegv|fatal signal|oom-killer|killed process|core dumped|unhandled level|null pointer" | tail -n 20 || true
  fi

  if [ -f "$GAMEDIR/core" ]; then
    echo "--- Found Core Dump ($GAMEDIR/core) ---"
    ls -lh "$GAMEDIR/core" 2>/dev/null || true
    if command -v gdb >/dev/null 2>&1; then
      echo "Running GDB stack trace:"
      gdb -batch -ex "bt" "$LOVE_BIN" "$GAMEDIR/core" 2>/dev/null || true
    fi
  fi
fi

# Cleanup with fallback if pm_finish is not available
if [[ -n "$(type -t pm_finish)" ]]; then
  pm_finish
else
  $ESUDO killall -9 gptokeyb gptokeyb2 2>/dev/null || true
  $ESUDO systemctl restart oga_events & 2>/dev/null || true
fi
