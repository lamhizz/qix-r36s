#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Run live source directory with love if available (instant live reload)
if [ -x "/Applications/love.app/Contents/MacOS/love" ] && [ -d "$DIR/src" ]; then
    "/Applications/love.app/Contents/MacOS/love" "$DIR/src"
    exit 0
elif command -v love >/dev/null 2>&1 && [ -d "$DIR/src" ]; then
    love "$DIR/src"
    exit 0
fi

# 2. Standalone Qix.app bundle
if [ -d "$DIR/Qix.app" ]; then
    open "$DIR/Qix.app"
    exit 0
fi

# 3. Packaged .love archive
if [ -f "$DIR/qix.love" ]; then
    open "$DIR/qix.love"
    exit 0
fi
