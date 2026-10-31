# memoloop audit — 2026-10-30/31

Scope: `src/memoloop`, `install.sh` (with `lib/installer.sh` in the picture), the
installed systemd unit, and the runtime state on this machine. Line numbers are
from the working tree at commit `e824f65`.

---

## 1. Why the daemon popup opens and closes immediately

**Short version:** the running `memoloop.service` was still executing the
pre-fix script from memory, that version launches `memoloop ask` without
`FOOT_POPUP=1`, and the *current* `cmd_ask` reacts to a missing `FOOT_POPUP` by
spawning a *second* `foot` and returning. The first window is then a wrapper
that exits instantly and takes the real window down with it.

### Evidence

The daemon started 2026-10-30 23:45 and was never restarted. Its script file has
since been replaced by `install.sh`:

```
$ ls -l /proc/348497/fd/255
lr-x------ 1 eru eru 64 ... /proc/348497/fd/255 -> /home/eru/.local/bin/memoloop (deleted)
```

Copying that fd out gives the 666-line version; the file on disk is the 809-line
version. The one relevant difference is `launch_popup`:

```sh
# in-memory (666-line version)
foot --app-id="memoloop" -e "$SELF_DIR/memoloop" ask "$id" &

# on disk (current)
FOOT_POPUP=1 foot --app-id="memoloop" -e "$SELF_DIR/memoloop" ask "$id" &
```

`cmd_ask` re-executes `$SELF_DIR/memoloop` **from disk**, so the popup child is
the new code while the launcher is the old code. New `cmd_ask` has two spawn
branches:

- line 416: `if [ -z "${FOOT_POPUP:-}" ] && [ ! -t 0 ]`
- line 435: `if [ -z "${FOOT_POPUP:-}" ]` ← inside foot, stdin **is** a tty, so
  the first branch is skipped, the question is selected, and this branch fires.

So the chain for a daemon-triggered popup is:

```
memoloop watch (stale)
  └─ foot #1  (empty window, app-id=memoloop)
       └─ memoloop ask (new code, FOOT_POPUP unset)
            └─ foot #2  (would show the question)  → ask returns 0
       → foot #1 exits immediately, pty #1 closes
       → foot #2 is a background job in foot #1's pty session and dies with it
```

Reproduced deterministically, without the daemon:

```
systemd-run --user foot -e /home/eru/.local/bin/memoloop ask fixed   # FOOT_POPUP unset
→ foot #1 appears and both processes are gone in <1 s; log gets "fired" only

foot --app-id=t2 -e /home/eru/.local/bin/memoloop ask fixed          # FOOT_POPUP=1
→ one foot + one `memoloop ask` child, stays alive and blocks in `read`
```

The second foot really is killed by the first window going away, not by its own
logic: in a controlled test (`foot -e 'foot -e sleep 40 & sleep 15'`) the nested
foot lives exactly as long as the outer one and dies the moment the outer
window's child exits. `setsid` alone does not save it either (its stdio is still
the outer pty).

### Why the other two paths work

| entry point | FOOT_POPUP | stdin | result |
|---|---|---|---|
| `memoloop ask` in a terminal | unset | tty | branch 416 skipped, branch 435 spawns foot #2, parent terminal stays open → works |
| niri `spawn-sh` (MOD+N) | unset | not a tty | branch 416 spawns foot with `FOOT_POPUP=1` → child renders, parent has no pty to close → works |
| `memoloop watch` (**stale**) | unset | tty inside foot | branch 416 skipped, branch 435 double-spawns → both windows die |

The empty window is foot #1; the "standard window" seen during the checks was
the deliberately different `--app-id` test window, which does not match the
`app-id=memoloop` niri rule and therefore tiles.

### Fix applied

```sh
systemctl --user restart memoloop.service
```

Verified after restart: `/proc/<MainPID>/fd/255` is no longer `(deleted)`, the
next fire produces exactly one `foot --app-id=memoloop` plus one
`memoloop ask` child, the window stays open, and a second due rule queues
(`random queued prompt already open`) instead of double-launching.

No state was touched; `next_due` was recalculated normally by the daemon.

### Why it will come back

`install.sh` only ever runs `systemctl --user enable` + `start`. `start` on an
already-active unit is a **no-op**, so every reinstall leaves the old daemon
running old code indefinitely. There is also no version check between the
running `watch` loop and the on-disk `ask` it spawns, so partial upgrades are
always possible. And the second spawn branch in `cmd_ask` is a live hazard even
without version skew — it is redundant with branch 416 and only fires when
`FOOT_POPUP` is missing, i.e. exactly in the broken case.

Check for a stale daemon at any time:

```sh
readlink /proc/"$(systemctl --user show -p MainPID --value memoloop.service)"/fd/255
# trailing " (deleted)" means the running code is not what is installed
```

---

## 2. Correctness bugs in `src/memoloop`

Ordered by impact.

1. **Double spawn in `cmd_ask` (line 435).** Redundant with line 416, only
   reachable in the broken state described above. Should be deleted; rendering
   should be gated on `FOOT_POPUP` alone and the launcher should always set it.

2. **`memoloop setup` is broken** (line 798). `cmd_setup` is never defined:

   ```
   $ ./src/memoloop setup
   ./src/memoloop: line 798: cmd_setup: command not found
   ```

   It is advertised in `usage`, in `README.md` and in the progress notes.

3. **`memoloop dnd HH:MM HH:MM` is broken** (line 728). `session_set` passes the
   value through `jq --argjson`, so `12:00` is parsed as JSON:

   ```
   $ memoloop dnd 12:00 13:00
   jq: invalid JSON text passed to --argjson
   ```

   It also never calls `state_init`, so on a clean system it would fail before
   that anyway. Strings need `--arg` (or an explicit `--argjson "$(printf
   '"%s"' "$v")"`); the same `session_set` is used for booleans and integers,
   which is why the bug stayed hidden.

4. **`random_min`/`random_max` from `intervals.conf` are ignored after the first
   run.** `state_init` bakes them into `rules.json` once
   (`rules_set_next_due` never rewrites `min`/`max`), and
   `rule_interval_seconds` reads `.min`/`.max` from the state file. `fixed`
   accidentally works because it re-reads `FIXED_SECONDS`. Editing the config
   therefore silently changes only one of the two rules.

5. **`intervals.conf` lives in the wrong directory.** `load_intervals` reads
   `$USER_DATA_DIR/intervals.conf` while `usage`/`README` document
   `~/.config/memoloop/intervals.conf`; `CONFIG_CONF` (line 25) is assigned and
   never read; `install.sh` writes the file into the data dir. Pick one place.

6. **`NOHELP` cannot be set by the environment.** `MEMOLOOP_NOHELP=1`, set by the
   niri binder in `niri/memoloop.kdl`, is never read; the only source is
   `nohelp=` in `intervals.conf`. Since the default is `true`, the binder is a
   no-op.

7. **`process_queue` writes state twice per 5-second loop, unconditionally**
   (lines 400–401): two `jq` runs and two file replacements even when there is
   nothing to do. That is ~19k writes in 13 h and is where the
   `7min 57s CPU / 13h` in `systemctl status` comes from. It should only write
   when a value actually changes.

8. **State files are read-modify-write with no locking.** `session_set`,
   `session_open_set`, `rules_set_next_due` and `save_answers` read the file,
   transform it, then `mv` a temp over it. The daemon and any CLI invocation
   (or a second popup) can interleave, and the last writer wins: a `memoloop
   pause` can be lost while the loop is rewriting `session.json`.
   `save_answers` truncates in place instead of replacing.

9. **Two rules due in the same second pick the same question.**
   `select_question` seeds `awk srand` with `$(epoch)`, so the fixed and random
   popups fired in one loop iteration produce identical `rand()` streams and
   therefore the same question.

10. **`due_rules` (line 376) reads `next_due == 0` as "never due".** `state_init`
    seeds `0`, and `cmd_watch` repairs it only at startup, so a hand-edited or
    stale `0` disables a rule forever. The `[ A ] || [ B ] || [ C ] && continue`
    form is also only correct because `&&`/`||` are left-associative — a
    parenthesised rewrite would change its meaning.

11. **`in_dnd` (line 355) compares `HH:MM` strings.** No overnight window is
    possible (`22:00–02:00` silently never matches), and `start == now` counts
    as DND while `end == now` also counts as DND.

12. **`die` blocks on a key inside a popup but not in the daemon.** With a tty
    the user gets "Press any key to close" and the window hangs; on the
    service's `/dev/null` stdin the daemon exits and `Restart=on-failure`
    restart-loops every 30 s. The unit has no `StartLimitBurst`/`StartLimitIntervalSec`,
    so a permanent config error spams the journal 120×/hour forever.

13. **`config.conf` is executed** (`. "$CONFIG_DIR/config.conf"`), not parsed.
    Anyone who can write that file runs shell in the user's session.

14. **`answers.json` is neither in the cache nor separate from user data.**
    `CACHE_DIR` and `USER_DATA_DIR` default to the same
    `~/.local/share/memoloop`, so questions, intervals and answers share a
    directory, while `README` calls answers a cache at `~/.local/share/memoloop`.

15. **State and log are installed next to the binary.** `STATE_DIR`/`LOG_DIR`
    are `$SELF_DIR/../state|log`, i.e. for the installed copy
    `~/.local/state` and `~/.local/log` with generic names: `rules.json`,
    `session.json`, `current.json`, `result.json`, `reminders.log`. That is a
    global namespace shared with every other tool, undocumented, not created by
    the installer, and left behind on uninstall.

16. **`usage` is wrong in three places:** cache path (`~/.cache/memoloop/` vs the
    real `~/.local/share/memoloop`), the `dnd` line (`dnd <e>   set ...`), and
    `setup` being listed although missing.

17. **Dead code:** `CONFIG_CONF` (line 25), `RULE_FIXED_ID` and `RULE_RANDOM_ID`
    (lines 51–52). `RANDOM_MIN`/`RANDOM_MAX` are only used when seeding
    `rules.json`, then shadowed by the state file (see item 4).

18. **`question_weight` can return > 1.** A backwards clock jump makes
    `hours_diff` negative and the decay factor greater than 1.

19. **`cmd_watch` draws a `term` frame into the journal on every start**
    (`term_notice "memoloop watch" ...`), which is noise in `journalctl`.

### Tests

`tests/memoloop_test.sh` sources `src/memoloop` as a library and asserts pure
functions only, so `setup`, `dnd`, `ask`, the popup launch path and the whole
installer are untested — which is why all of the above shipped green.

---

## 3. `install.sh` audit

### Blocking bugs

1. **Never restarts an active service** (the §1 trigger). `install_integration`
   does `daemon-reload`, `enable`, `start`. On an upgrade the unit is already
   active and `start` is a no-op. Needs `systemctl --user restart` (or
   `try-restart`) after the files are in place — and `disable --now` plus
   `daemon-reload` on uninstall.

2. **Uninstall leaves the daemon running.** `uninstall_integration` only
   `rm -f`s the unit file. No `stop`, no `disable`, no `daemon-reload`, so the
   process keeps running with `memoloop` already deleted from `~/.local/bin`
   (it survives on fd 255 until it fires something). State/log dirs,
   `~/.local/lib` and the answers file are never mentioned in the uninstall
   output either.

3. **`--install-path` breaks the install.** `INSTALLER_LIB_DIR` is computed in
   the `--user`/`--system` case block, before `installer_run` parses
   `--install-path`. So `./install.sh --install-path /opt/bin` puts `memoloop`
   in `/opt/bin` and `term.sh` in `~/.local/lib`; the script then looks for
   `/opt/lib/term.sh` and dies. The systemd unit is also hardcoded to
   `%h/.local/bin/memoloop`, so it points at a binary that does not exist.

4. **`--system` is non-functional end to end.** It writes a *user* unit
   (`WantedBy=graphical-session.target`, `%h` specifiers) into
   `/etc/systemd/system`, still calls `systemctl --user`, puts config in
   `/etc/memoloop` but generates `USER_DATA_DIR="$HOME/.local/share/memoloop"`
   inside it, and appends the alias to `/etc/zsh/zshrc` while the service it
   starts is a user service. Either implement it properly (absolute paths,
   `User=`/`PAMName=`, `systemctl` without `--user`) or remove the flag — the
   help text currently promises something that cannot work.

### Structural problems

5. **`set -euo pipefail` around a vendored POSIX library.** `lib/installer.sh` is
   written for `sh` without `-e` and relies on idioms like
   `[ $# -eq 0 ] && return 0` and `[ … ] && cmd`. Under `-e` a false comparison
   that is the last command of a function aborts the whole installer. The
   `installer_do_section` "is `$1` a verb or a message" heuristic (verb table
   contains `systemctl`, `install`, `rm`, …) is the same class of fragility: it
   works only because every call in `install.sh` happens to start with
   `installer_as_root`.

6. **The systemd unit and the default configs exist twice**, once in the repo
   and once as heredocs in `install.sh`, so they can drift (they already do: the
   repo's `niri/memoloop.kdl` sets `MEMOLOOP_NOHELP=1`, which the script
   ignores).

7. **No rollback and no error propagation.** `installer_do_section` runs
   commands inside a `case` and the failure of e.g. `systemctl --user start` is
   only visible as a non-zero status of the function; the install still prints
   "installed" and "next steps". A half-finished install (unit written, service
   not started, niri include appended) is reported as success.

8. **Overwrites user files without asking.** `install -m 644
   niri/memoloop.kdl` clobbers a user-edited copy; the appended alias and niri
   include blocks are idempotent but not versioned, so a changed block never
   replaces the old one.

9. **`ALIAS_LINE` (line 51) is dead**, and the alias actually written is
   `alias memoloop='…/memoloop'` — running it prints usage and exits 1. If the
   point is "the command", the alias should not exist at all (`~/.local/bin` is
   already on `PATH`); if the point is "open a prompt", it must be
   `…/memoloop ask`.

10. **`--purge-data` is accepted on install** (parsed in `install.sh`'s own loop
    regardless of action) although only uninstall reads it. Same for
    `--overwrite-data` on uninstall.

11. **Mixed regimes.** `install.sh` is bash with `local`; `installer.sh` is
    POSIX `sh` and gets `local` only because bash is sourcing it. The
    `. "$SCRIPT_DIR/lib/term.sh"` in `install.sh` is sourced twice (once
    directly, once inside `installer.sh`).

12. **`mkdir -p "$HOME/.config/niri"` + unconditional install** assumes niri is
    the compositor; there is no `--no-niri` and no check that `$HOME/.config/niri/config.kdl`
    exists before the include append (guarded, but silently skipped otherwise).

---

## 4. Minimal fix order

1. *(done)* `systemctl --user restart memoloop.service` — popups work again.
2. Delete the second spawn in `cmd_ask`; make `ask` require `FOOT_POPUP` to
   render and fail loudly otherwise; keep every launcher setting it.
3. `install.sh`: `systemctl --user restart` (not `start`) after files are
   installed; `disable --now` + `daemon-reload` on uninstall.
4. Fix `cmd_dnd` (`--arg`) and either implement or drop `cmd_setup`.
5. Make `install.sh --install-path` recompute `INSTALLER_LIB_DIR` and template
   the unit from `$INSTALLER_TARGET`; decide about `--system`.
6. State/log dirs: one `MEMOLOOP_STATE_DIR` (e.g. `$XDG_STATE_HOME/memoloop`),
   created by the installer and printed on uninstall.
7. Only write session/rules when a value changes; add a lock (or a single
   writer) for the shared JSON files.
8. Seed `select_question` from `$RANDOM`/nanoseconds instead of `epoch`.
9. Add tests: `setup`, `dnd`, a popup smoke test that runs `FOOT_POPUP=1
   memoloop ask` on a pty and asserts it blocks, and an `install.sh --dry-run`
   test.
