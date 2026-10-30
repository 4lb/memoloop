# memoloop

## Comments in code: DO NOT

Do not write comments in code. This is a hard rule, not a preference.

### Why

Comments rot. They drift from the code they describe. They become misinformation.
If code needs explaining, refactor the code, don't annotate it.

### What counts as a comment

- Full-line comments starting with `#`
- Inline comments at end of code lines (`code # explanation`)
- Block comments, docstrings, header comments
- TODOs, FIXMEs, notes to self

### What stays

- Shebang (`#!/usr/bin/env bash`)
- `#` inside strings, jq filters, sed expressions, awk programs
- `$((...))` arithmetic with `#` parameter expansion (`${#var}`)
- `$#` special shell variable

### Reference

This follows the same convention as the `t-linux/cli-utilities` catalog:
https://github.com/Kilo-Org/kilocode (conventions/output.md)

Every tool in that catalog is comment-free. `term.sh` and `installer.sh` are
vendored from there and are also comment-free.

### Exceptions

None. If you think code needs a comment, the code is unclear. Fix the code.
