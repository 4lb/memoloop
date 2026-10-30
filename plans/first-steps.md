
Start with the **Linux prototype**, not the full cross-platform app. The goal is to test the core loop—independent timers, overlapping prompts, and whether the interruptions feel useful—before choosing how much to build around it.

### Step 1: Freeze the prototype scope

For the first version, support just:

- Two independently running rules:
  - Fixed: every 15 minutes
  - Random: every 30–40 minutes
- One Japanese prompt per popup
- Answer, dismiss, and pause-all controls
- A simple DND window
- A log of when each prompt was due and shown

Skip SuperMemo scheduling, Anki import, hardcore mode, accounts, and fancy settings for now. Use a tiny hand-written set of Japanese prompts.

### Step 2: Define what a rule means

Use a simple rule shape like this:

```json
{
  "id": "random-short",
  "enabled": true,
  "interval": {
    "type": "random",
    "minMinutes": 30,
    "maxMinutes": 40
  },
  "session": {
    "questionCount": 1,
    "estimatedMinutes": 1
  }
}
```

Each rule should keep its own next due time. Decide now that a prompt **does not get queued** if it falls during DND or while the app is paused. That keeps missed prompts from piling up.

For the prototype, if two rules fire close together, show both separately and log them. Later, you can add an optional “bundle nearby prompts” setting.

### Step 3: Adapt your existing script

Keep the popup and timing code that already works. Add only the pieces needed to test the scope:

1. Represent each schedule as a separate rule.
2. Calculate the next due time independently for each rule.
3. Check pause and DND before displaying a prompt.
4. Record rule ID, scheduled time, actual display time, and answer/dismiss result.
5. Add a way to pause all rules and resume them.

Use a monotonic timer while the script is running where practical, and recalculate due times after restart. Don’t worry about perfect persistence yet; a small JSON file is enough.

### Step 4: Try it in real life

Run the prototype for several days. After each session, note:

- Was the prompt well-timed?
- Did overlapping prompts feel okay or annoying?
- Did you answer, dismiss, or ignore it?
- Was the popup too disruptive?
- Did DND and pause behave as expected?

The most valuable result is a better schedule and interruption design—not a larger feature list.

### Step 5: Then make the Tauri proof of concept

Once the prompt loop feels right, build the smallest Tauri app that proves the cross-platform risks:

- Tray icon and pause control
- Settings window
- App-owned question popup
- Local storage
- Startup and sleep/resume behavior

Test that on Linux, macOS, and Windows before investing in the full rule editor.

**Next practical move:** paste your current Bash script and, if separate, the mako configuration. I can help turn them into the first prototype plan and adapt the scheduling logic without throwing away what already works.
