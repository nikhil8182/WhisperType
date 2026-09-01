#!/bin/bash
# Installs the Iniyal WhisperType engine (mlx-whisper + large-v3-turbo) into
#   ~/Library/Application Support/IniyalWhisperType/engine
# Idempotent. Needs python3.11+ (Homebrew python or python.org build).
set -e
ENGINE_DIR="$HOME/Library/Application Support/IniyalWhisperType/engine"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ENGINE_DIR"

pick_python() {
  for p in python3.12 python3.11 python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3 python3; do
    if command -v "$p" >/dev/null 2>&1; then
      v=$("$p" -c 'import sys; print(sys.version_info >= (3,11) and sys.version_info < (3,14))' 2>/dev/null)
      [ "$v" = "True" ] && { echo "$p"; return; }
    fi
  done
  return 1
}

PY=$(pick_python) || { echo "❌ Need Python 3.11-3.13. Install: brew install python@3.12"; exit 1; }
echo "🐍 Using $PY"

if [ ! -x "$ENGINE_DIR/.venv/bin/python" ]; then
  echo "📦 Creating venv..."
  "$PY" -m venv "$ENGINE_DIR/.venv"
fi
"$ENGINE_DIR/.venv/bin/pip" install -q --upgrade pip
"$ENGINE_DIR/.venv/bin/pip" install -q mlx-whisper numpy

cp "$SRC_DIR/whispertype_server.py" "$ENGINE_DIR/whispertype_server.py"

echo "⬇️  Fetching whisper large-v3-turbo (one-time, ~1.6 GB)..."
"$ENGINE_DIR/.venv/bin/python" - <<'EOF'
import numpy as np, mlx_whisper
r = mlx_whisper.transcribe(np.zeros(16000, dtype=np.float32), path_or_hf_repo="mlx-community/whisper-large-v3-turbo", language="en")
print("✅ engine ready")
EOF

if command -v ollama >/dev/null 2>&1; then
  if ! ollama list 2>/dev/null | grep -q "^qwen3.5:9b"; then
    echo "⬇️  Pulling cleanup model qwen3.5:9b (one-time)..."
    ollama pull qwen3.5:9b || echo "⚠️  Ollama pull failed; smart cleanup will pass text through until a model exists"
  fi
else
  echo "⚠️  Ollama not installed (brew install ollama). Smart cleanup stays off until it is."
fi
echo "✅ Engine installed at $ENGINE_DIR"
