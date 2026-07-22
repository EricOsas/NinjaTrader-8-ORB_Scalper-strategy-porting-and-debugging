# CRT — NinjaTrader 8 (C#) Implementation Spec

Realises `01-STRATEGY-SPEC.md` on NinjaTrader 8 (NinjaScript / C#). It follows the proven
**ORB_NT** architecture — same file layout, same namespaces, same multi-timeframe wiring — and
lifts Time, Risk, News, Notify, State and the Direct2D dashboard almost verbatim. Only the
signal engine (CRT structure + CISD/IFVG confirmation) is new.

Namespace: `NinjaTrader.NinjaScript.Strategies.CRT_NT`
Folder: `CRT/CRT_NT/`

---

## 1. Module Map

| File | Role | Source |
|------|------|--------|
| `CRT_NT_Strategy.cs` | Main `Strategy`. `OnStateChange` (adds HTF + LTF data series), `OnBarUpdate` routing, phase machine, order/exec callbacks, dashboard render, chart mouse hooks. | new + ORB_NT_Strategy pattern |
| `CRT_NT_Inputs.cs` | `partial` class — all `[NinjaScriptProperty]` inputs with property groups. | ORB inputs pattern |
| `CRT_Types.cs` | Enums (`IntradayTF`, `EntryTriggerModel`, `CisdRefMode`, `SlotType`, `SetupPhase`, `TradeBias`), `Candle`, `FvgZone`, `CrtSetup`, `ActiveTrade`. | new |
| `CRT_Slots.cs` | Slot definitions, C1 window resolution per slot, LTF-minute derivation/override. | new + ORB_Sessions |
| `CRT_Structure.cs` | Per-slot C1→C2→C3 tracking: lock C1, detect HTF sweep, close-back-inside bias, 50% guard, invalidation, arming. | new |
| `CRT_Confirm.cs` | Rolling LTF tracker feeding CISD + FVG/IFVG detectors. | new (logic from DTR spec) |
| `CRT_HourFilter.cs` | CSV NY-hour parse + `IsExecHour` (C3-hour filter). | CCT hour-filter model |
| `CRT_Time.cs` | NY DST calendar math, True Day/Week/Month opens, chart↔UTC bridge. | **copied from ORB_Time.cs** |
| `CRT_Risk.cs` | Risk-% contract sizing, margin cap, Micro/Mini caps. | **copied from ORB_Risk.cs** |
| `CRT_News.cs` | FF JSON live feed + cache + historical CSV; `NewsGuardMode`; blackout query. | **copied from ORB_News.cs** |
| `CRT_Notify.cs` | Discord/Telegram queue, retry, dedupe; CRT-specific notify helpers. | ORB_Notify adapted |
| `CRT_State.cs` | Ledger (closed trades), live snapshot (single active trade), consumed-guard. | ORB_State adapted |
| `CRT_Execution.cs` | Order placement: market entry, 1:1 limit, SL/TP bracket (no OCO groups, no trailing). | ORB_Execution trimmed |
| `CRT_Visuals.cs` | C1 box, EQ line, sweep marker, CISD line, FVG/IFVG zone, entry/SL/TP lines. | ORB_Visuals adapted |
| `CRT_Dashboard.cs` | Liquid-glass Direct2D panel with CRT fields. | **ORB_Dashboard repurposed** |

---

## 2. Multi-Timeframe Wiring

`Calculate = Calculate.OnEachTick; IsUnmanaged = true;` (unmanaged order handling, as ORB).

`State.Configure` adds two secondary series **per the resolved config**:

```
// BIP0 = primary chart series (unused for logic beyond ticks)
AddDataSeries(htfBarsPeriodType, htfValue);   // BIP1: C1/C2/C3 HTF candles
AddDataSeries(BarsPeriodType.Minute, ltfMin); // BIP2: LTF sweep/CISD/IFVG bars
```

* `htfValue`/type from `IntradayTF` (15/30/60/120/240 Minute) or Day/Week/Month for HTF slots.
* `ltfMin` from `ExecTFMinutesOverride` (>0) else the §2.1 auto-derivation.
* Because NinjaScript needs series declared up-front, **only one C1 timeframe is active at a
  time** in v1: if Intraday is enabled it drives HTF; otherwise the first enabled HTF slot
  (Daily→Weekly→Monthly) drives it. (Multiple simultaneous HTF slots would need extra
  `AddDataSeries` calls; documented as a v2 extension. The single-active-trade rule makes one
  HTF series the pragmatic default.)

`OnBarUpdate` dispatch:

```
if (BarsInProgress == 2) { OnLtfBar(); }   // sweep + CISD/IFVG detection, entry triggers
if (BarsInProgress == 1) { OnHtfBar(); }   // C1 lock / C2 close bias / C3 window / invalidation
```

Trade management (SL/TP already resting as bracket orders) and dashboard render run on the LTF
pulse. Use `Times[1][]`, `Highs[1][]`, ... for HTF and `Times[2][]`, ... for LTF.

---

## 3. CRT Structure Engine (`CRT_Structure.cs`)

State per slot (`CrtSetup`):

```
enum SetupPhase { WaitC1, C1Locked, C2Watch, C2Closed_Armed, C3Window, Filled, Done }
enum TradeBias  { None, Long, Short }
```

Flow:

1. **C1 lock** — on each closed HTF bar, the just-closed bar becomes C1: store
   `C1_High=High[1][1]`, `C1_Low=Low[1][1]`, `C1_EQ=(H+L)/2`, `C1_time`. Phase → `C2Watch`.
   (The *next* forming HTF bar is C2.)
2. **C2 watch** — while the current HTF bar (C2) is forming:
   * On each LTF bar, update the running C2 extreme and detect sweep:
     `sweptHigh = C2runHigh > C1_High`, `sweptLow = C2runLow < C1_Low`.
   * Once swept, feed LTF bars to `CRT_Confirm` (§4) to search CISD / IFVG.
   * Track manipulation-leg extreme (highest high after an up-sweep / lowest low after a
     down-sweep) for the SL.
   * Enforce **50% guard**: if the running price reached `C1_EQ` on the eventual trade side, mark
     the setup dead.
3. **C2 close** (HTF bar close) — evaluate close-back-inside (§4 of strategy spec):
   * valid short/long → `bias` set, phase → `C2Closed_Armed`;
   * closed outside → phase → `Done` (invalidated).
   * If a trigger already fired inside C2, mark `carryToC3 = true`.
4. **C3 window** — apply optional C3-hour filter (`CRT_HourFilter`). If `carryToC3`, place the
   order at C3 open (§5). Otherwise keep scanning LTF bars inside C3 for the trigger.
5. **Window end** — at C3 close, cancel any resting limit and set phase → `Done`.

---

## 4. Confirmation Engine (`CRT_Confirm.cs`)

Maintains a rolling window of recent **closed LTF candles** (Open/High/Low/Close) since the sweep
began. Provides:

* **`DetectCISD(bias, refMode, c1Ext)`** →
  * Short: find the up-close run that pushed above `C1_High`; reference open =
    SingleCandle → last up-close candle's open; ConsecutiveSequence → first candle's open in the
    uninterrupted up-close run. CISD when a later candle **Close < referenceOpen**.
  * Long: mirror (down-close run below `C1_Low`; CISD when Close > referenceOpen).
* **`TrackFVG()`** — every 3 consecutive closed LTF candles, register a bullish/bearish `FvgZone`
  (only those born during/after the sweep on the relevant side).
* **`DetectIFVG(bias)`** — short: a bullish FVG whose far boundary (candle1.High) is **closed
  below**; long: a bearish FVG whose far boundary (candle1.Low) is **closed above**.
* **`Confirmed(model, ...)`** — combines per `EntryTriggerModel`: CISD, IFVG, or both.

Returns the confirming candle's close price + the manipulation-leg extreme (for SL).

---

## 5. Execution (`CRT_Execution.cs`) & Order Callbacks

No OCO, no trailing. Given a confirmed setup:

```
risk   = |entryRef - slPrice|          // slPrice = sweep extreme ± SL_BufferPoints (rounded to tick)
reward = |C1_EQ - entryRef|
if (priceAlreadyAtEQ) skip;            // 50% guard
if (reward >= risk)  -> SubmitOrderUnmanaged(Market)          // enter now / at C3 open
else                 -> SubmitOrderUnmanaged(Limit @ C1_EQ ∓ risk)  // 1:1 limit
```

* On entry fill (`OnOrderUpdate` Filled) → submit **SL** (StopMarket) and **TP** (Limit @ C1_EQ)
  via `PlaceBracketOrders` (reused, `slSlipCapPoints=0`). Record `ActiveTrade`, write live
  snapshot, notify fill.
* **Resting-limit management** (LTF pulse): if `Close` of LTF reaches `C1_EQ` before fill → cancel
  the limit, notify cancelled. No time-based cancel.
* On SL/TP fill (`OnExecutionUpdate`) → close `ActiveTrade`, append ledger, notify result, clear
  the global active-trade lock.
* **Global single-trade lock**: a static/instance flag blocks any slot from arming while
  `activeTrade != null || restingLimit != null`.

Contract count from `CRT_Risk.CalcContracts(balance, RiskPercent, risk, pointValue, ContractMode)`.

---

## 6. Hour Filter (`CRT_HourFilter.cs`)

Port of CCT: parse `ExecHoursNY` CSV → `HashSet<int>`; `bool IsExecHourAllowed(int nyHour)`.
When `Use_ExecHourFilter` is true, gate entry on `IsExecHourAllowed(NYhour(C3open))`.

---

## 7. Dashboard (`CRT_Dashboard.cs`)

Reuse `ORB_Dashboard` Direct2D liquid-glass rendering (movable header, collapse dot, palette,
Row/Divider/Pill helpers). Replace the `ORBDashState` struct with `CrtDashState`:

* Header: "CRT · <slot> <C1TF>" + NY clock.
* Rows: Bias | C1 High/Low/EQ | Sweep (High/Low/none) | Trigger model | CISD (armed/✓) |
  IFVG (watch/✓) | Entry (market/limit @ px) | SL/TP | Live R | plus account/news rows from ORB.
* Chart mouse hooks (`OnMouseDown/Move/Up`) and `OnRender` wired exactly as ORB_NT.

---

## 8. News / Notify / State / Time / Risk

* `CRT_Time.cs`, `CRT_Risk.cs`, `CRT_News.cs` — copied from ORB with only the namespace changed.
* `CRT_Notify.cs` — ORB_Notify with CRT-worded helpers (`NotifySetup` includes bias/EQ/trigger).
* `CRT_State.cs` — ORB_State trimmed to single-active-trade live snapshot + closed ledger +
  consumed-guard keyed by C1 identity (slot + C1 time) so a restart never re-arms a done C1.

---

## 9. Build / Deploy Notes

* Drop all `CRT_*.cs` into `Documents/NinjaTrader 8/bin/Custom/Strategies/CRT_NT/`.
* Requires the SharpDX references already used by ORB (Direct2D dashboard).
* Compile in the NinjaScript editor (F5). No external NuGet packages.
* `HttpClient` for news/notify is already referenced by the ORB modules.
