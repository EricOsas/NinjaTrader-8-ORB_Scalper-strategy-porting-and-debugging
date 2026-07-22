#ifndef CCT_DASHBOARD_MQH
#define CCT_DASHBOARD_MQH

#include "CCT_Globals.mqh"


// Dashboard redraw cache globals.
int    g_dashLastTab=-999;
bool   g_dashLastCollapsed=false;
#define CCTD_W 536
#define CCTD_H 466
#define CCTD_BAR_H 44
#define CCTD_SHELL_Y 52
#define CCTD_SHELL_H 414
#define CCTD_SCALE_NUM 4
#define CCTD_SCALE_DEN 5
#define CCTD_SW 429
#define CCTD_SH 373
#define CCTD_BAR_SH 35
#define CCTD_LAYOUT_HOLD_MS 260
#define CCTD_OVERLAY_THROTTLE_MS 420

uint   g_cctDashPixels[];
uint   g_cctDashScaledPixels[];
bool   g_dashCollapsed=false;
int    g_dashX=12;
int    g_dashY=18;
int    g_dashTab=0;               // 0 SIG, 1 RISK, 2 SAFE, 3 LOG
int    g_dashModeOverride=-1;     // -1 input, 0 dark, 1 dim-light
string g_dashLastBgKey="";
string g_dashLastOverlayKey="";
bool   g_dashCleared=false;
uint   g_dashLastInteractionMs=0;
uint   g_dashLastClickMs=0;
string g_dashLastClickObj="";
uint   g_dashLayoutHoldUntilMs=0;
uint   g_dashLastFullOverlayMs=0;
bool   g_dashOverlayPending=false;

struct DashPalette
  {
   color page;
   color chart;
   color grid;
   color panel;
   color panel2;
   color panel3;
   color inner;
   color border;
   color borderSoft;
   color text;
   color muted;
   color dim;
   color accent;
   color accent2;
   color good;
   color warn;
   color bad;
   color buy;
   color sell;
   color slSoft;
   color tpSoft;
   color cStepDone;
   color cStepActive;
   color cStepWait;
  };

string DashName(const string part)
  {
   return "CCTD_"+part;
  }

string DashResName()
  {
   return "::CCTD_COMMAND_SPLIT_V4_"+IntegerToString((long)ChartID());
  }

bool DashboardRuntimeEnabled()
  {
   return (Inp_ShowDashboard && !IsNonVisualTesterRun());
  }

bool DashDimLightMode()
  {
   if(g_dashModeOverride>=0)
      return (g_dashModeOverride==1);

   return (Inp_DashboardMode==DASH_MODE_DIM_LIGHT);
  }

uint DashA(color c,int alpha=255)
  {
   return ColorToARGB(c,(uchar)MathMax(0,MathMin(255,alpha)));
  }

int DashScaleCoord(int value)
  {
   return (int)MathRound((double)value*(double)CCTD_SCALE_NUM/(double)CCTD_SCALE_DEN);
  }

int DashScaleSize(int value)
  {
   return MathMax(1,DashScaleCoord(value));
  }

int DashScaleFont(int value)
  {
   return MathMax(6,DashScaleCoord(value));
  }

void Px(int x,int y,uint clr)
  {
   if(x<0 || x>=CCTD_W || y<0 || y>=CCTD_H)
      return;

   g_cctDashPixels[y*CCTD_W+x]=clr;
  }

void DashBuildScaledPixels()
  {
   ArrayResize(g_cctDashScaledPixels,CCTD_SW*CCTD_SH);
   for(int y=0;y<CCTD_SH;y++)
     {
      int sy=(int)((long)y*(long)CCTD_H/(long)CCTD_SH);
      if(sy<0)
         sy=0;
      if(sy>=CCTD_H)
         sy=CCTD_H-1;
      for(int x=0;x<CCTD_SW;x++)
        {
         int sx=(int)((long)x*(long)CCTD_W/(long)CCTD_SW);
         if(sx<0)
            sx=0;
         if(sx>=CCTD_W)
            sx=CCTD_W-1;
         g_cctDashScaledPixels[y*CCTD_SW+x]=g_cctDashPixels[sy*CCTD_W+sx];
        }
     }
  }

void FillRect(int x1,int y1,int x2,int y2,uint clr)
  {
   if(x1<0) x1=0;
   if(y1<0) y1=0;
   if(x2>=CCTD_W) x2=CCTD_W-1;
   if(y2>=CCTD_H) y2=CCTD_H-1;

   for(int y=y1;y<=y2;y++)
      for(int x=x1;x<=x2;x++)
         Px(x,y,clr);
  }

void StrokeRect(int x1,int y1,int x2,int y2,uint border,uint fill,int width=1)
  {
   FillRect(x1,y1,x2,y2,border);
   FillRect(x1+width,y1+width,x2-width,y2-width,fill);
  }

void DashSetInteger(const string name,ENUM_OBJECT_PROPERTY_INTEGER prop,long value)
  {
   if(ObjectFind(0,name)<0)
      return;

   if(ObjectGetInteger(0,name,prop)==value)
      return;

   ObjectSetInteger(0,name,prop,value);
  }

void DashSetString(const string name,ENUM_OBJECT_PROPERTY_STRING prop,string value)
  {
   if(ObjectFind(0,name)<0)
      return;

   if(ObjectGetString(0,name,prop)==value)
      return;

   ObjectSetString(0,name,prop,value);
  }

void DashApplyObject(const string name,bool selectable,int z)
  {
   DashSetInteger(name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   DashSetInteger(name,OBJPROP_SELECTABLE,selectable);
   DashSetInteger(name,OBJPROP_SELECTED,false);
   DashSetInteger(name,OBJPROP_HIDDEN,true);
   DashSetInteger(name,OBJPROP_BACK,false);
   DashSetInteger(name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   DashSetInteger(name,OBJPROP_ZORDER,900000+z);
  }


void DashText(const string id,string text,int x,int y,int fontSize,color clr,bool mono=false)
  {
   string name=DashName("TXT_"+id);

   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      DashSetString(name,OBJPROP_FONT,mono ? "Consolas" : "Segoe UI Semibold");
     }

   DashApplyObject(name,false,2200);
   DashSetInteger(name,OBJPROP_XDISTANCE,g_dashX+DashScaleCoord(x));
   DashSetInteger(name,OBJPROP_YDISTANCE,g_dashY+DashScaleCoord(y));
   DashSetInteger(name,OBJPROP_FONTSIZE,DashScaleFont(fontSize));
   DashSetInteger(name,OBJPROP_COLOR,clr);
   DashSetString(name,OBJPROP_TEXT,text);
  }


void DashHit(const string id,int x,int y,int w,int h)
  {
   string name=DashName(id);

   // Clicks are resolved from CHARTEVENT_CLICK coordinates. Selectable
   // transparent rectangles caused MT5 selection borders and stale hit-state.
   if(ObjectFind(0,name)>=0)
      ObjectDelete(0,name);
  }

bool DashRawHit(int ux,int uy,int x,int y,int w,int h)
  {
   return (ux>=x && ux<x+w && uy>=y && uy<y+h);
  }

string DashStepperTarget(const string id,int ux,int uy,int x,int y,int w,int h)
  {
   int bx=x+8;
   int by=y+18;
   int bw=w-16;
   int bh=h-23;
   int mini=17;

   if(DashRawHit(ux,uy,bx,by,mini,bh))
      return DashName("CTL_"+id+"_MINUS");
   if(DashRawHit(ux,uy,bx+bw-mini,by,mini,bh))
      return DashName("CTL_"+id+"_PLUS");
   return "";
  }

string DashSafeStepperTarget(const string id,int ux,int uy,int x,int y,int w)
  {
   int valueW=w-62;
   if(DashRawHit(ux,uy,x+6,y+23,valueW,17))
      return DashName("CTL_"+id+"_TOGGLE");
   if(DashRawHit(ux,uy,x+w-52,y+23,22,17))
      return DashName("CTL_"+id+"_MINUS");
   if(DashRawHit(ux,uy,x+w-27,y+23,22,17))
      return DashName("CTL_"+id+"_PLUS");
   return "";
  }

/*
Purpose: Resolve chart-coordinate clicks to dashboard controls without selectable hit objects.
Constitution: Dashboard interaction must stay lightweight and must not queue delayed object-click bursts.
Inputs: chartX/chartY - click position from CHARTEVENT_CLICK.
Outputs: Dashboard object-style control name, or empty when the click is not actionable.
*/
string DashClickTargetFromPoint(int chartX,int chartY)
  {
   int ux=(int)MathFloor((double)(chartX-g_dashX)*(double)CCTD_SCALE_DEN/(double)CCTD_SCALE_NUM);
   int uy=(int)MathFloor((double)(chartY-g_dashY)*(double)CCTD_SCALE_DEN/(double)CCTD_SCALE_NUM);

   if(ux<0 || uy<0 || ux>=CCTD_W || uy>=CCTD_H)
      return "";

   if(DashRawHit(ux,uy,482,6,42,30))
      return DashName("TOG");

   if(g_dashCollapsed)
      return "";

   for(int i=0;i<4;i++)
     {
      int ty=CCTD_SHELL_Y+66+i*38;
      if(DashRawHit(ux,uy,12,ty,62,32))
         return DashName("TAB"+IntegerToString(i));
     }

   int toneY=CCTD_SHELL_Y+CCTD_SHELL_H-42;
   if(DashRawHit(ux,uy,12,toneY,62,24))
      return DashName("TONE");

   if(g_dashTab==1)
     {
      int x=88;
      int y=CCTD_SHELL_Y+69;
      int w=420;
      int gap=6;
      int col3=(w-12)/3;
      int fy=y+100;

      if(DashRawHit(ux,uy,x,fy,col3,44))
         return DashName("CTL_RBASIS");
      string target=DashStepperTarget("RISK",ux,uy,x+col3+gap,fy,col3,44);
      if(target!="") return target;
      target=DashStepperTarget("CUSTOM",ux,uy,x+2*(col3+gap),fy,col3,44);
      if(target!="") return target;
      target=DashStepperTarget("RR",ux,uy,x,fy+42,col3,44);
      if(target!="") return target;
      target=DashStepperTarget("DL",ux,uy,x+col3+gap,fy+42,col3,44);
      if(target!="") return target;
      if(DashRawHit(ux,uy,x+2*(col3+gap),fy+42,col3,44))
         return DashName("CTL_DAILY_BASIS");
     }

   if(g_dashTab==2)
     {
      int x=88;
      int y=CCTD_SHELL_Y+67;
      int w=420;
      int gap=6;
      int col3=(w-12)/3;
      int by=y+88;

      string target=DashSafeStepperTarget("NEWS",ux,uy,x,by,col3);
      if(target!="") return target;
      if(DashRawHit(ux,uy,x+2*(col3+gap)+6,by+23,col3-12,17))
         return DashName("CTL_NEWS_IMPACT");

      int by2=by+50;
      target=DashSafeStepperTarget("MINOPEN",ux,uy,x,by2,col3);
      if(target!="") return target;
     }

   return "";
  }

string DashShort(string value,int maxLen)
  {
   if(StringLen(value)<=maxLen)
      return value;

   if(maxLen<=3)
      return StringSubstr(value,0,maxLen);

   return StringSubstr(value,0,maxLen-3)+"...";
  }

string DashPrice(double price)
  {
   if(price<=0.0)
      return "-";

   return DoubleToString(price,_Digits);
  }

string DashClock(datetime srv,bool seconds=true)
  {
   if(srv<=0)
      return "--:--";

   return CCTLocalClock(ToDisplay(srv),seconds);
  }

string DashDateTime(datetime srv)
  {
   if(srv<=0)
      return "-";

   return CCTTooltipTimeStamp(srv,false);
  }

string DashTfLabel(ENUM_TIMEFRAMES tf)
  {
   string s=EnumToString(tf);

   if(StringFind(s,"PERIOD_")==0)
      return StringSubstr(s,7);

   return s;
  }
DashPalette DashPaletteForInputs()
  {
   DashPalette p;
   bool light=DashDimLightMode();

   p.page       = light ? (color)C'43,48,57'    : (color)C'9,11,14';
   p.chart      = light ? (color)C'31,36,44'    : (color)C'5,7,10';
   p.grid       = light ? (color)C'61,69,82'    : (color)C'23,29,37';
   p.panel      = light ? (color)C'47,54,66'    : (color)C'20,26,34';
   p.panel2     = light ? (color)C'58,67,82'    : (color)C'27,34,45';
   p.panel3     = light ? (color)C'40,47,58'    : (color)C'15,20,27';
   p.inner      = light ? (color)C'52,60,74'    : (color)C'16,22,30';
   p.border     = light ? (color)C'116,131,153' : (color)C'59,72,89';
   p.borderSoft = light ? (color)C'88,102,122'  : (color)C'42,53,66';
   p.text     = light ? (color)C'255,255,255' : (color)C'248,252,255';
   p.muted    = light ? (color)C'235,240,248' : (color)C'210,220,235';
   p.dim      = light ? (color)C'190,202,218' : (color)C'168,182,205';
   p.buy        = (color)C'207,216,227';
   p.sell       = (color)C'30,76,255';
   p.good       = (color)C'84,212,154';
   p.warn       = (color)C'215,183,104';
   p.bad        = (color)C'225,116,126';
   p.slSoft     = light ? (color)C'70,38,45'    : (color)C'39,17,20';
   p.tpSoft     = light ? (color)C'36,76,74'    : (color)C'13,38,35';
   p.cStepDone  = light ? (color)C'54,69,86'    : (color)C'24,34,47';
   p.cStepActive= light ? (color)C'75,62,32'    : (color)C'42,33,15';
   p.cStepWait  = light ? (color)C'29,36,47'    : (color)C'13,18,25';

   if(Inp_DashboardTheme==DASH_THEME_BLUE)
     {
      p.accent=(color)C'111,167,255';
      p.accent2=(color)C'133,190,255';
      p.border=(color)C'56,90,131';
      p.borderSoft=(color)C'42,63,91';
     }
   else if(Inp_DashboardTheme==DASH_THEME_EMERALD)
     {
      p.accent=(color)C'78,210,154';
      p.accent2=(color)C'129,238,192';
      p.border=(color)C'49,84,72';
      p.borderSoft=(color)C'39,74,60';
     }
   else if(Inp_DashboardTheme==DASH_THEME_CHAMPAGNE)
     {
      p.accent=(color)C'223,189,106';
      p.accent2=(color)C'245,213,144';
      p.border=(color)C'85,69,43';
      p.borderSoft=(color)C'68,54,34';
     }
   else if(Inp_DashboardTheme==DASH_THEME_VIOLET)
     {
      p.accent=(color)C'178,136,255';
      p.accent2=(color)C'207,179,255';
      p.border=(color)C'105,78,150';
      p.borderSoft=(color)C'75,57,103';
     }
   else
     {
      p.accent=(color)C'199,211,223';
      p.accent2=(color)C'224,232,241';
      p.border=(color)C'78,92,108';
      p.borderSoft=(color)C'52,64,78';
     }

   return p;
  }

int DashOpenPositionCount()
  {
   int count=0;

   for(int p=PositionsTotal()-1;p>=0;p--)
     {
      ulong ticket=PositionGetTicket(p);

      if(ticket>0 && PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)==_Symbol && (long)PositionGetInteger(POSITION_MAGIC)==CCTEffectiveMagic())
            count++;
     }

   return count;
  }

string DashOpenPositionSummary()
  {
   for(int p=PositionsTotal()-1;p>=0;p--)
     {
      ulong ticket=PositionGetTicket(p);

      if(ticket<=0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (long)PositionGetInteger(POSITION_MAGIC)!=CCTEffectiveMagic())
         continue;

      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);

      return StringFormat("TKT %s | %s %.2f @ %s",
                          IntegerToString((long)ticket),
                          buy ? "BUY" : "SELL",
                          PositionGetDouble(POSITION_VOLUME),
                          DashPrice(PositionGetDouble(POSITION_PRICE_OPEN)));
     }

   return "No active trade";
  }


int DashLastExecIndex()
  {
   int best=-1;
   datetime bestTime=0;

   for(int i=0;i<g_nExecRecords;i++)
     {
      datetime t=g_execRecords[i].exitTime;

      if(t<=0)
         t=g_execRecords[i].triggerBarTime;

      if(t>=bestTime)
        {
         best=i;
         bestTime=t;
        }
     }

   return best;
  }


bool DashIsResolvedOutcome(SIB_STATE st)
  {
   return (st==SS_RESOLVED_TP ||
           st==SS_RESOLVED_SL ||
           st==SS_RESOLVED_BE ||
           st==SS_RESOLVED_BE_CO);
  }

int DashLastResolvedExecIndex()
  {
   int best=-1;
   datetime bestTime=0;

   for(int i=0;i<g_nExecRecords;i++)
     {
      if(!DashIsResolvedOutcome(g_execRecords[i].outcome) && g_execRecords[i].exitTime<=0)
         continue;

      datetime t=g_execRecords[i].exitTime;

      if(t<=0)
         t=g_execRecords[i].triggerBarTime;

      if(t>=bestTime)
        {
         best=i;
         bestTime=t;
        }
     }

   return best;
  }

datetime DashMostRecentExecTime()
  {
   datetime best=0;

   for(int i=0;i<g_nExecRecords;i++)
     {
      datetime t=g_execRecords[i].exitTime;

      if(t<=0)
         t=g_execRecords[i].triggerBarTime;

      if(t>best)
         best=t;
     }

   return best;
  }

bool DashIsDeadOutcome(SIB_STATE st)
  {
   return (st==SS_DEAD_SUPERSESSION ||
           st==SS_DEAD_WINDOW_CONSUMED ||
           st==SS_DEAD_WINDOW_EXPIRED ||
           st==SS_DEAD_UNAUTHORIZED_C1 ||
           st==SS_DEAD_CO_VIOLATION ||
           st==SS_DEAD_BIAS_FLIP);
  }

bool DashSignalDisplayActive()
  {
   if(DashOpenPositionCount()>0)
      return false;

   if(g_sigBirthTime<=0)
      return false;

   if(DashIsResolvedOutcome(g_sigState) || DashIsDeadOutcome(g_sigState))
      return false;

   if(g_sigState==SS_TRIGGERED && DashOpenPositionCount()<=0)
      return false;

   datetime lastExec=DashMostRecentExecTime();

   if(lastExec>=g_sigBirthTime && DashOpenPositionCount()<=0)
      return false;

   datetime now=CurrentServerTime();
   int maxAge=(int)MathMax(21600.0,(double)PeriodSeconds(HTF())*3.0);

   if(now>g_sigBirthTime+(datetime)maxAge && !g_sigC1 && !g_sigC2 && !g_sigC3)
      return false;

   return true;
  }


string DashSpreadText()
  {
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(ask<=0.0 || bid<=0.0 || _Point<=0.0)
      return "Sprd -";

   double raw=(ask-bid)/_Point;
   double shown=raw;
   int decimals=1;

   string sym=_Symbol;
   StringToUpper(sym);

   if(StringFind(sym,"XAU")>=0 || StringFind(sym,"XAG")>=0)
     {
      shown=MathAbs(ask-bid);
      decimals=(shown<10.0 ? 2 : 1);
     }
   else if(_Digits==3 || _Digits==5)
     {
      shown=raw/10.0;
      decimals=1;
     }
   else if(raw>=1000.0)
     {
      shown=raw/1000.0;
      decimals=1;
     }

   return "Sprd "+DoubleToString(shown,decimals);
  }

string DashMoney(double v)
  {
   string s=DoubleToString(v,2);

   if(v>0.0)
      return "+"+s;

   return s;
  }

string DashLots(double v)
  {
   if(v<=0.0)
      return "-";

   return DoubleToString(v,2)+" lots";
  }

struct DashTradeSnapshot
  {
   bool              valid;
   bool              bull;
   string            gen;
   string            model;
   string            result;
   datetime          triggerTime;
   datetime          exitTime;
   double            entry;
   double            exitPx;
   double            volume;
   double            sl;
   double            tp;
   double            be;
      bool              beApplied;
   double            maxProgressPct;
   SIB_STATE         outcome;
   int               sweepCount;
   datetime          c1Time;
   datetime          c2Time;
   datetime          c3Time;
   ulong             ticket;
  };

void DashResetSnapshot(DashTradeSnapshot &s)
  {
   s.valid=false;
   s.bull=true;
   s.gen="-";
   s.model="-";
   s.result="waiting";
   s.triggerTime=0;
   s.exitTime=0;
   s.entry=0.0;
   s.exitPx=0.0;
   s.volume=0.0;
   s.sl=0.0;
   s.tp=0.0;
   s.be=0.0;
      s.beApplied=false;
   s.maxProgressPct=0.0;
   s.outcome=SS_UNKNOWN_OUTCOME;
   s.sweepCount=0;
   s.c1Time=0;
   s.c2Time=0;
   s.c3Time=0;
   s.ticket=0;
  }

bool DashSnapshotFromExec(DashTradeSnapshot &s,int idx)
  {
   DashResetSnapshot(s);

   if(idx<0 || idx>=g_nExecRecords)
      return false;

   s.valid=true;
   s.bull=g_execRecords[idx].bull;
   s.gen=g_execRecords[idx].genKey;
   s.model=ModelTypeLabel(g_execRecords[idx].modelType);
   s.result=DashOutcomeLabel(g_execRecords[idx].outcome);
   s.triggerTime=g_execRecords[idx].triggerBarTime;
   s.exitTime=g_execRecords[idx].exitTime;
   s.entry=(g_execRecords[idx].brokerFill>0.0) ? g_execRecords[idx].brokerFill : g_execRecords[idx].visualEntry;
   s.exitPx=g_execRecords[idx].exitPrice;
   s.volume=g_execRecords[idx].execLots;
   s.sl=g_execRecords[idx].brokerSL;
   s.tp=g_execRecords[idx].brokerTP;

   if(g_execRecords[idx].beGeneralApplied && g_execRecords[idx].beGeneralPrice>0.0)
      s.be=g_execRecords[idx].beGeneralPrice;
   else if(g_execRecords[idx].beCoApplied && g_execRecords[idx].beCoPrice>0.0)
      s.be=g_execRecords[idx].beCoPrice;
   else if(g_execRecords[idx].bePrice>0.0)
      s.be=g_execRecords[idx].bePrice;
   else
      s.be=DashGlobalBEPrice(g_execRecords[idx].bull,s.entry,s.tp);

   s.beApplied=(g_execRecords[idx].beApplied || g_execRecords[idx].beGeneralApplied || g_execRecords[idx].beCoApplied);
   s.maxProgressPct=g_execRecords[idx].maxProgressPct;
   s.outcome=g_execRecords[idx].outcome;
   s.sweepCount=g_execRecords[idx].sweepCount;
   s.c1Time=g_execRecords[idx].c1Time;
   s.c2Time=g_execRecords[idx].c2Time;
   s.c3Time=g_execRecords[idx].c3Time;
   s.ticket=g_execRecords[idx].ticket;

   return true;
  }


string DashHistoryOutcomeLabel(ulong deal,double netProfit)
  {
   long reason=HistoryDealGetInteger(deal,DEAL_REASON);

   if(reason==DEAL_REASON_SL)
      return "SL "+DashMoney(netProfit);

   if(reason==DEAL_REASON_TP)
      return "TP "+DashMoney(netProfit);

   if(netProfit>0.0)
      return "WIN "+DashMoney(netProfit);

   if(netProfit<0.0)
      return "LOSS "+DashMoney(netProfit);

   return "BE "+DashMoney(netProfit);
  }

bool DashSnapshotFromHistory(DashTradeSnapshot &s)
  {
   DashResetSnapshot(s);

   datetime now=CurrentServerTime();

   if(now<=0)
      now=TimeCurrent();

   // CCT_DASH_HISTORY_SNAPSHOT_CACHE_V1
   // HistorySelect can block the chart thread badly on busy terminals. The
   // dashboard only needs a recent display snapshot, so reuse it briefly.
   static DashTradeSnapshot s_cached;
   static bool s_cachedValid=false;
   static uint s_cachedMs=0;
   static string s_cachedSymbol="";
   static long s_cachedMagic=0;

   uint nowMs=GetTickCount();
   long magic=CCTEffectiveMagic();
   if(s_cachedSymbol==_Symbol &&
      s_cachedMagic==magic &&
      s_cachedMs>0 &&
      (uint)(nowMs-s_cachedMs)<5000)
     {
      if(s_cachedValid)
        {
         s=s_cached;
         return true;
        }
      return false;
     }

   s_cachedSymbol=_Symbol;
   s_cachedMagic=magic;
   s_cachedMs=nowMs;
   s_cachedValid=false;
   DashResetSnapshot(s_cached);

   datetime from=now-(datetime)(86400*45);

   if(!HistorySelect(from,now))
      return false;

   int total=HistoryDealsTotal();
   ulong bestDeal=0;
   datetime bestTime=0;

   for(int i=total-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);

      if(deal==0)
         continue;

      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;

      if((long)HistoryDealGetInteger(deal,DEAL_MAGIC)!=CCTEffectiveMagic())
         continue;

      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);

      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT && entry!=DEAL_ENTRY_OUT_BY)
         continue;

      datetime t=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);

      if(t>=bestTime)
        {
         bestTime=t;
         bestDeal=deal;
        }
     }

   if(bestDeal==0)
      return false;

   ulong posId=(ulong)HistoryDealGetInteger(bestDeal,DEAL_POSITION_ID);
   ulong entryDeal=0;
   datetime entryTime=0;

   for(int j=total-1;j>=0;j--)
     {
      ulong deal=HistoryDealGetTicket(j);

      if(deal==0)
         continue;

      if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=posId)
         continue;

      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;

      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);

      if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT)
         continue;

      datetime t=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);

      if(entryDeal==0 || t<entryTime)
        {
         entryDeal=deal;
         entryTime=t;
        }
     }

   string mappedKey="";
   bool mappedBull=false;
   if(CCTFindGenKeyByPositionId(posId,mappedKey,mappedBull))
     {
      int idx=CCTEnsureExecRecord(mappedKey);
      if(idx>=0 && idx<g_nExecRecords && DashSnapshotFromExec(s,idx))
        {
         if(s.exitTime<=0)
            s.exitTime=(datetime)HistoryDealGetInteger(bestDeal,DEAL_TIME);
         if(s.exitPx<=0.0)
            s.exitPx=HistoryDealGetDouble(bestDeal,DEAL_PRICE);
         if(s.volume<=0.0)
            s.volume=HistoryDealGetDouble(bestDeal,DEAL_VOLUME);
         if(s.result=="waiting" || s.result=="Open")
           {
            double profit=HistoryDealGetDouble(bestDeal,DEAL_PROFIT)+HistoryDealGetDouble(bestDeal,DEAL_SWAP)+HistoryDealGetDouble(bestDeal,DEAL_COMMISSION);
            s.result=DashHistoryOutcomeLabel(bestDeal,profit);
           }
         s.ticket=posId;
         s_cached=s;
         s_cachedValid=true;
         return true;
        }
     }

   double profit=HistoryDealGetDouble(bestDeal,DEAL_PROFIT)+HistoryDealGetDouble(bestDeal,DEAL_SWAP)+HistoryDealGetDouble(bestDeal,DEAL_COMMISSION);
   long closeType=HistoryDealGetInteger(bestDeal,DEAL_TYPE);
   long openType=(entryDeal>0 ? HistoryDealGetInteger(entryDeal,DEAL_TYPE) : -1);

   s.valid=true;
   s.bull=(openType==DEAL_TYPE_BUY || (openType<0 && closeType==DEAL_TYPE_SELL));
   s.gen="HISTORY";
   s.model="History";
   s.result=DashHistoryOutcomeLabel(bestDeal,profit);
   s.triggerTime=(entryDeal>0 ? (datetime)HistoryDealGetInteger(entryDeal,DEAL_TIME) : 0);
   s.exitTime=(datetime)HistoryDealGetInteger(bestDeal,DEAL_TIME);
   s.entry=(entryDeal>0 ? HistoryDealGetDouble(entryDeal,DEAL_PRICE) : 0.0);
   s.exitPx=HistoryDealGetDouble(bestDeal,DEAL_PRICE);
   s.volume=HistoryDealGetDouble(bestDeal,DEAL_VOLUME);
   s.sl=0.0;
   s.tp=0.0;
   s.be=0.0;
   s.outcome=(profit>0.0 ? SS_RESOLVED_TP : (profit<0.0 ? SS_RESOLVED_SL : SS_RESOLVED_BE));
   s.sweepCount=0;
   s.c1Time=s.triggerTime;
   s.c2Time=0;
   s.c3Time=0;
   s.ticket=posId;

   s_cached=s;
   s_cachedValid=true;
   return true;
  }


bool DashGetLastTradeSnapshot(DashTradeSnapshot &s)
  {
   DashTradeSnapshot ex;
   DashTradeSnapshot hx;
   DashResetSnapshot(ex);
   DashResetSnapshot(hx);

   bool hasExec=DashSnapshotFromExec(ex,DashLastResolvedExecIndex());
   bool hasHist=DashSnapshotFromHistory(hx);

   if(hasExec && hasHist)
     {
      // Prefer execution-record truth when the history row maps back to the same CCT generation.
      if(hx.gen==ex.gen || hx.gen=="HISTORY")
        {
         if(hx.exitTime>ex.exitTime && hx.gen!=ex.gen)
            s=hx;
         else
            s=ex;
         return true;
        }

      s=(hx.exitTime>ex.exitTime) ? hx : ex;
      return true;
     }

   if(hasExec)
     {
      s=ex;
      return true;
     }

   if(hasHist)
     {
      s=hx;
      return true;
     }

   DashResetSnapshot(s);
   return false;
  }


int DashFindExecIndexByPosition(ulong positionId,ulong posTicket)
  {
   int best=-1;
   datetime bestTime=0;

   for(int i=0;i<g_nExecRecords;i++)
     {
      if(g_execRecords[i].ticket!=positionId && g_execRecords[i].ticket!=posTicket)
         continue;

      datetime t=g_execRecords[i].triggerBarTime;
      if(t>=bestTime)
        {
         best=i;
         bestTime=t;
        }
     }

   if(best>=0)
      return best;

   // Terminal restart path: Execution.mqh can recover persisted records by
   // matching the broker position id to GlobalVariable CCT_EXEC_<symbol>_<gen>_Y.
   string key="";
   bool bull=false;

   if(CCTFindGenKeyByPositionId(positionId,key,bull) || CCTFindGenKeyByPositionId(posTicket,key,bull))
     {
      int idx=CCTFindExecRecord(key);
      if(idx<0)
         idx=CCTEnsureExecRecord(key);

      if(idx>=0 && idx<g_nExecRecords)
         return idx;
     }

   return -1;
  }


bool DashGetLiveTradeSnapshot(DashTradeSnapshot &s)
  {
   DashResetSnapshot(s);

   for(int p=PositionsTotal()-1;p>=0;p--)
     {
      ulong posTicket=PositionGetTicket(p);

      if(posTicket<=0 || !PositionSelectByTicket(posTicket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (long)PositionGetInteger(POSITION_MAGIC)!=CCTEffectiveMagic())
         continue;

      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int idx=DashFindExecIndexByPosition(positionId,posTicket);

      if(idx<0)
        {
         string key="";
         bool commentBull=false;

         if(CCTTryGenKeyFromComment(PositionGetString(POSITION_COMMENT),key,commentBull))
            idx=CCTEnsureExecRecord(key);
        }

      if(idx>=0)
         DashSnapshotFromExec(s,idx);
      else
         DashResetSnapshot(s);

      s.valid=true;
      s.bull=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      s.ticket=(positionId>0 ? positionId : posTicket);
      s.entry=PositionGetDouble(POSITION_PRICE_OPEN);
      s.volume=PositionGetDouble(POSITION_VOLUME);
      s.sl=PositionGetDouble(POSITION_SL);
      s.tp=PositionGetDouble(POSITION_TP);
      s.outcome=SS_TRIGGERED;
      s.result="Open";

      if(s.gen=="" || s.gen=="-")
         s.gen="UNMAPPED";

      if(s.model=="" || s.model=="-")
         s.model="CCT";

      if(s.be<=0.0)
         s.be=DashGlobalBEPrice(s.bull,s.entry,s.tp);

      return true;
     }

   return false;
  }



double DashProgressR(const DashTradeSnapshot &s)
  {
   if(!s.valid || s.entry<=0.0 || s.sl<=0.0)
      return 0.0;

   double px=s.bull ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double risk=MathAbs(s.entry-s.sl);

   if(px<=0.0 || risk<=_Point*0.1)
      return 0.0;

   return (s.bull ? (px-s.entry) : (s.entry-px))/risk;
  }

double DashFrozenProgressR(const DashTradeSnapshot &s)
  {
   if(!s.valid || s.entry<=0.0 || s.sl<=0.0)
      return 0.0;

   double risk=MathAbs(s.entry-s.sl);
   if(risk<=_Point*0.1)
      return 0.0;

   if(s.exitPx>0.0 && CCTResolvedState(s.outcome))
      return (s.bull ? (s.exitPx-s.entry) : (s.entry-s.exitPx))/risk;

   if(s.maxProgressPct!=0.0 && s.tp>0.0)
     {
      double rr=MathAbs(s.tp-s.entry)/risk;
      return rr*(s.maxProgressPct/100.0);
     }

   if(s.exitPx>0.0)
      return (s.bull ? (s.exitPx-s.entry) : (s.entry-s.exitPx))/risk;

   return 0.0;
  }

string DashProgressText(const DashTradeSnapshot &s)
  {
   return DoubleToString(DashProgressR(s),2)+"R";
  }

double DashTPProgressPct(const DashTradeSnapshot &s)
  {
   if(!s.valid || s.entry<=0.0 || s.tp<=0.0)
      return 0.0;

   double px=s.bull ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double span=MathAbs(s.tp-s.entry);

   if(px<=0.0 || span<=_Point*0.1)
      return 0.0;

   double favorable=s.bull ? (px-s.entry) : (s.entry-px);
   return 100.0*favorable/span;
  }

bool DashBEThresholdMet(const DashTradeSnapshot &s)
  {
   if(!Inp_BEGlobal)
      return false;

   if(s.beApplied)
      return true;

   if(s.maxProgressPct>=g_beTriggerPct)
      return true;

   return (DashTPProgressPct(s)>=g_beTriggerPct);
  }

string DashBEStatusText(const DashTradeSnapshot &s)
  {
   if(!Inp_BEGlobal)
      return "BE disabled";

   if(s.beApplied)
      return "BE applied";

   if(DashBEThresholdMet(s))
      return "BE threshold met";

   return "Awaiting BE threshold";
  }

string DashSLBEText(const DashTradeSnapshot &s)
  {
   string sl=DashPrice(s.sl);

   if(!Inp_BEGlobal)
      return sl+" / BE off";

   if(s.be>0.0)
      return sl+" / "+DashPrice(s.be);

   return sl+" / pending";
  }


string DashTPRRText(const DashTradeSnapshot &s)
  {
   string rr=(s.entry>0.0 && s.sl>0.0 && s.tp>0.0) ? DoubleToString(MathAbs(s.tp-s.entry)/MathAbs(s.entry-s.sl),2)+"R" : "-";
   return DashPrice(s.tp)+" / "+rr;
  }

bool DashSignalMatchesSnapshot(const DashTradeSnapshot &s)
  {
   if(!s.valid || g_sigBirthTime<=0)
      return false;

   string key=GenKey(g_sigBull,g_sigBirthTime);
   return (key==s.gen);
  }
string DashSnapshotKey()
  {
   static uint s_lastMs=0;
   static string s_cached="";
   uint nowMs=GetTickCount();
   if(s_lastMs>0 && (uint)(nowMs-s_lastMs)<2500)
      return s_cached;

   DashTradeSnapshot s;

   if(!DashGetLastTradeSnapshot(s))
     {
      s_cached="no-snapshot";
      s_lastMs=nowMs;
      return s_cached;
     }

   s_cached=s.gen+"|"+s.result+"|"+IntegerToString((long)s.exitTime)+"|"+DashPrice(s.entry)+"|"+DashPrice(s.exitPx)+"|"+DoubleToString(s.volume,2);
   s_lastMs=nowMs;
   return s_cached;
  }

string DashModeText()
  {
   DashTradeSnapshot live;
   if(DashGetLiveTradeSnapshot(live))
      return "MANAGING";

   if(DashSignalDisplayActive())
      return "EXEC READY";

   return "STANDBY";
  }


color DashModeColor(const DashPalette &p)
  {
   DashTradeSnapshot live;
   if(DashGetLiveTradeSnapshot(live))
      return p.good;

   if(DashSignalDisplayActive())
      return p.text;

   return p.muted;
  }


double DashGlobalBEPrice(bool bull,double entry,double tp)
  {
   if(!Inp_BEGlobal || entry<=0.0 || tp<=0.0)
      return 0.0;

   double span=MathAbs(tp-entry);

   if(span<=_Point*0.1)
      return 0.0;

   return NormalizeDouble(entry+(bull ? 1.0 : -1.0)*(g_beMovePct/100.0)*span,_Digits);
  }

string DashStateLabel(SIB_STATE st)
  {
   if(st==SS_VALID) return "Valid";
   if(st==SS_ACTIVE) return "Active";
   if(st==SS_INACTIVE) return "Inactive";
   if(st==SS_TRIGGERED) return "Triggered";
   if(st==SS_DORMANT) return "Dormant";
   if(st==SS_RESOLVED_TP) return "TP";
   if(st==SS_RESOLVED_SL) return "SL";
   if(st==SS_RESOLVED_BE) return "BE";
   if(st==SS_RESOLVED_BE_CO) return "BE/CO";
   if(st==SS_DEAD_SUPERSESSION) return "Dead / superseded";
   if(st==SS_DEAD_WINDOW_CONSUMED) return "Window consumed";
   if(st==SS_DEAD_WINDOW_EXPIRED) return "Window expired";
   if(st==SS_DEAD_UNAUTHORIZED_C1) return "Unauthorized C1";
   if(st==SS_DEAD_CO_VIOLATION) return "CO violation";
   if(st==SS_DEAD_BIAS_FLIP) return "Bias flip";

   return "Waiting";
  }

string DashOutcomeLabel(SIB_STATE st)
  {
   if(st==SS_TRIGGERED) return "Open";
   if(st==SS_RESOLVED_TP) return "TP";
   if(st==SS_RESOLVED_SL) return "SL";
   if(st==SS_RESOLVED_BE) return "BE";
   if(st==SS_RESOLVED_BE_CO) return "BE/CO";

   return DashStateLabel(st);
  }

color DashOutcomeColor(const DashPalette &p,SIB_STATE st)
  {
   if(st==SS_RESOLVED_TP || st==SS_TRIGGERED)
      return p.good;

   if(st==SS_RESOLVED_SL)
      return p.bad;

   if(st==SS_RESOLVED_BE || st==SS_RESOLVED_BE_CO)
      return p.warn;

   return p.text;
  }

string CCTDashboardNewsText()
  {
   if(!CCTEffectiveNewsFilter())
      return "FILTER OFF";

   datetime now=CurrentServerTime();

   if(g_propCachedEntryNewsBlocked)
      return "BLACKOUT";

   if(g_cctNewsDashLastSeen>0 &&
      g_cctNewsDashTime>=now &&
      (now-g_cctNewsDashLastSeen)<=120)
     {
      string label=g_cctNewsDashLabel;
      string cur="NEWS";

      int sp=StringFind(label," ");

      if(sp>0)
         cur=StringSubstr(label,0,sp);
      else if(StringLen(label)>=3)
         cur=StringSubstr(label,0,3);

      StringToUpper(cur);

      int mins=g_cctNewsDashMinutes;

      if(mins<0)
        {
         int secs=(int)(g_cctNewsDashTime-now);

         if(secs<0)
            secs=0;

         mins=(int)MathCeil((double)secs/60.0);
        }

      return cur+" "+IntegerToString(mins)+"m";
     }

   return "NO NEWS";
  }

string CCTDashboardNewsDetailText()
  {
   if(!CCTEffectiveNewsFilter())
      return "News filter off; entries ignore calendar guard.";

   datetime now=CurrentServerTime();

   if(g_propCachedEntryNewsBlocked)
     {
      string reason=g_propCachedEntryNewsReason;
      if(reason=="")
         reason="News blackout active.";
      return reason;
     }

   if(g_cctNewsDashLastSeen>0 &&
      g_cctNewsDashTime>=now &&
      (now-g_cctNewsDashLastSeen)<=120)
     {
      int secs=(int)(g_cctNewsDashTime-now);
      if(secs<0)
         secs=0;
      int mins=(int)MathCeil((double)secs/60.0);
      return StringFormat("%s at %s NY | %dm until blackout/event window",
                          g_cctNewsDashLabel,
                          TimeToString(ToNY(g_cctNewsDashTime),TIME_MINUTES),
                          mins);
     }

   return "No high-impact news in the active warning window.";
  }

bool CCTDashboardNewsWarn()
  {
   if(!CCTEffectiveNewsFilter())
      return false;

   if(g_propCachedEntryNewsBlocked)
      return true;

   datetime now=CurrentServerTime();

   return (g_cctNewsDashLastSeen>0 &&
           g_cctNewsDashTime>=now &&
           (now-g_cctNewsDashLastSeen)<=120 &&
           g_cctNewsDashMinutes<=15);
  }

void DashTextCentered(const string id,string text,int x,int y,int w,int h,int fontSize,color clr,bool mono=false)
  {
   text=DashFitText(text,w,fontSize,mono);

   double factor=mono ? 0.70 : 0.66;
   int textW=(int)MathRound((double)StringLen(text)*(double)fontSize*factor);

   int tx=x+(w-textW)/2-2;
   int ty=y+(h-fontSize-5)/2-1;

   if(tx<x+2)
      tx=x+2;

   if(ty<y+1)
      ty=y+1;

   DashText(id,text,tx,ty,fontSize,clr,mono);
  }




string DashFitText(string text,int w,int fontSize,bool mono=false)
  {
   if(text=="")
      return text;

   double factor=mono ? 0.70 : 0.66;
   int usable=MathMax(6,w-8);
   int maxChars=(int)MathFloor((double)usable/((double)MathMax(1,fontSize)*factor));

   if(maxChars<1)
      maxChars=1;

   if(StringLen(text)<=maxChars)
      return text;

   if(maxChars<=3)
      return StringSubstr(text,0,maxChars);

   return StringSubstr(text,0,maxChars-3)+"...";
  }

string DashUpper(string s)
  {
   StringToUpper(s);
   return s;
  }

void DashTextLeftFit(const string id,string text,int x,int y,int w,int fontSize,color clr,bool mono=false)
  {
   DashText(id,DashFitText(text,w,fontSize,mono),x,y,fontSize,clr,mono);
  }
void DrawBox(const DashPalette &p,int x,int y,int w,int h,color bg,color br)
  {
   StrokeRect(x,y,x+w-1,y+h-1,DashA(br,255),DashA(bg,255),1);
  }


void DrawCard(const DashPalette &p,int x,int y,int w,int h)
  {
   DrawBox(p,x,y,w,h,p.panel,p.border);
  }

void DrawSoftCard(const DashPalette &p,int x,int y,int w,int h)
  {
   DrawBox(p,x,y,w,h,p.panel2,p.borderSoft);
  }

void DrawKVBox(const DashPalette &p,const string id,string k,string v,int x,int y,int w,int h,color fg,color bg=clrNONE,color br=clrNONE)
  {
   if(bg==clrNONE)
      bg=p.inner;

   if(br==clrNONE)
      br=p.borderSoft;

   DrawBox(p,x,y,w,h,bg,br);
   DashText("KV_"+id+"_K",DashUpper(k),x+9,y+6,7,p.dim);
   DashTextCentered("KV_"+id+"_V",v,x+6,y+18,w-12,h-20,8,fg,false);
  }




void DrawEvent(const DashPalette &p,const string id,string tag,string text,int x,int y,int w,bool important=false)
  {
   DrawBox(p,x,y,w,30,important ? p.panel2 : p.panel,p.borderSoft);

   DashText(id+"_T",DashShort(tag,8),x+7,y+8,8,important ? p.text : p.muted,true);
   DashText(id+"_V",DashShort(text,60),x+61,y+8,8,important ? p.text : p.muted,false);
  }






void DrawMiniBox(const DashPalette &p,const string id,string text,int x,int y,int w,int mode)
  {
   color bg=p.cStepWait;
   color br=p.borderSoft;
   color fg=p.dim;

   if(mode==1)
     {
      bg=p.cStepDone;
      br=p.accent;
      fg=p.text;
     }
   else if(mode==2)
     {
      bg=p.cStepActive;
      br=p.warn;
      fg=p.warn;
     }

   StrokeRect(x,y,x+w-1,y+27,DashA(br,235),DashA(bg,248),1);
   DashTextCentered("MINI_"+id,DashShort(text,18),x,y,w,28,8,fg,true);
  }

string DashStepTime(datetime t)
  {
   if(t<=0)
      return "--:--";

   return DashClock(t,false);
  }
void DrawCStep(const DashPalette &p,const string id,string text,int x,int y,int w,int mode,datetime stepTime=0)
  {
   color bg=p.cStepWait;
   color br=p.borderSoft;
   color fg=p.dim;

   if(mode==1)
     {
      bg=p.cStepDone;
      br=p.good;
      fg=p.text;
     }
   else if(mode==2)
     {
      bg=p.cStepActive;
      br=p.warn;
      fg=p.warn;
     }

   StrokeRect(x,y,x+w-1,y+31,DashA(br,245),DashA(bg,248),1);
   if(mode==1)
     {
      FillRect(x+2,y+2,x+w-3,y+4,DashA(p.good,120));
      FillRect(x+2,y+5,x+w-3,y+9,DashA(p.accent,45));
     }
   else if(mode==2)
     {
      FillRect(x+2,y+2,x+w-3,y+4,DashA(p.warn,120));
      FillRect(x+2,y+5,x+w-3,y+9,DashA(p.warn,38));
     }
   DashTextCentered("CSTEP_"+id,text,x,y+2,w,14,8,fg,true);
   DashTextCentered("CSTEP_"+id+"_T",DashStepTime(stepTime),x,y+16,w,14,7,mode==0 ? p.dim : (mode==1 ? p.good : fg),true);
  }





void DrawButtonSkin(const DashPalette &p,const string id,string text,int x,int y,int w,int h,color bg,color fg,color br,int fontSize=8)
  {
   StrokeRect(x,y,x+w-1,y+h-1,DashA(br,210),DashA(bg,242),1);
   DashTextCentered("BTN_"+id,text,x,y,w,h,fontSize,fg,false);
   DashHit(id,x,y,w,h);
  }




void DrawField(const DashPalette &p,const string id,string label,string value,int x,int y,int w,int h=44)
  {
   DrawBox(p,x,y,w,h,p.inner,p.borderSoft);
   DashText("FIELD_"+id+"_L",DashUpper(label),x+8,y+5,7,p.dim);

   bool stepped=(id=="RISK" || id=="RR" || id=="DL" || id=="CUSTOM");
   int bx=x+8;
   int by=y+18;
   int bw=w-16;
   int bh=h-23;

   if(stepped)
     {
      int mini=17;
      string ctl="CTL_"+id;

      StrokeRect(bx,by,bx+mini-1,by+bh-1,DashA(p.borderSoft,210),DashA(p.panel3,242),1);
      DashTextCentered("FIELD_"+id+"_MINUS","-",bx,by,mini,bh,8,p.muted,true);
      DashHit(ctl+"_MINUS",bx,by,mini,bh);

      StrokeRect(bx+mini+2,by,bx+bw-mini-3,by+bh-1,DashA(p.borderSoft,210),DashA(p.panel2,246),1);
      DashTextCentered("FIELD_"+id+"_V",value,bx+mini+2,by,bw-(mini*2)-4,bh,8,p.text,false);

      StrokeRect(bx+bw-mini,by,bx+bw-1,by+bh-1,DashA(p.borderSoft,210),DashA(p.panel3,242),1);
      DashTextCentered("FIELD_"+id+"_PLUS","+",bx+bw-mini,by,mini,bh,8,p.muted,true);
      DashHit(ctl+"_PLUS",bx+bw-mini,by,mini,bh);
     }
   else
     {
      StrokeRect(bx,by,bx+bw-1,by+bh-1,DashA(p.borderSoft,210),DashA(p.panel2,246),1);
      DashTextCentered("FIELD_"+id+"_V",value,bx,by,bw,bh,8,p.text,false);
     }
  }



void DrawSelectField(const DashPalette &p,const string id,string label,string value,int x,int y,int w,int h=44)
  {
   DrawBox(p,x,y,w,h,p.inner,p.borderSoft);
   DashText("SEL_"+id+"_L",DashUpper(label),x+8,y+5,7,p.dim);

   int bx=x+8;
   int by=y+18;
   int bw=w-16;
   int bh=h-23;

   StrokeRect(bx,by,bx+bw-1,by+bh-1,DashA(p.accent,230),DashA(p.panel2,248),1);
   DashTextCentered("SEL_"+id+"_V",value,bx,by,bw,bh,8,p.accent,false);
   DashHit("CTL_"+id,x,y,w,h);
  }



color DashModeBg(const DashPalette &p)
  {
   DashTradeSnapshot live;

   if(DashGetLiveTradeSnapshot(live))
      return p.tpSoft;

   if(DashSignalDisplayActive())
      return p.panel2;

   return p.inner;
  }

void DrawGlowBox(const DashPalette &p,int x,int y,int w,int h,color bg,color br,color glow)
  {
   StrokeRect(x,y,x+w-1,y+h-1,DashA(br,255),DashA(bg,255),1);
   FillRect(x+2,y+2,x+w-3,y+3,DashA(glow,175));
   FillRect(x+2,y+4,x+w-3,y+5,DashA(glow,82));
   FillRect(x+2,y+6,x+w-3,y+6,DashA(glow,36));
  }

void DrawNoteBox(const DashPalette &p,const string id,string tag,string line1,string line2,int x,int y,int w,int h,color clr)
  {
   DrawBox(p,x,y,w,h,p.panel,p.borderSoft);
   DashText(id+"_T",DashShort(tag,8),x+7,y+8,8,p.muted,true);
   DashText(id+"_V1",DashShort(line1,54),x+61,y+7,8,clr,false);
   DashText(id+"_V2",DashShort(line2,54),x+61,y+24,8,p.muted,false);
  }

string DashMoneyBrief(double v)
  {
   string s=DoubleToString(MathAbs(v),2);
   if(v<0.0)
      return "-"+s;
   return s;
  }

string DashSafeFooterLine()
  {
   string impact=CCTNewsImpactDashboardLabel();
   return "Impact "+impact+" | blackout "+DoubleToString(CCTEffectiveNewsBlackoutMinutes(),1)+"m | min-open "+IntegerToString(CCTEffectiveMinOpenMinutes())+"m.";
  }

ulong DashOpenTicket()
  {
   for(int p=PositionsTotal()-1;p>=0;p--)
     {
      ulong ticket=PositionGetTicket(p);

      if(ticket<=0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)==_Symbol && (long)PositionGetInteger(POSITION_MAGIC)==CCTEffectiveMagic())
         return ticket;
     }

   return 0;
  }

int DashLiveExecIndex()
  {
   ulong ticket=DashOpenTicket();

   if(ticket>0)
     {
      for(int i=0;i<g_nExecRecords;i++)
         if(g_execRecords[i].ticket==ticket)
            return i;
     }

   int best=-1;
   datetime bestTime=0;

   for(int i=0;i<g_nExecRecords;i++)
     {
      if(DashIsResolvedOutcome(g_execRecords[i].outcome))
         continue;

      datetime t=g_execRecords[i].triggerBarTime;

      if(t>=bestTime)
        {
         best=i;
         bestTime=t;
        }
     }

   if(best>=0)
      return best;

   return -1;
  }
string DashSessionChip()
  {
   datetime ny=ToNY(CurrentServerTime());

   if(ny<=0)
      return "OFF";

   MqlDateTime dt;
   TimeToStruct(ny,dt);

   int h=dt.hour;

   // Session labels are based on the user's CCT NY-session map.
   if(h>=0 && h<2)
      return "00-01";

   if(h>=2 && h<6)
      return "LND";

   if(h>=7 && h<11)
      return "NY AM";

   if(h>=12 && h<16)
      return "NY PM";

   if(h>=20 && h<23)
      return "ASIA";

   return "OFF";
  }

void DashTextCenteredBias(const string id,string text,int x,int y,int w,int h,int fontSize,color clr,bool mono=false,int biasX=0,int biasY=0)
  {
   double factor=mono ? 0.62 : 0.56;
   int textW=(int)MathRound((double)StringLen(text)*(double)fontSize*factor);

   int tx=x+(w-textW)/2+biasX;
   int ty=y+(h-fontSize-5)/2+biasY;

   if(tx<x+1)
      tx=x+1;

   if(ty<y+1)
      ty=y+1;

   DashText(id,text,tx,ty,fontSize,clr,mono);
  }
void RenderBar(const DashPalette &p)
  {
   DrawBox(p,0,0,CCTD_W,CCTD_BAR_H,p.panel,p.border);

   DashTextCentered("BAR_BRAND","CCT",4,5,50,30,10,p.accent,false);

   DrawGlowBox(p,58,6,146,30,p.inner,p.accent,p.text);
   DashTextCenteredBias("BAR_TIME",DisplayTZLabel()+" "+DashClock(CurrentServerTime(),true),58,6,146,30,10,p.accent,true,-6,-1);

   DrawBox(p,210,6,78,30,p.panel2,p.borderSoft);
   DashTextCenteredBias("BAR_SPRD",DashSpreadText(),210,6,78,30,8,p.muted,false,0,-1);

   DrawBox(p,294,6,70,30,p.panel2,p.borderSoft);
   DashTextCenteredBias("BAR_SESS",DashSessionChip(),294,6,70,30,8,p.muted,false,0,-1);

   bool newsWarn=CCTDashboardNewsWarn();
   string newsText=newsWarn ? CCTDashboardNewsText() : "NO NEWS";
   DrawGlowBox(p,370,6,106,30,newsWarn ? p.panel2 : p.inner,newsWarn ? p.warn : p.borderSoft,newsWarn ? p.warn : p.good);
   DashTextCenteredBias("BAR_NEWS",newsText,370,6,106,30,8,newsWarn ? p.warn : p.good,false,0,-1);

   DrawBox(p,482,6,42,30,p.inner,p.borderSoft);
   DashTextCentered("BAR_TOG",g_dashCollapsed ? "+" : "-",482,6,42,30,10,p.text,true);
   DashHit("TOG",482,6,42,30);

   DashHit("DRAG",0,0,476,CCTD_BAR_H);
  }




void RenderShellFrame(const DashPalette &p)
  {
   DrawBox(p,0,CCTD_SHELL_Y,CCTD_W,CCTD_SHELL_H,p.panel,p.border);
   DrawBox(p,7,CCTD_SHELL_Y+7,CCTD_W-14,CCTD_SHELL_H-14,p.panel3,p.borderSoft);

   DrawBox(p,8,CCTD_SHELL_Y+8,CCTD_W-16,52,p.panel2,p.border);

   bool live=(DashOpenPositionCount()>0);
   bool sig=DashSignalDisplayActive();

   string title="FLAT - Previous trade fallback";
   string sub="No active candidate | showing most recent resolved trade";

   if(sig)
     {
      title=StringFormat("%s %s - Signal forming",g_sigBull ? "BUY" : "SELL",g_sigModelLabel);
      sub=GenKey(g_sigBull,g_sigBirthTime)+" | "+_Symbol+" "+DashTfLabel(LTF())+" | "+DashStateLabel(g_sigState);
     }
   else if(live)
     {
      title="LIVE - Managing execution";
      sub=DashOpenPositionSummary();
     }

   bool newsWarn=CCTDashboardNewsWarn();
   if(newsWarn)
      sub=CCTDashboardNewsDetailText();

   int statusX=390;
   int statusW=118;
   int textW=statusX-36;

   DashTextLeftFit("HEAD_TITLE",title,18,CCTD_SHELL_Y+16,textW,9,p.text,false);
   DashTextLeftFit("HEAD_SUB",sub,18,CCTD_SHELL_Y+35,textW,7,p.muted,false);

   string mode="STANDBY";
   color modeFg=p.accent;
   color modeBg=p.inner;
   color modeBr=p.borderSoft;
   if(live)
     {
      mode="MANAGING";
      modeFg=p.good;
      modeBg=p.tpSoft;
      modeBr=p.good;
     }
   else if(sig)
     {
      mode="EXEC READY";
      modeFg=newsWarn ? p.warn : p.text;
      modeBg=newsWarn ? p.cStepActive : p.panel2;
      modeBr=newsWarn ? p.warn : p.accent;
     }
   else if(newsWarn)
     {
      mode="GUARD WATCH";
      modeFg=p.warn;
      modeBg=p.cStepActive;
      modeBr=p.warn;
     }

   DrawBox(p,statusX,CCTD_SHELL_Y+16,statusW,29,modeBg,modeBr);
   DashTextCentered("HEAD_MODE",mode,statusX,CCTD_SHELL_Y+16,statusW,29,8,modeFg,false);

   DrawBox(p,7,CCTD_SHELL_Y+59,72,CCTD_SHELL_H-73,p.inner,p.border);

   string tabs[4]={"SIG","RISK","SAFE","LOG"};

   for(int i=0;i<4;i++)
     {
      int ty=CCTD_SHELL_Y+66+i*38;
      bool active=(i==g_dashTab);

      DrawButtonSkin(p,"TAB"+IntegerToString(i),tabs[i],
                     12,ty,62,32,
                     active ? p.panel2 : p.panel3,
                     active ? p.text : p.muted,
                     p.borderSoft,
                     8);
     }

   int toneY=CCTD_SHELL_Y+CCTD_SHELL_H-42;
   bool dimMode=DashDimLightMode();
   DrawButtonSkin(p,"TONE",dimMode ? "DIM" : "DARK",
                  12,toneY,62,24,
                  dimMode ? p.panel2 : p.inner,
                  dimMode ? p.accent : p.dim,
                  dimMode ? p.accent : p.borderSoft,7);
  }





void DrawSignalTab(const DashPalette &p)
  {
   int x=88;
   int y=CCTD_SHELL_Y+67;
   int w=420;
   int gap=6;
   int col=(w-gap)/2;

   bool live=(DashOpenPositionCount()>0);
   bool hasSignal=(!live && DashSignalDisplayActive());
   int last=live ? DashLiveExecIndex() : (hasSignal ? DashLastExecIndex() : DashLastResolvedExecIndex());

   bool bull=true;
   string gen="-";
   string model="-";
   string side="-";
   string state="waiting";
   double entry=0.0,sl=0.0,tp=0.0,be=0.0;
   SIB_STATE outcome=SS_UNKNOWN_OUTCOME;
   datetime c1=0,c2=0,c3=0;
   datetime exitTime=0;
   double exitPrice=0.0;

   if(hasSignal)
     {
      bull=g_sigBull;
      gen=GenKey(g_sigBull,g_sigBirthTime);
      model=g_sigModelLabel;
      side=bull ? "BUY" : "SELL";
      state=DashStateLabel(g_sigState);
      entry=g_sigEntryPx;
      sl=g_sigSlPx;
      tp=g_sigTpPx;
      be=DashGlobalBEPrice(g_sigBull,g_sigEntryPx,g_sigTpPx);
      outcome=g_sigState;
      c1=g_sigC1Time;
      c2=g_sigC2Time;
      c3=g_sigC3Time;
     }
   else if(last>=0)
     {
      bull=g_execRecords[last].bull;
      gen=g_execRecords[last].genKey;
      model=ModelTypeLabel(g_execRecords[last].modelType);
      side=bull ? "BUY" : "SELL";
      state=live ? "managing" : DashOutcomeLabel(g_execRecords[last].outcome);
      entry=(g_execRecords[last].brokerFill>0.0) ? g_execRecords[last].brokerFill : g_execRecords[last].visualEntry;
      sl=g_execRecords[last].brokerSL;
      tp=g_execRecords[last].brokerTP;
      be=(g_execRecords[last].bePrice>0.0) ? g_execRecords[last].bePrice : DashGlobalBEPrice(g_execRecords[last].bull,entry,tp);
      outcome=g_execRecords[last].outcome;
      c1=g_execRecords[last].c1Time;
      c2=g_execRecords[last].c2Time;
      c3=g_execRecords[last].c3Time;
      exitTime=g_execRecords[last].exitTime;
      exitPrice=g_execRecords[last].exitPrice;
     }

   if(live && entry<=0.0)
     {
      for(int pidx=PositionsTotal()-1;pidx>=0;pidx--)
        {
         ulong ticket=PositionGetTicket(pidx);
         if(ticket>0 && PositionSelectByTicket(ticket))
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && (long)PositionGetInteger(POSITION_MAGIC)==CCTEffectiveMagic())
              {
               bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
               bull=buy;
               side=buy ? "BUY" : "SELL";
               entry=PositionGetDouble(POSITION_PRICE_OPEN);
               sl=PositionGetDouble(POSITION_SL);
               tp=PositionGetDouble(POSITION_TP);
               break;
              }
        }
     }

   bool fallback=(!hasSignal && !live);
   string sigALabel=fallback ? "Bias" : "Generation";
   string sigAValue=fallback ? side : gen;

   DrawKVBox(p,"SIG_A",sigALabel,sigAValue,x,y,col,38,fallback ? (bull ? p.good : p.bad) : p.text);
   DrawKVBox(p,"SIG_B","Model",side+" "+model,x+col+gap,y,col,38,p.text);

   string cardCLabel=hasSignal ? "POI / sibling" : (live ? "Live execution" : "Last result");
   string cardCValue=hasSignal ? ("POI "+DashPrice(g_sigLevel)) : (live ? ("TKT "+IntegerToString((long)DashOpenTicket())) : state);
   color resultClr=hasSignal ? p.accent : (live ? p.good : DashOutcomeColor(p,outcome));
   if(fallback && entry>0.0 && sl>0.0 && exitPrice>0.0)
     {
      double risk=MathAbs(entry-sl);
      if(risk>_Point*0.1)
        {
         double rr=(bull ? (exitPrice-entry) : (entry-exitPrice))/risk;
         cardCValue=state+" "+DoubleToString(rr,2)+"R";
         resultClr=(rr>0.0 ? p.good : (rr<0.0 ? p.bad : p.warn));
        }
     }

   string trigLabel=fallback ? "Exit" : "Trigger state";
   string trigValue=fallback ? ((exitTime>0 ? DashClock(exitTime,false) : "--:--")+" @ "+DashPrice(exitPrice)) : state;

   DrawKVBox(p,"SIG_C",cardCLabel,cardCValue,x,y+44,col,38,resultClr,p.panel2,hasSignal ? p.accent : p.borderSoft);
   DrawKVBox(p,"SIG_D",trigLabel,trigValue,x+col+gap,y+44,col,38,live ? p.good : resultClr);

   int stepY=y+88;
   int stepW=(w-12)/3;

   bool tradeComplete=(live ||
                       outcome==SS_TRIGGERED ||
                       DashIsResolvedOutcome(outcome) ||
                       exitTime>0 ||
                       exitPrice>0.0);
   int c1Mode=(tradeComplete || c1>0 ? 1 : 0);
   int c2Mode=(tradeComplete || c3>0 ? 1 : (c2>0 ? 2 : 0));
   int c3Mode=(tradeComplete || c3>0 ? 1 : 0);

   DrawCStep(p,"C1","C1",x,stepY,stepW,c1Mode,c1);
   DrawCStep(p,"C2","C2",x+stepW+6,stepY,stepW,c2Mode,c2);
   DrawCStep(p,"C3","C3",x+2*(stepW+6),stepY,stepW,c3Mode,c3);

   int levY=stepY+38;
   int levW=(w-18)/4;
   string beText=(be>0.0 ? DashPrice(be) : (CCTRuntimeBEGlobalEnabled() ? "pending" : "off"));

   DrawKVBox(p,"LEV_ENTRY",live ? "Fill" : (hasSignal ? "Entry ref" : "Fill"),DashPrice(entry),x,levY,levW,38,p.text);
   DrawKVBox(p,"LEV_BE",fallback ? "Generation" : "BE target",fallback ? DashShort(gen,14) : beText,x+levW+6,levY,levW,38,fallback ? p.text : p.warn,p.panel2,fallback ? p.borderSoft : p.warn);
   DrawKVBox(p,"LEV_SL","Stop loss",DashPrice(sl),x+2*(levW+6),levY,levW,38,p.bad,p.slSoft,p.bad);
   DrawKVBox(p,"LEV_TP",hasSignal ? "Take profit" : "Planned TP",DashPrice(tp),x+3*(levW+6),levY,levW,38,p.good,p.tpSoft,p.good);

   DrawKVBox(p,"SIG_E","Session authority","NY 07-11 OK",x,levY+44,col,38,p.good);
   DrawKVBox(p,"SIG_F",live ? "Execution rule" : (hasSignal ? "Execution rule" : "Fallback display"),
             live ? "Managing broker position" : (hasSignal ? "Wait for C3" : "Previous trade + planned TP"),
             x+col+gap,levY+44,col,38,live ? p.good : (hasSignal ? p.warn : p.muted));

   string eventText=live ? "Live trade: C1/C2/C3 are read from the execution record; ticket remains in the header." :
                    (hasSignal ? "Setup forming. C2/C3 can regress and reactivate while price builds." :
                     "Flat fallback keeps previous trade details, including planned TP after SL.");

   DrawEvent(p,"SIG_EVT",live ? "LIVE" : (hasSignal ? "SCAN" : "FALLBACK"),eventText,x,levY+88,w,true);
  }





void DrawRiskProgressBox(const DashPalette &p,const string id,string label,double r,int x,int y,int w,int h,color clr)
  {
   DrawBox(p,x,y,w,h,p.panel2,p.borderSoft);

   DashText(id+"_L",label,x+6,y+5,7,p.dim);
   DashText(id+"_V",DoubleToString(r,2)+"R",x+6,y+19,8,clr,true);

   int bx=x+8;
   int by=y+h-10;
   int bw=w-16;
   int bh=4;
   FillRect(bx,by,bx+bw,by+bh,DashA(p.inner,255));

   double pct=MathMin(1.0,MathAbs(r)/2.0);
   int fw=(int)MathRound((double)bw*pct);

   if(fw>0)
      FillRect(bx,by,bx+fw,by+bh,DashA(clr,255));
  }


void DrawSafeToggleStepper(const DashPalette &p,const string id,string label,string value,int x,int y,int w,bool onState)
  {
   DrawBox(p,x,y,w,46,p.panel,p.borderSoft);
   DashText("SAFE_CTL_"+id+"_L",DashShort(label,16),x+6,y+5,7,p.dim);

   color vBg=onState ? p.tpSoft : p.slSoft;
   color vClr=onState ? p.good : p.bad;
   int valueW=w-62;

   DrawBox(p,x+6,y+23,valueW,17,vBg,onState ? p.good : p.bad);
   DashTextCentered("SAFE_CTL_"+id+"_V",value,x+6,y+23,valueW,17,7,vClr,false);
   DashHit("CTL_"+id+"_TOGGLE",x+6,y+23,valueW,17);

   DrawButtonSkin(p,"CTL_"+id+"_MINUS","-",x+w-52,y+23,22,17,p.inner,p.text,p.borderSoft,7);
   DrawButtonSkin(p,"CTL_"+id+"_PLUS","+",x+w-27,y+23,22,17,p.inner,p.text,p.borderSoft,7);
  }


void DrawSafeValueBox(const DashPalette &p,const string id,string label,string value,int x,int y,int w,color valueClr)
  {
   DrawBox(p,x,y,w,46,p.panel,p.borderSoft);
   DashText("SAFE_VAL_"+id+"_L",DashShort(label,15),x+6,y+5,7,p.dim);
   DashTextCentered("SAFE_VAL_"+id+"_V",DashShort(value,15),x+6,y+23,w-12,17,7,valueClr,true);
  }


void DrawSafeActionBox(const DashPalette &p,const string id,string label,string value,int x,int y,int w,color valueClr,color bg,color br)
  {
   DrawBox(p,x,y,w,46,p.panel,p.borderSoft);
   DashText("SAFE_ACT_"+id+"_L",DashShort(label,15),x+6,y+5,7,p.dim);
   DrawBox(p,x+6,y+23,w-12,17,bg,br);
   DashTextCentered("SAFE_ACT_"+id+"_V",DashShort(value,15),x+6,y+23,w-12,17,7,valueClr,false);
   DashHit("CTL_"+id,x+6,y+23,w-12,17);
  }

void DrawRiskTab(const DashPalette &p)
  {
   int x=88;
   int y=CCTD_SHELL_Y+69;
   int w=420;
   int gap=6;
   int col2=(w-gap)/2;
   int col3=(w-12)/3;

   DashTradeSnapshot live;
   DashTradeSnapshot snap;
   bool hasLive=DashGetLiveTradeSnapshot(live);
   bool hasSnap=DashGetLastTradeSnapshot(snap);
   bool hasSignal=DashSignalDisplayActive();

   string liveLine="No active trade";
   double entry=0.0;
   double sl=0.0;
   double tp=0.0;
   double be=0.0;
   double vol=0.0;
   double pr=0.0;
   color prClr=p.dim;
   ulong ticket=0;

   if(hasLive)
     {
      liveLine=StringFormat("%s %.2f @ %s",live.bull ? "BUY" : "SELL",live.volume,DashPrice(live.entry));
      entry=live.entry;
      sl=live.sl;
      tp=live.tp;
      be=live.be;
      vol=live.volume;
      pr=DashProgressR(live);
      prClr=(pr>=0.0 ? p.good : p.bad);
      ticket=live.ticket;
     }
   else if(hasSignal)
     {
      liveLine="Signal forming";
      entry=g_sigEntryPx;
      sl=g_sigSlPx;
      tp=g_sigTpPx;
      be=DashGlobalBEPrice(g_sigBull,entry,tp);
      prClr=p.warn;
     }
   else if(hasSnap)
     {
      liveLine="Previous "+snap.result;
      entry=snap.entry;
      sl=snap.sl;
      tp=snap.tp;
      be=snap.be;
      vol=snap.volume;
      pr=DashFrozenProgressR(snap);
      prClr=DashOutcomeColor(p,snap.outcome);
      ticket=snap.ticket;
     }

   string tradeLabel=hasLive ? "Live execution" : (hasSnap ? "Previous trade" : (hasSignal ? "Signal" : "Trade state"));
   DrawKVBox(p,"RISK_LIVE",tradeLabel,liveLine,x,y,col2,38,hasLive ? p.good : (hasSnap ? p.text : p.dim));
   DrawKVBox(p,"RISK_FILL",hasLive ? "Fill / lots" : "Fill / lots",
             (hasLive && ticket>0 ? IntegerToString((long)ticket) : DashPrice(entry))+" / "+DashLots(vol),
             x+col2+gap,y,col2,38,p.text);

   if(hasLive || hasSnap)
      DrawRiskProgressBox(p,"RISK_PROG","Open progress",pr,x,y+46,col2,46,prClr);
   else
      DrawKVBox(p,"RISK_PROG","Open progress",hasSignal ? "Signal forming" : "flat",x,y+46,col2,46,hasSignal ? p.warn : p.dim);

   DrawKVBox(p,"RISK_BE","BE target",be>0.0 ? DashPrice(be) : "pending",x+col2+gap,y+46,col2,46,be>0.0 ? p.warn : p.dim);

   int fy=y+100;

   DrawSelectField(p,"RBASIS","Risk basis",CCTAccModeLabel(),x,fy,col3);
   DrawField(p,"RISK","Risk %",DoubleToString(g_riskPct,2),x+col3+gap,fy,col3);
   DrawField(p,"CUSTOM","Custom bal",DoubleToString(CCTEffectiveCustomCapital(),0),x+2*(col3+gap),fy,col3);

   DrawField(p,"RR","RR target",DoubleToString(g_rrPreset,2),x,fy+42,col3);
   DrawField(p,"DL","Daily loss %",DoubleToString(CCTEffectiveDailyLossLimitPct(),2),x+col3+gap,fy+42,col3);
   DrawSelectField(p,"DAILY_BASIS","Daily guard basis",CCTDailyLossBasisLabel(),x+2*(col3+gap),fy+42,col3);

   int boxY=fy+84;
   int boxW=(w-gap)/2;

   DrawKVBox(p,"RSL","Broker SL",DashPrice(sl),x,boxY,boxW,46,p.bad,p.slSoft,p.bad);
   DrawKVBox(p,"RTP","Broker TP",DashPrice(tp),x+boxW+gap,boxY,boxW,46,p.good,p.tpSoft,p.good);

   double base=EffectiveAccountBase();
   double tradeRisk=base*(g_riskPct/100.0);
   double dailyCap=base*(CCTEffectiveDailyLossLimitPct()/100.0);
   string riskLine="Trade cap "+DoubleToString(tradeRisk,2)+" | Daily cap "+DoubleToString(dailyCap,2)+" | "+CCTAccModeLabel();

   DrawEvent(p,"RISK_EVT","RISK",riskLine,x,boxY+54,w,false);
  }





void DrawSafeTab(const DashPalette &p)
  {
   int x=88;
   int y=CCTD_SHELL_Y+67;
   int w=420;
   int gap=6;
   int col2=(w-gap)/2;
   int col3=(w-12)/3;

   string dl=CCTEffectiveDailyLossGuard() ? "active" : "disabled";
   color dlClr=CCTEffectiveDailyLossGuard() ? p.good : p.muted;

   if(CCTEffectiveDailyLossGuard())
     {
      dl=g_propGuardCacheReady ?
         StringFormat("%.2f / %.2f",g_propCachedLossUsed,g_propCachedLossCap) :
         "warming";
      dlClr=g_propCachedDailyBreached ? p.bad : p.good;
     }

   string news=CCTDashboardNewsText();
   color newsClr=CCTDashboardNewsWarn() ? p.warn : (CCTEffectiveNewsFilter() ? p.good : p.muted);
   double spreadPts=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   string mgmtReason="";
   bool mgmtBlocked=CCTTradeManagementBlocked(mgmtReason);

   DrawKVBox(p,"SAFE_DAILY","Daily loss guard",dl,x,y,col2,38,dlClr);
   DrawKVBox(p,"SAFE_NEWS","News guard",news,x+col2+gap,y,col2,38,newsClr);
   DrawKVBox(p,"SAFE_WEEKEND","Weekend guard",Inp_WeekendGuard ? (g_propCachedEntryWeekendBlocked ? "blocked" : "inactive") : "disabled",
             x,y+42,col2,38,g_propCachedEntryWeekendBlocked ? p.bad : p.muted);
   DrawKVBox(p,"SAFE_SPREAD","Spread guard",DoubleToString(spreadPts,1)+" pts",x+col2+gap,y+42,col2,38,p.good);

   int by=y+88;

   DrawSafeToggleStepper(p,"NEWS","NEWS BLACKOUT",CCTEffectiveNewsFilter() ? "ON" : "OFF",
                         x,by,col3,CCTEffectiveNewsFilter());

   DrawSafeValueBox(p,"BLACKOUT","BLACKOUT MIN",DoubleToString(CCTEffectiveNewsBlackoutMinutes(),1)+"m each side",
                    x+col3+gap,by,col3,p.text);

   DrawSafeActionBox(p,"NEWS_IMPACT","NEWS IMPACT",CCTNewsImpactDashboardLabel(),
                     x+2*(col3+gap),by,col3,p.good,p.tpSoft,p.good);

   int by2=by+50;

   DrawSafeToggleStepper(p,"MINOPEN","MIN OPEN TP",
                         CCTEffectiveMinOpenTPEnabled() ? "ON" : "OFF",
                         x,by2,col3,CCTEffectiveMinOpenTPEnabled());

   DrawSafeValueBox(p,"MINDUR","MIN DURATION",IntegerToString(CCTEffectiveMinOpenMinutes())+" minutes",
                    x+col3+gap,by2,col3,p.text);

   string cutoff=StringFormat("NY %02d:%02d",Inp_WeekendFridayHour,Inp_WeekendFridayMinute);
   DrawSafeValueBox(p,"CUTOFF","FRIDAY CUTOFF",cutoff,x+2*(col3+gap),by2,col3,p.text);

   int by3=by2+52;
   bool entryBlocked=(g_propCachedEntryNewsBlocked || g_propCachedEntryWeekendBlocked || g_propCachedDailyBreached);

   DrawKVBox(p,"SAFE_ENTRY","Entry permission",entryBlocked ? "blocked" : "allowed",x,by3,col2,38,entryBlocked ? p.warn : p.good);
   DrawKVBox(p,"SAFE_MGMT","BE / TP edits",mgmtBlocked ? DashShort(mgmtReason,20) : "allowed",x+col2+gap,by3,col2,38,mgmtBlocked ? p.warn : p.good);

   int noteY=by3+44;
   DrawNoteBox(p,"SAFE_NOTE","SAFE","Calendar: MT5 + manual overrides. No News / Currency News / Lock states.",
               DashSafeFooterLine(),x,noteY,w,54,p.text);

   DrawEvent(p,"SAFE_EVT","SAFE","+/- edits blackout and min-open at runtime. Impact cycles by click.",x,noteY+60,w,false);
  }





void DrawLogTab(const DashPalette &p)
  {
   int x=88;
   int y=CCTD_SHELL_Y+69;
   int w=420;
   int row=36;

   DashTradeSnapshot live;
   DashTradeSnapshot snap;
   bool hasLive=DashGetLiveTradeSnapshot(live);
   bool hasSnap=DashGetLastTradeSnapshot(snap);
   bool hasSignal=DashSignalDisplayActive();

   string scanText="Scanner: no active candidate; fallback mode.";
   string stateText="State: waiting for next candidate, C1, trigger, or broker update.";
   string execText="Execution: no open CCT trade.";
   string exitText="Exit: no resolved trade in CCT record cache.";
   string tagScan="SCAN";
   string tagNews="NEWS";
   string tagExec="EXEC";
   string tagState="STATE";
   string tagExit="EXIT";

   if(hasLive)
     {
      scanText="Scanner: live position has dashboard priority over signal globals.";
      execText="Execution: "+StringFormat("%s mapped to %s",live.model,DashShort(live.gen,24))+".";
      stateText="State: "+StringFormat("%s %.2f | fill %s | %s",live.bull ? "BUY" : "SELL",live.volume,DashPrice(live.entry),DashProgressText(live))+".";
      tagExec=DashClock(live.triggerTime>0 ? live.triggerTime : 0,false);
      tagState=tagExec;
     }
   else if(hasSignal)
     {
      scanText="Scanner: "+GenKey(g_sigBull,g_sigBirthTime)+" | "+DashStateLabel(g_sigState)+".";
      stateText="State: "+g_sigModelLabel+" | C1 "+(g_sigC1 ? "done" : "wait")+" / C2 "+(g_sigC2 ? "done" : "wait")+" / C3 "+(g_sigC3 ? "done" : "wait")+".";
      tagScan=DashClock(g_sigBirthTime,false);
      tagState=tagScan;
     }
   else if(hasSnap)
     {
      scanText="Scanner: no active candidate; previous resolved trade is pinned.";
      execText="Execution: "+snap.model+" mapped to "+DashShort(snap.gen,24)+".";
      tagExec=DashClock(snap.triggerTime,false);
      stateText="State: "+snap.result+" | sweeps "+IntegerToString(snap.sweepCount)+" | "+(snap.bull ? "BUY" : "SELL")+".";
      tagState=tagExec;
     }

   if(hasSnap)
     {
      exitText="Exit: "+snap.result+" at "+DashPrice(snap.exitPx)+"; entry "+DashPrice(snap.entry)+".";
      tagExit=DashClock(snap.exitTime,false);
     }

   string newsText="News: "+CCTDashboardNewsText()+".";

   if(CCTDashboardNewsWarn())
      newsText="News: "+CCTDashboardNewsText()+"; watch/blackout active.";
   else if(!CCTEffectiveNewsFilter())
      newsText="News: filter off; entries ignore calendar guard.";
   else
      newsText="News: no high-impact news in the active warning window.";

   DrawEvent(p,"LOG_SCAN",tagScan,scanText,x,y,w,true);
   DrawEvent(p,"LOG_STATE",tagState,stateText,x,y+row,w,false);
   DrawEvent(p,"LOG_EXEC",tagExec,execText,x,y+2*row,w,false);
   DrawEvent(p,"LOG_EXIT",tagExit,exitText,x,y+3*row,w,false);
   DrawEvent(p,"LOG_NEWS",tagNews,newsText,x,y+4*row,w,false);
   DrawEvent(p,"LOG_STATUS","DASH","Fallback rows stay pinned until a new live candidate or trade appears.",x,y+5*row,w,false);
  }






void RenderCollapsed(const DashPalette &p)
  {
   FillRect(0,0,CCTD_W-1,CCTD_H-1,DashA(p.page,220));

   DrawBox(p,0,0,CCTD_W,CCTD_BAR_H,p.panel,p.border);

   DashTextCenteredBias("COL_BRAND","CCT",4,5,50,30,10,p.accent,false,0,-1);

   DrawGlowBox(p,58,6,146,30,p.inner,p.accent,p.text);
   DashTextCenteredBias("COL_TIME",DisplayTZLabel()+" "+DashClock(CurrentServerTime(),true),58,6,146,30,10,p.accent,true,-6,-1);

   DrawBox(p,210,6,78,30,p.panel2,p.borderSoft);
   DashTextCenteredBias("COL_SPRD",DashSpreadText(),210,6,78,30,8,p.muted,false,0,-1);

   DrawBox(p,294,6,70,30,p.panel2,p.borderSoft);
   DashTextCenteredBias("COL_SESS",DashSessionChip(),294,6,70,30,8,p.muted,false,0,-1);

   bool newsWarn=CCTDashboardNewsWarn();
   string newsText=newsWarn ? CCTDashboardNewsText() : "NO NEWS";

   DrawGlowBox(p,370,6,106,30,newsWarn ? p.panel2 : p.inner,newsWarn ? p.warn : p.borderSoft,newsWarn ? p.warn : p.good);
   DashTextCenteredBias("COL_NEWS",DashShort(newsText,11),370,6,106,30,8,newsWarn ? p.warn : p.good,false,0,-1);

   DrawBox(p,482,6,42,30,p.inner,p.borderSoft);
   DashTextCenteredBias("COL_TOG",g_dashCollapsed ? "+" : "-",482,6,42,30,10,p.text,true,0,-1);
   DashHit("TOG",482,6,42,30);

   DashHit("DRAG",0,0,476,CCTD_BAR_H);
  }


void RenderExpanded(const DashPalette &p)
  {
   ArrayResize(g_cctDashPixels,CCTD_W*CCTD_H);
   FillRect(0,0,CCTD_W-1,CCTD_H-1,DashA(p.page,220));

   RenderBar(p);
   RenderShellFrame(p);

   if(g_dashTab==0)
      DrawSignalTab(p);
   else if(g_dashTab==1)
      DrawRiskTab(p);
   else if(g_dashTab==2)
      DrawSafeTab(p);
   else
      DrawLogTab(p);
  }

void DashClearTextAndHits()
  {
   string bitmap=DashName("BITMAP");
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,"CCTD_")!=0 || name==bitmap)
         continue;
      ObjectDelete(0,name);
     }
  }

string DashBackgroundKey()
  {
   // CCT_DASHBOARD_STATIC_SKIN_KEY_V1
   // Only changes that alter the bitmap skin should recreate the bitmap
   // resource. Trade state, clocks, spread, news text, and runtime values are
   // label overlays and must not force a full bitmap rebuild every timer pulse.
   return IntegerToString(g_dashTab)+"|"+
          IntegerToString(g_dashCollapsed ? 1 : 0)+"|"+
          IntegerToString(DashDimLightMode() ? 1 : 0)+"|"+
          IntegerToString((int)Inp_DashboardTheme);
  }

string DashOverlayKey()
  {
   if(g_dashCollapsed)
     {
      bool newsWarn=CCTDashboardNewsWarn();
      return DashBackgroundKey()+"|collapsed|"+
             DashSpreadText()+"|"+
             DashSessionChip()+"|"+
             (newsWarn ? CCTDashboardNewsText() : "NO NEWS")+"|"+
             IntegerToString(DashOpenPositionCount());
     }

   string liveSkinKey="no-live";

   DashTradeSnapshot live;
   if(DashGetLiveTradeSnapshot(live))
     {
      double pct=MathMax(-100.0,MathMin(300.0,DashTPProgressPct(live)));
      int progressBucket=(int)MathFloor(pct/10.0);
      liveSkinKey=IntegerToString((long)DashOpenTicket())+"|"+IntegerToString(progressBucket);
     }

   return IntegerToString(g_dashTab)+"|"+
          IntegerToString(g_dashCollapsed ? 1 : 0)+"|"+
          IntegerToString(DashDimLightMode() ? 1 : 0)+"|"+
          IntegerToString((int)Inp_DashboardTheme)+"|"+
          IntegerToString((long)(DashSignalDisplayActive() ? g_sigBirthTime : 0))+"|"+
          IntegerToString((int)(DashSignalDisplayActive() ? g_sigState : SS_UNKNOWN_OUTCOME))+"|"+
          IntegerToString(g_sigC1 ? 1 : 0)+"|"+
          IntegerToString(g_sigC2 ? 1 : 0)+"|"+
          IntegerToString(g_sigC3 ? 1 : 0)+"|"+
          IntegerToString(g_nExecRecords)+"|"+
          CCTDashboardNewsText()+"|"+
          CCTNewsImpactDashboardLabel()+"|"+
          CCTAccModeLabel()+"|"+
          CCTDailyLossBasisLabel()+"|"+
          DoubleToString(g_riskPct,2)+"|"+
          DoubleToString(g_rrPreset,2)+"|"+
          DoubleToString(CCTEffectiveDailyLossLimitPct(),2)+"|"+
          DoubleToString(CCTEffectiveCustomCapital(),2)+"|"+
          IntegerToString(CCTEffectiveMinOpenTPEnabled() ? 1 : 0)+"|"+
          IntegerToString(CCTEffectiveMinOpenMinutes())+"|"+
          IntegerToString(DashOpenPositionCount())+"|"+DashSnapshotKey()+"|"+liveSkinKey;
  }

void DashRenderBitmap()
  {
   DashPalette p=DashPaletteForInputs();

   // Pass 1: create the bitmap skin. Render functions may create temporary
   // labels/hit zones here; those are removed before the final overlay pass.
   DashClearTextAndHits();

   if(g_dashCollapsed)
      RenderCollapsed(p);
   else
      RenderExpanded(p);

   string res=DashResName();
   ResourceFree(res);

   DashBuildScaledPixels();
   bool ok=ResourceCreate(res,g_cctDashScaledPixels,(uint)CCTD_SW,(uint)CCTD_SH,0,0,0,COLOR_FORMAT_ARGB_NORMALIZE);

   if(!ok)
     {
      Print("CCT dashboard ResourceCreate failed. err=",GetLastError());
      return;
     }

   string obj=DashName("BITMAP");

   if(ObjectFind(0,obj)<0)
      ObjectCreate(0,obj,OBJ_BITMAP_LABEL,0,0,0);

   DashApplyObject(obj,false,1800);
   DashSetInteger(obj,OBJPROP_XDISTANCE,g_dashX);
   DashSetInteger(obj,OBJPROP_YDISTANCE,g_dashY);
   DashSetInteger(obj,OBJPROP_XSIZE,CCTD_SW);
   DashSetInteger(obj,OBJPROP_YSIZE,g_dashCollapsed ? CCTD_BAR_SH : CCTD_SH);
   DashSetString(obj,OBJPROP_BMPFILE,res);

   // Pass 2: recreate visible text and click zones AFTER the bitmap object,
   // so MT5 cannot paint the bitmap over expanded-tab labels.
   DashClearTextAndHits();

   if(g_dashCollapsed)
      RenderCollapsed(p);
   else
      RenderExpanded(p);
  }


void DashForceRedraw()
  {
   ulong dashStartUs=GetMicrosecondCount();
   DashClearTextAndHits();
   ResourceFree(DashResName());
   g_dashCleared=false;
   g_dashLastOverlayKey="";

   g_dashLastBgKey="";
   g_dashLastTab=-999;
   g_dashLastCollapsed=!g_dashCollapsed;

   DashRenderBitmap();

   g_dashLastBgKey=DashBackgroundKey();
   g_dashLastOverlayKey=DashOverlayKey();
   g_dashLastTab=g_dashTab;
   g_dashLastCollapsed=g_dashCollapsed;
   g_dashLayoutHoldUntilMs=GetTickCount()+CCTD_LAYOUT_HOLD_MS;
   g_dashOverlayPending=false;

   ChartRedraw(ChartID());

   ulong dashElapsedUs=GetMicrosecondCount()-dashStartUs;
   if((CCTDebugEnabled() || dashElapsedUs>100000) && !CCTSuppressLiveCCTJournals())
      CCTJournalLine(StringFormat("[CCT DASH TIMING] phase=bitmap | collapsed=%s | tab=%d | elapsed_us=%s",
                                  g_dashCollapsed ? "yes" : "no",
                                  g_dashTab,
                                  IntegerToString((long)dashElapsedUs)));
  }

void DashRenderDynamicHeaderOnly(const DashPalette &p)
  {
   if(g_dashCollapsed)
     {
      DashTextCenteredBias("COL_TIME",DisplayTZLabel()+" "+DashClock(CurrentServerTime(),true),58,6,146,30,10,p.accent,true,-6,-1);
      DashTextCenteredBias("COL_SPRD",DashSpreadText(),210,6,78,30,8,p.muted,false,0,-1);
      DashTextCenteredBias("COL_SESS",DashSessionChip(),294,6,70,30,8,p.muted,false,0,-1);

      bool newsWarn=CCTDashboardNewsWarn();
      string newsText=newsWarn ? CCTDashboardNewsText() : "NO NEWS";
      DashTextCenteredBias("COL_NEWS",DashShort(newsText,11),370,6,106,30,8,newsWarn ? p.warn : p.good,false,0,-1);

      DashTextCenteredBias("COL_TOG",g_dashCollapsed ? "+" : "-",482,6,42,30,10,p.text,true,0,-1);
      return;
     }

   DashTextCenteredBias("BAR_TIME",DisplayTZLabel()+" "+DashClock(CurrentServerTime(),true),58,6,146,30,10,p.accent,true,-6,-1);
   DashTextCenteredBias("BAR_SPRD",DashSpreadText(),210,6,78,30,8,p.muted,false,0,-1);
   DashTextCenteredBias("BAR_SESS",DashSessionChip(),294,6,70,30,8,p.muted,false,0,-1);

   bool newsWarn=CCTDashboardNewsWarn();
   string newsText=newsWarn ? CCTDashboardNewsText() : "NO NEWS";
   DashTextCenteredBias("BAR_NEWS",newsText,370,6,106,30,8,newsWarn ? p.warn : p.good,false,0,-1);

   string mode=DashOpenPositionCount()>0 ? "MANAGING" : "STANDBY";
   DashTextCentered("HEAD_MODE",mode,390,CCTD_SHELL_Y+16,118,29,8,DashOpenPositionCount()>0 ? p.good : p.accent,false);
  }

void DashRenderOverlayOnly(bool force=false)
  {
   if(!DashboardRuntimeEnabled())
      return;

   ulong dashStartUs=GetMicrosecondCount();
   uint now=GetTickCount();

   DashPalette p=DashPaletteForInputs();

   if(!force && g_dashCollapsed)
     {
      DashRenderDynamicHeaderOnly(p);
      g_dashLastOverlayKey=DashOverlayKey();
      DashChartRedraw(false);
      return;
     }

   if(!force && g_dashLayoutHoldUntilMs>now)
     {
      g_dashOverlayPending=true;
      DashRenderDynamicHeaderOnly(p);
      DashChartRedraw(false);
      return;
     }

   if(!force && g_dashLastFullOverlayMs>0 && (uint)(now-g_dashLastFullOverlayMs)<CCTD_OVERLAY_THROTTLE_MS)
     {
      g_dashOverlayPending=true;
      DashRenderDynamicHeaderOnly(p);
      DashChartRedraw(false);
      return;
     }

   DashClearTextAndHits();

   if(g_dashCollapsed)
      RenderCollapsed(p);
   else
      RenderExpanded(p);

   g_dashLastOverlayKey=DashOverlayKey();
   g_dashLastFullOverlayMs=now;
   g_dashOverlayPending=false;
   DashChartRedraw(false);

   ulong dashElapsedUs=GetMicrosecondCount()-dashStartUs;
   if((CCTDebugEnabled() || dashElapsedUs>100000) && !CCTSuppressLiveCCTJournals())
      CCTJournalLine(StringFormat("[CCT DASH TIMING] phase=overlay | collapsed=%s | tab=%d | force=%s | elapsed_us=%s",
                                  g_dashCollapsed ? "yes" : "no",
                                  g_dashTab,
                                  force ? "yes" : "no",
                                  IntegerToString((long)dashElapsedUs)));
  }

void CCTDashRefreshAfterRuntimeChange()
  {
   CCTWarmPropFirmSafetyCache(false,1);
   DashRenderOverlayOnly(true);
  }


void CCTDashStepRisk(double delta)
  {
   g_riskPct=NormalizeDouble(MathMax(0.01,MathMin(5.0,g_riskPct+delta)),2);
   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashStepRR(double delta)
  {
   g_rrPreset=NormalizeDouble(MathMax(0.50,MathMin(5.00,g_rrPreset+delta)),2);
   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashStepDailyLoss(double delta)
  {
   double cur=CCTEffectiveDailyLossLimitPct();
   g_cctDashDailyLossLimitOverride=NormalizeDouble(MathMax(0.0,MathMin(20.0,cur+delta)),2);
   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashCycleRiskBasis()
  {
   int cur=(int)CCTEffectiveAccMode();
   cur++;

   if(cur>2)
      cur=0;

   g_cctDashAccModeOverride=cur;

   if(cur==2 && CCTEffectiveCustomCapital()<=0.0)
      g_cctDashCustomCapitalOverride=AccountInfoDouble(ACCOUNT_BALANCE);

   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashStepCustomCapital(double delta)
  {
   double cur=CCTEffectiveCustomCapital();

   if(cur<=0.0)
      cur=AccountInfoDouble(ACCOUNT_BALANCE);

   g_cctDashCustomCapitalOverride=NormalizeDouble(MathMax(0.0,cur+delta),2);
   g_cctDashAccModeOverride=(int)ACC_CUSTOM;

   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashToggleNews()
  {
   g_cctDashNewsFilterOverride=CCTEffectiveNewsFilter() ? 0 : 1;
   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashStepNewsBlackout(double delta)
  {
   double cur=CCTEffectiveNewsBlackoutMinutes();
   g_cctDashNewsBlackoutMinutesOverride=NormalizeDouble(MathMax(1.0,MathMin(30.0,cur+delta)),1);
   CCTDashRefreshAfterRuntimeChange();
  }
void CCTDashToggleDailyGuard()
  {
   g_cctDashDailyLossGuardOverride=CCTEffectiveDailyLossGuard() ? 0 : 1;
   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashCycleDailyBasis()
  {
   int cur=(int)CCTEffectiveDailyLossBasis();
   cur++;

   if(cur>2)
      cur=0;

   g_cctDashDailyLossBasisOverride=cur;

   if(cur==2 && CCTEffectiveDailyLossCustomBalance()<=0.0)
      g_cctDashDailyLossCustomOverride=AccountInfoDouble(ACCOUNT_BALANCE);

   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashToggleMinOpen()
  {
   g_cctDashMinOpenTPOverride=CCTEffectiveMinOpenTPEnabled() ? 0 : 1;

   if(g_cctDashMinOpenMinutesOverride<0)
      g_cctDashMinOpenMinutesOverride=CCTEffectiveMinOpenMinutes();

   CCTDashRefreshAfterRuntimeChange();
  }

void CCTDashStepMinOpen(int delta)
  {
   int cur=CCTEffectiveMinOpenMinutes();

   g_cctDashMinOpenMinutesOverride=MathMax(0,cur+delta);
   g_cctDashMinOpenTPOverride=(g_cctDashMinOpenMinutesOverride>0) ? 1 : 0;

   CCTDashRefreshAfterRuntimeChange();
  }

void DashCycleMode()
  {
   if(g_dashModeOverride<0)
      g_dashModeOverride=DashDimLightMode() ? 0 : 1;
   else
      g_dashModeOverride=(g_dashModeOverride==1) ? 0 : 1;

   DashForceRedraw();
  }

/*
Purpose: Debounce queued dashboard clicks so one delayed burst cannot toggle or tab-switch repeatedly.
Constitution: Dashboard interaction is visual/runtime control only; it must not block or corrupt scanner/execution state.
Inputs: sp - clicked dashboard object name.
Outputs: True when the click should be handled.
*/
bool DashAcceptClick(const string sp)
  {
   uint now=GetTickCount();
   g_dashLastInteractionMs=now;
   if(now<g_dashLayoutHoldUntilMs &&
      (sp==DashName("TOG") ||
       sp==DashName("MODE") ||
       sp==DashName("TONE") ||
       StringFind(sp,DashName("TAB"))==0))
      return false;

   if(g_dashLastClickMs>0 && sp==g_dashLastClickObj && (uint)(now-g_dashLastClickMs)<120)
      return false;

   g_dashLastClickObj=sp;
   g_dashLastClickMs=now;
   return true;
  }

void DashChartRedraw(bool force=false)
  {
   static uint s_lastRedrawMs=0;
   uint now=GetTickCount();
   if(!force && s_lastRedrawMs>0 && (uint)(now-s_lastRedrawMs)<250)
      return;

   s_lastRedrawMs=now;
   ChartRedraw(ChartID());
  }


void ClearDashboards()
  {
   if(g_dashCleared)
      return;

   ObjectsDeleteAll(0,"CCTD_");
   ResourceFree(DashResName());
   g_dashLastOverlayKey="";
   g_dashCleared=true;
   DashChartRedraw(true);
  }

void InitDashboards()
  {
   if(!DashboardRuntimeEnabled())
      return;

   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);

   DashClearTextAndHits();
   ResourceFree(DashResName());
   g_dashCleared=false;
   g_dashLastOverlayKey="";

   g_dashLastBgKey="";
   g_dashLastTab=-999;
   g_dashLastCollapsed=!g_dashCollapsed;

   DashRenderBitmap();

   g_dashLastBgKey=DashBackgroundKey();
   g_dashLastOverlayKey=DashOverlayKey();
   g_dashLastTab=g_dashTab;
   g_dashLastCollapsed=g_dashCollapsed;

   DashChartRedraw(true);
  }


void UpdateDashboards()
  {
   if(!DashboardRuntimeEnabled())
     {
      ClearDashboards();
      return;
     }

   string key=DashBackgroundKey();

   bool needsFull=(key!=g_dashLastBgKey ||
                   g_dashLastTab!=g_dashTab ||
                   g_dashLastCollapsed!=g_dashCollapsed ||
                   ObjectFind(0,DashName("BITMAP"))<0);

   if(needsFull)
     {
      DashForceRedraw();
      return;
     }

   string overlayKey=DashOverlayKey();
   if(overlayKey!=g_dashLastOverlayKey)
     {
      DashRenderOverlayOnly();
      return;
     }

   DashPalette p=DashPaletteForInputs();
   DashRenderDynamicHeaderOnly(p);

   DashChartRedraw(false);
  }





void HandleDashboardEvent(int id,long lp,double dp,string sp)
  {
   if(!DashboardRuntimeEnabled())
      return;

   if(id==CHARTEVENT_OBJECT_DRAG)
     {
      g_dashLastInteractionMs=GetTickCount();
      if(sp==DashName("BITMAP") || sp==DashName("DRAG"))
        {
         int nx=(int)ObjectGetInteger(0,sp,OBJPROP_XDISTANCE);
         int ny=(int)ObjectGetInteger(0,sp,OBJPROP_YDISTANCE);

         if(nx>=0 && ny>=0)
           {
            g_dashX=nx;
            g_dashY=ny;
            DashForceRedraw();
           }
        }

      return;
     }

   if(id==CHARTEVENT_CLICK || id==CHARTEVENT_OBJECT_CLICK)
     {
      string mapped=DashClickTargetFromPoint((int)lp,(int)dp);
      if(mapped!="")
         sp=mapped;
      else if(id==CHARTEVENT_CLICK)
         return;
     }
   else
      return;

   if(!DashAcceptClick(sp))
      return;

   if(sp==DashName("TOG"))
     {
      g_dashCollapsed=!g_dashCollapsed;
      DashForceRedraw();
      return;
     }

   if(sp==DashName("MODE") || sp==DashName("TONE"))
     {
      DashCycleMode();
      return;
     }

   for(int i=0;i<4;i++)
     {
      if(sp==DashName("TAB"+IntegerToString(i)))
        {
         g_dashTab=i;
         DashForceRedraw();
         return;
        }
     }

   if(sp==DashName("CTL_RISK_MINUS")) { CCTDashStepRisk(-0.25); return; }
   if(sp==DashName("CTL_RISK_PLUS"))  { CCTDashStepRisk(0.25);  return; }

   if(sp==DashName("CTL_RR_MINUS")) { CCTDashStepRR(-0.25); return; }
   if(sp==DashName("CTL_RR_PLUS"))  { CCTDashStepRR(0.25);  return; }

   if(sp==DashName("CTL_DL_MINUS")) { CCTDashStepDailyLoss(-0.25); return; }
   if(sp==DashName("CTL_DL_PLUS"))  { CCTDashStepDailyLoss(0.25);  return; }

   if(sp==DashName("CTL_RBASIS") || sp==DashName("CTL_RBASIS_MINUS") || sp==DashName("CTL_RBASIS_PLUS"))
     {
      CCTDashCycleRiskBasis();
      return;
     }

   if(sp==DashName("CTL_CUSTOM_MINUS")) { CCTDashStepCustomCapital(-100.0); return; }
   if(sp==DashName("CTL_CUSTOM_PLUS"))  { CCTDashStepCustomCapital(100.0);  return; }

   if(sp==DashName("CTL_DAILY_BASIS") || sp==DashName("CTL_DAILY_BASIS_MINUS") || sp==DashName("CTL_DAILY_BASIS_PLUS"))
     {
      CCTDashCycleDailyBasis();
      return;
     }

   if(sp==DashName("CTL_NEWS_TOGGLE"))
     {
      CCTDashToggleNews();
      return;
     }

   if(sp==DashName("CTL_NEWS_MINUS")) { CCTDashStepNewsBlackout(-1.0); return; }
   if(sp==DashName("CTL_NEWS_PLUS"))  { CCTDashStepNewsBlackout(1.0);  return; }

   if(sp==DashName("CTL_NEWS_IMPACT"))
     {
      CCTCycleNewsImpactDashboard();
      CCTDashRefreshAfterRuntimeChange();
      return;
     }

   if(sp==DashName("CTL_DAILY_TOGGLE") || sp==DashName("CTL_DAILY_GUARD_TOGGLE"))
     {
      CCTDashToggleDailyGuard();
      return;
     }

   if(sp==DashName("CTL_MINOPEN_TOGGLE") || sp==DashName("CTL_MINOPEN"))
     {
      CCTDashToggleMinOpen();
      return;
     }

   if(sp==DashName("CTL_MINOPEN_MINUS"))
     {
      CCTDashStepMinOpen(-1);
      return;
     }

   if(sp==DashName("CTL_MINOPEN_PLUS"))
     {
      CCTDashStepMinOpen(1);
      return;
     }
  }



#endif















