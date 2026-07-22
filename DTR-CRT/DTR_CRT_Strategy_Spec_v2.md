# DTR Time-Based Range + CRT Bias Strategy — Full Algorithmic Specification (v2)

This document is written for direct consumption by a coding LLM/automation engine. Every rule is stated explicitly in plain English. Where the source material was silent or ambiguous, this is flagged under **\[CONFIRM]** rather than silently assumed. No formulas or code are used — only procedural logic.

\---

## 0\. Conventions \& Definitions (read first)

* **Bullish candle**: Close > Open.
* **Bearish candle**: Close < Open.
* **Candle high:** Wick > Open.
* **Candle low:** Wick < Open.
* **HTF Sweep of a level**: price trades beyond the prior candle range's level (Candle high/low) intrabar (wick is sufficient — the candle's High or Low penetrates the level). A LTF sweep does NOT require a close beyond the level, only a HTF sweep does.
* **Close back inside**: after sweeping a level, the candle's Close is on the original side of that level (i.e., the close is below the swept candles high (if the high was swept) or the close is above the swept candles low if the low was swept)), note a HTF sweep requires a close to be confirmed, a LTF sweep does not, because a LTF sweep/manipulation leg could contain several candles beyond the range to reverse, but on the HTF bias, only 1 candle can define and use the range, so it has to be that prior candle that either defines the bias, sweeps its own prior candles level(s), or creates a neutral bias.
* **LTF Displacement**: a strong, often larger-than-average directional candle or short sequence of same-direction candles following a sweep, indicating intent to reverse.
* **Manipulation leg**: the price swing that runs from the moment Range\_High or Range\_Low is first breached, up to the most extreme point reached in that breach direction (the swing low to the last swing high for an upside sweep, the swing high to the last swing low for a downside sweep), immediately before price reverses, gives an entry back into/through the range.
* **Gap / FVG (Fair Value Gap)**: a 3-candle formation. Candle 1 = first candle, Candle 2 = the displacement candle that creates the imbalance, Candle 3 = the candle that does not trade back into Candle 1's range.

  * **Bullish FVG**: Candle 1's High is below Candle 3's Low. The gap zone runs from Candle 1's High (lower boundary) to Candle 3's Low (upper boundary).
  * **Bearish FVG**: Candle 1's Low is above Candle 3's High. The gap zone runs from Candle 3's High (lower boundary) to Candle 1's Low (upper boundary).
* **CISD (Change in State of Delivery)**: a close beyond a defined reference point that proves delivery has flipped direction. Full definition and reference point given in Section 4.1.
* **IFVG (Inverted Fair Value Gap)**: an FVG that price closes completely through (a candle closes beyond the gap's far boundary — the boundary nearest Candle 1). Once this happens, the gap is considered "inverted" and now acts as support/resistance in the opposite direction to its original delivery.
* All times are New York time unless stated otherwise.

\---

## 1\. Global Parameters

|Session|Range Window (NY Time)|Trading Window (NY Time)|HTF Bias Candle Size|Execution (LTF) Timeframe|Primary Target|
|-|-|-|-|-|-|
|**London**|01:12 – 02:12|02:12 – 04:00|3.5-Hour|4-Minute|Opposite range boundary|
|**New York**|08:12 – 09:12|09:30 – 10:30|7-Hour|1-Minute|Opposite range boundary|

All clock times above must be exposed as **configurable inputs** (not hardcoded), since DST shifts and broker server-time offsets will change the literal value while the relative structure stays fixed. However, for this project I would strongly advice that you blindly lift/port all time-related implementations from the ORB\_Scalper EA, as I created a highly polished and sorted system there, after squashing way too many bugs creating that EAs timer, I's hate to do the same here too, so save yourself the time wastage and look at how it handles all things time-related there, other stuff like risk calculations, lots, margin, Non-visual vs Visual tester implementations, range entry/execution object visualizations, dashboard design and even pointing system, however, since SL \& TP amount is no longer predefined, and is based on price at the time of execution, there is no need for those manual SL/TP distance parameters, but since both strategies are based on ranges, and have a lot in common, you will have to take a lot out of that project to create this new EA, ensure you have those core things settled before moving onto the next phase, as you gradually make your way onto the different phases, you will need to sit back and review the ORB\_Scalper and CCT\_v7 EAs in order to port aspects of their implementations into this EA, you will rarely have to actually build anything new, because these two EA projects have already accomplished so much..

\---

## 2\. Phase 1 — HTF Bias Determination (Full Exhaustive Logic)

The bias filter is evaluated **once per session**, immediately after Reference Candle B closes, before the session's range window even opens.

### 2.1 Reference Candles

**New York session bias:**

* Reference Candle A = the 7-hour "Asia" candle, 18:00–01:00.
* Reference Candle B = the 7-hour "London" candle, 01:00–08:00.
* Evaluated at 08:00, once Candle B closes.

**London session bias:**

* Reference Candle A = the 3.5-hour candle, 18:00–21:30.
* Reference Candle B = the 3.5-hour candle, 21:30–01:00.
* Evaluated at 01:00, once Candle B closes.

The evaluation logic below is **identical for both sessions** — only the candle (time range) size and clock times differ.

### 2.2 Inputs needed per evaluation

* A\_High, A\_Low, A\_Close (of Reference Candle A)
* B\_High, B\_Low, B\_Close (of Reference Candle B)
* A\_EQ = the exact midpoint price between A\_High and A\_Low.

### 2.3 Step 1 — Classify the sweep condition

Compute four boolean flags:

* **SweptHigh(Bearish)** = true if B\_High trades above A\_High, but B\_Close < A\_High (**CloseAboveHigh (BullishContinuation)** = true if B trades, and closes above A, B\_Close > A\_High).
* **SweptLow(Bullish)** = true if B\_Low trades below A\_Low but B\_Close < A\_Low (**CloseBelowLow (BearishContinuation)** = true if B trades, and closes below A, B\_Close < A\_Low).

There are exactly six possible combinations. Evaluate in this order:

### 2.4 Case 1 — SweptHigh = true, SweptLow = false (single-side high sweep)

* If B\_Close is at or below A\_High (closed back inside A's range) → **SHORT BIAS**.
* If B\_Close is above A\_High (closed beyond A's high, i.e., did NOT close back inside) → **NO VALID BIAS — flag session as "No Trade."** This is a genuine bullish continuation/breakout, not a liquidity-sweep-and-reversal pattern, and the strategy's premise (CRT/manipulation logic) does not apply. Do not scan either direction for this session. **\[CONFIRM: source material did not explicitly state this branch; it is included for logical completeness rather than left undefined. Confirm this should be "No Trade" rather than treated as a continuation Long bias.]**

### 2.5 Case 2 — SweptLow = true, SweptHigh = false (single-side low sweep)

* If B\_Close is at or above A\_Low (closed back inside A's range) → **LONG BIAS**.
* If B\_Close is below A\_Low (did NOT close back inside) → **NO VALID BIAS — flag session as "No Trade."** Same reasoning as 2.4. **\[CONFIRM — same flag as above.]**

### 2.6 Case 3 — SweptHigh = true AND SweptLow = true (Candle B is an outside bar, sweeping both sides of Candle A)

* If B\_Close is above A\_EQ → **LONG BIAS**.
* If B\_Close is below A\_EQ → **SHORT BIAS**.
* If B\_Close is exactly equal to A\_EQ (price-for-price tie) → **NEUTRAL BIAS** (both directions valid). This is an extreme edge case included only for completeness/robustness in code; it will almost never trigger on live tick data. **\[CONFIRM: tie-break rule not specified in source, defaulted to Neutral for safety.]**
* **Note:** EQ meaning 50% of the entire Candle A range, measured via a fib retracement anchor, from Candle A Low to Candle A high, there should be a toggle that allows the visibility of the range measurement to be hidden/visible.

### 2.7 Case 4 — SweptHigh = false AND SweptLow = false (Candle B is an inside bar — no sweep of either side)

* → **NEUTRAL BIAS** (both directions valid — both long and short setups in the session's range are permitted).
* This rule was explicitly stated for the London session in the source material. It is applied identically to the New York session for logical symmetry, since the underlying mechanism (inside bar = no manipulation = no directional lean) is session-agnostic. **\[Explicit source confirmation only exists for London; New York inside-bar handling is inferred by symmetry.]**

### 2.8 Bias Output Summary Table

|SweptHigh|SweptLow|Close condition|Resulting Bias|
|-|-|-|-|
|true|false|Close ≤ A\_High|Short|
|true|false|Close > A\_High|No Trade|
|false|true|Close ≥ A\_Low|Long|
|false|true|Close < A\_Low|No Trade|
|true|true|Close > A\_EQ|Long|
|true|true|Close < A\_EQ|Short|
|true|true|Close = A\_EQ|Neutral|
|false|false|—|Neutral|

This table is exhaustive — every possible relationship between Candle A and Candle B maps to exactly one of these eight rows. Nothing is left undefined.

\---

## 3\. Phase 2 — Range Formation

1. During the Range Window (Section 1), continuously track the highest High and lowest Low printed. Note, the EA should be able to retrieve these values if initialized half-way, or at/after the end/close of the range, as long as the entry time has not passed yet, and the EA should be able to know if a trigger has been met at/after the execution window is open, but before it ends, once the execution window ends, the EA doesn't bother with any executions till the next Range formation/Execution window the next day, the EA should take after the CCT in that it should draw the executions from the previous 2 - 3 NY days prior to the current day, tell me if you need anything.
2. At the close of the Range Window, lock these as **Range\_High** and **Range\_Low**. These values do not change for the remainder of the session.
3. Compute **Range\_EQ** as the exact midpoint price between Range\_High and Range\_Low. Asides bias formation, this value can also be used later for break-even logic context and was historically used as an informal break-even reference point, but is superseded by the precise percentage-based break-even system defined in Section 5.3.

\---

## 4\. Phase 3 — Liquidity Purge \& Directional Filter

Once the Trading Window opens, monitor price relative to Range\_High/Range\_Low, filtered by the bias computed in Phase 1:

|Bias|Valid Setup(s)|
|-|-|
|Short|Only watch for price to trade above Range\_High (upside sweep), then look for a short entry targeting Range\_Low.|
|Long|Only watch for price to trade below Range\_Low (downside sweep), then look for a long entry targeting Range\_High.|
|Neutral|Watch for either: an upside sweep of Range\_High (short setup, target Range\_Low) AND/OR a downside sweep of Range\_Low (long setup, target Range\_High). Whichever occurs first is the one that gets traded.|
|No Trade|Do not monitor either boundary. No entries are scanned for this session at all.|

For the New York session specifically: even though Range\_High/Range\_Low are locked at 09:12, **do not begin scanning for boundary sweeps or entries until 09:30** (NY cash equity open). Any boundary breach between 09:12 and 09:30 is ignored, however  the FVGs formed can be stored as they may be what could be used, alongside potential CISD triggering, only the FVG retest entry model requires an FVG formed after 09:30, but the IFVG model requires only an inversion of an FVG born prior to but inverted from/after 09:30.

\---

## 5\. Phase 4 — LTF Entry Trigger Models (Fully Defined)

Two trigger models exist. Both are built on two precisely-defined primitives — **CISD** and **FVG/IFVG** — rather than the more subjective "market structure shift" concept. Swing-high/swing-low-based structure shifts are explicitly excluded from this specification because "swing" is not objectively definable; CISD+FVG Retest and CISD+IFVG are used instead because they are mechanically deterministic.

### 5.1 CISD — Change in State of Delivery (precise definition) + FVG Retest

CISD is the candle close that proves the delivery direction (the directional bias of the candle sequence) has flipped.

* **Bullish CISD**: a candle closes above the reference high of the most recent bearish candle (or bearish candle sequence) within the manipulation leg.
* **Bearish CISD**: a candle closes below the reference low of the most recent bullish candle (or bullish candle sequence) within the manipulation leg.

**Reference point — must be a configurable, backtestable input (`CISD\_ReferenceMode`)**, with two selectable modes:

1. **Mode A — "Single Candle" (default)**: the reference point is the High (for bullish CISD) or Low (for bearish CISD) of the single most recent opposite-colored candle that occurred immediately before the reversal began.
2. **Mode B — "Consecutive Sequence"**: if multiple consecutive opposite-colored candles occurred immediately before the reversal, the reference point is the Open of the *first* candle in that consecutive same-direction sequence (i.e., the open furthest back in the run), rather than just the most recent single candle.

CISD must occur **after** the manipulation leg (i.e., after the boundary sweep), confirming the reversal back toward the opposite range boundary.

### 5.2 Trigger Model A — IFVG Entry

1. Identify the FVG that formed as part of (or immediately following) the manipulation leg, in the direction opposite to the intended trade (e.g., for a short setup, identify a bullish FVG that formed during the upside sweep).
2. Wait for a subsequent candle to close completely beyond that FVG's far boundary (the boundary nearest Candle 1 of that FVG's 3-candle formation) — i.e., the candle fully closes through the gap, inverting it.
3. This closing candle, by construction, also satisfies the CISD condition in Section 5.1, since closing fully through the FVG necessarily closes beyond the prior opposing structure.
4. **Entry execution**: open a market order immediately upon the close of this confirming/inverting candle. No limit order, no waiting for retracement.

### 5.3 Trigger Model B — CISD + FVG Retest Entry (more conservative)

This model requires, in strict order:

1. **Liquidity sweep** of Range\_High or Range\_Low has occurred (per Phase 3).
2. **CISD has occurred** (Section 5.1) — this is mandatory. If no CISD has formed, there is no valid setup under this model; do not proceed Note: CISD can occur before, during or immediately after the FVG is formed, but as long as the range available for profit is still within the minimum allowed RR.
3. **A new FVG forms in the trade direction**, after the CISD, as price displaces away from the sweep. Since an FVG requires 3 candles, once price has created a new FVG in the bias direction, e.g., A bearish FVG in a bearish setup, the Sell limit is placed at the Candle 3 high, this is referred to as the **"1st Presented FVG" (1stPFVG)** — the first fresh FVG presented in the new (post-reversal) delivery direction. Note however, if price goes on, without executing the buy limit at the close of the 1stPFVG gap, there should be a configurable option to allows the EA to execute at market if the 1stPFVG is unfilled at the close of the immediate next LTF candle after the 1stPFVG is confirmed, provided the available range still allows the minimum TP preset, or execute market at the close of the candle 3 that confirms the 1stPFVG.
* Note: an Inverted FVG from Step 2's CISD may or may not exist as a separate object. If the 1stPFVG's range overlaps with an inverted FVG from the sweep leg, this additionally constitutes a **BPR (Balanced Price Range)**. A BPR is **not required** for this trigger model — it is only logged as an informational confluence note if present, never a precondition. There may be an option that restricts executions to just BPR entries however, but this is option and for backtesting only.
4. **Entry price** is derived from the 1stPFVG's 3-candle formation (Candle 1 / Candle 2 / Candle 3 as defined in Section 0), using one of two configurable, mutually exclusive modes (`FVGRetestEntryMode`):

   * **Mode 1 — "Edge Touch"**: the limit order is placed exactly at Candle 3's Low (bullish scenario) or Candle 3's High (bearish scenario) — i.e., the boundary of the gap nearest Candle 3.
   * **Mode 2 — "50% fill" (default)**: the limit order is placed at a configurable percentage retracement into the gap, measured starting from Candle 3's edge and moving toward Candle 1's edge. The percentage value (`FVGRetestFillPercent`) must be a backtestable input, with a default of 50%. **\[CONFIRM: source text specifies "50% of the price gap" — implemented literally as a 50% fill from the Candle 3 edge (the standard ICT "Consequential Encroachment" midpoint) — both modes are exposed as configurable so either can be tested.]**
   * **Mode 3 -** Execute market at the close of the candle 3 that confirms the 1stPFVG+CISD, or IFVG+CISD.

Note, Both Modes 1 \& 2 can be shifted with the trail option, if the 1stPFVG option is selected, this is optional, and allows the EA to execute at market if the 1stPFVG is unfilled at the close of the next LTF candle after the 1stPFVG is confirmed.

5. The order remains a working limit order until either filled, invalidated (price trades back fully through the opposite side of the range / past the SL level without filling), or the session's Trading Window ends — at which point it is cancelled (Section 6.4).

\---

## 6\. Phase 5 — Risk \& Trade Management

### 6.1 Stop Loss — Two Modes

Both modes must be exposed as a selectable EA input (`SL\_Mode`: Fixed or Dynamic). A minimum Risk:Reward threshold (`MinRR`) must be a configurable input, defaulting to 1:3, there should also be a selectable Max/Req. RR, this should be at/beyond the MinRR (If lesser than, default to the Max/Req. RR figure).

**Fixed Mode:**

* For short trades: SL is placed at the extreme high of the manipulation leg (the highest point reached during the boundary sweep), plus any broker-required minimum stop-level buffer.
* For long trades: SL is placed at the extreme low of the manipulation leg (the lowest point reached during the boundary sweep), minus any broker-required minimum stop-level buffer.

**Dynamic Mode:**

1. First, calculate what the Risk:Reward ratio would be **using the Fixed SL distance** (the distance from Entry to the Fixed SL level) against the distance from Entry to TP (Range\_High or Range\_Low, per direction).
2. If this Fixed-SL-derived RR is already equal to or greater than `MinRR`, **no adjustment is made** — the SL stays at the Fixed level. Dynamic Mode never widens the stop beyond the Fixed level.
3. If the Fixed-SL-derived RR is below `MinRR`, the SL distance is **tightened** (reduced) just enough so that the resulting RR equals exactly `MinRR`. The new SL is placed closer to Entry than the Fixed level, in the same direction (above Entry for shorts, below Entry for longs).
4. **Safety check**: if the tightened SL distance computed in step 3 would fall inside the broker's minimum stop-level distance (i.e., too close to Entry to be a legally placeable stop) or inside the current spread, the trade must be **skipped entirely** rather than placing an invalid or unsafely tight stop.

### 6.2 Take Profit

* Short trades target Range\_Low.
* Long trades target Range\_High.
* Single fixed target — no partial-profit taking is specified, and none should be assumed unless added separately.

### 6.3 Break-Even Logic (percentage-based, fully defined)

Two independent configurable inputs are required, each with both a preset-selection option and a free-form manual numeric entry field:

1. **`BE\_TriggerPercent`** — the percentage of the total Entry-to-TP distance that price must travel in the trade's favor before break-even logic activates. Selectable presets: 5%, 10%, 20%, 30%, 50%, 80%, 90%. A manual override field must also accept any custom value (including values outside the preset list).
2. **`BE\_LockPercent`** — once the trigger condition is met, this defines how far into profit (again expressed as a percentage of the total Entry-to-TP distance) the Stop Loss is moved. Selectable presets: 2%, 5%, 10%, 15%. A manual override field must also accept any custom value, including 0% (which would represent moving the SL to the exact Entry price — true breakeven).

**Mechanism:**

* The "total Entry-to-TP distance" is the absolute price distance between the Entry price and the TP price (Range\_High or Range\_Low), and is fixed at trade entry regardless of which SL mode (Fixed/Dynamic) was used — SL mode does not affect this distance.
* Continuously track unrealized profit, expressed as the price distance currently moved in the trade's favor.
* The instant this unrealized profit reaches or exceeds `BE\_TriggerPercent` of the total Entry-to-TP distance, the EA modifies the open position's Stop Loss.
* The new Stop Loss is placed at the price level corresponding to `BE\_LockPercent` of the total Entry-to-TP distance, measured from Entry in the direction of profit (i.e., this locks in that percentage of the total potential reward as guaranteed profit if subsequently stopped out).
* This is a **single-stage** trigger as specified (one trigger level, one lock level) — not a multi-step trailing staircase. **\[This is not a multi-stage progressive trail through several of the listed percentages simultaneously.]**
* This logic applies identically and independently of which entry trigger model (IFVG or FVG Retest) was used, and independently of SL mode.

### 6.4 Session Kill Switch \& Re-Entry Rules

* If a working limit order (from the FVG Retest model) is not filled by the end of the session's Trading Window, cancel it.
* If no valid trigger ever forms after a boundary sweep before the Trading Window ends, no trade is taken for that session.
* **Re-entry after a stop-out is permitted within the same session**, provided all of the following remain true: the original bias is still valid, the Trading Window has not yet ended, and a fresh qualifying sweep/re-sweep of the range boundary plus a new valid entry trigger (IFVG or FVG Retest, per Section 5) forms again. There is no fixed cap on the number of re-entries within a single session under this rule, other than the Trading Window time limit itself.
* **Once the TP is hit, the session is immediately marked closed.** No further entries — in either direction — are taken for that session's range, even if a second valid setup subsequently appears.

\---

## 7\. Consolidated Backtestable Parameter List

|Parameter|Type|Default / Presets|
|-|-|-|
|London\_RangeStart / London\_RangeEnd|Time|01:12 / 02:12|
|London\_TradingWindowEnd|Time|04:00|
|NY\_RangeStart / NY\_RangeEnd|Time|08:12 / 09:12|
|NY\_TradingWindowStart / NY\_TradingWindowEnd|Time|09:30 / 10:30|
|London\_HTF\_CandleSize|Duration|3.5 hours|
|NY\_HTF\_CandleSize|Duration|7 hours|
|London\_LTF\_Timeframe|Timeframe|M4|
|NY\_LTF\_Timeframe|Timeframe|M1|
|CISD\_ReferenceMode|Enum|SingleCandle (default) / ConsecutiveSequence|
|EntryTriggerModel|Enum|IFVG / FVGRetest (selectable, or run both)|
|FVGRetestEntryMode|Enum|EdgeTouch / ShallowFillPercent (default)|
|FVGRetestFillPercent|Numeric|5% (default), free-form override|
|SL\_Mode|Enum|Fixed / Dynamic|
|MinRR|Numeric|1:3 (default), free-form override|
|BE\_TriggerPercent|Numeric (preset list + manual)|5/10/20/30/50/80/90, manual override|
|BE\_LockPercent|Numeric (preset list + manual)|2/5/10/15, manual override (incl. 0)|

\---



