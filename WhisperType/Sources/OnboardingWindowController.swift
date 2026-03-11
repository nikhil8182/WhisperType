import AppKit
import SwiftUI
import AVFoundation
import Combine

// MARK: - Window Controller

class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    
    private var window: NSWindow?
    private var viewModel: OnboardingViewModel?
    
    /// Show the onboarding window
    func show(forceShow: Bool = false) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let vm = OnboardingViewModel(forceShow: forceShow)
        self.viewModel = vm
        
        let contentView = OnboardingContainerView(viewModel: vm) { [weak self] in
            self?.completeOnboarding()
        }
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 620)
        hostingView.autoresizingMask = [.width, .height]
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.title = "WhisperType Setup"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1.0)
        win.isMovableByWindowBackground = true
        win.hasShadow = true
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
        window = nil
        viewModel?.stopTimers()
        viewModel = nil
    }
    
    /// Animate the window to the menu bar and close
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        guard let window = window else {
            close()
            return
        }
        
        // Find the approximate menu bar icon position
        let screenFrame = NSScreen.main?.frame ?? .zero
        let menuBarTarget = NSRect(
            x: screenFrame.maxX - 100,
            y: screenFrame.maxY - 24,
            width: 24,
            height: 24
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(menuBarTarget, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
        })
    }
}

// MARK: - View Model

class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case dependencies = 1
        case permissions = 2
        case howToUse = 3
        case ready = 4
    }
    
    @Published var currentStep: Step = .welcome
    @Published var depStatuses: [String: DependencyManager.DependencyStatus] = [:]
    @Published var isCheckingDeps = false
    @Published var isInstallingDeps = false
    @Published var depLog: [String] = []
    
    @Published var hasMicPermission = false
    @Published var hasAccessibilityPermission = false
    
    @Published var trialTranscription: String? = nil
    @Published var isTrialRecording = false
    @Published var isTrialTranscribing = false
    
    @Published var countdownValue: Int = 5
    @Published var isCountingDown = false
    
    private var permissionTimer: Timer?
    private var countdownTimer: Timer?
    private let forceShow: Bool
    
    var allDepsInstalled: Bool {
        !depStatuses.isEmpty && depStatuses.values.allSatisfy { $0 == .installed }
    }
    
    var allPermissionsGranted: Bool {
        hasMicPermission && hasAccessibilityPermission
    }
    
    init(forceShow: Bool) {
        self.forceShow = forceShow
        for dep in DependencyManager.dependencies {
            depStatuses[dep.name] = .unknown
        }
        checkPermissionsNow()
    }
    
    func stopTimers() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    // MARK: - Navigation
    
    func goToStep(_ step: Step) {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
        
        switch step {
        case .dependencies:
            checkDependencies()
        case .permissions:
            startPermissionPolling()
        case .ready:
            startCountdown()
        default:
            break
        }
    }
    
    func nextStep() {
        let nextRaw = currentStep.rawValue + 1
        if let next = Step(rawValue: nextRaw) {
            goToStep(next)
        }
    }
    
    func previousStep() {
        let prevRaw = currentStep.rawValue - 1
        if let prev = Step(rawValue: prevRaw) {
            goToStep(prev)
        }
    }
    
    // MARK: - Dependencies
    
    func checkDependencies() {
        isCheckingDeps = true
        depLog.removeAll()
        depLog.append("Checking dependencies...")
        
        DependencyManager.shared.checkAll { [weak self] results in
            guard let self = self else { return }
            self.depStatuses = results
            self.isCheckingDeps = false
            
            let missing = results.filter { $0.value == .missing }.map { $0.key }
            if missing.isEmpty {
                self.depLog.append("All dependencies installed ✅")
            } else {
                self.depLog.append("Missing: \(missing.joined(separator: ", "))")
            }
        }
    }
    
    func installMissing() {
        isInstallingDeps = true
        depLog.append("")
        depLog.append("Starting installation...")
        installNext(index: 0)
    }
    
    private func installNext(index: Int) {
        let deps = DependencyManager.dependencies
        guard index < deps.count else {
            depLog.append("Verifying installations...")
            DependencyManager.shared.checkAll { [weak self] results in
                guard let self = self else { return }
                self.depStatuses = results
                self.isInstallingDeps = false
                
                let stillMissing = results.filter { $0.value != .installed }
                if stillMissing.isEmpty {
                    self.depLog.append("All dependencies installed! ✅")
                } else {
                    self.depLog.append("Some deps still missing. Complete Homebrew install in Terminal, then re-check.")
                }
            }
            return
        }
        
        let dep = deps[index]
        if depStatuses[dep.name] == .installed {
            installNext(index: index + 1)
            return
        }
        
        DispatchQueue.main.async {
            self.depStatuses[dep.name] = .installing
        }
        
        DependencyManager.shared.install(dep, progressHandler: { [weak self] line in
            DispatchQueue.main.async {
                self?.depLog.append(line)
            }
        }) { [weak self] success, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if success && !dep.requiresTerminal {
                    self.depStatuses[dep.name] = .installed
                } else if !success {
                    self.depStatuses[dep.name] = .failed(error ?? "Unknown error")
                }
                self.installNext(index: index + 1)
            }
        }
    }
    
    // MARK: - Permissions
    
    func checkPermissionsNow() {
        hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    func startPermissionPolling() {
        permissionTimer?.invalidate()
        checkPermissionsNow()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermissionsNow()
        }
    }
    
    func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasMicPermission = granted
            }
        }
    }
    
    func openAccessibilitySettings() {
        TextPaster.openAccessibilitySettings()
    }
    
    // MARK: - Trial Recording
    
    func startTrialRecording() {
        guard !isTrialRecording && !isTrialTranscribing else { return }
        isTrialRecording = true
        trialTranscription = nil
        
        if AppState.shared.playSounds {
            SoundManager.shared.playStartSound()
        }
        AudioRecorder.shared.startRecording()
    }
    
    func stopTrialRecording() {
        guard isTrialRecording else { return }
        isTrialRecording = false
        isTrialTranscribing = true
        
        if AppState.shared.playSounds {
            SoundManager.shared.playStopSound()
        }
        
        AudioRecorder.shared.stopRecording { [weak self] audioURL in
            guard let self = self, let audioURL = audioURL else {
                DispatchQueue.main.async {
                    self?.isTrialTranscribing = false
                    self?.trialTranscription = "No audio captured. Try again!"
                }
                return
            }
            
            let model = AppState.shared.whisperModel
            WhisperManager.shared.transcribe(audioURL: audioURL, model: model, language: AppState.shared.language) { [weak self] result in
                try? FileManager.default.removeItem(at: audioURL)
                DispatchQueue.main.async {
                    self?.isTrialTranscribing = false
                    switch result {
                    case .success(let text):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        self?.trialTranscription = trimmed.isEmpty ? "No speech detected. Try again!" : trimmed
                    case .failure(let error):
                        self?.trialTranscription = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Countdown
    
    func startCountdown() {
        countdownValue = 5
        isCountingDown = true
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.countdownValue -= 1
            if self.countdownValue <= 0 {
                timer.invalidate()
                self.isCountingDown = false
            }
        }
    }
}

// MARK: - Container View

struct OnboardingContainerView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onComplete: () -> Void
    
    // Branding colors
    let deepBlue = Color(red: 0.1, green: 0.1, blue: 0.18)
    let teal = Color(red: 0.086, green: 0.627, blue: 0.522)
    let lightText = Color.white
    let subtleText = Color.white.opacity(0.6)
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [deepBlue, Color(red: 0.08, green: 0.08, blue: 0.15)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress dots
                progressDots
                    .padding(.top, 32)
                    .padding(.bottom, 16)
                
                // Content
                ZStack {
                    switch viewModel.currentStep {
                    case .welcome:
                        WelcomeStepView(teal: teal, lightText: lightText, subtleText: subtleText) {
                            viewModel.nextStep()
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    case .dependencies:
                        DependenciesStepView(viewModel: viewModel, teal: teal, lightText: lightText, subtleText: subtleText)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .permissions:
                        PermissionsStepView(viewModel: viewModel, teal: teal, lightText: lightText, subtleText: subtleText)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .howToUse:
                        HowToUseStepView(viewModel: viewModel, teal: teal, lightText: lightText, subtleText: subtleText)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .ready:
                        ReadyStepView(viewModel: viewModel, teal: teal, lightText: lightText, subtleText: subtleText, onComplete: onComplete)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .frame(width: 520, height: 620)
    }
    
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= viewModel.currentStep.rawValue ? teal : Color.white.opacity(0.2))
                    .frame(width: step == viewModel.currentStep ? 10 : 7, height: step == viewModel.currentStep ? 10 : 7)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
            }
        }
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStepView: View {
    let teal: Color
    let lightText: Color
    let subtleText: Color
    var onGetStarted: () -> Void
    
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [teal.opacity(0.3), .clear]),
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [teal, Color(red: 0.2, green: 0.8, blue: 0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            
            VStack(spacing: 12) {
                Text("Welcome to WhisperType")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(lightText)
                
                Text("Voice-to-text for macOS.\nHold a key, speak, release to type.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(subtleText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(textOpacity)
            
            Spacer()
            
            Button(action: onGetStarted) {
                HStack(spacing: 8) {
                    Text("Get Started")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 200, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(teal)
                )
                .shadow(color: teal.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .opacity(buttonOpacity)
            
            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                textOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                buttonOpacity = 1.0
            }
        }
    }
}

// MARK: - Step 2: Dependencies

struct DependenciesStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let teal: Color
    let lightText: Color
    let subtleText: Color
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 36))
                    .foregroundColor(teal)
                
                Text("Dependencies")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(lightText)
                
                Text("WhisperType needs a few tools to work")
                    .font(.system(size: 14))
                    .foregroundColor(subtleText)
            }
            .padding(.top, 8)
            
            // Dependency list
            VStack(spacing: 6) {
                ForEach(DependencyManager.dependencies, id: \.name) { dep in
                    depRow(dep)
                }
            }
            .padding(.horizontal, 24)
            
            // Log area (only show when installing)
            if !viewModel.depLog.isEmpty && (viewModel.isInstallingDeps || viewModel.depLog.count > 2) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.depLog.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(subtleText)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal, 24)
                    .onChange(of: viewModel.depLog.count) { _ in
                        if let last = viewModel.depLog.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 16) {
                if viewModel.allDepsInstalled {
                    Button(action: { viewModel.nextStep() }) {
                        HStack(spacing: 8) {
                            Text("All Set!")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 180, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(teal))
                    }
                    .buttonStyle(.plain)
                } else if viewModel.isInstallingDeps || viewModel.isCheckingDeps {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: teal))
                        .scaleEffect(0.8)
                    Text(viewModel.isInstallingDeps ? "Installing..." : "Checking...")
                        .font(.system(size: 14))
                        .foregroundColor(subtleText)
                } else {
                    Button(action: { viewModel.checkDependencies() }) {
                        Text("Re-check")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(subtleText)
                            .frame(height: 40)
                            .padding(.horizontal, 16)
                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { viewModel.installMissing() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install Missing")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(height: 44)
                        .padding(.horizontal, 24)
                        .background(RoundedRectangle(cornerRadius: 12).fill(teal))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    private func depRow(_ dep: DependencyManager.Dependency) -> some View {
        HStack(spacing: 12) {
            depStatusIcon(dep.name)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dep.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(lightText)
                Text(dep.description)
                    .font(.system(size: 11))
                    .foregroundColor(subtleText)
            }
            
            Spacer()
            
            depStatusLabel(dep.name)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    @ViewBuilder
    private func depStatusIcon(_ name: String) -> some View {
        switch viewModel.depStatuses[name] ?? .unknown {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 18))
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red.opacity(0.8))
                .font(.system(size: 18))
        case .installing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: teal))
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundColor(.gray)
                .font(.system(size: 18))
        }
    }
    
    @ViewBuilder
    private func depStatusLabel(_ name: String) -> some View {
        switch viewModel.depStatuses[name] ?? .unknown {
        case .installed:
            Text("Ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)
        case .missing:
            Text("Missing")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red.opacity(0.8))
        case .installing:
            Text("Installing…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)
        case .failed:
            Text("Failed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)
        case .unknown:
            Text("Checking…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Step 3: Permissions

struct PermissionsStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let teal: Color
    let lightText: Color
    let subtleText: Color
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundColor(teal)
                
                Text("Permissions")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(lightText)
                
                Text("Two quick permissions and you're good to go")
                    .font(.system(size: 14))
                    .foregroundColor(subtleText)
            }
            .padding(.top, 8)
            
            VStack(spacing: 12) {
                // Microphone
                permissionCard(
                    icon: "mic.fill",
                    iconColor: .red,
                    title: "Microphone Access",
                    subtitle: "To hear your voice and transcribe speech",
                    isGranted: viewModel.hasMicPermission,
                    buttonLabel: "Grant",
                    action: { viewModel.requestMicPermission() }
                )
                
                // Accessibility
                permissionCard(
                    icon: "accessibility",
                    iconColor: .blue,
                    title: "Accessibility Access",
                    subtitle: "To paste text into your apps automatically",
                    isGranted: viewModel.hasAccessibilityPermission,
                    buttonLabel: "Open Settings",
                    action: { viewModel.openAccessibilitySettings() }
                )
            }
            .padding(.horizontal, 24)
            
            if !viewModel.allPermissionsGranted {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: subtleText))
                        .scaleEffect(0.6)
                    Text("Waiting for permissions…")
                        .font(.system(size: 12))
                        .foregroundColor(subtleText)
                }
            }
            
            Spacer()
            
            // Continue button
            Button(action: { viewModel.nextStep() }) {
                HStack(spacing: 8) {
                    Text(viewModel.allPermissionsGranted ? "Continue" : "Skip for Now")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 200, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(viewModel.allPermissionsGranted ? teal : Color.white.opacity(0.15))
                )
                .shadow(color: viewModel.allPermissionsGranted ? teal.opacity(0.4) : .clear, radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }
    
    private func permissionCard(icon: String, iconColor: Color, title: String, subtitle: String, isGranted: Bool, buttonLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(lightText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(subtleText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: action) {
                    Text(buttonLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.7)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isGranted ? Color.green.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isGranted)
    }
}

// MARK: - Step 4: How to Use

struct HowToUseStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let teal: Color
    let lightText: Color
    let subtleText: Color
    
    @State private var animationStep = 0
    @State private var pulseRecording = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 36))
                    .foregroundColor(teal)
                
                Text("How to Use")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(lightText)
            }
            .padding(.top, 8)
            
            // Animated flow
            VStack(spacing: 16) {
                // Step indicators
                HStack(spacing: 32) {
                    flowStep(number: "1", icon: "hand.raised.fill", label: "Hold", desc: "Right Option", highlight: animationStep == 0)
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(subtleText)
                        .font(.system(size: 14))
                    
                    flowStep(number: "2", icon: "waveform", label: "Speak", desc: "Say anything", highlight: animationStep == 1)
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(subtleText)
                        .font(.system(size: 14))
                    
                    flowStep(number: "3", icon: "text.cursor", label: "Release", desc: "Auto-paste", highlight: animationStep == 2)
                }
                .padding(.horizontal, 16)
                
                // Hotkey callout
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 120, height: 36)
                        .overlay(
                            Text("Right Option ⌥")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(lightText)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(teal.opacity(0.5), lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 40)
            
            // Try it now section
            VStack(spacing: 12) {
                Text("Try it now!")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(lightText)
                
                Text("Press and hold the button below, speak, then release")
                    .font(.system(size: 13))
                    .foregroundColor(subtleText)
                    .multilineTextAlignment(.center)
                
                // Recording button
                Button(action: {
                    if viewModel.isTrialRecording {
                        viewModel.stopTrialRecording()
                    } else {
                        viewModel.startTrialRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isTrialRecording ? Color.red : teal)
                            .frame(width: 64, height: 64)
                            .shadow(color: (viewModel.isTrialRecording ? Color.red : teal).opacity(0.5), radius: 12, y: 2)
                        
                        if viewModel.isTrialRecording {
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 3)
                                .frame(width: 80, height: 80)
                                .scaleEffect(pulseRecording ? 1.2 : 1.0)
                                .opacity(pulseRecording ? 0.0 : 0.8)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: pulseRecording)
                        }
                        
                        Image(systemName: viewModel.isTrialRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: viewModel.isTrialRecording) { recording in
                    withAnimation {
                        pulseRecording = recording
                    }
                }
                
                // Transcription result or status
                if viewModel.isTrialTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: teal))
                            .scaleEffect(0.7)
                        Text("Transcribing…")
                            .font(.system(size: 13))
                            .foregroundColor(subtleText)
                    }
                } else if let result = viewModel.trialTranscription {
                    Text("\"\(result)\"")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(teal)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 400)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(teal.opacity(0.1))
                        )
                }
            }
            
            Spacer()
            
            Button(action: { viewModel.nextStep() }) {
                HStack(spacing: 8) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 200, height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(teal))
                .shadow(color: teal.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func flowStep(number: String, icon: String, label: String, desc: String, highlight: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(highlight ? teal.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(highlight ? teal : subtleText)
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(highlight ? lightText : subtleText)
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(subtleText)
        }
        .animation(.easeInOut(duration: 0.5), value: highlight)
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
            withAnimation {
                animationStep = (animationStep + 1) % 3
            }
        }
    }
}

// MARK: - Step 5: Ready

struct ReadyStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let teal: Color
    let lightText: Color
    let subtleText: Color
    var onComplete: () -> Void
    
    @State private var celebrationScale: CGFloat = 0.3
    @State private var celebrationOpacity: Double = 0
    @State private var arrowOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Celebration
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [teal.opacity(0.3), .clear]),
                            center: .center,
                            startRadius: 10,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                Text("🎉")
                    .font(.system(size: 64))
            }
            .scaleEffect(celebrationScale)
            .opacity(celebrationOpacity)
            
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(lightText)
                
                Text("WhisperType lives in your menu bar")
                    .font(.system(size: 15))
                    .foregroundColor(subtleText)
                
                // Arrow pointing up-right to menu bar
                HStack(spacing: 6) {
                    Text("Look for")
                        .font(.system(size: 13))
                        .foregroundColor(subtleText)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13))
                        .foregroundColor(teal)
                    Text("in the menu bar")
                        .font(.system(size: 13))
                        .foregroundColor(subtleText)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(teal)
                        .offset(y: arrowOffset)
                }
                .padding(.top, 8)
            }
            
            Spacer()
            
            // Countdown or Got it button
            VStack(spacing: 12) {
                Button(action: onComplete) {
                    Text("Got it!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 200, height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(teal))
                        .shadow(color: teal.opacity(0.4), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                
                if viewModel.isCountingDown && viewModel.countdownValue > 0 {
                    Text("Auto-closing in \(viewModel.countdownValue)s")
                        .font(.system(size: 12))
                        .foregroundColor(subtleText)
                }
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
                celebrationScale = 1.0
                celebrationOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                arrowOffset = -4
            }
        }
        .onChange(of: viewModel.countdownValue) { value in
            if value <= 0 {
                onComplete()
            }
        }
    }
}
