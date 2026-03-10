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
        installCrashHandler()

        logInfo("App", "WhisperType launching...")

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Setup status bar
        statusBarController = StatusBarController(appState: appState)

        checkPermissions()

        HotkeyManager.shared.setup(appState: appState)

        logInfo("App", "WhisperType launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("App", "WhisperType shutting down")
        AudioRecorder.shared.forceReset()
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
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Handle fatal signals (NOT SIGTRAP — used by debugger/Swift runtime)
        for sig: Int32 in [SIGABRT, SIGSEGV, SIGBUS] {
            signal(sig) { signalNumber in
                let msg = "FATAL: signal \(signalNumber)\n"
                let logPath = NSHomeDirectory() + "/Library/Logs/WhisperType/crash.log"
                if let fd = fopen(logPath, "a") {
                    fputs(msg, fd)
                    fclose(fd)
                }
                _exit(signalNumber)
            }
        }

        logInfo("App", "Crash handlers installed")
    }

    private func checkPermissions() {
        logInfo("App", "Checking permissions...")

        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            logInfo("App", "Mic permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logInfo("App", "Mic permission response: \(granted)")
                if !granted {
                    self.appState.showError("Microphone access denied. Enable in System Settings > Privacy & Security > Microphone.")
                }
            }
        case .denied, .restricted:
            logError("App", "Mic permission denied/restricted")
            appState.showError("Microphone access denied. Enable in System Settings > Privacy & Security > Microphone.")
        case .authorized:
            logInfo("App", "Mic permission: authorized")
        @unknown default:
            logWarn("App", "Mic permission: unknown status")
        }

        // Accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        logInfo("App", "Accessibility permission: \(axTrusted)")
        if !axTrusted {
            appState.showError("Accessibility access needed for global hotkey and paste. Enable in System Settings > Privacy & Security > Accessibility.")
        }

        // Whisper CLI
        WhisperManager.shared.checkAvailability { available in
            logInfo("App", "Whisper CLI available: \(available)")
            if !available {
                self.appState.showError("Whisper CLI not found. Install with: pipx install openai-whisper")
            }
        }

        // ffmpeg (required for recording)
        let ffmpegExists = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .contains { FileManager.default.fileExists(atPath: $0) }
        logInfo("App", "ffmpeg available: \(ffmpegExists)")
        if !ffmpegExists {
            appState.showError("ffmpeg not found. Install with: brew install ffmpeg")
        }
    }
}
