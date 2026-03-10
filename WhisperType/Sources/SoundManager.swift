import AppKit

class SoundManager {
    static let shared = SoundManager()
    
    private init() {}
    
    func playStartSound() {
        // Use system sounds for a native feel
        NSSound(named: "Tink")?.play()
    }
    
    func playStopSound() {
        NSSound(named: "Pop")?.play()
    }
    
    func playErrorSound() {
        NSSound(named: "Basso")?.play()
    }
    
    func playSuccessSound() {
        NSSound(named: "Glass")?.play()
    }
}
