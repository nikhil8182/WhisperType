import Cocoa

/// Non-activating AppKit HUD: it never takes focus from the dictation target.
final class OverlayWindowController {
    enum Kind { case recording, handsFree, transcribing, polishing, ready, attention, error }

    private let width: CGFloat = 440
    private let height: CGFloat = 112
    private var window: NSPanel?
    private var stageLabel: NSTextField!
    private var textLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var waveform: WaveformView!
    private var statusSymbol: NSImageView!
    private var progress: NSProgressIndicator!
    private var accentLine: NSView!
    private var currentKind: Kind?
    private var presentationID = UUID()
    private var hideWork: DispatchWorkItem?
    private var previewTimer: Timer?
    private var isPreview = false

    func show(text: String, kind: Kind) {
        if window == nil { createWindow() }
        presentationID = UUID()
        hideWork?.cancel()
        hideWork = nil
        let style = style(for: kind)
        stageLabel.stringValue = style.title
        stageLabel.textColor = style.accent
        hintLabel.stringValue = isPreview ? "Preview · no microphone" : style.hint
        textLabel.stringValue = text.isEmpty ? style.placeholder : text
        textLabel.textColor = text.isEmpty ? .secondaryLabelColor : .labelColor
        textLabel.setAccessibilityLabel(textLabel.stringValue)
        accentLine.layer?.backgroundColor = style.accent.withAlphaComponent(0.8).cgColor
        waveform.color = style.accent
        let listening = kind == .recording || kind == .handsFree
        waveform.isHidden = !listening
        statusSymbol.isHidden = kind != .ready && kind != .attention && kind != .error
        statusSymbol.image = NSImage(systemSymbolName: (kind == .attention || kind == .error) ? "exclamationmark.circle.fill" : "checkmark.circle.fill", accessibilityDescription: style.title)
        statusSymbol.contentTintColor = style.accent
        progress.isHidden = listening || !statusSymbol.isHidden
        if currentKind != kind {
            if listening { waveform.start(demo: isPreview) } else { waveform.stop() }
            if progress.isHidden { progress.stopAnimation(nil) } else { progress.startAnimation(nil) }
            currentKind = kind
        }
        guard let window, let content = window.contentView else { return }
        // Choose the active screen afresh for each recording, including after a display change.
        if !window.isVisible {
            let screen = NSScreen.main ?? NSScreen.screens.first
            if let frame = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.minY + 24))
            }
            content.alphaValue = reducedMotion ? 1 : 0
            window.orderFrontRegardless()
        }
        // Also restore opacity if a new recording interrupts the previous fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0 : 0.16
            content.animator().alphaValue = 1
        }
    }

    func hide(after delay: TimeInterval = 0.25) {
        guard let window, window.isVisible else { return }
        hideWork?.cancel()
        let id = presentationID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationID == id, let content = window.contentView else { return }
            self.waveform.stop()
            self.progress.stopAnimation(nil)
            self.currentKind = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.reducedMotion ? 0 : 0.18
                content.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.presentationID == id else { return }
                window.orderOut(nil)
                self.currentKind = nil
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// A visual tour of the real panel. No audio, history entries, or clipboard writes.
    func preview() {
        cancelPreview()
        isPreview = true
        let stages: [(Kind, String)] = [
            (.recording, "Speak naturally. Iniyal takes care of the typing."),
            (.handsFree, "Keep talking, without holding a key."),
            (.transcribing, "Your words are becoming text."),
            (.polishing, "A little polish. Still your words."),
            (.ready, "Ready for wherever you’re writing.")
        ]
        var index = 0
        show(text: stages[0].1, kind: stages[0].0)
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            index += 1
            guard index < stages.count else {
                timer.invalidate()
                self.previewTimer = nil
                self.isPreview = false
                self.hide()
                return
            }
            self.show(text: stages[index].1, kind: stages[index].0)
        }
        if let previewTimer { RunLoop.main.add(previewTimer, forMode: .common) }
    }

    func cancelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        if isPreview {
            isPreview = false
            presentationID = UUID()
            hideWork?.cancel()
            waveform?.stop()
            progress?.stopAnimation(nil)
            window?.orderOut(nil)
            currentKind = nil
        }
    }

    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private struct Style { let title: String; let hint: String; let placeholder: String; let accent: NSColor }
    private func style(for kind: Kind) -> Style {
        let key = AppState.shared.hotkeyKeyCode == 58 ? "Left ⌥" : "Right ⌥"
        switch kind {
        case .recording:
            return Style(title: "Listening", hint: "Release \(key)", placeholder: "Go ahead, I’m listening…", accent: .systemMint)
        case .handsFree:
            return Style(title: "Hands-free", hint: "Tap \(key) to finish", placeholder: "Take your time. No need to hold the key.", accent: .systemGreen)
        case .transcribing:
            return Style(title: "Finding your words", hint: "On your Mac", placeholder: "Turning your voice into text…", accent: .systemTeal)
        case .polishing:
            return Style(title: "Finishing touches", hint: "On your Mac", placeholder: "Tidying up your words…", accent: .systemPurple)
        case .ready:
            return Style(title: "Dictation ready", hint: "Saved in History", placeholder: "Your words are ready.", accent: .systemGreen)
        case .error:
            return Style(title: "Couldn’t finish", hint: "Try again", placeholder: "Please try another dictation.", accent: .systemOrange)
        case .attention:
            return Style(title: "One more step", hint: "Saved in History", placeholder: "Your text is available in History.", accent: .systemOrange)
        }
    }

    private func label(_ font: NSFont, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.frame = frame
        return label
    }

    private func createWindow() {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let panel = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Iniyal recording panel"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 24
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glass.material = .windowBackground
        }

        let avatar = NSImageView(frame: NSRect(x: 18, y: 59, width: 36, height: 36))
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 18
        avatar.layer?.masksToBounds = true
        avatar.imageScaling = .scaleProportionallyUpOrDown
        if let path = Bundle.main.path(forResource: "iniyal_face", ofType: "png") {
            avatar.image = NSImage(contentsOfFile: path)
        }
        avatar.setAccessibilityLabel("Iniyal")
        glass.addSubview(avatar)

        stageLabel = label(.systemFont(ofSize: 14, weight: .semibold), frame: NSRect(x: 65, y: 79, width: 238, height: 19))
        glass.addSubview(stageLabel)
        hintLabel = label(.systemFont(ofSize: 11, weight: .medium), frame: NSRect(x: 65, y: 60, width: 260, height: 16))
        hintLabel.textColor = .secondaryLabelColor
        glass.addSubview(hintLabel)

        waveform = WaveformView(frame: NSRect(x: 348, y: 66, width: 70, height: 26))
        glass.addSubview(waveform)
        progress = NSProgressIndicator(frame: NSRect(x: 390, y: 68, width: 20, height: 20))
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        glass.addSubview(progress)
        statusSymbol = NSImageView(frame: NSRect(x: 388, y: 66, width: 24, height: 24))
        glass.addSubview(statusSymbol)

        textLabel = label(.systemFont(ofSize: 13, weight: .regular), frame: NSRect(x: 20, y: 13, width: width - 40, height: 37))
        textLabel.maximumNumberOfLines = 2
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.cell?.wraps = true
        glass.addSubview(textLabel)
        accentLine = NSView(frame: NSRect(x: 24, y: 0, width: width - 48, height: 2))
        accentLine.wantsLayer = true
        accentLine.layer?.cornerRadius = 1
        glass.addSubview(accentLine)
        panel.contentView = glass
        window = panel
    }

    deinit { previewTimer?.invalidate(); hideWork?.cancel() }
}

/// Real microphone energy; demo motion is only used by the explicitly labelled preview.
final class WaveformView: NSView {
    var color: NSColor = .systemMint { didSet { needsDisplay = true } }
    private var history = Array(repeating: CGFloat(0), count: 12)
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var demo = false

    func start(demo: Bool = false) {
        stop()
        self.demo = demo
        history = Array(repeating: 0, count: 12)
        timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func tick() {
        phase += 0.22
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let level = demo ? (reduceMotion ? 0.3 : 0.18 + 0.5 * abs(sin(phase))) : CGFloat(AudioRecorder.shared.level)
        history.removeFirst()
        history.append(max(0.09, level))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let gap: CGFloat = 2.5
        let barWidth = (bounds.width - gap * CGFloat(history.count - 1)) / CGFloat(history.count)
        for (index, value) in history.enumerated() {
            let h = max(3, min(1, value) * bounds.height)
            color.withAlphaComponent(0.4 + 0.6 * CGFloat(index) / CGFloat(history.count - 1)).setFill()
            let rect = NSRect(x: CGFloat(index) * (barWidth + gap), y: bounds.midY - h / 2, width: barWidth, height: h)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
    deinit { stop() }
}
