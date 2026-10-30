
## Recommendation: Tauri 2 + TypeScript + Svelte + SQLite

For this app, I’d choose **Tauri 2** for the desktop shell, **TypeScript with Svelte** for the interface, and **SQLite** for local cards, rules, and review history.

Tauri targets Linux, macOS, and Windows from one codebase, with a Rust backend and a web-based UI. It provides system tray and notification capabilities, and supports packaging for the major desktop platforms. Its tradeoff is that it uses each operating system’s webview—WebKitGTK on Linux, WebView2 on Windows, and WKWebView on macOS—so rendering and some platform behaviors need testing on all three. <citation src="1,3"></citation>

| Part | Suggested choice | Why |
|---|---|---|
| Desktop shell | **Tauri 2** | Cross-platform app window, tray, packaging, and native integration |
| UI | **Svelte + TypeScript** | Lightweight UI, straightforward settings and rule editor |
| Local data | **SQLite** | Stores cards, schedules, review events, and settings locally |
| Scheduling and review logic | **TypeScript initially**, isolated behind interfaces | Easier to prototype and change; move performance- or OS-specific pieces to Rust only when needed |
| Japanese content | Local data format with import/export | Keeps the app usable offline and supports Anki-compatible exchange later |
| Builds | CI builds on Linux, macOS, and Windows | Catch platform-specific issues and produce each OS’s installer |

### Key design choice: notification or custom popup

Use the **native notification** as an optional low-interruption reminder, but build the actual question experience as an **app-owned popup window**. Native notifications differ across operating systems and aren’t a dependable place for a multi-question session, answer checking, or an app-level lock screen.

Make that window behave politely: position and focus behavior should be configurable, and the user should be able to choose whether prompts appear in front of other apps. Treat system-wide blocking or keyboard interception as out of scope; the app’s “lock” should be a screen inside the app.

### How your existing Linux prototype fits

Keep the Bash/mako setup as a **throwaway UX test harness**. It’s useful for validating timing, prompt wording, and whether frequent interruptions suit you. Don’t make it the final architecture: mako and Bash are specific to your Linux setup, while the final product needs consistent scheduling, storage, and app behavior on three operating systems.

You can reuse the product logic conceptually, but avoid tying the final scheduler to notification delivery. Have a scheduler decide *which rule is due and what session to show*; then let a platform-specific app layer display it.

### Build plan

1. **Prototype with Bash/mako:** test fixed and random rules, including overlapping prompts; record when prompts were due and shown.
2. **Build a small Tauri proof of concept:** tray icon, settings window, one app-owned prompt window, and local persistence.
3. **Test the risky platform details early:** app startup, sleep/resume behavior, tray interactions, notifications, and popup focus on Linux, macOS, and Windows.
4. **Add the real rule and review models:** keep scheduling rules separate from question selection and the SuperMemo-inspired review scheduler.
5. **Package and distribute:** produce native builds in CI and test actual installers on each OS.

**My short version:** build the final app in Tauri, but validate the learning loop in your existing mako prototype first. The main technical risk isn’t drawing the settings screen—it’s making timed, interactive popups behave predictably and considerately across three different desktop environments. <citation src="1,3"></citation>
