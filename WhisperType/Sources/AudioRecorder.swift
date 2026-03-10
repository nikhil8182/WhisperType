import AVFoundation
import Foundation

class AudioRecorder: NSObject {
    static let shared = AudioRecorder()
    
    private var audioRecorder: AVAudioRecorder?
    private var currentURL: URL?
    
    private override init() {
        super.init()
    }
    
    private func tempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "whispertype_\(UUID().uuidString).wav"
        return tempDir.appendingPathComponent(fileName)
    }
    
    func startRecording() {
        let url = tempAudioURL()
        currentURL = url
        
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
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
        } catch {
            print("Failed to start recording: \(error)")
            currentURL = nil
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard let recorder = audioRecorder, recorder.isRecording else {
            completion(nil)
            return
        }
        
        let url = currentURL
        recorder.stop()
        audioRecorder = nil
        
        // Small delay to ensure file is written
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion(url)
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording encode error: \(error)")
        }
    }
}
