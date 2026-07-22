<!-- Page 1 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
CCT
MASTER CONSTITUTION
Candle Continuation Theory — Automated Execution Framework
Version 3.0 — Authoritative Internal Reference
This document is the complete and final authority over every logic rule, state transition, timing decision, execution
condition, and visual behaviour in the CCT automated trading system. The logic described here supersedes
every prior document, every coded behaviour, and every verbal instruction whenever conflict exists. This
document contains no code. Any person or system reading it fully should be able to recreate the entire system
without ambiguity.
The system draws on three complementary disciplines: Inner Circle Trader (ICT) for liquidity theory, LTF imbalance
analysis, structural targets, and stop placement methodology; Indication Correction and Continuation (ICC) for the
range breakout and retest-continuation model that frames the overall execution logic; and Candle Range Theory
(CRT) for classifying structural time and price boundaries. CRT defines a candle of any timeframe as a discrete
time-and-price range — its open, high, low, and close are the range boundaries of that specific time segment.
Trading these well-defined ranges across timeframes produces more reliable structural context than relying on
subjective visual pattern recognition. These three disciplines are synthesised into an original rule-based execution
model called CCT.
Candle Continuation Theory — Execution Framework Page 1

<!-- Page 2 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
Table of Contents
PART ONE — FOUNDATIONS
Ch. 1 — Time Model and Sessions
Ch. 2 — The Two Time Frames
Ch. 3 — Virgin Wicks — Dual Structural Role
Ch. 4 — POI Birth, Generations, and Siblings
Ch. 5 — The Correction Origin — Full Lifecycle
PART TWO — THE CCT MODEL FRAMEWORK
Ch. 6 — CCT and CCT+TS — Structural Model Definitions
Ch. 7 — Turtle Soup: Liquidity Sweeps and Market Intent
Ch. 8 — Execution Hours, C1 Authority, and the Kill Rule
Ch. 9 — TS Classification at Runtime and the TS Filter
PART THREE — THE POI STATE MACHINE
Ch. 10 — Complete State Inventory
Ch. 11 — Sibling Activation and Supersession — The Correct Order
Ch. 12 — C1 — Activation
Ch. 13 — C2 — Reclaim
Ch. 14 — C3 — IFVG Inversion and the Most-Recent-Inversion Rule
Ch. 15 — CO Violation — Bar-Close Determination
PART FOUR — SUPERSESSION, DORMANCY, AND DEATH
Ch. 16 — Cross-Generation Supersession and Dormant Shoot-Through
Ch. 17 — Generation Death Conditions
Ch. 18 — Bias Flip, Memory, and Counter-Bias POIs
Ch. 19 — Daily Scope and Previous-Day Dormant Eligibility
PART FIVE — EXECUTION AND TRADE MANAGEMENT
Ch. 20 — Entry Price, Market Orders, and Multi-Trade Authority
Ch. 21 — Stop Loss — Fibonacci Extension and Scenario Detection
Ch. 22 — Take Profit and CO Extension
Ch. 23 — Breakeven Management
Ch. 24 — Risk and Lot Sizing
Ch. 25 — Outcome Truth and Persistence
PART SIX — THE VISUAL SYSTEM
Ch. 26 — Visual Architecture and Object Ownership
Ch. 27 — Object Anchoring, Timeframe Masks, and MT5 Rendering Rules
Ch. 28 — POI Line Drawing — Precise Specifications
Ch. 29 — Action Pillar Drawing — Rules and Conditions
Ch. 30 — FVG and IFVG Box Drawing
Ch. 31 — Execution Object Drawing and Resolved Trade Display
Ch. 32 — Colour Specifications
Ch. 33 — Dashboard Panels
PART SEVEN — SYSTEM ARCHITECTURE AND TESTING
Ch. 34 — File Responsibilities and Single Source of Truth
Ch. 35 — Testing Philosophy and Variable Sensitivity
PART EIGHT — SCANNER AND EXECUTION IMPLEMENTATION LOGIC
Ch. 36 — Scanner Implementation — Step-by-Step Specification
Ch. 37 — Execution Implementation — Step-by-Step Specification
Candle Continuation Theory — Execution Framework Page 2

<!-- Page 3 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART NINE — ABSOLUTE RULES
Ch. 38 — The Thirty-Two Non-Negotiables
Ch. — — Final System Definition
Candle Continuation Theory — Execution Framework Page 3

<!-- Page 4 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART ONE — FOUNDATIONS
Chapter 1 — Time Model and Sessions
1.1 New York Time Is the Only Time
Every time reference in the CCT system is expressed in New York time. Session windows, birth hours, execution
bar authority, and daily reset events all exist in New York time. Broker server times must be converted before any
session or hour logic is applied.
(cid:127) Eastern Standard Time (EST): UTC minus 5. First Sunday November through second Sunday March.
(cid:127) Eastern Daylight Time (EDT): UTC minus 4. Second Sunday March through first Sunday November.
1.2 Daily Reset
New York midnight is the boundary between trading days. All current-day tracking, display transitions, and session
membership reset at this boundary.
1.3 The Three Execution Session Families
(cid:127) London: 02:00–06:00 NY time.
(cid:127) New York AM: 07:00–11:00 NY time.
(cid:127) Asia: 20:00–23:00 NY time.
Chapter 2 — The Two Time Frames
2.1 HTF — Structural Frame
The Higher Time Frame (HTF) is the structural decision frame. Primary model: one-hour chart. Virgin wicks are
identified on the HTF. POIs are born on the HTF. Generations are created on the HTF. Bias is established on the
HTF. Execution bars are HTF bars.
2.2 LTF — Execution Frame
The Lower Time Frame (LTF) is the execution frame. Primary model: one-minute chart. C1 activations, C2
reclaims, FVG formations, IFVG inversions, and trigger confirmations all occur on the LTF.
2.3 Separation of Concerns
The HTF defines structure and authorization. The LTF defines when valid events occur. Neither frame alone is
sufficient for any execution decision.
Chapter 3 — Virgin Wicks — Dual Structural Role
3.1 Definition
A virgin wick is an HTF candle whose extreme — its high for a bullish wick, its low for a bearish wick — has never
been touched, equaled, or exceeded by any later HTF candle wick since formation. The test is strict.
3.2 The Dual Role
Every virgin wick simultaneously serves two structural roles:
(cid:127) Role 1 — POI Birth Source: A bullish virgin wick high becomes a bullish POI when a later HTF candle
body-closes above it. A bearish virgin wick low becomes a bearish POI when a later HTF candle body-closes
Candle Continuation Theory — Execution Framework Page 4

<!-- Page 5 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
below it.
(cid:127) Role 2 — Opposing Liquidity Target: During bullish bias, unswept bearish virgin wick lows beneath price are
liquidity pools the market may raid before completing the intended bullish move. The structural concept —
raiding lows to go higher, sweeping highs to go lower — is central to the Turtle Soup element of this system. ICT
calls this a Judas Swing. Other disciplines call it inducement or a liquidity grab. The name varies; the structural
reality is the same.
3.3 Transfer of Virginity
When a newer wick exceeds older virgin wicks, every older wick it reached or exceeded loses virgin standing and
virginity transfers to the newer wick. Wicks not reached retain their status. One newer wick can strip multiple older
wicks simultaneously.
3.4 Birth Condition — Body Close Only
(cid:127) Bullish POI birth: HTF body close above a bullish virgin wick high.
(cid:127) Bearish POI birth: HTF body close below a bearish virgin wick low.
A wick touch strips the virgin extreme of its virginity but does not create a POI. The body close is the only birth
event.
3.5 Candidate Status
While an HTF candle is actively trading beyond a virgin wick extreme but has not yet closed, the wick is in
candidate status. Candidates are not POIs. No execution logic responds to a candidate.
3.6 Virgin Wick Lifetime After Sweep
If a virgin wick low is swept during an execution sequence but no valid trigger fires and the execution hour closes,
and the next bar is not a selected execution bar that may still use that wick as a TS level, the wick is classified as
stripped and spent. The candle that performed the sweep may itself become a bearish POI birth candidate if bias
later flips. The original stripped wick does not persist as a bearish POI unless the sweeping candle's body also
closed below it.
Chapter 4 — POI Birth, Generations, and Siblings
4.1 Birth Event
POI birth occurs at the close of an HTF candle that body-closes beyond a valid virgin wick extreme. The birth
candle's opening timestamp is the permanent, immutable identity of the resulting generation.
4.2 The Generation
One birth candle creates one generation. One generation creates exactly one execution window for its entire
lifetime. No sibling can independently open a new window.
4.3 Sibling Starting State
All siblings start VALID and equal at birth. There is no hierarchy at birth.
4.4 Sibling Ordering
Siblings are ordered by price. For a bullish generation, the shallowest sibling has the highest price level
(encountered first as price corrects downward). The deepest sibling has the lowest price level. For a bearish
generation, the order is reversed.
4.5 The Action Pillar
The action pillar is the open time of the HTF candle immediately following the birth candle. No trade is valid before
the action pillar. The pillar is a vertical line on the chart drawn at that exact time.
(cid:127) Action pillars are always drawn, even when candidate POI lines are hidden.
Candle Continuation Theory — Execution Framework Page 5

<!-- Page 6 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) Action pillars belonging to POIs that are irrelevant to the selected execution hours (i.e., no authorized
execution bar exists for their generation given the user’s configuration) are not drawn. They would be
structurally meaningless visual noise.
(cid:127) Action pillars belonging to dormant generations are hidden alongside their POIs while the generation is
dormant. They reappear only when the generation is activated through the shoot-through rule.
4.6 Bias
A bullish birth establishes bullish bias. A bearish birth establishes bearish bias. The most recent birth determines
current bias. A bias change kills all active same-direction setups immediately.
Chapter 5 — The Correction Origin — Full Lifecycle
5.1 What the CO Is
The Correction Origin is the structural swing extreme from which price began the corrective move into the POI. In
ICT terms, it is the point of exhaustion — where the opposing side’s orders ran out of fuel and price had to correct.
That level is where residual orders from the prior structural move sit as targets. Reaching the CO means returning
price to where the opposition was overwhelmed.
5.2 Finding and Locking the CO
The scanner tracks the running extreme from the generation’s birth bar open through all LTF bars until the C1
confirmation bar closes:
(cid:127) Bullish setup: CO = highest LTF high reached from birth open to C1 close. The swing high from which price
descended into the POI.
(cid:127) Bearish setup: CO = lowest LTF low reached from birth open to C1 close. The swing low from which price
ascended into the POI.
The CO locks permanently at C1 time. It does not update as price progresses. Each generation locks its own CO
independently.
5.3 Three Functions
(cid:127) Function 1 — Invalidation Threshold: Described fully in Chapter 15.
(cid:127) Function 2 — Trade Target: When CO extension is enabled and the CO price is farther from entry than the
RR-based TP, the TP extends to the CO price.
(cid:127) Function 3 — Live Reference Line: Drawn on chart strictly between the visual entry price and the final TP.
Never drawn if CO equals or exceeds TP.
5.4 CO Visual Lifecycle
(cid:127) CO hit, then TP hit: CO line disappears at the moment TP is hit.
(cid:127) CO hit, then BE exit: CO line persists until all execution objects for the trade clear at midnight or EA removal.
The CO is a record that the structural target was reached even though the trade closed early.
(cid:127) Trade resolves without CO hit: CO line disappears at resolution.
(cid:127) CO never drawn if CO equals TP: The CO and TP lines would overlap. No separate CO line is drawn.
5.5 No Spread on CO
The CO is always the exact structural price. Spread is never applied.
Candle Continuation Theory — Execution Framework Page 6

<!-- Page 7 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART TWO — THE CCT MODEL FRAMEWORK
Chapter 6 — CCT and CCT+TS — Structural Model Definitions
6.1 Classification by Structural Character
The CCT model type is determined at runtime by counting how many relevant opposing virgin wick extremes were
swept before the trigger fires. This is the complete and only classifier for model type. There is no fixed bar-distance
requirement between birth bar and execution bar as a model classifier.
6.2 The Three Classifications
(cid:127) CCT (Plain): The trigger fires without any relevant opposing virgin wick extreme being swept before it. Direct
correction into the POI and confirmation.
(cid:127) CCT + Turtle Soup (CCT+TS): Exactly one relevant opposing virgin wick extreme was swept before the
trigger fired.
(cid:127) CCT + TS Extended (CCT+TS Ext): Two or more relevant opposing virgin wick extremes were swept before
the trigger fired.
6.3 What ‘Relevant’ Means
A relevant opposing wick is a virgin wick extreme on the opposite side of the trade direction within the structural
correction window of the active setup. For a bullish setup: bearish virgin wick lows below price, within the current
session’s structural context. Only genuine untouched virgin extremes qualify.
6.4 Execution Hours Still Control C1 Authorization
The user selects specific NY time hours as authorized execution bars. These selections control when C1 may
legally begin. The model type (CCT/CCT+TS/CCT+TS Ext) is determined dynamically by sweep count. The
execution hours remain the gate.
6.5 Birth Bar Is Any Valid In-Day POI
The POI may be born on any HTF bar from today’s midnight open onward, plus the previous-day dormant eligibility
described in Chapter 19. The single hard constraint: C1 may not occur before the designated execution bar
opens.
Chapter 7 — Turtle Soup: Liquidity Sweeps and Market Intent
7.1 The Structural Rationale
Before a significant directional continuation, price frequently sweeps opposing liquidity. In a bullish context: price
raids below structural lows, triggering sell-side stops and inducing wrong-way participation, before reversing
upward. This is described in Candle Range Theory (CRT) as raiding the low boundary of a prior candle’s range
before continuation, in ICT as a Judas Swing or liquidity grab. The name varies; the structural concept is
consistent.
In CCT, relevant opposing virgin wick extremes are the tracked liquidity levels. When such a level is swept before a
valid trigger fires, that is the TS event.
7.2 CCT+TS in Practice
Exactly one relevant opposing virgin wick extreme swept before trigger. The sweep can happen:
(cid:127) During the execution bar before C2+C3 complete.
Candle Continuation Theory — Execution Framework Page 7

<!-- Page 8 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) During an earlier bar within the active execution window’s correction phase.
(cid:127) When the execution bar goes below the birth candle’s own low (sweeping the birth candle’s wick as the TS
level) before triggering off the same generation’s POI.
7.3 CCT+TS Ext in Practice
Two or more distinct opposing virgin wick extremes swept before trigger. The deepest swept level is used as the
primary TS reference. Count of distinct swept extremes determines CCT+TS vs CCT+TS Ext.
7.4 A Plain CCT Hour Can Still Host a TS Trade
The execution hour label describes timing authorization. The trade model label describes structural character. A
Plain CCT execution hour can produce a CCT+TS or CCT+TS Ext trade if the structural sweep occurs. The TS
Filter (Chapter 9) controls whether this is permitted.
Chapter 8 — Execution Hours, C1 Authority, and the Kill Rule
8.1 The Execution Hour Gate
The user selects specific NY time hours as execution bars. C1 is only valid when an execution bar is open. If
C2+C3 do not complete within the execution bar, the sequence carries over into the next HTF bar. That carry-over
bar may complete C2+C3 but cannot simultaneously trigger a new, independent setup.
8.2 The C1 Kill Rule — Absolute
If a C1 body close is detected on any POI while the current HTF bar is NOT a selected execution bar, the POI is
killed immediately upon C1 detection. Not at bar close. Not at trigger development. At the moment the LTF body
close is confirmed.
(cid:127) Example: 9am is selected, 8am is not. 8am achieves C1 on a 7am-born POI. The POI is killed at the 8am C1
detection moment. 9am opens to find only the remaining unactivated siblings of the 7am generation.
(cid:127) If all siblings were killed by unauthorized C1 events, and no other valid in-bias POIs exist, the execution bar
has nothing to trade.
(cid:127) If 8am was also a selected execution bar, the 8am C1 is authorized. The model classification at 8am depends
on sweep count.
8.3 Carry-Over Rule
C1 achieved in a valid execution bar may carry over into the next HTF bar for C2+C3 completion. Bias must remain
valid throughout. The carry-over bar cannot independently trigger a new setup.
Chapter 9 — TS Classification at Runtime and the TS Filter
9.1 Runtime Classification
At trigger confirmation, the EA counts distinct opposing virgin wick extremes swept from the CO through the trigger
bar close. This count determines model label.
9.2 The TS Filter Parameter
(cid:127) TS Filter ON (default): If a Plain CCT execution hour produces a structural TS event, the trade executes and
is labeled as CCT+TS or CCT+TS Ext.
(cid:127) TS Filter OFF (testing): Only executes at Plain CCT hours if no opposing wick was swept. Any setup with a
sweep is rejected at Plain CCT hours.
9.3 Research Value
Candle Continuation Theory — Execution Framework Page 8

<!-- Page 9 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
This filter is among the highest-value testing dimensions. Isolating pure CCT vs CCT+TS performance reveals the
structural sweep premium.
Candle Continuation Theory — Execution Framework Page 9

<!-- Page 10 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART THREE — THE POI STATE MACHINE
Chapter 10 — Complete State Inventory
Every POI exists in exactly one state at any moment.
CANDIDATE
The current HTF candle is trading beyond a virgin wick extreme but has not yet closed. Not a POI. No execution
logic responds.
VALID
POI has been born. Action pillar opened. No C1 has occurred yet. All siblings start here, equal.
ACTIVE
The shallowest sibling achieved the first valid C1 in an authorized execution bar. That sibling is ACTIVE. All deeper
siblings are INACTIVE. CO is locked.
TRIGGERED
C1, C2, and C3 confirmed in a valid dual-path sequence. Trigger bar closed. Entry price is set (synthetic or broker
— see Chapter 20). This is also the ‘executed’ state. There is no separate executed state.
INACTIVE
A shallower sibling in the same generation achieved C1 first. This deeper sibling is suspended, not dead. It may
become ACTIVE if the shallower sibling dies by CO violation or any non-window-consuming death before
triggering.
DORMANT — IN-BIAS
A newer same-direction generation was born. This generation stepped back. Completely hidden from chart view
until activated by shoot-through.
RESOLVED — TP
Trade closed at take profit.
RESOLVED — SL
Trade closed at stop loss without prior BE move.
RESOLVED — BE
Trade closed at the moved breakeven stop level.
DEAD — BY SUPERSESSION
A deeper sibling (previously INACTIVE) achieved C1 while this sibling was ACTIVE. This previously-active sibling
is permanently dead.
DEAD — WINDOW CONSUMED
A sibling triggered, consuming the generation’s one execution. All remaining inactive siblings are permanently
dead.
DEAD — WINDOW EXPIRED
All authorized execution bars closed without a trigger. All remaining siblings are dead.
DEAD — UNAUTHORIZED C1
Candle Continuation Theory — Execution Framework Page 10

<!-- Page 11 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
C1 occurred during a non-selected execution bar. POI killed immediately at C1 detection.
DEAD — CO VIOLATION
C1 achieved, then a bar touched and closed at or beyond the CO without completing C2+C3 on that same close.
Specific active POI only.
DEAD — BIAS FLIP
Structural HTF bias flip killed this in-progress POI.
Chapter 11 — Sibling Activation and Supersession — The Correct Order
11.1 All Siblings Start Equal
At birth every sibling is VALID. No hierarchy exists.
11.2 Shallowest Activates First
As price corrects toward the generation, it first encounters the shallowest sibling. When that shallowest sibling
achieves a valid C1 body close:
(cid:127) Shallowest sibling fi ACTIVE.
(cid:127) All deeper siblings fi INACTIVE.
11.3 Deeper Activation Kills the Active Shallower
If price continues past the ACTIVE sibling without triggering it and achieves C1 on the next deeper INACTIVE
sibling:
(cid:127) Previously ACTIVE shallower sibling fi DEAD by supersession (permanent).
(cid:127) Newly activating deeper sibling fi ACTIVE.
(cid:127) Remaining even-deeper siblings fi stay INACTIVE.
This cascade repeats: each deeper activation permanently kills the previous active sibling.
11.4 Single-Bar Multi-Level Sweep
If one LTF bar body-closes through multiple sibling levels, the deepest reached is ACTIVE. All shallower ones
crossed in that same bar are dead by supersession.
11.5 Inactive Sibling Recovery
If the ACTIVE sibling dies by CO violation (not by window consumption), the next deeper INACTIVE sibling
becomes the new execution candidate, provided the window is still open. Once the window is consumed by a
trigger, all INACTIVE siblings die.
Chapter 12 — C1 — Activation
12.1 Definition
(cid:127) Bullish POI C1: LTF bar body-closes below the POI level.
(cid:127) Bearish POI C1: LTF bar body-closes above the POI level.
(cid:127) Wick touches are never C1. Intrabar crossings that revert before close are never C1.
12.2 The Execution Bar Gate
C1 is only legal during a selected execution bar. Any qualifying body close during a non-execution HTF bar kills the
POI immediately at C1 detection.
Candle Continuation Theory — Execution Framework Page 11

<!-- Page 12 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
The LTF bars within a selected execution HTF bar are fully monitored. The gate operates at the HTF bar level: if
the HTF bar is a selected execution hour, all LTF activity within it is eligible.
12.3 CO Locks at C1
The moment C1 is confirmed, the running extreme since birth locks permanently as the CO.
Chapter 13 — C2 — Reclaim
13.1 Definition
(cid:127) Bullish C2: LTF body-close above the POI level after C1.
(cid:127) Bearish C2: LTF body-close below the POI level after C1.
13.2 C2 Is Losable
If price body-closes back through the POI in the wrong direction after C2, the reclaim is lost. State returns to
ACTIVE. A new C2 is required. This may cycle multiple times.
Chapter 14 — C3 — IFVG Inversion and the Most-Recent-Inversion Rule
14.1 FVG Definition
(cid:127) Bearish FVG (bullish setup): C3.high strictly below C1.low. Gap spans from C3.high to C1.low. C2 fits
entirely within the gap.
(cid:127) Bullish FVG (bearish setup): C3.low strictly above C1.high. Gap spans from C1.high to C3.low.
14.2 Inversion
(cid:127) Bullish setup: LTF body-close above the FVG’s first candle’s low (C1.low of the FVG). Body close required.
(cid:127) Bearish setup: LTF body-close below the FVG’s first candle’s high (C1.high of the FVG). Body close required.
Wick touches never count.
14.3 The Most-Recent-Inversion Rule
The most recently inverted FVG is always the active trigger FVG. When a newer FVG is inverted, it supersedes
all previously inverted FVGs. The SL geometry always uses the most recently inverted FVG’s cluster at trigger
close.
FVGs are NOT invalidated by subsequent price action. Price trading back through an FVG’s range does not
remove it from candidacy. Only being superseded by a newer inversion removes an FVG from trigger FVG status.
14.4 FVG Eligibility Window
Eligible FVGs may form from the Correction Origin moment through trigger confirmation. This includes FVGs that
formed:
(cid:127) Between CO formation and C1 (pre-C1 phase).
(cid:127) Between C1 and C2 (the correction body).
(cid:127) After C2 but before trigger close. Post-C2 FVGs are eligible and may supersede older inversions right up to the
trigger close.
14.5 90-Minute Staleness
An FVG whose first candle opened more than 90 minutes before the current bar and that has NOT yet been
inverted is stale. A stale FVG cannot become the trigger FVG. An FVG inverted before reaching 90 minutes
remains valid indefinitely.
14.6 Path A and Path B
Candle Continuation Theory — Execution Framework Page 12

<!-- Page 13 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) Path A: FVG inverts first (before C2, while still deep). Then price reclaims for C2. Trigger fires on C2 bar
close.
(cid:127) Path B: Price reclaims for C2 first. Then FVG inverts. Trigger fires on inversion bar close.
Chapter 15 — CO Violation — Bar-Close Determination
15.1 The Precise Rule
CO violation occurs when any LTF bar — whether approached by wick or body — touches the locked Correction
Origin level AND that bar’s close is at or beyond the CO level WITHOUT a valid C2+C3 sequence confirmed on
that same close.
If the same bar that touches the CO closes with C2+C3 fully confirmed: NOT a violation. The trade triggers.
The test is at bar close, never intrabar. But any bar that closes at or beyond the CO without trigger confirmation
kills the POI, whether the CO was approached by wick or body.
15.2 Determination Process at Every LTF Bar Close
(cid:127) Did this bar’s high (bearish) or low (bullish) touch or exceed the CO at any point during the bar?
(cid:127) If yes: did this bar’s close simultaneously confirm a valid trigger (C2+C3)?
(cid:127) If trigger confirmed at close: NOT a violation. Trade executes immediately.
(cid:127) If bar closed at or beyond CO without confirming trigger: POI is dead by CO violation. No recovery.
15.3 Scope of CO Violation Kill
CO violation kills only the specific ACTIVE POI. INACTIVE siblings may become the new execution candidate if the
window is still open.
Candle Continuation Theory — Execution Framework Page 13

<!-- Page 14 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART FOUR — SUPERSESSION, DORMANCY, AND DEATH
Chapter 16 — Cross-Generation Supersession and Dormant Shoot-Through
16.1 Dormancy Assignment
A generation becomes DORMANT when a newer same-direction generation is born. It is completely hidden. POI
lines not drawn. Action pillar hidden. A generation waiting for its execution bar to open is NOT dormant. It is
VALID.
16.2 The Shoot-Through Event
When a valid execution bar is open and price bypasses the frontrunning generation’s POIs and reaches a dormant
generation’s POI, the dormant generation may activate under the authority of the open window.
The frontrunning generation’s sibling supersession cascade resolves before the dormant generation activates:
shallowest to deepest, each activation killing the previous active sibling. The deepest surviving active sibling dies
by generation supersession when the dormant generation’s POI achieves C1.
16.3 Dormant Sibling Activation
Normal sibling rules apply within the newly activated dormant generation: shallowest dormant sibling becomes
ACTIVE, deeper dormant siblings become INACTIVE, all become visible for the first time.
16.4 Model Label for Shoot-Through Trades
Model type is determined by TS sweep count at trigger time, same as any other trigger.
Chapter 17 — Generation Death Conditions
17.1 Window Consumption
A sibling triggers. All remaining INACTIVE siblings in the generation are killed. The generation is permanently
done. One execution per generation, forever.
17.2 Window Expiry
All authorized execution bars for a generation close without a trigger. All remaining siblings die. No subsequent bar
reopens the authority.
17.3 Unauthorized C1 Kill
C1 on a non-execution bar HTF candle kills the POI at C1 detection. Immediate.
17.4 CO Violation Kill
Bar closes at or beyond CO without trigger. Kills only the active POI. Inactive siblings may survive.
17.5 Bias Flip Kill
(cid:127) If the POI is ACTIVE (C1 achieved, price actively trading through it): killed by bias flip.
(cid:127) If POI is in VALID or INACTIVE state and price is not through it: removed from EA live memory silently. Not a
kill event.
(cid:127) A triggered live trade is not affected by bias changes. It continues to be managed.
Chapter 18 — Bias Flip, Memory, and Counter-Bias POIs
Candle Continuation Theory — Execution Framework Page 14

<!-- Page 15 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
18.1 What the EA Monitors
The EA tracks all in-bias POIs born from the current NY midnight open. It does not actively track counter-bias POIs
while they are counter-bias. The system is directional.
18.2 On Bias Flip
(cid:127) All previously in-bias POIs are purged from live tracking. Chart objects for killed or purged POIs are cleared.
(cid:127) The EA scans from midnight open to identify POIs in line with the new bias. Previous-day dormant generations
are also checked.
(cid:127) Triggered and resolved trades remain on chart as full execution objects until midnight regardless of bias
direction.
18.3 Recognizing Out-of-Memory Kill Events
When bias realigns, the EA must check whether any previously in-bias POI was crossed by price during the
counter-bias period:
(cid:127) On bias realignment, scan to determine whether any re-eligible POI had an LTF body close through it while the
EA was not monitoring it.
(cid:127) If yes: that POI is killed. It cannot be reinstated.
(cid:127) Only POIs not crossed during the counter-bias period are eligible for reinstatement.
Chapter 19 — Daily Scope and Previous-Day Dormant Eligibility
19.1 Current-Day Scope
The EA tracks all in-bias POIs born from the current NY midnight open through the current bar close. This is the
primary scope.
19.2 Previous-Day Dormant Eligibility — 00:00 to 03:00 Window Only
The two most recent in-bias valid and dormant generations from the previous session day are eligible for
activation, but only for triggers that occur between 00:00 and 03:00 New York time. This is the pre-London and
early London window. After 03:00 NY, no previous-day generation retains execution eligibility. Only
current-day-born POIs may trigger from 03:00 onward.
These generations must have been in-bias at birth, must not have been crossed by counter-bias price action since
birth, and must not have expired by their own generation window rules.
19.3 What the EA Does Not Track
The EA does not track counter-bias POIs. It knows all virgin wicks based on platform lookback history, but
execution tracking is limited to current-day scope plus the 00:00–03:00 previous-day exception.
Candle Continuation Theory — Execution Framework Page 15

<!-- Page 16 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART FIVE — EXECUTION AND TRADE MANAGEMENT
Chapter 20 — Entry Price, Market Orders, and Multi-Trade Authority
20.1 The Entry Price Philosophy
The system uses market orders exclusively. No pending limit entries. No stop-entry orders. The entry price is
determined as follows:
(cid:127) Synthetic-only mode (no broker execution): The visual entry reference is the closing price of the trigger bar.
This is the price used for all chart geometry, SL calculation, TP calculation, and RR labeling. It is the single
source of entry truth when no broker fill has occurred.
(cid:127) Broker execution enabled: A market order is placed immediately at trigger bar close. The actual broker fill
(live Ask for buys, live Bid for sells) becomes the real entry price. The visual geometry is still built from the
trigger bar close for display purposes, but the broker SL and TP are placed relative to the actual fill using the
locked RR ratio.
(cid:127) Synthetic and broker fill only differ if there is no broker fill at trigger close. In a properly functioning
system with fast execution, the broker fill should occur at or very near the trigger bar close. Any difference
reflects actual market slippage. The broker execution path must be treated as the authoritative truth for all real
trade management.
Chart geometry (entry line, SL box, TP box, RR label) always uses the trigger bar close. Broker SL and TP orders
always use the actual fill. These two references have separate, permanent roles and are never substituted for each
other.
20.2 Multi-Trade Authority
Multiple CCT trades may be simultaneously open on the same symbol if they originate from different generations in
different execution windows. There is no global one-trade-at-a-time restriction.
What is restricted: one trade per generation forever. Once triggered, the generation is done. And the carry-over bar
(hosting C2+C3 after a C1 from the prior bar) cannot simultaneously host a new independent trigger.
20.3 Locked Parameter Set at Trigger Close
(cid:127) Generation identity key
(cid:127) Trigger bar close time and price (visual entry reference)
(cid:127) Anchor A and Anchor B values
(cid:127) V-Shape or Deep Swing scenario (finalized at trigger close; monitored continuously from FVG inversion)
(cid:127) Raw Fibonacci SL price
(cid:127) Correction Origin price
(cid:127) Locked RR ratio
(cid:127) Model label
(cid:127) Session label
Chapter 21 — Stop Loss — Fibonacci Extension and Scenario Detection
21.1 Anchor A
(cid:127) Standard Mode: Anchor A is the gap-start extreme of the trigger FVG’s first candle (C1 of the FVG — not to
be confused with the setup’s C1 activation).
Candle Continuation Theory — Execution Framework Page 16

<!-- Page 17 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
– For a bullish setup (bearish FVG): Anchor A = FVG first candle’s LOW (C1.low of the FVG). This is the lower
boundary of the gap.
– For a bearish setup (bullish FVG): Anchor A = FVG first candle’s HIGH (C1.high of the FVG). This is the upper
boundary of the gap.
(cid:127) Momentum Mode: Anchor A is the closing price of the trigger bar.
21.2 Anchor B
(cid:127) Bullish setup: Anchor B = min(FVG C2 candle low, FVG C3 candle low). The deepest point of the cluster.
(cid:127) Bearish setup: Anchor B = max(FVG C2 candle high, FVG C3 candle high). The highest point of the cluster.
21.3 Extension Configurations
(cid:127) Configuration 1: Shallow = -0.50, Deep = -0.75.
(cid:127) Configuration 2: Shallow = -0.75, Deep = -1.00.
The extension value multiplies |A-B| and the result is placed beyond Anchor B in the direction away from entry.
21.4 Scenario Detection — Continuous from Inversion to Trigger
V-Shape vs Deep Swing monitoring begins at FVG inversion and continues on every tick until the trigger bar
closes. The scenario may change between inversion and trigger:
(cid:127) V-Shape: Price never went beyond Anchor B by even one tick at any point from FVG formation through trigger
close. The FVG cluster is the confirmed swing extreme. Use the deeper extension.
(cid:127) Deep Swing: Price exceeded Anchor B by even one tick at any point from FVG formation through trigger close
— whether before inversion, after inversion, or between inversion and trigger. Any breach at any moment =
Deep Swing. Use the shallower extension.
If the FVG inverted as V-Shape but price subsequently exceeds Anchor B before trigger close, the classification
upgrades to Deep Swing. The final scenario at trigger close is what is locked.
If the active trigger FVG is superseded by a newer inversion before trigger, detection stops entirely for the old FVG.
The new FVG’s Anchor B is used and detection restarts from the new FVG’s formation time.
21.5 Spread Widening
If enabled: raw SL is widened outward by live spread at broker order placement. Buy: SL moves further below. Sell:
further above. Spread never tightens the SL.
Chapter 22 — Take Profit and CO Extension
22.1 RR Floor
Primary TP from locked RR ratio × broker risk distance. Presets: 0.51R, 1.0R, 2.1R (default), 3.1R, 4.1R, 5.1R.
22.2 CO Extension
When enabled and CO is farther from entry than the RR TP, TP extends to CO. If CO is closer, RR floor stands.
CO never overrides the RR minimum downward.
Chapter 23 — Breakeven Management
23.1 Global Progress-Based BE
Applies to all trades when enabled. When the configured trigger percentage of the entry-to-TP distance is reached,
SL moves to entry plus the configured move percentage of TP distance beyond entry.
23.2 NY AM CO-Based BE
Applies only to NY AM triggered trades. Both safeguards must be satisfied simultaneously:
Candle Continuation Theory — Execution Framework Page 17

<!-- Page 18 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) Safeguard 1 — Minimum Elapsed Time: CO touch must occur at least the configured minimum seconds
after position open. Default: 300 seconds. CO touches within 300 seconds of entry are ignored.
(cid:127) Safeguard 2 — Minimum Progress: Current price must be at least the configured minimum percentage of TP
distance beyond entry. Default: 20%.
When both met: SL moves to entry + spread + commission equivalent.
23.3 Layer Priority
CO BE fires first if eligible. Progress BE fires if its threshold is reached but never moves SL to a less favorable
position than CO BE already placed it.
Chapter 24 — Risk and Lot Sizing
24.1 Price Risk Only
Risk percent = price-movement exposure only. Commission is not part of the denominator.
Lot size = Risk Cash / Price-Movement Cash Loss Per Lot. Cash loss per lot uses the broker’s profit calculation at
the exact entry-to-SL distance. No hardcoded pip values.
24.2 Account Base
(cid:127) Balance, Equity, or user-entered Custom amount.
24.3 Normalization
Normalize downward to nearest valid lot step within broker min/max. Always down.
Chapter 25 — Outcome Truth and Persistence
25.1 Trade Identity
Generation key: BU_[timestamp] for bullish, BE_[timestamp] for bearish. Unix seconds of birth candle open time.
Embedded in trade comment.
25.2 Outcome Classification
(cid:127) TP Hit, SL Hit, or BE Exit.
BE exit classification uses the known moved BE stop price, not profit sign.
25.3 Persistence and Restart
Outcomes written to global variables on close via OnTradeTransaction. On restart: read persisted outcomes before
scanning. Fallback: if no outcome and no open position, show as live/triggered, not falsely resolved.
Candle Continuation Theory — Execution Framework Page 18

<!-- Page 19 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART SIX — THE VISUAL SYSTEM
Chapter 26 — Visual Architecture and Object Ownership
26.1 Execution-First Rule
Visual logic must never delay or gate execution logic. A visual failure never blocks a trade from being placed. The
scanner determines truth. The visual layer reflects it.
26.2 Object Ownership
(cid:127) Scanner Visual Layer: POI lines, action pillars, FVG/IFVG boxes, TS markers, day/week separators,
candidate lines, virgin wick lines, scanner labels.
(cid:127) Execution Layer: Entry line, SL line, TP line, CO reference line, BE line, SL zone box, TP zone box, resolved
trade arrows and connectors.
(cid:127) Dashboard Layer: Both panels and all child objects.
26.3 Non-Destructive Drawing
Objects are created once and updated in place. No bulk deletion and recreation. Objects are removed only when
structural rules require end-of-life.
26.4 Resolved Trade Display — Full Objects Until Midnight
Triggered and resolved trades remain visible as full execution objects (entry line, SL zone, TP zone, CO if
applicable, final outcome line) until midnight, anchored to the bar times that produced the execution events. There
is no early compression to arrows. The full geometry persists as historical record regardless of subsequent bias
direction. At midnight, execution objects for closed trades are cleared.
26.5 EA Removal and Symbol Switch
EA removal clears all owned objects immediately. Symbol change clears all prior symbol objects before drawing for
the new symbol. No orphaned objects remain.
Chapter 27 — Object Anchoring, Timeframe Masks, and MT5 Rendering Rules
27.1 The MT5 Rendering Problem
MetaTrader 5 maps chart objects to bar times on the current chart's timeframe. An object anchored to a time that
does not correspond to an exact bar open time on the current TF is silently shifted to the nearest bar. This causes
POI lines, FVG boxes, and execution zones to appear visually displaced when the chart is switched between the
HTF and lower timeframes. The anchoring strategy must address this explicitly.
27.2 Left Anchor — POI Lines and HTF-Origin Objects
For any object whose structural origin is an HTF bar (POI lines, action pillars, day separators), the left anchor must
be set to the HTF bar’s open time as a datetime value. Do not shift it to the nearest LTF bar.
On lower timeframes, MT5 will find the nearest LTF bar at or after that time. This is acceptable for POI lines and
pillars because the HTF open time always corresponds to an exact LTF bar open on any standard timeframe below
the HTF.
27.3 Right Anchor — Live Objects
Candle Continuation Theory — Execution Framework Page 19

<!-- Page 20 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
For any live object that must extend to ‘now’ (POI lines before kill, FVG boxes, execution zone boxes), the right
anchor must be set to:
(cid:127) SERIES_LASTBAR_DATE(LTF) + one LTF period in seconds. This is the furthest valid time on the LTF
chart. It renders correctly on all timeframes at or below the HTF.
(cid:127) Never use a future HTF bar open time as the right anchor. That time may not yet exist on the LTF, causing
the object to appear truncated or invisible on LTF charts.
27.4 Right Anchor — Resolved and Killed Objects
When an object’s structural life ends (kill time, trigger time, resolution time), the right anchor is locked to that
specific bar’s open time. The object no longer extends dynamically. It is frozen at the historical moment of its end.
27.5 FVG and Execution Zone Boxes — Vertical Anchoring
FVG boxes are drawn as RECTANGLE_LABEL objects or equivalent, with price levels as the Y anchors. The left
time is the FVG’s first candle (C1 of the FVG) open time. The right time is dynamic (SERIES_LASTBAR_DATE +
LTF period) until the FVG is superseded or the trade resolves.
27.6 Timeframe Visibility Masks — OBJPROP_TIMEFRAMES
Every object must have its OBJPROP_TIMEFRAMES set explicitly:
(cid:127) Full-content objects (POI lines, action pillars, execution entry line, SL/TP zone boxes): Visible on all
timeframes from M1 through the model HTF (1H for the 1H/M1 model). Use a bitmask:
OBJ_PERIOD_M1|M2|M3|M4|M5|M6|M10|M12|M15|M20|M30|H1.
(cid:127) LTF-only detail objects (FVG boxes, CO line, BE line, tracking SL/TP lines): Visible on M1 through M5 for the
1H/M1 model. These objects are too granular for meaningful display on the HTF itself.
(cid:127) Above-HTF objects (day and week separators only): Visible on H2 through H12. POI and execution detail is
hidden above the HTF.
(cid:127) Dashboard objects: OBJ_ALL_PERIODS. Always visible.
(cid:127) Action pillars: Visible M1 through HTF (same as full-content objects).
27.7 Dual-Object Approach for POI Lines
For precise cross-TF rendering, each POI line may use two overlapping objects:
(cid:127) LTF-only version: Anchored with LTF-precision start time at the exact LTF bar that corresponds to the POI’s
birth. Visible on M1 through M5. This version shows the line with LTF bar-level precision on low TF charts.
(cid:127) Full-range version: Anchored to the HTF birth bar open time. Visible on M6 through H1. This version renders
cleanly on the HTF and intermediate TFs without sub-bar precision noise.
On timeframes where both objects overlap (e.g., M5 for a 1H/M1 model), the LTF version takes visual precedence
since it is at exact bar alignment.
27.8 Z-Order (Back to Front)
(cid:127) FVG/IFVG boxes (furthest back, OBJPROP_BACK=true, behind candles).
(cid:127) SL and TP zone boxes (behind candles, OBJPROP_BACK=true).
(cid:127) POI horizontal lines.
(cid:127) CO reference line, BE line (in front of zone boxes).
(cid:127) SL and TP tracking lines.
(cid:127) Entry line (trigger reference, highest priority execution line).
(cid:127) Action pillars, day separators (vertical lines).
(cid:127) Arrow markers for resolved trades if used (topmost chart layer).
(cid:127) Dashboard panels (absolute highest Z-order).
Candle Continuation Theory — Execution Framework Page 20

<!-- Page 21 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
Chapter 28 — POI Line Drawing — Precise Specifications
28.1 Geometry
Each POI is a horizontal line at the POI’s price level. Left anchor: HTF birth bar open time (or action pillar time for
precision). Right anchor: dynamic until kill or resolution, then locked to the kill/resolution HTF bar open time.
28.2 Visibility by State
(cid:127) VALID, ACTIVE, TRIGGERED: Always shown in current-day window.
(cid:127) DORMANT: Completely hidden. Not drawn at all.
(cid:127) INACTIVE sibling: Hidden while a shallower sibling is ACTIVE.
(cid:127) DEAD (any cause): Shown only when ShowKilled is enabled.
(cid:127) Counter-bias dormant: Always hidden. Never shown.
Object / State Specification
Candidate — Bull C'16,30,60' — dashed, width 1.
Candidate — Bear C'60,30,16' — dashed, width 1.
Virgin Wick — Bull C'74,92,118' — dotted, width 1.
Virgin Wick — Bear C'118,92,74' — dotted, width 1.
Valid — Bull C'28,50,84' — solid, width 1.
Valid — Bear C'84,50,28' — solid, width 1.
Active — Bull C'78,120,132' — solid, width 1.
Active — Bear C'132,108,78' — solid, width 1.
Triggered — Bull C'88,132,114' — solid, width 2.
Triggered — Bear C'142,114,88' — solid, width 2.
Dormant In-Bias Hidden. Never drawn while dormant.
Resolved TP C'86,138,110' — solid, width 1.
Resolved SL C'138,94,94' — solid, width 1.
Resolved BE C'152,132,84' — solid, width 1.
Dead (any cause) C'55,55,55' — dashed, width 1. Hidden unless ShowKilled.
TS Hint (swept, no trigger) C'120,80,20' — dashed, width 1.
Confirmed TS Level C'20,100,100' — dotted, width 1.
Chapter 29 — Action Pillar Drawing — Rules and Conditions
29.1 Geometry
The action pillar is a vertical line at the HTF open time of the bar immediately following the birth candle. It spans
from chart bottom to chart top (price-independent). Left and right anchors are both set to the pillar’s time value. It is
drawn as a vertical OBJ_VLINE or as a zero-width OBJ_TREND between the same time at two extreme prices.
29.2 Drawing Conditions
(cid:127) Draw if the generation has at least one authorized execution bar in the user’s configuration. If no execution bar
exists for this generation under any model, the pillar is useless and is not drawn.
(cid:127) Do NOT draw for dormant generations. Hidden alongside their POIs.
(cid:127) Draw for valid and active generations regardless of whether the execution window has opened yet.
Candle Continuation Theory — Execution Framework Page 21

<!-- Page 22 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) Draw for triggered and resolved generations (as historical markers) within the current-day display window.
Object / State Specification
Confirmed Action Pillar C'88,88,88' — dotted, width 1. Always visible M1–HTF.
Candidate Action Pillar C'88,88,88' — dotted, width 1. Shown while candidate is live.
Chapter 30 — FVG and IFVG Box Drawing
30.1 Geometry
FVG boxes are rectangles with the left time anchor at the FVG’s C1 candle open time, and the right anchor at
SERIES_LASTBAR_DATE(LTF) + one LTF period while live. Top and bottom price anchors are the FVG gap
boundaries (C1.low and C3.high for a bearish FVG; C1.high and C3.low for a bullish FVG). Drawn behind candles
(OBJPROP_BACK=true). Visible on LTF-max TF mask only.
30.2 States
(cid:127) Uninverted: drawn in neutral grey or muted tone.
(cid:127) Inverted (active trigger FVG): drawn in the setup’s direction colour.
(cid:127) Superseded by newer inversion: reverts to neutral or fades.
(cid:127) Stale (>90 min, not inverted): drawn in very dim tone. Not eligible as trigger FVG.
(cid:127) Active trigger FVG is locked at trigger close and remains on chart until midnight.
Object / State Specification
Bearish FVG (bull setup) C'12,45,130' — filled, behind candles, LTF-only.
Bullish FVG (bear setup) C'110,15,25' — filled, behind candles, LTF-only.
Uninverted / neutral C'40,48,60' — faint, behind candles.
Stale (>90 min) C'30,35,42' — very faint.
Chapter 31 — Execution Object Drawing and Resolved Trade Display
31.1 Entry Line
Horizontal line at the trigger bar close price. Left anchor: trigger bar open time. Right anchor: extends dynamically
to SERIES_LASTBAR_DATE(LTF) + LTF period while trade is open; locks to resolution bar open time at
resolution.
31.2 SL and TP Tracking Lines
Horizontal lines at the current broker SL and TP prices. Left anchor: trigger bar open time. Right anchor: same as
entry line. When SL moves (BE), the SL line updates to the new price.
31.3 Zone Boxes
Filled rectangles: entry-to-SL zone (SL box) and entry-to-TP zone (TP box). Left anchor: trigger bar open time.
Right anchor: same as entry line. OBJPROP_BACK=true, drawn behind candles.
31.4 CO Reference Line
Horizontal dotted line at the locked CO price. Drawn only when CO is strictly between visual entry and final TP. Left
anchor: C1 bar open time (the moment CO was locked). Right anchor: dynamic until CO is hit (then locked to CO
touch bar open time) or trade resolves.
31.5 Full Objects Persist Until Midnight
Candle Continuation Theory — Execution Framework Page 22

<!-- Page 23 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
All execution objects (entry, SL, TP, zone boxes, CO line if applicable, BE line if applicable) persist as full objects
until midnight or EA removal. There is no compression to arrows for resolved trades within the current trading day.
The full historical record in object form is the standard display until the daily reset.
Object / State Specification
Entry Line C'214,218,224' — solid, width 2.
SL Tracking Line C'150,88,88' — solid, width 1.
TP Tracking Line C'82,150,114' — solid, width 1.
CO Reference Line C'70,140,210' — dotted, width 1. LTF-only TF mask.
BE Line C'162,138,88' — solid, width 1. Appears after BE move.
SL Zone Box C'55,57,68' — filled, OBJPROP_BACK=true.
TP Zone Box C'22,55,120' — filled, OBJPROP_BACK=true.
Chapter 32 — Colour Specifications
32.1 Dashboard Palette
Object / State Specification
Background C'12,14,22'
Header bar C'18,22,34'
Field background C'20,24,36'
Active field C'26,30,44'
Border C'42,50,72'
Primary text C'210,216,228'
Dim text C'100,110,132'
Accent (active) C'88,148,248'
Positive/Bull C'72,186,112'
Negative/Bear C'206,82,82'
Amber/Warning C'206,170,80'
Teal C'38,196,196'
Chapter 33 — Dashboard Panels
33.1 Signal Panel (DB1)
Shows: directional bias, state, C1/C2/C3 traffic-light (per step, labeled, three-colour), visual entry price, SL, TP,
RR, session, live PnL and progress when trade is open. C-boxes: off=dark red/red; C1 confirmed=dark
green/green; C2/C3 waiting=dark amber/amber; confirmed=dark teal/teal.
33.2 Position Sizer Panel (DB2)
Shows: NY clock, date, session name (colour-coded), symbol and model, editable risk percent, cash risk display,
Balance/Equity/Custom mode buttons, balance, equity, editable custom balance, SL distance in pips, calculated lot
size labeled as estimate or live-open.
33.3 Persistence
Candle Continuation Theory — Execution Framework Page 23

<!-- Page 24 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
Panel position, collapsed state, risk percent, account mode, custom balance survive restart via global variables.
Reset on deliberate EA removal. Fully opaque backgrounds.
Candle Continuation Theory — Execution Framework Page 24

<!-- Page 25 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART SEVEN — SYSTEM ARCHITECTURE AND TESTING
Chapter 34 — File Responsibilities and Single Source of Truth
34.1 File Ownership
CCT_Globals.mqh
Shared enums, structs, inputs, NY time conversion, session logic, math helpers, object name caches, signal
exports. No drawing, scanning, or orders.
CCT_Scanner.mqh
Virgin wick classification, birth list construction, sibling ordering, FVG detection, IFVG winner/recency selection,
CO computation, TS sweep count, generation state machine. No drawing or orders.
CCT_Execution.mqh
Order placement, commission/lot sizing, margin checks, daily loss gate, BE management, outcome detection,
global variable persistence, OnTradeTransaction handler. No drawing or scanning.
CCT_Visual.mqh
All chart object creation, update, deletion. DrawGeneration, FVG boxes, action pillars, separators, execution zone
objects, MT5 anchoring, TF visibility masks, tooltip content. No scanning or orders.
CCT_Dashboard.mqh
Both panels, layout, interactive controls, event handling, persistence. Reads scanner signal exports and execution
outcome records.
CCT_EA_v7.mq5
Orchestration only: OnInit, OnTick, OnTimer, OnChartEvent, OnTradeTransaction, OnDeinit. No business logic.
34.2 Single Source of Truth
(cid:127) Visual entry reference — Execution pending record, locked at trigger close.
(cid:127) Raw SL price — Execution pending record, locked at trigger close.
(cid:127) RR ratio — Execution pending record, locked at trigger close.
(cid:127) Broker SL and TP — Execution state record, derived at fill time.
(cid:127) Trade outcome — Global variables, written by OnTradeTransaction.
(cid:127) CO price — Execution records, locked at C1 time.
(cid:127) Active trigger FVG — Scanner state, most-recently inverted.
(cid:127) Chart object lifecycle — Visual layer via object name cache.
Chapter 35 — Testing Philosophy and Variable Sensitivity
35.1 The EA as a Research Instrument
The CCT EA is a research instrument for understanding the statistical edge of structural execution under varying
configurations. Parameter isolation is as important as logic quality.
35.2 Key Testing Dimensions
Session and Hour Selection
Candle Continuation Theory — Execution Framework Page 25

<!-- Page 26 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
Which execution hours are selected determines the trade sample. London vs NY AM vs combined; single-hour vs
multi-hour; specific session timing.
TS Filter
Allows or blocks TS-structural triggers at Plain CCT hours. Isolates the TS sweep premium in results.
SL Anchor Mode
Standard (FVG first candle extreme) vs Momentum (trigger close) produces different SL distances and RR profiles
for identical setups.
FIB Pair Configuration
Config 1 (0.50/0.75) vs Config 2 (0.75/1.00): directly affects SL tightness and frequency of stop-out.
TP Preset
Scalp presets (0.51R, 1R) vs high-R (3R+) change win-rate vs average-win profile.
CO Extension
Whether CO or fixed R is the TP target tests structural vs mechanical exit quality.
Breakeven Settings
Global trigger/move percentages and CO BE safeguard thresholds change the SL-to-BE conversion rate
significantly.
Day-of-Week Filter
Isolates structural session bias by weekday.
Candle Continuation Theory — Execution Framework Page 26

<!-- Page 27 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART EIGHT — SCANNER AND EXECUTION IMPLEMENTATION LOGIC
Chapter 36 — Scanner Implementation — Step-by-Step Specification
This chapter defines precisely what the scanner must do at each stage of its operation. It is written for direct
implementation guidance.
36.1 HTF Data Load and Virgin Wick Classification
On every draw cycle, load HTF bars from platform lookback. For each HTF bar:
(cid:127) Record the bar’s high and low.
(cid:127) For each prior HTF bar’s high: check whether any later HTF bar’s high reached or exceeded that level. If yes,
the earlier wick is not virgin. If no, it is a bullish virgin wick.
(cid:127) For each prior HTF bar’s low: same check in reverse. If no later bar’s low touched or exceeded it, it is a bearish
virgin wick.
(cid:127) Transfer rule: when a newer wick exceeds multiple prior virgin wicks, strip all exceeded ones and mark the
newer wick as the current virgin holder for those levels.
(cid:127) Store all virgin wick extremes with their bar open time and direction.
(cid:127) Candidate status: if the current (still-open) HTF bar’s body or wick has crossed a virgin extreme but the bar
has not yet closed, mark it as a candidate. Do not convert to POI yet.
36.2 POI Birth Detection
At each HTF bar close (i.e., when a new bar opens, examine the just-closed bar):
(cid:127) For each bullish virgin wick high: if the closing bar’s close (body close) is above that level, a bullish POI is
born. Birth time = closing bar’s open time.
(cid:127) For each bearish virgin wick low: if the closing bar’s close is below that level, a bearish POI is born.
(cid:127) Assign all POIs born from the same closing bar to one generation. Generation ID = closing bar’s open time in
Unix seconds.
(cid:127) Sort siblings from shallowest to deepest by price.
(cid:127) Set all siblings to VALID state.
(cid:127) Compute and store the action pillar time = next HTF bar open time.
(cid:127) Determine which execution hours (if any) this generation is authorized for, given the current user configuration.
If no execution hour maps to this generation, mark it as irrelevant (no action pillar drawn).
36.3 Execution Window Authorization Check
For each generation, before running the state machine, determine whether any selected execution hour maps to
this generation:
(cid:127) For each selected execution hour H: check whether any authorized model (CCT, CCT+TS, CCT+TS Ext) can
use this generation as its birth source given sweep count at trigger. Since model type is now determined at
runtime by sweep count, the birth bar only needs to be a current-day (or eligible previous-day dormant) in-bias
POI.
(cid:127) The effective gate is: C1 may only start when an execution hour bar is open. Track the current HTF bar hour
and compare against the selected execution hours list.
(cid:127) If the current HTF bar hour is not in any execution hour list, any C1 detected during this bar kills the POI
immediately.
36.4 C1 Detection Loop
Candle Continuation Theory — Execution Framework Page 27

<!-- Page 28 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
On every LTF bar close, for each VALID or INACTIVE sibling of each in-bias generation:
(cid:127) Check whether the current HTF bar is a selected execution hour. If not, and if an LTF body close beyond this
sibling’s level occurred: kill the sibling immediately. Mark as DEAD — UNAUTHORIZED C1. Continue to the
next sibling.
(cid:127) If the HTF bar IS a selected execution hour: check whether the LTF bar’s close is beyond the POI level in the
correction direction (below for bullish POI, above for bearish POI).
(cid:127) If yes: identify the shallowest VALID sibling first. Set it to ACTIVE. Set all deeper siblings to INACTIVE. Lock
the CO at the running extreme since birth.
(cid:127) If a currently ACTIVE sibling is being bypassed by price (i.e., a deeper INACTIVE sibling’s level is now crossed
in this same LTF bar): set the previously ACTIVE sibling to DEAD by supersession. Set the newly crossed
deeper sibling to ACTIVE.
(cid:127) If one LTF bar crosses multiple levels: apply the supersession cascade in order from shallowest to deepest.
The deepest reached in that bar becomes ACTIVE.
(cid:127) Update CO: as long as C1 has not yet been confirmed, continue updating the running extreme from birth to the
current LTF bar. At the moment C1 is confirmed (the bar that crosses the POI closes), lock the CO at the current
running extreme.
36.5 CO Computation
The CO is computed on the LTF from the birth candle’s open time:
(cid:127) For a bullish setup: CO = the highest LTF high seen from birth bar open to (and including) the C1 confirmation
bar close.
(cid:127) For a bearish setup: CO = the lowest LTF low seen from birth bar open to C1 confirmation bar close.
(cid:127) Lock at C1 confirmation. Do not update after this point.
(cid:127) Store the locked CO price and the time at which it was locked per generation.
36.6 CO Violation Check
On every LTF bar close where a sibling is ACTIVE (C1 confirmed, waiting for C2+C3):
(cid:127) Check whether this bar’s low (bullish setup) or high (bearish setup) touched or exceeded the locked CO level
at any point during the bar.
(cid:127) If yes: check whether this same bar’s close simultaneously confirms both C2 (price reclaimed the POI level)
and C3 (a valid FVG inversion is confirmed as of this close).
(cid:127) If trigger confirmed on this close: the trade fires. NOT a CO violation.
(cid:127) If this bar’s close is at or beyond the CO level without trigger confirmation: kill the active sibling (DEAD — CO
VIOLATION).
(cid:127) The next deeper INACTIVE sibling (if any) may become the new execution candidate.
36.7 FVG Detection
On every LTF bar close (k ‡ 2), check the three-bar pattern ending at bar k:
(cid:127) For a bullish setup (looking for bearish FVG): if bar[k].high < bar[k-2].low, a bearish FVG exists. Store:
C1_time=bar[k-2].open, C1_low=bar[k-2].low, C3_high=bar[k].high, formed_time=bar[k].time.
(cid:127) For a bearish setup: if bar[k].low > bar[k-2].high, a bullish FVG exists. Store: C1_time=bar[k-2].open,
C1_high=bar[k-2].high, C3_low=bar[k].low.
(cid:127) Only store FVGs that formed after the CO moment. FVGs before the CO are not eligible.
(cid:127) Check 90-minute staleness: if (current_bar_time - C1_time) > 5400 seconds and the FVG has not yet been
inverted, mark it as stale.
36.8 IFVG Inversion Detection
On every LTF bar close, for each uninverted non-stale FVG in the active setup:
Candle Continuation Theory — Execution Framework Page 28

<!-- Page 29 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) For a bearish FVG (bullish setup): if bar[k].close > C1_low of the FVG (body-close above the gap start), the
FVG is inverted. Record inversion_time=bar[k].time.
(cid:127) For a bullish FVG (bearish setup): if bar[k].close < C1_high of the FVG, inverted.
(cid:127) Apply the most-recent-inversion rule: if multiple FVGs are inverted in the same bar, the one with the inversion
closest to the current close price (tightest gap to close) becomes the active trigger FVG. If tied, the most
recently formed FVG wins.
(cid:127) When a new inversion is confirmed, it supersedes the previous active trigger FVG. The previous FVG remains
in the records (for visual display) but is no longer the trigger FVG.
(cid:127) On inversion, begin V-Shape vs Deep Swing monitoring for the newly active FVG.
36.9 V-Shape / Deep Swing Monitoring
From the moment a FVG is inverted until trigger confirmation (or supersession):
(cid:127) Anchor B for the active FVG = min(C2.low, C3.low) for bearish FVG; max(C2.high, C3.high) for bullish FVG.
(cid:127) On every tick (not just bar close) while the FVG is the active trigger FVG: check whether current Ask (for buy)
or Bid (for sell) has exceeded Anchor B by any amount.
(cid:127) If at any point price exceeds Anchor B: classify as Deep Swing. Store this classification.
(cid:127) If price never exceeded Anchor B through trigger close: classify as V-Shape.
(cid:127) If the FVG is superseded by a newer inversion before trigger: stop monitoring the old FVG. Begin monitoring
the new FVG from scratch.
(cid:127) The classification stored at trigger close is what is locked into the execution record.
36.10 C2 Detection
After C1 is confirmed for the ACTIVE sibling:
(cid:127) On each LTF bar close: check whether the bar’s close is back across the POI level in the trade direction
(above POI level for bullish; below for bearish).
(cid:127) If yes: C2 is achieved. Record c2_time.
(cid:127) If price subsequently body-closes back through the POI in the wrong direction: C2 is lost. Reset c2_time = 0.
Require a new C2.
(cid:127) C2 can be lost and reachieved multiple times.
36.11 Trigger Detection
On each LTF bar close, check for trigger conditions:
(cid:127) Path A: If a valid FVG inversion was confirmed before the current bar, and this bar’s close is across the POI
level in the trade direction (C2 confirmed on this close): trigger fires. Record trigger_time=bar close time.
(cid:127) Path B: If C2 was confirmed on a prior bar, and this bar’s close inverts a valid FVG (C3 confirmed on this
close): trigger fires.
(cid:127) Simultaneously at trigger: confirm CO is not violated (bar close must not be at or beyond CO).
(cid:127) Confirm bias is still valid (no counter-bias birth since C1).
(cid:127) Confirm the execution window is still open (current HTF bar is a selected execution hour, or it is a carry-over
bar from a C1 achieved in the prior execution bar).
(cid:127) Lock all trigger parameters: generation key, trigger bar close time and price, Anchor A, Anchor B, scenario
(V-Shape/Deep Swing), raw SL, CO price, locked RR, model label.
36.12 TS Sweep Count at Trigger
At trigger confirmation, count distinct opposing virgin wick extremes swept:
(cid:127) Scan LTF bars from CO formation time to trigger bar close.
(cid:127) For each opposing virgin wick level (bearish lows for bullish setup, bullish highs for bearish setup) within this
window: check whether any LTF bar’s wick reached or exceeded that level.
Candle Continuation Theory — Execution Framework Page 29

<!-- Page 30 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) Count distinct swept extremes. 0 = CCT Plain; 1 = CCT+TS; 2+ = CCT+TS Ext.
(cid:127) Apply TS Filter: if execution hour is configured as Plain CCT only and TS Filter is OFF and sweep count > 0:
reject trigger. POI dies by window expiry.
(cid:127) Store the sweep count and model label in the execution record.
36.13 Dormant Generation Management
When a new same-direction generation is born:
(cid:127) All existing valid in-bias generations that have not yet triggered move to DORMANT state.
(cid:127) Their POI lines, action pillars, and all visual objects are hidden immediately.
(cid:127) They remain in memory as dormant candidates for shoot-through activation.
(cid:127) On each execution bar open: check whether any dormant generation’s shallowest unactivated sibling’s level
has been crossed by current price during the correction of the active setup.
(cid:127) If yes and the execution window is open: activate the dormant generation via shoot-through. Make its objects
visible. Apply sibling supersession cascade in the frontrunning generation.
36.14 Bias Flip Detection
On each HTF bar close:
(cid:127) Determine current bias from the most recent birth.
(cid:127) Check whether the new HTF bar’s close constitutes a valid birth of the opposite direction (body-closed below a
bearish virgin wick low for bearish bias, or above a bullish virgin wick high for bullish bias).
(cid:127) If yes: bias has flipped.
(cid:127) Kill all ACTIVE in-bias POIs (those with C1 achieved).
(cid:127) Silently remove all VALID and INACTIVE in-bias POIs from memory (no kill event).
(cid:127) If any in-bias POI is ACTIVE and was being crossed by price at the flip: assign DEAD — BIAS FLIP state.
(cid:127) Triggered trades in progress are not affected.
(cid:127) Re-scan from midnight open for the new bias direction.
(cid:127) Check previous-day dormant generations for the new bias direction if time is before 03:00 NY.
Chapter 37 — Execution Implementation — Step-by-Step Specification
This chapter defines precisely what the execution subsystem must do.
37.1 On Trigger Detection
(cid:127) Receive the locked trigger package from the scanner: generation key, trigger bar close time, trigger bar close
price (visual entry reference), Anchor A, Anchor B, scenario, raw SL price, CO price, locked RR ratio, model
label, direction.
(cid:127) Place a market order immediately: Buy for bullish, Sell for bearish.
(cid:127) Do not queue. Do not wait. Execute at the next available market price.
(cid:127) Record the actual broker fill price (Ask for buy, Bid for sell).
(cid:127) Compute the final broker SL: raw SL price ± spread if spread application is enabled.
(cid:127) Compute the final broker TP: actual_fill ± (locked_RR × |actual_fill - final_broker_SL|).
(cid:127) Place SL and TP orders at the broker.
(cid:127) Store the execution record: generation key, visual entry reference, actual fill, final broker SL, final broker TP,
CO price, scenario, RR ratio, trade ticket.
(cid:127) If no broker fill (order rejected or market closed): the visual entry reference stands as the synthetic entry. All
geometry is built from trigger bar close. Record the failure and do not leave a dangling pending state.
37.2 While Trade Is Open — Per-Tick Management
Candle Continuation Theory — Execution Framework Page 30

<!-- Page 31 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) On each tick: read current bid and ask. Compute current PnL in cash and as % of TP distance.
(cid:127) Update dashboard with current PnL and progress bar.
(cid:127) Check global progress-based BE: if progress % ‡ configured BE trigger % and BE not yet applied: move SL to
(visual_entry_reference + configured_move_% × |TP - entry|) in the trade direction.
(cid:127) Check NY AM CO-based BE: if current trade was triggered in NY AM hours, CO price is known, and both
safeguards met (minimum elapsed time, minimum progress %): move SL to (actual_fill + spread +
commission_equivalent) in the trade direction.
(cid:127) BE SL moves must only move the SL in the favorable direction (further from the current price toward the trade
direction). Never move SL adversely.
(cid:127) Layer priority: if CO BE fires and moves SL to X, subsequent progress BE must only move SL if its target is
more favorable than X.
(cid:127) On SL or TP hit: update execution record with exit time, exit price, outcome classification.
(cid:127) Write outcome to global variable immediately.
37.3 Outcome Classification
(cid:127) TP Hit: broker TP order triggered. Outcome = RESOLVED_TP.
(cid:127) SL Hit without prior BE move: Outcome = RESOLVED_SL.
(cid:127) SL Hit with prior BE move: check whether exit price matches the known BE stop price within one pip tolerance.
If yes: Outcome = RESOLVED_BE. If no: Outcome = RESOLVED_SL.
(cid:127) Write outcome, exit time, and exit price to global variable keyed by generation key.
37.4 OnTradeTransaction Handler
(cid:127) On every trade event: check if it involves a deal matching a known CCT generation key (by reading trade
comment).
(cid:127) If a closing deal is detected: classify the outcome (TP/SL/BE) and write to global variable.
(cid:127) This handler must be robust: trade comments can be truncated. Use a secondary lookup by ticket number
cross-referenced to the in-memory execution record as fallback.
(cid:127) After writing outcome: signal the visual layer to update execution object colors and states for the affected
generation.
37.5 Lot Size Calculation
(cid:127) Compute risk cash = account_base × risk_percent / 100.
(cid:127) Compute price-movement cash loss per lot: use broker’s OrderCalcProfit at one lot, the current symbol, the
direction, and the distance |visual_entry_reference - raw_SL|.
(cid:127) Lot size = risk_cash / cash_loss_per_lot.
(cid:127) Normalize: lot = floor(lot / lot_step) × lot_step. Clamp to [min_lot, max_lot].
(cid:127) If normalized lot < min_lot: use min_lot (accept slightly elevated risk). Do not skip the trade.
(cid:127) Check margin: use OrderCalcMargin to verify margin availability. If margin is insufficient: reduce lot to
maximum feasible, or skip and log.
(cid:127) Commission is NOT part of the lot size denominator. It is overhead only.
37.6 Restart and History Recovery
(cid:127) On EA initialization: read all global variables keyed by generation key format. Restore execution records from
persisted state.
(cid:127) Scan open positions for CCT comments. Match to generation keys. Restore live execution records for any
open positions found.
(cid:127) Check closed deal history for any generation keys without stored outcomes. Classify outcomes from history as
fallback.
Candle Continuation Theory — Execution Framework Page 31

<!-- Page 32 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
(cid:127) If no persisted outcome and no open/closed history match: default to TRIGGERED state (live pending), not to
resolved. This prevents false resolution before history loads.
(cid:127) Any persisted outcome supersedes history-derived outcome.
37.7 Visual Update Handoff
(cid:127) After every execution event (trigger, SL move, close): export the updated execution state to the visual layer’s
input structures.
(cid:127) The visual layer reads these structures on its next draw cycle and updates all affected objects without requiring
a full redraw pass.
(cid:127) The execution layer never directly creates or modifies chart objects. It writes state. The visual layer reads state
and manages objects.
Candle Continuation Theory — Execution Framework Page 32

<!-- Page 33 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
PART NINE — ABSOLUTE RULES
Chapter 38 — The Thirty-Two Non-Negotiables
No exceptions. No configuration overrides. No legacy behavior supersedes these.
1. C1 is an LTF body close only. Wick touches are never C1.
2. Bullish C1 is a body close below the POI level. Bearish C1 is above.
3. C1 on a non-execution HTF bar kills the POI immediately at C1 detection.
4. All siblings start VALID and equal at birth. No hierarchy at birth.
5. The SHALLOWEST sibling achieves C1 first and becomes ACTIVE. All deeper siblings become
INACTIVE.
6. When a deeper INACTIVE sibling achieves C1, the previously ACTIVE shallower sibling dies by
supersession permanently. The deeper sibling becomes ACTIVE.
7. CO violation: any bar that touches CO by wick or body AND closes at or beyond CO without C2+C3
confirmed on that same close kills the active POI. The test is at bar close only.
8. If the same bar that touches CO closes with C2+C3 confirmed: NOT a violation. Trade triggers.
9. C2 is an LTF body close back through the POI in the trade direction. C2 is losable and re-earnable.
10. C3 is a valid IFVG inversion by LTF body close through the FVG’s first candle extreme.
11. The MOST RECENTLY INVERTED FVG is always the active trigger FVG. FVGs are never invalidated by
subsequent price action, only superseded by newer inversions.
12. FVG eligibility begins at CO formation, not at C1. Pre-C1, post-C2 FVGs are all eligible.
13. V-Shape vs Deep Swing is monitored continuously from FVG inversion through trigger close. Any tick
beyond Anchor B = Deep Swing. Classification can upgrade after inversion.
14. Anchor A (Standard mode): FVG first candle’s LOW for bullish setups, HIGH for bearish setups.
15. CCT model type is determined by opposing virgin wick sweep count at trigger time, not by bar distance
between birth and execution.
16. One generation produces one execution, forever.
17. Dormant POIs are completely hidden until activated via shoot-through.
18. Action pillars are not drawn for dormant generations. They are not drawn for generations irrelevant to the
selected execution hour configuration.
19. Market orders only. No pending entries of any kind.
20. Visual entry reference (trigger bar close) and actual broker fill are permanently separate.
21. Locked RR is preserved at broker TP regardless of fill slippage.
22. Commission is not part of the lot size denominator.
23. A bias flip while a POI is ACTIVE kills it. POIs in VALID/INACTIVE state not being traded through are
removed from memory silently.
24. A triggered trade is not cancelled by subsequent structural changes.
25. The carry-over bar hosting C2+C3 cannot simultaneously trigger a new independent setup.
26. Previous-day dormant generations are only eligible for triggers between 00:00 and 03:00 NY. After 03:00,
only current-day-born POIs may trigger.
27. Resolved and triggered trades remain as full execution objects until midnight, regardless of subsequent
bias direction.
28. No bulk object deletion and recreation on any draw cycle.
Candle Continuation Theory — Execution Framework Page 33

<!-- Page 34 -->
CCT MASTER CONSTITUTION (cid:127) v3.0 Proprietary — Internal Reference
29. EA removal clears all owned objects immediately and completely.
30. Symbol change clears all prior symbol objects before drawing for the new symbol.
31. Non-visual tester mode suppresses all chart object creation and dashboard rendering.
32. This document supersedes every prior document, every prior coded behaviour, and every prior verbal
instruction.
Final System Definition
CCT is a session-authorized, HTF-to-LTF structural execution system in which a born POI becomes tradable only at a
designated execution bar, only after the shallowest sibling achieves a legal C1 body close, followed by a valid C2 reclaim
and confirmation of the most recently inverted IFVG within the CO-to-trigger window, subject to shallowest-first sibling
activation with supersession-by-deeper-activation death, permanent generation death after one execution, CO-violation
determination at bar close only (with the same bar that touches CO saving the trade if it also closes with trigger
confirmed), bias-flip memory management with out-of-memory kill detection on realignment, dormant POI shoot-through
under borrowed window authority, previous-day dormant eligibility limited to the 00:00–03:00 NY window, CCT model
classification by opposing virgin wick sweep count (not bar distance), TS Filter control over whether structural TS events
execute at Plain CCT hours, locked Fibonacci SL with Anchor A at FVG first-candle gap-start extreme, V-Shape vs Deep
Swing monitored continuously from FVG inversion through trigger close, market-order execution with synthetic entry from
trigger close as the sole entry reference when no broker fill differs, full execution objects persisting until midnight, CO
visual lifecycle tied to trade resolution type, action pillars drawn only for relevant and non-dormant generations, precise
MT5 object anchoring with right anchors at SERIES_LASTBAR_DATE+LTF-period for live objects and HTF-bar-open for
left anchors, dual-object POI lines for cross-TF rendering, timeframe visibility masks per object class, non-visual tester full
suppression, and a visual layer that reflects scanner and execution truth without influencing either.
CCT Constitution — Version 3.0 — This document is the system.
Candle Continuation Theory — Execution Framework Page 34
