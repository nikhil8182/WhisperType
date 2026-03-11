import Foundation

/// Manages checking and installing external dependencies required by WhisperType.
class DependencyManager {
    static let shared = DependencyManager()
    
    struct Dependency {
        let name: String
        let checkCommand: String
        let installCommand: String
        let description: String
        let requiresTerminal: Bool  // If true, open Terminal.app instead of running in-process
        
        init(name: String, check: String, install: String, desc: String, requiresTerminal: Bool = false) {
            self.name = name
            self.checkCommand = check
            self.installCommand = install
            self.description = desc
            self.requiresTerminal = requiresTerminal
        }
    }
    
    enum DependencyStatus: Equatable {
        case unknown
        case installed
        case missing
        case installing
        case failed(String)
    }
    
    /// Ordered list of dependencies — Homebrew must be first
    static let dependencies: [Dependency] = [
        Dependency(
            name: "Homebrew",
            check: "/opt/homebrew/bin/brew --version || /usr/local/bin/brew --version",
            install: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            desc: "macOS package manager",
            requiresTerminal: true  // Homebrew install is interactive, needs password
        ),
        Dependency(
            name: "Python 3",
            check: "/opt/homebrew/bin/python3 --version || /usr/local/bin/python3 --version || /usr/bin/python3 --version",
            install: "/opt/homebrew/bin/brew install python",
            desc: "Python runtime (needed for Whisper)"
        ),
        Dependency(
            name: "ffmpeg",
            check: "/opt/homebrew/bin/ffmpeg -version || /usr/local/bin/ffmpeg -version",
            install: "/opt/homebrew/bin/brew install ffmpeg",
            desc: "Audio processing library"
        ),
        Dependency(
            name: "pipx",
            check: "/opt/homebrew/bin/pipx --version || /usr/local/bin/pipx --version",
            install: "/opt/homebrew/bin/brew install pipx && /opt/homebrew/bin/pipx ensurepath",
            desc: "Python application installer"
        ),
        Dependency(
            name: "Whisper",
            check: "/opt/homebrew/bin/pipx list 2>/dev/null | grep -q openai-whisper || /usr/local/bin/pipx list 2>/dev/null | grep -q openai-whisper || ls ~/.local/bin/whisper 2>/dev/null",
            install: "/opt/homebrew/bin/pipx install openai-whisper",
            desc: "OpenAI speech recognition engine"
        ),
    ]
    
    /// Build a proper environment with all necessary PATH entries for GUI app context
    static func makeFullEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(homeDir)/.local/bin",
            "\(homeDir)/.local/pipx/venvs/openai-whisper/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        return env
    }
    
    /// Check if a single dependency is installed
    func checkDependency(_ dep: Dependency, completion: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", dep.checkCommand]
        process.environment = DependencyManager.makeFullEnv()
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            completion(process.terminationStatus == 0)
        } catch {
            logError("DependencyManager", "Failed to check \(dep.name): \(error)")
            completion(false)
        }
    }
    
    /// Check all dependencies and return their statuses
    func checkAll(completion: @escaping ([String: DependencyStatus]) -> Void) {
        let queue = DispatchQueue(label: "com.whispertype.depcheck", qos: .userInitiated)
        var results: [String: DependencyStatus] = [:]
        let group = DispatchGroup()
        let lock = NSLock()
        
        for dep in DependencyManager.dependencies {
            group.enter()
            queue.async {
                self.checkDependency(dep) { installed in
                    lock.lock()
                    results[dep.name] = installed ? .installed : .missing
                    lock.unlock()
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            logInfo("DependencyManager", "Check results: \(results)")
            completion(results)
        }
    }
    
    /// Returns true if all dependencies are installed
    func allInstalled(completion: @escaping (Bool) -> Void) {
        checkAll { results in
            let allGood = results.values.allSatisfy { $0 == .installed }
            completion(allGood)
        }
    }
    
    /// Install a single dependency. Calls progressHandler with log lines. 
    /// For terminal-required deps, opens Terminal.app instead.
    func install(
        _ dep: Dependency,
        progressHandler: @escaping (String) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        if dep.requiresTerminal {
            installViaTerminal(dep, progressHandler: progressHandler, completion: completion)
            return
        }
        
        let queue = DispatchQueue(label: "com.whispertype.install.\(dep.name)", qos: .userInitiated)
        queue.async {
            progressHandler("Installing \(dep.name)...")
            logInfo("DependencyManager", "Installing \(dep.name): \(dep.installCommand)")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", dep.installCommand]
            process.environment = DependencyManager.makeFullEnv()
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            // Stream output
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    for line in lines {
                        progressHandler(line)
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                pipe.fileHandleForReading.readabilityHandler = nil
                
                let status = process.terminationStatus
                if status == 0 {
                    logInfo("DependencyManager", "\(dep.name) installed successfully")
                    progressHandler("✅ \(dep.name) installed successfully")
                    completion(true, nil)
                } else {
                    let errorMsg = "Installation failed with exit code \(status)"
                    logError("DependencyManager", "\(dep.name) install failed: \(errorMsg)")
                    progressHandler("❌ \(dep.name) installation failed")
                    completion(false, errorMsg)
                }
            } catch {
                logError("DependencyManager", "Failed to run install for \(dep.name): \(error)")
                progressHandler("❌ Error: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            }
        }
    }
    
    /// Open Terminal.app to run interactive install (e.g., Homebrew)
    private func installViaTerminal(
        _ dep: Dependency,
        progressHandler: @escaping (String) -> Void,
        completion: @escaping (Bool, String?) -> Void
    ) {
        progressHandler("Opening Terminal to install \(dep.name)...")
        progressHandler("⚠️ \(dep.name) requires an interactive install (admin password needed)")
        progressHandler("Please complete the installation in Terminal, then click 'Re-check' below.")
        logInfo("DependencyManager", "Opening Terminal for \(dep.name) install")
        
        let script = """
        tell application "Terminal"
            activate
            do script "\(dep.installCommand.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        
        DispatchQueue.main.async {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            
            if let error = error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                logError("DependencyManager", "Failed to open Terminal: \(msg)")
                progressHandler("❌ Failed to open Terminal: \(msg)")
                completion(false, msg)
            } else {
                progressHandler("📺 Terminal opened — please complete the install there")
                // We don't know when it finishes, so report "success" meaning we launched it
                completion(true, nil)
            }
        }
    }
    
    /// Find the whisper binary, checking common paths
    func findWhisperBinary() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/.local/bin/whisper",
            "\(homeDir)/.local/pipx/venvs/openai-whisper/bin/whisper",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper",
        ]
        
        // Check file existence first
        if let found = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            logInfo("DependencyManager", "Found whisper at: \(found)")
            return found
        }
        
        // Fallback: use `which` with full PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["whisper"]
        process.environment = DependencyManager.makeFullEnv()
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    logInfo("DependencyManager", "Found whisper via which: \(path)")
                    return path
                }
            }
        } catch {
            logError("DependencyManager", "which whisper failed: \(error)")
        }
        
        logWarn("DependencyManager", "Whisper binary not found")
        return nil
    }
}
