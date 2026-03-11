import SwiftUI
import Combine
import AVFoundation

enum AppStatus: String {
    case idle = "Idle"
    case recording = "Recording..."
    case transcribing = "Transcribing..."
}

enum PermissionState: String {
    case ready = "🟢 Ready"
    case missingPermissions = "🟡 Missing Permissions"
    case error = "🔴 Error"
}

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval
    let model: String
    
    init(text: String, duration: TimeInterval, model: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.model = model
    }
}

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var status: AppStatus = .idle {
        didSet {
            logInfo("AppState", "Status changed: \(oldValue.rawValue) → \(status.rawValue)")
        }
    }
    @Published var errorMessage: String?
    @Published var showOverlay: Bool = false
    @Published var history: [TranscriptionEntry] = []
    @Published var permissionState: PermissionState = .missingPermissions
    @Published var hasMicPermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasWhisperCLI: Bool = false
    @Published var hasFfmpeg: Bool = false
    
    // Settings
    @AppStorage("whisperModel") var whisperModel: String = "base"
    @AppStorage("showFloatingOverlay") var showFloatingOverlay: Bool = true
    @AppStorage("playSounds") var playSounds: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 61
    @AppStorage("language") var language: String = "en"
    @AppStorage("maxHistoryCount") var maxHistoryCount: Int = 50
    
    private init() {
        loadHistory()
        logInfo("AppState", "Initialized. Model=\(whisperModel), Language=\(language)")
    }
    
    /// Thread-safe status update — always dispatches to main queue
    func setStatus(_ newStatus: AppStatus) {
        if Thread.isMainThread {
            self.status = newStatus
        } else {
            DispatchQueue.main.async {
                self.status = newStatus
            }
        }
    }
    
    func showError(_ message: String) {
        logError("AppState", "Error shown: \(message)")
        if Thread.isMainThread {
            self.errorMessage = message
        } else {
            DispatchQueue.main.async {
                self.errorMessage = message
            }
        }
    }
    
    /// Re-check all permissions and update overall state
    func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = AXIsProcessTrusted()
        
        let update = {
            self.hasMicPermission = mic
            self.hasAccessibilityPermission = ax
            self.updatePermissionState()
        }
        
        if Thread.isMainThread { update() }
        else { DispatchQueue.main.async { update() } }
    }
    
    func updatePermissionState() {
        if hasMicPermission && hasAccessibilityPermission && hasWhisperCLI && hasFfmpeg {
            permissionState = .ready
        } else if !hasMicPermission || !hasAccessibilityPermission {
            permissionState = .missingPermissions
        } else {
            permissionState = .error
        }
        logInfo("AppState", "Permission state: \(permissionState.rawValue) [mic=\(hasMicPermission) ax=\(hasAccessibilityPermission) whisper=\(hasWhisperCLI) ffmpeg=\(hasFfmpeg)]")
    }
    
    func addToHistory(_ entry: TranscriptionEntry) {
        let work = {
            self.history.insert(entry, at: 0)
            if self.history.count > self.maxHistoryCount {
                self.history = Array(self.history.prefix(self.maxHistoryCount))
            }
            self.saveHistory()
            logInfo("AppState", "Added history entry: \(entry.text.prefix(50))...")
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async { work() }
        }
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
        logInfo("AppState", "History cleared")
    }
    
    private var historyURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WhisperType")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL)
        } catch {
            logError("AppState", "Failed to save history: \(error)")
        }
    }
    
    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyURL)
            history = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
            logInfo("AppState", "Loaded \(history.count) history entries")
        } catch {
            logDebug("AppState", "No history to load or parse error: \(error.localizedDescription)")
        }
    }
}
