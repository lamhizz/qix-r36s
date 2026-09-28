#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=== Building PortMaster Native Love2D Package for Qix (R36S) ==="

PACKAGE_NAME="qix"
BUILD_DIR="build_temp"
DIST_DIR="dist"
SRC_DIR="src"
PORT_DIR="port"

# 1. Package src/ into qix.love archive
echo "Packaging qix.love from $SRC_DIR/..."
rm -f "qix.love"
cd "$SRC_DIR"
zip -9 -q -r "../qix.love" . -x "*.DS_Store"
cd "$DIR"

# 2. Sync macOS standalone app if present
if [ -d "Qix.app/Contents/Resources" ]; then
    cp "qix.love" "Qix.app/Contents/Resources/"
    echo "Updated local Qix.app bundle."
fi

# 3. Assemble distribution package
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR/$PACKAGE_NAME" "$DIST_DIR"

# Copy PortMaster launcher & metadata
cp "$PORT_DIR/Qix.sh" "$BUILD_DIR/"
chmod +x "$BUILD_DIR/Qix.sh"

cp "$PORT_DIR/love" "$BUILD_DIR/$PACKAGE_NAME/"
chmod +x "$BUILD_DIR/$PACKAGE_NAME/love"
cp -r "$PORT_DIR/libs" "$BUILD_DIR/$PACKAGE_NAME/"

cp "$PORT_DIR/port.json" "$BUILD_DIR/$PACKAGE_NAME/"
cp "$PORT_DIR/gameinfo.xml" "$BUILD_DIR/$PACKAGE_NAME/"
cp "$PORT_DIR/qix.gptk" "$BUILD_DIR/$PACKAGE_NAME/"
cp "$PORT_DIR/cover.png" "$BUILD_DIR/$PACKAGE_NAME/"
cp "$PORT_DIR/screenshot.png" "$BUILD_DIR/$PACKAGE_NAME/"

# Copy game package and loose art/fonts for easy user customization on SD card
cp "qix.love" "$BUILD_DIR/$PACKAGE_NAME/"
cp -r "$SRC_DIR/art" "$BUILD_DIR/$PACKAGE_NAME/"
cp -r "$SRC_DIR/foreground-art" "$BUILD_DIR/$PACKAGE_NAME/"
cp -r "$SRC_DIR/fonts" "$BUILD_DIR/$PACKAGE_NAME/"

# Remove any macOS metadata files
find "$BUILD_DIR" -name ".DS_Store" -delete

# 4. Create final PortMaster distribution zip
cd "$BUILD_DIR"
zip -r "../$DIST_DIR/${PACKAGE_NAME}.zip" "Qix.sh" "$PACKAGE_NAME" -x "*.DS_Store"
cd "$DIR"

rm -rf "$BUILD_DIR"

echo "=== Packaging Complete! ==="
echo "PortMaster zip created at: $DIST_DIR/${PACKAGE_NAME}.zip"
