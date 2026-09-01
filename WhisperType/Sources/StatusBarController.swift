import AppKit
import SwiftUI
import Combine
import UserNotifications

class StatusBarController {
    private var statusItem: NSStatusItem
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var popover: NSPopover?
    
    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupButton()
        setupMenu()
        observeState()
    }
    
    private func setupButton() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Iniyal WhisperType")
            button.image?.isTemplate = true
        }
    }
    
    private func setupMenu() {
        updateMenu()
    }
    
    private func observeState() {
        appState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateIcon(for: status)
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        appState.$permissionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        appState.$engineAvailable.combineLatest(appState.$llmAvailable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)

        appState.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showNotification(title: "Iniyal WhisperType", body: message)
            }
            .store(in: &cancellables)
    }
    
    private func updateIcon(for status: AppStatus) {
        guard let button = statusItem.button else { return }
        
        switch status {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Iniyal WhisperType - Idle")
            button.image?.isTemplate = true
            button.contentTintColor = nil
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Iniyal WhisperType - Recording")
            button.image?.isTemplate = false
            button.contentTintColor = .systemRed
        case .transcribing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Iniyal WhisperType - Transcribing")
            button.image?.isTemplate = false
            button.contentTintColor = .systemOrange
        }
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // Permission status indicator
        let permItem = NSMenuItem(title: appState.permissionState.rawValue, action: nil, keyEquivalent: "")
        permItem.isEnabled = false
        menu.addItem(permItem)
        
        // Show missing permissions detail
        if appState.permissionState != .ready {
            if !appState.hasMicPermission {
                let micItem = NSMenuItem(title: "  ⚠️ Microphone: Not Granted", action: nil, keyEquivalent: "")
                micItem.isEnabled = false
                menu.addItem(micItem)
            }
            if !appState.hasAccessibilityPermission {
                let axItem = NSMenuItem(title: "  ⚠️ Accessibility: Not Granted", action: #selector(openAccessibilitySettings), keyEquivalent: "")
                axItem.target = self
                menu.addItem(axItem)
            }
            if !appState.hasWhisperCLI {
                let whisperItem = NSMenuItem(title: "  ⚠️ Whisper CLI: Not Found", action: nil, keyEquivalent: "")
                whisperItem.isEnabled = false
                menu.addItem(whisperItem)
            }
            if !appState.hasFfmpeg {
                let ffmpegItem = NSMenuItem(title: "  ⚠️ ffmpeg: Not Found", action: nil, keyEquivalent: "")
                ffmpegItem.isEnabled = false
                menu.addItem(ffmpegItem)
            }
            
            let fixItem = NSMenuItem(title: "Request Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            fixItem.target = self
            menu.addItem(fixItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // App Status
        let statusItem = NSMenuItem(title: appState.status.rawValue, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        // Last transcription preview
        if let lastEntry = appState.history.first {
            let preview = String(lastEntry.text.prefix(45)) + (lastEntry.text.count > 45 ? "…" : "")
            let lastItem = NSMenuItem(title: "Last: \(preview)", action: #selector(copyLastTranscription), keyEquivalent: "")
            lastItem.target = self
            lastItem.toolTip = "Click to copy: \(lastEntry.text)"
            menu.addItem(lastItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Recent transcriptions
        let historyMenu = NSMenu()
        if appState.history.isEmpty {
            let emptyItem = NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            for (i, entry) in appState.history.prefix(10).enumerated() {
                let preview = String(entry.text.prefix(60)) + (entry.text.count > 60 ? "..." : "")
                let item = NSMenuItem(title: preview, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.toolTip = entry.text
                historyMenu.addItem(item)
            }
            historyMenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }
        
        let historyMenuItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
        historyMenuItem.submenu = historyMenu
        menu.addItem(historyMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Model selection
        let modelMenu = NSMenu()
        for model in ["tiny", "base", "small", "medium", "turbo"] {
            let item = NSMenuItem(title: model, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            if model == appState.whisperModel {
                item.state = .on
            }
            modelMenu.addItem(item)
        }
        let modelMenuItem = NSMenuItem(title: "Model: \(appState.whisperModel)", action: nil, keyEquivalent: "")
        modelMenuItem.submenu = modelMenu
        menu.addItem(modelMenuItem)
        
        // Engine status + smart cleanup
        let engineTitle = appState.engineAvailable
            ? "Engine: turbo ✓" + (appState.llmAvailable ? "  ·  cleanup ✓" : "  ·  cleanup off (Ollama down)")
            : (EngineClient.isInstalled ? "Engine: starting…" : "Engine: not installed (CLI fallback)")
        let engineItem = NSMenuItem(title: engineTitle, action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)

        let cleanupItem = NSMenuItem(title: "Smart Cleanup (local LLM)", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupItem.target = self
        cleanupItem.state = appState.smartCleanup ? .on : .off
        menu.addItem(cleanupItem)

        let previewItem = NSMenuItem(title: "Live Preview While Recording", action: #selector(togglePreview), keyEquivalent: "")
        previewItem.target = self
        previewItem.state = appState.livePreview ? .on : .off
        menu.addItem(previewItem)

        let styleMenu = NSMenu()
        for (tag, title) in [("auto", "Auto (by app)"), ("casual", "Casual chat"), ("formal", "Formal / email"), ("prompt", "AI prompt"), ("literal", "Literal"), ("neutral", "Neutral cleanup")] {
            let it = NSMenuItem(title: title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = tag
            if tag == appState.styleOverride { it.state = .on }
            styleMenu.addItem(it)
        }
        let styleItem = NSMenuItem(title: "Cleanup Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let vocabItem = NSMenuItem(title: "Edit Vocabulary…", action: #selector(editVocabulary), keyEquivalent: "")
        vocabItem.target = self
        menu.addItem(vocabItem)

        let appsItem = NSMenuItem(title: "Edit App Styles…", action: #selector(editAppStyles), keyEquivalent: "")
        appsItem.target = self
        menu.addItem(appsItem)

        menu.addItem(NSMenuItem.separator())

        // Overlay toggle
        let overlayItem = NSMenuItem(title: "Show Overlay", action: #selector(toggleOverlay), keyEquivalent: "")
        overlayItem.target = self
        overlayItem.state = appState.showFloatingOverlay ? .on : .off
        menu.addItem(overlayItem)
        
        // Sound toggle
        let soundItem = NSMenuItem(title: "Sound Effects", action: #selector(toggleSounds), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = appState.playSounds ? .on : .off
        menu.addItem(soundItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Setup Wizard
        let wizardItem = NSMenuItem(title: "Setup Wizard…", action: #selector(showSetupWizard), keyEquivalent: "")
        wizardItem.target = self
        menu.addItem(wizardItem)
        
        // Check Dependencies
        let depsItem = NSMenuItem(title: "Check Dependencies…", action: #selector(checkDependencies), keyEquivalent: "d")
        depsItem.target = self
        menu.addItem(depsItem)
        
        // Refresh permissions
        let refreshItem = NSMenuItem(title: "Refresh Permissions", action: #selector(refreshPermissions), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(title: "About Iniyal WhisperType", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Iniyal WhisperType", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < appState.history.count else { return }
        let text = appState.history[index].text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showNotification(title: "Copied", body: String(text.prefix(50)))
    }
    
    @objc private func copyLastTranscription() {
        guard let lastEntry = appState.history.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastEntry.text, forType: .string)
        showNotification(title: "Copied", body: String(lastEntry.text.prefix(50)))
    }
    
    @objc private func clearHistory() {
        appState.clearHistory()
    }
    
    @objc private func selectModel(_ sender: NSMenuItem) {
        if let model = sender.representedObject as? String {
            appState.whisperModel = model
        }
    }
    
    @objc private func toggleCleanup() { appState.smartCleanup.toggle(); updateMenu() }
    @objc private func togglePreview() { appState.livePreview.toggle(); updateMenu() }
    @objc private func selectStyle(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? String { appState.styleOverride = s; updateMenu() }
    }
    @objc private func editVocabulary() { openConfig("vocabulary.json") }
    @objc private func editAppStyles() { openConfig("apps.json") }
    private func openConfig(_ name: String) {
        let url = EngineClient.configDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            showNotification(title: "Iniyal WhisperType", body: "\(name) appears after the engine's first start.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleOverlay() {
        appState.showFloatingOverlay.toggle()
    }
    
    @objc private func toggleSounds() {
        appState.playSounds.toggle()
    }
    
    @objc private func openAccessibilitySettings() {
        TextPaster.openAccessibilitySettings()
    }
    
    @objc private func showSetupWizard() {
        // Show onboarding as a re-runnable setup wizard
        NSApp.setActivationPolicy(.regular)
        OnboardingWindowController.shared.show(forceShow: true)
        
        // Re-hide dock icon when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    @objc private func checkDependencies() {
        // Access the AppDelegate to trigger setup window
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showDependencySetup()
        }
    }
    
    @objc private func refreshPermissions() {
        appState.refreshPermissions()
        showNotification(title: "Iniyal WhisperType", body: "Permissions refreshed: \(appState.permissionState.rawValue)")
    }
    
    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "Iniyal, the Onwords AI, types what you say.\nby Onwords Smart Solutions · onwords.in",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Iniyal WhisperType",
            .applicationVersion: "1.2.0",
            .version: "3",
            .credits: credits,
            .applicationIcon: NSApp.applicationIconImage as Any
        ]
        
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    
    @objc private func quit() {
        NSApp.terminate(nil)
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
