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
    
    // Prevent re-entrant calls from rapid key events
    private var isProcessing = false
    
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
        
        if isOptionPressed && !currentlyRecording && !processing {
            logInfo("HotkeyManager", "Hotkey pressed — starting recording")
            startRecording()
        } else if !isOptionPressed && currentlyRecording {
            logInfo("HotkeyManager", "Hotkey released — stopping recording")
            stopRecordingAndTranscribe()
        }
    }
    
    private func startRecording() {
        guard let appState = appState else { return }
        
        lock.lock()
        // Guard against starting while already recording or processing
        guard !isRecording && !isProcessing else {
            logWarn("HotkeyManager", "startRecording called but already recording/processing. isRecording=\(isRecording), isProcessing=\(isProcessing)")
            lock.unlock()
            return
        }
        
        // Only start if idle
        let currentStatus = appState.status
        guard currentStatus == .idle else {
            logWarn("HotkeyManager", "startRecording called but status is \(currentStatus.rawValue), not idle")
            lock.unlock()
            return
        }
        
        isRecording = true
        isProcessing = true
        recordingStartTime = Date()
        lock.unlock()
        
        // UI updates on main thread
        DispatchQueue.main.async {
            appState.setStatus(.recording)
            
            if appState.playSounds {
                SoundManager.shared.playStartSound()
            }
            
            if appState.showFloatingOverlay {
                self.showOverlay(text: "🎙 Recording...")
            }
        }
        
        // Start audio recording
        AudioRecorder.shared.startRecording()
        logInfo("HotkeyManager", "Audio recording started")
        
        lock.lock()
        isProcessing = false  // Now we're just recording, not "processing"
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
                self.resetState()
                DispatchQueue.main.async {
                    appState.showError("Recording failed — no audio file")
                    self.hideOverlay()
                }
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
            
            // Transcribe
            logInfo("HotkeyManager", "Sending to WhisperManager for transcription")
            WhisperManager.shared.transcribe(audioURL: audioURL, model: appState.whisperModel, language: appState.language) { [weak self] result in
                guard let self = self else { return }
                
                // Clean up audio file
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
                        
                        // Add to history
                        let entry = TranscriptionEntry(text: trimmed, duration: duration, model: appState.whisperModel)
                        appState.addToHistory(entry)
                        
                        // Paste at cursor
                        TextPaster.shared.pasteText(trimmed)
                        
                        self.resetState()
                        appState.setStatus(.idle)
                        
                    case .failure(let error):
                        logError("HotkeyManager", "Transcription failed: \(error.localizedDescription)")
                        self.resetState()
                        appState.setStatus(.idle)
                        appState.showError("Transcription failed: \(error.localizedDescription)")
                    }
                }
            }
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
        // Must be called on main thread
        assert(Thread.isMainThread, "showOverlay must be called on main thread")
        if self.overlayWindow == nil {
            self.overlayWindow = OverlayWindowController()
        }
        self.overlayWindow?.show(text: text)
    }
    
    private func hideOverlay() {
        // Must be called on main thread
        assert(Thread.isMainThread, "hideOverlay must be called on main thread")
        self.overlayWindow?.hide()
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
