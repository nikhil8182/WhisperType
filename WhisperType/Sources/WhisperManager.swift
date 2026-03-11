import Foundation

class WhisperManager {
    static let shared = WhisperManager()
    
    private var whisperPath: String
    private let processQueue = DispatchQueue(label: "com.whispertype.whisper", qos: .userInitiated)
    private var currentProcess: Process?
    private var timeoutWorkItem: DispatchWorkItem?
    private let lock = NSLock()
    
    private static let whisperTimeout: TimeInterval = 60.0
    
    private init() {
        self.whisperPath = DependencyManager.shared.findWhisperBinary() ?? "whisper"
        logInfo("WhisperManager", "Initialized. Whisper path: \(whisperPath)")
    }
    
    /// Re-resolve the whisper binary path (e.g., after dependency install)
    func refreshWhisperPath() {
        let newPath = DependencyManager.shared.findWhisperBinary() ?? "whisper"
        if newPath != whisperPath {
            logInfo("WhisperManager", "Whisper path updated: \(whisperPath) → \(newPath)")
            whisperPath = newPath
        }
    }
    
    private func makeEnv() -> [String: String] {
        return DependencyManager.makeFullEnv()
    }
    
    func checkAvailability(completion: @escaping (Bool) -> Void) {
        processQueue.async { [self] in
            logInfo("WhisperManager", "Checking whisper availability...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["whisper"]
            process.environment = self.makeEnv()
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                let available = process.terminationStatus == 0
                logInfo("WhisperManager", "Whisper available: \(available)")
                completion(available)
            } catch {
                logError("WhisperManager", "Failed to check whisper: \(error)")
                completion(false)
            }
        }
    }
    
    func transcribe(audioURL: URL, model: String, language: String, completion: @escaping (Result<String, Error>) -> Void) {
        processQueue.async { [self] in
            logInfo("WhisperManager", "Starting transcription. Audio: \(audioURL.lastPathComponent), Model: \(model), Language: \(language)")
            
            let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("whispertype_out_\(UUID().uuidString)")
            
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            } catch {
                logError("WhisperManager", "Failed to create output dir: \(error)")
                completion(.failure(error))
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.whisperPath)
            process.arguments = [
                audioURL.path,
                "--model", model,
                "--language", language,
                "--output_format", "txt",
                "--output_dir", outputDir.path,
                "--fp16", "False",
                "--verbose", "False"
            ]
            process.environment = self.makeEnv()
            
            // Use separate pipes for stdout and stderr, read via data collection
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            // Collect data from pipes asynchronously to prevent deadlock
            let stdoutLock = NSLock()
            let stderrLock = NSLock()
            var stdoutData = Data()
            var stderrData = Data()
            
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stdoutLock.lock()
                    stdoutData.append(data)
                    stdoutLock.unlock()
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrLock.lock()
                    stderrData.append(data)
                    stderrLock.unlock()
                }
            }
            
            // Store reference for timeout killing
            self.lock.lock()
            self.currentProcess = process
            self.lock.unlock()
            
            // Set up timeout
            let timeout = DispatchWorkItem { [weak self] in
                self?.lock.lock()
                let proc = self?.currentProcess
                self?.currentProcess = nil
                self?.lock.unlock()
                
                if let proc = proc, proc.isRunning {
                    logError("WhisperManager", "Whisper process timed out after \(WhisperManager.whisperTimeout)s — killing")
                    proc.terminate()
                    // Give it a moment, then force kill
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if proc.isRunning {
                            logError("WhisperManager", "Force killing whisper process")
                            proc.interrupt()
                        }
                    }
                }
            }
            self.lock.lock()
            self.timeoutWorkItem = timeout
            self.lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + WhisperManager.whisperTimeout, execute: timeout)
            
            do {
                try process.run()
                logInfo("WhisperManager", "Whisper process launched (PID: \(process.processIdentifier))")
                
                process.waitUntilExit()
                
                // Cancel timeout
                timeout.cancel()
                
                // Stop reading handlers before reading final data
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                
                // Read any remaining data
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                stdoutLock.lock()
                stdoutData.append(remainingStdout)
                stdoutLock.unlock()
                
                stderrLock.lock()
                stderrData.append(remainingStderr)
                stderrLock.unlock()
                
                // Clear process reference
                self.lock.lock()
                self.currentProcess = nil
                self.lock.unlock()
                
                let status = process.terminationStatus
                logInfo("WhisperManager", "Whisper exited with status \(status)")
                
                if let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    logDebug("WhisperManager", "Whisper stderr: \(stderrStr.prefix(500))")
                }
                
                if status != 0 {
                    let errorString = String(data: stderrData, encoding: .utf8) ?? "Unknown whisper error (exit code \(status))"
                    logError("WhisperManager", "Whisper failed: \(errorString.prefix(300))")
                    completion(.failure(NSError(domain: "WhisperType", code: Int(status),
                                                userInfo: [NSLocalizedDescriptionKey: errorString])))
                    try? FileManager.default.removeItem(at: outputDir)
                    return
                }
                
                // Read the output text file
                let text = try self.readTranscriptionOutput(audioURL: audioURL, outputDir: outputDir, stdoutData: stdoutData)
                logInfo("WhisperManager", "Transcription result (\(text.count) chars): \(text.prefix(100))...")
                completion(.success(text))
                
            } catch {
                timeout.cancel()
                
                self.lock.lock()
                self.currentProcess = nil
                self.lock.unlock()
                
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                
                logError("WhisperManager", "Failed to run whisper: \(error)")
                completion(.failure(error))
            }
            
            // Cleanup
            try? FileManager.default.removeItem(at: outputDir)
        }
    }
    
    private func readTranscriptionOutput(audioURL: URL, outputDir: URL, stdoutData: Data) throws -> String {
        let audioName = audioURL.deletingPathExtension().lastPathComponent
        let txtFile = outputDir.appendingPathComponent("\(audioName).txt")
        
        if FileManager.default.fileExists(atPath: txtFile.path) {
            return try String(contentsOf: txtFile, encoding: .utf8)
        }
        
        // Try to find any .txt file in the output dir
        if let files = try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil) {
            let txtFiles = files.filter { $0.pathExtension == "txt" }
            if let first = txtFiles.first {
                logInfo("WhisperManager", "Found alternative txt file: \(first.lastPathComponent)")
                return try String(contentsOf: first, encoding: .utf8)
            }
        }
        
        // Fall back to stdout
        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logWarn("WhisperManager", "Using stdout as transcription output")
            return output
        }
        
        throw NSError(domain: "WhisperType", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "No transcription output found"])
    }
}
