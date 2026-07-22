#ifndef CRT_GLOBALS_MQH
#define CRT_GLOBALS_MQH

//======================================================================
// CRT_Globals.mqh — Candle Range Theory MQL5 EA
// All shared enums, structs, and globals that every module includes.
//
// Authoritative rules (mirror of 01-STRATEGY-SPEC.md §1):
//   C1  = reference candle: defines range High/Low and EQ (50%).
//   C2  = manipulation candle: sweep only; NEVER triggers/executes.
//         Sweep can ONLY happen in C2. CISD/IFVG born in C2 are
//         PROVISIONAL — only actioned at the C2-close/C3-open boundary.
//   C3  = execution candle: market order if >=1:1 at boundary,
//         otherwise a 1:1 LIMIT that PERSISTS beyond C3 close.
//   Limit dies ONLY on fill or when price touches C1_EQ (50% touch
//   invalidates the whole setup).
//   SL  = FIXED at the C2 extreme ± buffer; independent of C1_EQ.
//======================================================================

// ── Setup lifecycle ──────────────────────────────────────────────────
enum ENUM_CRT_PHASE
{
    CRT_PHASE_WAIT_C1       = 0, // waiting for a C1 to close
    CRT_PHASE_C2_WATCH      = 1, // C1 locked; C2 forming — watch sweep + CISD/IFVG (provisional)
    CRT_PHASE_C2_ARMED      = 2, // C2 closed with valid bias; boundary decision pending
    CRT_PHASE_C3_WINDOW     = 3, // C3 open — scan for trigger; manage carry-over
    CRT_PHASE_LIMIT_WORKING = 4, // 1:1 limit resting — persists beyond C3; dies on fill or 50%
    CRT_PHASE_FILLED        = 5, // entry filled; position live
    CRT_PHASE_DONE          = 6  // invalidated / TP / SL / no entry
};

enum ENUM_CRT_BIAS
{
    CRT_BIAS_NONE  = 0,
    CRT_BIAS_LONG  = 1,
    CRT_BIAS_SHORT = 2
};

enum ENUM_CRT_TRIGGER
{
    CRT_TRIGGER_CISD      = 0, // CISD only (default)
    CRT_TRIGGER_IFVG      = 1, // IFVG only
    CRT_TRIGGER_CISD_IFVG = 2  // Both required
};

enum ENUM_CRT_CISD_REF
{
    CRT_CISD_SINGLE     = 0, // Single candle reference
    CRT_CISD_SEQUENCE   = 1  // Consecutive same-direction run (first open)
};

enum ENUM_CRT_SLOT
{
    CRT_SLOT_INTRADAY = 0,
    CRT_SLOT_DAILY    = 1,
    CRT_SLOT_WEEKLY   = 2,
    CRT_SLOT_MONTHLY  = 3
};

enum ENUM_CRT_INTRADAY_TF
{
    CRT_TF_M15 = 15,  // 15 Minute
    CRT_TF_M30 = 30,  // 30 Minute
    CRT_TF_H1  = 60,  // 1 Hour
    CRT_TF_H2  = 120, // 2 Hour
    CRT_TF_H4  = 240  // 4 Hour
};

enum ENUM_CRT_ACC_MODE
{
    CRT_ACC_BALANCE = 0, // Balance
    CRT_ACC_EQUITY  = 1, // Equity
    CRT_ACC_CUSTOM  = 2  // Custom capital
};

enum ENUM_CRT_RISK_PRESET
{
    CRT_RISK_0_25 = 25,      // 0.25%
    CRT_RISK_0_50 = 50,      // 0.50%
    CRT_RISK_0_75 = 75,      // 0.75%
    CRT_RISK_1_00 = 100,     // 1.00%
    CRT_RISK_1_25 = 125,     // 1.25%
    CRT_RISK_1_50 = 150,     // 1.50%
    CRT_RISK_2_00 = 200,     // 2.00%
    CRT_RISK_CUSTOM = 10000  // Custom
};

enum ENUM_CRT_DASH_THEME
{
    CRT_DASH_DARK      = 0, // Dark
    CRT_DASH_DIM_LIGHT = 1  // Dim Light
};

// ── FVG zone ─────────────────────────────────────────────────────────
struct CrtFvg
{
    datetime bornTime;   // time of the 3rd candle that completed the gap
    double   farBound;   // C1 side of the gap (inversion boundary)
    double   nearBound;  // C3 side of the gap (entry side)
    bool     bullish;    // true = bullish gap (gap up)
    bool     inverted;   // true = a candle closed fully through farBound
};

// ── Per-setup state ───────────────────────────────────────────────────
#define CRT_MAX_FVGS 80

struct CrtSetup
{
    ENUM_CRT_PHASE   phase;
    ENUM_CRT_BIAS    bias;
    ENUM_CRT_SLOT    slotType;
    int              slotTfMin;    // HTF period in minutes (0 = non-intraday)

    // C1 range
    datetime         c1Time;
    double           c1High, c1Low, c1EQ;
    bool             c1Locked;
    bool             c1ValidBearish; // displacement filter
    bool             c1ValidBullish;

    // C2 / sweep
    datetime         c2OpenTime, c2CloseTime, c3OpenTime;
    bool             sweptHigh, sweptLow;
    double           c2RunHigh, c2RunLow; // C2 manipulation-candle running extremes (SL anchor)

    // SL (resolved at C2 close; fixed thereafter)
    double           slLevel;

    // Trigger carry-over
    bool             triggerFired;
    bool             triggerFiredInC2;
    bool             carryToC3;
    double           confirmClose;

    // Resting 1:1 limit
    bool             limitResting;
    double           limitPrice;
    bool             invalidated;

    // Sweep-start time for IFVG gate (gates "FVG born during/after sweep")
    datetime         sweepStartTime;

    // Session identity
    string           sessionKey;
    bool             orderPlaced;
    bool             dead;

    // Per-setup FVG window (max CRT_MAX_FVGS)
    CrtFvg           fvgs[CRT_MAX_FVGS];
    int              nFvgs;
};

// ── Active trade record ───────────────────────────────────────────────
struct CrtTrade
{
    ulong    ticket;
    ulong    slTicket;
    ulong    tpTicket;
    bool     isLong;
    double   entryPrice;
    datetime entryTime;
    double   slPrice;
    double   tpPrice;
    double   lots;
    string   sessionKey;
    bool     bracketPlaced;
};

// ── Ledger row ────────────────────────────────────────────────────────
struct CrtLedgerTrade
{
    datetime entryTime;
    datetime exitTime;
    string   sessionKey;
    bool     isLong;
    double   entryPrice;
    double   exitPrice;
    double   lots;
    double   pnl;
    string   exitReason;
};

// ── Runtime globals ───────────────────────────────────────────────────
// Set by the EA on init; shared across modules.
bool     g_crtStealthMode    = false;     // suppress non-essential journal output
bool     g_crtIsTester       = false;     // MQLInfoInteger(MQL_TESTER)
datetime g_crtRuntimeStart   = 0;         // freshness gate for notifications

#endif // CRT_GLOBALS_MQH
