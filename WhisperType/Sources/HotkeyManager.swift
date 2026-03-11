import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var appState: AppState?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isRecording = false
    private var recordingStartTime: Date?
    private var overlayWindow: OverlayWindowController?
    private let lock = NSLock()

    /// Prevents re-entrant calls from rapid key events
    private var isProcessing = false

    /// Consecutive failure count — triggers harder reset
    private var consecutiveFailures = 0
    private static let maxConsecutiveFailures = 3

    private init() {}

    func setup(appState: AppState) {
        self.appState = appState
        setupFlagsMonitor()
        logInfo("HotkeyManager", "Setup complete. Hotkey keyCode=\(appState.hotkeyKeyCode)")
    }

    private func setupFlagsMonitor() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        logInfo("HotkeyManager", "Flags monitors registered")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let appState = appState else { return }

        let keyCode = Int(event.keyCode)
        let targetKeyCode = appState.hotkeyKeyCode

        guard keyCode == targetKeyCode else { return }

        let isOptionPressed = event.modifierFlags.contains(.option)

        lock.lock()
        let currentlyRecording = isRecording
        let processing = isProcessing
        lock.unlock()

        DispatchQueue.main.async {
            if isOptionPressed && !currentlyRecording && !processing {
                logInfo("HotkeyManager", "Hotkey pressed — starting recording")
                self.startRecording()
            } else if !isOptionPressed && currentlyRecording {
                logInfo("HotkeyManager", "Hotkey released — stopping recording")
                self.stopRecordingAndTranscribe()
            }
        }
    }

    private func startRecording() {
        guard let appState = appState else { return }
        
        // Close onboarding window if open — its SwiftUI NSHostingView causes
        // constraint crashes when AppState updates during recording (macOS 26 bug)
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            OnboardingWindowController.shared.close()
            NSApp.setActivationPolicy(.accessory)
        }

        lock.lock()
        guard !isRecording && !isProcessing else {
            logWarn("HotkeyManager", "startRecording blocked: isRecording=\(isRecording), isProcessing=\(isProcessing)")
            lock.unlock()
            return
        }

        let currentStatus = appState.status
        guard currentStatus == .idle else {
            logWarn("HotkeyManager", "startRecording blocked: status is \(currentStatus.rawValue)")
            lock.unlock()
            return
        }

        isRecording = true
        isProcessing = true
        recordingStartTime = Date()
        lock.unlock()

        appState.setStatus(.recording)

        if appState.playSounds {
            SoundManager.shared.playStartSound()
        }

        if appState.showFloatingOverlay {
            showOverlay(text: "🎙 Recording...")
        }

        AudioRecorder.shared.startRecording()
        logInfo("HotkeyManager", "Audio recording started")

        lock.lock()
        isProcessing = false
        lock.unlock()
    }

    private func stopRecordingAndTranscribe() {
        guard let appState = appState else { return }

        lock.lock()
        guard isRecording else {
            logWarn("HotkeyManager", "stopRecording called but not recording")
            lock.unlock()
            return
        }

        isRecording = false
        isProcessing = true
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        lock.unlock()

        logInfo("HotkeyManager", "Recording duration: \(String(format: "%.1f", duration))s")

        AudioRecorder.shared.stopRecording { [weak self] audioURL in
            guard let self = self else { return }

            guard let audioURL = audioURL else {
                logError("HotkeyManager", "stopRecording returned nil URL")
                self.handleFailure(appState: appState, message: "Recording failed — no audio file")
                return
            }

            // Skip very short recordings (< 0.3s — likely accidental)
            if duration < 0.3 {
                logInfo("HotkeyManager", "Recording too short (\(String(format: "%.2f", duration))s), skipping")
                self.resetState()
                DispatchQueue.main.async {
                    appState.setStatus(.idle)
                    self.hideOverlay()
                }
                try? FileManager.default.removeItem(at: audioURL)
                return
            }

            DispatchQueue.main.async {
                appState.setStatus(.transcribing)

                if appState.playSounds {
                    SoundManager.shared.playStopSound()
                }

                if appState.showFloatingOverlay {
                    self.showOverlay(text: "⏳ Transcribing...")
                }
            }

            logInfo("HotkeyManager", "Sending to WhisperManager for transcription")
            WhisperManager.shared.transcribe(audioURL: audioURL, model: appState.whisperModel, language: appState.language) { [weak self] result in
                guard let self = self else { return }

                try? FileManager.default.removeItem(at: audioURL)
                logDebug("HotkeyManager", "Cleaned up audio file")

                DispatchQueue.main.async {
                    self.hideOverlay()

                    switch result {
                    case .success(let text):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            logWarn("HotkeyManager", "Transcription returned empty text")
                            self.resetState()
                            appState.setStatus(.idle)
                            return
                        }

                        logInfo("HotkeyManager", "Transcription success: \(trimmed.prefix(80))...")

                        // Reset failure counter on success
                        self.consecutiveFailures = 0

                        let entry = TranscriptionEntry(text: trimmed, duration: duration, model: appState.whisperModel)
                        appState.addToHistory(entry)

                        TextPaster.shared.pasteText(trimmed)

                        // Delay reset to let paste + clipboard restore finish
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.resetState()
                            appState.setStatus(.idle)
                        }

                    case .failure(let error):
                        logError("HotkeyManager", "Transcription failed: \(error.localizedDescription)")
                        self.handleFailure(appState: appState, message: "Transcription failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Handle failures with escalating recovery
    private func handleFailure(appState: AppState, message: String) {
        consecutiveFailures += 1
        logWarn("HotkeyManager", "Failure #\(consecutiveFailures): \(message)")

        if consecutiveFailures >= HotkeyManager.maxConsecutiveFailures {
            logError("HotkeyManager", "Too many consecutive failures (\(consecutiveFailures)), performing hard reset")
            AudioRecorder.shared.forceReset()
            consecutiveFailures = 0
        }

        resetState()
        DispatchQueue.main.async {
            appState.setStatus(.idle)
            appState.showError(message)
            self.hideOverlay()
        }
    }

    /// Reset all internal state to allow next recording cycle
    private func resetState() {
        lock.lock()
        isRecording = false
        isProcessing = false
        recordingStartTime = nil
        lock.unlock()
        logDebug("HotkeyManager", "State reset — ready for next cycle")
    }

    private func showOverlay(text: String) {
        assert(Thread.isMainThread)
        if overlayWindow == nil {
            overlayWindow = OverlayWindowController()
        }
        overlayWindow?.show(text: text)
    }

    private func hideOverlay() {
        assert(Thread.isMainThread)
        overlayWindow?.hide()
    }

    deinit {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
