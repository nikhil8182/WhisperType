import Foundation

class WhisperManager {
    static let shared = WhisperManager()
    
    private let whisperPath: String
    
    private init() {
        // Try to find whisper in common locations
        let possiblePaths = [
            "/Users/onwords/.local/bin/whisper",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper"
        ]
        
        self.whisperPath = possiblePaths.first { FileManager.default.fileExists(atPath: $0) } ?? "whisper"
    }
    
    func checkAvailability(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["whisper"]
            
            // Inherit PATH
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/Users/onwords/.local/bin:/opt/homebrew/bin:/usr/local/bin"
            if let existing = env["PATH"] {
                env["PATH"] = "\(extraPaths):\(existing)"
            } else {
                env["PATH"] = extraPaths
            }
            process.environment = env
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                completion(process.terminationStatus == 0)
            } catch {
                completion(false)
            }
        }
    }
    
    func transcribe(audioURL: URL, model: String, language: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("whispertype_out_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.whisperPath)
            process.arguments = [
                audioURL.path,
                "--model", model,
                "--language", language,
                "--output_format", "txt",
                "--output_dir", outputDir.path,
                "--fp16", "False",  // CPU doesn't support fp16
                "--verbose", "False"
            ]
            
            // Set up environment with proper PATH
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/Users/onwords/.local/bin:/opt/homebrew/bin:/usr/local/bin"
            if let existing = env["PATH"] {
                env["PATH"] = "\(extraPaths):\(existing)"
            } else {
                env["PATH"] = extraPaths
            }
            process.environment = env
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            // Read pipes asynchronously to avoid deadlocks
            var stdoutData = Data()
            var stderrData = Data()
            
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutData.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrData.append(handle.availableData)
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Stop reading
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                
                if process.terminationStatus != 0 {
                    let errorString = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    completion(.failure(NSError(domain: "WhisperType", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorString])))
                    // Cleanup
                    try? FileManager.default.removeItem(at: outputDir)
                    return
                }
                
                // Read the output text file
                let audioName = audioURL.deletingPathExtension().lastPathComponent
                let txtFile = outputDir.appendingPathComponent("\(audioName).txt")
                
                if FileManager.default.fileExists(atPath: txtFile.path) {
                    let text = try String(contentsOf: txtFile, encoding: .utf8)
                    completion(.success(text))
                } else {
                    // Try to find any .txt file in the output dir
                    let files = try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
                    if let txtFiles = files?.filter({ $0.pathExtension == "txt" }), let first = txtFiles.first {
                        let text = try String(contentsOf: first, encoding: .utf8)
                        completion(.success(text))
                    } else {
                        // Fall back to reading stdout
                        let output = String(data: stdoutData, encoding: .utf8) ?? ""
                        if output.isEmpty {
                            completion(.failure(NSError(domain: "WhisperType", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transcription output"])))
                        } else {
                            completion(.success(output))
                        }
                    }
                }
                
                // Cleanup output dir
                try? FileManager.default.removeItem(at: outputDir)
                
            } catch {
                completion(.failure(error))
                try? FileManager.default.removeItem(at: outputDir)
            }
        }
    }
}
