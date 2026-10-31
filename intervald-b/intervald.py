#!/usr/bin/env python3
"""intervald - run any command on fixed and/or random (re-rolled) intervals.

Config: ~/.config/intervald/config.yaml   (see config.example.yaml)
Usage:  intervald run | check | status | fire <job> | reload
"""
import argparse
import asyncio
import glob
import json
import os
import random
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("intervald: PyYAML missing (pacman -S python-yaml / apt install python3-yaml)")

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
DEFAULT_CONFIG = CONFIG_HOME / "intervald" / "config.yaml"
UNITS = {"s": 1, "m": 60, "h": 3600}
DUR_RE = re.compile(r"(\d+)([smh])")
NAME_RE = re.compile(r"[A-Za-z0-9_-]+")
TOP_KEYS = {"settings", "jobs"}
SETTINGS_KEYS = {"terminal"}
JOB_KEYS = {"command", "terminal", "shell", "overlap", "schedule"}
REAP_EVERY = 5.0  # seconds; also the max sleep of the scheduler loop


def sock_path() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "intervald.sock"


def log(msg: str) -> None:
    print(msg, flush=True)  # journald captures stdout


# --------------------------------------------------------------------------
# Config model
# --------------------------------------------------------------------------
@dataclass
class Rule:
    kind: str  # "every" | "random"
    lo: int    # seconds (for "every": the interval)
    hi: int

    def describe(self) -> str:
        if self.kind == "every":
            return f"every {fmt_secs(self.lo)}"
        return f"random {fmt_secs(self.lo)}..{fmt_secs(self.hi)}"


@dataclass
class Job:
    name: str
    command: str
    argv: list
    overlap: str = "skip"
    rules: list = field(default_factory=list)


@dataclass
class Config:
    jobs: dict


def fmt_secs(s: float) -> str:
    s = int(round(s))
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return " ".join(p for p in (f"{h}h" if h else "", f"{m}m" if m else "", f"{sec}s" if sec or not (h or m) else "") if p)


# --------------------------------------------------------------------------
# YAML loading (strict: duplicate keys are errors)
# --------------------------------------------------------------------------
class StrictLoader(yaml.SafeLoader):
    """SafeLoader subclass (still safe) that rejects duplicate mapping keys."""


def _construct_mapping(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=True)
        try:
            if key in seen:
                raise yaml.constructor.ConstructorError(
                    None, None, f"duplicate key {key!r}", key_node.start_mark)
            seen.add(key)
        except TypeError:
            pass  # unhashable key; let normal construction complain
    return yaml.SafeLoader.construct_mapping(loader, node, deep)


StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
def parse_duration(v, where: str, errs: list):
    """'45m' -> 2700. Appends to errs and returns None on problems."""
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        errs.append(f"{where}: {v!r} has no unit - write it like '{v}s', '{v}m' or '{v}h'")
        return None
    if not isinstance(v, str):
        errs.append(f"{where}: expected a duration like 90s, 45m, 2h (got {v!r})")
        return None
    m = DUR_RE.fullmatch(v.strip())
    if not m:
        errs.append(f"{where}: bad duration {v!r} (use integer + s|m|h, e.g. 90s, 45m, 2h)")
        return None
    n = int(m.group(1)) * UNITS[m.group(2)]
    if n <= 0:
        errs.append(f"{where}: duration must be positive (got {v!r})")
        return None
    return n


def _get_bool(d: dict, key: str, default: bool, where: str, errs: list) -> bool:
    if key not in d:
        return default
    v = d[key]
    if isinstance(v, bool):
        return v
    hint = " (quoted strings are not booleans - remove the quotes)" if isinstance(v, str) else ""
    errs.append(f"{where}.{key}: must be true or false, got {v!r}{hint}")
    return default


def build(data):
    """Validate parsed YAML. Returns (Config|None, errors, warnings)."""
    errs, warns = [], []
    if not isinstance(data, dict):
        return None, ["top level must be a mapping with 'settings' and 'jobs'"], warns
    for k in data:
        if k not in TOP_KEYS:
            errs.append(f"unknown top-level key {k!r} (allowed: settings, jobs)")

    settings = data.get("settings") or {}
    terminal = None
    if not isinstance(settings, dict):
        errs.append("settings: must be a mapping")
        settings = {}
    for k in settings:
        if k not in SETTINGS_KEYS:
            errs.append(f"settings: unknown key {k!r} (allowed: terminal)")
    t = settings.get("terminal")
    if t is not None:
        if not isinstance(t, str) or not t.strip():
            errs.append("settings.terminal: must be a non-empty string like \"foot -e\"")
        else:
            try:
                terminal = shlex.split(t)
                if not shutil.which(terminal[0]):
                    warns.append(f"settings.terminal: executable {terminal[0]!r} not found in PATH")
            except ValueError as e:
                errs.append(f"settings.terminal: {e}")

    jobs_raw = data.get("jobs")
    if not isinstance(jobs_raw, dict) or not jobs_raw:
        errs.append("jobs: must be a non-empty mapping of <job-name>: {...}")
        return None, errs, warns

    jobs = {}
    for name, j in jobs_raw.items():
        if not isinstance(name, str) or not NAME_RE.fullmatch(name):
            errs.append(f"job name {name!r}: must match [A-Za-z0-9_-]+")
            continue
        w = f"job {name!r}"
        if not isinstance(j, dict):
            errs.append(f"{w}: must be a mapping")
            continue
        for k in j:
            if k not in JOB_KEYS:
                errs.append(f"{w}: unknown key {k!r} (allowed: {', '.join(sorted(JOB_KEYS))})")

        cmd = j.get("command")
        if not isinstance(cmd, str) or not cmd.strip():
            errs.append(f"{w}.command: required, must be a non-empty string")
            cmd = None
        use_term = _get_bool(j, "terminal", False, w, errs)
        use_shell = _get_bool(j, "shell", False, w, errs)
        overlap = j.get("overlap", "skip")
        if overlap not in ("skip", "allow"):
            errs.append(f"{w}.overlap: must be 'skip' or 'allow', got {overlap!r}")
            overlap = "skip"

        argv = []
        if cmd:
            if use_shell:
                argv = ["/bin/sh", "-c", cmd]
            else:
                try:
                    argv = shlex.split(cmd)
                except ValueError as e:
                    errs.append(f"{w}.command: {e}")
                if argv and not shutil.which(argv[0]):
                    warns.append(f"{w}: executable {argv[0]!r} not found in PATH (yet?)")
            if use_term:
                if terminal is None:
                    errs.append(f"{w}: terminal: true but settings.terminal is not set")
                else:
                    argv = terminal + argv

        sched = j.get("schedule")
        rules = []
        if not isinstance(sched, list) or not sched:
            errs.append(f"{w}.schedule: required, must be a non-empty list")
            sched = []
        for i, r in enumerate(sched):
            rw = f"{w}.schedule[{i}]"
            if not isinstance(r, dict) or len(r) != 1 or next(iter(r)) not in ("every", "random"):
                errs.append(f"{rw}: must be exactly one of 'every: <dur>' or 'random: [<min>, <max>]'")
                continue
            kind, val = next(iter(r.items()))
            if kind == "every":
                d = parse_duration(val, f"{rw}.every", errs)
                if d:
                    rules.append(Rule("every", d, d))
            else:
                if not isinstance(val, list) or len(val) != 2:
                    errs.append(f"{rw}.random: must be a 2-item list [<min>, <max>]")
                    continue
                lo = parse_duration(val[0], f"{rw}.random[0]", errs)
                hi = parse_duration(val[1], f"{rw}.random[1]", errs)
                if lo and hi:
                    if lo > hi:
                        errs.append(f"{rw}.random: min ({val[0]}) is greater than max ({val[1]})")
                    else:
                        rules.append(Rule("random", lo, hi))
        if cmd:
            jobs[name] = Job(name, cmd, argv, overlap, rules)

    if errs:
        return None, errs, warns
    return Config(jobs), errs, warns


def load_config(path):
    """Read + validate. Returns (Config|None, errors, warnings)."""
    try:
        text = Path(path).read_text()
    except OSError as e:
        return None, [f"cannot read {path}: {e}"], []
    try:
        data = yaml.load(text, Loader=StrictLoader)  # StrictLoader subclasses SafeLoader
    except yaml.YAMLError as e:
        return None, [f"YAML error: {e}"], []
    return build(data)


# --------------------------------------------------------------------------
# Scheduling
# --------------------------------------------------------------------------
def roll(rule: Rule, rng=random) -> float:
    return float(rule.lo) if rule.kind == "every" else rng.uniform(rule.lo, rule.hi)


def next_deadline(rule: Rule, deadline: float, now: float, rng=random) -> float:
    """Next fire time after a rule fired. Fixed rules advance from the previous
    deadline (no drift); if we are already past that, restart from now.
    Random rules re-roll from now."""
    if rule.kind == "every":
        n = deadline + rule.lo
        return n if n > now else now + rule.lo
    return now + rng.uniform(rule.lo, rule.hi)


def fix_env(env: dict) -> None:
    """Make GUI apps launchable from a systemd user service."""
    rt = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    env.setdefault("XDG_RUNTIME_DIR", rt)
    if not env.get("WAYLAND_DISPLAY") and not env.get("DISPLAY"):
        socks = sorted(p for p in glob.glob(rt + "/wayland-*") if not p.endswith(".lock"))
        if socks:
            env["WAYLAND_DISPLAY"] = os.path.basename(socks[0])
        elif os.path.exists("/tmp/.X11-unix/X0"):
            env["DISPLAY"] = ":0"


class Daemon:
    def __init__(self, path, cfg: Config):
        self.path = path
        self.cfg = cfg
        self.timers = {}   # (job, rule_idx) -> monotonic deadline
        self.running = {}  # job -> [Popen]
        self.wake = asyncio.Event()
        self.stop = asyncio.Event()
        self.reroll()

    # -- timers ------------------------------------------------------------
    def reroll(self):
        now = time.monotonic()
        self.timers = {}
        for job in self.cfg.jobs.values():
            for i, rule in enumerate(job.rules):
                self.timers[(job.name, i)] = now + roll(rule)
                log(f"[timer] {job.name} [{rule.describe()}] next in "
                    f"{fmt_secs(self.timers[(job.name, i)] - now)}")

    # -- processes ---------------------------------------------------------
    def reap(self):
        for name, procs in self.running.items():
            for p in list(procs):
                rc = p.poll()
                if rc is not None:
                    procs.remove(p)
                    log(f"[exit] {name} pid={p.pid} rc={rc}")

    def spawn(self, job: Job, why: str) -> bool:
        self.reap()
        live = self.running.setdefault(job.name, [])
        if why == "scheduled" and job.overlap == "skip" and live:
            log(f"[skip] {job.name}: still running (pid {live[0].pid}), overlap=skip")
            return False
        env = os.environ.copy()
        fix_env(env)
        try:
            p = subprocess.Popen(job.argv, start_new_session=True, env=env,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
        except OSError as e:
            log(f"[error] {job.name}: spawn failed: {e}")
            return False
        live.append(p)
        log(f"[fire] {job.name} ({why}) pid={p.pid}: {' '.join(shlex.quote(a) for a in job.argv)}")
        return True

    # -- scheduler loop ----------------------------------------------------
    async def scheduler(self):
        while not self.stop.is_set():
            now = time.monotonic()
            for key, dl in list(self.timers.items()):
                if dl <= now:
                    job = self.cfg.jobs[key[0]]
                    rule = job.rules[key[1]]
                    self.spawn(job, "scheduled")
                    self.timers[key] = next_deadline(rule, dl, now)
                    log(f"[timer] {job.name} [{rule.describe()}] next in "
                        f"{fmt_secs(self.timers[key] - now)}")
            self.reap()
            soonest = min(self.timers.values(), default=time.monotonic() + REAP_EVERY)
            timeout = max(0.0, min(soonest - time.monotonic(), REAP_EVERY))
            try:
                await asyncio.wait_for(self.wake.wait(), timeout)
            except asyncio.TimeoutError:
                pass
            self.wake.clear()

    # -- reload ------------------------------------------------------------
    def reload(self):
        cfg, errs, warns = load_config(self.path)
        for w in warns:
            log(f"[warn] {w}")
        if errs:
            for e in errs:
                log(f"[error] reload rejected, keeping old config: {e}")
            return False, errs
        self.cfg = cfg
        self.reroll()
        self.wake.set()
        log(f"[reload] config loaded: {len(cfg.jobs)} job(s)")
        return True, []

    # -- control socket ----------------------------------------------------
    def dispatch(self, req: dict) -> dict:
        cmd = req.get("cmd")
        if cmd == "status":
            self.reap()
            now = time.monotonic()
            out = []
            for job in self.cfg.jobs.values():
                out.append({
                    "name": job.name, "command": " ".join(job.argv), "overlap": job.overlap,
                    "pids": [p.pid for p in self.running.get(job.name, [])],
                    "rules": [{"rule": r.describe(), "next_in": self.timers[(job.name, i)] - now}
                              for i, r in enumerate(job.rules)],
                })
            return {"ok": True, "jobs": out}
        if cmd == "fire":
            job = self.cfg.jobs.get(req.get("job"))
            if not job:
                return {"ok": False, "error": f"unknown job {req.get('job')!r}"}
            return {"ok": self.spawn(job, "manual"), "error": None}
        if cmd == "reload":
            ok, errs = self.reload()
            return {"ok": ok, "errors": errs}
        return {"ok": False, "error": f"unknown command {cmd!r}"}

    async def handle(self, reader, writer):
        try:
            req = json.loads((await reader.readline()).decode())
            resp = self.dispatch(req)
        except Exception as e:  # noqa: BLE001
            resp = {"ok": False, "error": str(e)}
        writer.write((json.dumps(resp) + "\n").encode())
        await writer.drain()
        writer.close()

    async def run(self):
        loop = asyncio.get_running_loop()
        loop.add_signal_handler(signal.SIGHUP, self.reload)
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, lambda: (self.stop.set(), self.wake.set()))
        sp = sock_path()
        sp.unlink(missing_ok=True)
        server = await asyncio.start_unix_server(self.handle, path=str(sp))
        os.chmod(sp, 0o600)
        log(f"[start] intervald running, {len(self.cfg.jobs)} job(s), socket {sp}")
        try:
            await self.scheduler()
        finally:
            server.close()
            sp.unlink(missing_ok=True)
            log("[stop] intervald stopped (spawned programs keep running)")


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def rpc(req: dict) -> dict:
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(5)
    try:
        s.connect(str(sock_path()))
    except OSError:
        sys.exit(f"intervald: daemon not running (no socket at {sock_path()})")
    s.sendall((json.dumps(req) + "\n").encode())
    return json.loads(s.makefile().readline())


def report(errs, warns):
    for w in warns:
        print(f"warning: {w}", file=sys.stderr)
    for e in errs:
        print(f"error: {e}", file=sys.stderr)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="intervald", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("run", "check"):
        p = sub.add_parser(name)
        p.add_argument("-c", "--config", default=str(DEFAULT_CONFIG))
    sub.add_parser("status")
    sub.add_parser("reload")
    pf = sub.add_parser("fire")
    pf.add_argument("job")
    args = ap.parse_args(argv)

    if args.cmd in ("run", "check"):
        cfg, errs, warns = load_config(args.config)
        report(errs, warns)
        if errs:
            return 2
        if args.cmd == "check":
            print(f"ok: {len(cfg.jobs)} job(s) in {args.config}")
            return 0
        asyncio.run(Daemon(args.config, cfg).run())
        return 0

    if args.cmd == "status":
        r = rpc({"cmd": "status"})
        for j in r["jobs"]:
            state = f"RUNNING pid {','.join(map(str, j['pids']))}" if j["pids"] else "idle"
            print(f"{j['name']}  [{state}]  overlap={j['overlap']}\n  $ {j['command']}")
            for ru in j["rules"]:
                eta = time.strftime("%H:%M:%S", time.localtime(time.time() + ru["next_in"]))
                print(f"  - {ru['rule']:<22} next in {fmt_secs(ru['next_in'])} (~{eta})")
        return 0

    if args.cmd == "reload":
        r = rpc({"cmd": "reload"})
        if r["ok"]:
            print("reloaded")
            return 0
        report(r.get("errors") or [r.get("error")], [])
        return 1

    if args.cmd == "fire":
        r = rpc({"cmd": "fire", "job": args.job})
        print("fired" if r["ok"] else f"failed: {r.get('error') or 'spawn error (see journal)'}")
        return 0 if r["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
