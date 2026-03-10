import Cocoa
import SwiftUI

class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?

    func show(text: String) {
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
        let contentView = OverlayView(text: "")
        let hosting = NSHostingView(rootView: contentView)
        hostingView = hosting

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        w.contentView = hosting
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.isMovableByWindowBackground = false
        w.hasShadow = true
        w.ignoresMouseEvents = true

        // Position at top center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
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
            } else if !text.isEmpty {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            }

            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
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
