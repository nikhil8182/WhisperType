import AVFoundation
import Foundation

/// Records audio using a PERSISTENT AVAudioEngine that lives for the entire app lifetime.
/// Records in native mic format — Whisper handles any conversion needed.
class AudioRecorder: NSObject {
    static let shared = AudioRecorder()

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var isCurrentlyRecording = false
    private let lock = NSLock()

    private override init() {
        super.init()
        logInfo("AudioRecorder", "Initialized (persistent AVAudioEngine)")
    }

    private func tempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "whispertype_\(UUID().uuidString).wav"
        return tempDir.appendingPathComponent(fileName)
    }

    func startRecording() {
        lock.lock()
        guard !isCurrentlyRecording else {
            logWarn("AudioRecorder", "Already recording, ignoring startRecording")
            lock.unlock()
            return
        }
        lock.unlock()

        removeTapSafely()

        if engine.isRunning {
            engine.stop()
        }

        let url = tempAudioURL()
        logInfo("AudioRecorder", "Starting recording to: \(url.lastPathComponent)")

        do {
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            logInfo("AudioRecorder", "Input format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                logError("AudioRecorder", "Invalid input format — no audio input device?")
                return
            }

            // Record in NATIVE format — no conversion, no crashes
            let file = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)

            lock.lock()
            self.audioFile = file
            self.currentURL = url
            lock.unlock()

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                self.lock.lock()
                let recording = self.isCurrentlyRecording
                let file = self.audioFile
                self.lock.unlock()

                guard recording, let file = file else { return }

                do {
                    try file.write(from: buffer)
                } catch {
                    logError("AudioRecorder", "Write error: \(error)")
                }
            }

            engine.prepare()
            try engine.start()

            lock.lock()
            isCurrentlyRecording = true
            lock.unlock()

            logInfo("AudioRecorder", "Recording started successfully")

        } catch {
            logError("AudioRecorder", "Failed to start recording: \(error)")
            removeTapSafely()
            if engine.isRunning { engine.stop() }

            lock.lock()
            audioFile = nil
            currentURL = nil
            lock.unlock()
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        lock.lock()
        guard isCurrentlyRecording else {
            logWarn("AudioRecorder", "stopRecording called but not recording")
            lock.unlock()
            completion(nil)
            return
        }

        isCurrentlyRecording = false
        let url = currentURL
        audioFile = nil
        currentURL = nil
        lock.unlock()

        logInfo("AudioRecorder", "Stopping recording")

        removeTapSafely()

        if engine.isRunning {
            engine.stop()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let url = url else {
                logError("AudioRecorder", "No URL after stop")
                completion(nil)
                return
            }

            let exists = FileManager.default.fileExists(atPath: url.path)
            var fileSize: UInt64 = 0
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                fileSize = size
            }

            logInfo("AudioRecorder", "Audio file exists: \(exists), size: \(fileSize) bytes")

            if exists && fileSize > 100 {
                completion(url)
            } else {
                logError("AudioRecorder", "Audio file missing or empty")
                try? FileManager.default.removeItem(at: url)
                completion(nil)
            }
        }
    }

    private func removeTapSafely() {
        engine.inputNode.removeTap(onBus: 0)
    }

    func forceReset() {
        logWarn("AudioRecorder", "Force reset")

        lock.lock()
        isCurrentlyRecording = false
        audioFile = nil
        currentURL = nil
        lock.unlock()

        removeTapSafely()
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        logInfo("AudioRecorder", "Engine reset complete")
    }
}
