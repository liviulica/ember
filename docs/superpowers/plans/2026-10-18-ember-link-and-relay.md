# EmberLink and the relay: Implementation Plan (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The shared message format (`EmberLink`, Swift) and the relay that carries it between a Mac and its phones (`ember-relay`, Cloudflare Worker + Durable Object), both fully tested without any Apple or Cloudflare account.

**Architecture:** `EmberLink` is a standalone SwiftPM package nested in the Ember repo (`EmberLink/`), with no dependencies beyond Foundation and CryptoKit. The relay lives in the new private repo `liviulica/ember-mobile` (`relay/`), which pins the Ember repo as a git submodule (`Vendor/Ember`) so both sides test against the same vectors. One Durable Object per pairing group routes sealed envelopes over hibernating WebSockets and sends APNs pushes through an `ApnsSender` interface (faked in tests; the real sender is proven by the milestone 0 spike).

**Tech Stack:** Swift 6.2, CryptoKit (ChaChaPoly, P256.Signing), XCTest; TypeScript, wrangler 4.147.0, vitest 4.1.11, @cloudflare/vitest-pool-workers 0.22.0, @cloudflare/workers-types 5.20261003.1, typescript 7.0.2 (all exact, none newer than two weeks on 2026-10-18).

**Spec:** `docs/superpowers/specs/2026-10-18-ember-iphone-companion-design.md`

**The three plans:** 1 (this): EmberLink + relay. 2: Ember's Mac side (`PhoneLink`, status, events, commands, Settings → iPhone, agents). 3: the iPhone app (pairing, main screen, demo mode, notifications and their extension, Live Activity). The milestone 0 spike (a deployed relay pushing to a development build) runs as soon as the owner has created the APNs key and signed in Xcode, before plan 3's push tasks.

## Global Constraints

- Nothing readable by the relay except: group id, device ids, message type, size, times, the session-on flag and the Live Activity state (mode, times, status kind). Status, event, command and ack bodies are always sealed.
- Each phone has its own 256-bit key with the Mac; the relay never receives it.
- Requests are signed with each device's P-256 key; the relay stores only public keys.
- Pairing ticket: works once, expires 10 minutes after creation.
- Commands: the relay never queues them. Delivered only to a connected Mac; the phone's request waits at most 10 s for the ack. The Mac dedupes by command id and rejects an `issuedAt` more than 10 minutes from its own clock.
- Remote extend cap (enforced on the Mac, plan 2; the format carries what it needs): 24 h of total session time since the session started.
- Went quiet: no heartbeat for 3 minutes while the session-on flag is set and the Mac did not send `ending`.
- A pairing group with no traffic for 60 days is deleted; a group that never got a phone is deleted after 24 h.
- Envelope size cap 64 KiB; sealed event body cap 3,000 bytes (APNs payloads are 4 KB).
- No em dashes in user-facing strings. Commit author `liviulica <826835+liviulica@users.noreply.github.com>`; trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Branch per repo; merging and pushing to `main` need the owner's yes each time; merge locally with `git merge --no-ff`.
- Bash 3.2-safe scripts; Swift 6 language mode, warnings as errors in CI.

## Review Focus

1. **Clock skew between phone and Mac** (minutes off): signing accepts ±300 s against the relay's clock; command acceptance must not depend on the phone and Mac agreeing to the second. Test in Task 4 (window edges) and Task 1 (`LinkCommand.isFresh` at ±9 and ±11 min).
2. **A retried command** (phone timed out, sends the same id again): the relay forwards it again; the Mac's dedupe (plan 2) answers with the first ack. Test in Task 7: same id twice reaches the Mac twice, and the relay does not cache acks across requests.
3. **Two sockets for one device** (reconnect race, app opened twice): routing goes to every open socket of the target device, and "Mac connected" stays true until the last Mac socket closes. Test in Task 6.
4. **A removed phone with a socket still open**: removal closes its sockets at once and its signed requests fail from then on. Test in Task 5.
5. **Malformed or oversized input** (bad JSON, unknown `type`, `from` not matching the socket's device, 65 KiB message): rejected with a close code or 400, and the object keeps serving the others. Test in Task 6.

---

### Task 1: EmberLink package and its message types

**Files:**
- Create: `EmberLink/Package.swift`, `EmberLink/Sources/EmberLink/Messages.swift`, `EmberLink/Tests/EmberLinkTests/MessagesTests.swift`
- Modify: `.github/workflows/ci.yml` (add a step to the `swift` job: `swift test --package-path EmberLink`)

**Interfaces:**
- Produces (all `public`, `Codable, Equatable, Sendable`):
  - `enum LinkMode: String { case off, screen, lid }`
  - `enum LinkInternetKind: String { case wifi, hotspot, ethernet, none, unknown }`; `struct LinkInternet { var kind: LinkInternetKind; var ssid: String? }`
  - `struct LinkBattery { var percent: Int; var charging: Bool }`
  - `enum LinkThermal: String { case normal, warm, hot, critical }` with `init(_ state: ProcessInfo.ThermalState)` mapping nominal/fair/serious/critical in that order
  - `enum LinkMemory: String { case normal, tight, critical }`
  - `enum LinkAgentState: String { case working, waiting, done }`; `struct LinkAgent { var id: String; var project: String; var state: LinkAgentState; var activity: String?; var message: String?; var since: Date }`
  - `struct LinkStatus { var mode: LinkMode; var paused: Bool; var endsAt: Date?; var remaining: TimeInterval?; var duration: TimeInterval?; var sessionStartedAt: Date?; var internet: LinkInternet; var battery: LinkBattery?; var thermal: LinkThermal; var memory: LinkMemory; var agents: [LinkAgent]; var emberVersion: String; var sentAt: Date }`
  - `enum LinkEventKind: String { case endsSoon, ended, battery, thermal, agentWaiting, restoreWarning, notice }`; `struct LinkEvent { var id: UUID; var kind: LinkEventKind; var title: String; var body: String; var sentAt: Date }`
  - `enum LinkCommandKind { case extend(seconds: Int); case stop }` (Codable as `{"kind":"extend","seconds":3600}` / `{"kind":"stop"}`); `struct LinkCommand { var id: UUID; var kind: LinkCommandKind; var issuedAt: Date; func isFresh(now: Date) -> Bool }` (true when `abs(issuedAt - now) <= 600`)
  - `enum LinkAckResult { case done; case refused(reason: String) }`; `struct LinkAck { var commandID: UUID; var result: LinkAckResult }`
  - `enum LinkActivityStatus: String { case working, offline, quiet, ended }`; `struct LinkActivityState { var mode: LinkMode; var paused: Bool; var endsAtEpoch: Double?; var remainingSeconds: Double?; var status: LinkActivityStatus }` (plaintext Live Activity content; epoch seconds, never `Date`, because ActivityKit decodes `Date` as seconds since 2001)
  - `enum LinkCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }`: dates as milliseconds since 1970, sorted keys.

- [ ] **Step 1: Write the failing tests** in `MessagesTests.swift`: `testStatusRoundTrips` (a full `LinkStatus` with two agents survives encode/decode equal); `testCommandKindJSON` (`.extend(seconds: 3600)` encodes to exactly `{"kind":"extend","seconds":3600}`, `.stop` to `{"kind":"stop"}`); `testCommandFreshness` (issuedAt now−540 s and now+540 s fresh; now−660 s and now+660 s not); `testThermalMapping` (`.nominal→.normal`, `.fair→.warm`, `.serious→.hot`, `.critical→.critical`); `testActivityStateUsesEpochSeconds` (encoded JSON of `endsAtEpoch: 1792300000` contains `"endsAtEpoch":1792300000`); `testDatesAreEpochMilliseconds` (`LinkEvent.sentAt = Date(timeIntervalSince1970: 1.5)` encodes `"sentAt":1500`).
- [ ] **Step 2: Run** `swift test --package-path EmberLink`. Expected: fails to compile (types missing).
- [ ] **Step 3: Write `EmberLink/Package.swift`** (tools 6.2; platforms `.macOS(.v26), .iOS(.v26)`; library `EmberLink`; test target; `.swiftLanguageMode(.v6)`) **and `Messages.swift`** with the types above.
- [ ] **Step 4: Run** `swift test --package-path EmberLink`. Expected: all pass. Run `swift build -c release -Xswiftc -warnings-as-errors --package-path EmberLink`: no warnings.
- [ ] **Step 5: Add the CI step and commit** `feat(link): EmberLink message types`.

### Task 2: Sealing

**Files:**
- Create: `EmberLink/Sources/EmberLink/Sealer.swift`, `EmberLink/Tests/EmberLinkTests/SealerTests.swift`

**Interfaces:**
- Consumes: `LinkCoding` (Task 1).
- Produces: `public enum Sealer { static func seal<T: Encodable>(_ value: T, key: SymmetricKey, context: SealContext) throws -> String; static func open<T: Decodable>(_ type: T.Type, from sealed: String, key: SymmetricKey, context: SealContext) throws -> T; static func newKey() -> SymmetricKey }`; `public struct SealContext: Sendable, Equatable { var type: String; var id: String; var from: String; var to: String?; var aad: Data }` (`aad` = UTF-8 of `"ember1|\(type)|\(id)|\(from)|\(to ?? "")"`); `public enum SealError: Error { case malformed, authenticationFailed }`. Output is base64 (standard, padded) of ChaChaPoly's `combined`.

- [ ] **Step 1: Write the failing tests:** `testRoundTrip`; `testWrongKeyFails` (throws `.authenticationFailed`); `testContextIsBound` (sealed with `to: "d_a"`, opened with `to: "d_b"` throws `.authenticationFailed`; same for a changed `type` and `id`); `testFlippedByteFails`; `testGarbageIsMalformed` (`"not base64!"` throws `.malformed`); `testFixedVector` (key = 32 bytes `0x01…0x20`, nonce = 12 bytes `0x00`, plaintext `{"a":1}`, context type `event` id `e1` from `d_mac` to `d_phone`: write the produced base64 into the test as the expected literal on first run, using an internal `seal(_:key:context:nonce:)` overload).
- [ ] **Step 2: Run** `swift test --package-path EmberLink --filter SealerTests`. Expected: compile failure.
- [ ] **Step 3: Implement** with `ChaChaPoly.seal(_:using:nonce:authenticating:)`; a random nonce except in the internal overload.
- [ ] **Step 4: Run** the filter. Expected: pass.
- [ ] **Step 5: Commit** `feat(link): seal and open message bodies`.

### Task 3: Envelope, request signing and the shared test vectors

**Files:**
- Create: `EmberLink/Sources/EmberLink/Envelope.swift`, `EmberLink/Sources/EmberLink/RequestSigner.swift`, `EmberLink/Tests/EmberLinkTests/SigningTests.swift`, `EmberLink/TestVectors/signing.json`

**Interfaces:**
- Produces:
  - `public struct LinkEnvelope: Codable, Equatable, Sendable { var v: Int = 1; var type: String; var id: String; var from: String; var to: String?; var sentAt: Int64 /* ms */; var sealed: String?; var hints: LinkHints? }` and `public struct LinkHints: Codable, Equatable, Sendable { var sessionOn: Bool?; var push: String? /* "alert" */; var alertKind: String?; var activity: LinkActivityState?; var activityPhase: String? /* "start","update","end" */ }`. Envelope types: `status`, `event`, `activity`, `ack`, `ending`, `command`.
  - `public struct DeviceIdentity { let privateKey: P256.Signing.PrivateKey; var publicKeyBase64: String /* x963, standard base64 */ }`
  - `public enum RequestSigner { static func canonical(method: String, path: String, timestampMs: Int64, body: Data) -> String; static func authorization(device: String, key: P256.Signing.PrivateKey, method: String, path: String, timestampMs: Int64, body: Data) throws -> String; static func verify(header: String, publicKeyX963: Data, method: String, path: String, body: Data, nowMs: Int64) -> Bool }`
  - Canonical string: `"\(method.uppercased())\n\(path)\n\(timestampMs)\n\(hex(SHA256(body)))"` (lowercase hex; `path` includes the query string if any).
  - Header: `EmberSig device=<id>,ts=<ms>,sig=<base64url, no padding, of the raw 64-byte r||s signature>`. Valid when `abs(nowMs - ts) <= 300_000`.
  - `EmberLink/TestVectors/signing.json`: `{ "privateKeyRawBase64", "publicKeyX963Base64", "device": "d_vector", "method": "POST", "path": "/v1/groups/g_vector/commands", "timestampMs": 1792300000000, "body": "{\"x\":1}", "canonical", "authorization" }`.

- [ ] **Step 1: Write the failing tests:** `testCanonicalString` (method `post`, path `/v1/a?b=1`, ts `1792300000000`, body `{"x":1}` gives exactly `"POST\n/v1/a?b=1\n1792300000000\n" + sha256hex`, with the hex asserted as a literal); `testSignVerifyRoundTrip`; `testVerifyRejectsSkew` (ts = now−300_001 and now+300_001 rejected, ±300_000 accepted); `testVerifyRejectsOtherBodyAndPath`; `testVectorsFileVerifies` (loads `TestVectors/signing.json` via `#filePath`, recomputes `canonical` and checks `verify(authorization)` is true at `nowMs = timestampMs`); `testEnvelopeJSONShape` (an envelope with `to: nil` and `hints: nil` encodes with sorted keys and omits nils).
- [ ] **Step 2: Run** `swift test --package-path EmberLink --filter SigningTests`. Expected: compile failure.
- [ ] **Step 3: Implement**, then generate `signing.json` once with a throwaway test (fixed private key raw = SHA256("ember vector key")), commit the file, delete the generator.
- [ ] **Step 4: Run** the whole package's tests. Expected: pass.
- [ ] **Step 5: Commit** `feat(link): envelope, request signing, shared vectors`.

### Task 4: Pairing code

**Files:**
- Create: `EmberLink/Sources/EmberLink/PairingCode.swift`, `EmberLink/Tests/EmberLinkTests/PairingCodeTests.swift`

**Interfaces:**
- Produces: `public struct PairingCode: Codable, Equatable, Sendable { var relay: URL; var group: String; var macDevice: String; var macName: String; var ticket: String /* base64url 32 bytes */; var key: String /* base64url 32 bytes, the phone's sealing key */; var url: URL { get }; init?(url: URL) }`. URL form: `https://chargingpixels.com/ember/pair#` + base64url(no padding) of the sorted-keys JSON. The fragment never reaches a server. Also `public static func ticketHash(_ ticket: String) -> String` (lowercase hex SHA-256 of the ticket's UTF-8 text) and `public var sealingKey: SymmetricKey? { get }`.

- [ ] **Step 1: Write the failing tests:** `testURLRoundTrip`; `testURLHasNoQueryAndUsesFragment`; `testRejectsOtherHostOrPath` (`init?(url:)` returns nil for `https://example.com/ember/pair#...` and for `/ember/other#...`); `testRejectsShortKey` (a 16-byte key gives `sealingKey == nil`); `testTicketHash` (`ticketHash("abc")` == `"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"`).
- [ ] **Step 2: Run** `swift test --package-path EmberLink --filter PairingCodeTests`. Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the package tests. Expected: pass.
- [ ] **Step 5: Commit** `feat(link): pairing code`. Push the branch `iphone-companion-design` to origin (a feature branch, not `main`), so the submodule in Task 5 can fetch it.

### Task 5: The ember-mobile repo, the relay skeleton, groups, tickets and devices

**Files (repo `~/Coding/ember-mobile`, private `liviulica/ember-mobile`):**
- Create: `README.md`, `.gitignore`, `Vendor/Ember` (submodule of `https://github.com/liviulica/ember`, at the Task 4 commit), `relay/package.json`, `relay/package-lock.json`, `relay/wrangler.jsonc`, `relay/tsconfig.json`, `relay/vitest.config.ts`, `relay/src/index.ts`, `relay/src/auth.ts`, `relay/src/group.ts`, `relay/src/ids.ts`, `relay/test/auth.test.ts`, `relay/test/pairing.test.ts`, `relay/test/helpers.ts`
- Register in atelier: `node ~/Coding/atelier/scripts/work/work.mjs register ~/Coding/ember-mobile --description="Ember for iPhone (SwiftUI) and its Cloudflare relay"` and `~/Coding/atelier/projects/ember-mobile.md`.

**Interfaces:**
- Consumes: `EmberLink/TestVectors/signing.json` (read in tests from `../Vendor/Ember/EmberLink/TestVectors/signing.json`), the header and canonical rules of Task 3, `PairingCode.ticketHash` rule of Task 4.
- Produces:
  - `auth.ts`: `canonical(method: string, path: string, ts: number, body: ArrayBuffer): Promise<string>`; `parseAuthorization(h: string): {device: string, ts: number, sig: Uint8Array} | null`; `verifySignature(publicKeyX963B64: string, header: string, method: string, path: string, body: ArrayBuffer, nowMs: number): Promise<boolean>` (WebCrypto ECDSA P-256 SHA-256, key imported `raw`).
  - `ids.ts`: `newId(prefix: "g" | "d"): string` (prefix + `_` + base64url of 16 random bytes).
  - `group.ts`: `export class EmberGroup extends DurableObject` with SQLite tables `devices(id TEXT PRIMARY KEY, role TEXT, public_key TEXT, name_sealed TEXT, apns_token TEXT, start_token TEXT, update_token TEXT, environment TEXT, disabled INTEGER, created_at INTEGER, last_seen INTEGER)`, `tickets(hash TEXT PRIMARY KEY, expires_at INTEGER)`, `meta(key TEXT PRIMARY KEY, value TEXT)`.
  - HTTP API (Worker routes to `env.GROUP.idFromName(groupId)`; every route except group creation and redemption requires a valid `Authorization` from a non-disabled device of that group):
    - `POST /v1/groups` body `{"publicKey"}` → 201 `{"group","device"}` (the Mac, role `mac`).
    - `POST /v1/groups/:g/tickets` (Mac only) body `{"ticketHash"}` → 204; expires 10 min later.
    - `POST /v1/groups/:g/devices` body `{"ticket","publicKey","nameSealed"}` → 201 `{"device"}` (role `phone`); 403 when the ticket is unknown, used or expired. Deletes the ticket.
    - `DELETE /v1/groups/:g/devices/:d` (any device of the group; a phone may remove itself or another phone, never the Mac; the Mac may remove any phone) → 204; sets `disabled = 1` and closes that device's sockets.
  - `wrangler.jsonc`: name `ember-relay`, `main: src/index.ts`, `compatibility_date: "2026-10-01"`, Durable Object binding `GROUP` → `EmberGroup`, migration `v1` with `new_sqlite_classes: ["EmberGroup"]`, vars `APNS_TOPIC: "app.chargingpixels.ember.ios"`, `APNS_TEAM_ID: "4UA742BB8G"`; secrets (not committed) `APNS_KEY_P8`, `APNS_KEY_ID`.

- [ ] **Step 1: Create the repo** (`gh repo create liviulica/ember-mobile --private`), set the repo-local git identity, add the submodule, scaffold `relay/` with the exact versions from the header, `npm install`.
- [ ] **Step 2: Write the failing tests:** `auth.test.ts`: `verifies the shared vector` (true at `nowMs = timestampMs`), `rejects at 300001 ms skew`, `accepts at 300000 ms skew`, `rejects a changed body`, `canonical matches the vector`. `pairing.test.ts`: `creates a group`; `redeems a ticket once` (second redemption 403); `rejects an expired ticket` (advance time by 600_001 ms through a `now()` the object reads from an injectable clock in tests); `rejects unsigned and wrongly signed requests` (401); `a phone cannot remove the Mac` (403); `a removed phone is rejected afterwards` (its next signed request 401) **and its open socket is closed** (Review Focus 4; open the socket first using Task 6's route, so write this case as `it.todo` now and fill it in Task 6).
- [ ] **Step 3: Run** `npm test` in `relay/`. Expected: failures (routes missing).
- [ ] **Step 4: Implement** `index.ts`, `auth.ts`, `ids.ts`, `group.ts` for these routes.
- [ ] **Step 5: Run** `npm test` and `npx tsc --noEmit`. Expected: pass, no type errors.
- [ ] **Step 6: Commit** `feat(relay): groups, pairing tickets, devices, signed requests` and push the branch `relay` (never `main` without the owner's yes; the first commit of a new repo goes on `main` only with that yes, otherwise start the repo with the branch).

### Task 6: Sockets, routing and the last status

**Files:**
- Modify: `relay/src/group.ts`, `relay/src/index.ts`
- Create: `relay/src/protocol.ts`, `relay/test/sockets.test.ts`

**Interfaces:**
- Consumes: Task 5's auth and tables; the envelope shape of Task 3.
- Produces:
  - `protocol.ts`: `type Envelope = { v: 1; type: "status"|"event"|"activity"|"ack"|"ending"|"command"; id: string; from: string; to?: string|null; sentAt: number; sealed?: string|null; hints?: Hints|null }`; `parseEnvelope(text: string): Envelope | null` (null on bad JSON, `v !== 1`, unknown type, missing fields, or `text.length > 65536`).
  - `GET /v1/groups/:g/socket` (WebSocket upgrade, signed): accepted with the hibernation API (`ctx.acceptWebSocket(ws, [deviceId, role])`).
  - Mac → relay messages: an envelope whose `from` is the socket's device. `status`/`event`/`activity`/`ack` with `to` = a phone id are forwarded to every open socket of that phone; `status` is also stored as that phone's last status; `ending` sets `meta.ending = 1`. Any envelope updates `meta.lastHeartbeat` and, when `hints.sessionOn` is present, `meta.sessionOn`.
  - Relay → device messages: `{"v":1,"type":"relay","event":"deviceAdded","device","nameSealed"}` to the Mac on redemption; `{"v":1,"type":"relay","event":"deviceRemoved","device"}` to the Mac on removal.
  - `GET /v1/groups/:g/status` (phone): 200 `{"status": Envelope|null, "macConnected": boolean, "lastHeartbeat": number|null, "quiet": boolean}`.
  - Bad input closes the sender's socket with code 1008 (policy) or 1009 (too big); other sockets are unaffected.

- [ ] **Step 1: Write the failing tests** in `sockets.test.ts`: `forwards a sealed status to the addressed phone only` (two phones; only the addressed one receives it); `stores the last status per phone` (GET status returns it); `macConnected follows the last Mac socket` (two Mac sockets; true after closing one, false after both: Review Focus 3); `delivers to every socket of the phone` (two sockets for one phone both receive); `rejects from-spoofing` (an envelope with another device's `from` closes the socket with 1008); `rejects bad JSON, unknown type and a 65537-char message` (1008, 1008, 1009) while a second socket still receives traffic (Review Focus 5); fill in Task 5's todo: removal closes the removed phone's socket.
- [ ] **Step 2: Run** `npm test -- sockets`. Expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npm test` and `npx tsc --noEmit`. Expected: pass.
- [ ] **Step 5: Commit** `feat(relay): sockets, routing, last status`.

### Task 7: Commands and acks

**Files:**
- Modify: `relay/src/group.ts`, `relay/src/index.ts`
- Create: `relay/test/commands.test.ts`

**Interfaces:**
- Consumes: Task 6's sockets.
- Produces: `POST /v1/groups/:g/commands` (phone), body = a `command` envelope from that phone to the Mac. 409 `{"error":"mac-offline"}` with no Mac socket; otherwise forwarded to every Mac socket, and the request resolves with 200 + the first `ack` envelope whose `id` equals the command's `id` and whose `to` is that phone, or 504 `{"error":"no-ack"}` after 10 s. Nothing is queued or cached.

- [ ] **Step 1: Write the failing tests:** `returns 409 when the Mac is offline`; `returns the Mac's ack`; `times out after 10 s` (fake timers or a configurable timeout set to 50 ms in tests); `a retried command id is forwarded again` (Review Focus 2: two requests with the same id both reach the Mac socket; each resolves with its own ack); `an ack for another phone does not resolve the request`.
- [ ] **Step 2: Run** `npm test -- commands`. Expected: fail.
- [ ] **Step 3: Implement** with a map of pending requests keyed by `phoneId + commandId`, resolved from `webSocketMessage`.
- [ ] **Step 4: Run** `npm test`. Expected: pass.
- [ ] **Step 5: Commit** `feat(relay): commands wait for the Mac's ack`.

### Task 8: Push tokens and pushes (alerts and Live Activity)

**Files:**
- Create: `relay/src/apns.ts`, `relay/test/apns.test.ts`, `relay/test/pushes.test.ts`
- Modify: `relay/src/group.ts`, `relay/src/index.ts`

**Interfaces:**
- Produces:
  - `interface ApnsSender { send(req: ApnsRequest): Promise<ApnsResult> }`; `type ApnsRequest = { token: string; environment: "sandbox"|"production"; pushType: "alert"|"liveactivity"; priority: 5|10; payload: object; expiration?: number }`; `type ApnsResult = { status: number; reason?: string }`.
  - `class HttpApnsSender implements ApnsSender` (constructor `(keyP8: string, keyId: string, teamId: string, topic: string, fetchImpl = fetch, now = Date.now)`): ES256 JWT (`{alg:"ES256",kid}` / `{iss: teamId, iat}`), reused for 50 minutes; host `api.sandbox.push.apple.com` or `api.push.apple.com`; headers `authorization: bearer <jwt>`, `apns-push-type`, `apns-priority`, `apns-topic` (= topic, or `topic + ".push-type.liveactivity"` for Live Activity).
  - The object gets its sender from `this.makeSender(env)`, overridable in tests with a recording fake.
  - `PUT /v1/groups/:g/devices/:d/push` (that device) body `{"apnsToken"?, "startToken"?, "environment"}` → 204. `PUT /v1/groups/:g/devices/:d/activity` body `{"updateToken": string|null}` → 204.
  - Alert push: for an `event` envelope with `hints.push == "alert"` and `to` = a phone with an `apns_token`: payload `{"aps":{"alert":{"title":"Ember","body":"Update from your Mac"},"mutable-content":1,"sound":"default","category":<hints.alertKind>},"ember":{"g":group,"t":"event","id":id,"s":sealed}}`, priority 10. Rejected with 1009 when `sealed` is over 3,000 bytes.
  - Live Activity push: for an `activity` envelope (one per phone, `to` set): phase `start` → to `start_token` with `{"aps":{"timestamp":<s>,"event":"start","content-state":<hints.activity>,"attributes-type":"EmberActivityAttributes","attributes":{"group":group},"alert":{"title":"Ember","body":"Session started on your Mac"}}}`; `update` → to `update_token` with `event:"update"`; `end` → `event:"end"` plus `"dismissal-date": <s + 300>`. All priority 10. Skipped silently when the token is missing.
  - APNs 410 or 400 `BadDeviceToken`: the token is cleared.

- [ ] **Step 1: Write the failing tests:** `apns.test.ts`: `signs an ES256 JWT that verifies with the public key` (generate a P-256 key in the test, export pkcs8 as PEM); `reuses the token for 50 minutes and renews after`; `uses the sandbox host and the liveactivity topic`. `pushes.test.ts` (recording fake): `alert event pushes a sealed payload with the generic fallback text`; `oversized sealed event closes with 1009 and sends nothing`; `activity start uses the start token and the attributes`; `activity end sets a dismissal date 300 s later`; `missing token sends nothing`; `410 clears the token`.
- [ ] **Step 2: Run** `npm test -- apns pushes`. Expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npm test` and `npx tsc --noEmit`. Expected: pass.
- [ ] **Step 5: Commit** `feat(relay): push tokens, alert and Live Activity pushes`.

### Task 9: Went quiet, back online, limits and cleanup

**Files:**
- Modify: `relay/src/group.ts`
- Create: `relay/test/quiet.test.ts`, `relay/test/limits.test.ts`

**Interfaces:**
- Produces:
  - On every Mac envelope while `sessionOn` is true and `ending` is not set: `ctx.storage.setAlarm(lastHeartbeat + 180_000)`. `sessionOn: false` or `ending` clears the alarm and the quiet state.
  - `alarm()`: if `sessionOn`, not `ending`, and `now - lastHeartbeat >= 180_000`, set `meta.quiet = 1` and push once per quiet spell to each phone with an `apns_token`: `{"aps":{"alert":{"title":"Ember","body":"Not heard from your Mac for 3 min. It may have lost its internet connection."},"mutable-content":1,"sound":"default","category":"quiet"},"ember":{"g":group,"t":"quiet","lastHeard":<ms>}}`, plus a Live Activity `update` with the phone's last activity state and `status: "quiet"` when an `update_token` exists (the object keeps each phone's last `hints.activity`).
  - The next Mac envelope after a quiet spell: `meta.quiet = 0` and an alert `{"aps":{"alert":{"title":"Ember","body":"Your Mac is back online"},"mutable-content":1,"category":"back"},"ember":{"g":group,"t":"back","from":<lastHeard ms>,"to":<now ms>}}`.
  - Limits: per device, 120 messages per rolling minute (over: socket closed 1008, HTTP 429); per group, 30 pushes per rolling hour (over: dropped and logged).
  - Cleanup alarm (shares the one alarm; the object stores the next due time of each job): a group whose only device is the Mac 24 h after creation, or with no envelope for 60 days, deletes all its storage.

- [ ] **Step 1: Write the failing tests:** `quiet.test.ts`: `pushes once after 3 min of silence during a session`; `no push when the session is off`; `no push after ending`; `one push per quiet spell` (alarm twice, one push); `back online push on the next envelope`; `quiet marks the Live Activity`. `limits.test.ts`: `121st message in a minute closes the socket`; `31st push in an hour is dropped`; `a group without a phone is deleted after 24 h`; `a group idle for 60 days is deleted`.
- [ ] **Step 2: Run** `npm test -- quiet limits`. Expected: fail.
- [ ] **Step 3: Implement** (use the injectable clock from Task 5; trigger alarms with `runDurableObjectAlarm` from `cloudflare:test`).
- [ ] **Step 4: Run** `npm test` and `npx tsc --noEmit`. Expected: pass.
- [ ] **Step 5: Commit** `feat(relay): went-quiet and back-online alerts, limits, cleanup`. Open a PR in each repo (Ember: the spec, the plan and EmberLink; ember-mobile: the relay), with the self-review and a Codex review, and report to the owner. Do not merge.

## After this plan

- Milestone 0 spike, once the owner has: created the APNs key, signed in Xcode, run `wrangler login`. Deploy `ember-relay` to a `workers.dev` address with the key as a secret, push one alert and one Live Activity start from inside the Durable Object to a development build. If the Durable Object cannot reach APNs, switch `HttpApnsSender` to send from the Worker (the object calls the Worker through a service binding), then to FCM.
- Plan 2 (Ember's Mac side) and plan 3 (iPhone app), written when this plan's PRs are up.

## Carried into plans 2 and 3 (from the reviews of plan 1)

- Plan 2 (Ember): call `GET /v1/groups/:g/devices` on every connect and delete the keys of removed phones; send `sessionOn: false` (or `ending`) on every end; wait for the relay's `{"type":"relay","event":"received","id"}` (up to 2 s) before letting the Mac sleep after "ended"; keep the command dedupe store at least 20 minutes across restarts; batch status sends so a Mac with several phones stays under 120 messages a minute; keep the socket alive and detect a half-open one (ping or heartbeat).
- Plan 3 (iPhone): treat 410 `removed` as "unpaired on the other side"; read acks from the command response, not the socket; let the phone mute the relay's own "went quiet" and "back online" alerts (a mute list in `PUT .../push`, or the Notification Service Extension filtering entitlement); dedupe events and ignore stale statuses (`sentAt`).
- Relay, later: rebuild Live Activity state from the allowed fields and reject unknown phases; refuse to start without the APNs key in production; CI for `relay/`; re-pin `Vendor/Ember` to `main` after this PR merges; fewer row writes per message.
