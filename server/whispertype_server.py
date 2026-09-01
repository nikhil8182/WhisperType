#!/usr/bin/env python3
"""Iniyal WhisperType local engine.

One warm process on 127.0.0.1:4877 that the menu-bar app talks to:
  GET  /health                     -> {"ok":true, "model":..., "llm":bool}
  POST /transcribe  (raw f32 PCM)  -> {"text":..., "raw":..., "ms":...}
        headers: X-Language (en|ta|...|auto), X-Partial (1 = live preview)
  POST /polish      (JSON)         -> {"text":..., "style":..., "ms":..., "llm":bool}
        body: {"text":..., "app_bundle":..., "app_name":..., "window_title":..., "style":"auto|casual|formal|prompt|literal|neutral"}

Speech: mlx-whisper large-v3-turbo on Apple Silicon (model loaded once).
Cleanup: local Ollama model (never leaves the Mac). Falls back to raw text if Ollama is down.
Config lives in ~/Library/Application Support/IniyalWhisperType/{vocabulary,apps,config}.json
"""
import json
import os
import re
import sys
import time
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

HOST, PORT = "127.0.0.1", 4877
HOME = os.path.expanduser("~")
APP_SUPPORT = os.path.join(HOME, "Library/Application Support/IniyalWhisperType")
LOG_DIR = os.path.join(HOME, "Library/Logs/IniyalWhisperType")
os.makedirs(APP_SUPPORT, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOG_DIR, "server.log")
START = time.time()

DEFAULT_CONFIG = {
    "whisper_model": "mlx-community/whisper-large-v3-turbo",
    "ollama_url": "http://127.0.0.1:11434",
    "llm_model": "qwen3.5:9b",
    "llm_timeout_s": 12,
    "llm_keep_alive": "60m",
    "min_words_for_llm": 3,
}

DEFAULT_VOCAB = {
    "_help": "terms: words Whisper should recognise (proper nouns, jargon). replacements: wrong -> right, matched case-insensitively on word boundaries.",
    "terms": [
        "Onwords", "Iniyal", "Nikhil", "Kavin", "Tamil Selvan", "Karun", "Prem", "Shankar",
        "Sajitha", "Srijith", "Roddy", "LHOS", "Living Home", "Living AI", "WTA", "Crestron",
        "KNX", "Coimbatore", "Chennai", "Bangalore", "Hyderabad", "SwastriCare", "Salary Savvy",
        "Master CRM", "Home Assistant", "ESPHome", "Zigbee", "Supabase", "openclaw", "Meta ads",
        "gate automation", "smart home", "proforma", "lakh", "crore",
    ],
    "replacements": {
        "on words": "Onwords", "on word": "Onwords", "onward's": "Onwords", "onwards": "Onwords",
        "in a yell": "Iniyal", "inial": "Iniyal", "inayel": "Iniyal", "inayal": "Iniyal", "iniyel": "Iniyal", "enial": "Iniyal",
        "l h o s": "LHOS", "w t a": "WTA", "k n x": "KNX", "c r m": "CRM",
        "swastri care": "SwastriCare", "swasthi care": "SwastriCare",
        "cavin": "Kavin", "calvin": "Kavin", "kevin": "Kavin", "tamil selvam": "Tamil Selvan",
    },
}

DEFAULT_APPS = {
    "_help": "Map the front app to a cleanup style. Keys are bundle ids (or a lowercase substring of the window title under 'titles'). Styles: casual, formal, prompt, literal, neutral.",
    "bundles": {
        "net.whatsapp.WhatsApp": "casual",
        "com.apple.MobileSMS": "casual",
        "ru.keepcoder.Telegram": "casual",
        "com.tinyspeck.slackmacgap": "casual",
        "com.hnc.Discord": "casual",
        "com.apple.mail": "formal",
        "com.microsoft.Outlook": "formal",
        "com.apple.Notes": "neutral",
        "com.apple.Terminal": "prompt",
        "com.googlecode.iterm2": "prompt",
        "com.mitchellh.ghostty": "prompt",
        "dev.warp.Warp-Stable": "prompt",
        "com.todesktop.230313mzl4w4u92": "prompt",
        "com.microsoft.VSCode": "prompt",
        "com.anthropic.claudefordesktop": "prompt",
        "com.openai.chat": "prompt",
        "com.apple.dt.Xcode": "literal",
        "com.apple.TextEdit": "literal",
    },
    "titles": {
        "whatsapp": "casual",
        "gmail": "formal",
        "mail -": "formal",
        "claude": "prompt",
        "chatgpt": "prompt",
        "grok": "prompt",
        "linkedin": "formal",
    },
    "default": "neutral",
}

STYLE_PROMPTS = {
    "neutral": "Clean up this dictated text. Remove fillers (um, uh, like, you know), false starts and repeated words. Fix grammar, capitalisation and punctuation. Keep the speaker's meaning, wording and language. Do not add, summarise or answer anything.",
    "casual": "Turn this dictated text into a natural chat message, like a person typing on WhatsApp. Short lines, relaxed tone, keep the speaker's own words and warmth. Remove fillers and stumbles. No greetings or sign-offs unless the speaker said them.",
    "formal": "Turn this dictated text into clean professional business writing, suitable for an email. Full sentences, correct punctuation, courteous but direct. Keep every fact and the speaker's intent. Do not invent greetings, sign-offs or facts.",
    "prompt": "This dictated text is an instruction to an AI coding assistant. Rewrite it as a clear, precise instruction. Remove fillers and chit-chat. Keep technical terms, file names, commands, numbers and quoted strings exactly as spoken. Do not carry out the instruction, only restate it.",
    "literal": "Only fix punctuation, capitalisation and obvious speech-recognition errors in this dictated text. Do not rephrase or reorder anything.",
}
COMMON_RULES = " Output ONLY the resulting text: no quotes, no preamble, no explanation, no markdown. Keep the same language as the input. Preserve any line breaks already present. If the input is already clean, return it unchanged."


def log(msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n"
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line)
    except Exception:
        pass
    sys.stderr.write(line)


def load_json(name, default):
    path = os.path.join(APP_SUPPORT, name)
    if not os.path.exists(path):
        with open(path, "w") as f:
            json.dump(default, f, indent=2, ensure_ascii=False)
        return dict(default)
    try:
        with open(path) as f:
            data = json.load(f)
        merged = dict(default)
        merged.update(data)
        return merged
    except Exception as e:
        log(f"config {name} unreadable ({e}), using defaults")
        return dict(default)


class Config:
    def __init__(self):
        self._mtimes = {}
        self.reload()

    def reload(self):
        self.cfg = load_json("config.json", DEFAULT_CONFIG)
        self.vocab = load_json("vocabulary.json", DEFAULT_VOCAB)
        self.apps = load_json("apps.json", DEFAULT_APPS)
        self._mtimes = {n: self._mtime(n) for n in ("config.json", "vocabulary.json", "apps.json")}
        self.prompt_bias = ", ".join(t for t in self.vocab.get("terms", []) if t)[:600]
        reps = self.vocab.get("replacements", {}) or {}
        self.replacements = [
            (re.compile(r"\b" + re.escape(k) + r"\b", re.IGNORECASE), v) for k, v in reps.items() if k
        ]

    def _mtime(self, name):
        try:
            return os.path.getmtime(os.path.join(APP_SUPPORT, name))
        except OSError:
            return 0

    def refresh_if_changed(self):
        for n, m in self._mtimes.items():
            if self._mtime(n) != m:
                log("config changed on disk, reloading")
                self.reload()
                return


CONFIG = Config()


# ---------------- speech ----------------
class Speech:
    def __init__(self, model):
        import mlx_whisper  # noqa
        self.mlx = mlx_whisper
        self.model = model
        self.lock = threading.Lock()
        t = time.time()
        self.mlx.transcribe(np.zeros(16000, dtype=np.float32), path_or_hf_repo=model, language="en", fp16=True)
        log(f"whisper warm: {model} in {time.time()-t:.1f}s")

    def transcribe(self, pcm: np.ndarray, language: str, partial: bool):
        kwargs = dict(
            path_or_hf_repo=self.model,
            fp16=True,
            condition_on_previous_text=False,
            no_speech_threshold=0.6,
            initial_prompt=CONFIG.prompt_bias or None,
        )
        if language and language != "auto":
            kwargs["language"] = language
        if partial:
            kwargs["temperature"] = 0.0
            kwargs["compression_ratio_threshold"] = None
        with self.lock:
            r = self.mlx.transcribe(pcm, **kwargs)
        # Drop hallucinated segments (silence / noise): whisper tags them with high no_speech_prob
        segs = r.get("segments") or []
        if segs:
            kept = [s for s in segs if not (s.get("no_speech_prob", 0) > 0.6 and s.get("avg_logprob", 0) < -0.8)]
            text = " ".join((s.get("text") or "").strip() for s in kept).strip()
        else:
            text = (r.get("text") or "").strip()
        return text, r.get("language")


def apply_replacements(text):
    for rx, v in CONFIG.replacements:
        text = rx.sub(v, text)
    return text


# ---------------- cleanup ----------------
VOICE_CMDS = [
    (re.compile(r"[,.]?\s*\bnew paragraph\b[,.]?\s*", re.I), "\n\n"),
    (re.compile(r"[,.]?\s*\bnew line\b[,.]?\s*", re.I), "\n"),
]


def voice_commands(text):
    if re.search(r"\bscratch that\b", text, re.I):
        text = re.split(r"\bscratch that\b[,.]?\s*", text, flags=re.I)[-1]
    for rx, rep in VOICE_CMDS:
        text = rx.sub(rep, text)
    return text.strip()


def pick_style(app_bundle, app_name, window_title, override):
    if override and override != "auto":
        return override
    apps = CONFIG.apps
    title = (window_title or "").lower()
    for key, style in (apps.get("titles") or {}).items():
        if key and key.lower() in title:
            return style
    if app_bundle and app_bundle in (apps.get("bundles") or {}):
        return apps["bundles"][app_bundle]
    name = (app_name or "").lower()
    for bundle, style in (apps.get("bundles") or {}).items():
        if name and name in bundle.lower():
            return style
    return apps.get("default", "neutral")


def ollama_alive():
    try:
        with urllib.request.urlopen(CONFIG.cfg["ollama_url"] + "/api/tags", timeout=1.5) as r:
            names = [m["name"] for m in json.load(r).get("models", [])]
        return CONFIG.cfg["llm_model"] in names or any(n.startswith(CONFIG.cfg["llm_model"]) for n in names)
    except Exception:
        return False


def ollama_chat(system, user, timeout):
    body = json.dumps({
        "model": CONFIG.cfg["llm_model"],
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "stream": False,
        "think": False,
        "keep_alive": CONFIG.cfg["llm_keep_alive"],
        "options": {"temperature": 0.15, "num_predict": 600},
    }).encode()
    req = urllib.request.Request(CONFIG.cfg["ollama_url"] + "/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.load(r)["message"]["content"]
    out = re.sub(r"<think>.*?</think>", "", out, flags=re.S).strip()
    return out


def sanity(raw, out):
    """Reject LLM output that clearly went off the rails."""
    if not out:
        return False
    rw, ow = len(raw.split()), len(out.split())
    if ow > rw * 2.5 + 8:
        return False
    low = out.lower()
    if low.startswith(("sure", "here is", "here's", "certainly")):
        return False
    return True


def warm_llm():
    if not ollama_alive():
        log("ollama not reachable, cleanup will pass raw text through")
        return
    try:
        t = time.time()
        ollama_chat("Reply with OK.", "OK", CONFIG.cfg["llm_timeout_s"] + 20)
        log(f"llm warm: {CONFIG.cfg['llm_model']} in {time.time()-t:.1f}s")
    except Exception as e:
        log(f"llm warm failed: {e}")


def polish(text, app_bundle, app_name, window_title, override):
    raw = text
    text = voice_commands(apply_replacements(text))
    style = pick_style(app_bundle, app_name, window_title, override)
    words = len(text.split())
    if words < CONFIG.cfg["min_words_for_llm"]:
        t = text.strip()
        return (t[:1].upper() + t[1:]) if t else t, style, False
    if not ollama_alive():
        return text, style, False
    system = STYLE_PROMPTS.get(style, STYLE_PROMPTS["neutral"]) + COMMON_RULES
    try:
        out = ollama_chat(system, text, CONFIG.cfg["llm_timeout_s"])
        out = out.strip().strip('"').strip()
        if sanity(text, out):
            return out, style, True
        log(f"llm output rejected by sanity check: {out[:80]!r}")
        return text, style, False
    except Exception as e:
        log(f"llm failed ({e}); returning raw")
        return text, style, False


# ---------------- http ----------------
SPEECH = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):  # quiet
        pass

    def _json(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/health"):
            CONFIG.refresh_if_changed()
            return self._json(200, {
                "ok": SPEECH is not None,
                "model": CONFIG.cfg["whisper_model"],
                "llm": ollama_alive(),
                "llm_model": CONFIG.cfg["llm_model"],
                "uptime_s": int(time.time() - START),
                "config_dir": APP_SUPPORT,
            })
        self._json(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n) if n else b""
        CONFIG.refresh_if_changed()
        try:
            if self.path.startswith("/transcribe"):
                return self._transcribe(body)
            if self.path.startswith("/polish"):
                return self._polish(body)
            if self.path.startswith("/reload"):
                CONFIG.reload()
                return self._json(200, {"ok": True})
        except Exception as e:
            log(f"error {self.path}: {e}")
            return self._json(500, {"error": str(e)})
        self._json(404, {"error": "not found"})

    def _transcribe(self, body):
        if SPEECH is None:
            return self._json(503, {"error": "model loading"})
        partial = self.headers.get("X-Partial", "0") == "1"
        language = (self.headers.get("X-Language") or "en").strip() or "auto"
        pcm = np.frombuffer(body, dtype=np.float32)
        if pcm.size < 1600:
            return self._json(200, {"text": "", "raw": "", "ms": 0})
        t = time.time()
        raw, lang = SPEECH.transcribe(pcm, language, partial)
        text = apply_replacements(raw)
        ms = int((time.time() - t) * 1000)
        if not partial:
            log(f"transcribe {pcm.size/16000:.1f}s audio -> {ms}ms: {text[:80]!r}")
        self._json(200, {"text": text, "raw": raw, "ms": ms, "language": lang})

    def _polish(self, body):
        req = json.loads(body or b"{}")
        text = (req.get("text") or "").strip()
        if not text:
            return self._json(200, {"text": "", "style": "none", "ms": 0, "llm": False})
        t = time.time()
        out, style, used = polish(text, req.get("app_bundle"), req.get("app_name"),
                                  req.get("window_title"), req.get("style"))
        ms = int((time.time() - t) * 1000)
        log(f"polish[{style}{'/llm' if used else ''}] {ms}ms: {text[:50]!r} -> {out[:50]!r}")
        self._json(200, {"text": out, "style": style, "ms": ms, "llm": used})


def main():
    global SPEECH
    log(f"starting on {HOST}:{PORT} pid {os.getpid()}")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Thread(target=warm_llm, daemon=True).start()
    SPEECH = Speech(CONFIG.cfg["whisper_model"])
    log("ready")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
