# DTR_Dashboard.mqh — Full Specification

This document defines every panel row, state, color, and update-function signature needed
to implement `DTR_Dashboard.mqh`. The coding bot must not invent anything not stated here.

---

## 1. Infrastructure (port verbatim from ORB_Dashboard.mqh)

Port the following **unchanged**:
- `_DB_BG()`, `_DB_GLASS()`, `_DB_PANEL()`, `_DB_BORDER()`, `_DB_HAIR()`, `_DB_TEXT()`,
  `_DB_MUTED()`, `_DB_ACCENT()`, `_DB_GREEN()` — three-theme color resolvers (Dark/Dim/Light).
- `_DB_Label()` — non-destructive OBJ_LABEL setter (create once, update properties only).
- `_DB_Rect()` — non-destructive OBJ_RECTANGLE_LABEL setter.
- `_DB_CanDraw()` — guard: returns false if dashboard disabled or running in non-visual tester.
- `DB_RestoreState()` / `DB_PersistState()` — GlobalVariable-backed position + collapse state,
  key prefix changed from `ORB_DB*` to `DTR_DB*`.
- `DB_Layout()` — shadow stack, header panel, accent pill, hairline, sheen. Title text
  changed to `"DTR · CRT"`.
- `DB_ShiftTo()` / `DB_BeginDrag()` / `DB_EndDrag()` / `DB_DragTo()` — drag machinery.
- `DB_HeaderHit()` / `DB_ToggleCollapse()` — hit-test and collapse/expand toggle.
- `InitDashboard()` / `ClearDashboard()`.
- All object name prefixes change from `ORBD_` to `DTRD_` throughout.
- Dirty-signature guard pattern (build a string of all visible values; skip object writes
  and `ChartRedraw(0)` if signature hasn't changed).

**Add one new theme color function** — not in ORB:
```
color _DB_RED()  { return C'220,90,80'; }   // blocked / failed indicator
color _DB_AMBER() { return C'210,160,50'; } // partial / pending trade indicator
```

---

## 2. Panel geometry

| Constant | Value | Notes |
|---|---|---|
| `DB_W` | 340 | Wider than ORB's 300px — more columns needed |
| `DB_HDR_H` | 36 | Same as ORB |
| `DB_ROW_H` | 20 | Standard row height |
| `DB_ROW_H_LG` | 24 | Large row (phase banner, bias direction row) |
| `DB_INDENT` | 14 | Left text margin |
| `DB_IND_X` | 8 | X offset of indicator dot from panel left edge |
| `DB_IND_SZ` | 8 | Width and height of indicator dot rectangle |
| `DB_IND_MID` | `DB_ROW_H/2 - DB_IND_SZ/2` | Vertical center of dot within a standard row |
| `DB_FULL_H` | Computed dynamically — see Section 6 | Varies by state |

---

## 3. DTRDashState struct

`UpdateDashboard()` accepts a single `DTRDashState` struct. Define it in
`DTR_Dashboard.mqh`. The EA populates it before every `OnTick()` UI update call.

```mql5
struct DTRDashState
{
    //--- Session & Phase
    string session;           // "London" | "NY" | "--"
    string phase;             // "Waiting" | "Range Forming" | "Range Locked" |
                              // "Trading Window" | "Closed"
    int    secsToNextPhase;   // seconds remaining until next phase boundary;
                              //  0 = phase has no countdown (e.g. "Closed")

    //--- HTF Bias
    string biasDir;           // "LONG" | "SHORT" | "NEUTRAL" | "NO TRADE"
    string candleBPos;        // "Discount" | "Premium" | "Inside Bar"
    string sweepType;         // "Swept High" | "Swept Low" | "Swept Both" | "No Sweep"
    double aHigh;             // Candle A High (0 = not yet computed)
    double aEQ;               // Candle A midpoint
    double aLow;              // Candle A Low

    //--- Range
    bool   rangeLocked;
    double rangeHigh;         // 0 = not yet formed
    double rangeLow;

    //--- Checklist
    int    sweepState;        //  0 = awaiting  |  1 = done  | -1 = n/a (NoTrade session)
    string sweepDetail;       // e.g. "High swept 09:34" | "Low swept 09:31"

    int    gateMode;          //  0 = none  |  1 = session gate  |  2 = daily gate
    int    gateState;         //  0 = awaiting  |  1 = satisfied  |  2 = carried from prior session
    string gateDetail;        // e.g. "Asia Low (09:15)" | "Prior Day Low" | "↩ London 02:41"

    int    cisdState;         //  0 = awaiting  |  1 = confirmed
    string cisdDetail;        // e.g. "09:36" (NY time)

    string entryModel;        // "IFVG" | "FVG Retest (Edge)" | "FVG Retest (5%)"
    int    triggerState;      //  0 = awaiting  |  1 = limit pending  |  2 = fired (in trade)
    string triggerDetail;     // e.g. "IFVG @ 2019.40" | "Limit @ 2019.25" | "Filled 09:38"

    //--- Trade State (only meaningful when inTrade = true or sideConsumed = true)
    bool   inTrade;
    string tradeDir;          // "LONG" | "SHORT"
    double entryPx;
    double slPx;
    double tpPx;
    double liveRR;            // current unrealised RR (distance to TP / risk) — 0 if not in trade
    string slMode;            // "Fixed" | "Dynamic"
    int    beState;           //  0 = pending  |  1 = activated
    string beDetail;          // "Threshold @ 2018.10 (30%)" | "SL moved → 2019.40 (5% locked)"

    //--- Side State
    bool   sideConsumed;      // true once the one permitted entry attempt was made
    string consumedResult;    // "Won" | "Lost" | "BE" — only meaningful when sideConsumed=true
};
```

---

## 4. Indicator dot rules

Every checklist row has a small 8×8 rectangle (`OBJ_RECTANGLE_LABEL`) on its left as a
status indicator. Color logic per `state` value (used consistently across all rows):

| State value | Dot color | Meaning |
|---|---|---|
| 0 (awaiting) | `_DB_MUTED()` | Not yet satisfied; still possible |
| 1 (done/satisfied/fired) | `_DB_GREEN()` | Condition met |
| 2 (carried / partial) | `_DB_ACCENT()` | Satisfied via carryover from a prior session |
| -1 (not applicable) | `_DB_BORDER()` | Session is NO TRADE — row greyed out |
| -2 (blocked) | `_DB_RED()` | Gate enabled, level NOT swept, trigger would have fired but was blocked |

State -2 only applies to the Gate row and is set when: `gateMode > 0` AND `gateState == 0`
AND `triggerState >= 1`. This makes it visible that the gate is actively suppressing an entry.

---

## 5. Full row layout (top to bottom)

All Y positions are relative to `g_dbY`. Object names use the `DTRD_` prefix.

### 5.0 Header (ported from ORB, always visible, Y=0..35)

| Object | Type | Content | Notes |
|---|---|---|---|
| `DTRD_SHADOW2` | Rect | depth shadow 2 | offset +6,+7 |
| `DTRD_SHADOW` | Rect | depth shadow 1 | offset +3,+3 |
| `DTRD_BG` | Rect | main panel body | full panel H |
| `DTRD_HEADER` | Rect | header band | H=36 |
| `DTRD_PILL` | Rect | accent pill | 8×8 at X+12,Y+14 |
| `DTRD_TITLE` | Label | `"DTR · CRT"` | `_DB_ACCENT()`, size 9 |
| `DTRD_SESSION_HDR` | Label | `"London"` / `"NY"` / `"--"` | `_DB_MUTED()`, size 8, right of title |
| `DTRD_CLOCK` | Label | `"NY HH:MM:SS"` | `_DB_MUTED()`, size 8, right-aligned |
| `DTRD_BTN` | Button | `"+"` / `"–"` | collapse button, same as ORB |
| `DTRD_HAIR` | Rect | hairline divider | 1px below header |
| `DTRD_HAIR2` | Rect | hairline shadow | 1px below HAIR |
| `DTRD_SHEEN` | Rect | sheen band | 8px below hairline |

Session label (`DTRD_SESSION_HDR`) shows the currently active session name. Position it
at `X + 75, Y + 11`. When no session is active, show `"--"` in `_DB_MUTED()`.

### 5.1 Phase Banner (Y=46, height=24)

Single row spanning the full panel width. No indicator dot.

| Object | Content | Color logic |
|---|---|---|
| `DTRD_PHASE` | Phase label + countdown | See below |

**Content and color per phase:**

| `phase` value | Text displayed | Color |
|---|---|---|
| `"Waiting"` | `"Waiting · Range opens in HH:MM"` | `_DB_MUTED()` |
| `"Range Forming"` | `"Range Forming · locks in MM:SS"` | `_DB_ACCENT()` |
| `"Range Locked"` | `"Range Locked · Trading Window in MM:SS"` | `_DB_TEXT()` |
| `"Trading Window"` | `"Trading Window · closes in MM:SS"` | `_DB_GREEN()` |
| `"Closed"` | `"Session Closed"` | `_DB_MUTED()` |

Countdown format: use `MM:SS` when `secsToNextPhase < 3600`, `HH:MM` otherwise.
When `secsToNextPhase == 0` (phase has no countdown), omit the `" · "` portion entirely.

### 5.2 Section divider (1px hairline, Y=70)

`DTRD_DIV1` — `_DB_BORDER()` fill, 1px height, full panel width.

### 5.3 HTF Bias Block (Y=72..139, three rows)

Section label: none — the bias block is self-labelling via its direction row.

**Row A — Bias Direction (Y=72, height=24, large row)**

| Object | Content | Color logic |
|---|---|---|
| `DTRD_BIAS_IND` | Indicator dot | State 1→GREEN (LONG/SHORT), State 0→MUTED (NEUTRAL), State -1→RED (NO TRADE) |
| `DTRD_BIAS_DIR` | Bias direction text | See below |
| `DTRD_BIAS_TF` | Candle period label | `_DB_MUTED()`, right-aligned in row |

`DTRD_BIAS_DIR` content and color per `biasDir`:
- `"LONG ↑"` → `_DB_GREEN()`
- `"SHORT ↓"` → `_DB_RED()`
- `"NEUTRAL ↔"` → `_DB_TEXT()`
- `"NO TRADE —"` → `_DB_MUTED()`

`DTRD_BIAS_TF` content: `"7H"` (NY session) or `"3.5H"` (London session), shown in
`_DB_MUTED()` at `X + DB_W - 30, Y_row + 5`. Shows which synthetic candle period is
currently in use.

**Row B — Candle B Position (Y=96, height=20)**

| Object | Content | Color logic |
|---|---|---|
| `DTRD_CANDLEB_IND` | Indicator dot | 1→GREEN (Discount long / Premium short align with bias), 0→MUTED (opposite or Inside) |
| `DTRD_CANDLEB_POS` | Position label + sweep label | See below |

`DTRD_CANDLEB_POS` content: two parts separated by a thin `"·"`:
- Part 1 (position): `"Discount"` (Candle B closed below A_EQ) in `_DB_GREEN()`, OR
  `"Premium"` (Candle B closed above A_EQ) in `_DB_RED()`, OR
  `"Inside Bar"` in `_DB_MUTED()`.
- Part 2 (sweep type): `"Swept High"` / `"Swept Low"` / `"Swept Both"` / `"No Sweep"` in
  `_DB_MUTED()`.

Example rendering: `"Discount · Swept High"` or `"Inside Bar · No Sweep"`.

The indicator dot for this row is GREEN when the Candle B position (Discount/Premium) is
consistent with the active bias direction (e.g., Discount + LONG bias, or Premium + SHORT
bias). It is MUTED when the position is neutral or opposite (including Inside Bar or
NO TRADE sessions).

**Row C — Reference Levels (Y=116, height=20)**

| Object | Content | Font |
|---|---|---|
| `DTRD_REF_LEVELS` | `"A: H 2024.50  EQ 2019.25  L 2014.00"` | Consolas, size 7, `_DB_MUTED()` |

When `aHigh == 0` (bias not yet computed), show `"A: H --  EQ --  L --"`.
No indicator dot on this row — informational only.

### 5.4 Section divider (Y=136)

`DTRD_DIV2` — same style as DIV1.

### 5.5 Range Block (Y=138, height=20)

**Row D — Range Status**

| Object | Content | Color logic |
|---|---|---|
| `DTRD_RANGE_IND` | Indicator dot | 0=MUTED (forming/waiting), 1=GREEN (locked) |
| `DTRD_RANGE_VAL` | Range text | See below |

Content per state:
- `rangeLocked == false` and phase is `"Range Forming"`:
  `"Range  H: --  L: --  (forming…)"` in `_DB_MUTED()`
- `rangeLocked == true`:
  `"Range  H: 2024.50  L: 2018.30  (63pts)"` in `_DB_TEXT()`
  — point distance displayed as `(rangeHigh - rangeLow) / _Point` rounded to nearest
  integer, labelled `"pts"`.
- Otherwise (waiting, no range yet):
  `"Range  H: --  L: --"` in `_DB_MUTED()`

Font: Consolas, size 8 for the price values.

### 5.6 Section divider (Y=158)

`DTRD_DIV3`.

### 5.7 Checklist Block (Y=160 onward)

Section header label: `DTRD_CL_HDR` — text `"Setup Checklist"`, `_DB_MUTED()`, size 7,
italic if available (use `"Segoe UI"` with no bold), at `X+DB_INDENT, Y_section`.
This label row itself is 16px tall.

Checklist rows follow immediately below the header, each 20px tall.

**Row E — HTF Alignment (Y=176)**

| Object | Key | Content |
|---|---|---|
| `DTRD_CL_HTF_IND` | Indicator | State from `biasDir`: 1 if LONG/SHORT/NEUTRAL, -1 if NO TRADE |
| `DTRD_CL_HTF_LBL` | Left label | `"HTF Alignment"` in `_DB_TEXT()` |
| `DTRD_CL_HTF_VAL` | Right value | Mirrors `biasDir` text, colored per bias (GREEN/RED/TEXT/MUTED) |

The value is right-aligned at `X + DB_W - DB_INDENT`.

**Row F — Range Sweep (Y=196)**

| Object | Key | Content |
|---|---|---|
| `DTRD_CL_SWP_IND` | Indicator | `sweepState` (0/1/-1) |
| `DTRD_CL_SWP_LBL` | Left label | `"Range Sweep"` |
| `DTRD_CL_SWP_VAL` | Right value | `sweepDetail` when `sweepState==1`, else `"Awaiting…"` in `_DB_MUTED()` |

**Row G — Confluence Gate (Y=216) — ONLY shown when `gateMode > 0`**

Left label changes per `gateMode`:
- `gateMode == 1`: label = `"Session Confluence"`
- `gateMode == 2`: label = `"Daily Confluence"`

Right value and color per `gateState`:
- `0` (awaiting): `"Awaiting sweep…"` in `_DB_MUTED()`. Indicator = MUTED.
- `1` (satisfied): `gateDetail` (e.g., `"Asia Low  09:15"` or `"Prior Day Low"`) in
  `_DB_GREEN()`. Indicator = GREEN.
- `2` (carried from prior session): `gateDetail` (e.g., `"↩ London  02:41"`) in
  `_DB_ACCENT()`. Indicator = ACCENT (state 2 color per Section 4).
- `-2` (blocked — gate enabled, trigger ready but gate not satisfied): `"Blocking entry!"` in
  `_DB_RED()`. Indicator = RED (state -2 color).

**Carryover display rule:** when `gateMode == 2` (daily gate) and `gateState == 2`
(carried), the detail string supplied by the EA will always be in the form
`"↩ London HH:MM"` or `"↩ Prior Session HH:MM"` — the dashboard renders this exactly
as supplied, in `_DB_ACCENT()`.

This row is the ONLY row that uses state value `2` or `-2`. All other rows use only
`0`, `1`, and `-1`.

**Row H — CISD (Y=216 if no gate shown, else Y=236)**

The Y position of all remaining checklist rows shifts down by 20 when Row G is visible.
Use a computed `g_clY` base offset inside `UpdateDashboard()` for all rows H onward.

| Object | Key | Content |
|---|---|---|
| `DTRD_CL_CISD_IND` | Indicator | `cisdState` (0/1) |
| `DTRD_CL_CISD_LBL` | Left label | `"CISD"` |
| `DTRD_CL_CISD_VAL` | Right value | `"Confirmed  " + cisdDetail` in GREEN when done, else `"Awaiting…"` in MUTED |

**Row I — Entry Trigger (g_clY + 20)**

| Object | Key | Content |
|---|---|---|
| `DTRD_CL_TRG_IND` | Indicator | 0=MUTED, 1=ACCENT (limit set, not filled), 2=GREEN (fired/in trade) |
| `DTRD_CL_TRG_LBL` | Left label | `"Entry · " + entryModel` (e.g., `"Entry · IFVG"`) |
| `DTRD_CL_TRG_VAL` | Right value | `triggerDetail` colored per state: MUTED(0), ACCENT(1), GREEN(2) |

`triggerDetail` examples the EA supplies:
- State 0: `""` (empty — dashboard shows `"Awaiting…"`)
- State 1: `"Limit @ 2019.25"` (FVG retest limit set, waiting for fill)
- State 2: `"IFVG @ 2019.40"` or `"Filled 09:38"` (trade is live)

### 5.8 Section divider (dynamic Y — only shown when `inTrade == true`)

`DTRD_DIV4` — same style. Positioned at `g_clY + 40 + 20`.

### 5.9 Trade Block (dynamic Y — only shown when `inTrade == true`)

All four rows begin at `g_tradeY = g_clY + 40 + 22`. No indicator dots in the trade block.

**Row J — Direction + Entry Model (g_tradeY)**

| Object | Content | Color |
|---|---|---|
| `DTRD_TR_DIR` | `"SHORT"` or `"LONG"` | RED for SHORT, GREEN for LONG, bold |
| `DTRD_TR_MODEL` | `"· " + entryModel + " · " + slMode + " SL"` (e.g., `"· IFVG · Dynamic SL"`) | `_DB_MUTED()` |

**Row K — Prices (g_tradeY + 20)**

| Object | Content | Font |
|---|---|---|
| `DTRD_TR_PX` | `"E: 2019.40  SL: 2024.80  TP: 2012.60"` | Consolas, size 7, `_DB_MUTED()` |

If any price is 0 (not yet filled, though this shouldn't occur when `inTrade==true`),
render `"--"` for that value.

**Row L — Live RR (g_tradeY + 40)**

| Object | Content | Color logic |
|---|---|---|
| `DTRD_TR_RR` | `"Live RR: 1.8R"` | AMBER if `liveRR < 1.0`, GREEN if `liveRR >= MinRR`, TEXT otherwise |

`liveRR` is computed by the EA (distance from current price to TP ÷ initial risk distance)
and passed in. When `liveRR <= 0` (price has moved against trade), display `"Live RR: —"` in
`_DB_RED()`.

**Row M — Break-Even Status (g_tradeY + 60)**

| Object | Content | Color logic |
|---|---|---|
| `DTRD_TR_BE` | See below | |

Content per `beState`:
- `0` (pending): `"BE pending  " + beDetail` in `_DB_MUTED()`.
  Example: `"BE pending  Threshold @ 2018.10 (30%)"`.
- `1` (activated): `"BE activated  " + beDetail` in `_DB_GREEN()`.
  Example: `"BE activated  SL → 2019.40 (5% locked)"`.

### 5.10 Side State footer (always shown, at bottom of visible content)

**Row N — Side Consumed (g_bottom - 22)**

`g_bottom` is the computed bottom of all visible content above, plus 4px padding.

| Object | Content | Color logic |
|---|---|---|
| `DTRD_SIDE_IND` | Indicator | 1=RED (consumed), 0=GREEN (available) |
| `DTRD_SIDE_LBL` | `"Side"` | `_DB_TEXT()` |
| `DTRD_SIDE_VAL` | See below | |

Content per `sideConsumed`:
- `false`: `"Available"` in `_DB_GREEN()`
- `true` + `consumedResult == "Won"`: `"Consumed  Won ✓"` in `_DB_GREEN()`
- `true` + `consumedResult == "Lost"`: `"Consumed  Lost"` in `_DB_RED()`
- `true` + `consumedResult == "BE"`: `"Consumed  Break-Even"` in `_DB_MUTED()`

---

## 6. Dynamic panel height

`DB_FULL_H` is not a compile-time constant for DTR — compute it fresh each time
`DB_Layout()` is called, based on which optional blocks are visible:

```
baseH   = 158       // header(36) + phase(24) + div(1) + bias3rows(68) + div(1) + range(22) + div(1) + clHdr(16) + padding
clRows  = 4                        // E, H, I, N always present (4 mandatory checklist rows)
if(gateMode > 0)    clRows += 1   // Row G
tradeH  = inTrade ? (22 + 4 + 80) : 0  // divider + 4 trade rows
DB_FULL_H = baseH + (clRows * 20) + tradeH + 20   // 20px bottom padding
```

Call `DB_Layout()` whenever the visible block composition changes (gate mode enabled/
disabled, trade opened/closed) so shadow plates resize correctly.

---

## 7. Checklist state machine — reset rules

The EA (not the dashboard) is responsible for resetting `DTRDashState` fields. The
dashboard only renders what it receives. However, the spec for WHEN the EA must reset
these fields is stated here for clarity:

- On entry to `"Range Forming"` phase (at the session's range window start time), the EA
  resets: `sweepState=0`, `sweepDetail=""`, `gateState=0`, `gateDetail=""`,
  `cisdState=0`, `cisdDetail=""`, `triggerState=0`, `triggerDetail=""`, `inTrade=false`,
  `sideConsumed=false`.
- **The gate's `gateState` is NOT reset at phase transition if `gateMode==2` (daily gate)
  AND the previous London session already set `gateState=1` or `gateState=2` for the same
  True Day.** In that case, `gateState=2` (carried) is passed in for NY's checklist row,
  and `gateDetail` is set to `"↩ London HH:MM"` with the time the London sweep occurred.
  The dashboard will render the ACCENT-colored carried indicator, making the carryover
  visually explicit.
- For `gateMode==1` (session confluence gate), `gateState` IS reset between London and NY,
  because each session must independently satisfy its own per-session reference list.

---

## 8. Dirty-signature string

The signature string (used to skip redundant redraws) must include every field of
`DTRDashState` that maps to any visible object, plus `g_dbX`, `g_dbY`, `g_dbCollapsed`,
and the current NY clock string. Build it with `StringConcatenate()` or repeated `+`
with `"|"` separators, same pattern as ORB. Only call `ChartRedraw(0)` when the
signature changes.

---

## 9. UpdateDashboard() signature

```mql5
void UpdateDashboard(const DTRDashState &state);
```

This is the single entry point called by the EA on every relevant `OnTick()` pass.
Internally it:
1. Calls `_DB_CanDraw()` guard — returns immediately if false.
2. Auto-recreates (`InitDashboard()`) if `DTRD_BG` no longer exists (handles param
   changes/template purges).
3. Builds the dirty-signature string. Returns without object writes if unchanged.
4. Updates the NY clock in the header (always updated if visible, even if collapsed).
5. If `g_dbCollapsed`: parks all body objects off-canvas at X=-9000 and returns.
6. Otherwise: writes all visible objects per Sections 5.1–5.10, computing `g_clY` and
   `g_tradeY` dynamically based on `state.gateMode > 0` and `state.inTrade`.
7. Calls `ChartRedraw(0)`.

---

## 10. Object inventory (all names)

For `DB_ShiftTo()` and `ClearDashboard()` to work correctly, the full name list must be
maintained. Full list of all `DTRD_` objects:

```
// Infrastructure
DTRD_SHADOW2, DTRD_SHADOW, DTRD_BG, DTRD_HEADER, DTRD_PILL, DTRD_TITLE,
DTRD_SESSION_HDR, DTRD_CLOCK, DTRD_BTN, DTRD_HAIR, DTRD_HAIR2, DTRD_SHEEN,
DTRD_DIV1, DTRD_DIV2, DTRD_DIV3, DTRD_DIV4,

// Phase
DTRD_PHASE,

// Bias
DTRD_BIAS_IND, DTRD_BIAS_DIR, DTRD_BIAS_TF,
DTRD_CANDLEB_IND, DTRD_CANDLEB_POS,
DTRD_REF_LEVELS,

// Range
DTRD_RANGE_IND, DTRD_RANGE_VAL,

// Checklist
DTRD_CL_HDR,
DTRD_CL_HTF_IND, DTRD_CL_HTF_LBL, DTRD_CL_HTF_VAL,
DTRD_CL_SWP_IND, DTRD_CL_SWP_LBL, DTRD_CL_SWP_VAL,
DTRD_CL_GATE_IND, DTRD_CL_GATE_LBL, DTRD_CL_GATE_VAL,   // only when gateMode > 0
DTRD_CL_CISD_IND, DTRD_CL_CISD_LBL, DTRD_CL_CISD_VAL,
DTRD_CL_TRG_IND,  DTRD_CL_TRG_LBL,  DTRD_CL_TRG_VAL,

// Trade block
DTRD_TR_DIR, DTRD_TR_MODEL,
DTRD_TR_PX,
DTRD_TR_RR,
DTRD_TR_BE,

// Side footer
DTRD_SIDE_IND, DTRD_SIDE_LBL, DTRD_SIDE_VAL
```

`ClearDashboard()` uses `ObjectsDeleteAll(0, "DTRD_")` plus an explicit delete of
`DTRD_BTN` (OBJ_BUTTON is not always caught by prefix sweep on some reinit paths).
