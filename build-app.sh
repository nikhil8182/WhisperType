#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="WhisperType"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="$PROJECT_DIR/WhisperType/WhisperType.entitlements"
INSTALL_DIR="/Applications/$APP_NAME.app"

echo "╔══════════════════════════════════════╗"
echo "║    WhisperType Build v1.1.0          ║"
echo "║    by Onwords Smart Solutions        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# --- Step 1: Build release binary ---
echo "🔨 Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

# --- Step 2: Generate icons ---
echo ""
echo "🎨 Generating app icon..."
python3 "$PROJECT_DIR/scripts/generate_icon.py"

echo "🎨 Generating menu bar icons..."
python3 "$PROJECT_DIR/scripts/generate_menubar_icon.py"

# --- Step 3: Create app bundle ---
echo ""
echo "📦 Creating app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp ".build/release/WhisperType" "$APP_BUNDLE/Contents/MacOS/WhisperType"

# Copy Info.plist
cp "WhisperType/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy entitlements
cp "$ENTITLEMENTS" "$APP_BUNDLE/Contents/Resources/WhisperType.entitlements"

# Copy app icon
if [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  ✅ App icon included"
fi

# Copy menu bar icons
if [ -d "$PROJECT_DIR/WhisperType/Resources" ]; then
    cp "$PROJECT_DIR/WhisperType/Resources/"*.png "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
    echo "  ✅ Menu bar icons included"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# --- Step 4: Code signing ---
echo ""
echo "🔐 Code signing..."
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    --preserve-metadata=entitlements,identifier \
    "$APP_BUNDLE" 2>&1 || {
        echo "⚠️  Signing with entitlements failed, trying basic..."
        codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 || echo "⚠️  Code signing skipped"
    }

# Verify
echo "🔍 Verifying signature..."
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true

# --- Step 5: Report ---
echo ""
APP_SIZE=$(du -sh "$APP_BUNDLE" | awk '{print $1}')
BINARY_SIZE=$(du -sh "$APP_BUNDLE/Contents/MacOS/WhisperType" | awk '{print $1}')
echo "═══════════════════════════════════════"
echo "  ✅ Build complete!"
echo "  📍 $APP_BUNDLE"
echo "  📏 App size: $APP_SIZE"
echo "  📏 Binary: $BINARY_SIZE"
echo "  📋 Version: 1.1.0 (build 2)"
echo "═══════════════════════════════════════"

# --- Step 6: Install (optional) ---
if [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
    echo ""
    echo "📲 Installing to /Applications..."
    
    killall WhisperType 2>/dev/null || true
    sleep 1
    
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR"
    
    echo "✅ Installed to $INSTALL_DIR"
    echo ""
    echo "🚀 Launching WhisperType..."
    open "$INSTALL_DIR"
else
    echo ""
    echo "To install: $0 --install"
    echo "To run:     open \"$APP_BUNDLE\""
fi

echo ""
echo "⚠️  First run setup:"
echo "  1. Grant Microphone access when prompted"
echo "  2. Grant Accessibility in System Settings → Privacy & Security"
echo "  3. Hold Right Option to record, release to transcribe & paste"
