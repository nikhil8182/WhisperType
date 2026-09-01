import Cocoa

/// Talks to the local WhisperType engine (whispertype_server.py) on 127.0.0.1:4877.
/// Also launches it on demand from the venv in ~/Library/Application Support/WhisperType/engine.
final class EngineClient {
    static let shared = EngineClient()

    struct Health { let ok: Bool; let llm: Bool; let model: String; let llmModel: String }
    struct Transcript { let text: String; let raw: String; let ms: Int }
    struct Polished { let text: String; let style: String; let ms: Int; let usedLLM: Bool }

    private let base = URL(string: "http://127.0.0.1:4877")!
    private let session: URLSession
    private var serverProcess: Process?
    private var lastLaunchAttempt: Date = .distantPast
    private let lock = NSLock()

    private(set) var isUp = false
    private(set) var llmUp = false

    static var engineDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperType/engine")
    }
    static var configDir: URL { engineDir.deletingLastPathComponent() }
    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: engineDir.appendingPathComponent(".venv/bin/python").path)
    }

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 90
        cfg.timeoutIntervalForResource = 120
        session = URLSession(configuration: cfg)
    }

    // MARK: - Health / launch

    func health(completion: @escaping (Health?) -> Void) {
        var req = URLRequest(url: base.appendingPathComponent("health"))
        req.timeoutInterval = 2
        session.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.setState(up: false, llm: false)
                completion(nil)
                return
            }
            let h = Health(ok: obj["ok"] as? Bool ?? false,
                           llm: obj["llm"] as? Bool ?? false,
                           model: obj["model"] as? String ?? "?",
                           llmModel: obj["llm_model"] as? String ?? "?")
            self.setState(up: h.ok, llm: h.llm)
            completion(h)
        }.resume()
    }

    private func setState(up: Bool, llm: Bool) {
        lock.lock(); let changed = (isUp != up) || (llmUp != llm); isUp = up; llmUp = llm; lock.unlock()
        if changed {
            logInfo("Engine", "state: server=\(up ? "up" : "down") llm=\(llm ? "up" : "down")")
            DispatchQueue.main.async {
                AppState.shared.engineAvailable = up
                AppState.shared.llmAvailable = llm
                AppState.shared.updatePermissionState()
            }
        }
    }

    /// Ensure the engine is running; launches it if installed and not answering.
    func ensureRunning() {
        health { h in
            if h?.ok == true { return }
            self.launchIfNeeded()
        }
    }

    private func launchIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if let p = serverProcess, p.isRunning { return }
        guard Date().timeIntervalSince(lastLaunchAttempt) > 20 else { return }
        lastLaunchAttempt = Date()
        guard EngineClient.isInstalled else {
            logWarn("Engine", "engine not installed at \(EngineClient.engineDir.path)")
            return
        }
        let python = EngineClient.engineDir.appendingPathComponent(".venv/bin/python").path
        var script = EngineClient.engineDir.appendingPathComponent("whispertype_server.py").path
        // Prefer the copy bundled with this build if it is newer (dev convenience)
        if let bundled = Bundle.main.path(forResource: "whispertype_server", ofType: "py") {
            let fm = FileManager.default
            let bm = (try? fm.attributesOfItem(atPath: bundled)[.modificationDate] as? Date) ?? .distantPast
            let im = (try? fm.attributesOfItem(atPath: script)[.modificationDate] as? Date) ?? .distantPast
            if bm > im { try? fm.removeItem(atPath: script); try? fm.copyItem(atPath: bundled, toPath: script) }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [script]
        p.environment = DependencyManager.makeFullEnv()
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WhisperType/server.stderr.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let fh = try? FileHandle(forWritingTo: logURL) { fh.seekToEndOfFile(); p.standardError = fh; p.standardOutput = fh }
        p.terminationHandler = { proc in
            logWarn("Engine", "server exited with status \(proc.terminationStatus)")
            self.setState(up: false, llm: false)
        }
        do {
            try p.run()
            serverProcess = p
            logInfo("Engine", "launched server pid \(p.processIdentifier)")
        } catch {
            logError("Engine", "failed to launch server: \(error)")
        }
    }

    func stop() {
        lock.lock(); let p = serverProcess; serverProcess = nil; lock.unlock()
        if let p = p, p.isRunning { p.terminate() }
    }

    // MARK: - Transcribe

    /// pcm = little-endian Float32 mono 16 kHz
    func transcribe(pcm: Data, language: String, partial: Bool, completion: @escaping (Result<Transcript, Error>) -> Void) {
        var req = URLRequest(url: base.appendingPathComponent("transcribe"))
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(language.isEmpty ? "auto" : language, forHTTPHeaderField: "X-Language")
        req.setValue(partial ? "1" : "0", forHTTPHeaderField: "X-Partial")
        req.timeoutInterval = partial ? 4 : 60
        session.uploadTask(with: req, from: pcm) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (resp as? HTTPURLResponse)?.statusCode == 200 else {
                completion(.failure(NSError(domain: "WhisperType", code: -2, userInfo: [NSLocalizedDescriptionKey: "engine returned bad response"])))
                return
            }
            completion(.success(Transcript(text: obj["text"] as? String ?? "",
                                           raw: obj["raw"] as? String ?? "",
                                           ms: obj["ms"] as? Int ?? 0)))
        }.resume()
    }

    // MARK: - Polish

    struct FrontApp { let bundle: String; let name: String; let title: String }

    /// Snapshot the app the user is typing into. Call BEFORE we do anything that could steal focus.
    static func captureFrontApp() -> FrontApp {
        guard let app = NSWorkspace.shared.frontmostApplication else { return FrontApp(bundle: "", name: "", title: "") }
        var title = ""
        if AXIsProcessTrusted() {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &win) == .success, let w = win {
                var t: CFTypeRef?
                if AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success {
                    title = (t as? String) ?? ""
                }
            }
        }
        return FrontApp(bundle: app.bundleIdentifier ?? "", name: app.localizedName ?? "", title: title)
    }

    func polish(text: String, app: FrontApp, styleOverride: String, completion: @escaping (Polished) -> Void) {
        var req = URLRequest(url: base.appendingPathComponent("polish"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let body: [String: Any] = ["text": text, "app_bundle": app.bundle, "app_name": app.name,
                                   "window_title": app.title, "style": styleOverride]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req) { data, _, err in
            guard err == nil, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let out = obj["text"] as? String, !out.isEmpty else {
                logWarn("Engine", "polish failed (\(err?.localizedDescription ?? "bad response")), using raw text")
                completion(Polished(text: text, style: "raw", ms: 0, usedLLM: false))
                return
            }
            completion(Polished(text: out, style: obj["style"] as? String ?? "?",
                                ms: obj["ms"] as? Int ?? 0, usedLLM: obj["llm"] as? Bool ?? false))
        }.resume()
    }
}
