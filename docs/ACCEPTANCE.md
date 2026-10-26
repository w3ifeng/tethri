# Verification and release checklist

## Distraction-accountability scope — October 19, 2026

- Removed the prompt's work-help, planning and next-task suggestions. The role now covers brief pushback on distractions and break requests, with no assignment/progress interviews or engagement questions. The initial desktop greeting no longer asks what the user is working on.
- 17 backend tests, TypeScript checks, bundling, native debug build and all desktop self-checks passed. Release app rebuilt and signature verified.
- Conversation deployment 7 is active. Five live synthetic role checks passed: an early break request, asking for one more meme post, an already explained lecture, an explicit essay-planning request, and old coaching text in history. Every reply was at most 240 characters, contained no unnecessary question, and did not expand into the user's work subject or suggest a work step.
- For the meme case, Gemini replied: “Scrolling memes is a distraction from your focus session. You have 15 minutes left until a break is available.” The explained lecture received a brief acknowledgment without a quiz.

## Companion role and break guidance — October 19, 2026

- 17 backend tests passed along with TypeScript checks and bundling. Added coverage for derived policy across all break states, exclusion of user instructions/history from system-policy facts, and explicit unearned-break context delivered to Gemini.
- Conversation deployment 6 is active. The system prompt now defines Tethri's accountability role and tells it how its advice must reflect current eligibility, remaining time, and the configured cap.
- Five live synthetic break-policy cases passed: wanting a break with 15 minutes left, referring to an earlier mistaken approval, requesting 30 minutes when only a five-minute earned break is allowed, trying to restart a 90-second remaining break, and requesting a break while idle. Intent classification, relevant time/cap wording, and requested duration extraction passed.
- For the direct unearned request, live Gemini acknowledged wanting to pause, said the break was not earned and 15 minutes remained, then offered help with the user's essay outline. It did not approve the early break. For the prior mistaken promise it explicitly corrected that advice.
- This revision changes backend role/context delivery only; the existing desktop request contract and local timing/enforcement policy remain compatible.

## Repeated-question regression verification — October 19, 2026

- 26 core scenarios and all desktop self-checks passed. Added coverage for returning to an unresolved resource, preserved replies/deadlines, cancelled in-flight replies, distinct resources/sessions, and no repeated transcript bubbles or automatic chat reopening across five activity switches.
- 14 backend tests, TypeScript checks and bundling passed. The prompt now explicitly continues from explanations in history and addresses complaints about repeated questions.
- Conversation deployment 5 is active. Five live synthetic Gemini checks passed, including a user who had already explained their lecture and asked to stop repeating the question. Gemini continued with the algebra problem set instead of repeating the intervention.
- The release app was rebuilt and its signature verified. Native foreground-window and transient Chrome failure behavior still benefit from manual reproduction on the user's desktop; automated checks cover the underlying state transitions.

## Contextual conversation verification — October 19, 2026

- 22 shared core scenarios and 14 backend tests passed; backend TypeScript checks and bundling passed.
- Native debug build and all app self-checks passed, including provider reply preservation, separate local policy status, complete visible-message history, phase/access context, unsupported-resource handling and rejection of late interpretations.
- Release app rebuilt at `build/Tethri.app`; `codesign --verify --deep --strict` passed.
- Conversation service deployment 4 is active in the existing Little Focus Neon project; existing environment settings were inherited.
- Four live Gemini requests passed via the deployed quota-backed endpoint: essay help after an old video discussion, a study explanation on Reddit, another break request during an existing break, and a question about remaining focus time. All returned the expected intent and no unsolicited YouTube reference.
- These live checks used synthetic messages and domain labels. Manual Chrome enforcement, keyboard focus and visual layout checks remain separate from this conversation validation.

## Automated results

- Native Swift debug build: passed on this Apple Silicon Mac with Command Line Tools / Swift 6.0.2.
- 14 shared core scenarios: passed through the standalone harness. XCTest requires full Xcode on this machine.
- 11 backend contract and quota/mock-provider scenarios: passed on Node 24.
- Backend TypeScript strict check: passed.
- Wrangler deployment dry run: passed, no deployment performed.
- Native dashboard launched and visually inspected; app rules exposed correct installed application names and controls through accessibility.

Core scenarios cover break cap/nonrenewal, early denial, sleep, clarification and request deadlines, stale responses and session changes, canonical lecture grants, homepage/native exception rejection, process/tab/navigation revalidation, encountered break resources, restart/clock recovery, fallback, rules snapshots and hostname boundaries. Backend tests cover contract limits, injection/action rejection, quotas, single-use invitations, hashing/revocation, retry attempt accounting, simultaneous requests, project sharing and logging privacy.

## Required manual checks before distribution

These checks have **not** been certified by automated tests or the UI screenshot. Use disposable tabs and no important unsaved content.

1. Start with Chrome permission denied. App monitoring works; website status says unavailable. Grant access yourself in System Settings, then check again. Revoke it during a session and verify degraded status.
2. VS Code/Notion are uninterrupted. Roblox asks a question. Ignore it for 20 seconds: Roblox is hidden, not terminated. Activate it again: it hides again. Verify failed-hide notice with a mocked or unhideable target.
3. In Chrome normal and incognito windows, open YouTube. Confirm a question normally appears within two seconds without taking typing focus. The API receives no request until text is submitted.
4. Submit “I’m bored.” Confirm only the captured tab closes. Move it between windows while waiting; navigate it to productive work; close it; restart Chrome; switch to another tab; end the session during the request. Confirm a different resource is never targeted.
5. Early break requests fail and show local time remaining. After a full interval, a break becomes quietly available with no forced dialog. Continue working. Request a shorter break, then an excessive one on a later interval: both respect policy. Repeated requests do not renew a running or consumed break.
6. Approve a YouTube lecture. Seek/change tracking parameters: grant persists. Cross the study threshold: no interruption. Autoplay, homepage and Shorts require a new explanation. Native distractions cannot receive lecture grants.
7. During a break, encounter two distracting tabs and a distracting app, then background them. At expiry, only those captured resources are revalidated and acted on. Pre-existing unrelated tabs remain. A last-30-second visual reminder appears quietly.
8. Sleep during work: no sleeping time is earned. Sleep past break expiry: wake enforces the expired encountered resources. Change the wall clock during a live session: deadlines remain monotonic. Quit/relaunch during work, an earned credit and a consumed break: Resume/End appears with preserved allowances.
9. Configure an unreachable backend, simulate provider quota/invalid JSON/timeout, and verify reason controls appear while the timer continues. Prompt injection cannot grant an early break, raise the cap, or issue commands.
10. Drag the creature across displays, unplug a display, switch Spaces and fullscreen apps. Recover it from the menu bar. Verify clicking the input allows typing and automatic questions never steal focus. Test VoiceOver, keyboard navigation, Reduce Motion and Low Power Mode.
11. Listen through at least two complete rain loops for clicks and level discontinuities. Test play/pause, mute, volume, auto-start, break pause, sleep and session-end fades on headphones and speakers. The current audio is synthetic, not a field recording.
12. Run a repeatable one-hour workload with and without the app on an M4 Mac and an older 8 GB Mac. Record resident memory and CPU relative to one core, measuring rain and animation separately. Targets: <150 MB resident, <1% quiet native monitoring, <3% Chrome monitoring. These targets are unmeasured.
13. Build both CPU architectures, sign with Developer ID, notarize and staple. Verify Gatekeeper on another Mac with no development checkout or resource bundles. Confirm no Gemini secret is embedded and routine logs omit message and browsing data.
14. Restrict the pilot to eligible adults/regions under current Gemini terms, validate natural conversation with real API credentials, and collect pilot feedback before releasing.

## Orb UI revision

- Diagnosed the reported checkbox crash from the native crash report: repeated `AppModel.preferences.setter` / `didset` frames exhausted the thread stack.
- Removed self-mutation from that observer; normalization runs on load/session start instead.
- Debug app self-checks pass: repeated checkbox writes, settings persistence, session startup, visible message state, successful mocked conversation, local early-break denial, transcript clearing and offline fallback.
- Floating orb and timer visually inspected; preview accessibility confirms the chat transcript, composer, send button and End Session control are present.
- Live Gemini replies and full keyboard/focus behavior across apps remain manual checks. The new chat was exercised through an injected mock client; no live provider response is claimed.

## Minimal overlay revision

- Visually inspected the isolated synthetic YouTube popup: domain context pill, local question, composer, send button, Close distraction and End session controls are accessible.
- Visually inspected the reduced settings shell and its collapsed privacy/connection sections. The dashboard cards and activity feed were removed.
- Popup content has no common background panel. Native production panels remain nonactivating; the debug preview uses a standard window for inspection.
- The popup estimates text height using native font metrics, caps long transcripts, and repositions its panel relative to the floating ring. Verify across displays and with unusually long replies in the manual focus tests.

## Continuous-chat revision

- 17 app checks pass, including typing before a session, retaining history across Start/End, continuing after End, denying idle break grants, and discarding replies from a previous phase.
- 15 core scenarios pass, including cancellation of general conversation before an intervention reply.
- Verified in the isolated native preview: composer and Start session are visible on launch; a typed pre-session message receives a mock reply; clicking Start keeps the same window and transcript and displays the running timer.
- Provider responses were mocked; live Gemini still requires the deployed backend and server-side Gemini key.

## Neon deployment

Tethri runs on a dedicated Ohio Neon project with a Node.js 24 function. The public HTTPS endpoint was verified: removed invitation routes return 404 and chat returns a validated Gemini reply with HTTP 200 after configuring the encrypted Gemini secret. Postgres reservation checks verified a client quota rejection leaves the project counter unchanged. Live Gemini validation passed with an HTTP 200 response in approximately 1.6 seconds.
