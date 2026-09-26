#!/bin/bash
set -e

echo "=== Building PortMaster Native Love2D Package for Qix (R36S) ==="

PACKAGE_NAME="qix"
BUILD_DIR="build_temp"
DIST_DIR="dist"

# Build qix.love archive
echo "Packaging qix.love..."
zip -9 -q -r "qix.love" main.lua conf.lua grid.lua player.lua qix.lua sparx.lua audio.lua fonts art cover.png

if [ -d "Qix.app/Contents/Resources" ]; then
    cp "qix.love" "Qix.app/Contents/Resources/"
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR/$PACKAGE_NAME" "$DIST_DIR"

# 1. Copy top-level launch script
cp "Qix.sh" "$BUILD_DIR/"
chmod +x "$BUILD_DIR/Qix.sh"

# 2. Copy Love2D standalone aarch64 binary and libraries
cp "love" "$BUILD_DIR/$PACKAGE_NAME/"
chmod +x "$BUILD_DIR/$PACKAGE_NAME/love"
cp -r "libs" "$BUILD_DIR/$PACKAGE_NAME/"

# 3. Copy Love2D game archive & loose source files
cp "qix.love" "$BUILD_DIR/$PACKAGE_NAME/"
cp "main.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp "conf.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp "grid.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp "player.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp "qix.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp "sparx.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp "audio.lua" "$BUILD_DIR/$PACKAGE_NAME/"
cp -r "fonts" "$BUILD_DIR/$PACKAGE_NAME/"
cp -r "art" "$BUILD_DIR/$PACKAGE_NAME/"

# 4. Copy PortMaster metadata & media
cp "port.json" "$BUILD_DIR/$PACKAGE_NAME/"
cp "gameinfo.xml" "$BUILD_DIR/$PACKAGE_NAME/"
cp "qix.gptk" "$BUILD_DIR/$PACKAGE_NAME/"
cp "README.md" "$BUILD_DIR/$PACKAGE_NAME/"
cp "screenshot.png" "$BUILD_DIR/$PACKAGE_NAME/"
cp "cover.png" "$BUILD_DIR/$PACKAGE_NAME/"

# 5. Remove any stray OS files (.DS_Store, etc.)
find "$BUILD_DIR" -name ".DS_Store" -delete

# 6. Create PortMaster distribution zip
cd "$BUILD_DIR"
zip -r "../$DIST_DIR/${PACKAGE_NAME}.zip" "Qix.sh" "$PACKAGE_NAME"
cd ..

rm -rf "$BUILD_DIR"

echo "=== Packaging Complete! ==="
echo "Standalone Love2D PortMaster zip created at: $DIST_DIR/${PACKAGE_NAME}.zip"
