#ifndef CRT_DASHBOARD_MQH
#define CRT_DASHBOARD_MQH

//======================================================================
// CRT_Dashboard.mqh — Pixel-buffer dashboard for CRT EA (MQL5).
//
// Modelled on CCT_Dashboard.mqh (pixel-buffer pattern, DashPalette,
// pixel-push Px() helpers) but repurposed for CRT state:
//   • Header bar: symbol + NY clock + phase
//   • Row 1: C1 High / Low / EQ
//   • Row 2: Sweep direction + bias
//   • Row 3: CISD / IFVG status
//   • Row 4: Entry / SL / TP
//   • Row 5: Lots / risk / daily P&L
//   • Row 6: News / hour-filter status
//   • Footer: session key + trades today
//
// Uses MQL5 Chart Object (OBJ_BITMAP_LABEL) + ResourceCreate to push
// the pixel buffer onto the chart — the same technique as CCT.
// Inputs: Inp_ShowDashboard, Inp_DashTheme (declared in CRT_EA.mq5).
//======================================================================

#include "CRT_Globals.mqh"
#include "CRT_Time.mqh"

extern bool              Inp_ShowDashboard;
extern ENUM_CRT_DASH_THEME Inp_DashTheme;

//----------------------------------------------------------------------
// Dashboard dimensions (same proportions as CCT — proven layout)
//----------------------------------------------------------------------
#define CRTD_W       400
#define CRTD_H       380
#define CRTD_BAR_H    38
#define CRTD_PAD       8
#define CRTD_ROW_H    32
#define CRTD_OBJ_NAME "CRTD_PANEL"

uint g_crtDashPixels[CRTD_W * CRTD_H];
int  g_crtDashX = 14;
int  g_crtDashY = 20;
bool g_crtDashInit = false;

//----------------------------------------------------------------------
// Palette
//----------------------------------------------------------------------
struct CrtDashPalette
{
    color bg;       // panel background
    color bar;      // header/section bar
    color text;     // primary text
    color muted;    // secondary / label text
    color accent;   // cyan highlight (values)
    color good;     // green (TP, long, armed)
    color warn;     // amber (working limit, caution)
    color bad;      // red (SL, short, news block)
    color border;   // outer border
};

CrtDashPalette CrtBuildPalette()
{
    CrtDashPalette p;
    if (Inp_DashTheme == CRT_DASH_DIM_LIGHT)
    {
        p.bg      = C'235,237,242';
        p.bar     = C'200,205,215';
        p.text    = C'30,35,50';
        p.muted   = C'100,110,130';
        p.accent  = C'0,100,200';
        p.good    = C'20,140,80';
        p.warn    = C'180,130,0';
        p.bad     = C'180,40,40';
        p.border  = C'150,155,165';
    }
    else // Dark (default)
    {
        p.bg      = C'18,22,34';
        p.bar     = C'28,34,52';
        p.text    = C'220,225,240';
        p.muted   = C'110,120,145';
        p.accent  = C'80,190,230';
        p.good    = C'50,210,120';
        p.warn    = C'230,180,40';
        p.bad     = C'220,60,75';
        p.border  = C'55,65,90';
    }
    return p;
}

//----------------------------------------------------------------------
// Low-level pixel helpers
//----------------------------------------------------------------------
uint CrtDA(color c, int alpha = 255)
{
    return ColorToARGB(c, (uchar)MathMax(0, MathMin(255, alpha)));
}

void CrtPx(int x, int y, uint clr)
{
    if (x < 0 || x >= CRTD_W || y < 0 || y >= CRTD_H) return;
    g_crtDashPixels[y * CRTD_W + x] = clr;
}

void CrtFill(int x0, int y0, int w, int h, uint clr)
{
    for (int y = y0; y < y0 + h; y++)
        for (int x = x0; x < x0 + w; x++)
            CrtPx(x, y, clr);
}

void CrtHLine(int y, int x0, int x1, uint clr)
{
    for (int x = x0; x <= x1; x++) CrtPx(x, y, clr);
}

void CrtVLine(int x, int y0, int y1, uint clr)
{
    for (int y = y0; y <= y1; y++) CrtPx(x, y, clr);
}

void CrtRect(int x, int y, int w, int h, uint clr)
{
    CrtHLine(y,     x, x + w - 1, clr);
    CrtHLine(y + h - 1, x, x + w - 1, clr);
    CrtVLine(x,     y, y + h - 1, clr);
    CrtVLine(x + w - 1, y, y + h - 1, clr);
}

// Draw text via the chart-label object overlay (positioned absolutely).
// This is the reliable MQL5 text-over-bitmap technique: we place
// OBJ_LABEL objects aligned with the bitmap panel rather than
// pixel-rendering fonts ourselves (which is fragile in MQL5).
void CrtDashLabel(const string name, const string text, int x, int y,
                  color clr, int fontSize = 8, bool bold = false)
{
    string fullName = "CRTD_LBL_" + name;
    if (ObjectFind(0, fullName) < 0)
    {
        ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, fullName, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(0, fullName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    }
    ObjectSetString(0,  fullName, OBJPROP_TEXT,      text);
    ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, g_crtDashX + x);
    ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, g_crtDashY + y);
    ObjectSetInteger(0, fullName, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE,  fontSize);
    ObjectSetString(0,  fullName, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
}

void CrtDashDeleteLabels()
{
    for (int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string n = ObjectName(0, i);
        if (StringFind(n, "CRTD_LBL_") == 0)
            ObjectDelete(0, n);
    }
}

//----------------------------------------------------------------------
// State snapshot pushed by the EA each tick / bar close.
//----------------------------------------------------------------------
struct CrtDashState
{
    string slotLabel;
    string nyClock;
    string phase;
    string bias;
    string sweepSide;
    double c1High, c1Low, c1EQ;
    string cisdStatus;
    string ifvgStatus;
    string triggerModel;
    bool   inTrade;
    string tradeDir;
    double entryPrice;
    double slPrice;
    double tpPrice;
    double lots;
    double sessionPnL;
    int    tradesToday;
    int    maxTradesDay;
    bool   newsBlocked;
    bool   hourFiltered;
    string sessionKey;
    double balance;
    string entryInfo;   // "market @ X.XX" or "limit @ X.XX"
};

CrtDashState g_crtDashState;

void CrtDashPublish(const CrtDashState &st)
{
    g_crtDashState = st;
}

//----------------------------------------------------------------------
// Render the dashboard to the pixel buffer and push it to the chart.
//----------------------------------------------------------------------
void CrtDashRender()
{
    if (!Inp_ShowDashboard) return;
    if ((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) return;

    CrtDashPalette p = CrtBuildPalette();
    CrtDashState   st = g_crtDashState;

    // Background + border
    CrtFill(0, 0, CRTD_W, CRTD_H, CrtDA(p.bg));
    CrtRect(0, 0, CRTD_W, CRTD_H, CrtDA(p.border));

    // Header bar
    CrtFill(1, 1, CRTD_W - 2, CRTD_BAR_H - 2, CrtDA(p.bar));
    CrtHLine(CRTD_BAR_H - 1, 1, CRTD_W - 2, CrtDA(p.border));

    // Divider lines between sections
    int divY[] = {CRTD_BAR_H + CRTD_ROW_H,
                  CRTD_BAR_H + CRTD_ROW_H * 2,
                  CRTD_BAR_H + CRTD_ROW_H * 3,
                  CRTD_BAR_H + CRTD_ROW_H * 4,
                  CRTD_BAR_H + CRTD_ROW_H * 5,
                  CRTD_BAR_H + CRTD_ROW_H * 6};
    for (int k = 0; k < 6; k++)
        CrtHLine(divY[k], CRTD_PAD, CRTD_W - CRTD_PAD, CrtDA(p.border, 120));

    // Push pixel buffer to chart resource
    string resName = "::CRTD_BMP_" + IntegerToString((long)ChartID());
    if (!ResourceCreate(resName, g_crtDashPixels, CRTD_W, CRTD_H, 0, 0, CRTD_W, COLOR_FORMAT_ARGB_NORMALIZE))
        return;

    // Create or update the bitmap label object
    if (!g_crtDashInit || ObjectFind(0, CRTD_OBJ_NAME) < 0)
    {
        if (ObjectFind(0, CRTD_OBJ_NAME) >= 0)
            ObjectDelete(0, CRTD_OBJ_NAME);
        ObjectCreate(0, CRTD_OBJ_NAME, OBJ_BITMAP_LABEL, 0, 0, 0);
        ObjectSetInteger(0, CRTD_OBJ_NAME, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, CRTD_OBJ_NAME, OBJPROP_XDISTANCE,  g_crtDashX);
        ObjectSetInteger(0, CRTD_OBJ_NAME, OBJPROP_YDISTANCE,  g_crtDashY);
        ObjectSetInteger(0, CRTD_OBJ_NAME, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, CRTD_OBJ_NAME, OBJPROP_HIDDEN,     true);
        g_crtDashInit = true;
    }
    ObjectSetString(0, CRTD_OBJ_NAME, OBJPROP_BMPFILE, resName);

    // ── Text labels ───────────────────────────────────────────────────
    // Header
    int headerMid = CRTD_BAR_H / 2 - 5;
    CrtDashLabel("title",  "CRT  " + _Symbol + "  " + st.slotLabel,
                 CRTD_PAD, headerMid, p.text, 9, true);
    CrtDashLabel("clock",  st.nyClock,
                 CRTD_W - 100, headerMid, p.muted, 8);

    // Phase + bias
    color phaseClr = (st.bias == "LONG") ? p.good : (st.bias == "SHORT") ? p.bad : p.muted;
    int   rowBase  = CRTD_BAR_H + 4;
    CrtDashLabel("phase",  "Phase: " + st.phase,  CRTD_PAD, rowBase, p.accent, 8);
    CrtDashLabel("bias",   "Bias: "  + st.bias,   CRTD_W / 2, rowBase, phaseClr, 8, true);

    // C1 levels
    rowBase += CRTD_ROW_H;
    CrtDashLabel("c1h",  "C1 H: " + DoubleToString(st.c1High, _Digits), CRTD_PAD,     rowBase, p.text, 8);
    CrtDashLabel("c1l",  "C1 L: " + DoubleToString(st.c1Low,  _Digits), CRTD_W / 2,  rowBase, p.text, 8);
    rowBase += 14;
    CrtDashLabel("c1eq", "EQ (50%): " + DoubleToString(st.c1EQ, _Digits), CRTD_PAD,  rowBase, p.accent, 8);

    // Sweep + confirm
    rowBase += CRTD_ROW_H;
    CrtDashLabel("sweep", "Sweep: " + st.sweepSide, CRTD_PAD,    rowBase, p.warn, 8);
    CrtDashLabel("trig",  "Model: " + st.triggerModel, CRTD_W / 2, rowBase, p.muted, 8);
    rowBase += 14;
    CrtDashLabel("cisd",  "CISD: " + st.cisdStatus, CRTD_PAD,    rowBase, p.accent, 8);
    CrtDashLabel("ifvg",  "IFVG: " + st.ifvgStatus, CRTD_W / 2,  rowBase, p.accent, 8);

    // Entry info
    rowBase += CRTD_ROW_H;
    color entryClr = st.inTrade ? phaseClr : p.muted;
    CrtDashLabel("entry", "Entry: " + st.entryInfo, CRTD_PAD, rowBase, entryClr, 8, st.inTrade);
    rowBase += 14;
    CrtDashLabel("sl",  "SL: " + DoubleToString(st.slPrice, _Digits),  CRTD_PAD,    rowBase, p.bad, 8);
    CrtDashLabel("tp",  "TP: " + DoubleToString(st.tpPrice, _Digits),  CRTD_W / 2,  rowBase, p.good, 8);

    // Lots + PnL
    rowBase += CRTD_ROW_H;
    CrtDashLabel("lots",   "Lots: "  + DoubleToString(st.lots, 2),       CRTD_PAD,   rowBase, p.text, 8);
    string pnlSign = (st.sessionPnL >= 0.0) ? "+" : "";
    CrtDashLabel("pnl",    "PnL: "   + pnlSign + DoubleToString(st.sessionPnL, 2),
                 CRTD_W / 2, rowBase, (st.sessionPnL >= 0.0 ? p.good : p.bad), 8);

    // Guards
    rowBase += CRTD_ROW_H;
    string newsStr = st.newsBlocked ? "BLOCKED" : "OK";
    color  newsClr = st.newsBlocked ? p.bad : p.good;
    CrtDashLabel("news",   "News: "  + newsStr,               CRTD_PAD,  rowBase, newsClr, 8);
    CrtDashLabel("trades", "Trades: " + IntegerToString(st.tradesToday) +
                 "/" + IntegerToString(st.maxTradesDay),       CRTD_W / 2, rowBase, p.muted, 8);

    // Footer
    rowBase += CRTD_ROW_H;
    CrtDashLabel("key",  st.sessionKey, CRTD_PAD,    rowBase, p.muted, 7);
    CrtDashLabel("bal",  "Bal: " + DoubleToString(st.balance, 2), CRTD_W / 2, rowBase, p.muted, 7);

    ChartRedraw(0);
}

void CrtDashClear()
{
    ObjectDelete(0, CRTD_OBJ_NAME);
    CrtDashDeleteLabels();
    g_crtDashInit = false;
    ChartRedraw(0);
}

#endif // CRT_DASHBOARD_MQH
