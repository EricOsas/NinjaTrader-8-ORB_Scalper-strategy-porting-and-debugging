# CCT EA — Repository Guidelines

## Live Root And Reference Paths
Project root: `C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\F49F6D84DE337BA25E6F8205834F0EB8\MQL5\Experts\CCT`

Primary references (read in this order):
1. `C:\CCT\All things needed to code\CCT_CONSTITUTION_v3.md` — authoritative master
2. `C:\CCT\All things needed to code\CCT_Master_Build_Specification_For_Codex.txt`
3. `C:\CCT\All things needed to code\CCT_Extended_Specifications.txt`
4. `C:\CCT\All things needed to code\CCT TECHNICAL CONSTITUTION.txt`
5. `C:\CCT\All things needed to code\mql5book.pdf`
6. `C:\CCT\Only read these when asked\Next Instructions.txt`

**Precedence:** Latest explicit user clarification > CCT_CONSTITUTION_v3 > Master Build Spec > Extended Specs > Legacy behavior.

## File Ownership
- `CCT_Scanner.mqh` — scanner, POI, generation, sibling supersession, C1/C2/C3, CO, IFVG winner, TS sweep count logic.
- `CCT_Visual.mqh` — chart object lifecycle, drawing, MT5 anchoring, TF visibility masks, prune behavior, tooltip content.
- `CCT_Execution.mqh` — post-fill truth, order placement, outcome resolution, BE management, execution records.
- `CCT_Globals.mqh` — shared enums, inputs, structs, caches, NY-time helpers, signal exports.
- `CCT_EA_v7.mq5` — orchestration only: `OnInit`, `OnTick`, `OnTimer`, `OnDeinit`, redraw scheduling, shared scanner refresh, module wiring.
- `CCT_Dashboard.mqh` — out of scope unless explicitly requested.

## Working Rules
- Patch live files directly.
- Prefer minimal targeted edits over rewrites.
- Do not rebuild from scratch.
- Do not treat legacy behavior as authoritative unless it matches the constitution.
- Compile after source edits unless the user explicitly asks not to. Primary compiler path on this machine: `C:\MetaTrader 5\MetaEditor64.exe`. Default MT5 installs may also expose `MetaEditor64.exe` under `C:\Program Files\...`.
- Compile command pattern: `& "C:\MetaTrader 5\MetaEditor64.exe" /compile:"<absolute path>\CCT_EA_v7.mq5" /log:"<absolute path>\CCT_EA_v7.log" /portable`.
- Dashboard work only when explicitly asked.

## Corrected Core Logic (Override Legacy Behavior)

### Sibling Activation Order
- All siblings start VALID and equal at birth.
- Shallowest sibling achieves C1 first → ACTIVE; all deeper siblings → INACTIVE.
- When a deeper INACTIVE sibling achieves C1 → deeper = ACTIVE; previously-active shallower = DEAD by supersession.
- Even deeper siblings stay INACTIVE. The cascade repeats for each deeper activation.
- This is the OPPOSITE of any prior implementation that activated deeper siblings first.

### CCT Model Classification
- Model type (CCT / CCT+TS / CCT+TS Ext) is determined by opposing virgin wick sweep count at trigger time.
- NOT by bar distance between birth and execution bar.
- Birth bar = any in-day bar; no fixed birth-to-execution offset required.
- C1 must still only occur on a selected execution bar or the POI is killed immediately.

### C1 Kill — Immediate, Not Deferred
- C1 on a non-execution bar kills the POI at C1 detection. Not at bar close.

### IFVG — Most Recent Inversion Wins
- Most recently inverted FVG = active trigger FVG.
- FVGs are NOT invalidated by price. Only superseded by newer inversions.
- FVG eligibility: from CO formation through trigger. Pre-C1 and post-C2 FVGs are eligible.
- SL geometry uses the most recently inverted FVG cluster at trigger close.

### CO Violation
- Any bar that touches CO (wick or body) AND closes at or beyond CO without C2+C3 confirmed on that same close = POI killed at bar close.
- If bar closes with C2+C3 confirmed: NOT a violation. Trade triggers.

### SL Anchor A
- Standard mode: FVG first candle's LOW for bullish (bearish FVG, C1.low = gap bottom). FVG first candle's HIGH for bearish (bullish FVG, C1.high).
- V-Shape/Deep Swing: monitored continuously from FVG formation through trigger close. Any tick beyond Anchor B = Deep Swing. Can upgrade from V-Shape to Deep Swing after inversion. If FVG superseded, restart for new FVG.

### Action Pillars
- NOT drawn for dormant generations. NOT drawn for generations with no authorized execution bar in the current config.
- Always drawn for valid, active, triggered generations.
- Reappear when a dormant generation is activated.
- Candidate POI action pillars show by default alongside live candidate POIs.
- Generations activated within the current NY day keep their AP visible for that day.

### Previous-Day Dormant
- Only the two most recent in-bias valid/dormant generations from previous day are eligible.
- Eligible ONLY for 00:00–03:00 NY triggers. After 03:00: current-day only.

### Entry Price
- Synthetic: trigger bar close. Used for chart geometry always.
- Broker fill: actual Ask/Bid at placement. Used for broker SL/TP.
- Only differ if broker fill doesn't occur at trigger close.

### Resolved Trade Display
- Full execution objects persist until midnight. No arrow compression within the trading day.

### Multi-Trade Authority
- Multiple trades may be open from different generations simultaneously.
- No pending order queue. Execute immediately on trigger.
- Carry-over bar (C2+C3 completion) cannot host a new independent trigger.

### Dormant Visibility
- Dormant POIs: completely hidden until activated by shoot-through.
- On activation: frontrunning generation's last active POI dies by generation supersession.

### CO Visual Lifecycle
- CO hit → TP: CO line cleared at TP.
- CO hit → BE: CO line stays until midnight cleanup.

## Execution Window Rules
One birth creates one execution window. The Action Pillar is the open of the next HTF bar after birth; no trade is valid before it. One execution per generation forever — no second trigger from the same generation under any circumstances. After a trigger, all remaining INACTIVE siblings in that generation die immediately. Older deeper in-bias dormant generations may supersede newer untriggered generations when an execution window is open; that supersession follows the structural model classification by sweep count.

## MT5 Anchoring Rules
- Right anchor for live objects: SERIES_LASTBAR_DATE(LTF) + one LTF period. Never a future HTF open.
- Full-content TF mask: M1 through HTF (FullContentTFs()).
- LTF-only objects: M1–M3 (LTFMaxTFs()).
- Dual-object POI lines: one LTFOnlyFlag, one AboveHTFFlag.
- Dashboard: OBJ_ALL_PERIODS.
- Tooltips required on all objects, matching live content in tester mode.

## Tester Performance
- Non-visual mode: suppress ALL chart object creation and dashboard rendering.
- Visual mode: bar-change gate on full draw; separate hint animation (tick) from structural draw (bar); cache LTF data.

## Visibility Rules
- In-bias dormant POIs: hidden by default. Revealed only on shoot-through activation.
- Dead POIs: hidden unless ShowKilled is enabled.
- Counter-bias POIs: never shown.
- Action pillars: shown by default for candidate POIs and non-dormant generations with authorized or current-day-activated visibility. Dormant APs stay hidden until that generation activates again.

## Reporting Format
For implementation work, report:
- Files changed
- Exact functions changed
- Exact root cause
- What was intentionally not changed
- Runtime checks for the user
