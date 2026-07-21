//+------------------------------------------------------------------+
//|                                                ORB_Scalper.mq5  |
//| Opening Range Breakout Expert Advisor                            |
//| Developed by Osamwonyi Eric  -  Alias: You_FoundEric            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025-2026, Osamwonyi Eric (You_FoundEric)"
#property link      "https://t.me/You_FoundEric"
#property version   "4.02"
#property description "ORB Scalper - Opening Range Breakout Expert Advisor"
#property description "Developed by You_FoundEric | First-Party Build"
#property description "Unauthorized redistribution prohibited."
#property strict
// v4.01: exec SL/TP box colors reaffirmed to CCT defaults (SL C'55,57,68' / TP C'22,55,120').
// NOTE: MT5 caches last-used input values per chart. If a terminal shows bright
// SL/TP colors (e.g. 225,116,126 / 84,212,154) it is using STALE SAVED INPUTS
// from an older build. Re-attach the EA and Reset inputs (or set the two color
// fields back to the CCT values) so the corrected defaults take effect.

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

enum ENUM_RISK_BASIS
{
    RISK_BASIS_BALANCE = 0, // Balance
    RISK_BASIS_EQUITY  = 1, // Equity
    RISK_BASIS_MARGIN  = 2  // Free Margin
};

enum ENUM_POINT_SCALE_MODE
{
    SCALE_BASE = 0, // Base (x10 tick scale - validated default, all assets)
    SCALE_WIDE = 1  // Wide (x100 tick scale - one decimal higher, all assets)
};

enum ENUM_TRAIL_MODE
{
    TRAIL_CONTINUOUS = 0, // Continuous (trail per-tick after activation)
    TRAIL_STEP       = 1  // Step (re-lock only each full threshold advance)
};

enum ENUM_RANGE_MINUTES
{
    RANGE_1_MIN  = 1,   // 1 Minute
    RANGE_5_MIN  = 5,   // 5 Minutes
    RANGE_10_MIN = 10,  // 10 Minutes
    RANGE_15_MIN = 15,  // 15 Minutes
    RANGE_30_MIN = 30,  // 30 Minutes
    RANGE_45_MIN = 45,  // 45 Minutes
    RANGE_60_MIN = 60,  // 1 Hour
    RANGE_120_MIN = 120, // 2 Hours
    RANGE_240_MIN  = 240  // 4 Hours
};

enum ENUM_DASH_THEME
{
    DASH_DARK      = 0, // Dark
    DASH_DIM_LIGHT = 1  // Dim-light
};

enum ENUM_TRAIL_BEHAVIOR
{
    TRAILB_ON  = 0, // Trail into profits (default)
    TRAILB_BE  = 1, // Breakeven only (lock spread + commission, then off)
    TRAILB_OFF = 2  // Off (fixed SL/TP only)
};

enum ENUM_RANGE_MODE
{
    RANGE_INTRADAY = 0, // Intraday  -> session candle range
    RANGE_DAILY    = 1, // Daily     -> prior D1 candle
    RANGE_WEEKLY   = 2, // Weekly    -> prior W1 candle
    RANGE_MONTHLY  = 3  // Monthly   -> prior MN1 candle
};

enum ENUM_SLOT2_ANCHOR
{
    SLOT2_ANCHOR_NY_TRUE = 0, // NY True Month/Week/Day
    SLOT2_ANCHOR_BROKER  = 1  // Broker Server Time
};

enum ENUM_SPREAD_PAD_MODE
{
    SPREAD_PAD_DISABLED = 0, // Disabled
    SPREAD_PAD_SLOT0    = 1, // Slot 0 Only
    SPREAD_PAD_SLOT1    = 2, // Slot 1 Only
    SPREAD_PAD_BOTH     = 3  // Slot 0 & 1
};

enum ENUM_LOTCAP_MODE
{
    LOTCAP_OFF       = 0, // Off  (broker limit only)
    LOTCAP_PER_ASSET = 1, // Per-market caps  (recommended for prop rules)
    LOTCAP_GLOBAL    = 2  // Single global cap across all assets
};

//+------------------------------------------------------------------+
//| Input Groups                                                     |
//+------------------------------------------------------------------+

input group "==========  1 - Risk & Capital  =========="
input double            Risk_Percent             = 1.0;                // Risk per trade (%)
input ENUM_RISK_BASIS   Risk_Basis               = RISK_BASIS_BALANCE; // Basis for risk calculation
input double            Custom_Balance_Override  = 0.0;                // Override balance (0 = use live account)
input bool              Use_Commission_Buffer    = true;               // Include observed commission in risk sizing
input double            Commission_Per_Lot_Override = 0.0;             // Manual commission per lot (0 = auto-detect from history)
input double            Max_Margin_Usage_Percent = 90.0;               // Max free margin to reserve per pending leg (%)

input group " "
input group "==========  2 - Sessions  =========="
input bool              Enable_NY_Session        = true;               // NY      |  Enable
input int               Opening_Hour_NY_Time     = 9;                  // NY      |  Open hour  (NY timezone)
input int               Opening_Minute_NY_Time   = 30;                 // NY      |  Open minute

input bool              Enable_London_Session    = false;              // London  |  Enable
input int               London_Hour_NY_Time      = 3;                  // London  |  Open hour  (NY timezone, 02-06)
input int               London_Minute_NY_Time    = 0;                  // London  |  Open minute

input bool              Enable_Asian_Session     = false;              // Asian   |  Enable
input int               Asian_Hour_NY_Time       = 18;                 // Asian   |  Open hour  (NY timezone, 17-21)
input int               Asian_Minute_NY_Time     = 0;                  // Asian   |  Open minute
input bool              Asian_Tokyo_Anchor       = true;               // Asian   |  Auto-shift +1 h in NY winter (Tokyo DST fix)

input group "  "
input group "==========  3 - Range Slots  =========="
input ENUM_RANGE_MINUTES Slot1_Range_Minutes     = RANGE_15_MIN;      // Intraday |  Trigger candle length  (shared by NY/London/Asian)

input bool              Enable_Daily_Range       = false;              // HTF     |  Enable Daily range  (prior D1 candle)
input bool              Enable_Weekly_Range      = false;              // HTF     |  Enable Weekly range  (prior W1 candle)
input bool              Enable_Monthly_Range     = false;              // HTF     |  Enable Monthly range  (prior MN1 candle)
input ENUM_SLOT2_ANCHOR Slot2_Anchor_Mode        = SLOT2_ANCHOR_NY_TRUE; // HTF     |  Daily/weekly anchor
input int               Slot2_Cutoff_Periods     = 1;                  // HTF     |  Expiry  (periods, shared by Daily/Weekly/Monthly)

input group "   "
input group "==========  4 - Trade Geometry  =========="
input bool              Reverse_Orders           = false;              // Flip direction  (sell high / buy low)
input ENUM_SPREAD_PAD_MODE Spread_Padding        = SPREAD_PAD_DISABLED; // Spread padding  |  Pad pending entry level by live spread at placement

input group "         "
input bool              Use_StopLimit_Orders     = false;              // Place Stop-Limit instead of Stop (caps slippage)
input bool              Use_Tiered_StopLimit_Escalation = false;       // Two-stage buffer widening; false = single fixed Tier1 buffer
input bool              Use_TP_Slippage_Pad      = false;             // Pad TP slippage limit
input double            TP_Slippage_Pad_Pct      = 0.0;               // TP pad percentage
input double            Max_Slippage_Points      = 0.0;               // Acceptable slippage (pts, 0=Off). Beyond this: SL/TP still recentred, but trailing is replaced by force-close-at-profit below.
input double            Slip_ForceClose_Profit_Points = 2.0;          // Excess-slip trades only: close at market once profit reaches this many points (never at a loss)

input group "          "
input bool              Use_Instant_Market_Execution = false;         // Master switch  |  Replace pending Buy/Sell Stop(-Limit) with tick-triggered market execution
input double            Instant_Max_Entry_Slippage_Points = 15.0;     // Max entry slippage (pts)  |  Gap between range level and live fill price beyond which entry is SKIPPED, never chased
input bool              Instant_Overslip_ForceClose = true;           // Post-fill guard  |  If the BROKER fill lands beyond the max slippage gate (pre-send quote passed, fill slipped in transit): recenter SL/TP on the fill, disable trailing, and hand the trade to the slip force-close manager (closes only at +Slip_ForceClose_Profit_Points, never at a loss)

input group "           "
input ENUM_POINT_SCALE_MODE Point_Scale_Mode     = SCALE_BASE;        // Point scale  (Base x10 / Wide x100)
input double            Fixed_SL_Points          = 200.0;             // Initial stop-loss  (normalised points, safety net)
input double            Fixed_TP_Points          = 200.0;             // Initial take-profit  (normalised points, safety net)

input group "            "
input ENUM_TRAIL_MODE   Trail_Mode               = TRAIL_CONTINUOUS;  // Trail mode  (Continuous / Step)
input ENUM_TRAIL_BEHAVIOR Trail_Behavior         = TRAILB_ON;         // Trail behaviour  (Trail / Breakeven / Off)
input double            Trail_Threshold_Points   = 120.0;             // Profit threshold before trail activates  (pts)
input double            Trail_Gap_Points         = 100.0;             // Trail gap behind price  (pts)
input bool              Use_Spread_Compensation  = true;              // Cost compensation (spread + auto-detected commission) on trail levels and BE
input double            Min_Trail_Minutes        = 0.0;               // Minimum time in trade before trail starts  (0 = immediate)
input bool              Force_Close_If_Trail_Stop_Too_Close = false;  // Trail safety  |  Close at market if broker stop distance blocks SL

input group "    "
input group "==========  5 - Filters  =========="
input bool              Use_Trend_Filter         = false;             // Trend filter  |  Enable EMA direction gate
input int               Trend_Ema_Period         = 50;               // Trend filter  |  EMA period
input ENUM_TIMEFRAMES   Trend_Ema_Timeframe      = PERIOD_H1;        // Trend filter  |  EMA timeframe
input bool              Use_Vol_Filter           = false;             // Volatility filter  |  Enable ATR size gate
input int               Vol_Atr_Period           = 10;               // Volatility filter  |  ATR period
input double            Vol_Atr_Multiplier       = 0.5;              // Volatility filter  |  Range must be >= ATR x this

input group "      "
input group "==========  6 - Display  =========="
input bool              Show_Dashboard           = true;              // Show dashboard panel
input bool              Show_Visuals             = true;              // Draw range box and execution objects
input ENUM_DASH_THEME   Dashboard_Theme          = DASH_DARK;         // Dashboard theme
input color             Clr_Range_Box_NY         = C'25,35,45';       // Range box  |  NY intraday
input color             Clr_Range_Box_London     = C'31,50,48';       // Range box  |  London intraday
input color             Clr_Range_Box_Asian      = C'44,39,57';       // Range box  |  Asian intraday
input color             Clr_Range_Box_Daily      = C'45,38,30';       // Range box  |  Daily
input color             Clr_Range_Box_Weekly     = C'36,43,56';       // Range box  |  Weekly
input color             Clr_Entry_Line           = C'214,218,224';    // Colour  |  Entry line
input color             Clr_SL_Line              = C'55,57,68';       // Colour  |  Stop-loss box
input color             Clr_TP_Line              = C'22,55,120';      // Colour  |  Take-profit box
input color             Clr_Trailing_Stop        = C'162,138,88';     // Colour  |  Active trailing stop

input group "     "
input group "==========  6b - Exposure & Lot Caps  =========="
input ENUM_LOTCAP_MODE  Lot_Cap_Mode        = LOTCAP_PER_ASSET;       // Lot cap mode
input double            Max_Lots_Global     = 4.0;                    // Cap  |  Global  (or fallback for uncategorised)
input double            Max_Lots_FX         = 4.0;                    // Cap  |  Forex
input double            Max_Lots_Metals     = 0.3;                    // Cap  |  Metals
input double            Max_Lots_Indices    = 2.0;                    // Cap  |  Indices
input double            Max_Lots_Crypto     = 1.0;                    // Cap  |  Crypto
input double            Max_Lots_Other      = 4.0;                    // Cap  |  Other / commodities
input bool              Split_Pair_Margin   = false;                  // Split margin across both sides  (OFF = each side sized to full room)

input group "       "
input group "==========  7 - Broker & Instance  =========="
input int               Server_UTC_Offset_Hours  = 0;                 // Server UTC offset  (hours)
input bool              Use_NewYork_DST          = true;              // Observe New York DST
input long              Magic_Number             = 1000000000;         // EA magic number
input bool              Isolate_Chart_Instances  = true;              // Isolate this chart from other same-symbol instances
input string            Instance_ID              = "";                // Stable instance ID  (blank = chart-persisted token)
input bool              Disable_Magic_Number     = false;             // Disable magic-number labelling
input bool              Cancel_Orders_On_Deinit  = true;              // Remove pending orders when EA is removed/closed

input group "        "
input group "==========  8 - Advanced  =========="
input double            Custom_Point_Multiplier  = 0.0;               // Custom point size  (0 = auto-detect)
input bool              Inp_StealthMode          = true;              // Stealth mode  (blank trade comments, quiet EA journal)
input bool              Use_OCO                  = false;             // One-cancels-other on first fill
input bool              Verbose_Journal          = false;             // Detailed EA journal logging

//+------------------------------------------------------------------+
//| Magic-number match helper (toggle-aware, independent of stealth)  |
//| When Use_Magic_Filter is off the EA treats every position/order   |
//| on this symbol as its own, regardless of magic.                   |
//+------------------------------------------------------------------+
long EffectiveMagic()
{
    return Disable_Magic_Number ? 0 : Magic_Number;
}

bool MagicMatch(long magic)
{
    return (magic == EffectiveMagic());
}

string InstanceKey()
{
    if(Instance_ID != "") return Instance_ID;

    string obj = "ORB_INSTANCE_TOKEN";
    if(ObjectFind(0, obj) >= 0)
    {
        string saved = ObjectGetString(0, obj, OBJPROP_TEXT);
        if(saved != "") return saved;
    }

    string token = StringFormat("%s_%d_%I64d_%lld", _Symbol, (int)_Period, EffectiveMagic(), (long)ChartID());
    if(ObjectFind(0, obj) < 0)
    {
        ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, -9000);
        ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, -9000);
    }
    ObjectSetString(0, obj, OBJPROP_TEXT, token);
    return token;
}

string TicketOwnerKey(ulong ticket)
{
    return StringFormat("ORB_OWNER_%s_%I64d_%llu", _Symbol, EffectiveMagic(), ticket);
}

double InstanceOwnerValue()
{
    string key = InstanceKey();
    uint hash = (uint)0x811C9DC5;
    for(int i = 0; i < StringLen(key); i++)
    {
        hash ^= (uint)StringGetCharacter(key, i);
        hash *= 16777619;
    }
    return (double)hash;
}

bool OwnsTicket(ulong ticket)
{
    if(!Isolate_Chart_Instances) return true;
    if(MQLInfoInteger(MQL_TESTER)) return true; // BYPASS in tester
    string key = TicketOwnerKey(ticket);
    return (GlobalVariableCheck(key) && GlobalVariableGet(key) == InstanceOwnerValue());
}

bool ClaimTicket(ulong ticket)
{
    if(!Isolate_Chart_Instances) return true;
    if(MQLInfoInteger(MQL_TESTER)) return true; // BYPASS in tester
    string key = TicketOwnerKey(ticket);
    double owner = InstanceOwnerValue();
    if(GlobalVariableCheck(key)) return (GlobalVariableGet(key) == owner);
    return GlobalVariableSetOnCondition(key, owner, 0.0);
}

//+------------------------------------------------------------------+
//| Bridge globals for include files                                 |
//+------------------------------------------------------------------+
string ORBPfx() { return "ORB_"; }

int     Inp_ServerUTCOffsetHours;
bool    Inp_UseNewYorkDST;
int     Inp_OpenNYHour;
int     Inp_OpenNYMinute;
// Active session's open (resolved from g_activeSession) so the trade engine
// keys the opening range/cutoff off whichever session is enabled to trade.
int     Inp_OpenActiveHour;
int     Inp_OpenActiveMin;
int     Inp_RangeMinutes;
// Per-session cutoff durations (minutes from each session's open).
int     Inp_CutoffNYMin;
int     Inp_CutoffLondonMin;
int     Inp_CutoffAsianMin;
// Active session's cutoff minutes (resolved from g_activeSession); used by the
// time engine to compute the trade-stop cutoff for whichever session is current.
int     Inp_CutoffActiveMin;
bool    Inp_ShowDashboard;
bool    Inp_ShowVisuals;
int     Inp_Slot2AnchorMode;
color   Inp_ClrRangeBoxNY;
color   Inp_ClrRangeBoxLondon;
color   Inp_ClrRangeBoxAsian;
color   Inp_ClrRangeBoxDaily;
color   Inp_ClrRangeBoxWeekly;
color   Inp_ClrEntryLine;
color   Inp_ClrSLLine;
color   Inp_ClrTPLine;
color   Inp_ClrTrailingStop;
int     Inp_DashTheme;  // forwarded to dashboard

// Session-enable + alternate-hour bridge globals (read by ORB_Dashboard.mqh)
bool    Inp_EnableNY;
bool    Inp_EnableLondon;
bool    Inp_EnableAsian;
int     Inp_LondonHour;
int     Inp_AsianHour;
int     Inp_LondonMinute;
int     Inp_AsianMinute;

// - Active session tracking (which session is currently active) -
// 0=NY, 1=London, 2=Asian
int     g_activeSession = 0;
bool    g_sessionIsLive = false;

#include "ORB_Time.mqh"
#include "ORB_Visuals.mqh"
#include "ORB_Dashboard.mqh"
#include "ORB_Notify.mqh"

//+------------------------------------------------------------------+
//| EA Globals                                                       |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    orderInfo;

int    emaHandle = INVALID_HANDLE;
int    atrHandle = INVALID_HANDLE;

string   g_sessionKey   = "";
string   g_visualSig    = "";   // signature of inputs affecting drawn objects; change -> purge stale visuals
bool     g_rangeReady   = false;
double   g_rangeHigh    = 0.0;
double   g_rangeLow     = 0.0;
datetime g_rangeStart   = 0;
datetime g_rangeEnd     = 0;
datetime g_eaActiveSince = 0;   // set once in OnInit(): when THIS instance started watching. A level crossed before this time happened while the EA wasn't running/initialized - stale, consumed outright. A level crossed at or after this time is a live touch, subject to the normal slippage gate.
datetime g_rangeHighTime = 0;   // exact candle that formed the range High
datetime g_rangeLowTime  = 0;

bool     g_buyPlaced    = false;
bool     g_sellPlaced   = false;
bool     g_buySendPending  = false;
bool     g_sellSendPending = false;
datetime g_buySendTime     = 0;
datetime g_sellSendTime    = 0;
bool     g_precloseArmed    = false;
// Market-closed retry state: when a broker rejects orders because the market
// is temporarily closed, we watch for a price change instead of burning retries.
bool     g_mktClosedPendingHigh  = false;  // awaiting market-reopen signal on high side
bool     g_mktClosedPendingLow   = false;  // awaiting market-reopen signal on low side
double   g_mktClosedLastAskHigh  = 0.0;   // ask price at the moment of last closed rejection (high)
double   g_mktClosedLastBidLow   = 0.0;   // bid price at the moment of last closed rejection (low)
datetime g_mktClosedLastCheckHigh = 0;    // timestamp of last closed-rejection on high side
datetime g_mktClosedLastCheckLow  = 0;    // timestamp of last closed-rejection on low side


string   g_rangeBuildKey = "";
datetime g_rangeBuildStart = 0;
datetime g_rangeBuildEnd = 0;
double   g_rangeBuildHigh = 0.0;
double   g_rangeBuildLow = 0.0;
datetime g_rangeBuildHighTime = 0;
datetime g_rangeBuildLowTime = 0;
bool     g_rangeBuildReady = false;

// - Slot state save/restore -
// All per-range mutable globals are mirrored in this struct so two independent
// range sessions can run simultaneously (slot 0 = primary, slot 1 = secondary).
struct ORBSlotState
{
    string   sessionKey;
    bool     rangeReady;
    double   rangeHigh, rangeLow;
    datetime rangeStart, rangeEnd;
    datetime rangeHighTime, rangeLowTime;
    bool     buyPlaced, sellPlaced;
    bool     buySendPending, sellSendPending;
    datetime buySendTime, sellSendTime;
    bool     precloseArmed;
    // Market-closed retry state
    bool     mktClosedPendingHigh, mktClosedPendingLow;
    double   mktClosedLastAskHigh, mktClosedLastBidLow;
    datetime mktClosedLastCheckHigh, mktClosedLastCheckLow;    string   buildKey;
    datetime buildStart, buildEnd;
    double   buildHigh, buildLow;
    datetime buildHighTime, buildLowTime;
    bool     buildReady;
    // These are set once from SetSlotContext before calling slot functions
    ENUM_RANGE_MODE ctxMode;
    int             ctxHour, ctxMin;
    int             ctxCutoffMin;
};
ORBSlotState g_slotState[6];

// Context bridge: writable globals read by ORB_Time.mqh slot-aware functions.
// SetSlotContext() populates these before calling any slot-sensitive function.
ENUM_RANGE_MODE g_ctxMode      = RANGE_INTRADAY;
int             g_ctxHour      = 0;
int             g_ctxMin       = 0;
int             g_ctxCutoffMin = 90;
int             g_ctxSlotIdx   = 0;

struct OrderMeta
{
    ulong    ticket;
    int      slotIdx;
    string   sessionKey;
    bool     highLevel;
    double   levelPx;
    datetime levelTime;
    datetime rangeStart;
    datetime rangeEnd;
    datetime expiry;
};
OrderMeta g_orderMeta[];

int ParseOrderSlot(const string comment)
{
    int p = StringFind(comment, "|S");
    if(p < 0) p = StringFind(comment, "#S");
    if(p < 0 || p + 2 >= StringLen(comment)) return -1;
    return (int)StringToInteger(StringSubstr(comment, p + 2, 1));
}

string ParseOrderSessionKey(const string comment)
{
    int p = StringFind(comment, "|K");
    if(p < 0) return "";
    int start = p + 2;
    int end = StringFind(comment, "|", start);
    if(end < 0) end = StringLen(comment);
    return StringSubstr(comment, start, end - start);
}

uint ORBHash(const string value)
{
    uint hash = (uint)0x811C9DC5;
    for(int i = 0; i < StringLen(value); i++)
    {
        hash ^= (uint)StringGetCharacter(value, i);
        hash *= 16777619;
    }
    return hash;
}

string OrderMetaKey(ulong ticket, string field)
{
    string owner = StringFormat("%s_%I64d_%s", _Symbol, EffectiveMagic(), InstanceKey());
    return StringFormat("OM_%08X_%llu_%s", ORBHash(owner), ticket, field);
}

int OrderMetaIdx(ulong ticket)
{
    for(int i = 0; i < ArraySize(g_orderMeta); i++)
        if(g_orderMeta[i].ticket == ticket) return i;
    return -1;
}

datetime EffectiveSlotCutoffServer(datetime serverTime);
void SetSlotContext(int slotIdx);
string ActiveSessionKey(datetime serverTime);
void ClearPendingSendLocks();
void ResetRangeBuild();
void CheckOpeningRange(datetime now);
void SyncPlacedFlagsFromLiveOrders();
void RegisterNewPositions(datetime now);
bool SideConsumed(string sessionKey, bool bull);
void SaveGlobalsToSlot(int s);
bool SlotEnabled(int slotIdx);

void RegisterOrderMeta(ulong ticket, bool highLevel)
{
    if(ticket == 0) return;
    int idx = OrderMetaIdx(ticket);
    if(idx < 0) { idx = ArraySize(g_orderMeta); ArrayResize(g_orderMeta, idx + 1); }
    g_orderMeta[idx].ticket     = ticket;
    g_orderMeta[idx].slotIdx    = g_ctxSlotIdx;
    g_orderMeta[idx].sessionKey = g_sessionKey;
    g_orderMeta[idx].highLevel  = highLevel;
    g_orderMeta[idx].levelPx    = highLevel ? g_rangeHigh : g_rangeLow;
    g_orderMeta[idx].levelTime  = highLevel ? g_rangeHighTime : g_rangeLowTime;
    g_orderMeta[idx].rangeStart = g_rangeStart;
    g_orderMeta[idx].rangeEnd   = g_rangeEnd;
    g_orderMeta[idx].expiry     = EffectiveSlotCutoffServer(TimeCurrent());

    GlobalVariableSet(OrderMetaKey(ticket, "SLOT"), (double)g_ctxSlotIdx);
    GlobalVariableSet(OrderMetaKey(ticket, "KEY"), (double)ORBHash(g_sessionKey));
    GlobalVariableSet(OrderMetaKey(ticket, "HIGH"), highLevel ? 1.0 : 0.0);
    GlobalVariableSet(OrderMetaKey(ticket, "EXP"), (double)g_orderMeta[idx].expiry);
}

bool CurrentSlotOwnsOrder(ulong ticket)
{
    int idx = OrderMetaIdx(ticket);
    if(idx < 0)
    {
        string slotKey = OrderMetaKey(ticket, "SLOT");
        string sessKey = OrderMetaKey(ticket, "KEY");
        if(GlobalVariableCheck(slotKey))
        {
            int slot = (int)GlobalVariableGet(slotKey);
            if(slot != g_ctxSlotIdx) return false;
            if(GlobalVariableCheck(sessKey))
                return ((uint)GlobalVariableGet(sessKey) == ORBHash(g_sessionKey));
            return true;
        }
        string c = OrderGetString(ORDER_COMMENT);
        int slot = ParseOrderSlot(c);
        if(slot < 0) return true; // pre-upgrade order: fall back to legacy magic ownership
        if(slot != g_ctxSlotIdx) return false;
        string key = ParseOrderSessionKey(c);
        if(key == "") return true;
        if(key == g_sessionKey) return true;
        return (key == StringFormat("%08X", ORBHash(g_sessionKey)));
    }
    return (g_orderMeta[idx].slotIdx == g_ctxSlotIdx &&
            g_orderMeta[idx].sessionKey == g_sessionKey);
}

bool CurrentSlotOwnsOrderAnySession(ulong ticket)
{
    int idx = OrderMetaIdx(ticket);
    if(idx >= 0) return (g_orderMeta[idx].slotIdx == g_ctxSlotIdx);

    string slotKey = OrderMetaKey(ticket, "SLOT");
    if(GlobalVariableCheck(slotKey))
        return ((int)GlobalVariableGet(slotKey) == g_ctxSlotIdx);

    string c = OrderGetString(ORDER_COMMENT);
    int slot = ParseOrderSlot(c);
    return (slot < 0 || slot == g_ctxSlotIdx);
}

bool GetOrderMeta(ulong ticket, OrderMeta &meta)
{
    int idx = OrderMetaIdx(ticket);
    if(idx >= 0)
    {
        meta = g_orderMeta[idx];
        return true;
    }

    string slotKey = OrderMetaKey(ticket, "SLOT");
    if(!GlobalVariableCheck(slotKey)) return false;

    meta.ticket = ticket;
    meta.slotIdx = (int)GlobalVariableGet(slotKey);
    int savedSlot = g_ctxSlotIdx;
    SetSlotContext(meta.slotIdx);
    meta.sessionKey = ActiveSessionKey(TimeCurrent());
    SetSlotContext(savedSlot);
    meta.highLevel = GlobalVariableCheck(OrderMetaKey(ticket, "HIGH")) && GlobalVariableGet(OrderMetaKey(ticket, "HIGH")) > 0.5;
    meta.levelPx = 0.0;
    meta.levelTime = 0;
    meta.rangeStart = 0;
    meta.rangeEnd = 0;
    meta.expiry = GlobalVariableCheck(OrderMetaKey(ticket, "EXP")) ? (datetime)GlobalVariableGet(OrderMetaKey(ticket, "EXP")) : 0;
    return true;
}

void PruneOrderMeta()
{
    for(int i = ArraySize(g_orderMeta)-1; i >= 0; i--)
    {
        ulong t = g_orderMeta[i].ticket;
        bool live = false;
        if(OrderSelect(t)) live = true;
        else if(PositionSelectByTicket(t)) live = true;
        if(live) continue;
        GlobalVariableDel(OrderMetaKey(t, "SLOT"));
        GlobalVariableDel(OrderMetaKey(t, "KEY"));
        GlobalVariableDel(OrderMetaKey(t, "HIGH"));
        GlobalVariableDel(OrderMetaKey(t, "EXP"));
        for(int j = i; j < ArraySize(g_orderMeta)-1; j++) g_orderMeta[j] = g_orderMeta[j+1];
        ArrayResize(g_orderMeta, ArraySize(g_orderMeta)-1);
    }
}

void ClaimAndRegisterLastOrder(bool highLevel, datetime overrideLevelTime = 0)
{
    ulong ticket = trade.ResultOrder();
    if(ticket > 0)
    {
        ClaimTicket(ticket);
        if(overrideLevelTime > 0)
        {
            RegisterOrderMetaSnapshot(ticket, g_ctxSlotIdx, g_sessionKey, highLevel,
                                      highLevel ? g_rangeHigh : g_rangeLow, overrideLevelTime,
                                      g_rangeStart, g_rangeEnd, EffectiveSlotCutoffServer(TimeCurrent()));
        }
        else
        {
            RegisterOrderMeta(ticket, highLevel);
        }
    }
}

void RegisterOrderMetaSnapshot(ulong ticket, int slotIdx, string sessionKey, bool highLevel,
                               double levelPx, datetime levelTime,
                               datetime rangeStart, datetime rangeEnd, datetime expiry)
{
    if(ticket == 0) return;
    int idx = OrderMetaIdx(ticket);
    if(idx < 0) { idx = ArraySize(g_orderMeta); ArrayResize(g_orderMeta, idx + 1); }
    g_orderMeta[idx].ticket     = ticket;
    g_orderMeta[idx].slotIdx    = slotIdx;
    g_orderMeta[idx].sessionKey = sessionKey;
    g_orderMeta[idx].highLevel  = highLevel;
    g_orderMeta[idx].levelPx    = levelPx;
    g_orderMeta[idx].levelTime  = levelTime;
    g_orderMeta[idx].rangeStart = rangeStart;
    g_orderMeta[idx].rangeEnd   = rangeEnd;
    g_orderMeta[idx].expiry     = expiry;

    GlobalVariableSet(OrderMetaKey(ticket, "SLOT"), (double)slotIdx);
    GlobalVariableSet(OrderMetaKey(ticket, "KEY"), (double)ORBHash(sessionKey));
    GlobalVariableSet(OrderMetaKey(ticket, "HIGH"), highLevel ? 1.0 : 0.0);
    GlobalVariableSet(OrderMetaKey(ticket, "EXP"), (double)expiry);
}

void SaveGlobalsToSlot(int s)
{
    g_slotState[s].sessionKey          = g_sessionKey;
    g_slotState[s].rangeReady          = g_rangeReady;
    g_slotState[s].rangeHigh           = g_rangeHigh;
    g_slotState[s].rangeLow            = g_rangeLow;
    g_slotState[s].rangeStart          = g_rangeStart;
    g_slotState[s].rangeEnd            = g_rangeEnd;
    g_slotState[s].rangeHighTime       = g_rangeHighTime;
    g_slotState[s].rangeLowTime        = g_rangeLowTime;
    g_slotState[s].buyPlaced           = g_buyPlaced;
    g_slotState[s].sellPlaced          = g_sellPlaced;
    g_slotState[s].buySendPending      = g_buySendPending;
    g_slotState[s].sellSendPending     = g_sellSendPending;
    g_slotState[s].buySendTime         = g_buySendTime;
    g_slotState[s].sellSendTime        = g_sellSendTime;
    g_slotState[s].precloseArmed       = g_precloseArmed;
    g_slotState[s].mktClosedPendingHigh   = g_mktClosedPendingHigh;
    g_slotState[s].mktClosedPendingLow    = g_mktClosedPendingLow;
    g_slotState[s].mktClosedLastAskHigh   = g_mktClosedLastAskHigh;
    g_slotState[s].mktClosedLastBidLow    = g_mktClosedLastBidLow;
    g_slotState[s].mktClosedLastCheckHigh = g_mktClosedLastCheckHigh;
    g_slotState[s].mktClosedLastCheckLow  = g_mktClosedLastCheckLow;    g_slotState[s].buildKey            = g_rangeBuildKey;
    g_slotState[s].buildStart          = g_rangeBuildStart;
    g_slotState[s].buildEnd            = g_rangeBuildEnd;
    g_slotState[s].buildHigh           = g_rangeBuildHigh;
    g_slotState[s].buildLow            = g_rangeBuildLow;
    g_slotState[s].buildHighTime       = g_rangeBuildHighTime;
    g_slotState[s].buildLowTime        = g_rangeBuildLowTime;
    g_slotState[s].buildReady          = g_rangeBuildReady;
}

void LoadSlotToGlobals(int s)
{
    g_sessionKey          = g_slotState[s].sessionKey;
    g_rangeReady          = g_slotState[s].rangeReady;
    g_rangeHigh           = g_slotState[s].rangeHigh;
    g_rangeLow            = g_slotState[s].rangeLow;
    g_rangeStart          = g_slotState[s].rangeStart;
    g_rangeEnd            = g_slotState[s].rangeEnd;
    g_rangeHighTime       = g_slotState[s].rangeHighTime;
    g_rangeLowTime        = g_slotState[s].rangeLowTime;
    g_buyPlaced           = g_slotState[s].buyPlaced;
    g_sellPlaced          = g_slotState[s].sellPlaced;
    g_buySendPending      = g_slotState[s].buySendPending;
    g_sellSendPending     = g_slotState[s].sellSendPending;
    g_buySendTime         = g_slotState[s].buySendTime;
    g_sellSendTime        = g_slotState[s].sellSendTime;
    g_precloseArmed       = g_slotState[s].precloseArmed;
    g_mktClosedPendingHigh   = g_slotState[s].mktClosedPendingHigh;
    g_mktClosedPendingLow    = g_slotState[s].mktClosedPendingLow;
    g_mktClosedLastAskHigh   = g_slotState[s].mktClosedLastAskHigh;
    g_mktClosedLastBidLow    = g_slotState[s].mktClosedLastBidLow;
    g_mktClosedLastCheckHigh = g_slotState[s].mktClosedLastCheckHigh;
    g_mktClosedLastCheckLow  = g_slotState[s].mktClosedLastCheckLow;    g_rangeBuildKey       = g_slotState[s].buildKey;
    g_rangeBuildStart     = g_slotState[s].buildStart;
    g_rangeBuildEnd       = g_slotState[s].buildEnd;
    g_rangeBuildHigh      = g_slotState[s].buildHigh;
    g_rangeBuildLow       = g_slotState[s].buildLow;
    g_rangeBuildHighTime  = g_slotState[s].buildHighTime;
    g_rangeBuildLowTime   = g_slotState[s].buildLowTime;
    g_rangeBuildReady     = g_slotState[s].buildReady;
    // Restore context
    g_ctxMode      = g_slotState[s].ctxMode;
    g_ctxHour      = g_slotState[s].ctxHour;
    g_ctxMin       = g_slotState[s].ctxMin;
    g_ctxCutoffMin = g_slotState[s].ctxCutoffMin;
    g_ctxSlotIdx   = s;
}

// Per-trade virtual tracking.
// MANAGEMENT-SNAPSHOT MODEL: every managed position carries its OWN geometry
// (gap/threshold/mode/min-trail-minutes/magic-at-open), captured at adoption.
// Management reads ONLY this snapshot, never the live inputs, so changing the
// EA configuration, session, or timeframe mid-trade can never orphan or
// mis-manage an already-open position. Survives relaunch via re-adoption.
struct VirtualTrade
{
    ulong    ticket;
    bool     active;
    bool     bull;
    double   entryPx;
    double   vSL;
    double   vTP;
    bool     trailing;
    datetime triggerTime;
    datetime trailStartTime;
    datetime exitTime;
    double   levelPx;
    datetime levelTime;
    datetime levelRangeStart;
    datetime levelRangeEnd;
    int      slotIdx;
    string   sessionKey;
    double   snapThreshRaw;
    double   snapGapRaw;
    int      snapTrailMode;
    int      snapMinTrailSec;
    int      snapBehavior;
    bool     snapSpreadComp;
    double   snapEntrySpreadRaw;
    double   snapBECostRaw;      // auto-detected commission, raw price units (0 if Use_Spread_Compensation is off) - replaces the old manual BE_Cost_Points input
    long     snapMagic;
    bool     closing;
    int      trailCount;        // trail steps fired (for Signal 3)
    double   lastTrailSL;       // SL at most recent trail step
    bool     trailFrozenLogged;
    bool     slipForceCloseArmed;   // excess-slip trade: trailing disabled, close only at +profit
    uint     lastModifyAttemptMs;   // GetTickCount() of the last PositionModify send, for debouncing
    bool     modifyInFlight;        // an async modify was sent and hasn't been confirmed/timed-out yet
};
VirtualTrade vTrades[];

int GetVTIdx(ulong ticket)
{
    for(int i = 0; i < ArraySize(vTrades); i++)
        if(vTrades[i].ticket == ticket) return i;
    return -1;
}

bool HasCurrentRangeTrade()
{
    // Only count positions whose range-formation candle fell within the CURRENT session
    // range window. Price-proximity alone is insufficient - a prior session position
    // near the same price level would falsely block new session orders.
    if(g_rangeStart <= 0 || g_rangeEnd <= 0) return false;
    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        if(!vTrades[i].active) continue;
        if(vTrades[i].slotIdx != g_ctxSlotIdx || vTrades[i].sessionKey != g_sessionKey) continue;
        if(vTrades[i].levelTime > 0 &&
           vTrades[i].levelTime >= g_rangeStart && vTrades[i].levelTime <= g_rangeEnd) return true;
    }
    return false;
}
// Snapshot the CURRENT live management params onto a trade exactly once, at
// adoption time. After this, the trade is managed off the snapshot only.
void SnapshotManagement(int idx)
{
    vTrades[idx].snapThreshRaw   = TrailThreshRaw();
    vTrades[idx].snapGapRaw      = TrailGapRaw();
    vTrades[idx].snapTrailMode   = (int)Trail_Mode;
    vTrades[idx].snapMinTrailSec = (int)MathMax(0.0, Min_Trail_Minutes * 60.0);
    vTrades[idx].snapBehavior    = (int)Trail_Behavior;
    vTrades[idx].snapSpreadComp  = Use_Spread_Compensation;
    vTrades[idx].snapBECostRaw   = Use_Spread_Compensation ? CommissionRawPriceOffset() : 0.0;
    vTrades[idx].closing         = false;
}

void RegisterVT(ulong ticket, bool bull, double entry, double vSL, double vTP, datetime trig,
                double levelPx = 0.0, datetime levelTime = 0, int slotIdx = -1, string sessionKey = "",
                datetime levelRangeStart = 0, datetime levelRangeEnd = 0)
{
    int idx = GetVTIdx(ticket);
    bool isNew = (idx < 0);
    if(isNew) { idx = ArraySize(vTrades); ArrayResize(vTrades, idx+1); }

    vTrades[idx].ticket        = ticket;
    vTrades[idx].active        = true;
    vTrades[idx].bull          = bull;
    vTrades[idx].entryPx       = entry;
    vTrades[idx].exitTime      = 0;
    vTrades[idx].levelPx       = (levelPx > 0.0) ? levelPx : entry;
    vTrades[idx].levelTime     = levelTime;
    vTrades[idx].levelRangeStart = (levelRangeStart > 0) ? levelRangeStart : g_rangeStart;
    vTrades[idx].levelRangeEnd   = (levelRangeEnd > 0) ? levelRangeEnd : g_rangeEnd;
    vTrades[idx].slotIdx       = (slotIdx >= 0) ? slotIdx : g_ctxSlotIdx;
    vTrades[idx].sessionKey    = (sessionKey != "") ? sessionKey : g_sessionKey;
    vTrades[idx].snapMagic     = EffectiveMagic();
    string slipArmKey = StringFormat("ORB_SLIPARM_%I64u", ticket);
    vTrades[idx].slipForceCloseArmed = GlobalVariableCheck(slipArmKey);
    if(vTrades[idx].slipForceCloseArmed) GlobalVariableDel(slipArmKey);

    if(isNew)
    {
        // First registration: initialise all trail state from scratch.
        vTrades[idx].vSL              = vSL;
        vTrades[idx].vTP              = vTP;
        vTrades[idx].snapEntrySpreadRaw = MathMax(0.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
        vTrades[idx].trailing         = false;
        vTrades[idx].triggerTime      = trig;
        vTrades[idx].trailStartTime   = 0;
        vTrades[idx].trailCount       = 0;
        vTrades[idx].lastTrailSL      = 0.0;
        vTrades[idx].trailFrozenLogged = false;
        vTrades[idx].lastModifyAttemptMs = 0;
        vTrades[idx].modifyInFlight   = false;
        SnapshotManagement(idx);
    }
    else
    {
        // Re-registration of a known position (OnTradeTransaction re-adoption,
        // OnInit restart, or delayed fill confirm). Preserve all trailing state
        // so that a position already in profit continues to trail without
        // interruption. Only refresh the SL/TP from the broker's live values
        // (the position may have been modified by a prior trail step).
        if(posInfo.SelectByTicket(ticket))
        {
            double liveSL = posInfo.StopLoss();
            double liveTP = posInfo.TakeProfit();
            // Accept the broker's live SL if it is more favourable (i.e. trailing
            // has already moved it) or if our local vSL is stale (== 0).
            if(vTrades[idx].vSL <= 0.0 ||
               (bull  && liveSL > vTrades[idx].vSL) ||
               (!bull && liveSL > 0.0 && liveSL < vTrades[idx].vSL))
                vTrades[idx].vSL = liveSL;
            if(liveTP > 0.0) vTrades[idx].vTP = liveTP;
        }
        // Refresh management snapshot so fresh inputs (e.g., if user changes
        // Trail_Mode or Trail_Behavior while a position is open) take effect
        // on NEXT interval.  The trail THRESHOLD and GAP snapshots are preserved
        // (they were frozen at adoption) so only the mode/behavior overrides.
        // *** Do NOT reset trailing / trailCount / lastTrailSL here ***
    }
}

//+------------------------------------------------------------------+
//| Persistent per-level "consumed" ledger (phantom re-fire fix #4)   |
//| A level (High/Low) gets ONE trade per session-day. Once triggered |
//| or otherwise spent, it is marked consumed in an MT5 GLOBAL VAR,   |
//| which survives EA removal/reattach, timeframe change, and full    |
//| terminal restart. This stops the EA from re-arming an already-    |
//| resolved order when re-initialized (observed: BTC sell re-fired   |
//| after the chart was removed and re-added).                        |
//| Key is hash-shortened to stay inside MT5 global-variable limits.  |
//| It blocks RE-PLACEMENT only; it never blocks MANAGING an open      |
//| position (adoption handles that independently).                   |
//+------------------------------------------------------------------+
string ConsumedKey(string sessionKey, bool bull)
{
    string raw = StringFormat("%s_%I64d_%s_%s_%s",
                              _Symbol, EffectiveMagic(), InstanceKey(), sessionKey, bull ? "B" : "S");
    return StringFormat("OD_%08X_%s", ORBHash(raw), bull ? "B" : "S");
}
bool SideConsumed(string sessionKey, bool bull)
{
    return GlobalVariableCheck(ConsumedKey(sessionKey, bull));
}
void MarkSideConsumed(string sessionKey, bool bull)
{
    GlobalVariableSet(ConsumedKey(sessionKey, bull), (double)TimeCurrent());
}

bool IsHighLevelPosition(bool bull)
{
    return Reverse_Orders ? !bull : bull;
}

bool IsHighLevelPrice(double price)
{
    if(g_rangeHigh <= 0.0 || g_rangeLow <= 0.0) return true;
    return MathAbs(price - g_rangeHigh) <= MathAbs(price - g_rangeLow);
}

void ClearPendingSendLocks()
{
    g_buySendPending = false;
    g_sellSendPending = false;
    g_buySendTime = 0;
    g_sellSendTime = 0;
}

void SyncPlacedFlagsFromLiveOrders()
{
    if(!g_rangeReady) return;

    bool highLive = false;
    bool lowLive  = false;

    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!OwnsTicket(ticket)) continue;
        if(!CurrentSlotOwnsOrder(ticket)) continue;

        ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(ot != ORDER_TYPE_BUY_STOP && ot != ORDER_TYPE_SELL_STOP &&
           ot != ORDER_TYPE_BUY_LIMIT && ot != ORDER_TYPE_SELL_LIMIT &&
           ot != ORDER_TYPE_BUY_STOP_LIMIT && ot != ORDER_TYPE_SELL_STOP_LIMIT) continue;

        if(IsHighLevelPrice(OrderGetDouble(ORDER_PRICE_OPEN))) highLive = true;
        else lowLive = true;
    }


    // BUG-FIX: When a pending order FILLS it leaves OrdersTotal and enters PositionsTotal.
    // Without this scan, highLive/lowLive becomes false on the next tick and the reinstate
    // path resets g_buyPlaced/g_sellPlaced to false, causing a duplicate order to be placed.
    // Fix: any active vTrade whose level fell within the CURRENT session range also counts as "live".
    for(int vj = 0; vj < ArraySize(vTrades); vj++)
    {
        if(!vTrades[vj].active) continue;
        if(vTrades[vj].slotIdx != g_ctxSlotIdx || vTrades[vj].sessionKey != g_sessionKey) continue;
        // Only count positions whose level candle is within the current session range window.
        if(vTrades[vj].levelTime <= 0 || g_rangeStart <= 0) continue;
        if(vTrades[vj].levelTime < g_rangeStart || vTrades[vj].levelTime > g_rangeEnd) continue;
        if(IsHighLevelPrice(vTrades[vj].levelPx)) highLive = true;
        else lowLive = true;
    }
        if(highLive) g_buyPlaced = true;
    if(lowLive) g_sellPlaced = true;

    datetime now = TimeCurrent();
    if(highLive) g_buySendPending = false;
    else if(g_buySendPending && (now - g_buySendTime) > 60) g_buySendPending = false;

    if(lowLive) g_sellSendPending = false;
    else if(g_sellSendPending && (now - g_sellSendTime) > 60) g_sellSendPending = false;

    if(!highLive && !g_buySendPending && g_buyPlaced && !SideConsumed(g_sessionKey, true))
        g_buyPlaced = false; // auto-reinstate manually deleted pending

    if(!lowLive && !g_sellSendPending && g_sellPlaced && !SideConsumed(g_sessionKey, false))
        g_sellPlaced = false; // auto-reinstate manually deleted pending
}

string ConfigSigKey()
{
    string raw = StringFormat("%s_%I64d_%s", _Symbol, EffectiveMagic(), InstanceKey());
    return StringFormat("OC_%08X", ORBHash(raw));
}

uint ConfigSigHash(const string sig)
{
    uint hash = (uint)0x811C9DC5;
    for(int i = 0; i < StringLen(sig); i++)
    {
        hash ^= (uint)StringGetCharacter(sig, i);
        hash *= 16777619;
    }
    return hash;
}

// Prune ledger markers older than ~2 days so globals never accumulate.
void PruneConsumedLedger()
{
    datetime cutoff = TimeCurrent() - 2*86400;
    int total = GlobalVariablesTotal();
    for(int i = total-1; i >= 0; i--)
    {
        string nm = GlobalVariableName(i);
        if(StringFind(nm, "OD_") != 0) continue;
        if((datetime)GlobalVariableGet(nm) < cutoff) GlobalVariableDel(nm);
    }
}

//+------------------------------------------------------------------+
//| Point utilities - auto-scale for 3/5 digit brokers               |
//+------------------------------------------------------------------+
// - Universal tick-anchored point system -
// "1 normalized point" = broker tickSize x scale factor.
// Digit-count-proof and broker-agnostic: derives geometry from the
// broker-reported tickSize (verified sane via diagnostics), never from
// symbol-name guesses or decimal-place counting.
//   BASE: scale = 10   (validated default geometry, e.g. NQ 200pts = 20.0 price units)
//   WIDE: scale = 100  (one decimal higher, uniform on every asset)
//
// BTC-CLASS WIDENING (Option A, no symbol names): instruments whose PRICE is
// very high (>= $40,000) need one decimal MORE scale, because a 20-price-unit
// stop on a $62,000 instrument is noise-level and stops out constantly
// (observed: BTC -$163 on a ~26-unit SL). The $40k gate is chosen so it can
// NEVER fire for NQ (~30k), Gold (~4.3k) or SPX (~6k) - those keep the exact
// validated 10/100 scale. Only BTC-class (and similarly-priced) instruments
// get the x10 widening: BASE -> 100, WIDE -> 1000.
double NormScaleFactor()
{
    double base = (Point_Scale_Mode == SCALE_WIDE) ? 100.0 : 10.0;

    // Price-magnitude gate. Use last price (bid); fall back to a recent close so
    // the value is stable even on the first tick / quiet charts.
    double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(px <= 0.0) px = iClose(_Symbol, PERIOD_M1, 0);
    if(px <= 0.0) px = iClose(_Symbol, PERIOD_CURRENT, 0);

    if(px >= 40000.0) base *= 10.0;   // BTC-class only; NQ/Gold/SPX excluded by threshold

    return base;
}
// "1 normalized point" anchored to a MEANINGFUL move, digit-count-proof.
// REGRESSION FIX: the prior tickSize-only definition made geometry ~100x
// too tight on indices/metals (e.g. NQ SL of 2.0 price units), so broker
// min-stop checks rejected orders and no trades formed in the tester.
// Restore the working baseline scale: 1 point = 1.0 price unit for
// index/metal/crypto, pip-scale for FX, derived WITHOUT symbol-name guesses.
double NormPoint()
{
    // Validated geometry (5f7971e0): "1 normalized point" = tickSize x scale.
    // Digit-count-proof and broker-agnostic; no symbol-name guessing.
    // On NQ (tickSize=0.01): BASE -> 0.1, so Fixed_SL_Points=200 = 20.0 price
    // units (the validated 20pt SL). WIDE (x100) -> 1.0 (one decimal higher).
    // ABSOLUTE override: when set (>0), ONE NORM POINT = exactly this price
    // distance. No scale multiplication, no BTC gate - what you type is what
    // you get (e.g. 0.01 on a 2-digit gold feed reproduces a 3-digit
    // Exness-style feed's geometry).
    if(Custom_Point_Multiplier > 0.0) return Custom_Point_Multiplier;

    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSize <= 0.0) tickSize = _Point;   // safe fallback
    if(tickSize <= 0.0) tickSize = 0.0001;   // last-resort fallback

    return tickSize * NormScaleFactor();
}
double PtsToRaw(double pts)  { return pts * NormPoint(); }
double RawToPts(double raw)  { double pt = NormPoint(); return (pt > 0.0) ? raw / pt : raw; }
double TrailPtsToRaw(double pts) { return PtsToRaw(pts); }
double SLRaw()               { return PtsToRaw(Fixed_SL_Points); }
double TPRaw()               { return PtsToRaw(Fixed_TP_Points); }
double TrailThreshRaw()      { return TrailPtsToRaw(Trail_Threshold_Points); }


// Short, unambiguous tag for trade comments: distinguishes every S0
// (NY / LDN / ASIA intraday) and S1 (DAILY / WEEKLY) case so a comment
// never has to be cross-referenced against inputs to identify it.
// (A MONTHLY branch is added here when the Monthly-mode patch lands.)
string SessionTag()
{
    if(g_ctxMode == RANGE_DAILY)   return "DAILY";
    if(g_ctxMode == RANGE_WEEKLY)  return "Weekly";
    if(g_ctxMode == RANGE_MONTHLY) return "MONTHLY";
    if(g_ctxSlotIdx == 1) return "LDN";
    if(g_ctxSlotIdx == 2) return "ASIA";
    return "NY";
}

// Human-readable session label for notifications: "NY 08:00", "Daily", "Weekly".
// Must be called while the correct slot context is loaded.
string SessionLabel()
{
    if(g_ctxMode == RANGE_DAILY)   return "Daily";
    if(g_ctxMode == RANGE_WEEKLY)  return "Weekly";
    if(g_ctxMode == RANGE_MONTHLY) return "Monthly";
    string sess = (g_ctxSlotIdx==1) ? "London" : (g_ctxSlotIdx==2) ? "Asian" : "NY";
    return StringFormat("%s %02d:%02d", sess, g_ctxHour, g_ctxMin);
}
double TrailGapRaw()
{
    // Gap = distance the stop stays behind price after activation.
    double gapRaw = TrailPtsToRaw(Trail_Gap_Points);
    double thrRaw = TrailThreshRaw();
    if(gapRaw <= 0.0)    gapRaw = TrailPtsToRaw(2.0); // sane default if misconfigured
    if(gapRaw >  thrRaw) gapRaw = thrRaw;        // gap cannot exceed threshold
    return gapRaw;
}

//+------------------------------------------------------------------+
//| Risk-based position sizing                                       |
//+------------------------------------------------------------------+
double GetRiskCapital()
{
    if(Custom_Balance_Override > 0.0) return Custom_Balance_Override;
    if(Risk_Basis == RISK_BASIS_EQUITY) return AccountInfoDouble(ACCOUNT_EQUITY);
    if(Risk_Basis == RISK_BASIS_MARGIN) return AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    return AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
//| Stealth-aware logging -  ALL journal output goes through here     |
//| When stealth is ON: zero output to Experts tab, zero comments.   |
//+------------------------------------------------------------------+
void ORBLog(string msg)
{
    if(Inp_StealthMode) return;
    if(!Verbose_Journal) return;
    Print(msg);
}

bool IsPendingOrderType(ENUM_ORDER_TYPE ot)
{
    return (ot == ORDER_TYPE_BUY_STOP  || ot == ORDER_TYPE_SELL_STOP ||
            ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT);
}

// Slot2OpenAt/Slot2CutoffFromOpen (removed): these hardcoded 'slot 1 = the
// HTF slot' from the old 2-slot scheme. Under the fixed 6-slot mapping, slot 1
// is London (intraday) and Daily/Weekly/Monthly each have their own slot
// (3/4/5), so that assumption no longer holds for any slot index. The
// fallback below is disabled rather than given a wrong per-slot answer - the
// primary meta.expiry mechanism in CancelExpiredPendingOrders (which already
// uses the correct per-slot cutoff via EffectiveSlotCutoffServer) covers the
// normal case; this was only ever a secondary check for orders placed before
// metadata existed.
bool FallbackPendingExpired(ulong ticket, datetime now, string &reason)
{
    return false;
}

void CancelExpiredPendingOrders()
{
    static datetime s_globalBlockUntil = 0;
    datetime now = TimeCurrent();
    if(now < s_globalBlockUntil) return;

    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!OwnsTicket(ticket)) continue;

        string c = OrderGetString(ORDER_COMMENT);
        int slot = ParseOrderSlot(c);
        if(slot >= 0 && !SlotEnabled(slot)) continue;

        ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(!IsPendingOrderType(ot)) continue;

        string reason = "model cutoff";
        OrderMeta meta;
        bool expired = (GetOrderMeta(ticket, meta) && meta.expiry > 0 && now >= meta.expiry);
        if(!expired)
            expired = FallbackPendingExpired(ticket, now, reason);
        if(!expired) continue;

        if(trade.OrderDelete(ticket))
        {
            ORBLog(StringFormat("[ORB] Expired pending order #%llu (%s).", ticket, reason));
        }
        else
        {
            uint rc = trade.ResultRetcode();
            if(IsMarketClosedRetcode(rc))
            {
                s_globalBlockUntil = now + 60;
                ORBLog(StringFormat("[ORB] Pending order #%llu deletion failed (market closed). Pausing retries for 60s.", ticket));
                return;
            }
        }
    }
    PruneOrderMeta();
}

// True cash risked by 1.0 lot over a price distance of |slRaw|, in account
// currency. Broker-agnostic and immune to a misreported SYMBOL_TRADE_TICK_VALUE
// (e.g. FundingPips gold reports tickValue=0.01 for a contractSize=100 symbol,
// which under-states risk by 100x). Strategy:
//   1) PRIMARY: OrderCalcProfit over the exact SL distance - the broker computes
//      real loss including contract size and quote-currency conversion.
//   2) FALLBACK: max of the tickValue-based and (tickSize*contractSize)-based
//      cash-per-lot, so an under-reported tickValue can never inflate the lot.
double CashPerLotForDistance(double slRaw)
{
    if(slRaw <= 0.0) return 0.0;
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(ask <= 0.0) ask = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // PRIMARY: ask the broker the real loss for 1 lot moving against us by slRaw.
    double loss = 0.0;
    if(ask > 0.0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, ask, ask - slRaw, loss))
    {
        double cash = MathAbs(loss);
        if(cash > 0.0) return cash;
    }

    // FALLBACK: never trust a tickValue that disagrees with contract-size math.
    double byTick     = (tickSize > 0.0) ? (slRaw / tickSize) * tickValue : 0.0;
    double byContract = slRaw * contract;          // price-distance * units per lot
    double cashPerLot = MathMax(byTick, byContract);
    return cashPerLot;
}

double ObservedCommissionPerLot()
{
    if(!Use_Commission_Buffer) return 0.0;
    if(Commission_Per_Lot_Override > 0.0) return Commission_Per_Lot_Override;

    static datetime s_checked = 0;
    static double   s_value = 0.0;
    datetime now = TimeCurrent();
    if(s_checked > 0 && now - s_checked < 3600) return s_value;
    s_checked = now;
    s_value = 0.0;

    datetime from = now - 180 * 86400;
    if(!HistorySelect(from, now)) return 0.0;

    double bestRoundTurn = 0.0;
    ulong posIds[];
    double posComm[];
    double posInVol[];
    double posOutVol[];

    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong deal = HistoryDealGetTicket(i);
        if(deal == 0) continue;
        if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;

        double vol = HistoryDealGetDouble(deal, DEAL_VOLUME);
        double comm = MathAbs(HistoryDealGetDouble(deal, DEAL_COMMISSION));
        if(vol <= 0.0 || comm <= 0.0) continue;

        ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
        ulong pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
        int idx = -1;
        for(int j = 0; j < ArraySize(posIds); j++)
            if(posIds[j] == pid) { idx = j; break; }
        if(idx < 0)
        {
            idx = ArraySize(posIds);
            ArrayResize(posIds, idx + 1);
            ArrayResize(posComm, idx + 1);
            ArrayResize(posInVol, idx + 1);
            ArrayResize(posOutVol, idx + 1);
            posIds[idx] = pid;
            posComm[idx] = 0.0;
            posInVol[idx] = 0.0;
            posOutVol[idx] = 0.0;
        }

        posComm[idx] += comm;
        if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT) posInVol[idx] += vol;
        if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY) posOutVol[idx] += vol;
    }

    double openOnlyMax = 0.0;
    for(int i = 0; i < ArraySize(posIds); i++)
    {
        if(posInVol[i] > 0.0)
            openOnlyMax = MathMax(openOnlyMax, posComm[i] / posInVol[i]);
        if(posInVol[i] > 0.0 && posOutVol[i] > 0.0)
            bestRoundTurn = MathMax(bestRoundTurn, posComm[i] / posInVol[i]);
    }

    s_value = (bestRoundTurn > 0.0) ? bestRoundTurn : openOnlyMax;
    if(!Inp_StealthMode && Verbose_Journal && s_value > 0.0)
        ORBLog(StringFormat("[ORB] Commission buffer learned: %.2f account-currency per 1.0 lot round turn.", s_value));
    return s_value;
}

// Converts the auto-detected round-turn commission (account currency per lot)
// into a raw price distance - independent of actual position size, since
// commission-per-lot and cash-per-point-per-lot both scale with lot size
// identically and cancel out. Inverts the existing, broker-accurate
// CashPerLotForDistance() rather than re-deriving the tick/contract math.
double CommissionRawPriceOffset()
{
    double commPerLot = ObservedCommissionPerLot();
    if(commPerLot <= 0.0) return 0.0;
    double cashPerPointLot = CashPerLotForDistance(_Point);
    if(cashPerPointLot <= 0.0) return 0.0;
    return commPerLot * _Point / cashPerPointLot;
}

double CalcLots(double slRaw)
{
    // Universal risk sizing for ALL asset classes (forex, indices, metals,
    // crypto), driven by the broker's TRUE cash-per-lot for the SL distance.
    double riskMoney  = GetRiskCapital() * (Risk_Percent / 100.0);
    double cashPerLot = CashPerLotForDistance(slRaw);
    cashPerLot += ObservedCommissionPerLot();
    if(cashPerLot <= 0.0 || slRaw <= 0.0 || riskMoney <= 0.0) return 0.0;
    double lots = riskMoney / cashPerLot;
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(step <= 0.0) step = 0.01;
    lots = MathFloor(lots / step) * step;
    if(lots < mn) return 0.0;
    lots = MathMax(mn, MathMin(mx, lots));

    // HARD RISK CEILING: after step-rounding/clamping, verify the chosen lot's
    // actual risk never exceeds the budget. If broker minimum lot would exceed
    // the budget, CalcLots already returned 0.0 and the order is skipped.
    double realRisk = lots * cashPerLot;
    if(realRisk > riskMoney && lots > mn)
    {
        double capped = MathFloor((riskMoney / cashPerLot) / step) * step;
        if(capped >= mn) lots = capped;
    }
    if(!Inp_StealthMode)
        ORBLog(StringFormat("[ORB] CalcLots: risk=$%.2f slRaw=%.5f cashPerLot=%.2f lots=%.2f (realRisk=$%.2f)",
                            riskMoney, slRaw, cashPerLot, lots, lots*cashPerLot));
    return lots;
}

//+------------------------------------------------------------------+
//| Asset-class classifier (for per-market lot caps).                |
//| Structure-first: forex is detected by the 6-letter A/B currency  |
//| shape; metals/crypto/indices by well-known roots; everything else |
//| falls to OTHER. Returns: 0=FX 1=Metals 2=Indices 3=Crypto 4=Other |
//+------------------------------------------------------------------+
bool _ContainsAny(string hay, string &needles[])
{
    string up = hay; StringToUpper(up);
    for(int i = 0; i < ArraySize(needles); i++)
        if(StringFind(up, needles[i]) >= 0) return true;
    return false;
}
int AssetClass()
{
    string s = _Symbol; StringToUpper(s);

    string metals[]; ArrayResize(metals,6);
    metals[0]="XAU"; metals[1]="XAG"; metals[2]="GOLD"; metals[3]="SILVER"; metals[4]="XPT"; metals[5]="XPD";
    if(_ContainsAny(s, metals)) return 1;

    string crypto[]; ArrayResize(crypto,8);
    crypto[0]="BTC"; crypto[1]="ETH"; crypto[2]="XRP"; crypto[3]="SOL"; crypto[4]="LTC"; crypto[5]="DOGE"; crypto[6]="ADA"; crypto[7]="BNB";
    if(_ContainsAny(s, crypto)) return 3;

    string idx[]; ArrayResize(idx,12);
    idx[0]="US100"; idx[1]="USTEC"; idx[2]="NAS"; idx[3]="NDX"; idx[4]="US500"; idx[5]="SPX";
    idx[6]="US30"; idx[7]="DJ"; idx[8]="GER"; idx[9]="DAX"; idx[10]="UK100"; idx[11]="JP225";
    if(_ContainsAny(s, idx)) return 2;

    // Forex: 6 alpha chars forming two known ISO currency codes.
    string ccy[]; ArrayResize(ccy,8);
    ccy[0]="USD"; ccy[1]="EUR"; ccy[2]="GBP"; ccy[3]="JPY"; ccy[4]="AUD"; ccy[5]="CAD"; ccy[6]="CHF"; ccy[7]="NZD";
    string core = ""; // strip non-alpha (handles suffixes like 'm', '.QTR')
    for(int i = 0; i < StringLen(s); i++)
    {
        ushort c = StringGetCharacter(s,i);
        if(c >= 'A' && c <= 'Z') core += ShortToString(c);
    }
    if(StringLen(core) >= 6)
    {
        string a = StringSubstr(core,0,3), b = StringSubstr(core,3,3);
        bool aok=false, bok=false;
        for(int i=0;i<ArraySize(ccy);i++){ if(a==ccy[i]) aok=true; if(b==ccy[i]) bok=true; }
        if(aok && bok) return 0; // FX
    }
    return 4; // Other/commodities
}

// Per-class configured cap (0 = no cap). Honors Lot_Cap_Mode.
double ConfiguredMaxLots()
{
    if(Lot_Cap_Mode == LOTCAP_OFF)    return 0.0;
    if(Lot_Cap_Mode == LOTCAP_GLOBAL) return MathMax(0.0, Max_Lots_Global);
    switch(AssetClass())
    {
        case 0: return MathMax(0.0, Max_Lots_FX);
        case 1: return MathMax(0.0, Max_Lots_Metals);
        case 2: return MathMax(0.0, Max_Lots_Indices);
        case 3: return MathMax(0.0, Max_Lots_Crypto);
        default:return MathMax(0.0, Max_Lots_Other);
    }
}

// Sum of THIS EA's currently open + pending lots on this symbol (worst case:
// pendings counted as if they will fill).
double OpenAndPendingLotsOnSymbol()
{
    double total = 0.0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(t == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)PositionGetInteger(POSITION_MAGIC))) continue;
        if(!OwnsTicket(t)) continue; // Bug2 fix: exclude other chart instances' lots from cap calc
        total += PositionGetDouble(POSITION_VOLUME);
    }
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(t == 0 || !OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)OrderGetInteger(ORDER_MAGIC))) continue;
        if(!OwnsTicket(t)) continue; // Bug2 fix: exclude other chart instances' lots from cap calc
        total += OrderGetDouble(ORDER_VOLUME_CURRENT);
    }
    return total;
}

// Round a lot down to broker step and clamp to [min,max].
double NormalizeLots(double lots)
{
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(step <= 0.0) step = 0.01;
    lots = MathFloor(lots / step) * step;
    if(lots < mn) return 0.0;            // below broker min -> not placeable
    return MathMin(mx, lots);
}

double MarginBudgetForLeg(bool reserveForPair)
{
    double pct = Max_Margin_Usage_Percent;
    if(pct <= 0.0) pct = 95.0;
    pct = MathMin(100.0, pct);
    double budget = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (pct / 100.0);
    if(reserveForPair && Split_Pair_Margin) budget *= 0.5;
    return budget;
}

double MarginPerLotAtEntry(bool bull, double entry)
{
    if(entry <= 0.0) return 0.0;
    double margin = 0.0;
    ENUM_ORDER_TYPE marketType = bull ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if(!OrderCalcMargin(marketType, _Symbol, 1.0, entry, margin)) return 0.0;
    return margin;
}

double MarginCappedLots(double lots, bool bull, double entry, bool reserveForPair)
{
    lots = NormalizeLots(lots);
    if(lots <= 0.0) return 0.0;

    double marginPerLot = MarginPerLotAtEntry(bull, entry);
    double budget = MarginBudgetForLeg(reserveForPair);
    if(marginPerLot <= 0.0) return lots;
    if(budget <= 0.0) return 0.0;

    double maxByMargin = NormalizeLots(budget / marginPerLot);
    if(maxByMargin <= 0.0)
    {
        ORBLog(StringFormat("[ORB] Margin cap: no placeable lot. budget=%.2f marginPerLot=%.2f entry=%.5f",
                            budget, marginPerLot, entry));
        return 0.0;
    }

    double capped = NormalizeLots(MathMin(lots, maxByMargin));
    if(capped < lots && !Inp_StealthMode)
        ORBLog(StringFormat("[ORB] Margin cap: lots %.2f -> %.2f | budget=%.2f marginPerLot=%.2f entry=%.5f",
                            lots, capped, budget, marginPerLot, entry));
    return capped;
}

//+------------------------------------------------------------------+
//| Pair sizing: per-order lot for the BuyStop/SellStop.              |
//| Default (Split_Pair_Margin = false): each side is sized           |
//| INDIVIDUALLY to the FULL remaining cap room and FULL affordable   |
//| margin. Rationale: both setups rarely fill simultaneously, so     |
//| each side keeps its full profit potential.                        |
//| Toggle ON (Split_Pair_Margin = true): conservative worst-case     |
//| halving - each side gets HALF the cap room and HALF the margin    |
//| so that if BOTH fill at once, total stays within cap + margin.    |
//| Returns 0.0 if there is no placeable room (caller skips the side). |
//+------------------------------------------------------------------+
double PlannedLegLots(double slRaw, bool bull, double entry, bool reserveForPair)
{
    double riskLots = CalcLots(slRaw);
    double lots = riskLots;
    double divisor = (reserveForPair && Split_Pair_Margin) ? 2.0 : 1.0;

    double cap = ConfiguredMaxLots();
    if(cap > 0.0)
    {
        double room = cap - OpenAndPendingLotsOnSymbol();
        if(room <= 0.0) return 0.0;
        double capDivisor = reserveForPair ? 2.0 : divisor;
        lots = MathMin(lots, room / capDivisor);
    }

    return MarginCappedLots(lots, bull, entry, reserveForPair);
}

void PlanRangeLots(double slRaw, bool highCanPlace, bool lowCanPlace,
                   double &lotsHigh, double &lotsLow)
{
    lotsHigh = 0.0;
    lotsLow = 0.0;
    bool pair = (highCanPlace && lowCanPlace);

    if(pair)
    {
        double highLots = PlannedLegLots(slRaw, !Reverse_Orders, g_rangeHigh, true);
        double lowLots  = PlannedLegLots(slRaw,  Reverse_Orders, g_rangeLow,  true);
        double pairLots = NormalizeLots(MathMin(highLots, lowLots));
        lotsHigh = pairLots;
        lotsLow  = pairLots;
        return;
    }

    if(highCanPlace)
        lotsHigh = PlannedLegLots(slRaw, !Reverse_Orders, g_rangeHigh, false);
    if(lowCanPlace)
        lotsLow = PlannedLegLots(slRaw, Reverse_Orders, g_rangeLow, false);
}

//+------------------------------------------------------------------+
//| Broker tick-economics self-diagnostic                            |
//| Prints the TRUE per-symbol values that drive universal sizing.   |
//| Digit-count-proof: relies on broker tickSize/tickValue, never on |
//| symbol-name guesses or decimal-place counting. Stealth-aware.    |
//+------------------------------------------------------------------+
void LogBrokerDiagnostics()
{
    if(Inp_StealthMode) return;

    double point     = _Point;
    int    digits    = _Digits;
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    string acctCcy   = AccountInfoString(ACCOUNT_CURRENCY);

    // Cash value of ONE broker point, per 1.0 lot, in account currency.
    double cashPerPointPerLot = (tickSize > 0.0) ? (point / tickSize) * tickValue : 0.0;

    // Health check: a broker that misreports tickValue (0 or negative) is flagged loudly.
    string health = (tickSize > 0.0 && tickValue > 0.0) ? "OK" : "WARN_BROKER_MISREPORT";

    Print("================ ORB BROKER DIAGNOSTIC ================");
    Print(StringFormat("  SYMBOL          = %s", _Symbol));
    Print(StringFormat("  ACCOUNT_CCY     = %s", acctCcy));
    Print(StringFormat("  DIGITS          = %d", digits));
    Print(StringFormat("  POINT (_Point)  = %.10f", point));
    Print(StringFormat("  TICK_SIZE       = %.10f", tickSize));
    Print(StringFormat("  TICK_VALUE      = %.6f (%s per tick per lot)", tickValue, acctCcy));
    Print(StringFormat("  CONTRACT_SIZE   = %.2f", contract));
    Print(StringFormat("  VOL_MIN/STEP/MAX= %.4f / %.4f / %.2f", volMin, volStep, volMax));
    Print(StringFormat("  CASH/POINT/LOT  = %.6f %s  (one point move, one lot)", cashPerPointPerLot, acctCcy));
    Print(StringFormat("  HEALTH          = %s", health));
    Print("  -> Lots for 1%% of 10000 over an 80-point SL would be:");
    if(cashPerPointPerLot > 0.0)
    {
        double exampleLots = (10000.0 * 0.01) / (80.0 * cashPerPointPerLot);
        Print(StringFormat("     %.4f lots  (risk $100 / (80pt * %.6f))", exampleLots, cashPerPointPerLot));
    }
    else
        Print("     UNCOMPUTABLE - broker misreported tick economics.");
    Print("======================================================");
}

//+------------------------------------------------------------------+
//| Trade comment builder                                            |
//+------------------------------------------------------------------+
string BuildComment(bool bull)
{
    if(Inp_StealthMode && !MQLInfoInteger(MQL_TESTER)) return "";
    return StringFormat("ORB|S%d|%s|%s|K%08X", g_ctxSlotIdx, SessionTag(), bull ? "BU" : "SE", ORBHash(g_sessionKey));
}

//+------------------------------------------------------------------+
//| Resolve which session is ACTIVE right now and bridge its open/    |
//| cutoff to the time engine + dashboard. Chronological: among the   |
//| ENABLED sessions, the one whose open is most recently in the past |
//| today (i.e. we are inside/after its open) wins; before any open,  |
//| the soonest-upcoming enabled session is shown. Returns true if    |
//| the active session CHANGED since the last call.                   |
//| Fixes: dashboard stuck on "NY Open:" after London becomes live,    |
//| and the trade engine keying the range off the wrong session.      |
//+------------------------------------------------------------------+
// Tokyo-anchor adjustment: +60 NY-minutes in winter (EST) so the Asian open
// tracks the same Tokyo wall-clock instant all year (Tokyo has no DST).
int AsianAdjMin()
{
    if(!Asian_Tokyo_Anchor) return 0;
    return NYIsDST(TimeCurrent()) ? 0 : 60;
}
int SessionOpenHour(int s)
{
    if(s==1) return London_Hour_NY_Time;
    if(s==2) return ((Asian_Hour_NY_Time*60 + Asian_Minute_NY_Time + AsianAdjMin())/60)%24;
    return Opening_Hour_NY_Time;
}
int SessionOpenMin(int s)
{
    if(s==1) return London_Minute_NY_Time;
    if(s==2) return (Asian_Hour_NY_Time*60 + Asian_Minute_NY_Time + AsianAdjMin())%60;
    return Opening_Minute_NY_Time;
}
bool SessionEnabled(int s)   { return (s==1)?Enable_London_Session : (s==2)?Enable_Asian_Session  : Enable_NY_Session; }
bool AnyIntradaySessionEnabled()
{
    return (Enable_NY_Session || Enable_London_Session || Enable_Asian_Session);
}
bool SlotEnabled(int slotIdx)
{
    if(slotIdx == 0) return Enable_NY_Session;
    if(slotIdx == 1) return Enable_London_Session;
    if(slotIdx == 2) return Enable_Asian_Session;
    if(slotIdx == 3) return Enable_Daily_Range;
    if(slotIdx == 4) return Enable_Weekly_Range;
    return Enable_Monthly_Range;   // slotIdx == 5
}
bool SlotIsIntraday(int slotIdx)
{
    return (slotIdx == 0 || slotIdx == 1 || slotIdx == 2);
}

// Single non-user-facing cutoff rule for ALL intraday sessions (NY/London/
// Asian alike): watch from arm time until the close of the current NY
// trading day (18:00 NY), then forget the range entirely until the next
// day's session forms a fresh one. No per-session duration input any more -
// e.g. a 2h range arming at 08:00 NY (06:00-08:00 range) watches for a
// trigger until 18:00 NY, then gives up regardless of whether it fired.
int SessionCutoffMin(int s)
{
    const int NY_DAY_CLOSE_MIN = 18 * 60;   // 18:00 NY
    int openMin = SessionOpenHour(s) * 60 + SessionOpenMin(s);
    int mins = NY_DAY_CLOSE_MIN - openMin;
    if(mins <= 0) mins += 1440;   // session opens at/after 18:00 NY -> cutoff rolls to 18:00 the following NY day
    return mins;
}

// NY/London/Asian are now fixed, independent slots (0/1/2 respectively) -
// each is gated only by its own Enable_X_Session toggle and uses
// SessionOpenHour/Min/SessionCutoffMin directly via SetSlotContext. The old
// dynamic "pick one active session and follow it" resolver has been removed;
// all enabled sessions now persist and arm concurrently.

string ActiveSessionKey(datetime serverTime)
{
    if(g_ctxMode == RANGE_DAILY)
        return StringFormat("S%d_DAILY_%lld", g_ctxSlotIdx, (long)SessionOpenServer(serverTime));
    if(g_ctxMode == RANGE_WEEKLY)
      return StringFormat("S%d_WEEKLY_%lld", g_ctxSlotIdx, (long)SessionOpenServer(serverTime));
  if(g_ctxMode == RANGE_MONTHLY)
      return StringFormat("S%d_MONTHLY_%lld", g_ctxSlotIdx, (long)SessionOpenServer(serverTime));

    return StringFormat("S%d_%s_M%d_%02d%02d",
                        g_ctxSlotIdx,
                        CurrentNYSessionKey(serverTime),
                        g_ctxSlotIdx,
                        g_ctxHour,
                        g_ctxMin);
}

datetime WeekendCarryCutoffServer()
{
    datetime anchor = (g_rangeEnd > 0) ? g_rangeEnd : SessionOpenServer(TimeCurrent());
    if(anchor <= 0) return 0;

    MqlDateTime ny;
    TimeToStruct(ServerToNY(anchor), ny);
    int addDays = -1;
    if(ny.day_of_week == 5) addDays = 3;      // Friday -> Monday close
    else if(ny.day_of_week == 0) addDays = 1; // Sunday -> Monday close
    if(addDays < 0) return 0;

    datetime nyMidnight = MakeDateTime(ny.year, ny.mon, ny.day, 0, 0, 0);
    MqlDateTime mondayClose;
    TimeToStruct(nyMidnight + (datetime)(addDays * 86400), mondayClose);
    return NYLocalToServer(mondayClose.year, mondayClose.mon, mondayClose.day, 23, 59, 59);
}

datetime WeekendCarryCutoffForAnchor(datetime anchor)
{
    if(anchor <= 0) return 0;

    MqlDateTime ny;
    TimeToStruct(ServerToNY(anchor), ny);
    int addDays = -1;
    if(ny.day_of_week == 5) addDays = 3;
    else if(ny.day_of_week == 0) addDays = 1;
    if(addDays < 0) return 0;

    datetime nyMidnight = MakeDateTime(ny.year, ny.mon, ny.day, 0, 0, 0);
    MqlDateTime mondayClose;
    TimeToStruct(nyMidnight + (datetime)(addDays * 86400), mondayClose);
    return NYLocalToServer(mondayClose.year, mondayClose.mon, mondayClose.day, 23, 59, 59);
}

datetime EffectiveSlotCutoffServer(datetime serverTime)
{
    datetime cutoff = SessionCutoffServer(serverTime);
    // HARD RULE: intraday sessions (NY/London/Asian) die at 18:00 NY, full
    // stop — no weekend carry. Carrying a Friday/Sunday-anchored intraday
    // session to Monday 23:59 kept yesterday's ranges armed and let stale
    // levels fire the next day (observed 2026-07-20: S0_20260719 still
    // watching at 00:02 Monday). Weekend carry now applies to HTF slots only.
    if(SlotIsIntraday(g_ctxSlotIdx)) return cutoff;
    datetime carry = WeekendCarryCutoffServer();
    if(carry > cutoff) return carry;
    return cutoff;
}

// SetSlotContext: populate context bridge globals for the given slot index.
// Must be called before CheckOpeningRange / PlaceOrders / SessionCutoffServer.
// Fixed mapping: slot 0=NY, 1=London, 2=Asian (each an independent, always-on
// intraday watcher gated only by its own Enable_X_Session toggle - no more
// dynamic single-active-session picking, so all three persist concurrently
// until the NY day closes). Slots 3/4/5 = Daily/Weekly/Monthly HTF, each an
// independent, always-on watcher gated only by its own Enable_X_Range toggle.
void SetSlotContext(int slotIdx)
{
    g_ctxSlotIdx = slotIdx;

    if(slotIdx == 0 || slotIdx == 1 || slotIdx == 2)
    {
        g_ctxMode      = RANGE_INTRADAY;
        g_ctxHour      = SessionOpenHour(slotIdx);
        g_ctxMin       = SessionOpenMin(slotIdx);
        g_ctxCutoffMin = SessionCutoffMin(slotIdx);

        // Dashboard/visuals (ORB_Dashboard.mqh, ORB_Visuals.mqh) read these two
        // directly to label/color whichever slot is currently being rendered -
        // keep them in sync with the slot actually loaded right now.
        g_activeSession = slotIdx;
        datetime nowSSC = TimeCurrent();
        MqlDateTime nySSC;
        TimeToStruct(ServerToNY(nowSSC), nySSC);
        int nowMinSSC  = nySSC.hour * 60 + nySSC.min;
        int openMinSSC = g_ctxHour * 60 + g_ctxMin;
        int endMinSSC  = openMinSSC + g_ctxCutoffMin;
        g_sessionIsLive = (nowMinSSC >= openMinSSC && nowMinSSC < endMinSSC);
    }
    else
    {
        // Slots 3/4/5: independent HTF ranges - Daily/Weekly/Monthly
        // respectively. Each is only ever reached if SlotEnabled(slotIdx) is
        // true, so no "disabled" case is needed here (unlike the old single-
        // choice Slot2_Mode picker from the earlier 2-slot design).
        if(slotIdx == 3)
        {
            g_ctxMode = RANGE_DAILY;
            g_ctxCutoffMin = Slot2_Cutoff_Periods * 1440;
        }
        else if(slotIdx == 4)
        {
            g_ctxMode = RANGE_WEEKLY;
            g_ctxCutoffMin = Slot2_Cutoff_Periods * 10080;
        }
        else // slotIdx == 5
        {
            g_ctxMode = RANGE_MONTHLY;
            g_ctxCutoffMin = Slot2_Cutoff_Periods * 43200;
        }
    }
    // Store ctx into the slot state struct so LoadSlotToGlobals can restore it
    g_slotState[slotIdx].ctxMode      = g_ctxMode;
    g_slotState[slotIdx].ctxHour      = g_ctxHour;
    g_slotState[slotIdx].ctxMin       = g_ctxMin;
    g_slotState[slotIdx].ctxCutoffMin = g_ctxCutoffMin;
}

void ResetSlotRuntimeGlobals(string sessionKey)
{
    g_sessionKey   = sessionKey;
    g_rangeReady   = false;
    g_rangeHigh    = 0.0;
    g_rangeLow     = 0.0;
    g_rangeStart   = 0;
    g_rangeEnd     = 0;
    g_rangeHighTime = 0;
    g_rangeLowTime  = 0;
    g_buyPlaced    = false;
    g_sellPlaced   = false;    ClearPendingSendLocks();
    g_precloseArmed = false;
    ResetRangeBuild();
}

void RecoverLockedRangeForSlot(int slotIdx, datetime now)
{
    if(!SlotEnabled(slotIdx)) return;
    SetSlotContext(slotIdx);

    // DEAD-SESSION GUARD (fix): a timeframe/parameter change reruns OnInit,
    // and this recovery used to resurrect ranges whose cutoff had already
    // passed — yesterday's boxes, level lines and pending visuals reappeared
    // on every TF switch. Past cutoff, the session stays forgotten.
    if(now >= EffectiveSlotCutoffServer(now))
    {
        ResetSlotRuntimeGlobals("");
        return;
    }

    string key = ActiveSessionKey(now);
    ResetSlotRuntimeGlobals(key);

    CheckOpeningRange(now);

    if(g_rangeReady)
        SyncPlacedFlagsFromLiveOrders();
    if(SideConsumed(g_sessionKey, true))  g_buyPlaced  = true;
    if(SideConsumed(g_sessionKey, false)) g_sellPlaced = true;
    SaveGlobalsToSlot(slotIdx);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    g_eaActiveSince = TimeCurrent();

    // Bridge to include files
    Inp_ServerUTCOffsetHours = Server_UTC_Offset_Hours;
    Inp_UseNewYorkDST        = Use_NewYork_DST;
    Inp_OpenNYHour           = Opening_Hour_NY_Time;
    Inp_OpenNYMinute         = Opening_Minute_NY_Time;
    Inp_RangeMinutes         = (int)Slot1_Range_Minutes;
    Inp_CutoffNYMin     = SessionCutoffMin(0);
    Inp_CutoffLondonMin = SessionCutoffMin(1);
    Inp_CutoffAsianMin  = SessionCutoffMin(2);
    Inp_ShowDashboard        = Show_Dashboard;
    Inp_ShowVisuals          = Show_Visuals;
    Inp_Slot2AnchorMode      = (int)Slot2_Anchor_Mode;
    Inp_ClrRangeBoxNY        = Clr_Range_Box_NY;
    Inp_ClrRangeBoxLondon    = Clr_Range_Box_London;
    Inp_ClrRangeBoxAsian     = Clr_Range_Box_Asian;
    Inp_ClrRangeBoxDaily     = Clr_Range_Box_Daily;
    Inp_ClrRangeBoxWeekly    = Clr_Range_Box_Weekly;
    Inp_ClrEntryLine         = Clr_Entry_Line;
    Inp_ClrSLLine            = Clr_SL_Line;
    Inp_ClrTPLine            = Clr_TP_Line;
    Inp_ClrTrailingStop      = Clr_Trailing_Stop;
    Inp_DashTheme            = (int)Dashboard_Theme;
    Inp_EnableNY             = Enable_NY_Session;
    Inp_EnableLondon         = Enable_London_Session;
    Inp_EnableAsian          = Enable_Asian_Session;
    Inp_LondonHour           = London_Hour_NY_Time;
    Inp_AsianHour            = Asian_Hour_NY_Time;
    Inp_LondonMinute         = London_Minute_NY_Time;
    Inp_AsianMinute          = Asian_Minute_NY_Time;
    // NY/London/Asian are now fixed, independent slots (0/1/2) - each uses its
    // own SessionOpenHour/Min/Cutoff directly via SetSlotContext, no dynamic
    // active-session resolution needed any more.
    SetSlotContext(0);
    // One-glance time check: prints what server time the NY open maps to, so the
    // correct Server_UTC_Offset_Hours is obvious from a single run.
    if(!Inp_StealthMode && Verbose_Journal) ORBLogTimeMapping(Opening_Hour_NY_Time, Opening_Minute_NY_Time);
    trade.SetExpertMagicNumber(EffectiveMagic());
    trade.SetDeviationInPoints(30); // Fixed, non-user-facing: ignored entirely by Market Execution mode brokers (FTMO/FundingPips-style), only matters for Instant/Exchange execution mode symbols
    trade.SetAsyncMode(true); // fast pending-order placement; management calls switch to sync locally

    if(Use_Trend_Filter)
        emaHandle = iMA(_Symbol, Trend_Ema_Timeframe, Trend_Ema_Period, 0, MODE_EMA, PRICE_CLOSE);
    if(Use_Vol_Filter)
        atrHandle = iATR(_Symbol, PERIOD_CURRENT, Vol_Atr_Period);

    ArrayResize(vTrades, 0);

    // - Relaunch guard: pre-populate placed flags from existing orders/positions -
    // Without this, g_buyPlaced/g_sellPlaced reset to false on every reattach,
    // causing PlaceOrders() to fire duplicates on the very first tick.
    datetime initNow = TimeCurrent();
    for(int s = 0; s < 6; s++)
        RecoverLockedRangeForSlot(s, initNow);
    SetSlotContext(0);
    LoadSlotToGlobals(0);
    string initKey = g_sessionKey; // set before first tick so day-reset block doesn't wipe flags
    bool incompatiblePendingGeometry = false;

    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(t == 0) continue;
        if(!OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!ClaimTicket(t)) continue; // Actively re-claim on relaunch so this instance wins before Chart 2 can steal
        if(!CurrentSlotOwnsOrder(t)) continue;
        ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(!Reverse_Orders)
        {
            if(ot == ORDER_TYPE_BUY_STOP  || ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY)  g_buyPlaced  = true;
            if(ot == ORDER_TYPE_SELL_STOP || ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL) g_sellPlaced = true;
            if(ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_BUY_LIMIT) incompatiblePendingGeometry = true;
        }
        else
        {
            if(ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL) g_buyPlaced  = true;
            if(ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_BUY)  g_sellPlaced = true;
            if(ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_SELL_STOP) incompatiblePendingGeometry = true;
        }
    }
    // Open positions are adopted/managed independently and must not block a new
    // session's pending orders. Filled current-session levels are blocked by the
    // consumed ledger when RegisterNewPositions() adopts the fill.
    // PERSISTENT LEDGER (phantom re-fire fix #4): even if NOTHING is open now
    // (the side already triggered AND resolved before this relaunch), the
    // consumed-ledger remembers the side was used today, so we must not re-arm.
    PruneConsumedLedger();
    ORBNPruneDedupe();
    if(SideConsumed(initKey, true))  g_buyPlaced  = true;
    if(SideConsumed(initKey, false)) g_sellPlaced = true;

    // - Retroactive Armed signal -
    // If both pending orders already exist for a slot but the Armed signal
    // was never sent (EA was offline when they were placed), send it now.
    for(int s = 0; s < 6; s++)
    {
        if(!SlotEnabled(s)) continue;
        SetSlotContext(s); LoadSlotToGlobals(s);
        if(!g_rangeReady || !g_buyPlaced || !g_sellPlaced) { SaveGlobalsToSlot(s); continue; }
        string armedKey = StringFormat("ORBN_ARMED_%s_%s", _Symbol, g_sessionKey);
        if(GlobalVariableCheck(armedKey))                  { SaveGlobalsToSlot(s); continue; }
        double bE=0,bS=0,bT=0,sE=0,sS=0,sT=0;
        for(int oi = OrdersTotal()-1; oi >= 0; oi--)
        {
            ulong ot2=OrderGetTicket(oi);
            if(ot2==0||!OrderSelect(ot2)) continue;
            if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
            if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
            ENUM_ORDER_TYPE ordType=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(bE<=0.0&&(ordType==ORDER_TYPE_BUY_STOP ||ordType==ORDER_TYPE_BUY_LIMIT))
            {bE=OrderGetDouble(ORDER_PRICE_OPEN);bS=OrderGetDouble(ORDER_SL);bT=OrderGetDouble(ORDER_TP);}
            if(sE<=0.0&&(ordType==ORDER_TYPE_SELL_STOP||ordType==ORDER_TYPE_SELL_LIMIT))
            {sE=OrderGetDouble(ORDER_PRICE_OPEN);sS=OrderGetDouble(ORDER_SL);sT=OrderGetDouble(ORDER_TP);}
        }
        if(bE<=0.0&&sE<=0.0) { SaveGlobalsToSlot(s); continue; }
        string bLbl=Reverse_Orders?"BUY LIMIT":"BUY STOP";
        string sLbl=Reverse_Orders?"SELL LIMIT":"SELL STOP";
        ORBNotifyArmed(g_sessionKey,SessionLabel(),g_rangeHigh,g_rangeLow,
                       bLbl,sLbl,bE,bS,bT,sE,sS,sT,
                       TrailThreshRaw(),TrailGapRaw(),(int)Trail_Mode);
        SaveGlobalsToSlot(s);
    }
    SetSlotContext(0); LoadSlotToGlobals(0);

    // Relaunch guard log - suppressed entirely in stealth mode
    if(!Inp_StealthMode && Verbose_Journal)
        ORBLog(StringFormat("[ORB] OnInit relaunch guard: sessionKey=%s buyPlaced=%s sellPlaced=%s",
                            initKey, g_buyPlaced?"true":"false", g_sellPlaced?"true":"false"));
    // - End relaunch guard -

    // Broker diagnostic - suppressed entirely in stealth mode
    if(!Inp_StealthMode && Verbose_Journal)
        LogBrokerDiagnostics();

    // - Config-change = FRESH SETUP guard -
    // Changing any setup-defining input (range minutes, reverse mode,
    // NY/London/Asian enable/hour/minute/cutoff, theme) triggers a fresh setup.
    // When the signature changes we start a clean setup for the day:
    //   - purge this chart's ORB visuals + dashboard,
    //   - cancel this EA's still-untriggered pending orders (old range),
    //   - clear today's consumed-ledger for BOTH sides,
    //   - reset placed-flags + range so the NEW session arms independently.
    // Any ALREADY-TRIGGERED position is left untouched; it keeps being managed
    // off its own snapshot, fully independent of the new setup.
    string newSig = StringFormat("RISK%.4f:%d:%.2f:%d:%.2f|GEOM%d:%d:%.6f:%.2f:%.2f|SLT%d|TPD%d:%.2f|R%d|S2%d:%d:%d:%d|REV%d|NY%d:%d:%d|LO%d:%d:%d|AS%d:%d:%d",
                                 Risk_Percent, (int)Risk_Basis, Custom_Balance_Override, (int)Use_Commission_Buffer, Max_Margin_Usage_Percent,
                                 (int)Point_Scale_Mode, (int)Trail_Behavior, Custom_Point_Multiplier, Fixed_SL_Points, Fixed_TP_Points,
                                 (int)Use_StopLimit_Orders, (int)Use_TP_Slippage_Pad, TP_Slippage_Pad_Pct,
                                 (int)Slot1_Range_Minutes,
                                 (int)Enable_Daily_Range, (int)Enable_Weekly_Range, (int)Enable_Monthly_Range, Slot2_Cutoff_Periods, (int)Reverse_Orders,
                                 (int)Enable_NY_Session,     Opening_Hour_NY_Time, Opening_Minute_NY_Time,
                                 (int)Enable_London_Session, London_Hour_NY_Time,  London_Minute_NY_Time,
                                 (int)Enable_Asian_Session,  Asian_Hour_NY_Time,   Asian_Minute_NY_Time);
    string sigKey = ConfigSigKey();
    double newSigHash = (double)ConfigSigHash(newSig);
    bool configChanged = incompatiblePendingGeometry || (GlobalVariableCheck(sigKey) && GlobalVariableGet(sigKey) != newSigHash);
    if(configChanged)
    {
        for(int s = 0; s < 6; s++)
        {
            if(!SlotEnabled(s)) continue;
            SetSlotContext(s);
            LoadSlotToGlobals(s);
            CancelPendingOrders();            // delete old range's untriggered pending orders
            ClearORBVisuals();
            string oldKey = g_sessionKey;
            GlobalVariableDel(ConsumedKey(oldKey, true));
            GlobalVariableDel(ConsumedKey(oldKey, false));
            // ORBN_ARMED intentionally NOT deleted: removing it caused the Armed
            // signal to re-fire on every parameter save even with orders still live.
            ResetSlotRuntimeGlobals(ActiveSessionKey(initNow));
            SaveGlobalsToSlot(s);
        }
        SetSlotContext(0);
        LoadSlotToGlobals(0);
        ClearDashboard();
        if(!Inp_StealthMode) ORBLog("[ORB] Config changed -> fresh setup (old position kept, new range will arm independently).");
    }
    GlobalVariableSet(sigKey, newSigHash);
    g_visualSig = newSig;

    // - TESTER-SPEED PACK -
    // Non-visual tester: no chart, no dashboard, no UI -> no timer at all.
    // CTrade journal chatter (one 'modify position' line per trail step;
    // thousands per year with continuous trailing) is the single largest
    // tester I/O cost - log errors only while testing. Visual tester keeps a
    // 1s timer; live keeps the fast 200ms timer (also the placement pulse).
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
    bool isVisual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
    if(Inp_StealthMode) trade.LogLevel(LOG_LEVEL_NO);
    else if(isTester) trade.LogLevel(LOG_LEVEL_ERRORS);
    if(!isTester)      EventSetMillisecondTimer(100);  // 100ms pulse - - <200ms notification drain latency
    else if(isVisual)  EventSetMillisecondTimer(1000);
    // else: non-visual tester -> no timer; OnTick drives everything.

    // Enable mouse-move events so the dashboard header is draggable. UI-only;
    // skipped in the non-visual tester (no chart to interact with).
    if(!isTester || isVisual)
        ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

    // Scan deal history for positions that closed while the EA was offline
    ScanOfflineClosedTrades();
    RedrawBrokerExecutions();
    SimulateSyntheticExecutions();
    
    // Adopt any already-live position immediately - vTrades[] is empty right
    // after a reload (it's in-memory only, not persisted), so without this the
    // forced visual-update loop below has nothing to draw for an existing
    // position until the next tick happens to arrive.
    RegisterNewPositions(TimeCurrent());

    // Force a visual update so historical executions draw immediately
    for(int s = 0; s < 6; s++)
    {
        if(!SlotEnabled(s)) continue;
        SetSlotContext(s);
        LoadSlotToGlobals(s);
        UpdateVisuals();
    }
    SetSlotContext(0);
    LoadSlotToGlobals(0);

    // Live management pulse (see OnTimer): without this, trailing/adoption/
    // slip-close were entirely dependent on the tick stream, with no
    // redundancy if ticks went quiet for any stretch. EventSetTimer had never
    // actually been called anywhere in this file - OnTimer was dead code.
    EventSetTimer(1);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);

    bool isHardRemoval = (reason == REASON_REMOVE     ||
                          reason == REASON_CHARTCLOSE ||
                          reason == REASON_CLOSE      ||
                          reason == REASON_PROGRAM    ||
                          reason == REASON_PARAMETERS);

    if(isHardRemoval)
    {
        if(Cancel_Orders_On_Deinit)
            CancelAllPendingOrdersForInstance();
        ClearAllSlotVisuals();
    }

    ClearDashboard();
    if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
    if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Get daily profit % for dashboard (CACHED)                        |
//| STALL FIX: the raw scan iterates every history deal of the day    |
//| and was being called on every 200ms timer tick, re-scanning a     |
//| growing window 5x/sec. We now recompute at most every 5 seconds,  |
//| or immediately when forced after a trade close.                   |
//+------------------------------------------------------------------+
double   g_dailyPctCache      = 0.0;
datetime g_dailyPctCacheTime  = 0;
datetime g_dailyPctCacheDay   = 0;
double   g_lastTradeProfit     = 0.0;   // dollar P&L of the most recently closed trade (displayed in dashboard)


double ComputeDailyProfitPct(datetime now)
{
    datetime start = now - (now % 86400); // Server midnight
    if(!HistorySelect(start, now)) return g_dailyPctCache;

    double profitMoney = 0.0;
    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)HistoryDealGetInteger(ticket, DEAL_MAGIC))) continue;

        profitMoney += HistoryDealGetDouble(ticket, DEAL_PROFIT);
        profitMoney += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        profitMoney += HistoryDealGetDouble(ticket, DEAL_SWAP);
    }

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0.0) return g_dailyPctCache;
    return (profitMoney / balance) * 100.0;
}

double GetDailyProfitPct(datetime now, bool force=false)
{
    datetime day = now - (now % 86400);
    // Reset cache at a new server day, or honor a forced recompute, or refresh every 5s.
    if(force || day != g_dailyPctCacheDay || (now - g_dailyPctCacheTime) >= 5)
    {
        g_dailyPctCache     = ComputeDailyProfitPct(now);
        g_dailyPctCacheTime = now;
        g_dailyPctCacheDay  = day;
    }
    return g_dailyPctCache;
}

double ActiveEntrySpreadRaw()
{
    for(int i = ArraySize(vTrades)-1; i >= 0; i--)
    {
        if(!vTrades[i].active) continue;
        if(vTrades[i].snapEntrySpreadRaw > 0.0) return vTrades[i].snapEntrySpreadRaw;
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Timer - live management pulse + UI refresh                       |
//+------------------------------------------------------------------+
void OnTimer()
{
    // TESTER-SPEED: non-visual tester has no UI - never spend time here.
    if((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) return;

    // Live management pulse: adopt fills and keep trailing responsive even if
    // chart/UI work delays tick-driven management. Uses the latest broker tick;
    // no price change = no-op.
    RegisterNewPositions(TimeCurrent());
    ManageTrailingStops();
    ManageSlipForceClose();
    SyncClosedTrades();

    static datetime s_lastSetupPulse = 0;
    datetime pulseNow = TimeCurrent();
    if(!(bool)MQLInfoInteger(MQL_TESTER) && pulseNow != s_lastSetupPulse)
    {
        s_lastSetupPulse = pulseNow;
        OnTick();
    }

    // Weekly/Monthly performance reports (60s-throttled, no-op in tester).
    ORBReportsOnTimer();
    // News signals (60s-throttled, no-op when disabled).
    ORBNewsOnTimer();

    // FLATTEN-BEFORE: close all positions when a news flatten window opens.
    if(ORBNNewsEnabled() && News_Flatten_Before)
    {
        if(IsNewsFlattening(TimeCurrent()))
        {
            for(int i=PositionsTotal()-1;i>=0;i--)
            {
                ulong t=PositionGetTicket(i);
                if(t==0) continue;
                if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
                if(!MagicMatch(PositionGetInteger(POSITION_MAGIC))) continue;
                int vi=GetVTIdx(t);
                if(vi>=0 && vTrades[vi].closing) continue;
                if(vi>=0) vTrades[vi].closing=true;
                bool ok=trade.PositionClose(t);
                if(vi>=0 && !ok) vTrades[vi].closing=false;
                if(!Inp_StealthMode && ok)
                    ORBLog(StringFormat("[ORB] News flatten: closed position #%llu",t));
            }
        }
    }

    int posCount = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
        if(PositionGetTicket(i) > 0 &&
           PositionGetString(POSITION_SYMBOL) == _Symbol &&
           MagicMatch(PositionGetInteger(POSITION_MAGIC)))
            posCount++;

    int pendingCount = 0;
    for(int i = OrdersTotal()-1; i >= 0; i--)
        if(OrderGetTicket(i) > 0 &&
           OrderGetString(ORDER_SYMBOL) == _Symbol &&
           MagicMatch(OrderGetInteger(ORDER_MAGIC)))
            pendingCount++;

    int activeVTrades = 0;
    int closedVTrades = 0;
    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        if(vTrades[i].active) activeVTrades++;
        if(!vTrades[i].active && vTrades[i].exitTime > 0) closedVTrades++;
    }

    string status = "Waiting";
    if(g_rangeReady && !g_buyPlaced && !g_sellPlaced) status = "Range Ready";
    else if(pendingCount > 0) status = "Order(s) Pending";
    
    if(posCount > 0) status = "In Trade (" + IntegerToString(posCount) + ")";
    else if(closedVTrades > 0) 
    {
        double pct = GetDailyProfitPct(TimeCurrent()); // cached; recomputes at most every 5s
        status = StringFormat("Done: %+.2f$ | Day %+.2f%%", g_lastTradeProfit, pct);
    }

    UpdateDashboard(status, g_rangeHigh, g_rangeLow, g_rangeHigh - g_rangeLow, Fixed_SL_Points, ActiveEntrySpreadRaw());
    // NOTE: UpdateDashboard now forces ChartRedraw(0) ONLY when its content
    // NOTE: UpdateDashboard now forces ChartRedraw(0) ONLY when its content
    // signature changes (clock tick, status, drag, collapse). The previous
    // unconditional per-timer ChartRedraw redrew the chart 5x/sec even when
    // nothing changed - half of the 10s idle stall. The dirty-signature path
    // keeps the clock live (it changes every second) without the idle cost.
    // - Drain one queued notification per timer cycle -
    // Placed LAST so trade placement, trailing, and all chart work complete
    // before the blocking WebRequest fires. At 100ms interval this delivers
    // notifications within ~200ms of the triggering event.
    ORBNDrainQueue();
}

//+------------------------------------------------------------------+
//| Click the [-]/[+] glyph to collapse/expand; drag the header bar  |
//| to move the whole stack. Never touches the execution path.       |
//| to move the whole stack. Never touches the execution path.       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(!Show_Dashboard) return;
    if((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) return;

    // Dedicated collapse/expand BUTTON: a real OBJ_BUTTON fires a clean object
    // click. Reset its pressed state (buttons latch by default) and toggle.
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == "ORBD_BTN")
        {
            ObjectSetInteger(0, "ORBD_BTN", OBJPROP_STATE, false);
            DB_ToggleCollapse();
        }
        return;
    }

    if(id == CHARTEVENT_MOUSE_MOVE)
    {
        int  mx = (int)lparam;
        int  my = (int)dparam;
        bool lbDown = ((int)StringToInteger(sparam) & 1) != 0;   // bit0 = left button

        // PRESS-EDGE detection: track the previous button state so we act once
        // on the down-edge (press), not continuously while held.
        static bool s_prevDown = false;
        bool justPressed = (lbDown && !s_prevDown);
        s_prevDown = lbDown;

        if(g_dbDragging)
        {
            if(lbDown) DB_DragTo(mx, my);
            else
            {
                DB_EndDrag();
                // Re-enable chart scroll/pan now that the drag is over.
                ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            }
            return;
        }

        if(justPressed)
        {
            // Collapse/expand is handled by the dedicated ORBD_BTN button via
            // CHARTEVENT_OBJECT_CLICK (above). Here we ONLY handle dragging.
            // DB_HeaderHit already excludes the button's box, so pressing the
            // button never starts a drag. Disable chart scroll/pan during the
            // drag so moving the panel never scrolls the chart behind it.
            if(DB_HeaderHit(mx, my))
            {
                ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
                DB_BeginDrag(mx, my);
            }
        }
        return;
    }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if(trans.order > 0) ClaimTicket(trans.order);
    if(trans.position > 0) ClaimTicket(trans.position);
    if(trans.order > 0 && OrderMetaIdx(trans.order) < 0 &&
       request.action == TRADE_ACTION_PENDING && request.symbol == _Symbol && g_rangeReady)
    {
        double px = (request.price > 0.0) ? request.price : trans.price;
        bool highLevel = IsHighLevelPrice(px);
        RegisterOrderMetaSnapshot(trans.order, g_ctxSlotIdx, g_sessionKey, highLevel,
                                  highLevel ? g_rangeHigh : g_rangeLow,
                                  highLevel ? g_rangeHighTime : g_rangeLowTime,
                                  g_rangeStart, g_rangeEnd, EffectiveSlotCutoffServer(TimeCurrent()));
    }
    
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(HistoryDealSelect(trans.deal))
        {
            if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
            {
                ulong posTicket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                if(posTicket > 0 && MagicMatch((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)))
                {
                    double fillPx = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                    OrderMeta meta;
                    if(GetOrderMeta(posTicket, meta))
                    {
                        NormalizeStopsToFill(posTicket, fillPx, meta.levelPx);
                    }
                }
            }
        }
    }
    datetime now = TimeCurrent();
    RegisterNewPositions(now);
    if(g_rangeReady) SyncPlacedFlagsFromLiveOrders();
    if(Use_OCO) CheckOCO();
    ManageTrailingStops();
    ManageSlipForceClose();
    SyncClosedTrades();
    CancelExpiredPendingOrders();
}

//+------------------------------------------------------------------+
//| OnTick - execution priority first, visuals last                  |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime now = TimeCurrent();
    if(g_eaActiveSince <= 0) g_eaActiveSince = now;   // OnInit ran before any tick was available (tester)


    // - PRIORITY 1: Adopt any fills that arrived since last tick, then manage -
    // RegisterNewPositions must run before ManageTrailingStops so a position
    // filled between the previous tick and this one is in vTrades before we
    // try to trail it. OnTradeTransaction also calls this, but it can fire
    // with a slight delay on some brokers; the OnTick call is the safety net.
    RegisterNewPositions(now);
    ManageTrailingStops();
    ManageSlipForceClose();
    SyncClosedTrades();
    CancelExpiredPendingOrders();

    // - PRIORITY 2: Session-key reset for all 4 slots -
    // Each of NY/London/Asian (0/1/2) and HTF (3) independently resets on its
    // own session-key change and clears only ITS OWN visuals, so all four can
    // persist and arm concurrently without disturbing one another.
    for(int s = 0; s < 6; s++)
    {
        if(!SlotEnabled(s)) continue;
        SetSlotContext(s);
        LoadSlotToGlobals(s);
        string key = ActiveSessionKey(now);
        if(key != g_sessionKey)
        {
            g_sessionKey    = key;
            g_rangeReady    = false;
            g_rangeHigh     = 0.0;
            g_rangeLow      = 0.0;
            g_rangeHighTime = 0;
            g_rangeLowTime  = 0;
            ResetRangeBuild();
            ClearPendingSendLocks();
            g_precloseArmed = false;
            g_buyPlaced     = false;
            g_sellPlaced    = false;
            ClearSlotVisuals(s);   // only this slot's own stale visuals
        }
        SaveGlobalsToSlot(s);
    }
    SetSlotContext(0);
    LoadSlotToGlobals(0);   // restore slot 0 as the default context for what follows

    // CANCEL_PENDING during news blackout (once per session-per-slot when window opens).
    if(ORBNNewsEnabled() && News_Cancel_Pending)
    {
        static string s_newsCancelKey[6] = {"", "", "", "", "", ""};
        for(int s = 0; s < 6; s++)
        {
            if(!SlotEnabled(s)) continue;
            SetSlotContext(s);
            LoadSlotToGlobals(s);
            string nck = g_sessionKey + ":NC";
            if(IsNewsBlocked(now) && s_newsCancelKey[s] != nck)
            {
                s_newsCancelKey[s] = nck;
                CancelPendingOrders();
                if(!Inp_StealthMode) ORBLog("[ORB] News blackout: pending orders cancelled.");
            }
        }
        SetSlotContext(0);
        LoadSlotToGlobals(0);
    }

    // - PRIORITY 3: Per-slot cutoff check - only return early once ALL enabled slots are past cutoff -
    static string s_cutoffDoneKey[6] = {"", "", "", "", "", ""};
    bool anySlotEnabled = false;
    bool allSlotsPastCutoff = true;
    for(int s = 0; s < 6; s++)
    {
        if(!SlotEnabled(s)) continue;
        anySlotEnabled = true;
        SetSlotContext(s);
        LoadSlotToGlobals(s);
        datetime cutoff = EffectiveSlotCutoffServer(now);
        if(now >= cutoff)
        {
            string ck = g_sessionKey + ":" + IntegerToString(s);
            if(s_cutoffDoneKey[s] != ck)
            {
                s_cutoffDoneKey[s] = ck;
                bool hadBuy=false, hadSell=false;
                for(int i=OrdersTotal()-1;i>=0;i--)
                {
                    ulong t=OrderGetTicket(i);
                    if(t==0||!OrderSelect(t)) continue;
                    if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
                    if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
                    if(!OwnsTicket(t)) continue;
                    if(!CurrentSlotOwnsOrder(t)) continue;
                    ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                    if(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_BUY_STOP_LIMIT)  hadBuy=true;
                    if(ot==ORDER_TYPE_SELL_STOP || ot==ORDER_TYPE_SELL_LIMIT || ot==ORDER_TYPE_SELL_STOP_LIMIT) hadSell=true;
                }
                CancelPendingOrders();
                ORBNotifyCutoffCancel(g_sessionKey, hadBuy, hadSell);
                UpdateVisuals();
            }
        }
        else
        {
            allSlotsPastCutoff = false;
        }
    }
    SetSlotContext(0);
    LoadSlotToGlobals(0);
    if(anySlotEnabled && allSlotsPastCutoff) return;

    // — PRIORITY 4: OCO —
    if(Use_OCO) CheckOCO();

    // — PRIORITY 5: Register newly filled positions —
    RegisterNewPositions(now);

    // — PRIORITY 6: Range check & order placement — loop over all slots —
    for(int s = 0; s < 6; s++)
    {
        if(!SlotEnabled(s)) continue;
        SetSlotContext(s);
        LoadSlotToGlobals(s);

        datetime slotCutoff = EffectiveSlotCutoffServer(now);
        if(now >= slotCutoff)
        {
            // SESSION OVER — the EA forgets this session completely:
            //   - range state wiped so no stale level can arm or fire tomorrow
            //   - the slot's chart objects (range box, level lines, exec
            //     objects) removed; the day is done, only the trade ledger
            //     (weekly/monthly reports) retains the results.
            // One-shot per session key.
            static string s_cutoffDoneKey[6] = {"", "", "", "", "", ""};
            int coSlot = (s >= 0 && s < 6) ? s : 0;
            if(g_rangeReady && s_cutoffDoneKey[coSlot] != g_sessionKey)
            {
                s_cutoffDoneKey[coSlot] = g_sessionKey;
                CancelPendingOrders();   // slot-context-scoped: cancels only this slot's pendings
                ResetSlotRuntimeGlobals(g_sessionKey);
                if(SlotIsIntraday(s)) ClearSlotVisuals(s);
                ORBLog(StringFormat("[ORB] S%d session cutoff reached — slot reset, visuals cleared, watching stopped.", s));
            }
            SaveGlobalsToSlot(s);
            continue;
        }

        if(!g_rangeReady) CheckOpeningRange(now);
        if(g_rangeReady) SyncPlacedFlagsFromLiveOrders();
        if(g_rangeReady && (!g_buyPlaced || !g_sellPlaced))
        {
            if(!IsNewsBlocked(now))
                PlaceOrders(now, slotCutoff);
            else
            {
                static string s_newsBlockLogKey[6] = {"", "", "", "", "", ""};
                int nbSlot = (s >= 0 && s < 4) ? s : 0;
                if(s_newsBlockLogKey[nbSlot] != g_sessionKey)
                {
                    s_newsBlockLogKey[nbSlot] = g_sessionKey;
                    ORBLog("[ORB] Orders blocked by News Engine blackout.");
                }
            }
        }
        StopLimitMonitor(now);
        SaveGlobalsToSlot(s);
    }
    // Restore slot 0 context for any downstream code (visuals, dashboard)
    SetSlotContext(0);
    LoadSlotToGlobals(0);

    // - PRIORITY 7: Draw (slowest, last) -
    static datetime s_lastVisualBar = 0;
    static int      s_lastVisualState = -1;
    // Visual refresh bucket: 15 s wall-clock. The old bucket was
    // Slot1_Range_Minutes*60 (with a 120-min range: ONE update every 2 h!),
    // which is why exec objects and trail lines froze until a timeframe or
    // parameter change forced a full redraw.
    int ltfSec = 15;
    datetime curBar = (datetime)((long)now / ltfSec * ltfSec);

    int stateSig = 0;
    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        stateSig += (vTrades[i].active ? 1 : 0) * 2 + (vTrades[i].trailing ? 1 : 0) * 4 + (vTrades[i].exitTime > 0 ? 1 : 0);
        // Trail movements must dirty the signature or the trail line freezes
        stateSig += vTrades[i].trailCount * 8;
        stateSig += (int)((long)vTrades[i].vSL) % 997;
    }
    stateSig += OrdersTotal() * 100 + PositionsTotal() * 10;

    if(curBar != s_lastVisualBar || stateSig != s_lastVisualState)
    {
        s_lastVisualBar   = curBar;
        s_lastVisualState = stateSig;
        for(int s = 0; s < 6; s++)
        {
            if(!SlotEnabled(s)) continue;
            SetSlotContext(s);
            LoadSlotToGlobals(s);
            UpdateVisuals();
        }
        SetSlotContext(0);
        LoadSlotToGlobals(0);
    }
}

//+------------------------------------------------------------------+
//| Adjust intended SL/TP if slippage skewed the geometric distance  |
//+------------------------------------------------------------------+
void NormalizeStopsToFill(ulong ticket, double fillPx, double levelPx)
{
    if(!posInfo.SelectByTicket(ticket)) return;
    bool bull = (posInfo.PositionType() == POSITION_TYPE_BUY);

    if(Use_StopLimit_Orders) return;   // stop-limit fills are not slipped by design
    // Note: instant-exec fills ALSO need recentering - the SL/TP sent with the order
    // are computed from the quote at order-send time; the broker fill can be 100-1000ms
    // later at a different price. NormalizeStopsToFill corrects this on the next tick
    // as a safety net. ExecuteInstantSide also does an immediate in-line correction.

    double slipPts = MathAbs(fillPx - levelPx) / NormPoint();
    datetime nowNSF = TimeCurrent();

    double newTP = bull ? fillPx + TPRaw() : fillPx - TPRaw();
    double newSL = bull ? fillPx - SLRaw() : fillPx + SLRaw();

    // ALREADY-CENTRED GUARD: if the broker SL/TP already sit at the targets
    // (the inline recenter in ExecuteInstantSide succeeded), a re-modify is
    // rejected as "no changes" (err 4756 / rc 10025) and was logged as a
    // scary FAILURE. Compare first; only send when something actually moves.
    double curSL = posInfo.StopLoss();
    double curTP = posInfo.TakeProfit();
    if(MathAbs(curSL - newSL) < _Point && MathAbs(curTP - newTP) < _Point)
    {
        int vtIdxOk = GetVTIdx(ticket);
        if(vtIdxOk >= 0)
        {
            vTrades[vtIdxOk].vSL = NormalizeDouble(newSL, _Digits);
            vTrades[vtIdxOk].vTP = NormalizeDouble(newTP, _Digits);
        }
        return; // already centred — success, not failure
    }

    if(IsNewsFreezingTrail(nowNSF))
    {
        ORBLog(StringFormat("[ORB] Ticket #%I64u filled with %.1f pts slip but news blackout blocks stop modification - broker SL/TP left at pre-slip levels.", ticket, slipPts));
        return;
    }

    trade.SetAsyncMode(false);
    bool modOk = trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), NormalizeDouble(newTP, _Digits));
    trade.SetAsyncMode(true);

    if(!modOk)
    {
        ORBLog(StringFormat("[ORB] Ticket #%I64u slip recenter FAILED err=%d - broker SL/TP left at pre-slip levels.", ticket, GetLastError()));
        return;
    }

    ORBLog(StringFormat("[ORB] Ticket #%I64u fill %.5f (%.1f pts slip). SL/TP recentred to SL=%.5f TP=%.5f.", ticket, fillPx, slipPts, newSL, newTP));

    // CRITICAL: sync the corrected stops back into vTrades so ManageTrailingStops
    // uses the right baseline. Without this, vSL stays at the pre-fill level-based
    // value, and TrailModifyOrLock's idempotency check (targetSL <= vSL) silently
    // blocks all trailing because the trail target is already below the stale vSL.
    int vtIdx = GetVTIdx(ticket);
    if(vtIdx >= 0)
    {
        vTrades[vtIdx].vSL = NormalizeDouble(newSL, _Digits);
        vTrades[vtIdx].vTP = NormalizeDouble(newTP, _Digits);
    }

    // Max_Slippage_Points is a Stop/Stop-Limit-only safety net: instant market
    // execution has its own dedicated slippage gate (Instant_Max_Entry_Slippage_Points)
    // that decides BEFORE the trade whether to take it at all, so this parameter
    // has no business touching an instant-exec fill after the fact.
    if(!Use_Instant_Market_Execution && Max_Slippage_Points > 0 && slipPts > Max_Slippage_Points)
    {
        GlobalVariableSet(StringFormat("ORB_SLIPARM_%I64u", ticket), 1.0);
        ORBLog(StringFormat("[ORB] Ticket #%I64u slip %.1f pts exceeds Max_Slippage_Points=%.1f - trailing disabled; EA will close at market only once profit reaches +%.1f pts (never at a loss).",
                            ticket, slipPts, Max_Slippage_Points, Slip_ForceClose_Profit_Points));
    }
}

void ManageSlipForceClose()
{
    double bidSFC = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double askSFC = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    datetime nowSFC = TimeCurrent();

    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        if(!vTrades[i].active) continue;
        if(vTrades[i].closing) continue;
        if(!vTrades[i].slipForceCloseArmed) continue;
        if(!PositionSelectByTicket(vTrades[i].ticket)) continue;

        double profitRaw = vTrades[i].bull ? (bidSFC - vTrades[i].entryPx) : (vTrades[i].entryPx - askSFC);
        double profitPts = profitRaw / _Point;
        if(profitPts < Slip_ForceClose_Profit_Points) continue;

        if(IsNewsFreezingTrail(nowSFC))
        {
            ORBLog(StringFormat("[ORB] Ticket #%I64u reached +%.1f pts (slip force-close armed) but news blackout blocks closing - will retry next tick.", vTrades[i].ticket, profitPts));
            continue;
        }

        vTrades[i].closing = true;
        if(trade.PositionClose(vTrades[i].ticket))
        {
            ORBLog(StringFormat("[ORB] Ticket #%I64u closed at +%.1f pts (slip force-close).", vTrades[i].ticket, profitPts));
        }
        else
        {
            vTrades[i].closing = false;
            ORBLog(StringFormat("[ORB] Ticket #%I64u slip force-close FAILED err=%d - will retry.", vTrades[i].ticket, GetLastError()));
        }
    }
}

//+------------------------------------------------------------------+
//| Register newly filled positions into virtual tracker             |
//+------------------------------------------------------------------+
void RegisterNewPositions(datetime now)
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!posInfo.SelectByTicket(ticket)) continue;
        if(posInfo.Symbol() != _Symbol) continue;
        if(!MagicMatch((long)posInfo.Magic())) continue;
        if(!ClaimTicket(ticket)) continue;
        if(GetVTIdx(ticket) >= 0) continue; // already tracked

        // ADOPT-ANY: this is one of OUR positions (magic-matched, or symbol-matched
        // when magic is disabled) but not yet tracked -> it was opened this session,
        // OR it is an orphan from before a relaunch / config change. Either way we
        // adopt and manage it. Geometry is reconstructed best-effort so management
        // is config-independent:
        //   - vSL/vTP come from the position's OWN live SL/TP when present (its real
        //     protective geometry), falling back to current-input distance only if
        //     the broker reports none. We never silently re-key an open trade to new
        //     inputs; the snapshot (taken in RegisterVT) freezes trail params now.
        double entry  = posInfo.PriceOpen();
        bool   bull   = (posInfo.PositionType() == POSITION_TYPE_BUY);
        double posSL  = posInfo.StopLoss();
        double posTP  = posInfo.TakeProfit();
        double vSL    = (posSL > 0.0) ? posSL : (bull ? entry - SLRaw() : entry + SLRaw());
        double vTP    = (posTP > 0.0) ? posTP : (bull ? entry + TPRaw() : entry - TPRaw());
        // Use the position's real open time as the fill anchor (for min-trail timing),
        // so an adopted orphan does not get a fresh min-trail window on every relaunch.
        datetime fillTime = (datetime)posInfo.Time();
        if(fillTime <= 0) fillTime = now;
        // RANGE-LEVEL ANCHOR: the level that armed this trade is the originating
        // STOP order's price (the exact range high/low), NOT the slipped fill and
        // NEVER the resolution price. The position ticket equals its opening
        // order's ticket, so recover the exact level from order history. The
        // level's formation candle comes from the live range markers.
        // Priority: recovered stop-order price (the exact range level) ->
        // captured range high/low -> entry (last resort). NEVER leave it on the
        // slipped fill, which is what reads on-chart as the level line "shifting
        // to the resolution price" when fill != level.
        OrderMeta meta;
        bool hasMeta = GetOrderMeta(ticket, meta);
        // Meta recovered from GlobalVariables carries levelPx=0/levelTime=0
        // (only slot/side survive the restart) — trusting those zeros anchored
        // exec objects at epoch/current-slot times (observed: London buy drawn
        // at the Daily box edge). Use each field only when actually valid.
        double   levelPx   = (hasMeta && meta.levelPx   > 0.0) ? meta.levelPx   : (bull ? g_rangeHigh : g_rangeLow);
        datetime levelTime = (hasMeta && meta.levelTime > 0)   ? meta.levelTime : (bull ? g_rangeHighTime : g_rangeLowTime);
        int      slotIdx   = hasMeta ? meta.slotIdx   : g_ctxSlotIdx;
        string   sessKey   = (hasMeta && meta.sessionKey != "") ? meta.sessionKey : g_sessionKey;

        RegisterVT(ticket, bull, entry, vSL, vTP, fillTime, levelPx, levelTime, slotIdx, sessKey);
        MarkSideConsumed((sessKey != "") ? sessKey : g_sessionKey, bull); // fill is permanent for the session, win or lose

        // Stamp trigger params to global variables for offline reconstruction
        // Only if we actually have trail enabled
        if(TrailThreshRaw() > 0.0)
        {
            string pk = StringFormat("ORB_PS_%I64d", (long)ticket);
            GlobalVariableSet(pk+"_THR", TrailThreshRaw());
            GlobalVariableSet(pk+"_GAP", TrailGapRaw());
            GlobalVariableSet(pk+"_MOD", (double)Trail_Mode);
            GlobalVariableSet(pk+"_SL",  vSL);
            GlobalVariableSet(pk+"_TP",  vTP);
            GlobalVariableSet(pk+"_BUL", bull ? 1.0 : 0.0);
            GlobalVariableSet(pk+"_TIM", (double)fillTime);
            // Encode session label: Daily=-1, Weekly=-2, intraday=HH*100+MM
            double lbl_enc = (g_ctxMode == RANGE_DAILY) ? -1.0
                         : (g_ctxMode == RANGE_WEEKLY) ? -2.0
                         : (g_ctxMode == RANGE_MONTHLY) ? -3.0
                           : (double)(g_ctxHour * 100 + g_ctxMin);
            GlobalVariableSet(pk+"_LBL", lbl_enc);
        }
        // The stop just FILLED -> its dashed pending line must be removed now
        // (it lingered until resolution before, overlapping the range level in
        // the same color and reading as a stray range line).
        ORBDeleteObj(ORBPfx()+"PENDING_"+IntegerToString(ticket));
        // Signal 2: Triggered
        ORBNotifyTriggered(ticket, g_sessionKey, bull, entry, vSL, vTP);
    }
}

//+------------------------------------------------------------------+
//| Scans history on init for today's (or this week's) trades and    |
//| registers them into vTrades so they draw retroactively.          |
//+------------------------------------------------------------------+
// First 18:00-NY day close at/after the given server time — the boundary
// past which ALL intraday artifacts (visuals, exec objects) are forgotten.
datetime IntradayDayCloseServer(datetime tSrv)
{
    MqlDateTime nyDC;
    TimeToStruct(ServerToNY(tSrv), nyDC);
    datetime closeSrv = NYLocalToServer(nyDC.year, nyDC.mon, nyDC.day, 18, 0, 0);
    if(tSrv >= closeSrv) closeSrv += 86400;
    return closeSrv;
}

void RedrawBrokerExecutions()
{
    if((bool)MQLInfoInteger(MQL_TESTER)) return;

    datetime now = TimeCurrent();
    
    // Evaluate Day Open and Week Open anchor times
    datetime s1Day = GetCurrentNYTrueDayOpen(now);
    datetime s2Day = (Inp_Slot2AnchorMode == 0) ? GetCurrentNYTrueDayOpen(now) : GetCurrentD1Open(now);
    datetime s2Wk  = (Inp_Slot2AnchorMode == 0) ? GetCurrentNYTrueWeekOpen(now) : GetCurrentW1Open(now);
    
    datetime monthOpen = (Inp_Slot2AnchorMode == 0) ? GetCurrentNYTrueMonthOpen(now) : GetCurrentMN1Open(now);

    datetime scanFrom = s1Day;
    if(SlotEnabled(5)) scanFrom = MathMin(scanFrom, monthOpen);
    if(SlotEnabled(4)) scanFrom = MathMin(scanFrom, s2Wk);
    if(SlotEnabled(3)) scanFrom = MathMin(scanFrom, s2Day);
    
    if(!HistorySelect(scanFrom, now)) return;
    int total = HistoryDealsTotal();
    for(int d = 0; d < total; d++)
    {
        ulong deal = HistoryDealGetTicket(d);
        if(deal == 0) continue;
        if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

        ulong posTicket = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
        if(GetVTIdx(posTicket) >= 0) continue; // Already tracked
        
        bool bull = (HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY);
        double entryPx = HistoryDealGetDouble(deal, DEAL_PRICE);
        datetime fillTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
        
        OrderMeta meta;
        bool hasMeta = GetOrderMeta(posTicket, meta);
        int slotIdx = hasMeta ? meta.slotIdx : 0;
        
        // Scope bounds check: ensure this deal belongs to the active timeframe of its slot
        datetime slotStart = s1Day;
        if(slotIdx == 5)      slotStart = monthOpen;
        else if(slotIdx == 4) slotStart = s2Wk;
        else if(slotIdx == 3) slotStart = s2Day;
        if(fillTime < slotStart) continue;

        // AMNESIA RULE (fix): intraday trades from a trading day that has
        // already closed (18:00 NY) are never re-registered/redrawn — a TF
        // change used to resurrect them here. History/reports keep them; the
        // chart does not.
        if(slotIdx <= 2 && now >= IntradayDayCloseServer(fillTime)) continue;
        
        double levelPx = hasMeta ? meta.levelPx : entryPx;
        datetime levelTime = hasMeta ? meta.levelTime : fillTime;
        string sessKey = hasMeta ? meta.sessionKey : "";
        
        // Geometry reconstruction: use DEAL values if available, else OrderMeta, else fallback to inputs
        double dealSL = HistoryDealGetDouble(deal, DEAL_SL);
        double dealTP = HistoryDealGetDouble(deal, DEAL_TP);
        
        double vSL = dealSL > 0.0 ? dealSL : ( (bull ? entryPx - SLRaw() : entryPx + SLRaw()));
        double vTP = dealTP > 0.0 ? dealTP : ( (bull ? entryPx + TPRaw() : entryPx - TPRaw()));
        
        RegisterVT(posTicket, bull, entryPx, vSL, vTP, fillTime, levelPx, levelTime, slotIdx, sessKey);
        
        // Mark as closed if an OUT deal exists
        for(int e = 0; e < total; e++)
        {
            ulong cd = HistoryDealGetTicket(e);
            if(cd == 0) continue;
            if((ulong)HistoryDealGetInteger(cd, DEAL_POSITION_ID) != posTicket) continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(cd, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
            
            int vtIdx = GetVTIdx(posTicket);
            if(vtIdx >= 0)
            {
                vTrades[vtIdx].active = false;
                vTrades[vtIdx].exitTime = (datetime)HistoryDealGetInteger(cd, DEAL_TIME);
            }
            break;
        }
    }
}


//+------------------------------------------------------------------+
//| Simulate synthetic executions for the current day/week (if no    |
//| real executions exist for that slot yet).                        |
//+------------------------------------------------------------------+
void SimulateSyntheticExecutions()
{
    if((bool)MQLInfoInteger(MQL_TESTER)) return;

    datetime now = TimeCurrent();

    for(int s = 0; s < 6; s++)
    {
        if(!SlotEnabled(s)) continue;

        SetSlotContext(s);
        LoadSlotToGlobals(s);

        if(!g_rangeReady || g_rangeHigh <= 0.0 || g_rangeLow >= 999999.0) continue;

        datetime srvOpen = SessionOpenServer(now);
        datetime srvCutoff = SessionCutoffServer(now);
        if(srvOpen <= 0 || srvCutoff <= 0) continue;

        // Skip if a real trade was already registered for this slot session
        bool hasReal = false;
        string key = ActiveSessionKey(now);
        for(int i = 0; i < ArraySize(vTrades); i++)
        {
            if(vTrades[i].slotIdx == s && StringFind(vTrades[i].sessionKey, key) >= 0)
            {
                hasReal = true;
                break;
            }
        }
        if(hasReal) continue;

        MqlRates rates[];
        // Only check bars after range cutoff
        int copied = CopyRates(_Symbol, PERIOD_M1, srvCutoff, now, rates);
        if(copied <= 0) continue;

        int triggerIdx = -1;
        bool triggeredBull = false;
        double triggerPx = 0.0;
        datetime triggerTime = 0;

        double bullTrigger = g_rangeHigh;
        double bearTrigger = g_rangeLow;

        for(int i = 0; i < copied; i++)
        {
            if(true)
            {
                if(rates[i].high >= bullTrigger)
                {
                    bool walkedAway = false;
                    if(Use_StopLimit_Orders)
                    {
                        double minRetrace = bullTrigger - (SLRaw() * 0.1);
                        if(rates[i].low <= minRetrace || rates[i].close <= minRetrace) walkedAway = true;
                    }
                    // The user said: "if price didn't retrace within the same 1m bar that activated it, then the limit most-likely did not trigger, regardless, i do not think that 10% retrace mechanism is important, as far as price retroactively touched the range high price level of the selected range, the EA should draw the execution objects"
                    // Therefore we IGNORE walkedAway. It triggers immediately on touch.
                    triggerIdx = i;
                    triggeredBull = true;
                    triggerPx = bullTrigger;
                    triggerTime = rates[i].time;
                    break;
                }
            }
            if(true)
            {
                if(rates[i].low <= bearTrigger)
                {
                    bool walkedAway = false;
                    if(Use_StopLimit_Orders)
                    {
                        double minRetrace = bearTrigger + (SLRaw() * 0.1);
                        if(rates[i].high >= minRetrace || rates[i].close >= minRetrace) walkedAway = true;
                    }
                    if(triggerIdx == -1) // If bull didn't trigger first in the same bar (or previous bar)
                    {
                        triggerIdx = i;
                        triggeredBull = false;
                        triggerPx = bearTrigger;
                        triggerTime = rates[i].time;
                        break;
                    }
                }
            }
        }

        if(triggerIdx != -1)
        {
            double vSL = triggeredBull ? triggerPx - SLRaw() : triggerPx + SLRaw();
            double vTP = triggeredBull ? triggerPx + TPRaw() : triggerPx - TPRaw();
            
            // Register it as a synthetic trade
            ulong fakeTicket = (ulong)triggerTime + s + 999000;
            RegisterVT(fakeTicket, triggeredBull, triggerPx, vSL, vTP, triggerTime, triggerPx, triggerTime, s, "SYNTHETIC_" + key);
        }
    }

    // Restore slot 0
    SetSlotContext(0);
    LoadSlotToGlobals(0);
}

//+------------------------------------------------------------------+
//| ComputeVirtualClose                                              |
//| Scans M1 bars from fill to close to find the price extreme, then |
//| computes where the trail stop WOULD have been at that extreme.   |
//|                                                                  |
//| Returns virtualClose when the trail would have meaningfully       |
//| improved on actualClose (- minDiff away); returns actualClose    |
//| otherwise, including when trail never activated.                 |
//|                                                                  |
//| NOTE: TP closes are NOT adjusted - the broker auto-executes TP   |
//| regardless of EA state. The caller must check for TP before      |
//| calling this function.                                           |
//+------------------------------------------------------------------+
double ComputeVirtualClose(bool bull, double entryPx,
                            double snapSL,   // initial broker SL (trail never goes past this)
                            double snapThreshRaw, double snapGapRaw, int snapTrailMode,
                            datetime openTime, datetime closeTime, double actualClose)
{
    if(snapThreshRaw <= 0.0 || snapGapRaw <= 0.0) return actualClose;
    if(openTime <= 0 || closeTime <= openTime)     return actualClose;

    // Scan every M1 bar between fill and close for the price extreme.
    // M1 bar highs/lows give sub-minute accuracy sufficient for trail math.
    MqlRates rates[];
    ArraySetAsSeries(rates, false);
    int cnt = CopyRates(_Symbol, PERIOD_M1, openTime, closeTime, rates);
    if(cnt <= 0) return actualClose;

    double extreme = entryPx;
    for(int k = 0; k < cnt; k++)
    {
        if(bull) extreme = MathMax(extreme, rates[k].high);
        else     extreme = MathMin(extreme, rates[k].low + (double)rates[k].spread * _Point);
    }

    double maxProfit = bull ? extreme - entryPx : entryPx - extreme;
    if(maxProfit < snapThreshRaw) return actualClose;  // trail threshold never reached

    // Compute virtual trail stop at the maximum excursion point.
    double virtualSL;
    if(snapTrailMode == 1)  // STEP: locked in whole-threshold increments
    {
        int steps = (int)MathFloor(maxProfit / snapThreshRaw);
        if(steps < 1) return actualClose;
        virtualSL = bull ? entryPx + ((double)steps * snapThreshRaw - snapGapRaw)
                         : entryPx - ((double)steps * snapThreshRaw - snapGapRaw);
    }
    else  // CONTINUOUS: trails by gap behind the extreme
    {
        virtualSL = bull ? extreme - snapGapRaw : extreme + snapGapRaw;
    }
    virtualSL = NormalizeDouble(virtualSL, _Digits);

    // Virtual stop must not be worse than the initial broker SL
    if(bull  && snapSL > 0.0) virtualSL = MathMax(virtualSL, snapSL);
    if(!bull && snapSL > 0.0) virtualSL = MathMin(virtualSL, snapSL);

    // Return virtual only if it is MEANINGFULLY better than actual close.
    // The 10% of gapRaw guard prevents M1 bar approximation noise from
    // falsely overriding a result where the EA was already managing correctly.
    double minDiff = MathMax(5.0 * _Point, 0.10 * snapGapRaw);
    if(bull  && virtualSL > actualClose + minDiff) return virtualSL;
    if(!bull && virtualSL < actualClose - minDiff) return virtualSL;
    return actualClose;
}

//+------------------------------------------------------------------+
//| ScanOfflineClosedTrades                                          |
//| Called once on EA init. Scans the last 7 days of deal history   |
//| for positions that closed while the EA was offline. For each one |
//| it checks if a resolution signal was already sent; if not, it    |
//| reconstructs the virtual close from M1 history and sends.        |
//+------------------------------------------------------------------+
void ScanOfflineClosedTrades()
{
    if((bool)MQLInfoInteger(MQL_TESTER)) return;
    datetime scanFrom = TimeCurrent() - 7 * 86400;
    if(!HistorySelect(scanFrom, TimeCurrent())) return;
    int total = HistoryDealsTotal();

    for(int d = 0; d < total; d++)
    {
        ulong closeDeal = HistoryDealGetTicket(d);
        if(closeDeal == 0) continue;
        if(HistoryDealGetString(closeDeal, DEAL_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)HistoryDealGetInteger(closeDeal, DEAL_MAGIC))) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(closeDeal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

        ulong posTicket = (ulong)HistoryDealGetInteger(closeDeal, DEAL_POSITION_ID);

        // Skip if either resolution path already fired for this position
        string offKey = StringFormat("ORBN_RESOFF_%I64d", (long)posTicket);
        if(GlobalVariableCheck(offKey)) continue;

        ENUM_DEAL_TYPE dType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(closeDeal, DEAL_TYPE);
        bool     bull      = (dType == DEAL_TYPE_SELL);
        double   closePx   = HistoryDealGetDouble(closeDeal, DEAL_PRICE);
        double   grossPnl  = HistoryDealGetDouble(closeDeal, DEAL_PROFIT);
        double   overhead  = HistoryDealGetDouble(closeDeal, DEAL_COMMISSION)
                           + HistoryDealGetDouble(closeDeal, DEAL_SWAP);
        datetime closeTime = (datetime)HistoryDealGetInteger(closeDeal, DEAL_TIME);

        // Find entry deal to get open price and fill time
        double   entryPx  = 0.0;
        datetime openTime = 0;
        for(int e = 0; e < total; e++)
        {
            ulong ed = HistoryDealGetTicket(e);
            if(ed == 0) continue;
            if((ulong)HistoryDealGetInteger(ed, DEAL_POSITION_ID) != posTicket) continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ed, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
            entryPx  = HistoryDealGetDouble(ed, DEAL_PRICE);
            openTime = (datetime)HistoryDealGetInteger(ed, DEAL_TIME);
            break;
        }
        if(entryPx <= 0.0 || openTime == 0) continue;

        // Load snap parameters stored at RegisterNewPositions time.
        // Fall back to current inputs only as last resort.
        string pk      = StringFormat("ORB_PS_%I64d", (long)posTicket);
        bool   hasSnap = GlobalVariableCheck(pk+"_THR");
        double thrRaw  = hasSnap ? GlobalVariableGet(pk+"_THR") : TrailThreshRaw();
        double gapRaw  = hasSnap ? GlobalVariableGet(pk+"_GAP") : TrailGapRaw();
        int    trlMode = hasSnap ? (int)GlobalVariableGet(pk+"_MOD") : (int)Trail_Mode;
        double snapSL  = hasSnap ? GlobalVariableGet(pk+"_SL")  : 0.0;
        double snapTP  = hasSnap ? GlobalVariableGet(pk+"_TP")  : 0.0;

        // Only apply virtual reconstruction when we have reliable snap data
        // AND the close was not at TP (TP is broker-auto regardless of EA state).
        bool closedAtTP = (snapTP > 0.0) && (bull ? closePx >= snapTP - 5.0*_Point
                                                   : closePx <= snapTP + 5.0*_Point);
        double effectivePx  = closePx;
        double effectivePnl = grossPnl + overhead;

        if(!closedAtTP && hasSnap && thrRaw > 0.0)
        {
            effectivePx = ComputeVirtualClose(bull, entryPx, snapSL,
                                              thrRaw, gapRaw, trlMode,
                                              openTime, closeTime, closePx);
            if(effectivePx != closePx)
            {
                double actualDiff  = bull ? closePx    - entryPx : entryPx - closePx;
                double virtualDiff = bull ? effectivePx - entryPx : entryPx - effectivePx;
                if(MathAbs(actualDiff) > _Point)
                    effectivePnl = grossPnl * (virtualDiff / actualDiff) + overhead;
            }
        }

        GlobalVariableSet(offKey, (double)TimeCurrent());
        // Reconstruct a sessionKey that SessionLabelFromKey can parse correctly
        string pk2     = StringFormat("ORB_PS_%I64d", (long)posTicket);
        string sessKey;
        if(GlobalVariableCheck(pk2+"_LBL"))
        {
            double lbl_enc = GlobalVariableGet(pk2+"_LBL");
            if(lbl_enc < -1.5)       sessKey = "S0_WEEKLY_0";
            else if(lbl_enc < -0.5)  sessKey = "S0_DAILY_0";
            else
            {
                int hh = (int)(lbl_enc / 100.0);
                int mm = (int)(lbl_enc - hh * 100.0);
                sessKey = StringFormat("S0_20000101_M0_%02d%02d", hh, mm);
            }
        }
        else
            sessKey = StringFormat("OFFLINE_%I64d", (long)posTicket);
        ORBNotifyResolution((ulong)posTicket, sessKey, bull,
                            entryPx, effectivePx, effectivePnl,
                            0, (trlMode==1), gapRaw, thrRaw, effectivePx,
                            AccountInfoDouble(ACCOUNT_BALANCE));
    }
}

//+------------------------------------------------------------------+
//| Sync closed positions                                            |
//+------------------------------------------------------------------+
void SyncClosedTrades()
{
    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        if(!vTrades[i].active) continue;
        if(PositionSelectByTicket(vTrades[i].ticket)) continue;  // still open

        if(vTrades[i].exitTime == 0)
        {
            vTrades[i].exitTime = TimeCurrent();
            bool bull = vTrades[i].bull;

            // Collect close price and time from deal history
            double   exitPx    = 0.0;
            double   pnl       = 0.0;
            double   grossPnl  = 0.0;
            double   overhead  = 0.0;
            datetime closeTime = 0;
            if(HistorySelectByPosition(vTrades[i].ticket))
                for(int d = HistoryDealsTotal()-1; d >= 0; d--)
                {
                    ulong dt = HistoryDealGetTicket(d);
                    if(dt == 0) continue;
                    grossPnl  += HistoryDealGetDouble(dt, DEAL_PROFIT);
                    overhead  += HistoryDealGetDouble(dt, DEAL_COMMISSION)
                               + HistoryDealGetDouble(dt, DEAL_SWAP);
                    ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY);
                    if(de == DEAL_ENTRY_OUT && exitPx == 0.0)
                    {
                        exitPx    = HistoryDealGetDouble(dt, DEAL_PRICE);
                        closeTime = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
                    }
                }
            
            if(exitPx == 0.0 || closeTime == 0)
            {
                vTrades[i].exitTime = 0;
                continue; // deal history not yet replicated, wait for next tick
            }
            
            pnl = grossPnl + overhead;
            // at the price extreme, then use the better of virtual vs actual.
            //
            // This covers four scenarios in one path:
            //   1. EA offline from entry: trail never managed, SL hit - - virtual saves it
            //   2. EA online then offline: trail moved once, price went further, EA
            //      couldn't trail further, hit older trail stop - - virtual finds max extreme
            //   3. EA fully online + trailing correct: virtual -  actual - - no change
            //   4. Trail never activated (price never hit threshold): virtual = actual
            bool closedAtTP = (vTrades[i].vTP > 0.0) &&
                              (bull ? exitPx >= vTrades[i].vTP - 5.0*_Point
                                    : exitPx <= vTrades[i].vTP + 5.0*_Point);

            if(!closedAtTP && vTrades[i].snapThreshRaw > 0.0 &&
               vTrades[i].triggerTime > 0 && closeTime > 0 && exitPx > 0.0)
            {
                double virtualPx = ComputeVirtualClose(
                    bull, vTrades[i].entryPx, vTrades[i].vSL,
                    vTrades[i].snapThreshRaw, vTrades[i].snapGapRaw,
                    vTrades[i].snapTrailMode,
                    vTrades[i].triggerTime, closeTime, exitPx);

                if(virtualPx != exitPx)
                {
                    double actualDiff  = bull ? exitPx    - vTrades[i].entryPx
                                              : vTrades[i].entryPx - exitPx;
                    double virtualDiff = bull ? virtualPx - vTrades[i].entryPx
                                              : vTrades[i].entryPx - virtualPx;
                    if(MathAbs(actualDiff) > _Point)
                        pnl = grossPnl * (virtualDiff / actualDiff) + overhead;
                    exitPx = virtualPx;
                }
            }

            // Signal 3: Resolution
            ORBNotifyResolution(vTrades[i].ticket, vTrades[i].sessionKey,
                                bull, vTrades[i].entryPx, exitPx, pnl,
                                vTrades[i].trailCount,
                                (vTrades[i].snapTrailMode == 1),
                                vTrades[i].snapGapRaw,
                                vTrades[i].snapThreshRaw,
                                vTrades[i].lastTrailSL,
                                AccountInfoDouble(ACCOUNT_BALANCE));

            // Stamp so ScanOfflineClosedTrades never re-fires for this ticket
            GlobalVariableSet(StringFormat("ORBN_RESOFF_%I64d", (long)vTrades[i].ticket),
                              (double)TimeCurrent());

            g_lastTradeProfit = pnl;
            GetDailyProfitPct(TimeCurrent(), true);
            ORBReportLedgerAppend(vTrades[i].bull, pnl);
        }
        vTrades[i].active = false;
    }
}

//+------------------------------------------------------------------+
//| Broker minimum stop distance (price units), with safe fallback.   |
//| Some brokers report SYMBOL_TRADE_STOPS_LEVEL = 0; treat that as no |
//| broker minimum and use a tiny epsilon so guards still behave.     |
//+------------------------------------------------------------------+
double BrokerStopLevelRaw()
{
    long sl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double raw = (double)sl * _Point;
    if(raw < _Point) raw = _Point;   // epsilon floor; never zero/negative
    return raw;
}

//+------------------------------------------------------------------+
//| Move SL when the target is valid and improves the current stop.    |
//| Returns true if a server action was sent.                          |
//+------------------------------------------------------------------+
bool TrailModifyOrLock(int idx, double targetSL, double bid, double ask)
{
    if(vTrades[idx].closing) return false;   // a close is already in flight

    double stopLvl = BrokerStopLevelRaw();
    bool   bull    = vTrades[idx].bull;
    // Distance from CURRENT market (exit side) to the candidate SL.
    double marketPx = bull ? bid : ask;          // closeable side
    double dist     = bull ? (marketPx - targetSL) : (targetSL - marketPx);

    if(dist < stopLvl && Force_Close_If_Trail_Stop_Too_Close)
    {
        vTrades[idx].closing = true;
        trade.SetAsyncMode(false);
        bool closed = trade.PositionClose(vTrades[idx].ticket);
        trade.SetAsyncMode(true);
        if(!closed) vTrades[idx].closing = false;
        return closed;
    }

    // Idempotent only: do not delay real trailing beyond a tick-sized change.
    double minMove = _Point;
    if(bull)
    {
        if(targetSL <= vTrades[idx].vSL + minMove) return false;
    }
    else
    {
        if(targetSL >= vTrades[idx].vSL - minMove) return false;
    }

    // Debounce: cap how often we actually hit the broker with a modify. Firing
    // a synchronous request on every single tick-sized nudge (as before) means
    // OnTick blocks for that request's full round-trip before it can process
    // the next tick - in a fast market that adds up and shows up as trailing
    // "taking breaks" then jumping to catch up. 150ms still feels effectively
    // instant to a human watching the chart, but gives the terminal room to
    // keep up with the tick stream between broker round-trips.
    uint nowMs = GetTickCount();
    if(vTrades[idx].lastModifyAttemptMs != 0 && (nowMs - vTrades[idx].lastModifyAttemptMs) < 150) return false;
    vTrades[idx].lastModifyAttemptMs = nowMs;

    // Async: don't block subsequent tick processing on this request's
    // round-trip. We optimistically record targetSL as the new vSL on send
    // (same as the previous synchronous behavior did on success) - if the
    // modify is ultimately rejected, the very next eligible tick will simply
    // try again since price will still justify a trail.
    trade.SetAsyncMode(true);
    bool ok = trade.PositionModify(vTrades[idx].ticket, targetSL, posInfo.TakeProfit());
    if(!ok)
    {
        ORBLog(StringFormat("[ORB] TrailModifyOrLock failed. Ticket: %I64d, Retcode: %d", vTrades[idx].ticket, trade.ResultRetcode()));
        return false;
    }
    vTrades[idx].vSL = targetSL;
    return true;
}

//+------------------------------------------------------------------+
//| Trailing stop logic - snapshot-driven, in-profit only            |
//| Reads ONLY each trade's frozen snapshot (gap/threshold/mode/min-  |
//| trail), never the live inputs, so config/session changes mid-     |
//| trade can never mis-manage an open position.                      |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
    double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double spread = ask - bid;
    datetime now  = TimeCurrent();

    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        if(!vTrades[i].active) continue;
        if(vTrades[i].closing) continue;                       // close already in flight
        if(vTrades[i].slipForceCloseArmed) continue;           // excess-slip trade: force-close-at-profit replaces trailing entirely
        if(!PositionSelectByTicket(vTrades[i].ticket)) continue;
        if(!posInfo.SelectByTicket(vTrades[i].ticket)) continue;

        // SELF-HEALING BASELINE (fix): the broker's live SL is ground truth.
        // Two desync modes both ended as "EA watches price move for nothing,
        // trade runs to full SL":
        //   1. vSL stale-behind (failed recenter/relaunch) → wrong baseline.
        //   2. vSL phantom-AHEAD: TrailModifyOrLock records the target on
        //      async SEND; if the broker rejects it, vSL stays advanced, the
        //      forward-only check then blocks every retry, and the REAL stop
        //      never moved.
        // Re-adopt the broker value in either direction once no modify has
        // been in flight for >2s (the optimistic window).
        double liveSLSync = posInfo.StopLoss();
        if(liveSLSync > 0.0 && MathAbs(liveSLSync - vTrades[i].vSL) > _Point)
        {
            uint nowMsSync = GetTickCount();
            bool inFlight = vTrades[i].lastModifyAttemptMs != 0 &&
                            (nowMsSync - vTrades[i].lastModifyAttemptMs) < 2000;
            if(!inFlight)
            {
                if(Verbose_Journal)
                    ORBLog(StringFormat("[ORB] Ticket #%I64u trail baseline re-synced from broker: vSL %.5f -> %.5f",
                                        vTrades[i].ticket, vTrades[i].vSL, liveSLSync));
                vTrades[i].vSL = liveSLSync;
            }
        }

        // SNAPSHOT-DRIVEN: read this trade's frozen geometry, never live inputs.
        double thrRaw = vTrades[i].snapThreshRaw;
        double gapRaw = vTrades[i].snapGapRaw;
        if(thrRaw <= 0.0) thrRaw = TrailThreshRaw();           // legacy/orphan fallback

        // TRAIL BEHAVIOR (snapshot): OFF -> fixed SL/TP only, never touch the stop.
        if(vTrades[i].snapBehavior == TRAILB_OFF) continue;

        // TRAIL FREEZE: news engine pauses trailing during blackout windows.
        if(IsNewsFreezingTrail(now))
        {
            if(!vTrades[i].trailFrozenLogged)
            {
                ORBLog(StringFormat("[ORB] Trailing frozen for ticket #%I64u due to active News blackout window.", vTrades[i].ticket));
                vTrades[i].trailFrozenLogged = true;
            }
            continue;
        }
        else
        {
            if(vTrades[i].trailFrozenLogged)
            {
                ORBLog(StringFormat("[ORB] News blackout window ended. Trailing resumed for ticket #%I64u.", vTrades[i].ticket));
                vTrades[i].trailFrozenLogged = false;
            }
        }

        // BREAKEVEN-ONLY: once profit reaches the activation threshold (and the
        // min-trail window has passed), move the SL ONCE to entry +/- costs
        // (live spread + snapshot commission cushion), then hands-off forever.
        if(vTrades[i].snapBehavior == TRAILB_BE)
        {
            if(vTrades[i].trailing) continue;                  // BE already set
            if(vTrades[i].snapMinTrailSec > 0 &&
               (long)(now - vTrades[i].triggerTime) < (long)vTrades[i].snapMinTrailSec) continue;
            double entryBE = vTrades[i].entryPx;
            double profBE  = vTrades[i].bull ? (bid - entryBE) : (entryBE - bid);
            if(profBE < thrRaw) continue;
            double cost = vTrades[i].snapSpreadComp ? (spread + vTrades[i].snapBECostRaw) : 0.0;
            double beSL = vTrades[i].bull ? entryBE + cost : entryBE - cost;
            if(TrailModifyOrLock(i, NormalizeDouble(beSL, _Digits), bid, ask))
            {
                vTrades[i].trailing       = true;
                vTrades[i].trailStartTime = now;
                ORBNotifyTrail(vTrades[i].ticket, vTrades[i].sessionKey,
                               vTrades[i].bull, beSL,
                               SessionLabelFromKey(vTrades[i].sessionKey),
                               vTrades[i].snapTrailMode, gapRaw);
            }
            continue;
        }
        if(gapRaw <= 0.0) gapRaw = TrailGapRaw();
        double trailGapRaw = gapRaw;
        double entrySpread = vTrades[i].snapEntrySpreadRaw;
        if(entrySpread <= 0.0) entrySpread = spread;
        if(vTrades[i].snapSpreadComp)
            trailGapRaw = MathMax(_Point, gapRaw - entrySpread);
        double activate = thrRaw;

        // MIN-TRAIL gate: trailing may not start until N seconds after fill,
        // regardless of profit reached (prevents trigger-candle pullback stops).
        // Applies only to ACTIVATION; once trailing, it keeps following.
        if(!vTrades[i].trailing && vTrades[i].snapMinTrailSec > 0
           && vTrades[i].triggerTime > 0
           && (now - vTrades[i].triggerTime) < vTrades[i].snapMinTrailSec)
            continue;

        double entry = vTrades[i].entryPx;

        if(vTrades[i].bull)
        {
            double profit = bid - entry;            // real closeable profit (at BID)
            if(profit < activate) continue;          // not yet eligible to trail

            double contSL   = bid - trailGapRaw;     // continuous follow, chart-price based
            double targetSL = contSL;
            if(vTrades[i].snapTrailMode == 1)        // STEP: lock per whole threshold, constant gap
            {
                int steps = (int)MathFloor(profit / thrRaw);
                if(steps < 1) continue;
                targetSL = entry + ((double)steps * thrRaw - trailGapRaw);
            }
            double maxSL = bid - BrokerStopLevelRaw();
            if(targetSL > maxSL) targetSL = maxSL;
            targetSL = NormalizeDouble(targetSL, _Digits);

            // Only advance the stop forward (never backward).
            if(vTrades[i].trailing && targetSL <= vTrades[i].vSL) continue;

            bool firstTrail = !vTrades[i].trailing;
            if(TrailModifyOrLock(i, targetSL, bid, ask))
            {
                if(firstTrail)
                {
                    vTrades[i].trailing       = true;
                    vTrades[i].trailStartTime = now;
                    ORBNotifyTrail(vTrades[i].ticket, vTrades[i].sessionKey,
                                   true, targetSL,
                                   SessionLabelFromKey(vTrades[i].sessionKey),
                                   vTrades[i].snapTrailMode, gapRaw);
                }
                vTrades[i].trailCount++;
                vTrades[i].lastTrailSL = targetSL;
            }
        }
        else
        {
            double profit = entry - bid;            // chart-price profit (BID); visually matches chart
            if(profit < activate) continue;

            double contSL   = ask + trailGapRaw;
            double targetSL = contSL;
            if(vTrades[i].snapTrailMode == 1)
            {
                int steps = (int)MathFloor(profit / thrRaw);
                if(steps < 1) continue;
                targetSL = entry - ((double)steps * thrRaw - trailGapRaw);
            }
            double minSL = ask + BrokerStopLevelRaw();
            if(targetSL < minSL) targetSL = minSL;
            targetSL = NormalizeDouble(targetSL, _Digits);

            if(vTrades[i].trailing && targetSL >= vTrades[i].vSL) continue;

            bool firstTrail = !vTrades[i].trailing;
            if(TrailModifyOrLock(i, targetSL, bid, ask))
            {
                if(firstTrail)
                {
                    vTrades[i].trailing       = true;
                    vTrades[i].trailStartTime = now;
                    ORBNotifyTrail(vTrades[i].ticket, vTrades[i].sessionKey,
                                   false, targetSL,
                                   SessionLabelFromKey(vTrades[i].sessionKey),
                                   vTrades[i].snapTrailMode, gapRaw);
                }
                vTrades[i].trailCount++;
                vTrades[i].lastTrailSL = targetSL;
            }
        }
    }
}

void ResetRangeBuild()
{
    g_rangeBuildKey = "";
    g_rangeBuildStart = 0;
    g_rangeBuildEnd = 0;
    g_rangeBuildHigh = 0.0;
    g_rangeBuildLow = 0.0;
    g_rangeBuildHighTime = 0;
    g_rangeBuildLowTime = 0;
    g_rangeBuildReady = false;
}

bool UpdateOpeningRangeBuild(datetime now)
{
    datetime rangeEnd = SessionOpenServer(now);
    datetime rangeStart = rangeEnd - ((int)Slot1_Range_Minutes * 60);
    if(now < rangeStart) return false;

    string buildKey = ActiveSessionKey(now);
    if(buildKey != g_rangeBuildKey || rangeStart != g_rangeBuildStart || rangeEnd != g_rangeBuildEnd)
    {
        ResetRangeBuild();
        g_rangeBuildKey = buildKey;
        g_rangeBuildStart = rangeStart;
        g_rangeBuildEnd = rangeEnd;
    }

    datetime copyTo = (now < rangeEnd) ? now : (rangeEnd - 1);
    if(copyTo < rangeStart) return false;

    MqlRates rates[];
    ArraySetAsSeries(rates, false);
    int copied = CopyRates(_Symbol, PERIOD_M1, rangeStart, copyTo, rates);
    if(copied <= 0) return false;

    double hi = -DBL_MAX, lo = DBL_MAX;
    datetime hiTime = rangeStart, loTime = rangeStart;
    for(int i = 0; i < copied; i++)
    {
        if(rates[i].high > hi) { hi = rates[i].high; hiTime = rates[i].time; }
        if(rates[i].low  < lo) { lo = rates[i].low;  loTime = rates[i].time; }
    }
    if(hi == -DBL_MAX || lo == DBL_MAX) return false;

    g_rangeBuildHigh = NormalizeDouble(hi, _Digits);
    g_rangeBuildLow = NormalizeDouble(lo, _Digits);
    g_rangeBuildHighTime = hiTime;
    g_rangeBuildLowTime = loTime;
    g_rangeBuildReady = true;
    return true;
}

bool LoadRangeWindow(datetime rangeStart, datetime rangeEnd,
                     double &hi, double &lo, datetime &hiTime, datetime &loTime)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, false);
    int copied = CopyRates(_Symbol, PERIOD_M1, rangeStart, rangeEnd - 1, rates);
    if(copied <= 0) return false;

    hi = -DBL_MAX;
    lo = DBL_MAX;
    hiTime = rangeStart;
    loTime = rangeStart;
    for(int i = 0; i < copied; i++)
    {
        if(rates[i].high > hi) { hi = rates[i].high; hiTime = rates[i].time; }
        if(rates[i].low  < lo) { lo = rates[i].low;  loTime = rates[i].time; }
    }
    return (hi != -DBL_MAX && lo != DBL_MAX);
}

int TimeframeMinutes(ENUM_TIMEFRAMES tf)
{
    return (int)(PeriodSeconds(tf) / 60);
}







//+------------------------------------------------------------------+
//| Check opening range candles and set g_rangeHigh/Low             |
//+------------------------------------------------------------------+
void CheckOpeningRange(datetime now)
{
    datetime sessionOpen = SessionOpenServer(now);

    if(g_ctxMode != RANGE_INTRADAY)
    {
        if(g_rangeReady) return;  // already locked for this session; do not redraw every tick
        if(now >= sessionOpen)
        {
            double hi = 0.0;
            double lo = 0.0;
            datetime hiTime = 0;
            datetime loTime = 0;
            datetime rangeStart = 0;
            datetime rangeEnd = sessionOpen;
            bool ok = false;

            bool trueAnchor = (g_ctxMode == RANGE_MONTHLY && Inp_Slot2AnchorMode == 0);
            bool isCrypto   = (ORBNFamily(_Symbol) == ORBN_FAM_CRYPTO);
            
            if(trueAnchor)
            {
                // For the M1 true-anchor, compute a rangeStart that lands on
                // the open of the previous *trading* day (skipping the weekend
                // gap on non-crypto assets).
                int secondsBack = (g_ctxMode == RANGE_DAILY) ? 86400 : (g_ctxMode == RANGE_WEEKLY) ? 7 * 86400 : 30 * 86400;
                rangeStart = sessionOpen - (datetime)secondsBack;
                
                if(!isCrypto && g_ctxMode == RANGE_DAILY)
                {
                    // Walk backward until we land on a weekday
                    MqlDateTime dtRS;
                    for(int safetyLimit = 0; safetyLimit < 3; safetyLimit++)
                    {
                        TimeToStruct(rangeStart, dtRS);
                        if(dtRS.day_of_week == 6)       rangeStart -= 86400; // Sat -> Fri
                        else if(dtRS.day_of_week == 0)  rangeStart -= 2*86400; // Sun -> Fri
                        else break;
                    }
                }
                
                ok = LoadRangeWindow(rangeStart, rangeEnd, hi, lo, hiTime, loTime);
                if(!ok)
                {
                    // Fresh broker logins often have D1/W1 history before the
                    // full M1 window is synchronized. Fall back to broker bars
                    // instead of leaving the secondary slot unarmed all day.
                    ENUM_TIMEFRAMES tf = (g_ctxMode == RANGE_DAILY) ? PERIOD_D1 : (g_ctxMode == RANGE_WEEKLY) ? PERIOD_W1 : PERIOD_MN1;
                    int barIdx = 1;
                    if(!isCrypto && g_ctxMode == RANGE_DAILY)
                    {
                        // Skip Sunday D1 bars (tiny weekend candle on some brokers)
                        for(int safetyLimit = 0; safetyLimit < 5; safetyLimit++, barIdx++)
                        {
                            datetime bt = iTime(_Symbol, tf, barIdx);
                            if(bt <= 0) break;
                            MqlDateTime dtB; TimeToStruct(bt, dtB);
                            if(dtB.day_of_week != 0) break; // not Sunday - - valid
                        }
                    }
                    hi = iHigh(_Symbol, tf, barIdx);
                    lo = iLow(_Symbol, tf, barIdx);
                    hiTime = iTime(_Symbol, tf, barIdx);
                    loTime = hiTime;
                    rangeStart = hiTime;
                    ok = (hi > 0.0 && lo > 0.0 && hiTime > 0);
                    if(ok && !Inp_StealthMode)
                        ORBLog("[ORB] True-anchor M1 range unavailable; using broker D1/W1 fallback range.");
                }
            }
            else
            {
                ENUM_TIMEFRAMES tf = (g_ctxMode == RANGE_DAILY) ? PERIOD_D1 : (g_ctxMode == RANGE_WEEKLY) ? PERIOD_W1 : PERIOD_MN1;
                int barIdx = 1;
                if(!isCrypto && g_ctxMode == RANGE_DAILY)
                {
                    // Skip Sunday D1 bars - on some retail brokers a tiny Sunday
                    // candle appears at index 1 (20:54- only). Walk forward
                    // until we find a non-Sunday bar (Friday = previous trading day).
                    for(int safetyLimit = 0; safetyLimit < 5; safetyLimit++, barIdx++)
                    {
                        datetime bt = iTime(_Symbol, tf, barIdx);
                        if(bt <= 0) break;
                        MqlDateTime dtB; TimeToStruct(bt, dtB);
                        if(dtB.day_of_week != 0) break; // not Sunday - - valid
                    }
                }
                hi = iHigh(_Symbol, tf, barIdx);
                lo = iLow(_Symbol, tf, barIdx);
                hiTime = iTime(_Symbol, tf, barIdx);
                loTime = hiTime;
                rangeStart = hiTime;
                ok = (hi > 0.0 && lo > 0.0 && hiTime > 0);
            }

            if(ok)
            {
                g_rangeHigh     = hi;
                g_rangeLow      = lo;
                g_rangeHighTime = hiTime;
                g_rangeLowTime  = loTime;
                g_rangeStart    = rangeStart;
                g_rangeEnd      = rangeEnd;
                g_rangeReady    = true;
                DrawRangeBox(g_sessionKey, g_rangeStart, g_rangeEnd, g_rangeHigh, g_rangeLow);
                ORBLog(StringFormat("[ORB] %s Range ready: Hi=%.5f Lo=%.5f Size=%.1f pts",
                                    (g_ctxMode == RANGE_DAILY ? "DAILY" : (g_ctxMode == RANGE_WEEKLY ? "WEEKLY" : "MONTHLY")),
                                    g_rangeHigh, g_rangeLow, (g_rangeHigh - g_rangeLow)/_Point));
            }
        }
        return;
    }

    datetime rangeEnd    = sessionOpen;
    datetime rangeStart  = rangeEnd - ((int)Slot1_Range_Minutes * 60);

    UpdateOpeningRangeBuild(now);
    if(now < rangeEnd)
    {
        // Always arm: compute pending levels within 1s of range close so orders
        // are fully staged before the breakout candle opens.
        bool inArmWindow = (!Reverse_Orders && 
                            !g_precloseArmed && g_rangeBuildReady &&
                            g_rangeBuildStart == rangeStart && g_rangeBuildEnd == rangeEnd &&
                            (double)(rangeEnd - now) <= 1.0);
        if(!inArmWindow) return;

        g_rangeHigh     = g_rangeBuildHigh;
        g_rangeLow      = g_rangeBuildLow;
        g_rangeHighTime = g_rangeBuildHighTime;
        g_rangeLowTime  = g_rangeBuildLowTime;
        g_rangeStart    = rangeStart;
        g_rangeEnd      = rangeEnd;
        g_rangeReady    = true;
        g_precloseArmed = true;
        DrawRangeBox(g_sessionKey, g_rangeStart, g_rangeEnd, g_rangeHigh, g_rangeLow);
        ORBLog(StringFormat("[ORB] Pre-close range armed: Hi=%.5f Lo=%.5f secsToClose=%.2f",
                            g_rangeHigh, g_rangeLow, (double)(rangeEnd - now)));
        return;
    }

    double hi = -DBL_MAX, lo = DBL_MAX;
    datetime hiTime = rangeStart, loTime = rangeStart;

    if(g_rangeBuildReady && g_rangeBuildStart == rangeStart && g_rangeBuildEnd == rangeEnd)
    {
        hi = g_rangeBuildHigh;
        lo = g_rangeBuildLow;
        hiTime = g_rangeBuildHighTime;
        loTime = g_rangeBuildLowTime;
    }
    else
    {
        if(!LoadRangeWindow(rangeStart, rangeEnd, hi, lo, hiTime, loTime))
        {
            datetime fallbackStart = sessionOpen;
            datetime fallbackEnd = sessionOpen + ((int)Slot1_Range_Minutes * 60);
            if(now < fallbackEnd)
            {
                static string s_fallbackWaitLogKey[6] = {"", "", "", "", "", ""};
                int fwSlot = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
                if(s_fallbackWaitLogKey[fwSlot] != g_sessionKey)
                {
                    s_fallbackWaitLogKey[fwSlot] = g_sessionKey;
                    ORBLog(StringFormat("[ORB] Pre-open range unavailable for %s; waiting for post-open fallback range.",
                                        (g_ctxSlotIdx==2)?"Asian":(g_ctxSlotIdx==1)?"London":"NY"));
                }
                return;
            }
            if(!LoadRangeWindow(fallbackStart, fallbackEnd, hi, lo, hiTime, loTime))
            {
                static string s_rangeCopyFailLogKey[6] = {"", "", "", "", "", ""};
                int rcSlot = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
                if(s_rangeCopyFailLogKey[rcSlot] != g_sessionKey)
                {
                    s_rangeCopyFailLogKey[rcSlot] = g_sessionKey;
                    ORBLog(StringFormat("[ORB] Range copy failed: err=%d", GetLastError()));
                }
                return;
            }
            rangeStart = fallbackStart;
            rangeEnd = fallbackEnd;
        }
    }
    if(hi == -DBL_MAX || lo == DBL_MAX) return;

    g_rangeHigh     = NormalizeDouble(hi, _Digits);
    g_rangeLow      = NormalizeDouble(lo, _Digits);
    g_rangeHighTime = hiTime;
    g_rangeLowTime  = loTime;
    g_rangeStart    = rangeStart;
    g_rangeEnd      = rangeEnd;
    g_rangeReady    = true;
    

    ORBLog(StringFormat("[ORB] Range ready: Hi=%.5f Lo=%.5f Size=%.1f pts",
                g_rangeHigh, g_rangeLow, RawToPts(g_rangeHigh - g_rangeLow)));

    // BREACH-AT-COMPLETION (bug 1b): if price ALREADY traded through a level in
    // the gap between range-end and the moment the EA evaluated it (e.g. the
    // range completed at 04:15 but we only got here at 04:18 and price had
    // already swept the low), that side's setup is spent. Inspect the M1 bars
    // from range-end through the last CLOSED M1 candle; if a level was touched,
    // consume that side so PlaceOrders never arms an already-used breakout. Do
    // not inspect the still-forming current M1 candle here: at range close that
    // can punish a fast symbol before the EA has had a fair placement pulse.
    // Skipped under Instant Market Execution: that mode fires the instant a level
    // is genuinely touched and judges staleness by live price distance
    // (Instant_Max_Entry_Slippage_Points), not by whether the level was re-tagged
    // at some point since range close. Leaving this on would pre-consume sides
    // before ExecuteInstantSide ever ran on a perfectly good touch.
    if(!Use_Instant_Market_Execution)
    {
        datetime postEnd = (datetime)(((long)now / 60) * 60 - 1);
        if(rangeEnd <= postEnd)
        {
            MqlRates post[];
            ArraySetAsSeries(post, false);
            int pc = CopyRates(_Symbol, PERIOD_M1, rangeEnd, postEnd, post);
            for(int i = 0; i < pc; i++)
            {
                if(post[i].high >= g_rangeHigh && !SideConsumed(g_sessionKey, true))
                {
                    g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true);
                    ORBLog(StringFormat("[ORB] HIGH level %.5f already breached before eval (post-range high %.5f) - side consumed.", g_rangeHigh, post[i].high));
                }
                if(post[i].low <= g_rangeLow && !SideConsumed(g_sessionKey, false))
                {
                    g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false);
                    ORBLog(StringFormat("[ORB] LOW level %.5f already breached before eval (post-range low %.5f) - side consumed.", g_rangeLow, post[i].low));
                }
            }
        }
    }

    DrawRangeBox(g_sessionKey, g_rangeStart, g_rangeEnd, g_rangeHigh, g_rangeLow);
}

bool SideBreachedAfterGrace(bool highLevel, datetime now)
{
    if(g_rangeEnd <= 0) return false;
    if((now - g_rangeEnd) <= 60) return false;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(highLevel && ask >= g_rangeHigh) return true;
    if(!highLevel && bid <= g_rangeLow) return true;

    datetime postEnd = (datetime)(((long)now / 60) * 60 - 1);
    if(postEnd < g_rangeEnd) return false;

    MqlRates post[];
    ArraySetAsSeries(post, false);
    int copied = CopyRates(_Symbol, PERIOD_M1, g_rangeEnd, postEnd, post);
    if(copied <= 0) return false;

    for(int i = 0; i < copied; i++)
    {
        if(highLevel && post[i].high >= g_rangeHigh) return true;
        if(!highLevel && post[i].low <= g_rangeLow) return true;
    }
    return false;
}

void ConsumeIfBreachedAfterGrace(bool highLevel, datetime now)
{
    if(SideConsumed(g_sessionKey, highLevel)) return;
    if(!SideBreachedAfterGrace(highLevel, now)) return;

    if(highLevel) g_buyPlaced = true;
    else          g_sellPlaced = true;
    MarkSideConsumed(g_sessionKey, highLevel);
    ORBLog(StringFormat("[ORB] %s level already breached after grace window - side consumed.",
                        highLevel ? "HIGH" : "LOW"));
}

bool LivePendingExistsAtLevel(bool highLevel)
{
    double level = highLevel ? g_rangeHigh : g_rangeLow;
    double tol = MathMax(_Point * 2.0, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 2.0);
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!OwnsTicket(ticket)) continue;   // don't let another chart instance's order on the same symbol/level count as "already covered" here

        ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(ot != ORDER_TYPE_BUY_STOP && ot != ORDER_TYPE_SELL_STOP &&
           ot != ORDER_TYPE_BUY_LIMIT && ot != ORDER_TYPE_SELL_LIMIT &&
           ot != ORDER_TYPE_BUY_STOP_LIMIT && ot != ORDER_TYPE_SELL_STOP_LIMIT) continue;

        if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - level) <= tol)
        {
            ClaimTicket(ticket);
            RegisterOrderMetaSnapshot(ticket, g_ctxSlotIdx, g_sessionKey, highLevel,
                                      level,
                                      highLevel ? g_rangeHighTime : g_rangeLowTime,
                                      g_rangeStart, g_rangeEnd,
                                      EffectiveSlotCutoffServer(TimeCurrent()));
            return true;
        }
    }
    return false;
}

bool IsSymbolInLiveTradingSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)dt.day_of_week;

    datetime from, to;
    // Check all session slots the broker publishes for today
    for(int i = 0; i < 5; i++)
    {
        if(!SymbolInfoSessionTrade(_Symbol, dow, i, from, to)) break; // no more session slots today
        datetime todayStart = TimeCurrent() - (TimeCurrent() % 86400);
        datetime sessFrom = todayStart + from;
        datetime sessTo   = todayStart + to;
        if(TimeCurrent() >= sessFrom && TimeCurrent() < sessTo) return true;
    }
    return false;
}

bool IsQuoteGenuinelyLive()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(bid <= 0.0 || ask <= 0.0) return false;
    if(ask - bid < _Point) return false; // zero/negative spread = frozen or synthetic feed

    // Detect Exness heartbeat pattern: consecutive identical quotes despite ticks arriving
    static double s_lastBid = 0.0, s_lastAsk = 0.0;
    static int    s_staleCount = 0;
    if(bid == s_lastBid && ask == s_lastAsk) s_staleCount++;
    else { s_staleCount = 0; s_lastBid = bid; s_lastAsk = ask; }
    return s_staleCount < 20; // ~20 identical consecutive quotes strongly suggests a heartbeat feed
}

bool BrokerAllowsNewEntries()
{
    long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
    if(mode != SYMBOL_TRADE_MODE_FULL) return false;
    if(!IsSymbolInLiveTradingSession()) return false;
    return IsQuoteGenuinelyLive();
}

bool IsMarketClosedRetcode(uint rc)
{
    return rc == TRADE_RETCODE_MARKET_CLOSED
        || rc == TRADE_RETCODE_TRADE_DISABLED
        || rc == TRADE_RETCODE_PRICE_OFF
        || rc == 10031                    // TRADE_RETCODE_CONNECTION (replaces speculative NO_QUOTES)
        || rc == TRADE_RETCODE_REQUOTE;   // stale/frozen feed can surface as requote; watch logs for misfires
}


// New monitoring globals (- ORB_StopLimit_v2_Corrected_Geometry.md)
bool  g_slMonitorHigh    = false;  // BUY_STOP_LIMIT placed and being monitored post-placement
bool  g_slTrigDetHigh    = false;  // trigger: order type flipped STOP_LIMIT->LIMIT
uint  g_slTrig100MsHigh  = 0;      // GetTickCount() at trigger (100ms reference)
bool  g_sl100CheckedHigh = false;  // one-shot 100ms zone decision taken
bool  g_slWaitWatchHigh  = false;  // waiting in 25-50% zone
bool  g_slMonitorLow     = false;
bool  g_slTrigDetLow     = false;
uint  g_slTrig100MsLow   = 0;
bool  g_sl100CheckedLow  = false;
bool  g_slWaitWatchLow   = false;

// - Helper: find EA-owned BUY_STOP_LIMIT/BUY_LIMIT (high) or SELL_STOP_LIMIT/SELL_LIMIT (low) -
// NOTE (Gap-1): deliberately matches BOTH *_STOP_LIMIT (pre-trigger) and plain *_LIMIT
// (post-trigger, already converted by broker).  Gate B sweeps BOTH states - a resting
// BUY_LIMIT that is mid-wait-and-watch is "pending/unfilled" for re-arm purposes, exactly
// the same as one that never triggered.
ulong FindSLOrder(bool isHigh)
{
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(t == 0 || !OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)OrderGetInteger(ORDER_MAGIC))) continue;
        long ot = OrderGetInteger(ORDER_TYPE);
        if(isHigh && (ot==ORDER_TYPE_BUY_STOP_LIMIT  || ot==ORDER_TYPE_BUY_LIMIT))  return t;
        if(!isHigh&& (ot==ORDER_TYPE_SELL_STOP_LIMIT || ot==ORDER_TYPE_SELL_LIMIT)) return t;
    }
    return 0;
}

// - Post-trigger state machine for one side -
// - of ORB_StopLimit_v2_Corrected_Geometry.md
// isHigh=true - â€™ BUY side (stop=g_rangeHigh, forward direction is up)
// Returns true when monitoring for this side should stop.
bool StopLimitMonitorLogic(bool isHigh, double ask, double bid, double slRaw,
                           bool &active, bool &trigDet, uint &trig100Ms, bool &done100, bool &waitWatch)
{
    if(!active) return false;

    double stopPx  = isHigh ? g_rangeHigh : g_rangeLow;
    double tpDist  = TPRaw(); // original unpadded TP distance
    double pct10   = isHigh ? stopPx + 0.10*tpDist : stopPx - 0.10*tpDist;
    double pct25   = isHigh ? stopPx + 0.25*tpDist : stopPx - 0.25*tpDist;
    double pct50   = isHigh ? stopPx + 0.50*tpDist : stopPx - 0.50*tpDist;
    double priceFwd = isHigh ? ask : bid; // forward price: ask for buy, bid for sell

    ulong ticket = FindSLOrder(isHigh);
    long  otype  = (ticket > 0) ? (long)OrderGetInteger(ORDER_TYPE) : -1L;
    bool  isSL   = isHigh ? (otype==ORDER_TYPE_BUY_STOP_LIMIT)  : (otype==ORDER_TYPE_SELL_STOP_LIMIT);
    bool  isLim  = isHigh ? (otype==ORDER_TYPE_BUY_LIMIT)        : (otype==ORDER_TYPE_SELL_LIMIT);

    // - Continuous 50% check (runs from trigger detection onwards) -
    if(trigDet)
    {
        bool past50 = isHigh ? (priceFwd >= pct50) : (priceFwd <= pct50);
        if(past50)
        {
            if(ticket > 0) trade.OrderDelete(ticket);
            MarkSideConsumed(g_sessionKey, isHigh);
            ORBLog(StringFormat("[ORB] %s SL: 50%% consumed before fill (%.5f). Skipping trade.",
                                isHigh?"BUY":"SELL", priceFwd));
            active=false; trigDet=false; done100=false; waitWatch=false;
            return true;
        }
    }

    // - Detect trigger (STOP_LIMIT - â€™ LIMIT flip) -
    if(!trigDet)
    {
        if(isLim)
        {
            trigDet   = true;
            trig100Ms = GetTickCount();
            ORBLog(StringFormat("[ORB] %s stop-limit triggered at %.5f. 100ms clock started.",
                                isHigh?"BUY":"SELL", OrderGetDouble(ORDER_PRICE_OPEN)));
        }
        else if(!isSL)
        {
            // Order vanished - check for existing position (may have filled before we polled)
            bool posExists = false;
            for(int i = PositionsTotal()-1; i >= 0; i--)
            {
                ulong pt = PositionGetTicket(i);
                if(pt==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
                if(!MagicMatch((long)PositionGetInteger(POSITION_MAGIC))) continue;
                posExists = true; break;
            }
            if(!posExists)
            {
                // Silent failure - market-execute (no limit to cancel first)
                double eqSL = isHigh ? NormalizeDouble(stopPx - slRaw,_Digits) : NormalizeDouble(stopPx + slRaw,_Digits);
                double eqTP = isHigh ? NormalizeDouble(stopPx + TPRaw(),_Digits) : NormalizeDouble(stopPx - TPRaw(),_Digits);
                ORBLog(StringFormat("[ORB] %s SL: silent failure. Market-executing.", isHigh?"BUY":"SELL"));
                double lots = PlannedLegLots(slRaw, isHigh ? !Reverse_Orders : Reverse_Orders, stopPx, false);
                if(lots > 0)
                {
                    bool ok = isHigh ? trade.Buy(lots,_Symbol,0,eqSL,eqTP,BuildComment(true))
                                     : trade.Sell(lots,_Symbol,0,eqSL,eqTP,BuildComment(false));
                    if(ok) { ClaimAndRegisterLastOrder(isHigh); ORBNotifyEntry(isHigh, isHigh?ask:bid, eqSL, eqTP); }
                    else   ORBLog(StringFormat("[ORB] %s silent-fail market exec FAILED err=%d", isHigh?"BUY":"SELL", GetLastError()));
                }
            }
            active=false; trigDet=false; done100=false; waitWatch=false;
            return true;
        }
        return false; // still STOP_LIMIT, not yet triggered
    }

    // - Wait-and-watch: price in 25-50% zone, limit still resting -
    if(waitWatch)
    {
        bool retracedTo10 = isHigh ? (priceFwd <= pct10) : (priceFwd >= pct10);
        if(retracedTo10)
        {
            if(ticket == 0)
            {
                // Order gone, position should exist (filled during retracement)
                active=false; trigDet=false; done100=false; waitWatch=false;
                return true;
            }
            // Limit still alive - cancel-before-market (mandatory sequential)
            double curSL = OrderGetDouble(ORDER_SL);
            double curTP = OrderGetDouble(ORDER_TP);
            ORBLog(StringFormat("[ORB] %s SL: retraced to 10%% zone. Cancel limit, market-exec.", isHigh?"BUY":"SELL"));
            if(trade.OrderDelete(ticket))
            {
                double lots = PlannedLegLots(slRaw, isHigh ? !Reverse_Orders : Reverse_Orders, stopPx, false);
                if(lots > 0)
                {
                    bool ok = isHigh ? trade.Buy(lots,_Symbol,0,curSL,curTP,BuildComment(true))
                                     : trade.Sell(lots,_Symbol,0,curSL,curTP,BuildComment(false));
                    if(ok) { ClaimAndRegisterLastOrder(isHigh); ORBNotifyEntry(isHigh, isHigh?ask:bid, curSL, curTP); }
                    else   ORBLog(StringFormat("[ORB] %s retracement exec FAILED err=%d", isHigh?"BUY":"SELL", GetLastError()));
                }
            }
            else ORBLog(StringFormat("[ORB] %s retracement OrderDelete FAILED err=%d. Skipping market exec.", isHigh?"BUY":"SELL", GetLastError()));
            active=false; trigDet=false; done100=false; waitWatch=false;
            return true;
        }
        return false; // still watching
    }

    // - 100ms one-shot check -
    if(!done100)
    {
        if((GetTickCount() - trig100Ms) < 100) return false; // not yet 100ms
        done100 = true;

        bool past50 = isHigh ? (priceFwd >= pct50) : (priceFwd <= pct50);
        bool past25 = isHigh ? (priceFwd >= pct25) : (priceFwd <= pct25);

        if(past50)
        {
            if(ticket > 0) trade.OrderDelete(ticket);
            MarkSideConsumed(g_sessionKey, isHigh);
            ORBLog(StringFormat("[ORB] %s 100ms check: at/past 50%% (%.5f). Skipping.", isHigh?"BUY":"SELL", priceFwd));
            active=false; trigDet=false; done100=false; waitWatch=false;
            return true;
        }
        else if(past25)
        {
            waitWatch = true;
            ORBLog(StringFormat("[ORB] %s 100ms check: 25-50%% zone (%.5f). Wait-and-watch.", isHigh?"BUY":"SELL", priceFwd));
            return false;
        }
        else
        {
            // < 25%: cancel-before-market (mandatory sequential)
            ORBLog(StringFormat("[ORB] %s 100ms check: below 25%% (%.5f). Cancel limit, market-exec.", isHigh?"BUY":"SELL", priceFwd));
            if(ticket > 0)
            {
                double curSL = OrderGetDouble(ORDER_SL);
                double curTP = OrderGetDouble(ORDER_TP);
                if(trade.OrderDelete(ticket))
                {
                    double lots = PlannedLegLots(slRaw, isHigh ? !Reverse_Orders : Reverse_Orders, stopPx, false);
                    if(lots > 0)
                    {
                        bool ok = isHigh ? trade.Buy(lots,_Symbol,0,curSL,curTP,BuildComment(true))
                                         : trade.Sell(lots,_Symbol,0,curSL,curTP,BuildComment(false));
                        if(ok) { ClaimAndRegisterLastOrder(isHigh); ORBNotifyEntry(isHigh, isHigh?ask:bid, curSL, curTP); }
                        else   ORBLog(StringFormat("[ORB] %s 100ms exec FAILED err=%d", isHigh?"BUY":"SELL", GetLastError()));
                    }
                }
                else ORBLog(StringFormat("[ORB] %s 100ms OrderDelete FAILED err=%d. Skipping exec.", isHigh?"BUY":"SELL", GetLastError()));
            }
            active=false; trigDet=false; done100=false; waitWatch=false;
            return true;
        }
    }

    return false;
}

bool StopLimitMonitorSide(bool isHigh, double ask, double bid, double slRaw)
{
    if(isHigh) return StopLimitMonitorLogic(isHigh, ask, bid, slRaw, g_slMonitorHigh, g_slTrigDetHigh, g_slTrig100MsHigh, g_sl100CheckedHigh, g_slWaitWatchHigh);
    else       return StopLimitMonitorLogic(isHigh, ask, bid, slRaw, g_slMonitorLow, g_slTrigDetLow, g_slTrig100MsLow, g_sl100CheckedLow, g_slWaitWatchLow);
}

// - Reset all per-side state machine flags to a clean "never started" state -
// Must be called whenever Gate B cancels an order mid-monitoring (Gap-2).
void SLResetSideState(bool isHigh)
{
    if(isHigh) { g_slMonitorHigh=false; g_slTrigDetHigh=false; g_slTrig100MsHigh=0; g_sl100CheckedHigh=false; g_slWaitWatchHigh=false; }
    else       { g_slMonitorLow =false; g_slTrigDetLow =false; g_slTrig100MsLow =0; g_sl100CheckedLow =false; g_slWaitWatchLow =false; }
}

// - Gate B strict-mode sweep (called once per tick while IsNewsStrictMode is active) -
// Cancels ALL pending entry orders (including already-triggered BUY/SELL_LIMIT, Gap-1),
// flattens ALL open positions, resets state machine (Gap-2), and re-arms only sides that
// were cancelled while still unfilled (filled-then-flattened sides remain consumed).
static bool s_strictSweepDone = false;  // one-shot guard: sweep runs exactly once per activation
static bool s_strictRearmBuy  = false;  // high side was cancelled unfilled - â€™ re-arm when window clears
static bool s_strictRearmSell = false;  // low  side was cancelled unfilled - â€™ re-arm when window clears

void StopLimitGateBSweep(datetime now)
{
    if(s_strictSweepDone) return; // already swept this activation
    s_strictSweepDone = true;
    s_strictRearmBuy  = false;
    s_strictRearmSell = false;

    // --- Cancel all pending entry orders (pre-trigger AND post-trigger LIMIT) ---
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong t = OrderGetTicket(i);
        if(t == 0 || !OrderSelect(t)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)OrderGetInteger(ORDER_MAGIC))) continue;
        long ot = OrderGetInteger(ORDER_TYPE);
        bool isBuySide  = (ot==ORDER_TYPE_BUY_STOP_LIMIT  || ot==ORDER_TYPE_BUY_LIMIT);
        bool isSellSide = (ot==ORDER_TYPE_SELL_STOP_LIMIT || ot==ORDER_TYPE_SELL_LIMIT);
        if(!isBuySide && !isSellSide) continue;
        // Mark for re-arm BEFORE cancel: order exists and is unfilled
        if(isBuySide)  s_strictRearmBuy  = true;
        if(isSellSide) s_strictRearmSell = true;
        if(trade.OrderDelete(t))
            ORBLog(StringFormat("[ORB] Gate B sweep: cancelled %s order #%llu (news strict mode).",
                                isBuySide?"BUY":"SELL", t));
        else
            ORBLog(StringFormat("[ORB] Gate B sweep: cancel FAILED for order #%llu err=%d.", t, GetLastError()));
    }

    // --- Reset state machine for cancelled sides (Gap-2) ---
    if(s_strictRearmBuy)  SLResetSideState(true);
    if(s_strictRearmSell) SLResetSideState(false);

    // --- Flatten all open positions ---
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(t == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!MagicMatch((long)PositionGetInteger(POSITION_MAGIC))) continue;
        // Position closing = a completed attempt - â€™ do NOT re-arm.  Clear re-arm flags
        // for whichever side this position corresponds to.
        bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
        if(isLong)  s_strictRearmBuy  = false;   // filled-then-flattened stays consumed
        else        s_strictRearmSell = false;
        if(trade.PositionClose(t))
            ORBLog(StringFormat("[ORB] Gate B sweep: flattened %s position #%llu (news strict mode).",
                                isLong?"LONG":"SHORT", t));
        else
            ORBLog(StringFormat("[ORB] Gate B sweep: flatten FAILED for position #%llu err=%d.", t, GetLastError()));
    }
    ORBLog(StringFormat("[ORB] Gate B sweep complete. Re-arm BUY=%s SELL=%s.",
                        s_strictRearmBuy?"YES":"NO", s_strictRearmSell?"YES":"NO"));
}

// - Per-tick entry point: call inside slot loop after PlaceOrders -
void StopLimitMonitor(datetime now)
{
    if(!Use_StopLimit_Orders) return;

    // - Gate B (strict mode): all three news flags active for this event -
    // Precedence: Gate B wins over Gate A. Sweep runs once, re-arm fires after clear.
    if(IsNewsStrictMode(now))
    {
        StopLimitGateBSweep(now);
        return; // Gate B active - no further state machine evaluation
    }
    else if(s_strictSweepDone)
    {
        // Gate B just cleared - apply re-arm if flagged, then reset sweep guard
        if(s_strictRearmBuy  && !SideConsumed(g_sessionKey, true))
        {
            g_buyPlaced = false;
            g_slMonitorHigh = true;
            ORBLog("[ORB] Gate B cleared: re-arming BUY side.");
        }
        if(s_strictRearmSell && !SideConsumed(g_sessionKey, false))
        {
            g_sellPlaced = false;
            g_slMonitorLow = true;
            ORBLog("[ORB] Gate B cleared: re-arming SELL side.");
        }
        s_strictSweepDone = false;
        s_strictRearmBuy  = false;
        s_strictRearmSell = false;
    }

    // - Gate A (modification-restricted): freeze_trail or block_entries alone -
    // Resting orders can still fill naturally; EA must not touch them.
    if(IsNewsFreezingTrail(now) || IsNewsBlocked(now)) return;

    // - Normal evaluation -
    if(!g_slMonitorHigh && !g_slMonitorLow) return;

    double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slRaw = SLRaw();

    if(g_slMonitorHigh) StopLimitMonitorSide(true,  ask, bid, slRaw);
    if(g_slMonitorLow)  StopLimitMonitorSide(false, ask, bid, slRaw);
}

//+------------------------------------------------------------------+
//| INSTANT MARKET EXECUTION                                          |
//| Alternative to Buy/Sell Stop(-Limit) placement (Use_Instant_       |
//| Market_Execution = true). No resting order ever sits at the level; |
//| the EA watches ticks and fires a market order the instant the      |
//| level is confirmed touched.                                        |
//|                                                                     |
//| Confirmation deliberately uses the OPPOSITE side of the market     |
//| from the one that will fill the order:                             |
//|   - HIGH level -> confirmed by BID reaching it. A resting BuyStop  |
//|     fills once ASK reaches the level, which a spread spike alone   |
//|     can trigger with no genuine trade-through. Requiring BID to    |
//|     also be there proves the market actually traded through.      |
//|   - LOW level  -> confirmed by ASK reaching it, mirror logic.      |
//|                                                                     |
//| Before sending, the prospective fill price (ASK for a buy, BID for |
//| a sell) is compared against the range level. If that gap already   |
//| exceeds Instant_Max_Entry_Slippage_Points the entry is SKIPPED     |
//| outright - never chased at a worse price. This is the core         |
//| difference vs. a stop order, which fills unconditionally and can   |
//| only be "fixed up" (SL/TP recentred) after the damage is done.     |
//| SL/TP here are computed off the real fill price at send time, so   |
//| there is nothing to recentre afterwards.                           |
//+------------------------------------------------------------------+
static string s_instFailKey[6]       = {"", "", "", "", "", ""};
static int    s_instFailCountHigh[6] = {0, 0, 0, 0, 0, 0};
static int    s_instFailCountLow[6]  = {0, 0, 0, 0, 0, 0};

void ResetInstantFailCountersIfNewSession()
{
    int slotIdx = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
    if(s_instFailKey[slotIdx] != g_sessionKey)
    {
        s_instFailKey[slotIdx]       = g_sessionKey;
        s_instFailCountHigh[slotIdx] = 0;
        s_instFailCountLow[slotIdx]  = 0;
    }
}

// isHigh = true  -> HIGH side of the range (BID confirms touch)
// isHigh = false -> LOW  side of the range (ASK confirms touch)
//
// A range side is either touched while this EA instance is active and watching
// it (a live touch - subject to the slippage gate, fire or skip on gap size),
// or it was touched while the EA was not yet initialized/running (stale - the
// side is simply dead, no gap evaluation, no execution attempt, period). The
// slippage gate exists to judge *how* to react to a live touch, not to decide
// *whether* a touch counts - those are separate questions.
//
// Tick feeds (especially in the tester, and in the pre-open minutes before a
// symbol is fully tradeable) can also jump straight past a level between two
// ticks while the EA IS active, without any single tick ever satisfying the
// live BID/ASK check. Bar history is used to catch that too, classified as
// live (not stale) since the EA was watching the whole time - it just missed
// the exact tick.
enum ENUM_LEVEL_CROSS { CROSS_NONE, CROSS_STALE, CROSS_LIVE };

ENUM_LEVEL_CROSS ClassifyLevelCrossing(bool isHigh, double levelPx, datetime &crossTime)
{
    crossTime = 0;
    if(g_rangeEnd <= 0) return CROSS_NONE;
    datetime scanEnd = TimeCurrent();
    if(scanEnd <= g_rangeEnd) return CROSS_NONE;

    // The level has been "live" since g_rangeEnd. This instance has only been
    // watching since g_eaActiveSince. Whichever is later is where the EA's
    // real-time coverage of this level begins.
    datetime activeSince = (g_eaActiveSince > g_rangeEnd) ? g_eaActiveSince : g_rangeEnd;

    // Per (slot, side) incremental scan cache. Without this, every tick that
    // the live BID/ASK check misses re-fetches and re-scans the ENTIRE
    // [g_rangeEnd, now] window from scratch - for a Daily/Weekly/Monthly range
    // sitting untouched for hours or days, that's thousands of bars re-read on
    // every single tick, which is what made the tester crawl. Instead: do the
    // (typically empty/tiny, since g_eaActiveSince usually predates
    // g_rangeEnd in a continuously-running instance) pre-active staleness
    // check exactly once per session, then only scan what's happened since
    // the last call from here on - normally 0-1 bars.
    int slotIdx = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
    static string   s_sessH[6] = {"", "", "", "", "", ""};
    static string   s_sessL[6] = {"", "", "", "", "", ""};
    static datetime s_curH[6]  = {0, 0, 0, 0, 0, 0};
    static datetime s_curL[6]  = {0, 0, 0, 0, 0, 0};
    static bool     s_staleDoneH[6] = {false, false, false, false, false, false};
    static bool     s_staleDoneL[6] = {false, false, false, false, false, false};

    string  curSess    = isHigh ? s_sessH[slotIdx]     : s_sessL[slotIdx];
    bool    staleDone   = isHigh ? s_staleDoneH[slotIdx] : s_staleDoneL[slotIdx];

    if(curSess != g_sessionKey)
    {
        // Fresh session for this slot/side: reset the incremental cursor and
        // re-arm the one-time pre-active staleness check.
        if(isHigh) { s_sessH[slotIdx] = g_sessionKey; s_curH[slotIdx] = g_rangeEnd; s_staleDoneH[slotIdx] = false; }
        else       { s_sessL[slotIdx] = g_sessionKey; s_curL[slotIdx] = g_rangeEnd; s_staleDoneL[slotIdx] = false; }
        staleDone = false;
    }

    if(!staleDone)
    {
        if(isHigh) s_staleDoneH[slotIdx] = true; else s_staleDoneL[slotIdx] = true;
        if(activeSince > g_rangeEnd)
        {
            MqlRates preRates[];
            ArraySetAsSeries(preRates, false);
            int preN = CopyRates(_Symbol, PERIOD_M1, g_rangeEnd, activeSince, preRates);
            for(int i = 0; i < preN; i++)
            {
                bool crossed = isHigh ? (preRates[i].high >= levelPx) : (preRates[i].low <= levelPx);
                if(crossed) return CROSS_STALE;
            }
        }
        if(isHigh) s_curH[slotIdx] = activeSince; else s_curL[slotIdx] = activeSince;
    }

    // Incremental scan: only what's happened since the last call.
    datetime scanFrom = isHigh ? s_curH[slotIdx] : s_curL[slotIdx];
    if(scanFrom < activeSince) scanFrom = activeSince;
    if(scanEnd <= scanFrom) return CROSS_NONE;

    MqlRates rates[];
    ArraySetAsSeries(rates, false);
    int n = CopyRates(_Symbol, PERIOD_M1, scanFrom, scanEnd, rates);
    // Advance the cursor regardless of hits, so this span is never rescanned.
    if(isHigh) s_curH[slotIdx] = scanEnd; else s_curL[slotIdx] = scanEnd;
    if(n <= 0) return CROSS_NONE;

    for(int i = 0; i < n; i++)
    {
        // Bars are bid-based; using bid-side high/low as the crossing proxy is
        // slightly looser than the live ask-confirms-low / bid-confirms-high
        // rule, but that's fine here - this only classifies WHEN the level was
        // first crossed, the live gate (using real Ask/Bid) still decides
        // whether to actually take a CROSS_LIVE touch. Everything in this
        // window is >= activeSince by construction, so any hit here is live.
        bool crossedThisBar = isHigh ? (rates[i].high >= levelPx) : (rates[i].low <= levelPx);
        if(crossedThisBar) { crossTime = rates[i].time; return CROSS_LIVE; }
    }
    return CROSS_NONE;
}

void ExecuteInstantSide(bool isHigh, double slRaw)
{
    double levelPx   = isHigh ? g_rangeHigh : g_rangeLow;
    double confirmPx = isHigh ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    bool   touched    = isHigh ? (confirmPx >= levelPx) : (confirmPx <= levelPx);
    bool   viaBarScan = false;
    datetime trueCrossTime = TimeCurrent();   // default: a live tick touch happens right now, this IS accurate

    if(touched)
    {
        // Live tick, right now, this instance is obviously active - proceed
        // straight to the slippage gate below.
    }
    else
    {
        datetime scanCrossTime = 0;
        ENUM_LEVEL_CROSS cs = ClassifyLevelCrossing(isHigh, levelPx, scanCrossTime);
        if(cs == CROSS_NONE) return;   // genuinely not touched yet - keep waiting

        if(cs == CROSS_STALE)
        {
            // Touched before this instance was watching - dead, full stop.
            // No gap/slippage evaluation: staleness isn't a distance question.
            ORBLog(StringFormat("[ORB] Instant exec %s level STALE: already breached before this instance was active/initialized (level=%.5f) - side consumed, no execution attempted.",
                                isHigh?"HIGH":"LOW", levelPx));
            if(isHigh) g_buyPlaced = true; else g_sellPlaced = true;
            MarkSideConsumed(g_sessionKey, isHigh);
            return;
        }

        // CROSS_LIVE: touched while this instance was actively watching, the
        // tick feed just didn't land exactly on it - the ORDER still has to
        // fire now (you can't send a market order into the past), but the
        // visual should be anchored at the real M1 bar where price actually
        // crossed, not at "now" - otherwise it misleadingly looks like the
        // breakout just happened at the chart's right edge.
        if(scanCrossTime > 0) trueCrossTime = scanCrossTime;
        touched    = true;
        viaBarScan = true;
    }

    bool   isBuy = isHigh ? !Reverse_Orders : Reverse_Orders;
    double fillPx = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // - Pre-trade slippage guard: skip outright, never chase. -
    double slipPts = MathAbs(fillPx - levelPx) / NormPoint();
    if(Instant_Max_Entry_Slippage_Points > 0 && slipPts > Instant_Max_Entry_Slippage_Points)
    {
        ORBLog(StringFormat("[ORB] Instant exec %s SKIPPED%s: entry slippage %.1f pts > Instant_Max_Entry_Slippage_Points=%.1f (level=%.5f fill~%.5f, confirm=%s %.5f).",
                            isHigh?"HIGH":"LOW", viaBarScan?" (crossing found via bar history, tick feed had gapped past it)":"", slipPts, Instant_Max_Entry_Slippage_Points, levelPx, fillPx, isHigh?"BID":"ASK", confirmPx));
        if(isHigh) g_buyPlaced = true; else g_sellPlaced = true;
        MarkSideConsumed(g_sessionKey, isHigh);
        return;
    }

    double lots = PlannedLegLots(slRaw, isBuy, levelPx, false);
    if(lots <= 0.0)
    {
        ORBLog(StringFormat("[ORB] Instant exec %s level skipped: no lot room (per-market cap or free margin exhausted).", isHigh?"HIGH":"LOW"));
        if(isHigh) g_buyPlaced = true; else g_sellPlaced = true;
        MarkSideConsumed(g_sessionKey, isHigh);
        return;
    }

    double tpDist = Use_TP_Slippage_Pad ? TPRaw() * (1.0 + TP_Slippage_Pad_Pct / 100.0) : TPRaw();
    double sl = isBuy ? NormalizeDouble(fillPx - slRaw,  _Digits) : NormalizeDouble(fillPx + slRaw,  _Digits);
    double tp = isBuy ? NormalizeDouble(fillPx + tpDist, _Digits) : NormalizeDouble(fillPx - tpDist, _Digits);

    if(isHigh) { g_buySendPending  = true; g_buySendTime  = TimeCurrent(); }
    else       { g_sellSendPending = true; g_sellSendTime = TimeCurrent(); }

    trade.SetDeviationInPoints(30); // Fixed, non-user-facing: ignored entirely by Market Execution mode brokers (FTMO/FundingPips-style), only matters for Instant/Exchange execution mode symbols
    bool sent = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, BuildComment(true))
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, BuildComment(false));

    if(sent && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL))
    {
        if(isHigh) g_buyPlaced = true; else g_sellPlaced = true;
        MarkSideConsumed(g_sessionKey, isHigh);
        ClaimAndRegisterLastOrder(isHigh, trueCrossTime);

        // Authoritative fill price from deal record (ResultPrice() can be 0 on some brokers)
        double actualFillPx = trade.ResultPrice();
        ulong  dealTicket   = trade.ResultDeal();
        if(actualFillPx <= 0.0 && dealTicket > 0 && HistoryDealSelect(dealTicket))
            actualFillPx = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
        if(actualFillPx <= 0.0) actualFillPx = fillPx;

        // ── POST-FILL OVERSLIP → SLIP FORCE-CLOSE ──
        // The pre-send gate checked the QUOTE; the broker can fill hundreds of
        // ms later far past it (observed XAUUSD: level 4023.66, fill 4026.18).
        // A hard market close here would often realize the spread+slip as an
        // instant loss, so instead: recenter SL/TP on the fill (done below),
        // disable trailing, and arm the slip force-close manager — the trade
        // exits at market the moment profit reaches +Slip_ForceClose_Profit_Points,
        // and NEVER at a loss (the recentred SL remains the disaster stop).
        double actualSlipPts = MathAbs(actualFillPx - levelPx) / NormPoint();
        if(Instant_Overslip_ForceClose && Instant_Max_Entry_Slippage_Points > 0 &&
           actualSlipPts > Instant_Max_Entry_Slippage_Points)
        {
            ulong osTicket = trade.ResultOrder();
            if(osTicket > 0)
            {
                // Persistent arm flag: RegisterVT picks it up whether the trade
                // is registered this tick or after a relaunch.
                GlobalVariableSet(StringFormat("ORB_SLIPARM_%I64u", osTicket), 1.0);
                int vtOS = GetVTIdx(osTicket);
                if(vtOS >= 0) vTrades[vtOS].slipForceCloseArmed = true;
                ORBLog(StringFormat("[ORB] Instant Market %s OVERSLIP: broker fill %.5f is %.1f pts past level %.5f (max %.1f). Trailing disabled; slip force-close armed (+%.1f pts, never at a loss).",
                                    isBuy?"BUY":"SELL", actualFillPx, actualSlipPts, levelPx,
                                    Instant_Max_Entry_Slippage_Points, Slip_ForceClose_Profit_Points));
            }
        }

        // CRITICAL: Recenter SL/TP from ACTUAL fill price.
        // The SL/TP sent with the order were from the pre-send bid/ask.
        // Broker fills 100-1000ms later at a different price. Fix it NOW.
        if(MathAbs(actualFillPx - fillPx) > _Point)
        {
            sl = isBuy ? NormalizeDouble(actualFillPx - slRaw,  _Digits)
                       : NormalizeDouble(actualFillPx + slRaw,  _Digits);
            tp = isBuy ? NormalizeDouble(actualFillPx + tpDist, _Digits)
                       : NormalizeDouble(actualFillPx - tpDist, _Digits);
            ulong posTicket = trade.ResultOrder();
            if(posTicket > 0)
            {
                trade.SetAsyncMode(false);
                // "No changes" (the SL/TP we sent with the order already match
                // the fill-centred targets) is SUCCESS, not failure — check
                // before modifying so err 4756 noise never appears.
                bool alreadyCentred = posInfo.SelectByTicket(posTicket) &&
                                      MathAbs(posInfo.StopLoss() - sl) < _Point &&
                                      MathAbs(posInfo.TakeProfit() - tp) < _Point;
                if(alreadyCentred || trade.PositionModify(posTicket, sl, tp))
                {
                    int vtIdx = GetVTIdx(posTicket);
                    if(vtIdx >= 0) { vTrades[vtIdx].vSL = sl; vTrades[vtIdx].vTP = tp; }
                    if(!alreadyCentred)
                        ORBLog(StringFormat("[ORB] Instant Market %s: fill %.5f vs quote %.5f - stops recentred SL=%.5f TP=%.5f",
                                            isBuy?"BUY":"SELL", actualFillPx, fillPx, sl, tp));
                }
                else
                {
                    ORBLog(StringFormat("[ORB] Instant Market %s: stop recenter FAILED err=%d (NormalizeStopsToFill retries next tick)",
                                        isBuy?"BUY":"SELL", GetLastError()));
                }
                trade.SetAsyncMode(true);
            }
        }

        ORBNotifyEntry(isBuy, actualFillPx, sl, tp);
        ORBLog(StringFormat("[ORB] Instant Market %s filled @ %.5f | lots=%.2f | SL=%.5f | TP=%.5f | confirm=%s %.5f -> level %.5f%s",
                            isBuy?"BUY":"SELL", actualFillPx, lots, sl, tp, isHigh?"BID":"ASK", confirmPx, levelPx, viaBarScan?" | via bar-scan fallback":""));
    }
    else
    {
        if(isHigh) g_buySendPending = false; else g_sellSendPending = false;
        uint rc = trade.ResultRetcode();
        if(IsMarketClosedRetcode(rc))
        {
            if(isHigh) { g_mktClosedPendingHigh = true; g_mktClosedLastAskHigh = fillPx; g_mktClosedLastCheckHigh = TimeCurrent(); }
            else       { g_mktClosedPendingLow  = true; g_mktClosedLastBidLow  = fillPx; g_mktClosedLastCheckLow  = TimeCurrent(); }
            ORBLog(StringFormat("[ORB] Instant exec %s rejected: market closed (rc=%u). Watching for price change to retry.", isHigh?"HIGH":"LOW", rc));
        }
        else
        {
            ResetInstantFailCountersIfNewSession();
            int fcSlot = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
            if(isHigh) s_instFailCountHigh[fcSlot]++; else s_instFailCountLow[fcSlot]++;
            int fc = isHigh ? s_instFailCountHigh[fcSlot] : s_instFailCountLow[fcSlot];
            ORBLog(StringFormat("[ORB] Instant exec %s FAILED err=%d rc=%u (attempt %d/3)", isHigh?"HIGH":"LOW", GetLastError(), rc, fc));
            if(fc >= 3)
            {
                if(isHigh) g_buyPlaced = true; else g_sellPlaced = true;
                MarkSideConsumed(g_sessionKey, isHigh);
                ORBLog(StringFormat("[ORB] Instant exec: max %s retries reached. Skipping.", isHigh?"HIGH":"LOW"));
            }
        }
    }
}

// Per-tick entry point for Instant Market Execution mode. Called from
// PlaceOrders() in place of the pending-order block when the toggle is on.
void PlaceInstantMarketOrders(bool allowHighLevel, bool allowLowLevel, double slRaw,
                              bool mktClosedBlockHigh, bool mktClosedBlockLow)
{
    ResetInstantFailCountersIfNewSession();

    // One slot per index - a single shared static here would have slot 0 and
    // slot 1 stomp on each other's "already logged" key every tick, since this
    // function is called once per slot per tick, re-triggering the log forever.
    static string s_armedKey[6] = {"", "", "", "", "", ""};
    int slotIdx = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
    if(s_armedKey[slotIdx] != g_sessionKey)
    {
        s_armedKey[slotIdx] = g_sessionKey;
        ORBLog(StringFormat("[ORB] Instant exec ARMED (slot %d): watching HIGH=%.5f (BID>=level -> BUY%s) / LOW=%.5f (ASK<=level -> SELL%s) | bid=%.5f ask=%.5f | Instant_Max_Entry_Slippage_Points=%.1f",
                            g_ctxSlotIdx, g_rangeHigh, Reverse_Orders?" reversed to SELL":"", g_rangeLow, Reverse_Orders?" reversed to BUY":"",
                            SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_ASK), Instant_Max_Entry_Slippage_Points));
    }

    if(allowHighLevel && !g_buyPlaced && !g_buySendPending && !SideConsumed(g_sessionKey, true) && !mktClosedBlockHigh)
        ExecuteInstantSide(true, slRaw);

    if(allowLowLevel && !g_sellPlaced && !g_sellSendPending && !SideConsumed(g_sessionKey, false) && !mktClosedBlockLow)
        ExecuteInstantSide(false, slRaw);
}

//+------------------------------------------------------------------+
//| Place BuyStop / SellStop orders at range extremes                |
//+------------------------------------------------------------------+
void PlaceOrders(datetime now, datetime cutoff)
{
    if(Use_OCO && HasCurrentRangeTrade())
    {
        // One trade triggered already, prevent further placements
        g_buyPlaced = true;
        g_sellPlaced = true;
        return;
    }

    // Volatility gate: range must meet minimum ATR threshold before orders are placed.
    if(Use_Vol_Filter && atrHandle != INVALID_HANDLE)
    {
        double atr[1];
        if(CopyBuffer(atrHandle, 0, 1, 1, atr) > 0)
        {
            double rangeSize = g_rangeHigh - g_rangeLow;
            if(rangeSize < atr[0] * Vol_Atr_Multiplier)
            {
                ORBLog(StringFormat("[ORB] Vol filter: range %.5f < ATR*mult %.5f - skip.", rangeSize, atr[0] * Vol_Atr_Multiplier));
                g_buyPlaced = true;
                g_sellPlaced = true;
                return;
            }
        }
    }

    bool allowLong  = true;
    bool allowShort = true;

    if(Use_Trend_Filter)
    {
        if(emaHandle != INVALID_HANDLE)
        {
            double ema[1];
            if(CopyBuffer(emaHandle, 0, 1, 1, ema) > 0)
            {
                double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                if(px > ema[0]) allowShort = false;
                if(px < ema[0]) allowLong  = false;
            }
        }
    }

    double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slRaw = SLRaw(); // STRICT Stop Loss to protect against modification bans during news
    double tpRaw = Use_TP_Slippage_Pad ? TPRaw() * (1.0 + TP_Slippage_Pad_Pct / 100.0) : TPRaw(); // Safety net Take Profit to prevent instant gap-closures
    bool allowHighLevel = Reverse_Orders ? allowShort : allowLong;
    bool allowLowLevel  = Reverse_Orders ? allowLong  : allowShort;
    double spreadPad = 0.0;
    if(Spread_Padding == SPREAD_PAD_BOTH || (Spread_Padding == SPREAD_PAD_SLOT0 && g_ctxSlotIdx == 0) || (Spread_Padding == SPREAD_PAD_SLOT1 && g_ctxSlotIdx == 1))
        spreadPad = ask - bid;

    // NOTE: this 60s wall-clock "already breached, abandon it" gate exists for the
    // pending-order model, where a stale unfilled Stop genuinely should be dropped.
    // Instant Market Execution judges staleness by actual price distance instead
    // (Instant_Max_Entry_Slippage_Points, evaluated per-tick in ExecuteInstantSide),
    // so this timer-based gate is skipped entirely in that mode - otherwise it can
    // consume a side before instant execution ever gets to fire on a genuine touch.
    if(!Use_Instant_Market_Execution)
    {
        ConsumeIfBreachedAfterGrace(true, now);
        ConsumeIfBreachedAfterGrace(false, now);
    }

    if(!BrokerAllowsNewEntries())
    {
        // Rate-limit to once per 60 s per slot. A session-key guard alone
        // can re-fire on every key transition (e.g. weekend->Monday rollover),
        // so a timestamp cooldown is more robust.
        static datetime s_brokerPauseLast[6] = {0, 0, 0, 0, 0, 0};
        int bpSlot = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
        if(TimeCurrent() - s_brokerPauseLast[bpSlot] >= 60)
        {
            s_brokerPauseLast[bpSlot] = TimeCurrent();
            ORBLog("[ORB] Entry placement paused: market closed or broker not accepting entries.");
        }
        return;
    }

    if(!g_buyPlaced && LivePendingExistsAtLevel(true))
    {
        g_buyPlaced = true;
        g_buySendPending = false;
    }
    if(!g_sellPlaced && LivePendingExistsAtLevel(false))
    {
        g_sellPlaced = true;
        g_sellSendPending = false;
    }

    bool highCanPlace = (allowHighLevel && !g_buyPlaced && !g_buySendPending &&
                         !SideConsumed(g_sessionKey, true) &&
                         (ask < g_rangeHigh || (now - g_rangeEnd) <= 60));
    bool lowCanPlace  = (allowLowLevel && !g_sellPlaced && !g_sellSendPending &&
                         !SideConsumed(g_sessionKey, false) &&
                         (bid > g_rangeLow || (now - g_rangeEnd) <= 60));
    double lotsHigh = 0.0;
    double lotsLow = 0.0;
    // ExecuteInstantSide sizes its own leg via PlannedLegLots() when it actually
    // fires; this pair-sizing pass is only consumed by the pending-order block
    // below, so skip it (and the per-tick CalcLots/margin log spam it produces)
    // when Instant Market Execution owns the tick.
    if(!Use_Instant_Market_Execution)
        PlanRangeLots(slRaw, highCanPlace, lowCanPlace, lotsHigh, lotsLow);

    static string s_failKey[6] = {"", "", "", "", "", ""};
    static int s_failCountHigh[6] = {0, 0, 0, 0, 0, 0};
    static int s_failCountLow[6] = {0, 0, 0, 0, 0, 0};
    int fcSlotStop = (g_ctxSlotIdx >= 0 && g_ctxSlotIdx < 6) ? g_ctxSlotIdx : 0;
    if(s_failKey[fcSlotStop] != g_sessionKey)
    {
        s_failKey[fcSlotStop] = g_sessionKey;
        s_failCountHigh[fcSlotStop] = 0;
        s_failCountLow[fcSlotStop] = 0;
        // Clear market-closed watch state on new session
        g_mktClosedPendingHigh   = false;
        g_mktClosedPendingLow    = false;
        g_mktClosedLastAskHigh   = 0.0;
        g_mktClosedLastBidLow    = 0.0;
        g_mktClosedLastCheckHigh = 0;
        g_mktClosedLastCheckLow  = 0;
    }
    trade.SetAsyncMode(false);

    // - Market-closed tick-watch guard -
    bool mktClosedBlockHigh = false;
    bool mktClosedBlockLow  = false;
    if(g_mktClosedPendingHigh)
    {
        double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        bool priceChanged = MathAbs(currentAsk - g_mktClosedLastAskHigh) > _Point;
        datetime elapsed = TimeCurrent() - g_mktClosedLastCheckHigh;
        if(!priceChanged && elapsed < 300)
            mktClosedBlockHigh = true;
        else
        { ORBLog("[ORB] 5m backoff or price change elapsed for Market Closed - retrying HIGH order."); g_mktClosedPendingHigh = false; mktClosedBlockHigh = false; }
    }
    if(g_mktClosedPendingLow)
    {
        double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        bool priceChanged = MathAbs(currentBid - g_mktClosedLastBidLow) > _Point;
        datetime elapsed = TimeCurrent() - g_mktClosedLastCheckLow;
        if(!priceChanged && elapsed < 300)
            mktClosedBlockLow = true;
        else
        { ORBLog("[ORB] 5m backoff or price change elapsed for Market Closed - retrying LOW order."); g_mktClosedPendingLow = false; mktClosedBlockLow = false; }
    }

    if(Use_Instant_Market_Execution)
    {
        PlaceInstantMarketOrders(allowHighLevel, allowLowLevel, slRaw, mktClosedBlockHigh, mktClosedBlockLow);
        trade.SetAsyncMode(true);
        return;
    }

    if(allowHighLevel && !g_buyPlaced && !g_buySendPending && !SideConsumed(g_sessionKey, true) && !mktClosedBlockHigh)
    {
        if(!highCanPlace && ask >= g_rangeHigh && (now - g_rangeEnd) > 60)
        { ORBLog(StringFormat("[ORB] HIGH level already breached and >1 min elapsed (ask %.5f >= high %.5f) - skipping order.", ask, g_rangeHigh)); g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true); }
        else if(lotsHigh <= 0.0)
        { ORBLog("[ORB] HIGH level skipped: no lot room (per-market cap or free margin exhausted)."); g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true); }
        else if(ask < g_rangeHigh)
        {
            if(Reverse_Orders)
            {
                double bSL = NormalizeDouble(g_rangeHigh + slRaw, _Digits);
                double bTP = NormalizeDouble(g_rangeHigh - tpRaw, _Digits);
                g_buySendPending = true; g_buySendTime = TimeCurrent();
                if(trade.SellLimit(lotsHigh, g_rangeHigh, _Symbol, bSL, bTP, ORDER_TIME_GTC, 0, BuildComment(false)))
                { ORBLog(StringFormat("[ORB] SellLimit placed @ %.5f | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeHigh, lotsHigh, bSL, bTP)); g_buyPlaced = true; ClaimAndRegisterLastOrder(true); ORBNotifyEntry(false, g_rangeHigh, bSL, bTP); }
                else
                { g_buySendPending = false; uint _rcHigh = trade.ResultRetcode(); if(IsMarketClosedRetcode(_rcHigh)) { g_mktClosedPendingHigh = true; g_mktClosedLastAskHigh = ask; g_mktClosedLastCheckHigh = TimeCurrent(); ORBLog(StringFormat("[ORB] SellLimit rejected: market closed (rc=%u). Watching for price change to retry.", _rcHigh)); } else { s_failCountHigh[fcSlotStop]++; ORBLog(StringFormat("[ORB] SellLimit FAILED err=%d (attempt %d/3)", GetLastError(), s_failCountHigh[fcSlotStop])); if(s_failCountHigh[fcSlotStop] >= 3) { g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true); ORBLog("[ORB] Max high-level retries reached. Skipping."); } } }
            }
            else
            {
                double bSL = NormalizeDouble(g_rangeHigh - slRaw, _Digits);
                double bTP = NormalizeDouble(g_rangeHigh + tpRaw, _Digits);
                g_buySendPending = true; g_buySendTime = TimeCurrent();
                bool sentB = false;
                if(Use_StopLimit_Orders)
                { bool sentB = trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP_LIMIT, lotsHigh, g_rangeHigh, g_rangeHigh, bSL, bTP, ORDER_TIME_GTC, 0, BuildComment(true)); if(sentB) ORBLog(StringFormat("[ORB] BuyStopLimit placed @ stop=limit=%.5f | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeHigh, lotsHigh, bSL, bTP)); }
                else
                { bool sentB = trade.BuyStop(lotsHigh, g_rangeHigh, _Symbol, bSL, bTP, ORDER_TIME_GTC, 0, BuildComment(true)); if(sentB) ORBLog(StringFormat("[ORB] BuyStop placed @ %.5f | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeHigh, lotsHigh, bSL, bTP)); }
                
                if(trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED)
                { g_buyPlaced = true; if(Use_StopLimit_Orders) { g_slMonitorHigh = true; g_slTrigDetHigh = false; g_sl100CheckedHigh = false; g_slWaitWatchHigh = false; } ClaimAndRegisterLastOrder(true); ORBNotifyEntry(true, g_rangeHigh, bSL, bTP); }
                else
                { g_buySendPending = false; uint _rcHighB = trade.ResultRetcode(); if(IsMarketClosedRetcode(_rcHighB)) { g_mktClosedPendingHigh = true; g_mktClosedLastAskHigh = ask; g_mktClosedLastCheckHigh = TimeCurrent(); ORBLog(StringFormat("[ORB] Buy%s rejected: market closed (rc=%u). Watching for price change to retry.", Use_StopLimit_Orders?"StopLimit":"Stop", _rcHighB)); } else { s_failCountHigh[fcSlotStop]++; ORBLog(StringFormat("[ORB] Buy%s FAILED err=%d (attempt %d/3)", Use_StopLimit_Orders?"StopLimit":"Stop", GetLastError(), s_failCountHigh[fcSlotStop])); if(s_failCountHigh[fcSlotStop] >= 3) { g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true); ORBLog("[ORB] Max high-level retries reached. Skipping."); } } }
            }
        }
        else // ask >= g_rangeHigh
        {
            if((TimeCurrent() - g_rangeEnd) <= 60)
            {
                double bSL = NormalizeDouble(g_rangeHigh - slRaw, _Digits);
                double bTP = NormalizeDouble(g_rangeHigh + tpRaw, _Digits);
                g_buySendPending = true; g_buySendTime = TimeCurrent();
                if(trade.BuyLimit(lotsHigh, g_rangeHigh, _Symbol, bSL, bTP, ORDER_TIME_GTC, 0, BuildComment(true)))
                { ORBLog(StringFormat("[ORB] 1-Min Fallback BuyLimit placed @ %.5f after spike | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeHigh, lotsHigh, bSL, bTP)); g_buyPlaced = true; ClaimAndRegisterLastOrder(true); ORBNotifyEntry(true, g_rangeHigh, bSL, bTP); }
                else
                { if(trade.BuyStop(lotsHigh, g_rangeHigh, _Symbol, bSL, bTP, ORDER_TIME_GTC, 0, BuildComment(true))) { ORBLog(StringFormat("[ORB] 1-Min Fallback BuyStop placed @ %.5f after Limit failed | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeHigh, lotsHigh, bSL, bTP)); g_buyPlaced = true; ClaimAndRegisterLastOrder(true); ORBNotifyEntry(true, g_rangeHigh, bSL, bTP); } else { g_buySendPending = false; uint _rcHighF = trade.ResultRetcode(); if(IsMarketClosedRetcode(_rcHighF)) { g_mktClosedPendingHigh = true; g_mktClosedLastAskHigh = ask; g_mktClosedLastCheckHigh = TimeCurrent(); ORBLog(StringFormat("[ORB] 1-Min Fallback (BuyLimit/BuyStop) rejected: market closed (rc=%u). Watching for price change to retry.", _rcHighF)); } else { s_failCountHigh[fcSlotStop]++; ORBLog(StringFormat("[ORB] 1-Min Fallback Orders FAILED err=%d (attempt %d/3)", GetLastError(), s_failCountHigh[fcSlotStop])); if(s_failCountHigh[fcSlotStop] >= 3) { g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true); } } } }
            }
            else
            { ORBLog(StringFormat("[ORB] HIGH level already breached and >1 min elapsed (ask %.5f >= high %.5f) - skipping order.", ask, g_rangeHigh)); g_buyPlaced = true; MarkSideConsumed(g_sessionKey, true); }
        }
    }

    // Low-level order: SellStop in breakout mode, BuyLimit in reverse mode.
    if(allowLowLevel && !g_sellPlaced && !g_sellSendPending && !SideConsumed(g_sessionKey, false) && !mktClosedBlockLow)
    {
        if(!lowCanPlace && bid <= g_rangeLow && (now - g_rangeEnd) > 60)
        { ORBLog(StringFormat("[ORB] LOW level already breached and >1 min elapsed (bid %.5f <= low %.5f) - skipping order.", bid, g_rangeLow)); g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false); }
        else if(lotsLow <= 0.0)
        { ORBLog("[ORB] LOW level skipped: no lot room (per-market cap or free margin exhausted)."); g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false); }
        else if(bid > g_rangeLow)
        {
            if(Reverse_Orders)
            {
                double sSL = NormalizeDouble(g_rangeLow - slRaw, _Digits);
                double sTP = NormalizeDouble(g_rangeLow + tpRaw, _Digits);
                g_sellSendPending = true; g_sellSendTime = TimeCurrent();
                if(trade.BuyLimit(lotsLow, g_rangeLow, _Symbol, sSL, sTP, ORDER_TIME_GTC, 0, BuildComment(true)))
                { ORBLog(StringFormat("[ORB] BuyLimit placed @ %.5f | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeLow, lotsLow, sSL, sTP)); g_sellPlaced = true; ClaimAndRegisterLastOrder(false); ORBNotifyEntry(true, g_rangeLow, sSL, sTP); }
                else
                { g_sellSendPending = false; uint _rcLowL = trade.ResultRetcode(); if(IsMarketClosedRetcode(_rcLowL)) { g_mktClosedPendingLow = true; g_mktClosedLastBidLow = bid; g_mktClosedLastCheckLow = TimeCurrent(); ORBLog(StringFormat("[ORB] BuyLimit rejected: market closed (rc=%u). Watching for price change to retry.", _rcLowL)); } else { s_failCountLow[fcSlotStop]++; ORBLog(StringFormat("[ORB] BuyLimit FAILED err=%d (attempt %d/3)", GetLastError(), s_failCountLow[fcSlotStop])); if(s_failCountLow[fcSlotStop] >= 3) { g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false); ORBLog("[ORB] Max low-level retries reached. Skipping."); } } }
            }
            else
            {
                double sSL = NormalizeDouble(g_rangeLow + slRaw, _Digits);
                double sTP = NormalizeDouble(g_rangeLow - tpRaw, _Digits);
                g_sellSendPending = true; g_sellSendTime = TimeCurrent();
                bool sentS = false;
                if(Use_StopLimit_Orders)
                { bool sentS = trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP_LIMIT, lotsLow, g_rangeLow, g_rangeLow, sSL, sTP, ORDER_TIME_GTC, 0, BuildComment(false)); if(sentS) ORBLog(StringFormat("[ORB] SellStopLimit placed @ stop=limit=%.5f | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeLow, lotsLow, sSL, sTP)); }
                else
                { bool sentS = trade.SellStop(lotsLow, g_rangeLow, _Symbol, sSL, sTP, ORDER_TIME_GTC, 0, BuildComment(false)); if(sentS) ORBLog(StringFormat("[ORB] SellStop placed @ %.5f | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeLow, lotsLow, sSL, sTP)); }
                
                if(trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED)
                { g_sellPlaced = true; if(Use_StopLimit_Orders) { g_slMonitorLow = true; g_slTrigDetLow = false; g_sl100CheckedLow = false; g_slWaitWatchLow = false; } ClaimAndRegisterLastOrder(false); ORBNotifyEntry(false, g_rangeLow, sSL, sTP); }
                else
                { g_sellSendPending = false; uint _rcLowS = trade.ResultRetcode(); if(IsMarketClosedRetcode(_rcLowS)) { g_mktClosedPendingLow = true; g_mktClosedLastBidLow = bid; g_mktClosedLastCheckLow = TimeCurrent(); ORBLog(StringFormat("[ORB] Sell%s rejected: market closed (rc=%u). Watching for price change to retry.", Use_StopLimit_Orders?"StopLimit":"Stop", _rcLowS)); } else { s_failCountLow[fcSlotStop]++; ORBLog(StringFormat("[ORB] Sell%s FAILED err=%d (attempt %d/3)", Use_StopLimit_Orders?"StopLimit":"Stop", GetLastError(), s_failCountLow[fcSlotStop])); if(s_failCountLow[fcSlotStop] >= 3) { g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false); ORBLog("[ORB] Max low-level retries reached. Skipping."); } } }
            }
        }
        else // bid <= g_rangeLow
        {
            if((TimeCurrent() - g_rangeEnd) <= 60)
            {
                double sSL = NormalizeDouble(g_rangeLow + slRaw, _Digits);
                double sTP = NormalizeDouble(g_rangeLow - tpRaw, _Digits);
                g_sellSendPending = true; g_sellSendTime = TimeCurrent();
                if(trade.SellLimit(lotsLow, g_rangeLow, _Symbol, sSL, sTP, ORDER_TIME_GTC, 0, BuildComment(false)))
                { ORBLog(StringFormat("[ORB] 1-Min Fallback SellLimit placed @ %.5f after spike | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeLow, lotsLow, sSL, sTP)); g_sellPlaced = true; ClaimAndRegisterLastOrder(false); ORBNotifyEntry(false, g_rangeLow, sSL, sTP); }
                else
                { if(trade.SellStop(lotsLow, g_rangeLow, _Symbol, sSL, sTP, ORDER_TIME_GTC, 0, BuildComment(false))) { ORBLog(StringFormat("[ORB] 1-Min Fallback SellStop placed @ %.5f after Limit failed | lots=%.2f | SL=%.5f | TP=%.5f", g_rangeLow, lotsLow, sSL, sTP)); g_sellPlaced = true; ClaimAndRegisterLastOrder(false); ORBNotifyEntry(false, g_rangeLow, sSL, sTP); } else { g_buySendPending = false; uint _rcLowF = trade.ResultRetcode(); if(IsMarketClosedRetcode(_rcLowF)) { g_mktClosedPendingLow = true; g_mktClosedLastBidLow = bid; g_mktClosedLastCheckLow = TimeCurrent(); ORBLog(StringFormat("[ORB] 1-Min Fallback (SellLimit/SellStop) rejected: market closed (rc=%u). Watching for price change to retry.", _rcLowF)); } else { s_failCountLow[fcSlotStop]++; ORBLog(StringFormat("[ORB] 1-Min Fallback Orders FAILED err=%d (attempt %d/3)", GetLastError(), s_failCountLow[fcSlotStop])); if(s_failCountLow[fcSlotStop] >= 3) { g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false); } } } }
            }
            else
            { ORBLog(StringFormat("[ORB] LOW level already breached and >1 min elapsed (bid %.5f <= low %.5f) - skipping order.", bid, g_rangeLow)); g_sellPlaced = true; MarkSideConsumed(g_sessionKey, false); }
        }
    }


    // Signal 1: Armed - send once both pending orders are confirmed live
    if(g_buyPlaced && g_sellPlaced)
    {
        double bEntry=0,bSL2=0,bTP2=0,sEntry=0,sSL2=0,sTP2=0;
        // Primary scan: owned orders only
        for(int i=OrdersTotal()-1;i>=0;i--)
        {
            ulong t=OrderGetTicket(i);
            if(t==0||!OrderSelect(t)) continue;
            if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
            if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
            if(!OwnsTicket(t)) continue;
            ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(ot==ORDER_TYPE_BUY_STOP||ot==ORDER_TYPE_BUY_LIMIT)
            {bEntry=OrderGetDouble(ORDER_PRICE_OPEN);bSL2=OrderGetDouble(ORDER_SL);bTP2=OrderGetDouble(ORDER_TP);}
            if(ot==ORDER_TYPE_SELL_STOP||ot==ORDER_TYPE_SELL_LIMIT)
            {sEntry=OrderGetDouble(ORDER_PRICE_OPEN);sSL2=OrderGetDouble(ORDER_SL);sTP2=OrderGetDouble(ORDER_TP);}
        }
        // Fallback: magic+symbol only - handles async placement where OwnsTicket GVs
        // are not yet populated at the moment the Armed block runs
        if(bEntry<=0.0||sEntry<=0.0)
        {
            for(int i=OrdersTotal()-1;i>=0;i--)
            {
                ulong t=OrderGetTicket(i);
                if(t==0||!OrderSelect(t)) continue;
                if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
                if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
                ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                if(bEntry<=0.0&&(ot==ORDER_TYPE_BUY_STOP||ot==ORDER_TYPE_BUY_LIMIT))
                {bEntry=OrderGetDouble(ORDER_PRICE_OPEN);bSL2=OrderGetDouble(ORDER_SL);bTP2=OrderGetDouble(ORDER_TP);}
                if(sEntry<=0.0&&(ot==ORDER_TYPE_SELL_STOP||ot==ORDER_TYPE_SELL_LIMIT))
                {sEntry=OrderGetDouble(ORDER_PRICE_OPEN);sSL2=OrderGetDouble(ORDER_SL);sTP2=OrderGetDouble(ORDER_TP);}
            }
        }
        string buyLabel  = Reverse_Orders ? "BUY LIMIT"  : "BUY STOP";
        string sellLabel = Reverse_Orders ? "SELL LIMIT" : "SELL STOP";
        ORBNotifyArmed(g_sessionKey, SessionLabel(), g_rangeHigh, g_rangeLow,
                       buyLabel, sellLabel,
                       bEntry, bSL2, bTP2, sEntry, sSL2, sTP2,
                       TrailThreshRaw(), TrailGapRaw(), (int)Trail_Mode);
    }
    trade.SetAsyncMode(true);
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA today                      |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!CurrentSlotOwnsOrder(ticket)) continue;
        if(!OwnsTicket(ticket)) continue;
        ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        bool isBuy=(otype==ORDER_TYPE_BUY_STOP || otype==ORDER_TYPE_BUY_LIMIT);
        double px=OrderGetDouble(ORDER_PRICE_OPEN);
        if(trade.OrderDelete(ticket))
        {
            ORBDeleteObj(ORBPfx()+"PENDING_"+IntegerToString(ticket));
            ORBLog(StringFormat("[ORB] Canceled pending order #%llu", ticket));
            ORBNotifyOrderCancelled(ticket,g_sessionKey,isBuy,px,"Cancelled by EA");
        }
    }
}

void CancelAllPendingOrdersForInstance()
{
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!OwnsTicket(ticket)) continue;

        ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(otype != ORDER_TYPE_BUY_STOP && otype != ORDER_TYPE_SELL_STOP &&
           otype != ORDER_TYPE_BUY_LIMIT && otype != ORDER_TYPE_SELL_LIMIT &&
           otype != ORDER_TYPE_BUY_STOP_LIMIT && otype != ORDER_TYPE_SELL_STOP_LIMIT) continue;

        double px = OrderGetDouble(ORDER_PRICE_OPEN);
        bool isBuy = (otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_BUY_LIMIT);
        if(trade.OrderDelete(ticket))
        {
            ORBLog(StringFormat("[ORB] Canceled pending order #%llu", ticket));
            ORBNotifyOrderCancelled(ticket, "", isBuy, px, "EA deinit");
        }
    }
}

void ClearAllSlotVisuals()
{
    int prevSlot = g_ctxSlotIdx;
    for(int s = 0; s < 6; s++)
    {
        g_ctxSlotIdx = s;
        ClearORBVisuals();
    }
    g_ctxSlotIdx = prevSlot;
}

//+------------------------------------------------------------------+
//| OCO: if any position active, cancel remaining pending orders     |
//+------------------------------------------------------------------+
void CheckOCO()
{
    if(!HasCurrentRangeTrade()) return;

    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        if(PositionGetTicket(i) == 0) continue;
        ulong pticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(PositionGetInteger(POSITION_MAGIC))) continue;
        if(!OwnsTicket(pticket)) continue;
        CancelPendingOrders();
        return;
    }
}

//+------------------------------------------------------------------+
//| Draw all visual objects for pending orders and active trades     |
//+------------------------------------------------------------------+
void UpdateVisuals()
{
    if(!ShouldRenderVisuals()) return;

    // Pending orders - draw dash line at stop price
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(!MagicMatch(OrderGetInteger(ORDER_MAGIC))) continue;
        if(!OwnsTicket(ticket)) continue;
        if(!CurrentSlotOwnsOrderAnySession(ticket)) continue;

        double px = OrderGetDouble(ORDER_PRICE_OPEN);
        ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        // Left anchor = exact candle that formed this level
        datetime leftAnchor = (otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_SELL_LIMIT) ? g_rangeHighTime : g_rangeLowTime;
        OrderMeta meta;
        if(GetOrderMeta(ticket, meta)) leftAnchor = meta.levelTime;
        if(leftAnchor == 0) leftAnchor = g_rangeStart; // fallback
        DrawPendingLine(ORBPfx()+"PENDING_"+IntegerToString(ticket), px, leftAnchor);
    }

    // Active and recently closed trades
    double slRaw = SLRaw();
    double tpRaw = TPRaw();

    for(int i = 0; i < ArraySize(vTrades); i++)
    {
        string ts = IntegerToString(vTrades[i].ticket);
        // Draw when this slot owns the trade, OR when the trade is unslotted
        // (slotIdx<0, adopted without meta) and we're on the slot-0 pass —
        // otherwise unslotted trades never draw at all (observed: NY-side and
        // London-low exec objects missing entirely).
        bool owned      = (vTrades[i].slotIdx == g_ctxSlotIdx);
        bool unslotted0 = (vTrades[i].slotIdx < 0 && g_ctxSlotIdx == 0);
        if(!owned && !unslotted0) continue;

        double riskPts   = RawToPts(MathAbs(vTrades[i].entryPx - vTrades[i].vSL));
        double rewardPts = RawToPts(MathAbs(vTrades[i].vTP - vTrades[i].entryPx));

        // Keep showing recently closed trades with snapped anchors
        if(!vTrades[i].active && vTrades[i].exitTime == 0) continue;

        // AMNESIA RULE: closed intraday trades stop drawing the moment their
        // NY trading day closes (18:00) — objects deleted, not just skipped.
        // Open positions keep their objects (real money is still managed).
        if(vTrades[i].slotIdx <= 2 && !vTrades[i].active &&
           vTrades[i].triggerTime > 0 &&
           TimeCurrent() >= IntradayDayCloseServer(vTrades[i].triggerTime))
        {
            DeleteExecObjects(ts);
            continue;
        }

        DrawExecObjects(ts, vTrades[i].bull, vTrades[i].entryPx, vTrades[i].vSL, vTrades[i].vTP,
                        vTrades[i].trailing, vTrades[i].triggerTime, vTrades[i].trailStartTime,
                        vTrades[i].exitTime, riskPts, rewardPts,
                        vTrades[i].levelPx, vTrades[i].levelTime);

        // Once resolved and snapped - delete pending line if any
        if(!vTrades[i].active) ORBDeleteObj(ORBPfx()+"PENDING_"+ts);
    }
}
























