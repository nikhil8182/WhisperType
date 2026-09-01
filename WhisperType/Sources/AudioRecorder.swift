import AVFoundation
import Foundation

/// Records audio using a PERSISTENT AVAudioEngine that lives for the entire app lifetime.
/// Writes the native-format WAV (fallback path for the whisper CLI) AND keeps a 16 kHz mono
/// Float32 buffer in memory for the local engine (live partials + final).
class AudioRecorder: NSObject {
    static let shared = AudioRecorder()

    static let engineFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var converter: AVAudioConverter?
    private var pcm16k = Data()
    private var isCurrentlyRecording = false
    private let lock = NSLock()

    /// Smoothed mic level 0...1 for the overlay waveform (written from the audio thread)
    private(set) var level: Float = 0

    private override init() {
        super.init()
        logInfo("AudioRecorder", "Initialized (persistent AVAudioEngine)")
    }

    private func tempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "whispertype_\(UUID().uuidString).wav"
        return tempDir.appendingPathComponent(fileName)
    }

    /// Seconds of audio captured so far (16 kHz buffer)
    var capturedSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(pcm16k.count / 4) / 16000.0
    }

    /// Copy of everything captured so far as Float32 LE 16 kHz mono
    func snapshotPCM() -> Data {
        lock.lock(); defer { lock.unlock() }
        return pcm16k
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
            let conv = AVAudioConverter(from: recordingFormat, to: AudioRecorder.engineFormat)
            let ratio = AudioRecorder.engineFormat.sampleRate / recordingFormat.sampleRate

            lock.lock()
            self.audioFile = file
            self.currentURL = url
            self.converter = conv
            self.pcm16k = Data()
            self.pcm16k.reserveCapacity(16000 * 4 * 60)
            lock.unlock()

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                self.lock.lock()
                let recording = self.isCurrentlyRecording
                let file = self.audioFile
                let conv = self.converter
                self.lock.unlock()

                guard recording, let file = file else { return }

                // Level meter (RMS → 0...1, fast attack / slow release)
                if let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    var sum: Float = 0
                    let n = Int(buffer.frameLength)
                    for i in 0..<n { sum += ch[i] * ch[i] }
                    let rms = sqrtf(sum / Float(n))
                    let target = min(1, rms * 9)
                    self.level = target > self.level ? target : self.level * 0.85 + target * 0.15
                }

                do {
                    try file.write(from: buffer)
                } catch {
                    logError("AudioRecorder", "Write error: \(error)")
                }

                // Downsample to 16 kHz mono float for the engine
                guard let conv = conv else { return }
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
                guard let out = AVAudioPCMBuffer(pcmFormat: AudioRecorder.engineFormat, frameCapacity: capacity) else { return }
                var consumed = false
                var convError: NSError?
                let status = conv.convert(to: out, error: &convError) { _, outStatus in
                    if consumed { outStatus.pointee = .noDataNow; return nil }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if status != .error, out.frameLength > 0, let ch = out.floatChannelData {
                    let bytes = Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Float>.size)
                    self.lock.lock()
                    self.pcm16k.append(bytes)
                    self.lock.unlock()
                } else if let e = convError {
                    logWarn("AudioRecorder", "convert error: \(e.localizedDescription)")
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
            converter = nil
            lock.unlock()
        }
    }

    /// Stops and returns (wavURL, pcm16k). URL is nil if the file is missing/empty.
    func stopRecording(completion: @escaping (URL?, Data) -> Void) {
        lock.lock()
        guard isCurrentlyRecording else {
            logWarn("AudioRecorder", "stopRecording called but not recording")
            lock.unlock()
            completion(nil, Data())
            return
        }

        isCurrentlyRecording = false
        level = 0
        let url = currentURL
        let pcm = pcm16k
        audioFile = nil
        currentURL = nil
        converter = nil
        lock.unlock()

        logInfo("AudioRecorder", "Stopping recording (\(String(format: "%.1f", Double(pcm.count / 4) / 16000))s captured)")

        removeTapSafely()

        if engine.isRunning {
            engine.stop()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let url = url else {
                logError("AudioRecorder", "No URL after stop")
                completion(nil, pcm)
                return
            }

            let exists = FileManager.default.fileExists(atPath: url.path)
            var fileSize: UInt64 = 0
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                fileSize = size
            }

            if exists && fileSize > 100 {
                completion(url, pcm)
            } else {
                logError("AudioRecorder", "Audio file missing or empty")
                try? FileManager.default.removeItem(at: url)
                completion(nil, pcm)
            }
        }
    }

    /// Discard the current recording without transcribing
    func cancelRecording() {
        stopRecording { url, _ in
            if let url = url { try? FileManager.default.removeItem(at: url) }
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
        converter = nil
        pcm16k = Data()
        lock.unlock()

        removeTapSafely()
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        logInfo("AudioRecorder", "Engine reset complete")
    }
}
