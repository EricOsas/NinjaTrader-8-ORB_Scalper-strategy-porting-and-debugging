//+------------------------------------------------------------------+
//| CCT_Globals.mqh  v6.0                                            |
//| Enums, structs, inputs, global state, NY utils, object cache.    |
//+------------------------------------------------------------------+
#ifndef CCT_GLOBALS_MQH
#define CCT_GLOBALS_MQH

#define CCT_PI  3.14159265358979
#define PFX     "CCT_"

//--- Enums -----------------------------------------------------------
enum ENUM_CCT_MODEL { MODEL_1H_1M=0, MODEL_4H_5M=1, MODEL_D1_15M=2 };
enum WICK_STATE     { WS_REGULAR, WS_VIRGIN, WS_CAND_ACTIVE, WS_POI };
// SS_DORMANT:     deeper inactive siblings after trigger, same bias — dim, awaiting new window
// SS_DORMANT_CTR: SS_INACTIVE sibs when HTF bias flips — invisible, silently killed if activated
// SS_KILLED_MIN:  activation before minimum trade window bars — killed by session hour filter
enum SIB_STATE      { SS_INACTIVE, SS_ACTIVE, SS_KILLED_CO, SS_KILLED_WINDOW, SS_KILLED_SIB, SS_KILLED_SUPER,
                       SS_TRIGGERED, SS_SL_HIT, SS_TP_HIT, SS_BE_HIT, SS_CO_HIT,
                       SS_DORMANT, SS_DORMANT_CTR, SS_KILLED_MIN, SS_UNKNOWN_OUTCOME };

//--- Enums for Phase 4 ----------------------------------------------
enum ENUM_SCAN_HORIZON_PROFILE { SCAN_PROFILE_LEAN=0, SCAN_PROFILE_STANDARD=1, SCAN_PROFILE_DEEP=2 };
enum ENUM_FIB_MODE  { FIB_MODE_STANDARD=0, FIB_MODE_MOMENTUM=1 };
enum ENUM_FIB_PAIR  { FIB_PAIR_050_075=0, FIB_PAIR_075_100=1 };
enum ENUM_SL_BRANCH { SL_BRANCH_VSHAPE=0, SL_BRANCH_DEEP_SWING=1 };
enum ENUM_TIMEZONE_MODE { Exchange=0, UTC=1 };
enum ENUM_UTC_PRESET
  {
   UtcMinus5NewYork    = 0,
   UtcMinus6Chicago    = 1,
   UtcMinus7Denver     = 2,
   UtcMinus8LosAngeles = 3,
   UtcMinus3SaoPaulo   = 4,
   UtcPlus0London      = 5,
   UtcPlus1Berlin      = 6,
   UtcPlus2Athens      = 7,
   UtcPlus4Dubai       = 8,
   UtcPlus8Singapore   = 9,
   UtcPlus9Tokyo       = 10,
   UtcPlus10Sydney     = 11
  };

//--- TP / Breakeven enums (must appear before input declarations) ---
enum ENUM_BROKER_EXECUTION { BROKER_EXEC_OFF=0, BROKER_EXEC_ON=1 };
enum ENUM_TP_PRESET
  {
   TP_051R = 0,   // 1:0.51R  (scalp exit)
   TP_100R = 1,   // 1:1.0R
   TP_210R = 2,   // 1:2.1R  (CCT standard)
   TP_310R = 3,   // 1:3.1R
   TP_410R = 4,   // 1:4.1R
   TP_510R = 5,   // 1:5.1R  (max)
  };
enum ENUM_BE_TRIGGER { BE_TRIG_50=50, BE_TRIG_75=75, BE_TRIG_90=90 };
enum ENUM_BE_MOVE    { BE_MOVE_5=5,   BE_MOVE_10=10, BE_MOVE_25=25, BE_MOVE_50=50 };
enum ENUM_CCT_LINE_STYLE
  {
   CCT_LINE_SOLID=0,
   CCT_LINE_DASH=1,
   CCT_LINE_DOT=2,
   CCT_LINE_DASHDOT=3,
   CCT_LINE_DASHDOTDOT=4
  };

// HTF bar counts are now derived from the hour-based trade mode fields below.
// See SECTION 3 for the new system.

//=================================================================
// ██████╗ ██████╗ ████████╗    ██╗███╗   ██╗██████╗ ██╗   ██╗████████╗███████╗
//██╔════╝██╔════╝ ╚══██╔══╝    ██║████╗  ██║██╔══██╗██║   ██║╚══██╔══╝██╔════╝
//██║     ██║         ██║       ██║██╔██╗ ██║██████╔╝██║   ██║   ██║   ███████╗
//██║     ██║         ██║       ██║██║╚██╗██║██╔═══╝ ██║   ██║   ██║   ╚════██║
//╚██████╗╚██████╗    ██║       ██║██║ ╚████║██║     ╚██████╔╝   ██║   ███████║
// ╚═════╝ ╚═════╝    ╚═╝       ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝
// CCT EA  v6  —  Parameter Reference
// ─────────────────────────────────────────────────────────────────────────────
//  HOW TO READ THESE PARAMETERS
//  Every parameter group is labelled with the model(s) it affects.
//    [ALL]    — applies to every model (1H, 4H, D1)
//    [1H]     — 1H+M1 model only
//    [4H]     — 4H+M5 model only
//    [D1]     — D1+M15 model only
//
//  EXECUTION WINDOW RULE (critical to understand)
//  Each execution bar is eligible for at most ONE trigger per direction.
//  Once a trigger fires + the trade closes (TP/SL/BE), the entire generation
//  is permanently done — no later bar can reuse it.
//  A subsequent bar (e.g. 10am) can only trade if:
//    (a) A new generation was born at the correct birth bar for that bar's mode
//    (b) The previous bar did NOT already exhaust a generation that would
//        otherwise have served as a CCT+TS birth for this bar
//  Dormant POIs (in-bias) may still activate if the current execution bar's
//  CCT-only birth bar actually produced a generation (supersession rule).
// ─────────────────────────────────────────────────────────────────────────────

input group "━━━━━━━━━━  EXECUTION  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input ENUM_BROKER_EXECUTION Inp_BrokerExecution = BROKER_EXEC_ON; // [ALL] Broker execution: OFF | ON
input bool   Inp_ApplySpread    = true;                  // [ALL] Add live spread to SL & TP

// Simplified live-first build: fixed to the 1H / M1 model.
ENUM_CCT_MODEL Inp_Model = MODEL_1H_1M;
ENUM_SCAN_HORIZON_PROFILE Inp_ScanProfile = SCAN_PROFILE_STANDARD;

input group "━━━━━━━━━━  DEBUG  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input bool Inp_ShowDebug = false;                        // [ALL] Debug log output

input group "━━━━━━━━━━  RESEARCH EXPORT  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input bool Inp_ResearchExport = false;                  // [ALL] Tester-only trade export for research runs
input string Inp_ResearchRunTag = "";                   // [ALL] Research run identifier written into export files

input group "━━━━━━━━━━  RISK  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input double Inp_DefaultRiskPct = 0.75;                 // [ALL] Default risk per trade %
input bool   Inp_DailyLossStop  = false;                // [ALL] Stop after max day loss
input double Inp_DailyLossMaxLosses = 3.0;              // [ALL] Max losses at current risk

input group "━━━━━━━━━━  STOP LOSS  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input ENUM_FIB_MODE Inp_FibMode = FIB_MODE_STANDARD;     // [ALL] Anchor A - C1 gap | trigger close
input ENUM_FIB_PAIR Inp_FibPair = FIB_PAIR_050_075;      // [ALL] Fib pair - V-shape | deep swing

input group "━━━━━━━━━━  BREAKEVEN  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input bool Inp_BE_Enabled = true;                       // [ALL] Global BE: OFF | ON
input ENUM_BE_TRIGGER Inp_BE_Trigger = BE_TRIG_90;     // [ALL] Global BE trigger %
input ENUM_BE_MOVE Inp_BE_Move = BE_MOVE_10;           // [ALL] Global BE move %
input bool Inp_BE_NYAfterCO = true;                    // [ALL] NY BE at CO: OFF | ON
input int    Inp_BE_CO_MinWaitSec     = 300;  // [1H] NY BE at CO: min seconds after trade open before CO touch qualifies
input int    Inp_BE_CO_MinProgressPct = 20;   // [1H] NY BE at CO: min % of TP distance reached before costSL arms (0=off)

input group "━━━━━━━━━━  TAKE PROFIT  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
// TP is expressed as a multiple of R (SL distance from entry).
// If the Correction Origin (CO) is farther than the preset RR-floor target,
// the CO may extend TP outward when Inp_UseCoIfFarther is ON.
// If CO is closer than the preset RR target, that trade keeps the preset RR floor.
// Spread at execution is added outward to both SL and TP automatically.
//
// Presets:  0.51R | 1.0R | 2.1R | 3.1R | 4.1R | 5.1R

input ENUM_TP_PRESET Inp_TPPreset = TP_210R;             // [ALL] TP preset in R
input bool Inp_UseCoIfFarther = false;                   // [ALL] Extend TP only if CO is farther

input group "━━━━━━━━━━  DISPLAY - Animation  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input int Inp_GlowFadeSec = 3;                          // [ALL] Glow fade seconds
input int Inp_GlowPulseSec = 2;                         // [ALL] Candidate pulse seconds

input group "━━━━━━━━━━  TIMEZONE  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input ENUM_TIMEZONE_MODE Inp_Timezone = UTC;             // [ALL] Timezone
input ENUM_UTC_PRESET Inp_UTCPreset = UtcMinus5NewYork; // [ALL] UTC preset - Used when Timezone = UTC

input group "━━━━━━━━━━  SESSION FILTERING  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

input group "━━━━━━━━━━  1H Model - Slots  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
// [1H] Controls which entered slots are tradable and what setup type is required.
// Enter hours as space-separated 24h integers in the selected Timezone. Example: "8 10"
// Leave blank ("") to disable a mode entirely.  "0" = all valid hours for that mode.
//
// How to read two written hours:
//   "8 10" in Plain CCT    = only 8am and 10am may trigger; the required birth bars are 7am and 9am.
//   "8 10" in CCT + TS     = only 8am and 10am may trigger; the required birth bars are 6am and 8am,
//                            while 7am and 9am become the development / TS bars.
//   "8 10" in CCT + TS Ext = only 8am and 10am may trigger; the required birth bars are 5am and 7am,
//                            while the next two HTF bars are the allowed development span.
//
// One execution window per bar per direction.
// If a generation triggered and its trade closed before a later bar,
// that generation is consumed — the later bar needs a NEW birth at its required hour.
//
// Dormant POIs (older in-bias generations) may still activate during a bar IF
// the CCT-only required birth bar for that exec hour actually birthed a generation
// (the supersession rule) — even if the dormant POI would normally need a
// delayed birth distance. Entered slots are mapped back to NY-session logic internally.

input bool Inp_SessionFilter = true;                // [1H] ON = only the listed execution hours are watched and tradable

input string InpCCTOnly = "3 8 9 10";               // [1H] Plain CCT exec hours. Example "8 10" = births must come from 7am and 9am

input string InpCCTTS = "3 9 10";                   // [1H] CCT+TS exec hours. Example "8 10" = births must come from 6am and 8am

input string InpCCTTSExt = "";                      // [1H] CCT+TS Ext exec hours. Example "8 10" = births must come from 5am and 7am

input group "━━━━━━━━━━  DAY-OF-WEEK FILTER - All Models  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
// [ALL] Prevents the EA from drawing or triggering on specific calendar days (NY time).
// Applies on top of any session filter above.  Both conditions must pass.
// Enable Saturday and Sunday only for crypto / 24-hour instruments.

input bool Inp_DayFilter = false;               // [ALL] Master switch: ON = restrict trading to selected days

input bool Inp_Day_Mon = true;    // Monday
input bool Inp_Day_Tue = true;    // Tuesday
input bool Inp_Day_Wed = true;    // Wednesday
input bool Inp_Day_Thu = true;    // Thursday
input bool Inp_Day_Fri = true;    // Friday
input bool Inp_Day_Sat = false;   // Saturday  (enable for crypto)
input bool Inp_Day_Sun = false;   // Sunday    (enable for crypto)

input group "━━━━━━━━━━  DISPLAY - Dashboard  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input bool Inp_ShowDashboard = true;                    // [ALL] Show dashboard

input group "━━━━━━━━━━  DISPLAY - What's Visible  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input bool Inp_ShowCandidates = true;                   // [ALL] Show candidate POIs
input bool Inp_ShowVirgins = false;                     // [ALL] Show virgin wicks
input bool Inp_ShowDormantInBias = false;               // [ALL] Show in-bias dormant
input bool Inp_ShowKilled = false;                      // [1H] Show dead POIs from valid expected birth bars only

input group "━━━━━━━━━━  DISPLAY - Styles - Separators & Pillars  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input color Inp_ClrDaySeparator = clrDimGray;           // [ALL] Day separator color
input ENUM_CCT_LINE_STYLE Inp_StyDaySeparator = CCT_LINE_DASH; // [ALL] Day separator style
input int   Inp_WidDaySeparator = 2;                    // [ALL] Day separator width
input color Inp_ClrWeekSeparator = clrDimGray;          // [ALL] Week separator color
input ENUM_CCT_LINE_STYLE Inp_StyWeekSeparator = CCT_LINE_DASH; // [ALL] Week separator style
input int   Inp_WidWeekSeparator = 1;                   // [ALL] Week separator width
input color Inp_ClrActionPillar = C'88,88,88';         // [ALL] Confirmed AP color
input ENUM_CCT_LINE_STYLE Inp_StyActionPillar = CCT_LINE_DOT; // [ALL] Confirmed AP style
input int   Inp_WidActionPillar = 1;                    // [ALL] Confirmed AP width
input color Inp_ClrCandidatePillar = C'88,88,88';      // [ALL] Candidate AP color
input ENUM_CCT_LINE_STYLE Inp_StyCandidatePillar = CCT_LINE_DOT; // [ALL] Candidate AP style
input int   Inp_WidCandidatePillar = 1;                 // [ALL] Candidate AP width

input group "━━━━━━━━━━  DISPLAY - Styles - Candidate & Virgin  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input color Inp_ClrCandidateBull = C'16,30,60';        // [ALL] Candidate bull base color
input color Inp_ClrCandidateBear = C'60,30,16';        // [ALL] Candidate bear base color
input ENUM_CCT_LINE_STYLE Inp_StyCandidate = CCT_LINE_DASH; // [ALL] Candidate line style
input int   Inp_WidCandidate = 1;                       // [ALL] Candidate line width
input color Inp_ClrVirginBull = C'74,92,118';          // [ALL] Virgin bull color
input color Inp_ClrVirginBear = C'118,92,74';          // [ALL] Virgin bear color
input ENUM_CCT_LINE_STYLE Inp_StyVirgin = CCT_LINE_DOT; // [ALL] Virgin line style
input int   Inp_WidVirgin = 1;                          // [ALL] Virgin line width
input color Inp_ClrCandGlowBullDim = C'18,36,90';      // [ALL] Candidate glow bull dim
input color Inp_ClrCandGlowBullBright = C'70,150,255'; // [ALL] Candidate glow bull bright
input color Inp_ClrCandGlowBearDim = C'90,36,18';      // [ALL] Candidate glow bear dim
input color Inp_ClrCandGlowBearBright = C'255,150,70'; // [ALL] Candidate glow bear bright

input group "━━━━━━━━━━  DISPLAY - Styles - Confirmed POIs  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input color Inp_ClrPOITriggeredBull = C'88,132,114';   // [ALL] Triggered bull POI
input color Inp_ClrPOITriggeredBear = C'142,114,88';   // [ALL] Triggered bear POI
input ENUM_CCT_LINE_STYLE Inp_StyPOITriggered = CCT_LINE_SOLID; // [ALL] Triggered POI style
input int   Inp_WidPOITriggered = 2;                    // [ALL] Triggered POI width
input color Inp_ClrPOIActiveBull = C'78,120,132';      // [ALL] Active bull POI
input color Inp_ClrPOIActiveBear = C'132,108,78';      // [ALL] Active bear POI
input ENUM_CCT_LINE_STYLE Inp_StyPOIActive = CCT_LINE_SOLID; // [ALL] Active POI style
input int   Inp_WidPOIActive = 1;                       // [ALL] Active POI width
input color Inp_ClrPOIInactiveBull = C'28,50,84';      // [ALL] Inactive bull POI
input color Inp_ClrPOIInactiveBear = C'84,50,28';      // [ALL] Inactive bear POI
input ENUM_CCT_LINE_STYLE Inp_StyPOIInactive = CCT_LINE_SOLID; // [ALL] Inactive POI style
input int   Inp_WidPOIInactive = 1;                     // [ALL] Inactive POI width
input color Inp_ClrPOIDormantBull = C'14,32,72';       // [ALL] Dormant bull POI
input color Inp_ClrPOIDormantBear = C'75,32,14';       // [ALL] Dormant bear POI
input ENUM_CCT_LINE_STYLE Inp_StyPOIDormant = CCT_LINE_DASH; // [ALL] Dormant POI style
input int   Inp_WidPOIDormant = 1;                      // [ALL] Dormant POI width
input color Inp_ClrPOITP = C'86,138,110';              // [ALL] TP-hit POI color
input color Inp_ClrPOISL = C'138,94,94';               // [ALL] SL-hit POI color
input color Inp_ClrPOIBE = C'152,132,84';              // [ALL] BE-hit POI color
input ENUM_CCT_LINE_STYLE Inp_StyPOIResolved = CCT_LINE_SOLID; // [ALL] Resolved POI style
input int   Inp_WidPOIResolved = 1;                     // [ALL] Resolved POI width
input color Inp_ClrPOIDead = C'55,55,55';              // [ALL] Dead POI color
input ENUM_CCT_LINE_STYLE Inp_StyPOIDead = CCT_LINE_DASH; // [ALL] Dead POI style
input int   Inp_WidPOIDead = 1;                         // [ALL] Dead POI width

input group "━━━━━━━━━━  DISPLAY - Styles - Execution  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input color Inp_ClrExecTrigger = C'214,218,224';       // [ALL] Execution line color
input ENUM_CCT_LINE_STYLE Inp_StyExecTrigger = CCT_LINE_SOLID; // [ALL] Execution line style
input int   Inp_WidExecTrigger = 2;                     // [ALL] Execution line width
input color Inp_ClrExecSL = C'150,88,88';              // [ALL] Execution SL line color
input ENUM_CCT_LINE_STYLE Inp_StyExecSL = CCT_LINE_SOLID; // [ALL] Execution SL style
input int   Inp_WidExecSL = 1;                          // [ALL] Execution SL width
input color Inp_ClrExecTP = C'82,150,114';             // [ALL] Execution TP line color
input ENUM_CCT_LINE_STYLE Inp_StyExecTP = CCT_LINE_SOLID; // [ALL] Execution TP style
input int   Inp_WidExecTP = 1;                          // [ALL] Execution TP width
input color Inp_ClrExecBE = C'162,138,88';             // [ALL] Execution BE line color
input ENUM_CCT_LINE_STYLE Inp_StyExecBE = CCT_LINE_SOLID; // [ALL] Execution BE style
input int   Inp_WidExecBE = 1;                          // [ALL] Execution BE width
input color Inp_ClrExecCO = C'70,140,210';             // [ALL] Execution CO line color
input ENUM_CCT_LINE_STYLE Inp_StyExecCO = CCT_LINE_DOT; // [ALL] Execution CO style
input int   Inp_WidExecCO = 1;                          // [ALL] Execution CO width
input color Inp_ClrExecSLBox = C'55,57,68';            // [ALL] Execution SL box color
input ENUM_CCT_LINE_STYLE Inp_StyExecSLBox = CCT_LINE_SOLID; // [ALL] Execution SL box style
input int   Inp_WidExecSLBox = 1;                       // [ALL] Execution SL box width
input color Inp_ClrExecTPBox = C'22,55,120';           // [ALL] Execution TP box color
input ENUM_CCT_LINE_STYLE Inp_StyExecTPBox = CCT_LINE_SOLID; // [ALL] Execution TP box style
input int   Inp_WidExecTPBox = 1;                       // [ALL] Execution TP box width

input group "━━━━━━━━━━  DISPLAY - Styles - IFVG & Turtle Soup  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input color Inp_ClrIFVGBull = C'12,45,130';            // [ALL] Bull IFVG box color
input color Inp_ClrIFVGBear = C'110,15,25';            // [ALL] Bear IFVG box color
input ENUM_CCT_LINE_STYLE Inp_StyIFVGBox = CCT_LINE_SOLID; // [ALL] IFVG box style
input int   Inp_WidIFVGBox = 1;                         // [ALL] IFVG box width
input color Inp_ClrTSBull = C'120,80,20';              // [ALL] Turtle Soup bull color
input color Inp_ClrTSBear = C'20,100,100';             // [ALL] Turtle Soup bear color
input ENUM_CCT_LINE_STYLE Inp_StyTSPending = CCT_LINE_DASH; // [ALL] TS pending style
input ENUM_CCT_LINE_STYLE Inp_StyTSTriggered = CCT_LINE_DOT; // [ALL] TS triggered style
input int   Inp_WidTS = 1;                              // [ALL] TS line width
input color Inp_ClrHintBullDim = C'16,34,62';          // [ALL] IFVG hint bull dim
input color Inp_ClrHintBullBright = C'34,72,118';      // [ALL] IFVG hint bull bright
input color Inp_ClrHintBearDim = C'62,26,20';          // [ALL] IFVG hint bear dim
input color Inp_ClrHintBearBright = C'118,48,36';      // [ALL] IFVG hint bear bright

ENUM_LINE_STYLE CCTLineStyle(const ENUM_CCT_LINE_STYLE sty)
  {
   switch(sty)
     {
      case CCT_LINE_DASH:       return STYLE_DASH;
      case CCT_LINE_DOT:        return STYLE_DOT;
      case CCT_LINE_DASHDOT:    return STYLE_DASHDOT;
      case CCT_LINE_DASHDOTDOT: return STYLE_DASHDOTDOT;
      default:                  return STYLE_SOLID;
     }
  }

int CCTLineWidth(const int width)
  {
   if(width<1) return 1;
   if(width>5) return 5;
   return width;
  }

//--- Structs ---------------------------------------------------------
// FVG struct — c2c3Extreme is Fib anchor B, stored at detection time
struct FVGInfo
  {
   datetime t1, t3;          // c1 open / c3 open
   double   c1Ext, c3Ext;    // inversion threshold / far gap edge
   double   c2c3Extreme;     // Fib B: min(c2.low,c3.low) bull | max(c2.hi,c3.hi) bear
   double   clusterExtreme;  // full c1/c2/c3 swing extreme used for V-shape vs deep swing
   bool     inverted;
   datetime invTime;
   bool     stale;           // (invTime - t1) > 5400 sec
   bool     invalidInv;      // inverted before or at active C1 bar
   bool     superseded;      // a newer valid inversion replaced this as C3
   bool     preC1Formed;     // formed before C1 fired — eligible once C1 is active
  };

struct SibInfo
  {
   int       wickIdx;
   datetime  wickTime;
   double    level;
   datetime  ltfAnchor;
   SIB_STATE state;
   datetime  c1Time, c2Time, c3Time;
   // Turtle Soup — populated once C1 is confirmed
   double    tsLevel;           // TS virgin wick price (0 = no TS level found)
   datetime  tsWickTime;        // LTF bar of the TS fractal extreme (left anchor)
   datetime  tsTouchTime;       // first LTF bar whose wick touched tsLevel (right anchor)
   bool      tsTouchedBeforeC1; // true if touch occurred before C1 (no glow needed)
  };

string ActualExecutionModelLabelForSibling(SibInfo &sib,string slotLabel,datetime triggerRef=0)
  {
   string label=(slotLabel!="")?slotLabel:"CCT";
   bool tsPathUsed=(sib.tsLevel>0.0
                    && sib.tsTouchTime>0
                    && sib.c1Time>0
                    && sib.tsTouchTime>=sib.c1Time
                    && (triggerRef<=0 || sib.tsTouchTime<=triggerRef));
   if(tsPathUsed)
     {
      if(label=="CCT+TS Ext")
         return "CCT+TS Ext";
      return "CCT+TS";
     }
   return label;
  }

// FVG hint: handles both pre-inversion grey glow and the grey→bias
// color transition for the 7 seconds following inversion confirmation.
struct HintTarget
  {
   double   c1Ext, c3Ext, gapSize;
   datetime t1;           // c1 open time — left anchor of box
   bool     bull;
   string   nm;
   // Pre-inversion state (grey glow)
   bool     barHadTick;   // current bar had any tick beyond c1 of gap
   datetime lastBarOpen;  // bar open time of last bar check
   bool     wasActive;    // price was in proximity band last tick
   double   fadeT;        // 0..1 fade value for proximity glow
   datetime lastChange;   // time of last wasActive toggle
   // Post-inversion transition state (grey → bias color over 7s)
   bool     hinverted;    // FVG body-close confirmed
   datetime invFadeStart; // server time when inversion was confirmed
   color    biasClrFull;  // target bias color after full transition
  };

// Candidate POI line — multi-state opacity (not a simple fade).
// Opacity states are driven entirely by bar-close and tick events.
// Action pillar visibility follows 25% segment rules, managed per-tick in DrawHints.
struct CandGlowTarget
  {
   double   level;
   bool     bull;
   string   nmHTF, nmLTF;
   // Opacity state machine
   double   opacity;           // current 0.0-1.0 (0=hidden, 0.1=dim, 0.2=partial, 1.0=full)
   bool     barAboveSinceOpen; // any tick above level in the current forming bar
   datetime lastBarOpen;       // open time of bar being tracked (to detect new bar)
   // Action pillar — 25% quarter segment rules
   string   nmPillar;          // action pillar object name
   bool     pillarVisible;     // current pillar show/hide state
   int      lastQuarter;       // last evaluated quarter (0-3) for transition detection
   datetime htfOpen;           // HTF bar open time (for quarter calculation)
   int      pSecHtf;           // HTF period in seconds
  };

// Turtle Soup wick glow — applied after C1, before first wick touch.
// Color-change on the existing TS line object per-tick.
// Mirrors candidate POI opacity logic but with wick-touch as the trigger.
struct TSGlowTarget
  {
   double   tsLevel;          // the TS price level
   bool     bull;             // bull POI (bearish wick low) or bear POI (bullish wick high)
   string   nmLine;           // object name of the TS line to recolor
   bool     barHadTick;       // has the current LTF bar had any tick reaching tsLevel?
   bool     reached100;       // has the 100% state been achieved (first close after touch)?
   datetime lastBarOpen;      // LTF bar open time for detecting new bar
   color    clrBase;          // base color at 100% (dimmed for 10%/20%)
  };

//--- Global state arrays (reset each Draw(), consumed per-tick) ------
HintTarget     g_hints[]; int g_nHints = 0;
CandGlowTarget g_cands[]; int g_nCands = 0;
TSGlowTarget   g_tsGlows[]; int g_nTsGlows = 0;

struct ExecFamilyTrack
  {
   string   genKey;
   bool     bull;
   datetime triggerTime;
   double   coPrice;
   SIB_STATE cachedOutcome;
   bool     outcomeLocked;
   datetime lastMilestoneBarOpen;
   datetime beAnchorTime;
   datetime beTouchTime;
   double   bePrice;
   datetime coTouchTime;
   bool     coFinalized;
  };

ExecFamilyTrack g_execFamilies[];
int             g_nExecFamilies=0;

MqlRates g_ltfWindowCache[];
int      g_ltfWindowCacheN=0;
datetime g_ltfWindowCacheFrom=0;
datetime g_ltfWindowCacheTo=0;
MqlRates g_htfDrawCache[];
int      g_htfDrawCacheN=0;
datetime g_htfDrawCacheLastBar=0;
int      g_htfDrawCacheBars=0;

//--- Chart-change debounce state ------------------------------------
// Set in OnChartEvent, consumed in OnTick after 400ms.
bool g_chartChangePending = false;
uint g_chartChangeTick    = 0;
bool g_needsRedraw        = false;
int  g_currentBias        = 0;

//--- Object cache (anti-flash) ---------------------------------------
// Each Draw() pass registers every object name it creates/updates.
// At end of Draw(), ObjCachePrune() deletes any object from the
// previous pass that was not re-registered this pass.
// DrawHints tick objects are NOT registered here — they manage
// themselves via ObjectFind checks.
string g_objCurr[]; int g_objCurrN = 0;  // names drawn this pass
string g_objPrev[]; int g_objPrevN = 0;  // names drawn last pass

void ObjCacheRegister(const string &nm)
  {
   if(ArraySize(g_objCurr)<=g_objCurrN)
      ArrayResize(g_objCurr,g_objCurrN+1,256);
   g_objCurr[g_objCurrN++] = nm;
  }

bool ObjCacheIsExecutionFamily(const string &nm)
  {
   string execPrefixes[]={"HNT_S_","HNT_T_","HNT_B_","BOX_SL_","BOX_TP_","TRIG_","COTR_"};
   for(int i=0;i<ArraySize(execPrefixes);i++)
      if(StringFind(nm,PFX+execPrefixes[i])==0)
         return true;
   return false;
  }

bool ObjCacheIsCarryForwardFamily(const string &nm)
  {
   string keepPrefixes[]={"CA_","VW_","CAP_","AP_","POI_","TS_","DAY_","WEEK_"};
   for(int i=0;i<ArraySize(keepPrefixes);i++)
      if(StringFind(nm,PFX+keepPrefixes[i])==0)
         return true;
   return false;
  }

void ObjCacheSeedCarryForward()
  {
   for(int i=0;i<g_objPrevN;i++)
     {
      string prevNm=g_objPrev[i];
      if(!ObjCacheIsCarryForwardFamily(prevNm)) continue;
      if(ObjectFind(0,prevNm)<0) continue;
      ObjCacheRegister(prevNm);
     }
  }

int ObjCacheFindSorted(const string &arr[],int n,const string &key)
  {
   int lo=0, hi=n-1;
   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      int cmp=StringCompare(arr[mid],key);
      if(cmp==0) return mid;
      if(cmp<0) lo=mid+1;
      else hi=mid-1;
     }
   return -1;
  }

void ObjCachePrune()
  {
   string sortedCurr[];
   if(g_objCurrN>0)
     {
      ArrayResize(sortedCurr,g_objCurrN);
      for(int i=0;i<g_objCurrN;i++) sortedCurr[i]=g_objCurr[i];
      ArraySort(sortedCurr);
     }
   for(int i=0;i<g_objPrevN;i++)
      if(!ObjCacheIsExecutionFamily(g_objPrev[i])
         && ObjCacheFindSorted(sortedCurr,g_objCurrN,g_objPrev[i])<0)
         ObjectDelete(0,g_objPrev[i]);
   // Swap curr -> prev, reset curr
   ArrayResize(g_objPrev,g_objCurrN);
   for(int i=0;i<g_objCurrN;i++) g_objPrev[i]=g_objCurr[i];
   g_objPrevN=g_objCurrN;
   g_objCurrN=0; ArrayResize(g_objCurr,0);
  }

void ObjCacheFullReset()
  {
   g_objCurrN=0; ArrayResize(g_objCurr,0);
   g_objPrevN=0; ArrayResize(g_objPrev,0);
  }

int FindExecFamilyTrack(const string &genKey)
  {
   for(int i=0;i<g_nExecFamilies;i++)
      if(g_execFamilies[i].genKey==genKey)
         return i;
   return -1;
  }

void RegisterExecFamilyTrack(string genKey,bool bull,datetime triggerTime,double coPrice)
  {
   if(genKey=="") return;
   int idx=FindExecFamilyTrack(genKey);
   if(idx<0)
     {
      ArrayResize(g_execFamilies,g_nExecFamilies+1);
      idx=g_nExecFamilies++;
      g_execFamilies[idx].genKey=genKey;
      g_execFamilies[idx].bull=bull;
      g_execFamilies[idx].triggerTime=triggerTime;
      g_execFamilies[idx].coPrice=coPrice;
      g_execFamilies[idx].cachedOutcome=SS_UNKNOWN_OUTCOME;
      g_execFamilies[idx].outcomeLocked=false;
      g_execFamilies[idx].lastMilestoneBarOpen=0;
      g_execFamilies[idx].beAnchorTime=0;
      g_execFamilies[idx].beTouchTime=0;
      g_execFamilies[idx].bePrice=0.0;
      g_execFamilies[idx].coTouchTime=0;
      g_execFamilies[idx].coFinalized=false;
      return;
     }
   g_execFamilies[idx].bull=bull;
   if(triggerTime>0) g_execFamilies[idx].triggerTime=triggerTime;
   if(coPrice>0.0)   g_execFamilies[idx].coPrice=coPrice;
  }

void UnregisterExecFamilyTrack(string genKey)
  {
   int idx=FindExecFamilyTrack(genKey);
   if(idx<0) return;
   for(int i=idx+1;i<g_nExecFamilies;i++)
      g_execFamilies[i-1]=g_execFamilies[i];
   g_nExecFamilies--;
   ArrayResize(g_execFamilies,g_nExecFamilies);
  }

void ResetExecFamilyTracks()
  {
   g_nExecFamilies=0;
   ArrayResize(g_execFamilies,0);
  }

void ResetLTFWindowCache()
  {
   g_ltfWindowCacheN=0;
   g_ltfWindowCacheFrom=0;
   g_ltfWindowCacheTo=0;
   ArrayResize(g_ltfWindowCache,0);
  }

void ResetHTFDrawCache()
  {
   g_htfDrawCacheN=0;
   g_htfDrawCacheLastBar=0;
   g_htfDrawCacheBars=0;
   ArrayResize(g_htfDrawCache,0);
  }

bool PrepareLTFWindowCache(datetime fromTime,datetime toTime)
  {
   if(fromTime<=0 || toTime<=0 || toTime<fromTime)
      return false;
   if(g_ltfWindowCacheN>0 && g_ltfWindowCacheFrom<=fromTime && g_ltfWindowCacheTo>=toTime)
      return true;
   ArrayResize(g_ltfWindowCache,0);
   g_ltfWindowCacheN=CopyRates(_Symbol,LTF(),fromTime,toTime,g_ltfWindowCache);
   if(g_ltfWindowCacheN<1)
     {
      ResetLTFWindowCache();
      return false;
     }
   g_ltfWindowCacheFrom=g_ltfWindowCache[0].time;
   g_ltfWindowCacheTo=g_ltfWindowCache[g_ltfWindowCacheN-1].time;
   return true;
  }

int CopyLTFWindowFromCache(datetime fromTime,datetime toTime,MqlRates &out[])
  {
   if(g_ltfWindowCacheN<1 || fromTime<=0 || toTime<fromTime)
      return 0;
   if(fromTime<g_ltfWindowCacheFrom || toTime>g_ltfWindowCacheTo)
      return 0;
   int startIdx=-1;
   int endIdx=-1;
   for(int i=0;i<g_ltfWindowCacheN;i++)
     {
      datetime barTime=g_ltfWindowCache[i].time;
      if(startIdx<0 && barTime>=fromTime)
         startIdx=i;
      if(barTime<=toTime)
         endIdx=i;
      if(barTime>toTime)
         break;
     }
   if(startIdx<0 || endIdx<startIdx)
      return 0;
   int count=endIdx-startIdx+1;
   ArrayResize(out,count);
   for(int i=0;i<count;i++)
      out[i]=g_ltfWindowCache[startIdx+i];
   return count;
  }

//--- Timeframe helpers -----------------------------------------------
ENUM_TIMEFRAMES HTF()
  {
   return PERIOD_H1;
  }
ENUM_TIMEFRAMES LTF()
  {
   return PERIOD_M1;
  }

datetime NYMidnightFor(datetime serverTime)
  {
   int nyOff=NYOffsetSec(serverTime);
   datetime nyNow=serverTime+nyOff;
   MqlDateTime dt; TimeToStruct(nyNow,dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt)-nyOff;
  }

datetime NYWeekOpen(datetime serverTime)
  {
   datetime dayOpen=NYMidnightFor(serverTime);
   datetime nyDay=ToNY(dayOpen);
   MqlDateTime dt; TimeToStruct(nyDay,dt);
   int daysFromMonday=(dt.day_of_week==0)?6:(dt.day_of_week-1);
   return dayOpen-(datetime)(daysFromMonday*86400);
  }

datetime MarketReferenceTime()
  {
   datetime ref=0;
   datetime ltfLast=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   datetime htfLast=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
   if(ltfLast>ref) ref=ltfLast;
   if(htfLast>ref) ref=htfLast;
   if(ref<=0) ref=TimeCurrent();
   return ref;
  }

datetime TodayOpenAt(datetime serverTime)
  {
   return NYMidnightFor(serverTime);
  }

datetime RecentFullProcessingStart()
  {
   datetime now=MarketReferenceTime();
   return TodayOpenAt(now);
  }

datetime PriorDaySupportStart()
  {
   datetime now=MarketReferenceTime();
   return (datetime)(TodayOpenAt(now)-86400);
  }

datetime RecentVisualStart()
  {
   return RecentFullProcessingStart();
  }

datetime CoreVisualStart()
  {
   datetime now=MarketReferenceTime();
   return TodayOpenAt(now);
  }

datetime ResolvedPOIVisualStart()
  {
   return CoreVisualStart();
  }

datetime ActionPillarVisualStart()
  {
   datetime now=MarketReferenceTime();
   return TodayOpenAt(now);
  }

datetime ResolvedActionPillarVisualStart()
  {
   return CoreVisualStart();
  }

datetime VirginVisualStart()
  {
   return (datetime)(TodayOpenAt(MarketReferenceTime())-365*86400);
  }

int ActionVisualBars()
  {
   return BarsFromStart(RecentVisualStart(),4);
  }

int VirginVisualBars()
  {
   return BarsFromStart(VirginVisualStart(),4);
  }

bool IsRecentVisualTime(datetime serverTime)
  {
   return (serverTime>0 && serverTime>=RecentVisualStart());
  }

datetime ExecutionVisualStart()
  {
   datetime now=MarketReferenceTime();
   return TodayOpenAt(now);
  }

bool IsRecentExecutionVisualTime(datetime serverTime)
  {
   return (serverTime>0 && serverTime>=ExecutionVisualStart());
  }

int ProfilePrefetchDays()
  {
   return 0;
  }

datetime StructuralPrefetchStart()
  {
   return TodayOpenAt(MarketReferenceTime());
  }

int BarsFromStart(datetime startTime,int padBars)
  {
   int shift=iBarShift(_Symbol,HTF(),startTime,false);
   if(shift<0)
     {
      int totalBars=Bars(_Symbol,HTF());
      if(totalBars>0)
         return totalBars+padBars;
      return MathMax(2,padBars);
     }
   int bars=shift+1+padBars;
   return (bars<2)?2:bars;
  }

int RecentFullProcessingBars()
  {
   int pSecHTF=(int)PeriodSeconds(HTF());
   if(pSecHTF<=0) return 2;
   int padBars=4;
   int fallback=52;
   int bars=BarsFromStart(RecentFullProcessingStart(),padBars);
   return (bars>0)?bars:fallback;
  }

// Individual MT5 period bitmasks
#define TFM_M1   OBJ_PERIOD_M1
#define TFM_M5   OBJ_PERIOD_M5
#define TFM_M15  OBJ_PERIOD_M15
#define TFM_MLOW (OBJ_PERIOD_M1|OBJ_PERIOD_M2|OBJ_PERIOD_M3|OBJ_PERIOD_M4|                   OBJ_PERIOD_M5|OBJ_PERIOD_M6|OBJ_PERIOD_M10|OBJ_PERIOD_M12|                   OBJ_PERIOD_M15|OBJ_PERIOD_M20|OBJ_PERIOD_M30)
#define TFM_H1   OBJ_PERIOD_H1
#define TFM_H4   (OBJ_PERIOD_H2|OBJ_PERIOD_H3|OBJ_PERIOD_H4)
#define TFM_H12  (OBJ_PERIOD_H6|OBJ_PERIOD_H8|OBJ_PERIOD_H12)

// FullContentTFs — TFs where all POI/FVG/arrow/pillar objects are visible.
// Everything up to and including the model HTF.
long FullContentTFs()
  {
   switch(HTF())
     {
      case PERIOD_H1: return TFM_MLOW|TFM_H1;
      case PERIOD_H4: return TFM_MLOW|TFM_H1|TFM_H4;
      case PERIOD_D1: return TFM_MLOW|TFM_H1|TFM_H4|TFM_H12|OBJ_PERIOD_D1;
      default:        return TFM_MLOW|TFM_H1;
     }
  }

// DaySepOnlyTFs — TFs above HTF but below D1 where only day separators show.
// Empty for D1 model (D1 is the top of its full-content range).
long DaySepOnlyTFs()
  {
   switch(HTF())
     {
      case PERIOD_H1: return TFM_H4|TFM_H12;  // H2 through H12
      case PERIOD_H4: return TFM_H12;          // H6 through H12
      case PERIOD_D1: return 0;                // nothing — D1 is already in full content
      default:        return TFM_H4|TFM_H12;
     }
  }

// LTFOnlyFlag — the exact LTF period only. Used for LTF-anchored dual POI lines.
long LTFOnlyFlag()
  {
   switch(LTF())
     {
      case PERIOD_M1:  return OBJ_PERIOD_M1;
      case PERIOD_M5:  return OBJ_PERIOD_M5;
      case PERIOD_M15: return OBJ_PERIOD_M15;
      default:         return OBJ_PERIOD_M1;
     }
  }

// AboveHTFFlag — full content minus the LTF. Used for HTF-anchored dual POI lines.
// These show on all full-content TFs except the LTF (where the LTF version is shown).
long AboveHTFFlag() { return FullContentTFs() & ~LTFOnlyFlag(); }

// LTFMaxTFs — TFs where LTF-clutter objects are visible (arrows, FVG boxes, CO line,
// hint boxes). Hard cap per model — these clutter intermediate TF views.
//   1H/1M  model → M1–M3
//   4H/5M  model → M1–M10
//   D1/15M model → M1–M30
long LTFMaxTFs()
  {
   long m3  =OBJ_PERIOD_M1|OBJ_PERIOD_M2|OBJ_PERIOD_M3;
   return m3;
  }

// BelowHTFTFs — TFs strictly below the model HTF.
// Used for candidate action pillar (shows on everything up to but not including HTF).
//   1H model → M1–M30 (everything below H1)
//   4H model → M1–H1 + H2/H3 (everything below H4)
//   D1 model → M1–H12 (everything below D1)
long BelowHTFTFs()
  {
   return TFM_MLOW;
  }

//--- NY time utilities (server/chart -> UTC -> NY, DST-aware) --------
int CurrentServerUTCOffsetSec()
  {
   datetime serverNow=TimeCurrent();
   datetime tradeNow=TimeTradeServer();
   datetime gmtNow=TimeGMT();

   int currentOff=(int)(serverNow-gmtNow);
   int tradeOff=(tradeNow>0)?(int)(tradeNow-gmtNow):0;

   // Prefer the chart/server clock that drives the EA.
   int rawOff=(MathAbs(currentOff)>=60)?currentOff:tradeOff;
   if(rawOff==0)
      rawOff=currentOff;

   // Broker server offsets are effectively whole-hour values here.
   return (int)(MathRound((double)rawOff/3600.0)*3600.0);
  }

int ServerUTCOffsetSec(datetime serverTime=0)
  {
   int liveOff=CurrentServerUTCOffsetSec();
   if(!IsTesterRun())
      return liveOff;

   datetime probeTime=(serverTime>0)?serverTime:MarketReferenceTime();
   if(probeTime<=0)
      return liveOff;

   // MT5 tester can report TimeCurrent/TimeGMT in a way that collapses the
   // broker's historical server offset toward UTC. For this feed the server
   // day is aligned to the 5pm New York close, which is NY+7 hours.
   datetime approxUtc=(datetime)(probeTime-2*3600);
   int nyOff=NYOffsetSecFromUTC(approxUtc);
   int modeledOff=nyOff + 7*3600;

   if(MathAbs(liveOff-modeledOff)>=2*3600 || liveOff==0)
      return modeledOff;
   return liveOff;
  }

datetime ServerToUTC(datetime serverTime)
  {
   return (datetime)(serverTime-ServerUTCOffsetSec(serverTime));
  }

int NYOffsetSecFromUTC(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc,d); int y=d.year;
   MqlDateTime m3;  TimeToStruct(StringToTime(string(y)+".03.01 00:00"),m3);
   int dow3=m3.day_of_week; int toSun3=(dow3==0)?0:(7-dow3);
   datetime dstStart=StringToTime(string(y)+".03.01 00:00")
                     +(datetime)((toSun3+7)*86400+7*3600);
   MqlDateTime m11; TimeToStruct(StringToTime(string(y)+".11.01 00:00"),m11);
   int dow11=m11.day_of_week; int toSun11=(dow11==0)?0:(7-dow11);
   datetime dstEnd=StringToTime(string(y)+".11.01 00:00")
                   +(datetime)(toSun11*86400+6*3600);
   return (utc>=dstStart && utc<dstEnd) ? -4*3600 : -5*3600;
  }

int NYUTCOffsetSec(datetime serverTime)
  {
   return NYOffsetSecFromUTC(ServerToUTC(serverTime));
  }

int LondonUTCOffsetSecFromUTC(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc,d);
   int y=d.year;
   datetime mar31=StringToTime(IntegerToString(y)+".03.31 01:00");
   datetime oct31=StringToTime(IntegerToString(y)+".10.31 01:00");
   MqlDateTime m3,m10; TimeToStruct(mar31,m3); TimeToStruct(oct31,m10);
   datetime bstStart=mar31-(datetime)(m3.day_of_week*86400);
   datetime bstEnd  =oct31-(datetime)(m10.day_of_week*86400);
   return (utc>=bstStart && utc<bstEnd)?3600:0;
  }

int EuropeDSTDeltaSecFromUTC(datetime utc)
  {
   return LondonUTCOffsetSecFromUTC(utc);
  }

int UTCPresetOffsetSec(datetime serverTime)
  {
   datetime utc=ServerToUTC(serverTime);
   switch(Inp_UTCPreset)
     {
      case UtcMinus6Chicago:    return NYOffsetSecFromUTC(utc)-3600;
      case UtcMinus7Denver:     return NYOffsetSecFromUTC(utc)-7200;
      case UtcMinus8LosAngeles: return NYOffsetSecFromUTC(utc)-10800;
      case UtcMinus3SaoPaulo:   return -3*3600;
      case UtcPlus0London:      return EuropeDSTDeltaSecFromUTC(utc);
      case UtcPlus1Berlin:      return 1*3600 + EuropeDSTDeltaSecFromUTC(utc);
      case UtcPlus2Athens:      return 2*3600 + EuropeDSTDeltaSecFromUTC(utc);
      case UtcPlus4Dubai:       return 4*3600;
      case UtcPlus8Singapore:   return 8*3600;
      case UtcPlus9Tokyo:       return 9*3600;
      case UtcPlus10Sydney:     return 10*3600;
      default:                  return NYOffsetSecFromUTC(utc);
     }
  }

string UTCPresetLabel()
  {
   switch(Inp_UTCPreset)
     {
      case UtcMinus6Chicago:    return " CHI";
      case UtcMinus7Denver:     return " DEN";
      case UtcMinus8LosAngeles: return " LA";
      case UtcMinus3SaoPaulo:   return " SP";
      case UtcPlus0London:      return " LON";
      case UtcPlus1Berlin:      return " BER";
      case UtcPlus2Athens:      return " ATH";
      case UtcPlus4Dubai:       return " DXB";
      case UtcPlus8Singapore:   return " SG";
      case UtcPlus9Tokyo:       return " TYO";
      case UtcPlus10Sydney:     return " SYD";
      default:               return " NY";
     }
  }

string TooltipTrimTail(string text)
  {
   while(StringLen(text)>0)
     {
      string tail=StringSubstr(text,StringLen(text)-1,1);
      if(tail!=" " && tail!="\n" && tail!="\r" && tail!="\t")
         break;
      text=StringSubstr(text,0,StringLen(text)-1);
     }
   return text;
  }

int TooltipSplitIndex(string text,int maxLen,int searchBack=80)
  {
   int len=StringLen(text);
   if(len<=maxLen) return len;
   int minIdx=maxLen-searchBack;
   if(minIdx<1) minIdx=1;
   for(int i=maxLen;i>=minIdx;i--)
      if(StringSubstr(text,i,1)=="\n")
         return i;
   return maxLen;
  }

string TooltipFit(string text,int maxLen=140,int maxLines=7,int maxLineLen=46)
  {
   const int hardMaxLen=140;
   const int hardMaxLines=7;
   const int hardMaxLineLen=46;
   text=TooltipTrimTail(text);
   if(maxLen<=0 || maxLen>hardMaxLen) maxLen=hardMaxLen;
   if(maxLines<=0 || maxLines>hardMaxLines) maxLines=hardMaxLines;
   if(maxLineLen<=0 || maxLineLen>hardMaxLineLen) maxLineLen=hardMaxLineLen;

   string out="";
   int pos=0;
   int lines=0;
   int totalLen=StringLen(text);
   while(pos<totalLen && lines<maxLines)
     {
      int nl=StringFind(text,"\n",pos);
      string line=(nl<0)?StringSubstr(text,pos):StringSubstr(text,pos,nl-pos);
      line=TooltipTrimTail(line);
      if(StringLen(line)>maxLineLen)
         line=TooltipTrimTail(StringSubstr(line,0,maxLineLen-3))+"...";

      string candidate=(out=="")?line:(out+"\n"+line);
      if(StringLen(candidate)>maxLen)
        {
         if(out=="")
            return TooltipTrimTail(StringSubstr(line,0,MathMax(1,maxLen-3)))+"...";
         return TooltipTrimTail(out)+"\n...";
        }

      out=candidate;
      lines++;
      if(nl<0)
        {
         pos=totalLen;
         break;
        }
      pos=nl+1;
     }

   if(pos<totalLen)
     {
      string withMore=(out=="")?"...":(out+"\n...");
      if(StringLen(withMore)<=maxLen)
         out=withMore;
      else if(out=="")
         out="...";
     }

   return TooltipTrimTail(out);
  }

void SplitTooltipPages(string text,string &page1,string &page2,int pageLen=140)
  {
   const int hardPageLen=140;
   text=TooltipTrimTail(text);
   if(pageLen<=0 || pageLen>hardPageLen) pageLen=hardPageLen;
   if(StringLen(text)<=pageLen)
     {
      page1=text;
      page2="";
      return;
     }
   int split=TooltipSplitIndex(text,pageLen,90);
   page1=TooltipFit(StringSubstr(text,0,split),pageLen,6,44);
   page2=TooltipFit(StringSubstr(text,split+1),pageLen,6,44);
  }

int InputPresetUTCOffsetSec(datetime serverTime)
  {
   if(Inp_Timezone==Exchange)
      return ServerUTCOffsetSec(serverTime);
   return UTCPresetOffsetSec(serverTime);
  }

int SlotHourToNYHour(int slotHour,datetime serverTime)
  {
   if(slotHour<0||slotHour>23) return slotHour;
   int presetOff=InputPresetUTCOffsetSec(serverTime);
   int nyOff=NYUTCOffsetSec(serverTime);
   int deltaHours=(nyOff-presetOff)/3600;
   return ((slotHour+deltaHours)%24+24)%24;
  }

int NYOffsetSec(datetime serverTime)
  {
   return NYUTCOffsetSec(serverTime)-ServerUTCOffsetSec(serverTime);
  }

datetime ToNY(datetime serverTime) { return serverTime+NYOffsetSec(serverTime); }

string NYStr(datetime serverTime)
  {
   datetime displayTime=serverTime;
   string tzLabel=" EXCH";
   if(Inp_Timezone==UTC)
     {
      int displayOff=UTCPresetOffsetSec(serverTime)-ServerUTCOffsetSec(serverTime);
      displayTime=serverTime+displayOff;
      tzLabel=UTCPresetLabel();
     }
   return TimeToString(displayTime,TIME_DATE|TIME_MINUTES)+tzLabel;
  }

datetime TodayOpen()
  {
   return TodayOpenAt(MarketReferenceTime());
  }

datetime BrokerDayOpen()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
  }

//--- Fibonacci SL helpers --------------------------------------------
// Returns the SL extension price for the confirmed IFVG.
// AnchorA: c1Ext (Mode 1) or trigger bar close (Mode 2).
// AnchorB: c2c3Extreme (min/max of C2 and C3 lows/highs).
// Extension multiplier: 0.5 / 0.75 / 1.0.
// SL is placed extMult * |A - B| beyond AnchorB (away from entry).
// CalcFibSL — SL price for the confirmed IFVG.
// The SL branch must be decided once from the full c1/c2/c3 cluster extreme:
//   Deep Swing = price breached the full cluster swing extreme
//   V-Shape    = price turned without breaching that full cluster extreme
// Mapping:
//   Deep Swing -> shallower extension of the selected pair
//   V-Shape    -> deeper extension of the selected pair

// ─────────────────────────────────────────────────────────────────────────────
// TP / BREAKEVEN / RISK  —  Enums & Inputs
// These correspond to the parameter groups defined above in the input section.
// ─────────────────────────────────────────────────────────────────────────────

// Lookup table — preset enum → R multiplier
double TPPresetR(ENUM_TP_PRESET p)
  {
   switch(p)
     {
      case TP_051R: return 0.51;
      case TP_100R: return 1.00;
      case TP_310R: return 3.10;
      case TP_410R: return 4.10;
      case TP_510R: return 5.10;
      default:      return 2.10;  // TP_210R
     }
  }

// Returns the effective minimum RR from the selected TP preset.
double Inp_MinRR_Eff() { return TPPresetR(Inp_TPPreset); }

ENUM_SL_BRANCH DetectSLBranch(const FVGInfo &fvg,bool bull,double priceProbe)
  {
   bool breached=bull?(priceProbe>fvg.clusterExtreme):(priceProbe<fvg.clusterExtreme);
   return breached?SL_BRANCH_DEEP_SWING:SL_BRANCH_VSHAPE;
  }

double ScanExtremeBetween(datetime fromTime,datetime toTime,bool lookHigh)
  {
   if(fromTime<=0 || toTime<fromTime)
      return 0.0;
   MqlRates ltf[];
   datetime scanTo=(datetime)(toTime+(datetime)PeriodSeconds(LTF()));
   int nl=CopyLTFWindowFromCache(fromTime,scanTo,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),fromTime,scanTo,ltf);
   if(nl<1)
      return 0.0;
   double extreme=lookHigh?ltf[0].high:ltf[0].low;
   for(int i=1;i<nl;i++)
     {
      if(lookHigh)
        {
         if(ltf[i].high>extreme) extreme=ltf[i].high;
        }
      else
        {
         if(ltf[i].low<extreme) extreme=ltf[i].low;
        }
     }
   return extreme;
  }

double FibExtensionMultiplier(ENUM_SL_BRANCH branch)
  {
   double shallow=(Inp_FibPair==FIB_PAIR_050_075)?0.50:0.75;
   double deep   =(Inp_FibPair==FIB_PAIR_050_075)?0.75:1.00;
   return (branch==SL_BRANCH_DEEP_SWING)?shallow:deep;
  }

double CalcFibSL(double anchorA,double anchorB,bool bull,ENUM_SL_BRANCH branch)
  {
   double extMult=FibExtensionMultiplier(branch);
   double gap=MathAbs(anchorA-anchorB);
   if(bull) return anchorB - extMult*gap;
   return   anchorB + extMult*gap;
  }

string FibBranchLabel(ENUM_SL_BRANCH branch)
  {
   return (branch==SL_BRANCH_DEEP_SWING) ? "Deep Swing" : "V-Shape";
  }

// CalcTPRaw — raw TP price from entry+SL using the selected preset R.
// Defined in Globals so both CCT_Visual.mqh and CCT_Execution.mqh can call it.
double CalcTPRaw(bool bull,double entry,double sl_raw,double coPrice)
  {
   double risk  = MathAbs(entry-sl_raw);
   double minRR = Inp_MinRR_Eff();
   double floorTP = bull?(entry+minRR*risk):(entry-minRR*risk);
   if(!Inp_UseCoIfFarther || coPrice<=0.0)
      return floorTP;
   return bull ? MathMax(floorTP,coPrice)
               : MathMin(floorTP,coPrice);
  }

//--- Codename generator (for POI labels) ----------------------------
string Codename(int idx)
  {
   string adj[] ={"Iron","Apex","Deep","Prime","Hard","Sharp","Core","Raw","Key","Wide",
                  "Bare","Keen","Bold","Dark","True","Cold","High","Low","Live","Firm"};
   string noun[]={"Ridge","Vault","Seal","Gate","Post","Mark","Node","Edge","Band","Shelf",
                  "Floor","Ceil","Zone","Line","Wall","Deck","Tier","Rung","Step","Block"};
   return adj[idx%20]+noun[(idx*7+3)%20];
  }

string CodenameFromTime(datetime t)
  {
   long key=(long)t;
   int idx=(int)MathAbs((int)(key/60));
   return Codename(idx);
  }

//--- Runtime risk/account globals ------------------------------------
double g_riskPct = 1.0; // Effective risk % — editable from dashboard
int    g_accMode = 0;   // 0=Balance  1=Equity  2=Custom
double g_custBal = 0.0; // User-typed custom balance

//--- DB1 signal state (exported by DrawGeneration, consumed by UpdateDashboards) ---
datetime  g_sigTrigTime  = 0;       // most recent trigger or C1 time (used to pick freshest signal)
bool      g_sigBull      = true;
string    g_sigName      = "";      // POI codename
SIB_STATE g_sigState     = SS_INACTIVE;
bool      g_sigC1        = false;
bool      g_sigC2        = false;
bool      g_sigC3        = false;
datetime  g_sigBirthTime = 0;
datetime  g_sigC1Time    = 0;
double    g_sigLevel     = 0.0;
double    g_sigSlPx      = 0.0;
double    g_sigTpPx      = 0.0;
double    g_sigCoPx      = 0.0;
string    g_sigModelLabel= "";

double EffectiveAccountBase()
  {
   if(g_accMode==1) return AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_accMode==2&&g_custBal>0.0) return g_custBal;
   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

bool IsTesterRun()
  {
   return ((bool)MQLInfoInteger(MQL_TESTER));
  }

bool IsVisualTesterRun()
  {
   return ((bool)MQLInfoInteger(MQL_TESTER) && (bool)MQLInfoInteger(MQL_VISUAL_MODE));
  }

bool IsNonVisualTesterRun()
  {
   return ((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE));
  }

//--- Hour-based trade mode helpers ----------------------------------
// Parsed hour lists (populated on first call to GetTradeWindow after init)
int  g_twOnly[],g_twTS[],g_twExt[];
int  g_twNOnly=0,g_twNTS=0,g_twNExt=0;
bool g_twParsed=false;

void ResetTradeWindowCache(){g_twParsed=false;g_twNOnly=0;g_twNTS=0;g_twNExt=0;}
int SlotHourToNYHour(int slotHour,datetime serverTime);

//--- Hour-based trade mode helpers ----------------------------------
// ParseHours: splits a space-separated string of ints into an array.
// Returns count of valid hours found.
int ParseHours(const string s, int &out[], int maxCount=12)
  {
   ArrayResize(out,0);
   int cnt=0;
   string tok[]; int n=StringSplit(s,' ',tok);
   for(int i=0;i<n&&cnt<maxCount;i++)
     {
      string t=tok[i];
      StringTrimLeft(t); StringTrimRight(t);
      if(StringLen(t)==0) continue;
      int h=(int)StringToInteger(t);
     if(h>=0&&h<24){ArrayResize(out,cnt+1);out[cnt++]=h;}
     }
   return cnt;
  }

int ParseHourSlots(const string s, int &out[], int maxCount=12)
  {
   ArrayResize(out,0);
   int cnt=0;
   string tok[]; int n=StringSplit(s,' ',tok);
   for(int i=0;i<n&&cnt<maxCount;i++)
     {
      string t=tok[i];
      StringTrimLeft(t); StringTrimRight(t);
      if(StringLen(t)==0) continue;
      int h=(int)StringToInteger(t);
      if(h<0||h>=24) continue;
      ArrayResize(out,cnt+1);
      out[cnt++]=h;
     }
   return cnt;
  }

// HourInList: returns true if h is in the parsed list, OR if list is {0} (wildcard = all valid).
bool HourInList(int h, const int &list[], int cnt)
  {
   if(cnt==0) return false;
   if(cnt==1&&list[0]==0) return true; // "0" = all hours
   for(int i=0;i<cnt;i++) if(list[i]==h) return true;
   return false;
  }

bool HourInListAtTime(int execHourNY,const int &list[],int cnt,datetime serverTime)
  {
   if(cnt==0) return false;
   if(cnt==1&&list[0]==0) return true;
   for(int i=0;i<cnt;i++)
      if(SlotHourToNYHour(list[i],serverTime)==execHourNY)
         return true;
   return false;
  }

// TradeWindowResult — describes what birth is needed for an exec bar
struct TradeWindowResult
  {
   bool   valid;        // exec hour is allowed
   int    birthHour;    // exact required birth hour (execHour - offset)
   int    minHTF;       // min intermediate bars
   int    maxHTF;       // max intermediate bars
   bool   tsRequired;   // true if TS wick required (minHTF >= 1)
  };

bool ResolveTradeWindowForOffset(int execHourNY,int offset,datetime refServerTime,TradeWindowResult &out)
  {
   ZeroMemory(out);
   out.valid=false;
   if(refServerTime<=0) refServerTime=TimeCurrent();

   if(!Inp_SessionFilter)
     {
      out.valid=true;
      out.birthHour=(execHourNY-offset+24)%24;
      out.minHTF=MathMax(0,offset-1);
      out.maxHTF=MathMax(0,offset-1);
      out.tsRequired=(offset>1);
      return true;
     }

   if(refServerTime<=0) refServerTime=TimeCurrent();

   if(!g_twParsed)
     {
      g_twNOnly=ParseHourSlots(InpCCTOnly,g_twOnly);
      g_twNTS  =ParseHourSlots(InpCCTTS,  g_twTS);
      g_twNExt =ParseHourSlots(InpCCTTSExt,g_twExt);
      g_twParsed=true;
     }

   bool allowed=false;
   if(offset<=1)
      allowed=HourInListAtTime(execHourNY,g_twOnly,g_twNOnly,refServerTime);
   else if(offset==2)
      allowed=HourInListAtTime(execHourNY,g_twTS,g_twNTS,refServerTime);
   else if(offset==3)
      allowed=HourInListAtTime(execHourNY,g_twExt,g_twNExt,refServerTime);

   if(!allowed)
      return false;

   out.valid=true;
   out.birthHour=(execHourNY-offset+24)%24;
   out.minHTF=MathMax(0,offset-1);
   out.maxHTF=MathMax(0,offset-1);
   out.tsRequired=(offset>1);
   return true;
  }

// GetTradeWindow: generic "is this execution hour tradable at all?" helper.
// When the same exec hour is enabled across multiple models, they coexist in parallel;
// this helper returns the earliest matching offset only for callers that only need
// a yes/no or fallback label. Birth-specific paths must use ResolveTradeWindowForOffset.
TradeWindowResult GetTradeWindow(int execHourNY,datetime refServerTime=0)
  {
   TradeWindowResult r; ZeroMemory(r); r.valid=false;
   if(!Inp_SessionFilter) { r.valid=true; r.minHTF=0; r.maxHTF=3; r.tsRequired=false; return r; }
   if(refServerTime<=0) refServerTime=TimeCurrent();

   for(int offset=1; offset<=3; offset++)
     {
      TradeWindowResult tw;
      if(ResolveTradeWindowForOffset(execHourNY,offset,refServerTime,tw))
         return tw;
     }
   return r;
  }

bool ResolveBirthTradeWindowCurrentModel(datetime birthTimeServer,TradeWindowResult &out)
  {
    ZeroMemory(out);
    out.valid=false;

    datetime nyBirth=ToNY(birthTimeServer);
    MqlDateTime bd; TimeToStruct(nyBirth,bd);
    int birthKey=bd.hour;

   if(!Inp_SessionFilter)
     {
      out.valid=true;
      out.birthHour=birthKey;
      out.minHTF=0;
      out.maxHTF=3;
       out.tsRequired=false;
       return true;
      }

    bool found=false;
    for(int offset=1;offset<=3;offset++)
      {
       int execH=(birthKey+offset)%24;
       TradeWindowResult twx;
       if(!ResolveTradeWindowForOffset(execH,offset,birthTimeServer+(datetime)(offset*PeriodSeconds(HTF())),twx))
         continue;

       if(twx.birthHour==birthKey)
         {
          if(!found)
            {
             out=twx;
             found=true;
            }
          else
            {
             out.minHTF=MathMin(out.minHTF,twx.minHTF);
             out.maxHTF=MathMax(out.maxHTF,twx.maxHTF);
            }
         }
      }
    if(found)
       out.tsRequired=(out.minHTF>0);
    return found;
  }

string TradeWindowLabelForOffset(int offset)
  {
   if(offset<=1) return "Plain CCT";
   if(offset==2) return "CCT + TS";
   return "CCT + TS Extended";
  }

string TradeWindowShortLabelForOffset(int offset)
  {
   if(offset<=1) return "CCT";
   if(offset==2) return "CCT+TS";
   return "CCT+TS Ext";
  }

string TradeModelShortLabelForBirth(datetime birthTimeServer)
  {
   TradeWindowResult tw;
   if(ResolveBirthTradeWindowCurrentModel(birthTimeServer,tw))
      return TradeWindowShortLabelForOffset(tw.maxHTF+1);
   return "CCT";
  }

bool ResolveExecutionWindowForTrigger(datetime triggerTimeServer,
                                      TradeWindowResult &out,
                                      datetime &windowOpenServer,
                                      datetime &windowEndServer,
                                      string &windowLabel,
                                      int &execKey,
                                      datetime birthTimeServer=0,
                                      datetime c1TimeServer=0)
  {
   ZeroMemory(out);
   out.valid=false;
   windowOpenServer=0;
   windowEndServer=0;
   windowLabel="";
   execKey=-1;

   int shift=iBarShift(_Symbol,HTF(),triggerTimeServer,false);
   if(shift<0)
      return false;

   datetime execOpenServer=iTime(_Symbol,HTF(),shift);
   int pSec=(int)PeriodSeconds(HTF());
   if(execOpenServer<=0 || pSec<=0)
      return false;

   datetime execKeyServer=ToNY(execOpenServer);
   MqlDateTime ed; TimeToStruct(execKeyServer,ed);
   execKey=ed.hour;

   // C1-time gate: C1 must have happened at or after the execution bar opens.
   // For Plain CCT (offset=1), execOpenServer == pillarOpen, and the pillarOpen
   // gate in ScanGeneration already guarantees c1Time >= pillarOpen. So this
   // check never blocks Plain CCT. For CCT+TS (offset=2), execOpenServer is
   // one bar later than pillarOpen; a C1 that fired on the development bar
   // (offset=1 from birth) is correctly blocked here.
   if(c1TimeServer > 0 && c1TimeServer < execOpenServer)
     return false;

   if(birthTimeServer>0)
     {
      int birthShift=iBarShift(_Symbol,HTF(),birthTimeServer,false);
      if(birthShift<0)
         return false;
      datetime birthOpenServer=iTime(_Symbol,HTF(),birthShift);
      if(birthOpenServer<=0)
         return false;

      int offset=(int)((execOpenServer-birthOpenServer)/pSec);
      if(offset<1 || offset>3)
         return false;

      if(!ResolveTradeWindowForOffset(execKey,offset,execOpenServer,out))
         return false;

      datetime nyBirth=ToNY(birthOpenServer);
      MqlDateTime bd; TimeToStruct(nyBirth,bd);
      if(out.birthHour!=bd.hour)
         return false;
     }
   else
     {
      out=GetTradeWindow(execKey,execOpenServer);
      if(!out.valid)
         return false;
     }

   windowOpenServer=execOpenServer;
   windowEndServer=(datetime)(execOpenServer+pSec-1);
   windowLabel=TradeWindowLabelForOffset(out.maxHTF+1);
   return (triggerTimeServer>=windowOpenServer && triggerTimeServer<=windowEndServer);
  }

string ResolveTriggerModelLabelForSibling(SibInfo &sib,
                                          datetime birthTimeServer,
                                          datetime triggerTimeServer,
                                          string fallbackLabel="CCT")
  {
   string label=(fallbackLabel!="")?fallbackLabel:"CCT";
   TradeWindowResult execWindow;
   datetime execOpenServer=0,execEndServer=0;
   string execHumanLabel="";
   int execKey=-1;
   if(triggerTimeServer>0
      && ResolveExecutionWindowForTrigger(triggerTimeServer,
                                          execWindow,
                                          execOpenServer,
                                          execEndServer,
                                          execHumanLabel,
                                          execKey,
                                          birthTimeServer))
      label=TradeWindowShortLabelForOffset(execWindow.maxHTF+1);
   return ActualExecutionModelLabelForSibling(sib,label,triggerTimeServer);
  }

bool ResolveFirstExecutionWindowForBirth(datetime birthTimeServer,
                                         datetime &windowOpenServer,
                                         datetime &windowEndServer,
                                         string &windowLabel)
  {
   windowOpenServer=0;
   windowEndServer=0;
   windowLabel="";

   int pSec=(int)PeriodSeconds(HTF());
   if(pSec<=0)
      return false;

   datetime nyBirth=ToNY(birthTimeServer);
   MqlDateTime bd; TimeToStruct(nyBirth,bd);
   int birthKey=bd.hour;

    if(!Inp_SessionFilter)
      {
       windowOpenServer=birthTimeServer+(datetime)pSec;
       windowEndServer=(datetime)(windowOpenServer+pSec-1);
       windowLabel="Plain CCT";
       return true;
      }

    int earliestOffset=0;
    for(int offset=1; offset<=3; offset++)
      {
       datetime execOpenServer=birthTimeServer+(datetime)(offset*pSec);
       datetime execKeyServer=ToNY(execOpenServer);
       MqlDateTime ed; TimeToStruct(execKeyServer,ed);
       TradeWindowResult twx;
      if(!ResolveTradeWindowForOffset(ed.hour,offset,execOpenServer,twx))
         continue;

       if(twx.birthHour!=birthKey)
          continue;

       earliestOffset=offset;
       break;
      }
    if(earliestOffset<=0)
       return false;

    windowOpenServer=birthTimeServer+(datetime)(earliestOffset*pSec);
    windowEndServer=(datetime)(windowOpenServer+pSec-1);
    windowLabel=TradeWindowLabelForOffset(earliestOffset);
    return true;
  }

bool ResolveGenerationActivationWindow(MqlRates &B[],int n,int pSec,int bb,
                                       datetime &pillarOpen,
                                       datetime &minActivateTime,
                                       datetime &maxActivateTime)
  {
   pillarOpen=(bb+1<n)?B[bb+1].time:B[bb].time+pSec;
   minActivateTime=pillarOpen;
   maxActivateTime=0;

   TradeWindowResult birthWindow;
   if(!ResolveBirthTradeWindowCurrentModel(B[bb].time,birthWindow))
     {
      minActivateTime=(datetime)(pillarOpen+pSec);
      maxActivateTime=pillarOpen;
      return false;
     }

   int minIdx=bb+1+birthWindow.minHTF;
   int maxIdx=bb+1+birthWindow.maxHTF;
   minActivateTime=(birthWindow.minHTF>0 && minIdx<n)?B[minIdx].time:pillarOpen;
   maxActivateTime=(maxIdx<n)?(datetime)(B[maxIdx].time+pSec):0;
   return true;
  }

// IsExecHourAllowed: quick check for any mode
bool IsExecHourAllowed(int execHourNY)
  { TradeWindowResult r=GetTradeWindow(execHourNY,TimeCurrent()); return r.valid; }

// IsBirthHourValidForExec: returns true if birth/exec pairing is valid.
// isDormant: if true, applies supersession rule (always allowed when exec window is open).
bool IsBirthHourValidForExec(int birthHourNY, int execHourNY, bool isDormant)
  {
   if(!Inp_SessionFilter) return true;
   bool anyAllowed=false;
   for(int offset=1; offset<=3; offset++)
     {
      TradeWindowResult r;
      if(!ResolveTradeWindowForOffset(execHourNY,offset,TimeCurrent(),r))
         continue;
      anyAllowed=true;
      if(isDormant) return true; // supersession rule: exec window is open, dormant POIs eligible
      if(birthHourNY==r.birthHour)
         return true;
     }
   return false;
  }

//--- IsNYAMSession — 07:00-11:00 NY time ----------------------------
bool IsNYAMSessionAt(datetime serverTime)
  {
   datetime nyNow=ToNY(serverTime);
   MqlDateTime dt; TimeToStruct(nyNow,dt);
   return (dt.hour>=7&&dt.hour<11);
  }

bool IsNYAMSession()
  {
   return IsNYAMSessionAt(TimeCurrent());
  }

//--- GetCurrentSession — returns session name for dashboard ---------
string GetCurrentSessionAt(datetime serverTime)
  {
   datetime nyNow=ToNY(serverTime);
   MqlDateTime dt; TimeToStruct(nyNow,dt);
   int h=dt.hour;
   if(h>=2 &&h<7)  return "London";
   if(h>=7 &&h<12) return "NY AM";
   if(h>=12&&h<17) return "NY PM";
   if(h>=19&&h<23) return "Asian";
   return "Off-session";
  }

string GetCurrentSession()
  {
   return GetCurrentSessionAt(TimeCurrent());
  }

#endif // CCT_GLOBALS_MQH
