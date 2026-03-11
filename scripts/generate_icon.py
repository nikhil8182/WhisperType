#!/usr/bin/env python3
"""Generate WhisperType app icon using CoreGraphics/AppKit.
Design: Stylized microphone with sound waves on deep blue → teal gradient.
"""
import Cocoa
import AppKit
import math
import os
import subprocess
import sys

# NSBezierPath line cap style constants
NSLineCapStyleRound = 1  # NSRoundLineCapStyle


def generate_icon(size, output_path):
    """Generate a single icon at the given pixel size."""
    img = AppKit.NSImage.alloc().initWithSize_(Cocoa.NSSize(size, size))
    img.lockFocus()

    # --- Background: Rounded rect with gradient ---
    corner_radius = size * 0.22
    rect = Cocoa.NSRect(Cocoa.NSPoint(0, 0), Cocoa.NSSize(size, size))
    bg_path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        rect, corner_radius, corner_radius
    )
    bg_path.addClip()

    # Gradient: deep blue (#1a1a2e) → teal (#16a085)
    gradient = AppKit.NSGradient.alloc().initWithStartingColor_endingColor_(
        AppKit.NSColor.colorWithRed_green_blue_alpha_(0.102, 0.102, 0.180, 1.0),
        AppKit.NSColor.colorWithRed_green_blue_alpha_(0.086, 0.627, 0.522, 1.0),
    )
    gradient.drawInRect_angle_(rect, 315)

    # --- Subtle radial glow in center ---
    cx, cy = size * 0.5, size * 0.45
    for i in range(15):
        r = size * 0.35 * (1.0 - i / 15.0)
        alpha = 0.06 * (1.0 - i / 15.0)
        c = AppKit.NSColor.colorWithRed_green_blue_alpha_(0.3, 0.9, 0.8, alpha)
        c.setFill()
        oval = AppKit.NSBezierPath.bezierPathWithOvalInRect_(
            Cocoa.NSRect(Cocoa.NSPoint(cx - r, cy - r), Cocoa.NSSize(r * 2, r * 2))
        )
        oval.fill()

    # --- Microphone body (capsule shape) ---
    mic_width = size * 0.20
    mic_height = size * 0.32
    mic_x = (size - mic_width) / 2
    mic_y = size * 0.38
    mic_corner = mic_width * 0.5

    mic_rect = Cocoa.NSRect(
        Cocoa.NSPoint(mic_x, mic_y),
        Cocoa.NSSize(mic_width, mic_height)
    )
    mic_path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        mic_rect, mic_corner, mic_corner
    )
    AppKit.NSColor.whiteColor().setFill()
    mic_path.fill()

    # Mic grille lines
    grille_color = AppKit.NSColor.colorWithRed_green_blue_alpha_(0.80, 0.80, 0.80, 0.5)
    grille_color.setStroke()
    num_lines = 5
    for i in range(1, num_lines + 1):
        frac = i / (num_lines + 1)
        ly = mic_y + mic_height * (0.2 + frac * 0.6)
        # Calculate horizontal bounds at this y position within the capsule
        dy = ly - (mic_y + mic_height / 2)
        half_h = mic_height / 2
        # For capsule, the width varies based on position
        if abs(dy) < half_h - mic_corner:
            hw = mic_width / 2
        else:
            dist_from_cap_center = abs(dy) - (half_h - mic_corner)
            if dist_from_cap_center > mic_corner:
                continue
            hw = math.sqrt(max(0, mic_corner**2 - dist_from_cap_center**2))
        
        line = AppKit.NSBezierPath()
        line.setLineWidth_(max(1, size * 0.005))
        line.moveToPoint_(Cocoa.NSPoint(cx - hw * 0.7, ly))
        line.lineToPoint_(Cocoa.NSPoint(cx + hw * 0.7, ly))
        line.stroke()

    # --- Mic stand: U-shape cradle ---
    stand_color = AppKit.NSColor.colorWithRed_green_blue_alpha_(1.0, 1.0, 1.0, 0.85)
    stand_color.setStroke()
    sw = max(1.5, size * 0.014)

    u_inset = mic_width * 0.3
    u_left = mic_x - u_inset
    u_right = mic_x + mic_width + u_inset
    u_top = mic_y + mic_height * 0.5
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

    # Vertical stem
    stem_bottom = size * 0.18
    stem = AppKit.NSBezierPath()
    stem.setLineWidth_(sw)
    stem.moveToPoint_(Cocoa.NSPoint(cx, u_bottom))
    stem.lineToPoint_(Cocoa.NSPoint(cx, stem_bottom))
    stem.stroke()

    # Base plate
    base_hw = size * 0.10
    base = AppKit.NSBezierPath()
    base.setLineWidth_(sw)
    base.setLineCapStyle_(NSLineCapStyleRound)
    base.moveToPoint_(Cocoa.NSPoint(cx - base_hw, stem_bottom))
    base.lineToPoint_(Cocoa.NSPoint(cx + base_hw, stem_bottom))
    base.stroke()

    # --- Sound waves (arcs on each side) ---
    wave_cy = mic_y + mic_height * 0.65

    for side in [-1, 1]:
        for radius_mult, alpha, lw_mult in [(0.22, 0.6, 0.018), (0.32, 0.38, 0.015), (0.42, 0.20, 0.012)]:
            wave_r = size * radius_mult
            wave_color = AppKit.NSColor.colorWithRed_green_blue_alpha_(1.0, 1.0, 1.0, alpha)
            wave_color.setStroke()

            wave = AppKit.NSBezierPath()
            wave.setLineWidth_(max(1, size * lw_mult))
            wave.setLineCapStyle_(NSLineCapStyleRound)

            if side == 1:
                wave.appendBezierPathWithArcWithCenter_radius_startAngle_endAngle_clockwise_(
                    Cocoa.NSPoint(cx, wave_cy), wave_r, -35, 35, False
                )
            else:
                wave.appendBezierPathWithArcWithCenter_radius_startAngle_endAngle_clockwise_(
                    Cocoa.NSPoint(cx, wave_cy), wave_r, 145, 215, False
                )
            wave.stroke()

    img.unlockFocus()

    # Save as PNG
    tiff = img.TIFFRepresentation()
    bitmap = AppKit.NSBitmapImageRep.alloc().initWithData_(tiff)
    png_data = bitmap.representationUsingType_properties_(
        AppKit.NSPNGFileType, {}
    )
    png_data.writeToFile_atomically_(output_path, True)


def main():
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    iconset_dir = os.path.join(project_dir, "build", "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    print("🎨 Generating WhisperType app icon...")
    for base_size, scale in sizes:
        actual_size = base_size * scale
        if scale > 1:
            name = f"icon_{base_size}x{base_size}@{scale}x.png"
        else:
            name = f"icon_{base_size}x{base_size}.png"

        output_path = os.path.join(iconset_dir, name)
        print(f"  {name} ({actual_size}x{actual_size})")
        generate_icon(actual_size, output_path)

    # Convert to icns
    icns_path = os.path.join(project_dir, "build", "AppIcon.icns")
    print("  Converting to .icns...")
    result = subprocess.run(
        ["iconutil", "-c", "icns", iconset_dir, "-o", icns_path],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  ERROR: iconutil failed: {result.stderr}")
        sys.exit(1)

    print(f"  ✅ Icon saved: {icns_path}")

    # Cleanup iconset
    import shutil
    shutil.rmtree(iconset_dir)

    return icns_path


if __name__ == "__main__":
    main()
