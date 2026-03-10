import Cocoa
import Carbon

class TextPaster {
    static let shared = TextPaster()
    
    private init() {}
    
    func pasteText(_ text: String) {
        logInfo("TextPaster", "Pasting text (\(text.count) chars): \(text.prefix(50))...")
        
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Small delay to ensure pasteboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
            logInfo("TextPaster", "Paste simulated")
            
            // Restore previous clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                    logDebug("TextPaster", "Clipboard restored")
                }
            }
        }
    }
    
    private func simulatePaste() {
        do {
            let source = CGEventSource(stateID: .hidSystemState)
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                logError("TextPaster", "Failed to create CGEvent for paste")
                return
            }
            
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
