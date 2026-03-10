<div align="center">

# 🎤 WhisperType

**Native macOS voice-to-text input — hold a key, speak, release.**  
Whisper transcribes locally and pastes anywhere. No cloud. No API keys. No subscriptions.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Binary Size](https://img.shields.io/badge/binary-%3C%20500KB-brightgreen)](https://github.com/nikhil8182/WhisperType/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

<br/>

<!-- Replace with actual GIF once recorded -->
> 🎬 **Demo GIF coming soon** — Hold Right Option → speak → release → text appears!

</div>

---

## ✨ What is WhisperType?

WhisperType is a tiny but powerful macOS menu bar app that turns your voice into typed text — **instantly and privately**. It uses [OpenAI's Whisper](https://github.com/openai/whisper) running entirely on your Mac. Your audio never leaves your machine.

### How it works

```
Hold Right Option  →  🔴 Recording starts
       Speak       →  🟡 Whisper transcribes (locally)
  Release key      →  ✅ Text auto-pastes at your cursor
```

Works in **any app** — Terminal, VS Code, Safari, Notes, Slack, Xcode, you name it.

---

## 🚀 Features

| Feature | Details |
|---|---|
| 🎤 **Hold-to-record** | Right Option key (configurable) — hold to record, release to transcribe |
| 🎯 **Works everywhere** | Any focusable app — Terminal, VS Code, Safari, Slack, Notes |
| 🔒 **100% local** | Whisper runs on your Mac — zero data leaves your machine |
| 📊 **Menu bar status** | Live state: Idle → Recording → Transcribing → Done |
| 🔴 **Floating overlay** | Always-visible status indicator while recording |
| 📋 **Transcription history** | Local log of all your dictations |
| 🔊 **Audio feedback** | System sounds on record start/stop |
| ⚙️ **Model selection** | Choose accuracy vs speed: `tiny` / `base` / `small` / `medium` |
| 🧹 **Auto-cleanup** | Temp WAV files deleted after transcription |
| 📋 **Clipboard-safe** | Your clipboard is preserved and restored after paste |
| 🚀 **Start at login** | Optional launch-at-login support |
| 🪶 **Lightweight** | Under 500KB binary |

---

## 📦 Requirements

- **macOS 13 Ventura** or later (Apple Silicon or Intel)
- **Whisper CLI** installed via pipx:
  ```bash
  pipx install openai-whisper
  ```
- **Microphone permission** — granted once on first launch
- **Accessibility permission** — for global hotkey + paste injection

> 💡 First-time Whisper run will download the model (~74MB for `tiny`, ~1.5GB for `medium`). After that, it's fully offline.

---

## 🛠 Installation

### Option 1 — Build from source (recommended)

```bash
# Clone the repo
git clone https://github.com/nikhil8182/WhisperType.git
cd WhisperType

# Build release binary
swift build -c release

# (Optional) Move to Applications
cp -r .build/release/WhisperType.app /Applications/
```

### Option 2 — Download release binary

> 📦 Pre-built `.app` releases coming soon — check the [Releases](https://github.com/nikhil8182/WhisperType/releases) page.

---

## 📸 Screenshots

<!-- Add screenshots here once available -->

> 🖼️ **Screenshots coming soon**
>
> _Menu bar icon · Status overlay · Settings panel · Transcription history_

---

## 🏗 Architecture

WhisperType is clean, modular, and ~10 Swift source files:

```
WhisperType/Sources/
├── WhisperTypeApp.swift          # Entry point, permission requests
├── AppState.swift                # Shared state, settings, history
├── HotkeyManager.swift           # Global hotkey monitoring (CGEvent)
├── AudioRecorder.swift           # AVFoundation — 16kHz mono WAV
├── WhisperManager.swift          # Whisper CLI subprocess manager
├── TextPaster.swift              # CGEvent paste + clipboard restore
├── StatusBarController.swift     # Menu bar UI
├── OverlayWindowController.swift # Floating status overlay
├── SoundManager.swift            # System audio feedback
└── SettingsView.swift            # SwiftUI settings panel
```

**Tech stack:** Swift + SwiftUI · AVFoundation · CGEvent · Whisper CLI (subprocess)

---

## ⚙️ Configuration

All settings are accessible from the menu bar icon → **Settings**:

- **Hotkey** — Default: Right Option. Remappable.
- **Whisper model** — `tiny` (fast) → `medium` (accurate)
- **Language** — Auto-detect or lock to a language
- **Start at login** — Toggle launch-at-login
- **History** — View / clear transcription history

---

## 🔐 Privacy

WhisperType is built privacy-first:

- ✅ No network calls — ever
- ✅ No telemetry, no analytics
- ✅ Whisper runs as a local subprocess
- ✅ Audio files are deleted immediately after transcription
- ✅ Clipboard restored to original content after paste
- ✅ Open source — audit it yourself

---

## 🤝 Contributing

Contributions are welcome! Whether it's bug fixes, new features, documentation, or translations.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Fork → Clone → Branch → Code → PR
git checkout -b feature/my-cool-feature
```

---

## 📜 License

MIT — see [LICENSE](LICENSE) for details.

---

## 👨‍💻 Author

Built by **Nikhil** ([@nikhil8182](https://github.com/nikhil8182)) with AI assistance.

> _"I built this because I type too slow and talk too fast."_

---

<div align="center">

**If WhisperType saves you time, give it a ⭐ — it means a lot!**

[⭐ Star on GitHub](https://github.com/nikhil8182/WhisperType) · [🐛 Report a Bug](https://github.com/nikhil8182/WhisperType/issues) · [💡 Request a Feature](https://github.com/nikhil8182/WhisperType/issues)

</div>
