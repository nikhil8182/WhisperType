# Iniyal WhisperType

[![GitHub release](https://img.shields.io/github/v/release/nikhil8182/WhisperType?label=Download&color=blue)](https://github.com/nikhil8182/WhisperType/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Iniyal, the Onwords AI, types what you say. Hold a key, talk, release.**

Iniyal WhisperType is a lightweight menu bar app that transcribes your voice and pastes the text into any active application. Hold the Right Option key to record, release to transcribe and paste. Powered by OpenAI's Whisper, running entirely on your Mac — no cloud, no API keys, no subscriptions.

<!-- ![WhisperType Screenshot](screenshot.png) -->

## 1.3.0 interface refresh

A compact glass recording panel shows live microphone activity, readable transcription, and clear finishing feedback without taking keyboard focus. Preview its stages from Settings without using the microphone. The panel respects Reduce Motion and follows the active display.

Settings now groups everyday controls, speech preferences, and searchable history. History supports full-text selection and copy feedback. The menu keeps the most useful actions close, with advanced controls tucked away. Settings follows the Mac's light or dark appearance.

## 1.2.1 reliability fixes

- Failed engine requests retain the WAV for CLI fallback. Auto language detection works in the fallback too.
- Cleanup preserves empty scratch commands, explicit line breaks, literal vocabulary values, and command casing. Truncated responses or changed numbers fall back to the original text.
- Clipboard restoration preserves all formats and skips restoration after a new copy. Switching apps during processing leaves the text available for manual paste and in History.
- Right Option release works while Left Option remains held. Preview responses from an earlier recording are ignored. Microphone start failures return to idle with an error.
- Installing an update restarts the local engine, including an orphan left by a previous force-quit.

Regression checks: `swift test` and the engine venv's `python -B -m unittest discover -s server -p 'test_*.py'`. Python tests use a temporary home and mocked models; Swift clipboard tests use isolated pasteboards.

## What's new in 1.2 (local engine)

- ⚡ **MLX engine** — whisper large-v3-turbo on Apple Silicon, warm in memory. 11 s of speech transcribes in ~0.6 s.
- 👀 **Live preview** — text appears in the overlay while you are still talking.
- 🧠 **Smart cleanup** — a local Ollama model (qwen3.5:9b) removes fillers, fixes grammar, keeps your meaning. Nothing leaves the Mac.
- 🎯 **App-aware tone** — WhatsApp gets a chat message, Mail/Gmail gets formal prose, Terminal/Cursor/Claude gets a clean AI prompt, Xcode gets literal text. Edit `apps.json`.
- 📚 **Custom vocabulary** — names, products and jargon Whisper normally mangles. Edit `vocabulary.json` (terms + replacements), reloads live.
- 🙌 **Hands-free** — double-tap Right Option to record without holding, tap once to stop.
- 🗣 **Voice commands** — "new line", "new paragraph", "scratch that".
- 🔁 **CLI fallback** — if the engine is not installed, the old `openai-whisper` CLI path still works.

## Features

- 🎙 **Push-to-talk** — Hold Right Option key to record, release to transcribe
- ⚡ **Instant paste** — Transcribed text is automatically pasted into the active app
- 🔒 **100% local** — Audio never leaves your Mac
- 🌍 **Multi-language** — English, Tamil, Hindi and more, or auto-detect
- 📋 **History** — Browse and copy recent transcriptions
- 🚀 **Launch at login**

## Requirements

- **macOS 13+**, Apple Silicon recommended (the MLX engine needs it; Intel falls back to the CLI)
- **Python 3.11-3.13** (`brew install python@3.12`) for the engine
- **Ollama** (`brew install ollama`) for smart cleanup, optional

## Installation

### Pre-built App (Recommended)

**[⬇️ Download WhisperType-1.1.0.dmg](https://github.com/nikhil8182/WhisperType/releases/latest)**

1. Download the DMG from the link above
2. Open the DMG — drag **Iniyal WhisperType** to the **Applications** folder
3. Launch Iniyal WhisperType — grant Microphone and Accessibility permissions when prompted
4. Install the engine once: `bash "/Applications/Iniyal WhisperType.app/Contents/Resources/install_engine.sh"` (downloads ~1.6 GB model + pulls the Ollama cleanup model). `./build-app.sh --install` does this for you when building from source.

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

1. **Launch** Iniyal WhisperType — it appears as a microphone icon in your menu bar
2. **Hold Right Option (⌥)** to record, watch the live preview, **release** to paste. Or **double-tap** for hands-free and tap once to stop.
3. Say "new line", "new paragraph" or "scratch that" while dictating.
4. Config lives in `~/Library/Application Support/IniyalWhisperType/`: `vocabulary.json`, `apps.json`, `config.json` (engine + LLM model). Logs: `~/Library/Logs/IniyalWhisperType/`.

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
- Check `~/Library/Logs/IniyalWhisperType/whispertype.log` for errors

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
