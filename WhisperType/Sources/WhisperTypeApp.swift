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
        // Install crash handler FIRST
        installCrashHandler()
        
        logInfo("App", "WhisperType launching...")
        
        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)
        
        // Setup status bar
        statusBarController = StatusBarController(appState: appState)
        
        // Check permissions
        checkPermissions()
        
        // Setup global hotkey monitor
        HotkeyManager.shared.setup(appState: appState)
        
        logInfo("App", "WhisperType launch complete")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logInfo("App", "WhisperType shutting down")
    }
    
    private func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let msg = """
            === UNCAUGHT EXCEPTION ===
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack: \(exception.callStackSymbols.joined(separator: "\n"))
            """
            logError("CRASH", msg)
            
            // Force flush
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Handle signals
        for sig: Int32 in [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP] {
            signal(sig) { signalNumber in
                logError("CRASH", "Caught signal \(signalNumber)")
                Thread.sleep(forTimeInterval: 0.5)
                exit(signalNumber)
            }
        }
        
        logInfo("App", "Crash handlers installed")
    }
    
    private func checkPermissions() {
        logInfo("App", "Checking permissions...")
        
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            logInfo("App", "Mic permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logInfo("App", "Mic permission response: \(granted)")
                if !granted {
                    self.appState.showError("Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone.")
                }
            }
        case .denied, .restricted:
            logError("App", "Mic permission denied/restricted")
            appState.showError("Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone.")
        case .authorized:
            logInfo("App", "Mic permission: authorized")
        @unknown default:
            logWarn("App", "Mic permission: unknown status")
        }
        
        // Check accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        logInfo("App", "Accessibility permission: \(axTrusted)")
        if !axTrusted {
            appState.showError("Accessibility access needed for global hotkey and paste. Please enable in System Settings > Privacy & Security > Accessibility.")
        }
        
        // Check whisper availability
        WhisperManager.shared.checkAvailability { available in
            logInfo("App", "Whisper CLI available: \(available)")
            if !available {
                self.appState.showError("Whisper CLI not found. Install with: pipx install openai-whisper")
            }
        }
    }
}
