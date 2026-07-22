# CRT — MQL5 (C++) Implementation Spec

Realises `01-STRATEGY-SPEC.md` on MetaTrader 5 (MQL5). It mirrors the C# `CRT_NT` design one-to-one
and lifts infrastructure from the two proven MQL5 projects in this repo:

* **ORB_Scalper** — time engine (NY DST calendar math, True Day/Week/Month opens, server-time
  bridge), risk/lot/margin sizing, visual vs non-visual tester handling, pointing system.
* **CCT_v7** — the **dashboard** (`CCT_Dashboard.mqh` / `CCT_Visual.mqh`), the **multi-hour NY
  execution filter** (`InpCCTOnly` CSV → `AppendHourSlots` / `IsExecHour`), FVG/IFVG scanning
  patterns, and the notification layer (`CCT_Notify.mqh`).

Folder: `CRT/CRT_MT5/`. Main EA: `CRT_EA.mq5` including the `.mqh` modules below.

---

## 1. Module Map

| File | Role | Source |
|------|------|--------|
| `CRT_EA.mq5` | `OnInit`/`OnTick`/`OnTimer`/`OnDeinit`/`OnTradeTransaction`; wires modules. | ORB_Scalper main |
| `CRT_Inputs.mqh` | All `input` declarations, property groups (CCT `input(name=...)` style). | CCT/ORB inputs |
| `CRT_Globals.mqh` | Enums, structs (`Candle`, `FvgZone`, `CrtSetup`, `ActiveTrade`), globals, helpers. | new + CCT globals |
| `CRT_Time.mqh` | NY DST math, True Day/Week/Month opens, server↔NY↔UTC bridge, session windows. | **ORB_Scalper time module** |
| `CRT_Risk.mqh` | Lot sizing from risk %, margin cap, broker volume min/step/max clamp. | **ORB_Scalper sizing** |
| `CRT_Structure.mqh` | Per-slot C1→C2→C3 tracking, sweep detect, close-back-inside bias, 50% guard. | new |
| `CRT_Confirm.mqh` | LTF CISD + FVG/IFVG detection over `CopyRates` LTF series. | CCT scanner patterns |
| `CRT_HourFilter.mqh` | CSV NY-hour parse + `IsExecHourAllowed`. | **CCT `AppendHourSlots`/`HasHour`** |
| `CRT_Execution.mqh` | Market entry / 1:1 limit / SL(=sweep wick) / TP(=C1_EQ); resting-limit cancel. | ORB/CCT execution trimmed |
| `CRT_News.mqh` | FF calendar (WebRequest live + cache + historical CSV), guard modes, blackout. | ORB_Scalper news |
| `CRT_Notify.mqh` | Discord/Telegram queue, retry, dedupe (`ClaimOnce`), CRT helpers. | **CCT_Notify.mqh** |
| `CRT_Dashboard.mqh` | On-chart dashboard panel with CRT fields. | **CCT_Dashboard.mqh repurposed** |
| `CRT_Visual.mqh` | C1 box, EQ line, sweep marker, CISD line, FVG/IFVG rectangles, entry/SL/TP. | **CCT_Visual.mqh** |
| `CRT_State.mqh` | Persist single live trade + closed ledger + consumed C1 guard (CSV in `MQL5/Files`). | ORB state |

---

## 2. Timeframe Model

* HTF from `IntradayTF` maps to `ENUM_TIMEFRAMES`: 15m→`PERIOD_M15`, 30m→`PERIOD_M30`,
  1H→`PERIOD_H1`, 2H→`PERIOD_H2`, 4H→`PERIOD_H4`; Daily→`PERIOD_D1`, Weekly→`PERIOD_W1`,
  Monthly→`PERIOD_MN1`.
* LTF: `ExecTFMinutesOverride>0` → nearest `ENUM_TIMEFRAMES` for that minute; else auto-derive
  (15m/30m→M1, 1H/2H→M5, 4H/Daily→M15, Weekly→H1, Monthly→H4).
* Unlike NT8, MQL5 reads any timeframe on demand via `CopyRates(_Symbol, tf, ...)`, so **multiple
  slots can run simultaneously**. The single-active-trade rule still applies globally.
* True Day/Week/Month opens and all DST handling come from `CRT_Time.mqh` (ported from
  ORB_Scalper) — **do not re-derive**; the ORB_Scalper timer was heavily debugged.

---

## 3. Structure & Confirmation

Same procedural logic as `02-NT8-IMPLEMENTATION.md` §3–§4, expressed over `MqlRates` arrays:

* On each new HTF bar close (detected via `iTime(_Symbol, htf, 0)` change): the just-closed bar
  becomes C1 → lock `C1_High/C1_Low/C1_EQ`.
* While C2 forms: `CopyRates` the LTF window `[C2_open, now]`; update running C2 extreme; detect
  sweep of `C1_High`/`C1_Low`; once swept, run `CRT_Confirm` for CISD/IFVG; track manipulation-leg
  extreme for SL; enforce the 50% guard.
* On C2 close: close-back-inside → bias; closed-outside → invalidate; set `carryToC3` if a trigger
  fired in C2.
* During C3: optional hour filter; place order (carry-over at C3 open, or on trigger in C3).

`CRT_Confirm.mqh`:
* `DetectCISD(bias, refMode, c1Ext)` — up/down-close run reference open, close-through test.
* `TrackFVG()` / `DetectIFVG(bias)` — 3-candle gap registration + far-boundary close-through.
* Combine per `EntryTriggerModel` (CISD default / IFVG / CISD+IFVG).

---

## 4. Execution

* `risk = |entryRef − sl|` (sl = sweep extreme ± `SL_BufferPoints`, respect
  `SYMBOL_TRADE_STOPS_LEVEL`), `reward = |C1_EQ − entryRef|`.
* 50% guard: skip if price already at `C1_EQ`.
* `reward ≥ risk` → `OrderSend` market; else `OrderSend` **BuyLimit/SellLimit** at `C1_EQ ∓ risk`
  (exactly 1:1). Cancel the pending order if price reaches `C1_EQ` before fill; no time cancel.
* On fill: set position SL (sweep wick) and TP (`C1_EQ`) — plain SL/TP on the position, **no OCO,
  no trailing**.
* Lots via `CRT_Risk.mqh` (risk-% / margin cap / broker clamp). Skip trade if 1:1 SL is inside
  stops-level/spread.
* Global single-active-trade lock across all slots (live position or working pending).

---

## 5. Hour Filter, News, Notify, Dashboard, Visual

* **Hour filter** — reuse CCT's exact CSV parsing (`AppendHourSlots`, `SortHoursAsc`, `HasHour`);
  `Use_ExecHourFilter` gates on C3-open NY hour.
* **News** — port ORB_Scalper's FF calendar loader (`WebRequest` live + `MQL5/Files` cache +
  historical CSV), `NewsGuardMode`, blackout window blocks new entries.
* **Notify** — reuse `CCT_Notify.mqh` queue/retry/dedupe; CRT-specific setup/fill/close/cancel
  messages (bias, C1 range, EQ, trigger model).
* **Dashboard** — repurpose `CCT_Dashboard.mqh`: header (slot + C1 TF + NY clock), CRT rows
  (bias, C1 H/L/EQ, sweep, trigger, CISD, IFVG, entry, SL/TP, live R) + account/news rows.
* **Visual** — repurpose `CCT_Visual.mqh` object helpers for C1 box, EQ line, sweep marker, CISD
  line, FVG/IFVG rectangles, entry/SL/TP lines; back-draw 2–3 NY days; respect visual vs
  non-visual tester mode (ORB_Scalper pattern).

---

## 6. Build / Deploy Notes

* Place `CRT_MT5/` under `MQL5/Experts/CRT/`; compile `CRT_EA.mq5` in MetaEditor.
* Add the FF calendar host and Discord/Telegram hosts to **Tools → Options → Expert Advisors →
  Allow WebRequest for listed URL**.
* `#property strict`; use `CTrade` (Trade/Trade.mqh) for order sending, consistent with ORB/CCT.
* Reuse ORB_Scalper's visual/non-visual tester switches so backtests stay fast.
