# Tethri

Native macOS 13+ focus companion built from [PLAN.md](PLAN.md). SwiftUI and AppKit desktop app, ScriptingBridge Chrome automation, local rain audio, and a TypeScript Neon Function with Postgres quota accounting.

## Run the Mac app

```sh
scripts/build-app.sh
open "build/Tethri.app"
```

Requires Swift 5.9+ / Apple Command Line Tools (Swift 6 recommended). SwiftPM downloads the pinned Sparkle updater framework on the first build. For both Apple Silicon and Intel:

```sh
UNIVERSAL=1 scripts/build-app.sh
```

The unsigned development build is ad-hoc signed for local use. The privacy notice is available in Settings; no approval checkbox is required to start a session. Use **Check Chrome Automation permission** with Chrome open to request access. The first check may show the macOS consent dialog. Allow it yourself to enable website enforcement. App monitoring works without Chrome access.

The app opens directly to the Focus timer page. Set a duration, optionally enter a goal, then click Start session (or Resume session for an interrupted session). The menu bar also opens this timer page. Once a session starts, click the small floating orb to open its chat. The timer appears above the orb during a session; starting a session closes the control window. Try “This is my lecture”, “I need five minutes”, or “I’m bored” when questioned. Conversation requires a configured Gemini service; without it, submitting a message exposes the local reason controls. The local timers work without a backend. An earned break must still be requested; it never interrupts work automatically.

## Site awareness

During a session, Chrome's active domain is categorized as Productive, Unproductive, or Neutral. Built-in rules cover common work, learning, social, and entertainment sites; unknown sites stay neutral. These are editable defaults based on typical use, not judgments about a page's contents. Rules shows all built-in sites and lets you override or reset them. Custom rules take priority, including explicit Neutral choices, and changes apply to the next session.

The chat displays the current app/domain and category. When you send a message, the app refreshes Chrome's active tab and sends its domain and category to Gemini, including before a session starts. While typing in Tethri, it uses the last foreground app and refreshes that browser's active tab. It uses the existing bounded label field; full addresses, paths, queries, and page content are not sent. If the current tab cannot be read, it sends app context rather than an older domain. Productive and neutral sites do not trigger interventions. Unproductive sites use the existing question, break, and validated enforcement flow; a granted YouTube study video is identified as allowed for study. No model requests run just to classify sites. Website awareness requires Chrome Automation access.

## Backend setup

Requires Node 24+, Neon Functions in a supported region, and a Gemini API key. The app already includes the deployed Tethri service address. No invitations or accounts are required for chat.

The backend is deployed to the **Little Focus** Neon project (the existing service for Tethri) in Ohio. `backend/neon.json` records the project, branch, function slug and public URL. The separate talkly project is unchanged.

```sh
cd backend
npm ci
npm run check
npm test
npm run build
```

Apply `backend/schema.sql` to the function branch's Postgres database before deployment. It creates only the `little_focus` schema, quota table and reservation function. Deploy `backend/function.zip` to the `littlefocus` Neon Function with Node.js 24. Neon injects `DATABASE_URL`; set `GEMINI_API_KEY` as an encrypted function environment variable. Keep local keys in the ignored `backend/.env.local` file. Never put the Gemini key in the desktop app.

The default model is `gemini-3.5-flash-lite`. Function variables `PROJECT_RPM`, `PROJECT_RPD`, `INSTALLATION_RPM` and `INSTALLATION_RPD` configure quotas (defaults 14, 450, 5 and 100). Each provider attempt, including retries, reserves project and client quotas in a single Postgres transaction using an advisory lock. UTC minute/day windows apply. Client identifiers are public fairness hints, not authentication; the shared project limit cannot be bypassed by changing one. Only identifier hashes and quota counts are stored.

The bundled address lives in `scripts/Info.plist`. To override it for a build:

```sh
BACKEND_URL=https://your-function-host scripts/build-app.sh
```

The service address is configured at build time. A maximum of two provider attempts shares the backend's 7.5-second budget and the app's eight-second request deadline. Database errors fail closed. No prompts or transcripts are stored in Postgres.

## Verification

```sh
python3 scripts/test-core.py      # core policy tests, works without Xcode
zsh scripts/test-automation.sh   # Chrome collection race and exception regression checks
cd backend && npm test && npm run check
```

With full Xcode installed, `swift test` runs the policy suite through XCTest. The standalone harness uses the same test methods when only Command Line Tools are available. Backend handler tests use an in-memory quota adapter and mocked provider responses. The deployed Postgres reservation function was also checked for quota rejection and atomicity. They do not contact Gemini.

See [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for manual release checks and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for policy and privacy details.

Chrome window and tab lists are evaluated into detached arrays before enumeration. A small Objective-C bridge catches collection exceptions that Swift cannot catch, so a list changing during a read reports a temporary monitoring failure instead of terminating Tethri. The next monitoring pulse retries; tab closure still revalidates the process, tab ID, resource and session authorization.

## Signing and release

```sh
DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)' UNIVERSAL=1 scripts/build-app.sh
NOTARY_PROFILE='your-keychain-profile' scripts/notarize.sh
```

These require your own Apple Developer membership, certificate, and previously configured notarytool profile. The scripts do not create signing credentials or publish a build. Distribute the resulting stapled `build/Tethri.zip` manually only after the acceptance checks and adult pilot.

## App updates

Tethri uses Sparkle 2.10.0 to check daily for updates and offer an install-and-relaunch dialog. **Check for Updates…** is available in the menu bar, application menu and Settings. Settings shows the installed version and lets users disable automatic checks. Scheduled checks skip active focus sessions; manual checks remain available. Installation requires the user's choice, and the existing session checkpoint is saved on termination.

The public feed URL and Ed25519 public key are in `updates.json`, configured for `w3ifeng/tethri` on GitHub Releases. The private signing key stays in the macOS login Keychain under Sparkle's `tethri` account. GitHub must have a published release containing `appcast.xml` before checks can succeed. Previews and command-line self-tests do not start the updater.

To prepare the next release locally:

```sh
APP_VERSION=0.1.2 BUILD_NUMBER=3 zsh scripts/prepare-github-release.sh w3ifeng/tethri
```

Upload the generated ZIP and `appcast.xml` from `build/updates` to a GitHub release using the printed tag. Publish it as a normal release marked **Latest**. Preparing the release does not upload or publish anything. To sign and notarize with Apple as well, provide `DEVELOPER_ID` and `NOTARY_PROFILE` to the same command.

Users must install the first updater-enabled build manually. Later updates are verified against the embedded public key before extraction, then installed by Sparkle. Ad-hoc builds can use signed Sparkle updates, but still have macOS first-install trust prompts; this does not provide Apple notarization.

See [docs/UPDATES.md](docs/UPDATES.md) for setup, key backup, publishing and an installation acceptance test. To verify release signatures:

```sh
python3 scripts/test-updater.py
UNIVERSAL=1 scripts/build-app.sh
python3 scripts/test-updater.py --integration
```

## Current limits

- The Neon backend is deployed, its Gemini key is configured server-side, and live Gemini conversation has been verified. Apple signing credentials remain external.
- Study rain uses a CC0 window-rain recording by Ylmir, softened and normalized for quiet listening with a seamless 43-second stereo loop and one-second playback fades. Source and regeneration details are in `scripts/audio/README.md`.
- Browser automation cannot prevent the first load and is not an atomic navigation lock. No tamper-resistant blocking, webpage inspection, or support for browsers other than Chrome.
- Live Chrome behavior, panel focus across Spaces/displays, real audio output, and power targets need the manual checks. No energy or pilot results are claimed.
- Interrupted breaks preserve continuous-clock deadlines across app restarts during the same boot. After a reboot, remaining time uses the saved wall-clock expiry, capped by the configured maximum; simultaneous system clock rollback and reboot cannot be resolved perfectly without a trusted external clock.

## Orb and chat UI checks

The desktop companion is a 66-point multicolor orb with a compact timer pill above it. An explicit orb click opens a fixed-size chat with an in-memory transcript, scrollable replies, a thinking state, composer and End Session control. Automatic questions open the chat without requesting keyboard focus. The control window is available from the menu bar and closes when a session starts.

The preferences observer no longer mutates its own published value, which previously caused stack overflow when the 18+ checkbox or another setting changed. Normalization runs on settings load and session capture.

```sh
CONFIGURATION=debug scripts/build-app.sh
.build/debug/FocusCompanion --self-test
scripts/build-preview.sh
open "build/Tethri Preview.app"
```

The debug-only self-test exercises 100 repeated preference writes, persistence, session startup, the chat send/thinking/reply sequence, early-break denial, transcript clearing and offline fallback. The separate preview uses a mock conversation client, separate preferences, and disables app/browser monitoring. It never contacts Gemini. Preview and self-test fixtures are excluded from release builds. Real Gemini responses still require backend setup.

## Reference-based glass design

The main window and chat use a dark, blurred glass theme with colorful yellow, orange, lavender, green and blue focus cards. The blue filament ring is drawn from shared native geometry in `RingGeometry.swift`; it appears in the floating companion, dashboard, chat, menu bar and app icon. No continuous animation loop is needed.

To regenerate the vector-derived macOS icon resources:

```sh
scripts/generate-icon.sh
```

`FocusIcon.icns` includes standard and Retina sizes; `FocusIcon.png` is the 1024-pixel artwork. Both build scripts include them automatically. The app's `Info.plist` registers the icon for Finder and Launch Services. The UI preview uses a separate standard chat window for reliable snapshots; the production chat remains a nonactivating floating panel.

The dashboard and chat now use genuinely nonopaque windows with behind-window blur and a light tint. Settings → Background opacity adjusts both surfaces (default 20%). The ring artwork and app icon have transparent backgrounds. macOS Reduce Transparency can override native blur rendering.

## Minimal settings and distraction overlay

The current UI keeps the reference's translucent shell while removing the dashboard cards, activity rail, marketing headings and duplicated stats. The compact window has Session, Rules, Sound and Settings tabs; privacy details are in a disclosure; the conversation service is configured by the app.

Distraction conversations use independent floating bubbles with a transparent space between them, dark companion replies, blue user messages, an optional captured-domain label, a ring beside the composer and a blue paper-plane send button. The popup fits its content within a bounded scroll area. Close/Hide distraction uses the existing validated enforcement path; the UI does not claim that a tab was closed before enforcement.

The debug preview starts with a synthetic YouTube intervention. All OS enforcement is disabled for fixtures, as well as monitoring and network conversation calls. Real monitoring, policy deadlines and permission behavior are unchanged in the release app.

## One continuous chat

The Focus timer page is the default surface on launch and app reopen. The floating companion appears when a session starts; clicking it during a session opens chat, and clicking it while idle returns to the timer. The menu bar offers the timer and chat. The chat composer works before, during and after a session, preserving the conversation across session transitions. Distraction questions are added to that thread too.

The Focus tab contains the optional goal, duration dial and Start/Resume button. Rules, Sound and Settings provide configuration. Pre-session messages use an ephemeral conversation identifier, the same bounded text-only backend transport and deadline, and cannot grant breaks or OS access. Changing session phase cancels stale replies. The last 40 visible messages and six provider-context messages stay in memory across session transitions and are discarded on app exit, never persisted as a transcript.

The isolated preview was used to type and receive a mock reply before a session, then start the timer from the same chat while preserving the prior messages. App checks cover pre/post-session conversation, stale replies, offline behavior and local break restrictions.

Study-related conversation without a captured distraction and distraction replies preserve Gemini's conversational text. Local policy still decides earned breaks, specific-video exceptions and enforcement; those decisions cannot be changed by a model reply. The preview app uses mock replies, while the normal Tethri app uses the configured Gemini service.

## Contextual conversation

Gemini receives the current session phase, remaining break time, goal, current app/domain category, captured distraction label and supported study-access capability. Current foreground activity and a captured distraction are distinct. Context contains no full URLs, page content, process IDs or tab IDs. The provider sees the last six visible messages, including session transitions and local policy outcomes, so old discussions are not mistaken for the current session.

Tethri's role is narrowly to push back on going off task and explain distraction/break rules. It does not tutor, plan work, ask about assignment details or progress, or suggest a next paragraph or problem. The goal is background for judging relevance, not a topic to discuss. Replies use one or two short sentences (instructed maximum 240 characters); a question is appropriate only when a missing fact is necessary to judge a flagged resource's relevance. The initial greeting explains this role without asking about the user's work.

Every provider request includes a separate system-policy snapshot derived from validated timing fields: no session, break not earned, break earned, break already running, or unknown phase for a legacy client. It includes the exact remaining focus/break time and break cap, without copying user-authored text into the system instruction. Wanting a break or referring to an earlier mistaken approval does not make an unearned break available; Gemini should explain the remaining time and push back on leaving early without pivoting into work coaching.

Chat preserves Gemini's conversational reply for every intent. Break and study-access outcomes appear as a separate session-status line in the reply bubble; the local engine remains authoritative. A work-help request has the chat intent and receives a brief explanation of Tethri's accountability role. Unrelated websites do not produce a preset instruction to open a YouTube lecture. Unavailable conversation still exposes local reason controls. A response rejected by the engine after its deadline is not displayed as a successful reply.

The backend accepts older requests without the optional context field. Deploy the updated backend before using the updated desktop app, which sends that field. For an optional live check using only synthetic examples (requires a nonempty local Gemini key):

```sh
cd backend
node --env-file=.env.local --experimental-strip-types scripts/check-conversation.ts
```

To check the deployed quota-backed service instead, set `CONVERSATION_URL` to the service's HTTPS base address and run `node --experimental-strip-types scripts/check-conversation.ts`. This makes five real requests using synthetic context and prints their replies, including continuing after an already answered intervention question.

Append `--break-policy` to run a separate five-request live suite covering unearned requests, earlier mistaken approval, an earned break above the cap, restarting a running break, and idle conversation.

Append `--accountability` for five live role checks: an early break request, bargaining for one more post, an already explained lecture, a work-planning request outside Tethri's scope, and earlier work-coaching messages in history. The suite checks short replies without work coaching or unnecessary questions.

Pending distraction questions remain associated with their exact resource when switching activities. Returning resumes the same question, reply and deadline without adding another bubble or reopening chat. Tethri's own windows and failed Chrome reads do not count as resource changes. Initial questions identify the app/domain instead of asking a generic “What are you doing?”
