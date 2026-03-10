# Contributing to WhisperType 🎤

Thanks for your interest in contributing! WhisperType is a small, focused macOS app — contributions of all sizes are welcome, from fixing typos to adding new features.

---

## Getting Started

### 1. Fork & Clone

```bash
git clone https://github.com/YOUR_USERNAME/WhisperType.git
cd WhisperType
```

### 2. Set Up

```bash
# Install Whisper CLI (required for testing)
pipx install openai-whisper

# Build the project
swift build
```

### 3. Create a Branch

Use a descriptive branch name:

```bash
git checkout -b feature/add-language-lock
git checkout -b fix/overlay-flicker-on-m1
git checkout -b docs/update-install-steps
```

---

## What to Work On

### 🐛 Bug Fixes
Check the [Issues](https://github.com/nikhil8182/WhisperType/issues) tab for open bugs. Label `good first issue` is a great starting point.

### ✨ Feature Ideas
- Configurable hotkey (beyond Right Option)
- Multiple language support with UI selector
- Word-level confidence highlighting
- Whisper model auto-download UI
- Menubar icon that reacts to audio level
- Onboarding flow for first-time setup
- Export transcription history

### 📖 Documentation
- Screenshots / GIF demos
- More detailed setup instructions
- Troubleshooting section

---

## Code Style

- **Swift:** Follow Swift API Design Guidelines
- **SwiftUI:** Prefer declarative patterns, avoid UIKit unless necessary
- **Naming:** Clear, descriptive names over abbreviations
- **Comments:** Explain *why*, not *what*
- **Commits:** Use conventional commits format:
  ```
  feat: add configurable hotkey support
  fix: restore clipboard after failed paste
  docs: add troubleshooting section to README
  refactor: extract audio level monitoring
  ```

---

## Submitting a PR

1. Make sure the project **builds** (`swift build`)
2. Test your change manually (record → transcribe → paste)
3. Update the README if you added/changed a feature
4. Open a PR with:
   - A clear title
   - Description of **what** and **why**
   - Steps to test
   - Screenshots/GIF if it's a UI change

---

## Reporting Bugs

Please include:
- macOS version
- Mac model (M1/M2/Intel)
- Whisper model in use
- Steps to reproduce
- What you expected vs what happened

---

## Code of Conduct

Be kind. Be constructive. We're all here to make something useful.

---

## Questions?

Open an issue or reach out to [@nikhil8182](https://github.com/nikhil8182) on GitHub.

Happy hacking! 🚀
