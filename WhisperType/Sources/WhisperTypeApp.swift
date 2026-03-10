import SwiftUI
import AVFoundation

@main
struct WhisperTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!
    let appState = AppState.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)
        
        // Setup status bar
        statusBarController = StatusBarController(appState: appState)
        
        // Check permissions
        checkPermissions()
        
        // Setup global hotkey monitor
        HotkeyManager.shared.setup(appState: appState)
    }
    
    private func checkPermissions() {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.appState.showError("Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone.")
                    }
                }
            }
        case .denied, .restricted:
            appState.showError("Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone.")
        case .authorized:
            break
        @unknown default:
            break
        }
        
        // Check accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            appState.showError("Accessibility access needed for global hotkey and paste. Please enable in System Settings > Privacy & Security > Accessibility.")
        }
        
        // Check whisper availability
        WhisperManager.shared.checkAvailability { available in
            if !available {
                DispatchQueue.main.async {
                    self.appState.showError("Whisper CLI not found. Install with: pipx install openai-whisper")
                }
            }
        }
    }
}
