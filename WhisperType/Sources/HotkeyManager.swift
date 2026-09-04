import Cocoa
import Carbon

/// Right Option (keyCode 61 by default):
///   hold          = push-to-talk (release to transcribe + paste)
///   double-tap    = hands-free recording, tap once more to stop
/// Live preview: while recording, the buffer is re-transcribed every ~1.5 s and shown in the overlay.
class HotkeyManager {
    static let shared = HotkeyManager()

    private var appState: AppState?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var overlayWindow: OverlayWindowController?

    // Recording state is confined to the main thread.
    private var isRecording = false
    private var isProcessing = false
    private var handsFree = false
    private var ignoreNextRelease = false
    private var recordingStartTime: Date?
    private var lastShortTap: Date?
    private var frontApp = EngineClient.FrontApp(bundle: "", name: "", title: "")

    // live preview
    private var partialTimer: Timer?
    private var recordingID = UUID()
    private var partialInFlight = false
    private var lastPartialSeconds: Double = 0
    private var lastPartialText = ""

    private var consecutiveFailures = 0
    private static let maxConsecutiveFailures = 3
    private static let shortTap: TimeInterval = 0.35
    private static let doubleTapWindow: TimeInterval = 0.6

    private init() {}

    func setup(appState: AppState) {
        self.appState = appState
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        logInfo("HotkeyManager", "Setup complete. Hotkey keyCode=\(appState.hotkeyKeyCode)")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let appState = appState else { return }
        guard Int(event.keyCode) == appState.hotkeyKeyCode else { return }
        let pressed = Self.isHotkeyPressed(keyCode: Int(event.keyCode), flags: event.modifierFlags)
        DispatchQueue.main.async {
            if pressed { self.onKeyDown() } else { self.onKeyUp() }
        }
    }

    static func isHotkeyPressed(keyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
        // Device-specific bits distinguish release while the OTHER Option key is held.
        let mask: UInt = keyCode == 61 ? 0x40 : 0x20
        return flags.rawValue & mask != 0
    }

    // MARK: - Key events (main thread)

    private func onKeyDown() {
        if handsFree && isRecording {
            ignoreNextRelease = true
            logInfo("HotkeyManager", "Hands-free stop")
            finishRecording()
            return
        }
        guard !isRecording, !isProcessing else { return }
        startRecording()
    }

    private func onKeyUp() {
        if ignoreNextRelease { ignoreNextRelease = false; return }
        guard isRecording, !handsFree else { return }
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        if duration < HotkeyManager.shortTap {
            let now = Date()
            if let t = lastShortTap, now.timeIntervalSince(t) < HotkeyManager.doubleTapWindow {
                lastShortTap = nil
                handsFree = true
                logInfo("HotkeyManager", "Double-tap → hands-free mode")
                showOverlay(text: lastPartialText, kind: .handsFree)
                return
            }
            lastShortTap = now
            logInfo("HotkeyManager", "Short tap (\(String(format: "%.2f", duration))s), discarding")
            cancelRecording()
            return
        }
        lastShortTap = nil
        logInfo("HotkeyManager", "Hotkey released — stopping recording")
        finishRecording()
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard let appState = appState else { return }
        guard appState.status == .idle else {
            logWarn("HotkeyManager", "startRecording blocked: status is \(appState.status.rawValue)")
            return
        }

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            OnboardingWindowController.shared.close()
            NSApp.setActivationPolicy(.accessory)
        }

        // Snapshot the target app BEFORE any UI of ours appears
        frontApp = EngineClient.captureFrontApp()

        recordingStartTime = Date()
        guard AudioRecorder.shared.startRecording() else {
            handleFailure(message: "Could not start microphone recording. Check microphone access and input device.")
            return
        }
        recordingID = UUID()
        isRecording = true
        handsFree = false
        lastPartialText = ""
        lastPartialSeconds = 0
        partialInFlight = false

        appState.setStatus(.recording)
        if appState.playSounds { SoundManager.shared.playStartSound() }
        if appState.showFloatingOverlay { showOverlay(text: "", kind: .recording) }

        logInfo("HotkeyManager", "Recording started (target: \(frontApp.name) \(frontApp.bundle))")

        if appState.livePreview && appState.engineAvailable {
            partialTimer?.invalidate()
            partialTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.tickPartial()
            }
        }
    }

    private func cancelRecording() {
        stopPartialTimer()
        isRecording = false
        handsFree = false
        recordingStartTime = nil
        AudioRecorder.shared.cancelRecording()
        appState?.setStatus(.idle)
        hideOverlay()
    }

    private func finishRecording() {
        guard let appState = appState, isRecording else { return }
        stopPartialTimer()
        isRecording = false
        handsFree = false
        isProcessing = true
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        let target = frontApp
        logInfo("HotkeyManager", "Recording duration: \(String(format: "%.1f", duration))s")

        AudioRecorder.shared.stopRecording { [weak self] audioURL, pcm in
            guard let self = self else { return }

            let seconds = Double(pcm.count / 4) / 16000.0
            let peak: Float = pcm.withUnsafeBytes { raw -> Float in
                let f = raw.bindMemory(to: Float.self)
                var m: Float = 0
                for v in f where abs(v) > m { m = abs(v) }
                return m
            }
            if audioURL == nil && pcm.isEmpty || (!pcm.isEmpty && peak < 0.015) {
                logInfo("HotkeyManager", "Nothing heard (\(String(format: "%.1f", seconds))s, peak \(String(format: "%.3f", peak))), skipping")
                if let url = audioURL { try? FileManager.default.removeItem(at: url) }
                self.resetState(); appState.setStatus(.idle); self.hideOverlay()
                return
            }

            appState.setStatus(.transcribing)
            if appState.playSounds { SoundManager.shared.playStopSound() }
            if appState.showFloatingOverlay { self.showOverlay(text: self.lastPartialText, kind: .transcribing) }

            if appState.engineAvailable && pcm.count > 16000 {
                EngineClient.shared.transcribe(pcm: pcm, language: appState.language, partial: false) { [weak self] result in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let t):
                            if let url = audioURL { try? FileManager.default.removeItem(at: url) }
                            logInfo("HotkeyManager", "Engine transcribed in \(t.ms)ms: \(t.text.prefix(80))")
                            self.deliver(raw: t.text, duration: duration, engine: "turbo", target: target)
                        case .failure(let e):
                            logError("HotkeyManager", "Engine transcription failed: \(e.localizedDescription)")
                            self.transcribeFallback(audioURL: audioURL, duration: duration, target: target)
                        }
                    }
                }
                return
            }

            self.transcribeFallback(audioURL: audioURL, duration: duration, target: target)
        }
    }

    private func transcribeFallback(audioURL: URL?, duration: TimeInterval, target: EngineClient.FrontApp) {
        guard let appState = appState else { return }
        guard let audioURL = audioURL else {
            handleFailure(message: "Recording failed: no audio file for fallback")
            return
        }
        logInfo("HotkeyManager", "Using whisper CLI fallback")
        WhisperManager.shared.transcribe(audioURL: audioURL, model: appState.whisperModel, language: appState.language) { [weak self] result in
            try? FileManager.default.removeItem(at: audioURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let text):
                    self.deliver(raw: text, duration: duration, engine: appState.whisperModel, target: target)
                case .failure(let error):
                    self.handleFailure(message: "Transcription failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Polish (if enabled + engine up) then paste. Main thread.
    private func deliver(raw: String, duration: TimeInterval, engine: String, target: EngineClient.FrontApp) {
        guard let appState = appState else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logWarn("HotkeyManager", "Transcription returned empty text")
            resetState(); appState.setStatus(.idle); hideOverlay()
            return
        }

        let finish: (String, String) -> Void = { [weak self] text, label in
            guard let self = self else { return }
            guard !text.isEmpty else {
                self.resetState(); appState.setStatus(.idle); self.hideOverlay()
                return
            }
            self.consecutiveFailures = 0
            appState.addToHistory(TranscriptionEntry(text: text, duration: duration, model: label))
            self.hideOverlay()
            TextPaster.shared.pasteText(text, targetPID: target.pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.resetState()
                appState.setStatus(.idle)
            }
        }

        if appState.smartCleanup && appState.engineAvailable {
            if appState.showFloatingOverlay { showOverlay(text: trimmed, kind: .polishing) }
            EngineClient.shared.polish(text: trimmed, app: target, styleOverride: appState.styleOverride) { p in
                DispatchQueue.main.async {
                    logInfo("HotkeyManager", "Polished [\(p.style)\(p.usedLLM ? "/llm" : "")] in \(p.ms)ms: \(p.text.prefix(80))")
                    finish(p.text, p.usedLLM ? "\(engine)+\(p.style)" : engine)
                }
            }
        } else {
            finish(trimmed, engine)
        }
    }

    // MARK: - Live preview

    private func tickPartial() {
        guard isRecording, !partialInFlight, let appState = appState, appState.engineAvailable else { return }
        let secs = AudioRecorder.shared.capturedSeconds
        guard secs >= 1.0, secs - lastPartialSeconds >= 0.8 else { return }
        partialInFlight = true
        lastPartialSeconds = secs
        let requestRecordingID = recordingID
        let pcm = AudioRecorder.shared.snapshotPCM()
        EngineClient.shared.transcribe(pcm: pcm, language: appState.language, partial: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.recordingID == requestRecordingID else { return }
                self.partialInFlight = false
                guard self.isRecording else { return }
                if case .success(let t) = result, !t.text.isEmpty {
                    self.lastPartialText = t.text
                    let tail = String(t.text.suffix(60))
                    self.showOverlay(text: (t.text.count > 60 ? "…" : "") + tail,
                                     kind: self.handsFree ? .handsFree : .recording)
                }
            }
        }
    }

    private func stopPartialTimer() {
        partialTimer?.invalidate()
        partialTimer = nil
    }

    // MARK: - Failure / reset

    private func handleFailure(message: String) {
        consecutiveFailures += 1
        logWarn("HotkeyManager", "Failure #\(consecutiveFailures): \(message)")
        if consecutiveFailures >= HotkeyManager.maxConsecutiveFailures {
            logError("HotkeyManager", "Too many consecutive failures, performing hard reset")
            AudioRecorder.shared.forceReset()
            consecutiveFailures = 0
        }
        resetState()
        DispatchQueue.main.async {
            self.appState?.setStatus(.idle)
            self.appState?.showError(message)
            self.hideOverlay()
        }
    }

    private func resetState() {
        stopPartialTimer()
        isRecording = false
        isProcessing = false
        handsFree = false
        ignoreNextRelease = false
        recordingStartTime = nil
        logDebug("HotkeyManager", "State reset — ready for next cycle")
    }

    private func showOverlay(text: String, kind: OverlayWindowController.Kind) {
        assert(Thread.isMainThread)
        if overlayWindow == nil { overlayWindow = OverlayWindowController() }
        overlayWindow?.show(text: text, kind: kind)
    }

    private func hideOverlay() {
        assert(Thread.isMainThread)
        overlayWindow?.hide()
    }

    deinit {
        if let monitor = flagsMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localFlagsMonitor { NSEvent.removeMonitor(monitor) }
    }
}
