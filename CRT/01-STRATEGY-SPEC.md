# CRT — Candle Range Theory EA · Strategy Specification (Platform-Agnostic)

> **Document 1 of 3.** This file defines *what* the system trades — the pure trading logic, independent of NinjaTrader (C#) or MetaTrader 5 (MQL5). Document 2 (`02-NT8-IMPLEMENTATION.md`) and Document 3 (`03-MQL5-IMPLEMENTATION.md`) define *how* each platform implements this spec by lifting proven modules from the ORB, CCT, and DTR-CRT code already in this repository.
>
> This document is written for direct consumption by a coding LLM/automation engine. Every rule is stated explicitly. Where the source material was silent or ambiguous, it is flagged **[CONFIRM]** rather than silently assumed.
>
> **All times are New York (America/New_York) time unless stated otherwise.**

---

## 0. Naming, Scope, and Provenance

- **System name:** **CRT (Candle Range Theory)**.
- **Variants:**
  - `CRT_NT` — C# NinjaScript strategy for NinjaTrader 8. Built first.
  - `CRT_MT5` — MQL5 Expert Advisor for MetaTrader 5. Built second, to parity.
- **Reused engines (do NOT rebuild — port):**
  - **Time / DST / session-anchor math, position sizing, margin caps, trailing/BE, persistence, and the NT8 dashboard** → lifted from **`ORB_NT`** (C#) and **`ORB_Scalper`** (MQL5).
  - **FVG / IFVG detection, the C1/C2/C3 FVG-generation model, the multi-intraday execution-hour filter, and the MQL5 dashboard** → lifted from **`CCT`** (MQL5, `CCT_EA_v7`).
  - **CRT bias / CISD / FVG / manipulation-leg definitions** → refined from **`DTR-CRT`** (`DTR_CRT_Strategy_Spec_v2.md`).
- The DTR-CRT EA is a *time-window* CRT (fixed London/NY range windows). **CRT is different:** it is a *rolling per-candle* CRT — **every** higher-timeframe candle is a self-contained range that can produce a setup, subject to one-trade-at-a-time concurrency.

---

## 1. Core Concept — The Three-Candle Model

Candle Range Theory treats every higher-timeframe (HTF) candle as a self-contained institutional range. Three consecutive HTF candles form the model:

| Candle | Role | What happens |
|--------|------|--------------|
| **C1** | **Range** | The reference candle. Its High and Low define the range; its 50% midpoint is **EQ**. |
| **C2** | **Manipulation** | Price sweeps (wicks beyond) C1's High or Low to grab liquidity, then reverses back inside C1's range. |
| **C3** | **Distribution / Execution** | Price expands in the reversal direction. Entry is executed here (or carried from C2), targeting C1's EQ. |

- A **high sweep** in C2 → **SHORT** bias (sell the failed breakout, target EQ from above).
- A **low sweep** in C2 → **LONG** bias (buy the failed breakdown, target EQ from below).

Because the model is **rolling**, candle N is C1 for the sequence (N, N+1, N+2); candle N+1 is simultaneously C1 for its own later sequence. Overlap is resolved by the **one-active-trade-at-a-time** rule (Section 9).

### 1.1 Definitions (read first)

- **Bullish candle:** Close > Open. **Bearish candle:** Close < Open. **Doji:** Close == Open (treated as its own prior-direction-neutral; see CISD run rules).
- **HTF sweep of a level:** an HTF/LTF price prints beyond C1's High (up-sweep) or C1's Low (down-sweep) — a **wick** beyond the level is sufficient to arm the sweep; a close beyond is *not* required to arm it.
- **Valid manipulation (close back inside):** after the sweep, price must trade back inside C1's range. If C2 **closes** beyond C1's swept extreme (a genuine breakout/continuation), the setup for that direction is **invalid** (see 3.3).
- **Manipulation leg:** the swing from the moment C1's level is first breached to the most extreme point reached in the breach direction, immediately before the reversal. Its extreme becomes the Stop-Loss anchor.
- **EQ (Equilibrium):** exact midpoint price of C1 = `(C1_High + C1_Low) / 2`. This is the **profit target**.
- **FVG (Fair Value Gap):** a 3-candle imbalance (candle a / b / c). **Bullish FVG:** `a.High < c.Low`; gap zone = `[a.High, c.Low]`. **Bearish FVG:** `a.Low > c.High`; gap zone = `[c.High, a.Low]`.
- **IFVG (Inverted FVG):** an FVG that price closes *completely* through (a candle closes beyond the gap's far boundary — the boundary nearest candle `a`). After inversion the zone flips polarity and the inverting close is the trigger.
- **CISD (Change in State of Delivery):** a close beyond the origin of the last opposing candle run, proving delivery flipped. Precise definition in Section 5.
- **HTF slot / C1 timeframe:** the timeframe on which C1/C2/C3 are measured (Section 2).
- **LTF / execution timeframe:** the lower timeframe on which the sweep, CISD, FVG/IFVG, and entry are read (Section 2.2).

---

## 2. Timeframe Model — Slots and Execution Timeframe

### 2.1 HTF Slots (C1 timeframe)

Four independently-enabled slots. Each enabled slot rolls its own C1→C2→C3 sequence continuously.

| Slot | C1 timeframe | Sub-slot options | Anchor |
|------|--------------|------------------|--------|
| **Intraday** | user-selected sub-slot | **M15, M30, H1, H2, H4** | broker/exchange candle boundaries (NY-aligned) |
| **Daily** | 1 day | — | NY **True Day** open (18:00 NY prior day) |
| **Weekly** | 1 week | — | NY **True Week** open (Sunday 18:00 NY) |
| **Monthly** | 1 month | — | NY **True Month** open |

- **Only the Intraday slot has a sub-slot timeframe selector** (`IntradayC1_TF` ∈ {M15, M30, H1, H2, H4}). When Intraday=H1, **every** 1H candle is a candidate C1 ("trade all 1H candles that form the setup").
- Daily/Weekly/Monthly C1 boundaries use the same **True Day/Week/Month open** math as ORB (18:00 NY anchor), *not* the raw broker D1/W1/MN1 candle. This is a lift from `ORB_Time`.
- **[CONFIRM]** Multiple HTF slots may be enabled simultaneously (e.g. Intraday H1 + Daily). Concurrency (Section 9) still caps live exposure to one trade globally; the first slot to trigger wins.

### 2.2 Execution (LTF) timeframe — auto-derived with single override

The LTF is where the sweep, CISD, FVG/IFVG, and entry are evaluated. It is chosen as follows:

1. **`ExecTF_OverrideMinutes`** (single integer input, default **0 / empty**).
   - If **> 0**, the LTF is exactly that many minutes **for every slot**, regardless of the HTF model chosen. (e.g. type `5` → M5 LTF everywhere.)
   - If **0 / empty**, the LTF is **auto-derived per slot** from the table below.

2. **Auto-derivation table (when override is empty):**

   | C1 timeframe | Auto LTF |
   |--------------|----------|
   | M15 | M1 |
   | M30 | M1 |
   | H1 | **M5** |
   | H2 | M5 |
   | H4 | M15 |
   | Daily | **M15** |
   | Weekly | **H1 (60m)** |
   | Monthly | H4 (240m) |

   (User-anchored points: H1→M5, Daily→M15, Weekly→H1, Monthly→H4. The remaining rows are interpolated for completeness and are **[CONFIRM]**-adjustable.)

---

## 3. Phase 1 — C1 Range Formation & C2 Sweep Detection

### 3.1 Locking C1

- When a new HTF candle (per the slot's timeframe/anchor) **closes**, that closed candle becomes the current **C1** for a fresh rolling sequence. Lock `C1_High`, `C1_Low`, `C1_Open`, `C1_Close`, and compute `EQ`.
- The EA must be able to reconstruct C1 if it initializes mid-sequence (read historical bars), mirroring how CCT rebuilds recent structure from the previous 2–3 NY days.

### 3.2 C2 sweep

- During the **next** HTF candle (C2), monitor the LTF for a sweep:
  - **Up-sweep:** LTF price prints above `C1_High` → arm **SHORT** candidate.
  - **Down-sweep:** LTF price prints below `C1_Low` → arm **LONG** candidate.
- A sweep **arms** the setup; it does not yet trigger it. Once armed, begin looking for CISD / IFVG (Section 4–5). **IFVG may only be searched for *after* the sweep has occurred** (price has gone beyond C1's wick), and only until trigger or invalidation.

### 3.3 Invalidation of the manipulation premise

The setup for a given direction is invalid if any of the following occur before a valid trigger:

1. **C2 closes beyond the swept extreme** — up-sweep where `C2_Close > C1_High` (bullish continuation) invalidates the SHORT; down-sweep where `C2_Close < C1_Low` invalidates the LONG. This is a genuine breakout, not a manipulation. **[CONFIRM]** — matches DTR "No Trade" handling.
2. **EQ already taken by C2** — if price reaches or trades through `EQ` during the sweep/manipulation (before any entry), there is **no profit left to target**: skip the setup (Section 7.2).
3. **C3 window ends** with no trigger (Section 8 lifecycle).
4. Price trades beyond the manipulation-leg extreme + SL buffer before a fill (stop-out of the premise).

---

## 4. Phase 2 — Trigger Models

`EntryTriggerMode` ∈ **{ CISD (default), IFVG, CISD_AND_IFVG }**.

- **CISD** — enter on Change in State of Delivery only (Section 5).
- **IFVG** — enter on Inverted FVG only (Section 6).
- **CISD_AND_IFVG** — both conditions must be satisfied (the inverting candle must also satisfy CISD; in practice IFVG inversion implies CISD, so this is the strictest confirmation).

All triggers are evaluated on the **LTF**, only **after** the C2 sweep has armed the setup, and only in the **reversal** direction (short after an up-sweep, long after a down-sweep).

---

## 5. CISD — Change in State of Delivery (precise)

CISD is the LTF candle **close** that proves delivery has flipped against the sweep.

### 5.1 The opposing run and its origin

- For a **SHORT** setup (up-sweep of `C1_High`): find the **up-close (bullish) candle, or the uninterrupted run of consecutive up-close candles, that produced the sweep** above `C1_High` on the LTF.
  - If a **single** bullish candle made the sweep → the **reference origin** is that candle's **Open**.
  - If an **uninterrupted run** of consecutive bullish candles led into the sweep → treat the whole run as **one** synthetic bullish candle; the reference origin is the **Open of the *first* candle in the run** (equivalently, the **lowest Open** of the run).
  - **CISD confirmed** when a subsequent LTF candle **closes below** that reference origin Open.
- For a **LONG** setup (down-sweep of `C1_Low`): symmetric — the down-close (bearish) candle/run that swept below `C1_Low`; reference origin = **Open of the first candle** of the run (equivalently the **highest Open**). **CISD confirmed** when a subsequent LTF candle **closes above** that reference origin Open.

### 5.2 "Uninterrupted run" rule

- A run is broken by any candle of the opposite body direction. A **doji** (Close == Open) **[CONFIRM]** does not extend and does not break the run; it is skipped. (Alternative: treat doji as break — flagged for backtest.)
- The run considered is the one immediately preceding / producing the sweep extreme — i.e. the last same-direction sequence that pushed price beyond C1's level.

### 5.3 CISD reference mode (configurable)

`CISD_ReferenceMode` ∈ { **RunOrigin (default)**, SingleCandle }:
- **RunOrigin:** use the first-candle Open of the consecutive run (Section 5.1). This is the user's primary definition.
- **SingleCandle:** always use only the single most-recent opposing candle's Open, ignoring the run. Exposed for backtesting.

### 5.4 CISD carry-over from C2 to C3

- If CISD confirms **within C2** (i.e. the confirming LTF close occurs while the C2 HTF candle is still forming), the trigger is **held** and the order is placed at **C3 open** (market or limit per Section 7). Entry is **not** taken mid-C2.
- If CISD confirms **within C3**, entry is executed **immediately** on that LTF close (market or limit per Section 7).
- **[CONFIRM]** carry-over spans exactly one candle (C2→C3). If CISD has not confirmed by the end of C3, the setup expires.

---

## 6. IFVG — Inverted Fair Value Gap (revised from CCT)

- IFVG search begins **only after** the C2 sweep (price beyond C1's wick) and runs until trigger or invalidation.
- **SHORT setup:** locate a **bullish FVG** formed during the up-sweep manipulation leg. When a later LTF candle **closes completely below** that FVG's **far boundary** (boundary nearest its candle `a`, i.e. the lower edge `a.High`), the FVG **inverts** → **SHORT trigger**.
- **LONG setup:** locate a **bearish FVG** formed during the down-sweep leg. When a later LTF candle **closes completely above** its far boundary (`a.Low`) → **LONG trigger**.
- The inverting close, by construction, also closes beyond the prior opposing structure and therefore also satisfies CISD (this is why `CISD_AND_IFVG` collapses to "IFVG with CISD-consistency check").
- Port the FVG-generation and inversion primitives from `CCT_Scanner.mqh` / `CCT_EA_v7.mq5` (the `close > c1Ext` inversion test), re-scoped to the C1/C2 manipulation window rather than CCT's POI generations.

---

## 7. Phase 3 — Entry, Target, Stop, and the 1:1 Rule

### 7.1 Target and Stop

- **Take Profit (TP) = `EQ`** (50% of C1). Short targets EQ from above; long targets EQ from below. Single fixed target; no partials unless added separately.
- **Stop Loss (SL) = just past the manipulation-leg extreme:**
  - Short: `SL = manipulationHigh + buffer`.
  - Long: `SL = manipulationLow − buffer`.
  - `buffer` = max(broker min-stop distance, spread, a small configurable tick pad).

### 7.2 The 50%-taken filter

- **No entry if `EQ` has already been reached or traded through by C2** (before entry). The target is spent; skip the setup. This is a hard precondition, checked at the moment a trigger would otherwise fire.

### 7.3 Market vs Limit — the minimum-1:1 rule

Let `risk = |entry_candidate − SL|` and `reward = |EQ − entry_candidate|`.

1. Determine the **market entry candidate** (current price at the confirming LTF close, or C3 open for a carried CISD).
2. **If `reward / risk ≥ MinRR`** (default `MinRR = 1.0`): **enter at market** immediately.
3. **If `reward / risk < MinRR`:** do **not** market-fill. Instead place a **working LIMIT** at the price that makes `reward / risk == MinRR` exactly (a deeper/better entry back toward the sweep). The limit is a pullback entry.
4. **If price reaches `EQ` before the limit fills → cancel the limit** (target reached without us; setup dead).
5. Once the limit is working, **it stays working with no time-based expiry** — "no matter how long price ranges between EQ and the limit, wait for anything to get hit" — until filled, EQ-cancelled (step 4), SL-invalidated, or the C3 lifecycle ends (Section 8). **[CONFIRM]** whether an unfilled limit is cancelled at C3 close or allowed to persist further.

### 7.4 Order placement summary

| Confirmation timing | Action |
|---------------------|--------|
| CISD/IFVG confirmed **within C3** | evaluate 7.3 immediately on the LTF close: market if ≥ MinRR, else working limit |
| CISD confirmed **within C2** (carry-over) | place order at **C3 open**: market if ≥ MinRR at C3 open price, else working limit |

---

## 8. Setup Lifecycle (state machine)

```
IDLE ──(C1 closes)──► RANGE_LOCKED
RANGE_LOCKED ──(C2 wick beyond C1 High/Low)──► SWEPT (bias set)
SWEPT ──(C2 closes beyond swept extreme)──────► INVALID
SWEPT ──(EQ reached before entry)─────────────► INVALID (target spent)
SWEPT ──(CISD/IFVG per mode)──────────────────► TRIGGERED
TRIGGERED ──(reward/risk ≥ MinRR)─────────────► LIVE (market fill)
TRIGGERED ──(reward/risk < MinRR)─────────────► WORKING_LIMIT
WORKING_LIMIT ──(fill)────────────────────────► LIVE
WORKING_LIMIT ──(EQ reached first)────────────► INVALID (cancel limit)
LIVE ──(price hits EQ)────────────────────────► CLOSED_TP
LIVE ──(price hits SL)────────────────────────► CLOSED_SL
(any) ──(C3 window ends w/o TRIGGERED)────────► EXPIRED   [CONFIRM]
```

- Each enabled slot runs this machine on its rolling sequence, but only **one** machine may be in `WORKING_LIMIT` or `LIVE` at a time globally (Section 9).

---

## 9. Concurrency — One Active Trade at a Time (global)

- **At most one setup may be armed-with-order (`WORKING_LIMIT`) or `LIVE` at any moment across all slots.**
- While one setup occupies that single slot, newly-swept/triggered setups on any slot are **ignored** (tracked for visuals only) until the occupying trade closes or its limit is cancelled/invalidated.
- **[CONFIRM]** A `WORKING_LIMIT` counts as occupying the slot (so we never stack a live trade on top of a pending one). If the user later wants "one per slot" or "unlimited", this is a single gating flag.

---

## 10. Risk, Sizing, Trailing, Break-Even (lift from ORB)

- **Position sizing:** risk-percent model with margin-usage cap and Micro/Mini contract modes — port `ORB_Risk.CalcContracts` / `MarginCappedContracts` verbatim (C#), and the MQL5 sizing from `ORB_Scalper`.
- **No fixed SL/TP distance inputs.** SL and TP are derived per-setup from price (manipulation extreme and EQ). The ORB `FixedSLPoints`/`FixedTPPoints` inputs are **removed**; sizing uses the live `|entry − SL|` distance.
- **Trailing / Break-Even:** port ORB's snapshot-frozen trailing engine (`ORB_Execution.ComputeTrailTarget`): Continuous/Step modes, BE-only mode, spread compensation, min-trail-seconds gate, forward-only. Geometry is frozen at fill so mid-trade input changes never affect an open position.
- **MinRR** default 1.0 (user: "at least 1:1"). Optional **`ReqRR`** ≥ MinRR may extend the target beyond EQ **[CONFIRM]** — by default TP stays at EQ.

---

## 11. Optional C3 Execution-Hour Filter (CCT-style)

- **`EnableExecHourFilter`** (default **false** → trade 24h, every qualifying candle).
- **`ExecHoursNY`** — a multi-select set of NY hours `{0..23}`. When the filter is ON, a setup may **only execute if the C3 (execution) candle's opening hour ∈ `ExecHoursNY`**. Example: `{3, 7, 10}` → only the 03:00, 07:00, and 10:00 NY candles may host C3/execution.
- Modeled on **CCT Chapter 8** (Execution Hours, C1 Authority, Kill Rule) and CCT's multi-intraday hour selection UI — preferred here over ORB's single-hour session model.
- For sub-hour Intraday TFs (M15/M30), the gate uses the C3 candle's **opening hour**; for H2/H4 the C3 candle's opening hour must be in the set.
- **[CONFIRM]** the filter gates the **C3/execution** candle (not C1 or C2), per the user's "if 3, 7 and 10 are enabled only 3am, 7am & 10am can be Candle 3".

---

## 12. Visualization (parity across variants)

- **C1 range box** (High↔Low across the C1 candle), **EQ line** (50%), optional fib-style range measurement with a visibility toggle (from DTR).
- **Sweep marker** on the manipulation extreme; **CISD line** at the reference origin Open; **FVG/IFVG box** (from CCT visuals).
- **Entry / SL / TP** objects and resolved-trade display (lift ORB visuals for NT8; CCT visuals for MQL5).
- All object anchoring must use real bar times (never wall-clock) so weekend/sparse data never distorts boxes — lift ORB's bar-time anchoring discipline.

---

## 13. Persistence & Restart Safety (lift from ORB)

- **Closed-trade ledger** (append-only CSV), **live-trade snapshot** (re-adopt open positions after restart), and a **consumed ledger** keyed by **C1 candle identity** (slot + C1 open time + side) so a restart never re-arms a C1 sequence that already traded. Port `ORB_State`.
- Draw setups from the **previous 2–3 NY days** on init (CCT behavior) so mid-day (re)starts reconstruct recent C1/C2/C3 context.

---

## 14. Full Input Catalog (platform-agnostic)

| Input | Type | Default | Notes |
|-------|------|---------|-------|
| `RiskPercent` | double | 1.0 | % of balance risked per trade |
| `ContractMode` / lot mode | enum | Micro | Micro/Mini (NT8); lot mode (MQL5) |
| `MaxContractsOverride` | int | 0 | 0 = use mode cap |
| `MaxMarginUsagePercent` | double | 50 | margin budget cap |
| `EnableIntraday` | bool | true | |
| `IntradayC1_TF` | enum | H1 | M15/M30/H1/H2/H4 |
| `EnableDaily` | bool | false | |
| `EnableWeekly` | bool | false | |
| `EnableMonthly` | bool | false | |
| `ExecTF_OverrideMinutes` | int | 0 | 0/empty = auto-derive per slot |
| `EntryTriggerMode` | enum | CISD | CISD / IFVG / CISD_AND_IFVG |
| `CISD_ReferenceMode` | enum | RunOrigin | RunOrigin / SingleCandle |
| `TreatDojiAsBreak` | bool | false | CISD run rule [CONFIRM] |
| `MinRR` | double | 1.0 | market-vs-limit threshold |
| `ReqRR` | double | 0 | 0 = TP stays at EQ [CONFIRM] |
| `SL_BufferTicks` | int | broker-min | pad past manipulation extreme |
| `EnableExecHourFilter` | bool | false | CCT-style C3-hour gate |
| `ExecHoursNY` | set<int> | {} | active NY hours for C3 |
| `TrailMode` | enum | Continuous | Continuous/Step |
| `TrailBehavior` | enum | Trail | Trail / BE-only / Off |
| `TrailThreshold` / `TrailGap` | double | — | price-unit distances |
| `MinTrailSeconds` | int | 0 | activation gate |
| `SpreadComp` | bool | true | spread/commission compensation |
| `ShowVisuals` | bool | true | |
| `ShowRangeMeasurement` | bool | true | EQ fib toggle |
| `ShowDashboard` | bool | true | |

---

## 15. Open Questions (all **[CONFIRM]** flags, consolidated)

1. C2-close-beyond-extreme → treat as hard "No Trade" for that direction (assumed yes).
2. Doji handling inside a CISD run (assumed: skip, don't break).
3. Setup expiry: does an unfilled working limit / untriggered setup die at C3 close, or persist? (assumed: dies at end of C3).
4. Does a `WORKING_LIMIT` occupy the single global concurrency slot? (assumed: yes).
5. Auto-LTF rows for M15/M30/H2/Monthly (H1/Daily/Weekly anchored by user).
6. `ReqRR` extension of TP beyond EQ (assumed: off; TP = EQ).
7. Multiple HTF slots enabled at once — allowed, first-to-trigger wins (assumed yes).

> Resolve these against live examples before locking the backtest. Every other rule in this document is deterministic and complete.
