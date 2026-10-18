# Ember for iPhone: status, alerts and controls for a Mac you walked away from

Date: 2026-10-18. Status: agreed with the owner in conversation ("finish the
plan and start working"). What the app is for, its main screen, the lock
screen and the notifications were agreed with mockups; the owner handed the
technical calls to Claude and chose the relay and the private repo. Closes the idea in
liviulica/ember#1 ("Phone push when a lid session is about to end or has
ended") in a bigger form: the owner wants "our own app", not a webhook.

## Why

Ember keeps a Mac awake with the lid closed so coding agents keep working
while the owner is away. Everything Ember says goes to the Mac's own screen,
which is shut. On 2026-10-15 a Lid mode ended as planned, the Mac slept under
running agents and nothing warned the owner. Today there is no way to know,
from somewhere else, whether the Mac is still working, still online, how long
it has left or what the agents are doing, and no way to act on it.

## What it is

An iPhone app from ChargingPixels, on the App Store, that pairs with Ember on
one or more Macs. For anyone who closes the lid and walks away while work
keeps running. It answers "is my Mac still doing its job?" from anywhere, and
lets them extend, stop or fix the session.

The first release is free. A one-time purchase comes in a later phase
(owner). Nothing in this design may need a recurring bill to work at small
scale.

## Goals

1. **It's working, at a glance.** Alive, online (Wi-Fi or iPhone hotspot),
   time left, Mac health (battery, charging, heat, memory), and what each
   coding agent is doing.
2. **Warned in time, on the phone.** "Sleeps in 5 min", "ended, Mac
   sleeping", "lost internet / went quiet", "battery low", "running hot",
   "an agent is waiting for you". Each one arrives within seconds.
3. **Act from the phone.** Extend and Stop (Stop with the lid closed puts
   the Mac to sleep, so it is also the fix for overheating or a draining
   battery). From the app, from the lock screen and from a notification.
   When the Mac cannot be reached, the app says what to check instead.
4. **On the lock screen without opening the app.** Starting Lid mode or
   Screen mode on the Mac puts a live countdown on the paired phone's lock
   screen (a Live Activity), updated when the session is extended and removed
   when it ends.

## Non-goals (this release)

- Starting a mode from the phone. The Mac starts sessions; the phone watches
  and steers them.
- The one-time purchase, a paywall, receipts (later phase).
- Syncing Ember's Mac settings between Macs, or editing them from the phone.
- Agents other than Claude Code (built so others can be added).
- iPad, Apple Watch, widgets on the home screen, Android.
- History and charts of past sessions.

## Anti-goals (failure even if it technically works)

- **Late warnings.** A "sleeps in 5 min" that arrives after the Mac slept is
  worse than none. Delivery must be seconds, not "eventually".
- **Leaking the owner's work.** Project names, agent messages and the Wi-Fi
  name must not be readable by ChargingPixels' server or anyone between the
  Mac and the phone.
- **Making Ember less safe.** The phone can never do more than the menu bar
  can, and a lost phone or a leaked server must not be able to keep a Mac
  awake forever or run anything on it.
- **Accounts.** No sign-up, no email, no password.
- **Slowing the Mac or the agents.** Reporting must not block Claude Code or
  wake the Mac more than it already is.

## The experience

### Pairing

1. Ember on the Mac: Settings → **iPhone** → "Pair an iPhone". Ember shows a
   QR code and a one-line explanation.
2. The iPhone app's first screen explains it needs Ember on a Mac, with
   "Scan the code in Ember" and "Try the demo".
3. Scan. Both sides show the pairing ("Liviu's iPhone" in Ember, "Liviu's
   MacBook Pro" on the phone). The phone asks for notification permission at
   this point, with the reason.
4. Several Macs: scan each one. Several phones per Mac: allowed. Either side
   can unpair; unpairing on one side removes it on the other the next time
   they connect.
5. **Lost phone:** from any other paired phone, "Remove this iPhone" on the
   Mac's page; the relay disables that phone's device secret at once (no
   need to open the lid), and the Mac deletes its key when it next
   connects. From the Mac: Settings → iPhone → Unpair.

### Main screen (agreed mockup, "v2")

Mac picker at the top when more than one Mac is paired. Then, top to bottom:

- **Header:** Mac name, a status line ("Working, online via hotspot";
  "Working, no internet"; "Asleep since 02:40"; "Not heard from for 4 min"),
  a large countdown ring ("3:12 left of 8 h") and two buttons, **Extend**
  (+1 h, long-press or menu for +2 h / +4 h) and **Stop**.
- **Health box:** Internet (Wi-Fi name or "iPhone hotspot" or "Ethernet" or
  "None"), Battery (% and charging), Heat (Normal / Warm / Hot / Critical),
  Memory (Normal / Tight / Critical). Anything not normal is coloured and
  tappable for what to do.
- **Agents box** (shown whenever sessions run, with or without a mode on): one row per running Claude Code session: project folder
  name, state (Working / Waiting for you / Done), what it is doing in a few
  words (the tool it is using: "Running a command", "Editing files"), and for
  how long.
- With nothing on: "Idle. The Mac sleeps as usual." and the health box.

### Lock screen and Dynamic Island

The Live Activity shows Ember, the mode, a self-updating countdown, the time
it sleeps, the status dot (working / no internet / went quiet), and buttons
**+1 h** and **Stop**. It appears when a mode starts on the Mac, changes when
the session is extended or paused (Lid mode with the lid open), and ends
when the mode ends, with a final "Ended, Mac sleeping" state left for a few
minutes.

### Notifications

| When | Text (draft) | Action buttons |
|---|---|---|
| 5 min before the session ends (Lid: closed-lid time; Screen: clock) | "MacBook Pro sleeps in 5 min" | +1 h, +2 h |
| The session ended | "Lid mode ended. MacBook Pro is going to sleep." (reason when not the timer) | |
| The Mac went quiet (no heartbeat for 3 min during a session, and it did not say it was ending). This is also the "lost internet" alert: a Mac without internet cannot say so itself | "Not heard from MacBook Pro for 3 min. It may have lost its internet connection." plus, when the Mac was on a hotspot, "If it uses your iPhone's hotspot, open Settings → Personal Hotspot so it can find it." | |
| The Mac is back after going quiet | "MacBook Pro is back online (offline 02:10 to 02:14, now on iPhone hotspot)" | |
| Battery at Ember's floor, or heat Hot/Critical | "MacBook Pro is running hot (Lid mode continues)" | Stop |
| A Claude Code session needs input, while Lid mode or Screen mode is on (Claude's call: no alerts while you sit at the Mac with nothing on) | "ember: Claude is waiting for your answer" | |
| An Ember restore warning (today's on-Mac warnings) | Same title and text as on the Mac | |

Each kind can be switched off in the app's settings. The on-Mac
notifications stay as they are.

### Fixing problems

The phone offers only actions the Mac can safely do, each one a command the
Mac carries out and acknowledges: **Extend** and **Stop**. A remote "rejoin
the hotspot" was dropped (Claude's call after the builder check): a Mac with
no internet cannot receive it, and Ember already retries the hotspot by
itself every 5 to 30 s. The real fix is usually on the phone (the hotspot is
often the owner's own iPhone, which stops advertising when idle), so the
"went quiet" alert and the app's offline screen say that. When the Mac is
unreachable, the app says so plainly and lists what to check; it does not
pretend to fix it.

## How it is built

Three parts. The technical choices below are Claude's calls (owner: "all
good" to native, iCloud and a possible small relay; see "Change from what
was discussed").

```
 Ember (Mac)  ──WebSocket──►  relay (Cloudflare Worker + Durable Object)  ──APNs──►  iPhone app
      ▲                             one object per pairing                          ▲   (alerts,
      └──────── commands ◄──────── WebSocket / HTTPS ◄──────────────────────────────┘    Live Activity)
```

### Change from what was discussed: a relay instead of iCloud

In conversation Claude proposed iCloud (CloudKit) for sync and pairing plus
possibly a small relay. Research changed that:

- CloudKit alerts are coalesced and can arrive minutes late, with occasional
  silent drops; Apple says not to rely on them for specific changes. That
  breaks goal 2 and the first anti-goal.
- Silent pushes to a Developer ID Mac app have an open Apple bug (minutes
  late or missing, still on macOS 26.3), so commands would need polling.
- The lock-screen countdown needs a server anyway: only a server holding the
  APNs key can start and update a Live Activity remotely.
- Only a server can notice that a Mac went silent (it cannot report its own
  disappearance).
- CloudKit would also add restricted entitlements and an embedded
  provisioning profile to Ember's signing; a wrong profile stops Ember from
  launching at all.

Once a relay is needed, routing everything through it is simpler and
reliable. Cost: Cloudflare's free plan covers roughly a few hundred active
users a day; past that it is the $5/month Workers Paid plan. The owner chose
the relay over "iCloud only" on 2026-10-18.

### 1. The protocol package: `EmberLink` (Swift)

A SwiftPM library used by Ember and the iPhone app: the message types
(status snapshot, event, command, ack), encoding, versioning, and the
end-to-end encryption. One source of truth so the two apps cannot drift.

- **Status snapshot:** mode (off / screen / lid), paused, ends-at or
  remaining (send remaining while paused: `Session.endsAt` is only a lease
  then), duration, internet (kind, SSID if known), battery %, charging,
  thermal, memory pressure, agents (id, project name, state, activity,
  since), Ember version, sent-at. Sent on change and as a heartbeat every
  60 s while a mode is on (every 10 min when off).
- **Event:** kind (the notification table), fields, id, sent-at.
- **Command:** id, kind (extend seconds / stop), issued-at, expires 2 min
  later. The Mac rejects expired or repeated ids and answers with an ack
  (done / refused with reason). Extend is capped twice (Claude's call):
  Ember's existing "no more than 24 h from now", and new for remote
  extends, no more than 24 h of total session time since the session
  started. A phone can never keep a Mac awake past that.
- **Encryption:** each phone's pairing creates its own 256-bit key, shared
  only by the Mac and that phone (in the QR code, never sent to the relay).
  Every status, event and command body is sealed with it (CryptoKit
  ChaChaPoly); the Mac seals one copy per paired phone. The relay sees only
  the pairing id, device ids, message kind, size and time. Keys live in the
  Keychain on both sides. Per-phone keys mean unpairing one phone needs no
  re-keying of the others.

### 2. The relay: `ember-relay` (TypeScript, Cloudflare)

A Worker on its own subdomain (Claude's call: `relay.chargingpixels.com`),
separate from the static site Worker, with one SQLite-backed Durable Object
per pairing group (one Mac and its phones).

- **Auth:** each device gets a random device secret at pairing; requests
  carry a short-lived token signed with it (HMAC). The Mac's QR code carries
  a one-time pairing ticket that expires after 10 minutes and works once.
- **Live link:** Ember and the open iPhone app hold WebSockets (hibernation
  API, so idle sockets cost nothing). The object keeps the last sealed
  status, so an app that opens gets it at once.
- **Pushes:** the object sends APNs requests itself (token auth, ES256 JWT
  via WebCrypto, `.p8` stored as a Worker secret): visible alerts (sealed
  body, `mutable-content` so the phone's Notification Service Extension
  decrypts and writes the real text; the fallback text is generic: "Update
  from your Mac"), and Live Activity push-to-start, update and end. Live
  Activity content can't be decrypted on the phone, so it carries only mode,
  times and status kind, never names. The APNs sender sits behind one
  interface so it can move to Firebase Cloud Messaging or a small Lambda if
  Cloudflare's undocumented HTTP/2 upgrade ever stops working.
- **Went-quiet detection:** during a mode, an alarm fires when no heartbeat
  came for 3 min and the Mac did not announce an end or sleep; it pushes the
  "not heard from" alert once.
- **Limits:** per-pairing rate limits on messages and pushes; a pairing with
  no traffic for 60 days is deleted; unpair deletes it at once. No logs of
  message bodies (they are sealed anyway).
- **Tests:** vitest with Cloudflare's Workers test pool, plus a deployed
  sandbox check (local `wrangler dev` cannot reach APNs: no HTTP/2).

### 3. Ember (Mac side)

A new `PhoneLink` module, created in `AppDelegate`, owning the WebSocket,
pairing and the sealed messages.

- **Status:** built from what Ember already has: mode from
  `StatusItemController.mode`, time from `Session` / `AwakeController`,
  battery and heat from `PowerMonitor`, SSID from `NetworkFailover`. New:
  memory pressure (`DispatchSource.makeMemoryPressureSource`), a "hotspot vs
  Wi-Fi" state (SSID equals the configured hotspot, or `NWPath.isExpensive`),
  and a `PowerMonitor` that also runs outside sessions while a phone is
  paired. (Today `AppServices` observers only run during a Lid session.)
- **Events:** a `Notifying` decorator forwards every on-Mac notification;
  `ReminderScheduler` (which posts directly) gets the same hook so "5 minutes
  left" reaches the phone. The reminder fires on the Mac's clock even with
  the lid closed, which is the point.
- **Ending:** before Ember lets the Mac sleep at the end of a session it
  sends the "ended" event and waits up to 2 s for the relay's receipt, so the
  phone hears it before the Mac goes dark.
- **Commands:** extend (Lid: `SessionManager.extend(by:)`; Screen: a new
  `AwakeController` extend), stop (Screen: `awake.turnOff`; Lid: a new end
  reason, `.remote`, for which `EndReason.sleepsAClosedLid` is true, so a
  closed-lid Mac goes to sleep instead of running on with nothing to put it
  to sleep; `.user` does not sleep a closed lid today). Logged like menu
  actions. A command the menu could not do is refused. The "ended" alert for
  a remote stop says "Stopped from iPhone. MacBook Pro is going to sleep."
- **Settings → iPhone:** pair, the list of paired phones with Unpair, a
  switch to report agents, and the connection state.
- **Signing:** nothing changes. Ember needs no new entitlement: it talks to
  the relay over plain HTTPS/WebSocket.

### 4. Agents (Claude Code)

- **Source:** Claude Code hooks. With the owner's click in Settings → iPhone
  ("Report Claude Code sessions"), Ember adds `async` command hooks to
  `~/.claude/settings.json` for SessionStart, UserPromptSubmit, PreToolUse,
  Notification, Stop and SessionEnd, showing the exact change first and
  keeping the user's existing hooks. The hook runs Ember's own binary
  (`Ember --agent-event`), which reads the event JSON on stdin and hands it
  to the running app over a Unix socket in Ember's support folder (owner-only
  permissions). No network listener: a localhost HTTP port could be hit by
  any web page.
- **What is kept and sent:** session id, project folder name (last path
  component), state (working / waiting / done), activity (the tool category,
  not its input), `notification_type` and Claude's short notification message
  for "waiting". Never prompts, file contents, commands or transcripts.
- **Reconcile:** `~/.claude/sessions/<pid>.json` (undocumented, may change)
  and process liveness remove sessions that died without a SessionEnd.
  Turning the switch off removes Ember's hooks.

### 5. The iPhone app

- SwiftUI, iOS 26 and later, iPhone only. Claude's call: display name
  "Ember", bundle id `app.chargingpixels.ember.ios`.
- Targets: the app; a widget extension for the Live Activity (countdown with
  `Text(timerInterval:)`, so it ticks with no pushes); a Notification Service
  Extension (decrypts alerts); App Intents for +1 h / Stop on the lock screen
  and in notifications (they send the command over HTTPS).
- Pairings, device secrets and keys in the Keychain, shared with the
  extensions through an app group.
- Push-to-start token and per-activity update tokens are sent to the relay
  when they change.
- **Demo mode:** sample Mac, a running countdown and two agents, so App
  Review and curious users can see it without a Mac (guideline 4.2.3; the
  review note explains Ember for Mac and includes a video).
- **Settings:** notification kinds on/off, paired Macs (rename, unpair),
  about and privacy.

### Where the code lives

Owner's choice (2026-10-18): `EmberLink` and the Mac side in this repo (public, MIT, since Ember has to
speak the protocol anyway); the iPhone app and the relay in a new private
repo `liviulica/ember-ios`, which depends on `EmberLink` by git tag.

## Owner actions needed (not code)

1. **APNs key:** developer.apple.com → Keys → new key with Apple Push
   Notifications service, team 4UA742BB8G. Download the `.p8` once; it goes
   into the relay's Worker secret and LastPass.
2. **App ID** `app.chargingpixels.ember.ios` with Push Notifications and an
   App Group (Claude can do this with an App Store Connect API key that has
   the Admin or App Manager role, or the owner does it in the portal).
3. **Xcode signed in** with the owner's Apple ID (Settings → Accounts) so
   development builds can run on the owner's iPhone. Today no account is
   signed in.
4. **Cloudflare:** `wrangler login` once on this Mac, and the
   `relay.chargingpixels.com` route.
5. **App Store Connect:** the app record, when TestFlight is near.

## Milestones

0. **Spike (throwaway, day one):** a deployed Worker and Durable Object send
   one alert and one Live Activity push-to-start to a development build
   (APNs sandbox). Proves the riskiest assumption before anything else.
1. `EmberLink`: messages, sealing, tests.
2. Relay: pairing, sockets, status store, commands, pushes, went-quiet
   alarm, tests.
3. Ember: `PhoneLink`, status, events, commands, Settings → iPhone, tests.
4. iPhone app: pairing, main screen, demo mode, notifications with actions.
5. Live Activity: push-to-start, update, end, lock-screen buttons.
6. Agents: hooks install/remove, socket, reconcile, the agents box.
7. Real use on the owner's Mac and iPhone; then TestFlight.

## Testing

- Unit: `EmberLink` round trips, sealing and tamper rejection, command
  expiry and replay; relay auth, ticket single use, rate limits, alarm;
  Ember's command handling against fakes (as `TestSupport.swift` does);
  hooks merge/unmerge of `settings.json` on fixtures; the iPhone view models.
- Integration: the deployed sandbox relay with a development build on the
  owner's iPhone. The simulator runtime does not load on this Mac today
  (`simctl` hangs); fix that or use the device.
- Real-Mac checks, added to the awake spec's Testing list: lid closed on the
  hotspot, 5-minute warning arrives, extend from the lock screen, Mac taken
  offline produces "not heard from", session end reaches the phone before
  sleep.

## Residual risks

- Cloudflare's outbound HTTP/2 to APNs is real but undocumented, and it is
  unverified from inside a Durable Object. Milestone 0 tests it; the sender
  interface allows a switch.
- Live Activities last at most 8 hours (then 4 more on the lock screen,
  frozen). An 8-hour Lid mode fits; a longer one ends the activity and the
  app keeps the status. Lid mode time counts only with the lid closed, so the
  real duration can be longer than the countdown; the activity shows "Paused,
  lid open" then.
- App Review may still read the app as needing another app (4.2.3); demo
  mode and the review note are the mitigation.
- `~/.claude/sessions/` is undocumented; the hooks are the main source.
- With the Mac asleep or offline, nothing can be fixed remotely; the app is
  honest about it.

## Later (phase 2 and beyond)

One-time purchase; start a mode from the phone; settings sync between Macs;
other agents (Codex, Cursor); home screen widget and Apple Watch; history.

## Decisions log

- Owner: App Store app, free first, one-time purchase later; main screen v2
  (B's header, A's health and agents boxes); lock screen countdown; the
  notification list; relay on Cloudflare rather than iCloud only; iPhone app
  and relay in a new private repo.
- Claude's calls (the owner may overrule any): native SwiftUI, iOS 26+;
  `relay.chargingpixels.com`; bundle id `app.chargingpixels.ember.ios`;
  end-to-end encryption with per-phone keys; remote Stop sleeps a closed
  lid; remote extends capped at 24 h of total session time; no remote
  "rejoin hotspot" (folded into the "went quiet" alert); "waiting for you"
  alerts only while a mode is on; agent reporting through Claude Code
  command hooks and a Unix socket, never a network port; prompts and file
  contents never leave the Mac.
