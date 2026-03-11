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
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installCrashHandler()

        logInfo("App", "WhisperType launching...")

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Setup status bar
        statusBarController = StatusBarController(appState: appState)

        checkPermissions()

        HotkeyManager.shared.setup(appState: appState)

        // Periodically re-check permissions (user may grant them later)
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.recheckPermissions()
        }

        logInfo("App", "WhisperType launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionCheckTimer?.invalidate()
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

        // --- Microphone ---
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            logInfo("App", "Mic permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logInfo("App", "Mic permission response: \(granted)")
                DispatchQueue.main.async {
                    self.appState.hasMicPermission = granted
                    if !granted {
                        self.appState.showError("Microphone access denied. Enable in System Settings > Privacy & Security > Microphone.")
                    }
                    self.appState.updatePermissionState()
                }
            }
        case .denied, .restricted:
            logError("App", "Mic permission denied/restricted")
            appState.hasMicPermission = false
            appState.showError("Microphone access denied. Enable in System Settings > Privacy & Security > Microphone.")
        case .authorized:
            logInfo("App", "Mic permission: authorized")
            appState.hasMicPermission = true
        @unknown default:
            logWarn("App", "Mic permission: unknown status")
        }

        // --- Accessibility ---
        let axTrusted = AXIsProcessTrusted()
        appState.hasAccessibilityPermission = axTrusted
        logInfo("App", "Accessibility permission: \(axTrusted)")
        
        if !axTrusted {
            showAccessibilityAlert()
        }

        // --- Whisper CLI ---
        WhisperManager.shared.checkAvailability { available in
            DispatchQueue.main.async {
                self.appState.hasWhisperCLI = available
                logInfo("App", "Whisper CLI available: \(available)")
                if !available {
                    self.appState.showError("Whisper CLI not found. Install with: pipx install openai-whisper")
                }
                self.appState.updatePermissionState()
            }
        }

        // --- ffmpeg ---
        let ffmpegExists = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .contains { FileManager.default.fileExists(atPath: $0) }
        appState.hasFfmpeg = ffmpegExists
        logInfo("App", "ffmpeg available: \(ffmpegExists)")
        if !ffmpegExists {
            appState.showError("ffmpeg not found. Install with: brew install ffmpeg")
        }

        appState.updatePermissionState()
    }

    /// Periodically re-check Accessibility (user may grant it in System Settings)
    private func recheckPermissions() {
        let axTrusted = AXIsProcessTrusted()
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        DispatchQueue.main.async {
            let changed = (self.appState.hasAccessibilityPermission != axTrusted) ||
                          (self.appState.hasMicPermission != micAuth)
            
            self.appState.hasAccessibilityPermission = axTrusted
            self.appState.hasMicPermission = micAuth
            
            if changed {
                self.appState.updatePermissionState()
                logInfo("App", "Permission state changed — ax=\(axTrusted) mic=\(micAuth)")
            }
        }
    }

    /// Show a clear alert for Accessibility permission with button to open Settings
    private func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            WhisperType needs Accessibility access to paste transcribed text into your apps.
            
            Click "Open Settings" to grant access:
            1. Click the + button
            2. Navigate to WhisperType.app and add it
            3. Toggle it ON
            
            You may need to restart WhisperType after granting access.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                TextPaster.openAccessibilitySettings()
            }
        }
    }
}
