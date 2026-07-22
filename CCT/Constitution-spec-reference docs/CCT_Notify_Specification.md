# CCT_Notify — Full Subsystem Specification for Codex
**Version:** 1.0  
**Date:** 2026-05-15  
**Purpose:** Complete implementation specification for the notification subsystem.  
Codex must implement this as `CCT_Notify.mqh` and wire it into `CCT_Execution.mqh` and `CCT_EA_v6.mq5` at the defined hook points. No other existing files are modified beyond those hook points.

---

## 0. Precedence and Scope

This spec integrates with all existing CCT architecture rules. Subsystem ownership rules from `CCT_Master_Build_Specification_For_Codex.txt` and `CCT_CONSTITUTION_v3.md` apply:

- `CCT_Notify.mqh` is a **pure output layer**. It reads from `ExecutionState` and `PendingExec` structures. It never modifies scanner state, execution truth, or chart objects.
- Notification calls are **non-blocking in terms of logic** — a `WebRequest()` failure must never prevent or delay a trade from firing. Fire-and-forget with logged failure.
- Notifications are suppressed entirely in **non-visual tester mode**.
- All symbol routing, message building, and HTTP dispatch live inside this single file.

---

## 1. New File: `CCT_Notify.mqh`

### 1.1 Input Parameters (added to `CCT_Globals.mqh` inputs block)

```
// ── Notifications ──────────────────────────────────────────────
input bool   NOTIFY_DISCORD_ENABLED   = false;
input string NOTIFY_DISCORD_XAUUSD    = "";   // Webhook URL for Gold channel
input string NOTIFY_DISCORD_XAGUSD    = "";   // Webhook URL for Silver channel
input string NOTIFY_DISCORD_NQ        = "";   // Webhook URL for NQ/NASDAQ channel
input string NOTIFY_DISCORD_AUDUSD    = "";   // Webhook URL for AUDUSD channel
input string NOTIFY_DISCORD_BTCUSD    = "";   // Webhook URL for BTCUSD channel
input string NOTIFY_DISCORD_DEFAULT   = "";   // Fallback webhook for unmapped symbols

input bool   NOTIFY_TELEGRAM_ENABLED  = false;
input string NOTIFY_TELEGRAM_TOKEN    = "";   // Bot token from @BotFather
input string NOTIFY_TELEGRAM_XAUUSD   = "";   // Chat/topic ID for Gold
input string NOTIFY_TELEGRAM_XAGUSD   = "";   // Chat/topic ID for Silver
input string NOTIFY_TELEGRAM_NQ       = "";   // Chat/topic ID for NQ
input string NOTIFY_TELEGRAM_AUDUSD   = "";   // Chat/topic ID for AUDUSD
input string NOTIFY_TELEGRAM_BTCUSD   = "";   // Chat/topic ID for BTCUSD
input string NOTIFY_TELEGRAM_DEFAULT  = "";   // Fallback chat ID for unmapped symbols
// Telegram forum/topic mode: if chat ID is a supergroup with topics enabled,
// supply the topic ID here. Bot must be admin with "Manage Topics" permission.

input int    NOTIFY_SCREENSHOT_DELAY_MS = 800; // Milliseconds to wait after trigger before screenshotting
                                               // Allows chart objects to render before capture
input bool   NOTIFY_SCREENSHOT_ENABLED = true; // False = text-only messages
```

### 1.2 Symbol Router

The router maps any broker-specific symbol variant to a canonical asset family, then returns the correct webhook URL / chat ID.

**Canonical family definitions:**

| Family | Broker symbol variants (case-insensitive, prefix/suffix stripped) |
|--------|-------------------------------------------------------------------|
| XAUUSD | XAUUSD, GOLD, XAU, GC, GCUSD, XAUUSD.a, XAUUSD+, XAUUSD. (any suffix) |
| XAGUSD | XAGUSD, SILVER, XAG, SI, SIUSD |
| NQ     | NQ, USTEC, US100, USTECH, NAS100, MNQ, NDX, NASDAQ, NASUSD, US100+, NAS100+ |
| AUDUSD | AUDUSD, AUD/USD, AUDUSD.a, AUDUSD+ |
| BTCUSD | BTCUSD, BITCOIN, BTC, BTCUSDT, XBTUSD |

**Router function signature:**
```mql5
string NotifyResolveWebhook(string symbol, NotifyPlatform platform);
// Returns the configured URL/ID for the matched family, or the DEFAULT if no match.
// Returns "" if the platform is disabled or no URL is configured for this family.
```

**Implementation rule:** Strip all non-alpha-numeric characters from the raw symbol, uppercase it, then test against each family's variants using `StringFind`. First match wins.

---

## 2. Notification Event Types

There are exactly **three notification events**:

| Event | Trigger point | Fires from |
|-------|--------------|------------|
| `NOTIFY_ENTRY` | Immediately after broker fill confirmed (or synthetic entry locked if no broker) | `CCT_Execution.mqh` → after fill record is written |
| `NOTIFY_BE_MOVE` | Immediately after any BE stop move (Global BE or NY CO-BE) | `CCT_Execution.mqh` → after `CCTUpdatePositionBE()` confirms SL moved |
| `NOTIFY_EXIT` | Immediately after outcome is latched (TP/SL/BE classified) | `CCT_Execution.mqh` → inside `OnTradeTransaction` handler after global variable write |

No other events generate notifications.

---

## 3. Screenshot Workflow

### 3.1 Chart Resolution

The EA runs on the HTF chart. The screenshot must capture the **LTF chart** for the triggered symbol and model.

```
LTF per model:
  1H / 1M  model → screenshot PERIOD_M1 chart
  4H / 5M  model → screenshot PERIOD_M5 chart
  1D / 15M model → screenshot PERIOD_M15 chart
```

**Chart search algorithm:**
1. Call `ChartFirst()` then iterate `ChartNext()` to walk all open chart IDs.
2. For each chart ID, call `ChartSymbol(id)` and `ChartPeriod(id)`.
3. Match: `ChartSymbol(id) == _Symbol` AND `ChartPeriod(id) == target_LTF_period`.
4. First matching chart ID wins. If no match, fall back to the current EA chart ID.

### 3.2 Capture Sequence

```
1. Resolve target chart ID (per 3.1).
2. Sleep(NOTIFY_SCREENSHOT_DELAY_MS) to allow pending chart object renders to flush.
3. Build filename: "CCT_<symbol>_<genKey>_<eventType>.png"
   e.g. "CCT_XAUUSD_BU_260325_0200_ENTRY.png"
4. Call ChartScreenShot(chartId, filename, 1920, 1080, ALIGN_LEFT).
5. Read file bytes from terminal Files directory using FileOpen / FileReadArray / FileClose.
6. Pass byte array to the dispatcher.
7. On dispatcher success: FileDelete(filename). On failure: leave for inspection, log error.
```

### 3.3 Multi-Model Side-by-Side (Future Extension Point)

When more than one LTF period is active for the same symbol (e.g. both 1M and 5M models running), capture both charts as separate screenshots and send them as two attachments in the same Discord message or two sequential Telegram `sendPhoto` calls in the same notification burst. The spec for this extension is:

- Capture screenshot A (lower LTF, e.g. M1).
- Capture screenshot B (higher LTF, e.g. M5).
- Discord: attach both as `files[0]` and `files[1]` in the single multipart POST.
- Telegram: send `sendPhoto` twice to the same chat/topic with the same caption on the first photo and an empty caption on the second (no duplicate text).

Current implementation (single model) sends one image. The two-attachment path is built as a loop over a `screenshot_paths[]` array of size 1..2 so the extension requires no structural change.

---

## 4. Message Content Schema

### 4.1 NOTIFY_ENTRY Message

```
[Direction emoji] CCT [BUY|SELL] — [Symbol Display Name] | [Session] | [Model Label]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 Entry          [entry price, formatted to symbol digits]
🎯 Take Profit    [TP price] ([RR]R)
🛑 Stop Loss      [SL price]
📏 Risk/Reward    [RR ratio]:1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[BE section — show all that apply, omit headers for any that are disabled]

⚖️ Global BE
   Trigger at     [BE trigger price — the price at which progress threshold is met]
   SL moves to    [BE target price — entry ± configured move%]

🔵 CO Reference   [CO price]

🔵 CO-BE (NY AM only)
   Activates if   CO touched after [min_age_seconds]s AND price ≥ [min_progress%]% of TP progress
   SL moves to    [entry + spread + commission equivalent — show as "~entry" if identical]
   CO price       [CO price]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⏱ Trigger         [trigger bar close time, NY timezone, format: HH:MM NY]
🕐 Session         [London | NY AM | Asia]
📊 Model           [CCT | CCT+TS | CCT+TS Ext] · [HTF]/[LTF]
🏛 Birth           [birth bar open time, NY timezone]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ Risk Disclosure
This is an automated signal from a rule-based system. All trades carry risk.
Past performance does not guarantee future results. Manage your risk accordingly.
```

**Direction emoji:** 🟢 for BUY, 🔴 for SELL.

**Symbol Display Names:**

| Family | Display Name |
|--------|-------------|
| XAUUSD | Gold (XAUUSD) |
| XAGUSD | Silver (XAGUSD) |
| NQ     | NASDAQ 100 (NQ) |
| AUDUSD | AUD/USD |
| BTCUSD | Bitcoin (BTCUSD) |
| Default | raw symbol from `_Symbol` |

**Global BE trigger price calculation:**
```
Bull:  entry + (BE_trigger_pct / 100.0) * (TP - entry)
Bear:  entry - (BE_trigger_pct / 100.0) * (entry - TP)
```
This is the price at which the progress gate fires, not the SL move target. Both prices are shown.

**CO-BE section** is shown only when:
- The trade session is NY AM, AND
- NY CO-BE is enabled in EA inputs, AND
- CO price is known and valid.

### 4.2 NOTIFY_BE_MOVE Message

```
⚖️ BE Move — [Symbol Display Name] | [Session] | [Model Label]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Type            [Global BE | CO-BE (NY AM)]
📍 Entry        [entry price]
🔒 SL Moved To  [new SL price]
🎯 TP           [TP price]
📍 CO           [CO price, if applicable]

⏱ Time          [current NY time]

⚠️ Risk Disclosure
This is an automated signal from a rule-based system. Manage your risk accordingly.
```

**Type** field: "Global BE" when triggered by progress threshold; "CO-BE (NY AM)" when triggered by CO touch with NY AM silent BE.

### 4.3 NOTIFY_EXIT Message

```
[Outcome emoji] [Outcome label] — [Symbol Display Name] | [Session] | [Model Label]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 Entry         [entry price]
🏁 Exit          [exit price]
💰 Result        [+/-][R result]R  ([+/-][pips] pips)
⏱ Duration      [HH]h [MM]m

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Model         [CCT | CCT+TS | CCT+TS Ext] · [HTF]/[LTF]
🕐 Session       [London | NY AM | Asia]

⚠️ Risk Disclosure
This is an automated signal from a rule-based system. Manage your risk accordingly.
```

**Outcome emoji + label:**

| Outcome | Emoji | Label |
|---------|-------|-------|
| TP Hit | ✅ | TP HIT |
| SL Hit | ❌ | SL HIT |
| BE Exit (Global) | ⚖️ | BREAKEVEN EXIT |
| BE Exit (CO-BE) | 🔵 | CO BREAKEVEN EXIT |

**R result calculation:**
```
R result = (exit_price - entry_price) / (entry_price - SL_price)   [bull]
R result = (entry_price - exit_price) / (SL_price - entry_price)   [bear]
```
Use the locked SL from `ExecutionState`, not the broker's current SL (which may have moved for BE).  
Format: `+2.08R` or `-1.00R`. Always show sign.

**Pips calculation:** `|exit - entry| / _Point / 10.0` for 5-digit brokers; divide by point size normalized to standard pip. Use the broker pip size from symbol info rather than hardcoding.

**Duration:** from `trade_open_time` (broker fill time) to `exit_time`. Format as `1h 23m` or `47m` (omit hours if < 1h).

---

## 5. Platform Dispatch Implementation

### 5.1 Discord — Multipart Webhook POST

Discord webhook URL already includes authentication. No headers beyond `Content-Type` are required.

**Endpoint:** `POST {webhook_url}?wait=true`

**Payload structure (with screenshot):**
Use `multipart/form-data`. Two parts:

Part 1 — `payload_json`:
```json
{
  "content": "",
  "embeds": [{
    "description": "<full message text from Section 4>",
    "color": <color_int>,
    "image": { "url": "attachment://screenshot.png" }
  }]
}
```
`color_int`: `65280` (green, 0x00FF00) for BUY entry; `16711680` (red, 0xFF0000) for SELL entry; `16776960` (yellow, 0xFFFF00) for BE move; `65280` for TP; `16711680` for SL; `16776960` for BE exit; `3381759` (teal) for CO-BE exit.

Part 2 — `files[0]`:  
Binary PNG bytes. Filename in the multipart header: `screenshot.png`.

**Without screenshot:**  
Omit the `image` field and the file part. Send only `payload_json` with `Content-Type: application/json`.

**MQL5 multipart construction:**
```
Build body as a uchar array:
  "--BOUNDARY\r\n"
  "Content-Disposition: form-data; name=\"payload_json\"\r\n"
  "Content-Type: application/json\r\n\r\n"
  <json string bytes>
  "\r\n--BOUNDARY\r\n"
  "Content-Disposition: form-data; name=\"files[0]\"; filename=\"screenshot.png\"\r\n"
  "Content-Type: image/png\r\n\r\n"
  <png bytes>
  "\r\n--BOUNDARY--\r\n"

Content-Type header: "multipart/form-data; boundary=BOUNDARY"
```
Use a fixed boundary string e.g. `"CCTNotifyBoundary7x3q"`.

**WebRequest call:**
```mql5
int res = WebRequest(
  "POST",
  url,
  "Content-Type: multipart/form-data; boundary=CCTNotifyBoundary7x3q\r\n",
  5000,       // timeout ms
  body,
  response,
  responseHeaders
);
// res == 200 or 204 = success. Log anything else as a warning.
```

### 5.2 Telegram — sendPhoto / sendMessage

**Base URL:** `https://api.telegram.org/bot{token}/`

**With screenshot:** `POST sendPhoto` with `multipart/form-data`:
```
Fields:
  chat_id        = <chat ID string, may be negative for groups>
  message_thread_id = <topic ID if forum mode; omit if not a topic>
  caption        = <message text, max 1024 chars>
  parse_mode     = "HTML"
  photo          = <binary PNG bytes as file part>
```

**Without screenshot or if caption would exceed 1024 chars:**
1. `POST sendMessage` with `chat_id`, `message_thread_id`, `text` (full message), `parse_mode=HTML`.
2. If screenshot exists, follow immediately with `POST sendPhoto` with empty `caption`.

**Telegram message formatting:**
Telegram supports HTML mode: use `<b>` for bold headers, plain text for values. Replace the `━` dividers with `——————————————`. The emoji set is identical to Discord.

**Character limit handling:**
Build the full text. If `StringLen(text) > 1000` (conservative margin under 1024): truncate the BE section and CO-BE detail, keeping entry/TP/SL/RR and the risk disclosure. Log the truncation.

**MQL5 WebRequest call:**
```mql5
string url = "https://api.telegram.org/bot" + NOTIFY_TELEGRAM_TOKEN + "/sendPhoto";
// same multipart construction as Discord, different field names
```

---

## 6. Public Interface — Functions Codex Must Implement

All six functions are in `CCT_Notify.mqh`. No other file defines notify logic.

```mql5
// Call once from OnInit after all inputs are loaded.
// Validates that configured URLs are non-empty when enabled.
// Logs a warning per platform if enabled but no default URL configured.
void NotifyInit();

// Call from CCT_Execution.mqh immediately after broker fill is recorded
// (or after synthetic entry is locked if no broker fill).
// exec: the fully populated ExecutionState record for this trade.
// modelHTF: e.g. PERIOD_H1. modelLTF: e.g. PERIOD_M1.
void NotifyEntry(const ExecutionState &exec, ENUM_TIMEFRAMES modelHTF, ENUM_TIMEFRAMES modelLTF);

// Call from CCT_Execution.mqh immediately after SL is confirmed moved
// (both Global BE and CO-BE paths call this).
// beType: 0 = Global BE, 1 = CO-BE (NY AM).
void NotifyBEMove(const ExecutionState &exec, int beType, ENUM_TIMEFRAMES modelHTF, ENUM_TIMEFRAMES modelLTF);

// Call from CCT_Execution.mqh inside OnTradeTransaction,
// after the outcome global variable is written.
// outcome: SS_RESOLVED_TP | SS_RESOLVED_SL | SS_RESOLVED_BE | SS_RESOLVED_BE_CO
void NotifyExit(const ExecutionState &exec, int outcome, ENUM_TIMEFRAMES modelHTF, ENUM_TIMEFRAMES modelLTF);

// Internal — resolves the correct Discord webhook or Telegram chat ID for the current _Symbol.
// platform: 0 = Discord, 1 = Telegram. Returns "" if not configured.
string NotifyResolveTarget(int platform);

// Internal — captures LTF chart screenshot, returns file path or "" on failure.
string NotifyCaptureScreenshot(ENUM_TIMEFRAMES ltfPeriod, string genKey, string eventSuffix);
```

---

## 7. Hook Points in Existing Files

### 7.1 `CCT_EA_v6.mq5` — OnInit

```mql5
// After all existing init logic:
#include "CCT_Notify.mqh"
// Inside OnInit(), after CCT_Globals init:
NotifyInit();
```

### 7.2 `CCT_Execution.mqh` — After Fill Confirmed

Locate the block where the `ExecutionState` record is written after broker fill (or after synthetic lock). Immediately after that block:

```mql5
if(!IsTesting() || (IsTesting() && IsVisualMode()))
   NotifyEntry(exec, MODEL_HTF_PERIOD, MODEL_LTF_PERIOD);
```

`MODEL_HTF_PERIOD` and `MODEL_LTF_PERIOD` are existing EA globals or input-derived values representing the current model's HTF and LTF timeframe enums.

### 7.3 `CCT_Execution.mqh` — After BE SL Move Confirmed

Locate both the Global BE path and the CO-BE path where `PositionModify` succeeds. In each:

```mql5
// Global BE path:
if(!IsTesting() || (IsTesting() && IsVisualMode()))
   NotifyBEMove(exec, 0, MODEL_HTF_PERIOD, MODEL_LTF_PERIOD);

// CO-BE path:
if(!IsTesting() || (IsTesting() && IsVisualMode()))
   NotifyBEMove(exec, 1, MODEL_HTF_PERIOD, MODEL_LTF_PERIOD);
```

### 7.4 `CCT_Execution.mqh` — Inside OnTradeTransaction After Outcome Write

Locate the block where outcome is latched and the global variable is written. Immediately after:

```mql5
if(!IsTesting() || (IsTesting() && IsVisualMode()))
   NotifyExit(exec, outcome, MODEL_HTF_PERIOD, MODEL_LTF_PERIOD);
```

---

## 8. MT5 WebRequest URL Allow-List

The following URLs must be added to `Tools → Options → Expert Advisors → Allow WebRequest for listed URLs`:

```
https://discord.com
https://discordapp.com
https://api.telegram.org
```

Codex must include a comment in `NotifyInit()` that prints these instructions to the Experts log if either platform is enabled, so the user sees the requirement on first run:

```mql5
Print("CCT_Notify: Add to MT5 WebRequest whitelist: https://discord.com, https://api.telegram.org");
```

---

## 9. Error Handling Rules

- `WebRequest()` return code ≠ 200/204: log `"[CCT_Notify] Dispatch failed — platform: X, code: Y, symbol: Z"`. Never retry. Never throw.
- `ChartScreenShot()` returns false: log failure, continue with text-only dispatch for that notification.
- `FileOpen()` fails on screenshot file: log failure, continue text-only.
- Empty URL resolved by router: skip that platform silently (not an error — means user hasn't configured that channel).
- Any `StringFormat` or build failure: catch with a safe fallback string `"[CCT Notify] Message build error — see Experts log."` and dispatch that instead of nothing.
- Never call `ExpertRemove()` or any trade-side function from within `CCT_Notify.mqh`.

---

## 10. Suppression Rules

Notifications are suppressed (no call, no log) when:

1. `IsTesting() && !IsVisualMode()` — non-visual tester.
2. Both `NOTIFY_DISCORD_ENABLED` and `NOTIFY_TELEGRAM_ENABLED` are false.
3. The resolved target URL/ID is `""` for all configured platforms for this symbol.
4. The `ExecutionState` record passed to the function has an invalid generation key (empty string or zero ticket).

---

## 11. File Structure Summary

```
CCT_Notify.mqh
├── Section A: Includes and forward declarations
├── Section B: Symbol router (NotifyResolveTarget)
├── Section C: Screenshot capture (NotifyCaptureScreenshot)
├── Section D: Message builders
│   ├── BuildEntryMessage()    → returns string
│   ├── BuildBEMoveMessage()   → returns string
│   └── BuildExitMessage()     → returns string
├── Section E: Multipart body builder (BuildMultipartBody)
├── Section F: Platform dispatchers
│   ├── DispatchDiscord(text, image_bytes[], image_present)
│   └── DispatchTelegram(text, image_bytes[], image_present, chat_id)
└── Section G: Public API
    ├── NotifyInit()
    ├── NotifyEntry()
    ├── NotifyBEMove()
    └── NotifyExit()
```

All internal helpers are prefixed `Notify` and are `static` or file-scope functions. No symbol namespace collisions with the rest of the EA.

---

## 12. Discord Server and Telegram Setup (User Configuration Guide)

Codex must include this as a comment block at the top of `CCT_Notify.mqh`:

```
// ─────────────────────────────────────────────────────────────────────
// DISCORD SETUP
// 1. Create a Discord server named "CCT Signals" (or any name).
// 2. Create one text channel per asset, e.g.: #gold, #silver, #nasdaq, #audusd, #btcusd.
// 3. For each channel: Settings → Integrations → Webhooks → New Webhook → Copy URL.
// 4. Paste each URL into the corresponding NOTIFY_DISCORD_* input.
// 5. Add https://discord.com to MT5 WebRequest whitelist.
//
// TELEGRAM SETUP
// 1. Open @BotFather in Telegram. Send /newbot. Follow prompts. Copy the token.
// 2. Create a Telegram supergroup or channel for "CCT Signals".
//    For per-asset separation: enable Topics (supergroup → Edit → Topics → Enable).
//    Create one topic per asset.
// 3. Add your bot to the group/channel as admin with "Post Messages" and "Manage Topics" permissions.
// 4. Get the group chat_id: forward any message from the group to @userinfobot or use getUpdates.
//    Get each topic's message_thread_id from a message URL or getUpdates.
// 5. Set NOTIFY_TELEGRAM_TOKEN and the per-asset NOTIFY_TELEGRAM_* IDs.
//    Format: "-1001234567890" for group chat_id; "12345" for topic message_thread_id.
// 6. Add https://api.telegram.org to MT5 WebRequest whitelist.
// ─────────────────────────────────────────────────────────────────────
```

---

## 13. Example Rendered Messages (Reference for Codex)

### Entry — Gold Buy

```
🟢 CCT BUY — Gold (XAUUSD) | London | CCT+TS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 Entry          2,345.20
🎯 Take Profit    2,378.50  (+2.1R)
🛑 Stop Loss      2,328.40
📏 Risk/Reward    2.1:1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚖️ Global BE
   Trigger at     2,369.10  (90% of TP progress)
   SL moves to    2,349.45

🔵 CO Reference   2,376.00

🔵 CO-BE (NY AM only)
   Activates if   CO touched ≥ 300s after entry AND progress ≥ 20%
   SL moves to    ~entry (entry + spread)
   CO price       2,376.00

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⏱ Trigger         03:14 NY
🕐 Session         London
📊 Model           CCT+TS · 1H/1M
🏛 Birth           02:00 NY

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ Risk Disclosure
This is an automated signal from a rule-based system. All trades carry risk.
Past performance does not guarantee future results. Manage your risk accordingly.
```

### Exit — TP Hit

```
✅ TP HIT — Gold (XAUUSD) | London | CCT+TS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 Entry          2,345.20
🏁 Exit           2,378.50
💰 Result         +2.08R  (+33.3 pips)
⏱ Duration       1h 23m

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Model          CCT+TS · 1H/1M
🕐 Session        London

⚠️ Risk Disclosure
This is an automated signal from a rule-based system. Manage your risk accordingly.
```

### BE Move

```
⚖️ BE Move — Gold (XAUUSD) | London | CCT+TS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Type            Global BE
📍 Entry        2,345.20
🔒 SL Moved To  2,349.45
🎯 TP           2,378.50

⏱ Time          04:37 NY

⚠️ Risk Disclosure
This is an automated signal from a rule-based system. Manage your risk accordingly.
```

---

*End of CCT_Notify Specification v1.0*
