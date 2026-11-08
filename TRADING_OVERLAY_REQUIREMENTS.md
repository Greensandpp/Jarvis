# GreenSoil JARVIS — TradingView Overlay / Intelligent Trading Monitor
Status: approved user requirement, NOT implemented as a live signal engine. V2 test branch only.

## User experience
- "Jarvis, open TradingView" or launching TradingView manually activates a permission-approved floating Arc Reactor bubble and trading monitor, when monitoring is enabled.
- Compact draggable toggle expands a multi-action HUD. Avoid intrusive persistent transcript/input box. Tap to expand, long-press for alternate display style. Arc Reactor and humanoid JARVIS are themes of one assistant, not separate assistant modes.
- Main home: a single primary JARVIS experience, microphone/text available; optional Chat/Agent modes in compact mode menu or Settings. Macro/Air Gesture/Self-Evolution appear in Settings until demonstrated safe and useful.
- Overlay shortcuts: Listen/push-to-talk, Chat, Trading Mode, Summarize, Torch, Payment Safety, Settings and Stop Monitoring. Shortcuts must be real, verified and permission-aware; no fake success.
- Preserve background safety, battery and Android policy limits. Overlay must be dismissible and must not obscure charts or private input.
- Payment Safety closes overlay and guides user to disable sensitive Accessibility controls manually. No OS bypass, silent permission modification, OTP/UPI PIN automation or screen reading in banking apps.

## Chart monitor — independent data feeds required
- NIFTY and SENSEX only for phase 1, PAPER/read-only by default.
- For market structure: previous day high/low/close, support/resistance, VWAP, EMA9, ORB/CPR, swing HH/HL/LH/LL, liquidity sweep, BOS/CHOCH, order blocks, FVG zones, breakout/retest, reversal and continuation. Pro Trace-like contextual visualization may be an inspiration, not a claim of identical proprietary algorithms.
- Get verified index OHLC and 5-minute locked-close, option premium OHLC, open-interest/volume/OI changes, option chain, PCR, greeks/spread and freshness metadata from legitimate APIs or owner-authorized feeds.
- Do not pretend that reading TradingView pixels via Accessibility is a sufficient source for continuous OI/option chain, prices or tick-accurate confirmation. Android screen capture requires consent and may be unavailable/blocked in secure apps. Do not bypass FLAG_SECURE.
- De-duplicate TradingView webhook indicator signals and AI observed setup alerts by symbol, side, signal ID, event and 5-minute candle timestamp.
- Distinguish potential setup, confirmed 5-minute-close signal, actual Railway PAPER fill, TP touched, TP confirmed, SL triggered, SL order acknowledged, trailing SL moved, runner active, reversal warning, position exit and risk lock. Never announce a fill absent an execution receipt.
- For existing position announce verified MFE, next targets TP1–TP6, take-profit status, reversals, risk and exit, source/timestamp; no invented levels.
- Never predict a maximum target as certain. Use confidence and conditions; <70% or missing premium/OI confirmation => NO TRADE.
- Voice + sound overlays configurable by priority, language and quiet hours, no duplicate or continuous noisy beeps.
- Strong isolation from cloud personal-data leakage: no upload of WhatsApp/banking/contacts/screenshots without explicit scope-specific consent. Gemini cloud requests only when owner intentionally enables cloud mode.
- Background Android monitoring relies on opted-in foreground service, notification permission and Android 16 OS restrictions; not guaranteed 24/7 uninterrupted.
- All real-money orders require a separate explicit consent flow; trading monitor must not make autonomous trades.

## Implementation milestones
P0: install-safe V2, secret encryption, network audit, Android 16 device QA.
P1: home UX consolidation, overlay shortcuts (initial code committed), overlay safety.
P1: data-provider contract, read-only feeds and verification timestamps, signal event engine.
P1: TradingView open/close recognition with opted-in monitoring lifecycle, notifications and event dedup.
P1: technical chart algorithms and validated OI/premium data reconciliation with existing Pine and Railway PAPER bot.
P2: additional UI themes, macros/air gesture promotion only after quality assessment.

## Acceptance gates
Each shortcut and alert must be demonstrated with real device tests and captured diagnostic evidence. No fake live prices, empty dashboards labelled live, fabricated confirmation, or pretending that generic screen summaries are active market surveillance.
