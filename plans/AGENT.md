Implement the first Linux prototype of the Japanese desktop language-learning app.

[PATH] = /home/eru/r/projects/a-memoloop

The product plan and prior decisions are in [PATH]/plans/*. Read those files first. If anything here conflicts with a more recent, explicit decision in the plans, follow the plans and note the conflict in your summary.

## Working directory and source examples

Create the prototype as an independent git repo, that eventually will become whole desktop app, so make some simple dir structure for this future:
[PATH]
Treat it as the destination directory.

(side note: ~/r/ → is sym link to → /mnt/r/)

Use these existing projects as references:
- /t-linux/cli-utilities/utilities/glyph-key — reference for a popup terminal that accepts input, displays Japanese text correctly, and reflects its current state.
- /t-linux/cli-utilities/utilities/desk-reminder — reference for interval scheduling and reminder behavior.

Inspect both projects before implementing. Reuse ideas and patterns where helpful, but do not modify either source project or make the new prototype depend on files inside them at runtime. The deliverable must be self-contained in [PATH].

Path to japanese resources to get text for first draft content (prefer md and txt files over binaries):
/home/eru/q/_sync/MEGA/Preply-Nihongo
/home/eru/q/NIHONGO

## Prototype goal

Test whether independent, overlapping Japanese study reminders are useful in real life. This is a Linux prototype, not the final cross-platform app. Keep it small and easy to run.

Build a popup-terminal question experience that:
- Opens a terminal popup using an approach informed by glyph-key.
- Correctly displays Japanese text and accepts typed input.
- Shows the question, any necessary answer instructions, and clear current status.
- Lets the user submit an answer, reveal/see feedback, dismiss the prompt, or pause all reminders.
- Works with a small local sample set of Japanese questions.

“Current status” should make it clear whether reminders are running, paused, or in DND, and, when practical, show the next due reminder or the rule that triggered the current prompt.

## Scheduling requirements

Implement two independent rules by default:
1. Fixed rule: one prompt every 15 minutes.
2. Random rule: one prompt at a randomly selected interval between 30 and 40 minutes.

Each rule must maintain its own next-due time. Rules may fire close together or at the same time; do not silently merge or discard one. For the prototype, show each due prompt separately and record which rule triggered it. If a prompt is already open when another rule fires, handle that situation deliberately—queue the second prompt within the app, rather than launching overlapping popup terminals. Explain this behavior in the README.

Implement:
- A global pause/resume control.
- A configurable Do Not Disturb window, using the simplest suitable configuration approach for this prototype.
- No backlog: prompts whose due times pass during pause or DND should be skipped, not queued for later.
- Clear and consistent timer behavior on restart. Document it; do not invent a complicated persistence system.

Use the interval behavior in desk-reminder as a reference, but inspect its actual implementation before deciding what to reuse.

## Question and feedback requirements

Provide a small, local sample question set that includes Japanese text (kana and, if practical, kanji), English meanings, and accepted answers. Keep content easy to edit.

Support at least:
- Showing a Japanese prompt.
- Accepting typed input.
- Checking against one or more accepted answers, with reasonable whitespace handling.
- Showing whether the answer was accepted and displaying the intended answer.
- Dismissing without answering.

Do not claim to implement SuperMemo or spaced-repetition scheduling in this prototype. Scheduling rules determine when prompts appear; this prototype uses a simple local question set.

## Implementation constraints

- First inspect the two reference projects and the plans. Then implement; do not stop after producing a proposal.
- Keep all new source, configuration, sample data, logs, and documentation inside [PATH], except for normal system dependencies.
- Do not modify the reference projects.
- Avoid unnecessary dependencies. Prefer the simplest maintainable implementation compatible with the existing glyph-key and desk-reminder patterns.
- Don’t add system-wide keyboard interception, OS locking, a punishment screen, accounts, cloud sync, Anki integration, or cross-platform packaging.
- Handle missing terminal/display dependencies with a useful error message.
- Make Japanese display and input a specific test target; document any required locale, terminal, or font assumptions.
- Add basic automated tests for interval selection, independent rule scheduling, DND/pause skipping, and answer matching if the project structure makes that practical.

## Before finishing

Run the prototype’s available tests and perform basic checks. Do not claim something works unless you tested it; report any checks you could not run.

Add a README in [PATH] with:
- What the prototype does and does not do.
- Dependencies and exact run instructions.
- How to configure intervals and DND.
- How to edit the sample questions.
- How simultaneous rules and an already-open popup are handled.
- Restart, pause, and missed-prompt behavior.
- Any limitations or follow-up work.

Finish with a concise summary of:
1. What you implemented.
2. The files created.
3. Commands to run and test it.
4. Any assumptions, failures, or unresolved issues.
