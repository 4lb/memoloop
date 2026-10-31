import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = SourceFileLoader("intervald", str(ROOT / "intervald"))
SPEC = importlib.util.spec_from_loader("intervald", LOADER)
intervald = importlib.util.module_from_spec(SPEC)
sys.modules["intervald"] = intervald
LOADER.exec_module(intervald)


class DurationTest(unittest.TestCase):
    def test_valid(self):
        errors = []
        self.assertEqual(intervald.parse_duration("90s", "x", errors), 90)
        self.assertEqual(intervald.parse_duration("45m", "x", errors), 2700)
        self.assertEqual(intervald.parse_duration("2h", "x", errors), 7200)
        self.assertEqual(errors, [])

    def test_bare_number(self):
        errors = []
        self.assertIsNone(intervald.parse_duration(30, "x", errors))
        self.assertIn("add one", errors[0])

    def test_rejected(self):
        for value in ("0s", "1h30m", "1.5h", "30", "1d", "-5m", 1.5):
            errors = []
            self.assertIsNone(intervald.parse_duration(value, "x", errors))
            self.assertTrue(errors, value)


class ConfigTest(unittest.TestCase):
    def load(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text(text)
            return intervald.load_config(path)

    def test_valid(self):
        config, errors, warnings = self.load(
            "settings:\n"
            "  terminal: foot -e\n"
            "jobs:\n"
            "  test:\n"
            "    command: echo hi\n"
            "    terminal: true\n"
            "    schedule:\n"
            "      - every: 45m\n"
            "      - random: [15m, 30m]\n"
        )
        self.assertEqual(errors, [])
        self.assertIsNotNone(config)
        self.assertEqual(len(config.jobs["test"].rules), 2)

    def test_empty_jobs_valid(self):
        config, errors, warnings = self.load(
            "settings:\n  terminal: foot -e\njobs: {}\n"
        )
        self.assertEqual(errors, [])
        self.assertIsNotNone(config)
        self.assertEqual(config.jobs, {})

    def test_duplicate_key(self):
        config, errors, warnings = self.load(
            "jobs:\n"
            "  test:\n"
            "    command: echo hi\n"
            "    command: echo bye\n"
            "    schedule:\n"
            "      - every: 1m\n"
        )
        self.assertIsNone(config)
        self.assertTrue(any("duplicate key" in error for error in errors))

    def test_bad_fields(self):
        config, errors, warnings = self.load(
            "jobs:\n"
            "  test:\n"
            "    command: echo hi\n"
            "    terminal: 'true'\n"
            "    extra: 1\n"
            "    schedule:\n"
            "      - every: 30\n"
            "      - every: 1m\n"
            "        random: [1m, 2m]\n"
            "      - random: [2h, 1h]\n"
        )
        self.assertIsNone(config)
        joined = "\n".join(errors)
        self.assertIn("quoted string", joined)
        self.assertIn("unknown key", joined)
        self.assertIn("add one", joined)
        self.assertIn("exactly one", joined)
        self.assertIn("greater than max", joined)

    def test_terminal_requires_setting(self):
        config, errors, warnings = self.load(
            "jobs:\n"
            "  test:\n"
            "    command: echo hi\n"
            "    terminal: true\n"
            "    schedule:\n"
            "      - every: 1m\n"
        )
        self.assertIsNone(config)
        self.assertTrue(any("settings.terminal" in error for error in errors))

    def test_reports_all_errors(self):
        config, errors, warnings = self.load(
            "jobs:\n"
            '  "a b":\n'
            "    command: x\n"
            "    terminal: 'true'\n"
            "    extra: 1\n"
            "    schedule:\n"
            "      - every: 30\n"
            "      - every: 1m\n"
            "        random: [1m, 2m]\n"
            "      - random: [2h, 1h]\n"
        )
        self.assertIsNone(config)
        joined = "\n".join(errors)
        self.assertIn("invalid job name", joined)
        self.assertIn("unknown key", joined)
        self.assertIn("quoted string", joined)
        self.assertIn("add one", joined)
        self.assertIn("exactly one", joined)
        self.assertIn("greater than max", joined)


class NextFireTest(unittest.TestCase):
    def test_fixed_no_drift(self):
        rule = intervald.Rule("every", 60)
        timer = intervald.Timer(None, rule, 100)
        daemon = intervald.Daemon.__new__(intervald.Daemon)
        self.assertEqual(daemon.advance(timer, 100), 160)
        self.assertEqual(daemon.advance(intervald.Timer(None, rule, 100), 130), 160)

    def test_fixed_missed_resets_from_now(self):
        rule = intervald.Rule("every", 60)
        daemon = intervald.Daemon.__new__(intervald.Daemon)
        self.assertEqual(daemon.advance(intervald.Timer(None, rule, 100), 170), 230)

    def test_random_rerolled_from_now(self):
        rule = intervald.Rule("random", 10, 10)
        daemon = intervald.Daemon.__new__(intervald.Daemon)
        daemon.rng = intervald.random.Random(1)
        self.assertEqual(daemon.advance(intervald.Timer(None, rule, 100), 500), 510)


class OverlapTest(unittest.TestCase):
    def load(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.yaml"
            path.write_text(text)
            return intervald.load_config(path)

    def test_spawn_tracks_and_active(self):
        config, _, _ = self.load(
            'jobs:\n  a: {command: "sleep 5", schedule: [{every: 1h}]}\n'
        )
        d = intervald.Daemon("-")
        d.config = config
        a = config.jobs["a"]
        try:
            proc = d.spawn(a, "scheduled")
            self.assertIsNotNone(proc)
            self.assertEqual(len(d.active("a")), 1)
            self.assertEqual(d.active("a")[0].pid, proc.pid)
        finally:
            for procs in d.running.values():
                for p in procs:
                    p.kill()
                    p.wait()

    def test_overlap_skip_decision(self):
        config, _, _ = self.load(
            'jobs:\n  a: {command: "sleep 5", overlap: skip, schedule: [{every: 1h}]}\n'
        )
        d = intervald.Daemon("-")
        d.config = config
        a = config.jobs["a"]
        try:
            d.spawn(a, "scheduled")
            self.assertTrue(d.active("a"))
            skipped = a.overlap == "skip" and bool(d.active("a"))
            self.assertTrue(skipped)
        finally:
            for procs in d.running.values():
                for p in procs:
                    p.kill()
                    p.wait()


class ReloadTest(unittest.TestCase):
    GOOD = 'settings: {terminal: "foot -e"}\njobs:\n  a: {command: "sleep 5", schedule: [{every: 45m}]}\n'

    def test_reload_keeps_old_on_error(self):
        f = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False)
        with f:
            f.write(self.GOOD)
        config, errors, _ = intervald.load_config(f.name)
        self.assertEqual(errors, [])
        d = intervald.Daemon(f.name)
        d.config = config
        with open(f.name, "w") as fh:
            fh.write("jobs: [broken")
        ok = d.reload()
        self.assertFalse(ok)
        self.assertIs(d.config, config)
        os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
