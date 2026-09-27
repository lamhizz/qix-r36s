#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ -x "/Applications/love.app/Contents/MacOS/love" ] && [ -d "$DIR/src" ]; then
    "/Applications/love.app/Contents/MacOS/love" "$DIR/src"
elif [ -d "$DIR/Qix.app" ]; then
    open "$DIR/Qix.app"
elif [ -f "$DIR/qix.love" ]; then
    open "$DIR/qix.love"
fi
