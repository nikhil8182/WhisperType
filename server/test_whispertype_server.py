"""Text integrity regressions. Uses a temporary home, no live models or user data."""
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch


class TextIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = tempfile.TemporaryDirectory(prefix="whispertype-test-")
        spec = importlib.util.spec_from_file_location(
            "whispertype_test_engine", Path(__file__).with_name("whispertype_server.py")
        )
        cls.engine = importlib.util.module_from_spec(spec)
        with patch.dict(os.environ, {"HOME": cls.home.name}):
            spec.loader.exec_module(cls.engine)

    @classmethod
    def tearDownClass(cls):
        cls.home.cleanup()

    def polish(self, text, style="neutral"):
        return self.engine.polish(text, "", "", "", style)

    def test_prompt_bypass_preserves_case_sensitive_command(self):
        with patch.object(self.engine, "ollama_alive", side_effect=AssertionError("LLM called")):
            self.assertEqual(self.polish("npm install lodash", "prompt"),
                             ("npm install lodash", "prompt", False))

    def test_short_literal_preserves_identifier_case(self):
        self.assertEqual(self.polish("fooBar", "literal"), ("fooBar", "literal", False))

    def test_replacement_values_are_literal(self):
        replacements = [(re.compile(r"\bpath\b"), r"C:\Users\Nikhil\1")]
        with patch.object(self.engine.CONFIG, "replacements", replacements):
            self.assertEqual(self.engine.apply_replacements("use path"), r"use C:\Users\Nikhil\1")

    def test_standalone_formatting_commands_survive(self):
        for spoken, expected in (("new line", "\n"), ("new paragraph", "\n\n")):
            with self.subTest(spoken=spoken):
                self.assertEqual(self.polish(spoken)[0], expected)

    def test_boundary_formatting_survives_without_llm(self):
        with patch.object(self.engine, "ollama_alive", side_effect=AssertionError("LLM called")):
            self.assertEqual(self.polish("send all files tomorrow new paragraph")[0],
                             "send all files tomorrow\n\n")
            self.assertEqual(self.polish("new line send all files tomorrow")[0],
                             "\nsend all files tomorrow")

    def test_internal_formatting_and_scratch_still_work(self):
        self.assertEqual(self.engine.voice_commands("first new paragraph second"), "first\n\nsecond")
        self.assertEqual(self.engine.voice_commands("wrong scratch that right"), "right")

    def test_rejects_silently_shortened_output(self):
        raw = "Please deliver all thirty gate motors to the Chennai office tomorrow and call Kavin before leaving."
        with patch.object(self.engine, "ollama_alive", return_value=True), \
                patch.object(self.engine, "ollama_chat", return_value="Please deliver all thirty gate motors."):
            self.assertEqual(self.polish(raw), (raw, "neutral", False))

    def test_rejects_changed_or_dropped_numbers(self):
        for out in ("Invoice Kavin for 1200 rupees.", "Invoice Kavin for rupees."):
            with self.subTest(out=out):
                self.assertFalse(self.engine.sanity("Invoice Kavin for 12000 rupees.", out))

    def test_accepts_normal_cleanup_preserving_numbers(self):
        self.assertTrue(self.engine.sanity("um please send 12 files tomorrow",
                                           "Please send 12 files tomorrow."))

    def test_output_limit_falls_back_even_when_length_looks_plausible(self):
        raw = "Please send the files tomorrow morning."
        response = io.BytesIO(json.dumps({
            "message": {"content": "Please send the files tomorrow"},
            "done_reason": "length",
        }).encode())
        with patch.object(self.engine, "ollama_alive", return_value=True), \
                patch.object(self.engine.urllib.request, "urlopen", return_value=response):
            self.assertEqual(self.polish(raw), (raw, "neutral", False))

    def test_ollama_failure_keeps_text(self):
        raw = "Please send all files tomorrow."
        with patch.object(self.engine, "ollama_alive", return_value=True), \
                patch.object(self.engine, "ollama_chat", side_effect=TimeoutError("test timeout")):
            self.assertEqual(self.polish(raw), (raw, "neutral", False))


if __name__ == "__main__":
    unittest.main()
