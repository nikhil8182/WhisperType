import Cocoa
import Carbon

class TextPaster {
    static let shared = TextPaster()
    
    private init() {}
    
    /// Check if Accessibility permission is granted
    static var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request Accessibility permission (shows system prompt)
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// Open System Settings → Accessibility
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func pasteText(_ text: String) {
        logInfo("TextPaster", "Pasting text (\(text.count) chars): \(text.prefix(50))...")
        
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Increased delay to 200ms before paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let success = self.performPaste()
            
            if success {
                logInfo("TextPaster", "Paste succeeded — restoring clipboard in 2s")
                // Only restore clipboard if paste succeeded
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if let previous = previousContents {
                        pasteboard.clearContents()
                        pasteboard.setString(previous, forType: .string)
                        logDebug("TextPaster", "Clipboard restored")
                    }
                }
            } else {
                logError("TextPaster", "All paste methods failed — leaving text on clipboard for manual Cmd+V")
            }
        }
    }
    
    /// Try paste methods in order: CGEvent → AppleScript → notify user
    /// Returns true if any method succeeded
    private func performPaste() -> Bool {
        // Method 1: CGEvent (fastest, requires Accessibility)
        if Self.isAccessibilityGranted {
            if pasteViaCGEvent() {
                logInfo("TextPaster", "✅ Paste succeeded via CGEvent")
                return true
            }
            logWarn("TextPaster", "CGEvent paste failed, trying AppleScript...")
        } else {
            logWarn("TextPaster", "Accessibility not granted, skipping CGEvent")
        }
        
        // Method 2: AppleScript
        if pasteViaAppleScript() {
            logInfo("TextPaster", "✅ Paste succeeded via AppleScript")
            return true
        }
        logWarn("TextPaster", "AppleScript paste failed, trying pbpaste fallback...")
        
        // Method 3: Notification fallback — text is already on clipboard
        logError("TextPaster", "❌ All paste methods failed. Text is on clipboard.")
        return false
    }
    
    /// CGEvent-based Cmd+V paste
    private func pasteViaCGEvent() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            logError("TextPaster", "Failed to create CGEvent for paste")
            return false
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
    
    /// AppleScript-based Cmd+V paste
    private func pasteViaAppleScript() -> Bool {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            logError("TextPaster", "Failed to create AppleScript")
            return false
        }
        
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        
        if let error = error {
            logError("TextPaster", "AppleScript paste failed: \(error)")
            return false
        }
        
        return true
    }
}
