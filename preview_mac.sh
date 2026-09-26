#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# 1. Native Qix.app standalone bundle
if [ -d "$DIR/Qix.app" ]; then
    open "$DIR/Qix.app"
    exit 0
fi

# 2. Open .love archive with default Love2D runner
if [ -f "$DIR/qix.love" ]; then
    open "$DIR/qix.love"
    exit 0
fi

# 3. Direct binary execution with absolute directory path
if [ -x "/Applications/love.app/Contents/MacOS/love" ]; then
    "/Applications/love.app/Contents/MacOS/love" "$DIR"
elif command -v love >/dev/null 2>&1; then
    love "$DIR"
fi
