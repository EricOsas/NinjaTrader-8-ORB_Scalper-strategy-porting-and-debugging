# CCT Model Clarifications

Purpose: Capture explicit user clarifications that are not yet stated cleanly enough in the constitution markdown, so future implementation and audits stay aligned.

Precedence:
- Latest explicit user clarification in chat
- This clarification file
- `CCT_CONSTITUTION_v3.md`
- Other build specifications

## Execution Hour Family Vs Structural Model Label

- Selected execution hours decide when `C1` may legally begin.
- Final model label is assigned structurally at trigger time by opposing-sweep count.
- `CCT` = `0` relevant opposing sweeps before trigger.
- `CCT+TS` = `1` relevant opposing sweep before trigger.
- `CCT+TS Ext` = `2+` relevant opposing sweeps before trigger.
- Bar distance between birth and execution does not determine the final model label.
- A no-sweep continuation from an older source may execute only when the later hour is explicitly selected in the plain `CCT` list; TS-only hours still require at least one relevant opposing sweep.

## Immediate Source Ownership

- For a selected execution hour `H`, the immediate source to check first is always `H-1`.
- If `H-1` birthed a valid generation, that generation owns hour `H`.
- Older current-day birth bars do not compete with that immediate source just because TS sweeps happen before trigger.

## Candidate POIs

- Candidate POIs are only current-bias virgin wick levels being traded through on the forming HTF bar.
- Bullish virgin wick levels are wick highs.
- Bearish virgin wick levels are wick lows.
- Opposing-side traded-through virgin wick levels are TS inputs, not candidate POIs.
- Candidate POI action pillars show by default alongside current-bias candidate POIs.
- Same-bias virgin wicks may draw as virgin/candidate POI material.
- Opposing-side virgin wicks must not draw as normal virgin/candidate POI objects during the current bias.
- Opposing-side virgin wicks are represented only through TS hint/level logic when swept by the active setup.
- Candidate APs exist only for current-bias candidate POIs with an authorized future execution window. Opposing-side TS inputs never get candidate APs.
- Candidate POIs and candidate APs use subtle grey-biased colors: visible enough to audit, but clearly provisional and quieter than confirmed POIs/APs.

## TS Levels

- TS sweep counting is structural model information, not a separate execution-family override.
- Count every relevant opposing virgin wick sweep before trigger for model classification.
- Draw only the most recently swept opposing virgin wick level as the visible TS line.
- If price sweeps a newer opposing wick and then a deeper/older opposing wick before trigger, the visible TS line moves to the deeper/older wick, but the earlier sweep still counts.
- If multiple opposing TS levels are swept by the same LTF candle, all valid swept levels count. The visible TS line should represent the deepest swept level for that setup, not whichever source wick happens to be processed last.
- TS, CO, and POI source anchors must be inside the HTF candle that created the source wick. The first LTF candle of the next HTF candle must never be used as that source wick's left anchor.
- TS levels never get action pillars.
- If no trigger happens before bias flips, remove the TS hint entirely and let the new in-bias POI own the level normally.
- Bias-flip termination must be evaluated before any further C2/C3/trigger processing for the old generation on that scan step. An old generation may not convert a pre-flip TS hint into a historical triggered TS after the counter-bias birth is known.
- If a POI has achieved C1 and HTF bias flips before trigger, that active POI is killed by bias flip and its paired TS hint becomes useless immediately.
- Bias flip does not automatically consume untouched deeper siblings forever. Deeper inactive siblings become counter-bias dormant: hidden and non-executable, but still monitored.
- If a counter-bias dormant sibling individually achieves C1 and then C2+C3 while bias remains against the generation, all siblings in that counter-bias dormant set are killed by bias flip invalidation.
- If bias later returns in favor of that generation before dormant invalidation, a deeper sibling may only use fresh TS information from sweeps after the reset point; pre-flip TS sweeps must not be reused.
- TS is independent from CO. A TS display fix must not change CO visibility or CO lifecycle behavior.
- Historical TS lines persist only when their owning generation triggered. Untriggered TS hints must be removed on bias flip.
- Rebuilt scanner passes must not resurrect old untriggered TS hints from pre-flip history. If the latest post-birth bias is counter to an untriggered generation, TS display/counting stays empty; if bias returns in favor, TS counting restarts after the last counter-bias birth.
- A TS source wick is eligible for sweep counting only after the HTF candle that created that wick has closed. The candle creating its own wick is not a TS sweep of that wick.

## POI Tooltips

- Active POI tooltips include the C1 time.
- Triggered and resolved POI tooltips include both C1 time and trigger time.
- Valid POI tooltips do not need C1 or trigger timestamps.

## CO Lifecycle

- CO uses only HTF virgin wick structure.
- CO uses in-bias virgin wick structure only. Bullish generations use bullish virgin wicks; bearish generations use bearish virgin wicks.
- The visible CO line anchors to the exact lower-timeframe wick that belongs to the chosen HTF virgin wick.
- An older same-bias generation freezes its CO at the close of the immediate newer birth bar only.
- A counter-bias flip does not discard CO; it freezes silently in scanner memory at the last qualifying pre-flip extreme.
- If a dormant generation later reactivates, CO resumes from that previously frozen state instead of recomputing from scratch.
- CO is only drawn after trigger and only on chart timeframes below H1.
- CO is drawn only when it is relevant to the triggered execution geometry: strictly between the visual entry and final TP, or when explicit CO TP extension is enabled.
- CO and TS must remain separate scanner/visual concepts: CO is same-bias structural memory; TS is opposing-side liquidity sweep information.
- CO visual left anchor is the source wick's exact LTF anchor. Its live right edge follows the LTF chart one bar ahead until the first post-entry CO touch; once touched, the line locks to that touch candle close.
- CO touch locking is independent of the SL/TP/BE execution object right edge. CO shares the live edge only before touch. If the trade resolves before CO is touched, the CO line is deleted rather than locked to the trade exit edge.
- Close-confirmed LTF event visuals use the event's previous-second edge. If an IFVG inversion, CO touch, or synthetic exit is confirmed by the `10:20` scanner timestamp, the visual right edge is `10:19:59`, not `10:20:59` or `10:21:00`.

## Breakeven Lifecycle

- Only the general BE draws a visible BE line. NY CO BE is silent: it can move the stop and affect outcome state, but it must not draw its own BE line.
- The general BE line appears when the configured profit threshold is met.
- The general BE line price is always the exact BE price. Its left anchor time is the latest LTF candle between visual entry and BE trigger whose wick/body range touched that BE price.
- If no historical LTF candle range contains the BE price because of a rare price gap, the BE line still anchors at the exact BE price; its left anchor time falls back to the time the BE threshold was met.
- A trade stopped out after NY CO BE silently moved the stop resolves as BE/CO, not plain SL. This implementation uses the dedicated `SS_RESOLVED_BE_CO` state.

## Dynamic POI Right Edge

- A newly valid POI line ends at the close of its birth HTF bar; it must not drift to the current LTF edge before activation.
- After a valid C1, only the sibling that actually activated extends to the close of that C1 HTF bar. Deeper inactive siblings remain anchored at the birth HTF close until they independently activate, die, or become dormant.
- If a deeper sibling supersedes before trigger, that deeper sibling inherits the live extension authority.
- After trigger, an unresolved POI may keep extending one HTF bar at a time until resolution or HTF bias flip.
- Triggered-unresolved POIs use an HTF rolling close, not the LTF execution-object edge. The line advances to the current HTF close, then stops at TP/SL/BE resolution or the first counter-bias HTF birth after trigger.
- Dead, dormant, and non-live POIs do not keep following current price.

## Plain CCT With TS Filter Enabled

- If a plain `CCT` execution hour is selected and the plain-TS feature is enabled, the immediate `H-1` source may self-elevate structurally.
- Example: if `3 AM` is selected as plain `CCT`, `2 AM` birthed, and `3 AM` sweeps the `2 AM` low and the `1 AM` low before triggering from the `2 AM` POI, the setup may still become structurally `CCT+TS` or `CCT+TS Ext`.
- That structural elevation does not require a `1 AM` or `12 AM` birth.
- This rule changes only the final structural label. It does not transfer source ownership away from the immediate `H-1` birth.

## Fallback Birth-Source Ladder

- A fallback source is only relevant when the EA wants an older generation to become the owning source for the selected execution hour.
- `H-2` is only eligible as a fallback owner if `H-1` did not birth and the hour is selected for `CCT+TS`.
- `H-3` is only eligible as a fallback owner if no nearer valid source exists and the hour is selected for `CCT+TS Ext`.
- A fallback owner must actually exist as a birthed generation. Swept highs/lows alone do not create fallback ownership.

## Same-Bias Birth Ownership

- A newer confirmed same-bias generation demotes older untouched same-bias generations even when the newer generation's next action hour is not selected.
- The older generation stays dormant/hidden unless it earns live authority through a valid dormant activation or already has execution history.
- The EA must not require the newer generation's next hour to be enabled just to hide the older generation.
- A hidden newer generation with no authorized execution hour can still act as the structural ownership barrier that prevents stale older POIs/APs from reappearing.

## Dormant Takeover Is Separate From Plain TS Self-Elevation

- If price revalidates and activates an older dormant generation outside the immediate `H-1` source, that is no longer plain-CCT self-elevation.
- That is an ownership-transfer event.
- `H-2` dormant takeover requires the execution hour to be selected for `CCT+TS`.
- `H-3+` dormant takeover requires the execution hour to be selected for `CCT+TS Ext`.
- If the selected hour does not authorize that older-source family, the reactivated older POI is invalid for execution and should die by the wrong-model-hour / unauthorized path.

## Dormant Takeover And Generation Supersession

- A newer same-bias birth makes the older generation dormant, but the older generation remains structurally important.
- If a valid selected TS or TS Ext execution bar trades through and gives an older dormant generation C1, generation supersession is immediate.
- The newer/front-running authority is killed at the dormant C1 event. The EA must not wait to see whether the newer generation later triggers.
- If a prior broker trigger already consumed that execution window, the dormant generation is monitored record-only. It may structurally spend itself, but it must not place a broker order.

## C2/C3 Reset By Deeper Or Cross-Generation C1

- If an HTF bar opens after an earlier generation has C1 and can still finish C2/C3, that is allowed.
- If that later bar achieves a fresh C1 on a deeper sibling or on an older dormant same-bias generation, the earlier C2/C3 path is reset/nullified for the superseded authority.
- The later fresh C1 may or may not be executable depending on the selected model hour.

## Turtle Soup Context For Dormant Takeover

- TS sweeps are execution-window structure, not CO memory.
- A newer same-bias birth may freeze the older generation's CO, but it must not freeze TS counting for a later valid dormant takeover.
- When a dormant generation is revalidated during a selected TS or TS Ext hour, opposing virgin-wick sweeps that happened inside that execution window before the dormant C1 still count toward the model classification.
- Example bearish path: if a 7 PM high is swept during the 8 PM execution window before the 6 PM dormant bearish POI is revalidated, the 6 PM takeover path is TS/Ext according to sweep count, not plain CCT.
- If the active execution bar first sweeps one opposing virgin wick and later sweeps deeper/older opposing virgin wicks before trigger, all sweeps count, but only the latest swept level is displayed as the TS hint.

## Broker Authorization

- Normal source-birth ownership and dormant-takeover ownership are different gates.
- A broker trigger is authorized when the active sibling had an authorized C1 and either:
  - the generation owns the execution bar through the normal source/fallback ladder, or
  - the generation reclaimed authority through a valid dormant takeover C1.
- Record-only dormant activations must keep `hadAuthorizedC1=false` so they cannot broker-trigger.

## Model Comment Classes

- Broker comments and tester logs should use `GEN|HH|MODEL`, for example `BE_260106_0800|09|CCT+TS EXT`.
- `CCT` is a normal plain CCT setup where the selected plain CCT hour activates/triggers without needing TS structure and without later-hour extension authority.
- `CCT EXT` is a later-hour plain continuation from an earlier valid, non-dormant generation when the earlier AP hour did not activate/trigger and the later hour is enabled as plain CCT.
- `CCT+STRUCT_TS` is a plain CCT route allowed by the structural TS option: the immediate post-birth path sweeps relevant TS-side liquidity before trigger, but it does not activate an older/deeper dormant generation.
- `CCT+TS` is the selected CCT+TS model route where a TS sweep is required/satisfied, including dormant-takeover paths and carried C1 paths where later sweeps become the model reason.
- `CCT+TS EXT` is the selected extended TS route where the setup completes through the extended TS model path after the earlier intended TS AP window.

## TS Sweep Source Split

- The scanner must distinguish TS sweeps whose wick source is the birth bar or an older HTF candle from sweeps whose wick source is a post-birth HTF candle.
- `CCT+STRUCT_TS` is only valid when the sweep set comes from the birth bar and/or older HTF candles and no older/deeper dormant generation takes over before trigger.
- If a carried C1 path later sweeps a post-birth candle's opposing virgin wick before trigger, that sweep is a classic TS-family reason, not structural TS.
- Example: a 6 AM bullish birth activates at 7 AM; if 8 AM sweeps the 7 AM opposing TS-side wick before trigger, the model label must be `CCT+TS` or `CCT+TS EXT` according to sweep count, not `CCT+STRUCT_TS`.
- Total sweep count still drives TS vs TS Ext, but the visible TS line remains the latest swept level only.

## Resolved Generation Immutability

- Once a generation has a broker execution record or persisted resolved outcome, that generation is consumed by its first execution.
- Rebuilt scanner passes must not allow the same generation key to discover a newer C1/C2/C3 trigger after SL, TP, or BE.
- A later valid opportunity requires a later birth and therefore a new generation key.


## Trigger Consumption And Sibling Death

- Once a generation triggers, it is consumed forever.
- A later hour may not reuse that triggered generation.
- Triggering from any sibling kills all deeper siblings in that same generation immediately.
- C1 activation is inclusive at the POI level. A bullish POI activates on the first eligible LTF close at or below the POI price; a bearish POI activates on the first eligible LTF close at or above the POI price.
- If an unselected hour achieves C1 and that same unauthorized C1 later completes C2+C3, the generation is consumed even if the completion happens during a later selected hour. The EA must kill the generation as structurally spent, not execute it and not allow a deeper sibling to reuse that source.
- The active sibling's C2+C3 trigger check has priority over deeper sibling supersession. If the active sibling triggers, the generation is consumed before any deeper inactive sibling can become active.
- After a sibling achieves an authorized C1, deeper inactive siblings remain eligible to supersede during that same active carry sequence. Deeper supersession is not limited to bars whose HTF hour is independently selected as an execution hour.
- CO-violation recovery may also promote the next deeper inactive sibling during the active carry sequence. The original authorized C1 opens the carry authority; the current bar does not need to be a fresh execution-hour bar.
- A CO wick touch kills the active sibling if that same candle does not validly complete C2+C3. The scanner checks the trigger first; if no trigger is accepted, the CO touch is terminal for that sibling.
- The exact LTF candle that first achieves C1 cannot kill that same sibling by CO violation. CO-death checks begin after the C1 candle.
- CO violation kills only the active sibling that touched CO. Deeper siblings remain available unless they independently activate, supersede, violate CO, expire, or trigger.

## Non-Visual Tester Runtime

- Non-visual tester mode still uses the same scanner truth for births, C1/C2/C3, IFVG selection, and broker order acceptance.
- Broker position management is tick-owned by `CCTUpdatePositionBE()` plus `OnTradeTransaction()`, so an open broker position alone must not force a full historical scanner rebuild on every LTF bar.
- After a non-visual scanner rebuild attempts any fresh broker execution, chart-only refresh work is skipped: TS display refresh, synthetic outcome replay, CO visual refresh, counter-bias display passes, and object pruning are visual responsibilities.
- Non-visual tester rebuilds remain mandatory on HTF boundaries and selected execution/carry bars so birth ownership and trigger eligibility stay chronological.
- Visual tester still rebuilds scanner truth on every processed closed LTF bar, but expensive chart-object reconstruction is throttled to HTF boundaries, fresh C1/C2/C3/trigger events, and a short periodic interval.
- This visual throttling must not gate broker execution checks; it only reduces object drawing, pruning, and redraw overhead.
- A locked CO must not drift to post-C1 structure for the same active sibling. It may be force-relocked only when authority truly moves to a deeper sibling or when a dormant generation is reactivated.
- If a newer same-bias generation makes an older generation dormant, that older generation's dormant CO context is the correction-side extreme from its birth bar through the close of the newer birth bar. On later dormant activation, the CO is rebuilt from that dormant ownership context.
- If counter-bias birth flips the HTF bias before trigger, the active sibling dies; restored deeper siblings are dormant/counter-bias dormant. If bias later returns and one of those deeper siblings activates, the CO is force-relocked for the newly active sibling rather than inheriting the killed sibling's CO.
- A source candle that triggered may still close and create a fresh new generation at HTF close, but that new generation is a new object with new later authority. The already-triggered generation stays unavailable.

## C2+C3 Trigger Framework

- A valid trigger is a C2+C3 event, not merely a CO touch, bar delay, or label repaint.
- C3/IFVG must be scanner state. A visual IFVG or trigger label without scanner-side `c3Time` and `c3FvgIdx` is not sufficient.
- Path A: a valid IFVG inversion already exists, then the current close confirms C2.
- Path B: C2 already exists, then the current close inverts the valid IFVG.
- Same-bar C2 + same-bar C3 is valid. If the close that confirms C2 also inverts a newer FVG, that newer same-close IFVG supersedes older inverted FVGs and becomes the trigger IFVG immediately.
- The closed-bar scanner order is: mark valid IFVG inversions, choose the most recent IFVG winner, update C2 reclaim/lapse, trigger immediately if C1+C2+C3 now coexist, then evaluate deeper sibling supersession only if no trigger occurred.
- IFVG selection follows the most-recent-inversion-wins rule through trigger close.
- Sibling supersession is evaluated only after the currently active sibling fails to trigger on the same scan step.

## FVG, IFVG, And Synthetic Execution Geometry

- Trigger-side FVG scanning is scanner state, not a visual-only convenience.
- FVGs are eligible from CO formation through trigger; because CO is only known at C1, the scanner may backfill from birth but must ignore any FVG whose formation time is before the locked CO time.
- FVG formation may exist before C1, but an inversion at or before the active sibling's C1 is invalid for that sibling forever. The scanner begins watching inversion validity only after C1.
- FVGs are stale only if they remain uninverted for more than 90 minutes after their first candle. Price later trading through an already inverted FVG does not invalidate it.
- The active trigger IFVG is always the most recent inversion. If multiple inversions share the same close time, use the FVG whose C1 extreme is closest to that trigger-side close.
- A newly inverted FVG supersedes older inverted FVGs for trigger geometry. On-chart, only the winning trigger IFVG should be visible; waiting, stale, invalid, and superseded FVGs should be hidden.
- SL Anchor A in Standard mode is the winning FVG's first-candle extreme: first-candle low for bullish setups and first-candle high for bearish setups.
- SL Anchor A in Momentum mode is the structural trigger close, not the next-candle visual entry.
- SL Anchor B is the winning FVG's C2/C3 extreme: min of the second and third FVG-candle lows for bullish setups, max of those highs for bearish setups.
- V-Shape versus Deep Swing is monitored from the winning FVG formation through trigger close. If price exceeds Anchor B during that interval, the branch is Deep Swing; otherwise it remains V-Shape.
- If a newer IFVG wins before trigger, SL branch monitoring restarts from the newer FVG's formation.
- Synthetic execution geometry is spread-aware. For bullish trades, the visual entry is the next LTF open plus the trigger spread; for bearish trades, the visual entry is the next LTF open bid/reference price.
- The execution SL is widened outward by spread when spread SL is enabled: bullish SL below the raw fib SL, bearish SL above the raw fib SL.
- TP is calculated from the spread-adjusted entry and spread-adjusted SL so the locked RR reflects the executable risk distance.
- The fib debug object remains raw-geometry evidence. It uses the scanner's raw fib SL before spread widening, while the execution boxes use the final spread-adjusted SL/TP.
- Structural trigger time remains the closed LTF bar that completed C1+C2+C3. Synthetic execution visuals begin at the next LTF candle open after that trigger close.
- Visual execution entry uses the next LTF open/first tick when available. Until that bar exists, the scanner may temporarily fall back to the trigger close price.
- Execution tooltips should show both the structural trigger close time and the visual/broker-intended entry time.
- Optional fib visualization uses clean custom line objects rather than `OBJ_FIBO`.
- Fib Anchor A/B construction lines must never be drawn. Only the fib extension/stop evidence lines are user-toggleable.
- Fib extension prices live in tooltips; visible price labels are suppressed.
- The winning IFVG is drawn as a thin-border filled background box behind candles. Waiting, stale, invalid, and superseded FVGs remain hidden.
- TS hint/confirmed styling should stay subtle: hint is dim dotted, confirmed is slightly brighter dashed, and neither should share BE-line identity.
- TS sweep count is scoped to the current/trigger HTF candle. Prior-hour sweeps do not accumulate into a later execution hour's model label; e.g. if 5am sweeps 4am's low and 6am later sweeps only 5am's low, the 6am setup has one sweep, not two. A same-hour sweep that occurs before C1 may become visible only after C1 is achieved, but it is still part of that hour's sweep context.
- Broker execution is fresh-trigger only. The EA may place a market order only when the current closed LTF bar is the same bar that structurally triggered; historical rebuilt triggers must never create delayed broker entries.
- Position sizing uses broker-aware `OrderCalcProfit` risk per lot, broker min/max/step normalization, and free-margin fitting.
- Position sizing must floor to the broker volume step without rounding upward. Non-decimal steps such as `0.25` and `0.05` must be normalized with enough volume precision so the final projected loss stays at or below the selected cash risk.
- Broker entry/fill becomes authoritative for the displayed execution entry once MT5 reports the deal. If no broker deal exists, the spread-adjusted synthetic entry remains the visual truth.
- Historical synthetic rebuilds may use the saved entry-bar spread from M1 rates when available. If MT5 history has no stored spread for that old bar and no broker record exists, the EA must not fall back to the current live spread because widened current spreads would mutate old execution boxes and outcomes.
- Persisted broker/synthetic execution records are authoritative only when both the generation key and stored trigger bar time match the scanner's rebuilt trigger. A broker-executed later trigger must never overwrite the geometry or outcome of an earlier trigger from the same generation after execution-hour settings change.
- Non-visual tester mode must suppress chart objects and dashboards entirely. Visual/live mode should run scanner truth on closed bars and throttle full chart redraws to bar changes, while dashboard updates may remain lightweight.
- Tester and live execution-hour authority both use broker/server time converted to New York time. Server timezone is not a user input; the EA derives the server-to-UTC offset automatically from the terminal/tester clock, then applies DST-aware New York conversion for all engine, scanner, session, AP, and execution-hour decisions.
- Display timezone is visual/reporting-only. The selected display preset may change tooltips, tester journal timestamps, dashboard text, and compact trade comments, but it must never alter scanner geometry, object anchors, generation identity, or execution-hour authority.
- Custom display timezone accepts decimal hours so minute offsets are possible: `5.5` means UTC+05:30 and `-9.5` means UTC-09:30. Minute-offset presets such as Mumbai, Kathmandu, and Marquesas exist as examples.
- Generation keys are human-readable NY birth identities: `BU_YYMMDD_HHMM` or `BE_YYMMDD_HHMM`. Example: `BE_260325_0200` means a bearish generation born on March 25, 2026 at 02:00 NY. The old epoch-second style remains parser-compatible for already-open or historical broker comments.
- Broker entry comments stay compact because MT5 truncates them: `CCT|<gen-key>|NMMdd-HHmm` for default NY display, or `CCT|<gen-key>|DMMdd-HHmm` when a non-NY display preset is selected. Detailed entry and exit timestamps belong in tester/live journal lines and tooltips.
- Visual tester must not scan twice for the same closed LTF bar. Scanner plus drawing should happen from the bar-change tick path; timer work is limited to lightweight dashboard refresh.
- Debug lifecycle journals are event-bar gated. Historical scanner replay must not reprint old triggers, rejects, unauthorized consumes, or C1 notices on every visual/live redraw; full generation-state dumps are reserved for HTF boundaries in visual tester.
- Visual tester dashboard timer cadence may be slower than live chart cadence; dashboard smoothness must not be allowed to steal time from scanner execution or broker simulation.

## Broker Execution And BE Management

- Broker orders are immediate market orders: buy uses Ask, sell uses Bid.
- Broker SL is widened from the raw fib SL by the live trigger spread when spread SL is enabled.
- Broker TP is recalculated from the final broker entry and widened SL, not from the pre-spread raw SL.
- NY CO BE is silent visually, but if it moves the broker stop and that stop is later hit, the outcome is `SS_RESOLVED_BE_CO`.
- NY CO BE applies from 07:00 through 18:00 NY. It moves the stop to entry plus/minus the configured percent of initial risk distance, with no spread or commission padding in the BE move itself.
- NY CO BE must obey the configured minimum trade age and minimum profit-progress gates before either synthetic or broker management may move the stop. A first candle after entry that touches CO is not enough by itself if the minimum age/progress has not been reached.
- NY CO BE minimum profit progress is based on maximum favorable excursion since entry, not the current retrace candle/tick at CO. If price reaches the configured progress first and later retraces to CO, the CO touch may still activate the silent BE move.
- General BE may still draw the visible BE line using the exact BE price and its historical left-anchor rule.
- CO memory is refreshed before synthetic resolution and again after persisted broker outcomes so the CO line can lock to its first post-entry touch but remain bounded by actual TP/SL/BE resolution.
- Counter-bias dormant POIs stay hidden even when dormant display is enabled. Only triggered/resolved counter-bias execution history or explicitly enabled killed-state inspection may draw.

## Hour-Relevance Visual Authority

- Action pillars, TS hints, and untriggered TS overlays must respect the currently selected execution-hour families. If a birth cannot map to any authorized action/execution hour under the active CCT/CCT+TS inputs, its AP and TS hint must be removed rather than left as an orphaned visual.
- Parameter changes that remove an execution hour should rebuild visual relevance immediately. A POI may be hidden by scanner eligibility, and its AP/TS companions must not remain visible as stale evidence.

## One Execution Per Window

- One selected execution-hour window cannot produce two independent setups from multiple sources.
- If one valid source triggers, an older fallback source cannot also trigger in that same window unless a fresh HTF close creates a new valid generation after the trigger.

## Previous-Day Late-Asia Scope

- Previous-day dormant carry is restricted to prior-day `22:00` and `23:00` NY births.
- `00:00` NY belongs to the current day and is handled as a current-day birth.
