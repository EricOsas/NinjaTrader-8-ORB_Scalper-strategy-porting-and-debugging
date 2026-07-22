#ifndef CCT_GLOBALS_MQH
#define CCT_GLOBALS_MQH

#define CCT_MAX_SIBS 20
#define CCT_MAX_FVGS 30

// CCT_VISUAL_LIVE_HISTORICAL_RECONSTRUCTION_V2
// False by default. RefreshState(true) temporarily enables this so chart
// rebuilds can reconstruct old visual/synthetic triggers without allowing
// broker orders from stale trigger bars.
// CCT_VISUAL_LIVE_HISTORICAL_RECONSTRUCTION_V3
// CCT_HISTORICAL_TRIGGER_REPLAY_WINDOW_EXPIRED_DEFER_V5
bool g_cctAllowHistoricalReplayTriggers=false;
bool g_cctFastInitialVisualMode=false;

enum WICK_STATE
  {
   WS_VIRGIN = 0,
   WS_CANDIDATE,
   WS_STRIPPED
  };

enum SIB_STATE
  {
   SS_VALID = 0,
   SS_ACTIVE,
   SS_INACTIVE,
   SS_TRIGGERED,
   SS_DORMANT,
   SS_RESOLVED_TP,
   SS_RESOLVED_SL,
   SS_RESOLVED_BE,
   SS_RESOLVED_BE_CO,
   SS_DEAD_SUPERSESSION,
   SS_DEAD_WINDOW_CONSUMED,
   SS_DEAD_WINDOW_EXPIRED,
   SS_DEAD_UNAUTHORIZED_C1,
   SS_DEAD_CO_VIOLATION,
   SS_DEAD_BIAS_FLIP,
   SS_UNKNOWN_OUTCOME
  };

enum ENUM_MODEL_TYPE
  {
   MODEL_CCT = 0,     // CCT
   MODEL_CCT_TS,      // CCT + TS
   MODEL_CCT_TS_EXT,  // CCT + TS Ext
   MODEL_CCT_EXT,     // CCT Ext
   MODEL_CCT_STRUCT_TS // CCT + Structural TS
  };

enum ENUM_CCT_AUTH_ROUTE
  {
   AUTH_ROUTE_NONE = 0,
   AUTH_ROUTE_CCT,
   AUTH_ROUTE_CCT_EXT,
   AUTH_ROUTE_TS,
   AUTH_ROUTE_TS_EXT,
   AUTH_ROUTE_RECORD_ONLY
  };

enum ENUM_SL_BRANCH
  {
   BRANCH_VSHAPE = 0,    // V-Shape
   BRANCH_DEEP_SWING     // Deep Swing
  };

enum ENUM_FIB_MODE
  {
   FIB_STANDARD = 0,   // Standard anchor A
   FIB_MOMENTUM        // Momentum anchor A
  };

enum ENUM_FIB_CFG
  {
   FIB_CFG_1 = 0,   // Standard extension (0.50 / 0.75)
   FIB_CFG_2        // Wider extension (0.75 / 1.00)
  };

enum ENUM_ACC_MODE
  {
   ACC_BALANCE = 0,   // Balance
   ACC_EQUITY,        // Equity
   ACC_CUSTOM         // Custom capital
  };

enum ENUM_RR_PRESET
  {
   RR_PRESET_0_50 = 50,       // 0.50R
   RR_PRESET_0_75 = 75,       // 0.75R
   RR_PRESET_1_00 = 100,      // 1.00R
   RR_PRESET_1_25 = 125,      // 1.25R
   RR_PRESET_1_50 = 150,      // 1.50R
   RR_PRESET_2_00 = 200,      // 2.00R
   RR_PRESET_2_50 = 250,      // 2.50R
   RR_PRESET_3_00 = 300,      // 3.00R
   RR_PRESET_4_00 = 400,      // 4.00R
   RR_PRESET_5_00 = 500,      // 5.00R
   RR_PRESET_CUSTOM = 10000   // Custom (use field below)
  };

enum ENUM_PERCENT_PRESET
  {
   PCT_PRESET_10 = 10,        // 10%
   PCT_PRESET_20 = 20,        // 20%
   PCT_PRESET_25 = 25,        // 25%
   PCT_PRESET_33 = 33,        // 33%
   PCT_PRESET_50 = 50,        // 50%
   PCT_PRESET_60 = 60,        // 60%
   PCT_PRESET_75 = 75,        // 75%
   PCT_PRESET_80 = 80,        // 80%
   PCT_PRESET_90 = 90,        // 90%
   PCT_PRESET_100 = 100,      // 100%
   PCT_PRESET_CUSTOM = 1000   // Custom (use field below)
  };

enum ENUM_SECONDS_PRESET
  {
   SEC_PRESET_60 = 60,        // 60 sec
   SEC_PRESET_120 = 120,      // 120 sec
   SEC_PRESET_180 = 180,      // 180 sec
   SEC_PRESET_300 = 300,      // 300 sec
   SEC_PRESET_600 = 600,      // 600 sec
   SEC_PRESET_900 = 900,      // 900 sec
   SEC_PRESET_1800 = 1800,    // 1800 sec
   SEC_PRESET_CUSTOM = 10000  // Custom (use field below)
  };

enum ENUM_RISK_PRESET
  {
   RISK_PRESET_0_25 = 25,      // 0.25%
   RISK_PRESET_0_50 = 50,      // 0.50%
   RISK_PRESET_0_75 = 75,      // 0.75%
   RISK_PRESET_1_00 = 100,     // 1.00%
   RISK_PRESET_1_25 = 125,     // 1.25%
   RISK_PRESET_1_50 = 150,     // 1.50%
   RISK_PRESET_2_00 = 200,     // 2.00%
   RISK_PRESET_CUSTOM = 10000  // Custom (use field below)
  };

enum ENUM_BE_CO_LOCK_PRESET
  {
   BECO_LOCK_0_25 = 25,       // 0.25%
   BECO_LOCK_0_50 = 50,       // 0.50%
   BECO_LOCK_1_00 = 100,      // 1.00%
   BECO_LOCK_1_50 = 150,      // 1.50%
   BECO_LOCK_2_00 = 200,      // 2.00%
   BECO_LOCK_3_00 = 300,      // 3.00%
   BECO_LOCK_5_00 = 500,      // 5.00%
   BECO_LOCK_CUSTOM = 10000   // Custom (use field below)
  };

enum ENUM_CCT_CO_BE_SCOPE
  {
   CO_BE_SCOPE_NY_AM_ONLY = 0,       // NY AM only
   CO_BE_SCOPE_ALL_SESSIONS,         // All sessions
   CO_BE_SCOPE_SELECTED_MODELS       // Selected models/sessions
  };

enum ENUM_CCT_IFVG_LOOKBACK_MODE
  {
   IFVG_LOOKBACK_STANDARD = 0,      // Standard: 1H=90m, 4H=6h, 1D=36h
   IFVG_LOOKBACK_CONSERVATIVE,      // Conservative: half of Standard
   IFVG_LOOKBACK_DISABLED           // Disabled: no IFVG inversion time filter
  };

enum ENUM_BROKER_EXEC_MODE
  {
   BROKER_EXEC_OFF = 0, // Signals/visuals only
   BROKER_EXEC_ON       // Send live broker orders
  };

enum ENUM_CCT_PRIVACY_MODE
  {
   PRIVACY_NORMAL = 0,          // Full comments and diagnostics
   PRIVACY_SAFE_CLOAK,          // Blank broker comments, suppress live CCT logs, keep magic
   PRIVACY_AGGRESSIVE_INCOGNITO // Blank comments/logs; optional zero magic with reduced recovery safety
  };

enum ENUM_CCT_PROP_SCOPE
  {
   PROP_SCOPE_ACCOUNT = 0,     // Account-wide guard accounting
   PROP_SCOPE_EA_MAGIC,        // EA magic number only
   PROP_SCOPE_SYMBOL           // Current symbol and EA magic only
  };

enum ENUM_CCT_MAX_LOT_MODE
  {
   MAX_LOTS_OFF = 0,            // Disabled
   MAX_LOTS_GLOBAL,             // Use global Max lots for each asset class
   MAX_LOTS_PER_ASSET           // Use per-asset-class Max lots fields
  };

enum ENUM_CCT_ASSET_CLASS
  {
   ASSET_CLASS_FX = 0,    // FX
   ASSET_CLASS_METALS,    // Metals
   ASSET_CLASS_COMMODITY, // Energy/Commodities
   ASSET_CLASS_INDICES,   // Indices
   ASSET_CLASS_CRYPTO,    // Crypto
   ASSET_CLASS_OTHER      // General/Other
  };

enum ENUM_CCT_DAILY_LOSS_BASIS
  {
   DAILY_LOSS_INITIAL_BALANCE = 0, // Balance captured when EA initializes
   DAILY_LOSS_NY_DAY_START,        // Equity captured at NY day start / attach
   DAILY_LOSS_CUSTOM               // Custom reference balance
  };

enum ENUM_CCT_NEWS_IMPACT
  {
   NEWS_IMPACT_HIGH = 0,       // High impact only
   NEWS_IMPACT_MED_HIGH,       // Medium and high impact
   NEWS_IMPACT_ALL             // Low, medium, and high impact
  };

enum ENUM_DISPLAY_TZ_PRESET
  {
   DISPLAY_TZ_NY = 0,        // New York
   DISPLAY_TZ_UTC,           // UTC
   DISPLAY_TZ_LONDON,        // London
   DISPLAY_TZ_LAGOS,         // Lagos / WAT
   DISPLAY_TZ_LAX,           // LAX / Los Angeles
   DISPLAY_TZ_CHICAGO,       // Chicago / Central
   DISPLAY_TZ_DUBAI,         // Dubai / GST
   DISPLAY_TZ_TOKYO,         // Tokyo / JST
   DISPLAY_TZ_MUMBAI,        // Mumbai / IST UTC+05:30
   DISPLAY_TZ_KATHMANDU,     // Kathmandu / NPT UTC+05:45
   DISPLAY_TZ_MARQUESAS,     // Marquesas / MART UTC-09:30
   DISPLAY_TZ_CUSTOM         // Custom fixed UTC offset
  };

enum ENUM_CCT_TESTER_TIME_MODEL
  {
   CCT_TESTER_TIME_AUTO = 0,       // Auto
   CCT_TESTER_TIME_LIVE_OFFSET,    // Use terminal live offset
   CCT_TESTER_TIME_UTC,            // Tester chart time is UTC
   CCT_TESTER_TIME_NY_PLUS_7,      // Tester chart time is NY+7/EET-style server time
   CCT_TESTER_TIME_CUSTOM          // Use custom UTC offset hours
  };

enum ENUM_CCT_DASHBOARD_THEME
  {
   DASH_THEME_BLUE = 0,       // Blue
   DASH_THEME_PLATINUM,       // Platinum / Silver
   DASH_THEME_EMERALD,        // Emerald
   DASH_THEME_VIOLET,         // Violet
   DASH_THEME_CHAMPAGNE       // Champagne / Gold
  };

enum ENUM_CCT_DASHBOARD_MODE
  {
   DASH_MODE_DARK = 0,        // Dark
   DASH_MODE_DIM_LIGHT        // Dim light
  };

enum ENUM_NOTIFY_REPORT_DAY
  {
   NOTIFY_REPORT_DAY_SATURDAY = 6, // Saturday
   NOTIFY_REPORT_DAY_SUNDAY = 0    // Sunday
  };

enum ENUM_CCT_4H_ANCHOR_MODE
  {
   CCT_4H_ANCHOR_1_5_9  = 0, // 1,5,9,13,17,21
   CCT_4H_ANCHOR_2_6_10 = 1  // 2,6,10,14,18,22
  };

enum ENUM_CCT_WEEK_START_MODE
  {
   CCT_WEEK_START_SUNDAY = 0, // Sunday=1
   CCT_WEEK_START_MONDAY = 1  // Monday=1
  };

enum ENUM_CCT_TIMEFRAME_MODEL
  {
   CCT_TFM_1H_M1  = 0, // 1H/1m
   CCT_TFM_4H_M5  = 1, // 4H/5m
   CCT_TFM_D1_M15 = 2  // 1D/15m
  };

enum ENUM_CCT_LOOKBACK_PROFILE
  {
   CCT_LOOKBACK_DEFAULT  = 0, // Standard
   CCT_LOOKBACK_ENHANCED = 1  // Extended
  };

struct WickInfo
  {
   datetime          barTime;
   datetime          ltfAnchor;
   double            level;
   bool              bull;
   WICK_STATE        state;
  };

struct SibInfo
  {
   datetime          wickTime;
   datetime          ltfAnchor;
   double            level;
   SIB_STATE         state;
   datetime          c1Time;
   datetime          c2Time;
   datetime          c3Time;
   bool              hadAuthorizedC1;
   ENUM_CCT_AUTH_ROUTE authorityRoute;
   datetime          authorityHTFOpen;
   int               authorityHourNY;
   int               authorityOffset;
   bool              authorityDormantTakeover;
   bool              authorityRecordOnly;
   datetime          tsScopeFrom;
   double            tsLevel;
   datetime          tsWickTime;
   datetime          dynamicEndTime;
  };

struct FVGInfo
  {
   datetime          t1;
   datetime          t2;
   datetime          t3;
   double            c1Ext;
   double            c3Ext;
   double            c2c3Extreme;
   datetime          c2c3ExtremeTime;
   double            clusterExtreme;
   bool              inverted;
   datetime          invTime;
   bool              invalidInv;
   bool              stale;
   bool              superseded;
  };

struct GenInfo
  {
   datetime          birthTime;
   bool              bull;
   bool              dormant;
   SibInfo           sibs[CCT_MAX_SIBS];
   int               nSibs;
   double            coPrice;
   datetime          coTime;
   bool              coLocked;
   datetime          coLtfAnchor;
   datetime          coFreezeTime;
   bool              coFrozen;
   datetime          coTouchTime;
   FVGInfo           fvgs[CCT_MAX_FVGS];
   int               nFvgs;
   int               c3FvgIdx;
   datetime          triggerTime;
   ENUM_MODEL_TYPE   modelType;
   int               sweepCount;
   int               tsBirthOrOlderSweepCount;
   int               tsPostBirthSweepCount;
   double            tsDisplayLevel;
   datetime          tsDisplayWickTime;
   datetime          tsDisplayLtfAnchor;
   datetime          tsFirstTouchTime;
   datetime          tsEligibleFrom;
   bool              tsConfirmed;
   ENUM_SL_BRANCH    slBranch;
   double            anchorA;
   datetime          anchorATime;
   double            anchorB;
   datetime          anchorBTime;
   double            visualEntry;
   datetime          visualEntryTime;
   double            triggerSpread;
   double            fibRawSL;
   double            rawSL;
   double            rawTP;
   double            lockedRR;
   SIB_STATE         outcome;
   datetime          exitTime;
   double            exitPrice;
   bool              beApplied;
   bool              beGeneralApplied;
   bool              beCoApplied;
   double            bePrice;
   datetime          beTriggerTime;
   datetime          beLeftAnchorTime;
      double            beGeneralPrice;
   datetime          beGeneralTime;
   datetime          beGeneralLeftAnchorTime;
   double            beCoPrice;
   datetime          beCoTime;
   datetime          beCoLeftAnchorTime;
int               activeSibIdx;
  };

struct ExecRecord
  {
   string            genKey;
   bool              bull;
   datetime          triggerBarTime;
   double            visualEntry;
   double            brokerFill;
   double            triggerSpread;
   double            brokerSL;
   double            brokerTP;
   double            coPrice;
   double            anchorA;
   datetime          anchorATime;
   double            anchorB;
   datetime          anchorBTime;
   double            rawSL;
   double            lockedRR;
   ENUM_SL_BRANCH    slBranch;
   ENUM_MODEL_TYPE   modelType;
   int               sweepCount;
    double            execLots;
    int               sibIndex;
    datetime          c1Time;
   datetime          c2Time;
   datetime          c3Time;
   bool              beApplied;
   bool              beGeneralApplied;
   bool              beCoApplied;
   double            bePrice;
   datetime          beTime;
   datetime          beLeftAnchorTime;
      double            beGeneralPrice;
   datetime          beGeneralTime;
   datetime          beGeneralLeftAnchorTime;
   double            beCoPrice;
   datetime          beCoTime;
   datetime          beCoLeftAnchorTime;
double            maxProgressPct;
   bool              coTouched;
   datetime          coTouchTime;
   bool              virtualTPActive;
   bool              virtualTPTouched;
   datetime          virtualTPTouchTime;
   SIB_STATE         outcome;
   datetime          exitTime;
   double            exitPrice;
   ulong             ticket;
   bool              isSynthetic;
  };

input group "01 - Model & Sessions"
input(name="Model") ENUM_CCT_TIMEFRAME_MODEL    Inp_TimeframeModel        = CCT_TFM_1H_M1; // Active model
input(name="Use session filter") bool           Inp_SessionFilter         = true;    // Restrict entries to the selected model hours/days
input(name="1H/1m CCT Hours") string             InpCCTOnly                = "1,2,3,4,5,6,7,8,9,10,11,20,21,22,23";  // NY hours
input(name="1H/1m CCT + TS Hours") string        InpCCTTS                  = "1,2,3,4,5,6,7,8,9,10,11,20,21,22,23";  // NY hours
input(name="1H/1m CCT + TS Ext Hours") string    InpCCTTSExt               = "1,2,3,4,5,6,7,8,9,10,11,20,21,22,23";  // NY hours
input(name="1H/1m Use CCT Days") bool            Inp_1H_UseDailyDayGuard   = false;   // Guard 1H/1m hours with Daily Model CCT Days
input(name="FVG inversion lookback") ENUM_CCT_IFVG_LOOKBACK_MODE Inp_IFVGLookback = IFVG_LOOKBACK_STANDARD; // Standard, Conservative, or Disabled
input(name="Allow structural TS upgrades") bool  Inp_TSFilter             = true;    // Allow qualifying plain CCT setups to upgrade by TS sweep count

input group "02 - 4H Model"
input(name="Start Hours") ENUM_CCT_4H_ANCHOR_MODE Inp_4H_AnchorMode       = CCT_4H_ANCHOR_1_5_9;
input(name="CCT Hours") string                   Inp_4H_CCT_Blocks        = "1,5,9,13,17,21";
input(name="CCT + TS Hours") string              Inp_4H_TS_Blocks         = "1,5,9,13,17,21";
input(name="CCT + TS Ext Hours") string          Inp_4H_TSExt_Blocks      = "1,5,9,13,17,21";
input(name="Use CCT Days") bool                  Inp_4H_UseDailyDayGuard  = false;   // Guard 4H hours with Daily Model CCT days

input group "03 - Daily Model"
input(name="Daily Model Numbering") ENUM_CCT_WEEK_START_MODE Inp_Daily_WeekStart = CCT_WEEK_START_SUNDAY;
input(name="CCT Days") string                    Inp_Daily_CCT_Days       = "1,2,3,4,5,6,7";
input(name="CCT + TS Days") string               Inp_Daily_TS_Days        = "1,2,3,4,5,6,7";
input(name="CCT + TS Ext Days") string           Inp_Daily_TSExt_Days     = "1,2,3,4,5,6,7";
input(name="CCT Day Exec. sessions") string      Inp_Daily_CCT_Sessions   = "0"; // blank/0 all; 1=LON 2=NYAM 3=NYPM 4=Asia 5=00-01
input(name="CCT + TS Day Exec. sessions") string Inp_Daily_TS_Sessions    = "0"; // blank/0 all; 1=LON 2=NYAM 3=NYPM 4=Asia 5=00-01
input(name="CCT + TS Ext Day Exec. sessions") string Inp_Daily_TSExt_Sessions = "0"; // blank/0 all; 1=LON 2=NYAM 3=NYPM 4=Asia 5=00-01

input group "04 - Risk & Capital"
input(name="Risk per trade preset") ENUM_RISK_PRESET Inp_RiskPreset       = RISK_PRESET_1_00; // Risk per trade
input(name="Risk per trade custom %") double    Inp_RiskCustomPct         = 1.0;     // Used only when Risk per trade preset = Custom
input(name="Risk capital source") ENUM_ACC_MODE Inp_AccMode               = ACC_CUSTOM; // Balance, equity, or custom capital
input(name="Custom risk capital") double        Inp_CustBal               = 10000.0; // Used only when Risk capital source = Custom capital

input group "05 - Broker Execution & Privacy"
input(name="Send broker orders") ENUM_BROKER_EXEC_MODE Inp_BrokerExecution = BROKER_EXEC_ON; // On = send market orders on fresh triggers
input(name="Max slippage/deviation points") int Inp_MaxDeviationPoints    = 10;      // Market order deviation guard
input(name="Hide broker trade comments") bool   Inp_HideTradeComments     = false;   // Blank broker comments while keeping normal EA ownership
input(name="Privacy / stealth mode") ENUM_CCT_PRIVACY_MODE Inp_PrivacyMode = PRIVACY_NORMAL; // Controls live comments and journal diagnostics
input(name="Incognito: use magic number 0") bool Inp_IncognitoMagicZero    = false;   // Risky: weaker restart recovery and manual-trade separation
input(name="No-money fallback: use max affordable lot") bool Inp_NoMoneyUseMaxAffordableLot = false; // If risk lots exceed margin, send the largest affordable lot

input group "06 - Prop Guard: Daily Loss"
input(name="Enable daily loss guard") bool       Inp_DailyLossGuard        = false;   // Stop new entries once NY trading-day loss cap is reached
input(name="Daily loss limit %") double          Inp_DailyLossLimitPct     = 3.0;     // Loss cap for the 17:00 NY trading day
input(name="Daily loss reference") ENUM_CCT_DAILY_LOSS_BASIS Inp_DailyLossBasis = DAILY_LOSS_INITIAL_BALANCE;
input(name="Daily loss custom reference") double Inp_DailyLossCustomBalance = 0.0;   // Used only when Daily loss reference = Custom
input(name="Daily loss scope") ENUM_CCT_PROP_SCOPE Inp_DailyLossScope      = PROP_SCOPE_ACCOUNT;
input(name="Close EA trades on breach") bool     Inp_DailyLossClosePositions = true;  // Emergency close EA-managed positions on breach
input(name="Block BE/TP after breach") bool      Inp_DailyLossBlockManagement = false; // Leave false unless the firm forbids all EA modifications

input group "07 - Prop Guard: News"
input(name="Enable news blackout") bool          Inp_NewsFilter            = false;   // Calendar/manual blackout; off until configured
input(name="News blackout minutes") double       Inp_NewsBlackoutMinutes   = 5.0;     // Symmetric before/after window, clamped 2.5..7
input(name="Block entries during news") bool     Inp_NewsBlockEntries      = true;
input(name="Block BE/TP during news") bool       Inp_NewsBlockModifications = true;
input(name="News impact level") ENUM_CCT_NEWS_IMPACT Inp_NewsImpactFilter  = NEWS_IMPACT_HIGH;
input(name="Manual news currencies CSV") string  Inp_NewsManualCurrencies  = "USD";  // Extra relevance map for metals, indices, crypto
input(name="Manual news events NY") string       Inp_NewsManualEvents      = "";     // Format: 2026.05.01 08:30 USD;2026.05.01 10:00 USD

input group "08 - Prop Guard: Weekend"
input(name="Enable weekend guard") bool          Inp_WeekendGuard          = false;
input(name="Friday cutoff hour NY") int          Inp_WeekendFridayHour     = 16;
input(name="Friday cutoff minute NY") int        Inp_WeekendFridayMinute   = 45;
input(name="Close minutes before cutoff") int    Inp_WeekendCloseMinutesBefore = 15;
input(name="Block entries near weekend") bool    Inp_WeekendBlockEntries   = true;
input(name="Block BE/TP near weekend") bool      Inp_WeekendBlockModifications = true;
input(name="Force-close EA trades") bool         Inp_WeekendClosePositions = true;
input(name="Weekend guard scope") ENUM_CCT_PROP_SCOPE Inp_WeekendScope     = PROP_SCOPE_SYMBOL;

input group "09 - Trade Management: Minimum TP Time"
input(name="Enable minimum TP hold") bool        Inp_MinOpenTPEnabled      = false;   // Uses virtual TP until the minimum hold time elapses
input(name="Minimum TP hold minutes") int        Inp_MinOpenMinutes        = 3;

input group "10 - Exposure & Lot Caps"
input(name="Lot cap mode") ENUM_CCT_MAX_LOT_MODE Inp_MaxLotMode            = MAX_LOTS_PER_ASSET; // Hard lot ceiling mode
input(name="Max lots general/other") double      Inp_MaxLots               = 4.0;     // Used in Global mode or as the Other fallback
input(name="Max lots FX") double                 Inp_MaxLots_FX            = 4.0;     // Total open FX lots allowed
input(name="Max lots metals") double             Inp_MaxLots_Metals        = 0.3;     // Total open metals lots allowed
input(name="Max lots energy/commodities") double Inp_MaxLots_Commodity     = 0.3;     // Total open energy/commodity lots allowed
input(name="Max lots indices") double            Inp_MaxLots_Indices       = 2.0;     // Total open index lots allowed
input(name="Max lots crypto") double             Inp_MaxLots_Crypto        = 1.0;     // Total open crypto lots allowed
input(name="Max risk per idea %") double         Inp_MaxRiskPerIdeaPct     = 2.0;     // Same symbol+direction open risk cap; 0 disables
input(name="Max exposure %") double              Inp_MaxExposurePct        = 2.0;     // Account-wide open exposure cap; 0 disables

input group "11 - Stop Loss"
input(name="SL anchor source") ENUM_FIB_MODE     Inp_FibMode               = FIB_STANDARD; // Standard or momentum anchor A
input(name="SL fib extension") ENUM_FIB_CFG      Inp_FibCfg                = FIB_CFG_1;    // Extension pair used for the raw SL
input(name="Add spread to SL") bool              Inp_SpreadSL              = true;         // Apply spread when building broker SL

input group "12 - Take Profit"
input(name="TP R multiple preset") ENUM_RR_PRESET Inp_RRPreset             = RR_PRESET_CUSTOM; // Choose a common R multiple from 0.5R to 5.0R
input(name="TP custom R multiple") double        Inp_RRCustom              = 2.10;    // Used only when TP R multiple preset = Custom
input(name="Allow TP extension to CO") bool      Inp_UseCOTP               = false;   // Extend TP to CO when CO is farther away

input group "13 - Breakeven"
input(name="Enable Global BE") bool              Inp_BEGlobal              = true;    // Master breakeven switch
input(name="Tester: force no-BE baseline") bool  Inp_TesterForceNoBE       = false;   // Strategy Tester only: force Global BE and CO BE off
input(name="Global BE trigger preset") ENUM_PERCENT_PRESET Inp_BETriggerPreset = PCT_PRESET_80; // Progress needed before Global BE arms
input(name="Global BE trigger custom %") double  Inp_BETriggerCustomPct    = 80.0;    // Used only when Global BE trigger preset = Custom
input(name="Global BE lock preset") ENUM_PERCENT_PRESET Inp_BEMovePreset   = PCT_PRESET_10; // Portion of entry-to-TP distance locked
input(name="Global BE lock custom %") double     Inp_BEMoveCustomPct       = 10.0;    // Used only when Global BE lock preset = Custom
input(name="Enable CO BE") bool                  Inp_BENYCOEnabled         = true;    // Extra BE gate once CO has matured
input(name="CO BE scope") ENUM_CCT_CO_BE_SCOPE   Inp_BECO_Scope            = CO_BE_SCOPE_NY_AM_ONLY; // Where CO BE is allowed to apply
input(name="CO BE: apply to 1H/1m") bool         Inp_BECO_Apply_1H_M1      = true;    // Used when CO BE scope = Selected models/sessions
input(name="CO BE: apply to 4H/5m") bool         Inp_BECO_Apply_4H_M5      = true;    // Used when CO BE scope = Selected models/sessions
input(name="CO BE: apply to 1D/15m") bool        Inp_BECO_Apply_D1_M15     = true;    // Used when CO BE scope = Selected models/sessions
input(name="CO BE sessions") string              Inp_BECO_Sessions         = "0";     // 0/blank all; 1=LON 2=NY AM 3=NY PM 4=Asia 5=00-01
input(name="CO BE minimum age") ENUM_SECONDS_PRESET Inp_BECOMinSecPreset   = SEC_PRESET_180; // Minimum CO age before CO BE can apply
input(name="CO BE custom age seconds") int       Inp_BECOMinSecCustom      = 180;     // Used only when CO BE minimum age = Custom
input(name="CO BE minimum progress") ENUM_PERCENT_PRESET Inp_BECOMinProgPreset = PCT_PRESET_CUSTOM; // Minimum progress before CO BE can apply
input(name="CO BE custom progress %") double     Inp_BECOMinProgCustomPct  = 40.0;    // Used only when CO BE minimum progress = Custom
input(name="CO BE lock preset") ENUM_BE_CO_LOCK_PRESET Inp_BECOLockPreset  = BECO_LOCK_5_00; // Portion of entry-to-TP distance locked when CO is touched
input(name="CO BE custom lock %") double         Inp_BECOLockCustomPct     = 5.0;     // Used only when CO BE lock preset = Custom

input group "14 - Signals: Routing & Reports"
input(name="Discord: enable") bool               NOTIFY_DISCORD_ENABLED    = false;
input(name="Discord MEC webhook") string         NOTIFY_DISCORD_XAUUSD     = "";
input(name="Discord General-Access webhook") string NOTIFY_DISCORD_XAGUSD  = "";
input(name="Discord Indices webhook") string     NOTIFY_DISCORD_NQ         = "";
input(name="Discord FX webhook") string          NOTIFY_DISCORD_AUDUSD     = "";
input(name="Discord Crypto webhook") string      NOTIFY_DISCORD_BTCUSD     = "";
input(name="Telegram: enable") bool              NOTIFY_TELEGRAM_ENABLED   = false;
input(name="Telegram bot token") string          NOTIFY_TELEGRAM_TOKEN     = "";
input(name="Telegram MEC chat/topic") string     NOTIFY_TELEGRAM_XAUUSD    = "-1003996863325|5";
input(name="Telegram General-Access chat") string NOTIFY_TELEGRAM_XAGUSD   = "-1003996863325";
input(name="Telegram Indices chat/topic") string NOTIFY_TELEGRAM_NQ        = "-1003996863325|2";
input(name="Telegram FX chat/topic") string      NOTIFY_TELEGRAM_AUDUSD    = "-1003996863325|4";
input(name="Telegram Crypto chat/topic") string  NOTIFY_TELEGRAM_BTCUSD    = "-1003996863325|3";
input(name="Screenshot delay ms") int            NOTIFY_SCREENSHOT_DELAY_MS = 800;
input(name="Entry signal defer seconds") int     NOTIFY_ENTRY_DEFER_SECONDS = 8; // Screenshot wait after entry; broker work is not delayed
input(name="Screenshot max LTF bars") int        NOTIFY_SCREENSHOT_MAX_LTF_BARS = 80; // Lower = more horizontally zoomed-in screenshots
input(name="Entry/exit screenshots enabled") bool NOTIFY_SCREENSHOT_ENABLED = true; // BE threshold messages remain text-only
input(name="Reports: enable R summaries") bool   NOTIFY_REPORTS_ENABLED    = false; // Weekly/monthly text-only R reports
input(name="Reports: weekly summary") bool       NOTIFY_REPORT_WEEKLY      = true;  // Sends prior completed week once
input(name="Reports: monthly summary") bool      NOTIFY_REPORT_MONTHLY     = true;  // Sends prior completed calendar month once
input(name="Reports: detailed General-Access") bool NOTIFY_REPORT_GENERAL_DETAILED = false; // False = compact cumulative General report
input(name="Reports: weekly send day") ENUM_NOTIFY_REPORT_DAY NOTIFY_REPORT_WEEKLY_DAY = NOTIFY_REPORT_DAY_SATURDAY; // Weekend day for weekly R report
input(name="Report send time") string            NOTIFY_REPORT_SEND_TIME   = "10:00"; // Preferred report time. Examples: 10, 10:30, 10am, 10:30pm
input(name="Reports: send one test") bool        NOTIFY_REPORT_TEST_NOW    = false; // Sends one test report per day, then leave false

input group "15 - Chart Visuals"
input(name="Show confirmed POIs") bool           Inp_ShowVirgins           = true;   // Draw confirmed virgin wick/POI lines
input(name="Show live candidate POIs") bool      Inp_ShowCandidates        = true;   // Draw candidate lines on the forming HTF bar
input(name="Show dormant POIs") bool             Inp_ShowDormant           = false;  // Diagnostic/reserved visibility
input(name="Show killed POIs") bool              Inp_ShowKilled            = false;  // Diagnostic/reserved visibility
input(name="Show dead counter-bias POIs") bool   Inp_ShowCounterBiasDead   = false;  // Debug-only visibility override
input(name="Debug logging") bool                 Inp_ShowDebug             = false;  // Print [CCT DBG] diagnostics
input(name="Visual reconcile logging") bool      Inp_DebugVisualReconcile  = true;   // Log visual keep/prune behavior
input(name="Visual reconcile log interval seconds") int Inp_VisualReconcileLogSeconds = 300; // Throttle non-deleting reconcile logs
input(name="Tester debug logging") bool          Inp_ForceTesterDebug      = true;   // Force [CCT DBG] diagnostics in Strategy Tester
input(name="Profile timing logs") bool           Inp_ProfileTimingLogs     = false;  // Print slow-path timing/profile diagnostics
input(name="Show execution fib lines") bool      Inp_ShowFibExtensions     = true;   // Draw optional fib extension/SL evidence lines at trigger
input(name="Show pre-trigger C3 IFVG") bool      Inp_ShowPreTriggerC3IFVG  = false;  // Optional debug hint after C1 before final trigger
input(name="Display timezone") ENUM_DISPLAY_TZ_PRESET Inp_DisplayTZPreset  = DISPLAY_TZ_NY; // Display only; engine remains New York based
input(name="Custom display UTC offset hours") double Inp_DisplayUTCOffsetHours = 0.0; // Decimal hours allowed: 5.5=UTC+05:30, -9.5=UTC-09:30

input group "16 - Visual Colors & Dashboard"
input(name="Execution trigger line color") color  Inp_ClrExecTrigger       = C'214,218,224';
input(name="Execution BE line color") color       Inp_ClrExecBE            = C'162,138,88';
input(name="Execution CO line color") color       Inp_ClrExecCO            = C'70,140,210';
input(name="Execution SL zone color") color       Inp_ClrExecSLBox         = C'55,57,68';
input(name="Execution TP zone color") color       Inp_ClrExecTPBox         = C'22,55,120';
input(name="Bullish IFVG color") color            Inp_ClrIFVGBull          = C'12,45,130';
input(name="Bearish IFVG color") color            Inp_ClrIFVGBear          = C'110,15,25';
input(name="Show dashboard") bool                 Inp_ShowDashboard        = false;
input(name="Dashboard theme") ENUM_CCT_DASHBOARD_THEME Inp_DashboardTheme  = DASH_THEME_PLATINUM;
input(name="Dashboard brightness") ENUM_CCT_DASHBOARD_MODE Inp_DashboardMode = DASH_MODE_DARK;

input group "17 - Advanced"
input(name="Lookback") ENUM_CCT_LOOKBACK_PROFILE Inp_VirginLookbackProfile = CCT_LOOKBACK_DEFAULT; // Standard = 3/5/8; Extended = 4/6/10
input(name="Tester time model") ENUM_CCT_TESTER_TIME_MODEL Inp_TesterTimeModel = CCT_TESTER_TIME_AUTO; // Auto fixes local broker/QT tester clocks without changing live charts
input(name="Tester custom UTC offset hours") double Inp_TesterCustomUTCOffsetHours = 0.0; // Used only when Tester time model = Custom
input(name="Tester execution NY shift hours") double Inp_TesterExecutionNYShiftHours = 0.0; // Tester-only session/comment shift; structural POI labels stay untouched
input(name="EA magic number") int              Inp_Magic                 = 202700;  // Broker-side trade ownership tag

int                   g_accMode          = 0;
double                g_riskPct          = 1.0;
double                g_custBal          = 0.0;
double                g_rrPreset         = 2.1;
double                g_beTriggerPct     = 90.0;
double                g_beMovePct        = 50.0;
int                   g_beCoMinSec       = 300;
double                g_beCoMinProgPct   = 20.0;
double                g_beCoLockPct      = 0.5;

int                   g_cctOnlyHours[];
int                   g_cctTsHours[];
int                   g_cctTsExtHours[];
bool                  g_execHourCacheReady = false;
string                g_execHourCacheSignature = ""; // CCT_EXEC_HOUR_CACHE_SIGNATURE_V1

/*
Purpose: Return whether tester research should force all BE paths off at runtime.
Constitution: Tester no-BE baseline research must override raw .set/input values without changing live/demo behavior.
Inputs: None.
Outputs: True in MT5 Strategy Tester.
*/
bool CCTTesterNoBEBaseline()
  {
   return ((bool)MQLInfoInteger(MQL_TESTER) && Inp_TesterForceNoBE);
  }

/*
Purpose: Runtime gate for general breakeven logic.
Constitution: Live/demo obey user input; tester no-BE research mode forces BE off even if MT5 prints raw inputs as true.
Inputs: None.
Outputs: Effective general BE enablement.
*/
bool CCTRuntimeBEGlobalEnabled()
  {
   if(CCTTesterNoBEBaseline())
      return false;

   return Inp_BEGlobal;
  }

/*
Purpose: Runtime gate for NY CO-based breakeven logic.
Constitution: Live/demo obey user input; tester no-BE research mode forces CO-BE off even if MT5 prints raw inputs as true.
Inputs: None.
Outputs: Effective CO-BE enablement.
*/
bool CCTRuntimeBECOEnabled()
  {
   if(CCTTesterNoBEBaseline())
      return false;

   return Inp_BENYCOEnabled;
  }

bool CCTCOBECurrentModelAllowed()
  {
   switch(Inp_TimeframeModel)
     {
      case CCT_TFM_4H_M5:  return Inp_BECO_Apply_4H_M5;
      case CCT_TFM_D1_M15: return Inp_BECO_Apply_D1_M15;
      default:             return Inp_BECO_Apply_1H_M1;
     }
  }

bool CCTCOBELegacyNYWindow(datetime serverTime)
  {
   MqlDateTime ny={};
   TimeToStruct(ToNY(serverTime),ny);
   return (ny.hour>=7 && ny.hour<=18);
  }

bool CCTCOBEApplies(datetime serverTime)
  {
   if(!CCTRuntimeBECOEnabled())
      return false;
   if(serverTime<=0)
      serverTime=CurrentServerTime();

   switch(Inp_BECO_Scope)
     {
      case CO_BE_SCOPE_ALL_SESSIONS:
         return true;

      case CO_BE_SCOPE_SELECTED_MODELS:
         return (CCTCOBECurrentModelAllowed() &&
                 CCTDailySessionCsvAllows(Inp_BECO_Sessions,serverTime));

      case CO_BE_SCOPE_NY_AM_ONLY:
      default:
         // Preserve the legacy NY management window used by the existing EA.
         return CCTCOBELegacyNYWindow(serverTime);
     }
  }

string CCTCOBELabel()
  {
   if(Inp_BECO_Scope==CO_BE_SCOPE_NY_AM_ONLY)
      return "NY BE-CO";
   return "CO BE";
  }

string CCTCOBEScopeText()
  {
   switch(Inp_BECO_Scope)
     {
      case CO_BE_SCOPE_ALL_SESSIONS:    return "All sessions";
      case CO_BE_SCOPE_SELECTED_MODELS: return "Selected models/sessions";
      case CO_BE_SCOPE_NY_AM_ONLY:
      default:                          return "NY AM only";
     }
  }

double                g_propInitialBalance = 0.0;
datetime              g_propDayOpen        = 0;
double                g_propDayStartBalance = 0.0;
double                g_propDayStartEquity = 0.0;
bool                  g_propDailyBreached  = false;
datetime              g_propLastDailyJournal = 0;
datetime              g_propLastNewsJournal = 0;
datetime              g_propLastWeekendJournal = 0;
datetime              g_propLastVirtualTPJournal = 0;
datetime              g_propGuardCacheTime = 0;
bool                  g_propGuardCacheReady = false;
double                g_propCachedPnl = 0.0;
double                g_propCachedLossUsed = 0.0;
double                g_propCachedLossCap = 0.0;
double                g_propCachedLossLeft = 0.0;
bool                  g_propCachedDailyBreached = false;
bool                  g_propCachedEntryNewsBlocked = false;
bool                  g_propCachedMgmtNewsBlocked = false;
bool                  g_propCachedEntryWeekendBlocked = false;
bool                  g_propCachedMgmtWeekendBlocked = false;
string                g_propCachedEntryNewsReason = "";
string                g_propCachedMgmtNewsReason = "";
string                g_cctNewsDashLabel = "";
datetime              g_cctNewsDashTime = 0;
int                   g_cctNewsDashMinutes = -1;
int                   g_cctNewsDashBucket = 0;
datetime              g_cctNewsDashLastSeen = 0;
int                   g_cctDashNewsFilterOverride = -1;          // -1 input, 0 off, 1 on
double                g_cctDashNewsBlackoutMinutesOverride = -1.0; // <0 input, otherwise runtime minutes
int                   g_cctDashMinOpenTPOverride = -1;            // -1 input, 0 off, 1 on
int                   g_cctDashMinOpenMinutesOverride = -1;       // -1 input, otherwise runtime minutes
int                   g_cctDashDailyLossGuardOverride = -1;       // -1 input, 0 off, 1 on
double                g_cctDashDailyLossLimitOverride = -1.0;     // <0 input, otherwise runtime %
int                   g_cctDashDailyLossBasisOverride = -1;       // -1 input, otherwise ENUM_CCT_DAILY_LOSS_BASIS
double                g_cctDashDailyLossCustomOverride = -1.0;    // <0 input, otherwise runtime custom balance
int                   g_cctDashAccModeOverride = -1;              // -1 input, otherwise ENUM_ACC_MODE
double                g_cctDashCustomCapitalOverride = -1.0;      // <0 input, otherwise runtime custom capital
int                   g_cctDashNewsImpactOverride = -1; // -1 = use input; 0 high; 1 medium+high; 2 all
string                g_propCachedEntryWeekendReason = "";
string                g_propCachedMgmtWeekendReason = "";

bool                  g_sigBull          = true;
SIB_STATE             g_sigState         = SS_UNKNOWN_OUTCOME;
double                g_sigLevel         = 0.0;
double                g_sigSlPx          = 0.0;
double                g_sigTpPx          = 0.0;
double                g_sigCoPx          = 0.0;
bool                  g_sigC1            = false;
bool                  g_sigC2            = false;
bool                  g_sigC3            = false;
datetime              g_sigC1Time        = 0;
datetime              g_sigC2Time        = 0;
datetime              g_sigC3Time        = 0;
datetime              g_sigTrigTime      = 0;
datetime              g_sigEntryTime     = 0;
datetime              g_sigBirthTime     = 0;
double                g_sigEntryPx       = 0.0;
int                   g_sigSibIdx        = -1;
string                g_sigModelLabel    = "";
double                g_sigSLDistPips    = 0.0;

MqlRates              g_ltfCache[];
datetime              g_ltfCacheFrom     = 0;
datetime              g_ltfCacheTo       = 0;
datetime              g_ltfCacheLastBar  = 0;
datetime              g_extremeAnchorCacheLastBar = 0;
datetime              g_extremeAnchorHtfTimes[];
int                   g_extremeAnchorDirs[];
datetime              g_extremeAnchorLtfTimes[];

extern MqlRates       g_htf[];
extern int            g_nHtf;
extern int            g_bullBirths[];
extern int            g_nBull;
extern int            g_bearBirths[];
extern int            g_nBear;

/*
Purpose: Resolve an RR preset input to a numeric R multiple.
Constitution: Ch. 22 take-profit configuration and user-facing input surface.
Inputs: preset - selected RR preset, customValue - custom override.
Outputs: Numeric R multiple.
*/
double ResolveRRPresetValue(ENUM_RR_PRESET preset,double customValue)
  {
   switch(preset)
     {
      case RR_PRESET_0_50: return 0.50;
      case RR_PRESET_0_75: return 0.75;
      case RR_PRESET_1_00: return 1.00;
      case RR_PRESET_1_25: return 1.25;
      case RR_PRESET_1_50: return 1.50;
      case RR_PRESET_2_00: return 2.00;
      case RR_PRESET_2_50: return 2.50;
      case RR_PRESET_3_00: return 3.00;
      case RR_PRESET_4_00: return 4.00;
      case RR_PRESET_5_00: return 5.00;
      case RR_PRESET_CUSTOM: return MathMax(0.50,MathMin(5.00,customValue));
     }
   return 2.00;
  }

/*
Purpose: Resolve a percentage preset input to a numeric percentage.
Constitution: Ch. 23 and pass-1 UI reconstruction for preset-driven inputs.
Inputs: preset - selected percentage preset, customValue - custom override.
Outputs: Percentage clamped to 0..100.
*/
double ResolvePercentPresetValue(ENUM_PERCENT_PRESET preset,double customValue)
  {
   double value=0.0;
   switch(preset)
     {
      case PCT_PRESET_10:  value=10.0; break;
      case PCT_PRESET_20:  value=20.0; break;
      case PCT_PRESET_25:  value=25.0; break;
      case PCT_PRESET_33:  value=33.0; break;
      case PCT_PRESET_50:  value=50.0; break;
      case PCT_PRESET_60:  value=60.0; break;
      case PCT_PRESET_75:  value=75.0; break;
      case PCT_PRESET_80:  value=80.0; break;
      case PCT_PRESET_90:  value=90.0; break;
      case PCT_PRESET_100: value=100.0; break;
      case PCT_PRESET_CUSTOM: value=customValue; break;
      default: value=customValue; break;
     }

   if(value<0.0)
      value=0.0;
   if(value>100.0)
      value=100.0;
   return value;
  }

/*
Purpose: Resolve a seconds preset input to a numeric duration in seconds.
Constitution: Ch. 23 and pass-1 UI reconstruction for preset-driven inputs.
Inputs: preset - selected seconds preset, customValue - custom override.
Outputs: Positive integer seconds.
*/
int ResolveSecondsPresetValue(ENUM_SECONDS_PRESET preset,int customValue)
  {
   switch(preset)
     {
      case SEC_PRESET_60: return 60;
      case SEC_PRESET_120: return 120;
      case SEC_PRESET_180: return 180;
      case SEC_PRESET_300: return 300;
      case SEC_PRESET_600: return 600;
      case SEC_PRESET_900: return 900;
      case SEC_PRESET_1800: return 1800;
      case SEC_PRESET_CUSTOM: return MathMax(1,customValue);
     }
   return 300;
  }

/*
Purpose: Resolve a risk preset input to a numeric percentage.
Constitution: Ch. 24 risk configuration and user-facing input surface.
Inputs: preset - selected risk preset, customValue - custom override.
Outputs: Positive risk percentage.
*/
double ResolveRiskPresetValue(ENUM_RISK_PRESET preset,double customValue)
  {
   switch(preset)
     {
      case RISK_PRESET_0_25: return 0.25;
      case RISK_PRESET_0_50: return 0.50;
      case RISK_PRESET_0_75: return 0.75;
      case RISK_PRESET_1_00: return 1.00;
      case RISK_PRESET_1_25: return 1.25;
      case RISK_PRESET_1_50: return 1.50;
      case RISK_PRESET_2_00: return 2.00;
      case RISK_PRESET_CUSTOM: return MathMax(0.01,customValue);
     }
   return 1.00;
  }

double ResolveBECOLockPresetValue(ENUM_BE_CO_LOCK_PRESET preset,double customValue)
  {
   switch(preset)
     {
      case BECO_LOCK_0_25: return 0.25;
      case BECO_LOCK_0_50: return 0.50;
      case BECO_LOCK_1_00: return 1.00;
      case BECO_LOCK_1_50: return 1.50;
      case BECO_LOCK_2_00: return 2.00;
      case BECO_LOCK_3_00: return 3.00;
      case BECO_LOCK_5_00: return 5.00;
      case BECO_LOCK_CUSTOM: return MathMax(0.0,MathMin(20.0,customValue));
     }
   return 0.50;
  }

/*
Purpose: Resolve the configured account base for risk sizing.
Constitution: Risk may be based on balance, equity, or custom capital.
Inputs: None.
Outputs: Account base cash value.
*/
bool CCTOverrideBool(int overrideValue,bool inputValue)
  {
   if(overrideValue>=0)
      return (overrideValue>0);
   return inputValue;
  }

bool CCTEffectiveNewsFilter()
  {
   return CCTOverrideBool(g_cctDashNewsFilterOverride,Inp_NewsFilter);
  }

double CCTEffectiveNewsBlackoutMinutes()
  {
   if(g_cctDashNewsBlackoutMinutesOverride>=0.0)
      return MathMax(1.0,MathMin(30.0,g_cctDashNewsBlackoutMinutesOverride));
   return MathMax(1.0,MathMin(30.0,Inp_NewsBlackoutMinutes));
  }
bool CCTEffectiveNewsBlockEntries()
  {
   return CCTOverrideBool(-1,Inp_NewsBlockEntries);
  }

bool CCTEffectiveNewsBlockModifications()
  {
   return CCTOverrideBool(-1,Inp_NewsBlockModifications);
  }

bool CCTEffectiveMinOpenTPEnabled()
  {
   return CCTOverrideBool(g_cctDashMinOpenTPOverride,Inp_MinOpenTPEnabled);
  }

int CCTEffectiveMinOpenMinutes()
  {
   if(g_cctDashMinOpenMinutesOverride>=0)
      return MathMax(0,g_cctDashMinOpenMinutesOverride);
   return Inp_MinOpenMinutes;
  }

bool CCTEffectiveDailyLossGuard()
  {
   return CCTOverrideBool(g_cctDashDailyLossGuardOverride,Inp_DailyLossGuard);
  }

double CCTEffectiveDailyLossLimitPct()
  {
   if(g_cctDashDailyLossLimitOverride>=0.0)
      return MathMax(0.0,g_cctDashDailyLossLimitOverride);
   return Inp_DailyLossLimitPct;
  }

ENUM_CCT_DAILY_LOSS_BASIS CCTEffectiveDailyLossBasis()
  {
   if(g_cctDashDailyLossBasisOverride>=0 && g_cctDashDailyLossBasisOverride<=2)
      return (ENUM_CCT_DAILY_LOSS_BASIS)g_cctDashDailyLossBasisOverride;
   return Inp_DailyLossBasis;
  }

double CCTEffectiveDailyLossCustomBalance()
  {
   if(g_cctDashDailyLossCustomOverride>=0.0)
      return g_cctDashDailyLossCustomOverride;
   return Inp_DailyLossCustomBalance;
  }

ENUM_ACC_MODE CCTEffectiveAccMode()
  {
   if(g_cctDashAccModeOverride>=0 && g_cctDashAccModeOverride<=2)
      return (ENUM_ACC_MODE)g_cctDashAccModeOverride;
   return Inp_AccMode;
  }

double CCTEffectiveCustomCapital()
  {
   if(g_cctDashCustomCapitalOverride>=0.0)
      return g_cctDashCustomCapitalOverride;
   return Inp_CustBal;
  }

string CCTAccModeLabel()
  {
   ENUM_ACC_MODE m=CCTEffectiveAccMode();
   if(m==ACC_EQUITY)
      return "Equity";
   if(m==ACC_CUSTOM)
      return "Custom";
   return "Balance";
  }

string CCTDailyLossBasisLabel()
  {
   ENUM_CCT_DAILY_LOSS_BASIS b=CCTEffectiveDailyLossBasis();
   if(b==DAILY_LOSS_NY_DAY_START)
      return "17:00 NY day equity";
   if(b==DAILY_LOSS_CUSTOM)
      return "Custom";
   return "Initial bal";
  }
double EffectiveAccountBase()
  {
   ENUM_ACC_MODE mode=CCTEffectiveAccMode();

   if(mode==ACC_EQUITY)
      return AccountInfoDouble(ACCOUNT_EQUITY);

   if(mode==ACC_CUSTOM)
     {
      double custom=CCTEffectiveCustomCapital();
      if(custom>0.0)
         return custom;
     }

   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

/*
Purpose: Return whether the chart symbol uses the CCT Dukascopy custom-symbol server-time model.
Constitution: Tester/data verification must preserve the same NY+7 server clock used by the EA time model.
Inputs: None.
Outputs: True for CCT Dukascopy custom symbols.
*/
bool CCTSymbolUsesDukaServerModel()
  {
   return (StringFind(_Symbol,"_DUKA")>=0);
  }

/*
Purpose: Return the newest locally available bar time for the attached symbol.
Constitution: Offline/custom-symbol verification charts must scan the imported history, not the terminal's unrelated live day.
Inputs: None.
Outputs: Latest known M1/chart bar open time, or 0 when unavailable.
*/
datetime CCTLatestAvailableSymbolBarTime()
  {
   datetime latest=0;
   datetime m1=(datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_LASTBAR_DATE);
   datetime chart=(datetime)SeriesInfoInteger(_Symbol,(ENUM_TIMEFRAMES)_Period,SERIES_LASTBAR_DATE);

   if(m1>latest)
      latest=m1;
   if(chart>latest)
      latest=chart;

   return latest;
  }

/*
Purpose: Return a current server timestamp suitable for timer-based logic.
Constitution: Ch. 1 and visual timing helpers need a stable server clock.
Inputs: None.
Outputs: Current trade-server time, or the imported symbol's latest bar time when live server time is unrelated.
*/
datetime CurrentServerTime()
  {
   datetime now=TimeTradeServer();
   if(now<=0)
      now=TimeCurrent();

   if(!(bool)MQLInfoInteger(MQL_TESTER))
     {
      datetime latest=CCTLatestAvailableSymbolBarTime();
      if(latest>0 && now>latest+(datetime)(3*86400))
        {
         int sec=(int)PeriodSeconds(PERIOD_M1);
         if(sec<=0)
            sec=60;
         return latest+(datetime)sec;
        }
     }

   return now;
  }

/*
Purpose: Trim leading and trailing ASCII spaces from CSV fragments.
Constitution: Ch. 1, Ch. 34 support helper for time/session parsing.
Inputs: value - raw string token.
Outputs: Trimmed string token.
*/
string TrimSpaces(string value)
  {
   int start=0;
   int end=StringLen(value)-1;

   while(start<=end)
     {
      ushort ch=(ushort)StringGetCharacter(value,start);
      if(ch!=' ' && ch!='\t' && ch!='\r' && ch!='\n')
         break;
      start++;
     }

   while(end>=start)
     {
      ushort ch=(ushort)StringGetCharacter(value,end);
      if(ch!=' ' && ch!='\t' && ch!='\r' && ch!='\n')
         break;
      end--;
     }

   if(end<start)
      return "";

   return StringSubstr(value,start,end-start+1);
  }

/*
Purpose: Compute the day-of-month for the nth Sunday in a given month.
Constitution: Ch. 1 for DST-aware New York time conversion.
Inputs: year - four-digit year, month - 1..12, nth - nth Sunday to locate.
Outputs: Day-of-month for the requested Sunday, or 1 on invalid input.
*/
int NthSundayOfMonth(const int year,const int month,const int nth)
  {
   if(nth<1)
      return 1;

   MqlDateTime dt={};
   dt.year=year;
   dt.mon=month;
   dt.day=1;
   dt.hour=0;
   dt.min=0;
   dt.sec=0;

   datetime firstDay=StructToTime(dt);
   TimeToStruct(firstDay,dt);
   int firstDow=dt.day_of_week;
   int firstSunday=1 + ((7-firstDow)%7);
   return firstSunday + (nth-1)*7;
  }

int LastSundayOfMonth(const int year,const int month)
  {
   if(month<1 || month>12)
      return 1;

   MqlDateTime dt={};
   dt.year=year;
   dt.mon=month;
   dt.day=1;
   dt.hour=0;
   dt.min=0;
   dt.sec=0;

   if(month==12)
     {
      dt.year=year+1;
      dt.mon=1;
     }
   else
      dt.mon=month+1;

   datetime firstNext=StructToTime(dt);
   datetime lastDay=firstNext-86400;
   TimeToStruct(lastDay,dt);
   return dt.day - dt.day_of_week;
  }

int EETUTCOffsetSec(datetime utcTime)
  {
   MqlDateTime utc={};
   TimeToStruct(utcTime,utc);
   int year=utc.year;

   MqlDateTime startUtc={};
   startUtc.year=year;
   startUtc.mon=3;
   startUtc.day=LastSundayOfMonth(year,3);
   startUtc.hour=1;

   MqlDateTime endUtc={};
   endUtc.year=year;
   endUtc.mon=10;
   endUtc.day=LastSundayOfMonth(year,10);
   endUtc.hour=1;

   datetime dstStart=StructToTime(startUtc);
   datetime dstEnd=StructToTime(endUtc);
   return (utcTime>=dstStart && utcTime<dstEnd) ? 3*3600 : 2*3600;
  }

int LondonUTCOffsetSec(datetime utcTime)
  {
   MqlDateTime utc={};
   TimeToStruct(utcTime,utc);
   int year=utc.year;

   MqlDateTime startUtc={};
   startUtc.year=year;
   startUtc.mon=3;
   startUtc.day=LastSundayOfMonth(year,3);
   startUtc.hour=1;

   MqlDateTime endUtc={};
   endUtc.year=year;
   endUtc.mon=10;
   endUtc.day=LastSundayOfMonth(year,10);
   endUtc.hour=1;

   datetime dstStart=StructToTime(startUtc);
   datetime dstEnd=StructToTime(endUtc);
   return (utcTime>=dstStart && utcTime<dstEnd) ? 3600 : 0;
  }

int LosAngelesUTCOffsetSec(datetime utcTime)
  {
   MqlDateTime utc={};
   TimeToStruct(utcTime,utc);
   int year=utc.year;

   int marchSunday=NthSundayOfMonth(year,3,2);
   int novemberSunday=NthSundayOfMonth(year,11,1);

   MqlDateTime startUtc={};
   startUtc.year=year;
   startUtc.mon=3;
   startUtc.day=marchSunday;
   startUtc.hour=10;

   MqlDateTime endUtc={};
   endUtc.year=year;
   endUtc.mon=11;
   endUtc.day=novemberSunday;
   endUtc.hour=9;

   datetime dstStart=StructToTime(startUtc);
   datetime dstEnd=StructToTime(endUtc);
   return (utcTime>=dstStart && utcTime<dstEnd) ? -7*3600 : -8*3600;
  }

/*
Purpose: Return the current broker server offset from UTC in seconds.
Constitution: Ch. 1 requires server-time conversion before session logic.
Inputs: None.
Outputs: Broker server minus UTC in seconds.
*/
int CurrentServerUTCOffsetSec()
  {
   datetime serverNow=TimeCurrent();
   datetime tradeNow=TimeTradeServer();
   datetime gmtNow=TimeGMT();

   int currentOff=(int)(serverNow-gmtNow);
   int tradeOff=(tradeNow>0) ? (int)(tradeNow-gmtNow) : 0;

   // CCT_TRADE_SERVER_OFFSET_AUTHORITY_V1
   // TimeCurrent() is last-tick time and can go stale on quiet/offline charts.
   // TimeTradeServer() is the live trade-server clock and must be preferred for live display/session conversion.
   int raw=0;
   if(tradeNow>0)
      raw=tradeOff;
   else if(MathAbs(currentOff)>=60)
      raw=currentOff;

   return (int)(MathRound((double)raw/3600.0)*3600.0);
  }

ENUM_CCT_TESTER_TIME_MODEL CCTEffectiveTesterTimeModel()
  {
   if(Inp_TesterTimeModel!=CCT_TESTER_TIME_AUTO)
      return Inp_TesterTimeModel;

   if(CCTSymbolUsesDukaServerModel())
      return CCT_TESTER_TIME_NY_PLUS_7;

   // Local broker/QT Strategy Tester history is stored on a UTC chart lattice.
   // Keep this narrow so the old Dukascopy custom symbols do not lose their NY+7 model.
   if((bool)MQLInfoInteger(MQL_TESTER))
      return CCT_TESTER_TIME_UTC;

   return CCT_TESTER_TIME_LIVE_OFFSET;
  }

string CCTTesterTimeModelLabel()
  {
   ENUM_CCT_TESTER_TIME_MODEL mode=CCTEffectiveTesterTimeModel();
   switch(mode)
     {
      case CCT_TESTER_TIME_LIVE_OFFSET: return "LIVE_OFFSET";
      case CCT_TESTER_TIME_UTC:         return "UTC";
      case CCT_TESTER_TIME_NY_PLUS_7:   return "NY_PLUS_7";
      case CCT_TESTER_TIME_CUSTOM:      return "CUSTOM";
      case CCT_TESTER_TIME_AUTO:        return "AUTO";
     }
   return "UNKNOWN";
  }

int CCTCustomTesterUTCOffsetSec()
  {
   double hours=MathMax(-14.0,MathMin(14.0,Inp_TesterCustomUTCOffsetHours));
   return (int)MathRound(hours*3600.0);
  }

int CCTTesterExecutionNYShiftSec()
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return 0;
   double hours=MathMax(-12.0,MathMin(12.0,Inp_TesterExecutionNYShiftHours));
   return (int)MathRound(hours*3600.0);
  }

int CCTNYPlus7OffsetForServerTime(datetime serverTime)
  {
   datetime approxUtc=serverTime-(datetime)(2*3600);
   return NYUTCOffsetSec(approxUtc)+7*3600;
  }

int ServerUTCOffsetSec(datetime srv=0)
  {
   int liveOff=CurrentServerUTCOffsetSec();
   if(!(bool)MQLInfoInteger(MQL_TESTER) && !CCTSymbolUsesDukaServerModel())
      return liveOff;

   datetime probe=(srv>0) ? srv : CurrentServerTime();
   if(probe<=0)
      return liveOff;

   ENUM_CCT_TESTER_TIME_MODEL mode=CCTEffectiveTesterTimeModel();
   if(mode==CCT_TESTER_TIME_UTC)
      return 0;
   if(mode==CCT_TESTER_TIME_CUSTOM)
      return CCTCustomTesterUTCOffsetSec();
   if(mode==CCT_TESTER_TIME_NY_PLUS_7)
      return CCTNYPlus7OffsetForServerTime(probe);

   return liveOff;
  }

int ServerUTCOffsetSecForUTC(datetime referenceUtc)
  {
   if(referenceUtc>0 && ((bool)MQLInfoInteger(MQL_TESTER) || CCTSymbolUsesDukaServerModel()))
     {
      ENUM_CCT_TESTER_TIME_MODEL mode=CCTEffectiveTesterTimeModel();
      if(mode==CCT_TESTER_TIME_UTC)
         return 0;
      if(mode==CCT_TESTER_TIME_CUSTOM)
         return CCTCustomTesterUTCOffsetSec();
      if(mode==CCT_TESTER_TIME_NY_PLUS_7)
         return NYUTCOffsetSec(referenceUtc)+7*3600;
     }
   return ServerUTCOffsetSec();
  }

/*
Purpose: Return the New York UTC offset for the supplied UTC instant.
Constitution: Ch. 1.1 New York time is the only time and must be DST-aware.
Inputs: t - UTC instant.
Outputs: -4*3600 during EDT, -5*3600 otherwise.
*/
int NYUTCOffsetSec(datetime t)
  {
   MqlDateTime utc={};
   TimeToStruct(t,utc);
   int year=utc.year;

   int marchSunday=NthSundayOfMonth(year,3,2);
   int novemberSunday=NthSundayOfMonth(year,11,1);

   MqlDateTime startUtc={};
   startUtc.year=year;
   startUtc.mon=3;
   startUtc.day=marchSunday;
   startUtc.hour=7;
   startUtc.min=0;
   startUtc.sec=0;

   MqlDateTime endUtc={};
   endUtc.year=year;
   endUtc.mon=11;
   endUtc.day=novemberSunday;
   endUtc.hour=6;
   endUtc.min=0;
   endUtc.sec=0;

   datetime dstStartUtc=StructToTime(startUtc);
   datetime dstEndUtc=StructToTime(endUtc);

   if(t>=dstStartUtc && t<dstEndUtc)
      return -4*3600;

   return -5*3600;
  }

/*
Purpose: Convert broker server time into New York local time.
Constitution: Ch. 1.1 and Ch. 1.2 session and reset rules run in NY time.
Inputs: srv - broker server datetime.
Outputs: Equivalent New York datetime.
*/
datetime ToNY(datetime srv)
  {
   datetime utc=srv-ServerUTCOffsetSec(srv);
   return utc + NYUTCOffsetSec(utc);
  }

datetime ToExecutionNY(datetime srv)
  {
   if(srv<=0)
      return 0;
   return ToNY(srv)+(datetime)CCTTesterExecutionNYShiftSec();
  }

datetime ToUTC(datetime srv)
  {
   if(srv<=0)
      return 0;
   return srv-ServerUTCOffsetSec(srv);
  }

int DisplayUTCOffsetSec(datetime utcTime)
  {
   switch(Inp_DisplayTZPreset)
     {
      case DISPLAY_TZ_UTC:    return 0;
      case DISPLAY_TZ_LONDON: return LondonUTCOffsetSec(utcTime);
      case DISPLAY_TZ_LAGOS:  return 3600;
      case DISPLAY_TZ_LAX:    return LosAngelesUTCOffsetSec(utcTime);
      case DISPLAY_TZ_CHICAGO:return NYUTCOffsetSec(utcTime)-3600;
      case DISPLAY_TZ_DUBAI:  return 4*3600;
      case DISPLAY_TZ_TOKYO:  return 9*3600;
      case DISPLAY_TZ_MUMBAI: return 5*3600+30*60;
      case DISPLAY_TZ_KATHMANDU: return 5*3600+45*60;
      case DISPLAY_TZ_MARQUESAS: return -(9*3600+30*60);
      case DISPLAY_TZ_CUSTOM:
        {
         double h=MathMax(-14.0,MathMin(14.0,Inp_DisplayUTCOffsetHours));
         return (int)MathRound(h*3600.0);
        }
      case DISPLAY_TZ_NY:
      default:                return NYUTCOffsetSec(utcTime);
     }
  }

datetime ToDisplay(datetime srv)
  {
   if(srv<=0)
      return 0;
   datetime utc=ToUTC(srv);
   return utc + DisplayUTCOffsetSec(utc);
  }

bool DisplayTZIsNY()
  {
   return (Inp_DisplayTZPreset==DISPLAY_TZ_NY);
  }

string DisplayTZLabel()
  {
   switch(Inp_DisplayTZPreset)
     {
      case DISPLAY_TZ_UTC:    return "UTC";
      case DISPLAY_TZ_LONDON: return "LON";
      case DISPLAY_TZ_LAGOS:  return "WAT";
      case DISPLAY_TZ_LAX:    return "LAX";
      case DISPLAY_TZ_CHICAGO:return "CHI";
      case DISPLAY_TZ_DUBAI:  return "DXB";
      case DISPLAY_TZ_TOKYO:  return "TYO";
      case DISPLAY_TZ_MUMBAI: return "IST";
      case DISPLAY_TZ_KATHMANDU: return "NPT";
      case DISPLAY_TZ_MARQUESAS: return "MART";
      case DISPLAY_TZ_CUSTOM:
        {
         int offset=(int)MathRound(MathMax(-14.0,MathMin(14.0,Inp_DisplayUTCOffsetHours))*3600.0);
         return "UTC" + CCTOffsetSuffix(offset);
        }
      case DISPLAY_TZ_NY:
      default:                return "NY";
     }
  }

string CCTOffsetSuffix(int offsetSec)
  {
   string sign=(offsetSec>=0) ? "+" : "-";
   int absSec=(int)MathAbs(offsetSec);
   int hh=absSec/3600;
   int mm=(absSec%3600)/60;
   if(mm==0)
      return sign + IntegerToString(hh);
   return StringFormat("%s%02d:%02d",sign,hh,mm);
  }

string CCTLocalDateTime(datetime localTime,bool includeSeconds,bool compact=false)
  {
   if(localTime<=0)
      return "-";
   MqlDateTime dt={};
   TimeToStruct(localTime,dt);
   if(compact)
     {
      if(includeSeconds)
         return StringFormat("%02d/%02d %02d:%02d:%02d",dt.mon,dt.day,dt.hour,dt.min,dt.sec);
      return StringFormat("%02d/%02d %02d:%02d",dt.mon,dt.day,dt.hour,dt.min);
     }
   if(includeSeconds)
      return StringFormat("%04d.%02d.%02d %02d:%02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec);
   return StringFormat("%04d.%02d.%02d %02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min);
  }

string CCTLocalClock(datetime localTime,bool includeSeconds)
  {
   if(localTime<=0)
      return "-";
   MqlDateTime dt={};
   TimeToStruct(localTime,dt);
   if(includeSeconds)
      return StringFormat("%02d:%02d:%02d",dt.hour,dt.min,dt.sec);
   return StringFormat("%02d:%02d",dt.hour,dt.min);
  }

string CCTNYTimeStamp(datetime srv,bool includeSeconds)
  {
   if(srv<=0)
      return "-";
   return "NY " + CCTLocalDateTime(ToNY(srv),includeSeconds,false);
  }

string CCTDisplayTimeStamp(datetime srv,bool includeSeconds)
  {
   if(srv<=0)
      return "-";
   return DisplayTZLabel() + " " + CCTLocalDateTime(ToDisplay(srv),includeSeconds,false);
  }

string CCTEventTimeStamp(datetime srv,bool includeSeconds)
  {
   if(srv<=0)
      return "-";
   if(DisplayTZIsNY())
      return CCTNYTimeStamp(srv,includeSeconds);
   return CCTNYTimeStamp(srv,includeSeconds) + " | " + CCTDisplayTimeStamp(srv,includeSeconds);
  }

string CCTEventClockStamp(datetime srv,bool includeSeconds)
  {
   if(srv<=0)
      return "-";
   string out="NY " + CCTLocalClock(ToNY(srv),includeSeconds);
   if(!DisplayTZIsNY())
      out += " | " + DisplayTZLabel() + " " + CCTLocalClock(ToDisplay(srv),includeSeconds);
   return out;
  }

string CCTTooltipTimeStamp(datetime srv,bool includeSeconds)
  {
   if(srv<=0)
      return "-";
   return CCTLocalDateTime(ToDisplay(srv),includeSeconds,true);
  }

string CCTTooltipClockStamp(datetime srv,bool includeSeconds)
  {
   if(srv<=0)
      return "-";
   return CCTLocalClock(ToDisplay(srv),includeSeconds);
  }

string CCTJournalTimeStamp(datetime srv)
  {
   return CCTEventTimeStamp(srv,true);
  }

string CCTCommentTimeStamp(datetime srv)
  {
   if(srv<=0)
      return "N0000-0000";
   datetime localTime=DisplayTZIsNY() ? ToNY(srv) : ToDisplay(srv);
   MqlDateTime dt={};
   TimeToStruct(localTime,dt);
   string tag=DisplayTZIsNY() ? "N" : "D";
   return StringFormat("%s%02d%02d-%02d%02d",tag,dt.mon,dt.day,dt.hour,dt.min);
  }

string CCTNYHourLabel(datetime srv)
  {
   if(srv<=0)
      return "NY --:--";
   MqlDateTime ny={};
   TimeToStruct(ToNY(srv),ny);
   return StringFormat("NY %02d:00",ny.hour);
  }

/*
Purpose: Return the New York UTC offset that applies at a local NY midnight.
Constitution: Ch. 1.1 and Ch. 1.2 daily reset occurs at NY midnight.
Inputs: nyMidnight - NY-local midnight datetime.
Outputs: UTC offset in seconds that applies at that midnight.
*/
int NYOffsetAtMidnight(datetime nyMidnight)
  {
   MqlDateTime ny={};
   TimeToStruct(nyMidnight,ny);
   int marchSunday=NthSundayOfMonth(ny.year,3,2);
   int novemberSunday=NthSundayOfMonth(ny.year,11,1);

   if(ny.mon<3 || ny.mon>11)
      return -5*3600;
   if(ny.mon>3 && ny.mon<11)
      return -4*3600;
   if(ny.mon==3)
     {
      if(ny.day<=marchSunday)
         return -5*3600;
      return -4*3600;
     }
   if(ny.day<=novemberSunday)
      return -4*3600;
   return -5*3600;
  }

/*
Purpose: Return the server-time datetime for the current NY midnight.
Constitution: Ch. 1.2 daily reset boundary is NY midnight.
Inputs: None.
Outputs: Current NY midnight converted back to broker server time.
*/

#define CCT_NY1700_STRUCTURAL_TIME_LATTICE_V1 1
#define CCT_1H_SERVER_NY_STRUCTURAL_TIME_V1 1

bool CCTUseChartUTCStructuralTime()
  {
   // 1H/M1 DUKA custom-symbol execution is imported on the broker/server-time lattice.
   // For 1H births and execution ownership, raw chart timestamps must convert through
   // the server->UTC->NY model; otherwise 2026.01.07 06:00 server is labelled NY 01:00
   // instead of the expected NY 23:00 previous day.
   if(Inp_TimeframeModel==CCT_TFM_1H_M1)
      return false;

   // Higher structural models keep the chart-UTC lattice used by the NY 17:00 structural-day code.
   return ((bool)MQLInfoInteger(MQL_TESTER) || CCTSymbolUsesDukaServerModel());
  }

datetime CCTStructuralNYLocalForTime(datetime serverTime)
  {
   if(serverTime<=0)
      return 0;

   if(CCTUseChartUTCStructuralTime())
     {
      datetime utc=serverTime;
      return utc+(datetime)NYUTCOffsetSec(utc);
     }

   return ToNY(serverTime);
  }

datetime CCTStructuralTimeFromNYLocal(datetime nyLocal)
  {
   if(nyLocal<=0)
      return 0;

   datetime guessUtc=nyLocal+(datetime)(5*3600);
   int nyOffset=NYUTCOffsetSec(guessUtc);
   datetime utc=nyLocal-(datetime)nyOffset;
   int correctedOffset=NYUTCOffsetSec(utc);
   if(correctedOffset!=nyOffset)
      utc=nyLocal-(datetime)correctedOffset;

   if(CCTUseChartUTCStructuralTime())
      return utc;

   return utc+(datetime)ServerUTCOffsetSecForUTC(utc);
  }

datetime CCTStructuralDayOpenForTime(datetime serverTime)
  {
   if(serverTime<=0)
      return 0;

   datetime nyTime=CCTStructuralNYLocalForTime(serverTime);
   MqlDateTime ny={};
   TimeToStruct(nyTime,ny);

   if(ny.hour<17)
     {
      nyTime-=(datetime)86400;
      TimeToStruct(nyTime,ny);
     }

   ny.hour=17;
   ny.min=0;
   ny.sec=0;
   return CCTStructuralTimeFromNYLocal(StructToTime(ny));
  }

datetime CCTShiftStructuralDayOpen(datetime structuralDayOpen,int dayDelta)
  {
   if(structuralDayOpen<=0)
      return 0;

   MqlDateTime ny={};
   TimeToStruct(CCTStructuralNYLocalForTime(structuralDayOpen),ny);
   ny.hour=17;
   ny.min=0;
   ny.sec=0;

   datetime shiftedNy=StructToTime(ny)+(datetime)(dayDelta*86400);
   return CCTStructuralTimeFromNYLocal(shiftedNy);
  }

datetime CCTTodayStructuralOpen()
  {
   return CCTStructuralDayOpenForTime(CurrentServerTime());
  }

int CCTModelHTFSeconds()
  {
   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return 86400;

   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return 4*3600;

   // CCT_MODEL_HTF_SECONDS_RECURSION_REPAIR_V3
   // Default 1H/M1 must use the native selected HTF period length.
   // Do not call CCTModelHTFSeconds() from inside itself.
   int htfSec=(int)PeriodSeconds(HTF());
   if(htfSec<=0)
      htfSec=3600;

   return htfSec;
  }

int CCTIFVGMaxAgeSeconds()
  {
   // CCT_IFVG_LOOKBACK_MODE_V1
   // Standard keeps the original model-scaled rule:
   // 1H/1m = 90m, 4H/5m = 6h, 1D/15m = 36h.
   // Conservative is half of Standard. Disabled removes the age filter.
   int htfSec=CCTModelHTFSeconds();
   if(htfSec<=0)
      htfSec=3600;

   long scaled=((long)htfSec*3)/2;
   if(scaled<1)
      scaled=5400;

   if(Inp_IFVGLookback==IFVG_LOOKBACK_DISABLED)
      return INT_MAX/4;

   if(Inp_IFVGLookback==IFVG_LOOKBACK_CONSERVATIVE)
      scaled=MathMax(1,scaled/2);

   return (int)scaled;
  }

datetime CCTModelHTFOpenForTime(datetime eventTime)
  {
   if(eventTime<=0)
      return 0;

   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return CCTStructuralDayOpenForTime(eventTime);

   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
     {
      datetime dayOpen=CCTStructuralDayOpenForTime(eventTime);
      if(dayOpen<=0)
         return 0;

      int htfSec=4*3600;
      long diff=(long)(eventTime-dayOpen);
      if(diff<0)
         diff=0;
      int block=(int)(diff/htfSec);
      if(block<0)
         block=0;
      if(block>5)
         block=5;
      return dayOpen+(datetime)(block*htfSec);
     }

   int shift=iBarShift(_Symbol,HTF(),eventTime,false);
   if(shift<0)
      return 0;
   return iTime(_Symbol,HTF(),shift);
  }

datetime CCTCurrentHTFBarOpenMarker()
  {
   if(Inp_TimeframeModel==CCT_TFM_D1_M15 || Inp_TimeframeModel==CCT_TFM_4H_M5)
     {
      ENUM_TIMEFRAMES src=(Inp_TimeframeModel==CCT_TFM_D1_M15 ? PERIOD_M15 : PERIOD_M5);
      datetime probe=(datetime)SeriesInfoInteger(_Symbol,src,SERIES_LASTBAR_DATE);
      if(probe<=0)
         probe=CurrentServerTime();
      return CCTModelHTFOpenForTime(probe);
     }

   return (datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
  }

datetime CCTVisualDayOpenForServerTime(datetime serverTime)
  {
   return CCTStructuralDayOpenForTime(serverTime);
  }

datetime CCTVisualTodayOpen()
  {
   return CCTTodayStructuralOpen();
  }

datetime CCTVisualNextDayOpen(datetime currentOpen)
  {
   if(currentOpen<=0)
      return 0;
   return CCTShiftStructuralDayOpen(currentOpen,1);
  }
datetime TodayOpen()
  {
   // CCT_NY1700_STRUCTURAL_TIME_LATTICE_V1
   // Standard CCT day reset: 17:00 NY -> 17:00 NY.
   return CCTTodayStructuralOpen();
  }

/*
Purpose: Classify the current NY session family from broker time.
Constitution: Ch. 1.3 defines the session windows in NY time.
Inputs: None.
Outputs: "London", "NY AM", "Asia", or "Off-session".
*/
string GetCurrentSession()
  {
   MqlDateTime ny={};
   TimeToStruct(ToNY(CurrentServerTime()),ny);

   if(ny.hour>=2 && ny.hour<6)
      return "London";
   if(ny.hour>=7 && ny.hour<=11)
      return "NY AM";
   if(ny.hour>=20 && ny.hour<=23)
      return "Asia";
   return "Off-session";
  }

/*
Purpose: Check whether an integer hour already exists in the target array.
Constitution: Ch. 8 and Ch. 36 support helper for execution-hour gating.
Inputs: hourValue - hour to test, arr - parsed hour list.
Outputs: True if the hour already exists in the array.
*/
bool HasHour(const int hourValue,int &arr[])
  {
   int count=ArraySize(arr);
   for(int i=0;i<count;i++)
     {
      if(arr[i]==hourValue)
         return true;
     }
   return false;
  }

/*
Purpose: Append parsed hours from one CSV string into an existing unique hour array.
Constitution: Ch. 8 and Ch. 36.3 execution-hour authorization is config-driven.
Inputs: csv - source hour CSV, arr - destination unique hour array.
Outputs: arr extended with any new valid hours.
*/
void AppendHourSlots(string csv,int &arr[])
  {
   string parts[];
   int n=StringSplit(csv,',',parts);
   if(n<1)
      return;

   for(int i=0;i<n;i++)
     {
      string token=TrimSpaces(parts[i]);
      if(token=="")
         continue;

      int hourValue=(int)StringToInteger(token);
      if(hourValue<0 || hourValue>23)
         continue;
      if(HasHour(hourValue,arr))
         continue;

      int newSize=ArraySize(arr)+1;
      ArrayResize(arr,newSize);
      arr[newSize-1]=hourValue;
     }
  }

/*
Purpose: Sort an execution-hour array ascending in-place.
Constitution: Ch. 8 and Ch. 36.3 execution authorization uses ordered NY hours.
Inputs: arr - hour array to sort.
Outputs: arr sorted ascending.
*/
void SortHoursAsc(int &arr[])
  {
   int n=ArraySize(arr);
   for(int i=1;i<n;i++)
     {
      int key=arr[i];
      int j=i-1;
      while(j>=0 && arr[j]>key)
        {
         arr[j+1]=arr[j];
         j--;
        }
      arr[j+1]=key;
     }
  }

/*
Purpose: Collect the full unique execution-hour union across all configured model lists.
Constitution: Ch. 8 and Ch. 36.3 model type is runtime-determined, but hour selection still gates authority.
Inputs: hours - output NY-hour array.
Outputs: True when at least one execution hour is configured.
*/
bool CollectExecHours(int &hours[])
  {
   ArrayResize(hours,0);
   AppendHourSlots(InpCCTOnly,hours);
   AppendHourSlots(InpCCTTS,hours);
   AppendHourSlots(InpCCTTSExt,hours);
   SortHoursAsc(hours);
   return (ArraySize(hours)>0);
  }

/*
Purpose: Parse a comma-separated list of NY execution hours into an int array.
Constitution: Ch. 8 and Ch. 9 execution-hour authorization.
Inputs: csv - comma-separated hour list, arr - output array.
Outputs: True if at least one valid hour was parsed.
*/
bool ParseHourSlots(string csv,int &arr[])
  {
   ArrayResize(arr,0);
   AppendHourSlots(csv,arr);
   return (ArraySize(arr)>0);
  }

string ExecutionHourCacheSignature()
  {
   return InpCCTOnly + "|" + InpCCTTS + "|" + InpCCTTSExt;
  }

void RefreshExecutionHourCache()
  {
   ArrayResize(g_cctOnlyHours,0);
   ArrayResize(g_cctTsHours,0);
   ArrayResize(g_cctTsExtHours,0);

   AppendHourSlots(InpCCTOnly,g_cctOnlyHours);
   AppendHourSlots(InpCCTTS,g_cctTsHours);
   AppendHourSlots(InpCCTTSExt,g_cctTsExtHours);

   SortHoursAsc(g_cctOnlyHours);
   SortHoursAsc(g_cctTsHours);
   SortHoursAsc(g_cctTsExtHours);
   g_execHourCacheSignature=ExecutionHourCacheSignature();
   g_execHourCacheReady=true;
  }

void EnsureExecutionHourCacheFresh()
  {
   string sig=ExecutionHourCacheSignature();
   if(!g_execHourCacheReady || sig!=g_execHourCacheSignature)
      RefreshExecutionHourCache();
  }

bool CachedCCTHour(int nyHour)
  {
   EnsureExecutionHourCacheFresh();
   return HasHour(nyHour,g_cctOnlyHours);
  }

bool CachedTSHour(int nyHour)
  {
   EnsureExecutionHourCacheFresh();
   return HasHour(nyHour,g_cctTsHours);
  }

bool CachedExtHour(int nyHour)
  {
   EnsureExecutionHourCacheFresh();
   return HasHour(nyHour,g_cctTsExtHours);
  }

/*
Purpose: Check whether the supplied NY hour is authorized by any execution list.
Constitution: Ch. 8.1 execution-hour gate.
Inputs: nyHour - NY hour to test.
Outputs: True if the hour is present in any configured execution list.
*/

#define CCT_MODEL_AWARE_AUTH_V1 1

bool CCTModelCCTAuthAllows(datetime serverTime)
  {
   if(!Inp_SessionFilter)
      return true;

   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return CCT4HBlockCsvAllows(Inp_4H_CCT_Blocks,serverTime) &&
             (!Inp_4H_UseDailyDayGuard || CCTDailyDayCsvAllows(Inp_Daily_CCT_Days,serverTime));

   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return CCTDailyCsvAllows(Inp_Daily_CCT_Days,Inp_Daily_CCT_Sessions,serverTime);

   MqlDateTime ny={};
   TimeToStruct(ToExecutionNY(serverTime),ny);
   return CachedCCTHour(ny.hour) &&
          (!Inp_1H_UseDailyDayGuard || CCTDailyDayCsvAllows(Inp_Daily_CCT_Days,serverTime));
  }

bool CCTModelTSAuthAllows(datetime serverTime)
  {
   if(!Inp_SessionFilter)
      return true;

   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return CCT4HBlockCsvAllows(Inp_4H_TS_Blocks,serverTime) &&
             (!Inp_4H_UseDailyDayGuard || CCTDailyDayCsvAllows(Inp_Daily_CCT_Days,serverTime));

   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return CCTDailyCsvAllows(Inp_Daily_TS_Days,Inp_Daily_TS_Sessions,serverTime);

   MqlDateTime ny={};
   TimeToStruct(ToExecutionNY(serverTime),ny);
   return CachedTSHour(ny.hour) &&
          (!Inp_1H_UseDailyDayGuard || CCTDailyDayCsvAllows(Inp_Daily_CCT_Days,serverTime));
  }

bool CCTModelExtAuthAllows(datetime serverTime)
  {
   if(!Inp_SessionFilter)
      return true;

   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return CCT4HBlockCsvAllows(Inp_4H_TSExt_Blocks,serverTime) &&
             (!Inp_4H_UseDailyDayGuard || CCTDailyDayCsvAllows(Inp_Daily_CCT_Days,serverTime));

   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return CCTDailyCsvAllows(Inp_Daily_TSExt_Days,Inp_Daily_TSExt_Sessions,serverTime);

   MqlDateTime ny={};
   TimeToStruct(ToExecutionNY(serverTime),ny);
   return CachedExtHour(ny.hour) &&
          (!Inp_1H_UseDailyDayGuard || CCTDailyDayCsvAllows(Inp_Daily_CCT_Days,serverTime));
  }

bool CCTModelAnyAuthAllows(datetime serverTime)
  {
   return (CCTModelCCTAuthAllows(serverTime) ||
           CCTModelTSAuthAllows(serverTime) ||
           CCTModelExtAuthAllows(serverTime));
  }

bool CCTModelTSOrExtAuthAllows(datetime serverTime)
  {
   return (CCTModelTSAuthAllows(serverTime) || CCTModelExtAuthAllows(serverTime));
  }

bool CCTModelWindowHasAnyAuth(datetime fromTime,datetime toTime)
  {
   if(!Inp_SessionFilter)
      return true;

   if(fromTime<=0 || toTime<=fromTime)
      return false;

   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
     {
      for(datetime t=fromTime;t<toTime;t+=(datetime)3600)
        {
         if(CCTModelAnyAuthAllows(t))
            return true;
        }

      return CCTModelAnyAuthAllows(toTime-1);
     }

   return CCTModelAnyAuthAllows(fromTime);
  }
bool IsExecHour(int nyHour)
  {
   return (CachedCCTHour(nyHour) || CachedTSHour(nyHour) || CachedExtHour(nyHour));
  }

/*
Purpose: Return the configured execution-hour label for a NY hour.
Constitution: Ch. 8 and Ch. 9 execution-hour families.
Inputs: nyHour - NY hour to classify.
Outputs: "CCT", "CCT+TS", "CCT+TS Ext", or "Unset".
*/
string ExecHourLabel(int nyHour)
  {
   if(CachedCCTHour(nyHour))
      return "CCT";
   if(CachedTSHour(nyHour))
      return "CCT+TS";
   if(CachedExtHour(nyHour))
      return "CCT+TS Ext";

   return "Unset";
  }

/*
Purpose: Return the structural HTF used by the 1H/M1 model.
Constitution: Ch. 2.1 HTF is the structural frame.
Inputs: None.
Outputs: PERIOD_H1.
*/
string CCTTimeframeModelLabel()
  {
   switch(Inp_TimeframeModel)
     {
      case CCT_TFM_4H_M5:  return "4H/M5";
      case CCT_TFM_D1_M15: return "D1/M15";
      default:             return "1H/M1";
     }
  }

double CCTVirginLookbackYearsForModel()
  {
   if(Inp_VirginLookbackProfile==CCT_LOOKBACK_ENHANCED)
     {
      switch(Inp_TimeframeModel)
        {
         case CCT_TFM_4H_M5:  return 6.0;
         case CCT_TFM_D1_M15: return 10.0;
         default:             return 4.0;
        }
     }

   switch(Inp_TimeframeModel)
     {
      case CCT_TFM_4H_M5:  return 5.0;
      case CCT_TFM_D1_M15: return 8.0;
      default:             return 3.0;
     }
  }

ENUM_TIMEFRAMES CCTSelectedHTF()
  {
   switch(Inp_TimeframeModel)
     {
      case CCT_TFM_4H_M5:  return PERIOD_H4;
      case CCT_TFM_D1_M15: return PERIOD_D1;
      default:             return PERIOD_H1;
     }
  }

ENUM_TIMEFRAMES CCTSelectedLTF()
  {
   switch(Inp_TimeframeModel)
     {
      case CCT_TFM_4H_M5:  return PERIOD_M5;
      case CCT_TFM_D1_M15: return PERIOD_M15;
      default:             return PERIOD_M1;
     }
  }

#define CCT_CSV_AUTH_HELPERS_V1 1

string CCTTrimString(string value)
  {
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

bool CCTCsvHasInt(string csv,int value)
  {
   csv=CCTTrimString(csv);
   if(csv=="")
      return false;

   string parts[];
   int n=StringSplit(csv,StringGetCharacter(",",0),parts);
   for(int i=0;i<n;i++)
     {
      string token=CCTTrimString(parts[i]);
      if(token=="")
         continue;
      if((int)StringToInteger(token)==value)
         return true;
     }

   return false;
  }

bool CCTCsvBlankOrZeroMeansAll(string csv)
  {
   csv=CCTTrimString(csv);
   if(csv=="")
      return true;
   return CCTCsvHasInt(csv,0);
  }

int CCTDailyConfiguredDayNumber(datetime serverTime)
  {
   datetime nyTime=CCTStructuralNYLocalForTime(serverTime);
   MqlDateTime ny={};
   TimeToStruct(nyTime,ny);

   if(ny.hour>=17)
     {
      nyTime+=(datetime)86400;
      TimeToStruct(nyTime,ny);
     }

   if(Inp_Daily_WeekStart==CCT_WEEK_START_MONDAY)
     {
      if(ny.day_of_week==0)
         return 7;
      return ny.day_of_week;
     }

   return ny.day_of_week+1;
  }

bool CCTDailyDayCsvAllows(string csv,datetime serverTime)
  {
   if(CCTCsvBlankOrZeroMeansAll(csv))
      return true;
   return CCTCsvHasInt(csv,CCTDailyConfiguredDayNumber(serverTime));
  }

bool CCTDailySessionCodeAllows(const int sessionCode,const int nyHour)
  {
   // Session codes remain NY clock-hour based inside the 17:00 NY trading day.
   switch(sessionCode)
     {
      case 1: return (nyHour>=2  && nyHour<6);   // London
      case 2: return (nyHour>=7  && nyHour<11);  // NY AM
      case 3: return (nyHour>=12 && nyHour<16);  // NY PM
      case 4: return (nyHour>=20 && nyHour<23);  // Asia
      case 5: return (nyHour>=0  && nyHour<2);   // Optional 00:00-01:59 block
     }

   return false;
  }

bool CCTDailySessionCsvAllows(string csv,datetime serverTime)
  {
   if(CCTCsvBlankOrZeroMeansAll(csv))
      return true;

   MqlDateTime ny={};
   TimeToStruct(CCTStructuralNYLocalForTime(serverTime),ny);

   string parts[];
   int n=StringSplit(csv,StringGetCharacter(",",0),parts);
   for(int i=0;i<n;i++)
     {
      string token=CCTTrimString(parts[i]);
      if(token=="")
         continue;
      int code=(int)StringToInteger(token);
      if(CCTDailySessionCodeAllows(code,ny.hour))
         return true;
     }

   return false;
  }

bool CCTDailyCsvAllows(string dayCsv,string sessionCsv,datetime serverTime)
  {
   return (CCTDailyDayCsvAllows(dayCsv,serverTime) && CCTDailySessionCsvAllows(sessionCsv,serverTime));
  }

int CCT4HUserBlockCode(datetime serverTime)
  {
   datetime htfOpen=CCTModelHTFOpenForTime(serverTime);
   if(htfOpen<=0)
      htfOpen=serverTime;

   MqlDateTime ny={};
   TimeToStruct(CCTStructuralNYLocalForTime(htfOpen),ny);

   // User-facing synthetic 4H block codes: 17,21,1,5,9,13.
   return ny.hour;
  }

bool CCT4HBlockCsvAllows(string csv,datetime serverTime)
  {
   if(CCTCsvBlankOrZeroMeansAll(csv))
      return true;
   return CCTCsvHasInt(csv,CCT4HUserBlockCode(serverTime));
  }

ENUM_TIMEFRAMES HTF()
  {
   return CCTSelectedHTF();
  }

/*
Purpose: Return the execution LTF used by the 1H/M1 model.
Constitution: Ch. 2.2 LTF is the execution frame.
Inputs: None.
Outputs: PERIOD_M1.
*/
ENUM_TIMEFRAMES LTF()
  {
   return CCTSelectedLTF();
  }

/*
Purpose: Return the full-content timeframe visibility mask for 1H/M1 objects.
Constitution: Ch. 27.6 explicit OBJPROP_TIMEFRAMES mask for full-content objects.
Inputs: None.
Outputs: Bitmask covering M1 through H1.
*/
long TFMask_Full()
  {
   return OBJ_PERIOD_M1|OBJ_PERIOD_M2|OBJ_PERIOD_M3|OBJ_PERIOD_M4|OBJ_PERIOD_M5|
          OBJ_PERIOD_M6|OBJ_PERIOD_M10|OBJ_PERIOD_M12|OBJ_PERIOD_M15|OBJ_PERIOD_M20|
          OBJ_PERIOD_M30|OBJ_PERIOD_H1;
  }

/*
Purpose: Return the LTF-only timeframe visibility mask for detail objects.
Constitution: Ch. 27.6 explicit OBJPROP_TIMEFRAMES mask for LTF detail.
Inputs: None.
Outputs: Bitmask covering M1 through M5.
*/
long TFMask_LTFOnly()
  {
   return OBJ_PERIOD_M1|OBJ_PERIOD_M2|OBJ_PERIOD_M3|OBJ_PERIOD_M4|OBJ_PERIOD_M5;
  }

/*
Purpose: Return the timeframe visibility mask for all periods below the HTF.
Constitution: Latest user clarification that CO and TS object families should appear on every timeframe below H1.
Inputs: None.
Outputs: Bitmask covering all chart periods below H1.
*/
long TFMask_BelowHTF()
  {
   return TFMask_Full() & ~OBJ_PERIOD_H1;
  }

/*
Purpose: Return the exact LTF visibility mask for precision-anchored dual objects.
Constitution: Backup-proven MT5 anchoring pattern where the exact LTF object is shown only on the model LTF.
Inputs: None.
Outputs: Bitmask for the exact configured LTF period.
*/
long TFMask_ExactLTF()
  {
   switch(LTF())
     {
      case PERIOD_M1:  return OBJ_PERIOD_M1;
      case PERIOD_M2:  return OBJ_PERIOD_M2;
      case PERIOD_M3:  return OBJ_PERIOD_M3;
      case PERIOD_M4:  return OBJ_PERIOD_M4;
      case PERIOD_M5:  return OBJ_PERIOD_M5;
      case PERIOD_M6:  return OBJ_PERIOD_M6;
      case PERIOD_M10: return OBJ_PERIOD_M10;
      case PERIOD_M12: return OBJ_PERIOD_M12;
      case PERIOD_M15: return OBJ_PERIOD_M15;
      case PERIOD_M20: return OBJ_PERIOD_M20;
      case PERIOD_M30: return OBJ_PERIOD_M30;
      case PERIOD_H1:  return OBJ_PERIOD_H1;
     }
   return OBJ_PERIOD_M1;
  }

/*
Purpose: Return the non-LTF visibility mask for the HTF-aligned side of a dual line.
Constitution: Backup-proven MT5 anchoring pattern where exact LTF and above-LTF objects render separately.
Inputs: None.
Outputs: Full-content mask with the exact LTF period removed.
*/
long TFMask_AboveLTF()
  {
   return TFMask_Full() & ~TFMask_ExactLTF();
  }

/*
Purpose: Compute the raw Fibonacci stop-loss anchor extension.
Constitution: Ch. 21 and pass-1 SL helper requirements.
Inputs: aA - Anchor A, aB - Anchor B, bull - direction, branch - V-shape or deep-swing, cfg - fib config preset.
Outputs: Raw SL price.
*/
double CalcFibSL(double aA,double aB,bool bull,ENUM_SL_BRANCH branch,ENUM_FIB_CFG cfg)
  {
   double shallow=(cfg==FIB_CFG_1)?0.50:0.75;
   double deep=(cfg==FIB_CFG_1)?0.75:1.00;
   double ext=(branch==BRANCH_VSHAPE)?deep:shallow;

   if(bull)
      return aB - ext*(aA-aB);

   return aB + ext*(aB-aA);
  }

/*
Purpose: Compute the raw TP using RR first, then optional CO extension.
Constitution: Ch. 22 take-profit and CO extension rules.
Inputs: bull - direction, entry - entry price, sl - stop price, coPrice - correction origin, rr - RR preset, useCO - enable CO extension.
Outputs: Raw TP price.
*/
double CalcTPRaw(bool bull,double entry,double sl,double coPrice,double rr,bool useCO)
  {
   double primary=entry + (bull ? 1.0 : -1.0) * rr * MathAbs(entry-sl);

   if(useCO && coPrice>0.0)
     {
      if(bull && coPrice>primary)
         return coPrice;
      if(!bull && coPrice<primary)
         return coPrice;
     }

   return primary;
  }

/*
Purpose: Return the display edge for events detected on a just-closed LTF candle.
Constitution: Latest user clarification that close-confirmed execution/FVG/CO events visually end at the previous second, not one full bar later.
Inputs: eventTime - scanner event timestamp.
Outputs: One second before eventTime, or 0 when invalid.
*/
datetime ClosedLTFEventEdge(datetime eventTime)
  {
   if(eventTime<=0)
      return 0;
   return eventTime-1;
  }

/*
Purpose: Return the current live right edge for LTF-only execution objects.
Constitution: Live execution objects track one LTF bar ahead until an independent event locks them.
Inputs: None.
Outputs: Latest LTF chart edge.
*/
datetime LTFLiveRightEdge()
  {
   return (datetime)(SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE)+PeriodSeconds(LTF())-1);
  }

/*
Purpose: Identify non-visual tester runs where all drawing must be suppressed.
Constitution: Ch. 26 and tester-performance rules from AGENTS and skill.
Inputs: None.
Outputs: True when running in tester without visual mode.
*/
bool IsNonVisualTesterRun()
  {
   return ((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE));
  }

bool CCTDebugEnabled()
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER) && Inp_PrivacyMode!=PRIVACY_NORMAL)
      return false;
   return (Inp_ShowDebug || (Inp_ForceTesterDebug && (bool)MQLInfoInteger(MQL_TESTER)));
  }

bool CCTProfileTimingEnabled()
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER) && Inp_PrivacyMode!=PRIVACY_NORMAL)
      return false;
   return (Inp_ProfileTimingLogs || CCTDebugEnabled());
  }

bool CCTLifecycleJournalEnabled()
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER) && Inp_PrivacyMode!=PRIVACY_NORMAL)
      return false;
   return (Inp_ShowDebug || (bool)MQLInfoInteger(MQL_TESTER));
  }

bool CCTSuppressLiveCCTJournals()
  {
   return (!(bool)MQLInfoInteger(MQL_TESTER) && Inp_PrivacyMode!=PRIVACY_NORMAL);
  }

long CCTEffectiveMagic()
  {
   if(Inp_PrivacyMode==PRIVACY_AGGRESSIVE_INCOGNITO && Inp_IncognitoMagicZero)
      return 0;
   return Inp_Magic;
  }

int    g_cctTesterJournalHandle=INVALID_HANDLE;
string g_cctTesterJournalFileName="";
int    g_cctTesterJournalPending=0;

// CCT_EXEC_TRIGGER_TO_SEND_TIMING_V1
// Stamped by the broker-critical execution pulse so order attempts can explain
// whether latency came from tick arrival, scanner work, or the broker call.
datetime g_cctExecPulseSeenLtf=0;
datetime g_cctExecPulseSeenServer=0;
ulong    g_cctExecPulseScanStartUs=0;
ulong    g_cctExecPulseScanEndUs=0;
string   g_cctExecPulseSource="";

/*
Purpose: Convert a value into a filesystem-safe token for tester journal mirror filenames.
Constitution: Tester diagnostics must remain parseable and recoverable even when MT5 UI log tabs hide Expert output.
Inputs: value - raw token.
Outputs: Sanitized token containing no path separators or timestamp punctuation.
*/
string CCTSafeFileToken(string value)
  {
   StringReplace(value,"\\","_");
   StringReplace(value,"/","_");
   StringReplace(value,":","-");
   StringReplace(value," ","_");
   StringReplace(value,".","_");
   return value;
  }

/*
Purpose: Open the Strategy Tester mirror log used as a stable black-box recorder for CCT diagnostics.
Constitution: Live/demo behavior must not change; tester/debug evidence must be available even if MT5 routes logs away from the Experts tab.
Inputs: None.
Outputs: Opens g_cctTesterJournalHandle when running in tester.
*/
void CCTTesterJournalInit()
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return;
   if(g_cctTesterJournalHandle!=INVALID_HANDLE)
      return;

   FolderCreate("CCT",FILE_COMMON);
   FolderCreate("CCT\\tester_journal",FILE_COMMON);

   string stamp=CCTSafeFileToken(TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS));
   string nonce=IntegerToString((long)GetMicrosecondCount());
   string symbol=CCTSafeFileToken(_Symbol);
   string baseName=StringFormat("CCT\\tester_journal\\CCT_TesterJournal_%s_%s_%s",symbol,stamp,nonce);
   g_cctTesterJournalFileName=baseName+".log";
   for(int attempt=1;attempt<1000 && FileIsExist(g_cctTesterJournalFileName,FILE_COMMON);attempt++)
      g_cctTesterJournalFileName=StringFormat("%s_%03d.log",baseName,attempt);
   ResetLastError();
   g_cctTesterJournalHandle=FileOpen(g_cctTesterJournalFileName,
                                     FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
   if(g_cctTesterJournalHandle==INVALID_HANDLE)
     {
      PrintFormat("[CCT ERR] tester journal mirror open failed | file=%s | err=%d",
                  g_cctTesterJournalFileName,GetLastError());
      return;
     }

   string fullPath=TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+g_cctTesterJournalFileName;
   PrintFormat("[CCT INIT] tester journal mirror=%s",fullPath);
   FileWriteString(g_cctTesterJournalHandle,"# CCT tester journal mirror\r\n");
   FileWriteString(g_cctTesterJournalHandle,"# "+fullPath+"\r\n");
   FileFlush(g_cctTesterJournalHandle);
   g_cctTesterJournalPending=0;
  }

/*
Purpose: Flush pending tester journal mirror rows.
Constitution: Tester research logs must survive shutdown and remain parseable.
Inputs: None.
Outputs: Flushes the open mirror file.
*/
void CCTTesterJournalFlush()
  {
   if(g_cctTesterJournalHandle==INVALID_HANDLE)
      return;
   FileFlush(g_cctTesterJournalHandle);
   g_cctTesterJournalPending=0;
  }

/*
Purpose: Close the tester journal mirror safely at EA shutdown.
Constitution: Tester diagnostics must not be lost at the end of a run.
Inputs: None.
Outputs: Flushes and closes the mirror file if open.
*/
void CCTTesterJournalClose()
  {
   if(g_cctTesterJournalHandle==INVALID_HANDLE)
      return;
   CCTTesterJournalFlush();
   FileClose(g_cctTesterJournalHandle);
   g_cctTesterJournalHandle=INVALID_HANDLE;
  }

/*
Purpose: Emit one CCT diagnostic/audit line to MT5 and to the tester mirror file.
Constitution: The scanner has one truth path; tester evidence must show the same births, kills, triggers, risk, exits, and research rows regardless of MT5 tab routing.
Inputs: line - complete parseable log row.
Outputs: Prints to MT5 and mirrors to a tester file when in Strategy Tester.
*/
void CCTJournalLine(const string line)
  {
   if(CCTSuppressLiveCCTJournals())
      return;
   Print(line);
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return;

   CCTTesterJournalInit();
   if(g_cctTesterJournalHandle==INVALID_HANDLE)
      return;

   string stamp=TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS);
   FileWriteString(g_cctTesterJournalHandle,stamp+"\t"+line+"\r\n");
   g_cctTesterJournalPending++;
   if(g_cctTesterJournalPending>=50)
      CCTTesterJournalFlush();
  }

/*
Purpose: Build the generation key from direction and NY birth time.
Constitution: Ch. 4.1 and Ch. 36.2 generation identity.
Inputs: bull - direction, birthTime - HTF birth bar open time.
Outputs: Stable, human-readable generation key string.
*/
string GenKey(bool bull,datetime birthTime)
  {
   MqlDateTime ny={};
   TimeToStruct(CCTStructuralNYLocalForTime(birthTime),ny);
   return StringFormat("%s_%02d%02d%02d_%02d%02d",
                       bull ? "BU" : "BE",
                       ny.year%100,ny.mon,ny.day,ny.hour,ny.min);
  }

/*
Purpose: Build a chart object name under the CCT namespace.
Constitution: Ch. 26 object ownership and lifecycle.
Inputs: gk - generation key, sfx - object suffix.
Outputs: Stable CCT object name.
*/
string ObjN(string gk,string sfx)
  {
   return "CCT_" + gk + "_" + sfx;
  }

/*
Purpose: Build a stable name for NY daily separator objects.
Constitution: Ch. 26 visual ownership and day-separator lifecycle.
Inputs: dayOpen - server-time NY midnight.
Outputs: Stable separator object name.
*/
string DaySepName(datetime dayOpen)
  {
   MqlDateTime ny={};
   TimeToStruct(CCTStructuralNYLocalForTime(dayOpen),ny);
   return StringFormat("CCT_DAY_%04d%02d%02d",ny.year,ny.mon,ny.day);
  }

/*
Purpose: Shift a server-time NY-midnight marker by whole New York calendar days.
Constitution: Ch. 1.2 daily reset boundaries and scanner window rules use NY-day arithmetic, not raw 24-hour server offsets.
Inputs: serverNyMidnight - server-time datetime already representing NY midnight, dayDelta - signed NY-day shift.
Outputs: Server-time datetime for the shifted NY midnight.
*/
datetime ShiftNYMidnightServer(datetime serverNyMidnight,int dayDelta)
  {
   if(serverNyMidnight<=0)
      return 0;

   MqlDateTime ny={};
   TimeToStruct(ToNY(serverNyMidnight),ny);
   ny.hour=0;
   ny.min=0;
   ny.sec=0;

   datetime shiftedNyMidnight=StructToTime(ny) + (datetime)(dayDelta*86400);
   int nyOffset=NYOffsetAtMidnight(shiftedNyMidnight);
   datetime utcMidnight=shiftedNyMidnight - nyOffset;
   return utcMidnight + ServerUTCOffsetSecForUTC(utcMidnight);
  }

/*
Purpose: Return the oldest NY midnight included in the greedy generation scanner window.
Constitution: Visibility retention is model-scaled by NY 17:00 structural trading days, with Saturday structural opens skipped.
Inputs: None.
Outputs: Server-time NY 17:00 structural open for the oldest retained trading day.
*/
bool CCTStructuralOpenIsTradingDay(datetime structuralOpen)
  {
   if(structuralOpen<=0)
      return false;

   MqlDateTime ny={};
   TimeToStruct(CCTStructuralNYLocalForTime(structuralOpen),ny);
   return (ny.day_of_week!=6); // Saturday 17:00 structural opens are non-trading retention gaps.
  }

datetime CCTShiftTradingStructuralDayOpen(datetime structuralOpen,int tradingDayDelta)
  {
   if(structuralOpen<=0 || tradingDayDelta==0)
      return structuralOpen;

   int dir=(tradingDayDelta>0) ? 1 : -1;
   int remaining=MathAbs(tradingDayDelta);
   datetime cur=structuralOpen;
   int guard=0;

   while(remaining>0 && guard<32)
     {
      cur=CCTShiftStructuralDayOpen(cur,dir);
      if(cur<=0)
         return 0;

      if(CCTStructuralOpenIsTradingDay(cur))
         remaining--;
      guard++;
     }

   return (remaining==0 ? cur : 0);
  }

int CCTModelPriorTradingDaysRetained()
  {
   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return 7;
   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return 3;
   return 2;
  }

datetime GenerationScanStart()
  {
   // CCT_NY_STRUCTURAL_RETENTION_BY_MODEL_V1
   datetime today=CCTTodayStructuralOpen();
   if(today<=0)
      return 0;

   while(today>0 && !CCTStructuralOpenIsTradingDay(today))
      today=CCTShiftTradingStructuralDayOpen(today,-1);

   return CCTShiftTradingStructuralDayOpen(today,-CCTModelPriorTradingDaysRetained());
  }

/*
Purpose: Return whether a server timestamp belongs to the current NY trading day.
Constitution: Current-day activation visibility and daily carry-over rules are keyed to NY-midnight boundaries.
Inputs: srvTime - broker server datetime.
Outputs: True when srvTime belongs to the current NY day.
*/
bool IsCurrentNYDay(datetime srvTime)
  {
   return (srvTime>0 && CCTStructuralDayOpenForTime(srvTime)==CCTTodayStructuralOpen());
  }

/*
Purpose: Return whether a server timestamp belongs to the active two-day generation scan horizon.
Constitution: Latest user clarification keeps births/APs/executions to current NY day plus the immediately previous NY day.
Inputs: srvTime - broker server datetime.
Outputs: True when the timestamp belongs to the current or immediately previous NY day.
*/
bool IsWithinGenerationScanRange(datetime srvTime)
  {
   return (srvTime>0 && CCTStructuralDayOpenForTime(srvTime)>=GenerationScanStart());
  }

/*
Purpose: Return the action pillar time for a generation birth.
Constitution: Ch. 4.5 and Ch. 29.1 action pillar timing.
Inputs: birthTime - HTF birth bar open time.
Outputs: Next HTF bar open time.
*/
datetime ActionPillarTime(datetime birthTime)
  {
   return birthTime+(datetime)CCTModelHTFSeconds();
  }

/*
Purpose: Return the time when a birth can affect scanner authority.
Constitution: Latest model clarification: the HTF candle owns its generation key from bar open, but bias, dormancy, and execution authority begin only after that HTF candle closes.
Inputs: birthTime - HTF birth bar open time.
Outputs: Next HTF bar open time, which is also the action-pillar open.
*/
datetime BirthEffectiveTime(datetime birthTime)
  {
   return ActionPillarTime(birthTime);
  }

/*
Purpose: Return the server-time NY midnight for the NY day containing the supplied server timestamp.
Constitution: Ch. 1.2 daily reset boundary and visual day separators.
Inputs: srvTime - broker server datetime.
Outputs: Server-time datetime corresponding to that NY day's midnight.
*/
datetime NYDayOpenForServerTime(datetime srvTime)
  {
   MqlDateTime ny={};
   TimeToStruct(ToNY(srvTime),ny);
   ny.hour=0;
   ny.min=0;
   ny.sec=0;

   datetime nyMidnight=StructToTime(ny);
   int nyOffset=NYOffsetAtMidnight(nyMidnight);
   datetime utcMidnight=nyMidnight - nyOffset;
   return utcMidnight + ServerUTCOffsetSecForUTC(utcMidnight);
  }

/*
Purpose: Convert an NY-hour offset on a known NY day into broker server time.
Constitution: Ch. 1 NY-time authority and Ch. 29 execution-window timing are keyed to NY calendar hours.
Inputs: serverNyMidnight - broker server timestamp that represents NY midnight, nyHour - NY hour on that same day.
Outputs: Broker server timestamp for that NY-hour bar open, or 0 when inputs are invalid.
*/
datetime NYHourOpenServer(datetime serverNyMidnight,int nyHour)
  {
   if(serverNyMidnight<=0 || nyHour<0 || nyHour>23)
      return 0;

   return serverNyMidnight + (datetime)(nyHour*3600);
  }

/*
Purpose: Check whether a specific execution hour is enabled for a specific birth-to-execution offset family.
Constitution: Ch. 8 execution-hour authorization, Ch. 29 generation relevance, and latest user clarification that visible births must belong to the configured CCT timing families rather than to the raw union of all selected hours.
Inputs: execHourNY - NY execution hour to test, offset - HTF bars from birth to execution (1=CCT, 2=CCT+TS timing, 3=CCT+TS Ext timing).
Outputs: True when the hour is enabled for that timing family.
*/
bool IsExecHourAllowedForBirthOffset(int execHourNY,int offset)
  {
   if(execHourNY<0 || execHourNY>23 || offset<1 || offset>3)
      return false;

   if(!Inp_SessionFilter)
      return true;

   bool hasCct=CachedCCTHour(execHourNY);
   bool hasTs=CachedTSHour(execHourNY);
   bool hasExt=CachedExtHour(execHourNY);

   // The immediate H-1 birth owns any selected execution hour first, regardless of
   // whether the final structural outcome later classifies as CCT, TS, or TS Ext.
   if(offset==1)
      return (hasCct || hasTs || hasExt);

   // Later selected hours are still execution windows. The model route is
   // resolved at C1/trigger time: plain hours can become CCT EXT, while TS/Ext
   // hours can authorize older/dormant liquidity paths when their sweep rules pass.
   return (hasCct || hasTs || hasExt);
  }

/*
Purpose: Resolve the exact HTF execution window owned by a birth for one timing-family offset.
Constitution: Ch. 4.5 action-pillar timing, Ch. 8 execution-hour authorization, Ch. 29 generation relevance, and latest user clarification that births must map cleanly into the configured execution-hour families.
Inputs: birthTime - HTF birth bar open time in broker time, offset - HTF bars from birth to execution (1..3).
Outputs: execOpen - broker server time of the authorized execution bar open, execEnd - broker server time of that bar close; returns true when this birth owns that timing window.
*/
bool ResolveBirthOffsetExecutionWindow(datetime birthTime,int offset,datetime &execOpen,datetime &execEnd)
  {
   execOpen=0;
   execEnd=0;

   if(birthTime<=0 || offset<1 || offset>3)
      return false;

   int htfSec=CCTModelHTFSeconds();
   if(htfSec<=0)
      return false;

   if(Inp_TimeframeModel==CCT_TFM_1H_M1)
     {
      datetime birthDayOpen=CCTStructuralDayOpenForTime(birthTime);
      if(birthDayOpen<=0 || birthDayOpen<GenerationScanStart())
         return false;

      MqlDateTime birthNy={};
      TimeToStruct(CCTStructuralNYLocalForTime(birthTime),birthNy);

      int rawExecHour=birthNy.hour+offset;
      int execHour=rawExecHour%24;
      if(!IsExecHourAllowedForBirthOffset(execHour,offset))
         return false;

      birthNy.hour=execHour;
      birthNy.min=0;
      birthNy.sec=0;
      datetime execNY=StructToTime(birthNy)+(datetime)((rawExecHour/24)*86400);
      execOpen=CCTStructuralTimeFromNYLocal(execNY);
      if(execOpen<=0)
         return false;

      execEnd=execOpen+(datetime)htfSec;
      return (execEnd>execOpen);
     }

   execOpen=birthTime+(datetime)(offset*htfSec);
   execEnd=execOpen+(datetime)htfSec;
   if(execOpen<=birthTime || execEnd<=execOpen)
      return false;

   if(!CCTModelWindowHasAnyAuth(execOpen,execEnd))
      return false;

   return true;
  }

/*
Purpose: Return the configured execution offset between a generation birth and an HTF execution bar.
Constitution: Ch. 8 execution-hour gate and CCT_MODEL_CLARIFICATIONS fallback source ladder require birth-specific ownership, not a raw union of all selected hours.
Inputs: birthTime - generation birth HTF open, htfOpen - candidate execution HTF open.
Outputs: Offset in HTF bars, or -1 when the bar cannot belong to the generation.
*/
int GenerationExecutionOffset(datetime birthTime,datetime htfOpen)
  {
   int htfSec=CCTModelHTFSeconds();
   if(birthTime<=0 || htfOpen<=birthTime || htfSec<=0)
      return -1;

   int delta=(int)(htfOpen-birthTime);
   if(delta%htfSec!=0)
      return -1;

   int offset=delta/htfSec;
   if(offset<1 || offset>3)
      return -1;

   return offset;
  }

/*
Purpose: Detect whether a newer same-bias birth exists between one source birth and a candidate execution bar.
Constitution: Fallback source ladder requires H-2/H-3 owners to yield to nearer same-bias births; selected hours are execution hours, not blanket birth visibility.
Inputs: bull - generation direction, fromExclusive - older source birth, toExclusive - candidate execution HTF open.
Outputs: True when a nearer same-bias generation exists before the execution bar.
*/
bool SameBiasBirthExistsBetween(bool bull,datetime fromExclusive,datetime toExclusive)
  {
   if(fromExclusive<=0 || toExclusive<=fromExclusive)
      return false;

   int count=bull ? g_nBull : g_nBear;
   for(int i=0;i<count;i++)
     {
      int idx=bull ? g_bullBirths[i] : g_bearBirths[i];
      if(idx<0 || idx>=g_nHtf)
         continue;

      datetime birth=g_htf[idx].time;
      datetime effective=BirthEffectiveTime(birth);
      if(birth>fromExclusive && effective<=toExclusive)
         return true;
     }

   return false;
  }

/*
Purpose: Return whether an older fallback source is blocked by a nearer same-bias birth.
Constitution: H-1 owns first; H-2/H-3 fallback authority exists only when the nearer source did not birth.
Inputs: g - candidate generation, htfOpen - execution bar open, offset - HTF source distance.
Outputs: True when this generation must not own the execution bar.
*/
bool GenerationFallbackBlockedByNearerSource(const GenInfo &g,datetime htfOpen,int offset)
  {
   if(offset<=1)
      return false;

   return SameBiasBirthExistsBetween(g.bull,g.birthTime,htfOpen);
  }

/*
Purpose: Resolve the last authorized execution-bar end for a generation under the current hour configuration.
Constitution: Ch. 29 drawing conditions, Ch. 36.3 execution-window authorization, and latest user clarification that relevance is tied to births that structurally map into the configured CCT timing families plus next-day early carry.
Inputs: birthTime - HTF birth bar open time in broker time.
Outputs: lastEnd - broker server time where the final authorized HTF bar closes; returns true when any authorized execution bar exists.
*/
bool ResolveGenerationLastAuthorizedEnd(datetime birthTime,datetime &lastEnd)
  {
   lastEnd=0;

   for(int offset=1;offset<=3;offset++)
     {
      datetime execOpen=0;
      datetime execEnd=0;
      if(!ResolveBirthOffsetExecutionWindow(birthTime,offset,execOpen,execEnd))
         continue;

      if(execEnd>lastEnd)
         lastEnd=execEnd;
     }

   return (lastEnd>0);
  }

/*
Purpose: Map an arbitrary server timestamp onto the open time of its containing HTF bar.
Constitution: Ch. 8 carry-over authority and Ch. 27 object anchoring require HTF-bar ownership to be resolved from structural event times.
Inputs: eventTime - server timestamp inside an HTF bar.
Outputs: HTF bar open time, or 0 when the time cannot be resolved.
*/

#define CCT_SYNTH_D1_NY1700_HELPERS_V1 1

#define CCT_SYNTH_D1_UTC_CHART_TIME_V2 1

datetime CCTSyntheticD1NYLocalFromChartTime(datetime chartTime)
  {
   // D1/M15 synthetic source uses the M15 chart timestamp as the UTC/OANDA-style reference timeline.
   // Example in May/EDT: chart 21:00 -> NY 17:00.
   if(chartTime<=0)
      return 0;
   datetime utc=chartTime;
   return utc + (datetime)NYUTCOffsetSec(utc);
  }

datetime CCTSyntheticD1ChartTimeFromNYLocal(datetime nyLocal)
  {
   // Convert NY-local wall-clock time directly to the chart timestamp timeline.
   // This deliberately does NOT add ServerUTCOffsetSecForUTC(), because that pushed NY 17:00 to MT5 00:00.
   if(nyLocal<=0)
      return 0;

   datetime guessUtc=nyLocal+(datetime)(5*3600);
   int nyOffset=NYUTCOffsetSec(guessUtc);
   datetime utc=nyLocal-(datetime)nyOffset;
   int correctedOffset=NYUTCOffsetSec(utc);
   if(correctedOffset!=nyOffset)
      utc=nyLocal-(datetime)correctedOffset;

   return utc;
  }

datetime CCTServerFromNYLocal(datetime nyLocal)
  {
   return CCTStructuralTimeFromNYLocal(nyLocal);
  }

datetime CCTNY1700DailyOpenForServerTime(datetime serverTime)
  {
   return CCTStructuralDayOpenForTime(serverTime);
  }

datetime CCTNY1700ShiftDailyOpen(datetime dailyOpen,int dayDelta)
  {
   return CCTShiftStructuralDayOpen(dailyOpen,dayDelta);
  }datetime HTFBarOpenForTime(datetime eventTime)
  {
   return CCTModelHTFOpenForTime(eventTime);
  }

/*
Purpose: Return whether a generation owns the HTF execution bar containing eventTime.
Constitution: Execution-hour selections authorize C1 for a specific birth source/fallback family; a selected hour alone is not enough for every older generation.
Inputs: g - generation record, eventTime - LTF/HTF time inside the candidate execution bar.
Outputs: True when the generation's birth maps to this selected execution bar.
*/
bool GenerationOwnsExecutionBar(const GenInfo &g,datetime eventTime)
  {
   datetime htfOpen=HTFBarOpenForTime(eventTime);
   if(htfOpen<=0)
      return false;

   int offset=GenerationExecutionOffset(g.birthTime,htfOpen);
   if(offset<1)
      return false;

   if(GenerationFallbackBlockedByNearerSource(g,htfOpen,offset))
      return false;

   datetime execOpen=0;
   datetime execEnd=0;
   if(!ResolveBirthOffsetExecutionWindow(g.birthTime,offset,execOpen,execEnd))
      return false;

   return (execOpen==htfOpen);
  }

/*
Purpose: Return whether a dormant older generation may reclaim authority by shoot-through on this HTF execution bar.
Constitution: Cross-generation dormant takeover is different from default source ownership. A nearer same-bias birth owns the hour first, but if price actually C1s an older dormant source during a selected TS/Ext family hour, the older source may supersede the newer authority.
Inputs: g - dormant generation record, eventTime - LTF close time being tested.
Outputs: True for authorized dormant takeover bars; false for plain CCT-only fallback attempts.
*/
bool GenerationOwnsDormantTakeoverBar(const GenInfo &g,datetime eventTime)
  {
   datetime htfOpen=HTFBarOpenForTime(eventTime);
   if(htfOpen<=0)
      return false;

   int offset=GenerationExecutionOffset(g.birthTime,htfOpen);
   if(offset<2 || offset>3)
      return false;

   MqlDateTime ny={};
   TimeToStruct(ToNY(htfOpen),ny);
   if(Inp_SessionFilter && !CCTModelTSOrExtAuthAllows(eventTime))
      return false;

   datetime execOpen=0;
   datetime execEnd=0;
   if(!ResolveBirthOffsetExecutionWindow(g.birthTime,offset,execOpen,execEnd))
      return false;

   return (execOpen==htfOpen);
  }

/*
Purpose: Resolve the last authorized execution end for a concrete generation, including fallback source ownership rules.
Constitution: Visual relevance and AP ownership must use the same source ladder as the scanner; older fallback births do not stay live when a nearer same-bias birth exists.
Inputs: g - generation record.
Outputs: lastEnd - latest authorized HTF close for this exact generation; returns true when one exists.
*/
bool ResolveGenerationLastAuthorizedEndForGeneration(const GenInfo &g,datetime &lastEnd)
  {
   lastEnd=0;

   for(int offset=1;offset<=3;offset++)
     {
      datetime execOpen=0;
      datetime execEnd=0;
      if(!ResolveBirthOffsetExecutionWindow(g.birthTime,offset,execOpen,execEnd))
         continue;

      if(GenerationFallbackBlockedByNearerSource(g,execOpen,offset))
         continue;

      if(execEnd>lastEnd)
         lastEnd=execEnd;
     }

   return (lastEnd>0);
  }

/*
Purpose: Return the close timestamp of a known HTF bar open.
Constitution: Pass 2 dynamic POI extension locks lines at HTF-bar closes.
Inputs: htfOpen - HTF bar open time.
Outputs: HTF bar close timestamp, or 0 when the input is invalid.
*/
datetime HTFBarCloseForOpen(datetime htfOpen)
  {
   if(htfOpen<=0)
      return 0;

   return htfOpen+(datetime)CCTModelHTFSeconds()-1;
  }

/*
Purpose: Return the HTF bar close timestamp for an arbitrary server time.
Constitution: Pass 2 dynamic POI extension advances one HTF bar at a time.
Inputs: eventTime - server timestamp inside an HTF bar.
Outputs: HTF bar close timestamp, or 0 when the time cannot be resolved.
*/
datetime HTFBarCloseForTime(datetime eventTime)
  {
   return HTFBarCloseForOpen(HTFBarOpenForTime(eventTime));
  }

/*
Purpose: Resolve the effective end of a generation's usable window at a specific reference time.
Constitution: Latest user clarification that valid POIs first end at the next HTF close after birth, extend one HTF bar after valid C1, and triggered unresolved POIs may keep extending bar-by-bar until resolution or HTF bias flip.
Inputs: g - generation record, refTime - server timestamp used to evaluate dynamic extension.
Outputs: endTime - server time where the generation should currently stop rendering; returns true when any usable end could be resolved.
*/
bool ResolveGenerationEffectiveEndAt(const GenInfo &g,datetime refTime,datetime &endTime)
  {
   endTime=0;

   int htfSec=CCTModelHTFSeconds();
   if(htfSec<=0 || g.birthTime<=0)
      return false;

   datetime lastAuthorizedEnd=0;
   if(ResolveGenerationLastAuthorizedEndForGeneration(g,lastAuthorizedEnd))
      endTime=lastAuthorizedEnd;
   else
      endTime=HTFBarCloseForOpen(ActionPillarTime(g.birthTime));

   for(int s=0;s<g.nSibs;s++)
     {
      if(!g.sibs[s].hadAuthorizedC1 || g.sibs[s].c1Time<=0)
         continue;

      datetime c1CarryEnd=HTFBarCloseForOpen(HTFBarOpenForTime(g.sibs[s].c1Time)+(datetime)htfSec);
      if(c1CarryEnd>endTime)
         endTime=c1CarryEnd;
     }

   if(g.triggerTime>0 && refTime>0)
     {
      datetime dynamicTriggeredEnd=HTFBarCloseForTime(refTime);
      if(dynamicTriggeredEnd>endTime)
         endTime=dynamicTriggeredEnd;
     }

   return (endTime>0);
  }

/*
Purpose: Resolve the effective end of a generation's usable window, including the one-bar carry earned by a valid C1.
Constitution: Ch. 8.3 and Ch. 29 require a valid execution-bar C1 to carry one HTF bar forward for C2+C3 completion, while untouched generations still expire at the end of their authorized execution bar.
Inputs: g - generation record.
Outputs: endTime - server time where the generation fully expires; returns true when any usable end could be resolved.
*/
bool ResolveGenerationEffectiveEnd(const GenInfo &g,datetime &endTime)
  {
   return ResolveGenerationEffectiveEndAt(g,CurrentServerTime(),endTime);
  }

/*
Purpose: Return whether a specific generation is still within its effective live window.
Constitution: Ch. 8.3 carry-over and Ch. 29 live-object expiry require the chart layer to honor the same effective end as the scanner.
Inputs: g - generation record, nowTime - broker server timestamp to evaluate.
Outputs: True when the generation still has remaining live time, including earned carry-over after valid C1.
*/
bool GenerationHasRemainingLiveWindow(const GenInfo &g,datetime nowTime)
  {
   if(nowTime<=0)
      nowTime=CurrentServerTime();

   datetime endTime=0;
   if(!ResolveGenerationEffectiveEndAt(g,nowTime,endTime))
      return false;

   return (nowTime<endTime);
  }

/*
Purpose: Return whether a generation still has a future or currently-open authorized execution bar.
Constitution: Ch. 29 plus latest user clarification that POIs and APs should stop following price once the selected execution hours are exhausted.
Inputs: birthTime - HTF birth bar open time, nowTime - broker server timestamp to evaluate.
Outputs: True when the generation is still relevant to the current execution-hour schedule.
*/
bool GenerationHasRemainingAuthorizedExec(datetime birthTime,datetime nowTime)
  {
   if(nowTime<=0)
      nowTime=CurrentServerTime();

   datetime lastEnd=0;
   if(!ResolveGenerationLastAuthorizedEnd(birthTime,lastEnd))
      return false;

   return (nowTime<lastEnd);
  }

/*
Purpose: Determine whether a birth still owns any authorized execution time for its action pillar.
Constitution: Ch. 4.5, Ch. 29, prior-day London carry-over rules, and latest user clarification that only current-day plus previous-day generations belong to the AP scan horizon.
Inputs: birthTime - HTF birth bar open time in broker time.
Outputs: True when the generation still has an enabled execution slot inside the allowed two-day scan horizon.
*/
bool GenerationHasAuthorizedExec(datetime birthTime)
  {
   datetime lastEnd=0;
   return ResolveGenerationLastAuthorizedEnd(birthTime,lastEnd);
  }

#endif
