import Cocoa

/// Floating overlay using pure AppKit — no SwiftUI NSHostingView.
/// Avoids EXC_BREAKPOINT constraint crashes on macOS 26.
/// Shows live partial text while recording, then the pipeline stage.
class OverlayWindowController {
    enum Kind { case recording, handsFree, transcribing, polishing }

    private static let width: CGFloat = 420
    private static let height: CGFloat = 46

    private var window: NSWindow?
    private var containerView: NSView?
    private var textField: NSTextField?
    private var indicator: NSView?
    private var pulseTimer: Timer?
    private var currentKind: Kind?

    func show(text: String, kind: Kind) {
        if window == nil { createWindow() }
        textField?.stringValue = text
        if kind != currentKind {
            currentKind = kind
            applyKind(kind)
        }
        window?.orderFront(nil)
    }

    func hide() {
        stopPulse()
        currentKind = nil
        window?.orderOut(nil)
    }

    private func applyKind(_ kind: Kind) {
        indicator?.isHidden = false
        switch kind {
        case .recording:
            indicator?.layer?.backgroundColor = NSColor.systemRed.cgColor
            startPulse()
        case .handsFree:
            indicator?.layer?.backgroundColor = NSColor.systemGreen.cgColor
            startPulse()
        case .transcribing:
            indicator?.layer?.backgroundColor = NSColor.systemOrange.cgColor
            stopPulse()
        case .polishing:
            indicator?.layer?.backgroundColor = NSColor.systemPurple.cgColor
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
        let W = OverlayWindowController.width, H = OverlayWindowController.height
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.88).cgColor
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        container.layer?.borderWidth = 0.5

        let dot = NSView(frame: NSRect(x: 16, y: (H - 10) / 2, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.isHidden = true
        container.addSubview(dot)
        self.indicator = dot

        let label = NSTextField(frame: NSRect(x: 34, y: (H - 22) / 2, width: W - 50, height: 22))
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        label.stringValue = ""
        container.addSubview(label)
        self.textField = label

        w.contentView = container
        self.containerView = container

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            w.setFrameOrigin(NSPoint(x: screenFrame.midX - W / 2, y: screenFrame.maxY - 80))
        }
        self.window = w
    }
}
