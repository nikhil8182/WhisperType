#!/usr/bin/env python3
"""Turn a square artwork PNG into AppIcon.icns with the macOS squircle mask.
usage: make_icns.py <artwork.png> <out.icns>   (uses /usr/bin/python3 + AppKit)"""
import sys, os, subprocess, tempfile
import AppKit, Cocoa

src, out = sys.argv[1], sys.argv[2]
art = AppKit.NSImage.alloc().initWithContentsOfFile_(src)
assert art, "cannot read artwork"

def render(size):
    img = AppKit.NSImage.alloc().initWithSize_(Cocoa.NSSize(size, size))
    img.lockFocus()
    # Apple icon grid: artwork occupies ~80% of the canvas, corner radius ~22.5% of that
    inset = size * 0.10
    box = Cocoa.NSRect(Cocoa.NSPoint(inset, inset), Cocoa.NSSize(size - 2*inset, size - 2*inset))
    r = box.size.width * 0.225
    path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(box, r, r)
    # soft shadow
    AppKit.NSGraphicsContext.saveGraphicsState()
    sh = AppKit.NSShadow.alloc().init()
    sh.setShadowOffset_(Cocoa.NSSize(0, -size*0.01)); sh.setShadowBlurRadius_(size*0.03)
    sh.setShadowColor_(AppKit.NSColor.colorWithWhite_alpha_(0, 0.35)); sh.set()
    AppKit.NSColor.colorWithRed_green_blue_alpha_(0.04, 0.06, 0.10, 1).setFill(); path.fill()
    AppKit.NSGraphicsContext.restoreGraphicsState()
    AppKit.NSGraphicsContext.saveGraphicsState()
    path.addClip()
    art.drawInRect_fromRect_operation_fraction_(box, Cocoa.NSZeroRect, AppKit.NSCompositingOperationSourceOver, 1.0)
    AppKit.NSGraphicsContext.restoreGraphicsState()
    img.unlockFocus()
    tiff = img.TIFFRepresentation()
    rep = AppKit.NSBitmapImageRep.imageRepWithData_(tiff)
    rep.setSize_(Cocoa.NSSize(size, size))
    return rep.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, {})

tmp = tempfile.mkdtemp(); iconset = os.path.join(tmp, "AppIcon.iconset"); os.makedirs(iconset)
for pts in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pts * scale
        name = f"icon_{pts}x{pts}" + ("@2x" if scale == 2 else "") + ".png"
        render(px).writeToFile_atomically_(os.path.join(iconset, name), True)
subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", out])
print("wrote", out)
