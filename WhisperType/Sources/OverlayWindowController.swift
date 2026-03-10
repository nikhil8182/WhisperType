import Cocoa
import SwiftUI

class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private var overlayText: String = ""
    
    func show(text: String) {
        overlayText = text
        
        if window == nil {
            createWindow()
        }
        
        hostingView?.rootView = OverlayView(text: text)
        window?.orderFront(nil)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    private func createWindow() {
        let contentView = OverlayView(text: overlayText)
        let hosting = NSHostingView(rootView: contentView)
        hostingView = hosting
        
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        w.contentView = hosting
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.isMovableByWindowBackground = false
        w.hasShadow = true
        w.ignoresMouseEvents = true
        
        // Position at top center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 100
            let y = screenFrame.maxY - 80
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window = w
    }
}

struct OverlayView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            if text.contains("Recording") {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .modifier(PulseAnimation())
            } else {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            }
            
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.8))
        )
        .shadow(color: .black.opacity(0.3), radius: 10)
    }
}

struct PulseAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}
