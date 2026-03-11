import Cocoa

/// Floating overlay using pure AppKit — no SwiftUI NSHostingView.
/// Avoids EXC_BREAKPOINT constraint crashes on macOS 26.
class OverlayWindowController {
    private var window: NSWindow?
    private var containerView: NSView?
    private var textField: NSTextField?
    private var indicator: NSView?
    private var pulseTimer: Timer?

    func show(text: String) {
        if window == nil {
            createWindow()
        }
        updateContent(text: text)
        window?.orderFront(nil)
    }

    func hide() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        window?.orderOut(nil)
    }

    private func updateContent(text: String) {
        textField?.stringValue = text
        
        // Show red dot for recording, spinner-like for transcribing
        if text.contains("Recording") {
            indicator?.isHidden = false
            indicator?.layer?.backgroundColor = NSColor.red.cgColor
            startPulse()
        } else if text.contains("Transcribing") {
            indicator?.isHidden = false
            indicator?.layer?.backgroundColor = NSColor.orange.cgColor
            stopPulse()
        } else {
            indicator?.isHidden = true
            stopPulse()
        }
    }

    private func startPulse() {
        pulseTimer?.invalidate()
        var bright = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let indicator = self?.indicator else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                indicator.animator().alphaValue = bright ? 0.3 : 1.0
            }
            bright.toggle()
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        indicator?.alphaValue = 1.0
    }

    private func createWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.isMovableByWindowBackground = false
        w.hasShadow = true
        w.ignoresMouseEvents = true

        // Container with rounded background
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.85).cgColor
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        container.layer?.borderWidth = 0.5

        // Red/orange dot indicator
        let dot = NSView(frame: NSRect(x: 16, y: 17, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.red.cgColor
        dot.isHidden = true
        container.addSubview(dot)
        self.indicator = dot

        // Text label
        let label = NSTextField(frame: NSRect(x: 34, y: 10, width: 170, height: 24))
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .left
        label.stringValue = ""
        container.addSubview(label)
        self.textField = label

        w.contentView = container
        self.containerView = container

        // Position at top center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
            let y = screenFrame.maxY - 80
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = w
    }
}
