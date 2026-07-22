# CRT — MetaTrader 5 (MQL5) Implementation Spec · `CRT_MT5`

> **Document 3 of 3.** Maps `01-STRATEGY-SPEC.md` onto an MQL5 Expert Advisor. Built **after** `CRT_NT`, to functional parity. The MQL5 dashboard is a **repurpose of `CCT`'s dashboard** (`CCT_Dashboard.mqh`); the FVG/IFVG engine and the multi-intraday execution-hour filter are **lifted from `CCT`** (`CCT_Scanner.mqh` / `CCT_EA_v7.mq5`); the time/DST and position-sizing engines are **lifted from `ORB_Scalper`** (`ORB_Time.mqh`) and mirrored 1:1 with the C# `CRT_NT` build.
>
> Target: **MetaTrader 5**, MQL5, `.mq5` EA + `.mqh` includes, tick-driven `OnTick`.

---

## 0. Provenance — What Comes From CCT and ORB_Scalper

| Source file | Reuse for CRT | Notes |
|-------------|---------------|-------|
| `ORB_Scalper/ORB_Time.mqh` | **LIFT VERBATIM** | Broker-server↔NY time, DST calendar math, True Day/Week/Month opens. This is the canonical time engine the C# `ORB_Time.cs` was itself ported from — keep both variants byte-identical in behavior. |
| `ORB_Scalper` position sizing / lots / margin | **LIFT + MIRROR** | Risk-% lots, margin cap, min-stop handling. Must match `CRT_NT` `CRT_Risk` outputs on the same inputs. |
| `ORB_Scalper/ORB_Visuals.mqh` | **REFERENCE** | Range/level object drawing, bar-time anchoring, non-visual vs visual tester handling. |
| `CCT/CCT_Scanner.mqh` | **LIFT + ADAPT** | The C1/C2/C3 FVG-generation model + IFVG inversion (`close` fully beyond far boundary). Re-scope from CCT POI generations to CRT's single C1/C2 manipulation window. |
| `CCT/CCT_Globals.mqh` | **REFERENCE** | FVG struct, `ENUM_CCT_IFVG_LOOKBACK_MODE`, inversion enums. Adapt struct names to CRT. |
| `CCT/CCT_Execution.mqh` | **LIFT + ADAPT** | Market/limit order placement, bracket, breakeven/trail. Replace CCT entry model with CRT market/limit + MinRR rule. |
| `CCT/CCT_Dashboard.mqh` | **REPURPOSE** | Panel layout, object ownership, timeframe masks, MT5 rendering rules. Replace CCT panel rows with CRT rows (Section 7). |
| `CCT/CCT_Visual.mqh` | **LIFT + ADAPT** | FVG/IFVG boxes, action-pillar-style markers, CISD lines, execution-object display. |
| `CCT/CCT_Notify.mqh` | **LIFT VERBATIM** | Notification transport (parity with `ORB_Notify`). |
| `CCT` execution-hour selection (Ch. 8 model) | **LIFT** | Multi-intraday NY-hour gate → CRT's C3-hour filter (Section 8). Preferred over ORB single-hour session. |

> **Do not rebuild** time, sizing, FVG/IFVG, dashboard, or notifications from scratch. CCT and ORB_Scalper already solved these; CRT_MT5 is 90% assembly + re-scoping.

---

## 1. Module Map — `CRT_MT5/`

```
CRT_MT5/
  CRT_EA.mq5           Main EA: OnInit/OnTick/OnDeinit/OnTradeTransaction, slot loop
  CRT_Inputs.mqh       All `input` declarations (mirror CRT_NT inputs 1:1)
  CRT_Globals.mqh      Enums + structs: SlotType, C1TF, TriggerMode, CISDMode, SetupState,
                       SequenceState, FvgCtx, CisdCtx  (adapted from CCT_Globals.mqh)
  CRT_Time.mqh         LIFT from ORB_Scalper/ORB_Time.mqh
  CRT_Slots.mqh        C1 window resolution + LTF derivation (mirror CRT_Slots.cs)
  CRT_Sequence.mqh     Per-slot C1/C2/C3 rolling state machine (mirror CRT_Sequence.cs)
  CRT_Scanner.mqh      Sweep + CISD run + FVG/IFVG detection (adapted from CCT_Scanner.mqh)
  CRT_Execution.mqh    Market/limit + bracket + trail/BE (adapted from CCT_Execution.mqh)
  CRT_Risk.mqh         Lots/margin sizing (mirror CRT_Risk.cs / ORB_Scalper sizing)
  CRT_Dashboard.mqh    REPURPOSED CCT_Dashboard.mqh + CRT panel rows
  CRT_Visual.mqh       C1 box, EQ line, sweep/CISD/IFVG/entry objects (adapted CCT_Visual.mqh)
  CRT_Notify.mqh       LIFT from CCT_Notify.mqh
  CRT_State.mqh        Consumed-ledger (by C1 identity) + persistence (parity with CRT_State.cs)
```

---

## 2. Multi-Timeframe Data Access

- MQL5 reads any TF on demand via `CopyRates` / `iHigh` / `iLow` / `iOpen` / `iClose` / `iTime` with an explicit `ENUM_TIMEFRAMES` — no equivalent of NT8's `AddDataSeries` is required.
- **C1/C2/C3 boundaries:** computed from `CRT_Time` calendar math (NY-aligned), then read the C1 candle O/H/L/C directly from the C1 TF (`iHigh(_Symbol, c1tf, shift)` etc.). Intraday C1 TF maps to a native `ENUM_TIMEFRAMES` (M15/M30/H1/H2/H4). Daily/Weekly/Monthly use the **True open** windows (not raw PERIOD_D1/W1/MN1) via `CRT_Time`, aggregating from the LTF or an intraday TF as CCT does.
- **LTF:** the resolved execution TF (Section 3). All sweep/CISD/FVG/entry logic reads LTF bars, driven off new-LTF-bar detection inside `OnTick` (compare `iTime(_Symbol, ltf, 0)`).
- Follow CCT's **non-visual vs visual tester** guards (`MQLInfoInteger(MQL_TESTER)` / `MQL_VISUAL_MODE`) so object drawing is skipped in non-visual optimization runs.

---

## 3. Slots & LTF Resolution — `CRT_Slots.mqh`

Mirror `CRT_Slots.cs` exactly:

```mql5
int ResolveLtfMinutes(SlotType slot, C1TF c1tf) {
   if (InpExecTF_OverrideMinutes > 0) return InpExecTF_OverrideMinutes;   // global override
   switch(slot) {
      case SLOT_INTRADAY:
         switch(c1tf){ case TF_M15: return 1; case TF_M30: return 1;
                       case TF_H1: return 5;  case TF_H2:  return 5;
                       case TF_H4: return 15; }
      case SLOT_DAILY:   return 15;
      case SLOT_WEEKLY:  return 60;
      case SLOT_MONTHLY: return 240;
   }
}
ENUM_TIMEFRAMES MinutesToTF(int m);   // 1→PERIOD_M1, 5→PERIOD_M5, 15→PERIOD_M15, 60→PERIOD_H1, 240→PERIOD_H4 ...
```

`MinutesToTF` must map to the nearest supported `ENUM_TIMEFRAMES`; reject unsupported minute values with a clear `Print` + fall back to the auto value.

---

## 4. Scanner — `CRT_Scanner.mqh` (adapted from `CCT_Scanner.mqh`)

- **Sweep detection:** LTF high beyond `C1High` (short bias) or LTF low below `C1Low` (long bias) inside the C2 window; record `ManipExtreme`.
- **CISD run detection:** port the strategy-spec Section 5 rules. Walk LTF bars back from the sweep extreme to find the consecutive same-direction run; reference origin = first-candle Open of the run (`CISD_ReferenceMode` = RunOrigin/SingleCandle). CISD confirmed when a later LTF bar closes beyond that origin.
- **FVG / IFVG:** reuse CCT's 3-candle FVG builder and the inversion test (a bar `close` fully beyond the gap's far boundary). Scope the FVG search to bars formed **after** the C2 sweep. Keep CCT's `ENUM_..._IFVG_LOOKBACK_MODE` as an optional bounding of how far back to scan.
- Emit a `TriggerResult { bool fired; bool isLong; double manipExtreme; bool cisdInC2; ENUM_TRIGGER_KIND kind; }` consumed by the sequence engine.

---

## 5. Sequence Engine — `CRT_Sequence.mqh`

Mirror `CRT_Sequence.cs`. `SequenceState` struct (in `CRT_Globals.mqh`) with the identical `SetupState` enum and transitions from strategy-spec Section 8. One instance per enabled slot (fixed-size array, MQL5 has no dynamic class arrays without pointers — use a `struct[]`).

Per new-LTF-bar:
1. Roll C1 (lock High/Low/EQ, set C2/C3 windows, redraw).
2. Detect sweep → `SWEPT` + bias.
3. Invalidation (C2 close beyond extreme; EQ taken; beyond ManipExtreme+buffer).
4. `CRT_Scanner` trigger per `EntryTriggerMode`.
5. Placement (global concurrency + C3-hour filter; carry-over to C3 open if `cisdInC2`).
6. Manage working limit (EQ-cancel) and live trade (trail/BE).

---

## 6. Execution — `CRT_Execution.mqh` (adapted from `CCT_Execution.mqh`)

- **TP = EQ**, **SL = ManipExtreme ± buffer** (buffer ≥ `SYMBOL_TRADE_STOPS_LEVEL` and spread).
- **MinRR market/limit rule** (identical math to `CRT_NT`):
  ```
  risk = |mktPx - slPx|; reward = |eqPx - mktPx|;
  if (reward/risk >= MinRR)  → market (CTrade.PositionOpen / Buy/Sell)
  else                       → working limit at eqPx ∓ MinRR*risk (BuyLimit/SellLimit)
  ```
- **EQ-cancel:** if a working CRT pending order exists and price reaches EQ → `OrderDelete`.
- **Trailing / BE:** reuse CCT/ORB trailing (snapshot geometry, Continuous/Step, BE-only, spread-comp). Persist snapshot in `CRT_State` for restart re-adoption (parity with CRT_NT `LiveTradeSnapshot`).
- **Lots:** `CRT_Risk.CalcLots(balance, RiskPercent, riskPriceDistance, tickValue, ...)` with margin cap — output must equal the C# `CRT_Risk` contract/lot count on equivalent inputs.

---

## 7. Dashboard — `CRT_Dashboard.mqh` (repurposed `CCT_Dashboard.mqh`)

- Keep CCT's panel architecture: object ownership, timeframe masks, MT5 rendering rules, colour spec, draggable/collapsible panels, and the theme `.tpl` support (`EricGreen-Black`, `EricWhite-Black`, `EricWhite-Blue`).
- Replace CCT's POI/generation rows with CRT rows (identical information set to the `CRTDashState` in `02-NT8-IMPLEMENTATION.md`):
  - Header + NY clock.
  - **Slot / ExecTF** (e.g. "Intraday H1 · M5 auto").
  - **C1 High / EQ / Low**.
  - **Bias / SetupState**.
  - **Trigger mode / CISD status / FVG-IFVG status**.
  - **ExecHour filter** (on/off + active hours).
  - **Trade block:** dir / entry / SL / TP / live RR / lots / BE.
  - **Compliance block:** balance / drawdown floor / consistency (if the firm-rules trackers are carried over from ORB — optional in MQL5).
  - **News row** (optional).

---

## 8. C3 Execution-Hour Filter (CCT model)

- Inputs: `InpEnableExecHourFilter` (bool, default false) + 24 `input bool` hour toggles `InpHour00..InpHour23` **exactly as CCT exposes execution hours** (this is the UI the user prefers over ORB's single-hour model).
- At placement, compute the C3 candle's opening NY hour via `CRT_Time` and require it ∈ enabled set; else skip (sequence → `EXPIRED`).

---

## 9. Parity Matrix — `CRT_NT` ⇄ `CRT_MT5`

| Concern | CRT_NT (C#) | CRT_MT5 (MQL5) | Parity requirement |
|---------|-------------|----------------|--------------------|
| Time/DST | `CRT_Time.cs` (from ORB_Time.cs) | `CRT_Time.mqh` (from ORB_Time.mqh) | identical NY anchors |
| Sizing | `CRT_Risk.cs` | `CRT_Risk.mqh` | identical size on same inputs |
| Sequence FSM | `CRT_Sequence.cs` | `CRT_Sequence.mqh` | identical states/transitions |
| CISD | `CRT_Cisd.cs` | `CRT_Scanner.mqh` | identical run-origin rule |
| FVG/IFVG | `CRT_Fvg.cs` | `CRT_Scanner.mqh` (from CCT) | identical inversion test |
| MinRR entry | `CRT_Execution.cs` | `CRT_Execution.mqh` | identical market/limit price |
| Trailing/BE | ORB trailing | CCT/ORB trailing | identical target math |
| Dashboard | repurposed ORB (Direct2D) | repurposed CCT | same information set |
| Hour filter | CSV/bools | CCT-style 24 bools | same gate semantics |

---

## 10. Build Order (MQL5, after NT8 is validated)

1. `CRT_Inputs.mqh`, `CRT_Globals.mqh`, `CRT_Time.mqh` (lift), `CRT_Risk.mqh` (mirror).
2. `CRT_Slots.mqh` — windows + LTF derivation.
3. `CRT_Scanner.mqh` (from CCT) + `CRT_Sequence.mqh` (mirror C#).
4. `CRT_Execution.mqh` (from CCT) + concurrency + EQ-cancel.
5. `CRT_EA.mq5` wiring (OnTick loop, OnTradeTransaction, trailing).
6. `CRT_Visual.mqh`, `CRT_Dashboard.mqh` (repurpose CCT), `CRT_Notify.mqh`, `CRT_State.mqh`.
7. Compile with MetaEditor; validate against `CRT_NT` on identical historical windows.

> **MQL5 compile note:** compilation requires MetaEditor (`metaeditor64 /compile`), which is not available in this sandbox. The `mql5-x-compile` skill documents a local Wine/macOS compile path for the user's own machine; here the code is authored to MQL5 conventions already proven in the CCT and ORB_Scalper EAs in this repo. The `mql5-docs-research` and `mql5-indicator-patterns` skills are the reference for any unfamiliar MQL5 API.
