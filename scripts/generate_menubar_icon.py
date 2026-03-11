#!/usr/bin/env python3
"""Generate menu bar template images for WhisperType (mic icon)."""
import Cocoa
import AppKit
import math
import os

NSLineCapStyleRound = 1


def generate_menubar_icon(size, output_path):
    """Generate a mic template icon at the given size. Black on transparent."""
    img = AppKit.NSImage.alloc().initWithSize_(Cocoa.NSSize(size, size))
    img.lockFocus()

    black = AppKit.NSColor.blackColor()
    
    # Microphone body (capsule)
    mic_w = size * 0.32
    mic_h = size * 0.42
    mic_x = (size - mic_w) / 2
    mic_y = size * 0.38
    mic_r = mic_w / 2
    cx = size / 2

    mic_rect = Cocoa.NSRect(Cocoa.NSPoint(mic_x, mic_y), Cocoa.NSSize(mic_w, mic_h))
    mic_path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        mic_rect, mic_r, mic_r
    )
    black.setFill()
    mic_path.fill()

    # U-shape cradle
    black.setStroke()
    sw = max(1.2, size * 0.06)
    u_inset = mic_w * 0.35
    u_left = mic_x - u_inset
    u_right = mic_x + mic_w + u_inset
    u_top = mic_y + mic_h * 0.45
    u_bottom = mic_y - size * 0.02
    u_radius = (u_right - u_left) / 2

    u_path = AppKit.NSBezierPath()
    u_path.setLineWidth_(sw)
    u_path.setLineCapStyle_(NSLineCapStyleRound)
    u_path.moveToPoint_(Cocoa.NSPoint(u_left, u_top))
    u_path.lineToPoint_(Cocoa.NSPoint(u_left, u_bottom + u_radius))
    u_path.appendBezierPathWithArcFromPoint_toPoint_radius_(
        Cocoa.NSPoint(u_left, u_bottom),
        Cocoa.NSPoint(cx, u_bottom),
        u_radius
    )
    u_path.appendBezierPathWithArcFromPoint_toPoint_radius_(
        Cocoa.NSPoint(u_right, u_bottom),
        Cocoa.NSPoint(u_right, u_bottom + u_radius),
        u_radius
    )
    u_path.lineToPoint_(Cocoa.NSPoint(u_right, u_top))
    u_path.stroke()

    # Stem
    stem_bottom = size * 0.14
    stem = AppKit.NSBezierPath()
    stem.setLineWidth_(sw)
    stem.moveToPoint_(Cocoa.NSPoint(cx, u_bottom))
    stem.lineToPoint_(Cocoa.NSPoint(cx, stem_bottom))
    stem.stroke()

    # Base
    base_hw = size * 0.16
    base = AppKit.NSBezierPath()
    base.setLineWidth_(sw)
    base.setLineCapStyle_(NSLineCapStyleRound)
    base.moveToPoint_(Cocoa.NSPoint(cx - base_hw, stem_bottom))
    base.lineToPoint_(Cocoa.NSPoint(cx + base_hw, stem_bottom))
    base.stroke()

    img.unlockFocus()

    tiff = img.TIFFRepresentation()
    bitmap = AppKit.NSBitmapImageRep.alloc().initWithData_(tiff)
    png_data = bitmap.representationUsingType_properties_(AppKit.NSPNGFileType, {})
    png_data.writeToFile_atomically_(output_path, True)


def main():
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    resources_dir = os.path.join(project_dir, "WhisperType", "Resources")
    os.makedirs(resources_dir, exist_ok=True)

    print("🎨 Generating menu bar icons...")
    
    # 18x18 @1x
    path_1x = os.path.join(resources_dir, "MenuBarIcon.png")
    generate_menubar_icon(18, path_1x)
    print(f"  MenuBarIcon.png (18x18)")

    # 36x36 @2x
    path_2x = os.path.join(resources_dir, "MenuBarIcon@2x.png")
    generate_menubar_icon(36, path_2x)
    print(f"  MenuBarIcon@2x.png (36x36)")

    print("  ✅ Menu bar icons saved")


if __name__ == "__main__":
    main()
