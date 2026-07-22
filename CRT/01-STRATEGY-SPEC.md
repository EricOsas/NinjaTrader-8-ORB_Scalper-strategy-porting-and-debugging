# CRT — Candle Range Theory EA · Platform-Agnostic Strategy Specification

This document defines the CRT trading model in plain, procedural English so it can be
implemented identically on **NinjaTrader 8 (C#)** and **MQL5 (C++)**. It is the single
source of truth; the two implementation specs (`02-NT8-IMPLEMENTATION.md`,
`03-MQL5-IMPLEMENTATION.md`) only describe *how* each platform realises the rules below.

Everything time-related, position-sizing, margin, notifications, news filtering, dashboards
and visuals is **lifted from the existing ORB_Scalper (MQL5) / ORB_NT (C#) and CCT_v7 (MQL5)
projects**. This spec never re-invents those solved problems — it only defines the CRT
signal engine and how it is wired into that proven infrastructure.

> **Scope note (explicit exclusions).** This build **does NOT** include: trailing-stop logic,
> break-even logic, EMA / volatility / trend filters, or OCO bracket logic. Stops and targets
> are static per trade (SL just past the sweep wick, TP at C1 equilibrium). Everything else —
> News filter, Discord/Telegram notifications, position sizing, time engine, dashboard, visuals,
> state persistence — **is** included.

---

## 0. Conventions & Definitions (read first)

* **Bullish candle**: Close > Open.
* **Bearish candle**: Close < Open.
* **Candle high / low**: the bar's High / Low (wick extremes).
* All clock times are **New York (America/New_York)** time unless stated otherwise. DST is
  handled by the ported ORB time engine (calendar-math based, broker-timezone independent).
* **HTF** = the higher timeframe the reference candle (C1) lives on (e.g. 1H).
* **LTF** = the lower timeframe on which the sweep, CISD and IFVG are read (e.g. 5m).
* **HTF Sweep of a level**: price trades beyond a level intrabar — the candle's High or Low
  penetrates it. Wick penetration is sufficient.
* **Close back inside**: after sweeping a level, the candle's **Close** returns to the original
  side of that level (below C1 High if the high was swept; above C1 Low if the low was swept).
* **Manipulation leg**: the swing that runs from the moment C1's High or Low is first breached
  to the most extreme point reached in that breach direction, immediately before price reverses.
* **FVG (Fair Value Gap)** — a 3-candle imbalance:
  * **Bullish FVG**: candle1.High < candle3.Low. Gap zone = [candle1.High (lower), candle3.Low (upper)].
  * **Bearish FVG**: candle1.Low > candle3.High. Gap zone = [candle3.High (lower), candle1.Low (upper)].
* **IFVG (Inverted FVG)**: an FVG that a later candle **closes completely through** (beyond the
  gap's far boundary — the boundary nearest that FVG's candle1). Once inverted it acts as
  support/resistance in the opposite direction.
* **CISD (Change in State of Delivery)**: a candle close beyond the reference open of the most
  recent opposite-delivery candle (or consecutive same-direction run) inside the manipulation
  leg. Precise definition in §5.
* **Equilibrium (EQ / 50%)**: the exact midpoint price of C1's range = (C1.High + C1.Low) / 2.

---

## 1. The 3-Candle Model

CRT treats **every** reference candle on the configured HTF as a self-contained range where
liquidity is swept and reversed. Unlike the DTR model, there is **no separate HTF-bias phase** —
the sweep on C2 itself defines direction.

* **Candle 1 (C1) — the Range.** The reference HTF candle. Lock `C1_High`, `C1_Low` and
  `C1_EQ = (C1_High + C1_Low)/2` at C1 close. These never change for that setup.
* **Candle 2 (C2) — the Manipulation.** The HTF candle immediately following C1. We watch for
  C2 to **sweep** one extreme of C1 (trade beyond C1_High or C1_Low) and then **close back inside**
  C1's range.
  * Sweep of **C1_High** + close back inside → **SHORT bias** (target C1_EQ below).
  * Sweep of **C1_Low** + close back inside → **LONG bias** (target C1_EQ above).
  * If C2 **closes outside** C1 (beyond the swept extreme) → **setup invalid** (genuine
    breakout/continuation, not a sweep-reversal). Discard.
  * If C2 sweeps neither side → no setup from this C1.
* **Candle 3 (C3) — the Execution.** The HTF candle following C2. Entry orders are placed on
  the LTF during C2 (once a trigger fires) and/or at C3 open (if the trigger fired inside C2 —
  see §6). The setup window closes at the end of C3.

> **Timeframe relationship.** C1/C2/C3 are consecutive HTF candles. The sweep, CISD and IFVG
> are all detected on **LTF** bars printed *inside* the C2 (and C3) HTF windows.

---

## 2. Timeframe Model (Slots)

Four independent, individually-enable-able slot **types**. Only **Intraday** exposes a
sub-timeframe selector.

| Slot      | C1 timeframe                          | C1 anchor (NY)                    |
|-----------|---------------------------------------|-----------------------------------|
| Intraday  | selectable: **15m, 30m, 1H, 2H, 4H**  | each aligned HTF candle of the day|
| Daily     | 1 day                                 | True Day open = 18:00 prior day   |
| Weekly    | 1 week                                | True Week open = Sunday 18:00     |
| Monthly   | 1 month                               | True Month open = 18:00 before 1st|

* When Intraday is set to (e.g.) 1H, **every** 1H candle that forms a valid C1→C2→C3 sequence
  is eligible throughout the 24h day.
* True Day/Week/Month opens are computed by the **ported ORB time engine**
  (`GetCurrentNYTrueDayOpen`, `GetCurrentNYTrueWeekOpen`, `GetCurrentNYTrueMonthOpen`).
* The EA should be able to reconstruct C1/C2 if it is initialised mid-sequence (as long as C3's
  execution window has not passed), and it should draw setups for the previous 2–3 NY days
  (CCT-style back-draw).

### 2.1 Execution (LTF) timeframe resolution

A single optional input **`ExecTFMinutesOverride`** governs the LTF:

* If **> 0**: that minute value is used as the LTF for **all** slots, regardless of the HTF model.
* If **empty / 0**: the LTF is **auto-derived per slot**:

| C1 timeframe | Auto LTF |
|--------------|----------|
| 15m          | 1m       |
| 30m          | 1m       |
| 1H           | 5m       |
| 2H           | 5m       |
| 4H           | 15m      |
| Daily        | 15m      |
| Weekly       | 1H       |
| Monthly      | 4H       |

---

## 3. Setup Lifecycle (per C1)

1. **C1 forms & closes** → lock `C1_High`, `C1_Low`, `C1_EQ`.
2. **C2 window opens.** On each LTF bar inside C2:
   * Detect the **HTF sweep**: has C2 (so far) traded beyond `C1_High` (short candidate) or
     `C1_Low` (long candidate)?
   * Once swept, begin scanning the manipulation leg for **CISD** and, **only after the wick has
     breached C1's extreme**, for an **IFVG** (§5). IFVGs may only be *looked for* after C2 has
     gone above/below the C1 wick extreme, and only until a trigger fires or the setup invalidates.
3. **C2 closes.**
   * If C2 closed **back inside** C1 on the swept side → bias confirmed (§1).
   * If C2 closed **outside** C1 → **invalidate** the setup.
4. **50% guard.** If, at any time before entry, price has already reached `C1_EQ` on the trade
   side (i.e. C2 already took 50% of C1), **no entry is taken** — the reward is gone (§6.1).
5. **Trigger & entry** per the selected model (§5, §6). Entry may occur inside C2 (deferred to C3
   open) or inside C3.
6. **Setup window ends at C3 close.** After that, no entry for this C1.
7. **In trade**: managed to **TP = C1_EQ** or **SL = just past the sweep wick** (§7). No trailing,
   no break-even.

---

## 4. Directional Filter (Bias from the Sweep)

| C2 sweep of C1 | C2 close condition        | Bias  | Target |
|----------------|---------------------------|-------|--------|
| C1_High swept  | Close back below C1_High  | SHORT | C1_EQ  |
| C1_High swept  | Close above C1_High       | Invalid (breakout) | — |
| C1_Low swept   | Close back above C1_Low   | LONG  | C1_EQ  |
| C1_Low swept   | Close below C1_Low        | Invalid (breakout) | — |
| neither        | —                         | No setup | —   |

If C2 sweeps **both** sides (outside bar), use the side whose close-back-inside condition holds;
if both hold, prefer the side price most recently returned from (the last extreme touched). This
is an edge case; log it.

---

## 5. Trigger Primitives — CISD & IFVG

The EA exposes **`EntryTriggerModel`** with three options; **CISD is the default**:

1. **CISD** (default)
2. **IFVG**
3. **CISD + IFVG** (both must be satisfied by the confirming candle)

### 5.1 CISD — Change in State of Delivery (precise)

CISD is the LTF candle close that proves delivery flipped back into the range.

* **Bearish CISD (for a SHORT setup, after a C1_High sweep):** a candle closes **below** the
  reference **open** of the up-close run that drove price above C1_High.
* **Bullish CISD (for a LONG setup, after a C1_Low sweep):** a candle closes **above** the
  reference **open** of the down-close run that drove price below C1_Low.

**Reference point — input `CISD_ReferenceMode`:**

* **Mode A — "Single Candle" (default):** reference = the Open of the single most recent
  opposite-delivery candle immediately before the reversal (for a short: the last up-close
  candle's open; for a long: the last down-close candle's open).
* **Mode B — "Consecutive Sequence":** if an **uninterrupted run** of same-delivery candles
  (e.g. a stream of up-close OLHC candles) led into the sweep, treat the whole run as a single
  candle and use the **Open of the *first* candle in that run** (the open furthest back).

> **Worked example (from the source).** C1 = 04:00 on 1H. At 05:00 (C2) on the 5m LTF we look for
> the last up-close candle to trade above 04:00's high. If that candle's **open** is later closed
> **below**, that is a CISD (short). If an uninterrupted stream of up-close candles led into the
> sweep, they count as one candle and the **first** candle's open in the run must be closed below.

### 5.2 IFVG — Inverted Fair Value Gap

* IFVGs are only **searched for after C2 has breached C1's wick extreme**, and only until a
  trigger fires or the setup invalidates.
* For a **SHORT** setup: identify a **bullish FVG** formed during the upside sweep. When a later
  candle **closes fully below** that FVG's far boundary (nearest its candle1), the FVG inverts →
  IFVG short trigger. (By construction this close also satisfies bearish CISD.)
* For a **LONG** setup: mirror — a **bearish FVG** formed during the downside sweep, inverted when
  a later candle **closes fully above** its far boundary.

### 5.3 Combined model (CISD + IFVG)

The confirming candle must satisfy **both** CISD (§5.1) and the IFVG inversion (§5.2) — in practice
the inverting candle usually satisfies CISD automatically, but both are checked explicitly.

---

## 6. Entry Execution

Once the selected trigger fires (during C2 or C3), determine the entry:

### 6.1 The 50% reward guard (mandatory pre-check)

* Target `TP = C1_EQ`. Compute the reward available from the prospective entry to `C1_EQ`.
* If price has **already reached C1_EQ** (C2 took ≥50% of C1) → **skip the setup entirely**.

### 6.2 Market vs 1:1 limit

Let `risk = |entry − SL|` where SL is just past the sweep wick (§7), and
`reward = |C1_EQ − entry|`.

* **If `reward ≥ risk` (≥ 1:1 available at market):** enter **at market** on the close of the
  confirming candle.
* **If `reward < risk` (market entry would be < 1:1):** do **not** market-fill. Instead place a
  **limit** at the price that yields exactly **1:1** (i.e. `limit = C1_EQ ∓ risk`, on the trade
  side, so that entry-to-EQ distance equals the risk distance).
  * **Cancel rule:** if price reaches `C1_EQ` (the 50% level) **before** the limit fills, cancel
    the limit — the opportunity is gone.
  * **No time cancel:** otherwise the limit rests indefinitely (no matter how long price ranges
    between 50% and the limit) until it fills, `C1_EQ` is hit, or the setup invalidates.

### 6.3 CISD-in-C2 carry-over

If the CISD (or CISD+IFVG) confirmation occurred **inside C2**, it **carries over to C3**: place
the market/limit order at **C3 open**, applying the same §6.1/§6.2 rules at that moment.

### 6.4 Concurrency

**One active trade at a time, globally.** While a position is live **or** a working entry
(limit/pending) exists, no other slot may arm a new entry. Other slots continue to be *tracked
and drawn*, but cannot place orders until the active trade/limit resolves.

---

## 7. Risk & Trade Management

* **Position sizing / contracts / lots / margin caps** — lifted verbatim from ORB (`ORB_Risk` /
  MT5 position sizer): risk-% of balance, margin-usage cap, Micro/Mini contract caps (C#),
  broker lot constraints (MT5).
* **Stop Loss:** placed just **past the sweep wick** (the manipulation-leg extreme) plus a small
  configurable buffer (`SL_BufferPoints`, plus any broker min-stop distance on MT5). For a short:
  above the sweep high; for a long: below the sweep low.
* **Take Profit:** `C1_EQ` (50% of C1). Single fixed target.
* **Minimum RR:** `MinRR` default **1:1** (§6.2 enforces it via the limit mechanism). If the
  broker min-stop / spread makes the 1:1 SL un-placeable, **skip the trade**.
* **No trailing, no break-even, no OCO** (explicit exclusion).
* **Re-entry:** after a stop-out, a fresh qualifying setup on a *new* C1 may trade (subject to the
  single-active-trade rule). Once TP is hit for a given C1, that C1 is done.

---

## 8. Time / Session Filter (optional)

* **Default: trade 24h** — every qualifying HTF candle.
* **Optional C3-hour filter** (`Use_ExecHourFilter`, default **off**), modelled on **CCT's**
  multi-hour selection: a CSV of allowed **NY hours** (`ExecHoursNY`, e.g. `"3,7,10"`). When
  enabled, a setup may only execute if **C3 (the execution candle) opens in an allowed NY hour**.
  Hours outside the list are tracked/drawn but never traded.
* Parsing/`HasHour` semantics mirror CCT (`AppendHourSlots` / `IsExecHour`).

---

## 9. News Filter

Lifted from ORB (`ORB_News` / CCT news layer):

* ForexFactory weekly JSON feed (live) + local cache + optional historical CSV for backtests.
* `NewsGuardMode`: Off / RedOnly / RedAndOrange / All (USD events).
* When inside a blackout window (`BlockMinutesBefore` / `BlockMinutesAfter` around an event of
  the selected impact), **no new entries** are placed. (No trailing freeze — there is no trailing.)
* Dashboard shows the next event + countdown and a blackout indicator.

---

## 10. Notifications

Lifted from ORB (`ORB_Notify`) / CCT notify layer — Discord webhook + Telegram bot, background
send queue with retry and dedupe (`ClaimOnce`). Events:

* **Setup armed** (bias, C1 range, EQ, trigger model, SL/TP).
* **Order filled** (dir, fill, SL, TP, size).
* **Trade closed** (dir, entry→exit, PnL, %).
* **Limit cancelled** (reason: 50% reached / setup invalid / window end).

---

## 11. Dashboard & Visuals

* **NT8 variant:** repurpose the **ORB_NT liquid-glass Direct2D dashboard** (`ORB_Dashboard`).
* **MQL5 variant:** repurpose the **CCT dashboard** (`CCT_Dashboard` / `CCT_Visual`).
* CRT-specific fields to surface: active slot & C1 timeframe, C1 High/Low/EQ, bias, sweep status,
  trigger model, CISD status, IFVG status, entry (market/limit + level), SL/TP, live R, plus the
  standard account/compliance/news rows already in the ORB/CCT dashboards.
* Visuals: C1 range box, EQ (50%) line, sweep wick marker, CISD level line, FVG/IFVG zone,
  entry/SL/TP lines — drawn per slot, back-drawn 2–3 NY days.

---

## 12. Consolidated Parameter List

| Parameter | Type | Default |
|-----------|------|---------|
| `RiskPercent` | double | 1.0 |
| `ContractMode` (NT8) / lot mode (MT5) | enum | Micro |
| `EnableIntraday` | bool | true |
| `IntradayTF` | enum {15m,30m,1H,2H,4H} | 1H |
| `EnableDaily` / `EnableWeekly` / `EnableMonthly` | bool | false |
| `ExecTFMinutesOverride` | int (0 = auto) | 0 |
| `EntryTriggerModel` | enum {CISD, IFVG, CISD_IFVG} | CISD |
| `CISD_ReferenceMode` | enum {SingleCandle, ConsecutiveSequence} | SingleCandle |
| `MinRR` | double | 1.0 |
| `SL_BufferPoints` | double | (per-instrument small) |
| `Use_ExecHourFilter` | bool | false |
| `ExecHoursNY` | string CSV | "" |
| `NewsGuardMode` | enum | RedOnly |
| `NewsBlockMinutesBefore` / `After` | int | 5 / 5 |
| `EnableDiscord` / `EnableTelegram` | bool | false |
| `DiscordWebhookUrl` / `TelegramBotToken` / `TelegramChatId` | string | "" |
| `ShowDashboard` / `ShowVisuals` | bool | true |

---

## 13. Open Confirmations / Assumptions

* **[ASSUMED]** Outside-bar C2 (both sides swept): trade the side price last returned from; logged.
* **[ASSUMED]** When `EntryTriggerModel = CISD` alone, no FVG is required; entry is at the CISD
  candle close under §6.
* **[ASSUMED]** Monthly slot uses H4 LTF by auto-derivation; override applies globally if set.
* **[ASSUMED]** `MinRR` default 1:1 per the user's "at least 1:1" instruction; exposed for tuning.
