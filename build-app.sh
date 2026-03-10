#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="WhisperType"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building WhisperType..."

# Build release
cd "$PROJECT_DIR"
swift build -c release 2>&1

echo "📦 Creating app bundle..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp ".build/release/WhisperType" "$APP_BUNDLE/Contents/MacOS/WhisperType"

# Copy Info.plist
cp "WhisperType/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Create a simple icon (using system icon via iconutil)
# For now, we'll use a placeholder approach
ICONSET_DIR="$BUILD_DIR/WhisperType.iconset"
mkdir -p "$ICONSET_DIR"

# Generate icon images using sips from a system icon
# We'll create a simple colored circle icon
python3 -c "
import subprocess, os, tempfile

iconset_dir = '$ICONSET_DIR'
sizes = [(16,1), (16,2), (32,1), (32,2), (128,1), (128,2), (256,1), (256,2), (512,1), (512,2)]

for size, scale in sizes:
    actual = size * scale
    suffix = f'icon_{size}x{size}' + (f'@{scale}x' if scale > 1 else '')
    filepath = os.path.join(iconset_dir, f'{suffix}.png')
    
    # Use CoreGraphics via Python to create a mic icon
    subprocess.run([
        'python3', '-c', f'''
import Cocoa, AppKit
size = {actual}
img = AppKit.NSImage(size=Cocoa.NSSize(size, size))
img.lockFocus()

# Background circle
path = AppKit.NSBezierPath(ovalIn=Cocoa.NSRect(Cocoa.NSPoint(size*0.05, size*0.05), Cocoa.NSSize(size*0.9, size*0.9)))
AppKit.NSColor(red=0.2, green=0.6, blue=1.0, alpha=1.0).setFill()
path.fill()

# Draw mic symbol
attrs = {{
    AppKit.NSAttributedString.Key.font: AppKit.NSFont.systemFont(ofSize=size*0.5, weight=AppKit.NSFont.Weight.bold),
    AppKit.NSAttributedString.Key.foregroundColor: AppKit.NSColor.white,
}}
mic = Cocoa.NSAttributedString.alloc().initWithString_attributes_(\"🎙\", attrs)
mic_size = mic.size()
mic.drawAtPoint_(Cocoa.NSPoint((size - mic_size.width)/2, (size - mic_size.height)/2))

img.unlockFocus()
tiff = img.TIFFRepresentation()
bitmap = AppKit.NSBitmapImageRep(data=tiff)
png = bitmap.representationUsingType_properties_(AppKit.NSBitmapImageRep.FileType.png, {{}})
png.writeToFile_atomically_(\"{filepath}\", True)
'''], check=True)
" 2>/dev/null || echo "⚠️  Icon generation skipped (optional)"

# Try to create icns
if [ -d "$ICONSET_DIR" ] && [ "$(ls -A "$ICONSET_DIR" 2>/dev/null)" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
rm -rf "$ICONSET_DIR"

echo "✅ App bundle created at: $APP_BUNDLE"
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo ""
echo "⚠️  First run setup:"
echo "  1. Grant Microphone access when prompted"
echo "  2. Grant Accessibility access in System Settings > Privacy & Security > Accessibility"
echo "  3. Hold Right Option key to record, release to transcribe & paste"
