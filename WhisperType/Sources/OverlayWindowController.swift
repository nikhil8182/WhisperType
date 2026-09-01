import Cocoa

/// Floating "listening" pill. Pure AppKit (no SwiftUI: NSHostingView crashes on macOS 26).
///
///  ┌──────────────────────────────────────────────────────────┐
///  │ (Iniyal)  LISTENING                       release ⌥ to paste │
///  │           ▁▃▅▇▅▃▁ live waveform  /  live text tail          │
///  └──────────────────────────────────────────────────────────┘
class OverlayWindowController {
    enum Kind { case recording, handsFree, transcribing, polishing }

    private static let width: CGFloat = 520
    private static let height: CGFloat = 68
    private static let avatarSize: CGFloat = 44

    private var window: NSWindow?
    private var stageLabel: NSTextField!
    private var textLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var waveform: WaveformView!
    private var avatarRing: NSView!
    private var progress: NSProgressIndicator!
    private var currentKind: Kind?
    private var hideWork: DispatchWorkItem?

    // MARK: - API

    func show(text: String, kind: Kind) {
        if window == nil { createWindow() }
        hideWork?.cancel()
        if kind != currentKind {
            currentKind = kind
            applyKind(kind)
        }
        let hasText = !text.isEmpty
        textLabel.stringValue = text
        textLabel.isHidden = !hasText
        waveform.isHidden = hasText || !(kind == .recording || kind == .handsFree)
        guard let w = window, let glass = w.contentView else { return }
        if !w.isVisible {
            w.alphaValue = 1
            glass.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                glass.animator().alphaValue = 1
            }
            logInfo("Overlay", "shown kind=\(kind) frame=\(w.frame) screen=\(NSScreen.main?.frame ?? .zero) visible=\(w.isVisible)")
        }
    }

    func hide() {
        guard let w = window, w.isVisible else { return }
        waveform.stop()
        progress.stopAnimation(nil)
        currentKind = nil
        let work = DispatchWorkItem { [weak self] in
            guard let glass = w.contentView else { w.orderOut(nil); return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                glass.animator().alphaValue = 0
            }, completionHandler: {
                if self?.hideWork?.isCancelled == false { w.orderOut(nil) }
            })
        }
        hideWork = work
        // Let the final text sit for a beat before fading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: - Stage styling

    private struct Style { let stage: String; let hint: String; let accent: NSColor }

    private func style(for kind: Kind) -> Style {
        switch kind {
        case .recording:    return Style(stage: "LISTENING",   hint: "release ⌥ to paste",   accent: NSColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 1))   // sky #38BDF8
        case .handsFree:    return Style(stage: "HANDS-FREE",  hint: "tap ⌥ to stop",        accent: NSColor(srgbRed: 0.05, green: 0.69, blue: 0.29, alpha: 1))   // green #0DB14B
        case .transcribing: return Style(stage: "TRANSCRIBING", hint: "",                    accent: NSColor(srgbRed: 0.96, green: 0.65, blue: 0.14, alpha: 1))   // amber #F5A623
        case .polishing:    return Style(stage: "POLISHING",   hint: "",                     accent: NSColor(srgbRed: 0.66, green: 0.55, blue: 0.98, alpha: 1))   // violet
        }
    }

    private func applyKind(_ kind: Kind) {
        let st = style(for: kind)
        stageLabel.stringValue = st.stage
        stageLabel.textColor = st.accent
        hintLabel.stringValue = st.hint
        waveform.color = st.accent
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            avatarRing.animator().layer?.borderColor = st.accent.cgColor
        }
        avatarRing.layer?.borderColor = st.accent.cgColor
        avatarRing.layer?.shadowColor = st.accent.cgColor
        switch kind {
        case .recording, .handsFree:
            progress.stopAnimation(nil); progress.isHidden = true
            waveform.start()
        case .transcribing, .polishing:
            waveform.stop()
            progress.isHidden = false
            progress.startAnimation(nil)
        }
    }

    // MARK: - Build

    private func createWindow() {
        let W = OverlayWindowController.width, H = OverlayWindowController.height
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.appearance = NSAppearance(named: .darkAqua)

        // Glass pill
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = H / 2
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true

        let tint = NSView(frame: glass.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 0.04, green: 0.06, blue: 0.10, alpha: 0.72).cgColor  // navy #0A0F1A
        tint.autoresizingMask = [.width, .height]
        glass.addSubview(tint)

        let border = NSView(frame: glass.bounds)
        border.wantsLayer = true
        border.layer?.cornerRadius = H / 2
        border.layer?.cornerCurve = .continuous
        border.layer?.borderWidth = 1
        border.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        border.autoresizingMask = [.width, .height]
        glass.addSubview(border)

        // Avatar with accent ring
        let A = OverlayWindowController.avatarSize
        let ring = NSView(frame: NSRect(x: 12, y: (H - A) / 2, width: A, height: A))
        ring.wantsLayer = true
        ring.layer?.cornerRadius = A / 2
        ring.layer?.borderWidth = 2
        ring.layer?.borderColor = NSColor.systemBlue.cgColor
        ring.layer?.shadowOpacity = 0.55
        ring.layer?.shadowRadius = 8
        ring.layer?.shadowOffset = .zero
        glass.addSubview(ring)
        avatarRing = ring

        let avatar = NSImageView(frame: ring.bounds.insetBy(dx: 3, dy: 3))
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = avatar.bounds.width / 2
        avatar.layer?.masksToBounds = true
        avatar.imageScaling = .scaleProportionallyUpOrDown
        if let path = Bundle.main.path(forResource: "iniyal_face", ofType: "png"), let img = NSImage(contentsOfFile: path) {
            avatar.image = img
        } else {
            avatar.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
            avatar.contentTintColor = .white
        }
        ring.addSubview(avatar)

        // Text column
        let left = 12 + A + 14
        let stage = NSTextField(labelWithString: "LISTENING")
        stage.frame = NSRect(x: left, y: H - 26, width: 200, height: 14)
        stage.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        stage.textColor = .systemBlue
        stage.alignment = .left
        if let f = stage.font { stage.attributedStringValue = NSAttributedString(string: "LISTENING", attributes: [.font: f, .kern: 1.6, .foregroundColor: NSColor.systemBlue]) }
        glass.addSubview(stage)
        stageLabel = stage

        let hint = NSTextField(labelWithString: "")
        hint.frame = NSRect(x: W - 220, y: H - 26, width: 204, height: 14)
        hint.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        hint.textColor = NSColor(white: 1, alpha: 0.45)
        hint.alignment = .right
        glass.addSubview(hint)
        hintLabel = hint

        let bodyW = W - CGFloat(left) - 16
        let text = NSTextField(labelWithString: "")
        text.frame = NSRect(x: CGFloat(left), y: 10, width: bodyW, height: 22)
        text.font = NSFont.systemFont(ofSize: 14.5, weight: .medium)
        text.textColor = .white
        text.lineBreakMode = .byTruncatingHead
        text.maximumNumberOfLines = 1
        text.cell?.truncatesLastVisibleLine = true
        text.isHidden = true
        glass.addSubview(text)
        textLabel = text

        let wave = WaveformView(frame: NSRect(x: CGFloat(left), y: 10, width: bodyW, height: 24))
        glass.addSubview(wave)
        waveform = wave

        let spin = NSProgressIndicator(frame: NSRect(x: W - 34, y: 10, width: 18, height: 18))
        spin.style = .spinning
        spin.controlSize = .small
        spin.isIndeterminate = true
        spin.isHidden = true
        spin.appearance = NSAppearance(named: .darkAqua)
        glass.addSubview(spin)
        progress = spin

        w.contentView = glass
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            w.setFrameOrigin(NSPoint(x: f.midX - W / 2, y: f.maxY - H - 18))
        }
        window = w
    }
}

/// Rounded-bar waveform driven by the mic level; idle bars breathe gently so it never looks dead.
final class WaveformView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }
    private let barCount = 28
    private var history: [CGFloat] = []
    private var timer: Timer?
    private var phase: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        history = Array(repeating: 0, count: barCount)
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        timer?.invalidate()
        history = Array(repeating: 0, count: barCount)
        timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        phase += 0.18
        let lvl = CGFloat(AudioRecorder.shared.level)
        let idle = 0.06 + 0.04 * (1 + sin(phase))
        history.removeFirst()
        history.append(max(idle, lvl))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let n = history.count
        let gap: CGFloat = 3
        let barW = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let midY = bounds.midY
        for (i, v) in history.enumerated() {
            let h = max(3, v * bounds.height)
            let x = CGFloat(i) * (barW + gap)
            let r = NSRect(x: x, y: midY - h / 2, width: barW, height: h)
            let age = CGFloat(i) / CGFloat(n - 1)            // older bars fade to the left
            color.withAlphaComponent(0.25 + 0.75 * age).setFill()
            NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }
}
