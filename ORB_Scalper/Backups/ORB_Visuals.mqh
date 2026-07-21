//+------------------------------------------------------------------+
//| ORB_Visuals.mqh                                                  |
//| Chart drawing and execution visualization (CCT style)            |
//+------------------------------------------------------------------+
#ifndef ORB_VISUALS_MQH
#define ORB_VISUALS_MQH



//---- Low level property setters to avoid write overhead --------
void _dsi(string n, ENUM_OBJECT_PROPERTY_INTEGER p, int mod, long v)
{
    if(ObjectFind(0,n) < 0) return;
    if(ObjectGetInteger(0,n,p,mod) == v) return;
    ObjectSetInteger(0,n,p,mod,v);
}
void _dsi(string n, ENUM_OBJECT_PROPERTY_INTEGER p, long v) { _dsi(n,p,0,v); }
void _dsd(string n, ENUM_OBJECT_PROPERTY_DOUBLE p, double v) { _dsd(n,p,0,v); }

void _dsd(string n, ENUM_OBJECT_PROPERTY_DOUBLE p, int mod, double v)
{
    if(ObjectFind(0,n) < 0) return;
    if(ObjectGetDouble(0,n,p,mod) == v) return;
    ObjectSetDouble(0,n,p,mod,v);
}
void _dss(string n, ENUM_OBJECT_PROPERTY_STRING p, string v)
{
    if(ObjectFind(0,n) < 0) return;
    if(ObjectGetString(0,n,p) == v) return;
    ObjectSetString(0,n,p,v);
}

//---- Guard: suppress drawing in non-visual tester -----------------
bool ShouldRenderVisuals()
{
    if(!Inp_ShowVisuals) return false;
    if((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) return false;
    return true;
}

//---- LTF period seconds (uses current chart timeframe) -------
int ORBLTFSeconds() { return PeriodSeconds(); }

//---- Live right edge: snaps to current Range_Minutes block boundary -------
// STALL FIX: previously returned blockStart+ltfSec-1, but it was recomputed
// from TimeCurrent() every tick, so on fast symbols the right edge advanced
// every second -> OBJPROP_TIME[1] genuinely changed each tick -> the
// write-through guard re-set every exec/pending object EVERY TICK, saturating
// MT5's render queue and freezing the whole UI (dashboard included) for
// seconds. The edge now snaps to the END of the CURRENT bar block, which only
// changes once per Range_Minutes bar. The write-through guard then suppresses
// redundant sets and the render queue stays empty between bars.
datetime ORBLiveRightEdge()
{
    int ltfSec = ORBLTFSeconds();
    datetime now = TimeCurrent();
    datetime blockStart = (datetime)((long)now / ltfSec * ltfSec);
    // Project one full bar ahead so lines visibly lead price, but on a
    // boundary that only moves once per bar (not once per second/tick).
    return blockStart + (datetime)(2 * ltfSec) - 1;
}

//---- Execution live right edge: entry+3 bars, then live+1 bar ---------------
// Both terms are bar-snapped, so this value only changes on a new chart bar.
datetime ORBExecLiveRightEdge(datetime triggerTime)
{
    int ltfSec = PeriodSeconds();
    datetime now = TimeCurrent();
    datetime blockStart = (datetime)((long)now / ltfSec * ltfSec);
    datetime liveEdge = blockStart + (datetime)ltfSec;
    datetime minEdge = triggerTime + (datetime)(3 * ltfSec);
    return liveEdge > minEdge ? liveEdge : minEdge;
}

//---- Resolved right edge: exitTime-1, minimum 3 bars from trigger ------------
datetime ORBExecResolvedRightEdge(datetime triggerTime, datetime exitTime)
{
    int ltfSec = ORBLTFSeconds();
    if(exitTime > 0)
    {
        datetime snap = exitTime - 1;
        datetime minEdge = triggerTime + (datetime)(3 * ltfSec);
        return snap > minEdge ? snap : minEdge;
    }
    return triggerTime + (datetime)(3 * ltfSec);
}

//---- Set tooltip on both TOOLTIP and TEXT (CCT pattern) -----------
void ORBSetTooltip(string name, string tip)
{
    if(ObjectFind(0,name) < 0) return;
    if(ObjectGetString(0,name,OBJPROP_TOOLTIP) != tip)
        ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
    ObjectSetString(0,name,OBJPROP_TEXT,tip);
}

//---- Delete object if exists --------------------------------------
void ORBDeleteObj(string name)
{
    if(ObjectFind(0,name) >= 0) ObjectDelete(0,name);
}

//+------------------------------------------------------------------+
//| Draw the opening range box                                       |
//+------------------------------------------------------------------+
void DrawRangeBox(string sessionKey, datetime timeStart, datetime timeEnd, double priceHigh, double priceLow)
{
    if(!ShouldRenderVisuals()) return;
    string name = ORBPfx() + "BOX_" + sessionKey;
    color boxClr = Inp_ClrRangeBoxNY;
    if(g_ctxMode == RANGE_DAILY) boxClr = Inp_ClrRangeBoxDaily;
    else if(g_ctxMode == RANGE_WEEKLY) boxClr = Inp_ClrRangeBoxWeekly;
    else if(g_activeSession == 1) boxClr = Inp_ClrRangeBoxLondon;
    else if(g_activeSession == 2) boxClr = Inp_ClrRangeBoxAsian;
    else if(g_activeSession == 0) boxClr = Inp_ClrRangeBoxNY;
    if(ObjectFind(0,name) < 0)
    {
        ObjectCreate(0,name,OBJ_RECTANGLE,0,timeStart,priceHigh,timeEnd,priceLow);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_BACK,true);
        ObjectSetInteger(0,name,OBJPROP_FILL,true);
    }
    _dsi(name,OBJPROP_TIME,0,(long)timeStart);
    _dsd(name,OBJPROP_PRICE,0,priceHigh);
    _dsi(name,OBJPROP_TIME,1,(long)timeEnd);
    _dsd(name,OBJPROP_PRICE,1,priceLow);
    _dsi(name,OBJPROP_COLOR,(long)boxClr);
    string tip = StringFormat("ORB %d-Min Range | Hi: %.5f | Lo: %.5f", Inp_RangeMinutes, priceHigh, priceLow);
    ORBSetTooltip(name,tip);
}

//+------------------------------------------------------------------+
//| Draw a non-ray horizontal OBJ_TREND line (CCT CreateHLine)      |
//+------------------------------------------------------------------+
void ORBCreateHLine(string name, double price, color clr, ENUM_LINE_STYLE sty, int width,
                    datetime leftAnchor, datetime rightAnchor, string tooltip)
{
    if(!ShouldRenderVisuals()) return;
    if(leftAnchor <= 0 || rightAnchor <= leftAnchor) return;

    if(ObjectFind(0,name) < 0)
    {
        ObjectCreate(0,name,OBJ_TREND,0,leftAnchor,price,rightAnchor,price);
        ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
        ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_BACK,false);
        ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES, OBJ_PERIOD_M1|OBJ_PERIOD_M2|OBJ_PERIOD_M3|OBJ_PERIOD_M4|OBJ_PERIOD_M5|OBJ_PERIOD_M6|OBJ_PERIOD_M10|OBJ_PERIOD_M12|OBJ_PERIOD_M15);
    }
    _dsi(name,OBJPROP_TIME,0,(long)leftAnchor);
    _dsd(name,OBJPROP_PRICE,0,price);
    _dsi(name,OBJPROP_TIME,1,(long)rightAnchor);
    _dsd(name,OBJPROP_PRICE,1,price);
    _dsi(name,OBJPROP_COLOR,(long)clr);
    _dsi(name,OBJPROP_STYLE,(long)sty);
    _dsi(name,OBJPROP_WIDTH,(long)width);
    _dsi(name,OBJPROP_RAY_RIGHT,0);
    _dsi(name,OBJPROP_RAY_LEFT,0);
    ORBSetTooltip(name,tooltip);
}

//+------------------------------------------------------------------+
//| Draw a bordered (no fill) box CCT CreateBorderBox              |
//+------------------------------------------------------------------+
void ORBCreateBorderBox(string name, datetime leftAnchor, datetime rightAnchor,
                        double priceA, double priceB, color clr, int width, string tooltip)
{
    if(!ShouldRenderVisuals()) return;
    if(leftAnchor <= 0 || rightAnchor <= leftAnchor) return;
    if(MathAbs(priceA - priceB) <= _Point * 0.1) return;

    double top    = MathMax(priceA, priceB);
    double bottom = MathMin(priceA, priceB);

    if(ObjectFind(0,name) < 0)
    {
        ObjectCreate(0,name,OBJ_RECTANGLE,0,leftAnchor,top,rightAnchor,bottom);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES, OBJ_PERIOD_M1|OBJ_PERIOD_M2|OBJ_PERIOD_M3|OBJ_PERIOD_M4|OBJ_PERIOD_M5|OBJ_PERIOD_M6|OBJ_PERIOD_M10|OBJ_PERIOD_M12|OBJ_PERIOD_M15);
    }
    _dsi(name,OBJPROP_TIME,0,(long)leftAnchor);
    _dsd(name,OBJPROP_PRICE,0,top);
    _dsi(name,OBJPROP_TIME,1,(long)rightAnchor);
    _dsd(name,OBJPROP_PRICE,1,bottom);
    _dsi(name,OBJPROP_COLOR,(long)clr);
    _dsi(name,OBJPROP_STYLE,(long)STYLE_SOLID);
    _dsi(name,OBJPROP_WIDTH,(long)width);
    _dsi(name,OBJPROP_BACK,1);   // behind candles
    _dsi(name,OBJPROP_FILL,0);   // no fill, borders only
    ORBSetTooltip(name,tooltip);
}

//+------------------------------------------------------------------+
//| Draw all execution objects for one trade (entry+SL+TP+trail)     |
//| Called every tick while active; draws CCT-style anchored objects |
//+------------------------------------------------------------------+
void DrawExecObjects(string ts, bool bull, double entry, double vSL, double vTP,
                     bool trailing, datetime triggerTime, datetime trailStartTime,
                     datetime exitTime, double riskPts, double rewardPts,
                     double levelPx = 0.0, datetime levelTime = 0)
{
    if(!ShouldRenderVisuals()) return;

    bool resolved = (exitTime > 0);
    datetime rightEdge = resolved
        ? ORBExecResolvedRightEdge(triggerTime, exitTime)
        : ORBExecLiveRightEdge(triggerTime);

    if(rightEdge <= triggerTime) rightEdge = triggerTime + ORBLTFSeconds();

    string side    = bull ? "LONG" : "SHORT";
    string dir     = bull ? ShortToString(0x25B2) : ShortToString(0x25BC); // up / down triangle
    string outcome = resolved ? (exitTime > 0 ? "Closed" : "?") : "Live";

    double   linePx = (levelPx   > 0.0) ? levelPx   : entry;
    datetime lineL  = (levelTime > 0)   ? levelTime : triggerTime;
    datetime lineR  = triggerTime;
    if(lineR <= lineL) lineR = lineL + ORBLTFSeconds();
    
    bool isSynth = (StringFind(ts, "SYNTHETIC") >= 0);
    ENUM_LINE_STYLE style = isSynth ? STYLE_DASH : STYLE_SOLID;
    string entryTip = StringFormat("%s%s ORB LEVEL | %s | Level: %.5f | Fill: %.5f\nRisk: %.1f pts | Reward: %.1f pts",
                                   isSynth ? "[SYNTHETIC] " : "", dir, outcome, linePx, entry, riskPts, rewardPts);
    ORBCreateHLine(ORBPfx()+"ENT_"+ts, linePx, Inp_ClrEntryLine, style, 2,
                   lineL, lineR, entryTip);

    if(!trailing)
    {
        string slTip = StringFormat("%s%s ORB SL | Risk: %.1f pts | Level: %.5f",
                                    isSynth ? "[SYNTHETIC] " : "", dir, riskPts, vSL);
        ORBCreateBorderBox(ORBPfx()+"SL_"+ts, triggerTime, rightEdge, entry, vSL,
                           Inp_ClrSLLine, 2, slTip);
    }
    else
    {
        ORBDeleteObj(ORBPfx()+"SL_"+ts);
    }

    string tpTip = StringFormat("%s%s ORB TP | Reward: %.1f pts | Level: %.5f",
                                isSynth ? "[SYNTHETIC] " : "", dir, rewardPts, vTP);
    ORBCreateBorderBox(ORBPfx()+"TP_"+ts, triggerTime, rightEdge, entry, vTP,
                       Inp_ClrTPLine, 2, tpTip);

    if(trailing && trailStartTime > 0)
    {
        datetime trailLeft  = (trailStartTime >= triggerTime) ? trailStartTime : triggerTime;
        datetime trailRight = rightEdge;
        if(trailRight <= trailLeft) trailRight = trailLeft + ORBLTFSeconds();

        string trailTip = StringFormat("%s ORB TRAIL SL | Level: %.5f | Active from: %s",
                                       dir, vSL, TimeToString(trailStartTime, TIME_MINUTES));
        ORBCreateHLine(ORBPfx()+"TRAIL_"+ts, vSL, Inp_ClrTrailingStop, STYLE_DOT, 1,
                       trailLeft, trailRight, trailTip);
    }
    else
    {
        ORBDeleteObj(ORBPfx()+"TRAIL_"+ts);
    }
}

//+------------------------------------------------------------------+
//| Delete all objects for a specific trade                          |
//+------------------------------------------------------------------+
void DeleteExecObjects(string ts)
{
    ORBDeleteObj(ORBPfx()+"ENT_"+ts);
    ORBDeleteObj(ORBPfx()+"SL_"+ts);
    ORBDeleteObj(ORBPfx()+"TP_"+ts);
    ORBDeleteObj(ORBPfx()+"TRAIL_"+ts);
    ORBDeleteObj(ORBPfx()+"PENDING_"+ts);
}

//+------------------------------------------------------------------+
//| Draw pending stop order level line                               |
//+------------------------------------------------------------------+
void DrawPendingLine(string name, double price, datetime fromTime)
{
    if(!ShouldRenderVisuals()) return;
    datetime rightEdge = ORBLiveRightEdge();
    if(rightEdge <= fromTime) rightEdge = fromTime + ORBLTFSeconds();
    string tip = StringFormat("ORB Pending Stop | Level: %.5f", price);
    ORBCreateHLine(name, price, Inp_ClrEntryLine, STYLE_DASH, 1, fromTime, rightEdge, tip);
}

//+------------------------------------------------------------------+
//| Clear all ORB-owned chart objects                                |
//+------------------------------------------------------------------+
void ClearORBVisuals(int exceptSlot = -1)
{
    // Scoped to THIS chart's namespace only. If exceptSlot >= 0, objects
    // belonging to that slot (range/pending boxes tagged "S<slot>_", and
    // exec objects for that slot's currently-tracked tickets) are skipped,
    // so a Slot 0 daily reset can no longer wipe Slot 1's weekly/monthly
    // execution objects (or vice versa).
    string pfx = ORBPfx();
    string slotTag = (exceptSlot >= 0) ? ("S" + IntegerToString(exceptSlot) + "_") : "";

    string protectTickets[];
    int protectCount = 0;
    if(exceptSlot >= 0)
    {
        ArrayResize(protectTickets, ArraySize(vTrades));
        for(int j = 0; j < ArraySize(vTrades); j++)
        {
            if(vTrades[j].slotIdx == exceptSlot)
            {
                protectTickets[protectCount] = IntegerToString(vTrades[j].ticket);
                protectCount++;
            }
        }
        ArrayResize(protectTickets, protectCount);
    }

    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, pfx) != 0) continue;

        if(exceptSlot >= 0)
        {
            if(slotTag != "" && StringFind(name, slotTag) >= 0) continue;

            bool isProtectedTicket = false;
            for(int k = 0; k < protectCount; k++)
            {
                if(StringFind(name, "_" + protectTickets[k]) >= 0) { isProtectedTicket = true; break; }
            }
            if(isProtectedTicket) continue;
        }

        ObjectDelete(0, name);
    }
}

#endif // ORB_VISUALS_MQH

