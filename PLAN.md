> Implementation update: conversation now uses a public Neon Function and Postgres quotas; the invite-only Cloudflare design below is historical. See README.md for current setup.

# Focus Companion — v1 implementation specification

## 1. Product and scope

Build a lightweight Mac desktop app with a small animated character that helps people stay focused. It recognizes distracting apps and websites, asks why the user opened them, and manages study permissions and earned breaks through typed conversation.

**Confirmed product decisions**

- Mac first; support Apple Silicon and Intel Macs running macOS 13 or later.
- Optimize for older computers and low battery use, not only the developer’s M4 Mac with 16 GB RAM.
- A friendly but firm desktop creature with speech bubbles.
- Gemini **3.5 Flash Lite** handles conversation.
- Conversation is the normal experience. Reason-selection buttons appear only when AI is unavailable.
- No Chrome extension. Use macOS Automation permission to inspect and close Chrome tabs.
- Close distracting browser tabs when access is denied; hide distracting desktop apps.
- Default to 25 minutes of study followed by an available five-minute break, with configurable timings.
- Breaks are optional and quiet. Never interrupt someone simply because they have earned a break.
- First release is a small, invite-only adult beta.

**v1 boundaries**

Support Chrome websites and native Mac apps. Defer Windows, other browsers, screen recognition, voice conversation, local AI models, multiple characters, and tamper-resistant blocking.

The app recognizes applications and website addresses; it does not understand everything happening on screen or prove someone is working.

## 2. User experience and focus rules

### Desktop character

Use a small, original creature drawn with native shapes for the initial implementation. Start with a soft green, rounded character and simple facial expressions.

- Default size approximately 120 × 140 points, draggable between displays.
- Float above ordinary windows and support macOS Spaces.
- Provide idle, focusing, questioning, thinking, break, and celebration states.
- Use occasional blinks and short reaction animations. Avoid constant movement.
- Clicking the character opens its conversation bubble.
- Automatic questions must not steal keyboard focus. Focus the text input only when clicked.
- Provide menu-bar access to start/end sessions, settings, audio controls, and recovering an off-screen character.
- Respect Reduce Motion and support keyboard navigation and VoiceOver.

The character’s tone should be supportive, concise, and firm. It should never shame the user or pretend to verify whether an explanation is truthful.

### Starting and continuing a session

Before starting, the user can enter an optional study goal and configure:

| Setting | Default | Allowed range |
|---|---|---|
| Study interval | 25 minutes | 5–180 minutes |
| Maximum break duration | 5 minutes | 1–30 minutes |
| Rain | Off | On/off and volume |
| Productive/distracting apps and sites | Suggested initial lists | Editable |

Suggest VS Code and Notion as productive, Roblox Player as distracting, and YouTube as distracting. Match applications by bundle identifier after resolving the installed app. Treat unclassified apps and websites as neutral.

Session rules are captured when the session starts. Changes to timing or classifications take effect in the next session.

A session continues until the user explicitly ends it. Completing a study interval does not end the session or automatically start a break.

### Earning and taking breaks

- Begin with no available break.
- Accumulate study time while the session is active, the computer is awake, and the user is outside a known distraction or unresolved intervention.
- Approved lecture viewing counts toward study time. Neutral applications also count; v1 does not attempt to measure effort.
- After the configured interval, make one break available.
- Show this quietly on the character or its status indicator. No alarm, forced dialog, sound, or automatic break.
- The user can keep working indefinitely. Break credits do not accumulate.
- A typed request starts an earned break. Requests made too early are denied with the time remaining.
- Allow a shorter requested break; cap longer requests at the configured maximum.
- Starting a break consumes the credit. Ending it early forfeits unused time.
- After a break ends, require another complete study interval before the next break.
- During a break, configured distractions are allowed without repeated questioning.
- Show a countdown, with a quiet visual reminder 30 seconds before expiry.
- At expiry, close tracked distracting tabs and hide tracked distracting apps. Resume study time.

Keep an explicit **End Session** control available. This is voluntary focus assistance.

### Distraction conversations

When a distracting target becomes active outside an authorized break or lecture grant, show a local question immediately, such as:

> “Is this for your study goal, or do you need a break?”

The opening question does not require an API call. Send an AI request only after the user submits text.

| User explanation | Required behavior |
|---|---|
| “I’m bored.” | Encourage returning to the task; close the tab or hide the app. |
| “I need five minutes.” | Start a break if earned; otherwise explain the remaining study time and deny access. |
| “Can I have another break?” | Apply the same earned-break rules. Repeated requests cannot override them. |
| “This is my lecture.” | Allow the specific YouTube video when a valid video target is available. |
| “I need YouTube.” | Ask a short follow-up to distinguish study from entertainment. |
| Unrelated conversation | Respond briefly without granting access. |

**Waiting behavior**

- Allow 20 seconds to submit an explanation.
- If ignored, close the captured distracting tab or hide the distracting app.
- Submission suspends that deadline while the AI request runs, for at most eight seconds.
- A clarification starts another 20-second response window.
- Keep one intervention visible at a time.
- Cancel an obsolete intervention when the user leaves the target and returns to allowed work.
- Never apply a response to a different tab, app instance, or session.

### Lecture permissions

A lecture explanation grants access to **one video in the captured tab**, rather than all of YouTube.

- Identify videos by canonical YouTube video ID.
- Ignore harmless tracking parameters and playback-position changes.
- Changing to another video, the homepage, Shorts, or a browsing page requires another explanation.
- If the user is on the homepage, ask them to open or paste the specific lecture video.
- The approved video can continue beyond the 25-minute study threshold without interruption.
- A grant expires when its tab navigates away from that video, closes, or the session ends.
- Autoplay to another video requires a new explanation.
- Desktop apps classified as distracting do not receive automatic study exceptions in v1; classifications can be changed before another session.

### Rain sounds

Bundle a properly licensed, seamless rain recording and play it locally.

- Volume slider, mute, and play/pause controls.
- Optional automatic playback when a session starts.
- Gentle one-second fade on start and stop.
- Continue during breaks by default; provide a setting to pause during breaks.
- Stop on session end and pause during system sleep.
- No audio streaming, microphone access, or AI calls.

## 3. Architecture, interfaces, and enforcement

### Native Mac application

Use **Swift, SwiftUI, AppKit, ScriptingBridge, and AVFoundation**.

Separate these responsibilities behind testable interfaces:

- `SessionEngine`: timing, break eligibility, session transitions, and policy decisions.
- `ActivityMonitor`: application-switch events and Chrome snapshots.
- `EnforcementController`: validated tab closing and app hiding.
- `CompanionClient`: conversation requests and error handling.
- `CharacterPresenter` and `RainPlayer`: presentation and local audio.

Use a transparent, nonactivating `NSPanel` for the character and conversation. Track whether the chat input has keyboard focus separately from which application macOS reports as frontmost.

### Detecting apps and websites

Use `NSWorkspace` application-activation events for app detection.

For Chrome:

- Request macOS Automation permission during onboarding.
- Use ScriptingBridge to read active tab identity and URL, and close specific tabs. Chrome exposes these capabilities through its scripting interface. [Chromium scripting dictionary](https://chromium.googlesource.com/chromium/src.git/+/lkgr/chrome/browser/ui/cocoa/applescript/scripting.sdef)
- Query immediately when Chrome becomes foreground, then once per second while a session is active and Chrome remains foreground.
- Stop recurring browser queries when Chrome is backgrounded or the system sleeps.
- Use one serial automation worker, one operation in flight, and a short timeout.
- Do not repeatedly launch `osascript`, inspect screenshots, execute webpage JavaScript, or read page contents.
- Website detection should normally react within two seconds. It cannot prevent the first page load or moment of playback.
- Apply rules to normal and incognito Chrome windows where automation exposes them; keep their metadata transient.
- Match domains at hostname boundaries, including subdomains. `youtube.com.example.org` must not match `youtube.com`.

If permission is denied, revoked, or Chrome cannot be inspected, keep app detection working and visibly mark website enforcement unavailable.

### Safe enforcement

Capture browser process identity, tab ID, canonical target, session ID, and intervention ID.

Immediately before closing:

1. Confirm that the session and intervention remain current.
2. Locate the captured tab by ID, including if it moved to another window.
3. Read its current URL.
4. Confirm that it still represents a denied or expired distraction.
5. Close that tab only.

Never use keyboard shortcuts, tab indexes, or “close the current tab.” Revalidation reduces navigation races; it is not atomic blocking.

Track distracting resources encountered during breaks. At expiry, act on those resources even if backgrounded, after revalidation. Do not sweep through unrelated tabs that existed before the session.

For desktop distractions, call `NSRunningApplication.hide()` and verify the result. Re-hide denied apps if the user activates them again. Hiding leaves the application running and can leave its audio playing; report a failed hide without force-quitting it. [Apple hide API](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide())

### Session data and timing

Maintain these core records:

- **Session:** ID, settings snapshot, accumulated study time, break eligibility, current phase.
- **Target:** app/process identity or browser/tab identity and canonical resource.
- **Intervention:** ID, target, response deadline, request generation.
- **AccessGrant:** target, permission type, and expiry or invalidation condition.

Use monotonic time for live deadlines. Suspend study accumulation during sleep; break deadlines continue across sleep and are checked on wake.

Persist settings and a minimal interrupted-session checkpoint locally. After an app restart, show **Resume / End Session**. Resuming must preserve earned time and consumed breaks rather than refill allowances. Revalidate saved targets before enforcement.

Do not persist browsing history or chat transcripts by default.

### AI and backend

Use **`gemini-3.5-flash-lite`**, text input/output, minimal thinking, and structured output. No search, computer-use, vision, or live audio tools. The model supports structured responses. [Model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite)

AI interprets explanations and supplies conversational wording. Local code owns permission grants, timers, limits, and operating-system actions.

Use a small TypeScript Cloudflare Worker backend with a SQLite-backed Durable Object for invite credentials and shared quota accounting.

Public endpoints:

- `POST /v1/installations/redeem`: exchange a one-use beta invitation for an installation credential.
- `POST /v1/companion/interpret`: interpret a typed message and return a validated response.

The interpretation contract contains:

```text
Request:
  requestId, sessionId, interventionId
  message, bounded recent conversation
  app/domain label, optional study goal
  break eligibility and relevant timing

Response:
  matching request identifiers
  intent: break_request | study_exception | distraction | clarify | chat
  requestedBreakMinutes: number or null
  reply: plain text
```

Keep exact tab identities and full URLs on the Mac. Send only the app/domain label and minimal session context.

Implementation requirements:

- Store the Gemini key in backend secrets, never in the desktop binary. [Google key security guidance](https://ai.google.dev/gemini-api/docs/api-key)
- Store installation credentials in macOS Keychain; store credential hashes server-side and support revocation.
- Limit messages to 1,000 characters and context to six recent messages.
- Validate JSON, enums, numeric fields, and lengths.
- Render model text as plain text.
- Recheck local policy when responses arrive. Model prose never authorizes an action.
- Display actual permission status and countdowns from code.
- Use an eight-second total deadline, with at most one transient retry inside it.
- Ignore stale responses after session or target changes.
- Log latency, request counts, token usage, and error categories; omit conversation text and browsing metadata.

Begin with configurable ceilings of 14 provider requests/minute and 450/day across the project, plus 5/minute and 100/day per installation. Count retry attempts. These are operating defaults beneath the supplied 15 RPM / 500 RPD dashboard limits, not guaranteed provider capacity. [Google rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)

**Minimal fallback:** on offline, quota, timeout, or invalid-response errors, show reason buttons for break, lecture, or return to work. Apply the same policy engine. Existing timers and enforcement continue. Keep this secondary to the conversational experience.

## 4. Performance, privacy, and release defaults

**Power and resource targets**

- No local language model, continuous screen capture, or continuous cloud analysis.
- No AI calls merely because the foreground app changed.
- No permanent network connection or idle heartbeat.
- Pause animations when hidden or asleep.
- Use static presentation under Reduce Motion and Low Power Mode.
- Target under 150 MB resident memory, under 1% average CPU while quietly monitoring native apps, and under 3% while monitoring Chrome, measured relative to one CPU core.
- Measure rain playback and animation separately. These are acceptance targets to verify, not assumed results.
- Compare a repeatable one-hour study workload with and without the companion on an M4 Mac and an older 8 GB Mac.

**Privacy and audience**

Explain during onboarding that Chrome Automation reads active website addresses and can close distracting tabs. Request neither Screen Recording nor Accessibility permission for v1.

Explain that typed conversation is sent to Google. Under unpaid Gemini terms, inputs and outputs may be used for improvement and human review; avoid sending sensitive content. Limit the initial beta to adults in supported regions where unpaid service is permitted. Google currently requires paid services for API clients offered in the EEA, Switzerland, or UK. [Gemini terms](https://ai.google.dev/gemini-api/terms)

**Distribution**

Ship a Developer ID signed, notarized, non-sandboxed Mac app through direct download. Keep Windows and Mac App Store distribution for later evaluation. Apple’s program and signing requirements are separate from free AI usage. [Apple Developer Program](https://developer.apple.com/programs/)

Provide manual beta updates initially. Keep the model identifier and backend quota ceilings configurable server-side.

## 5. Acceptance tests and implementation order

**Required acceptance scenarios**

1. VS Code and Notion remain uninterrupted; Roblox triggers a question.
2. Opening YouTube or switching to a distracting tab triggers detection within the normal two-second target.
3. Ignoring a question for 20 seconds closes the correct tab or hides the correct app.
4. “I’m bored” denies access; an early break request cannot bypass the study interval.
5. Earning a break produces no alarm, forced break, or interruption to continued work.
6. An earned break starts on request, expires correctly, and cannot be immediately renewed.
7. An approved lecture continues past the study threshold; navigation or autoplay to another video triggers a fresh check.
8. Moved tabs, closed tabs, productive navigation, restarted Chrome, and delayed AI responses never intentionally target a different tab.
9. Sleep/wake, app restart, clock changes, and simultaneous requests do not duplicate breaks or extend running grants.
10. Offline and quota errors expose fallback controls without stopping local timers.
11. Permission denial and failed hiding display an honest degraded state.
12. Prompt injection cannot alter session rules, issue operating-system commands, or grant extra time.
13. The character does not steal typing focus and remains recoverable across displays, Spaces, and fullscreen modes.
14. Rain loops cleanly, respects mute/volume settings, and stops correctly.
15. No Gemini secret ships in the app, and routine logs contain no raw conversations or browsing history.

Use unit tests for the session policy and URL matching, mocked integration tests for automation and backend failures, and manual Mac tests for real Chrome behavior, window focus, audio, and energy use.

**Build order**

1. Native character, menu bar, configurable session engine, and rain.
2. App monitoring, Chrome Automation, and safe enforcement.
3. Gemini conversation through the backend, lecture grants, and break requests.
4. Minimal outage fallback, recovery behavior, accessibility, and performance tuning.
5. Signed beta packaging, end-to-end verification, and a small adult pilot.

Release only after the pilot confirms that conversations feel natural, breaks respect the user’s flow, and enforcement targets the intended distraction.
