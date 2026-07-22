//+------------------------------------------------------------------+
//|                                                      DTR_CRT.mq5 |
//| DTR Time-Based Range + CRT Bias Strategy EA (v2)                 |
//+------------------------------------------------------------------+
#property copyright "Custom Build"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
#include "DTR_Inputs.mqh"

//+------------------------------------------------------------------+
//| Modules                                                          |
//+------------------------------------------------------------------+
#include "DTR_Core.mqh"
#include "DTR_Engine.mqh"
#include "DTR_UI.mqh"

//+------------------------------------------------------------------+
//| Helper Methods                                                   |
//+------------------------------------------------------------------+
void PrepareDashboardState(datetime serverTime)
{
    DTRDashState state;
    state.session = "NY"; // Default, update based on time
    
    if(IsInRangeWindow(serverTime, SESSION_LONDON) || IsInTradingWindow(serverTime, SESSION_LONDON))
        state.session = "London";
    else if(IsInRangeWindow(serverTime, SESSION_NY) || IsInTradingWindow(serverTime, SESSION_NY))
        state.session = "NY";
    else
        state.session = "--";
        
    state.phase = "Waiting";
    if(IsInRangeWindow(serverTime, SESSION_LONDON) || IsInRangeWindow(serverTime, SESSION_NY))
        state.phase = "Range Forming";
    else if(IsInTradingWindow(serverTime, SESSION_LONDON) || IsInTradingWindow(serverTime, SESSION_NY))
        state.phase = "Trading Window";
    
    state.biasDir = "WAITING";
    if(state.session == "London")
    {
        if(g_londonBias == BIAS_LONG) state.biasDir = "LONG ↑";
        else if(g_londonBias == BIAS_SHORT) state.biasDir = "SHORT ↓";
        else if(g_londonBias == BIAS_NEUTRAL) state.biasDir = "NEUTRAL ↔";
        else if(g_londonBias == BIAS_NOTRADE) state.biasDir = "NO TRADE —";
    }
    else if(state.session == "NY")
    {
        if(g_nyBias == BIAS_LONG) state.biasDir = "LONG ↑";
        else if(g_nyBias == BIAS_SHORT) state.biasDir = "SHORT ↓";
        else if(g_nyBias == BIAS_NEUTRAL) state.biasDir = "NEUTRAL ↔";
        else if(g_nyBias == BIAS_NOTRADE) state.biasDir = "NO TRADE —";
    }
    
    state.sweepType = "Awaiting";
    ManipulationLeg leg = (state.session == "London") ? g_londonLeg : g_nyLeg;
    if(leg.active)
    {
        state.sweepType = leg.isUpsideSweep ? "Upside Sweep" : "Downside Sweep";
    }
    
    UpdateDashboard(state);
}

void InitRecoveryReplay()
{
    datetime nowSrv = TimeCurrent();
    datetime trueDayOpen = DTRNYTrueDayOpenForServerTime(nowSrv);
    
    MqlRates m1[];
    int copied = CopyRates(_Symbol, PERIOD_M1, trueDayOpen, nowSrv, m1);
    if(copied <= 0) return;
    
    UpdateBiasState(nowSrv);
    
    for(int i = copied-1; i >= 0; i--)
    {
        ManageLiveRanges(m1[i].time, m1[i]);
        TickMandatoryScanner(m1[i].time, m1[i], SESSION_NY); 
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
    InitRecoveryReplay();
    InitDashboard();
    EventSetTimer(1);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    ObjectsDeleteAll(0, "DTR_");
    ObjectsDeleteAll(0, "DTRD_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime serverTime = TimeCurrent();
    
    MqlRates m1[1];
    if(CopyRates(_Symbol, PERIOD_M1, 0, 1, m1) <= 0) return;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    CheckPendingRetestFills(bid, ask);
    CheckBreakEvenTick(bid, ask);
    
    UpdateBiasState(serverTime);
    ManageLiveRanges(serverTime, m1[0]);
    
    TickMandatoryScanner(serverTime, m1[0], SESSION_LONDON);
    TickMandatoryScanner(serverTime, m1[0], SESSION_NY);
    
    RunCachedScanner(serverTime, Inp_London_LTF, SESSION_LONDON);
    RunCachedScanner(serverTime, Inp_NY_LTF, SESSION_NY);
    
    EnforceSessionCutoffs(serverTime);
    
    PrepareDashboardState(serverTime);
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
    datetime serverTime = TimeCurrent();
    PrepareDashboardState(serverTime);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == "DTRD_BTN")
        {
            DB_ToggleCollapse();
            ObjectSetInteger(0,"DTRD_BTN",OBJPROP_STATE,false); 
        }
    }
    else if(id == CHARTEVENT_MOUSE_MOVE)
    {
        int x = (int)lparam;
        int y = (int)dparam;
        int state = (int)StringToInteger(sparam);
        bool lbutton = (state & 1) != 0;
        
        if(!lbutton)
        {
            if(g_dbDragging) DB_EndDrag();
            return;
        }
        
        if(g_dbDragging)
        {
            DB_DragTo(x, y);
            ChartRedraw(0);
        }
        else if(DB_HeaderHit(x, y))
        {
            DB_BeginDrag(x, y);
        }
    }
}
//+------------------------------------------------------------------+
