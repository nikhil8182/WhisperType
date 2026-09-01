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
    private var engineTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installCrashHandler()
        


        logInfo("App", "WhisperType launching...")

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Setup status bar
        statusBarController = StatusBarController(appState: appState)

        checkPermissions()

        // Onboarding disabled — SwiftUI NSHostingView causes constraint crashes on macOS 26
        // TODO: Re-implement onboarding with AppKit (no SwiftUI) to avoid
        // EXC_BREAKPOINT in _postWindowNeedsUpdateConstraints
        checkDependencies()

        HotkeyManager.shared.setup(appState: appState)

        // Local engine: launch if installed, keep an eye on it
        EngineClient.shared.ensureRunning()
        engineTimer = Timer(timeInterval: 10.0, repeats: true) { _ in
            EngineClient.shared.ensureRunning()
        }
        RunLoop.main.add(engineTimer!, forMode: .common)

        // Re-check mic + accessibility only (cheap, no process spawns)
        permissionCheckTimer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.recheckPermissions()
        }
        RunLoop.main.add(permissionCheckTimer!, forMode: .common)

        logInfo("App", "WhisperType launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionCheckTimer?.invalidate()
        engineTimer?.invalidate()
        logInfo("App", "WhisperType shutting down")
        AudioRecorder.shared.forceReset()
        EngineClient.shared.stop()
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
        
        // Accessibility alert is now handled by onboarding (step 3)
        // Only show the old alert if onboarding was already completed
        if !axTrusted && UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showAccessibilityAlert()
        }

        // --- Whisper CLI ---
        WhisperManager.shared.checkAvailability { available in
            DispatchQueue.main.async {
                self.appState.hasWhisperCLI = available
                logInfo("App", "Whisper CLI available: \(available)")
                if !available && !EngineClient.isInstalled {
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
        if !ffmpegExists && !EngineClient.isInstalled {
            appState.showError("ffmpeg not found. Install with: brew install ffmpeg")
        }

        // Don't call updatePermissionState() here — wait for async whisper check to complete
    }

    /// Periodically re-check all permissions (user may grant them in System Settings)
    private func recheckPermissions() {
        let axTrusted = AXIsProcessTrusted()
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ffmpegExists = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .contains { FileManager.default.fileExists(atPath: $0) }
        
        DispatchQueue.main.async {
            let changed = (self.appState.hasAccessibilityPermission != axTrusted) ||
                          (self.appState.hasMicPermission != micAuth) ||
                          (self.appState.hasFfmpeg != ffmpegExists)
            
            self.appState.hasAccessibilityPermission = axTrusted
            self.appState.hasMicPermission = micAuth
            self.appState.hasFfmpeg = ffmpegExists
            
            if changed {
                self.appState.updatePermissionState()
                logInfo("App", "Permission state changed — ax=\(axTrusted) mic=\(micAuth) ffmpeg=\(ffmpegExists)")
            }
        }
    }

    // MARK: - Dependency Management
    
    /// Check if all dependencies are installed; show setup window if not
    private func checkDependencies() {
        if EngineClient.isInstalled {
            logInfo("App", "Local engine installed — CLI dependency setup not required")
            WhisperManager.shared.refreshWhisperPath()
            return
        }
        logInfo("App", "Checking dependencies...")
        DependencyManager.shared.allInstalled { [weak self] allGood in
            if allGood {
                logInfo("App", "All dependencies are installed ✅")
                // Refresh whisper path in case it changed
                WhisperManager.shared.refreshWhisperPath()
            } else {
                logInfo("App", "Some dependencies are missing — showing setup window")
                self?.showDependencySetup()
            }
        }
    }
    
    /// Show the dependency setup window
    func showDependencySetup() {
        SetupWindowController.shared.showSetupWindow { [weak self] in
            logInfo("App", "Dependency setup complete — rechecking permissions")
            // Refresh whisper path and re-check CLI tools
            WhisperManager.shared.refreshWhisperPath()
            WhisperManager.shared.checkAvailability { available in
                DispatchQueue.main.async {
                    self?.appState.hasWhisperCLI = available
                    
                    let ffmpegExists = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
                        .contains { FileManager.default.fileExists(atPath: $0) }
                    self?.appState.hasFfmpeg = ffmpegExists
                    
                    self?.appState.updatePermissionState()
                }
            }
        }
    }
    
    /// Non-blocking Accessibility nudge: system prompt (adds us to the list) + open the pane.
    /// Never runModal here: a modal loop freezes the engine/permission timers.
    private func showAccessibilityAlert() {
        DispatchQueue.main.async {
            TextPaster.requestAccessibility()
            TextPaster.openAccessibilitySettings()
            self.appState.showError("Accessibility needed to paste: toggle WhisperType ON in System Settings → Privacy & Security → Accessibility.")
        }
    }
}
