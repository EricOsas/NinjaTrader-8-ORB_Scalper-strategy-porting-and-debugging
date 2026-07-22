//+------------------------------------------------------------------+
//|                                                       CRT_EA.mq5 |
//| Candle Range Theory Expert Advisor — MQL5 port                   |
//| Matches CRT_NT_Strategy.cs (NinjaTrader 8) logic exactly.        |
//|                                                                   |
//| Authoritative rules (see CRT/01-STRATEGY-SPEC.md §1):            |
//|   C1 = reference candle: defines range High/Low and EQ (50%).    |
//|   C2 = manipulation candle: sweep ONLY; NEVER executes.          |
//|   C3 = execution candle: market (>=1:1) or 1:1 resting limit.   |
//|   Limit PERSISTS beyond C3 close; dies on fill or 50% touch.     |
//|   SL  = FIXED at C2 extreme ± buffer; independent of C1_EQ.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025-2026, Osamwonyi Eric (You_FoundEric)"
#property link      "https://t.me/You_FoundEric"
#property version   "1.00"
#property description "CRT EA — Candle Range Theory (MQL5)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

#include "CRT_Globals.mqh"
#include "CRT_Time.mqh"
#include "CRT_Risk.mqh"
#include "CRT_Confirm.mqh"
#include "CRT_Notify.mqh"
#include "CRT_Dashboard.mqh"

//======================================================================
// Inputs — grouped to match the C# CRT_Inputs.cs parameter surface
//======================================================================

input group "01 — Timeframe / Slot"
input(name="Active slot") ENUM_CRT_SLOT         Inp_Slot           = CRT_SLOT_INTRADAY;
input(name="Intraday TF (C1/C2/C3)") ENUM_CRT_INTRADAY_TF Inp_IntradayTf = CRT_TF_H1;
input(name="LTF override (min, 0=auto)") int   Inp_LtfOverrideMin = 0;   // 0 = auto-derive per spec pairings

input group "02 — Session Window (intraday guard)"
input(name="Restrict session") bool             Inp_RestrictSession = true;
input(name="Session start (NY HH:MM)") string  Inp_SessionStart   = "02:00";
input(name="Session end   (NY HH:MM)") string  Inp_SessionEnd     = "11:30";
input(name="Flatten at    (NY HH:MM)") string  Inp_FlattenAt      = "15:55";

input group "03 — CRT Model"
input(name="Trigger model") ENUM_CRT_TRIGGER    Inp_TriggerModel   = CRT_TRIGGER_CISD_IFVG;
input(name="CISD reference") ENUM_CRT_CISD_REF  Inp_CisdRef        = CRT_CISD_SEQUENCE;
input(name="Carry C2 trigger into C3") bool     Inp_CarryToC3      = true;

input group "04 — Entry"
input(name="SL buffer ticks (beyond C2 extreme)") int Inp_SlBufferTicks = 2;

input group "05 — Risk"
input(name="Risk preset") ENUM_CRT_RISK_PRESET  Inp_RiskPreset     = CRT_RISK_0_50;
input(name="Risk custom %") double              Inp_RiskCustomPct  = 0.5;
input(name="Account mode") ENUM_CRT_ACC_MODE    Inp_AccMode        = CRT_ACC_BALANCE;
input(name="Custom capital") double             Inp_CustomCapital  = 10000.0;
input(name="Max lots (0=off)") double           Inp_MaxLotsGlobal  = 0.0;
input(name="Max trades per day") int            Inp_MaxTradesDay   = 3;
input(name="Max consec losses") int             Inp_MaxConsecLosses= 3;
input(name="Daily loss limit % (0=off)") double Inp_DailyLossPct   = 0.0;

input group "06 — NY Hour Filter"
input(name="Enable hour filter") bool           Inp_HourFilter     = true;
input(name="Allowed NY hours (CSV)") string     Inp_AllowedHours   = "2,3,4,9,10,11";

input group "07 — News"
input(name="Enable news blackout") bool         Inp_NewsFilter     = false;
input(name="Manual news events (YY.MM.DD HH:MM CCY;...)") string Inp_NewsEvents = "";
input(name="Block minutes before") int          Inp_NewsBeforeMin  = 5;
input(name="Block minutes after") int           Inp_NewsAfterMin   = 5;

input group "08 — Notifications"
input(name="Enable notifications") bool         Inp_NotifyEnabled  = false;
input(name="Discord: enabled") bool             Inp_DiscordEnabled = false;
input(name="Discord: webhook URL") string       Inp_DiscordWebhook = "";
input(name="Telegram: enabled") bool            Inp_TelegramEnabled= false;
input(name="Telegram: bot token") string        Inp_TelegramToken  = "";
input(name="Telegram: chat ID") string          Inp_TelegramChatId = "";

input group "09 — Broker"
input(name="Magic number") int                  Inp_Magic          = 20250001;
input(name="Max slippage points") int           Inp_MaxSlippage    = 10;
input(name="Server UTC offset (0=auto)") int    Inp_ServerUTCOffsetHours = 0;
input(name="Use NY DST") bool                   Inp_UseNewYorkDST  = true;

input group "10 — Visuals"
input(name="Show dashboard") bool               Inp_ShowDashboard  = true;
input(name="Dashboard theme") ENUM_CRT_DASH_THEME Inp_DashTheme    = CRT_DASH_DARK;
input(name="Draw CRT levels on chart") bool     Inp_DrawVisuals    = true;
input(name="Stealth mode (suppress logs)") bool Inp_StealthMode    = false;

//======================================================================
// Derived effective risk %
//======================================================================
double Inp_RiskPct = 0.5; // resolved in OnInit from preset

//======================================================================
// Globals
//======================================================================
CTrade  g_trade;
CrtSetup        g_setup;
CrtConfirmState g_confirm;
CrtTrade        g_activeTrade;
bool            g_hasTrade    = false;

ENUM_TIMEFRAMES g_htfPeriod;
ENUM_TIMEFRAMES g_ltfPeriod;
int             g_htfHandle   = INVALID_HANDLE;
int             g_ltfHandle   = INVALID_HANDLE;

// Daily counters
int      g_tradesToday     = 0;
int      g_consecLosses    = 0;
double   g_dayStartBalance = 0.0;
string   g_currentNyDayKey = "";
double   g_sessionPnL      = 0.0;

// Session window (parsed from Inp_SessionStart/End/FlattenAt)
int g_sesStartHour = 2, g_sesStartMin = 0;
int g_sesEndHour   = 11, g_sesEndMin  = 30;
int g_flatHour     = 15, g_flatMin    = 55;

// News: simple manual event list (YY.MM.DD HH:MM CCY  semicolon-separated)
datetime g_newsEvents[];
int      g_nNewsEvents = 0;

//======================================================================
// Forward declarations
//======================================================================
void   CrtOnHtfClose();
void   CrtOnLtfClose();
void   CrtTryLockC1();
void   CrtOnC2Closed();
void   CrtOnC3Closed();
void   CrtDecideEntry(double refPrice, bool atC3Open);
void   CrtInvalidateOnFifty();
void   CrtCompleteSetup(const string reason);
void   CrtRollDailyCounters();
bool   CrtNewsBlocked();
bool   CrtInSessionWindow();
void   CrtFlattenIfNeeded();
void   CrtDrawLevels(double entry, double sl, double tp, bool isLong);
void   CrtClearLevels();
void   CrtPublishDash(const CrtConfirmState &st);
void   CrtParseSessionTime(const string hhmm, int &hourOut, int &minOut);
void   CrtParseNewsEvents();
double CrtAccountBalance();

//======================================================================
// OnInit
//======================================================================
int OnInit()
{
    g_crtStealthMode  = Inp_StealthMode;
    g_crtIsTester     = (bool)MQLInfoInteger(MQL_TESTER);
    g_crtRuntimeStart = TimeCurrent();

    // Resolve effective risk %
    if (Inp_RiskPreset == CRT_RISK_CUSTOM)
        Inp_RiskPct = Inp_RiskCustomPct;
    else
        Inp_RiskPct = (double)Inp_RiskPreset / 100.0;

    // Configure trade object
    g_trade.SetExpertMagicNumber(Inp_Magic);
    g_trade.SetDeviationInPoints(Inp_MaxSlippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    // Resolve periods
    g_htfPeriod = CrtHtfPeriod(Inp_Slot, Inp_IntradayTf);
    g_ltfPeriod = CrtLtfPeriod(Inp_Slot, Inp_IntradayTf, Inp_LtfOverrideMin);

    // Create indicators for HTF and LTF bar data (dummy MA to prime history)
    g_htfHandle = iMA(_Symbol, g_htfPeriod, 1, 0, MODE_SMA, PRICE_CLOSE);
    g_ltfHandle = iMA(_Symbol, g_ltfPeriod, 1, 0, MODE_SMA, PRICE_CLOSE);
    if (g_htfHandle == INVALID_HANDLE || g_ltfHandle == INVALID_HANDLE)
    {
        Print("[CRT] ERROR: failed to create series handles");
        return INIT_FAILED;
    }

    // Init setup state
    ZeroMemory(g_setup);
    g_setup.phase  = CRT_PHASE_WAIT_C1;
    g_setup.slotType = Inp_Slot;
    g_setup.slotTfMin = (int)Inp_IntradayTf;
    g_setup.c2RunHigh = DBL_MIN;
    g_setup.c2RunLow  = DBL_MAX;
    g_setup.nFvgs     = 0;
    ZeroMemory(g_confirm);
    ZeroMemory(g_activeTrade);
    g_hasTrade = false;

    // Hour filter
    CrtParseHourFilter(Inp_AllowedHours);

    // Session window
    CrtParseSessionTime(Inp_SessionStart, g_sesStartHour, g_sesStartMin);
    CrtParseSessionTime(Inp_SessionEnd,   g_sesEndHour,   g_sesEndMin);
    CrtParseSessionTime(Inp_FlattenAt,    g_flatHour,     g_flatMin);

    // News events
    CrtParseNewsEvents();

    // Daily counters
    g_dayStartBalance = CrtAccountBalance();
    g_currentNyDayKey = CrtNYDayKey(TimeCurrent());

    if (!g_crtStealthMode)
        PrintFormat("[CRT] Init | Slot=%s HTF=%s LTF=%s Risk=%.2f%%",
                    CrtSlotLabel(Inp_Slot, Inp_IntradayTf),
                    EnumToString(g_htfPeriod), EnumToString(g_ltfPeriod),
                    Inp_RiskPct);

    return INIT_SUCCEEDED;
}

//======================================================================
// OnDeinit
//======================================================================
void OnDeinit(const int reason)
{
    CrtDashClear();
    CrtClearLevels();
    if (g_htfHandle != INVALID_HANDLE) { IndicatorRelease(g_htfHandle); g_htfHandle = INVALID_HANDLE; }
    if (g_ltfHandle != INVALID_HANDLE) { IndicatorRelease(g_ltfHandle); g_ltfHandle = INVALID_HANDLE; }
}

//======================================================================
// OnTick — detect HTF/LTF bar closes; dispatch.
//======================================================================
static datetime s_prevHtfTime = 0;
static datetime s_prevLtfTime = 0;

void OnTick()
{
    CrtRollDailyCounters();
    CrtFlattenIfNeeded();

    // HTF bar close detection
    datetime htfNow = iTime(_Symbol, g_htfPeriod, 0);
    if (htfNow != s_prevHtfTime && s_prevHtfTime != 0)
        CrtOnHtfClose();
    s_prevHtfTime = htfNow;

    // LTF bar close detection
    datetime ltfNow = iTime(_Symbol, g_ltfPeriod, 0);
    if (ltfNow != s_prevLtfTime && s_prevLtfTime != 0)
        CrtOnLtfClose();
    s_prevLtfTime = ltfNow;

    // Manage resting limit: check 50% guard on every tick while limit is working
    if (g_setup.phase == CRT_PHASE_LIMIT_WORKING && g_setup.bias != CRT_BIAS_NONE)
    {
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if (g_setup.bias == CRT_BIAS_SHORT && bid <= g_setup.c1EQ)
            { CrtInvalidateOnFifty(); return; }
        if (g_setup.bias == CRT_BIAS_LONG  && ask >= g_setup.c1EQ)
            { CrtInvalidateOnFifty(); return; }
    }

    CrtPublishDash(g_confirm);
    CrtDashRender();
}

//======================================================================
// HTF bar close handler
//======================================================================
void CrtOnHtfClose()
{
    // Need at least 2 closed HTF bars
    if (iTime(_Symbol, g_htfPeriod, 1) == 0) return;

    switch (g_setup.phase)
    {
        case CRT_PHASE_WAIT_C1:
            CrtTryLockC1();
            break;

        case CRT_PHASE_C2_WATCH:
            // The just-closed HTF bar IS C2. Resolve bias + decide entry.
            CrtOnC2Closed();
            break;

        case CRT_PHASE_C2_ARMED:
        case CRT_PHASE_C3_WINDOW:
            // The just-closed HTF bar IS C3. Market-entry window closes.
            // A resting 1:1 limit PERSISTS — do NOT cancel.
            CrtOnC3Closed();
            break;

        case CRT_PHASE_LIMIT_WORKING:
            // Limit outlives C3 — a new HTF bar never cancels it.
            // Check if we can now start a new C1 (we can't while a limit rests).
            break;

        case CRT_PHASE_FILLED:
        case CRT_PHASE_DONE:
        default:
            break;
    }
}

//======================================================================
// Try to lock the last-closed HTF bar as C1.
//======================================================================
void CrtTryLockC1()
{
    // Single-trade lock: don't arm while a live trade or resting limit exists.
    if (g_hasTrade || g_setup.limitResting) return;
    if (g_setup.phase != CRT_PHASE_WAIT_C1) return;

    // Session window guard (intraday only)
    if (Inp_Slot == CRT_SLOT_INTRADAY && Inp_RestrictSession && !CrtInSessionWindow()) return;

    // Closed C1 bar = HTF[1]; HTF[2] = prior bar for displacement filter
    datetime c1T = iTime (_Symbol, g_htfPeriod, 1);
    double   c1O = iOpen (_Symbol, g_htfPeriod, 1);
    double   c1H = iHigh (_Symbol, g_htfPeriod, 1);
    double   c1L = iLow  (_Symbol, g_htfPeriod, 1);
    double   c1C = iClose(_Symbol, g_htfPeriod, 1);
    double prevH = iHigh (_Symbol, g_htfPeriod, 2);
    double prevL = iLow  (_Symbol, g_htfPeriod, 2);

    if (c1T == 0) return;

    // Lock C1
    g_setup.c1Time    = c1T;
    g_setup.c1High    = c1H;
    g_setup.c1Low     = c1L;
    g_setup.c1EQ      = (c1H + c1L) * 0.5;
    g_setup.c1Locked  = true;
    g_setup.sessionKey = CrtSessionKey(Inp_Slot, Inp_IntradayTf, c1T);

    // Displacement filter flags
    g_setup.c1ValidBearish = !(c1C > prevH);
    g_setup.c1ValidBullish = !(c1C < prevL);

    // Reset sweep scan
    g_setup.bias         = CRT_BIAS_NONE;
    g_setup.sweptHigh    = false;
    g_setup.sweptLow     = false;
    g_setup.c2RunHigh    = DBL_MIN;
    g_setup.c2RunLow     = DBL_MAX;
    g_setup.triggerFired = false;
    g_setup.triggerFiredInC2 = false;
    g_setup.carryToC3    = false;
    g_setup.confirmClose = 0.0;
    g_setup.slLevel      = 0.0;
    g_setup.limitResting = false;
    g_setup.limitPrice   = 0.0;
    g_setup.invalidated  = false;
    g_setup.sweepStartTime = 0;
    g_setup.nFvgs        = 0;
    g_setup.orderPlaced  = false;
    g_setup.dead         = false;

    ZeroMemory(g_confirm);

    g_setup.phase = CRT_PHASE_C2_WATCH;
    g_setup.c2OpenTime = TimeCurrent();

    if (!g_crtStealthMode)
        PrintFormat("[CRT] C1 locked | %s H=%.5f L=%.5f EQ=%.5f | key=%s",
                    TimeToString(c1T, TIME_DATE | TIME_MINUTES),
                    c1H, c1L, g_setup.c1EQ, g_setup.sessionKey);
}

//======================================================================
// C2 HTF close handler
//======================================================================
void CrtOnC2Closed()
{
    // Fold the C2 HTF bar's extreme into the running sweep tracker
    // (belt-and-braces — LTF bars already tracked it on every tick close).
    double c2H = iHigh (_Symbol, g_htfPeriod, 1);
    double c2L = iLow  (_Symbol, g_htfPeriod, 1);
    double c2C = iClose(_Symbol, g_htfPeriod, 1);

    if (c2H > g_setup.c2RunHigh) g_setup.c2RunHigh = c2H;
    if (c2L < g_setup.c2RunLow)  g_setup.c2RunLow  = c2L;
    if (!g_setup.sweptHigh && c2H > g_setup.c1High) g_setup.sweptHigh = true;
    if (!g_setup.sweptLow  && c2L < g_setup.c1Low)  g_setup.sweptLow  = true;

    // The sweep can ONLY be satisfied in C2. No sweep → no setup.
    if (!g_setup.sweptHigh && !g_setup.sweptLow)
    { CrtCompleteSetup("no sweep in C2"); return; }

    // Resolve bias from C2 close
    bool shortValid = g_setup.sweptHigh && c2C < g_setup.c1High;
    bool longValid  = g_setup.sweptLow  && c2C > g_setup.c1Low;

    if (shortValid && longValid) // outside bar — prefer the side price last returned from
    {
        double dH = MathAbs(g_setup.c1High - c2C);
        double dL = MathAbs(c2C - g_setup.c1Low);
        g_setup.bias = (dH < dL) ? CRT_BIAS_SHORT : CRT_BIAS_LONG;
    }
    else if (shortValid) g_setup.bias = CRT_BIAS_SHORT;
    else if (longValid)  g_setup.bias = CRT_BIAS_LONG;
    else { CrtCompleteSetup("C2 closed outside C1 (breakout)"); return; }

    // Displacement filter (optional — always checked for safety)
    if (g_setup.bias == CRT_BIAS_SHORT && !g_setup.c1ValidBearish)
    { CrtCompleteSetup("C1 displacement filter: invalid for short"); return; }
    if (g_setup.bias == CRT_BIAS_LONG && !g_setup.c1ValidBullish)
    { CrtCompleteSetup("C1 displacement filter: invalid for long"); return; }

    // SL fixed at the C2 extreme ± buffer (independent of the 50% calc)
    double bufPx = Inp_SlBufferTicks * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    // Use tick size (not point) for proper futures/metals sizing
    double tickSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tickSz > 0) bufPx = Inp_SlBufferTicks * tickSz;

    double sweepExt = (g_setup.bias == CRT_BIAS_SHORT) ? g_setup.c2RunHigh : g_setup.c2RunLow;
    g_setup.slLevel = (g_setup.bias == CRT_BIAS_SHORT)
                      ? CrtRound(sweepExt + bufPx)
                      : CrtRound(sweepExt - bufPx);

    g_setup.phase = CRT_PHASE_C2_ARMED;
    g_setup.c2CloseTime = TimeCurrent();

    if (!g_crtStealthMode)
        PrintFormat("[CRT] C2 closed | bias=%s sweepExt=%.5f SL=%.5f EQ=%.5f",
                    (g_setup.bias == CRT_BIAS_LONG ? "LONG" : "SHORT"),
                    sweepExt, g_setup.slLevel, g_setup.c1EQ);

    // Act on a provisional C2 trigger at the C2-close / C3-open boundary.
    // C2 NEVER executes — any order placed here is attributed to C3 open.
    if (g_setup.triggerFired && Inp_CarryToC3)
        CrtDecideEntry(c2C, true);

    // Advance to C3 window regardless (fresh C3 trigger still possible)
    g_setup.c3OpenTime = TimeCurrent();
    if (g_setup.phase == CRT_PHASE_C2_ARMED)
        g_setup.phase = CRT_PHASE_C3_WINDOW;

    // Notify: setup armed
    if (Inp_NotifyEnabled && !g_hasTrade && !g_setup.limitResting)
        CrtNotifySetupArmed(g_setup, Inp_Slot, Inp_IntradayTf);
}

//======================================================================
// C3 HTF close handler
//======================================================================
void CrtOnC3Closed()
{
    // Market-entry opportunity ends here. Resting limit keeps working.
    if (g_setup.limitResting) { g_setup.phase = CRT_PHASE_LIMIT_WORKING; return; }
    if (g_hasTrade) return; // filled; managed by OnTradeTransaction
    CrtCompleteSetup("C3 closed with no entry");
}

//======================================================================
// LTF bar close handler (sweep, confirmation, 50% guard)
//======================================================================
void CrtOnLtfClose()
{
    if (!g_setup.c1Locked) return;

    // Use iTime/iOpen etc. for LTF[1] (just-closed bar)
    datetime ltfT = iTime (_Symbol, g_ltfPeriod, 1);
    double   ltfO = iOpen (_Symbol, g_ltfPeriod, 1);
    double   ltfH = iHigh (_Symbol, g_ltfPeriod, 1);
    double   ltfL = iLow  (_Symbol, g_ltfPeriod, 1);
    double   ltfC = iClose(_Symbol, g_ltfPeriod, 1);
    if (ltfT == 0) return;

    // 50% guard — live for the ENTIRE setup life (C3Window and LimitWorking).
    if (g_setup.bias != CRT_BIAS_NONE &&
        (g_setup.phase == CRT_PHASE_C3_WINDOW  ||
         g_setup.phase == CRT_PHASE_LIMIT_WORKING ||
         g_setup.phase == CRT_PHASE_C2_ARMED))
    {
        bool fiftyHit = false;
        if (g_setup.bias == CRT_BIAS_SHORT && ltfL <= g_setup.c1EQ) fiftyHit = true;
        if (g_setup.bias == CRT_BIAS_LONG  && ltfH >= g_setup.c1EQ) fiftyHit = true;
        if (fiftyHit) { CrtInvalidateOnFifty(); return; }
    }

    switch (g_setup.phase)
    {
        case CRT_PHASE_C2_WATCH:
        {
            // Track sweep in C2 (the sweep can ONLY happen here)
            if (ltfH > g_setup.c2RunHigh) g_setup.c2RunHigh = ltfH;
            if (ltfL < g_setup.c2RunLow)  g_setup.c2RunLow  = ltfL;
            bool newSweep = false;
            if (!g_setup.sweptHigh && g_setup.c2RunHigh > g_setup.c1High)
            { g_setup.sweptHigh = true; newSweep = true; }
            if (!g_setup.sweptLow && g_setup.c2RunLow < g_setup.c1Low)
            { g_setup.sweptLow = true; newSweep = true; }
            if (newSweep && g_setup.sweepStartTime == 0)
                g_setup.sweepStartTime = ltfT;

            // Provisional trigger scanning (only after sweep begins)
            if (g_setup.sweptHigh || g_setup.sweptLow)
            {
                ENUM_CRT_BIAS provBias = g_setup.sweptHigh ? CRT_BIAS_SHORT : CRT_BIAS_LONG;
                bool fired = CrtConfirmPushAndEvaluate(g_confirm, g_setup,
                                 ltfT, ltfO, ltfH, ltfL, ltfC,
                                 Inp_TriggerModel, Inp_CisdRef);
                if (fired && !g_setup.triggerFired)
                {
                    g_setup.triggerFired     = true;
                    g_setup.triggerFiredInC2 = true;
                    g_setup.confirmClose     = g_confirm.confirmClose;
                    // Provisional — C2 never executes; carried to C2-close boundary.
                }
            }
            break;
        }

        case CRT_PHASE_C3_WINDOW:
        {
            // If no C2 carry-over, scan for a C3 trigger
            if (!g_setup.triggerFired && g_setup.bias != CRT_BIAS_NONE)
            {
                bool fired = CrtConfirmPushAndEvaluate(g_confirm, g_setup,
                                 ltfT, ltfO, ltfH, ltfL, ltfC,
                                 Inp_TriggerModel, Inp_CisdRef);
                if (fired)
                {
                    g_setup.triggerFired = true;
                    g_setup.confirmClose = g_confirm.confirmClose;
                    CrtDecideEntry(ltfC, false);
                }
            }
            else
            {
                // Even with a carry-over, keep the FVG window updated in case
                // the limit hasn't been placed yet (e.g. no carry-over path).
                CrtConfirmAddBar(g_confirm, ltfT, ltfO, ltfH, ltfL, ltfC);
                CrtConfirmTrackFvg(g_confirm, g_setup);
            }
            break;
        }

        case CRT_PHASE_LIMIT_WORKING:
            // Only 50% touch (handled above) can end the resting limit.
            // No time-based cancel.
            break;

        default: break;
    }
}

//======================================================================
// Entry decision: market (>=1:1) or 1:1 resting limit.
// refPrice = confirm close (C3) or c2C (carry-over at C2-close boundary).
//======================================================================
void CrtDecideEntry(double refPrice, bool atC3Open)
{
    if (g_hasTrade || g_setup.limitResting) return;
    if (g_setup.bias == CRT_BIAS_NONE) return;
    if (g_setup.orderPlaced) return;

    // Hour filter — gate on C3-open NY hour.
    if (Inp_HourFilter)
    {
        int nyH = CrtNYHour(TimeCurrent());
        if (!CrtHourAllowed(nyH)) { CrtCompleteSetup("hour filter"); return; }
    }

    // News block
    if (Inp_NewsFilter && CrtNewsBlocked())
    { CrtCompleteSetup("news blackout"); return; }

    // Daily risk guards
    if (g_tradesToday >= Inp_MaxTradesDay) { CrtCompleteSetup("max trades/day"); return; }
    if (g_consecLosses >= Inp_MaxConsecLosses) { CrtCompleteSetup("max consec losses"); return; }
    if (Inp_DailyLossPct > 0.0)
    {
        double loss = g_dayStartBalance - CrtAccountBalance();
        if (loss >= g_dayStartBalance * Inp_DailyLossPct / 100.0)
        { CrtCompleteSetup("daily loss limit"); return; }
    }

    bool isLong     = (g_setup.bias == CRT_BIAS_LONG);
    double sweepExt = (isLong) ? g_setup.c2RunLow : g_setup.c2RunHigh;
    double sl       = g_setup.slLevel;   // already resolved at C2 close
    double tp       = g_setup.c1EQ;      // 50% of C1

    // 50% guard on entry side
    double priceNow = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if ((isLong && priceNow >= tp) || (!isLong && priceNow <= tp))
    { CrtCompleteSetup("50% already taken at entry"); return; }

    double riskAtMarket   = MathAbs(refPrice - sl);
    double rewardAtMarket = MathAbs(tp - refPrice);
    if (riskAtMarket <= 0) { CrtCompleteSetup("zero risk distance"); return; }

    bool useLimit;
    double entryRef;

    if (rewardAtMarket >= riskAtMarket)
    {
        // >= 1:1 at market — enter now.
        useLimit = false;
        entryRef = refPrice;
    }
    else
    {
        // Place a 1:1 limit: entry = (TP + SL) / 2 (midpoint → equal risk/reward)
        useLimit = true;
        entryRef = CrtRound((tp + sl) * 0.5);

        // Safety: limit must sit between current price and TP on the trade side.
        if (isLong && entryRef <= sl)  { CrtCompleteSetup("limit below SL"); return; }
        if (!isLong && entryRef >= sl) { CrtCompleteSetup("limit above SL"); return; }
    }

    // Min stop distance check
    double minStop = CrtMinStopPx();
    if (minStop > 0 && MathAbs(entryRef - sl) < minStop)
    { CrtCompleteSetup("SL inside min-stop distance"); return; }

    // Size the position
    double lots = CrtCalcLots(MathAbs(entryRef - sl), Inp_RiskPct);
    lots = CrtAffordableLots(lots);
    if (lots <= 0.0) { CrtCompleteSetup("lot size = 0"); return; }

    // Submit the order
    string tag = "CRT_" + g_setup.sessionKey;
    bool ok = false;
    if (!useLimit)
    {
        ok = isLong ? g_trade.Buy(lots, _Symbol, 0, sl, tp, tag)
                    : g_trade.Sell(lots, _Symbol, 0, sl, tp, tag);
    }
    else
    {
        ok = isLong ? g_trade.BuyLimit(lots, entryRef, _Symbol, sl, tp, 0, 0, tag)
                    : g_trade.SellLimit(lots, entryRef, _Symbol, sl, tp, 0, 0, tag);
    }

    if (!ok)
    {
        if (!g_crtStealthMode)
            PrintFormat("[CRT] Order failed: %s err=%d", tag, g_trade.ResultRetcode());
        CrtCompleteSetup("order failed: " + IntegerToString(g_trade.ResultRetcode()));
        return;
    }

    // Record the active trade
    g_setup.orderPlaced  = true;
    g_setup.limitResting = useLimit;
    g_setup.limitPrice   = useLimit ? entryRef : 0.0;

    if (useLimit)
        g_setup.phase = CRT_PHASE_LIMIT_WORKING;

    // Populate the trade record (ticket resolved in OnTradeTransaction)
    g_activeTrade.isLong    = isLong;
    g_activeTrade.slPrice   = sl;
    g_activeTrade.tpPrice   = tp;
    g_activeTrade.lots      = lots;
    g_activeTrade.sessionKey= g_setup.sessionKey;
    g_activeTrade.ticket    = g_trade.ResultOrder();
    g_hasTrade = (g_activeTrade.ticket > 0);

    if (!g_crtStealthMode)
        PrintFormat("[CRT] %s | %s entry=%.5f SL=%.5f TP=%.5f lots=%.2f | %s",
                    (useLimit ? "LIMIT" : "MARKET"),
                    (isLong ? "BUY" : "SELL"),
                    entryRef, sl, tp, lots, tag);

    if (Inp_DrawVisuals) CrtDrawLevels(entryRef, sl, tp, isLong);
}

//======================================================================
// 50% invalidation: cancel the resting limit and complete the setup.
//======================================================================
void CrtInvalidateOnFifty()
{
    if (g_setup.limitResting && g_activeTrade.ticket > 0)
    {
        if (!g_trade.OrderDelete(g_activeTrade.ticket))
            if (!g_crtStealthMode)
                PrintFormat("[CRT] OrderDelete fail: ticket=%d err=%d",
                            g_activeTrade.ticket, g_trade.ResultRetcode());
        CrtNotifyCancelled(g_setup, Inp_Slot, Inp_IntradayTf, "50% (C1_EQ) reached before fill");
    }
    g_setup.invalidated = true;
    g_hasTrade = false;
    ZeroMemory(g_activeTrade);
    CrtCompleteSetup("invalidated: 50% taken");
}

//======================================================================
// Setup completion / reset
//======================================================================
void CrtCompleteSetup(const string reason)
{
    if (!g_crtStealthMode)
        PrintFormat("[CRT] Setup complete: %s | key=%s", reason, g_setup.sessionKey);

    if (Inp_DrawVisuals) CrtClearLevels();

    g_setup.phase     = CRT_PHASE_WAIT_C1;
    g_setup.c1Locked  = false;
    g_setup.bias      = CRT_BIAS_NONE;
    g_setup.sweptHigh = false;
    g_setup.sweptLow  = false;
    g_setup.c2RunHigh = DBL_MIN;
    g_setup.c2RunLow  = DBL_MAX;
    g_setup.triggerFired     = false;
    g_setup.triggerFiredInC2 = false;
    g_setup.carryToC3        = false;
    g_setup.confirmClose     = 0.0;
    g_setup.slLevel          = 0.0;
    g_setup.limitResting     = false;
    g_setup.limitPrice       = 0.0;
    g_setup.invalidated      = false;
    g_setup.sweepStartTime   = 0;
    g_setup.nFvgs            = 0;
    g_setup.orderPlaced      = false;
    ZeroMemory(g_confirm);
}

//======================================================================
// OnTradeTransaction — detect fills and exits.
//======================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if (!g_hasTrade) return;
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

    ulong deal = trans.deal;
    if (!HistoryDealSelect(deal)) return;

    long magic = (long)HistoryDealGetInteger(deal, DEAL_MAGIC);
    if (magic != Inp_Magic) return;

    ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
    double dealPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
    double dealLots  = HistoryDealGetDouble(deal, DEAL_VOLUME);
    double profit    = HistoryDealGetDouble(deal, DEAL_PROFIT);

    if (entry == DEAL_ENTRY_IN)
    {
        // Entry filled
        g_activeTrade.entryPrice  = dealPrice;
        g_activeTrade.entryTime   = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
        g_activeTrade.ticket      = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
        g_setup.limitResting      = false;
        g_setup.phase             = CRT_PHASE_FILLED;
        g_tradesToday++;
        g_hasTrade = true;

        if (!g_crtStealthMode)
            PrintFormat("[CRT] FILLED | %s @ %.5f lots=%.2f",
                        (g_activeTrade.isLong ? "BUY" : "SELL"),
                        dealPrice, dealLots);

        CrtNotifyFill(g_activeTrade, g_setup, Inp_Slot, Inp_IntradayTf);
    }
    else if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
    {
        // Exit (SL, TP, or manual close)
        double pnl = profit;
        bool   tpHit = (pnl > 0.0); // approx; refine via deal comment if needed
        string exitReason = tpHit ? "TP" : "SL";

        if (pnl < 0.0) g_consecLosses++;
        else g_consecLosses = 0;

        g_sessionPnL += pnl;

        if (!g_crtStealthMode)
            PrintFormat("[CRT] EXIT | %s pnl=%.2f | %s",
                        exitReason, pnl, g_activeTrade.sessionKey);

        CrtNotifyExit(g_activeTrade, dealPrice, exitReason, pnl, Inp_Slot, Inp_IntradayTf);

        g_hasTrade = false;
        ZeroMemory(g_activeTrade);
        CrtCompleteSetup(exitReason + " hit");
    }
}

//======================================================================
// Helpers
//======================================================================
void CrtRollDailyCounters()
{
    string nyDayKey = CrtNYDayKey(TimeCurrent());
    if (nyDayKey != g_currentNyDayKey)
    {
        g_currentNyDayKey  = nyDayKey;
        g_tradesToday      = 0;
        g_consecLosses     = 0;
        g_dayStartBalance  = CrtAccountBalance();
        g_sessionPnL       = 0.0;
    }
}

double CrtAccountBalance()
{
    return AccountInfoDouble(ACCOUNT_BALANCE);
}

bool CrtNewsBlocked()
{
    if (!Inp_NewsFilter || g_nNewsEvents == 0) return false;
    datetime now = TimeCurrent();
    int before = Inp_NewsBeforeMin * 60;
    int after  = Inp_NewsAfterMin  * 60;
    for (int i = 0; i < g_nNewsEvents; i++)
    {
        if (now >= g_newsEvents[i] - before && now <= g_newsEvents[i] + after)
            return true;
    }
    return false;
}

bool CrtInSessionWindow()
{
    MqlDateTime ny;
    TimeToStruct(CrtNowNY(), ny);
    int nowMin = ny.hour * 60 + ny.min;
    int startMin = g_sesStartHour * 60 + g_sesStartMin;
    int endMin   = g_sesEndHour   * 60 + g_sesEndMin;
    return (nowMin >= startMin && nowMin < endMin);
}

void CrtFlattenIfNeeded()
{
    if (!g_hasTrade) return;
    MqlDateTime ny;
    TimeToStruct(CrtNowNY(), ny);
    int nowMin   = ny.hour * 60 + ny.min;
    int flatMin  = g_flatHour * 60 + g_flatMin;
    if (nowMin >= flatMin)
    {
        g_trade.PositionClose(_Symbol, Inp_MaxSlippage);
        g_hasTrade = false;
        ZeroMemory(g_activeTrade);
        CrtCompleteSetup("flatten at EOD");
    }
}

void CrtParseSessionTime(const string hhmm, int &hourOut, int &minOut)
{
    string parts[];
    if (StringSplit(hhmm, ':', parts) >= 2)
    {
        hourOut = (int)StringToInteger(parts[0]);
        minOut  = (int)StringToInteger(parts[1]);
    }
}

void CrtParseNewsEvents()
{
    // Format: "2026.05.01 08:30 USD;2026.06.01 14:00 GBP"
    // We store only the server-time instants; CCY filtering skipped for simplicity.
    if (Inp_NewsEvents == "") return;
    string evts[];
    int n = StringSplit(Inp_NewsEvents, ';', evts);
    ArrayResize(g_newsEvents, n);
    g_nNewsEvents = 0;
    for (int i = 0; i < n; i++)
    {
        string e = evts[i];
        StringTrimLeft(e); StringTrimRight(e);
        if (StringLen(e) < 10) continue;
        // Extract "YYYY.MM.DD HH:MM" portion (first 16 chars)
        string dtStr = StringSubstr(e, 0, 16);
        datetime dt = StringToTime(dtStr);
        if (dt > 0)
        {
            g_newsEvents[g_nNewsEvents++] = dt;
        }
    }
}

//======================================================================
// Chart visuals: CRT boxes and levels
//======================================================================
void CrtDrawLevels(double entry, double sl, double tp, bool isLong)
{
    if (!Inp_DrawVisuals) return;
    string pfx = "CRT_LEVEL_";
    color  entClr = isLong ? C'50,210,120' : C'220,60,75';

    // SL line
    ObjectCreate(0, pfx + "SL", OBJ_HLINE, 0, 0, sl);
    ObjectSetInteger(0, pfx + "SL", OBJPROP_COLOR,     C'180,40,40');
    ObjectSetInteger(0, pfx + "SL", OBJPROP_STYLE,     STYLE_DASH);
    ObjectSetInteger(0, pfx + "SL", OBJPROP_WIDTH,     1);
    ObjectSetInteger(0, pfx + "SL", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, pfx + "SL", OBJPROP_HIDDEN,     true);

    // TP line
    ObjectCreate(0, pfx + "TP", OBJ_HLINE, 0, 0, tp);
    ObjectSetInteger(0, pfx + "TP", OBJPROP_COLOR,     C'22,55,120');
    ObjectSetInteger(0, pfx + "TP", OBJPROP_STYLE,     STYLE_DASH);
    ObjectSetInteger(0, pfx + "TP", OBJPROP_WIDTH,     1);
    ObjectSetInteger(0, pfx + "TP", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, pfx + "TP", OBJPROP_HIDDEN,     true);

    // Entry line
    ObjectCreate(0, pfx + "ENTRY", OBJ_HLINE, 0, 0, entry);
    ObjectSetInteger(0, pfx + "ENTRY", OBJPROP_COLOR,     entClr);
    ObjectSetInteger(0, pfx + "ENTRY", OBJPROP_STYLE,     STYLE_SOLID);
    ObjectSetInteger(0, pfx + "ENTRY", OBJPROP_WIDTH,     1);
    ObjectSetInteger(0, pfx + "ENTRY", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, pfx + "ENTRY", OBJPROP_HIDDEN,     true);

    // C1 EQ line
    ObjectCreate(0, pfx + "EQ", OBJ_HLINE, 0, 0, g_setup.c1EQ);
    ObjectSetInteger(0, pfx + "EQ", OBJPROP_COLOR,     C'80,190,230');
    ObjectSetInteger(0, pfx + "EQ", OBJPROP_STYLE,     STYLE_DOT);
    ObjectSetInteger(0, pfx + "EQ", OBJPROP_WIDTH,     1);
    ObjectSetInteger(0, pfx + "EQ", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, pfx + "EQ", OBJPROP_HIDDEN,     true);

    ChartRedraw(0);
}

void CrtClearLevels()
{
    string pfx = "CRT_LEVEL_";
    string names[] = {"SL", "TP", "ENTRY", "EQ"};
    for (int i = 0; i < 4; i++)
        ObjectDelete(0, pfx + names[i]);
}

//======================================================================
// Dashboard publish
//======================================================================
void CrtPublishDash(const CrtConfirmState &st)
{
    if (!Inp_ShowDashboard) return;

    CrtDashState ds;
    ds.slotLabel    = "CRT " + CrtSlotLabel(Inp_Slot, Inp_IntradayTf);
    ds.nyClock      = CrtNYClockStr(TimeCurrent());
    ds.phase        = EnumToString(g_setup.phase);
    ds.bias         = (g_setup.bias == CRT_BIAS_LONG)  ? "LONG" :
                      (g_setup.bias == CRT_BIAS_SHORT) ? "SHORT" : "--";
    ds.sweepSide    = g_setup.sweptHigh ? "High" : g_setup.sweptLow ? "Low" : "none";
    ds.c1High       = g_setup.c1High;
    ds.c1Low        = g_setup.c1Low;
    ds.c1EQ         = g_setup.c1EQ;
    ds.cisdStatus   = st.cisdOk ? "armed" : "watch";
    ds.ifvgStatus   = st.ifvgOk ? "armed" : "watch";
    ds.triggerModel = EnumToString(Inp_TriggerModel);
    ds.inTrade      = g_hasTrade && g_setup.phase == CRT_PHASE_FILLED;
    ds.tradeDir     = g_hasTrade ? (g_activeTrade.isLong ? "LONG" : "SHORT") : "--";
    ds.entryPrice   = g_hasTrade ? g_activeTrade.entryPrice : 0.0;
    ds.slPrice      = g_hasTrade ? g_activeTrade.slPrice : g_setup.slLevel;
    ds.tpPrice      = g_hasTrade ? g_activeTrade.tpPrice : g_setup.c1EQ;
    ds.lots         = g_hasTrade ? g_activeTrade.lots : 0.0;
    ds.sessionPnL   = g_sessionPnL;
    ds.tradesToday  = g_tradesToday;
    ds.maxTradesDay = Inp_MaxTradesDay;
    ds.newsBlocked  = Inp_NewsFilter && CrtNewsBlocked();
    ds.hourFiltered = Inp_HourFilter && !CrtHourAllowed(CrtNYHour(TimeCurrent()));
    ds.sessionKey   = g_setup.sessionKey;
    ds.balance      = CrtAccountBalance();
    ds.entryInfo    = g_setup.limitResting
                      ? ("limit @ " + DoubleToString(g_setup.limitPrice, _Digits))
                      : (g_hasTrade
                         ? ("filled @ " + DoubleToString(g_activeTrade.entryPrice, _Digits))
                         : "--");

    CrtDashPublish(ds);
}
