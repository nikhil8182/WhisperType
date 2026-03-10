import AVFoundation
import Foundation

class AudioRecorder: NSObject {
    static let shared = AudioRecorder()
    
    private var audioRecorder: AVAudioRecorder?
    private var currentURL: URL?
    private let lock = NSLock()
    private var isCurrentlyRecording = false
    
    private override init() {
        super.init()
        logInfo("AudioRecorder", "Initialized")
    }
    
    private func tempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "whispertype_\(UUID().uuidString).wav"
        return tempDir.appendingPathComponent(fileName)
    }
    
    func startRecording() {
        lock.lock()
        defer { lock.unlock() }
        
        // Clean up any previous recorder
        if let existing = audioRecorder {
            logWarn("AudioRecorder", "Previous recorder still exists, cleaning up")
            existing.stop()
            audioRecorder = nil
        }
        
        let url = tempAudioURL()
        currentURL = url
        
        logInfo("AudioRecorder", "Starting recording to: \(url.lastPathComponent)")
        
        // WAV format settings optimized for Whisper (16kHz mono 16-bit)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            
            if recorder.record() {
                audioRecorder = recorder
                isCurrentlyRecording = true
                logInfo("AudioRecorder", "Recording started successfully")
            } else {
                logError("AudioRecorder", "record() returned false")
                currentURL = nil
                isCurrentlyRecording = false
            }
        } catch {
            logError("AudioRecorder", "Failed to create recorder: \(error)")
            currentURL = nil
            isCurrentlyRecording = false
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        lock.lock()
        
        guard let recorder = audioRecorder, isCurrentlyRecording else {
            logWarn("AudioRecorder", "stopRecording called but not recording")
            let url = currentURL
            currentURL = nil
            isCurrentlyRecording = false
            lock.unlock()
            completion(url) // Return URL if we have one even if recorder state is odd
            return
        }
        
        let url = currentURL
        logInfo("AudioRecorder", "Stopping recording. Duration: \(String(format: "%.1f", recorder.currentTime))s")
        
        recorder.stop()
        audioRecorder = nil
        currentURL = nil
        isCurrentlyRecording = false
        lock.unlock()
        
        // Small delay to ensure file is flushed to disk
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let url = url {
                let exists = FileManager.default.fileExists(atPath: url.path)
                logInfo("AudioRecorder", "Audio file exists: \(exists), path: \(url.lastPathComponent)")
                if exists {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? UInt64 {
                        logInfo("AudioRecorder", "Audio file size: \(size) bytes")
                    }
                    completion(url)
                } else {
                    logError("AudioRecorder", "Audio file missing after recording!")
                    completion(nil)
                }
            } else {
                logError("AudioRecorder", "No URL after recording!")
                completion(nil)
            }
        }
    }
    
    /// Reset state completely — call if things get stuck
    func forceReset() {
        lock.lock()
        defer { lock.unlock() }
        logWarn("AudioRecorder", "Force reset")
        audioRecorder?.stop()
        audioRecorder = nil
        currentURL = nil
        isCurrentlyRecording = false
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        logInfo("AudioRecorder", "Delegate: finished recording, success=\(flag)")
        if !flag {
            logError("AudioRecorder", "Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            logError("AudioRecorder", "Encode error: \(error)")
        }
    }
}
