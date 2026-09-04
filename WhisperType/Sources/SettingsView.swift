import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("settingsSelectedTab") private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Iniyal WhisperType")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("A little less typing. A little more you.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("On your Mac", systemImage: "lock.shield")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 22)

            Picker("Settings section", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Transcription").tag(1)
                Text("History").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            Divider()
            ScrollView {
                Group {
                    switch selectedTab {
                    case 1: TranscriptionSettingsView()
                    case 2: HistorySettingsView()
                    default: GeneralSettingsView()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(selectedTab)
        }
        .tint(SettingsPalette.accent)
        .frame(width: 680, height: 600)
    }

    @ViewBuilder private var avatar: some View {
        if let path = Bundle.main.path(forResource: "iniyal_face", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(SettingsPalette.accent)
                .frame(width: 54, height: 54)
                .background(SettingsPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 16) {
            shortcutCard
            SettingsCard(title: "While you speak", symbol: "waveform") {
                SettingsToggle(title: "Live words", detail: "See your words appear while you speak.", isOn: $appState.livePreview)
                Divider()
                SettingsToggle(title: "Floating recording panel", detail: "Keep recording progress in view above your other apps.", isOn: $appState.showFloatingOverlay)
                Divider()
                SettingsToggle(title: "Sound effects", detail: "Hear when recording starts and stops.", isOn: $appState.playSounds)
                HStack {
                    Spacer()
                    Button("Preview recording panel") {
                        NotificationCenter.default.post(name: Notification.Name("WhisperTypePreviewOverlay"), object: nil)
                    }
                    .help("Show a sample of the recording panel without using the microphone.")
                }
            }
            SettingsCard(title: "Make yourself at home", symbol: "desktopcomputer") {
                SettingsToggle(title: "Launch at login", detail: "Have Iniyal ready when you sign in to your Mac.", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: setLaunchAtLogin
                ))
            }
            permissionsCard
        }
        .onAppear { appState.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissions()
        }
        .alert("Could not update login setting", isPresented: Binding(
            get: { loginError != nil },
            set: { if !$0 { loginError = nil } }
        )) {
            Button("OK", role: .cancel) { loginError = nil }
        } message: {
            Text(loginError ?? "Please try again in System Settings.")
        }
    }

    private var shortcutCard: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your voice, wherever you type.")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Hold to talk. Release to paste.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Double-tap for hands-free dictation. Press again to finish.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: 5) {
                Text("⌥").font(.system(size: 30, weight: .regular))
                Text(hotkeyDisplayName).font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 110, height: 80)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.10)))
            .accessibilityLabel("Dictation shortcut: \(hotkeyDisplayName)")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SettingsPalette.accent.opacity(0.15)))
    }

    private var permissionsCard: some View {
        SettingsCard(title: "Ready to listen and type", symbol: "checkmark.shield") {
            HStack {
                Label("Microphone", systemImage: "mic")
                Spacer()
                PermissionStatusBadge(granted: appState.hasMicPermission)
            }
            HStack {
                Label("Accessibility", systemImage: "keyboard")
                Spacer()
                PermissionStatusBadge(granted: appState.hasAccessibilityPermission)
            }
            Text("Microphone access captures your voice. Accessibility lets Iniyal paste your words into the active app.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Microphone settings…") { openPrivacy("Privacy_Microphone") }
                Button("Accessibility settings…") { openPrivacy("Privacy_Accessibility") }
            }
            .buttonStyle(.link)
        }
    }

    private var hotkeyDisplayName: String {
        switch appState.hotkeyKeyCode {
        case 61: return "Right Option"
        case 58: return "Left Option"
        default: return "Key \(appState.hotkeyKeyCode)"
        }
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            appState.launchAtLogin = enabled
        } catch {
            loginError = error.localizedDescription
        }
    }
}

struct TranscriptionSettingsView: View {
    @EnvironmentObject var appState: AppState
    private let models = ["tiny", "base", "small", "medium", "turbo"]

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Speech recognition", symbol: "waveform.circle") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(appState.engineAvailable ? "Local MLX engine" : "Local engine unavailable")
                            .font(.system(size: 16, weight: .semibold))
                        Text(appState.engineAvailable ? "large-v3-turbo" : "The app will try the Whisper CLI fallback.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(appState.engineAvailable ? "Connected" : "Fallback", systemImage: appState.engineAvailable ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(appState.engineAvailable ? SettingsPalette.accent : Color.secondary)
                }
                Divider()
                Picker("Spoken language", selection: $appState.language) {
                    Text("Auto-detect").tag("")
                    Text("English").tag("en")
                    Text("Tamil").tag("ta")
                    Text("Hindi").tag("hi")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }
            }
            SettingsCard(title: "Words that sound like you", symbol: "sparkles") {
                SettingsToggle(title: "Smart cleanup", detail: "Polish dictated text with a local language model on this Mac.", isOn: $appState.smartCleanup)
                if appState.smartCleanup && !appState.llmAvailable {
                    Label("Cleanup model is unavailable. Your transcription will still be kept.", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Writing style", selection: $appState.styleOverride) {
                    Text("Automatic, based on app").tag("auto")
                    Text("Casual chat").tag("casual")
                    Text("Formal / email").tag("formal")
                    Text("AI prompt").tag("prompt")
                    Text("Literal").tag("literal")
                    Text("Neutral cleanup").tag("neutral")
                }
                .disabled(!appState.smartCleanup)
                Divider()
                Text("Personalize names, phrases and the style used in each app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Edit vocabulary…") { openConfig("vocabulary.json") }
                    Button("Edit app styles…") { openConfig("apps.json") }
                }
            }
            SettingsCard(title: "Backup recognition", symbol: "arrow.triangle.2.circlepath") {
                Picker("Whisper CLI model", selection: $appState.whisperModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model.capitalized).tag(model)
                    }
                }
                Text("Used only when the local MLX engine is unavailable. This setting does not change the MLX model. Larger CLI models use more memory and can take longer to load.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openConfig(_ name: String) {
        NSWorkspace.shared.open(EngineClient.configDir.appendingPathComponent(name))
    }
}

struct HistorySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var search = ""
    @State private var confirmClear = false

    private var filteredHistory: [TranscriptionEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? appState.history : appState.history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your recent words")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Saved on this Mac, ready when you need them.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear history…", role: .destructive) { confirmClear = true }
                    .disabled(appState.history.isEmpty)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your transcriptions", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search transcriptions")
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.10)))

            HStack {
                Stepper("Keep up to \(appState.maxHistoryCount) entries", value: $appState.maxHistoryCount, in: 10...200, step: 10)
                    .fixedSize()
                Spacer()
                Text("\(filteredHistory.count) \(filteredHistory.count == 1 ? "entry" : "entries")")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))

            if appState.history.isEmpty {
                SettingsEmptyState(symbol: "text.bubble", title: "Your next thought starts here", detail: "Hold your dictation shortcut and say a few words. Your finished transcription will appear here.")
            } else if filteredHistory.isEmpty {
                SettingsEmptyState(symbol: "magnifyingglass", title: "No matching words", detail: "Try another word or clear your search to see all saved transcriptions.")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredHistory) { entry in
                        HistoryEntryCard(entry: entry)
                    }
                }
            }
        }
        .alert("Clear all transcription history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear history", role: .destructive) { appState.clearHistory() }
        } message: {
            Text("This removes all \(appState.history.count) saved entries from this Mac. This cannot be undone.")
        }
    }
}

private struct HistoryEntryCard: View {
    let entry: TranscriptionEntry
    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: copyText) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .frame(minWidth: 54)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(copied ? SettingsPalette.accent : Color.secondary)
                .help("Copy full transcription")
            }
            Text(entry.text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Label(String(format: "%.1f sec", entry.duration), systemImage: "waveform")
                Text("·")
                Text(entry.model)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.06)))
        .contextMenu { Button("Copy transcription", action: copyText) }
        .onDisappear {
            copyReset?.cancel()
            copied = false
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
