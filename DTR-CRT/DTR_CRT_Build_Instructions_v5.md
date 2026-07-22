# DTR-CRT EA — Consolidated Build Instructions (v5, final)

This document fully replaces all prior build instruction versions. Read alongside
`DTR_CRT_Strategy_Spec_v2.md` (trading-logic source of truth). This file covers
architecture/porting decisions.

---

## 0. Core timing (unchanged — restated for completeness)

| Session | Range Window (NY) | Trading Window (NY) | Bias Candle | LTF Execution TF |
|---|---|---|---|---|
| London | 01:12–02:12 | 02:12–04:00 | 3.5H (18:00–21:30 / 21:30–01:00) | 4-Minute |
| New York | 08:12–09:12 | 09:30–10:30 | 7H (18:00–01:00 / 01:00–08:00) | 1-Minute |

Nothing below changes any of this. The layering is: **Bias Candles (Phase 1)** determine
direction → **Session Range (Phase 2)** is the tradeable level → **Confluence checks
(Section 5)** gate whether a trigger is allowed to fire → **Execution Window** is where the
EA watches LTF price action for CISD/FVG/IFVG.

## 1. No SDK / external routing

Both ORB_Scalper and CCT_v7 use direct native MQL5 only. Build DTR-CRT the same way.

## 2. Conflict resolution

Where ORB_Scalper and CCT_v7 disagree, ORB_Scalper is definitive (newer codebase).

## 3. Dynamic SL — resolved algorithm

1. `Natural_RR` = TP distance ÷ Fixed_SL_distance (Fixed_SL_distance = entry to the
   manipulation-leg extreme).
2. If `Natural_RR >= MinRR`: use Fixed SL unchanged.
3. If `Natural_RR < MinRR`: compute the SL distance required to hit MinRR exactly. If that
   distance falls below `Min_SL_Sanity_Distance` (broker stop-level or a multiple of
   spread), do not force it — fall back to the full Fixed SL distance and accept the lower
   resulting RR rather than place an unsafely tight stop.
4. SL distance never exceeds the original Fixed SL distance, in any branch.
5. No separate `MaxRR` input — it never binds under this logic.

## 4. BPR

`Require_BPR` (boolean), selectable in both live and Strategy Tester, default `false`. No
environment lockout.

## 5. Re-entry, confluence gate, and daily sweep (fully resolved)

### 5.1 No re-entries

Port `ConsumedKey()`/`SideConsumed()`/`MarkSideConsumed()` from ORB_Scalper **unchanged**
— one-shot per side per session, win or lose. `DTR_SessionManager.mqh` wraps this; no
TP-vs-SL distinction needed.

### 5.2 Two separate, independent toggles (not one merged input)

- **`Require_PriorSessionConfluence`** (default `false`) — lighter, session-specific check.
- **`Require_PriorDays_Level`** (default `false`) — stricter, universal daily check.
- **Precedence:** if `Require_PriorDays_Level` is `true`, it is evaluated standalone and
  `Require_PriorSessionConfluence`'s session-specific check is skipped entirely, regardless
  of that toggle's own state.

### 5.3 Session Range vs. Bias Candle — must not be conflated in code

- **Bias Candle (Phase 1):** Candle A/B — used only to compute directional bias. The Asia
  reference used throughout Section 5 is **this exact object** (the 18:00–01:00 7H
  candle), read directly — it is never built as a second, separate "session range" type.
  It confirms bias; it is reused as a sweep reference, but architecturally it stays a
  Phase 1 object.
- **Session Range (Phase 2):** `Range_High`/`Range_Low` — the narrow, locked London
  (01:12–02:12) and NY (08:12–09:12) ranges. These are genuine Phase 2 range objects, used
  for the original same-session Phase 3 sweep AND reused cross-session/cross-day for the
  confluence gate below. Because of that second use, **London's range must now also be
  persisted across day rollover** (`PriorDay_London_Range`) — this is a new persistence
  requirement that did not exist before this correction.

### 5.4 `Require_PriorSessionConfluence` — per-session reference lists

Each list is ordered **chronologically, oldest to newest**. The gate is satisfied if price
has swept **any one** of the levels in the active session's list (OR logic):

| Active Session | Reference list (oldest → newest) |
|---|---|
| London | `PriorDay_London_Range` → `PriorDay_NY_Range` → `Asia_Candle` (the same Phase 1 object, reused) |
| NY | `PriorDay_NY_Range` → `Asia_Candle` (same Phase 1 object) → `CurrentDay_London_Range` |

Only the boundary matching the active manipulation leg's direction is checked (Low for
long setups, High for short).

**Why this ordering, and the logging rule:** sweeping an older level necessarily means
price traded through the newer levels in the same list on the way there — a session
range can sit "Virgin" (untouched as a trigger reference) even while price has already
traded beyond it en route to an older level; that doesn't change that it was swept. So:
when recording which level satisfied the gate (trade comment + metadata), **log only the
oldest (first-matching) level in the chronological list that was actually swept** — do not
also log the newer levels it subsumes.

### 5.5 `Require_PriorDays_Level` — universal daily sweep

A separate, simpler, **session-agnostic** check — applies identically whether London or NY
is currently active, no per-session list.

- **Definition:** build a continuously-tracked "Prior True Day" range spanning one complete
  18:00 NY → 18:00 NY cycle. "Prior" means the **completed** cycle that ended at 18:00 NY
  today (i.e., 18:00 yesterday → 18:00 today, where "yesterday" and "today" are NY
  calendar dates). This is a single 24h synthetic candle, built continuously, not derived
  from the narrower Asia/London/NY sub-objects — there are uncovered hours between those
  sub-objects where the true daily extreme could print.
- **Construction:** built as a 4th synthetic HTF candle type using the exact same pattern
  as Candle A/B (Section 8), with a 24-hour period anchored at 18:00 NY.
- **Why 18:00 and not 00:00 (midnight):** ICT distinguishes "Midnight Open" (00:00 NY, a
  separate bias-reference concept) from the "True Day Open" (18:00 NY, matching CME
  futures session rollover) — the latter is the authoritative institutional day-boundary
  for true daily range work. 18:00 is also the only choice internally consistent with this
  strategy, since Candle A already starts at 18:00 — anchoring at midnight would split the
  Asia candle across two different "days."
- **Condition:** price must have swept the **single boundary matching the active
  manipulation leg's direction** (Low for long setups, High for short setups) of the
  completed Prior True Day range. Same single-side rule as Section 5.4 — the difference
  is only the size of the reference object (one full 18:00→18:00 cycle vs. a narrower
  session-specific range).
- When this toggle is `true`, no per-session list (5.4) is evaluated — see precedence in
  5.2.

### 5.6 Exact lock times for all tracked reference objects

Every swept-flag is keyed to the moment its reference object's data is fully available
and locked. These are the authoritative lock times — off-by-one errors here are easy and
expensive to debug:

| Object | Locks at (NY time) | Notes |
|---|---|---|
| `PriorDay_London_Range` | 02:12 NY, yesterday | Yesterday's London Range Window close |
| `PriorDay_NY_Range` | 09:12 NY, yesterday | Yesterday's NY Range Window close |
| `CurrentDay_Asia_Candle` | 01:00 NY, today | The 18:00→01:00 7H Candle A closes; this is the same object used for bias calc |
| `CurrentDay_London_Range` | 02:12 NY, today | Today's London Range Window close |
| `Prior_True_Day` (Require_PriorDays_Level) | 18:00 NY, today | The completed 18:00(yesterday)→18:00(today) cycle locks the moment today's True Day opens |

"Yesterday" and "today" above are relative to the currently active session on a given
trading day, in NY time.

### 5.7 Swept-flag state model — one-way latch, continuously tracked

This applies to every swept-flag across both confluence toggles (5.4 and 5.5). The
implementation must treat these as persistent boolean flags, not live comparisons:

- **Tracking begins the moment an object locks** (see 5.6 for exact lock times), not when
  a window opens. This means Asia can satisfy a flag for London's session before London's
  own Range Window even opens — the flag simply reads `true` by the time the check runs.
- **One-way latch:** once a flag is set `true`, it stays `true` for the lifetime of that
  object — it must never be implemented as "is price currently beyond the level right now,"
  which would flicker as price moves back inside. Liquidity taken is taken.
- **Sweep definition is wick-sufficient, no close required** — exactly as defined in
  Strategy Spec Section 0 (same as the Phase 3 range-boundary sweep definition). No new
  or stricter definition applies here.
- **Gate evaluated at trigger time:** when a CISD/FVG/IFVG trigger forms and wants to
  fire, the EA reads the relevant flag(s). If any required flag is still `false` at that
  moment, the trigger is suppressed. The EA continues watching; the first valid trigger
  that forms after the flag finally flips `true` becomes the permitted entry.
- **Flags persist within the same True Day** and are reset at the next 18:00 NY rollover.
  They must be stored in a way that survives EA restarts within the same day (i.e.,
  same persistence layer as `MarkSideConsumed()` — see Section 5.1). This is not optional;
  losing flag state on a crash/restart during a live session is a live trading bug.

### 5.8 Persistence vs. visibility

- All reference objects (`PriorDay_NY_Range`, `PriorDay_London_Range`, `Prior_True_Day`,
  `CurrentDay_Asia_Candle`) are **always persisted**, regardless of whether either gate
  toggle is enabled — they are needed for mid-session init recovery (Section 10) as well
  as the gate logic.
- `Show_Prior_Session_Levels` — a separate, visual-only toggle, independent of both gate
  toggles, so these levels can be audited on chart at any time.

### 5.9 Historical visual scoping (unchanged, reaffirmed)

The 2–3 day historical drawing (CCT-style) covers **only** the 7H/3.5H bias candles and
execution objects for prior days. The confluence reference-level boxes
(`Show_Prior_Session_Levels`) render **only for today's** relevant levels — never
redrawn retroactively for past days, regardless of which gate toggle they belong to.

## 6. ORB_Time.mqh — precise port boundary

**Port verbatim:** `ServerNYOffsetSec()`, `NYUTCOffsetSec()`, `NthSundayOfMonthUTC()`,
`IsNYDSTDate()`, `ServerToNY()`, `NYLocalToServer()`, `NYIsDST()`, `CurrentNYSessionKey()`,
`TesterWeekAnchorOffsetSec()`, `MakeDateTime()`. Pure conversion primitives, no
session-specific assumptions, auto-detect each broker's server-to-NY offset at runtime.

**Do not port as-is:** `SessionOpenServer()`/`SessionCutoffServer()`/`ResolveActiveSession()`
assume ONE mutually-exclusive active session. DTR needs Asia/London/NY anchors tracked
concurrently. Build a new orchestration layer in `DTR_Time.mqh` on top of the ported
primitives.

## 7. Tick vs. Timer architecture — non-negotiable

1. **All trading-correctness logic** (sweep detection, CISD, FVG/IFVG, confluence gate
   evaluation, entry triggers, order placement, BE/SL management) lives in `OnTick()`.
   Zero dependency on `OnTimer` firing.
2. `OnTimer()`, if used, is only a live-mode convenience duplicate (mirroring
   ORB_Scalper's 200ms live-only pulse). Must be a no-op in non-visual tester
   (`MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)`).
3. **Caching allowed for CISD/FVG/IFVG scanning only.** Follow CCT_EA_v7.mq5's
   `CCTShouldRunNonVisualTesterScan`/`CCTNonVisualCachedReplayNeedsScan` pattern: re-scan
   only on an HTF boundary, an exec/carry bar, or a closed-bar close crossing a tracked
   level; otherwise reuse cached state. Safe because CISD and FVG/IFVG are defined on
   candle closes per the spec.
4. **Exception — never cache, always tick-level, every mode:** Breakeven trigger checking
   and FVG-retest limit-fill checking. Mirrors CCT_EA_v7.mq5's
   `CCTNonVisualTesterCanSkipIntrabarManagement()`, which refuses to skip intrabar work
   whenever BE is active — DTR's BE is always active. This boundary (3 vs. 4) is the most
   likely place a tester/live discrepancy hides — treat it as load-bearing.

## 8. Synthetic HTF candle construction — anchor time is 18:00 NY, not 17:00

**Critical correction for the coding bot:** CCT_EA_v7.mq5 builds its synthetic
multi-timeframe candles using a `NY1700` anchor (`CCTNY1700DailyOpenForServerTime`,
`CCTLoadSyntheticDailyHTFScannerState`). **DTR-CRT does not use 17:00.** Do not carry
that anchor time over. The 17:00 anchor was appropriate for CCT's own strategy; for
DTR-CRT the correct anchor is **18:00 NY** (the ICT True Day Open / CME futures session
open), because every HTF object in this strategy — Candle A, Candle B, and the Prior True
Day range — is explicitly bounded by 18:00 NY. Using 17:00 would shift every synthetic
candle boundary by one hour, silently misidentifying which session a bar belongs to.

**What to port from CCT vs. what to change:**
- **Port the structural pattern:** the way `CCTLoadSyntheticDailyHTFScannerState()` builds
  custom-anchored OHLC bars by aggregating M15 (or M1) source bars, the caching keyed by
  symbol + HTF type + lookback bar count, and the rule that a candle is only rebuilt when
  a new HTF bar closes.
- **Replace the anchor function:** do not use `CCTNY1700DailyOpenForServerTime`. Write a
  new function `DTRNYTrueDayOpenForServerTime(datetime serverTime)` that returns the server
  timestamp corresponding to 18:00 NY on the True Day that `serverTime` falls within, using
  the exact same `ServerToNY()`/`NYLocalToServer()` primitives ported from ORB_Time.mqh
  (Section 6). This one function, called with the correct 18:00 anchor, is the single
  source of truth for all HTF bar boundaries in this EA.

**Build three anchor functions on top of `DTRNYTrueDayOpenForServerTime`:**

| Candle type | Period | Boundaries (NY time) | Used for |
|---|---|---|---|
| 7H Candle A | 7 hours | 18:00 → 01:00 | NY session bias, Candle A |
| 7H Candle B | 7 hours | 01:00 → 08:00 | NY session bias, Candle B |
| 3.5H Candle A | 3.5 hours | 18:00 → 21:30 | London session bias, Candle A |
| 3.5H Candle B | 3.5 hours | 21:30 → 01:00 | London session bias, Candle B |
| 24H Prior True Day | 24 hours | 18:00 → 18:00 | `Require_PriorDays_Level` gate (5.5) |

The 7H and 3.5H pairs share the same True Day anchor (18:00) and their sub-boundaries
fall out naturally from it — no separate anchor function needed per sub-candle, just
offsets from the same 18:00 base.

**For the historical visual daily separator (Section 11):** CCT's `DrawDailySeparator`
draws its `OBJ_VLINE` at the NY day open — for DTR-CRT this separator must be placed at
the **18:00 NY** server-time equivalent, not 17:00. Use `DTRNYTrueDayOpenForServerTime`
to compute the correct server timestamp for the separator line.

## 9. FVG / IFVG geometry

CCT_Scanner.mqh's `FVGInfo` struct and `TrackGenerationFVGFormation()` — 3-candle gap
detection, `c1Ext`/`c3Ext` boundary tracking, inversion check (close beyond `c1Ext`) —
reuse as-is for `DTR_Scanner.mqh`.

**Do not assume the rest transfers.** CISD and "BPR" do not exist anywhere in CCT's
codebase. CCT's FVG/IFVG handling is embedded in its Virgin Wick sibling/generation/birth
POI framework, which DTR doesn't use. Extract only the `FVGInfo` struct + detection
geometry. CISD, the FVG-retest sequencing (sweep → CISD → 1stPFVG → entry), and the
entry-price-mode logic (Edge Touch / Shallow Fill % / market-on-C3-close) are new work.

## 10. Mid-session init recovery — full historical replay required

When the EA attaches mid-Range-Window, mid-Trading-Window, or at any point during the
active True Day after 18:00 NY, it must reconstruct **all** of the following from M1
history — not just live tick accumulation going forward:

1. **Range_High / Range_Low** for the active session: replay M1 bars from the Range
   Window open to the current server time (or Range Window close if it has already passed).
2. **All swept-flags** (Section 5.7): for every reference object that has already locked
   (see exact lock times in 5.6), replay M1 bars from that object's lock time forward
   through every bar up to the current time, checking whether the relevant boundary (High
   for short setups, Low for long setups) was ever penetrated intrabar (wick-sufficient).
   If it was, set the flag `true` — do not leave it `false` simply because the EA wasn't
   running at the time the sweep occurred.
3. **Prior True Day range** (if `Require_PriorDays_Level` enabled or `Show_Prior_Session_Levels`
   on): the 24H synthetic candle for the completed prior True Day must be built from M1
   history, identical to the normal build process — it just happens retroactively on init
   rather than incrementally in real time.

This replay must run in `OnInit()` before the EA begins processing live ticks. Failure to
replay swept-flags means the confluence gate will silently reject valid entries for the
rest of the session after a restart — a live trading bug with no visible error.

## 11. Visual / execution object anchoring (resolved, per-element selection)

| Element | Take from | Why |
|---|---|---|
| Object naming | **ORB** (`ORBPfx()+"SL_"+ts`, ticket-keyed) | CCT's naming is coupled to its sibling/generation POI system, which DTR doesn't have. |
| Entry anchor | **ORB** (separate "level" object/time vs. actual fill price/time) | Matters more for DTR, where `FVGRetestEntryMode` (Edge Touch vs. Shallow Fill %) means signal level and fill price can differ, plus slippage. |
| Resolved right-edge (post-exit box width) | **ORB** (enforces minimum 2-bar width after resolution) | CCT's resolved edge has no such floor — can render unreadably narrow boxes on fast-resolving trades. |
| Live right-edge (pre-resolution box width) | **Either — already converged** | Both compute `max(triggerTime + 5×LTF_bars, live_edge)`. |
| BE threshold pre-visualization | **CCT** (threshold line drawn at entry, before it's hit, then replaced by a distinct fired-BE line once applied) | ORB only draws after the fact. CCT's pre-visualization is more useful for auditing DTR's precise `BE_TriggerPercent`/`BE_LockPercent` system, since the threshold price is known the instant a trade opens. |
| FVG / IFVG zone boxes | **CCT** (`DrawFVGBox`/`CreateFVGFillBox`) — only available reference | Filled rectangle spanning `c1Ext`/`c3Ext`, distinct bull/bear colors (`Inp_ClrFVGBull`/`Inp_ClrFVGBear`). Also port the candidate-vs-confirmed style distinction (dotted/thin while forming, solid/thick once the entry trigger fires). |
| Daily separator (multi-day history) | **CCT** (`DrawDailySeparator`, `OBJ_VLINE` at NY day open) | Purely additive, useful for the 2–3 day historical-population requirement and for visually delineating prior-day persistence (Section 5). |
| Tooltip density | **CCT** convention (RR, risk %, BE thresholds, model label) | Adapt to DTR's own fields: CISD reference mode used, FVG retest entry mode used, and — when either gate toggle is on — which level satisfied it (per the oldest-level-only logging rule in 5.4, or "Prior True Day swept" for 5.5). |

## 12. Range / Candle A / Candle B / Entry-highlight visual scheme

Reuse existing drawing primitives (`DrawRangeBox`, `ORBCreateBorderBox`,
`ORBCreateHLine`/`CreateHLine`, write-through setters, chart-scoped naming,
`ShouldRenderVisuals()` guard) — no new drawing primitives needed:

- **Range box** — the active session's Range_High/Range_Low. `Show_Range_Box` toggle.
- **Candle A box** — new color `Inp_ClrCandleA_Box`, `Show_CandleA_Box` toggle,
  border-only.
- **Candle B box** — new color `Inp_ClrCandleB_Box`, `Show_CandleB_Box` toggle,
  border-only, visually distinct from Candle A.
- **Entry/trigger time highlight** — new color `Inp_ClrEntryHighlight`,
  `Show_EntryHighlight` toggle, marking the confirmed CISD/IFVG/FVG-retest window.

All objects default to visually distinct colors — Candle A, Candle B, and the Range box
can all be on screen simultaneously.

## 13. File / module plan (final)

```
MQL5\Experts\DTR-CRT\
  DTR_CRT.mq5            — main EA: OnInit/OnTick/OnTimer, all inputs
  DTR_Time.mqh            — ported primitives (Section 6) + concurrent multi-session
                            orchestration + 24H Prior True Day anchor (Section 5.5/8)
  DTR_HTF_Bias.mqh        — synthetic 7H/3.5H/24H candle construction (Section 8) + bias
                            truth table (strategy spec Section 2)
  DTR_Scanner.mqh         — sweep detection, manipulation leg, CISD, FVG/IFVG (Section 9),
                            both confluence checks (Section 5.4 and 5.5)
  DTR_SessionManager.mqh  — ported ConsumedKey pattern (5.1), range-locked state, Trading
                            Window state, all prior-day/session level persistence (5.6)
  DTR_Execution.mqh       — entry models (IFVG / FVG Retest), Fixed/Dynamic SL (Section 3)
  DTR_Risk.mqh            — percentage-based BE (strategy spec Section 6.3), lot sizing
                            ported from ORB_Scalper
  DTR_Visuals.mqh         — per-element selections (Section 11), color scheme (Section 12)
  DTR_Dashboard.mqh       — ported from ORB_Dashboard.mqh, extended for session/bias/
                            confluence-gate state display
```

Re-issue confirmation of this plan before writing any code.
