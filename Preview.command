#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ -d "$DIR/Qix.app" ]; then
    open "$DIR/Qix.app"
elif [ -f "$DIR/qix.love" ]; then
    open "$DIR/qix.love"
fi
