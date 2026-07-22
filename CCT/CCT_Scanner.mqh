#ifndef CCT_SCANNER_MQH
#define CCT_SCANNER_MQH

#include "CCT_Globals.mqh"

/*
Purpose: Resolve the HTF history depth used by virgin-wick and birth detection.
Constitution: Virgin wick truth must be based on the configured multi-year HTF lookback, not the old fixed 500-bar scanner window.
Inputs: None.
Outputs: Number of HTF bars to request from CopyRates.
*/
int CCTVirginLookbackBars()
  {
   int htfSec=CCTModelHTFSeconds();
   if(htfSec<=0)
      htfSec=4*3600;

   // CCT_FAST_INITIAL_VISUAL_LOOKBACK_V1
   // The first chart paint should make the dashboard usable and draw recent
   // context quickly. The full historical POI cache is reconciled later, after
   // the dashboard has had idle time to accept clicks.
   if(g_cctFastInitialVisualMode)
     {
      if(Inp_TimeframeModel==CCT_TFM_D1_M15)
         return 40;
      if(Inp_TimeframeModel==CCT_TFM_4H_M5)
         return 96;
      return 120;
     }

   double years=CCTVirginLookbackYearsForModel();
   if(years<0.01)
      years=0.01;

   double seconds=years*365.25*86400.0;
   int bars=(int)MathCeil(seconds/(double)htfSec)+10;

   // Preserve the old 500-bar minimum when a smaller value is configured.
   if(bars<500)
      bars=500;

   return bars;
  }
/*
Purpose: Reset the exact LTF-extreme cache only when the chart/scanner context changes.
Constitution: Tester-performance and visual-precision rules require reusing stable closed-HTF anchors across LTF bars.
Inputs: None.
Outputs: Cache arrays cleared on symbol/timeframe changes, not on every M1 close.
*/
void ResetExtremeAnchorCacheIfNeeded()
  {
   static string s_anchorContext="";
   string context=_Symbol+"|LTF="+IntegerToString((int)LTF())+"|HTF="+IntegerToString((int)HTF());
   if(context==s_anchorContext)
      return;

   s_anchorContext=context;
   g_extremeAnchorCacheLastBar=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   ArrayResize(g_extremeAnchorHtfTimes,0);
   ArrayResize(g_extremeAnchorDirs,0);
   ArrayResize(g_extremeAnchorLtfTimes,0);
  }

/*
Purpose: Find the exact LTF bar that made the HTF extreme for a wick or POI source bar.
Constitution: Backup-proven anchoring pattern for precise M1 rendering while preserving HTF-aligned dual objects on higher timeframes.
Inputs: htfBarTime - HTF source bar open time, bull - true for HTF high extreme, false for HTF low extreme.
Outputs: LTF bar time of the exact extreme, or the HTF bar open as a fallback.
*/
datetime FindLTFExtremeBar(datetime htfBarTime,bool bull)
  {
   if(htfBarTime<=0)
      return 0;

   ResetExtremeAnchorCacheIfNeeded();
   int dirFlag=bull ? 1 : 0;
   int cacheCount=ArraySize(g_extremeAnchorHtfTimes);
   for(int i=0;i<cacheCount;i++)
     {
      if(g_extremeAnchorHtfTimes[i]==htfBarTime && g_extremeAnchorDirs[i]==dirFlag)
         return g_extremeAnchorLtfTimes[i];
     }

   int ltfSec=(int)PeriodSeconds(LTF());
   int htfSec=CCTModelHTFSeconds();
   int need=(ltfSec>0) ? (htfSec/ltfSec) : 0;
   if(need<1)
      need=1;

   datetime htfClose=(datetime)(htfBarTime+htfSec);
   datetime htfLastInside=(datetime)(htfClose-1);
   MqlRates ltf[];
   int nl=CopyRates(_Symbol,LTF(),htfBarTime,htfLastInside,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),htfLastInside,need,ltf);

   datetime anchor=htfBarTime;
   if(nl>0)
     {
      double extreme=bull ? ltf[0].high : ltf[0].low;
      anchor=ltf[0].time;
      for(int k=1;k<nl;k++)
        {
         if(bull && ltf[k].high>extreme)
           {
            extreme=ltf[k].high;
            anchor=ltf[k].time;
           }
         if(!bull && ltf[k].low<extreme)
           {
            extreme=ltf[k].low;
            anchor=ltf[k].time;
           }
        }
     }

   int newSize=cacheCount+1;
   ArrayResize(g_extremeAnchorHtfTimes,newSize);
   ArrayResize(g_extremeAnchorDirs,newSize);
   ArrayResize(g_extremeAnchorLtfTimes,newSize);
   g_extremeAnchorHtfTimes[cacheCount]=htfBarTime;
   g_extremeAnchorDirs[cacheCount]=dirFlag;
   g_extremeAnchorLtfTimes[cacheCount]=anchor;
   return anchor;
  }

/*
Purpose: Load and cache an LTF rates window so later scanner passes avoid hot-loop CopyRates calls.
Constitution: Ch. 36 scanner data load, tester performance rules, and pass-1 cache requirement.
Inputs: from - inclusive start time, to - inclusive end time, out - destination rates array.
Outputs: Number of bars copied into out.
*/
int CopyLTFWindow(datetime from,datetime to,MqlRates &out[])
  {
   datetime lastBar=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);

   // CCT_LTF_CACHE_RESPECTS_REQUESTED_TO_V5
   // Cache hits must return only bars <= the caller-requested `to` time.
   // Otherwise pre-init/historical scans can receive future LTF bars,
   // making valid synthetic triggers look stale or expired.
   if(to<from)
     {
      ArrayResize(out,0);
      return 0;
     }

   if(from==g_ltfCacheFrom && lastBar==g_ltfCacheLastBar && ArraySize(g_ltfCache)>0 && g_ltfCacheTo>0 && to<=g_ltfCacheTo)
     {
      int cacheN=ArraySize(g_ltfCache);
      int n=0;

      while(n<cacheN && g_ltfCache[n].time<=to)
         n++;

      ArrayResize(out,n);
      for(int i=0;i<n;i++)
         out[i]=g_ltfCache[i];

      return n;
     }

   if(from==g_ltfCacheFrom && ArraySize(g_ltfCache)>0 && g_ltfCacheTo>0 && to>g_ltfCacheTo)
     {
      MqlRates add[];
      datetime appendFrom=g_ltfCacheTo+(datetime)PeriodSeconds(LTF());
      int added=0;
      if(appendFrom<=to)
         added=CopyRates(_Symbol,LTF(),appendFrom,to,add);

      if(added>0)
        {
         int oldSize=ArraySize(g_ltfCache);
         ArrayResize(g_ltfCache,oldSize+added);
         for(int i=0;i<added;i++)
            g_ltfCache[oldSize+i]=add[i];

         g_ltfCacheTo=to;
         g_ltfCacheLastBar=lastBar;
         ArrayCopy(out,g_ltfCache);
         return ArraySize(out);
        }
     }

   ArrayResize(g_ltfCache,0);
   int copied=CopyRates(_Symbol,LTF(),from,to,g_ltfCache);
   if(copied<1)
     {
      ArrayResize(out,0);
      return 0;
     }

   g_ltfCacheFrom=from;
   g_ltfCacheTo=to;
   g_ltfCacheLastBar=lastBar;
   ArrayCopy(out,g_ltfCache);
   return copied;
  }

/*
Purpose: Classify closed HTF virgin wicks and live-candidate wick states for the forming HTF bar.
Constitution: Ch. 3, Ch. 28, and Ch. 36.1 virgin wick and candidate rules.
Inputs: B - HTF bars newest-first, n - bar count, bulls - bullish wick outputs, nBull - bullish count, bears - bearish wick outputs, nBear - bearish count.
Outputs: Populated bull and bear wick arrays with WS_VIRGIN or WS_CANDIDATE states.
*/
void ClassifyWicks(MqlRates &B[],int n,WickInfo &bulls[],int &nBull,WickInfo &bears[],int &nBear)
  {
   nBull=0;
   nBear=0;

   if(n<2)
      return;

   int bullCap=ArraySize(bulls);
   int bearCap=ArraySize(bears);

   double maxClosedHigh=-DBL_MAX;
   double minClosedLow=DBL_MAX;

   for(int i=1;i<n;i++)
     {
      // Newest-first series: a wick is virgin when no newer CLOSED bar
      // has already reached it. Running records avoid the old O(n^2) scan.
      bool virginBull=(maxClosedHigh<B[i].high);
      bool virginBear=(minClosedLow>B[i].low);

      if(virginBull && nBull<bullCap)
        {
         bulls[nBull].barTime=B[i].time;
         // Exact LTF anchoring is resolved lazily only for wicks that are actually drawn.
         bulls[nBull].ltfAnchor=B[i].time;
         bulls[nBull].level=B[i].high;
         bulls[nBull].bull=true;
         bulls[nBull].state=WS_VIRGIN;
         nBull++;
        }

      if(virginBear && nBear<bearCap)
        {
         bears[nBear].barTime=B[i].time;
         // Exact LTF anchoring is resolved lazily only for wicks that are actually drawn.
         bears[nBear].ltfAnchor=B[i].time;
         bears[nBear].level=B[i].low;
         bears[nBear].bull=false;
         bears[nBear].state=WS_VIRGIN;
         nBear++;
        }

      if(B[i].high>maxClosedHigh)
         maxClosedHigh=B[i].high;
      if(B[i].low<minClosedLow)
         minClosedLow=B[i].low;
     }

   for(int i=0;i<nBull;i++)
     {
      if(B[0].high>=bulls[i].level)
         bulls[i].state=WS_CANDIDATE;
     }

   for(int i=0;i<nBear;i++)
     {
      if(B[0].low<=bears[i].level)
         bears[i].state=WS_CANDIDATE;
     }
  }

/*
Purpose: Append a birth index once per direction so one birth bar yields one generation entry.
Constitution: Ch. 4.1 and Ch. 36.2 one birth candle creates one generation.
Inputs: idx - HTF bar index to add, births - destination array, count - current array count.
Outputs: Updated birth list and count with duplicates prevented.
*/
void AddBirthIndex(int idx,int &births[],int &count)
  {
   int cap=ArraySize(births);
   for(int i=0;i<count;i++)
     {
      if(births[i]==idx)
         return;
     }

   if(count>=cap)
     {
      int newCap=(cap<1) ? 32 : (cap+32);
      ArrayResize(births,newCap);
     }

   births[count]=idx;
   count++;
  }

/*
Purpose: Build bullish and bearish HTF birth-bar index lists from historical virgin wick conversions.
Constitution: Ch. 3.4, Ch. 4.1, and Ch. 36.2 body-close birth detection.
Inputs: B - HTF bars newest-first, n - bar count, bullBirths - bullish output indices, nBull - bullish count, bearBirths - bearish output indices, nBear - bearish count.
Outputs: Unique birth-bar index lists for bullish and bearish generations.
*/
void BuildBirthLists(MqlRates &B[],int n,int &bullBirths[],int &nBull,int &bearBirths[],int &nBear)
  {
   nBull=0;
   nBear=0;

   if(n<3)
      return;

   double bullVirginStack[];
   double bearVirginStack[];
   int bullVirginCount=0;
   int bearVirginCount=0;
   ArrayResize(bullVirginStack,n);
   ArrayResize(bearVirginStack,n);

   for(int i=n-1;i>=1;i--)
     {
      bool bullBirth=(bullVirginCount>0 && B[i].close>bullVirginStack[bullVirginCount-1]);
      bool bearBirth=(bearVirginCount>0 && B[i].close<bearVirginStack[bearVirginCount-1]);

      if(bullBirth)
         AddBirthIndex(i,bullBirths,nBull);
      if(bearBirth)
         AddBirthIndex(i,bearBirths,nBear);

      while(bullVirginCount>0 && B[i].high>=bullVirginStack[bullVirginCount-1])
         bullVirginCount--;
      bullVirginStack[bullVirginCount]=B[i].high;
      bullVirginCount++;

      while(bearVirginCount>0 && B[i].low<=bearVirginStack[bearVirginCount-1])
         bearVirginCount--;
      bearVirginStack[bearVirginCount]=B[i].low;
      bearVirginCount++;
     }
  }

/*
Purpose: Find and lock the correction origin between generation birth and the C1 bar using the legacy V6 extreme-selection rule.
Constitution: CO is the correction-side origin extreme that exists before/at C1; post-C1 structure must not contaminate the locked CO.
Inputs: ltf - LTF rates array, nl - bar count, bull - direction, birthFrom - generation birth time, c1BarTime - LTF bar open time that achieved C1, coPrice - output CO price, coTime - output CO LTF wick time.
Outputs: coPrice and coTime set to the latest exact LTF extreme through C1, or zeroed when unavailable.
*/
void FindCorrectionOrigin(MqlRates &ltf[],int nl,bool bull,datetime birthFrom,datetime c1BarTime,double &coPrice,datetime &coTime)
  {
   coPrice=0.0;
   coTime=0;

   if(nl<1 || birthFrom<=0 || c1BarTime<=0)
      return;

   double priceTol=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(priceTol<=0.0)
      priceTol=_Point;
   if(priceTol<=0.0)
      priceTol=1e-8;

   double displayTol=(_Point>0.0) ? (_Point*0.5) : priceTol;

   bool found=false;
   double extreme=0.0;
   datetime extTime=0;
   datetime sourceStart=birthFrom;
   datetime cutoff=c1BarTime;

   for(int i=0;i<nl;i++)
     {
      if(ltf[i].time<sourceStart || ltf[i].time>cutoff)
         continue;

      double value=bull ? ltf[i].high : ltf[i].low;

      if(!found)
        {
         extreme=value;
         extTime=ltf[i].time;
         found=true;
         continue;
        }

      double dispExtreme=NormalizeDouble(extreme,_Digits);
      double dispValue=NormalizeDouble(value,_Digits);

      if(bull)
        {
         if(value>extreme+priceTol)
           {
            extreme=value;
            extTime=ltf[i].time;
           }
         else if((MathAbs(value-extreme)<=priceTol || MathAbs(dispValue-dispExtreme)<=displayTol) &&
                 ltf[i].time>extTime)
           {
            extTime=ltf[i].time;
           }
        }
      else
        {
         if(value<extreme-priceTol)
           {
            extreme=value;
            extTime=ltf[i].time;
           }
         else if((MathAbs(value-extreme)<=priceTol || MathAbs(dispValue-dispExtreme)<=displayTol) &&
                 ltf[i].time>extTime)
           {
            extTime=ltf[i].time;
           }
        }
     }

   if(!found)
      return;

   coPrice=extreme;
   coTime=extTime;
  }

/*
Purpose: Lock a generation's CO once at its first valid C1 and prevent later C2/C3 or sibling recovery bars from moving it.
Constitution: CO is pre-trigger correction context; post-C1 structure must never overwrite the already-locked CO.
Inputs: g - generation record, ltf - LTF rates, nl - LTF count, c1BarTime - C1 bar used only if CO is not already locked.
Outputs: g.coPrice/g.coTime/g.coLtfAnchor set once.
*/
void LockCorrectionOriginIfNeeded(GenInfo &g,MqlRates &ltf[],int nl,datetime c1BarTime,bool forceRelock=false)
  {
   if(!forceRelock && g.coLocked && g.coTime>0 && g.coPrice>0.0)
      return;

   FindCorrectionOrigin(ltf,nl,g.bull,g.birthTime,c1BarTime,g.coPrice,g.coTime);
   g.coLocked=(g.coTime>0);
   g.coLtfAnchor=g.coTime;
  }

/*
Purpose: Sort sibling POI levels from shallowest to deepest for activation order.
Constitution: Ch. 11 sibling supersession order and Pass 2 ordering rules.
Inputs: sibs - sibling array, n - sibling count, bull - direction.
Outputs: Siblings sorted shallow-first.
*/
void SortSiblingsShallowFirst(SibInfo &sibs[],int n,bool bull)
  {
   for(int i=1;i<n;i++)
     {
      SibInfo key=sibs[i];
      int j=i-1;

      while(j>=0)
        {
         bool move=bull ? (sibs[j].level<key.level) : (sibs[j].level>key.level);
         if(!move)
            break;
         sibs[j+1]=sibs[j];
         j--;
        }
      sibs[j+1]=key;
     }
  }

/*
Purpose: Check whether a historical HTF wick was still virgin immediately before a birth bar.
Constitution: Ch. 3.1, Ch. 3.4, and Pass 2 sibling construction rules.
Inputs: B - HTF bars newest-first, birthIdx - birth bar index, wickIdx - candidate wick index, bull - direction.
Outputs: True if the wick remained virgin until the birth bar converted it.
*/
bool WasVirginAtBirth(MqlRates &B[],int birthIdx,int wickIdx,bool bull)
  {
   if(wickIdx<=birthIdx)
      return false;

   for(int m=birthIdx+1;m<wickIdx;m++)
     {
      if(bull && B[m].high>=B[wickIdx].high)
         return false;
      if(!bull && B[m].low<=B[wickIdx].low)
         return false;
     }

   return true;
  }

/*
Purpose: Build the sibling set for one generation from all wick levels converted by its birth bar.
Constitution: Ch. 4 and Pass 2 sibling-construction rules.
Inputs: B - HTF bars newest-first, n - bar count, birthIdx - birth bar index, bull - direction, g - generation to populate.
Outputs: g.sibs and g.nSibs populated and sorted shallow-first.
*/
void BuildGenerationSiblings(MqlRates &B[],int n,int birthIdx,bool bull,GenInfo &g,bool resolveLtfAnchors=true)
  {
   g.nSibs=0;
   if(birthIdx<1 || birthIdx>=n)
      return;

   double closePx=B[birthIdx].close;

   for(int j=birthIdx+1;j<n && g.nSibs<CCT_MAX_SIBS;j++)
     {
      double level=bull ? B[j].high : B[j].low;
      bool converted=bull ? (closePx>level) : (closePx<level);
      if(!converted || !WasVirginAtBirth(B,birthIdx,j,bull))
         continue;

      bool duplicate=false;
      for(int s=0;s<g.nSibs;s++)
        {
         if(MathAbs(g.sibs[s].level-level)<=MathMax(_Point,1e-8))
           {
            duplicate=true;
            break;
           }
        }
      if(duplicate)
         continue;

      g.sibs[g.nSibs].level=level;
      g.sibs[g.nSibs].wickTime=B[j].time;
      g.sibs[g.nSibs].ltfAnchor=resolveLtfAnchors ? FindLTFExtremeBar(B[j].time,bull) : B[j].time;
      g.sibs[g.nSibs].state=SS_VALID;
      g.sibs[g.nSibs].c1Time=0;
      g.sibs[g.nSibs].c2Time=0;
      g.sibs[g.nSibs].c3Time=0;
      g.sibs[g.nSibs].hadAuthorizedC1=false;
      g.sibs[g.nSibs].authorityRoute=AUTH_ROUTE_NONE;
      g.sibs[g.nSibs].authorityHTFOpen=0;
      g.sibs[g.nSibs].authorityHourNY=-1;
      g.sibs[g.nSibs].authorityOffset=-1;
      g.sibs[g.nSibs].authorityDormantTakeover=false;
      g.sibs[g.nSibs].authorityRecordOnly=false;
      g.sibs[g.nSibs].tsScopeFrom=0;
      g.sibs[g.nSibs].tsLevel=0.0;
      g.sibs[g.nSibs].tsWickTime=0;
      g.sibs[g.nSibs].dynamicEndTime=0;
      g.nSibs++;
     }

   SortSiblingsShallowFirst(g.sibs,g.nSibs,bull);
  }

/*
Purpose: Return whether a sibling state is still structurally alive for Pass 2 scanning.
Constitution: Ch. 10 state inventory and Pass 2 scan guards.
Inputs: state - sibling state.
Outputs: True for VALID, ACTIVE, or INACTIVE.
*/
bool IsAliveSiblingState(SIB_STATE state)
  {
   return (state==SS_VALID || state==SS_ACTIVE || state==SS_INACTIVE || state==SS_DORMANT);
  }

/*
Purpose: Test whether an LTF close has crossed a POI level in the correction direction.
Constitution: Ch. 12 and Ch. 36.4 C1 detection always uses LTF body-close direction.
Inputs: bull - trade direction, cls - LTF close, level - sibling price.
Outputs: True when the close has crossed the level in correction direction.
*/
bool IsC1Cross(bool bull,double cls,double level)
  {
   double tol=MathMax(_Point*0.1,1e-8);
   return bull ? (cls<=level+tol) : (cls>=level-tol);
  }

/*
Purpose: Identify dormant siblings whose first C1 happened while bias was counter to the generation.
Constitution: Latest user clarification that counter-bias C1 can never become executable later even if bias flips back before C2+C3.
Inputs: sib - sibling record.
Outputs: True when the sibling must only be monitored for terminal invalidation, never reactivated.
*/
bool DormantCounterBiasC1Poisoned(const SibInfo &sib)
  {
   return (sib.state==SS_DORMANT && sib.c1Time>0 && !sib.hadAuthorizedC1);
  }

/*
Purpose: Return the shallowest crossed sibling index among scannable states for the current LTF close.
Constitution: Ch. 11 corrected shallowest-first activation order and Pass 2 initial C1 rules.
Inputs: g - generation, cls - LTF close, includeInactive - whether inactive siblings are eligible.
Outputs: Shallowest crossed sibling index, or -1 if none were crossed.
*/
int ShallowestCrossedSibling(const GenInfo &g,double cls,bool includeInactive)
  {
   for(int s=0;s<g.nSibs;s++)
     {
      if(DormantCounterBiasC1Poisoned(g.sibs[s]))
         continue;
      bool eligible=(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT) ||
                    (includeInactive && g.sibs[s].state==SS_INACTIVE);
      if(!eligible)
         continue;
      if(IsC1Cross(g.bull,cls,g.sibs[s].level))
         return s;
     }
   return -1;
  }

/*
Purpose: Return the deepest crossed sibling index among scannable states for the current LTF close.
Constitution: Ch. 11.4 and Ch. 36.4 deepest reached in one bar becomes active.
Inputs: g - generation, cls - LTF close, includeInactive - whether inactive siblings are eligible.
Outputs: Deepest crossed sibling index, or -1 if none were crossed.
*/
int DeepestCrossedSibling(const GenInfo &g,double cls,bool includeInactive)
  {
   int deepest=-1;
   for(int s=0;s<g.nSibs;s++)
     {
      if(DormantCounterBiasC1Poisoned(g.sibs[s]))
         continue;
      bool eligible=(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT) ||
                    (includeInactive && g.sibs[s].state==SS_INACTIVE);
      if(!eligible)
         continue;
      if(IsC1Cross(g.bull,cls,g.sibs[s].level))
         deepest=s;
     }
   return deepest;
  }

/*
Purpose: Move all still-live siblings in a generation to a terminal dead state.
Constitution: Ch. 16 and execution-window supersession rules remove prior untriggered ownership.
Inputs: g - generation to kill, deadState - terminal state to assign, eventTime - structural end time.
Outputs: g updated in place.
*/
/*
Purpose: Test whether the current LTF candle actually crossed into C1 territory.
Constitution: C1 must be assigned only on the first LTF close that crosses the POI, not on a later candle already sitting beyond the POI.
Inputs: bull - trade direction, prevCls - previous LTF close or current open fallback, cls - current LTF close, level - sibling POI level.
Outputs: True only for a close-to-close C1 edge crossing. A close exactly at the POI level counts.
*/
bool IsC1EdgeCross(bool bull,double prevCls,double cls,double level)
  {
   double tol=MathMax(_Point*0.1,1e-8);
   return bull ? (prevCls>=level-tol && cls<=level+tol) : (prevCls<=level+tol && cls>=level-tol);
  }
 
/*
Purpose: Resolve previous LTF close for C1 edge detection.
Constitution: First available LTF bar uses its own open as fallback.
Inputs: ltf - LTF rates array, k - current index.
Outputs: Previous close when available, otherwise current open.
*/
double C1PrevClose(MqlRates &ltf[],int k)
  {
   if(k>0)
      return ltf[k-1].close;
   return ltf[k].open;
  }

/*
Purpose: Return the first eligible sibling whose current closed LTF bar actually crosses into C1 territory.
Constitution: C1 activation must be a close-to-close edge crossing, not a later candle that was already beyond the POI.
Inputs: g - generation, prevCls - retained for older callers, cls - current LTF close, includeInactive - whether inactive siblings can be selected.
Outputs: Shallowest crossed sibling index, or -1 if no eligible sibling is crossed.
*/
int ShallowestCrossedSiblingEdge(const GenInfo &g,double prevCls,double cls,bool includeInactive)
  {
   for(int s=0;s<g.nSibs;s++)
     {
      if(DormantCounterBiasC1Poisoned(g.sibs[s]))
         continue;
      bool eligible=(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT) ||
                    (includeInactive && g.sibs[s].state==SS_INACTIVE);
      if(!eligible)
         continue;
      if(IsC1EdgeCross(g.bull,prevCls,cls,g.sibs[s].level))
         return s;
     }
   return -1;
  }

/*
Purpose: Clear execution-authority metadata attached to a sibling.
Constitution: A fresh C1 path must not inherit stale model routing, TS scope, or broker eligibility from an older path unless the scanner explicitly copies it.
Inputs: sib - sibling record.
Outputs: Authority fields reset in place.
*/
void ClearSiblingAuthority(SibInfo &sib)
  {
   sib.hadAuthorizedC1=false;
   sib.authorityRoute=AUTH_ROUTE_NONE;
   sib.authorityHTFOpen=0;
   sib.authorityHourNY=-1;
   sib.authorityOffset=-1;
   sib.authorityDormantTakeover=false;
   sib.authorityRecordOnly=false;
   sib.tsScopeFrom=0;
  }

/*
Purpose: Resolve whether a closed LTF C1 belongs to a configured execution route.
Constitution: Execution-hour selection authorizes C1; the later trigger carries that C1 authority rather than re-guessing from trigger-bar distance.
Inputs: g - generation, eventTime - C1 close time, dormantTakeover - true for older dormant shoot-through.
Outputs: Route metadata for the C1 authority.
*/
bool ResolveC1AuthorityRoute(const GenInfo &g,datetime eventTime,bool dormantTakeover,
                             ENUM_CCT_AUTH_ROUTE &route,datetime &htfOpen,int &nyHour,int &offset)
  {
   route=AUTH_ROUTE_NONE;
   htfOpen=HTFBarOpenForTime(eventTime);
   nyHour=-1;
   offset=-1;

   if(htfOpen<=0 || g.birthTime<=0)
      return false;

   offset=GenerationExecutionOffset(g.birthTime,htfOpen);
   if(offset<1)
      return false;

   datetime authTime=(Inp_TimeframeModel==CCT_TFM_1H_M1 ? htfOpen : eventTime);
   MqlDateTime ny={};
   TimeToStruct(ToExecutionNY(authTime),ny);
   nyHour=ny.hour;

   if(!Inp_SessionFilter)
     {
      route=(offset<=1 ? AUTH_ROUTE_CCT : AUTH_ROUTE_CCT_EXT);
      return true;
     }

   bool hasCct=CCTModelCCTAuthAllows(authTime);
   bool hasTs=CCTModelTSAuthAllows(authTime);
   bool hasExt=CCTModelExtAuthAllows(authTime);
   if(!hasCct && !hasTs && !hasExt)
      return false;

   if(dormantTakeover)
     {
      if(hasTs)
        {
         route=AUTH_ROUTE_TS;
         return true;
        }
      if(hasExt)
        {
         route=AUTH_ROUTE_TS_EXT;
         return true;
        }
      return false;
     }

   if(GenerationFallbackBlockedByNearerSource(g,htfOpen,offset))
      return false;

   if(offset==1)
     {
      if(hasCct)
         route=AUTH_ROUTE_CCT;
      else if(hasTs)
         route=AUTH_ROUTE_TS;
      else
         route=AUTH_ROUTE_TS_EXT;
      return true;
     }

   if(hasCct)
     {
      route=AUTH_ROUTE_CCT_EXT;
      return true;
     }

   if(hasTs)
     {
      route=AUTH_ROUTE_TS;
      return true;
     }

   if(hasExt)
     {
      route=AUTH_ROUTE_TS_EXT;
      return true;
     }

   return false;
  }

/*
Purpose: Attach a resolved C1 authority route to a sibling.
Constitution: Final trigger authorization and model comments must use the C1 route that was actually earned.
Inputs: g - generation, sibIdx - sibling index, route metadata, recordOnly - block broker execution while still monitoring structure.
Outputs: Sibling authority fields updated in place.
*/
void StampSiblingAuthority(GenInfo &g,int sibIdx,ENUM_CCT_AUTH_ROUTE route,datetime htfOpen,
                           int nyHour,int offset,bool dormantTakeover,bool recordOnly,datetime tsScopeFrom)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs)
      return;

   g.sibs[sibIdx].hadAuthorizedC1=!recordOnly;
   g.sibs[sibIdx].authorityRoute=recordOnly ? AUTH_ROUTE_RECORD_ONLY : route;
   g.sibs[sibIdx].authorityHTFOpen=htfOpen;
   g.sibs[sibIdx].authorityHourNY=nyHour;
   g.sibs[sibIdx].authorityOffset=offset;
   g.sibs[sibIdx].authorityDormantTakeover=dormantTakeover;
   g.sibs[sibIdx].authorityRecordOnly=recordOnly;

   datetime floor=ActionPillarTime(g.birthTime);
   if(tsScopeFrom<=0)
      tsScopeFrom=floor;
   if(tsScopeFrom<floor)
      tsScopeFrom=floor;
   g.sibs[sibIdx].tsScopeFrom=tsScopeFrom;
  }

/*
Purpose: Move active authority to a deeper sibling without changing the selected C1 route.
Constitution: A deeper sibling supersession resets confirmation geometry, but it may inherit the active execution path when it occurs inside an already-authorized carry sequence.
Inputs: g - generation, fromIdx - prior active sibling, toIdx - new active sibling, eventTime - deeper C1 time.
Outputs: New sibling receives inherited C1 authority and a fresh TS scope from its C1 HTF open.
*/
void InheritSiblingAuthority(GenInfo &g,int fromIdx,int toIdx,datetime eventTime)
  {
   if(fromIdx<0 || fromIdx>=g.nSibs || toIdx<0 || toIdx>=g.nSibs)
      return;

   datetime scope=HTFBarOpenForTime(eventTime);
   if(scope<=0)
      scope=g.sibs[fromIdx].tsScopeFrom;

   StampSiblingAuthority(g,toIdx,g.sibs[fromIdx].authorityRoute,
                         g.sibs[fromIdx].authorityHTFOpen,
                         g.sibs[fromIdx].authorityHourNY,
                         g.sibs[fromIdx].authorityOffset,
                         g.sibs[fromIdx].authorityDormantTakeover,
                         g.sibs[fromIdx].authorityRecordOnly,
                         scope);
  }

void KillGenerationLiveSiblings(GenInfo &g,SIB_STATE deadState,datetime eventTime)
  {
   g.dormant=false;
   g.activeSibIdx=-1;
   for(int s=0;s<g.nSibs;s++)
     {
      if(!IsAliveSiblingState(g.sibs[s].state))
         continue;
      g.sibs[s].state=deadState;
      if(g.sibs[s].c1Time==0)
         g.sibs[s].c1Time=eventTime;
     }
  }

/*
Purpose: Terminate only the currently traded POI when HTF bias flips before trigger.
Constitution: Latest user clarification that a bias flip kills the active C1 POI and invalidates its TS hint, but does not automatically burn untouched deeper siblings forever.
Inputs: g - generation record, eventTime - bias-flip scan time.
Outputs: Active sibling killed, deeper inactive siblings restored for possible future activation, and TS eligibility reset after the flip.
*/
void KillActiveSiblingOnBiasFlip(GenInfo &g,datetime eventTime)
  {
   int killedIdx=g.activeSibIdx;
   if(killedIdx>=0 && killedIdx<g.nSibs && g.sibs[killedIdx].state==SS_ACTIVE)
     {
      g.sibs[killedIdx].state=SS_DEAD_BIAS_FLIP;
      if(g.sibs[killedIdx].c1Time<=0)
         g.sibs[killedIdx].c1Time=eventTime;
      g.sibs[killedIdx].c2Time=0;
      g.sibs[killedIdx].c3Time=0;
     }

   for(int s=0;s<g.nSibs;s++)
     {
      if(g.sibs[s].state==SS_INACTIVE)
        {
          g.sibs[s].state=SS_DORMANT;
          g.sibs[s].c1Time=0;
          g.sibs[s].c2Time=0;
          g.sibs[s].c3Time=0;
          ClearSiblingAuthority(g.sibs[s]);
         }
      }

   g.activeSibIdx=-1;
   g.tsEligibleFrom=eventTime;
   g.tsDisplayLevel=0.0;
   g.tsDisplayWickTime=0;
   g.tsDisplayLtfAnchor=0;
   g.tsFirstTouchTime=0;
   g.tsConfirmed=false;
   g.sweepCount=0;
   g.tsBirthOrOlderSweepCount=0;
   g.tsPostBirthSweepCount=0;
   g.modelType=MODEL_CCT;
   g.c3FvgIdx=-1;
  }

/*
Purpose: Stop record-only unauthorized C1 tracking when HTF bias flips before structural completion.
Constitution: A C1 that was not authorized may be monitored only while the same-bias structure remains alive; an opposite-bias HTF birth invalidates that pending path before it can later mutate into C2/C3.
Inputs: g - generation record, eventTime - bias-flip scan time.
Outputs: Unauthorized C1 siblings converted to terminal bias-flip deaths and TS/trigger memory cleared for the invalidated path.
*/
bool KillUnauthorizedC1SiblingsOnBiasFlip(GenInfo &g,datetime eventTime)
  {
   bool killed=false;
   for(int s=0;s<g.nSibs;s++)
     {
      if(g.sibs[s].state!=SS_DEAD_UNAUTHORIZED_C1 || g.sibs[s].c1Time<=0)
         continue;
      if(g.sibs[s].c2Time>0 && g.sibs[s].c3Time>0)
         continue;
      g.sibs[s].state=SS_DEAD_BIAS_FLIP;
      g.sibs[s].c2Time=0;
      g.sibs[s].c3Time=0;
      ClearSiblingAuthority(g.sibs[s]);
      killed=true;
     }

   if(!killed)
      return false;

   g.activeSibIdx=-1;
   g.tsEligibleFrom=eventTime;
   g.tsDisplayLevel=0.0;
   g.tsDisplayWickTime=0;
   g.tsDisplayLtfAnchor=0;
   g.tsFirstTouchTime=0;
   g.tsConfirmed=false;
   g.sweepCount=0;
   g.tsBirthOrOlderSweepCount=0;
   g.tsPostBirthSweepCount=0;
   g.modelType=MODEL_CCT;
   g.c3FvgIdx=-1;
   return true;
  }

/*
Purpose: Check whether all siblings in a generation are no longer scannable.
Constitution: Pass 2 generation-scan skip rules.
Inputs: g - generation record.
Outputs: True if no sibling remains VALID, ACTIVE, or INACTIVE.
*/
bool AllSiblingsDead(const GenInfo &g)
  {
   for(int i=0;i<g.nSibs;i++)
     {
      if(IsAliveSiblingState(g.sibs[i].state))
         return false;
     }
   return true;
  }

/*
Purpose: Locate the first lower-timeframe bar that can affect a generation scan.
Constitution: Scanner truth may replay history, but a generation cannot activate before its action pillar; avoiding earlier bars preserves behaviour while preventing non-visual tester replays from repeatedly walking irrelevant history.
Inputs: ltf - oldest-first lower-timeframe bars, nl - bar count, when - minimum event time.
Outputs: Index of the first bar at or after when, clamped to the available LTF window.
*/
int FirstLTFIndexAtOrAfter(MqlRates &ltf[],int nl,datetime when)
  {
   if(nl<=0 || when<=0)
      return 0;

   int lo=0;
   int hi=nl-1;
   int ans=nl;
   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      if(ltf[mid].time>=when)
        {
         ans=mid;
         hi=mid-1;
        }
      else
         lo=mid+1;
     }

   if(ans<0)
      return 0;
   if(ans>=nl)
      return nl;
   return ans;
  }

/*
Purpose: Determine whether an event belongs to the current closed LTF bar window.
Constitution: Historical replay must not be confused with the live/current lifecycle edge.
Inputs: eventTime - structural event bar time.
Outputs: True when the event belongs to the current closed LTF bar window.
*/
bool EventIsCurrentLTF(datetime eventTime)
  {
   if(eventTime<=0)
      return false;

   datetime lastBar=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   int ltfSec=(int)PeriodSeconds(LTF());
   if(lastBar<=0 || ltfSec<=0)
      return true;

   return (eventTime>=lastBar-(datetime)ltfSec && eventTime<=lastBar);
  }

/*
Purpose: Gate debug lifecycle messages so historical scanner replay does not reprint old events on every tester redraw.
Constitution: Tester journals should report meaningful lifecycle events once, not replay the entire scan history every visual refresh.
Inputs: eventTime - structural event bar time.
Outputs: True when debug is enabled and the event belongs to the current closed LTF bar window.
*/
bool DebugEventIsCurrentLTF(datetime eventTime)
  {
   return (CCTDebugEnabled() && EventIsCurrentLTF(eventTime));
  }

/*
Purpose: Suppress duplicate debug lifecycle messages from repeated historical scanner reconstruction.
Constitution: Live and tester journals should show meaningful lifecycle events without replaying the same event every redraw.
Inputs: kind - event family, genKey - generation key, sibIdx - sibling index, eventTime - event timestamp.
Outputs: True once per event while debug is enabled and the event belongs to the current LTF window.
*/
bool DebugEventShouldPrint(string kind,string genKey,int sibIdx,datetime eventTime)
  {
   if(!DebugEventIsCurrentLTF(eventTime))
      return false;

   static string printedKeys[];
   static int printedCount=0;

   string key=kind+"|"+genKey+"|"+IntegerToString(sibIdx)+"|"+IntegerToString((long)eventTime);
   for(int i=0;i<printedCount;i++)
     {
      if(printedKeys[i]==key)
         return false;
     }

   if(printedCount>=512)
     {
      ArrayResize(printedKeys,0);
      printedCount=0;
     }

   ArrayResize(printedKeys,printedCount+1);
   printedKeys[printedCount]=key;
   printedCount++;
   return true;
  }

/*
Purpose: Compact boolean formatter for scanner diagnostics.
Constitution: Tester forensic logs must be parseable and avoid ambiguous true/false spellings.
Inputs: value - boolean condition.
Outputs: "yes" when true, "no" when false.
*/
string DebugBoolText(bool value)
  {
   return value ? "yes" : "no";
  }

/*
Purpose: Explain why a crossed POI could not receive authorized C1 ownership.
Constitution: Selected execution windows authorize C1; rejected C1s must be auditable so live, visual tester, and non-visual tester decisions can be compared.
Inputs: g - generation, sibIdx - crossed sibling, eventTime - LTF close time, cls - close that crossed, dormantTakeover - true for dormant shoot-through path, reason - local scanner reason.
Outputs: Emits one [CCT DBG] row when debug is enabled.
*/
void DebugPrintC1AuthorityReject(const GenInfo &g,int sibIdx,datetime eventTime,double cls,bool dormantTakeover,string reason)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   if(!DebugEventShouldPrint("C1_AUTH_REJECT",genKey,sibIdx,eventTime))
      return;

   datetime htfOpen=HTFBarOpenForTime(eventTime);
   int offset=GenerationExecutionOffset(g.birthTime,htfOpen);
   int hour=-1;
   bool hasCct=false;
   bool hasTs=false;
   bool hasExt=false;
   if(htfOpen>0)
     {
      MqlDateTime ny={};
      TimeToStruct(ToExecutionNY(htfOpen),ny);
      hour=ny.hour;
      hasCct=CachedCCTHour(hour);
      hasTs=CachedTSHour(hour);
      hasExt=CachedExtHour(hour);
     }

   bool fallbackBlocked=(offset>1 && htfOpen>0 && GenerationFallbackBlockedByNearerSource(g,htfOpen,offset));
   bool owns=GenerationOwnsExecutionBar(g,eventTime);
   bool dormantOwns=GenerationOwnsDormantTakeoverBar(g,eventTime);
   bool opposite=GenerationBiasIsOppositeAt(g,eventTime);
   double level=(sibIdx>=0 && sibIdx<g.nSibs) ? g.sibs[sibIdx].level : 0.0;

   datetime endAt=0;
   bool hasEnd=ResolveGenerationLastAuthorizedEndForGeneration(g,endAt);

   CCTJournalLine(StringFormat("[CCT DBG] C1_AUTH_REJECT | gen=%s | S%d | reason=%s | dormantPath=%s | eventNY=%s | htfNY=%s | hour=%02d | offset=%d | level=%.5f | cls=%.5f | hasCCT=%s hasTS=%s hasEXT=%s | fallbackBlocked=%s | owns=%s dormantOwns=%s | oppositeBias=%s | hasEnd=%s endNY=%s",
                               genKey,
                               sibIdx+1,
                               reason,
                               DebugBoolText(dormantTakeover),
                               TimeToString(ToNY(eventTime),TIME_DATE|TIME_MINUTES),
                               htfOpen>0 ? TimeToString(ToNY(htfOpen),TIME_DATE|TIME_MINUTES) : "-",
                               hour,
                               offset,
                               level,
                               cls,
                               DebugBoolText(hasCct),
                               DebugBoolText(hasTs),
                               DebugBoolText(hasExt),
                               DebugBoolText(fallbackBlocked),
                               DebugBoolText(owns),
                               DebugBoolText(dormantOwns),
                               DebugBoolText(opposite),
                               DebugBoolText(hasEnd),
                               endAt>0 ? TimeToString(ToNY(endAt),TIME_DATE|TIME_MINUTES) : "-"));
  }

/*
Purpose: Explain when a generation is killed because its unactivated execution window expired.
Constitution: Window-expiry is a terminal lifecycle decision and must not silently mask valid delayed-C1 carry.
Inputs: g - generation, eventTime - LTF close time where expiry is applied.
Outputs: Emits one [CCT DBG] row when debug is enabled.
*/
void DebugPrintWindowExpired(const GenInfo &g,datetime eventTime)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   if(!DebugEventShouldPrint("WINDOW_EXPIRED",genKey,-1,eventTime))
      return;

   datetime endAt=0;
   bool hasEnd=ResolveGenerationLastAuthorizedEndForGeneration(g,endAt);
   CCTJournalLine(StringFormat("[CCT DBG] WINDOW_EXPIRED | gen=%s | eventNY=%s | activeIdx=%d | hasCarry=%s | hasEnd=%s endNY=%s",
                               genKey,
                               TimeToString(ToNY(eventTime),TIME_DATE|TIME_MINUTES),
                               g.activeSibIdx,
                               DebugBoolText(GenerationHasAuthorizedC1Carry(g)),
                               DebugBoolText(hasEnd),
                               endAt>0 ? TimeToString(ToNY(endAt),TIME_DATE|TIME_MINUTES) : "-"));
  }

/*
Purpose: Preserve generation carry authority after an already-authorized active sibling dies before trigger.
Constitution: A CO-violated shallow sibling must not erase the deeper siblings' chance to activate inside the same execution ownership context.
Inputs: g - generation record.
Outputs: True when any sibling previously achieved an authorized C1.
*/
bool GenerationHasAuthorizedC1Carry(const GenInfo &g)
  {
   for(int i=0;i<g.nSibs;i++)
     {
      if(g.sibs[i].hadAuthorizedC1 && g.sibs[i].c1Time>0)
         return true;
     }
   return false;
  }

/*
Purpose: Return whether an older same-bias generation has earned the right to become the visible/live owner again.
Constitution: A newer same-bias birth demotes untouched older generations; older generations only re-emerge after real dormant activation or execution history.
Inputs: g - generation record.
Outputs: True when the generation has current live authority rather than passive untouched validity.
*/
bool GenerationHasLiveCarryAuthority(const GenInfo &g)
  {
   if(g.triggerTime>0)
      return true;

   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs && g.sibs[g.activeSibIdx].state==SS_ACTIVE)
      return true;

   return GenerationHasAuthorizedC1Carry(g);
  }

/*
Purpose: Reassign dormancy after scan outcomes without resurrecting expired older generations.
Constitution: Same-bias generation ownership is newest-first after the newer birth is structurally confirmed; an older generation whose authorized window is already exhausted must remain dormant so the dormant scanner can either activate it from a valid historical C1 or kill it chronologically as window-expired.
Inputs: gens - generation array newest-first, nGens - generation count, scanTime - latest closed LTF bar used by the current scanner replay.
Outputs: gens[].dormant updated in place; sibling truth states are not changed here.
*/
void ReconcileGenerationDormancy(GenInfo &gens[],int nGens,datetime scanTime)
  {
   int leadLiveIdx=-1;

   for(int i=0;i<nGens;i++)
     {
      if(gens[i].triggerTime>0)
        {
         leadLiveIdx=i;
         break;
        }

      if(AllSiblingsDead(gens[i]))
         continue;

      if(scanTime>0 && IsGenerationWindowExpired(gens[i],scanTime))
         continue;

      if(i>0 && !GenerationHasLiveCarryAuthority(gens[i]))
         continue;

      leadLiveIdx=i;
      break;
     }

   for(int i=0;i<nGens;i++)
     {
      if(gens[i].triggerTime>0)
        {
         gens[i].dormant=false;
         continue;
        }

      if(AllSiblingsDead(gens[i]))
        {
         gens[i].dormant=false;
         continue;
        }

      if(scanTime>0 && IsGenerationWindowExpired(gens[i],scanTime))
        {
         gens[i].dormant=true;
         continue;
        }

      if(i>0 && !GenerationHasLiveCarryAuthority(gens[i]))
        {
         gens[i].dormant=true;
         continue;
        }

      gens[i].dormant=(i!=leadLiveIdx);
     }
  }

/*
Purpose: Find the next deeper inactive sibling after a failed active sibling.
Constitution: Ch. 11 and Pass 2 CO-violation recovery rules.
Inputs: g - generation record.
Outputs: Index of the next deeper inactive sibling, or -1 if none exists.
*/
int NextDeeperInactiveSibling(const GenInfo &g)
  {
   if(g.activeSibIdx<0)
      return -1;

   for(int i=g.activeSibIdx+1;i<g.nSibs;i++)
     {
      if(g.sibs[i].state==SS_INACTIVE)
         return i;
     }
   return -1;
  }

/*
Purpose: Find the next deeper inactive sibling starting from an explicit index.
Constitution: Ch. 11.5 and Ch. 36.6 CO-violation recovery promotes the next deeper inactive sibling.
Inputs: g - generation record, fromIdx - prior active sibling index.
Outputs: Index of the next deeper inactive sibling, or -1 if none exists.
*/
int NextDeeperInactiveSiblingFrom(const GenInfo &g,int fromIdx)
  {
   if(fromIdx<0)
      return -1;

   for(int i=fromIdx+1;i<g.nSibs;i++)
     {
      if(g.sibs[i].state==SS_INACTIVE)
         return i;
     }
   return -1;
  }

/*
Purpose: Kill all remaining live siblings once one sibling consumes the generation by trigger.
Constitution: Ch. 17.1 one execution per generation and latest user clarification that no sibling may activate after the generation has triggered.
Inputs: g - generation record, triggeredIdx - sibling that triggered, triggerTime - trigger close time.
Outputs: g updated in place.
*/
void ConsumeInactiveSiblingsOnTrigger(GenInfo &g,int triggeredIdx,datetime triggerTime)
  {
   for(int s=0;s<g.nSibs;s++)
     {
      if(s==triggeredIdx)
         continue;
      if(!IsAliveSiblingState(g.sibs[s].state))
         continue;
      g.sibs[s].state=SS_DEAD_WINDOW_CONSUMED;
      if(g.sibs[s].c1Time<=0)
         g.sibs[s].c1Time=triggerTime;
     }
  }

/*
Purpose: Apply the generation-consumption effects of a confirmed trigger.
Constitution: Ch. 8 carry-over completion, Ch. 15 CO same-close trigger override, and Ch. 17.1 one execution per generation.
Inputs: g - generation record, triggerIdx - triggering sibling index, triggerTime - trigger close time.
Outputs: g updated in place with TRIGGERED state and consumed deeper siblings.
*/
void MarkSiblingTriggered(GenInfo &g,int triggerIdx,datetime triggerTime)
  {
   if(triggerIdx<0 || triggerIdx>=g.nSibs || triggerTime<=0)
      return;

   // CCT_MARK_TRIGGER_REJECTS_COUNTER_BIAS_V1
   // A broker-valid trigger may only be recorded if the generation is still
   // directionally valid at the actual trigger/C3 time. A trigger discovered
   // on or after a counter-bias HTF flip is a dead bias-flip path, not authority.
   if(GenerationBiasIsOppositeAt(g,triggerTime))
     {
      if(DebugEventShouldPrint("TRIGGER_REJECTED_BIAS_FLIP",GenKey(g.bull,g.birthTime),triggerIdx,triggerTime))
         CCTJournalLine(StringFormat("[CCT DBG] TRIGGER_REJECTED_BIAS_FLIP | gen=%s | S%d | trigger=%s",
                                     GenKey(g.bull,g.birthTime),
                                     triggerIdx+1,
                                     TimeToString(triggerTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));

      if(g.sibs[triggerIdx].state==SS_ACTIVE)
         KillActiveSiblingOnBiasFlip(g,triggerTime);
      else
        {
         g.sibs[triggerIdx].state=SS_DEAD_BIAS_FLIP;
         if(g.sibs[triggerIdx].c1Time<=0)
            g.sibs[triggerIdx].c1Time=triggerTime;
         g.sibs[triggerIdx].c2Time=0;
         g.sibs[triggerIdx].c3Time=0;
         ClearSiblingAuthority(g.sibs[triggerIdx]);
         g.activeSibIdx=-1;
         g.dormant=false;
        }

      g.triggerTime=0;
      return;
     }

   if(g.sibs[triggerIdx].c2Time<=0)
      g.sibs[triggerIdx].c2Time=triggerTime;

   if(g.sibs[triggerIdx].c3Time<=0)
      g.sibs[triggerIdx].c3Time=triggerTime;
   g.sibs[triggerIdx].state=SS_TRIGGERED;
   g.triggerTime=triggerTime;
   g.activeSibIdx=triggerIdx;
   g.dormant=false;
   ConsumeInactiveSiblingsOnTrigger(g,triggerIdx,triggerTime);
  }

/*
Purpose: Terminally consume a trigger pattern that is discovered only by a later full replay, preventing stale chart/broker resurrection.
Constitution: A trigger may execute only at its true closed-bar edge; if that edge was missed, the generation is spent but not executable.
Inputs: g - generation record, triggerIdx - structurally completed sibling, triggerTime - historical trigger close, scanEnd - current replay edge.
Outputs: Generation marked consumed without broker-trigger state.
*/
void SuppressStaleReplayTrigger(GenInfo &g,int triggerIdx,datetime triggerTime,datetime scanEnd)
  {
   if(triggerIdx<0 || triggerIdx>=g.nSibs)
      return;

   if(triggerTime<=0)
      return;

   // CCT_STALE_REPLAY_REJECTS_COUNTER_BIAS_V1
   // Stale replay suppression may spend a missed trigger only if that missed
   // trigger was still directionally valid at its actual completion time.
   // Otherwise it fabricates SS_DEAD_WINDOW_CONSUMED and poisons newer bias generations.
   if(GenerationBiasIsOppositeAt(g,triggerTime))
     {
      if(DebugEventShouldPrint("STALE_REPLAY_TRIGGER_REJECTED_BIAS_FLIP",GenKey(g.bull,g.birthTime),triggerIdx,triggerTime))
         CCTJournalLine(StringFormat("[CCT DBG] STALE_REPLAY_TRIGGER_REJECTED_BIAS_FLIP | gen=%s | S%d | trigger=%s | scanEnd=%s",
                                     GenKey(g.bull,g.birthTime),
                                     triggerIdx+1,
                                     TimeToString(triggerTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));

      if(g.sibs[triggerIdx].state==SS_ACTIVE)
         KillActiveSiblingOnBiasFlip(g,triggerTime);
      else
        {
         g.sibs[triggerIdx].state=SS_DEAD_BIAS_FLIP;
         if(g.sibs[triggerIdx].c1Time<=0)
            g.sibs[triggerIdx].c1Time=triggerTime;
         g.sibs[triggerIdx].c2Time=0;
         g.sibs[triggerIdx].c3Time=0;
         ClearSiblingAuthority(g.sibs[triggerIdx]);
         g.activeSibIdx=-1;
         g.dormant=false;
        }

      g.triggerTime=0;
      return;
     }

   if(g.sibs[triggerIdx].c2Time<=0)
      g.sibs[triggerIdx].c2Time=triggerTime;
   if(g.sibs[triggerIdx].c3Time<=0)
      g.sibs[triggerIdx].c3Time=triggerTime;

   g.sibs[triggerIdx].state=SS_DEAD_WINDOW_CONSUMED;
   g.triggerTime=0;
   g.activeSibIdx=-1;
   g.dormant=false;
   ConsumeInactiveSiblingsOnTrigger(g,triggerIdx,triggerTime);

   if(DebugEventShouldPrint("STALE_REPLAY_TRIGGER_SUPPRESSED",GenKey(g.bull,g.birthTime),triggerIdx,triggerTime))
      CCTJournalLine(StringFormat("[CCT DBG] STALE_REPLAY_TRIGGER_SUPPRESSED | gen=%s | S%d | trigger=%s | scanEnd=%s",
                                  GenKey(g.bull,g.birthTime),
                                  triggerIdx+1,
                                  TimeToString(ToNY(triggerTime),TIME_DATE|TIME_MINUTES),
                                  TimeToString(ToNY(scanEnd),TIME_DATE|TIME_MINUTES)));
  }

/*
Purpose: Resolve the floor for FVG eligibility without letting CO timing erase valid trigger evidence.
Constitution: C3/IFVG belongs to the generation's post-birth trigger structure; the inversion must still occur after C1, but the FVG can form before the C1/CO bar.
Inputs: g - generation record.
Outputs: Earliest eligible FVG formation time.
*/
datetime GenerationFVGScanFloor(const GenInfo &g)
  {
   return g.birthTime;
  }

/*
Purpose: Drop FVG records that predate the generation birth or no longer qualify for the active generation.
Constitution: CO is execution geometry, not an IFVG memory floor; invalidation is controlled by post-C1 inversion checks.
Inputs: g - generation record.
Outputs: g.fvgs compacted in place; c3 winner reset/remapped as needed.
*/
void PruneIneligibleFVGs(GenInfo &g)
  {
   if(g.coTime<=0 || g.nFvgs<=0)
      return;

   datetime scanFloor=GenerationFVGScanFloor(g);
   int oldWinner=g.c3FvgIdx;
   int newWinner=-1;
   int writeIdx=0;
   for(int f=0;f<g.nFvgs;f++)
     {
      if(g.fvgs[f].t1<scanFloor)
         continue;

      if(writeIdx!=f)
         g.fvgs[writeIdx]=g.fvgs[f];
      if(f==oldWinner)
         newWinner=writeIdx;
      writeIdx++;
     }

   g.nFvgs=writeIdx;
   g.c3FvgIdx=newWinner;
  }

/*
Purpose: Add newly formed trigger-side FVGs to a generation's scanner memory.
Constitution: IFVG eligibility is scanner truth, most-recent inversion wins, and visual labels must not outrun state.
Inputs: g - generation record, ltf - LTF rates oldest-first, nl - bar count, k - current LTF index.
Outputs: g.fvgs updated with a non-duplicate FVG when the current 3-candle cluster qualifies.
*/
void TrackGenerationFVGFormation(GenInfo &g,MqlRates &ltf[],int nl,int k)
  {
   PruneIneligibleFVGs(g);
   if(k<2 || k>=nl || g.nFvgs>=CCT_MAX_FVGS)
      return;
   if(ltf[k-2].time<g.birthTime)
      return;

   bool found=false;
   FVGInfo fi;
   fi.t1=ltf[k-2].time;
   fi.t2=ltf[k-1].time;
   fi.t3=ltf[k].time;
   fi.c1Ext=0.0;
   fi.c3Ext=0.0;
   fi.c2c3Extreme=0.0;
   fi.c2c3ExtremeTime=0;
   fi.clusterExtreme=0.0;
   fi.inverted=false;
   fi.invTime=0;
   fi.invalidInv=false;
   fi.stale=false;
   fi.superseded=false;

   if(g.bull && ltf[k].high<ltf[k-2].low)
     {
      fi.c1Ext=ltf[k-2].low;
      fi.c3Ext=ltf[k].high;
      if(ltf[k-1].low<=ltf[k].low)
        {
         fi.c2c3Extreme=ltf[k-1].low;
         fi.c2c3ExtremeTime=ltf[k-1].time;
        }
      else
        {
         fi.c2c3Extreme=ltf[k].low;
         fi.c2c3ExtremeTime=ltf[k].time;
        }
      fi.clusterExtreme=MathMax(ltf[k-2].high,MathMax(ltf[k-1].high,ltf[k].high));
      found=true;
     }
   else if(!g.bull && ltf[k].low>ltf[k-2].high)
     {
      fi.c1Ext=ltf[k-2].high;
      fi.c3Ext=ltf[k].low;
      if(ltf[k-1].high>=ltf[k].high)
        {
         fi.c2c3Extreme=ltf[k-1].high;
         fi.c2c3ExtremeTime=ltf[k-1].time;
        }
      else
        {
         fi.c2c3Extreme=ltf[k].high;
         fi.c2c3ExtremeTime=ltf[k].time;
        }
      fi.clusterExtreme=MathMin(ltf[k-2].low,MathMin(ltf[k-1].low,ltf[k].low));
      found=true;
     }

   if(!found)
      return;

   for(int f=0;f<g.nFvgs;f++)
     {
      if(g.fvgs[f].t1==fi.t1 && g.fvgs[f].t3==fi.t3)
         return;
     }

   g.fvgs[g.nFvgs]=fi;
   g.nFvgs++;
  }

/*
Purpose: Continuously classify the SL branch for the currently winning IFVG.
Constitution: V-Shape can upgrade to Deep Swing from FVG formation through trigger close; a current winner never downgrades.
Inputs: g - generation record, ltf - LTF rates oldest-first, nl - bar count, throughTime - closed-bar scan ceiling.
Outputs: g.slBranch updated for the active IFVG.
*/
void RefreshGenerationSLBranch(GenInfo &g,MqlRates &ltf[],int nl,datetime throughTime)
  {
   if(g.c3FvgIdx<0 || g.c3FvgIdx>=g.nFvgs || nl<=0 || throughTime<=0)
      return;

   double anchorB=g.fvgs[g.c3FvgIdx].c2c3Extreme;
   bool deep=false;
   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time<g.fvgs[g.c3FvgIdx].t1 || ltf[k].time>throughTime)
         continue;

      if(g.bull && ltf[k].low<anchorB)
        {
         deep=true;
         break;
        }
      if(!g.bull && ltf[k].high>anchorB)
        {
         deep=true;
         break;
        }
     }

   if(deep)
      g.slBranch=BRANCH_DEEP_SWING;
   else if(g.slBranch!=BRANCH_DEEP_SWING)
      g.slBranch=BRANCH_VSHAPE;
  }

/*
Purpose: Promote the most recent valid FVG inversion to scanner-side C3 for the active sibling.
Constitution: Trigger requires C2+C3, and the most recently inverted FVG is the active trigger FVG.
Inputs: g - generation record, sibIdx - active sibling, ltf - LTF rates oldest-first, nl - bar count, currentIdx - current closed LTF index.
Outputs: g.c3FvgIdx, sibling c3Time, FVG supersession, and SL branch updated from exact IFVG history.
*/
void UpdateGenerationC3State(GenInfo &g,int sibIdx,MqlRates &ltf[],int nl,int currentIdx)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs)
      return;
   if(currentIdx<0 || currentIdx>=nl)
      return;
   SIB_STATE trackState=g.sibs[sibIdx].state;
   bool canTrack=(trackState==SS_ACTIVE || trackState==SS_DORMANT || trackState==SS_DEAD_UNAUTHORIZED_C1);
   if(!canTrack || g.sibs[sibIdx].c1Time<=0)
      return;

   PruneIneligibleFVGs(g);
   const MqlRates bar=ltf[currentIdx];
   datetime scanFloor=GenerationFVGScanFloor(g);
   datetime activeC1=g.sibs[sibIdx].c1Time;
   int winner=-1;
   double winnerDist=0.0;
   for(int f=0;f<g.nFvgs;f++)
     {
      if(g.fvgs[f].t1<scanFloor)
        {
         g.fvgs[f].superseded=false;
         continue;
        }

      if(!g.fvgs[f].inverted && !g.fvgs[f].stale)
        {
         datetime staleAt=g.fvgs[f].t1+(datetime)CCTIFVGMaxAgeSeconds();
         for(int j=0;j<=currentIdx;j++)
           {
            if(ltf[j].time<=g.fvgs[f].t3 || ltf[j].time<scanFloor)
               continue;
            if(ltf[j].time>staleAt)
               break;

            bool inverted=g.bull ? (ltf[j].close>g.fvgs[f].c1Ext) : (ltf[j].close<g.fvgs[f].c1Ext);
            if(!inverted)
               continue;

            g.fvgs[f].inverted=true;
            g.fvgs[f].invTime=ltf[j].time;
            g.fvgs[f].invalidInv=(ltf[j].time<=activeC1);
            g.fvgs[f].superseded=g.fvgs[f].invalidInv;
            break;
           }

         if(!g.fvgs[f].inverted && bar.time>staleAt)
            g.fvgs[f].stale=true;
        }

      if(g.fvgs[f].inverted && g.fvgs[f].invTime<=activeC1)
         g.fvgs[f].invalidInv=true;

      if(!g.fvgs[f].inverted || g.fvgs[f].stale || g.fvgs[f].invalidInv)
         continue;
      if(g.fvgs[f].invTime<scanFloor)
         continue;
      if(g.fvgs[f].invTime<=activeC1)
         continue;

      double dist=MathAbs(g.fvgs[f].c1Ext-bar.close);
      if(winner<0
         || g.fvgs[f].invTime>g.fvgs[winner].invTime
         || (g.fvgs[f].invTime==g.fvgs[winner].invTime && dist<winnerDist))
        {
         winner=f;
         winnerDist=dist;
        }
     }

   if(winner<0)
     {
      g.c3FvgIdx=-1;
      g.sibs[sibIdx].c3Time=0;
      return;
     }

   for(int f=0;f<g.nFvgs;f++)
      g.fvgs[f].superseded=(f!=winner && g.fvgs[f].inverted && !g.fvgs[f].stale && !g.fvgs[f].invalidInv && g.fvgs[f].t1>=scanFloor);

   if(g.c3FvgIdx!=winner)
      g.slBranch=BRANCH_VSHAPE;
   g.c3FvgIdx=winner;
   g.sibs[sibIdx].c3Time=g.fvgs[winner].invTime;
   RefreshGenerationSLBranch(g,ltf,nl,bar.time);
  }

/*
Purpose: Clear confirmation state that belongs to a superseded active sibling before a deeper sibling takes over.
Constitution: Each sibling owns its own C2+C3 sequence; deeper supersession cannot inherit the shallower sibling's trigger state.
Inputs: g - generation record, sibIdx - newly active sibling index.
Outputs: New active sibling confirmation state reset.
*/
void ResetActiveSiblingConfirmation(GenInfo &g,int sibIdx)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs)
      return;

   g.sibs[sibIdx].c2Time=0;
   g.sibs[sibIdx].c3Time=0;
   g.c3FvgIdx=-1;
   g.slBranch=BRANCH_VSHAPE;
   g.anchorA=0.0;
   g.anchorATime=0;
   g.anchorB=0.0;
   g.anchorBTime=0;
   g.visualEntry=0.0;
   g.visualEntryTime=0;
   g.triggerSpread=0.0;
   g.fibRawSL=0.0;
   g.rawSL=0.0;
   g.rawTP=0.0;
   g.beApplied=false;
   g.beGeneralApplied=false;
   g.beCoApplied=false;
   g.bePrice=0.0;
   g.beTriggerTime=0;
   g.beLeftAnchorTime=0;
   for(int f=0;f<g.nFvgs;f++)
      g.fvgs[f].superseded=false;
  }

/*
Purpose: Promote the deepest inactive sibling reached by the current C1 close after the active sibling has failed its trigger check.
Constitution: Ch. 11.3-11.4 deeper sibling supersession, with active-sibling C2+C3 trigger priority over later deeper activation.
Inputs: g - generation record, ltf - LTF rates oldest-first, nl - bar count, k - current LTF index.
Outputs: True when authority moved to a deeper sibling and shallower untriggered siblings were killed.
*/
bool PromoteDeepestCrossedInactiveSibling(GenInfo &g,MqlRates &ltf[],int nl,int k)
  {
   if(k<0 || k>=nl || g.triggerTime>0)
      return false;
   if(g.activeSibIdx<0 || g.activeSibIdx>=g.nSibs)
      return false;
   if(g.sibs[g.activeSibIdx].state!=SS_ACTIVE)
      return false;

   int priorActive=g.activeSibIdx;
   int deepestCrossed=-1;
   double prevCls=C1PrevClose(ltf,k);
   double cls=ltf[k].close;

   for(int s=priorActive+1;s<g.nSibs;s++)
     {
      if(g.sibs[s].state!=SS_INACTIVE)
         continue;
      if(IsC1EdgeCross(g.bull,prevCls,cls,g.sibs[s].level))
         deepestCrossed=s;
     }

   if(deepestCrossed<0)
      return false;

   for(int s=0;s<deepestCrossed;s++)
     {
      if(!IsAliveSiblingState(g.sibs[s].state))
         continue;

      g.sibs[s].state=SS_DEAD_SUPERSESSION;
      if(g.sibs[s].c1Time<=0)
         g.sibs[s].c1Time=ltf[k].time;
      g.sibs[s].c2Time=0;
      g.sibs[s].c3Time=0;
     }

   g.sibs[deepestCrossed].state=SS_ACTIVE;
   g.sibs[deepestCrossed].c1Time=ltf[k].time;
   InheritSiblingAuthority(g,priorActive,deepestCrossed,ltf[k].time);
   g.activeSibIdx=deepestCrossed;

   for(int s=deepestCrossed+1;s<g.nSibs;s++)
     {
      if(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT)
         g.sibs[s].state=SS_INACTIVE;
     }

   ResetActiveSiblingConfirmation(g,g.activeSibIdx);
   LockCorrectionOriginIfNeeded(g,ltf,nl,ltf[k].time,true);
   UpdateGenerationC3State(g,g.activeSibIdx,ltf,nl,k);
   DebugPrintC1CO(ltf[k].time,g);
   return true;
  }

/*
Purpose: Monitor counter-bias dormant siblings for the invalidating C1 + C2+C3 sequence.
Constitution: Latest user clarification that counter-bias dormant siblings are hidden/non-executable, but if one completes C1 then C2+C3 while bias remains opposite, the whole sibling set dies.
Inputs: g - generation record, ltf - LTF rates oldest-first, nl - bar count, k - current LTF index.
Outputs: True when the generation was killed by counter-bias dormant invalidation.
*/
bool ScanCounterBiasDormantSiblings(GenInfo &g,MqlRates &ltf[],int nl,int k)
  {
   if(k<0 || k>=nl)
      return false;

   double cls=ltf[k].close;
   for(int s=0;s<g.nSibs;s++)
     {
      if(g.sibs[s].state!=SS_DORMANT)
         continue;

      if(g.sibs[s].c1Time<=0)
        {
          if(!IsC1EdgeCross(g.bull,C1PrevClose(ltf,k),cls,g.sibs[s].level))
             continue;
          g.sibs[s].c1Time=ltf[k].time;
          ClearSiblingAuthority(g.sibs[s]);
         }

      UpdateGenerationC3State(g,s,ltf,nl,k);

      bool reclaim=(g.bull && cls>=g.sibs[s].level) || (!g.bull && cls<=g.sibs[s].level);
      if(reclaim && g.sibs[s].c2Time==0)
         g.sibs[s].c2Time=ltf[k].time;

      bool lapse=(g.bull && cls<g.sibs[s].level) || (!g.bull && cls>g.sibs[s].level);
      if(lapse && g.sibs[s].c2Time>0)
         g.sibs[s].c2Time=0;

      if(g.sibs[s].c2Time>0 && g.sibs[s].c3Time>0)
        {
         KillGenerationLiveSiblings(g,SS_DEAD_BIAS_FLIP,ltf[k].time);
         return true;
        }
     }

   return false;
  }

/*
Purpose: Confirm that C2+C3 was actually completed by the current closed LTF bar.
Constitution: Trigger must use the winning IFVG, not the old CO/HTF bridge fallback; Path A is old IFVG then C2, Path B is old C2 then same-bar IFVG.
Inputs: g - generation record, sibIdx - active sibling index, bar - current closed LTF bar, priorC2Time - sibling C2 time before this bar was processed.
Outputs: True when the bar is the trigger close for the active sibling.
*/
bool TriggerBridgeConfirmed(const GenInfo &g,int sibIdx,const MqlRates &bar,datetime priorC2Time)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs)
      return false;

   SIB_STATE st=g.sibs[sibIdx].state;
   // CCT_UNSELECTED_HOUR_C1_CANNOT_TRIGGER_V1
   // Unauthorized C1 paths may consume a generation, but they must never be
   // promoted back into an executable C2+C3 bridge.
   bool triggerTrackState=(st==SS_ACTIVE && g.sibs[sibIdx].hadAuthorizedC1);
   if(!triggerTrackState || g.sibs[sibIdx].c2Time<=0)
      return false;

   if(g.sibs[sibIdx].c3Time<=0 || g.c3FvgIdx<0 || g.c3FvgIdx>=g.nFvgs)
      return false;
   if(!g.fvgs[g.c3FvgIdx].inverted || g.fvgs[g.c3FvgIdx].stale || g.fvgs[g.c3FvgIdx].invalidInv)
      return false;
   if(g.fvgs[g.c3FvgIdx].invTime<=g.sibs[sibIdx].c1Time)
      return false;

   bool biasSideClose=g.bull ? (bar.close>=g.sibs[sibIdx].level) : (bar.close<=g.sibs[sibIdx].level);
   if(!biasSideClose)
      return false;

   bool c2Now=(g.sibs[sibIdx].c2Time==bar.time);
   bool c3Now=(g.fvgs[g.c3FvgIdx].invTime==bar.time);
   bool pathA=(c2Now && g.fvgs[g.c3FvgIdx].invTime>0 && g.fvgs[g.c3FvgIdx].invTime<bar.time);
   bool pathB=(priorC2Time>0 && priorC2Time<=bar.time &&
               g.fvgs[g.c3FvgIdx].invTime==bar.time);
   bool sameBar=(c2Now && c3Now);
   return (pathA || pathB || sameBar);
  }

/*
Purpose: Prevent historical replays from inventing fresh executable triggers after their true closed-bar edge has passed.
Constitution: Live, visual tester, and non-visual tester share one closed-bar truth path; a broker/synthetic trigger is born only on the bar that completes C2+C3.
Inputs: triggerTime - structural trigger close, scanEnd - latest closed LTF bar in this scanner pass.
Outputs: True only when the trigger belongs to the current scanner edge.
*/
bool TriggerIsCurrentReplayEdge(datetime triggerTime,datetime scanEnd)
  {
   if(triggerTime<=0 || scanEnd<=0)
      return false;
   return (triggerTime==scanEnd);
  }

/*
Purpose: Detect a completed authorized C1+C2+C3 sequence even when replay state was reconstructed after the exact trigger close.
Constitution: C2+C3 coexistence consumes the active sibling before any deeper sibling may supersede it.
Inputs: g - generation, sibIdx - active sibling, currentTime - current replay bar time, completedAt - resolved structural trigger close.
Outputs: True when the active sibling has already structurally triggered by currentTime.
*/
bool AuthorizedStructuralTriggerCompleted(const GenInfo &g,int sibIdx,datetime currentTime,datetime &completedAt)
  {
   completedAt=0;
   if(sibIdx<0 || sibIdx>=g.nSibs || currentTime<=0)
      return false;
   if(g.sibs[sibIdx].state!=SS_ACTIVE)
      return false;
   if(g.sibs[sibIdx].c1Time<=0 || !g.sibs[sibIdx].hadAuthorizedC1)
      return false;
   if(g.sibs[sibIdx].c2Time<=0 || g.sibs[sibIdx].c3Time<=0)
      return false;
   if(g.sibs[sibIdx].c2Time<=g.sibs[sibIdx].c1Time ||
      g.sibs[sibIdx].c3Time<=g.sibs[sibIdx].c1Time)
      return false;
   if(g.c3FvgIdx<0 || g.c3FvgIdx>=g.nFvgs)
      return false;
   if(!g.fvgs[g.c3FvgIdx].inverted || g.fvgs[g.c3FvgIdx].stale || g.fvgs[g.c3FvgIdx].invalidInv)
      return false;
   if(g.fvgs[g.c3FvgIdx].invTime!=g.sibs[sibIdx].c3Time)
      return false;

   completedAt=(g.sibs[sibIdx].c2Time>g.sibs[sibIdx].c3Time) ? g.sibs[sibIdx].c2Time : g.sibs[sibIdx].c3Time;
   return (completedAt>0 && completedAt<=currentTime);
  }

/*
Purpose: Check whether a counter-bias birth has occurred after a generation was born.
Constitution: Ch. 18 and Pass 2 bias-flip kill rule.
Inputs: g - generation record, nowTime - scan time.
Outputs: True if an opposite-direction birth exists after g.birthTime and before nowTime.
*/
bool CounterBiasBirthExists(const GenInfo &g,datetime nowTime)
  {
   if(g.bull)
     {
      for(int i=0;i<g_nBear;i++)
        {
         int idx=g_bearBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;
         datetime birthTime=g_htf[idx].time;
         datetime effective=BirthEffectiveTime(birthTime);
         if(birthTime>g.birthTime && effective<=nowTime)
            return true;
        }
     }
   else
     {
      for(int i=0;i<g_nBull;i++)
        {
         int idx=g_bullBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;
         datetime birthTime=g_htf[idx].time;
         datetime effective=BirthEffectiveTime(birthTime);
         if(birthTime>g.birthTime && effective<=nowTime)
            return true;
        }
     }
   return false;
  }

/*
Purpose: Determine whether the latest known HTF bias at a scan timestamp is against the generation.
Constitution: Latest user clarification that a counter-bias flip invalidates the active POI/TS, but deeper siblings may become relevant again if bias later returns in favor.
Inputs: g - generation record, nowTime - scan time.
Outputs: True only while the most recent post-birth HTF bias birth is counter to the generation.
*/
bool GenerationBiasIsOppositeAt(const GenInfo &g,datetime nowTime)
  {
   datetime latestSameClose=HTFBarCloseForOpen(g.birthTime);
   if(latestSameClose<=0 || latestSameClose>nowTime)
      latestSameClose=g.birthTime;

   datetime latestCounterClose=0;

   if(g.bull)
     {
      for(int i=0;i<g_nBull;i++)
        {
         int idx=g_bullBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;

         datetime birthTime=g_htf[idx].time;
         if(birthTime<=g.birthTime)
            continue;

         datetime closeTime=HTFBarCloseForOpen(birthTime);
         if(closeTime<=0 || closeTime>nowTime)
            continue;

         if(closeTime>latestSameClose)
            latestSameClose=closeTime;
        }

      for(int i=0;i<g_nBear;i++)
        {
         int idx=g_bearBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;

         datetime birthTime=g_htf[idx].time;
         if(birthTime<=g.birthTime)
            continue;

         datetime closeTime=HTFBarCloseForOpen(birthTime);
         if(closeTime<=0 || closeTime>nowTime)
            continue;

         if(closeTime>latestCounterClose)
            latestCounterClose=closeTime;
        }
     }
   else
     {
      for(int i=0;i<g_nBear;i++)
        {
         int idx=g_bearBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;

         datetime birthTime=g_htf[idx].time;
         if(birthTime<=g.birthTime)
            continue;

         datetime closeTime=HTFBarCloseForOpen(birthTime);
         if(closeTime<=0 || closeTime>nowTime)
            continue;

         if(closeTime>latestSameClose)
            latestSameClose=closeTime;
        }

      for(int i=0;i<g_nBull;i++)
        {
         int idx=g_bullBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;

         datetime birthTime=g_htf[idx].time;
         if(birthTime<=g.birthTime)
            continue;

         datetime closeTime=HTFBarCloseForOpen(birthTime);
         if(closeTime<=0 || closeTime>nowTime)
            continue;

         if(closeTime>latestCounterClose)
            latestCounterClose=closeTime;
        }
     }

   return (latestCounterClose>0 && latestCounterClose>latestSameClose);
  }

/*
Purpose: Resolve the TS scan reset point from reconstructed bias history.
Constitution: Untriggered TS hints die on counter-bias flip; if bias later returns, only fresh post-reset sweeps can classify a deeper sibling.
Inputs: g - generation record, scanEnd - scan ceiling, outFromTime - reset floor for TS scanning.
Outputs: False when untriggered TS must be empty because latest bias is counter to the generation.
*/
bool ResolveGenerationTSFromTime(const GenInfo &g,datetime scanEnd,datetime &outFromTime)
  {
   outFromTime=ActionPillarTime(g.birthTime);
   if(g.tsEligibleFrom>outFromTime)
      outFromTime=g.tsEligibleFrom;

   datetime latestSame=BirthEffectiveTime(g.birthTime);
   datetime latestCounter=0;

   if(g.bull)
     {
      for(int i=0;i<g_nBull;i++)
        {
         int idx=g_bullBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;
          datetime birthTime=g_htf[idx].time;
          datetime effective=BirthEffectiveTime(birthTime);
          if(birthTime>g.birthTime && effective<=scanEnd && effective>latestSame)
             latestSame=effective;
        }
      for(int i=0;i<g_nBear;i++)
        {
         int idx=g_bearBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;
          datetime birthTime=g_htf[idx].time;
          datetime effective=BirthEffectiveTime(birthTime);
          if(birthTime>g.birthTime && effective<=scanEnd && effective>latestCounter)
             latestCounter=effective;
        }
     }
   else
     {
      for(int i=0;i<g_nBear;i++)
        {
         int idx=g_bearBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;
          datetime birthTime=g_htf[idx].time;
          datetime effective=BirthEffectiveTime(birthTime);
          if(birthTime>g.birthTime && effective<=scanEnd && effective>latestSame)
             latestSame=effective;
        }
      for(int i=0;i<g_nBull;i++)
        {
         int idx=g_bullBirths[i];
         if(idx<0 || idx>=g_nHtf)
            continue;
          datetime birthTime=g_htf[idx].time;
          datetime effective=BirthEffectiveTime(birthTime);
          if(birthTime>g.birthTime && effective<=scanEnd && effective>latestCounter)
             latestCounter=effective;
        }
     }

   if(g.triggerTime<=0 && latestCounter>latestSame)
      return false;

   if(latestCounter>0 && latestSame>latestCounter && latestCounter>outFromTime)
      outFromTime=latestCounter;

   return true;
  }

/*
Purpose: Resolve the HTF bar index that owns a server timestamp.
Constitution: Pass 2 structural state needs historical virginity checks at exact event times.
Inputs: B - HTF bars newest-first, n - bar count, srvTime - server timestamp.
Outputs: HTF bar index containing srvTime, or -1 when none can be resolved.
*/
int HtfIndexForServerTime(MqlRates &B[],int n,datetime srvTime)
  {
   if(srvTime<=0 || n<1)
      return -1;

   int htfSec=CCTModelHTFSeconds();
   for(int i=0;i<n;i++)
     {
      datetime open=B[i].time;
      if(open<=0)
         continue;
      datetime close=open+(datetime)htfSec;
      if(srvTime>=open && srvTime<close)
         return i;
     }
   return -1;
  }

/*
Purpose: Check whether a wick was still virgin at a specific server timestamp.
Constitution: TS and CO may only use wick structure that was still virgin when price first reached it.
Inputs: B - HTF bars newest-first, n - bar count, wickIdx - wick source index, bull - wick side, eventTime - first-touch server time.
Outputs: True when the wick was still virgin at eventTime.
*/
bool WasVirginAtTime(MqlRates &B[],int n,int wickIdx,bool bull,datetime eventTime)
  {
   int eventIdx=HtfIndexForServerTime(B,n,eventTime);
   if(eventIdx<0)
      return false;

   if(wickIdx<=eventIdx)
      return false;

   return WasVirginAtBirth(B,eventIdx,wickIdx,bull);
  }

/*
Purpose: Find the earliest LTF bar that touched a level inside a bounded scan range.
Constitution: TS and CO history lock to the first touch of the selected wick level.
Inputs: ltf - LTF bars oldest-first, nl - bar count, fromTime - inclusive scan start, toTime - inclusive scan end, level - price, touchLowSide - true when touch is low<=level, false when touch is high>=level.
Outputs: First touch time, or 0 if untouched.
*/
datetime FindFirstLevelTouch(MqlRates &ltf[],int nl,datetime fromTime,datetime toTime,double level,bool touchLowSide)
  {
   // CCT_FINDFIRSTLEVELTOUCH_BINARY_V1
   // ltf[] is oldest-first in this EA path. Jump to the first bar >= fromTime,
   // then stop as soon as time exceeds toTime. This preserves the same first-touch
   // result while avoiding repeated full-array scans from RefreshGenerationTSState().
   if(fromTime<=0 || toTime<fromTime || nl<=0)
      return 0;

   int actual=ArraySize(ltf);
   if(actual<=0)
      return 0;
   if(nl>actual)
      nl=actual;

   int lo=0;
   int hi=nl-1;
   int start=nl;

   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      if(ltf[mid].time>=fromTime)
        {
         start=mid;
         hi=mid-1;
        }
      else
         lo=mid+1;
     }

   for(int k=start;k<nl;k++)
     {
      if(ltf[k].time>toTime)
         break;

      bool hit=touchLowSide ? (ltf[k].low<=level) : (ltf[k].high>=level);
      if(hit)
         return ltf[k].time;
     }

   return 0;
  }

/*
Purpose: Find the next same-bias or counter-bias birth after a generation.
Constitution: Same-bias newer births freeze older CO; counter-bias births freeze it silently for future reuse.
Inputs: g - generation record, wantSameBias - true for same-bias search, outBirthTime - output birth time.
Outputs: True when a later birth of the requested side exists.
*/
bool FindBirthAfter(const GenInfo &g,bool wantSameBias,datetime &outBirthTime)
  {
   outBirthTime=0;

   if(wantSameBias)
     {
      if(g.bull)
        {
         for(int i=0;i<g_nBull;i++)
           {
            int idx=g_bullBirths[i];
            if(idx<0 || idx>=g_nHtf)
               continue;
            datetime birthTime=g_htf[idx].time;
            if(birthTime>g.birthTime && (outBirthTime==0 || birthTime<outBirthTime))
               outBirthTime=birthTime;
           }
        }
      else
        {
         for(int i=0;i<g_nBear;i++)
           {
            int idx=g_bearBirths[i];
            if(idx<0 || idx>=g_nHtf)
               continue;
            datetime birthTime=g_htf[idx].time;
            if(birthTime>g.birthTime && (outBirthTime==0 || birthTime<outBirthTime))
               outBirthTime=birthTime;
           }
        }
     }
   else
     {
      if(g.bull)
        {
         for(int i=0;i<g_nBear;i++)
           {
            int idx=g_bearBirths[i];
            if(idx<0 || idx>=g_nHtf)
               continue;
            datetime birthTime=g_htf[idx].time;
            if(birthTime>g.birthTime && (outBirthTime==0 || birthTime<outBirthTime))
               outBirthTime=birthTime;
           }
        }
      else
        {
         for(int i=0;i<g_nBull;i++)
           {
            int idx=g_bullBirths[i];
            if(idx<0 || idx>=g_nHtf)
               continue;
            datetime birthTime=g_htf[idx].time;
            if(birthTime>g.birthTime && (outBirthTime==0 || birthTime<outBirthTime))
               outBirthTime=birthTime;
           }
        }
     }

   return (outBirthTime>0);
  }

/*
Purpose: Resolve the generation's structural freeze cutoff before trigger.
Constitution: Same-bias newer birth freezes CO at the immediate newer birth close; counter-bias flip freezes it at the pre-flip extreme without discarding it.
Inputs: g - generation record, scanEnd - current scan ceiling.
Outputs: Freeze cutoff to use for TS/CO scanning.
*/
datetime ResolveGenerationFreezeCutoff(const GenInfo &g,datetime scanEnd)
  {
   datetime cutoff=(g.triggerTime>0 && g.triggerTime<scanEnd) ? g.triggerTime : scanEnd;
   int htfSec=CCTModelHTFSeconds();

   datetime nextSame=0;
   if(FindBirthAfter(g,true,nextSame))
     {
      datetime sameClose=nextSame + (datetime)htfSec - 1;
      if(sameClose<cutoff)
         cutoff=sameClose;
     }

   datetime nextCounter=0;
   if(FindBirthAfter(g,false,nextCounter))
     {
      datetime counterClose=nextCounter + (datetime)htfSec - 1;
      if(counterClose<cutoff)
         cutoff=counterClose;
     }

   return cutoff;
  }

/*
Purpose: Refresh TS sweep state for one generation from opposing virgin wick structure.
Constitution: TS sweep count follows the active C1 path; once C1 exists, later carried triggers keep earlier path sweeps visible/countable.
Inputs: g - generation record, B - HTF bars newest-first, n - bar count, ltf - LTF bars oldest-first, nl - bar count, scanEnd - current scan ceiling.
Outputs: g TS fields updated in place.
*/
ENUM_MODEL_TYPE ModelTypeForAuthorityRoute(ENUM_CCT_AUTH_ROUTE route,int sweeps,int postBirthSweeps)
  {
   if(route==AUTH_ROUTE_CCT_EXT)
      return (sweeps>=2 ? MODEL_CCT_TS_EXT : (sweeps==1 ? MODEL_CCT_TS : MODEL_CCT_EXT));
   if(route==AUTH_ROUTE_TS || route==AUTH_ROUTE_TS_EXT)
      return (sweeps>=2 ? MODEL_CCT_TS_EXT : (sweeps==1 ? MODEL_CCT_TS : MODEL_CCT));
   if(route==AUTH_ROUTE_CCT)
     {
      if(sweeps<=0)
         return MODEL_CCT;
      return (postBirthSweeps>0 ? (sweeps>=2 ? MODEL_CCT_TS_EXT : MODEL_CCT_TS) : MODEL_CCT_STRUCT_TS);
     }
   return (sweeps>=2 ? MODEL_CCT_TS_EXT : (sweeps==1 ? MODEL_CCT_TS : MODEL_CCT));
  }

// CCT_MODEL_LABEL_SWEEP_TRUTH_V1
// Final user-facing structural model labels must be consistent with trigger-time
// opposing-wick sweep count. Execution-hour family/route may authorize C1, but
// it must not leave CCT+TS/CCT+TS EXT labels on zero-sweep trades.
ENUM_MODEL_TYPE CCTModelTypeForSweepTruth(ENUM_MODEL_TYPE modelType,int sweeps,int postBirthSweeps)
  {
   if(sweeps<=0)
     {
      if(modelType==MODEL_CCT_EXT)
         return MODEL_CCT_EXT;
      return MODEL_CCT;
     }

   if(sweeps==1)
     {
      if(modelType==MODEL_CCT_STRUCT_TS && postBirthSweeps<=0)
         return MODEL_CCT_STRUCT_TS;
      return MODEL_CCT_TS;
     }

   return MODEL_CCT_TS_EXT;
  }

void CCTNormalizeGenModelBySweepTruth(GenInfo &g)
  {
   g.modelType=CCTModelTypeForSweepTruth(g.modelType,g.sweepCount,g.tsPostBirthSweepCount);
  }

bool ResolveAuthorizedModelFromRoute(ENUM_CCT_AUTH_ROUTE route,int sweeps,int postBirthSweeps,
                                     int nyHour,int offset,ENUM_MODEL_TYPE &modelType)
  {
   modelType=MODEL_CCT;

   if(route==AUTH_ROUTE_RECORD_ONLY || route==AUTH_ROUTE_NONE)
      return false;

   bool hourKnown=(nyHour>=0 && nyHour<=23);
   bool hasTs=(!Inp_SessionFilter || (hourKnown && CachedTSHour(nyHour)));
   bool hasExt=(!Inp_SessionFilter || (hourKnown && CachedExtHour(nyHour)));
   if(!hourKnown)
     {
      // Authority was already earned before reaching this function. If an older
      // record lacks the hour field, keep TS-family routes from downgrading to
      // plain labels during replay/persistence reconciliation.
      hasTs=(route==AUTH_ROUTE_TS || route==AUTH_ROUTE_TS_EXT || route==AUTH_ROUTE_CCT_EXT);
      hasExt=(route==AUTH_ROUTE_TS_EXT);
     }

   if(Inp_TimeframeModel!=CCT_TFM_1H_M1)
     {
      // For 4H/Daily, route authority was already resolved from model-specific
      // block/day/session CSVs at C1 time. Do not re-interpret the stored hour
      // through the 1H hour caches here.
      hasTs=(route==AUTH_ROUTE_TS || route==AUTH_ROUTE_TS_EXT || route==AUTH_ROUTE_CCT_EXT);
      hasExt=(route==AUTH_ROUTE_TS_EXT);
     }

   if(route==AUTH_ROUTE_CCT)
     {
      if(sweeps<=0)
        {
         modelType=MODEL_CCT;
         return true;
        }

      if(postBirthSweeps>0)
        {
         if(sweeps>=2 && hasExt)
           {
            modelType=MODEL_CCT_TS_EXT;
            return true;
           }

         if(hasTs || hasExt)
           {
            modelType=MODEL_CCT_TS;
            return true;
           }

         return false;
        }

      if(Inp_TSFilter && offset==1)
        {
         modelType=MODEL_CCT_STRUCT_TS;
         return true;
        }

      return false;
     }

   if(route==AUTH_ROUTE_CCT_EXT)
     {
      if(sweeps<=0)
        {
         modelType=MODEL_CCT_EXT;
         return true;
        }

      if(sweeps>=2 && hasExt)
        {
         modelType=MODEL_CCT_TS_EXT;
         return true;
        }

      if(hasTs)
        {
         modelType=MODEL_CCT_TS;
         return true;
        }

      return false;
     }

   if(route==AUTH_ROUTE_TS)
     {
      if(sweeps<1)
         return false;
      modelType=(sweeps>=2 && hasExt) ? MODEL_CCT_TS_EXT : MODEL_CCT_TS;
      return true;
     }

   if(route==AUTH_ROUTE_TS_EXT)
     {
      if(sweeps<2)
         return false;
      modelType=MODEL_CCT_TS_EXT;
      return true;
     }

   return false;
  }

int LastSiblingAuthorityIndex(const GenInfo &g)
  {
   int best=-1;
   for(int i=0;i<g.nSibs;i++)
     {
      if(g.sibs[i].authorityRoute==AUTH_ROUTE_NONE ||
         g.sibs[i].authorityRoute==AUTH_ROUTE_RECORD_ONLY ||
         g.sibs[i].authorityRecordOnly ||
         g.sibs[i].c1Time<=0)
         continue;
      if(best<0 || g.sibs[i].c1Time>g.sibs[best].c1Time)
         best=i;
     }
   return best;
  }

void RefreshGenerationTSState(GenInfo &g,MqlRates &B[],int n,MqlRates &ltf[],int nl,datetime scanEnd)
  {
   // CCT_TS_INNER_PROFILE_V1
   // Timing-only instrumentation. This function preserves the existing TS semantics.
   ulong cctTsStart=GetMicrosecondCount();
   ulong cctTsStep=0;
   ulong cctTsPriorUs=0;
   ulong cctTsFirstUs=0;
   ulong cctTsVirginUs=0;
   ulong cctTsAnchorUs=0;
   int cctTsLoopBars=0;
   int cctTsSkipFuture=0;
   int cctTsSkipTouchAfterCutoff=0;
   int cctTsPriorCalls=0;
   int cctTsPriorHits=0;
   int cctTsFirstCalls=0;
   int cctTsFirstHits=0;
   int cctTsVirginCalls=0;
   int cctTsVirginFails=0;
   int cctTsAnchorCalls=0;

   g.sweepCount=0;
   g.tsBirthOrOlderSweepCount=0;
   g.tsPostBirthSweepCount=0;
   g.tsDisplayLevel=0.0;
   g.tsDisplayWickTime=0;
   g.tsDisplayLtfAnchor=0;
   g.tsFirstTouchTime=0;
   g.tsConfirmed=(g.triggerTime>0);

   if(g.birthTime<=0 || scanEnd<=0)
      return;

   datetime fromTime=0;
   if(!ResolveGenerationTSFromTime(g,scanEnd,fromTime))
      return;
   // TS is execution-window structure, not generation CO memory.
   // A newer same-bias birth may freeze the older generation's CO, but if price
   // revalidates that older dormant generation during a TS/Ext hour, sweeps made
   // inside that execution bar still classify the eventual trigger.
   datetime cutoff=(g.triggerTime>0 && g.triggerTime<scanEnd) ? g.triggerTime : scanEnd;
   if(cutoff<fromTime)
      return;

   int tsAuthorityIdx=LastSiblingAuthorityIndex(g);
   bool hasRecordedC1=(tsAuthorityIdx>=0 && tsAuthorityIdx<g.nSibs);
   if(hasRecordedC1)
     {
      datetime c1ScopeOpen=HTFBarOpenForTime(g.sibs[tsAuthorityIdx].c1Time);
      datetime routeScope=(g.sibs[tsAuthorityIdx].tsScopeFrom>0) ? g.sibs[tsAuthorityIdx].tsScopeFrom : c1ScopeOpen;
      if(routeScope>fromTime)
         fromTime=routeScope;
      }
   else if(g.triggerTime<=0)
     {
      datetime scopeOpen=HTFBarOpenForTime(scanEnd);
      if(scopeOpen>fromTime)
         fromTime=scopeOpen;
     }
   if(cutoff<fromTime)
      return;

   bool wickBull=!g.bull;
   bool touchLowSide=g.bull;
   int htfSeconds=CCTModelHTFSeconds();
   if(htfSeconds<=0)
      htfSeconds=3600;

   for(int j=n-1;j>=1;j--)
     {
      cctTsLoopBars++;

      if(B[j].time>cutoff)
        {
         cctTsSkipFuture++;
         continue;
        }

      double level=wickBull ? B[j].high : B[j].low;
      datetime wickReadyTime=B[j].time+htfSeconds;
      datetime touchStart=(fromTime>wickReadyTime ? fromTime : wickReadyTime);
      if(touchStart>cutoff)
        {
         cctTsSkipTouchAfterCutoff++;
         continue;
        }

            // CCT_TS_CURRENT_TOUCH_FIRST_V2
      // Semantics-preserving reorder:
      // a wick cannot count as TS unless it is touched inside the active TS window.
      // Therefore test current-window touch first, and only run the expensive
      // historical prior-touch check for wicks that actually touched now.
      cctTsFirstCalls++;
      cctTsStep=GetMicrosecondCount();
      datetime firstTouch=FindFirstLevelTouch(ltf,nl,touchStart,cutoff,level,touchLowSide);
      cctTsFirstUs+=GetMicrosecondCount()-cctTsStep;
      if(firstTouch<=0)
         continue;
      cctTsFirstHits++;

      if(fromTime>wickReadyTime)
        {
         cctTsPriorCalls++;
         cctTsStep=GetMicrosecondCount();
         datetime priorTouch=FindFirstLevelTouch(ltf,nl,wickReadyTime,(datetime)(fromTime-1),level,touchLowSide);
         cctTsPriorUs+=GetMicrosecondCount()-cctTsStep;
         if(priorTouch>0)
           {
            cctTsPriorHits++;
            continue;
           }
        }

      cctTsVirginCalls++;
      cctTsStep=GetMicrosecondCount();
      bool virginOk=WasVirginAtTime(B,n,j,wickBull,firstTouch);
      cctTsVirginUs+=GetMicrosecondCount()-cctTsStep;
      if(!virginOk)
        {
         cctTsVirginFails++;
         continue;
        }

      g.sweepCount++;
      if(B[j].time>g.birthTime)
         g.tsPostBirthSweepCount++;
      else
         g.tsBirthOrOlderSweepCount++;
      bool betterDisplay=false;
      if(g.tsFirstTouchTime<=0 || firstTouch>g.tsFirstTouchTime)
         betterDisplay=true;
      else if(firstTouch==g.tsFirstTouchTime)
        {
         if(g.bull && (g.tsDisplayLevel<=0.0 || level<g.tsDisplayLevel))
            betterDisplay=true;
         if(!g.bull && (g.tsDisplayLevel<=0.0 || level>g.tsDisplayLevel))
            betterDisplay=true;
        }

      if(betterDisplay)
        {
         g.tsDisplayLevel=level;
         g.tsDisplayWickTime=B[j].time;
         cctTsAnchorCalls++;
         cctTsStep=GetMicrosecondCount();
         g.tsDisplayLtfAnchor=FindLTFExtremeBar(B[j].time,wickBull);
         cctTsAnchorUs+=GetMicrosecondCount()-cctTsStep;
         g.tsFirstTouchTime=firstTouch;
        }
     }

   if(hasRecordedC1)
      g.modelType=ModelTypeForAuthorityRoute(g.sibs[tsAuthorityIdx].authorityRoute,
                                              g.sweepCount,
                                              g.tsPostBirthSweepCount);
   else if(g.sweepCount<=0)
      g.modelType=MODEL_CCT;
   else if(g.sweepCount==1)
      g.modelType=MODEL_CCT_TS;
   else
      g.modelType=MODEL_CCT_TS_EXT;

   CCTNormalizeGenModelBySweepTruth(g);

   ulong cctTsTotal=GetMicrosecondCount()-cctTsStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctTsTotal>250000))
      CCTJournalLine(StringFormat("[CCT TS PROFILE V1] symbol=%s | gen=%s | birth=%s | trigger=%s | total_us=%s | loops=%s | skipFuture=%s | skipTouchAfterCutoff=%s | priorCalls=%s | priorHits=%s | priorUs=%s | firstCalls=%s | firstHits=%s | firstUs=%s | virginCalls=%s | virginFails=%s | virginUs=%s | anchorCalls=%s | anchorUs=%s | sweeps=%s | postBirth=%s | olderOrBirth=%s | from=%s | cutoff=%s | scanEnd=%s | n=%s | nl=%s",
                                  _Symbol,
                                  GenKey(g.bull,g.birthTime),
                                  TimeToString(g.birthTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  g.triggerTime>0 ? TimeToString(g.triggerTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS) : "-",
                                  IntegerToString((long)cctTsTotal),
                                  IntegerToString(cctTsLoopBars),
                                  IntegerToString(cctTsSkipFuture),
                                  IntegerToString(cctTsSkipTouchAfterCutoff),
                                  IntegerToString(cctTsPriorCalls),
                                  IntegerToString(cctTsPriorHits),
                                  IntegerToString((long)cctTsPriorUs),
                                  IntegerToString(cctTsFirstCalls),
                                  IntegerToString(cctTsFirstHits),
                                  IntegerToString((long)cctTsFirstUs),
                                  IntegerToString(cctTsVirginCalls),
                                  IntegerToString(cctTsVirginFails),
                                  IntegerToString((long)cctTsVirginUs),
                                  IntegerToString(cctTsAnchorCalls),
                                  IntegerToString((long)cctTsAnchorUs),
                                  IntegerToString(g.sweepCount),
                                  IntegerToString(g.tsPostBirthSweepCount),
                                  IntegerToString(g.tsBirthOrOlderSweepCount),
                                  TimeToString(fromTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(cutoff,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  IntegerToString(n),
                                  IntegerToString(nl)));
  }

/*
Purpose: Refresh CO touch/freeze state from scanner truth after a generation has triggered.
Constitution: CO is locked at C1, touch tracking begins only after trigger, and tracking must stop permanently at trade exit. If SL/BE resolves before CO touch, the CO is frozen as untouched and hidden by the visual gate.
Inputs: g - generation record, htf - HTF rates, nh - HTF count, ltf - LTF rates, nl - LTF count, scanEnd - latest closed LTF scan time.
Outputs: g.coTouchTime, g.coFrozen, g.coFreezeTime, and g.coLtfAnchor updated without changing trigger truth.
*/
void RefreshGenerationCOState(GenInfo &g,MqlRates &htf[],int nh,MqlRates &ltf[],int nl,datetime scanEnd)
  {
   // CO terminal lifecycle guard:
   // Once execution is resolved, CO may only scan up to the exit bar.
   // This prevents SL/BE-before-CO trades from recording a phantom CO touch after exit.
   if(g.exitTime>0)
     {
      if(g.coTouchTime>0)
         return;

      if(scanEnd<=0 || g.exitTime<scanEnd)
         scanEnd=g.exitTime;
     }

   if(g.coPrice<=0.0 || g.coTime<=0 || !g.coLocked)
     {
      g.coTouchTime=0;
      g.coFrozen=false;
      g.coFreezeTime=0;
      return;
     }

   if(g.coLtfAnchor<=0)
      g.coLtfAnchor=g.coTime;

   if(g.triggerTime<=0)
     {
      g.coTouchTime=0;
      g.coFrozen=false;
      g.coFreezeTime=0;
      return;
     }

   if(g.coTouchTime>0)
     {
      g.coFrozen=true;
      if(g.coFreezeTime<=0)
         g.coFreezeTime=g.coTouchTime;
      return;
     }

   datetime until=scanEnd;
   if(g.exitTime>0 && (until<=0 || g.exitTime<until))
      until=g.exitTime;

   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time<g.triggerTime)
         continue;
      if(until>0 && ltf[k].time>until)
         break;

      bool touched=g.bull ? (ltf[k].high>=g.coPrice) : (ltf[k].low<=g.coPrice);
      if(!touched)
         continue;

      g.coTouchTime=ltf[k].time;
      g.coFreezeTime=ltf[k].time;
      g.coFrozen=true;
      break;
     }

   // Critical: if the trade exited before CO touch, CO must stop tracking.
   // It remains untouched, but the visual layer will delete/hide it.
   if(g.coTouchTime<=0 && g.exitTime>0)
     {
      g.coFrozen=true;
      g.coFreezeTime=g.exitTime;
     }
  }

/*
Purpose: Find the last surviving authority in a generation for cross-generation supersession.
Constitution: Latest user clarification that dormant shoot-through should kill only the newer frontrunning generation's final surviving authority, not every live sibling.
Inputs: g - generation record.
Outputs: Sibling index of the generation's last surviving authority, or -1 if none exists.
*/
int FindGenerationLastAuthority(const GenInfo &g)
  {
   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs && IsAliveSiblingState(g.sibs[g.activeSibIdx].state))
      return g.activeSibIdx;

   for(int s=g.nSibs-1;s>=0;s--)
     {
      if(IsAliveSiblingState(g.sibs[s].state))
         return s;
     }
   return -1;
  }

/*
Purpose: Kill only the last surviving authority in a generation.
Constitution: Latest user clarification that cross-generation supersession should not mass-kill all newer live siblings.
Inputs: g - generation record, deadState - terminal state, eventTime - structural end time.
Outputs: g updated in place.
*/
void KillGenerationLastAuthority(GenInfo &g,SIB_STATE deadState,datetime eventTime)
  {
   int idx=FindGenerationLastAuthority(g);
   if(idx<0)
      return;

   SIB_STATE priorState=g.sibs[idx].state;
   g.sibs[idx].state=deadState;
   if(g.sibs[idx].c1Time<=0)
      g.sibs[idx].c1Time=eventTime;
   if(g.activeSibIdx==idx)
      g.activeSibIdx=-1;

   if(DebugEventShouldPrint("GEN_AUTHORITY_KILL",GenKey(g.bull,g.birthTime),idx,eventTime))
      CCTJournalLine(StringFormat("[CCT DBG] GEN_AUTHORITY_KILL | gen=%s | S%d | %s -> %s | event=%s",
                                  GenKey(g.bull,g.birthTime),
                                  idx+1,
                                  EnumToString(priorState),
                                  EnumToString(deadState),
                                  TimeToString(ToNY(eventTime),TIME_DATE|TIME_MINUTES)));
  }

/*
Purpose: Emit a lightweight real-time debug message for newly-detected C1 events.
Constitution: Pass 2 verification requires CO debug output; logging is gated by Inp_ShowDebug.
Inputs: c1Time - time of the C1 bar, g - generation record.
Outputs: None.
*/
void DebugPrintC1CO(datetime c1Time,const GenInfo &g)
  {
   if(!DebugEventShouldPrint("C1",GenKey(g.bull,g.birthTime),g.activeSibIdx,c1Time))
      return;

   CCTJournalLine(StringFormat("[CCT DBG] C1 %s | CO %.5f | %s",
                               GenKey(g.bull,g.birthTime),
                               g.coPrice,
                               TimeToString(ToNY(c1Time),TIME_DATE|TIME_MINUTES)));
  }

/*
Purpose: Emit a compact scanner summary for the current draw pass.
Constitution: Ch. 35 research instrumentation and debug logging is gated by Inp_ShowDebug.
Inputs: bullBias - current bias direction, bullBirths - bullish birth count, bearBirths - bearish birth count, gens - generation array, nGens - generation count.
Outputs: None.
*/
void DebugPrintScanSummary(bool bullBias,int bullBirths,int bearBirths,GenInfo &gens[],int nGens)
  {
   if(!CCTDebugEnabled())
      return;

   static datetime s_lastSummaryBar=0;
   datetime ltfBar=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   if(ltfBar==s_lastSummaryBar)
      return;
   s_lastSummaryBar=ltfBar;

   int dormant=0;
   int liveSibs=0;
   int deadSibs=0;
   for(int i=0;i<nGens;i++)
     {
      if(gens[i].dormant)
         dormant++;
      for(int s=0;s<gens[i].nSibs;s++)
        {
         if(IsAliveSiblingState(gens[i].sibs[s].state))
            liveSibs++;
         else
            deadSibs++;
        }
     }

   CCTJournalLine(StringFormat("[CCT DBG] Scan summary | bias=%s | bullBirths=%d | bearBirths=%d | gens=%d | dormant=%d | liveSibs=%d | deadSibs=%d",
                               bullBias ? "bull" : "bear",
                               bullBirths,
                               bearBirths,
                               nGens,
                               dormant,
                               liveSibs,
                               deadSibs));

   for(int i=0;i<nGens && i<12;i++)
     {
      CCTJournalLine(StringFormat("[CCT DBG] Gen inventory | %s | dormant=%s | sibs=%d | trigger=%s | active=%d",
                                  GenKey(gens[i].bull,gens[i].birthTime),
                                  gens[i].dormant ? "yes" : "no",
                                  gens[i].nSibs,
                                  gens[i].triggerTime>0 ? TimeToString(ToNY(gens[i].triggerTime),TIME_DATE|TIME_MINUTES) : "-",
                                  gens[i].activeSibIdx));
     }
  }

/*
Purpose: Emit sibling-by-sibling state details after Pass 2 scanning to separate scan-state failures from draw-layer failures.
Constitution: Pass 2 diagnostics only; gated by Inp_ShowDebug.
Inputs: gens - generation array, nGens - generation count.
Outputs: None.
*/
void DebugPrintSiblingStates(GenInfo &gens[],int nGens)
  {
   if(!CCTDebugEnabled())
      return;

   for(int i=0;i<nGens;i++)
     {
      for(int s=0;s<gens[i].nSibs;s++)
        {
         CCTJournalLine(StringFormat("[CCT DBG] State Gen[%d] Sib[%d] | birth=%s | dormant=%s | state=%s | level=%.5f | c1=%s | c2=%s | c3=%s | auth=%s route=%d recOnly=%s | trig=%s | activeIdx=%d",
                                      i,
                                      s,
                                      TimeToString(ToNY(gens[i].birthTime),TIME_DATE|TIME_MINUTES),
                                      gens[i].dormant ? "yes" : "no",
                                      EnumToString(gens[i].sibs[s].state),
                                      gens[i].sibs[s].level,
                                      gens[i].sibs[s].c1Time>0 ? TimeToString(ToNY(gens[i].sibs[s].c1Time),TIME_DATE|TIME_MINUTES) : "-",
                                      gens[i].sibs[s].c2Time>0 ? TimeToString(ToNY(gens[i].sibs[s].c2Time),TIME_DATE|TIME_MINUTES) : "-",
                                      gens[i].sibs[s].c3Time>0 ? TimeToString(ToNY(gens[i].sibs[s].c3Time),TIME_DATE|TIME_MINUTES) : "-",
                                      gens[i].sibs[s].hadAuthorizedC1 ? "yes" : "no",
                                      (int)gens[i].sibs[s].authorityRoute,
                                      gens[i].sibs[s].authorityRecordOnly ? "yes" : "no",
                                      gens[i].triggerTime>0 ? TimeToString(ToNY(gens[i].triggerTime),TIME_DATE|TIME_MINUTES) : "-",
                                      gens[i].activeSibIdx));
        }
     }
  }

/*
Purpose: Build the in-bias generation list for Pass 2 state scanning.
Constitution: Ch. 16, Ch. 19, pass-2 generation-building rules, and latest user clarification that births/APs/executions only scan the current NY day plus the immediately previous NY day.
Inputs: B - HTF bars newest-first, n - bar count, birthIdxArr - birth indices for the in-bias direction, nBirths - birth count, bull - direction, gens - output generation array, nGens - generation count.
Outputs: gens populated newest-first with dormant status assigned.
*/
void BuildInBiasGenerations(MqlRates &B[],int n,int &birthIdxArr[],int nBirths,bool bull,GenInfo &gens[],int &nGens,datetime effectiveCutoff,bool resolveLtfAnchors=true)
  {
   nGens=0;

   if(nBirths<1)
      return;

   datetime scanStart=GenerationScanStart();

   int order[];
   ArrayResize(order,nBirths);
   for(int i=0;i<nBirths;i++)
      order[i]=birthIdxArr[i];

   for(int i=1;i<nBirths;i++)
     {
      int key=order[i];
      datetime keyTime=B[key].time;
      int j=i-1;
      while(j>=0 && B[order[j]].time<keyTime)
        {
         order[j+1]=order[j];
         j--;
        }
      order[j+1]=key;
     }

   for(int i=0;i<nBirths && nGens<ArraySize(gens);i++)
     {
      int bi=order[i];
      if(bi<0 || bi>=n)
         continue;

      datetime birthTime=B[bi].time;
      if(effectiveCutoff>0 && BirthEffectiveTime(birthTime)>effectiveCutoff)
         continue;

      datetime birthDayOpen=CCTStructuralDayOpenForTime(birthTime);
      if(birthDayOpen<scanStart)
         continue;

      GenInfo g={};
      g.birthTime=birthTime;
      g.bull=bull;
      g.dormant=(nGens>0);
      g.nSibs=0;
      g.coPrice=0.0;
      g.coTime=0;
      g.coLocked=false;
      g.nFvgs=0;
      g.c3FvgIdx=-1;
      g.triggerTime=0;
      g.modelType=MODEL_CCT;
      g.sweepCount=0;
      g.tsBirthOrOlderSweepCount=0;
      g.tsPostBirthSweepCount=0;
      g.tsDisplayLevel=0.0;
      g.tsDisplayWickTime=0;
      g.tsDisplayLtfAnchor=0;
      g.tsFirstTouchTime=0;
      g.tsEligibleFrom=0;
      g.tsConfirmed=false;
      g.slBranch=BRANCH_VSHAPE;
      g.anchorA=0.0;
      g.anchorATime=0;
      g.anchorB=0.0;
      g.anchorBTime=0;
      g.visualEntry=0.0;
      g.visualEntryTime=0;
      g.triggerSpread=0.0;
      g.fibRawSL=0.0;
      g.rawSL=0.0;
      g.rawTP=0.0;
      g.lockedRR=0.0;
      g.outcome=SS_UNKNOWN_OUTCOME;
      g.exitTime=0;
      g.exitPrice=0.0;
      g.beApplied=false;
      g.beGeneralApplied=false;
      g.beCoApplied=false;
      g.bePrice=0.0;
      g.beTriggerTime=0;
      g.beLeftAnchorTime=0;
      g.activeSibIdx=-1;
      g.coLtfAnchor=0;
      g.coFreezeTime=0;
      g.coFrozen=false;
      g.coTouchTime=0;

      BuildGenerationSiblings(B,n,bi,bull,g,resolveLtfAnchors);
      if(g.nSibs<1)
         continue;

      for(int s=0;s<g.nSibs;s++)
         g.sibs[s].state=SS_VALID;

      gens[nGens]=g;
      nGens++;
     }
  }

/*
Purpose: Return whether a generation has reached the end of its final authorized execution window.
Constitution: Ch. 29 drawing conditions, previous-day London carry rules, and latest user clarification that stale untriggered generations die once their selected execution hours are exhausted.
Inputs: g - generation record, barTime - LTF closed-bar time currently being scanned.
Outputs: True when the generation should be killed as window-expired before processing barTime.
*/
bool IsGenerationWindowExpired(const GenInfo &g,datetime barTime)
  {
   if(barTime<=0)
      return false;

   // A confirmed birth must remain structural even when its action hour is not selected.
   // Execution-hour selection controls C1 authorization, not whether this birth can
   // demote older same-bias generations during dormancy reconciliation.
   if(!GenerationHasAuthorizedExec(g.birthTime))
      return false;

   // Once a POI has a valid C1, the AP hour selected the setup. Confirmation may
   // legally complete on later HTF bars until bias flip, deeper supersession, CO
   // violation, or trigger/resolution spends the structure.
   if(GenerationHasAuthorizedC1Carry(g))
      return false;

   datetime lastEnd=0;
   if(!ResolveGenerationEffectiveEndAt(g,barTime,lastEnd))
      return (barTime>=ActionPillarTime(g.birthTime));

   return (barTime>=lastEnd);
  }

void KillDormantGenerationIfTouchedOrExpired(GenInfo &g,MqlRates &ltf[],int nl,datetime scanEnd)
  {
   // CCT_DORMANT_PASSIVE_DEATH_SWEEP_V2
   // Dormant POIs are replayed chronologically. Do not expire the whole
   // generation at scanEnd before earlier bars have had a chance to activate,
   // invalidate, or mark unauthorized C1 attempts.
   if(!g.dormant || g.triggerTime>0 || AllSiblingsDead(g) || nl<=0)
      return;

   datetime startTime=ActionPillarTime(g.birthTime);
   int startIdx=FirstLTFIndexAtOrAfter(ltf,nl,startTime);
   for(int k=startIdx;k<nl;k++)
     {
      if(GenerationBiasIsOppositeAt(g,ltf[k].time))
        {
         for(int s=0;s<g.nSibs;s++)
           {
            if(!IsAliveSiblingState(g.sibs[s].state))
               continue;
            if(BarTouchesPrice(ltf[k],g.sibs[s].level))
              {
               KillGenerationLiveSiblings(g,SS_DEAD_BIAS_FLIP,ltf[k].time);
               g.dormant=false;
               return;
              }
            }
         }

      int crossedIdx=ShallowestCrossedSiblingEdge(g,C1PrevClose(ltf,k),ltf[k].close,false);
      if(crossedIdx>=0)
         {
         ENUM_CCT_AUTH_ROUTE c1Route=AUTH_ROUTE_NONE;
         datetime c1HTFOpen=0;
         int c1HourNY=-1;
         int c1Offset=-1;
         bool dormantTakeoverHour=ResolveC1AuthorityRoute(g,ltf[k].time,true,c1Route,c1HTFOpen,c1HourNY,c1Offset);
         if(!dormantTakeoverHour)
           {
            DebugPrintC1AuthorityReject(g,crossedIdx,ltf[k].time,ltf[k].close,true,"dormant_passive_unauthorized_c1");
            g.sibs[crossedIdx].state=SS_DEAD_UNAUTHORIZED_C1;
            if(g.sibs[crossedIdx].c1Time<=0)
               g.sibs[crossedIdx].c1Time=ltf[k].time;
            g.sibs[crossedIdx].c2Time=0;
            g.sibs[crossedIdx].c3Time=0;
            ClearSiblingAuthority(g.sibs[crossedIdx]);
            if(AllSiblingsDead(g))
              {
               g.dormant=false;
               return;
              }
            }
         }

      if(IsGenerationWindowExpired(g,ltf[k].time))
        {
         DebugPrintWindowExpired(g,ltf[k].time);
         KillGenerationLiveSiblings(g,SS_DEAD_WINDOW_EXPIRED,ltf[k].time);
         return;
        }
     }

   if(IsGenerationWindowExpired(g,scanEnd))
     {
      DebugPrintWindowExpired(g,scanEnd);
      KillGenerationLiveSiblings(g,SS_DEAD_WINDOW_EXPIRED,scanEnd);
      }
   }

void SweepDormantPassiveDeaths(GenInfo &gens[],int nGens,MqlRates &ltf[],int nl,datetime scanEnd)
  {
   for(int i=0;i<nGens;i++)
      KillDormantGenerationIfTouchedOrExpired(gens[i],ltf,nl,scanEnd);
  }

/*
Purpose: Return the display label for a structural model type.
Constitution: Debug/export labels must follow the runtime sweep count, not bar distance.
Inputs: modelType - structural model enum.
Outputs: User-facing model label.
*/
string ModelTypeLabel(ENUM_MODEL_TYPE modelType)
  {
   if(modelType==MODEL_CCT_TS)
      return "CCT+TS";
   if(modelType==MODEL_CCT_TS_EXT)
      return "CCT+TS EXT";
   if(modelType==MODEL_CCT_EXT)
      return "CCT EXT";
   if(modelType==MODEL_CCT_STRUCT_TS)
      return "CCT+STRUCT_TS";
   return "CCT";
  }

/*
Purpose: Find a closed LTF bar by its open time inside the current scan window.
Constitution: Synthetic execution geometry uses the trigger bar close, so the trigger bar must be resolved exactly.
Inputs: ltf - LTF rates oldest-first, nl - bar count, barTime - bar open time to find.
Outputs: Index in ltf, or -1 when not present.
*/
int LTFIndexByTime(MqlRates &ltf[],int nl,datetime barTime)
  {
   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time==barTime)
         return k;
     }
   return -1;
  }

/*
Purpose: Resolve the visual execution start from the first LTF candle after the structural trigger close.
Constitution: Latest user clarification that structural trigger time is the close that completes C1+C2+C3, while execution visuals begin at the next LTF open.
Inputs: ltf - LTF rates oldest-first, nl - bar count, triggerIdx - trigger bar index, triggerTime - trigger bar open, triggerClose - fallback entry price.
Outputs: entryTime and entry price set to next LTF open when available, otherwise trigger close fallback.
*/
void ResolveVisualEntryFromNextLTFOpen(MqlRates &ltf[],int nl,int triggerIdx,datetime triggerTime,double triggerClose,datetime &entryTime,double &entryPrice)
  {
   int ltfSec=(int)PeriodSeconds(LTF());
   entryTime=triggerTime+(datetime)ltfSec;
   entryPrice=triggerClose;

   int nextIdx=triggerIdx+1;
   if(nextIdx>=0 && nextIdx<nl && ltf[nextIdx].time==entryTime)
     {
      entryPrice=ltf[nextIdx].open;
      return;
     }

   MqlRates one[];
   ArraySetAsSeries(one,false);
   if(CopyRates(_Symbol,LTF(),entryTime,1,one)==1 && one[0].time==entryTime)
      entryPrice=one[0].open;
  }

/*
Purpose: Resolve the spread that belonged to the trigger/entry handoff bar.
Constitution: Latest user clarification requires synthetic and broker geometry to reflect the spread available at trigger entry when possible.
Inputs: ltf - LTF rates, nl - count, triggerIdx - trigger bar index.
Outputs: Spread in price units, falling back to live Bid/Ask when history lacks spread.
*/
double ResolveTriggerSpreadPx(MqlRates &ltf[],int nl,int triggerIdx)
  {
   int spreadPts=0;
   int entryIdx=triggerIdx+1;
   if(entryIdx>=0 && entryIdx<nl)
      spreadPts=(int)ltf[entryIdx].spread;
   if(spreadPts<=0 && triggerIdx>=0 && triggerIdx<nl)
      spreadPts=(int)ltf[triggerIdx].spread;
   if(spreadPts>0)
      return NormalizeDouble(spreadPts*_Point,_Digits);

   datetime triggerTime=(triggerIdx>=0 && triggerIdx<nl) ? ltf[triggerIdx].time : 0;
   if(!EventIsCurrentLTF(triggerTime))
      return 0.0;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(ask>bid && bid>0.0)
      return NormalizeDouble(ask-bid,_Digits);
   return 0.0;
  }

/*
Purpose: Check whether the triggered structural model is authorized by the selected execution-hour family.
Constitution: Plain H-1 sources may self-elevate into TS models only when enabled; older dormant/fallback sources require their explicit TS family.
Inputs: g - generation, triggerTime - structural trigger close/open time.
Outputs: True when the final model may execute under current inputs.
*/
bool TriggerModelAuthorized(GenInfo &g,int sibIdx,datetime triggerTime)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs)
      return false;

   if(Inp_SessionFilter && triggerTime>0)
     {
      // CCT_TRIGGER_HOUR_MUST_REMAIN_SELECTED_V1
      // C1 authority can carry scanner state, but a visible/executable trigger
      // must still complete inside a currently selected execution hour/session.
      datetime triggerHTF=HTFBarOpenForTime(triggerTime);
      datetime triggerAuthTime=(Inp_TimeframeModel==CCT_TFM_D1_M15) ? triggerTime : triggerHTF;
      if(triggerAuthTime<=0 || !CCTModelAnyAuthAllows(triggerAuthTime))
         return false;
     }

   ENUM_CCT_AUTH_ROUTE route=g.sibs[sibIdx].authorityRoute;
   if(route==AUTH_ROUTE_NONE && g.sibs[sibIdx].c1Time>0)
     {
      datetime htfOpen=0;
      int nyHour=-1;
      int offset=-1;
      if(!ResolveC1AuthorityRoute(g,g.sibs[sibIdx].c1Time,false,route,htfOpen,nyHour,offset))
         return false;
      StampSiblingAuthority(g,sibIdx,route,htfOpen,nyHour,offset,false,false,ActionPillarTime(g.birthTime));
     }

   if(g.sibs[sibIdx].authorityRecordOnly || route==AUTH_ROUTE_RECORD_ONLY || route==AUTH_ROUTE_NONE)
      return false;

   int modelHourNY=g.sibs[sibIdx].authorityHourNY;
   int modelOffset=g.sibs[sibIdx].authorityOffset;

   // If a post-birth TS sweep happens after C1 but before trigger, the final
   // model belongs to the HTF bar that completed the trigger/sweep path, not
   // blindly to the original C1 authority hour.
   if(g.tsPostBirthSweepCount>0 && triggerTime>0)
     {
      datetime triggerHTF=HTFBarOpenForTime(triggerTime);
      if(triggerHTF>0)
        {
         MqlDateTime triggerNY={};
         TimeToStruct(ToNY(triggerHTF),triggerNY);
         modelHourNY=triggerNY.hour;
        }
     }

   ENUM_MODEL_TYPE authorizedModel=MODEL_CCT;
   bool allowed=ResolveAuthorizedModelFromRoute(route,
                                                g.sweepCount,
                                                g.tsPostBirthSweepCount,
                                                modelHourNY,
                                                modelOffset,
                                                authorizedModel);
   if(allowed)
     {
      g.modelType=authorizedModel;
      CCTNormalizeGenModelBySweepTruth(g);
     }
   return allowed;
  }

/*
Purpose: Export the accepted trigger through the shared signal globals.
Constitution: Scanner owns trigger truth; execution and chart layers consume the same locked geometry.
Inputs: g - generation record, sibIdx - triggered sibling index.
Outputs: g_sig* globals updated.
*/
void ExportSignalGlobals(const GenInfo &g,int sibIdx)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs)
      return;

   g_sigBull=g.bull;
   g_sigState=SS_TRIGGERED;
   g_sigLevel=g.sibs[sibIdx].level;
   g_sigSlPx=g.rawSL;
   g_sigTpPx=g.rawTP;
   g_sigCoPx=g.coPrice;
   g_sigC1=(g.sibs[sibIdx].c1Time>0);
   g_sigC2=(g.sibs[sibIdx].c2Time>0);
   g_sigC3=(g.sibs[sibIdx].c3Time>0);
   g_sigC1Time=g.sibs[sibIdx].c1Time;
   g_sigC2Time=g.sibs[sibIdx].c2Time;
   g_sigC3Time=g.sibs[sibIdx].c3Time;
   g_sigTrigTime=g.triggerTime;
   g_sigEntryTime=g.visualEntryTime;
   g_sigBirthTime=g.birthTime;
   g_sigEntryPx=g.visualEntry;
   g_sigSibIdx=sibIdx+1;
   ENUM_MODEL_TYPE exportModel=CCTModelTypeForSweepTruth(g.modelType,g.sweepCount,g.tsPostBirthSweepCount);
   g_sigModelLabel=ModelTypeLabel(exportModel);
   g_sigSLDistPips=(g.visualEntry>0.0 && g.rawSL>0.0) ? MathAbs(g.visualEntry-g.rawSL)/_Point : 0.0;
  }

/*
Purpose: Finalize or reject a true IFVG trigger after refreshing runtime TS classification and locking synthetic geometry.
Constitution: Trigger requires C2+C3, TS model label resolves at trigger time, and synthetic entry/SL/TP use trigger-close geometry without spread.
Inputs: g - generation record, sibIdx - active sibling, ltf - LTF scan window, nl - LTF count, triggerTime - trigger close time.
Outputs: True when the trigger is accepted and stored; false when rejected.
*/
bool ConfirmGenerationTrigger(GenInfo &g,int sibIdx,MqlRates &ltf[],int nl,datetime triggerTime)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs || triggerTime<=0)
      return false;
   if(g.sibs[sibIdx].state!=SS_ACTIVE)
      return false;
   if(g.sibs[sibIdx].c1Time<=0 || !g.sibs[sibIdx].hadAuthorizedC1)
      return false;
   if(g.c3FvgIdx<0 || g.c3FvgIdx>=g.nFvgs || !g.fvgs[g.c3FvgIdx].inverted || g.fvgs[g.c3FvgIdx].stale || g.fvgs[g.c3FvgIdx].invalidInv)
      return false;

   int triggerIdx=LTFIndexByTime(ltf,nl,triggerTime);
   if(triggerIdx<0)
      return false;

   RefreshGenerationTSState(g,g_htf,g_nHtf,ltf,nl,triggerTime);

   bool triggerModelAuthorized=TriggerModelAuthorized(g,sibIdx,triggerTime);
   if(!triggerModelAuthorized)
     {
      ENUM_CCT_AUTH_ROUTE fallbackRoute=g.sibs[sibIdx].authorityRoute;
      bool historicalReplay=!EventIsCurrentLTF(triggerTime);
      bool hasAuthorizedRoute=(g.sibs[sibIdx].hadAuthorizedC1 &&
                               !g.sibs[sibIdx].authorityRecordOnly &&
                               fallbackRoute!=AUTH_ROUTE_NONE &&
                               fallbackRoute!=AUTH_ROUTE_RECORD_ONLY);

      // CCT_PREINIT_TRIGGER_AUTH_FALLBACK_V5
      // A historical/pre-init replay may reconstruct the trigger after its true edge.
      // If the C1 was already authorized, restore the synthetic trigger for visuals/records.
      // Live/current triggers remain strict; old triggers cannot broker-execute because
      // CCTTryExecuteGeneration requires g.triggerTime == freshTriggerTime.
      if(historicalReplay && hasAuthorizedRoute)
        {
         int replayHourNY=g.sibs[sibIdx].authorityHourNY;
         int replayOffset=g.sibs[sibIdx].authorityOffset;
         if(g.tsPostBirthSweepCount>0 && triggerTime>0)
           {
            datetime triggerHTF=HTFBarOpenForTime(triggerTime);
            if(triggerHTF>0)
              {
               MqlDateTime triggerNY={};
               TimeToStruct(ToNY(triggerHTF),triggerNY);
               replayHourNY=triggerNY.hour;
               replayOffset=GenerationExecutionOffset(g.birthTime,triggerHTF);
              }
           }

         ENUM_MODEL_TYPE replayModel=MODEL_CCT;
         if(ResolveAuthorizedModelFromRoute(fallbackRoute,
                                            g.sweepCount,
                                            g.tsPostBirthSweepCount,
                                            replayHourNY,
                                            replayOffset,
                                            replayModel))
            g.modelType=replayModel;
         else
            g.modelType=ModelTypeForAuthorityRoute(fallbackRoute,g.sweepCount,g.tsPostBirthSweepCount);
         CCTNormalizeGenModelBySweepTruth(g);
         if(DebugEventShouldPrint("TRIGGER_REPLAY_AUTH_FALLBACK",GenKey(g.bull,g.birthTime),sibIdx,triggerTime))
            CCTJournalLine(StringFormat("[CCT DBG] TRIGGER_REPLAY_AUTH_FALLBACK | %s | S%d | model=%s sweeps=%d | route=%d offset=%d hour=%02d | trigger=%s",
                                        GenKey(g.bull,g.birthTime),
                                        sibIdx+1,
                                        ModelTypeLabel(g.modelType),
                                        g.sweepCount,
                                        (int)fallbackRoute,
                                        g.sibs[sibIdx].authorityOffset,
                                        g.sibs[sibIdx].authorityHourNY,
                                        TimeToString(ToNY(triggerTime),TIME_DATE|TIME_MINUTES)));
        }
      else
        {
         if(DebugEventShouldPrint("TRIGGER_REJECT",GenKey(g.bull,g.birthTime),sibIdx,triggerTime))
           {
            CCTJournalLine(StringFormat("[CCT DBG] TRIGGER REJECT | %s | S%d | model=%s sweeps=%d | route=%d offset=%d hour=%02d | recordOnly=%s | trigger=%s",
                                         GenKey(g.bull,g.birthTime),
                                         sibIdx+1,
                                         ModelTypeLabel(g.modelType),
                                         g.sweepCount,
                                         (int)g.sibs[sibIdx].authorityRoute,
                                         g.sibs[sibIdx].authorityOffset,
                                         g.sibs[sibIdx].authorityHourNY,
                                         g.sibs[sibIdx].authorityRecordOnly ? "yes" : "no",
                                         TimeToString(ToNY(triggerTime),TIME_DATE|TIME_MINUTES)));
           }
         g.sibs[sibIdx].state=SS_DEAD_WINDOW_EXPIRED;
         if(g.sibs[sibIdx].c3Time<=0)
            g.sibs[sibIdx].c3Time=triggerTime;
         ConsumeInactiveSiblingsOnTrigger(g,sibIdx,triggerTime);
         g.activeSibIdx=-1;
         return false;
        }
     }

   RefreshGenerationSLBranch(g,ltf,nl,triggerTime);
   double triggerClose=ltf[triggerIdx].close;
   double entryBid=0.0;
   ResolveVisualEntryFromNextLTFOpen(ltf,nl,triggerIdx,triggerTime,triggerClose,g.visualEntryTime,entryBid);
   g.triggerSpread=ResolveTriggerSpreadPx(ltf,nl,triggerIdx);
   g.visualEntry=NormalizeDouble(g.bull ? (entryBid+g.triggerSpread) : entryBid,_Digits);
   g.anchorA=(Inp_FibMode==FIB_STANDARD) ? g.fvgs[g.c3FvgIdx].c1Ext : triggerClose;
   g.anchorATime=(Inp_FibMode==FIB_STANDARD) ? g.fvgs[g.c3FvgIdx].t1 : triggerTime;
   g.anchorB=g.fvgs[g.c3FvgIdx].c2c3Extreme;
   g.anchorBTime=(g.fvgs[g.c3FvgIdx].c2c3ExtremeTime>0) ? g.fvgs[g.c3FvgIdx].c2c3ExtremeTime : g.fvgs[g.c3FvgIdx].t3;
   g.fibRawSL=CalcFibSL(g.anchorA,g.anchorB,g.bull,g.slBranch,Inp_FibCfg);
   g.rawSL=NormalizeDouble(Inp_SpreadSL ? (g.bull ? (g.fibRawSL-g.triggerSpread) : (g.fibRawSL+g.triggerSpread)) : g.fibRawSL,_Digits);
   g.lockedRR=ResolveRRPresetValue(Inp_RRPreset,Inp_RRCustom);
   g.rawTP=CalcTPRaw(g.bull,g.visualEntry,g.rawSL,g.coPrice,g.lockedRR,Inp_UseCOTP);
   g.outcome=SS_TRIGGERED;
   g.exitTime=0;
   g.exitPrice=0.0;
   g.beApplied=false;
   g.beGeneralApplied=false;
   g.beCoApplied=false;
   g.bePrice=0.0;
   g.beTriggerTime=0;
   g.beLeftAnchorTime=0;

   MarkSiblingTriggered(g,sibIdx,triggerTime);
   RefreshGenerationTSState(g,g_htf,g_nHtf,ltf,nl,triggerTime);
   ExportSignalGlobals(g,sibIdx);

   if(DebugEventShouldPrint("TRIGGER",GenKey(g.bull,g.birthTime),sibIdx,triggerTime))
     {
      CCTJournalLine(StringFormat("[CCT DBG] TRIGGER | %s | %s sweeps=%d | IFVG=%d inv=%s | branch=%s | triggerClose=%s | visualEntry=%s %.5f spread=%.5f A=%.5f B=%.5f fibSL=%.5f execSL=%.5f execTP=%.5f",
                                  GenKey(g.bull,g.birthTime),
                                  ModelTypeLabel(g.modelType),
                                  g.sweepCount,
                                  g.c3FvgIdx,
                                  TimeToString(ToNY(g.fvgs[g.c3FvgIdx].invTime),TIME_DATE|TIME_MINUTES),
                                  EnumToString(g.slBranch),
                                  TimeToString(ToNY(triggerTime),TIME_DATE|TIME_MINUTES),
                                  TimeToString(ToNY(g.visualEntryTime),TIME_DATE|TIME_MINUTES),
                                  g.visualEntry,
                                  g.triggerSpread,
                                  g.anchorA,
                                  g.anchorB,
                                  g.fibRawSL,
                                  g.rawSL,
                                  g.rawTP));
      CCTJournalLine(StringFormat("[CCT DBG] TRIGGER_DETAIL | %s | S%d level=%.5f wick=%s ltfAnchor=%s | c1=%s c2=%s c3=%s | route=%d hour=%02d offset=%d dormantRoute=%s recordOnly=%s | tsCount=%d tsLevel=%.5f tsTouch=%s tsWick=%s",
                                  GenKey(g.bull,g.birthTime),
                                  sibIdx+1,
                                  g.sibs[sibIdx].level,
                                  g.sibs[sibIdx].wickTime>0 ? TimeToString(ToNY(g.sibs[sibIdx].wickTime),TIME_DATE|TIME_MINUTES) : "-",
                                  g.sibs[sibIdx].ltfAnchor>0 ? TimeToString(ToNY(g.sibs[sibIdx].ltfAnchor),TIME_DATE|TIME_MINUTES) : "-",
                                  g.sibs[sibIdx].c1Time>0 ? TimeToString(ToNY(g.sibs[sibIdx].c1Time),TIME_DATE|TIME_MINUTES) : "-",
                                  g.sibs[sibIdx].c2Time>0 ? TimeToString(ToNY(g.sibs[sibIdx].c2Time),TIME_DATE|TIME_MINUTES) : "-",
                                  g.sibs[sibIdx].c3Time>0 ? TimeToString(ToNY(g.sibs[sibIdx].c3Time),TIME_DATE|TIME_MINUTES) : "-",
                                  (int)g.sibs[sibIdx].authorityRoute,
                                  g.sibs[sibIdx].authorityHourNY,
                                  g.sibs[sibIdx].authorityOffset,
                                  g.sibs[sibIdx].authorityDormantTakeover ? "yes" : "no",
                                  g.sibs[sibIdx].authorityRecordOnly ? "yes" : "no",
                                  g.sweepCount,
                                  g.tsDisplayLevel,
                                  g.tsFirstTouchTime>0 ? TimeToString(ToNY(g.tsFirstTouchTime),TIME_DATE|TIME_MINUTES) : "-",
                                  g.tsDisplayWickTime>0 ? TimeToString(ToNY(g.tsDisplayWickTime),TIME_DATE|TIME_MINUTES) : "-"));
     }
   return true;
  }

/*
Purpose: Return whether a bar's range traded through a specific price.
Constitution: Synthetic execution and BE visualization are range-based in tester reconstruction.
Inputs: bar - LTF bar, level - price level.
Outputs: True when the bar range contains level.
*/
bool BarTouchesPrice(const MqlRates &bar,double level)
  {
   return (level>0.0 && bar.low<=level && bar.high>=level);
  }

/*
Purpose: Compute the best favorable progress reached by an LTF bar as a percentage of entry-to-TP distance.
Constitution: BE progress is measured from visual entry toward the locked TP.
Inputs: g - generation, bar - LTF bar.
Outputs: Favorable progress percentage.
*/
double BarTPProgressPct(const GenInfo &g,const MqlRates &bar)
  {
   double span=MathAbs(g.rawTP-g.visualEntry);
   if(span<=_Point*0.1)
      return 0.0;

   double favorable=g.bull ? (bar.high-g.visualEntry) : (g.visualEntry-bar.low);
   return 100.0*favorable/span;
  }

bool SyntheticCOBEGateReady(const GenInfo &g,const MqlRates &bar,double progress)
  {
   if(g.visualEntryTime<=0 || bar.time<g.visualEntryTime)
      return false;
   if(bar.time<=g.visualEntryTime)
      return false;
   if((int)(bar.time-g.visualEntryTime)<g_beCoMinSec)
      return false;
   return (progress>=g_beCoMinProgPct);
  }

/*
Purpose: Compute the configured progress-BE stop price.
Constitution: Global BE moves SL to entry plus configured move percent of TP distance in the trade direction.
Inputs: g - generation.
Outputs: BE stop price.
*/
double GeneralBEPrice(const GenInfo &g)
  {
   double span=MathAbs(g.rawTP-g.visualEntry);
   double px=g.visualEntry + (g.bull ? 1.0 : -1.0)*(g_beMovePct/100.0)*span;
   return NormalizeDouble(px,_Digits);
  }

/*
Purpose: Return whether a candidate BE stop improves the current synthetic stop.
Constitution: BE moves must never move the stop adversely.
Inputs: g - generation, candidate - candidate stop.
Outputs: True when candidate is usable.
*/
bool BEStopIsFavorable(const GenInfo &g,double candidate)
  {
   if(candidate<=0.0)
      return false;
   if(!g.beApplied || g.bePrice<=0.0)
      return true;
   return g.bull ? (candidate>g.bePrice+_Point*0.1) : (candidate<g.bePrice-_Point*0.1);
  }

/*
Purpose: Find the visual left anchor for the visible general BE line.
Constitution: Latest user clarification that BE anchors to the latest LTF candle between entry and BE trigger whose range touched the BE price, falling back to the trigger time on gaps.
Inputs: ltf - LTF rates, nl - count, fromTime - visual entry, toTime - BE trigger time, bePrice - BE price.
Outputs: Anchor time.
*/
datetime FindBELeftAnchor(MqlRates &ltf[],int nl,datetime fromTime,datetime toTime,double bePrice)
  {
   datetime anchor=0;
   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time<fromTime || ltf[k].time>toTime)
         continue;
      if(BarTouchesPrice(ltf[k],bePrice))
         anchor=ltf[k].time;
     }
   return (anchor>0) ? anchor : toTime;
  }

/*
Purpose: Return whether CO BE may apply at the supplied management event time.
Constitution: CO BE scope is parameter-driven and shared by synthetic replay and live broker management.
Inputs: triggerTime - management/event time being evaluated.
Outputs: True when CO BE is enabled and the configured scope allows the event.
*/
bool TriggeredInNYCOBEWindow(datetime triggerTime)
  {
   return CCTCOBEApplies(triggerTime);
  }

double COBEPrice(const GenInfo &g)
  {
   // CCT_CO_BE_LOCK_USES_TP_DISTANCE_V1
   // CO BE lock percent is a portion of the planned TP profit distance, not
   // initial SL risk. Example: 5% of a $93.50 TP span locks $4.675.
   double span=MathAbs(g.rawTP-g.visualEntry);
   if(span<=_Point*0.1)
      return 0.0;
   double px=g.visualEntry + (g.bull ? 1.0 : -1.0)*(g_beCoLockPct/100.0)*span;
   return NormalizeDouble(px,_Digits);
  }

/*
Purpose: Apply a synthetic BE stop if it improves the current stop.
Constitution: CO BE is silent, general BE is visible, and both share one effective stop price.
Inputs: g - generation, candidate - stop price, eventTime - LTF event time, leftAnchor - visible line left anchor, general - visible general BE, coBased - silent CO BE.
Outputs: True when the effective stop moved.
*/
bool ApplySyntheticBEStop(GenInfo &g,double candidate,datetime eventTime,datetime leftAnchor,bool general,bool coBased)
  {
   if(!BEStopIsFavorable(g,candidate))
      return false;

   g.beApplied=true;
   g.bePrice=candidate;
   g.beTriggerTime=eventTime;
   g.beLeftAnchorTime=(leftAnchor>0) ? leftAnchor : eventTime;
   if(general)
     {
       g.beGeneralApplied=true;
      g.beGeneralPrice=candidate;
      g.beGeneralTime=eventTime;
      g.beGeneralLeftAnchorTime=g.beLeftAnchorTime;
     }
   if(coBased)
     {
      g.beCoApplied=true;
      g.beCoPrice=candidate;
      g.beCoTime=eventTime;
      g.beCoLeftAnchorTime=g.beLeftAnchorTime;
     }
   return true;
  }

/*
Purpose: Resolve synthetic TP/SL/BE outcome from closed LTF bars after the visual entry.
Constitution: Execution boxes track one LTF bar ahead while live, then lock to the close-confirmed event edge; progress BE is visible while NY CO BE is silent.
Inputs: g - triggered generation, ltf - LTF rates oldest-first, nl - bar count, scanEnd - latest scan ceiling.
Outputs: g.outcome/exitTime/exitPrice/BE state and triggered sibling state updated when a resolution is reached.
*/
void RefreshSyntheticExecutionOutcome(GenInfo &g,MqlRates &ltf[],int nl,datetime scanEnd)
  {
   if(g.triggerTime<=0 || g.activeSibIdx<0 || g.activeSibIdx>=g.nSibs)
      return;
   if(g.rawSL<=0.0 || g.rawTP<=0.0 || g.visualEntryTime<=0)
      return;
   if(g.sibs[g.activeSibIdx].state==SS_RESOLVED_TP ||
      g.sibs[g.activeSibIdx].state==SS_RESOLVED_SL ||
      g.sibs[g.activeSibIdx].state==SS_RESOLVED_BE ||
      g.sibs[g.activeSibIdx].state==SS_RESOLVED_BE_CO)
      return;
   if(g.sibs[g.activeSibIdx].state!=SS_TRIGGERED)
      return;

   datetime fromTime=g.visualEntryTime;
   int ltfSec=(int)PeriodSeconds(LTF());
   double maxProgress=0.0;
   for(int k=0;k<nl;k++)
     {
      if(ltf[k].time<fromTime || ltf[k].time>scanEnd)
         continue;

      double progress=BarTPProgressPct(g,ltf[k]);
      if(progress>maxProgress)
         maxProgress=progress;

      if(CCTRuntimeBECOEnabled() && !g.beCoApplied && g.coLocked && g.coPrice>0.0 &&
         TriggeredInNYCOBEWindow(ltf[k].time))
        {
         bool ageOk=(g.visualEntryTime>0 && ltf[k].time>g.visualEntryTime &&
                     (int)(ltf[k].time-g.visualEntryTime)>=g_beCoMinSec);
         if(ageOk && g.coTouchTime<=0 && BarTouchesPrice(ltf[k],g.coPrice))
            g.coTouchTime=ltf[k].time;

         if(g.coTouchTime>0 && SyntheticCOBEGateReady(g,ltf[k],maxProgress))
           {
            double coBE=COBEPrice(g);
            datetime leftAnchor=FindBELeftAnchor(ltf,nl,g.visualEntryTime,ltf[k].time,coBE);
            ApplySyntheticBEStop(g,coBE,ltf[k].time,leftAnchor,false,true);
           }
        }

      if(CCTRuntimeBEGlobalEnabled() && !g.beGeneralApplied && progress>=g_beTriggerPct)
        {
         double beCandidate=GeneralBEPrice(g);
         datetime leftAnchor=FindBELeftAnchor(ltf,nl,fromTime,ltf[k].time,beCandidate);
         ApplySyntheticBEStop(g,beCandidate,ltf[k].time,leftAnchor,true,false);
        }

      datetime barEdge=ClosedLTFEventEdge(ltf[k].time);
      if(barEdge<=ltf[k].time)
         barEdge=ltf[k].time+(datetime)ltfSec-1;
      bool beActiveForBar=(g.beApplied && g.bePrice>0.0 &&
                           (g.beTriggerTime<=0 || barEdge>=g.beTriggerTime));
      double activeStop=beActiveForBar ? g.bePrice : g.rawSL;
      bool stopHit=g.bull ? (ltf[k].low<=activeStop) : (ltf[k].high>=activeStop);
      bool tpHit=g.bull ? (ltf[k].high>=g.rawTP) : (ltf[k].low<=g.rawTP);
      if(stopHit || tpHit)
        {
         // With closed OHLC only, same-bar ambiguity is resolved conservatively: active stop before TP.
         if(stopHit)
           {
            if(beActiveForBar)
              {
               bool coOnly=(g.beCoApplied && !g.beGeneralApplied);
               g.sibs[g.activeSibIdx].state=coOnly ? SS_RESOLVED_BE_CO : SS_RESOLVED_BE;
               g.outcome=g.sibs[g.activeSibIdx].state;
              }
            else
              {
               g.sibs[g.activeSibIdx].state=SS_RESOLVED_SL;
               g.outcome=SS_RESOLVED_SL;
              }
            g.exitPrice=activeStop;
           }
         else
           {
            g.sibs[g.activeSibIdx].state=SS_RESOLVED_TP;
            g.outcome=SS_RESOLVED_TP;
            g.exitPrice=g.rawTP;
           }

         if(barEdge<=fromTime)
            barEdge=ltf[k].time+(datetime)ltfSec-1;
         g.exitTime=barEdge;
         return;
        }
     }
  }

/*
Purpose: Allow a dormant generation to activate via shoot-through under an open execution bar.
Constitution: Ch. 16 dormant shoot-through and Ch. 36.13 dormant activation management.
Inputs: g - dormant generation, ltf - LTF rates oldest-first, nl - bar count, isExecBarOpen - current HTF execution gate, currentHTFHourNY - current NY hour.
Outputs: True when the generation activates and leaves dormancy.
*/
bool ScanDormantGenerationC1(GenInfo &g,MqlRates &ltf[],int nl,bool isExecBarOpen,int currentHTFHourNY,datetime dormantCOCutoff=0)
  {
   if(!g.dormant || g.triggerTime>0 || AllSiblingsDead(g))
      return false;

   datetime pillarTime=ActionPillarTime(g.birthTime);

   int startIdx=FirstLTFIndexAtOrAfter(ltf,nl,pillarTime);
   for(int k=startIdx;k<nl;k++)
     {
       TrackGenerationFVGFormation(g,ltf,nl,k);
      if(ScanCounterBiasPoisonedDormantSiblings(g,ltf,nl,k))
         return false;
      if(GenerationBiasIsOppositeAt(g,ltf[k].time) && g.triggerTime==0)
        {
         bool killedUnauthorized=KillUnauthorizedC1SiblingsOnBiasFlip(g,ltf[k].time);
         if(g.activeSibIdx>=0)
            KillActiveSiblingOnBiasFlip(g,ltf[k].time);
         else if(!killedUnauthorized && ScanCounterBiasDormantSiblings(g,ltf,nl,k))
            return false;
         continue;
        }
      if(ScanUnauthorizedStructuralTrigger(g,ltf,nl,k))
         return false;

      ENUM_CCT_AUTH_ROUTE c1Route=AUTH_ROUTE_NONE;
      datetime c1HTFOpen=0;
      int c1HourNY=-1;
      int c1Offset=-1;
      bool dormantTakeoverHour=ResolveC1AuthorityRoute(g,ltf[k].time,true,c1Route,c1HTFOpen,c1HourNY,c1Offset);
       if(!dormantTakeoverHour)
         {
          int unauthorizedIdx=ShallowestCrossedSiblingEdge(g,C1PrevClose(ltf,k),ltf[k].close,false);
          if(unauthorizedIdx>=0)
            {
             DebugPrintC1AuthorityReject(g,unauthorizedIdx,ltf[k].time,ltf[k].close,true,"dormant_takeover_not_authorized");
             g.sibs[unauthorizedIdx].state=SS_DEAD_UNAUTHORIZED_C1;
             g.sibs[unauthorizedIdx].c1Time=ltf[k].time;
             g.sibs[unauthorizedIdx].c2Time=0;
             g.sibs[unauthorizedIdx].c3Time=0;
             ClearSiblingAuthority(g.sibs[unauthorizedIdx]);
            if(ScanUnauthorizedStructuralTrigger(g,ltf,nl,k))
               return false;
           }
         continue;
        }

      int activatedIdx=ShallowestCrossedSiblingEdge(g,C1PrevClose(ltf,k),ltf[k].close,false);
      if(activatedIdx<0)
         continue;

      for(int s=0;s<activatedIdx;s++)
        {
         if(!IsAliveSiblingState(g.sibs[s].state))
            continue;
         g.sibs[s].state=SS_DEAD_SUPERSESSION;
         if(g.sibs[s].c1Time<=0)
            g.sibs[s].c1Time=ltf[k].time;
         g.sibs[s].c2Time=0;
         g.sibs[s].c3Time=0;
        }

      g.dormant=false;
      g.sibs[activatedIdx].state=SS_ACTIVE;
      g.sibs[activatedIdx].c1Time=ltf[k].time;
      StampSiblingAuthority(g,activatedIdx,c1Route,c1HTFOpen,c1HourNY,c1Offset,true,false,c1HTFOpen);
      for(int s=activatedIdx+1;s<g.nSibs;s++)
        {
         if(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT)
            g.sibs[s].state=SS_INACTIVE;
        }

      g.activeSibIdx=activatedIdx;
      datetime coCutoff=(dormantCOCutoff>0 && dormantCOCutoff<ltf[k].time) ? dormantCOCutoff : ltf[k].time;
      LockCorrectionOriginIfNeeded(g,ltf,nl,coCutoff,true);
      DebugPrintC1CO(ltf[k].time,g);
      return true;
     }

   return false;
  }

/*
Purpose: Kill all newer live generations after an older dormant generation wins shoot-through authority.
Constitution: Ch. 16 generation supersession and execution-window ownership transfer.
Inputs: gens - generation array newest-first, activatedIdx - index of the newly activated older generation, eventTime - activation time.
Outputs: Newer generations updated in place.
*/
void SupersedeNewerGenerations(GenInfo &gens[],int activatedIdx,datetime eventTime)
  {
   for(int i=0;i<activatedIdx;i++)
     {
      // GEN_SUPERSESSION / generation-authority supersession:
      // Cross-generation authority transfer only.
      // Not intra-generation sibling supersession.
      // Not FVG / IFVG inversion supersession.

      if(ActionPillarTime(gens[i].birthTime)>eventTime)
         continue;

      // Historical replay can make a newer frontrunner trigger after an older dormant
      // generation had already reactivated. If the frontrunner's trigger happened
      // AFTER the older dormant activation event, the older dormant generation wins
      // authority and the newer trigger must be cleared so both cannot execute.
      //
      // If the frontrunner triggered BEFORE or AT eventTime, its trade stands.
      if(gens[i].triggerTime>0 && gens[i].triggerTime>eventTime)
        {
         string genKey=GenKey(gens[i].bull,gens[i].birthTime);

         for(int s=0;s<gens[i].nSibs;s++)
           {
            if(gens[i].sibs[s].state==SS_TRIGGERED)
              {
               gens[i].sibs[s].state=SS_DEAD_SUPERSESSION;

               if(gens[i].sibs[s].c1Time<=0)
                  gens[i].sibs[s].c1Time=eventTime;

               gens[i].sibs[s].c2Time=0;
               gens[i].sibs[s].c3Time=0;
               break;
              }
           }

         if(DebugEventShouldPrint("GEN_SUPERSESSION",genKey,-1,eventTime))
            CCTJournalLine(StringFormat("[CCT DBG] GEN_SUPERSESSION | killed post-dormant-activation trigger gen=%s trigger=%s event=%s",
                                        genKey,
                                        TimeToString(gens[i].triggerTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                        TimeToString(eventTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));

         gens[i].triggerTime=0;
         gens[i].activeSibIdx=-1;
        }

      KillGenerationLastAuthority(gens[i],SS_DEAD_SUPERSESSION,eventTime);
     }
  }

/*
Purpose: Consume a generation when an off-authorization C1 later completes the structural trigger sequence.
Constitution: One execution per generation forever. A completed structural trigger outside selected hours cannot execute, but it still spends the generation before any deeper sibling may trade.
Inputs: g - generation, sibIdx - unauthorized sibling that completed C2+C3, eventTime - structural trigger close.
Outputs: All still-live siblings are terminally consumed while the unauthorized sibling remains marked by its invalid C1 reason.
*/
void ConsumeGenerationAfterUnauthorizedTrigger(GenInfo &g,int sibIdx,datetime eventTime)
  {
   if(sibIdx<0 || sibIdx>=g.nSibs || eventTime<=0)
      return;

   // CCT_UNAUTHORIZED_CONSUME_REJECTS_COUNTER_BIAS_V1
   // Unauthorized structural completion may spend a generation only while
   // that generation is still bias-valid at the actual C2/C3 completion time.
   // After a bias flip it is a bias-flip death, not window consumption.
   if(GenerationBiasIsOppositeAt(g,eventTime))
     {
      if(DebugEventShouldPrint("UNAUTH_CONSUME_REJECTED_BIAS_FLIP",GenKey(g.bull,g.birthTime),sibIdx,eventTime))
         CCTJournalLine(StringFormat("[CCT DBG] UNAUTH_CONSUME_REJECTED_BIAS_FLIP | gen=%s | S%d | completed=%s",
                                     GenKey(g.bull,g.birthTime),
                                     sibIdx+1,
                                     TimeToString(eventTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));

      g.sibs[sibIdx].state=SS_DEAD_BIAS_FLIP;
      if(g.sibs[sibIdx].c1Time<=0)
         g.sibs[sibIdx].c1Time=eventTime;
      g.sibs[sibIdx].c2Time=0;
      g.sibs[sibIdx].c3Time=0;
      ClearSiblingAuthority(g.sibs[sibIdx]);
      g.activeSibIdx=-1;
      g.dormant=false;
      g.triggerTime=0;
      return;
     }

   if(g.sibs[sibIdx].c2Time<=0)
      g.sibs[sibIdx].c2Time=eventTime;
   if(g.sibs[sibIdx].c3Time<=0)
      g.sibs[sibIdx].c3Time=eventTime;
   g.sibs[sibIdx].state=SS_DEAD_UNAUTHORIZED_C1;

   KillGenerationLiveSiblings(g,SS_DEAD_WINDOW_CONSUMED,eventTime);
   g.activeSibIdx=-1;
   g.dormant=false;
   g.tsDisplayLevel=0.0;
   g.tsDisplayWickTime=0;
   g.tsDisplayLtfAnchor=0;
   g.tsFirstTouchTime=0;
   g.tsConfirmed=false;
   g.sweepCount=0;
   g.tsBirthOrOlderSweepCount=0;
   g.tsPostBirthSweepCount=0;
   g.modelType=MODEL_CCT;

   if(DebugEventShouldPrint("UNAUTH_CONSUME",GenKey(g.bull,g.birthTime),sibIdx,eventTime))
     {
      CCTJournalLine(StringFormat("[CCT DBG] UNAUTHORIZED STRUCTURAL CONSUME | %s | S%d | c1=%s | spent=%s",
                                  GenKey(g.bull,g.birthTime),
                                  sibIdx+1,
                                  TimeToString(ToNY(g.sibs[sibIdx].c1Time),TIME_DATE|TIME_MINUTES),
                                  TimeToString(ToNY(eventTime),TIME_DATE|TIME_MINUTES)));
     }
  }

/*
Purpose: Detect a completed unauthorized C1+C2+C3 sequence even when historical IFVG/C2 state was reconstructed after the exact trigger close.
Constitution: A C1 from an unselected execution hour can never become an executable carry; once C2+C3 coexist, the whole generation is spent.
Inputs: g - generation, sibIdx - unauthorized sibling, currentTime - current replay bar time, completedAt - resolved structural completion time.
Outputs: True when this unauthorized sibling has already structurally consumed the generation.
*/
bool UnauthorizedStructuralTriggerCompleted(const GenInfo &g,int sibIdx,datetime currentTime,datetime &completedAt)
  {
   completedAt=0;
   if(sibIdx<0 || sibIdx>=g.nSibs || currentTime<=0)
      return false;
   if(g.sibs[sibIdx].state!=SS_DEAD_UNAUTHORIZED_C1)
      return false;
   if(g.sibs[sibIdx].c1Time<=0 || g.sibs[sibIdx].c2Time<=0 || g.sibs[sibIdx].c3Time<=0)
      return false;
   if(g.sibs[sibIdx].c2Time<=g.sibs[sibIdx].c1Time || g.sibs[sibIdx].c3Time<=g.sibs[sibIdx].c1Time)
      return false;

   completedAt=(g.sibs[sibIdx].c2Time>g.sibs[sibIdx].c3Time) ? g.sibs[sibIdx].c2Time : g.sibs[sibIdx].c3Time;
   return (completedAt>0 && completedAt<=currentTime);
  }

/*
Purpose: Continue monitoring POIs killed by unauthorized C1 only for the single question of whether they structurally consumed the generation.
Constitution: Unselected hours may not execute or visualize a trigger, but if C1+C2+C3 completes before selected-hour usage, the generation is spent and no deeper sibling may later trigger.
Inputs: g - generation, ltf - LTF rates oldest-first, nl - bar count, k - current closed LTF index.
Outputs: True when the generation was consumed by an unauthorized structural trigger.
*/
bool ScanUnauthorizedStructuralTrigger(GenInfo &g,MqlRates &ltf[],int nl,int k)
  {
   if(k<0 || k>=nl || g.triggerTime>0)
      return false;

   double cls=ltf[k].close;
   for(int s=0;s<g.nSibs;s++)
     {
      if(g.sibs[s].state!=SS_DEAD_UNAUTHORIZED_C1 || g.sibs[s].c1Time<=0)
         continue;
      if(ltf[k].time<g.sibs[s].c1Time)
         continue;

      UpdateGenerationC3State(g,s,ltf,nl,k);

      double level=g.sibs[s].level;
      datetime priorC2Time=g.sibs[s].c2Time;
      bool reclaim=(g.bull && cls>=level) || (!g.bull && cls<=level);
      if(reclaim && g.sibs[s].c2Time==0)
         g.sibs[s].c2Time=ltf[k].time;

      bool lapse=(g.bull && cls<level) || (!g.bull && cls>level);
      if(lapse && g.sibs[s].c2Time>0)
         g.sibs[s].c2Time=0;

      if(TriggerBridgeConfirmed(g,s,ltf[k],priorC2Time))
        {
         ConsumeGenerationAfterUnauthorizedTrigger(g,s,ltf[k].time);
         return true;
        }

      datetime completedAt=0;
      if(UnauthorizedStructuralTriggerCompleted(g,s,ltf[k].time,completedAt))
        {
         ConsumeGenerationAfterUnauthorizedTrigger(g,s,completedAt);
         return true;
        }
     }

   return false;
  }

/*
Purpose: Continue monitoring dormant siblings that were first crossed while the generation was counter-bias.
Constitution: C1 is decisive; once a POI gets counter-bias C1, a later C2+C3 kills the sibling set even if bias has flipped back in favour on or before the completion candle.
Inputs: g - generation record, ltf - LTF rates oldest-first, nl - bar count, k - current LTF index.
Outputs: True when the generation was killed by the poisoned counter-bias sequence.
*/
bool ScanCounterBiasPoisonedDormantSiblings(GenInfo &g,MqlRates &ltf[],int nl,int k)
  {
   if(k<0 || k>=nl)
      return false;

   double cls=ltf[k].close;
   for(int s=0;s<g.nSibs;s++)
     {
      if(!DormantCounterBiasC1Poisoned(g.sibs[s]))
         continue;
      if(ltf[k].time<g.sibs[s].c1Time)
         continue;

      UpdateGenerationC3State(g,s,ltf,nl,k);

      bool reclaim=(g.bull && cls>=g.sibs[s].level) || (!g.bull && cls<=g.sibs[s].level);
      if(reclaim && g.sibs[s].c2Time==0)
         g.sibs[s].c2Time=ltf[k].time;

      bool lapse=(g.bull && cls<g.sibs[s].level) || (!g.bull && cls>g.sibs[s].level);
      if(lapse && g.sibs[s].c2Time>0)
         g.sibs[s].c2Time=0;

      if(g.sibs[s].c2Time>g.sibs[s].c1Time && g.sibs[s].c3Time>g.sibs[s].c1Time)
        {
         KillGenerationLiveSiblings(g,SS_DEAD_BIAS_FLIP,ltf[k].time);
         return true;
        }
     }

   return false;
  }

/*
Purpose: Scan one generation through Pass 2's C1, supersession, C2, CO violation, and bias-flip rules.
Constitution: Ch. 8, Ch. 11, Ch. 12, Ch. 13, Ch. 15, Ch. 18, and Pass 2 scan rules.
Inputs: g - generation record, ltf - LTF rates array, nl - bar count, isExecBarOpen - whether the current HTF bar is an execution hour, currentHTFHourNY - current HTF NY hour.
Outputs: g updated in place.
*/
// CCT_VISUAL_LIVE_HISTORICAL_RECONSTRUCTION_V3
// Historical trigger replay is allowed only during visual/live render
// reconstruction. Execution-only scans remain fresh-edge strict.
// CCT_HISTORICAL_TRIGGER_REPLAY_WINDOW_EXPIRED_DEFER_V5_SCANNER_REPLAY
// During visual/live reconstruction only, let already-active historical POIs
// scan past their expiry check long enough to rediscover the old trigger.
// If no trigger is found by scanEnd, they are still killed as window expired.
void ScanGenerationC1C2(GenInfo &g,MqlRates &ltf[],int nl,bool isExecBarOpen,int currentHTFHourNY)
  {
   if(g.dormant || g.triggerTime>0 || AllSiblingsDead(g))
      return;

   datetime pillarTime=ActionPillarTime(g.birthTime);

   datetime startTime=pillarTime;
   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs && g.sibs[g.activeSibIdx].c1Time>startTime)
      startTime=g.sibs[g.activeSibIdx].c1Time;
   else
     {
      datetime earliestUnauthorized=0;
      for(int s=0;s<g.nSibs;s++)
        {
         if(g.sibs[s].state==SS_DEAD_UNAUTHORIZED_C1 && g.sibs[s].c1Time>0 &&
            (earliestUnauthorized==0 || g.sibs[s].c1Time<earliestUnauthorized))
            earliestUnauthorized=g.sibs[s].c1Time;
        }
      if(earliestUnauthorized>startTime)
         startTime=earliestUnauthorized;
     }

   int startIdx=FirstLTFIndexAtOrAfter(ltf,nl,startTime);
   datetime scanEnd=(nl>0) ? ltf[nl-1].time : 0;
   for(int k=startIdx;k<nl;k++)
     {
       TrackGenerationFVGFormation(g,ltf,nl,k);
      if(ScanCounterBiasPoisonedDormantSiblings(g,ltf,nl,k))
         return;
      if(g.activeSibIdx>=0 && g.sibs[g.activeSibIdx].c1Time>0 && ltf[k].time<g.sibs[g.activeSibIdx].c1Time)
         continue;
      if(GenerationBiasIsOppositeAt(g,ltf[k].time) && g.triggerTime==0)
        {
         bool killedUnauthorized=KillUnauthorizedC1SiblingsOnBiasFlip(g,ltf[k].time);
         if(g.activeSibIdx>=0)
            KillActiveSiblingOnBiasFlip(g,ltf[k].time);
         else if(!killedUnauthorized && ScanCounterBiasDormantSiblings(g,ltf,nl,k))
            return;
         continue;
        }
       // CCT_HISTORICAL_TRIGGER_REPLAY_WINDOW_EXPIRED_DEFER_V5_EXPIRY_GATE
      bool cctDeferHistoricalWindowExpiry=(g_cctAllowHistoricalReplayTriggers &&
                                           g.triggerTime<=0 &&
                                           g.activeSibIdx>=0);

      if(!cctDeferHistoricalWindowExpiry && IsGenerationWindowExpired(g,ltf[k].time))
        {
         DebugPrintWindowExpired(g,ltf[k].time);
         KillGenerationLiveSiblings(g,SS_DEAD_WINDOW_EXPIRED,ltf[k].time);
         return;
        }

      if(ScanUnauthorizedStructuralTrigger(g,ltf,nl,k))
         return;

      double cls=ltf[k].close;
      ENUM_CCT_AUTH_ROUTE c1Route=AUTH_ROUTE_NONE;
      datetime c1HTFOpen=0;
      int c1HourNY=-1;
      int c1Offset=-1;
      bool execHour=ResolveC1AuthorityRoute(g,ltf[k].time,false,c1Route,c1HTFOpen,c1HourNY,c1Offset);

      if(g.activeSibIdx<0)
        {
         bool generationCarry=GenerationHasAuthorizedC1Carry(g);
         if(!execHour && !generationCarry)
           {
            for(int s=0;s<g.nSibs;s++)
              {
               if(g.sibs[s].state!=SS_VALID)
                  continue;
                bool crossed=IsC1EdgeCross(g.bull,C1PrevClose(ltf,k),cls,g.sibs[s].level);
                if(!crossed)
                   continue;
                DebugPrintC1AuthorityReject(g,s,ltf[k].time,cls,false,"no_c1_authority");
                g.sibs[s].state=SS_DEAD_UNAUTHORIZED_C1;
                g.sibs[s].c1Time=ltf[k].time;
                g.sibs[s].c2Time=0;
                g.sibs[s].c3Time=0;
                 ClearSiblingAuthority(g.sibs[s]);
              }
            if(ScanUnauthorizedStructuralTrigger(g,ltf,nl,k))
               return;
            continue;
           }

         int activatedIdx=ShallowestCrossedSiblingEdge(g,C1PrevClose(ltf,k),cls,generationCarry);
         if(activatedIdx>=0)
           {
            SIB_STATE priorState=g.sibs[activatedIdx].state;
            bool relockForReactivation=(generationCarry || priorState==SS_INACTIVE || priorState==SS_DORMANT);
            for(int s=0;s<activatedIdx;s++)
              {
               if(!IsAliveSiblingState(g.sibs[s].state))
                  continue;
               g.sibs[s].state=SS_DEAD_SUPERSESSION;
               if(g.sibs[s].c1Time<=0)
                  g.sibs[s].c1Time=ltf[k].time;
               g.sibs[s].c2Time=0;
               g.sibs[s].c3Time=0;
              }

            g.sibs[activatedIdx].state=SS_ACTIVE;
            g.sibs[activatedIdx].c1Time=ltf[k].time;
            if(generationCarry)
              {
               int sourceIdx=LastSiblingAuthorityIndex(g);
               if(sourceIdx>=0)
                  InheritSiblingAuthority(g,sourceIdx,activatedIdx,ltf[k].time);
               else
                  StampSiblingAuthority(g,activatedIdx,c1Route,c1HTFOpen,c1HourNY,c1Offset,false,false,ActionPillarTime(g.birthTime));
              }
            else
               StampSiblingAuthority(g,activatedIdx,c1Route,c1HTFOpen,c1HourNY,c1Offset,false,false,ActionPillarTime(g.birthTime));
            for(int s=activatedIdx+1;s<g.nSibs;s++)
              {
               if(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT)
                  g.sibs[s].state=SS_INACTIVE;
              }

            g.activeSibIdx=activatedIdx;
            LockCorrectionOriginIfNeeded(g,ltf,nl,ltf[k].time,relockForReactivation);
            UpdateGenerationC3State(g,g.activeSibIdx,ltf,nl,k);
            DebugPrintC1CO(ltf[k].time,g);
            PromoteDeepestCrossedInactiveSibling(g,ltf,nl,k);
          }
        }

      if(g.activeSibIdx>=0 && g.sibs[g.activeSibIdx].state==SS_ACTIVE)
        {
         bool activeCarry=(g.sibs[g.activeSibIdx].hadAuthorizedC1 && g.sibs[g.activeSibIdx].c1Time>0);
         if(!execHour && !activeCarry)
           {
            for(int s=g.activeSibIdx+1;s<g.nSibs;s++)
              {
               if(g.sibs[s].state!=SS_INACTIVE)
                  continue;
                if(!IsC1EdgeCross(g.bull,C1PrevClose(ltf,k),cls,g.sibs[s].level))
                   continue;
                 DebugPrintC1AuthorityReject(g,s,ltf[k].time,cls,false,"deeper_inactive_no_c1_authority");
                 g.sibs[s].state=SS_DEAD_UNAUTHORIZED_C1;
                 g.sibs[s].c1Time=ltf[k].time;
                 g.sibs[s].c2Time=0;
                g.sibs[s].c3Time=0;
                ClearSiblingAuthority(g.sibs[s]);
               }
            if(ScanUnauthorizedStructuralTrigger(g,ltf,nl,k))
               return;
         }
         else
           {
            UpdateGenerationC3State(g,g.activeSibIdx,ltf,nl,k);

            double actLvl=g.sibs[g.activeSibIdx].level;
            datetime priorC2Time=g.sibs[g.activeSibIdx].c2Time;
            bool reclaim=(g.bull && cls>=actLvl) || (!g.bull && cls<=actLvl);
            if(reclaim && g.sibs[g.activeSibIdx].c2Time==0)
               g.sibs[g.activeSibIdx].c2Time=ltf[k].time;

            bool lapse=(g.bull && cls<actLvl) || (!g.bull && cls>actLvl);
            if(lapse && g.sibs[g.activeSibIdx].c2Time>0)
               g.sibs[g.activeSibIdx].c2Time=0;

            if(TriggerBridgeConfirmed(g,g.activeSibIdx,ltf[k],priorC2Time))
              {
               // CCT_RESTORE_PREINIT_SYNTHETIC_TRIGGER_V1_LTF_BRIDGE
// Historical/pre-init structural triggers must be restored as synthetic
// trigger records, not converted into DEAD_WINDOW_CONSUMED. Broker
// execution remains guarded by CCTTryExecuteGeneration fresh-trigger checks.
ConfirmGenerationTrigger(g,g.activeSibIdx,ltf,nl,ltf[k].time);
               return;
              }

            datetime activeCompletedAt=0;
            if(AuthorizedStructuralTriggerCompleted(g,g.activeSibIdx,ltf[k].time,activeCompletedAt))
              {
               // CCT_RESTORE_PREINIT_SYNTHETIC_TRIGGER_V1_ACTIVE_COMPLETED
// If an already-active POI completed C2+C3 before this replay edge,
// restore it as a synthetic trigger. Do not suppress it into a dead state.
ConfirmGenerationTrigger(g,g.activeSibIdx,ltf,nl,activeCompletedAt);
               return;
              }

            if(g.coLocked && ltf[k].time>g.sibs[g.activeSibIdx].c1Time)
              {
                bool touched=(g.bull && ltf[k].high>=g.coPrice) || (!g.bull && ltf[k].low<=g.coPrice);
                bool closeViolated=(g.bull && cls>=g.coPrice) || (!g.bull && cls<=g.coPrice);
                if(touched && !closeViolated && DebugEventShouldPrint("CO_TOUCH_HELD",GenKey(g.bull,g.birthTime),g.activeSibIdx,ltf[k].time))
                   CCTJournalLine(StringFormat("[CCT DBG] CO_TOUCH_HELD | gen=%s | sib=%d | bar=%s | co=%.5f | cls=%.5f | hi=%.5f | lo=%.5f",
                                               GenKey(g.bull,g.birthTime),
                                               g.activeSibIdx,
                                               TimeToString(ToNY(ltf[k].time),TIME_DATE|TIME_MINUTES),
                                               g.coPrice,
                                               cls,
                                               ltf[k].high,
                                               ltf[k].low));
                if(touched && closeViolated)
                  {
                   if(DebugEventShouldPrint("CO_VIOLATION",GenKey(g.bull,g.birthTime),g.activeSibIdx,ltf[k].time))
                      CCTJournalLine(StringFormat("[CCT DBG] CO_VIOLATION | gen=%s | sib=%d | bar=%s | co=%.5f | cls=%.5f | hi=%.5f | lo=%.5f | c1=%s | c2=%s | c3=%s",
                                                  GenKey(g.bull,g.birthTime),
                                                  g.activeSibIdx,
                                                  TimeToString(ToNY(ltf[k].time),TIME_DATE|TIME_MINUTES),
                                                  g.coPrice,
                                                  cls,
                                                  ltf[k].high,
                                                  ltf[k].low,
                                                  TimeToString(ToNY(g.sibs[g.activeSibIdx].c1Time),TIME_DATE|TIME_MINUTES),
                                                  g.sibs[g.activeSibIdx].c2Time>0 ? TimeToString(ToNY(g.sibs[g.activeSibIdx].c2Time),TIME_DATE|TIME_MINUTES) : "-",
                                                  g.sibs[g.activeSibIdx].c3Time>0 ? TimeToString(ToNY(g.sibs[g.activeSibIdx].c3Time),TIME_DATE|TIME_MINUTES) : "-"));
                   int failedIdx=g.activeSibIdx;
                   g.sibs[failedIdx].state=SS_DEAD_CO_VIOLATION;
                   g.sibs[failedIdx].c2Time=0;
                   g.sibs[failedIdx].c3Time=0;
                   g.activeSibIdx=-1;

                   int nextIdx=-1;
                   double prevCls=C1PrevClose(ltf,k);
                   for(int s=failedIdx+1;s<g.nSibs;s++)
                     {
                      if(g.sibs[s].state!=SS_INACTIVE)
                         continue;
                      if(IsC1EdgeCross(g.bull,prevCls,cls,g.sibs[s].level))
                         nextIdx=s;
                     }

                   if((execHour || activeCarry) && nextIdx>=0)
                     {
                      for(int s=failedIdx+1;s<nextIdx;s++)
                        {
                         if(!IsAliveSiblingState(g.sibs[s].state))
                            continue;
                         g.sibs[s].state=SS_DEAD_SUPERSESSION;
                         if(g.sibs[s].c1Time<=0)
                            g.sibs[s].c1Time=ltf[k].time;
                         g.sibs[s].c2Time=0;
                         g.sibs[s].c3Time=0;
                        }

                       g.sibs[nextIdx].state=SS_ACTIVE;
                       g.sibs[nextIdx].c1Time=ltf[k].time;
                       InheritSiblingAuthority(g,failedIdx,nextIdx,ltf[k].time);
                      g.activeSibIdx=nextIdx;
                     ResetActiveSiblingConfirmation(g,g.activeSibIdx);
                      LockCorrectionOriginIfNeeded(g,ltf,nl,ltf[k].time,true);
                     UpdateGenerationC3State(g,g.activeSibIdx,ltf,nl,k);
                     DebugPrintC1CO(ltf[k].time,g);
                    }
                  continue;
                 }
              }

            if((execHour || activeCarry) && PromoteDeepestCrossedInactiveSibling(g,ltf,nl,k))
               continue;

          }
        }

      if(GenerationBiasIsOppositeAt(g,ltf[k].time) && (g.triggerTime==0 || ltf[k].time<g.triggerTime))
        {
         bool killedUnauthorized=KillUnauthorizedC1SiblingsOnBiasFlip(g,ltf[k].time);
         if(g.activeSibIdx>=0)
            KillActiveSiblingOnBiasFlip(g,ltf[k].time);
         else if(!killedUnauthorized && ScanCounterBiasDormantSiblings(g,ltf,nl,k))
            return;
         continue;
        }

     }

   // CCT_HISTORICAL_TRIGGER_REPLAY_WINDOW_EXPIRED_DEFER_V5_FINALIZER
   // If visual historical replay deferred expiry for an active POI but no
   // old trigger was found by the end of the scan, expire it now.
   if(g_cctAllowHistoricalReplayTriggers &&
      g.triggerTime<=0 &&
      g.activeSibIdx>=0 &&
      IsGenerationWindowExpired(g,scanEnd))
     {
      DebugPrintWindowExpired(g,scanEnd);
      KillGenerationLiveSiblings(g,SS_DEAD_WINDOW_EXPIRED,scanEnd);
     }

  }

#endif
