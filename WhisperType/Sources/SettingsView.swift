import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            TranscriptionSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
                .tag(1)
            
            HistorySettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(2)
        }
        .frame(width: 450, height: 320)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Hotkey")
                    Spacer()
                    Text(hotkeyDisplayName)
                        .foregroundColor(.secondary)
                    // Future: Add hotkey recording button
                }
                
                Toggle("Show floating overlay", isOn: $appState.showFloatingOverlay)
                Toggle("Sound effects", isOn: $appState.playSounds)
                Toggle("Launch at login", isOn: $appState.launchAtLogin)
                    .onChange(of: appState.launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
            
            Section("Permissions") {
                HStack {
                    Text("Microphone")
                    Spacer()
                    PermissionStatusBadge(granted: checkMicPermission())
                }
                HStack {
                    Text("Accessibility")
                    Spacer()
                    PermissionStatusBadge(granted: AXIsProcessTrusted())
                }
                
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }
    
    private var hotkeyDisplayName: String {
        switch appState.hotkeyKeyCode {
        case 61: return "Right ⌥ Option"
        case 58: return "Left ⌥ Option"
        default: return "Key \(appState.hotkeyKeyCode)"
        }
    }
    
    private func checkMicPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
}

struct PermissionStatusBadge: View {
    let granted: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(granted ? "Granted" : "Not Granted")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

import AVFoundation

struct TranscriptionSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    let models = ["tiny", "base", "small", "medium"]
    let modelDescriptions = [
        "tiny": "~1GB RAM, fastest, least accurate",
        "base": "~1GB RAM, good balance (recommended)",
        "small": "~2GB RAM, better accuracy",
        "medium": "~5GB RAM, best accuracy, slowest"
    ]
    
    var body: some View {
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $appState.whisperModel) {
                    ForEach(models, id: \.self) { model in
                        VStack(alignment: .leading) {
                            Text(model.capitalized)
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(modelDescriptions[appState.whisperModel] ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Language") {
                Picker("Language", selection: $appState.language) {
                    Text("English").tag("en")
                    Text("Auto-detect").tag("")
                    Text("Tamil").tag("ta")
                    Text("Hindi").tag("hi")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct HistorySettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section {
                Stepper("Keep \(appState.maxHistoryCount) items", value: $appState.maxHistoryCount, in: 10...200, step: 10)
                
                Button("Clear All History", role: .destructive) {
                    appState.clearHistory()
                }
            }
            
            Section("Recent Transcriptions") {
                if appState.history.isEmpty {
                    Text("No transcriptions yet")
                        .foregroundColor(.secondary)
                } else {
                    List(appState.history.prefix(20)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text)
                                .lineLimit(2)
                                .font(.body)
                            HStack {
                                Text(entry.timestamp, style: .relative)
                                Text("• \(String(format: "%.1fs", entry.duration))")
                                Text("• \(entry.model)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
