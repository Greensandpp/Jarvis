# GreenSoil JARVIS — unified Flutter app: status and evidence

**Status: NOT COMPLETE.** Major items are still UNVERIFIED (see section 6).

Branch `feature/jarvis-unified-20261120`, based on `staging/aira-five-modes-20261119`.
The original Flutter JARVIS (all features, hologram assets, AIRA 5-mode work) is kept intact; the native
ADS app's brain, diagnostics, watchdog, memory, risk gate and journal audit were ported into it in Dart.
Nothing was merged to `main`, deployed, or installed on the owner's phone.

Legend: **PASS-DEVICE** = passed inside the real APK on Android 15 and 16 emulators (CI) ·
**PASS-UNIT** = unit/widget test only · **TEST DOUBLE** = uses a mock AI/HTTP server (not live Gemini) ·
**UNVERIFIED** = not proven · **NOT BUILT**.

## 1. Two builds from one codebase

| | Standard | Full Control |
|---|---|---|
| Application ID (CI test build) | `com.greensoil.jarvis.unified.visualstaging` | `com.greensoil.jarvis.unified.full.visualstaging` |
| Launcher name | JARVIS | JARVIS Full Control |
| Accessibility, overlay bubble, contacts, all-package listing, usage stats, WRITE_SETTINGS, storage-wide, Shizuku | removed (manifest `tools:node="remove"`) and hidden in UI | kept (original) |
| Overwrites existing installs | no (new IDs) | no (new IDs) |

## 2. Device acceptance (in-app `integration_test`, real APK, no mocks, no API key)

| ID | Check | Result |
|---|---|---|
| U01 | Both builds install side by side | PASS-DEVICE |
| U02 | Standard build has no high-risk permissions / no accessibility or overlay service | PASS-DEVICE |
| U03/U04 | JARVIS Core, AIRA, Office, APEX, MIRA and AIRA models render, no crash | PASS-DEVICE |
| I01/I02 | Build identifies itself; floating bubble only in Full Control | PASS-DEVICE |
| I03 | A question with no AI configured is answered by the brain path and JARVIS leaves THINKING in ~3 s with an honest "Cloud AI is switched off" message | PASS-DEVICE |
| I04/I05 | Settings shows STANDARD/FULL CONTROL BUILD; AI status "AI NOT CONNECTED" (never falsely ONLINE) | PASS-DEVICE |
| I06 | Connection diagnostics on the real network: DNS ok, TLS ok, stops at "No API key set", generation skipped | PASS-DEVICE |
| I07 | Risk gate: valid setup → TRADE (PAPER) with sizing ≤ ₹1,200 and TP1–TP8; 09:20 + 65% → NO TRADE with reasons | PASS-DEVICE |
| I08 | Journal audit finds before-09:30, <70%, >₹1,200 risk; journal persisted | PASS-DEVICE |
| I09 | Indicators (EMA9, MA9, VWAP, Supertrend, structure) and OI (PCR, max pain, support/resistance) from pasted data | PASS-DEVICE |
| I10 | JARVIS Control Center: 14/14 sections open | PASS-DEVICE |
| I11 | Microphone/TTS diagnostics report real facts (recognizer available, Tamil TTS installed, mic permission state) | PASS-DEVICE |
| I12 | Memory: add, correct (history kept), undo, encrypted backup file, wrong passphrase rejected, restore, persisted | PASS-DEVICE |
| I13 | Typed command "switch to apex" / "aira jellyfish mode" switches visuals through the same path as voice | see final run below |

Final run: see the PR/CI link in the delivery message (`.github/workflows/jarvis-unified.yml`).
Defects found by these device runs and fixed: "setState() called when widget tree was locked" from the
original HUD dispose (regression test added), accessibility banner shown in the Standard build, legacy
"what is …" shortcuts bypassing the brain, backup encryption blocking the UI thread.

## 3. Unit / widget tests (160, all passing)

| Area | Tests | Kind |
|---|---|---|
| AI failure kinds (DNS/TLS/connect/timeout/400 API_KEY_INVALID/401/403/404/429/5xx), retry, model discovery + fallback, verified status | brain_reliability_test | TEST DOUBLE (MockClient) |
| Brain: multi-step tool use, approvals, blocked payments/orders, unavailable tools, cancel, max steps, reply verification, prompt contents, tool catalog | brain_tool_calling_test | TEST DOUBLE (scripted model) |
| Spoken approval flow: implicit fact → "Shall I remember…?" → yes/seri saves, no/vendam dismisses; audit log | brain_tool_calling_test | real services, no AI |
| Tamil / Tanglish / English detection; offline shortcuts (time, visuals, language, female voice) | brain_tool_calling_test | PASS-UNIT |
| Semantic memory with embedder, keyword fallback offline, persistence after restart | brain_tool_calling_test | TEST DOUBLE embeddings |
| Memory corrections/undo, encrypted backup round-trip, wrong passphrase + tamper rejection, suggestions need approval | memory_upgrade_test | PASS-UNIT |
| Risk gate (each rule blocks independently), journal audit | trading_engine_test | PASS-UNIT |
| EMA/SMA/VWAP/Supertrend/structure, choppy → NO TRADE, malformed rows rejected, OI, chart-screenshot reading judge | indicators_test | PASS-UNIT |
| Notify-during-dispose regression | jarvis_notify_lock_test | PASS-UNIT |
| Original suites (five modes, AIRA, Office, Gemini Live, security/privacy, features, widgets) | 8 files | PASS-UNIT |

## 4. What was added (all in the original app)

- **AI brain** (`lib/brain/`): OpenAI-compatible tool calling on the configured provider (Gemini endpoint),
  plan → tools → verified answer, up to 6 steps, cancel (Stop / "cancel"), 120 s command watchdog.
  26 tools across five agents (Commander, Researcher, Operator, Trading Analyst, Archivist) wrapping the
  original services. Approval required for message drafts, screen automation, memory writes; payments and
  live orders are blocked. Original fast commands remain as offline shortcuts; the original intent
  router is used when the brain is switched off (Control Center → AI Brain).
- **Memory**: relevance-ranked recall injected into the brain prompt; Gemini embeddings when allowed,
  keyword fallback offline; corrections with history + undo; implicit facts and observed preferences
  are only *suggested* until approved; passphrase-encrypted backup file (PBKDF2-HMAC-SHA256 + MAC) with
  share/restore.
- **Voice**: reply language follows Tamil script / Tanglish / English (or fixed); female neural voices
  (Pallavi ta-IN, Neerja en-IN) when cloud TTS is allowed, otherwise local TTS in that language;
  voice commands change visuals, language and voice; microphone/TTS diagnostics.
- **Trading (PAPER ONLY)**: risk gate (09:30, 5-min close, ≥70%, ₹1,200/entry incl. fees, ₹3,000/day,
  one position, stale quotes, SL width), TP1–TP8 + trailing plan, journal audit, indicators, OI, and
  TradingView/broker screenshot reading (Gemini reads only visible values; missing values lower
  confidence; never guessed).
- **Visuals**: original layers kept; MIRA gains a procedural holographic bust; APEX gains perspective
  orbits, light sweep and flare.
- **Settings**: JARVIS Control Center reaching AI Brain, API key & Models, Diagnostics, Voice, Memory &
  Backup, Learning, Trading, Agents & Audit, Tools, Visuals, Permissions, Automation (original), Device &
  PC, Security & Privacy.

## 5. Safety constraints (enforced in code)

No orders, payments, Pine/PB7/Railway/broker changes; OTP/UPI PIN only by the owner; messages are drafts
the owner sends; memory writes need approval; API key stays on the phone (never in source/logs);
cloud AI, cloud TTS and web lookups are off until the owner enables them.

## 6. UNVERIFIED / NOT BUILT

| Item | Status | What unblocks it |
|---|---|---|
| Live Gemini answers, tool calling and embeddings with a real key | UNVERIFIED | Owner enters key in Settings → AI, enables cloud AI, runs the connection test |
| Tamil/Tanglish speech recognition accuracy, female voice on iQOO 13 | UNVERIFIED | Test on the phone |
| Screen automation, overlay, contacts (Full Control build) | UNVERIFIED | Owner grants on a real device |
| Live market data, OI feed, PB7 status, Telegram reports | NOT CONNECTED | Read-only data source + credentials + approval |
| Comparison with the three reference videos | BLOCKED | Videos were not provided to this session |
| Photoreal humanoid characters | NOT BUILT | Needs licensed or owner-supplied 3D assets |
| Windows PC companion | NOT BUILT | |
| Release signing | CI debug key only (test builds) | Owner's signing key |
