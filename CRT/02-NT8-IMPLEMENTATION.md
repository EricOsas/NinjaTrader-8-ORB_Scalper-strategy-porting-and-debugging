# CRT — NinjaTrader 8 (C#) Implementation Spec · `CRT_NT`

> **Document 2 of 3.** Maps the platform-agnostic logic in `01-STRATEGY-SPEC.md` onto a concrete C# NinjaScript module layout, and specifies exactly what is **lifted verbatim**, **adapted**, or **built new** from the existing **`ORB_NT`** project (the C# ORB Scalper port already in this repo). The NT8 dashboard is a **repurpose of `ORB_Dashboard.cs`**.
>
> Target: **NinjaTrader 8**, NinjaScript C#, `IsUnmanaged = true`, `Calculate = Calculate.OnEachTick`.

---

## 0. Provenance — What Comes From `ORB_NT`

`ORB_NT` (audited) is organized as a `partial`-style multi-file strategy in namespace `NinjaTrader.NinjaScript.Strategies.ORB_NT`. Key files and their reuse verdict:

| ORB_NT file | Lines | Reuse for CRT | Notes |
|-------------|-------|---------------|-------|
| `ORB_Time.cs` | 228 | **LIFT VERBATIM** | NY DST calendar math, platform-TZ bridge, True Day/Week/Month opens, `GetSessionOpenUTC`. Rename namespace only. |
| `ORB_Risk.cs` | 86 | **LIFT VERBATIM** | `CalcContracts`, margin table, `MarginCappedContracts`, Micro/Mini caps. |
| `ORB_State.cs` | 343 | **LIFT + ADAPT** | Ledger + live snapshot + consumed ledger + reports. Re-key consumed ledger by **C1 identity** (slot + C1 open + side). |
| `ORB_Execution.cs` | 194 | **LIFT + ADAPT** | Keep `ComputeTrailTarget`, `PlaceBracketOrders`, `SlLimitPrice`. Replace fixed-distance entry OCO with CRT market/limit placement (Section 4). |
| `ORB_Dashboard.cs` | 459 | **REPURPOSE** | Direct2D liquid-glass panel. Replace `ORBDashState` fields with `CRTDashState` (Section 7). |
| `ORB_Sessions.cs` | 111 | **REPLACE** | ORB's range-window phase machine → CRT's per-candle C1/C2/C3 sequence machine (`CRT_Sequence.cs`). |
| `ORB_NT_Strategy.cs` | 495 | **REPLACE (pattern)** | Keep the `OnStateChange`/`OnBarUpdate`/slot-loop/`OnOrderUpdate`/trailing skeleton; swap ORB range logic for CRT logic. |
| `ORB_NT.cs` | 179 | **LIFT + ADAPT** | Keep tracker classes (`DrawdownTracker`, `ConsistencyTracker`, `FastTradeTracker`) and the `ActiveTrade` record incl. snapshot geometry. |
| `ORB_Visuals.cs` | 288 | **LIFT + ADAPT** | Range box + level draw helpers → C1 box, EQ line, sweep/CISD/IFVG objects. |
| `ORB_Notify.cs` | 235 | **LIFT VERBATIM** | Notification transport. |
| `ORB_News.cs` | 281 | **OPTIONAL** | News blackout — carry over as optional feature. |
| `ORB_Strategy.cs` | 2402 | **REFERENCE** | The large monolith; consult for edge-case handling only. |

---

## 1. Module Map — `CRT_NT/`

```
CRT_NT/
  CRT_NT.cs             Main class shell: tracker classes + ActiveTrade record (from ORB_NT.cs)
  CRT_NT_Strategy.cs    Strategy orchestrator: OnStateChange/OnBarUpdate/slot loop/order events
  CRT_Types.cs          Enums + structs: SlotType, C1TF, TriggerMode, CISDMode, SetupState, Candle
  CRT_Time.cs           LIFT from ORB_Time.cs (NY DST, True D/W/M opens)
  CRT_Slots.cs          Slot config → C1 timeframe resolution + LTF derivation (Section 3)
  CRT_Sequence.cs       Per-slot C1/C2/C3 rolling state machine (Section 5) — the heart
  CRT_Cisd.cs           CISD run detection (Section 5.4)
  CRT_Fvg.cs            FVG build + IFVG inversion (ported from CCT scanner logic)
  CRT_Signal.cs         Combines sweep + CISD/IFVG per EntryTriggerMode → trigger decision
  CRT_Risk.cs           LIFT from ORB_Risk.cs (sizing, margin caps)
  CRT_Execution.cs      Market/limit placement + bracket + trailing (adapted ORB_Execution.cs)
  CRT_State.cs          LIFT+ADAPT from ORB_State.cs (ledger/live/consumed by C1 identity)
  CRT_Visuals.cs        C1 box, EQ line, sweep/CISD/IFVG/entry objects (adapted ORB_Visuals.cs)
  CRT_Dashboard.cs      REPURPOSED ORB_Dashboard.cs (Direct2D) + CRTDashState
  CRT_Notify.cs         LIFT from ORB_Notify.cs
```

All in namespace `NinjaTrader.NinjaScript.Strategies.CRT_NT`.

---

## 2. Data Series & `OnStateChange`

- `IsUnmanaged = true`, `Calculate = Calculate.OnEachTick`, `EntriesPerDirection = 1`, `IsExitOnSessionCloseStrategy = false`, `BarsRequiredToTrade = 2`.
- **Series design (differs from ORB's single M1 series):** CRT needs *both* HTF-candle boundaries and an LTF read.
  - **BIP0** = the chart series (any TF — used only for OnRender/dashboard cadence).
  - **BIP1** = the **LTF execution series** — added in `State.Configure` from the resolved LTF minutes. All sweep/CISD/FVG/entry evaluation happens here.
  - **HTF C1/C2/C3 boundaries** are computed from calendar math (`CRT_Time` + `CRT_Slots`), then C1 High/Low are aggregated from BIP1 bars inside `[C1_start, C1_end)` — exactly the `TryLoadHtfRange` pattern already in `ORB_NT_Strategy.cs`.
  - **[CONFIRM]** For the Intraday sub-slot TFs we can instead `AddDataSeries` the actual C1 TF (e.g. H1) as BIP2 for exact O/H/L/C. Decide per-slot vs aggregate-from-LTF at build time. Aggregate-from-LTF keeps series count low and matches ORB.

---

## 3. Slots & LTF Resolution — `CRT_Slots.cs`

- Enum `SlotType { Intraday, Daily, Weekly, Monthly }`; `C1TF { M15, M30, H1, H2, H4 }`.
- `ResolveC1WindowUTC(slot, nowUTC)` → `(c1StartUTC, c1EndUTC)` using:
  - Intraday: floor `nowUTC` to the C1TF grid aligned to the NY day; C1 = the last *closed* candle, C2 = current forming candle, etc.
  - Daily/Weekly/Monthly: `CRT_Time.GetCurrentNYTrueDayOpen/WeekOpen/MonthOpen` (verbatim ORB).
- `ResolveLtfMinutes(slot)`:
  ```
  if (ExecTF_OverrideMinutes > 0) return ExecTF_OverrideMinutes;   // global override
  switch (c1tf) { M15→1; M30→1; H1→5; H2→5; H4→15; }               // auto table
  Daily→15; Weekly→60; Monthly→240;
  ```

---

## 4. Execution — `CRT_Execution.cs`

Adapt `ORB_Execution.cs`:

- **Keep:** `ComputeTrailTarget` (snapshot-frozen trailing, Continuous/Step/BE-only/spread-comp), `PlaceBracketOrders` (SL/TP StopLimit/StopMarket + `SlLimitPrice`).
- **Remove:** `PlacePendingEntryOCO` fixed-range breakout logic and `FixedSLPoints`/`FixedTPPoints` usage.
- **Add CRT entry placement:**
  ```csharp
  // On trigger: TP = EQ, SL = manipExtreme ± buffer.
  // reward/risk >= MinRR → market order; else working limit at the 1:1 price.
  PlaceCrtEntry(isLong, marketPx, eqPx, slPx, contracts, minRR, oco):
      risk   = |marketPx - slPx|
      reward = |eqPx - marketPx|
      if reward/risk >= minRR:
          submit MARKET (SubmitOrderUnmanaged OrderType.Market)
      else:
          limitPx = isLong ? eqPx - minRR*risk : eqPx + minRR*risk   // price giving exactly MinRR
          submit LIMIT at limitPx (working, no expiry)
  ```
- **EQ-cancel watcher:** each tick, if a working CRT limit exists and price has reached `EQ`, cancel it (Section 7.3 of the strategy spec).
- Contracts from `CRT_Risk.CalcContracts(balance, RiskPercent, risk /*price dist entry→SL*/, pointValue, mode)` — note SL distance is now **dynamic** (per-setup), not a fixed input.

---

## 5. The Sequence Engine — `CRT_Sequence.cs` (new, the core)

One `SequenceState` per enabled slot. Rolling C1/C2/C3 with the Section-8 state machine from the strategy spec.

```csharp
enum SetupState { Idle, RangeLocked, Swept, Triggered, WorkingLimit, Live, ClosedTP, ClosedSL, Invalid, Expired }

class SequenceState {
    int      SlotIndex;
    SlotType Type;
    // C1
    DateTime C1StartUTC, C1EndUTC;
    double   C1High, C1Low, C1Open, C1Close, EQ;
    bool     C1Locked;
    // C2/C3 windows
    DateTime C2StartUTC, C2EndUTC, C3StartUTC, C3EndUTC;
    // sweep / bias
    bool     Swept; bool IsLong;            // long = down-sweep of C1Low
    double   ManipExtreme;                   // SL anchor
    bool     CisdInC2;                       // carry-over flag
    // trigger primitives
    CisdContext Cisd; FvgContext Fvg;
    SetupState State;
    string   C1Key;                          // slot + C1 open time (consumed-ledger identity)
}
```

Per-LTF-bar update (called from `OnBarUpdate` when `BarsInProgress == 1`):

1. **Roll C1:** if a new C1 window has closed, lock `C1High/Low/EQ`, reset sequence to `RangeLocked`, set C2/C3 windows, redraw C1 box + EQ line.
2. **Detect sweep** (`RangeLocked`→`Swept`): LTF high > C1High (short bias) or LTF low < C1Low (long bias) while inside the C2 window. Record `ManipExtreme`, set `IsLong`.
3. **Invalidation checks** (→`Invalid`): C2 close beyond swept extreme; EQ already reached; beyond ManipExtreme+buffer.
4. **Trigger** (`Swept`→`Triggered`): `CRT_Signal.Evaluate(...)` per `EntryTriggerMode`:
   - CISD via `CRT_Cisd.Check(...)`, IFVG via `CRT_Fvg.CheckInversion(...)`.
   - Set `CisdInC2` if confirmation happened while C2 still forming.
5. **Placement** (`Triggered`→`Live`/`WorkingLimit`): respect **global concurrency** (Section 6) and **C3-hour filter** (Section 8); if `CisdInC2`, defer to C3 open.
6. **Manage** `WorkingLimit` (EQ-cancel) and `Live` (trailing/BE via `CRT_Execution`).

---

## 6. Global Concurrency Gate

- The strategy holds a single nullable `ActiveTrade activeTrade` and a single `Order workingLimit` (not per-slot arrays as ORB does). Before any placement, `if (activeTrade != null || workingLimit != null) return;`.
- On close/cancel, clear both so the next qualifying sequence can arm. Persist via `CRT_State` live snapshot for restart re-adoption.

---

## 7. Dashboard — `CRT_Dashboard.cs` (repurposed `ORB_Dashboard.cs`)

Keep the Direct2D liquid-glass renderer, drag/collapse, `Publish`/`Render`, color palette, `OnMouseDown/Move/Up`. Replace the `ORBDashState` struct with:

```csharp
public struct CRTDashState {
    // Account / Compliance (unchanged from ORB)
    double CurrentBalance, DrawdownFloor; bool FloorLocked; double DistanceToFloor;
    double ConsistencyPctOfTotal, EvalProfitTarget, EvalProfitProgress; int TradingDaysCompleted;
    double FastTradePct; bool ConsistencyWarning;
    // CRT structure (replaces ORB "Session")
    string ActiveSlot;      // "Intraday H1" | "Daily" | ...
    string ExecTF;          // "M5 (auto)" | "M3 (override)"
    string NYClock;
    string C1Window;        // "04:00–05:00 NY"
    double C1High, C1Low, EQ;
    string Bias;            // "SHORT (high sweep)" | "LONG (low sweep)" | "—"
    string SetupState;      // Idle/RangeLocked/Swept/Triggered/WorkingLimit/Live/...
    string TriggerMode;     // CISD | IFVG | CISD+IFVG
    string CisdStatus;      // "armed @ 3987.5" | "confirmed" | "—"
    string FvgStatus;       // "bull FVG 3985–3987" | "inverted" | "—"
    bool   ExecHourFilterOn; string ExecHours;   // "03,07,10 NY"
    // Trade (unchanged from ORB)
    bool InTrade; string TradeDir; double EntryPrice, StopLoss, TakeProfit; int ContractCount;
    string ContractMode; double LiveRR; bool BEActive; string BEDetail;
    // Instrument / News (unchanged)
    string InstrumentName; double TickSize, PointSize, PointValue;
    bool NewsBlackoutActive; string NextNewsEvent, NewsSourceMode;
}
```

Rows to render (top→bottom): header + NY clock; **Slot / ExecTF**; **C1 High / EQ / Low**; **Bias / SetupState**; **Trigger / CISD / FVG**; **ExecHour filter**; Trade block (dir/entry/SL/TP/RR/contracts/BE); Compliance block; News row.

---

## 8. C3 Execution-Hour Filter

- Inputs: `EnableExecHourFilter` (bool), `ExecHoursNY` (expose as 24 individual `bool Hour00..Hour23` NinjaScriptProperties, or a CSV string parsed to a `HashSet<int>` — CSV recommended for compactness).
- At placement time, compute the C3 candle's **opening NY hour** (`CRT_Time.UTCToNY(seq.C3StartUTC).Hour`); if filter ON and hour ∉ set → skip (setup `Expired` for that sequence).

---

## 9. Build Order (NT8 first)

1. `CRT_Types.cs`, `CRT_Time.cs` (lift), `CRT_Risk.cs` (lift) — foundations.
2. `CRT_Slots.cs` — slot windows + LTF derivation.
3. `CRT_Sequence.cs` + `CRT_Cisd.cs` + `CRT_Fvg.cs` + `CRT_Signal.cs` — core logic.
4. `CRT_Execution.cs` (adapt) + concurrency gate.
5. `CRT_NT_Strategy.cs` wiring (OnBarUpdate loop, order events, trailing).
6. `CRT_Visuals.cs`, `CRT_Dashboard.cs` (repurpose), `CRT_State.cs` (lift+adapt), `CRT_Notify.cs`.
7. Compile in NT8, resolve `IsUnmanaged` order-handling edge cases against `ORB_Strategy.cs` reference.

> **NinjaScript compile note:** there is no NT8 compiler in this sandbox. Code is authored to NinjaScript 8 API conventions used throughout `ORB_NT` (verified against that project). Final compile happens in the NinjaTrader editor.
