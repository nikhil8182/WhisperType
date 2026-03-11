import AppKit
import SwiftUI

/// Controls the dependency setup window shown on first launch or when dependencies are missing.
class SetupWindowController: NSObject {
    static let shared = SetupWindowController()
    
    private var window: NSWindow?
    private var viewModel: SetupViewModel?
    
    /// Show the setup window. If already visible, bring to front.
    func showSetupWindow(onComplete: (() -> Void)? = nil) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let vm = SetupViewModel(onComplete: onComplete)
        self.viewModel = vm
        
        let contentView = SetupView(viewModel: vm)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 500)
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "WhisperType Setup"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start checking dependencies immediately
        vm.checkAllDependencies()
    }
    
    func close() {
        window?.close()
        window = nil
        viewModel = nil
    }
}

// MARK: - ViewModel

class SetupViewModel: ObservableObject {
    @Published var statuses: [String: DependencyManager.DependencyStatus] = [:]
    @Published var logLines: [String] = []
    @Published var isInstalling = false
    @Published var isComplete = false
    @Published var isChecking = false
    
    private var onComplete: (() -> Void)?
    
    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
        // Initialize all as unknown
        for dep in DependencyManager.dependencies {
            statuses[dep.name] = .unknown
        }
    }
    
    func checkAllDependencies() {
        isChecking = true
        appendLog("🔍 Checking dependencies...")
        
        DependencyManager.shared.checkAll { [weak self] results in
            guard let self = self else { return }
            self.statuses = results
            self.isChecking = false
            
            let missing = results.filter { $0.value == .missing }.map { $0.key }
            if missing.isEmpty {
                self.appendLog("✅ All dependencies are installed!")
                self.isComplete = true
                // Auto-close after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.onComplete?()
                    SetupWindowController.shared.close()
                }
            } else {
                self.appendLog("Missing: \(missing.joined(separator: ", "))")
                self.appendLog("Click 'Install All' to set up everything automatically.")
            }
        }
    }
    
    func installAll() {
        isInstalling = true
        appendLog("")
        appendLog("🚀 Starting installation...")
        
        // Install sequentially (order matters — brew first, then brew packages, etc.)
        installNext(index: 0)
    }
    
    private func installNext(index: Int) {
        let deps = DependencyManager.dependencies
        
        guard index < deps.count else {
            // All done — re-check everything
            appendLog("")
            appendLog("🔄 Verifying installations...")
            recheckAfterInstall()
            return
        }
        
        let dep = deps[index]
        
        // Skip already installed
        if statuses[dep.name] == .installed {
            appendLog("✅ \(dep.name) — already installed, skipping")
            installNext(index: index + 1)
            return
        }
        
        // Update status to installing
        DispatchQueue.main.async {
            self.statuses[dep.name] = .installing
        }
        
        DependencyManager.shared.install(dep, progressHandler: { [weak self] line in
            DispatchQueue.main.async {
                self?.appendLog(line)
            }
        }) { [weak self] success, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if success {
                    // For terminal deps, status stays as installing until recheck
                    if !dep.requiresTerminal {
                        self.statuses[dep.name] = .installed
                    }
                } else {
                    self.statuses[dep.name] = .failed(error ?? "Unknown error")
                    self.appendLog("⚠️ \(dep.name) failed, continuing with others...")
                }
                
                // Continue to next dependency
                self.installNext(index: index + 1)
            }
        }
    }
    
    private func recheckAfterInstall() {
        DependencyManager.shared.checkAll { [weak self] results in
            guard let self = self else { return }
            self.statuses = results
            self.isInstalling = false
            
            let missing = results.filter { $0.value != .installed }
            if missing.isEmpty {
                self.appendLog("")
                self.appendLog("🎉 Setup Complete!")
                self.appendLog("Note: The first transcription will download the Whisper model (~150MB for 'base').")
                self.appendLog("This is a one-time download and may take a minute.")
                self.isComplete = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.onComplete?()
                    SetupWindowController.shared.close()
                }
            } else {
                let names = missing.map { $0.key }.joined(separator: ", ")
                self.appendLog("")
                self.appendLog("⚠️ Some dependencies still missing: \(names)")
                self.appendLog("You may need to complete Homebrew install in Terminal first, then click 'Re-check'.")
            }
        }
    }
    
    func recheck() {
        checkAllDependencies()
    }
    
    private func appendLog(_ line: String) {
        if Thread.isMainThread {
            logLines.append(line)
        } else {
            DispatchQueue.main.async {
                self.logLines.append(line)
            }
        }
    }
}

// MARK: - SwiftUI View

struct SetupView: View {
    @ObservedObject var viewModel: SetupViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("WhisperType Setup")
                        .font(.title2.bold())
                    Text("Installing required dependencies")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Dependency list
            VStack(spacing: 6) {
                ForEach(DependencyManager.dependencies, id: \.name) { dep in
                    HStack {
                        statusIcon(for: dep.name)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dep.name)
                                .font(.system(.body, design: .rounded).bold())
                            Text(dep.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        statusLabel(for: dep.name)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
            .padding(.horizontal)
            
            // Log view
            VStack(alignment: .leading, spacing: 4) {
                Text("Log")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(logColor(for: line))
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 140)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .onChange(of: viewModel.logLines.count) { _ in
                        if let last = viewModel.logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Buttons
            HStack {
                if viewModel.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    Text("Setup Complete!")
                        .font(.headline)
                        .foregroundColor(.green)
                } else {
                    Button("Re-check") {
                        viewModel.recheck()
                    }
                    .disabled(viewModel.isInstalling || viewModel.isChecking)
                    
                    Spacer()
                    
                    if viewModel.isInstalling || viewModel.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                    
                    Button("Install All") {
                        viewModel.installAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isInstalling || viewModel.isChecking || viewModel.isComplete)
                }
                
                Spacer()
                
                Button("Close") {
                    SetupWindowController.shared.close()
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 520, height: 500)
    }
    
    @ViewBuilder
    private func statusIcon(for name: String) -> some View {
        switch viewModel.statuses[name] ?? .unknown {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundColor(.gray)
        }
    }
    
    @ViewBuilder
    private func statusLabel(for name: String) -> some View {
        switch viewModel.statuses[name] ?? .unknown {
        case .installed:
            Text("Installed")
                .font(.caption)
                .foregroundColor(.green)
        case .missing:
            Text("Missing")
                .font(.caption)
                .foregroundColor(.red)
        case .installing:
            Text("Installing...")
                .font(.caption)
                .foregroundColor(.orange)
        case .failed(let msg):
            Text("Failed")
                .font(.caption)
                .foregroundColor(.orange)
                .help(msg)
        case .unknown:
            Text("Checking...")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private func logColor(for line: String) -> Color {
        if line.contains("✅") || line.contains("🎉") { return .green }
        if line.contains("❌") || line.contains("⚠️") { return .orange }
        if line.contains("🔍") || line.contains("🚀") || line.contains("🔄") { return .blue }
        return .primary
    }
}
