import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var appState: AppState?
    private var flagsMonitor: Any?
    private var isRecording = false
    private var recordingStartTime: Date?
    private var overlayWindow: OverlayWindowController?
    
    private init() {}
    
    func setup(appState: AppState) {
        self.appState = appState
        setupFlagsMonitor()
    }
    
    private func setupFlagsMonitor() {
        // Monitor global key events for the hotkey (Right Option key)
        // We use flagsChanged to detect modifier keys
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // Also monitor local events (when our app is focused)
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        guard let appState = appState else { return }
        
        let keyCode = Int(event.keyCode)
        let targetKeyCode = appState.hotkeyKeyCode
        
        // Right Option key = keyCode 61
        guard keyCode == targetKeyCode else { return }
        
        let isOptionPressed = event.modifierFlags.contains(.option)
        
        if isOptionPressed && !isRecording {
            // Key pressed - start recording
            startRecording()
        } else if !isOptionPressed && isRecording {
            // Key released - stop recording and transcribe
            stopRecordingAndTranscribe()
        }
    }
    
    private func startRecording() {
        guard let appState = appState else { return }
        guard appState.status == .idle else { return }
        
        isRecording = true
        recordingStartTime = Date()
        
        DispatchQueue.main.async {
            appState.status = .recording
            
            // Play start sound
            if appState.playSounds {
                SoundManager.shared.playStartSound()
            }
            
            // Show overlay
            if appState.showFloatingOverlay {
                self.showOverlay(text: "🎙 Recording...")
            }
        }
        
        // Start audio recording
        AudioRecorder.shared.startRecording()
    }
    
    private func stopRecordingAndTranscribe() {
        guard let appState = appState else { return }
        guard isRecording else { return }
        
        isRecording = false
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        
        // Stop recording
        AudioRecorder.shared.stopRecording { [weak self] audioURL in
            guard let self = self, let audioURL = audioURL else {
                DispatchQueue.main.async {
                    appState.status = .idle
                    appState.showError("Recording failed")
                    self?.hideOverlay()
                }
                return
            }
            
            // Skip very short recordings (< 0.3s - likely accidental)
            if duration < 0.3 {
                DispatchQueue.main.async {
                    appState.status = .idle
                    self.hideOverlay()
                }
                try? FileManager.default.removeItem(at: audioURL)
                return
            }
            
            DispatchQueue.main.async {
                appState.status = .transcribing
                
                if appState.playSounds {
                    SoundManager.shared.playStopSound()
                }
                
                if appState.showFloatingOverlay {
                    self.showOverlay(text: "⏳ Transcribing...")
                }
            }
            
            // Transcribe
            WhisperManager.shared.transcribe(audioURL: audioURL, model: appState.whisperModel, language: appState.language) { result in
                // Clean up audio file
                try? FileManager.default.removeItem(at: audioURL)
                
                DispatchQueue.main.async {
                    self.hideOverlay()
                    
                    switch result {
                    case .success(let text):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            appState.status = .idle
                            return
                        }
                        
                        // Add to history
                        let entry = TranscriptionEntry(text: trimmed, duration: duration, model: appState.whisperModel)
                        appState.addToHistory(entry)
                        
                        // Paste at cursor
                        TextPaster.shared.pasteText(trimmed)
                        
                        appState.status = .idle
                        
                    case .failure(let error):
                        appState.status = .idle
                        appState.showError("Transcription failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showOverlay(text: String) {
        DispatchQueue.main.async {
            if self.overlayWindow == nil {
                self.overlayWindow = OverlayWindowController()
            }
            self.overlayWindow?.show(text: text)
        }
    }
    
    private func hideOverlay() {
        DispatchQueue.main.async {
            self.overlayWindow?.hide()
        }
    }
    
    deinit {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
