import AppKit
import Combine
import UserNotifications

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        appState.$status.receive(on: DispatchQueue.main).sink { [weak self] status in
            self?.updateIcon(status)
        }.store(in: &cancellables)
        appState.$errorMessage.compactMap { $0 }.receive(on: DispatchQueue.main).sink { [weak self] message in
            self?.notify(title: "Iniyal WhisperType", body: message)
        }.store(in: &cancellables)
    }

    private func updateIcon(_ status: AppStatus) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch status {
        case .idle: symbol = "waveform"
        case .recording: symbol = "waveform.circle.fill"
        case .transcribing: symbol = "ellipsis.circle"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Iniyal WhisperType: \(status.rawValue)")
        button.image?.isTemplate = status != .recording
        button.contentTintColor = status == .recording ? .systemGreen : nil
        button.toolTip = status == .idle ? "Iniyal WhisperType · Hold Option to speak" : status.rawValue
    }

    // Build on opening, so settings and history are always current without replacing a tracked menu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem()
        header.view = makeHeader()
        menu.addItem(header)
        menu.addItem(.separator())
        if appState.permissionState != .ready {
            add("Review permissions…", "exclamationmark.circle", #selector(openSettings), to: menu)
        }
        let copy = add("Copy last dictation", "doc.on.doc", #selector(copyLast), to: menu)
        copy.isEnabled = !appState.history.isEmpty
        let recent = NSMenu()
        if appState.history.isEmpty {
            let empty = NSMenuItem(title: "Your words will appear here", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recent.addItem(empty)
        } else {
            for entry in appState.history.prefix(7) {
                let plain = entry.text.replacingOccurrences(of: "\n", with: " ")
                let title = String(plain.prefix(36)) + (plain.count > 36 ? "…" : "")
                let item = add(title, nil, #selector(copyEntry(_:)), to: recent)
                item.representedObject = entry.text
                item.toolTip = "Click to copy this dictation"
            }
        }
        recent.addItem(.separator())
        add("Open history…", "clock", #selector(openHistory), to: recent)
        addSubmenu("Recent dictations", "clock", recent, to: menu)
        menu.addItem(.separator())
        add("Preview recording panel", "rectangle.bottomthird.inset.filled", #selector(preview), to: menu)

        let preferences = NSMenu()
        toggle("Smart cleanup", appState.smartCleanup, #selector(toggleCleanup), in: preferences)
        toggle("Live transcript", appState.livePreview, #selector(togglePreview), in: preferences)
        toggle("Recording panel", appState.showFloatingOverlay, #selector(toggleOverlay), in: preferences)
        toggle("Sound effects", appState.playSounds, #selector(toggleSounds), in: preferences)
        addSubmenu("Quick controls", "slider.horizontal.3", preferences, to: menu)
        menu.addItem(.separator())
        let settings = add("Settings…", "gearshape", #selector(openSettings), to: menu)
        settings.keyEquivalent = ","
        let help = NSMenu()
        let status = NSMenuItem(title: appState.engineAvailable ? "Local speech engine ready" : "Local speech engine unavailable", action: nil, keyEquivalent: "")
        status.isEnabled = false
        help.addItem(status)
        add("Refresh permissions", "arrow.clockwise", #selector(refreshPermissions), to: help)
        add("Check dependencies…", "wrench.and.screwdriver", #selector(checkDependencies), to: help)
        add("About Iniyal WhisperType", "info.circle", #selector(showAbout), to: help)
        addSubmenu("Help", "questionmark.circle", help, to: menu)
        menu.addItem(.separator())
        let quit = add("Quit Iniyal WhisperType", nil, #selector(quit), to: menu)
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ title: String, _ symbol: String?, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }
    private func addSubmenu(_ title: String, _ symbol: String, _ child: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.submenu = child
        menu.addItem(item)
    }
    private func toggle(_ title: String, _ enabled: Bool, _ action: Selector, in menu: NSMenu) {
        add(title, nil, action, to: menu).state = enabled ? .on : .off
    }

    private func makeHeader() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 96))
        let avatar = NSImageView(frame: NSRect(x: 18, y: 40, width: 38, height: 38))
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 19
        avatar.layer?.masksToBounds = true
        avatar.imageScaling = .scaleProportionallyUpOrDown
        if let path = Bundle.main.path(forResource: "iniyal_face", ofType: "png") { avatar.image = NSImage(contentsOfFile: path) }
        view.addSubview(avatar)
        let title = NSTextField(labelWithString: "Iniyal WhisperType")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 67, y: 60, width: 210, height: 21)
        view.addSubview(title)
        let ready = appState.permissionState == .ready
        let state = NSTextField(labelWithString: appState.status == .idle ? (ready ? "Ready when you are" : "A little setup needed") : appState.status.rawValue)
        state.font = .systemFont(ofSize: 12)
        state.textColor = ready ? .secondaryLabelColor : .systemOrange
        state.frame = NSRect(x: 67, y: 41, width: 210, height: 18)
        view.addSubview(state)
        let key = appState.hotkeyKeyCode == 58 ? "Left Option" : "Right Option"
        let hint = NSTextField(labelWithString: "Hold \(key) to speak · release to paste")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 18, y: 11, width: 260, height: 17)
        view.addSubview(hint)
        return view
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        copy(text)
    }
    @objc private func copyLast() { if let text = appState.history.first?.text { copy(text) } }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notify(title: "Copied", body: "Your dictation is ready to paste.")
    }
    @objc private func toggleCleanup() { appState.smartCleanup.toggle() }
    @objc private func togglePreview() { appState.livePreview.toggle() }
    @objc private func toggleOverlay() { appState.showFloatingOverlay.toggle() }
    @objc private func toggleSounds() { appState.playSounds.toggle() }
    @objc private func preview() { NotificationCenter.default.post(name: .init("WhisperTypePreviewOverlay"), object: nil) }
    @objc private func openHistory() {
        UserDefaults.standard.set(2, forKey: "settingsSelectedTab")
        openSettings()
    }
    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func refreshPermissions() { appState.refreshPermissions() }
    @objc private func checkDependencies() { (NSApp.delegate as? AppDelegate)?.showDependencySetup() }
    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Iniyal WhisperType",
            .applicationVersion: info["CFBundleShortVersionString"] as? String ?? "",
            .version: info["CFBundleVersion"] as? String ?? "",
            .credits: NSAttributedString(string: "Your voice. Your words. On your Mac.\nMade by Onwords.")
        ])
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
