"""Smoke test: python3 test_smoke.py"""
import random, subprocess, sys, time
import yaml
import intervald as I

def cfg(text):
    return I.build(yaml.load(text, Loader=I.StrictLoader))

GOOD = """
settings: {terminal: "foot -e"}
jobs:
  a: {command: "sleep 5", terminal: true, schedule: [{every: 45m}, {random: [15m, 30m]}]}
"""

def test_durations():
    e = []
    assert I.parse_duration("90s", "x", e) == 90
    assert I.parse_duration("2h", "x", e) == 7200
    assert not e
    for bad in (30, "1h30m", "5d", "0m", "1.5h", True, None):
        e = []
        assert I.parse_duration(bad, "x", e) is None and e, bad

def test_good_config():
    c, errs, _ = cfg(GOOD)
    assert not errs and c.jobs["a"].argv[:2] == ["foot", "-e"] and len(c.jobs["a"].rules) == 2

def test_bad_configs():
    cases = {
        "min>max": 'jobs: {a: {command: x, schedule: [{random: [30m, 15m]}]}}',
        "bare number": 'jobs: {a: {command: x, schedule: [{every: 30}]}}',
        "no schedule": 'jobs: {a: {command: x}}',
        "unknown key": 'jobs: {a: {command: x, schedule: [{every: 1m}], bogus: 1}}',
        "both rules": 'jobs: {a: {command: x, schedule: [{every: 1m, random: [1m, 2m]}]}}',
        "term w/o setting": 'jobs: {a: {command: x, terminal: true, schedule: [{every: 1m}]}}',
        "quoted bool": 'jobs: {a: {command: x, shell: "yes", schedule: [{every: 1m}]}}',
        "bad name": 'jobs: {"a b": {command: x, schedule: [{every: 1m}]}}',
        "no command": 'jobs: {a: {schedule: [{every: 1m}]}}',
    }
    for name, text in cases.items():
        c, errs, _ = cfg(text)
        assert c is None and errs, name

def test_duplicate_keys():
    try:
        cfg("jobs: {a: {command: x, schedule: [{every: 1m}]}, a: {command: y}}")
    except yaml.YAMLError:
        return
    raise AssertionError("duplicate key not rejected")

def test_next_deadline():
    fixed, rnd = I.Rule("every", 100, 100), I.Rule("random", 10, 20)
    assert I.next_deadline(fixed, 1000, 1001) == 1100          # no drift
    assert I.next_deadline(fixed, 1000, 5000) == 5100          # woke late: restart from now
    for _ in range(200):
        assert 5010 <= I.next_deadline(rnd, 0, 5000, random) <= 5020

def test_overlap_and_manual_fire():
    c, _, _ = cfg('jobs: {a: {command: "sleep 5", schedule: [{every: 1h}]}, b: {command: "sleep 5", overlap: allow, schedule: [{every: 1h}]}}')
    d = I.Daemon("-", c)
    a, b = c.jobs["a"], c.jobs["b"]
    try:
        assert d.spawn(a, "scheduled") is True
        assert d.spawn(a, "scheduled") is False   # skipped: still running
        assert d.spawn(a, "manual") is True       # manual ignores overlap
        assert d.spawn(b, "scheduled") and d.spawn(b, "scheduled")  # allow
    finally:
        for procs in d.running.values():
            for p in procs:
                p.kill(); p.wait()

def test_reload_keeps_old_on_error(tmp=None):
    import tempfile, os
    f = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False)
    f.write(GOOD.replace("foot -e", "true -e")); f.close()
    c, errs, _ = I.load_config(f.name)
    assert not errs
    d = I.Daemon(f.name, c)
    open(f.name, "w").write("jobs: [broken")
    ok, errs = d.reload()
    assert not ok and errs and d.cfg is c
    os.unlink(f.name)

if __name__ == "__main__":
    for n, fn in list(globals().items()):
        if n.startswith("test_"):
            fn(); print("ok", n)
