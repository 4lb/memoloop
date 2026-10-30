
## Revised product plan

A standalone desktop app that delivers short Japanese-learning prompts throughout the day. Its distinctive feature is **multiple independent scheduling rules**: users can run several schedules at once, and prompts from different rules may happen close together—or even back-to-back.

The app should separate two things:

- **When a prompt can appear:** scheduling rules and Do Not Disturb.
- **What happens when it appears:** question type, number of questions, estimated effort, and response flow.

That separation keeps simple schedules easy to set up while leaving room for an advanced rule builder later.

## Scheduling rules

Let users create, enable, disable, edit, and delete as many rules as they need. Rules operate independently; they don’t replace or merge with one another.

Examples:

- **Quick check:** one yes/no question every 15 minutes.
- **Random check:** one short question at a random interval of 30–40 minutes.
- **Mini-session:** two questions every hour, designed to take about two minutes.
- **Workday review:** one Japanese-to-English prompt every 45 minutes, weekdays only.

If fixed and random rules both fire close together, both prompts are valid—for example, one at 14:15 and another at 14:16. The app should offer a setting to either show them separately or bundle nearby prompts into a short session. Keep “show separately” as the faithful default, and make bundling optional so people don’t miss which rule triggered what.

Each rule needs its own:

- Schedule type: fixed interval or random interval range
- Prompt format and question count
- Optional time/day restrictions
- Behavior when the user is busy or a prompt is missed

**Important scheduling detail:** use each rule’s own timer, not one shared global timer. If a prompt is postponed, skipped, or interrupted, define whether that changes only that rule’s next time or leaves its schedule unchanged. A sensible initial choice is that answering or dismissing a prompt resets that rule’s timer; missed prompts don’t accumulate.

## Question sessions and Japanese

A rule should specify a **session recipe**, rather than just “show a card.” For example:

- One fast yes/no check
- One recall question with typed answer
- Two questions in a roughly two-minute session

For the first Japanese version, start with a small set of question types: Japanese word to meaning, meaning to Japanese word, kana reading, and yes/no recognition. Support kana and allow multiple accepted answers where appropriate. Show the answer and a concise explanation after each response; don’t make exact text matching the only way to be marked correct.

Later, the advanced rule builder can add filters such as “only kana,” “only words tagged as difficult,” or “questions due for review.”

## Review scheduling: SuperMemo-inspired

Use a spaced-repetition scheduler to decide **which learning items are due**, while the rules decide **when to present a session**. These are related but distinct jobs: a rule can fire every hour, but the scheduler should choose suitable due items for that session.

You mentioned SM-19 specifically. It is a later SuperMemo algorithm, and its scheduling model is substantially more involved than a simple “repeat tomorrow, then next week” sequence. For an early prototype, keep the scheduler behind a replaceable interface and test the reminder experience with a simple, transparent review queue. Before committing to SM-19, check the implementation and licensing options, or decide whether a different available scheduler is acceptable. Don’t label a simplified scheduler “SM-19.” <citation src="3,5"></citation>

The app should store each review outcome and the information needed to schedule the next review. Keep a clear boundary between the scheduling engine and the popup/rule system so the scheduler can be changed without rewriting the app.

## Locking and accountability

The “punishment” feature can be an **optional app-level lock screen** after an incorrect answer. The app can remain in that state until the user completes a brief review or uses the configured dismissal option.

Recommended options:

- **Standard mode:** lock screen always has a visible dismiss button.
- **Hardcore mode:** hide the normal dismiss button, but require a clear, deliberate opt-in after explaining what the setting does and how to recover.
- **Emergency access:** provide a documented recovery route, such as a system-tray control or keyboard shortcut, unless the user deliberately disables that route too.

For the MVP, keep this strictly inside the app. Do not intercept system-wide keyboard input or attempt to lock the operating system. Those measures are fragile, can interfere with accessibility or urgent use, and are much riskier than a focused app screen. If you later explore stronger enforcement, make it a separate opt-in feature with recovery and safety testing.

## Do Not Disturb and pause

DND should be a global guardrail over all rules:

- Choose days and time windows, such as weekdays during work hours.
- Pause all rules on demand for a chosen duration.
- Resume without triggering a backlog of missed prompts.
- Allow users to decide what happens when a prompt lands right as DND begins; a good default is to suppress it.

Add a global “pause everything” control in the tray/menu bar, plus per-rule enable/disable controls.

## Stages

| Stage | Build | Goal |
|---|---|---|
| **1. Reuse your reminder prototype** | Adapt your existing Bash/mako reminder to show a Japanese test prompt. Add one fixed interval and one random interval rule. | Quickly test whether language prompts fit naturally into your day and whether close-together prompts feel acceptable. |
| **2. Interaction prototype** | Add a basic answer flow, feedback, pause, DND, dismiss, and a simple app-level lock-screen experiment. Keep the deck tiny and the scheduler simple. | Validate the popup, interruption frequency, and lock-screen behavior before building a full app. |
| **3. MVP** | Standalone desktop app; independent fixed and random rules; multiple rules; global DND and pause; small editable Japanese deck; review history; app-level lock with always-available dismiss by default. | Make the core useful and dependable for daily use. |
| **4. Learning system** | Add a replaceable spaced-repetition engine, richer answer grades, Japanese content filters, import/export, and review statistics. | Make sessions adapt to recall rather than merely show prompts on a timer. |
| **5. Advanced mode** | Visual rule builder, session recipes, rule-specific conditions, optional bundling, and carefully guarded hardcore settings. | Give power users flexibility without making basic setup overwhelming. |
| **6. Anki-compatible import/export** | Support bringing in and taking out cards, with clear handling of fields, tags, and review data. | Let Anki users reuse material without making the app an Anki plugin. |

## Prototype using your existing reminder

Your Bash/mako reminder is an excellent starting point. Keep the first prototype narrow:

1. Reuse the existing notification/display mechanism.
2. Add a small local set of Japanese prompts.
3. Implement two independent rules: a fixed 15-minute rule and a random 30–40-minute rule.
4. Log each rule’s scheduled time and actual display time so you can spot timer bugs and prompt collisions.
5. Add answer, dismiss, pause, and DND controls.
6. Try it yourself for several days before adding more question types.

That prototype can answer the most important early question: **Do independent, recurring learning prompts help you study—or do they become interruptions you quickly ignore?**
