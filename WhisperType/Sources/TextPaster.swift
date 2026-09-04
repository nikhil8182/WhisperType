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
    
    // Copy every representation; NSPasteboardItem instances cannot be reused after a clear.
    static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { values[type] = item.data(forType: type) }
            return values
        }
    }

    @discardableResult
    static func restore(_ contents: [[NSPasteboard.PasteboardType: Data]],
                        to pasteboard: NSPasteboard, ifUnchanged expectedCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedCount else { return false }
        let items = contents.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return true
    }

    func pasteText(_ text: String, targetPID: pid_t?) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previousContents = Self.snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let writtenCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pasteboard.changeCount == writtenCount else {
                AppState.shared.showError("Clipboard changed before paste. Dictation is saved in History.")
                return
            }
            guard let targetPID = targetPID,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
                AppState.shared.showError("Active app changed. Dictation is on the clipboard and in History.")
                return
            }
            if self.performPaste() {
                // Posting a key event is not proof that the target consumed it. History
                // remains the recovery path; never overwrite something copied since then.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    Self.restore(previousContents, to: pasteboard, ifUnchanged: writtenCount)
                }
            } else {
                AppState.shared.showError("Could not paste. Dictation is on the clipboard and in History.")
            }
        }
    }

    /// Try paste methods in order: CGEvent → AppleScript → notify user
    /// Returns true if any method succeeded
    private func performPaste() -> Bool {
        // Method 1: CGEvent (fastest, requires Accessibility)
        if Self.isAccessibilityGranted {
            if pasteViaCGEvent() {
                logInfo("TextPaster", "Paste shortcut posted via CGEvent")
                return true
            }
            logWarn("TextPaster", "CGEvent paste failed, trying AppleScript...")
        } else {
            logWarn("TextPaster", "Accessibility not granted, skipping CGEvent")
        }
        
        // Method 2: AppleScript
        if pasteViaAppleScript() {
            logInfo("TextPaster", "Paste shortcut posted via AppleScript")
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
