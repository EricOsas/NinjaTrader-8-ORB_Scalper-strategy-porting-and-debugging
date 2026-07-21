#ifndef ORB_DASHBOARD_MQH
#define ORB_DASHBOARD_MQH

#include "ORB_Time.mqh"

//+------------------------------------------------------------------+
//|                                             ORB_Dashboard.mqh   |
//| Compact info panel for ORB Scalper EA                            |
//+------------------------------------------------------------------+

extern bool   Inp_ShowDashboard;
extern int    Inp_OpenNYHour;
extern int    Inp_OpenNYMinute;
extern int    Inp_DashTheme;   // 0=Dark, 1=Dim-light

int  g_dbX        = 20;
int  g_dbY        = 20;
bool g_dbCollapsed = false;
bool g_dbDragging  = false;
int  g_dbDragDX    = 0;
int  g_dbDragDY    = 0;

#define DB_W 300
#define DB_FULL_H 170
#define DB_HDR_H  36

extern bool   Inp_EnableNY;
extern bool   Inp_EnableLondon;
extern bool   Inp_EnableAsian;
extern int    Inp_LondonHour;
extern int    Inp_AsianHour;
extern int    Inp_LondonMinute;
extern int    Inp_AsianMinute;
extern int    g_activeSession;
extern bool   g_sessionIsLive;

color _DB_BG()      { if(Inp_DashTheme==1) return C'232,237,245'; return C'14,18,26'; }
color _DB_GLASS()   { if(Inp_DashTheme==1) return C'245,248,252'; return C'24,31,44'; }
color _DB_PANEL()   { if(Inp_DashTheme==1) return C'255,255,255'; return C'30,40,58'; }
color _DB_BORDER()  { if(Inp_DashTheme==1) return C'200,210,224'; return C'52,68,92'; }
color _DB_HAIR()    { if(Inp_DashTheme==1) return C'255,255,255'; return C'70,90,120'; }
color _DB_TEXT()    { if(Inp_DashTheme==1) return C'24,32,46';    return C'230,238,252'; }
color _DB_MUTED()   { if(Inp_DashTheme==1) return C'96,112,134';  return C'140,158,185'; }
color _DB_ACCENT()  { if(Inp_DashTheme==1) return C'40,90,170';   return C'190,210,236'; }
color _DB_GREEN()   { return C'120,210,150'; }

#define ORB_C_BG      _DB_BG()
#define ORB_C_PANEL   _DB_PANEL()
#define ORB_C_BORDER  _DB_BORDER()
#define ORB_C_TEXT    _DB_TEXT()
#define ORB_C_MUTED   _DB_MUTED()
#define ORB_C_ACCENT  _DB_ACCENT()

string _DB_LabelForSession(int s)
{
    if(s == 1) return "London Open:";
    if(s == 2) return "Asian Open:";
    return "NY Open:";
}

// Self-contained, time-based: never trusts g_activeSession or g_ctx* (both
// reflect whichever slot the main EA loop happened to process last, which can
// be stale by the time the dashboard actually renders - especially since
// UpdateDashboard is called once per timer tick, not per-slot). Always
// computes fresh from the current time vs each session's own schedule,
// mirroring the same "watch until 18:00 NY" cutoff rule used for trading.
// Returns the chosen session index (0=NY,1=London,2=Asian,-1=none enabled),
// its open/cutoff server times, and whether it's live right now.
int GetDisplaySessionInfo(datetime &sessionOpenOut, datetime &cutoffOut, bool &isLiveOut)
{
    datetime now = TimeCurrent();
    MqlDateTime ny;
    TimeToStruct(ServerToNY(now), ny);
    int nowMin = ny.hour * 60 + ny.min;

    int best = -1, next = -1;
    int bestStart = -1, nextStart = 9999;
    bool bestLive = false;

    for(int s = 0; s < 3; s++)
    {
        bool enabled = (s==1) ? Inp_EnableLondon : (s==2) ? Inp_EnableAsian : Inp_EnableNY;
        if(!enabled) continue;

        int hh = (s==1) ? Inp_LondonHour : (s==2) ? Inp_AsianHour : Inp_OpenNYHour;
        int mm = (s==1) ? Inp_LondonMinute : (s==2) ? Inp_AsianMinute : Inp_OpenNYMinute;
        int openMin = hh * 60 + mm;

        // Mirrors SessionCutoffMin(): watch until 18:00 NY, wrapping to the
        // next day if this session opens at/after 18:00 itself (e.g. Asian).
        int durMin = (18 * 60) - openMin;
        if(durMin <= 0) durMin += 1440;
        int endMinRaw = openMin + durMin;   // may exceed 1440 - handled below

        bool isLiveNow = (endMinRaw <= 1440)
                       ? (nowMin >= openMin && nowMin < endMinRaw)
                       : (nowMin >= openMin || nowMin < (endMinRaw - 1440));

        if(isLiveNow && openMin > bestStart) { best = s; bestStart = openMin; bestLive = true; }
        if(!isLiveNow && openMin > nowMin && openMin < nextStart) { next = s; nextStart = openMin; }
    }

    int chosen = (best >= 0) ? best : next;
    if(chosen < 0)
    {
        // Nothing live and nothing later today -> TOMORROW's first session:
        // the enabled session with the EARLIEST open minute. (The old
        // fallback always showed "NY Open" even when London 00:00 or Asian
        // 18:00 was actually next.)
        int earliest = 24 * 60 + 1;
        for(int s2 = 0; s2 < 3; s2++)
        {
            bool en2 = (s2==1) ? Inp_EnableLondon : (s2==2) ? Inp_EnableAsian : Inp_EnableNY;
            if(!en2) continue;
            int hh2 = (s2==1) ? Inp_LondonHour : (s2==2) ? Inp_AsianHour : Inp_OpenNYHour;
            int mm2 = (s2==1) ? Inp_LondonMinute : (s2==2) ? Inp_AsianMinute : Inp_OpenNYMinute;
            int om2 = hh2 * 60 + mm2;
            if(om2 < earliest) { earliest = om2; chosen = s2; }
        }
    }
    if(chosen < 0) { sessionOpenOut = 0; cutoffOut = 0; isLiveOut = false; return -1; }

    int hh = (chosen==1) ? Inp_LondonHour : (chosen==2) ? Inp_AsianHour : Inp_OpenNYHour;
    int mm = (chosen==1) ? Inp_LondonMinute : (chosen==2) ? Inp_AsianMinute : Inp_OpenNYMinute;
    datetime openToday = NYLocalToServer(ny.year, ny.mon, ny.day, hh, mm, 0);

    // If this session's open-minute is BEFORE now but it isn't "live" (i.e. we
    // picked it as tomorrow's "next"), the open time is actually tomorrow.
    int openMinChosen = hh*60+mm;
    bool liveChosen = (chosen == best);
    if(!liveChosen && openMinChosen <= nowMin) openToday += 86400;

    int durMin = (18*60) - openMinChosen;
    if(durMin <= 0) durMin += 1440;

    sessionOpenOut = openToday;
    cutoffOut      = openToday + (datetime)(durMin * 60);
    isLiveOut      = liveChosen;
    return chosen;
}

string _DB_SessionLabel(int chosenSession)
{
    if(chosenSession < 0) return "Session:";
    return _DB_LabelForSession(chosenSession);
}

void _DB_Label(string name, int x, int y, string text, int fs, color clr, string font="Segoe UI Semibold")
{
    if(ObjectFind(0,name) < 0)
    {
        ObjectCreate(0,name,OBJ_LABEL,0,0,0);
        ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_BACK,false);
        ObjectSetString(0,name,OBJPROP_FONT,font);
    }
    if(ObjectGetInteger(0,name,OBJPROP_XDISTANCE) != x) ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
    if(ObjectGetInteger(0,name,OBJPROP_YDISTANCE) != y) ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
    if(ObjectGetInteger(0,name,OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
    if(ObjectGetInteger(0,name,OBJPROP_COLOR)     != clr) ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
    if(ObjectGetString(0,name,OBJPROP_TEXT)       != text) ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void _DB_Rect(string name, int x, int y, int w, int h, color bg, color border)
{
    if(ObjectFind(0,name) < 0)
    {
        ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
        ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_BACK,false);
    }
    ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
    ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
    ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
    ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
    ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
    ObjectSetInteger(0,name,OBJPROP_COLOR,border);
    ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
}

bool _DB_CanDraw()
{
    if(!Inp_ShowDashboard) return false;
    if((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) return false;
    return true;
}

void DB_RestoreState()
{
    if(GlobalVariableCheck("ORB_DBX")) g_dbX = (int)GlobalVariableGet("ORB_DBX");
    if(GlobalVariableCheck("ORB_DBY")) g_dbY = (int)GlobalVariableGet("ORB_DBY");
    if(GlobalVariableCheck("ORB_DBC")) g_dbCollapsed = (GlobalVariableGet("ORB_DBC") != 0.0);
    long chartW = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    long chartH = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    if(chartW <= 0) chartW = 1200;
    if(chartH <= 0) chartH = 700;
    if(g_dbX < 0 || g_dbX > (int)chartW - 40) g_dbX = 20;
    if(g_dbY < 0 || g_dbY > (int)chartH - 40) g_dbY = 20;
}
void DB_PersistState()
{
    GlobalVariableSet("ORB_DBX", (double)g_dbX);
    GlobalVariableSet("ORB_DBY", (double)g_dbY);
    GlobalVariableSet("ORB_DBC", g_dbCollapsed ? 1.0 : 0.0);
}

void DB_Layout()
{
    if(!_DB_CanDraw()) return;
    int X = g_dbX, Y = g_dbY;
    int bodyH = g_dbCollapsed ? DB_HDR_H : DB_FULL_H;

    _DB_Rect("ORBD_SHADOW2", X+6, Y+7, DB_W, bodyH, _DB_BG(),    _DB_BG());
    _DB_Rect("ORBD_SHADOW",  X+3, Y+3, DB_W, bodyH, _DB_BG(),    _DB_BG());
    _DB_Rect("ORBD_BG",      X,   Y,   DB_W, bodyH, _DB_GLASS(), _DB_BORDER());
    _DB_Rect("ORBD_HEADER",  X,   Y,   DB_W, DB_HDR_H, _DB_PANEL(), _DB_BORDER());
    _DB_Rect("ORBD_PILL",    X+12, Y+14, 8, 8, _DB_ACCENT(), _DB_ACCENT());
    _DB_Label("ORBD_TITLE",  X+26, Y+11, "ORB SCALPER", 9, _DB_ACCENT());
    
    string tg = g_dbCollapsed ? "+" : ShortToString(0x2013);   // + / en-dash
    int btnSz = 22;
    int btnX  = X + DB_W - btnSz - 7;
    int btnY  = Y + (DB_HDR_H - btnSz)/2;
    if(ObjectFind(0,"ORBD_BTN")<0)
    {
        ObjectCreate(0,"ORBD_BTN",OBJ_BUTTON,0,0,0);
        ObjectSetInteger(0,"ORBD_BTN",OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,"ORBD_BTN",OBJPROP_HIDDEN,true);
        ObjectSetString(0,"ORBD_BTN",OBJPROP_FONT,"Segoe UI Semibold");
    }
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_XDISTANCE,btnX);
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_YDISTANCE,btnY);
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_XSIZE,btnSz);
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_YSIZE,btnSz);
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_FONTSIZE,12);
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_COLOR,_DB_TEXT());
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_BGCOLOR,_DB_GLASS());
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_BORDER_COLOR,_DB_BORDER());
    ObjectSetInteger(0,"ORBD_BTN",OBJPROP_STATE,false);
    ObjectSetString(0,"ORBD_BTN",OBJPROP_TEXT,tg);
    

    if(g_dbCollapsed)
    {
        _DB_Rect("ORBD_HAIR",  X, Y+DB_HDR_H,   DB_W, 1, _DB_HAIR(), _DB_HAIR());
        _DB_Rect("ORBD_HAIR2", X, Y+DB_HDR_H+1, DB_W, 1, _DB_BG(),   _DB_BG());
        if(ObjectFind(0,"ORBD_SHEEN")>=0) ObjectSetInteger(0,"ORBD_SHEEN",OBJPROP_YSIZE,0);
    }
    else
    {
        _DB_Rect("ORBD_HAIR",  X, Y+36, DB_W, 1, _DB_HAIR(), _DB_HAIR());
        _DB_Rect("ORBD_HAIR2", X, Y+37, DB_W, 1, _DB_BG(),   _DB_BG());
        _DB_Rect("ORBD_SHEEN", X+1, Y+38, DB_W-2, 8, _DB_PANEL(), _DB_PANEL());
    }
}

void InitDashboard()
{
    if(!_DB_CanDraw()) return;
    DB_RestoreState();
    DB_Layout();
}

double   g_dbPtCache     = 0.0;
datetime g_dbPtCacheTime = 0;
double DB_EffPoint()
{
    datetime now = TimeCurrent();
    if(g_dbPtCache <= 0.0 || (now - g_dbPtCacheTime) >= 5)
    {
        g_dbPtCache     = NormPoint();
        g_dbPtCacheTime = now;
    }
    return g_dbPtCache;
}

void UpdateDashboard(string status, double rangeHigh, double rangeLow, double rangeRaw, double slPts, double entrySpreadRaw)
{
    if(!_DB_CanDraw()) return;
    if(ObjectFind(0, "ORBD_BG") < 0) InitDashboard();

    datetime srv = TimeCurrent();
    datetime ny  = ServerToNY(srv);
    string   clock = TimeToString(ny, TIME_MINUTES|TIME_SECONDS);

    double effPt = DB_EffPoint();
    datetime sessionOpen, cutoff;
    bool dispIsLive;
    int dispSession = GetDisplaySessionInfo(sessionOpen, cutoff, dispIsLive);
    string sessLabel;
    string cntdown;

    if(g_ctxMode == RANGE_DAILY || g_ctxMode == RANGE_WEEKLY || g_ctxMode == RANGE_MONTHLY)
    {
        // HTF display: unchanged from before this fix - reflects whichever
        // slot the main loop last processed into g_ctx*.
        sessionOpen = SessionOpenServer(srv);
        cutoff      = SessionCutoffServer(srv);
        sessLabel   = (g_ctxMode == RANGE_DAILY) ? "Daily Open:" : (g_ctxMode == RANGE_WEEKLY) ? "Weekly Open:" : "Monthly Open:";
        cntdown     = (cutoff <= sessionOpen) ? "Disabled"
                    : (srv < cutoff) ? "Open"
                    : "Closed";
    }
    else
    {
        sessLabel = _DB_SessionLabel(dispSession);
        cntdown   = (dispSession < 0) ? "Disabled"
                  : dispIsLive ? "Open"
                  : GetCountdownText(sessionOpen, srv);
    }

    static string s_sig = "";
    string sig = clock + "|" + status + "|" + cntdown + "|" +
                 DoubleToString(rangeHigh,_Digits) + "|" + DoubleToString(rangeLow,_Digits) + "|" +
                 DoubleToString(effPt,5) + "|" + IntegerToString((int)slPts) + "|" +
                 DoubleToString(entrySpreadRaw,_Digits) + "|" +
                 IntegerToString(g_dbX) + "|" + IntegerToString(g_dbY) + "|" +
                 (g_dbCollapsed?"C":"O");
    if(sig == s_sig) return;
    s_sig = sig;

    int X = g_dbX, Y = g_dbY;

    _DB_Label("ORBD_CLOCK", X+190, Y+9, "NY " + clock, 8, _DB_MUTED());

    if(g_dbCollapsed)
    {
        string body[] = {"ORBD_STATUS","ORBD_TIMER","ORBD_RANGE","ORBD_POINT","ORBD_ASSET"};
        for(int i=0;i<ArraySize(body);i++) if(ObjectFind(0,body[i])>=0)
            ObjectSetInteger(0,body[i],OBJPROP_XDISTANCE,-9000);
        ChartRedraw(0);
        return;
    }

    color statusClr = (StringFind(status,"Trade") >= 0) ? _DB_GREEN() : _DB_TEXT();
    _DB_Label("ORBD_STATUS", X+12, Y+48, "Status: " + status, 8, statusClr);
    _DB_Label("ORBD_TIMER",  X+12, Y+68, sessLabel + " " + cntdown, 8, _DB_TEXT());

    string rangeText = "Range: --";
    if(rangeHigh > 0.0 && rangeLow > 0.0)
    {
        double pts = (_Point > 0.0) ? rangeRaw / _Point : rangeRaw;
        rangeText = StringFormat("Range: %.2f – %.2f  (%d pts)", rangeLow, rangeHigh, (int)MathRound(pts));
    }
    _DB_Label("ORBD_RANGE", X+12, Y+88, rangeText, 8, _DB_MUTED(), "Consolas");

    string ptMode = (Custom_Point_Multiplier > 0.0) ? "C"
                  : (Point_Scale_Mode == SCALE_WIDE) ? "W" : "B";
    _DB_Label("ORBD_POINT", X+12, Y+108,
              StringFormat("Pt %s %s  SL %.0f=%s",
                           DoubleToString(effPt, 4), ptMode, slPts,
                           DoubleToString(slPts*effPt, _Digits)),
              7, _DB_ACCENT(), "Consolas");

    _DB_Label("ORBD_ASSET", X+12, Y+126,
              StringFormat("%s  1pt=%s  SprE=%s", _Symbol, DoubleToString(_Point,5),
                           entrySpreadRaw > 0.0 ? DoubleToString(entrySpreadRaw, _Digits) : "--"),
              7, _DB_MUTED(), "Consolas");

    ChartRedraw(0);
}

bool DB_HeaderHit(int x, int y)
{
    bool inHeader = (x >= g_dbX && x <= g_dbX+DB_W && y >= g_dbY && y <= g_dbY+DB_HDR_H);
    if(!inHeader) return false;
    int btnSz = 22;
    int btnX  = g_dbX + DB_W - btnSz - 7;
    int btnY  = g_dbY + (DB_HDR_H - btnSz)/2;
    bool inBtn = (x >= btnX-2 && x <= btnX+btnSz+2 && y >= btnY-2 && y <= btnY+btnSz+2);
    return !inBtn;
}
void DB_BeginDrag(int x, int y) { g_dbDragging = true; g_dbDragDX = x - g_dbX; g_dbDragDY = y - g_dbY; }
void DB_EndDrag()               { if(g_dbDragging){ g_dbDragging=false; DB_Layout(); ChartRedraw(0); DB_PersistState(); } }

void DB_ShiftTo(int X, int Y)
{
    int dx = X - g_dbX, dy = Y - g_dbY;
    if(dx == 0 && dy == 0) return;
    string objs[] = {"ORBD_SHADOW2","ORBD_SHADOW","ORBD_BG","ORBD_HEADER","ORBD_PILL",
                     "ORBD_TITLE","ORBD_BTN","ORBD_HAIR","ORBD_HAIR2","ORBD_SHEEN",
                     "ORBD_CLOCK","ORBD_STATUS","ORBD_TIMER","ORBD_RANGE","ORBD_POINT","ORBD_ASSET"};
    for(int i=0;i<ArraySize(objs);i++)
    {
        if(ObjectFind(0,objs[i])<0) continue;
        ObjectSetInteger(0,objs[i],OBJPROP_XDISTANCE,(int)ObjectGetInteger(0,objs[i],OBJPROP_XDISTANCE)+dx);
        ObjectSetInteger(0,objs[i],OBJPROP_YDISTANCE,(int)ObjectGetInteger(0,objs[i],OBJPROP_YDISTANCE)+dy);
    }
    g_dbX = X; g_dbY = Y;
}
void DB_DragTo(int x, int y)
{
    int nx = x - g_dbDragDX, ny = y - g_dbDragDY;
    if(nx < 0) nx = 0;
    if(ny < 0) ny = 0;
    if(nx == g_dbX && ny == g_dbY) return;
    static uint s_lastDragMs = 0;
    uint nowMs = GetTickCount();
    DB_ShiftTo(nx, ny);
    if(nowMs - s_lastDragMs >= 50) { s_lastDragMs = nowMs; ChartRedraw(0); }
}
void DB_ToggleCollapse()
{
    g_dbCollapsed = !g_dbCollapsed;
    DB_Layout();
    DB_PersistState();
    ChartRedraw(0);
}

void ClearDashboard()
{
    ObjectsDeleteAll(0, "ORBD_");
}

#endif // ORB_DASHBOARD_MQH
