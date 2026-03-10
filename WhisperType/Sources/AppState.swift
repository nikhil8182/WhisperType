import SwiftUI
import Combine

enum AppStatus: String {
    case idle = "Idle"
    case recording = "Recording..."
    case transcribing = "Transcribing..."
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
    
    @Published var status: AppStatus = .idle
    @Published var errorMessage: String?
    @Published var showOverlay: Bool = false
    @Published var history: [TranscriptionEntry] = []
    
    // Settings
    @AppStorage("whisperModel") var whisperModel: String = "base"
    @AppStorage("showFloatingOverlay") var showFloatingOverlay: Bool = true
    @AppStorage("playSounds") var playSounds: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 61 // Right Option = key code 61
    @AppStorage("language") var language: String = "en"
    @AppStorage("maxHistoryCount") var maxHistoryCount: Int = 50
    
    private init() {
        loadHistory()
    }
    
    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
    }
    
    func addToHistory(_ entry: TranscriptionEntry) {
        DispatchQueue.main.async {
            self.history.insert(entry, at: 0)
            if self.history.count > self.maxHistoryCount {
                self.history = Array(self.history.prefix(self.maxHistoryCount))
            }
            self.saveHistory()
        }
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    private var historyURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WhisperType")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL)
        }
    }
    
    private func loadHistory() {
        if let data = try? Data(contentsOf: historyURL),
           let loaded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) {
            history = loaded
        }
    }
}
