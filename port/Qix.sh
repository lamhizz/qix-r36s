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

# Start controller mapper
$GPTOKEYB "love" -c "$GAMEDIR/qix.gptk" &
pm_platform_helper "$LOVE_BIN"

echo "Launching Qix..."
$LOVE_BIN "$GAMEDIR/qix.love"
QIX_EXIT_CODE=$?
echo "=== Qix Process Exited with Code: $QIX_EXIT_CODE ==="
if [ $QIX_EXIT_CODE -ne 0 ]; then
  echo "WARNING: Game exited with status $QIX_EXIT_CODE! Kernel diagnostics:"
  dmesg | tail -n 25 | grep -i "oom\|kill\|segfault\|out of memory\|mali" || true
fi

pm_finish
