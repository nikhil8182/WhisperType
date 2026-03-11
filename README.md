# WhisperType

[![GitHub release](https://img.shields.io/github/v/release/nikhil8182/WhisperType?label=Download&color=blue)](https://github.com/nikhil8182/WhisperType/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Voice-to-text for macOS — just hold a key and speak.**

WhisperType is a lightweight menu bar app that transcribes your voice and pastes the text into any active application. Hold the Right Option key to record, release to transcribe and paste. Powered by OpenAI's Whisper, running entirely on your Mac — no cloud, no API keys, no subscriptions.

<!-- ![WhisperType Screenshot](screenshot.png) -->

## Features

- 🎙 **Push-to-talk** — Hold Right Option key to record, release to transcribe
- ⚡ **Instant paste** — Transcribed text is automatically pasted into the active app
- 🔒 **100% local** — Audio never leaves your Mac. Whisper runs on-device
- 🎯 **Multiple models** — Choose from tiny, base, small, medium, or turbo
- 🌍 **Multi-language** — Supports English, Tamil, Hindi, Spanish, French, German, Japanese, Chinese, and auto-detect
- 📋 **History** — Browse and copy recent transcriptions
- 🔊 **Sound effects** — Audio feedback for start/stop recording
- 💬 **Floating overlay** — Visual indicator while recording/transcribing
- 🚀 **Launch at login** — Optional auto-start via macOS Login Items
- ⚙️ **Preferences** — Full settings panel with model, language, and history management

## Requirements

- **macOS 13.0** (Ventura) or later
- **Apple Silicon** (M1/M2/M3) or Intel Mac
- **OpenAI Whisper CLI** — local transcription engine
- **ffmpeg** — audio processing

## Installation

### Pre-built App (Recommended)

**[⬇️ Download WhisperType-1.1.0.dmg](https://github.com/nikhil8182/WhisperType/releases/latest)**

1. Download the DMG from the link above
2. Open the DMG — drag **WhisperType** to the **Applications** folder
3. Launch WhisperType — grant Microphone and Accessibility permissions when prompted
4. **Dependencies are installed automatically on first launch** — a setup window will guide you through it

> All releases: [github.com/nikhil8182/WhisperType/releases](https://github.com/nikhil8182/WhisperType/releases)

### What Gets Installed

On first launch, WhisperType will check for and offer to install:
- **Homebrew** — macOS package manager (opens Terminal for interactive install)
- **Python 3** — runtime for Whisper
- **ffmpeg** — audio processing
- **pipx** — isolated Python app installer
- **openai-whisper** — the speech recognition engine

You can also trigger this anytime from the menu bar: **Check Dependencies…**

> **Note:** The first transcription after install will download the Whisper model (~150MB for 'base'). This is a one-time download.

### Build from Source

```bash
# Clone the repo
git clone https://github.com/nikhil8182/WhisperType.git
cd WhisperType

# Build and install
./build-app.sh --install
```

> When building from source, dependencies are still installed at runtime on first launch — no manual setup needed.

## Usage

1. **Launch** WhisperType — it appears as a microphone icon in your menu bar
2. **Hold Right Option (⌥)** key to start recording
3. **Speak** clearly
4. **Release** the key — your speech is transcribed and pasted into the active text field

### Menu Bar

Click the menu bar icon to:
- See recording status and permission state
- View and copy recent transcriptions
- Switch Whisper models
- Toggle overlay and sound effects
- Access Settings and About

### Settings

Open Settings (`⌘,` or via menu) to configure:
- **General** — Hotkey, overlay, sounds, launch at login
- **Transcription** — Whisper model and language
- **History** — Max items, clear history, browse past transcriptions

## Whisper Models

| Model | RAM | Speed | Accuracy |
|-------|-----|-------|----------|
| tiny | ~1 GB | Fastest | Basic |
| base | ~1 GB | Fast | Good (recommended) |
| small | ~2 GB | Moderate | Better |
| medium | ~5 GB | Slow | High |
| turbo | ~6 GB | Fast | Best trade-off |

## Permissions

WhisperType requires two macOS permissions:

1. **Microphone** — To record audio (prompted automatically)
2. **Accessibility** — To paste text via keyboard simulation (must be enabled manually in System Settings → Privacy & Security → Accessibility)

The app will guide you through setup on first launch.

## Troubleshooting

**"Whisper CLI not found"**
Click the menu bar icon → **Check Dependencies…** to auto-install, or manually:
```bash
pipx install openai-whisper
```

**"Accessibility not granted"**
1. Open System Settings → Privacy & Security → Accessibility
2. Click the lock to make changes
3. Add WhisperType.app and enable it
4. Restart WhisperType

**No transcription output**
- Make sure your microphone is working (test in Voice Memos)
- Try a longer recording (> 0.5 seconds)
- Check `~/Library/Logs/WhisperType/whispertype.log` for errors

## Project Structure

```
WhisperType/
├── Package.swift              # Swift Package Manager config
├── build-app.sh               # Build & install script
├── scripts/
│   ├── generate_icon.py       # App icon generator
│   └── generate_menubar_icon.py
└── WhisperType/
    ├── Info.plist
    ├── WhisperType.entitlements
    ├── Resources/
    │   ├── MenuBarIcon.png
    │   └── MenuBarIcon@2x.png
    └── Sources/
        ├── WhisperTypeApp.swift       # App entry point & delegate
        ├── AppState.swift             # Shared state & settings
        ├── DependencyManager.swift    # Auto dependency checking & installation
        ├── SetupWindowController.swift # First-run setup window UI
        ├── StatusBarController.swift  # Menu bar UI
        ├── HotkeyManager.swift        # Right Option key handling
        ├── AudioRecorder.swift        # AVAudioEngine recording
        ├── WhisperManager.swift       # Whisper CLI integration
        ├── TextPaster.swift           # Cmd+V paste via CGEvent
        ├── OverlayWindowController.swift # Floating status overlay
        ├── SettingsView.swift         # SwiftUI preferences
        ├── SoundManager.swift         # System sound effects
        └── Logger.swift               # File-based logging
```

## License

MIT License — see [LICENSE](LICENSE) for details.

## Credits

Built by **[Nikhil](https://github.com/nikhil8182)** · [Onwords Smart Solutions](https://onwords.in) 🇮🇳

Powered by [OpenAI Whisper](https://github.com/openai/whisper).

---

[⭐ Star on GitHub](https://github.com/nikhil8182/WhisperType) · [🐛 Report a Bug](https://github.com/nikhil8182/WhisperType/issues) · [⬇️ Download Latest](https://github.com/nikhil8182/WhisperType/releases/latest)
