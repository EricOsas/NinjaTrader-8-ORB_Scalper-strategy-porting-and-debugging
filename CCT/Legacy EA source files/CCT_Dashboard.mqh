//+------------------------------------------------------------------+
//| CCT_Dashboard.mqh  v7.0                                          |
//| Two-panel retained-object dashboard.                             |
//|   DB1 — Signal panel (POI · C-sequence · live trade)            |
//|   DB2 — Position sizer (risk · lot · account · session)         |
//+------------------------------------------------------------------+
#ifndef CCT_DASHBOARD_MQH
#define CCT_DASHBOARD_MQH

#include "CCT_Globals.mqh"

// Forward declarations (defined in CCT_Execution.mqh)
bool ResolveTradeState(string genKey,SIB_STATE &outState,datetime &outExitTime,double &outExitPrice);
bool HasOpenCCTPositionForGenKey(string genKey);
double EstimateCashLossPerLot(const string symbol,double entry,double sl);

//══════════════════════════════════════════════════════════════════
//  PALETTE
//══════════════════════════════════════════════════════════════════
#define C_BG          ((color)C'12,14,22')
#define C_HDR         ((color)C'18,22,34')
#define C_FIELD       ((color)C'20,24,36')
#define C_FIELD2      ((color)C'26,30,44')
#define C_BORDER      ((color)C'42,50,72')
#define C_SEP         ((color)C'52,60,82')
#define C_TXT         ((color)C'210,216,228')
#define C_DIM         ((color)C'100,110,132')
#define C_SUB         ((color)C'130,140,162')
#define C_BLUE        ((color)C'88,148,248')
#define C_GREEN       ((color)C'72,186,112')
#define C_RED         ((color)C'206,82,82')
#define C_AMBER       ((color)C'206,170,80')
#define C_TEAL        ((color)C'38,196,196')
#define C_C1_OFF_BG   ((color)C'70,18,18')
#define C_C1_OFF_TX   ((color)C'196,58,58')
#define C_C1_ON_BG    ((color)C'18,74,38')
#define C_C1_ON_TX    ((color)C'58,196,100')
#define C_WAIT_BG     ((color)C'56,46,8')
#define C_WAIT_TX     ((color)C'154,134,38')
#define C_TEAL_BG     ((color)C'8,66,66')
#define C_TEAL_TX     ((color)C'38,194,194')

//══════════════════════════════════════════════════════════════════
//  PREFIXES & GV KEYS
//══════════════════════════════════════════════════════════════════
#define DASH_PFX  "CCTD_"
#define D1_PFX    "CCTD_1_"
#define D2_PFX    "CCTD_2_"
#define GV_X      "CCT_DASH_X"
#define GV_Y      "CCT_DASH_Y"
#define GV_COL1   "CCT_DASH_1COL"
#define GV_COL2   "CCT_DASH_2COL"
#define GV_RISK   "CCT_RPCT"
#define GV_AMOD   "CCT_AMODE"
#define GV_CBAL   "CCT_CBAL"

//══════════════════════════════════════════════════════════════════
//  LAYOUT CONSTANTS  (all in pixels)
//══════════════════════════════════════════════════════════════════
#define R_HDR   20
#define R_ROW   18
#define R_CBOX  20
#define R_SEP    5
#define R_GAP    3
#define PANEL_W 218
#define PAD       8

// DB1 body height (computed manually from rows below):
// SIG(18)+gap + POI(18)+gap + CBOX(20)+gap + sep(1)+gap
// + DIR(18)+gap + SLTP(18)+gap + PROG(18)+gap + PNL(18)+gap + STAT(18)+4pad
#define DB1_BH  (18+3+18+3+20+3+1+3+18+3+18+3+18+3+18+3+18+4)  // = 178

// DB2 body height:
// TIME(18)+g + DATE(18)+g + SESS(18)+g + MDL(18)+g
// + sep(1)+g + RISK row(18)+g + BTNS(18)+g + BAL(18)+g + EQ(18)+g + CST(18)+g
// + sep(1)+g + SLP(18)+g + LOT(18)+4pad
#define DB2_BH  (18+3+18+3+18+3+18+3+1+3+18+3+18+3+18+3+18+3+18+3+1+3+18+3+18+4) // = 229

//══════════════════════════════════════════════════════════════════
//  STATE
//══════════════════════════════════════════════════════════════════
struct PanelSt { int x,y,w,hh,bh; bool col; };

PanelSt g_db1={16,32,PANEL_W,R_HDR,DB1_BH,false};
PanelSt g_db2={16, 0,PANEL_W,R_HDR,DB2_BH,false};

bool g_dashInit=false;
bool g_dragging=false, g_anyDrag=false;
int  g_dragPanel=0, g_dox=0, g_doy=0;

// last-trigger cache (today only)
string    g_ltKey="";   bool   g_ltBull=true;
datetime  g_ltTime=0;   double g_ltLv=0,g_ltSl=0,g_ltTp=0;
SIB_STATE g_ltSt=SS_UNKNOWN_OUTCOME;

// body registries
string g_r1[]; int g_n1=0;
string g_r2[]; int g_n2=0;

//══════════════════════════════════════════════════════════════════
//  WRITE-THROUGH GUARDS
//══════════════════════════════════════════════════════════════════
bool dsi(const string n,ENUM_OBJECT_PROPERTY_INTEGER p,long v)
  { if(ObjectFind(0,n)<0)return false; if(ObjectGetInteger(0,n,p)==v)return false;
    return ObjectSetInteger(0,n,p,v); }
bool dss(const string n,ENUM_OBJECT_PROPERTY_STRING p,const string v)
  { if(ObjectFind(0,n)<0)return false; if(ObjectGetString(0,n,p)==v)return false;
    return ObjectSetString(0,n,p,v); }

//══════════════════════════════════════════════════════════════════
//  PRIMITIVES
//══════════════════════════════════════════════════════════════════
void _cmn(const string n,int x,int y,int w,int h,long z)
  { dsi(n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    dsi(n,OBJPROP_XDISTANCE,x); dsi(n,OBJPROP_YDISTANCE,y);
    dsi(n,OBJPROP_XSIZE,w);     dsi(n,OBJPROP_YSIZE,h);
    dsi(n,OBJPROP_ZORDER,z);    dsi(n,OBJPROP_BACK,false);
    dsi(n,OBJPROP_SELECTABLE,false); dsi(n,OBJPROP_HIDDEN,true);
    dsi(n,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
    dss(n,OBJPROP_TOOLTIP,"\n"); }

void _rect(const string n,int x,int y,int w,int h,color bg,color brd,long z)
  { if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
    _cmn(n,x,y,w,h,z);
    dsi(n,OBJPROP_BGCOLOR,bg); dsi(n,OBJPROP_BORDER_COLOR,brd); dsi(n,OBJPROP_COLOR,brd); }

void _edit(const string n,int x,int y,int w,int h,const string txt,
           bool ro,color bg,color brd,color clr,ENUM_ALIGN_MODE al,long z)
  { if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_EDIT,0,0,0);
    _cmn(n,x,y,w,h,z);
    dsi(n,OBJPROP_BGCOLOR,bg); dsi(n,OBJPROP_BORDER_COLOR,brd); dsi(n,OBJPROP_COLOR,clr);
    dsi(n,OBJPROP_READONLY,ro); dsi(n,OBJPROP_ALIGN,al);
    dsi(n,OBJPROP_FONTSIZE,8); dss(n,OBJPROP_FONT,"Courier New"); dss(n,OBJPROP_TEXT,txt); }

void _lbl(const string n,int x,int y,int w,int h,const string txt,color clr,long z)
  { if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_LABEL,0,0,0);
    _cmn(n,x,y,w,h,z);
    dsi(n,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER); dsi(n,OBJPROP_FONTSIZE,8);
    dss(n,OBJPROP_FONT,"Courier New"); dsi(n,OBJPROP_COLOR,clr);
    dss(n,OBJPROP_TEXT,txt); dsi(n,OBJPROP_ALIGN,ALIGN_LEFT); }

void _btn(const string n,int x,int y,int w,int h,const string txt,color bg,color clr,long z)
  { if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_BUTTON,0,0,0);
    _cmn(n,x,y,w,h,z);
    dsi(n,OBJPROP_BGCOLOR,bg); dsi(n,OBJPROP_BORDER_COLOR,C_BORDER); dsi(n,OBJPROP_COLOR,clr);
    dsi(n,OBJPROP_FONTSIZE,8); dss(n,OBJPROP_FONT,"Courier New"); dss(n,OBJPROP_TEXT,txt); }

void _vis(const string n,bool v)
  { if(ObjectFind(0,n)>=0)dsi(n,OBJPROP_TIMEFRAMES,v?OBJ_ALL_PERIODS:0); }

void _reg(bool d1,const string n)
  { if(d1){ for(int i=0;i<g_n1;i++)if(g_r1[i]==n)return;
             ArrayResize(g_r1,g_n1+1);g_r1[g_n1++]=n;return;}
    for(int i=0;i<g_n2;i++)if(g_r2[i]==n)return;
    ArrayResize(g_r2,g_n2+1);g_r2[g_n2++]=n; }

void _showBody(bool d1,bool v)
  { if(d1){for(int i=0;i<g_n1;i++)_vis(g_r1[i],v);return;}
    for(int i=0;i<g_n2;i++)_vis(g_r2[i],v); }

void _clrReg(){ ArrayResize(g_r1,0);g_n1=0;ArrayResize(g_r2,0);g_n2=0; }

//══════════════════════════════════════════════════════════════════
//  PERSISTENCE
//══════════════════════════════════════════════════════════════════
void DBLoad()
  { if(GlobalVariableCheck(GV_RISK))g_riskPct=GlobalVariableGet(GV_RISK);
    if(GlobalVariableCheck(GV_AMOD))g_accMode=(int)GlobalVariableGet(GV_AMOD);
    if(GlobalVariableCheck(GV_CBAL))g_custBal=GlobalVariableGet(GV_CBAL);
    if(GlobalVariableCheck(GV_X))   g_db1.x=(int)GlobalVariableGet(GV_X);
    if(GlobalVariableCheck(GV_Y))   g_db1.y=(int)GlobalVariableGet(GV_Y);
    if(GlobalVariableCheck(GV_COL1))g_db1.col=(GlobalVariableGet(GV_COL1)>0.5);
    if(GlobalVariableCheck(GV_COL2))g_db2.col=(GlobalVariableGet(GV_COL2)>0.5); }

void DBSave()
  { GlobalVariableSet(GV_RISK,g_riskPct); GlobalVariableSet(GV_AMOD,g_accMode);
    GlobalVariableSet(GV_CBAL,g_custBal); GlobalVariableSet(GV_X,g_db1.x);
    GlobalVariableSet(GV_Y,g_db1.y);
    GlobalVariableSet(GV_COL1,g_db1.col?1.0:0.0);
    GlobalVariableSet(GV_COL2,g_db2.col?1.0:0.0); }

//══════════════════════════════════════════════════════════════════
//  FORMAT HELPERS
//══════════════════════════════════════════════════════════════════
string _sfx(int d){ int m=d%100; if(m>=11&&m<=13)return "th";
  switch(d%10){case 1:return "st";case 2:return "nd";case 3:return "rd";}return "th";}
string _mon(int m){ string a[]={"","Jan","Feb","Mar","Apr","May","Jun",
                                  "Jul","Aug","Sep","Oct","Nov","Dec"};
  return(m>=1&&m<=12)?a[m]:""; }
string _dow(int d){ string a[]={"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
  return(d>=0&&d<=6)?a[d]:""; }
string FmtDate(datetime t)
  { MqlDateTime dt;TimeToStruct(t,dt);
    return StringFormat("%s %d%s %s %d",_dow(dt.day_of_week),dt.day,_sfx(dt.day),_mon(dt.mon),dt.year); }
string FmtBar(double pct)
  { int n=(int)MathRound(MathMin(100.0,MathAbs(pct))/12.5); if(n<0)n=0;if(n>8)n=8;
    string b="[";for(int i=0;i<8;i++)b+=(i<n)?"#":".";b+="]";
    return b+" "+(pct>=0?"+":"")+DoubleToString(pct,1)+"%"; }
double _pct(bool buy,double en,double sl,double tp,double cur)
  { if(buy){if(cur>=en&&tp>en)return MathMin(100.0,(cur-en)/(tp-en)*100.0);
             if(cur<en&&en>sl)return MathMax(-100.0,(cur-en)/(en-sl)*100.0);}
    else  { if(cur<=en&&tp<en)return MathMin(100.0,(en-cur)/(en-tp)*100.0);
             if(cur>en&&en<sl)return MathMax(-100.0,(en-cur)/(sl-en)*100.0);}
    return 0.0; }
color _stClr(SIB_STATE st,bool bull)
  { if(st==SS_TP_HIT)return C_GREEN;if(st==SS_SL_HIT)return C_RED;
    if(st==SS_BE_HIT)return C_AMBER;return bull?C_GREEN:C_RED; }

//══════════════════════════════════════════════════════════════════
//  CLAMP
//══════════════════════════════════════════════════════════════════
void _clamp()
  { int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
    int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
    if(cw<=0||ch<=0)return;
    int h1=g_db1.hh+(g_db1.col?0:g_db1.bh);
    int h2=g_db2.hh+(g_db2.col?0:g_db2.bh);
    if(g_db1.x<0)g_db1.x=0; if(g_db1.y<20)g_db1.y=20;
    if(g_db1.x+g_db1.w>cw)g_db1.x=MathMax(0,cw-g_db1.w);
    if(g_db1.y+h1+4+h2>ch)g_db1.y=MathMax(20,ch-h1-4-h2);
    g_db2.x=g_db1.x; g_db2.y=g_db1.y+h1+4; }

bool _inHdr(const PanelSt &p,int mx,int my)
  { return(mx>=p.x&&mx<=p.x+p.w&&my>=p.y&&my<=p.y+p.hh); }

//══════════════════════════════════════════════════════════════════
//  LAYOUT
//══════════════════════════════════════════════════════════════════
void DBLayout()
  {
   _clamp();
   const int iw=PANEL_W-2*PAD;
   const long Z=205000001;

   int h1f=g_db1.hh+(g_db1.col?0:g_db1.bh);
   int h2f=g_db2.hh+(g_db2.col?0:g_db2.bh);

   //── DB1 shell ───────────────────────────────────────────────────
   _rect(D1_PFX+"BG",  g_db1.x,g_db1.y,PANEL_W,h1f,C_BG,C_BORDER,Z);
   _rect(D1_PFX+"HDR", g_db1.x,g_db1.y,PANEL_W,R_HDR,C_HDR,C_BORDER,Z+1);
   _lbl( D1_PFX+"HTXT",g_db1.x+PAD,g_db1.y+4,PANEL_W-56,14,"Signal / Trade",C_TXT,Z+2);
   _btn( D1_PFX+"COL",
         g_db1.x+PANEL_W-(g_db1.col?44:22),g_db1.y+2,
         g_db1.col?42:20,16, g_db1.col?"+":"−", C_FIELD,C_TXT,Z+2);

   //── DB1 body rows ───────────────────────────────────────────────
   int y=g_db1.y+R_HDR+R_GAP;

   _edit(D1_PFX+"SIG",g_db1.x+PAD,y,iw,R_ROW,"SIGNAL",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"SIG"); y+=R_ROW+R_GAP;

   _edit(D1_PFX+"POI",g_db1.x+PAD,y,iw,R_ROW,"--",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"POI"); y+=R_ROW+R_GAP;

   // C1 / C2 / C3  — three equal boxes filling inner width
   { int cw3=(iw-4)/3;
     for(int ci=0;ci<3;ci++)
       { string ix=IntegerToString(ci+1);
         int bx=g_db1.x+PAD+ci*(cw3+2);
         _rect(D1_PFX+"C"+ix+"B",bx,y,cw3,R_CBOX,C_C1_OFF_BG,C_BORDER,Z+2);
         _lbl( D1_PFX+"C"+ix+"T",bx+2,y+4,cw3-4,12,"C"+ix,C_C1_OFF_TX,Z+3);
         _reg(true,D1_PFX+"C"+ix+"B"); _reg(true,D1_PFX+"C"+ix+"T"); }
   } y+=R_CBOX+R_GAP;

   _rect(D1_PFX+"SEP",g_db1.x+PAD,y,iw,1,C_SEP,C_SEP,Z+2);
   _reg(true,D1_PFX+"SEP"); y+=1+R_GAP;

   _edit(D1_PFX+"DIR", g_db1.x+PAD,y,iw,R_ROW,"--",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"DIR"); y+=R_ROW+R_GAP;
   _edit(D1_PFX+"SLTP",g_db1.x+PAD,y,iw,R_ROW,"SL --   TP --",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"SLTP"); y+=R_ROW+R_GAP;
   _edit(D1_PFX+"PROG",g_db1.x+PAD,y,iw,R_ROW,"[........] +0.0%",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"PROG"); y+=R_ROW+R_GAP;
   _edit(D1_PFX+"PNL", g_db1.x+PAD,y,iw,R_ROW,"--",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"PNL"); y+=R_ROW+R_GAP;
   _edit(D1_PFX+"STAT",g_db1.x+PAD,y,iw,R_ROW,"Trades: 0   Sprd: 0p",true,C_FIELD,C_BORDER,C_SUB,ALIGN_LEFT,Z+2);
   _reg(true,D1_PFX+"STAT");

   //── DB2 shell ───────────────────────────────────────────────────
   _rect(D2_PFX+"BG",  g_db2.x,g_db2.y,PANEL_W,h2f,C_BG,C_BORDER,Z);
   _rect(D2_PFX+"HDR", g_db2.x,g_db2.y,PANEL_W,R_HDR,C_HDR,C_BORDER,Z+1);
   _lbl( D2_PFX+"HTXT",g_db2.x+PAD,g_db2.y+4,PANEL_W-56,14,"Position Sizer",C_TXT,Z+2);
   _btn( D2_PFX+"COL",
         g_db2.x+PANEL_W-(g_db2.col?44:22),g_db2.y+2,
         g_db2.col?42:20,16, g_db2.col?"+":"−", C_FIELD,C_TXT,Z+2);

   //── DB2 body rows ───────────────────────────────────────────────
   y=g_db2.y+R_HDR+R_GAP;
   const int iw2=PANEL_W-2*PAD;

   _edit(D2_PFX+"TIME",g_db2.x+PAD,y,iw2,R_ROW,"00:00:00 EDT",true,C_FIELD,C_BORDER,C_BLUE,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"TIME"); y+=R_ROW+R_GAP;
   _edit(D2_PFX+"DATE",g_db2.x+PAD,y,iw2,R_ROW,"Mon 1st Jan 2026",true,C_FIELD,C_BORDER,C_SUB,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"DATE"); y+=R_ROW+R_GAP;
   _edit(D2_PFX+"SESS",g_db2.x+PAD,y,iw2,R_ROW,"Off-session",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"SESS"); y+=R_ROW+R_GAP;
   _edit(D2_PFX+"MDL", g_db2.x+PAD,y,iw2,R_ROW,_Symbol+" 1H/M1",true,C_FIELD,C_BORDER,C_TXT,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"MDL"); y+=R_ROW+R_GAP;

   _rect(D2_PFX+"SP1",g_db2.x+PAD,y,iw2,1,C_SEP,C_SEP,Z+2);
   _reg(false,D2_PFX+"SP1"); y+=1+R_GAP;

   // Risk row: "Risk %" label | edit | cash display
   int eLw=44, eCw=iw2-38-eLw-2;
   _lbl( D2_PFX+"RL",  g_db2.x+PAD,    y+3,36,12,"Risk%",C_SUB,Z+2);
   _edit(D2_PFX+"RE",  g_db2.x+PAD+38, y,eLw,R_ROW,DoubleToString(g_riskPct,2),false,C_FIELD2,C_BLUE,C_TXT,ALIGN_RIGHT,Z+2);
   _edit(D2_PFX+"RC",  g_db2.x+PAD+38+eLw+2,y,eCw,R_ROW,"$0.00",true,C_FIELD,C_BORDER,C_BLUE,ALIGN_RIGHT,Z+2);
   _reg(false,D2_PFX+"RL"); _reg(false,D2_PFX+"RE"); _reg(false,D2_PFX+"RC");
   y+=R_ROW+R_GAP;

   // Mode buttons
   { int bw=30;
     _btn(D2_PFX+"BB",g_db2.x+PAD,         y,bw,R_ROW,"Bal",C_FIELD,C_TXT,Z+2);
     _btn(D2_PFX+"BE",g_db2.x+PAD+bw+3,    y,bw,R_ROW,"Eq", C_FIELD,C_TXT,Z+2);
     _btn(D2_PFX+"BC",g_db2.x+PAD+2*(bw+3),y,bw,R_ROW,"Cst",C_FIELD,C_TXT,Z+2);
     _reg(false,D2_PFX+"BB"); _reg(false,D2_PFX+"BE"); _reg(false,D2_PFX+"BC");
   } y+=R_ROW+R_GAP;

   _edit(D2_PFX+"BAL",g_db2.x+PAD,y,iw2,R_ROW,"Bal --",true,C_FIELD,C_BORDER,C_TXT,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"BAL"); y+=R_ROW+R_GAP;
   _edit(D2_PFX+"EQ", g_db2.x+PAD,y,iw2,R_ROW,"Eq  --",true,C_FIELD,C_BORDER,C_TXT,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"EQ"); y+=R_ROW+R_GAP;
   _edit(D2_PFX+"CS", g_db2.x+PAD,y,iw2,R_ROW,"",g_accMode!=2,
         C_FIELD,(g_accMode==2)?C_BLUE:C_BORDER,(g_accMode==2)?C_TXT:C_SUB,ALIGN_RIGHT,Z+2);
   _reg(false,D2_PFX+"CS"); y+=R_ROW+R_GAP;

   _rect(D2_PFX+"SP2",g_db2.x+PAD,y,iw2,1,C_SEP,C_SEP,Z+2);
   _reg(false,D2_PFX+"SP2"); y+=1+R_GAP;

   _edit(D2_PFX+"SLD",g_db2.x+PAD,y,iw2,R_ROW,"SL Dist: --",true,C_FIELD,C_BORDER,C_DIM,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"SLD"); y+=R_ROW+R_GAP;
   _edit(D2_PFX+"LOT",g_db2.x+PAD,y,iw2,R_ROW,"Lot: --",true,C_FIELD2,C_BLUE,C_TEAL,ALIGN_LEFT,Z+2);
   _reg(false,D2_PFX+"LOT");

   _showBody(true, !g_db1.col);
   _showBody(false,!g_db2.col);
  }

//══════════════════════════════════════════════════════════════════
//  LAST-TRIGGER
//══════════════════════════════════════════════════════════════════
void _ltRefresh()
  {
   datetime tod=TodayOpen();
   if(g_ltTime>0&&g_ltTime<tod)
     { g_ltKey="";g_ltLv=g_ltSl=g_ltTp=0;g_ltTime=0;
       g_ltBull=true;g_ltSt=SS_UNKNOWN_OUTCOME; }
   if(g_sigState==SS_TRIGGERED&&g_sigName!=""&&g_sigBirthTime>0&&g_sigTrigTime>=g_ltTime)
     { g_ltKey=(g_sigBull?"BU":"BE")+"_"+IntegerToString((int)g_sigBirthTime);
       g_ltBull=g_sigBull; g_ltTime=g_sigTrigTime;
       g_ltLv=g_sigLevel; g_ltSl=g_sigSlPx; g_ltTp=g_sigTpPx; g_ltSt=SS_TRIGGERED; }
   if(g_ltKey!=""&&g_ltTime>=tod)
     { SIB_STATE rs=SS_UNKNOWN_OUTCOME;datetime rt=0;double rp=0;
       if(ResolveTradeState(g_ltKey,rs,rt,rp)&&(rs==SS_TP_HIT||rs==SS_SL_HIT||rs==SS_BE_HIT))
          g_ltSt=rs; }
  }

//══════════════════════════════════════════════════════════════════
//  TRAFFIC-BOX UPDATE
//══════════════════════════════════════════════════════════════════
void _tbox(const string stem,color bg,color tx,const string lbl)
  { dsi(stem+"B",OBJPROP_BGCOLOR,bg); dsi(stem+"B",OBJPROP_BORDER_COLOR,C_BORDER);
    dss(stem+"T",OBJPROP_TEXT,lbl);   dsi(stem+"T",OBJPROP_COLOR,tx); }

//══════════════════════════════════════════════════════════════════
//  UPDATE DB1
//══════════════════════════════════════════════════════════════════
void DBUpdateDB1()
  {
   _ltRefresh();
   bool useLt=(g_ltTime>=TodayOpen()&&g_ltKey!="");
   bool hasSig=useLt||(g_sigName!=""||g_sigState==SS_ACTIVE);
   bool bull  =useLt?g_ltBull:g_sigBull;
   SIB_STATE st=useLt?g_ltSt:g_sigState;
   double lv=useLt?g_ltLv:g_sigLevel;
   double sl=useLt?g_ltSl:g_sigSlPx;
   double tp=useLt?g_ltTp:g_sigTpPx;
   bool c1=useLt?true:g_sigC1, c2=useLt?true:g_sigC2, c3=useLt?true:g_sigC3;
   string nm=useLt?g_ltKey:(g_sigBirthTime>0?CodenameFromTime(g_sigBirthTime):"");

   // Signal header
   string shdr="▪ SIGNAL"; color sclr=C_DIM;
   if(hasSig)
     { shdr=(bull?"▲ BULL":"▼ BEAR")
           +(st==SS_TRIGGERED?" · LIVE"
            :st==SS_TP_HIT?" · TP HIT"
            :st==SS_SL_HIT?" · SL HIT"
            :st==SS_BE_HIT?" · BE EXIT":" · ACTIVE");
       sclr=_stClr(st,bull); }
   dss(D1_PFX+"SIG",OBJPROP_TEXT,shdr); dsi(D1_PFX+"SIG",OBJPROP_COLOR,sclr);

   // POI
   string poiTxt=(nm!=""&&lv>0)?(nm+"  "+DoubleToString(lv,_Digits)):"--";
   dss(D1_PFX+"POI",OBJPROP_TEXT,poiTxt); dsi(D1_PFX+"POI",OBJPROP_COLOR,hasSig?C_BLUE:C_DIM);

   // C-boxes
   if(!c1)
     { _tbox(D1_PFX+"C1",C_C1_OFF_BG,C_C1_OFF_TX,"C1");
       _tbox(D1_PFX+"C2",C_C1_OFF_BG,C_C1_OFF_TX,"C2");
       _tbox(D1_PFX+"C3",C_C1_OFF_BG,C_C1_OFF_TX,"C3"); }
   else
     { _tbox(D1_PFX+"C1",C_C1_ON_BG,C_C1_ON_TX,"C1 ✓");
       _tbox(D1_PFX+"C2",c2?C_TEAL_BG:C_WAIT_BG, c2?C_TEAL_TX:C_WAIT_TX, c2?"C2 ✓":"C2 …");
       _tbox(D1_PFX+"C3",c3?C_TEAL_BG:C_WAIT_BG, c3?C_TEAL_TX:C_WAIT_TX, c3?"C3 ✓":"C3 …"); }

   // Live position
   bool hasPos=false,pBull=true;
   double en=0,psl=0,ptp=0,pnl=0,cur=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk))continue;
       if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
       if(PositionGetInteger(POSITION_MAGIC)!=202600)continue;
       hasPos=true; pBull=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
       en=PositionGetDouble(POSITION_PRICE_OPEN); psl=PositionGetDouble(POSITION_SL);
       ptp=PositionGetDouble(POSITION_TP);         pnl=PositionGetDouble(POSITION_PROFIT);
       cur=pBull?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
       break; }

   string dirT="--",sltpT="SL --   TP --",progT="[........] +0.0%",pnlT="--";
   color dirC=C_DIM,pnlC=C_DIM;
   string cur3=AccountInfoString(ACCOUNT_CURRENCY);
   if(hasPos)
     { double pct=_pct(pBull,en,psl,ptp,cur);
       dirT=(pBull?"LONG  ":"SHORT ")+DoubleToString(en,_Digits);
       sltpT="SL "+DoubleToString(psl,_Digits)+"   TP "+DoubleToString(ptp,_Digits);
       progT=FmtBar(pct); pnlT=(pnl>=0?"+":"")+DoubleToString(pnl,2)+" "+cur3;
       dirC=pBull?C_GREEN:C_RED; pnlC=(pnl>=0)?C_GREEN:C_RED; }
   else if(useLt)
     { dirT=(bull?"LONG  ":"SHORT ")+(lv>0?DoubleToString(lv,_Digits):"--");
       if(sl>0||tp>0)sltpT="SL "+DoubleToString(sl,_Digits)+"   TP "+DoubleToString(tp,_Digits);
       if(st==SS_TP_HIT){progT="[########] 100%"; pnlT="TP HIT";pnlC=C_GREEN;}
       else if(st==SS_SL_HIT){progT="[........] -100%";pnlT="SL HIT";pnlC=C_RED;}
       else if(st==SS_BE_HIT){progT="[####....] ≈0%"; pnlT="BE EXIT";pnlC=C_AMBER;}
       else{progT="[####....] LIVE";pnlT="Live";pnlC=_stClr(st,bull);}
       dirC=bull?C_GREEN:C_RED; }
   dss(D1_PFX+"DIR", OBJPROP_TEXT,dirT);  dsi(D1_PFX+"DIR", OBJPROP_COLOR,dirC);
   dss(D1_PFX+"SLTP",OBJPROP_TEXT,sltpT);
   dss(D1_PFX+"PROG",OBJPROP_TEXT,progT);
   dss(D1_PFX+"PNL", OBJPROP_TEXT,pnlT);  dsi(D1_PFX+"PNL", OBJPROP_COLOR,pnlC);

   // Stats
   double sprd=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   int nt=0;
   if(HistorySelect(TodayOpen(),TimeCurrent()))
     for(int d=HistoryDealsTotal()-1;d>=0;d--)
       { ulong tk=HistoryDealGetTicket(d);
         if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=202600)continue;
         if(HistoryDealGetString(tk,DEAL_SYMBOL)!=_Symbol)continue;
         if(HistoryDealGetInteger(tk,DEAL_ENTRY)==DEAL_ENTRY_IN)nt++; }
   dss(D1_PFX+"STAT",OBJPROP_TEXT,"Trades: "+IntegerToString(nt)+"   Sprd: "+DoubleToString(sprd,1)+"p");
  }

//══════════════════════════════════════════════════════════════════
//  UPDATE DB2 — Position Sizer
//══════════════════════════════════════════════════════════════════
void _modeBtn(const string n,bool active)
  { dsi(n,OBJPROP_BGCOLOR,active?C_BLUE:C_FIELD); dsi(n,OBJPROP_COLOR,active?C_BG:C_TXT); }

void DBUpdateDB2()
  {
   // Clock & date
   datetime srv=TimeTradeServer();if(srv<=0)srv=TimeCurrent();if(srv<=0)srv=MarketReferenceTime();
   datetime ny=ToNY(srv); bool edt=(NYUTCOffsetSec(srv)==-4*3600);
   dss(D2_PFX+"TIME",OBJPROP_TEXT,TimeToString(ny,TIME_MINUTES|TIME_SECONDS)+(edt?" EDT":" EST"));
   dss(D2_PFX+"DATE",OBJPROP_TEXT,FmtDate(ny));

   // Session
   string sess=GetCurrentSession();
   color sclr=(sess=="London")?C_BLUE:(sess=="NY AM")?C_GREEN:(sess=="NY PM")?C_TEAL
             :(sess=="Asian")?C_AMBER:C_DIM;
   dss(D2_PFX+"SESS",OBJPROP_TEXT,sess); dsi(D2_PFX+"SESS",OBJPROP_COLOR,sclr);
   dss(D2_PFX+"MDL", OBJPROP_TEXT,_Symbol+" 1H/M1");

   // Risk
   string cur3=AccountInfoString(ACCOUNT_CURRENCY);
   double riskAmt=EffectiveAccountBase()*(g_riskPct/100.0);
   dss(D2_PFX+"RE",OBJPROP_TEXT,DoubleToString(g_riskPct,2));
   dss(D2_PFX+"RC",OBJPROP_TEXT,cur3+" "+DoubleToString(riskAmt,2));

   // Mode buttons
   _modeBtn(D2_PFX+"BB",g_accMode==0);
   _modeBtn(D2_PFX+"BE",g_accMode==1);
   _modeBtn(D2_PFX+"BC",g_accMode==2);

   // Balance / equity
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   dss(D2_PFX+"BAL",OBJPROP_TEXT,"Bal "+cur3+" "+DoubleToString(bal,2));
   dss(D2_PFX+"EQ", OBJPROP_TEXT,"Eq  "+cur3+" "+DoubleToString(eq,2));
   dsi(D2_PFX+"EQ", OBJPROP_COLOR,(eq>=bal)?C_GREEN:C_RED);

   // Custom balance field
   dss(D2_PFX+"CS",OBJPROP_TEXT,(g_accMode==2&&g_custBal>0)?DoubleToString(g_custBal,2):"");
   dsi(D2_PFX+"CS",OBJPROP_READONLY,   g_accMode!=2);
   dsi(D2_PFX+"CS",OBJPROP_BGCOLOR,    g_accMode==2?C_FIELD2:C_FIELD);
   dsi(D2_PFX+"CS",OBJPROP_BORDER_COLOR,g_accMode==2?C_BLUE:C_BORDER);
   dsi(D2_PFX+"CS",OBJPROP_COLOR,       g_accMode==2?C_TXT:C_SUB);

   //── Position sizer ─────────────────────────────────────────────
   double sEn=0,sSl=0;
   string sldT="SL Dist: --", lotT="Lot: --"; color lotC=C_DIM;

   // Priority 1: open position lot
   bool foundOpen = false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     { ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;
       if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;
       if(PositionGetInteger(POSITION_MAGIC)!=202600)continue;
       sEn=PositionGetDouble(POSITION_PRICE_OPEN); sSl=PositionGetDouble(POSITION_SL);
       double vlots=PositionGetDouble(POSITION_VOLUME);
       double slDist=MathAbs(sEn-sSl)/_Point;
       sldT="SL Dist: "+DoubleToString(slDist,1)+"p";
       lotT="Lot: "+DoubleToString(vlots,2)+" (open)"; lotC=C_TEAL;
       foundOpen = true;
       break; }

   // Priority 2: live signal estimate
   if(!foundOpen)
     { double sEntry=0,sSig=0;
       if(g_sigSlPx>0&&g_sigLevel>0){ sEntry=g_sigLevel; sSig=g_sigSlPx; }
       else if(g_ltSl>0&&g_ltLv>0&&g_ltTime>=TodayOpen()){ sEntry=g_ltLv; sSig=g_ltSl; }
       if(sEntry>0&&sSig>0)
         { double slDist=MathAbs(sEntry-sSig)/_Point;
           sldT="SL Dist: "+DoubleToString(slDist,1)+"p";
           double pll=EstimateCashLossPerLot(_Symbol,sEntry,sSig);
           if(pll>0)
             { double lots=riskAmt/pll;
               double lstp=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); if(lstp<=0)lstp=0.01;
               double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
               double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
               lots=MathFloor(lots/lstp)*lstp; lots=MathMin(MathMax(lots,0),maxL);
               if(lots>=minL){lotT="Lot: ~"+DoubleToString(lots,2)+" (est)";lotC=C_SUB;} } } }

   dss(D2_PFX+"SLD",OBJPROP_TEXT,sldT);
   dss(D2_PFX+"LOT",OBJPROP_TEXT,lotT); dsi(D2_PFX+"LOT",OBJPROP_COLOR,lotC);
  }

//══════════════════════════════════════════════════════════════════
//  PUBLIC API
//══════════════════════════════════════════════════════════════════
void InitDashboards()
  { if(IsNonVisualTesterRun())return;
    ClearDashboards(); DBLoad(); _clrReg();
    g_db1.w=PANEL_W;g_db1.hh=R_HDR;g_db1.bh=DB1_BH;
    g_db2.w=PANEL_W;g_db2.hh=R_HDR;g_db2.bh=DB2_BH;
    DBLayout(); g_dashInit=true; }

void ClearDashboards()
  { g_dashInit=false;g_dragging=false;g_anyDrag=false;g_dragPanel=0;
    ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
    ObjectsDeleteAll(0,DASH_PFX); _clrReg(); }

void UpdateDashboards()
  { if(IsNonVisualTesterRun())return;
    if(!g_dashInit)InitDashboards();
    DBLayout(); DBUpdateDB1(); DBUpdateDB2(); }

void DBToggle(bool db1)
  { if(db1)g_db1.col=!g_db1.col; else g_db2.col=!g_db2.col;
    DBSave();DBLayout();UpdateDashboards(); }

void DBHandleEdit(const string nm)
  { string txt=ObjectGetString(0,nm,OBJPROP_TEXT);
    if(nm==D2_PFX+"RE")
      { StringReplace(txt,"%","");double v=StringToDouble(txt);
        if(v>0){g_riskPct=v;DBSave();}
        dss(D2_PFX+"RE",OBJPROP_TEXT,DoubleToString(g_riskPct,2));UpdateDashboards();return; }
    if(nm==D2_PFX+"CS")
      { double v=StringToDouble(txt);if(v>0){g_custBal=v;DBSave();}UpdateDashboards(); } }

void DBStartDrag(int panel,int mx,int my)
  { g_dragging=true;g_dragPanel=panel;g_anyDrag=false;
    g_dox=mx-g_db1.x;g_doy=my-g_db1.y; }  // always relative to DB1

void DBStopDrag()
  { if(g_dragging||g_anyDrag)ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
    g_dragging=false;g_anyDrag=false;g_dragPanel=0;DBSave(); }

void HandleDashboardEvent(const int id,const long &lp,const double &dp,const string &sp)
  {
   if(IsNonVisualTesterRun()||!g_dashInit)return;

   if(id==CHARTEVENT_OBJECT_CLICK)
     { if(sp==D1_PFX+"COL") {DBToggle(true); return;}
       if(sp==D2_PFX+"COL") {DBToggle(false);return;}
       if(sp==D2_PFX+"BB")  {g_accMode=0;DBSave();UpdateDashboards();return;}
       if(sp==D2_PFX+"BE")  {g_accMode=1;DBSave();UpdateDashboards();return;}
       if(sp==D2_PFX+"BC")  {g_accMode=2;DBSave();UpdateDashboards();return;} }

   if(id==CHARTEVENT_OBJECT_ENDEDIT){DBHandleEdit(sp);return;}

   if(id==CHARTEVENT_MOUSE_MOVE)
     { int mx=(int)lp,my=(int)dp,mask=(int)StringToInteger(sp);
       bool ld=((mask&1)!=0);
       if(ld)
         { if(!g_dragging)
             { if(_inHdr(g_db1,mx,my))DBStartDrag(1,mx,my);
               else if(_inHdr(g_db2,mx,my))DBStartDrag(2,mx,my); }
           else
             { if(!g_anyDrag){g_anyDrag=true;ChartSetInteger(0,CHART_MOUSE_SCROLL,false);}
               g_db1.x=mx-g_dox;g_db1.y=my-g_doy;DBLayout(); } }
       else if(g_dragging)DBStopDrag();
       return; }

   if(id==CHARTEVENT_CLICK)
     { int mx=(int)lp,my=(int)dp;
       if(g_anyDrag){DBStopDrag();return;}
       if(g_db1.col&&_inHdr(g_db1,mx,my)){DBToggle(true); return;}
       if(g_db2.col&&_inHdr(g_db2,mx,my)){DBToggle(false);return;} }
  }

#endif // CCT_DASHBOARD_MQH
