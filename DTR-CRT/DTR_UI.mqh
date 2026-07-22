//+------------------------------------------------------------------+
//|                                                      DTR_UI.mqh  |
//| TradingView-Style Visuals & Liquid Glass Dashboard               |
//+------------------------------------------------------------------+
#ifndef DTR_UI_MQH
#define DTR_UI_MQH

#include "DTR_Core.mqh"



int g_ctxSlotIdx = 0;

string ORBPfx()
{
    return "DTR_" + IntegerToString((long)ChartID()) + "_S" + IntegerToString(g_ctxSlotIdx) + "_";
}

void _dsi(string n, ENUM_OBJECT_PROPERTY_INTEGER p, long v)
{
    if(ObjectFind(0,n) < 0) return;
    if(ObjectGetInteger(0,n,p) == v) return;
    ObjectSetInteger(0,n,p,v);
}
void _dsi(string n, ENUM_OBJECT_PROPERTY_INTEGER p, int mod, long v)
{
    if(ObjectFind(0,n) < 0) return;
    if(ObjectGetInteger(0,n,p,mod) == v) return;
    ObjectSetInteger(0,n,p,mod,v);
}
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

bool ShouldRenderVisuals()
{
    if(!Inp_ShowVisuals) return false;
    if((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) return false;
    return true;
}

void ORBSetTooltip(string name, string tip)
{
    if(ObjectFind(0,name) < 0) return;
    if(ObjectGetString(0,name,OBJPROP_TOOLTIP) != tip)
        ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
    ObjectSetString(0,name,OBJPROP_TEXT,tip);
}

void ORBDeleteObj(string name)
{
    if(ObjectFind(0,name) >= 0) ObjectDelete(0,name);
}

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
    }
    _dsi(name,OBJPROP_TIME,0,(long)leftAnchor);
    _dsd(name,OBJPROP_PRICE,0,top);
    _dsi(name,OBJPROP_TIME,1,(long)rightAnchor);
    _dsd(name,OBJPROP_PRICE,1,bottom);
    _dsi(name,OBJPROP_COLOR,(long)clr);
    _dsi(name,OBJPROP_STYLE,(long)STYLE_SOLID);
    _dsi(name,OBJPROP_WIDTH,(long)width);
    _dsi(name,OBJPROP_BACK,1);
    _dsi(name,OBJPROP_FILL,0);
    ORBSetTooltip(name,tooltip);
}

//+------------------------------------------------------------------+
//| Dashboard Components                                             |
//+------------------------------------------------------------------+
struct DTRDashState
{
    string session;           
    string phase;             
    int    secsToNextPhase;   
    string biasDir;           
    string candleBPos;        
    string sweepType;         
    double aHigh;             
    double aEQ;               
    double aLow;              
    bool   rangeLocked;
    double rangeHigh;         
    double rangeLow;
    int    sweepState;        
    string sweepDetail;       
    int    gateMode;          
    int    gateState;         
    string gateDetail;        
    int    cisdState;         
    string cisdDetail;        
    string entryModel;        
    int    triggerState;      
    string triggerDetail;     
    bool   inTrade;
    string tradeDir;          
    double entryPx;
    double slPx;
    double tpPx;
    double liveRR;            
    string slMode;            
    int    beState;           
    string beDetail;          
    bool   sideConsumed;      
    string consumedResult;    
};

int  g_dbX        = 20;    
int  g_dbY        = 20;    
bool g_dbCollapsed = false; 

color _DB_BG()      { if(Inp_DashTheme==2) return C'232,237,245'; if(Inp_DashTheme==1) return C'30,36,48';  return C'14,18,26'; }
color _DB_GLASS()   { if(Inp_DashTheme==2) return C'245,248,252'; if(Inp_DashTheme==1) return C'40,49,66';  return C'24,31,44'; }
color _DB_PANEL()   { if(Inp_DashTheme==2) return C'255,255,255'; if(Inp_DashTheme==1) return C'48,60,82';  return C'30,40,58'; }
color _DB_BORDER()  { if(Inp_DashTheme==2) return C'200,210,224'; if(Inp_DashTheme==1) return C'70,88,116'; return C'52,68,92'; }
color _DB_HAIR()    { if(Inp_DashTheme==2) return C'255,255,255'; if(Inp_DashTheme==1) return C'92,112,144';return C'70,90,120'; }
color _DB_TEXT()    { if(Inp_DashTheme==2) return C'24,32,46';    return C'230,238,252'; }
color _DB_MUTED()   { if(Inp_DashTheme==2) return C'96,112,134';  return C'140,158,185'; }
color _DB_ACCENT()  { if(Inp_DashTheme==2) return C'40,90,170';   if(Inp_DashTheme==1) return C'170,190,220'; return C'190,210,236'; }
color _DB_GREEN()   { return C'120,210,150'; }
color _DB_RED()     { return C'220,90,80'; }
color _DB_AMBER()   { return C'210,160,50'; }

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


// ── Dashboard drag state ──────────────────────────────────────────
bool g_dbDragging   = false;
int  g_dbDragOfsX   = 0;
int  g_dbDragOfsY   = 0;
string s_dirtySignature = "";

// ── Constants ─────────────────────────────────────────────────────
#define DTR_DB_W         340
#define DTR_DB_HDR_H      36
#define DTR_DB_ROW_H      20
#define DTR_DB_ROW_H_LG   24
#define DTR_DB_INDENT     14
#define DTR_DB_IND_X       8
#define DTR_DB_IND_SZ      8

// ── Dot color by state ────────────────────────────────────────────
color _DotColor(int st)
{
    if(st ==  1) return _DB_GREEN();
    if(st ==  2) return _DB_ACCENT();
    if(st == -1) return _DB_BORDER();
    if(st == -2) return _DB_RED();
    return _DB_MUTED(); // 0
}

void _DB_Dot(string name, int x, int y, int state)
{
    _DB_Rect(name, x, y + DTR_DB_ROW_H/2 - DTR_DB_IND_SZ/2, DTR_DB_IND_SZ, DTR_DB_IND_SZ, _DotColor(state), _DotColor(state));
}

// ── Persistence ───────────────────────────────────────────────────
void DB_RestoreState()
{
    string pfx = "DTR_DB_" + IntegerToString((long)ChartID()) + "_";
    if(GlobalVariableCheck(pfx+"X")) g_dbX = (int)GlobalVariableGet(pfx+"X");
    if(GlobalVariableCheck(pfx+"Y")) g_dbY = (int)GlobalVariableGet(pfx+"Y");
    if(GlobalVariableCheck(pfx+"C")) g_dbCollapsed = (GlobalVariableGet(pfx+"C") > 0.5);
}

void DB_PersistState()
{
    string pfx = "DTR_DB_" + IntegerToString((long)ChartID()) + "_";
    GlobalVariableSet(pfx+"X", (double)g_dbX);
    GlobalVariableSet(pfx+"Y", (double)g_dbY);
    GlobalVariableSet(pfx+"C", g_dbCollapsed ? 1.0 : 0.0);
}

// ── Layout (structural chrome) ────────────────────────────────────
void DB_Layout()
{
    if(!_DB_CanDraw()) return;
    int X = g_dbX, Y = g_dbY;
    int bodyH = g_dbCollapsed ? DTR_DB_HDR_H : 460; // generous default; resized by UpdateDashboard

    _DB_Rect("DTRD_SHADOW2", X+6, Y+7,  DTR_DB_W, bodyH, _DB_BG(),    _DB_BG());
    _DB_Rect("DTRD_SHADOW",  X+3, Y+3,  DTR_DB_W, bodyH, _DB_BG(),    _DB_BG());
    _DB_Rect("DTRD_BG",      X,   Y,    DTR_DB_W, bodyH, _DB_GLASS(), _DB_BORDER());
    _DB_Rect("DTRD_HEADER",  X,   Y,    DTR_DB_W, DTR_DB_HDR_H, _DB_PANEL(), _DB_BORDER());
    _DB_Rect("DTRD_PILL",    X+12, Y+14, 8, 8, _DB_ACCENT(), _DB_ACCENT());
    _DB_Label("DTRD_TITLE",  X+26, Y+11, "DTR · CRT", 9, _DB_ACCENT());
    _DB_Rect("DTRD_HAIR",    X, Y+DTR_DB_HDR_H,   DTR_DB_W, 1, _DB_HAIR(),   _DB_HAIR());
    _DB_Rect("DTRD_HAIR2",   X, Y+DTR_DB_HDR_H+1, DTR_DB_W, 1, _DB_BORDER(), _DB_BORDER());
    _DB_Rect("DTRD_SHEEN",   X, Y+DTR_DB_HDR_H+2, DTR_DB_W, 8, _DB_GLASS(),  _DB_GLASS());

    // Collapse button
    if(ObjectFind(0,"DTRD_BTN") < 0)
    {
        ObjectCreate(0,"DTRD_BTN",OBJ_BUTTON,0,0,0);
        ObjectSetInteger(0,"DTRD_BTN",OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,"DTRD_BTN",OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,"DTRD_BTN",OBJPROP_HIDDEN,true);
        ObjectSetString(0,"DTRD_BTN",OBJPROP_FONT,"Segoe UI Semibold");
    }
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_XDISTANCE, X + DTR_DB_W - 26);
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_YDISTANCE, Y + 8);
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_XSIZE, 18);
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_YSIZE, 18);
    ObjectSetString(0,"DTRD_BTN",OBJPROP_TEXT, g_dbCollapsed ? "+" : "–");
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_COLOR, (long)_DB_MUTED());
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_BGCOLOR, (long)_DB_PANEL());
    ObjectSetInteger(0,"DTRD_BTN",OBJPROP_BORDER_COLOR, (long)_DB_BORDER());
}

// ── Drag machinery ────────────────────────────────────────────────
void DB_ShiftTo(int x, int y)
{
    int dx = x - g_dbX, dy = y - g_dbY;
    g_dbX = x; g_dbY = y;
    // Shift every DTRD_ object
    int total = ObjectsTotal(0);
    for(int i = 0; i < total; i++)
    {
        string n = ObjectName(0, i);
        if(StringFind(n,"DTRD_") != 0) continue;
        ENUM_OBJECT ot = (ENUM_OBJECT)ObjectGetInteger(0,n,OBJPROP_TYPE);
        if(ot == OBJ_LABEL || ot == OBJ_RECTANGLE_LABEL || ot == OBJ_BUTTON)
        {
            long cx = ObjectGetInteger(0,n,OBJPROP_XDISTANCE);
            long cy = ObjectGetInteger(0,n,OBJPROP_YDISTANCE);
            ObjectSetInteger(0,n,OBJPROP_XDISTANCE, cx+dx);
            ObjectSetInteger(0,n,OBJPROP_YDISTANCE, cy+dy);
        }
    }
}

bool DB_HeaderHit(int mx, int my)
{
    int bx = g_dbX + DTR_DB_W - 26;
    int by = g_dbY + 8;
    if(mx >= bx && mx <= bx+18 && my >= by && my <= by+18) return false; // button area
    return (mx >= g_dbX && mx <= g_dbX+DTR_DB_W && my >= g_dbY && my <= g_dbY+DTR_DB_HDR_H);
}

void DB_BeginDrag(int mx, int my)
{
    g_dbDragging = true;
    g_dbDragOfsX = mx - g_dbX;
    g_dbDragOfsY = my - g_dbY;
}

void DB_DragTo(int mx, int my)
{
    if(!g_dbDragging) return;
    DB_ShiftTo(mx - g_dbDragOfsX, my - g_dbDragOfsY);
    DB_PersistState();
}

void DB_EndDrag()
{
    g_dbDragging = false;
    DB_PersistState();
}

void DB_ToggleCollapse()
{
    g_dbCollapsed = !g_dbCollapsed;
    DB_PersistState();
    DB_Layout();
    s_dirtySignature = ""; // force full redraw
}

// ── Init / Clear ──────────────────────────────────────────────────
void InitDashboard()
{
    if(!_DB_CanDraw()) return;
    DB_RestoreState();
    DB_Layout();
}

void ClearDashboard()
{
    ObjectsDeleteAll(0, "DTRD_");
    if(ObjectFind(0,"DTRD_BTN") >= 0) ObjectDelete(0,"DTRD_BTN");
    s_dirtySignature = "";
}

// ── Helper: park object off-canvas ───────────────────────────────
void _DB_Park(string name)
{
    if(ObjectFind(0,name) >= 0)
        ObjectSetInteger(0,name,OBJPROP_XDISTANCE,-9000);
}

// ── Main update entry point ───────────────────────────────────────
void UpdateDashboard(const DTRDashState &state)
{
    if(!_DB_CanDraw()) return;
    if(ObjectFind(0,"DTRD_BG") < 0) InitDashboard();

    // NY clock string
    datetime srv = TimeCurrent();
    MqlDateTime dt; TimeToStruct(srv, dt);
    // Approximate NY time (server - offset); we use server for display
    string clockStr = StringFormat("NY %02d:%02d:%02d", dt.hour, dt.min, dt.sec);

    // Build dirty signature
    string sig = clockStr + "|" + (string)g_dbX + "|" + (string)g_dbY + "|" + (string)g_dbCollapsed
               + "|" + state.session + "|" + state.phase + "|" + (string)state.secsToNextPhase
               + "|" + state.biasDir + "|" + state.candleBPos + "|" + state.sweepType
               + "|" + DoubleToString(state.aHigh,5) + "|" + DoubleToString(state.aLow,5)
               + "|" + (state.rangeLocked?"1":"0") + "|" + DoubleToString(state.rangeHigh,5)
               + "|" + DoubleToString(state.rangeLow,5) + "|" + (string)state.sweepState
               + "|" + state.sweepDetail + "|" + (string)state.gateMode + "|" + (string)state.gateState
               + "|" + state.gateDetail + "|" + (string)state.cisdState + "|" + state.cisdDetail
               + "|" + state.entryModel + "|" + (string)state.triggerState + "|" + state.triggerDetail
               + "|" + (state.inTrade?"1":"0") + "|" + state.tradeDir
               + "|" + DoubleToString(state.entryPx,5) + "|" + DoubleToString(state.slPx,5)
               + "|" + DoubleToString(state.tpPx,5) + "|" + DoubleToString(state.liveRR,2)
               + "|" + (string)state.beState + "|" + (state.sideConsumed?"1":"0")
               + "|" + state.consumedResult;

    if(sig == s_dirtySignature) return;
    s_dirtySignature = sig;

    int X = g_dbX, Y = g_dbY;

    // Always update clock + session header
    _DB_Label("DTRD_CLOCK",       X + DTR_DB_W - 100, Y+11, clockStr,        8, _DB_MUTED());
    _DB_Label("DTRD_SESSION_HDR", X + 75,              Y+11, state.session,   8, _DB_MUTED());

    // Resize BG/shadows to fit content
    int gateRows  = (state.gateMode > 0) ? 1 : 0;
    int tradeH    = state.inTrade ? (22 + 4 + 80) : 0;
    int fullH     = 158 + ((4 + gateRows) * DTR_DB_ROW_H) + tradeH + 20;
    ObjectSetInteger(0,"DTRD_BG",     OBJPROP_YSIZE, g_dbCollapsed ? DTR_DB_HDR_H : fullH);
    ObjectSetInteger(0,"DTRD_SHADOW", OBJPROP_YSIZE, g_dbCollapsed ? DTR_DB_HDR_H : fullH);
    ObjectSetInteger(0,"DTRD_SHADOW2",OBJPROP_YSIZE, g_dbCollapsed ? DTR_DB_HDR_H : fullH);

    if(g_dbCollapsed)
    {
        // Park all body objects
        string bodyObjs[] = {
            "DTRD_PHASE","DTRD_DIV1","DTRD_DIV2","DTRD_DIV3","DTRD_DIV4",
            "DTRD_BIAS_IND","DTRD_BIAS_DIR","DTRD_BIAS_TF",
            "DTRD_CANDLEB_IND","DTRD_CANDLEB_POS","DTRD_REF_LEVELS",
            "DTRD_RANGE_IND","DTRD_RANGE_VAL","DTRD_CL_HDR",
            "DTRD_CL_HTF_IND","DTRD_CL_HTF_LBL","DTRD_CL_HTF_VAL",
            "DTRD_CL_SWP_IND","DTRD_CL_SWP_LBL","DTRD_CL_SWP_VAL",
            "DTRD_CL_GATE_IND","DTRD_CL_GATE_LBL","DTRD_CL_GATE_VAL",
            "DTRD_CL_CISD_IND","DTRD_CL_CISD_LBL","DTRD_CL_CISD_VAL",
            "DTRD_CL_TRG_IND","DTRD_CL_TRG_LBL","DTRD_CL_TRG_VAL",
            "DTRD_TR_DIR","DTRD_TR_MODEL","DTRD_TR_PX","DTRD_TR_RR","DTRD_TR_BE",
            "DTRD_SIDE_IND","DTRD_SIDE_LBL","DTRD_SIDE_VAL"
        };
        for(int i = 0; i < ArraySize(bodyObjs); i++) _DB_Park(bodyObjs[i]);
        ChartRedraw(0);
        return;
    }

    // 5.1 Phase banner (Y=46, H=24)
    string phaseText = state.phase;
    color  phaseClr  = _DB_MUTED();
    int    sc        = state.secsToNextPhase;
    string cd        = "";
    if(sc > 0) cd = (sc < 3600)
        ? StringFormat(" · %02d:%02d", sc/60, sc%60)
        : StringFormat(" · %02d:%02d", sc/3600, (sc%3600)/60);

    if(state.phase == "Waiting")         { phaseText = "Waiting" + cd;                         phaseClr = _DB_MUTED();  }
    else if(state.phase == "Range Forming") { phaseText = "Range Forming" + cd;                phaseClr = _DB_ACCENT(); }
    else if(state.phase == "Range Locked")  { phaseText = "Range Locked" + cd;                 phaseClr = _DB_TEXT();   }
    else if(state.phase == "Trading Window"){ phaseText = "Trading Window" + cd;               phaseClr = _DB_GREEN();  }
    else if(state.phase == "Closed")        { phaseText = "Session Closed";                    phaseClr = _DB_MUTED();  }
    _DB_Label("DTRD_PHASE", X+DTR_DB_INDENT, Y+46, phaseText, 8, phaseClr);

    // 5.2 DIV1
    _DB_Rect("DTRD_DIV1", X, Y+70, DTR_DB_W, 1, _DB_BORDER(), _DB_BORDER());

    // 5.3 HTF Bias (Y=72..139)
    // Row A – Bias direction
    int biasState = (state.biasDir=="LONG ↑"||state.biasDir=="SHORT ↓"||state.biasDir=="NEUTRAL ↔") ? 1
                  : (state.biasDir=="NO TRADE —") ? -1 : 0;
    color biasClr = (state.biasDir=="LONG ↑")    ? _DB_GREEN()
                  : (state.biasDir=="SHORT ↓")   ? _DB_RED()
                  : (state.biasDir=="NO TRADE —") ? _DB_MUTED()
                  : _DB_TEXT();
    _DB_Dot("DTRD_BIAS_IND", X+DTR_DB_IND_X, Y+72, biasState);
    _DB_Label("DTRD_BIAS_DIR", X+DTR_DB_INDENT+10, Y+75, state.biasDir, 9, biasClr);
    _DB_Label("DTRD_BIAS_TF",  X+DTR_DB_W-30, Y+75,
              (state.session=="NY") ? "7H" : "3.5H", 7, _DB_MUTED());

    // Row B – Candle B position (Y=96)
    bool bAligned = ((state.candleBPos=="Discount" && (state.biasDir=="LONG ↑")) ||
                     (state.candleBPos=="Premium"  && (state.biasDir=="SHORT ↓")));
    int candBState = bAligned ? 1 : 0;
    color candBClr = (state.candleBPos=="Discount") ? _DB_GREEN()
                   : (state.candleBPos=="Premium")  ? _DB_RED()
                   : _DB_MUTED();
    string candBText = state.candleBPos + " · " + state.sweepType;
    _DB_Dot("DTRD_CANDLEB_IND", X+DTR_DB_IND_X, Y+96, candBState);
    _DB_Label("DTRD_CANDLEB_POS", X+DTR_DB_INDENT+10, Y+98, candBText, 8, candBClr);

    // Row C – Reference levels (Y=116)
    string refText = (state.aHigh == 0)
        ? "A:  H --   EQ --   L --"
        : StringFormat("A:  H %.5f   EQ %.5f   L %.5f", state.aHigh, state.aEQ, state.aLow);
    _DB_Label("DTRD_REF_LEVELS", X+DTR_DB_INDENT, Y+118, refText, 7, _DB_MUTED(), "Consolas");

    // 5.4 DIV2
    _DB_Rect("DTRD_DIV2", X, Y+136, DTR_DB_W, 1, _DB_BORDER(), _DB_BORDER());

    // 5.5 Range (Y=138)
    int rangeState = state.rangeLocked ? 1 : 0;
    string rangeText;
    color  rangeClr;
    if(state.rangeLocked && state.rangeHigh > 0)
    {
        int pts = (int)MathRound((state.rangeHigh - state.rangeLow) / _Point);
        rangeText = StringFormat("Range  H: %.5f  L: %.5f  (%d pts)", state.rangeHigh, state.rangeLow, pts);
        rangeClr  = _DB_TEXT();
    }
    else if(state.phase == "Range Forming")
    {
        rangeText = "Range  H: --  L: --  (forming…)";
        rangeClr  = _DB_MUTED();
    }
    else
    {
        rangeText = "Range  H: --  L: --";
        rangeClr  = _DB_MUTED();
    }
    _DB_Dot("DTRD_RANGE_IND", X+DTR_DB_IND_X, Y+138, rangeState);
    _DB_Label("DTRD_RANGE_VAL", X+DTR_DB_INDENT+10, Y+140, rangeText, 8, rangeClr, "Consolas");

    // 5.6 DIV3
    _DB_Rect("DTRD_DIV3", X, Y+158, DTR_DB_W, 1, _DB_BORDER(), _DB_BORDER());

    // 5.7 Checklist
    _DB_Label("DTRD_CL_HDR", X+DTR_DB_INDENT, Y+160, "Setup Checklist", 7, _DB_MUTED(), "Segoe UI");

    // Row E – HTF Alignment (Y=176)
    int htfState = (state.biasDir=="NO TRADE —") ? -1 : 1;
    _DB_Dot("DTRD_CL_HTF_IND", X+DTR_DB_IND_X, Y+176, htfState);
    _DB_Label("DTRD_CL_HTF_LBL", X+DTR_DB_INDENT+10, Y+178, "HTF Alignment", 8, _DB_TEXT());
    _DB_Label("DTRD_CL_HTF_VAL", X+DTR_DB_W-DTR_DB_INDENT-60, Y+178, state.biasDir, 8, biasClr);

    // Row F – Range Sweep (Y=196)
    _DB_Dot("DTRD_CL_SWP_IND", X+DTR_DB_IND_X, Y+196, state.sweepState);
    _DB_Label("DTRD_CL_SWP_LBL", X+DTR_DB_INDENT+10, Y+198, "Range Sweep", 8, _DB_TEXT());
    string swpVal = (state.sweepState==1) ? state.sweepDetail : "Awaiting…";
    color  swpClr = (state.sweepState==1) ? _DB_GREEN() : _DB_MUTED();
    _DB_Label("DTRD_CL_SWP_VAL", X+DTR_DB_W-DTR_DB_INDENT-80, Y+198, swpVal, 8, swpClr);

    // Row G – Confluence Gate (conditional, Y=216)
    int clBaseY = 216;
    if(state.gateMode > 0)
    {
        string gateLbl = (state.gateMode==1) ? "Session Confluence" : "Daily Confluence";
        string gateVal;
        color  gateClr;
        int    gateIndSt = state.gateState;
        if(state.gateState==0)        { gateVal="Awaiting sweep…";   gateClr=_DB_MUTED();  }
        else if(state.gateState==1)   { gateVal=state.gateDetail;    gateClr=_DB_GREEN();  }
        else if(state.gateState==2)   { gateVal=state.gateDetail;    gateClr=_DB_ACCENT(); }
        else /* -2 */                 { gateVal="Blocking entry!";   gateClr=_DB_RED(); gateIndSt=-2; }
        _DB_Dot("DTRD_CL_GATE_IND", X+DTR_DB_IND_X, Y+216, gateIndSt);
        _DB_Label("DTRD_CL_GATE_LBL", X+DTR_DB_INDENT+10, Y+218, gateLbl,  8, _DB_TEXT());
        _DB_Label("DTRD_CL_GATE_VAL", X+DTR_DB_W-DTR_DB_INDENT-100, Y+218, gateVal, 8, gateClr);
        clBaseY = 236;
    }
    else
    {
        // Park gate row off-canvas when not needed
        _DB_Park("DTRD_CL_GATE_IND");
        _DB_Park("DTRD_CL_GATE_LBL");
        _DB_Park("DTRD_CL_GATE_VAL");
    }

    // Row H – CISD
    _DB_Dot("DTRD_CL_CISD_IND", X+DTR_DB_IND_X, Y+clBaseY, state.cisdState);
    _DB_Label("DTRD_CL_CISD_LBL", X+DTR_DB_INDENT+10, Y+clBaseY+2, "CISD", 8, _DB_TEXT());
    string cisdVal = (state.cisdState==1) ? ("Confirmed  " + state.cisdDetail) : "Awaiting…";
    color  cisdClr = (state.cisdState==1) ? _DB_GREEN() : _DB_MUTED();
    _DB_Label("DTRD_CL_CISD_VAL", X+DTR_DB_W-DTR_DB_INDENT-100, Y+clBaseY+2, cisdVal, 8, cisdClr);

    // Row I – Entry Trigger
    int trgY = clBaseY + DTR_DB_ROW_H;
    color trgClr = (state.triggerState==0) ? _DB_MUTED()
                 : (state.triggerState==1) ? _DB_ACCENT()
                 : _DB_GREEN();
    int trgIndSt = (state.triggerState==2) ? 1 : state.triggerState; // map 2->fired->green dot
    _DB_Dot("DTRD_CL_TRG_IND", X+DTR_DB_IND_X, Y+trgY, trgIndSt);
    _DB_Label("DTRD_CL_TRG_LBL", X+DTR_DB_INDENT+10, Y+trgY+2, "Entry · " + state.entryModel, 8, _DB_TEXT());
    string trgVal = (state.triggerState==0 || state.triggerDetail=="") ? "Awaiting…" : state.triggerDetail;
    _DB_Label("DTRD_CL_TRG_VAL", X+DTR_DB_W-DTR_DB_INDENT-100, Y+trgY+2, trgVal, 8, trgClr);

    // Dynamic bottom position for side footer and trade block
    int g_clY    = clBaseY + DTR_DB_ROW_H;
    int g_tradeY = g_clY + 20 + 22; // after trigger + divider

    // 5.8 Trade block (conditional)
    if(state.inTrade)
    {
        _DB_Rect("DTRD_DIV4", X, Y+g_clY+20, DTR_DB_W, 1, _DB_BORDER(), _DB_BORDER());

        color dirClr = (state.tradeDir=="LONG") ? _DB_GREEN() : _DB_RED();
        _DB_Label("DTRD_TR_DIR",   X+DTR_DB_INDENT, Y+g_tradeY,    state.tradeDir, 9, dirClr);
        _DB_Label("DTRD_TR_MODEL", X+DTR_DB_INDENT+40, Y+g_tradeY, "· " + state.entryModel + " · " + state.slMode + " SL", 8, _DB_MUTED());

        string epx = (state.entryPx > 0) ? DoubleToString(state.entryPx, _Digits) : "--";
        string spx = (state.slPx    > 0) ? DoubleToString(state.slPx,    _Digits) : "--";
        string tpx = (state.tpPx    > 0) ? DoubleToString(state.tpPx,    _Digits) : "--";
        _DB_Label("DTRD_TR_PX", X+DTR_DB_INDENT, Y+g_tradeY+20,
                  "E: "+epx+"  SL: "+spx+"  TP: "+tpx, 7, _DB_MUTED(), "Consolas");

        string rrText;
        color  rrClr;
        if(state.liveRR <= 0)      { rrText="Live RR: —";                                        rrClr=_DB_RED();   }
        else if(state.liveRR < 1)  { rrText=StringFormat("Live RR: %.1fR", state.liveRR);        rrClr=_DB_AMBER(); }
        else if(state.liveRR >= Inp_MinRR) { rrText=StringFormat("Live RR: %.1fR", state.liveRR); rrClr=_DB_GREEN(); }
        else                       { rrText=StringFormat("Live RR: %.1fR", state.liveRR);        rrClr=_DB_TEXT();  }
        _DB_Label("DTRD_TR_RR", X+DTR_DB_INDENT, Y+g_tradeY+40, rrText, 8, rrClr);

        string beText = (state.beState==0) ? ("BE pending  " + state.beDetail)
                                           : ("BE activated  " + state.beDetail);
        color  beClr  = (state.beState==1) ? _DB_GREEN() : _DB_MUTED();
        _DB_Label("DTRD_TR_BE", X+DTR_DB_INDENT, Y+g_tradeY+60, beText, 8, beClr);
    }
    else
    {
        _DB_Park("DTRD_DIV4");
        _DB_Park("DTRD_TR_DIR"); _DB_Park("DTRD_TR_MODEL");
        _DB_Park("DTRD_TR_PX"); _DB_Park("DTRD_TR_RR"); _DB_Park("DTRD_TR_BE");
    }

    // 5.10 Side footer
    int sideY = state.inTrade ? (g_tradeY + 80 + 4) : (g_clY + 24);
    int sideIndSt = state.sideConsumed ? 1 : 0;
    color sideValClr;
    string sideValText;
    if(!state.sideConsumed)            { sideValText="Available";             sideValClr=_DB_GREEN(); sideIndSt=0; }
    else if(state.consumedResult=="Won")  { sideValText="Consumed  Won ✓";    sideValClr=_DB_GREEN(); }
    else if(state.consumedResult=="Lost") { sideValText="Consumed  Lost";     sideValClr=_DB_RED();   }
    else                               { sideValText="Consumed  Break-Even"; sideValClr=_DB_MUTED(); }

    _DB_Dot("DTRD_SIDE_IND", X+DTR_DB_IND_X, Y+sideY, sideIndSt);
    _DB_Label("DTRD_SIDE_LBL", X+DTR_DB_INDENT+10, Y+sideY+2, "Side", 8, _DB_TEXT());
    _DB_Label("DTRD_SIDE_VAL", X+DTR_DB_W-DTR_DB_INDENT-100, Y+sideY+2, sideValText, 8, sideValClr);

    ChartRedraw(0);
}

#endif // DTR_UI_MQH

