# Question file format

A question set is plain JSON. This document is the contract: anything that
follows it can be shown by MemoLoop, and anything that does not may render
badly or be ignored.

## Where files live

```
~/.local/share/memoloop/questions/      # or $MEMOLOOP_DATA_DIR/questions
├── greetings/
│   ├── basics.json
│   └── polite.json
├── verbs/
│   └── godan.json
└── weather/
    └── basics.json
```

- Each direct subdirectory of `questions/` is a **group**.
- Only `*.json` files directly inside a group directory are read. Nested
  directories are not scanned.
- A group is active only when its name is listed in
  `~/.config/memoloop/pickup.set` (one group per line, `#` starts a comment,
  blank lines ignored).
- Files are read in shell glob order and merged, so the order of questions
  inside a group is: filename ascending, then array order.
- A fresh install copies the bundled groups from `data/questions/`.

## File shape

Every file is a UTF-8 JSON **array of objects**:

```json
[
  {
    "id": "greet-001",
    "type": "translation",
    "japanese": "こんにちは",
    "english": "Hello / Good afternoon",
    "accepted": ["こんにちは", "konnichiwa"],
    "note": "Standard daytime greeting."
  }
]
```

No comments, no trailing commas, one array per file. A file may hold one
question or hundreds; they are equivalent.

Files must be written with indentation, one field per line — never minified
into one long line. The bundled data is formatted with
[Prettier](https://prettier.io) defaults (2 spaces, 80 columns). If `prettier`
is installed, format every question file in place:

```sh
prettier --write 'data/questions/*/*.json'
```

Otherwise match the existing indentation by hand. `jq` output is also valid,
but run it through `prettier` before committing so diffs stay readable.

## Fields

| Field | Required | Type | Meaning |
| --- | --- | --- | --- |
| `id` | yes | string | Stable unique identifier for this question. |
| `type` | no | string | `translation`, `reverse`, `cloze`, or `choice`. Defaults to `translation`. |
| `japanese` | yes | string | The Japanese side of the question. Its exact use depends on `type`. |
| `english` | yes | string | The English side, shown as the meaning or the prompt. |
| `accepted` | yes | array of strings | Answers counted as correct. The first entry is shown after answering. |
| `note` | no | string | Extra line shown under the prompt for `reverse` and `cloze`. Defaults to empty. |
| `target` | for `cloze` | string | Substring of `japanese` to blank out. |
| `choices` | for `choice` | array of strings | Options, rendered one per line exactly as written. |
| `answer` | for `choice` | string | Correct option letter, e.g. `"B"`. |

Unknown fields are ignored. (`romaji` appears in the bundled data but is only
documentation; put romaji spellings in `accepted` if they should be accepted.)

`id` must be unique across every active group. Progress and scoring are keyed
by `id` in `answers.json`; reusing an id makes two questions share history.
A common convention is `<group>-<number>`, but any non-empty string works.

## Answer checking

Before comparison, both the typed answer and every `accepted` entry are:

1. lowercased,
2. trimmed of leading and trailing whitespace,
3. stripped of all remaining whitespace.

So `ありがとう ございます`, `Arigatou Gozaimasu`, and
`arigatougozaimasu` are the same answer. Punctuation is not removed, and kanji
and kana are not converted — list every spelling you want to accept.

Special single-letter answers, checked before scoring but after the same
normalisation:

| Input | Effect |
| --- | --- |
| empty, `s`, `S` | skip: no score change |
| `d`, `D` | dismiss: no score change |
| `p`, `P` | pause all reminders, close the popup |

For `choice`, correctness is decided by `answer` alone; `accepted` is still
required because its first entry is used in the feedback text. A `choices`
entry that is itself `"A. big"` is correct when the user types `A`.

## Types

### `translation` (default)

Prompt shows the Japanese and its English meaning; the user types the Japanese
(or romaji).

```
  こんにちは
  English: Hello / Good afternoon
  Japanese: _
```

- Uses: `japanese`, `english`, `accepted`.
- `note` is not shown.

### `reverse`

Prompt shows the English (and the note); the user types the Japanese.

```
  English: Thank you
  Translate this English to Japanese: Thank you
  Japanese: _
```

- Uses: `japanese`, `english`, `accepted`, `note`.
- Reusing `japanese` and `accepted` from a `translation` entry is normal; only
  the direction of the prompt changes.

### `cloze`

Prompt shows `japanese` with the first occurrence of `target` replaced by
`___`, then the note and the English meaning; the user types the missing word.

```json
{
  "id": "kana-025",
  "type": "cloze",
  "japanese": "あいうえお",
  "target": "あ",
  "english": "First hiragana vowel",
  "accepted": ["あ", "a"],
  "note": "あ (a) - First vowel in the gojuon order."
}
```

```
  ___いうえお
  あ (a) - First vowel in the gojuon order.
  Meaning: First hiragana vowel
  Fill in the blank: _
```

- Uses: `japanese`, `target`, `english`, `accepted`, `note`.
- `target` is treated as a regular expression by the substitution; keep it
  plain text (no `|`, `*`, `.`, `[`, `\`) and make sure it occurs in
  `japanese`.
- `japanese` may already contain `___`; the result is then unchanged.
- Correctness is checked against `accepted`, not against `target`.

### `choice`

Prompt shows `japanese` (the question text), the options, and asks for a
letter.

```json
{
  "id": "fam-004",
  "type": "choice",
  "japanese": "妻 means?",
  "english": "wife",
  "choices": ["A. son", "B. wife", "C. daughter"],
  "answer": "B",
  "accepted": ["B", "b"],
  "note": "妻 (tsuma) = wife."
}
```

```
  妻 means?

    A. son
    B. wife
    C. daughter

  Answer (A/B/C): _
```

- Uses: `japanese`, `english`, `choices`, `answer`, `accepted`.
- `choices` is printed verbatim; include the `A. ` / `B. ` prefixes yourself
  so the visible letters match `answer`.
- Any number of options works; the `Answer (A/B/C):` label is fixed text.
- `english` and `note` are used in the feedback/scoring flow but are not shown
  as a separate prompt line.
- Matching is case-insensitive, so `b` and `B` are both correct.

## How questions are picked

The daemon does not walk the list in order. Each question has a point budget in
`answers.json` (default 100, +10 correct, -10 wrong, floor 0). Selection is
weighted random:

- lower points → higher chance of being picked,
- points decay towards their original weight with time (`decay_hours`),
- until `min_per_day` prompts have been shown today, questions not yet shown
  today are preferred.

This is why `id` matters: a new id starts at full weight with no history.

## Validation

Check one or more files with `jq`:

```sh
jq -e '
  type == "array" and all(.[];
    (.id | type) == "string" and (.id | length) > 0 and
    (.japanese | type) == "string" and
    (.english | type) == "string" and
    (.accepted | type) == "array" and
    ((.type // "translation") |
      IN("translation", "reverse", "cloze", "choice")) and
    (if (.type // "translation") == "choice"
     then ((.choices | type) == "array") and ((.answer | type) == "string")
     else true end) and
    (if (.type // "translation") == "cloze"
     then (.target | type) == "string"
     else true end)
  )
' data/questions/*/*.json
```

Then confirm the ids are unique:

```sh
jq -s -e '[.[][] | .id] | length == (unique | length)' data/questions/*/*.json
```

## Adding a group

1. Create `~/.local/share/memoloop/questions/<group>/` and add one or more
   `.json` arrays.
2. Add `<group>` to `~/.config/memoloop/pickup.set`.
3. Check it with `memoloop config` (question counts per group) and
   `memoloop test`.
