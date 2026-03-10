import AVFoundation
import Foundation

/// Records audio using a PERSISTENT AVAudioEngine that lives for the entire app lifetime.
/// The engine is created once and never destroyed — only taps are installed/removed.
/// This avoids the SIGTRAP crash caused by repeated engine creation/destruction.
class AudioRecorder: NSObject {
    static let shared = AudioRecorder()

    /// Single engine — created once, lives forever
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var isCurrentlyRecording = false
    private let lock = NSLock()

    /// Target format for Whisper: 16kHz mono 16-bit PCM
    private let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: true)!

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

        // Ensure clean state — remove any stale tap
        removeTapSafely()

        // If engine is running from a previous cycle, stop it first
        if engine.isRunning {
            engine.stop()
            logInfo("AudioRecorder", "Stopped previously-running engine")
        }

        let url = tempAudioURL()

        logInfo("AudioRecorder", "Starting recording to: \(url.lastPathComponent)")

        do {
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            logInfo("AudioRecorder", "Input format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

            // Validate the format
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                logError("AudioRecorder", "Invalid input format — no audio input device?")
                return
            }

            // Create output file
            let file = try AVAudioFile(forWriting: url, settings: whisperFormat.settings)

            lock.lock()
            self.audioFile = file
            self.currentURL = url
            lock.unlock()

            // Create converter for resampling
            let converter = AVAudioConverter(from: recordingFormat, to: whisperFormat)

            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                self.lock.lock()
                let recording = self.isCurrentlyRecording
                let file = self.audioFile
                self.lock.unlock()

                guard recording, let file = file else { return }

                do {
                    if let converter = converter {
                        let ratio = 16000.0 / recordingFormat.sampleRate
                        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                        guard frameCount > 0,
                              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.whisperFormat, frameCapacity: frameCount) else { return }

                        var error: NSError?
                        let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }

                        if status == .haveData || status == .endOfStream {
                            try file.write(from: convertedBuffer)
                        } else if let error = error {
                            logError("AudioRecorder", "Converter error: \(error)")
                        }
                    } else {
                        try file.write(from: buffer)
                    }
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

        // Remove the tap (but keep the engine alive)
        removeTapSafely()

        // Stop the engine (will restart on next recording)
        if engine.isRunning {
            engine.stop()
        }

        // Brief delay for file I/O to flush
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

    /// Safely remove tap — ignores errors if no tap is installed
    private func removeTapSafely() {
        // removeTap will crash if no tap is installed on some OS versions,
        // so we swallow any issues
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
        // Reset the engine's graph to clear any stale state
        engine.reset()
        logInfo("AudioRecorder", "Engine reset complete")
    }
}
