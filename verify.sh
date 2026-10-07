#!/bin/bash
# ==============================================================================
# QIX (R36S) - Automated Pre-Flight Verification & Build Pipeline
# Runs unit tests, stress simulation, asset validation, and package generation.
# ==============================================================================

set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "======================================================="
echo " QIX: AUTOMATED PRE-FLIGHT VERIFICATION PIPELINE"
echo "======================================================="

# 1. Determine Love2D runner
LOVE_RUNNER=""
if [ -x "$DIR/tools/love.app/Contents/MacOS/love" ]; then
    LOVE_RUNNER="$DIR/tools/love.app/Contents/MacOS/love"
elif command -v love >/dev/null 2>&1; then
    LOVE_RUNNER="love"
elif [ -x "/Applications/love.app/Contents/MacOS/love" ]; then
    LOVE_RUNNER="/Applications/love.app/Contents/MacOS/love"
fi

if [ -z "$LOVE_RUNNER" ]; then
    echo "ERROR: Love2D runner not found in tools/ or system!"
    exit 1
fi

echo "Selected Love runner: $LOVE_RUNNER"

# 2. Run Headless Simulation & Stress-Test Harness
echo -e "\n[STEP 1/3] Running Headless Simulation & Stress-Test Suite..."
"$LOVE_RUNNER" "$DIR/tools/test_harness"

# 3. Validate Manifest & Image Asset Files
echo -e "\n[STEP 2/3] Checking Asset Directories & Manifest..."
if [ ! -f "$DIR/src/art/manifest.txt" ]; then
    echo "ERROR: Missing src/art/manifest.txt!"
    exit 1
fi
MANIFEST_COUNT=$(grep -v '^[[:space:]]*#' "$DIR/src/art/manifest.txt" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
echo "  Manifest contains $MANIFEST_COUNT registered backgrounds."

# 4. Build Distribution Package
echo -e "\n[STEP 3/3] Generating PortMaster Package..."
"$DIR/build_package.sh" > /dev/null

echo -e "\n======================================================="
echo " \033[32mPRE-FLIGHT VERIFICATION COMPLETE: ALL SYSTEMS READY!\033[0m"
echo " Package: dist/qix.zip"
echo "=======================================================\n"
