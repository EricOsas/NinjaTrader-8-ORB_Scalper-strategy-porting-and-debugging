#ifndef CCT_VISUAL_MQH
#define CCT_VISUAL_MQH

#include "CCT_Globals.mqh"

/*
Purpose: Delete a single owned chart object if it exists.
Constitution: Ch. 26 object ownership and end-of-life handling.
Inputs: name - object name.
Outputs: None.
*/
void DeleteObj(string name)
  {
   if(ObjectFind(0,name)>=0)
      ObjectDelete(0,name);
  }

/*
Purpose: Write-through integer setter for scalar chart object properties.
Constitution: Ch. 26.3 non-destructive drawing and pass-1 write-through requirement.
Inputs: n - object name, p - integer property, v - desired value.
Outputs: None.
*/
void _dsi(string n,ENUM_OBJECT_PROPERTY_INTEGER p,long v)
  {
   if(ObjectFind(0,n)<0)
      return;
   if(ObjectGetInteger(0,n,p)==v)
      return;
   ObjectSetInteger(0,n,p,v);
  }

/*
Purpose: Write-through integer setter for point-indexed chart object properties.
Constitution: Ch. 26.3 non-destructive drawing and MT5 anchoring rules.
Inputs: n - object name, p - integer property, modifier - point index, v - desired value.
Outputs: None.
*/
void _dsi(string n,ENUM_OBJECT_PROPERTY_INTEGER p,int modifier,long v)
  {
   if(ObjectFind(0,n)<0)
      return;
   if(ObjectGetInteger(0,n,p,modifier)==v)
      return;
   ObjectSetInteger(0,n,p,modifier,v);
  }

/*
Purpose: Write-through string setter for chart object properties.
Constitution: Ch. 26.3 non-destructive drawing and tooltip requirements.
Inputs: n - object name, p - string property, v - desired value.
Outputs: None.
*/
void _dss(string n,ENUM_OBJECT_PROPERTY_STRING p,string v)
  {
   if(ObjectFind(0,n)<0)
      return;
   if(ObjectGetString(0,n,p)==v)
      return;
   ObjectSetString(0,n,p,v);
  }
/*
Purpose: Format a New York timestamp for compact chart-object tooltips.
Constitution: Visual-layer tooltip formatting only; no scanner or execution state is changed.
Inputs: t - server-time timestamp, includeSeconds - whether to include seconds.
Outputs: User-facing NY time label, or "-" when unavailable.
*/
string CCTNYTimeLabel(datetime t,bool includeSeconds)
  {
   if(t<=0)
      return "-";
   return CCTTooltipTimeStamp(t,includeSeconds);
  }

/*
Purpose: Format a compact New York clock label for dense multi-line tooltips.
Constitution: Visual-layer formatting only; no scanner or execution state is changed.
Inputs: t - server-time timestamp, includeSeconds - whether to include seconds.
Outputs: HH:MM or HH:MM:SS NY label, or "-" when unavailable.
*/
string CCTNYClockLabel(datetime t,bool includeSeconds)
  {
   if(t<=0)
      return "-";
   return CCTTooltipClockStamp(t,includeSeconds);
  }

color CCTCandidateColor(bool bull)
  {
   return bull ? (color)C'78,86,98' : (color)C'98,86,78';
  }

color CCTCandidateGlowColor(bool bull)
  {
   return bull ? (color)C'48,56,68' : (color)C'68,56,48';
  }

color CCTRGB(int r,int g,int b)
  {
   r=(int)MathMax(0,MathMin(255,r));
   g=(int)MathMax(0,MathMin(255,g));
   b=(int)MathMax(0,MathMin(255,b));
   return (color)(r | (g<<8) | (b<<16));
  }

color CCTCandidatePulseColor(bool bull,bool glow)
  {
   double wave=(MathSin((double)(GetTickCount()%2400)/2400.0*6.28318530718)+1.0)*0.5;
   int baseR=bull ? (glow ? 40 : 72) : (glow ? 60 : 90);
   int baseG=bull ? (glow ? 48 : 80) : (glow ? 48 : 80);
   int baseB=bull ? (glow ? 60 : 92) : (glow ? 40 : 72);
   int lift=glow ? (int)(12.0*wave) : (int)(18.0*wave);
   return CCTRGB(baseR+lift,baseG+lift,baseB+lift);
  }

color CCTCandidateAPColor(bool bull)
  {
   return bull ? (color)C'70,74,82' : (color)C'82,74,70';
  }

string CCTCandidateExecLabel(datetime candidateBarTime)
  {
   if(candidateBarTime<=0)
      return "Exec -";

   string out="";
   for(int offset=1;offset<=3;offset++)
     {
      datetime execOpen=0;
      datetime execEnd=0;
      if(!ResolveBirthOffsetExecutionWindow(candidateBarTime,offset,execOpen,execEnd))
         continue;

      MqlDateTime ny={};
      TimeToStruct(ToNY(execOpen),ny);
      string part="H+"+IntegerToString(offset)+" "+IntegerToString(ny.hour)+":00 "+ExecHourLabel(ny.hour);
      if(out=="")
         out=part;
      else
         out+=" | "+part;
     }

   return (out=="") ? "Exec -" : out;
  }

bool CandidateCloseBeyond(bool bull,double close,double level)
  {
   double tol=MathMax(_Point*0.1,1e-8);
   return bull ? (close>level+tol) : (close<level-tol);
  }

int LatestLTFIndexInHTF(MqlRates &ltf[],int nl,datetime htfOpen)
  {
   int htfSec=(int)PeriodSeconds(HTF());
   if(htfOpen<=0 || htfSec<=0)
      return -1;

   datetime htfEnd=htfOpen+(datetime)htfSec;
   int latest=-1;
   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time<htfOpen || ltf[k].time>=htfEnd)
         continue;
      if(latest<0 || ltf[k].time>ltf[latest].time)
         latest=k;
     }
   return latest;
  }

bool CandidateLineActiveFromLTF(bool bull,double level,datetime candidateBarTime,MqlRates &ltf[],int nl)
  {
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double live=(bid>0.0 && ask>0.0) ? (bid+ask)*0.5 : MathMax(bid,ask);
   if(live>0.0 && CandidateCloseBeyond(bull,live,level))
      return true;

   int latest=LatestLTFIndexInHTF(ltf,nl,candidateBarTime);
   if(latest<0)
      return false;
   return CandidateCloseBeyond(bull,ltf[latest].close,level);
  }

bool CandidateAPQuarterActiveFromLTF(bool bull,double level,datetime candidateBarTime,MqlRates &ltf[],int nl)
  {
   int latest=LatestLTFIndexInHTF(ltf,nl,candidateBarTime);
   if(latest<0)
      return false;

   int htfSec=(int)PeriodSeconds(HTF());
   if(htfSec<=0)
      htfSec=3600;
   int quarterSec=htfSec/4;
   if(quarterSec<=0)
      quarterSec=900;

   int elapsed=(int)(ltf[latest].time-candidateBarTime);
   if(elapsed<0)
      return false;
   int quarter=elapsed/quarterSec;
   if(quarter<0)
      quarter=0;
   if(quarter>3)
      quarter=3;

   datetime quarterStart=candidateBarTime+(datetime)(quarter*quarterSec);
   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time<quarterStart || ltf[k].time>ltf[latest].time)
         continue;
      if(CandidateCloseBeyond(bull,ltf[k].close,level))
         return true;
     }

   return false;
  }

/*
Purpose: Clean internal enum names for user-facing chart tooltips.
Constitution: Visual-layer formatting only; state truth remains unchanged.
Inputs: state - sibling state enum.
Outputs: A compact readable state label.
*/
string CCTStateLabel(SIB_STATE state)
  {
   string out=EnumToString(state);
   StringReplace(out,"SS_","");
   StringReplace(out,"RESOLVED_","");
   StringReplace(out,"DEAD_","DEAD ");
   StringReplace(out,"_"," ");
   return out;
  }

/*
Purpose: Format price distance in user-auditable terms instead of raw asset-price decimals.
Constitution: Visual-layer tooltip formatting only; scanner and execution geometry stay unchanged.
Inputs: distancePx - absolute price distance, refPrice - entry/reference price for percentage context.
Outputs: Compact points plus percent label.
*/
string CCTDistanceUserLabel(double distancePx,double refPrice)
  {
   double dist=MathAbs(distancePx);
   if(dist<=0.0)
      return "-";

   double points=(_Point>0.0) ? dist/_Point : dist;
   string pointText=(points>=100.0) ? DoubleToString(points,0) : DoubleToString(points,1);
   double pct=(refPrice>0.0) ? (dist/refPrice)*100.0 : 0.0;
   return pointText + " pts | " + DoubleToString(pct,2) + "%";
  }

/*
Purpose: Add the displayed-timezone label once per tooltip instead of repeating it beside every timestamp.
Constitution: Latest user clarification requires compact tooltips with one explicit timezone declaration for all displayed times.
Inputs: tooltip - already formatted object-specific tooltip text.
Outputs: Tooltip text with one "TZ <label>" marker on the first line.
*/
string CCTTooltipWithTimezone(string tooltip)
  {
   string marker="TZ " + DisplayTZLabel();
   if(StringFind(tooltip,"TZ ")>=0)
      return tooltip;

   int nl=StringFind(tooltip,"\n");
   if(nl<0)
      return tooltip + " | " + marker;

   return StringSubstr(tooltip,0,nl) + " | " + marker + StringSubstr(tooltip,nl);
  }

/*
Purpose: Write both tooltip and object text so normal charts and visual tester mode have the same descriptive fallback.
Constitution: Visual-layer metadata only; chart geometry and scanner truth remain unchanged.
Inputs: n - object name, tooltip - compact horizontal tooltip text.
Outputs: Object string metadata updated.
*/
void SetCCTTooltip(string n,string tooltip)
  {
   if(ObjectFind(0,n)<0)
      return;

   string finalTip=CCTTooltipWithTimezone(tooltip);
   if(ObjectGetString(0,n,OBJPROP_TOOLTIP)!=finalTip)
      ObjectSetString(0,n,OBJPROP_TOOLTIP,finalTip);

   ObjectSetString(0,n,OBJPROP_TEXT,finalTip);
  }

bool CCTStringEndsWith(string text,string suffix)
  {
   int lt=StringLen(text);
   int ls=StringLen(suffix);
   if(ls<=0 || lt<ls)
      return false;
   return (StringSubstr(text,lt-ls,ls)==suffix);
  }

void PulseCandidateGlowObjects()
  {
   if(!Inp_ShowCandidates || IsNonVisualTesterRun())
      return;

   for(int i=ObjectsTotal(0)-1;i>=0;i--)
     {
      string name=ObjectName(0,i);
      if(StringFind(name,"CCT_")!=0)
         continue;

      bool glow=(StringFind(name,"_VW_GLOW")>=0);
      if(!glow)
         continue;

      bool bull=(StringFind(name,"CCT_BU_")==0);
      ObjectSetInteger(0,name,OBJPROP_COLOR,(long)CCTCandidatePulseColor(bull,glow));
     }
  }

/*
Purpose: Write-through double setter for scalar chart object properties.
Constitution: Ch. 26.3 non-destructive drawing and pass-1 write-through requirement.
Inputs: n - object name, p - double property, v - desired value.
Outputs: None.
*/
void _dsd(string n,ENUM_OBJECT_PROPERTY_DOUBLE p,double v)
  {
   if(ObjectFind(0,n)<0)
      return;
   double tol=MathMax(_Point,1e-8);
   if(MathAbs(ObjectGetDouble(0,n,p)-v)<=tol)
      return;
   ObjectSetDouble(0,n,p,v);
  }

/*
Purpose: Write-through double setter for point-indexed chart object properties.
Constitution: Ch. 26.3 non-destructive drawing and MT5 anchoring rules.
Inputs: n - object name, p - double property, modifier - point index, v - desired value.
Outputs: None.
*/
void _dsd(string n,ENUM_OBJECT_PROPERTY_DOUBLE p,int modifier,double v)
  {
   if(ObjectFind(0,n)<0)
      return;
   double tol=MathMax(_Point,1e-8);
   if(MathAbs(ObjectGetDouble(0,n,p,modifier)-v)<=tol)
      return;
   ObjectSetDouble(0,n,p,modifier,v);
  }

/*
Purpose: Track a currently valid CCT object name so stale objects can be pruned after draw.
Constitution: Ch. 26 object lifecycle ownership in the visual layer.
Inputs: name - object to keep, keep - keep-list array, count - keep count.
Outputs: Updated keep list.
*/
void KeepObj(string name,string &keep[],int &count)
  {
   if(name=="")
      return;

   for(int i=0;i<count;i++)
     {
      if(keep[i]==name)
         return;
     }

   int newSize=count+1;
   ArrayResize(keep,newSize);
   keep[count]=name;
   count=newSize;
  }

/*
Purpose: Check whether an object name belongs to the current keep list.
Constitution: Ch. 26 object lifecycle ownership in the visual layer.
Inputs: name - object to test, keep - keep-list array, count - keep count.
Outputs: True if the name should remain on chart.
*/
bool InKeepList(string name,string &keep[],int count)
  {
   for(int i=0;i<count;i++)
     {
      if(keep[i]==name)
         return true;
     }
   return false;
  }

/*
Purpose: Remove stale CCT-owned objects that were not redrawn this pass.
Constitution: Ch. 26.3 non-destructive drawing without bulk recreate loops.
Inputs: keep - keep-list array, count - keep count.
Outputs: None.
*/

/*
Purpose: Count chart objects by prefix for visual reconciliation diagnostics.
Constitution: Diagnostic only; does not change scanner, POI state, execution, or object lifecycle rules.
Inputs: prefix - object-name prefix.
Outputs: Matching chart object count.
*/
int CCTVisualCountObjectsByPrefix(const string prefix)
  {
   int count=0;

   for(int i=ObjectsTotal(0)-1;i>=0;i--)
     {
      string name=ObjectName(0,i);
      if(StringFind(name,prefix)==0)
         count++;
     }

   return count;
  }

/*
Purpose: Append a compact object-name sample for MT5 Expert-log diagnostics.
Constitution: Diagnostic only; no chart object is created, deleted, or modified.
Inputs: sample - current sample string; name - candidate object name; limit - maximum names.
Outputs: Updated sample and count.
*/
void CCTVisualAppendSample(string &sample,int &sampleCount,const string name,const int limit)
  {
   if(sampleCount>=limit)
      return;

   if(sample!="")
      sample+=" | ";

   sample+=name;
   sampleCount++;
  }

/*
Purpose: Throttle visual reconciliation logs so timeframe/reinit events are visible without timer spam.
Constitution: Diagnostic only; pruning decisions remain controlled by the existing keep list.
Inputs: beforeCount - CCT object count before prune; keepCount - keep-list count; deletedCount - deleted stale object count; afterCount - CCT object count after prune.
Outputs: True when a diagnostic log should be printed.
*/
bool CCTVisualReconcileShouldLog(const int beforeCount,const int keepCount,const int deletedCount,const int afterCount)
  {
   // CCT_VISUAL_RECONCILE_LOG_HELPERS_V1
   if(!Inp_DebugVisualReconcile)
      return false;

   if(deletedCount>0)
      return true;

   static bool s_first=true;
   static uint s_lastLogMs=0;
   static int s_lastBefore=-1;
   static int s_lastKeep=-1;
   static int s_lastAfter=-1;

   uint nowMs=GetTickCount();
   uint throttleMs=(uint)MathMax(1,Inp_VisualReconcileLogSeconds)*1000;

   if(s_first)
     {
      s_first=false;
      s_lastLogMs=nowMs;
      s_lastBefore=beforeCount;
      s_lastKeep=keepCount;
      s_lastAfter=afterCount;
      return true;
     }

   if(beforeCount!=s_lastBefore || keepCount!=s_lastKeep || afterCount!=s_lastAfter)
     {
      s_lastLogMs=nowMs;
      s_lastBefore=beforeCount;
      s_lastKeep=keepCount;
      s_lastAfter=afterCount;
      return true;
     }

   if((uint)(nowMs-s_lastLogMs)>=throttleMs)
     {
      s_lastLogMs=nowMs;
      s_lastBefore=beforeCount;
      s_lastKeep=keepCount;
      s_lastAfter=afterCount;
      return true;
     }

   return false;
  }
void PruneCCTObjects(string &keep[],int count)
  {
   // CCT_VISUAL_RECONCILE_PRUNE_LOG_V1
   int beforeCount=CCTVisualCountObjectsByPrefix("CCT_");
   int deletedCount=0;
   string deletedSample="";
   string keptSample="";
   int deletedSampleCount=0;
   int keptSampleCount=0;

   for(int k=0;k<count;k++)
      CCTVisualAppendSample(keptSample,keptSampleCount,keep[k],8);

   for(int i=ObjectsTotal(0)-1;i>=0;i--)
     {
      string name=ObjectName(0,i);
      if(StringFind(name,"CCT_")!=0)
         continue;
      if(InKeepList(name,keep,count))
         continue;

      CCTVisualAppendSample(deletedSample,deletedSampleCount,name,8);
      if(ObjectDelete(0,name))
         deletedCount++;
     }

   int afterCount=CCTVisualCountObjectsByPrefix("CCT_");

   if(CCTVisualReconcileShouldLog(beforeCount,count,deletedCount,afterCount))
     {
      PrintFormat("[CCT VISUAL RECONCILE] prune | symbol=%s | period=%s | before=%d | keep=%d | deleted=%d | after=%d | keptSample=%s | deletedSample=%s",
                  _Symbol,
                  EnumToString(_Period),
                  beforeCount,
                  count,
                  deletedCount,
                  afterCount,
                  keptSample,
                  deletedSample);
     }
  }

/*
Purpose: Create or update a non-ray horizontal trend line using stable anchors.
Constitution: Ch. 27, Ch. 28, and pass-1 write-through object update rules.
Inputs: name - object name, price - horizontal price, clr - line color, sty - line style, width - line width, tfMask - timeframe mask, leftAnchor - start time, rightAnchor - end time, tooltip - hover text.
Outputs: None.
*/
void CreateHLine(string name,double price,color clr,ENUM_LINE_STYLE sty,int width,long tfMask,datetime leftAnchor,datetime rightAnchor,string tooltip)
  {
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_TREND,0,leftAnchor,price,rightAnchor,price))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
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
   _dsi(name,OBJPROP_BACK,0);
   _dsi(name,OBJPROP_TIMEFRAMES,tfMask);
   SetCCTTooltip(name,tooltip);
  }

/*
Purpose: Delete both members of a dual line family that separates HTF and exact-LTF anchors.
Constitution: Backup-proven dual-object ownership pattern for cross-timeframe precision.
Inputs: baseName - shared object family base name.
Outputs: Both objects deleted if present.
*/
void DeleteDualHLine(string baseName)
  {
   DeleteObj(baseName);
   DeleteObj(baseName+"_LTF");
  }

/*
Purpose: Draw matching HTF and exact-LTF horizontal line objects from separate anchor times.
Constitution: Backup-proven dual-object anchoring pattern for clean higher-timeframe rendering and precise M1 rendering.
Inputs: baseName - shared family base name, price - horizontal price, clr - line color, sty - line style, width - line width, htfLeftAnchor - HTF-aligned start time, ltfLeftAnchor - exact LTF start time, rightAnchor - current or locked end time, tooltip - hover text.
Outputs: Dual line family created or updated.
*/
void CreateDualHLine(string baseName,double price,color clr,ENUM_LINE_STYLE sty,int width,datetime htfLeftAnchor,datetime ltfLeftAnchor,datetime rightAnchor,string tooltip)
  {
   datetime exactLtfLeft=(ltfLeftAnchor>0) ? ltfLeftAnchor : htfLeftAnchor;
   CreateHLine(baseName,price,clr,sty,width,TFMask_AboveLTF(),htfLeftAnchor,rightAnchor,tooltip);
   CreateHLine(baseName+"_LTF",price,clr,sty,width,TFMask_ExactLTF(),exactLtfLeft,rightAnchor,tooltip);
  }

/*
Purpose: Draw or remove a virgin/candidate wick line using constitution colors and anchors.
Constitution: Ch. 3.5, Ch. 27, Ch. 28, and pass-1 visual requirements.
Inputs: bull - direction, barTime - source HTF bar time, ltfAnchor - exact LTF extreme time inside the HTF source bar, level - wick price, state - virgin/candidate/stripped state.
Outputs: None.
*/
void DrawVirginWick(bool bull,datetime barTime,datetime ltfAnchor,double level,WICK_STATE state,datetime candidateBarTime)
  {
   string name=ObjN(GenKey(bull,barTime),"VW");
   string glowName=name+"_GLOW";

   if(state==WS_STRIPPED)
     {
      DeleteDualHLine(name);
      DeleteDualHLine(glowName);
      return;
     }

   if(!Inp_ShowVirgins && state!=WS_CANDIDATE)
     {
      DeleteDualHLine(name);
      DeleteDualHLine(glowName);
      return;
     }
   if(!Inp_ShowCandidates && state==WS_CANDIDATE)
     {
      DeleteDualHLine(name);
      DeleteDualHLine(glowName);
      return;
     }

   color clr=(state==WS_CANDIDATE)
             ? CCTCandidateColor(bull)
             :(bull ? (color)C'74,92,118' : (color)C'118,92,74');
   ENUM_LINE_STYLE sty=(state==WS_CANDIDATE)?STYLE_DOT:STYLE_DOT;
   datetime rightAnchor=(datetime)(SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE)+PeriodSeconds(LTF()));
   if(state==WS_CANDIDATE && candidateBarTime>0)
      rightAnchor=(datetime)(candidateBarTime+PeriodSeconds(HTF())-1);

   string wickKind=(state==WS_CANDIDATE) ? "CANDIDATE POI" : "VIRGIN WICK";
   string dir=bull ? "BULL" : "BEAR";
   string wickTime=(ltfAnchor>0) ? CCTNYTimeLabel(ltfAnchor,true) : CCTNYTimeLabel(barTime,false);
   string tooltip=dir + " " + wickKind + " | " + GenKey(bull,barTime) + "\n" +
                  "Px " + DoubleToString(level,_Digits) +
                  " | Src " + wickTime + "\n" +
                  "Use " + ((state==WS_CANDIDATE) ? "candidate birth" : "liquidity") +
                  " | Anchor " + ((ltfAnchor>0) ? "LTF" : "HTF");
   if(state==WS_CANDIDATE && candidateBarTime>0)
     {
      datetime birthClose=(datetime)(candidateBarTime+PeriodSeconds(HTF())-1);
      datetime pillarTime=ActionPillarTime(candidateBarTime);
      tooltip+="\nBirth " + CCTNYTimeLabel(birthClose,false) +
               " | AP " + CCTNYTimeLabel(pillarTime,false) + "\n" +
               CCTCandidateExecLabel(candidateBarTime);
     }

   if(state==WS_CANDIDATE)
      DeleteDualHLine(glowName);
   else
      DeleteDualHLine(glowName);

   CreateDualHLine(name,level,clr,sty,1,barTime,ltfAnchor,rightAnchor,tooltip);
  }

/*
Purpose: Draw or remove a candidate action pillar that belongs to a live candidate POI.
Constitution: Latest user clarification that candidate POI APs show by default, plus Ch. 4.5/Ch. 29 action-pillar timing.
Inputs: bull - direction, wickTime - originating wick time for stable naming, candidateBarTime - current HTF candidate bar open time, relevant - whether the candidate still exists and should render.
Outputs: None.
*/
void DrawCandidateActionPillar(bool bull,datetime wickTime,datetime candidateBarTime,double level,bool relevant,int candidateOrdinal,int candidateCount)
  {
   string name=ObjN(GenKey(bull,candidateBarTime),"CAP");
   if(!relevant)
     {
      DeleteObj(name);
      return;
     }

   datetime pillarTime=ActionPillarTime(candidateBarTime);
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_VLINE,0,pillarTime,0.0))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

   datetime birthClose=(datetime)(candidateBarTime + PeriodSeconds(HTF()) - 1);
   _dsi(name,OBJPROP_TIME,0,(long)pillarTime);
   _dsi(name,OBJPROP_COLOR,(long)CCTCandidateAPColor(bull));
   _dsi(name,OBJPROP_STYLE,(long)STYLE_DOT);
   _dsi(name,OBJPROP_WIDTH,1);
   _dsi(name,OBJPROP_TIMEFRAMES,TFMask_Full());
   string dir=bull ? "BULL" : "BEAR";
   string tooltip=dir + " Candidate AP | " + GenKey(bull,candidateBarTime) + "\n" +
                  "Cand " + IntegerToString(candidateCount) +
                  " | Px " + DoubleToString(level,_Digits) + "\n" +
                  "Birth " + CCTNYTimeLabel(birthClose,false) + "\n" +
                  "AP " + CCTNYTimeLabel(pillarTime,false) + " | Pending\n" +
                  CCTCandidateExecLabel(candidateBarTime);
   SetCCTTooltip(name,tooltip);
  }

/*
Purpose: Draw or remove an action pillar for a generation.
Constitution: Ch. 4.5, Ch. 29, and Ch. 27 timeframe visibility rules.
Inputs: genKey - generation key, birthTime - generation birth bar open time, pillarTime - next HTF bar open time, relevant - whether the generation is draw-authorized, stateLabel - short visibility/status note for tooltip.
Outputs: None.
*/
void DrawActionPillar(string genKey,datetime birthTime,datetime pillarTime,bool relevant,string stateLabel,bool bull,int siblingCount,int validCount,int activeCount,int inactiveCount,int triggeredCount,int resolvedCount,int deadCount,int activeSibIdx,datetime c1Time,datetime triggerTime,string modelLabel)
  {
   string name=ObjN(genKey,"AP");
   if(!relevant)
      {
      DeleteObj(name);
      return;
     }

   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_VLINE,0,pillarTime,0.0))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

   _dsi(name,OBJPROP_TIME,0,(long)pillarTime);
   _dsi(name,OBJPROP_COLOR,(long)C'88,88,88');
   _dsi(name,OBJPROP_STYLE,(long)STYLE_DOT);
   _dsi(name,OBJPROP_WIDTH,1);
   _dsi(name,OBJPROP_TIMEFRAMES,TFMask_Full());
   string dir=bull ? "BULL" : "BEAR";
   string tooltip=dir + " AP | " + genKey + "\n" +
                  "Birth " + CCTNYTimeLabel(birthTime,false) +
                  " | Exec " + CCTNYTimeLabel(pillarTime,false) + "\n" +
                  "Siblings " + IntegerToString(siblingCount) +
                  " | " + modelLabel;
   if(triggerTime>0)
     {
      datetime entryTime=triggerTime+(datetime)PeriodSeconds(LTF());
      tooltip+="\nC1 " + CCTNYTimeLabel(c1Time,true) +
               " | Entry " + CCTNYTimeLabel(entryTime,true);
     }
   SetCCTTooltip(name,tooltip);
  }

/*
Purpose: Draw or remove the currently displayed TS level for one generation.
Constitution: Latest user clarification that TS counts all swept opposing virgin wicks but only the most recently swept level is shown, locked forever at its first-touch time.
Inputs: genKey - generation key, bull - generation direction, level - TS level price, htfLeftAnchor - source HTF wick time, ltfLeftAnchor - exact source LTF anchor, firstTouchTime - locked right edge, confirmed - whether the level survived into a triggered TS family, relevant - whether the TS line should be visible.
Outputs: None.
*/
void DrawTSLevel(string genKey,bool bull,double level,datetime htfLeftAnchor,datetime ltfLeftAnchor,datetime firstTouchTime,bool confirmed,bool relevant)
  {
   string name=ObjN(genKey,"TS");
   if(!relevant || level<=0.0 || firstTouchTime<=0)
     {
      DeleteObj(name);
      return;
     }

   datetime leftAnchor=(ltfLeftAnchor>0) ? ltfLeftAnchor : htfLeftAnchor;
   datetime rightAnchor=firstTouchTime;
   if(rightAnchor<=leftAnchor)
      rightAnchor=leftAnchor+PeriodSeconds(LTF());

   color clr=confirmed ? (bull ? (color)C'132,118,92' : (color)C'106,134,104')
                       : (bull ? (color)C'82,74,58' : (color)C'62,82,62');
   ENUM_LINE_STYLE sty=confirmed ? STYLE_DASH : STYLE_DOT;
   string dir=bull ? "BULL" : "BEAR";
   string sourceTime=(ltfLeftAnchor>0) ? CCTNYTimeLabel(ltfLeftAnchor,true) : CCTNYTimeLabel(htfLeftAnchor,false);
   string tooltip=dir + " TS | " + (confirmed ? "Confirmed" : "Hint") + " | " + genKey + "\n" +
                  "Px " + DoubleToString(level,_Digits) +
                  " | Src " + sourceTime + "\n" +
                  "Sweep time " + CCTNYTimeLabel(firstTouchTime,true) +
                  " | Liquidity sweep";

   CreateHLine(name,level,clr,sty,1,TFMask_BelowHTF(),leftAnchor,rightAnchor,tooltip);
  }

/*
Purpose: Draw or remove a CO line for one triggered generation.
Constitution: Latest user clarification that CO appears only below H1 after trigger, extends live until first touch or disappearance, and locks forever at first touch.
Inputs: genKey - generation key, bull - direction, price - CO price, htfLeftAnchor - source HTF wick time, ltfLeftAnchor - exact source LTF anchor, triggerTime - trigger open/close anchor, touchTime - post-trigger first CO touch when known, relevant - whether the CO line should be visible.
Outputs: None.
*/
void DrawCOLine(string genKey,bool bull,double price,datetime htfLeftAnchor,datetime ltfLeftAnchor,datetime triggerTime,datetime touchTime,bool relevant)
  {
   string name=ObjN(genKey,"CO");
   if(!relevant || price<=0.0 || triggerTime<=0)
     {
      DeleteObj(name);
      return;
     }

   datetime leftAnchor=(ltfLeftAnchor>0) ? ltfLeftAnchor : htfLeftAnchor;
   datetime rightAnchor=(touchTime>0) ? ClosedLTFEventEdge(touchTime) : LTFLiveRightEdge();
   if(rightAnchor<triggerTime)
      rightAnchor=triggerTime;
   if(rightAnchor<=leftAnchor)
      rightAnchor=leftAnchor+PeriodSeconds(LTF());

   string touchLabel=(touchTime>0) ? CCTNYTimeLabel(touchTime,true) : "live";
   string sourceTime=(ltfLeftAnchor>0) ? CCTNYTimeLabel(ltfLeftAnchor,true) : CCTNYTimeLabel(htfLeftAnchor,true);
   string dir=bull ? "BULL" : "BEAR";
   string tooltip=dir + " CO | " + genKey + "\n" +
                  "Px " + DoubleToString(price,_Digits) +
                  " | Src " + sourceTime + "\n" +
                  "Touch " + touchLabel;

   CreateHLine(name,price,Inp_ClrExecCO,STYLE_DASHDOT,1,TFMask_BelowHTF(),leftAnchor,rightAnchor,tooltip);
  }

/*
Purpose: Create or update a bordered rectangle without fill.
Constitution: MT5 execution and FVG zones should remain inspectable without opaque filled boxes.
Inputs: name - object name, left/right - time anchors, priceA/priceB - zone prices, clr - border color, width - border width, tfMask - visibility mask, tooltip - hover text.
Outputs: Rectangle object created or updated.
*/
void CreateBorderBox(string name,datetime leftAnchor,datetime rightAnchor,double priceA,double priceB,color clr,int width,long tfMask,string tooltip)
  {
   if(leftAnchor<=0 || rightAnchor<=leftAnchor || priceA<=0.0 || priceB<=0.0 || MathAbs(priceA-priceB)<=_Point*0.1)
     {
      DeleteObj(name);
      return;
     }

   double top=MathMax(priceA,priceB);
   double bottom=MathMin(priceA,priceB);
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,leftAnchor,top,rightAnchor,bottom))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

   _dsi(name,OBJPROP_TIME,0,(long)leftAnchor);
   _dsd(name,OBJPROP_PRICE,0,top);
   _dsi(name,OBJPROP_TIME,1,(long)rightAnchor);
   _dsd(name,OBJPROP_PRICE,1,bottom);
   _dsi(name,OBJPROP_COLOR,(long)clr);
   _dsi(name,OBJPROP_STYLE,(long)STYLE_SOLID);
   _dsi(name,OBJPROP_WIDTH,width);
   _dsi(name,OBJPROP_BACK,1);
   _dsi(name,OBJPROP_FILL,0);
   _dsi(name,OBJPROP_TIMEFRAMES,tfMask);
   SetCCTTooltip(name,tooltip);
  }

/*
Purpose: Create or update a filled background rectangle for the winning IFVG only.
Constitution: IFVG boxes are LTF execution evidence and should sit behind candles without thick front-border clutter.
Inputs: name - object name, left/right - time anchors, priceA/priceB - zone prices, clr - fill/border color, tfMask - visibility mask, tooltip - hover text.
Outputs: Rectangle object created or updated.
*/
void CreateFVGFillBox(string name,datetime leftAnchor,datetime rightAnchor,double priceA,double priceB,color clr,long tfMask,string tooltip)
  {
   if(leftAnchor<=0 || rightAnchor<=leftAnchor || priceA<=0.0 || priceB<=0.0 || MathAbs(priceA-priceB)<=_Point*0.1)
     {
      DeleteObj(name);
      return;
     }

   double top=MathMax(priceA,priceB);
   double bottom=MathMin(priceA,priceB);
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,leftAnchor,top,rightAnchor,bottom))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

   _dsi(name,OBJPROP_TIME,0,(long)leftAnchor);
   _dsd(name,OBJPROP_PRICE,0,top);
   _dsi(name,OBJPROP_TIME,1,(long)rightAnchor);
   _dsd(name,OBJPROP_PRICE,1,bottom);
   _dsi(name,OBJPROP_COLOR,(long)clr);
   _dsi(name,OBJPROP_STYLE,(long)STYLE_SOLID);
   _dsi(name,OBJPROP_WIDTH,1);
   _dsi(name,OBJPROP_BACK,1);
   _dsi(name,OBJPROP_FILL,1);
   _dsi(name,OBJPROP_TIMEFRAMES,tfMask);
   SetCCTTooltip(name,tooltip);
  }

/*
Purpose: Draw or remove one scanner-owned FVG box.
Constitution: FVG boxes are scanner evidence; the active winning IFVG highlights while stale/superseded boxes disappear.
Inputs: genKey - generation key, fvgIdx - FVG index, fi - FVG record, bull - generation direction, isActiveTrigger - whether this FVG is the current IFVG winner, relevant - whether the FVG is inside the CO eligibility window.
Outputs: FVG rectangle drawn or deleted.
*/
void DrawFVGBox(string genKey,int fvgIdx,FVGInfo &fi,bool bull,bool isActiveTrigger,bool relevant,bool confirmedTrigger)
  {
   string name=ObjN(genKey,"FVG_"+IntegerToString(fvgIdx));
   if(!relevant || !isActiveTrigger || !fi.inverted || fi.stale || fi.superseded || fi.invalidInv)
     {
      DeleteObj(name);
      return;
     }

   // CCT_IFVG_RIGHT_ANCHOR_CLOSE_SECOND_V1
   // IFVG inversion is stored as the opening time of the inversion candle.
   // The visual box should end at that candle's actual close second (xx:xx:59 on M1),
   // not one second before the candle begins.
   datetime rightAnchor=fi.invTime+(datetime)PeriodSeconds(LTF())-1;
   if(rightAnchor<=fi.t1)
      rightAnchor=fi.t3+(datetime)PeriodSeconds(LTF())-1;

   color clr=bull ? Inp_ClrIFVGBull : Inp_ClrIFVGBear;
   string status=confirmedTrigger ? "confirmed C3" : "candidate C3";
   string tooltip="IFVG | " + genKey + " | " + status + "\n" +
                  "Gap " + CCTNYClockLabel(fi.t2,false) +
                  " | Inv " + CCTNYTimeLabel(fi.invTime,true);

   CreateFVGFillBox(name,fi.t1,rightAnchor,fi.c1Ext,fi.c3Ext,clr,TFMask_BelowHTF(),tooltip);

   // CCT_PRETRIGGER_C3_IFVG_TOGGLE_V2
   // Candidate C3 IFVGs are mild hints; confirmed trigger IFVGs are solid.
   ObjectSetInteger(0,name,OBJPROP_STYLE,confirmedTrigger ? STYLE_SOLID : STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,confirmedTrigger ? 2 : 1);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
  }

/*
Purpose: Delete the clean fib-debug object family and the retired MT5 OBJ_FIBO object.
Constitution: Fib debug visuals are temporary, generation-owned execution details.
Inputs: genKey - generation key.
Outputs: Stale fib debug objects removed.
*/
void DeleteTriggerFibObjects(string genKey)
  {
   DeleteObj(ObjN(genKey,"EXEC_FIB"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_ANCHOR"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_A"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_B"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_SHALLOW"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_DEEP"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_RAW"));
  }

/*
Purpose: Create or update a non-ray trend segment for fib-debug anchoring.
Constitution: Debug anchors must sit on exact FVG anchor candles/prices rather than on arbitrary execution times.
Inputs: name - object name, left/right - time anchors, priceA/priceB - prices, clr/style/width - visual styling, tooltip - hover text.
Outputs: Trend segment drawn.
*/
void CreateTrendSegment(string name,datetime leftAnchor,double priceA,datetime rightAnchor,double priceB,color clr,ENUM_LINE_STYLE sty,int width,string tooltip)
  {
   if(leftAnchor<=0 || rightAnchor<=leftAnchor || priceA<=0.0 || priceB<=0.0)
     {
      DeleteObj(name);
      return;
     }

   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_TREND,0,leftAnchor,priceA,rightAnchor,priceB))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

   _dsi(name,OBJPROP_TIME,0,(long)leftAnchor);
   _dsd(name,OBJPROP_PRICE,0,priceA);
   _dsi(name,OBJPROP_TIME,1,(long)rightAnchor);
   _dsd(name,OBJPROP_PRICE,1,priceB);
   _dsi(name,OBJPROP_COLOR,(long)clr);
   _dsi(name,OBJPROP_STYLE,(long)sty);
   _dsi(name,OBJPROP_WIDTH,width);
   _dsi(name,OBJPROP_RAY_RIGHT,0);
   _dsi(name,OBJPROP_RAY_LEFT,0);
   _dsi(name,OBJPROP_BACK,0);
   _dsi(name,OBJPROP_TIMEFRAMES,TFMask_BelowHTF());
   SetCCTTooltip(name,tooltip);
  }

/*
Purpose: Draw clean fib-debug anchors and extension segments at trigger.
Constitution: Fib geometry must show the same anchors and raw SL candidates used by the trigger, without MT5 fib-object inversion.
Inputs: genKey - generation key, bull - direction, anchorA/B time and price, rawSL - selected stop, branch/cfg - SL branch and preset.
Outputs: Anchor markers and white dotted extension segments drawn or removed.
*/
void DrawTriggerFibObject(string genKey,bool bull,datetime anchorATime,datetime anchorBTime,double anchorA,double anchorB,double rawSL,ENUM_SL_BRANCH branch,ENUM_FIB_CFG cfg)
  {
   if(anchorATime<=0 || anchorBTime<=0 || anchorA<=0.0 || anchorB<=0.0 || rawSL<=0.0 || MathAbs(anchorA-anchorB)<=_Point*0.1)
     {
      DeleteTriggerFibObjects(genKey);
      return;
     }

   DeleteObj(ObjN(genKey,"EXEC_FIB"));

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;
   datetime segLeft=anchorBTime;
   datetime segRight=anchorBTime+(datetime)(ltfSec*3)-1;
   if(segRight<=segLeft)
      segRight=segLeft+(datetime)ltfSec;

   double gap=MathAbs(anchorA-anchorB);
   double shallowExt=(cfg==FIB_CFG_1)?0.50:0.75;
   double deepExt=(cfg==FIB_CFG_1)?0.75:1.00;
   double shallowPx=NormalizeDouble(bull ? (anchorB-shallowExt*gap) : (anchorB+shallowExt*gap),_Digits);
   double deepPx=NormalizeDouble(bull ? (anchorB-deepExt*gap) : (anchorB+deepExt*gap),_Digits);
   double rawPx=NormalizeDouble(rawSL,_Digits);

   color extClr=(color)C'168,168,168';
   string tooltip="FIB | " + genKey + " | " + EnumToString(branch) + "\n" +
                  "A=" + DoubleToString(anchorA,_Digits) + " @ " + CCTNYClockLabel(anchorATime,true) + "\n" +
                  "B=" + DoubleToString(anchorB,_Digits) + " @ " + CCTNYClockLabel(anchorBTime,true) + "\n" +
                  "Ext: shallow " + DoubleToString(shallowPx,_Digits) +
                  " | deep " + DoubleToString(deepPx,_Digits) +
                  " | raw " + DoubleToString(rawPx,_Digits);

   DeleteObj(ObjN(genKey,"EXEC_FIB_ANCHOR"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_A"));
   DeleteObj(ObjN(genKey,"EXEC_FIB_B"));

   if(!Inp_ShowFibExtensions)
     {
      DeleteObj(ObjN(genKey,"EXEC_FIB_SHALLOW"));
      DeleteObj(ObjN(genKey,"EXEC_FIB_DEEP"));
      DeleteObj(ObjN(genKey,"EXEC_FIB_RAW"));
      return;
     }

   CreateHLine(ObjN(genKey,"EXEC_FIB_SHALLOW"),shallowPx,extClr,STYLE_DOT,1,TFMask_BelowHTF(),segLeft,segRight,tooltip);
   CreateHLine(ObjN(genKey,"EXEC_FIB_DEEP"),deepPx,extClr,STYLE_DOT,1,TFMask_BelowHTF(),segLeft,segRight,tooltip);
   CreateHLine(ObjN(genKey,"EXEC_FIB_RAW"),rawPx,extClr,STYLE_DOT,2,TFMask_BelowHTF(),segLeft,segRight,tooltip);
  }

/*
Purpose: Draw or remove the synthetic execution long/short tool using bordered SL/TP boxes and an entry line.
Constitution: Synthetic entry is the trigger bar close; SL/TP visualization uses raw geometry only and deliberately excludes spread for now.
Inputs: genKey - generation key, bull - direction, triggerTime - trigger LTF bar time, entry - synthetic entry, rawSL - raw stop, rawTP - raw target, anchorA/B - fib anchors, branch - SL branch, modelType/sweepCount - classification detail.
Outputs: Execution objects drawn or removed.
*/
bool CCTExecutionOutcomeIsResolved(SIB_STATE outcome)
  {
   return (outcome==SS_RESOLVED_TP ||
           outcome==SS_RESOLVED_SL ||
           outcome==SS_RESOLVED_BE ||
           outcome==SS_RESOLVED_BE_CO);
  }

datetime CCTExecutionLiveRightEdge(datetime entryTime)
  {
   // CCT_EXEC_OBJECT_INITIAL_WIDTH_5_LTF_V1
   // Live execution overlays need enough width at entry to show entry, BE thresholds, and exit geometry.
   // After live time catches up, track one full LTF candle ahead of the current forming candle.
   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;

   datetime currentOpen=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   datetime liveEdge=(currentOpen>0) ? currentOpen+(datetime)(2*ltfSec)-1 : LTFLiveRightEdge();

   if(entryTime<=0)
      return liveEdge;

   datetime initialEdge=entryTime+(datetime)(ltfSec*5)-1;
   return (initialEdge>liveEdge) ? initialEdge : liveEdge;
  }

datetime CCTExecutionResolvedRightEdge(datetime triggerTime,datetime entryTime,datetime exitTime)
  {
   if(exitTime>0)
      return exitTime;

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;

   datetime fallback=(triggerTime>0) ? triggerTime+(datetime)ltfSec-1 : 0;
   if(fallback<=0)
      fallback=entryTime;
   if(fallback<=entryTime)
      fallback=entryTime+1;
   return fallback;
  }

void DrawSyntheticExecutionObjects(string genKey,bool bull,datetime triggerTime,datetime entryTime,double entry,double rawSL,double rawTP,
                                   datetime anchorATime,datetime anchorBTime,double anchorA,double anchorB,ENUM_SL_BRANCH branch,ENUM_MODEL_TYPE modelType,int sweepCount,
                                   SIB_STATE outcome,datetime exitTime,double coPrice,datetime coTouchTime,
                                   bool beGeneralApplied,bool beCoApplied,double bePrice,datetime beLeftAnchorTime,datetime beTriggerTime,
                                   double beGeneralPrice,datetime beGeneralLeftAnchorTime,datetime beGeneralTime,
                                   double beCoPrice,datetime beCoLeftAnchorTime,datetime beCoTime,double fibRawSL)
  {
   string entryName=ObjN(genKey,"EXEC_ENTRY");
   string slName=ObjN(genKey,"EXEC_SL_BOX");
   string tpName=ObjN(genKey,"EXEC_TP_BOX");
   string beName=ObjN(genKey,"EXEC_BE");
   string beCoName=ObjN(genKey,"EXEC_BE_CO");
   string beGlobalThrName=ObjN(genKey,"EXEC_BE_GLOBAL_THR");
   string beCoThrName=ObjN(genKey,"EXEC_BE_CO_THR");

   if(triggerTime<=0 || entryTime<=0 || entry<=0.0 || rawSL<=0.0 || rawTP<=0.0)
     {
      DeleteObj(entryName);
      DeleteObj(slName);
      DeleteObj(tpName);
      DeleteObj(beName);
      DeleteObj(beCoName);
      DeleteObj(beGlobalThrName);
      DeleteObj(beCoThrName);
      DrawTriggerFibObject(genKey,bull,0,0,0.0,0.0,0.0,branch,Inp_FibCfg);
      return;
     }

   bool resolvedOutcome=CCTExecutionOutcomeIsResolved(outcome);
   datetime rightAnchor=resolvedOutcome ? CCTExecutionResolvedRightEdge(triggerTime,entryTime,exitTime)
                                        : CCTExecutionLiveRightEdge(entryTime);
   if(rightAnchor<=entryTime)
      rightAnchor=entryTime+1;

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;

   datetime thresholdRight=rightAnchor;
   datetime thresholdLeft=thresholdRight-(datetime)ltfSec;
   if(thresholdLeft<entryTime)
      thresholdLeft=entryTime;
   if(thresholdRight<=thresholdLeft)
      thresholdRight=thresholdLeft+1;

   string modelLabel=ModelTypeLabel(modelType);
   string outcomeLabel=(outcome==SS_RESOLVED_TP) ? "TP" :
                       (outcome==SS_RESOLVED_SL) ? "SL" :
                       (outcome==SS_RESOLVED_BE) ? "BE" :
                       (outcome==SS_RESOLVED_BE_CO) ? "BE/CO" : "Live";
   double riskPts=MathAbs(entry-rawSL);
   double rewardPts=MathAbs(rawTP-entry);
   double rr=(riskPts>0.0) ? rewardPts/riskPts : 0.0;
   string side=bull ? "LONG" : "SHORT";
   MqlDateTime trigNY={};
   TimeToStruct(ToNY(triggerTime),trigNY);
   bool nyBECOVisible=(CCTCOBEApplies(CurrentServerTime()) && coPrice>0.0);
   string coBELabel=CCTCOBELabel();

   double globalThreshold=0.0;
   if(CCTRuntimeBEGlobalEnabled() && rewardPts>_Point)
      globalThreshold=NormalizeDouble(entry+(bull ? 1.0 : -1.0)*(g_beTriggerPct/100.0)*rewardPts,_Digits);

   double coThreshold=0.0;
   if(nyBECOVisible && rewardPts>_Point)
      coThreshold=NormalizeDouble(entry+(bull ? 1.0 : -1.0)*(g_beCoMinProgPct/100.0)*rewardPts,_Digits);

   double effectiveGlobalBE=(beGeneralPrice>0.0) ? beGeneralPrice : ((beGeneralApplied && bePrice>0.0) ? bePrice : 0.0);
   datetime effectiveGlobalTime=(beGeneralTime>0) ? beGeneralTime : ((beGeneralApplied && beTriggerTime>0) ? beTriggerTime : 0);
   datetime effectiveGlobalLeft=(beGeneralLeftAnchorTime>0) ? beGeneralLeftAnchorTime : ((beGeneralApplied && beLeftAnchorTime>0) ? beLeftAnchorTime : 0);

   double effectiveCOBE=(beCoPrice>0.0) ? beCoPrice : ((beCoApplied && bePrice>0.0) ? bePrice : 0.0);
   datetime effectiveCOTime=(beCoTime>0) ? beCoTime : ((beCoApplied && beTriggerTime>0) ? beTriggerTime : 0);
   datetime effectiveCOLeft=(beCoLeftAnchorTime>0) ? beCoLeftAnchorTime : ((beCoApplied && beLeftAnchorTime>0) ? beLeftAnchorTime : 0);

   string baseTip=side + " EXEC | " + modelLabel + " | " + outcomeLabel + "\n" +
                  genKey + " | Hour " + IntegerToString(trigNY.hour) + ":00" +
                  " | Sweeps " + IntegerToString(sweepCount);

   string entryTip=baseTip + "\nEntry " + DoubleToString(entry,_Digits) +
                   " @ " + CCTNYTimeLabel(entryTime,true);
   if(exitTime>0)
      entryTip+=" | Exit " + CCTNYTimeLabel(exitTime,true);
   if(effectiveGlobalBE>0.0 && beGeneralApplied)
      entryTip+=" | G-BE " + DoubleToString(effectiveGlobalBE,_Digits);
   if(effectiveCOBE>0.0 && beCoApplied)
      entryTip+=" | " + coBELabel + " " + DoubleToString(effectiveCOBE,_Digits);
   if(!(beGeneralApplied || beCoApplied) && globalThreshold>0.0)
      entryTip+=" | G-BE thr " + DoubleToString(globalThreshold,_Digits);

   string slTip=side + " SL | " + modelLabel + " | " + outcomeLabel + "\n" +
                genKey + " | SL " + DoubleToString(rawSL,_Digits) +
                " | Risk " + CCTDistanceUserLabel(riskPts,entry) +
                "\nRiskCfg " + DoubleToString(g_riskPct,2) + "%";
   if(outcome==SS_RESOLVED_SL && exitTime>0)
      slTip+=" | Hit " + CCTNYTimeLabel(exitTime,true);

   string tpTip=side + " TP | " + modelLabel + " | " + outcomeLabel + "\n" +
                genKey + " | TP " + DoubleToString(rawTP,_Digits) +
                " | Reward " + CCTDistanceUserLabel(rewardPts,entry) +
                "\nRR " + DoubleToString(rr,2);
   if(globalThreshold>0.0)
      tpTip+=" | G-BE Thr " + DoubleToString(globalThreshold,_Digits);
   if(coThreshold>0.0)
      tpTip+=" | " + coBELabel + " Thr " + DoubleToString(coThreshold,_Digits);
   if(effectiveGlobalBE>0.0 && beGeneralApplied)
      tpTip+=" | G-BE " + DoubleToString(effectiveGlobalBE,_Digits);
   if(effectiveCOBE>0.0 && beCoApplied)
      tpTip+=" | " + coBELabel + " " + DoubleToString(effectiveCOBE,_Digits);
   if(outcome==SS_RESOLVED_TP && exitTime>0)
      tpTip+=" | Hit " + CCTNYTimeLabel(exitTime,true);

   CreateHLine(entryName,entry,Inp_ClrExecTrigger,STYLE_SOLID,2,TFMask_BelowHTF(),entryTime,rightAnchor,entryTip);
   CreateBorderBox(slName,entryTime,rightAnchor,entry,rawSL,Inp_ClrExecSLBox,2,TFMask_BelowHTF(),slTip);
   CreateBorderBox(tpName,entryTime,rightAnchor,entry,rawTP,Inp_ClrExecTPBox,2,TFMask_BelowHTF(),tpTip);

   bool showGlobalThreshold=(!resolvedOutcome && exitTime<=0 && CCTRuntimeBEGlobalEnabled() && globalThreshold>0.0 && !beGeneralApplied);
   if(showGlobalThreshold)
     {
      string gThrTip=side + " GLOBAL BE THRESHOLD | " + modelLabel + "\n" +
                     genKey + " | Threshold " + DoubleToString(globalThreshold,_Digits) +
                     " | Trigger " + DoubleToString(g_beTriggerPct,2) + "%\n" +
                     "Right-anchored at execution box edge; extends one live LTF candle left.";
      CreateHLine(beGlobalThrName,globalThreshold,Inp_ClrExecBE,STYLE_DASHDOTDOT,1,TFMask_BelowHTF(),thresholdLeft,thresholdRight,gThrTip);
     }
   else
      DeleteObj(beGlobalThrName);

   bool showCOThreshold=(!resolvedOutcome && exitTime<=0 && nyBECOVisible && coThreshold>0.0 && !beCoApplied);
   if(showCOThreshold)
     {
      string coThrTip=side + " " + coBELabel + " THRESHOLD | " + modelLabel + "\n" +
                      genKey + " | Threshold " + DoubleToString(coThreshold,_Digits) +
                      " | Min progress " + DoubleToString(g_beCoMinProgPct,2) + "%\n" +
                      "CO " + DoubleToString(coPrice,_Digits) +
                      " | Right edge uses live execution box | Min age " + IntegerToString(g_beCoMinSec) + " sec";
      CreateHLine(beCoThrName,coThreshold,Inp_ClrExecCO,STYLE_DASHDOTDOT,1,TFMask_BelowHTF(),thresholdLeft,thresholdRight,coThrTip);
     }
   else
      DeleteObj(beCoThrName);

   bool showGlobalBELine=(beGeneralApplied && effectiveGlobalBE>0.0 && effectiveGlobalLeft>0 && outcome!=SS_RESOLVED_TP);
   if(showGlobalBELine)
     {
      datetime beLeft=(effectiveGlobalLeft<entryTime) ? entryTime : effectiveGlobalLeft;
      datetime beRight=rightAnchor;
      if(beRight<=beLeft)
         beRight=beLeft+1;
      string beTip=side + " GLOBAL BE | " + modelLabel + " | " + outcomeLabel + "\n" +
                   genKey + " | BE " + DoubleToString(effectiveGlobalBE,_Digits) +
                   " | Lock " + DoubleToString(g_beMovePct,2) + "%\n" +
                   "Threshold " + DoubleToString(g_beTriggerPct,2) + "% | From " + CCTNYTimeLabel(beLeft,true) +
                   " | Hit " + CCTNYTimeLabel(effectiveGlobalTime,true);
      CreateHLine(beName,effectiveGlobalBE,Inp_ClrExecBE,STYLE_DOT,1,TFMask_BelowHTF(),beLeft,beRight,beTip);
     }
   else
      DeleteObj(beName);

   bool showCOBELine=(beCoApplied && effectiveCOBE>0.0 && effectiveCOLeft>0 && outcome!=SS_RESOLVED_TP);
   if(showCOBELine)
     {
      datetime coLeft=(effectiveCOLeft<entryTime) ? entryTime : effectiveCOLeft;
      datetime coRight=rightAnchor;
      if(coRight<=coLeft)
         coRight=coLeft+1;
      string coBETip=side + " " + coBELabel + " | " + modelLabel + " | " + outcomeLabel + "\n" +
                     genKey + " | BE-CO " + DoubleToString(effectiveCOBE,_Digits) +
                     " | Lock " + DoubleToString(g_beCoLockPct,2) + "% TP progress\n" +
                     "CO " + DoubleToString(coPrice,_Digits) + " | From " + CCTNYTimeLabel(coLeft,true) + " | Touch " + CCTNYTimeLabel(coTouchTime,true) +
                     " | Hit " + CCTNYTimeLabel(effectiveCOTime,true);
      CreateHLine(beCoName,effectiveCOBE,Inp_ClrExecCO,STYLE_DOT,1,TFMask_BelowHTF(),coLeft,coRight,coBETip);
     }
   else
      DeleteObj(beCoName);

   double fibSL=(fibRawSL>0.0) ? fibRawSL : rawSL;
   DrawTriggerFibObject(genKey,bull,anchorATime,anchorBTime,anchorA,anchorB,fibSL,branch,Inp_FibCfg);
  }


/*
Purpose: Draw or remove a New York daily separator line.
Constitution: Ch. 26 visual ownership and NY daily reset visibility.
Inputs: dayOpen - server-time NY midnight, relevant - whether the separator should remain on chart.
Outputs: None.
*/
void DrawDailySeparator(datetime dayOpen,bool relevant)
  {
   string name=DaySepName(dayOpen);
   if(!relevant)
     {
      DeleteObj(name);
      return;
     }

   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_VLINE,0,dayOpen,0.0))
        {
         PrintFormat("[CCT ERR] ObjectCreate failed for %s (%d)",name,GetLastError());
         return;
        }
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

   _dsi(name,OBJPROP_TIME,0,(long)dayOpen);
   _dsi(name,OBJPROP_COLOR,(long)C'108,108,108');
   _dsi(name,OBJPROP_STYLE,(long)STYLE_DASHDOTDOT);
   _dsi(name,OBJPROP_WIDTH,2);
   _dsi(name,OBJPROP_TIMEFRAMES,TFMask_Full());
   SetCCTTooltip(name,"DAY SEPARATOR\n" + CCTNYTimeLabel(dayOpen,false));
  }

/*
Purpose: Map an event time onto the owning HTF bar open so POI right anchors lock to structural bar opens.
Constitution: Ch. 28.1 precise POI geometry and Ch. 34 visual-layer ownership of anchoring rules.
Inputs: eventTime - structural event timestamp.
Outputs: HTF bar open time containing the event, or the raw event time as fallback.
*/
datetime LockPOIToHTFOpen(datetime eventTime)
  {
   if(eventTime<=0)
      return 0;

   int shift=iBarShift(_Symbol,HTF(),eventTime,false);
   if(shift<0)
      return eventTime;

   datetime htfOpen=iTime(_Symbol,HTF(),shift);
   return (htfOpen>0) ? htfOpen : eventTime;
  }

/*
Purpose: Draw one POI line as overlapping HTF and LTF precision objects for Pass 2 state visibility.
Constitution: Ch. 27.7, Ch. 28, latest user clarification on dormant generation hiding, and the agreed inactive-sibling dim-visibility rule.
Inputs: genKey - generation key, sibIdx - sibling index, level - POI price, bull - direction, state - sibling state, htfLeftAnchor - source wick HTF bar open, ltfLeftAnchor - exact source wick LTF extreme time, rightAnchorLocked - locked end time for dead/resolved states, isLive - whether the line should extend dynamically.
Outputs: None.
*/
void DrawPOILine(string genKey,int sibIdx,double level,bool bull,SIB_STATE state,datetime htfLeftAnchor,datetime ltfLeftAnchor,datetime rightAnchorLocked,bool isLive,datetime c1Time,datetime triggerTime)
  {
   string nmH=ObjN(genKey,"POI_"+IntegerToString(sibIdx)+"_H");
   string nmL=ObjN(genKey,"POI_"+IntegerToString(sibIdx)+"_L");

   if(state==SS_DORMANT && !Inp_ShowDormant)
      {
       DeleteObj(nmH);
       DeleteObj(nmL);
       return;
      }

   bool deadState=(state==SS_DEAD_SUPERSESSION || state==SS_DEAD_CO_VIOLATION ||
                   state==SS_DEAD_WINDOW_CONSUMED || state==SS_DEAD_WINDOW_EXPIRED ||
                   state==SS_DEAD_UNAUTHORIZED_C1 || state==SS_DEAD_BIAS_FLIP);
    if(deadState && !Inp_ShowKilled)
      {
       DeleteObj(nmH);
       DeleteObj(nmL);
       return;
      }

   datetime rightT=isLive ? (datetime)(SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE)+PeriodSeconds(LTF()))
                          : rightAnchorLocked;
   if(rightT<=htfLeftAnchor)
      rightT=htfLeftAnchor+PeriodSeconds(HTF());

   color clr=(state==SS_DORMANT)       ? (bull ? (color)C'14,32,72' : (color)C'75,32,14') :
              (state==SS_VALID)         ? (bull ? (color)C'28,50,84' : (color)C'84,50,28') :
              (state==SS_INACTIVE)      ? (bull ? (color)C'28,50,84' : (color)C'84,50,28') :
              (state==SS_ACTIVE)        ? (bull ? (color)C'78,120,132' : (color)C'132,108,78') :
              (state==SS_TRIGGERED)     ? (bull ? (color)C'88,132,114' : (color)C'142,114,88') :
              (state==SS_RESOLVED_TP)   ? (color)C'86,138,110' :
              (state==SS_RESOLVED_SL)   ? (color)C'138,94,94' :
              (state==SS_RESOLVED_BE)   ? (color)C'152,132,84' :
              (state==SS_RESOLVED_BE_CO)? (color)C'162,138,88' :
                                          (color)C'55,55,55';
   int width=(state==SS_TRIGGERED)?2:1;
   ENUM_LINE_STYLE sty=(state==SS_DORMANT) ? STYLE_DASH :
                        (state==SS_INACTIVE) ? STYLE_DOT :
                        (deadState ? STYLE_DASH : STYLE_SOLID);
   string dir=bull ? "BULL" : "BEAR";
   string wickTime=(ltfLeftAnchor>0) ? CCTNYTimeLabel(ltfLeftAnchor,true) : CCTNYTimeLabel(htfLeftAnchor,false);
   string tooltip=dir + " POI | " + genKey + "\n" +
                  "Px " + DoubleToString(level,_Digits) +
                  " | Src " + wickTime + "\n" +
                  CCTStateLabel(state);
   if((state==SS_ACTIVE || state==SS_TRIGGERED || state==SS_RESOLVED_TP || state==SS_RESOLVED_SL || state==SS_RESOLVED_BE || state==SS_RESOLVED_BE_CO) && c1Time>0)
      tooltip+="\nC1 " + CCTNYTimeLabel(c1Time,true);
   if((state==SS_TRIGGERED || state==SS_RESOLVED_TP || state==SS_RESOLVED_SL || state==SS_RESOLVED_BE || state==SS_RESOLVED_BE_CO) && triggerTime>0)
      tooltip+=" | Entry " + CCTNYTimeLabel(triggerTime+(datetime)PeriodSeconds(LTF()),true);

   CreateHLine(nmH,level,clr,sty,width,TFMask_AboveLTF(),htfLeftAnchor,rightT,tooltip);
   CreateHLine(nmL,level,clr,sty,width,TFMask_ExactLTF(),(ltfLeftAnchor>0)?ltfLeftAnchor:htfLeftAnchor,rightT,tooltip);
  }

#endif
