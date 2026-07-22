//+------------------------------------------------------------------+
//| CCT_Scanner.mqh  v6.0                                            |
//| HTF/LTF bar utilities, virgin wick classification,               |
//| CO calculation, full generation state machine, birth lists.      |
//+------------------------------------------------------------------+
#ifndef CCT_SCANNER_MQH
#define CCT_SCANNER_MQH

#include "CCT_Globals.mqh"

//+------------------------------------------------------------------+
// FindLTFWickBar — LTF bar that made the extreme within one HTF bar
//+------------------------------------------------------------------+
// FindLTFWickBar — LTF bar that made the extreme within one HTF bar.
// Uses count-based CopyRates (more reliable for historical bars than
// datetime-range form, which can return 0 when data isn't preloaded).
// Requests exactly (pSec/ltfSec) bars starting from HTF bar open.
//+------------------------------------------------------------------+
datetime FindLTFWickBar(int idx,MqlRates &B[],int pSec,bool bull)
  {
   if(idx<0) return 0;
   int    ltfSec=(int)PeriodSeconds(LTF());
   int    need  =pSec/ltfSec;
   if(need<1) need=1;
   datetime htfOpen=(datetime)B[idx].time;
   datetime htfClose=(datetime)(htfOpen+pSec);

   MqlRates ltf[];
   int nl=CopyLTFWindowFromCache(htfOpen,htfClose,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),htfOpen,htfClose,ltf);
   if(nl<1)
     {
      // Pre-warm: request a block of LTF history containing this bar
      // then retry. SeriesInfoInteger ensures MT5 loads the data.
      SeriesInfoInteger(_Symbol,LTF(),SERIES_BARS_COUNT);
      nl=CopyLTFWindowFromCache(htfOpen,htfClose,ltf);
      if(nl<1)
         nl=CopyRates(_Symbol,LTF(),htfOpen,htfClose,ltf);
     }
   if(nl<1)
     {
      // Second fallback: count-based form anchored from htfClose backwards
      nl=CopyRates(_Symbol,LTF(),(datetime)(htfClose-1),need,ltf);
     }
   if(nl<1) return htfOpen; // genuine data unavailable — return HTF bar open

   double ex=bull?ltf[0].high:ltf[0].low; datetime et=ltf[0].time;
   for(int k=1;k<nl;k++)
     {
      if(bull&&ltf[k].high>ex){ex=ltf[k].high;et=ltf[k].time;}
      if(!bull&&ltf[k].low <ex){ex=ltf[k].low; et=ltf[k].time;}
     }
   return et;
  }

//+------------------------------------------------------------------+
// HTFBarEndOf — returns (bar.time + pSec - 1) for the bar owning t
//+------------------------------------------------------------------+
datetime HTFBarEndOf(MqlRates &B[],int n,int pSec,datetime t)
  {
   for(int k=n-1;k>=0;k--)
      if(B[k].time<=t&&t<(datetime)(B[k].time+pSec)) return B[k].time+pSec-1;
   // t is outside all known bars.
   // Cap at end of last known bar — prevents lines extending into weekend gaps.
   if(n>0&&t>=(datetime)(B[n-1].time+pSec)) return (datetime)(B[n-1].time+pSec-1);
   if(n>0&&t<B[0].time) return (datetime)(B[0].time+pSec-1);
   return (n>0)?(datetime)(B[n-1].time+pSec-1):t;
  }

//+------------------------------------------------------------------+
// GetBias — returns +1 (bull) or -1 (bear) from HTF bar array
//+------------------------------------------------------------------+
int GetBias(MqlRates &B[],int n)
  {
   for(int j=n-2;j>=1;j--)
     {
      double bHi=MathMax(B[j].open,B[j].close),bLo=MathMin(B[j].open,B[j].close);
      for(int i=0;i<j;i++)
        {
         double lev=B[i].high; bool vir=true;
         for(int k=i+1;k<j;k++)
            if(B[k].high>lev||MathMax(B[k].open,B[k].close)>=lev){vir=false;break;}
         if(vir&&bHi>=lev) return 1;
         lev=B[i].low; vir=true;
         for(int k=i+1;k<j;k++)
            if(B[k].low<lev||MathMin(B[k].open,B[k].close)<=lev){vir=false;break;}
         if(vir&&bLo<=lev) return -1;
        }
     }
   return 1;
  }

//+------------------------------------------------------------------+
// ClassifyClosed — returns bar index that first body-closed beyond
// wick at index i, -1 if touched without body close, -2 if virgin
//+------------------------------------------------------------------+
int ClassifyClosed(MqlRates &B[],int n,int i,bool bull)
  {
   double level=bull?B[i].high:B[i].low;
   for(int j=i+1;j<=n-2;j++)
     {
      if(bull){if(MathMax(B[j].open,B[j].close)>=level) return j; if(B[j].high>level) return -1;}
      else    {if(MathMin(B[j].open,B[j].close)<=level) return j; if(B[j].low <level) return -1;}
     }
   return -2;
  }

//+------------------------------------------------------------------+
// CheckCandidate — is the current HTF bar trading beyond the level?
//+------------------------------------------------------------------+
WICK_STATE CheckCandidate(double level,bool bull,datetime htfOpen)
  {
   MqlRates hf[]; if(CopyRates(_Symbol,HTF(),0,1,hf)<1) return WS_VIRGIN;
   if(bull&&hf[0].high<level)  return WS_VIRGIN;
   if(!bull&&hf[0].low >level) return WS_VIRGIN;
   return WS_CAND_ACTIVE;
  }

//+------------------------------------------------------------------+
// CandPillarVisible — 25%-segment gate for action pillar display
//+------------------------------------------------------------------+
bool CandPillarVisible(double level,bool bull,datetime htfOpen,int pSec)
  {
   int elapsed=(int)(TimeCurrent()-htfOpen); if(elapsed<0) return false;
   int q=(elapsed*4)/pSec; if(q>3)q=3; if(q==0) return true;
   datetime snapTime=htfOpen+(datetime)((long)q*pSec/4);
   MqlRates ltf[]; int nl=CopyRates(_Symbol,LTF(),htfOpen,snapTime,ltf);
   if(nl<1) return true;
   double rHi=MathMax(ltf[nl-1].open,ltf[nl-1].close);
   double rLo=MathMin(ltf[nl-1].open,ltf[nl-1].close);
   if(bull&&rHi>=level)  return true;
   if(!bull&&rLo<=level) return true;
   return false;
  }

//+------------------------------------------------------------------+
// FindCorrectionOrigin — locates and locks the CO price/time
//+------------------------------------------------------------------+
double FindCorrectionOrigin(MqlRates &B[],int n,int pSec,
                            double poiLevel,bool bull,int bb,
                            int nextSameGen,int nextCounterGen,
                            bool &coLocked,datetime &coTime,datetime &coEndTime)
  {
   coLocked=false; coTime=0; coEndTime=0;
   if(bb<0||bb>=n) return 0;
   datetime ltfLast=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   datetime nextSameTime=(nextSameGen>=0&&nextSameGen<n)?B[nextSameGen].time:0;
   datetime nextCtrTime =(nextCounterGen>=0&&nextCounterGen<n)?B[nextCounterGen].time:0;
   datetime evtCeil=ltfLast;
   if(nextSameTime>0)
     {
      datetime e=(datetime)(nextSameTime-1);
      if(e>B[bb].time && e<evtCeil) evtCeil=e;
     }
   if(nextCtrTime >0){datetime e=nextCtrTime +(datetime)pSec;if(e<evtCeil)evtCeil=e;}
   if(evtCeil<=B[bb].time) evtCeil=ltfLast;
   double priceTol=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(priceTol<=0.0)
      priceTol=_Point;
   if(priceTol<=0.0)
      priceTol=1e-8;
   double displayTol=(_Point>0.0)?(_Point*0.5):priceTol;

   double   extreme=bull?B[bb].high:B[bb].low;
   datetime extTime=B[bb].time;
   {
    MqlRates seed[];
    int ns=CopyLTFWindowFromCache(B[bb].time,(datetime)(B[bb].time+pSec),seed);
    if(ns<1)
       ns=CopyRates(_Symbol,LTF(),B[bb].time,(datetime)(B[bb].time+pSec),seed);
    for(int k=0;k<ns;k++)
      {
       double dispExtreme=NormalizeDouble(extreme,_Digits);
       if(bull)
         {
          if(seed[k].high>extreme+priceTol)
            {extreme=seed[k].high;extTime=seed[k].time;}
          else if((MathAbs(seed[k].high-extreme)<=priceTol
                   || MathAbs(NormalizeDouble(seed[k].high,_Digits)-dispExtreme)<=displayTol)
                  && seed[k].time>extTime)
            {extTime=seed[k].time;}
         }
       else
         {
          if(seed[k].low<extreme-priceTol)
            {extreme=seed[k].low; extTime=seed[k].time;}
          else if((MathAbs(seed[k].low-extreme)<=priceTol
                   || MathAbs(NormalizeDouble(seed[k].low,_Digits)-dispExtreme)<=displayTol)
                  && seed[k].time>extTime)
            {extTime=seed[k].time;}
         }
      }
   }
   MqlRates ltf[];
   int nl=CopyLTFWindowFromCache(B[bb].time,evtCeil,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),B[bb].time,evtCeil,ltf);
   if(nl<1)
     {
      coTime=extTime;
      coEndTime=HTFBarEndOf(B,n,pSec,extTime+(datetime)(pSec/4));
      return extreme;
     }
   datetime birthBarClose=B[bb].time+(datetime)pSec;
   for(int k=0;k<nl;k++)
     {
      double dispExtreme=NormalizeDouble(extreme,_Digits);
      if(bull)
        {
         if(ltf[k].high>extreme+priceTol)
           {extreme=ltf[k].high;extTime=ltf[k].time;}
         else if((MathAbs(ltf[k].high-extreme)<=priceTol
                  || MathAbs(NormalizeDouble(ltf[k].high,_Digits)-dispExtreme)<=displayTol)
                 && ltf[k].time>extTime)
           {extTime=ltf[k].time;}
        }
      else
        {
         if(ltf[k].low<extreme-priceTol)
           {extreme=ltf[k].low; extTime=ltf[k].time;}
         else if((MathAbs(ltf[k].low-extreme)<=priceTol
                  || MathAbs(NormalizeDouble(ltf[k].low,_Digits)-dispExtreme)<=displayTol)
                 && ltf[k].time>extTime)
           {extTime=ltf[k].time;}
        }
      if(ltf[k].time>=birthBarClose)
        {
         double bHi=MathMax(ltf[k].open,ltf[k].close);
         double bLo=MathMin(ltf[k].open,ltf[k].close);
         if(bull&&bLo<poiLevel)
           {coLocked=true;coTime=extTime;
            coEndTime=HTFBarEndOf(B,n,pSec,ltf[k].time);return extreme;}
         if(!bull&&bHi>poiLevel)
           {coLocked=true;coTime=extTime;
            coEndTime=HTFBarEndOf(B,n,pSec,ltf[k].time);return extreme;}
        }
     }
   coTime=extTime;
   bool ctrFirst=(nextCtrTime>0&&(nextSameTime==0||nextCtrTime<=nextSameTime));
   bool sameFirst=(nextSameTime>0&&!ctrFirst);
   if(sameFirst)
     {
      coLocked=true;
      coEndTime=(nextSameTime>B[bb].time)?(datetime)(nextSameTime-1):HTFBarEndOf(B,n,pSec,extTime);
      return extreme;
     }
   if(ctrFirst) {coLocked=true;coEndTime=HTFBarEndOf(B,n,pSec,extTime); return extreme;}
   coLocked=false;
   coEndTime=HTFBarEndOf(B,n,pSec,ltf[nl-1].time+(datetime)(pSec/4));
   return extreme;
  }

//+------------------------------------------------------------------+
// SortSiblings — shallowest-first (bull: desc price; bear: asc price)
//+------------------------------------------------------------------+
void SortSiblings(SibInfo &s[],int n,bool bull)
  {
   for(int i=1;i<n;i++)
     {
      SibInfo key=s[i]; int j=i-1;
      if(bull) {while(j>=0&&s[j].level<key.level){s[j+1]=s[j];j--;}}
      else     {while(j>=0&&s[j].level>key.level){s[j+1]=s[j];j--;}}
      s[j+1]=key;
     }
  }

//+------------------------------------------------------------------+
// RecomputeC3 — after retroactive invalidation, promote newest valid
// inversion to c3FvgIdx; mark all older valid inversions superseded.
//+------------------------------------------------------------------+
void RecomputeC3(FVGInfo &fvgs[],int nFvgs,
                 bool &activeC3,datetime &activeC3Time,int &c3FvgIdx)
  {
   activeC3=false; activeC3Time=0; c3FvgIdx=-1;
   for(int f=nFvgs-1;f>=0;f--)
     {
      if(!fvgs[f].inverted||fvgs[f].invalidInv||fvgs[f].stale) continue;
      if(!activeC3)
        {fvgs[f].superseded=false;activeC3=true;activeC3Time=fvgs[f].invTime;c3FvgIdx=f;}
      else
        fvgs[f].superseded=true;
     }
  }

//+------------------------------------------------------------------+
// ScanGeneration — chronological LTF pass from coTime.
//
// New parameters vs Phase 1:
//   pSec          — HTF bar period in seconds, needed for bias-flip
//                   same-bar invalidation check.
//   lockAfterTime — if >0, any C1-level activation at or after this
//                   time is killed (one-execution-per-window gate:
//                   a newer same-bias generation already triggered).
//
// Bias flip same-bar rule:
//   If the trigger fires on the final LTF bar of the counter-bias HTF
//   birth bar (i.e., triggerTime >= ctrBiasFrom+pSec-ltfSec AND
//   triggerTime < ctrBiasFrom+pSec), the trigger is INVALID — that
//   exact LTF close simultaneously confirms the HTF counter-bias POI.
//+------------------------------------------------------------------+
void ScanGeneration(datetime coTime,double coPrice,bool bull,
                    SibInfo &sibs[],int nSibs,datetime scanEnd,
                    datetime pillarOpen,datetime ctrBiasFrom,
                    datetime supersedeAfterTime,datetime lockAfterTime,int pSec,
                    datetime minActivateTime,datetime maxActivateTime,
                    datetime nextSameTime,
                    FVGInfo &fvgs[],int &nFvgs,
                    int &c3FvgIdx,datetime &triggerTime,bool &coVisible)
  {
   nFvgs=0; c3FvgIdx=-1; triggerTime=0; coVisible=false;
   ArrayResize(fvgs,0);
   for(int s=0;s<nSibs;s++)
     {sibs[s].state=SS_INACTIVE;sibs[s].c1Time=sibs[s].c2Time=sibs[s].c3Time=0;
      sibs[s].tsLevel=0.0;sibs[s].tsWickTime=0;sibs[s].tsTouchTime=0;sibs[s].tsTouchedBeforeC1=false;}
   bool hasValidCO=(coTime>0 && coPrice>0.0);
   datetime scanStart=hasValidCO?coTime:pillarOpen;
   if(scanEnd<=scanStart) return;
   MqlRates ltf[];
   int nl=CopyLTFWindowFromCache(scanStart,scanEnd,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),scanStart,scanEnd,ltf);
   if(nl<1) return;

   int      activeSibIdx=-1;
   datetime activeC1Time=0;
   bool     activeC2=false;  datetime activeC2Time=0;
   bool     activeC3=false;  datetime activeC3Time=0;
   int      ltfSec=(int)PeriodSeconds(LTF());

   for(int k=0;k<nl;k++)
     {
      double cls=ltf[k].close;

      //=== Steps 1 & 2 — completed bars only ===
      if(k<nl-1)
        {
         //--- Step 1: FVG inversions ---
         // When multiple FVGs are inverted by the same bar close, the winner is
         // the one whose C1 level is closest to the close price (tightest gap).
         // Only if that gap ties do we keep the earliest-formed one.
         // Pass A: mark all newly inverted FVGs, record their indices.
         for(int f=0;f<nFvgs;f++)
           {
            if(fvgs[f].inverted) continue;
            bool inv=(bull&&cls>=fvgs[f].c1Ext)||(!bull&&cls<=fvgs[f].c1Ext);
            if(!inv) continue;
            fvgs[f].inverted  =true;
            fvgs[f].invTime   =ltf[k].time;
            fvgs[f].stale     =((int)(ltf[k].time-fvgs[f].t1)>5400);
            fvgs[f].invalidInv=(activeC1Time==0
                               ||ltf[k].time<=activeC1Time
                               ||ltf[k].time<pillarOpen);
            fvgs[f].superseded=false;
           }
         // Pass B: among FVGs inverted THIS bar, promote only the valid owner whose
         // C1 opening is tightest to the closing price. On ties, keep the earliest-
         // formed box. Intrabar "nearest-two" logic is provisional only; once the bar
         // closes there is one confirmed owner and same-close losers are dead.
         {
          int latestValid=-1;
          double bestGap=DBL_MAX;
          for(int f=0;f<nFvgs;f++)
            {
             if(!fvgs[f].inverted||fvgs[f].invTime!=ltf[k].time) continue;
             if(fvgs[f].invalidInv||fvgs[f].stale) continue;
             double gap=MathAbs(cls-fvgs[f].c1Ext);
             bool better=(latestValid<0
                          || gap<bestGap
                          || (MathAbs(gap-bestGap)<=_Point
                              && fvgs[f].t1<fvgs[latestValid].t1));
             if(better)
               {
                latestValid=f;
                bestGap=gap;
               }
            }
          if(latestValid>=0)
            {
             for(int f=0;f<nFvgs;f++)
               {
                if(!fvgs[f].inverted||fvgs[f].invTime!=ltf[k].time) continue;
                if(f==latestValid)
                  {
                   fvgs[f].invalidInv=false;
                   fvgs[f].superseded=false;
                   continue;
                  }
                fvgs[f].inverted=false;
                fvgs[f].invalidInv=true;
                fvgs[f].superseded=true;
                fvgs[f].stale=true;
               }
             if(c3FvgIdx>=0) fvgs[c3FvgIdx].superseded=true;
             c3FvgIdx=latestValid;
             activeC3=true; activeC3Time=ltf[k].time;
            }
         }
         //--- Step 2: new FVG detection — open until trigger fires ---
         if(k>=2)
           {
            bool ok=false; FVGInfo fi;
            fi.inverted=false;fi.invTime=0;fi.stale=false;
            fi.invalidInv=false;fi.superseded=false;
            fi.preC1Formed=(activeC1Time==0);
            if(bull&&ltf[k].high<ltf[k-2].low)
              {
               fi.t1=ltf[k-2].time;fi.t3=ltf[k].time;
               fi.c1Ext=ltf[k-2].low;fi.c3Ext=ltf[k].high;
               fi.c2c3Extreme=MathMin(ltf[k-1].low,ltf[k].low);
               fi.clusterExtreme=MathMax(ltf[k-2].high,MathMax(ltf[k-1].high,ltf[k].high));
               ok=true;
              }
            else if(!bull&&ltf[k].low>ltf[k-2].high)
              {
               fi.t1=ltf[k-2].time;fi.t3=ltf[k].time;
               fi.c1Ext=ltf[k-2].high;fi.c3Ext=ltf[k].low;
               fi.c2c3Extreme=MathMax(ltf[k-1].high,ltf[k].high);
               fi.clusterExtreme=MathMin(ltf[k-2].low,MathMin(ltf[k-1].low,ltf[k].low));
               ok=true;
              }
            if(ok)
              {
               bool dup=false;
               for(int f=0;f<nFvgs;f++)
                  if(fvgs[f].t1==fi.t1&&fvgs[f].t3==fi.t3){dup=true;break;}
               if(!dup){ArrayResize(fvgs,nFvgs+1);fvgs[nFvgs++]=fi;}
              }
           }
        } // end completed-bars-only block

      //=== Step 3a: Supersession → C2 → Trigger ===
      // Supersession runs first: a bar closing through multiple sibling
      // levels promotes the deepest before C2/trigger are evaluated.
      if(k<nl-1&&activeSibIdx>=0&&sibs[activeSibIdx].state==SS_ACTIVE)
        {
         if(supersedeAfterTime>0 && ltf[k].time>=supersedeAfterTime)
           {
            for(int s=0;s<nSibs;s++)
              {
               if(sibs[s].state==SS_TRIGGERED
                  || sibs[s].state==SS_TP_HIT
                  || sibs[s].state==SS_SL_HIT
                  || sibs[s].state==SS_BE_HIT
                  || sibs[s].state==SS_DORMANT_CTR)
                  continue;
               if(sibs[s].state==SS_INACTIVE
                  || sibs[s].state==SS_ACTIVE
                  || sibs[s].state==SS_DORMANT)
                 {
                  sibs[s].state=SS_KILLED_SUPER;
                  sibs[s].c1Time=(s==activeSibIdx && activeC1Time>0)?activeC1Time:ltf[k].time;
                 }
              }
            if(Inp_ShowDebug)
               PrintFormat("[CCT DBG] ACTIVE SUPER KILL level=%.5f c1=%s superAfter=%s",
                           sibs[activeSibIdx].level,
                           TimeToString((activeC1Time>0)?activeC1Time:ltf[k].time,TIME_MINUTES),
                           TimeToString(supersedeAfterTime,TIME_MINUTES));
            activeSibIdx=-1;
            activeC1Time=0;
            activeC2=false; activeC2Time=0;
            activeC3=false; activeC3Time=0;
            c3FvgIdx=-1;
            coVisible=false;
            break;
           }
         if(lockAfterTime>0 && ltf[k].time>=lockAfterTime)
           {
            for(int s=0;s<nSibs;s++)
              {
               if(sibs[s].state==SS_TRIGGERED
                  || sibs[s].state==SS_TP_HIT
                  || sibs[s].state==SS_SL_HIT
                  || sibs[s].state==SS_BE_HIT
                  || sibs[s].state==SS_DORMANT_CTR)
                  continue;
               if(sibs[s].state==SS_INACTIVE
                  || sibs[s].state==SS_ACTIVE
                  || sibs[s].state==SS_DORMANT)
                 {
                  sibs[s].state=SS_KILLED_WINDOW;
                  sibs[s].c1Time=(s==activeSibIdx && activeC1Time>0)?activeC1Time:ltf[k].time;
                 }
              }
            if(Inp_ShowDebug)
               PrintFormat("[CCT DBG] ACTIVE WINDOW KILL level=%.5f c1=%s lockAfter=%s",
                           sibs[activeSibIdx].level,
                           TimeToString((activeC1Time>0)?activeC1Time:ltf[k].time,TIME_MINUTES),
                           TimeToString(lockAfterTime,TIME_MINUTES));
            activeSibIdx=-1;
            activeC1Time=0;
            activeC2=false; activeC2Time=0;
            activeC3=false; activeC3Time=0;
            c3FvgIdx=-1;
            coVisible=false;
            break;
           }

         // Bias flip death: active C1 sequence killed when structural bias flip bar closes.
         // Rule: C1 achieved but C2/C3 not yet confirmed before bias flips = brutal termination.
         if(ctrBiasFrom>0 && ltf[k].time>=ctrBiasFrom)
           {
            sibs[activeSibIdx].state=SS_KILLED_CO;
            sibs[activeSibIdx].c1Time=activeC1Time;
            activeSibIdx=-1; activeC1Time=0;
            activeC2=false;  activeC2Time=0;
            activeC3=false;  activeC3Time=0; c3FvgIdx=-1;
            coVisible=false;
            if(Inp_ShowDebug)
               PrintFormat("[CCT DBG] BIAS FLIP DEATH C1 killed genKey bias flip at %s",
                           TimeToString(ltf[k].time,TIME_MINUTES));
            break;
           }

         //--- Supersession ---
         int deepest=-1;
         for(int s=activeSibIdx+1;s<nSibs;s++)
           {
            if(sibs[s].state!=SS_INACTIVE) continue;
            bool crossed=(bull&&cls<sibs[s].level)||(!bull&&cls>sibs[s].level);
            if(crossed) deepest=s;
           }
         if(deepest>=0)
           {
            for(int s=0;s<deepest;s++)
              {
               if(sibs[s].state==SS_TRIGGERED
                  || sibs[s].state==SS_TP_HIT
                  || sibs[s].state==SS_SL_HIT
                  || sibs[s].state==SS_BE_HIT)
                  continue;
               if(sibs[s].state==SS_INACTIVE
                  || sibs[s].state==SS_ACTIVE
                  || sibs[s].state==SS_DORMANT)
                 {
                  sibs[s].state=SS_KILLED_SUPER;
                  sibs[s].c1Time=(s==activeSibIdx && activeC1Time>0)?activeC1Time:ltf[k].time;
                 }
              }
            activeSibIdx=deepest;
            sibs[activeSibIdx].state=SS_ACTIVE;
            sibs[activeSibIdx].c1Time=ltf[k].time;
            activeC1Time=ltf[k].time;
            activeC2=false; activeC2Time=0;
            for(int f=0;f<nFvgs;f++)
               if(fvgs[f].inverted&&fvgs[f].invTime<=activeC1Time)
                 {fvgs[f].invalidInv=true;fvgs[f].superseded=false;}
            for(int f=0;f<nFvgs;f++)
               if(fvgs[f].preC1Formed&&fvgs[f].t1>=activeC1Time)
                  fvgs[f].preC1Formed=false;
            RecomputeC3(fvgs,nFvgs,activeC3,activeC3Time,c3FvgIdx);
            coVisible=true;
           }
         //--- C2 (Reclaim) — re-read actLvl after possible supersession ---
         double actLvl=sibs[activeSibIdx].level;
         if(activeC1Time>0)
           {
            bool reclaim=(bull&&cls>=actLvl)||(!bull&&cls<=actLvl);
            bool lapsed =(bull&&cls< actLvl)||(!bull&&cls> actLvl);
            if(reclaim&&!activeC2){activeC2=true; activeC2Time=ltf[k].time;}
            if(lapsed &&activeC2) {activeC2=false;activeC2Time=0;}
           }
         //--- Trigger ---
         if(activeC1Time>0&&activeC2&&activeC3&&triggerTime==0)
           {
            // Same-bar bias flip check:
            // If ctrBiasFrom>0, check whether this LTF bar is the FINAL bar
            // of the counter-bias HTF birth bar. If so the trigger is invalid —
            // the same close that triggers also constitutes the HTF bias flip.
            bool biasFlipSameBar=false;
            if(ctrBiasFrom>0&&pSec>0&&ltfSec>0)
              {
               datetime ctrFinalLTF=ctrBiasFrom+(datetime)(pSec-ltfSec);
               biasFlipSameBar=(ltf[k].time>=ctrFinalLTF
                               &&ltf[k].time<ctrBiasFrom+(datetime)pSec);
              }
            if(biasFlipSameBar)
              {
               // Trigger invalidated: simultaneous HTF counter-bias close
               sibs[activeSibIdx].state=SS_KILLED_CO;
               sibs[activeSibIdx].c1Time=activeC1Time;
               activeSibIdx=-1; activeC1Time=0;
               activeC2=false;  activeC2Time=0;
               activeC3=false;  activeC3Time=0; c3FvgIdx=-1;
               coVisible=false;
               break;
              }
            sibs[activeSibIdx].state=SS_TRIGGERED;
            sibs[activeSibIdx].c1Time=activeC1Time;
            sibs[activeSibIdx].c2Time=activeC2Time;
            sibs[activeSibIdx].c3Time=activeC3Time;
            triggerTime=ltf[k].time;
            coVisible=false;
            // Trigger consumes the generation's execution window. Any other still-
            // inactive sibling in this generation is dead immediately.
            for(int s=0;s<nSibs;s++)
              {
               if(s==activeSibIdx) continue;
               if(sibs[s].state==SS_TRIGGERED
                  || sibs[s].state==SS_TP_HIT
                  || sibs[s].state==SS_SL_HIT
                  || sibs[s].state==SS_BE_HIT)
                  continue;
               if(sibs[s].state==SS_INACTIVE)
                 {
                  sibs[s].state=SS_KILLED_SIB;
                  if(sibs[s].c1Time<=0)
                     sibs[s].c1Time=triggerTime;
                 }
              }
            if(Inp_ShowDebug)
               PrintFormat("[CCT DBG] WINDOW CONSUMED gen trigger=%s deeper siblings killed",
                           TimeToString(triggerTime,TIME_MINUTES));
            break;
           }
        }

      //=== Step 3b: CO kill ===
      // CO touch can invalidate an active sibling, but it must not kill a bar
      // that already completed the trigger on that same candle.
      if(triggerTime==0
         && hasValidCO
         && activeSibIdx>=0&&sibs[activeSibIdx].state==SS_ACTIVE
         && activeC1Time>0&&!(activeC2&&activeC3))
        {
         bool coHit=(bull&&ltf[k].high>=coPrice)||(!bull&&ltf[k].low<=coPrice);
         if(coHit)
           {
            sibs[activeSibIdx].state=SS_KILLED_CO;
            sibs[activeSibIdx].c1Time=activeC1Time;
            activeSibIdx=-1; activeC1Time=0;
            activeC2=false;  activeC2Time=0;
            activeC3=false;  activeC3Time=0; c3FvgIdx=-1;
            coVisible=false;
           }
        }

      //=== Step 4: C1 detection (pillarOpen gate) ===
      // FIX: C1 requires CLOSE beyond POI, not just wick touch
      if(activeSibIdx<0&&ltf[k].time>=pillarOpen)
        {
         if(supersedeAfterTime>0 && ltf[k].time>=supersedeAfterTime)
           {
            for(int s=0;s<nSibs;s++)
              {
               if(sibs[s].state==SS_INACTIVE || sibs[s].state==SS_DORMANT)
                 {
                  sibs[s].state=SS_KILLED_SUPER;
                  sibs[s].c1Time=ltf[k].time;
                 }
              }
            break;
           }
         if(lockAfterTime>0 && ltf[k].time>=lockAfterTime)
           {
            for(int s=0;s<nSibs;s++)
              {
               if(sibs[s].state==SS_INACTIVE || sibs[s].state==SS_DORMANT)
                 {
                  sibs[s].state=SS_KILLED_WINDOW;
                  sibs[s].c1Time=ltf[k].time;
                 }
              }
            break;
           }
         int deepest=-1;
         for(int s=0;s<nSibs;s++)
           {
            if(sibs[s].state!=SS_INACTIVE) continue;
            // FIX: Use CLOSE (cls) not wick for C1 activation
            bool crossed=(bull&&cls<sibs[s].level)||(!bull&&cls>sibs[s].level);
            if(crossed) deepest=s;
           }
          if(deepest>=0)
            {
             for(int s=0;s<deepest;s++)
                if(sibs[s].state==SS_INACTIVE)
                  {
                   // FIX: Use CLOSE (cls) not wick for supersession kill
                   bool cr2=(bull&&cls<sibs[s].level)||(!bull&&cls>sibs[s].level);
                   if(cr2){sibs[s].state=SS_KILLED_SUPER;sibs[s].c1Time=ltf[k].time;}
                  }
            activeSibIdx=deepest;
            // Counter-bias time gate: bias flipped before this sib could activate.
            // Mark as SS_DORMANT_CTR — invisible, silently killed if price tries to
            // activate while still counter-bias. All remaining INACTIVE sibs follow.
            // (SS_KILLED_CO reserved for sibs that were actively mid-C1 when killed.)
            if(ctrBiasFrom>0&&ltf[k].time>=ctrBiasFrom)
              {
               sibs[activeSibIdx].state=SS_DORMANT_CTR;
               sibs[activeSibIdx].c1Time=0;
               activeSibIdx=-1;
               for(int sc=0;sc<nSibs;sc++)
                  if(sibs[sc].state==SS_INACTIVE) sibs[sc].state=SS_DORMANT_CTR;
               break;
              }
            // Min HTF bars gate: activation before minimum window → kill
            // minActivateTime=0 means no minimum constraint (e.g. dormant exempt)
            if(minActivateTime>0&&ltf[k].time<minActivateTime)
              {
               sibs[activeSibIdx].state=SS_KILLED_MIN;
               sibs[activeSibIdx].c1Time=ltf[k].time;
               activeSibIdx=-1;
               continue;  // keep scanning — later bars may satisfy min
              }
            // Max HTF bars gate: activation after maximum window → kill, stop scanning
            // maxActivateTime=0 means no maximum constraint (dormant POIs)
            if(maxActivateTime>0&&ltf[k].time>=maxActivateTime)
              {
               sibs[activeSibIdx].state=SS_KILLED_CO;
               sibs[activeSibIdx].c1Time=ltf[k].time;
               activeSibIdx=-1;
               break;  // no bar after this can be valid either
              }
            // One-execution-per-window gate
            if(lockAfterTime>0&&ltf[k].time>=lockAfterTime)
              {
               sibs[activeSibIdx].state=SS_KILLED_WINDOW;
               sibs[activeSibIdx].c1Time=ltf[k].time;
               if(Inp_ShowDebug)
                  PrintFormat("[CCT DBG] WINDOW KILL level=%.5f c1=%s lockAfter=%s",
                              sibs[activeSibIdx].level,
                              TimeToString(ltf[k].time,TIME_MINUTES),
                              TimeToString(lockAfterTime,TIME_MINUTES));
               activeSibIdx=-1;
               continue;
              }
            sibs[activeSibIdx].state=SS_ACTIVE;
            sibs[activeSibIdx].c1Time=ltf[k].time;
            activeC1Time=ltf[k].time;
            activeC2=false; activeC2Time=0;
            activeC3=false; activeC3Time=0; c3FvgIdx=-1;
            coVisible=true;
           }
        }
     } // end bar loop

   // Persist live state for the currently active (forming) bar
   if(activeSibIdx>=0&&sibs[activeSibIdx].state==SS_ACTIVE)
     {
      sibs[activeSibIdx].c1Time=activeC1Time;
      sibs[activeSibIdx].c2Time=activeC2?activeC2Time:0;
      sibs[activeSibIdx].c3Time=activeC3?activeC3Time:0;
     }

   // Post-loop: once a trigger fires, any same-generation sibling that somehow
   // remained unresolved and inactive must still be killed. Dormant generations
   // are handled by window-consumption rules when they later try to activate.
   if(triggerTime>0)
     {
      for(int s=0;s<nSibs;s++)
        {
         if(sibs[s].state==SS_INACTIVE)
           {
            sibs[s].state=SS_KILLED_SIB;
            if(sibs[s].c1Time<=0)
               sibs[s].c1Time=triggerTime;
           }
        }
     }

   // Post-loop dormant normalization belongs to scanner ownership. Once a newer
   // same-bias generation has been born and this generation never triggered,
   // any still-valid unresolved in-bias sibling is no longer the current valid
   // POI and must surface as DORMANT for downstream reveal logic.
   if(triggerTime==0&&nextSameTime>0)
     {
      datetime ltfLast2=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
      bool pastSame=(ltfLast2>=nextSameTime);
      bool dormantEligible=(minActivateTime>0 && nextSameTime<minActivateTime);
      if(pastSame)
        {
         for(int s=0;s<nSibs;s++)
           {
            if(sibs[s].state==SS_INACTIVE)
               sibs[s].state=dormantEligible?SS_DORMANT:SS_KILLED_WINDOW;
           }
        }
     }

   // Post-trigger same-generation cleanup: enforce the same rule again after all
   // scanner passes. Only still-inactive siblings of the triggered generation are
   // killed as SS_KILLED_SIB here.
   if(triggerTime>0)
     {
      for(int s=0;s<nSibs;s++)
        {
         if(sibs[s].state==SS_TRIGGERED
            || sibs[s].state==SS_TP_HIT
            || sibs[s].state==SS_SL_HIT
            || sibs[s].state==SS_BE_HIT
            || sibs[s].state==SS_KILLED_CO
            || sibs[s].state==SS_KILLED_WINDOW
            || sibs[s].state==SS_KILLED_SIB
            || sibs[s].state==SS_KILLED_SUPER
            || sibs[s].state==SS_KILLED_MIN)
            continue;
         if(sibs[s].state==SS_INACTIVE)
           {
            sibs[s].state=SS_KILLED_SIB;
            if(sibs[s].c1Time<=0)
               sibs[s].c1Time=triggerTime;
           }
        }
     }

   // Post-loop: convert SS_DORMANT sibs to SS_DORMANT_CTR if bias has flipped.
   // SS_DORMANT sibs are set when a trigger fires — but if ctrBiasFrom is
   // reached after the trigger, those sibs are still drawn as in-bias dormant.
   // They should be invisible (counter-bias dormant) once bias flips.
   // Also convert any remaining SS_INACTIVE sibs that are past ctrBiasFrom.
   if(ctrBiasFrom>0)
     {
      // Check if the scan window actually reached ctrBiasFrom
      datetime ltfLast2=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
      bool pastCtr=(ltfLast2>=ctrBiasFrom);
      if(pastCtr)
        {
         for(int s=0;s<nSibs;s++)
           {
            if(sibs[s].state==SS_DORMANT||sibs[s].state==SS_INACTIVE)
               sibs[s].state=SS_DORMANT_CTR;
           }
        }
     }
  }

//+------------------------------------------------------------------+
// ScanCOReach — second pass after trigger.
// Returns the LTF bar open time when price first touched coPrice
// after triggerTime, or 0 if not yet reached.
//+------------------------------------------------------------------+
datetime ScanCOReach(datetime fromTime,double coPrice,bool bull)
  {
   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   if(fromTime>=scanEnd) return 0;
   MqlRates ltf[]; int nl=CopyRates(_Symbol,LTF(),fromTime,scanEnd+1,ltf); // include live bar
   if(nl<1) return 0;
   for(int k=0;k<nl;k++)
     {
      bool hit=(bull&&ltf[k].high>=coPrice)||(!bull&&ltf[k].low<=coPrice);
      if(hit) return ltf[k].time;
     }
   return 0;
  }

//+------------------------------------------------------------------+
// ScanHit — returns the LTF bar open time when price touched px
//+------------------------------------------------------------------+
datetime ScanHit(datetime fromTime,double px,bool lookForLow)
  {
   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   if(fromTime>=scanEnd) return 0;
   MqlRates ltf[];
   int nl=CopyLTFWindowFromCache(fromTime,scanEnd+1,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),fromTime,scanEnd+1,ltf); // include live bar
   if(nl<1) return 0;
   for(int k=0;k<nl;k++)
     {
      bool hit=lookForLow?(ltf[k].low<=px):(ltf[k].high>=px);
      if(hit) return ltf[k].time;
     }
   return 0;
  }

//+------------------------------------------------------------------+
// FindTSLevel — finds the Turtle Soup virgin wick level for an active POI.
//
// TS wick selection rules (fully corrected):
//   Bull POI → bearish virgin wick LOWs (B[i].low). Can be above OR below POI level.
//   Bear POI → bullish virgin wick HIGHs (B[i].high). Can be above OR below POI level.
//   No side filter — nearest in price to POI level is the only selection criterion.
//   Only the relevant side needs to be virgin (low for bull, high for bear).
//
// Scan window: startBar → c1BarIdx (exclusive).
//   startBar = nextSameBar if a newer same-bias generation exists between bb and C1,
//              otherwise bb itself. This gives the oldest newer generation's birth bar,
//              which is the correct TS window start for dormant POI setups.
//
// Touch detection:
//   Scans LTF from generation birth (B[bb].time) through scanEnd for first wick touch.
//   If touch happened before C1: tsTouchedBeforeC1=true, no glow needed.
//   If touch happened at/after C1: tsTouchedBeforeC1=false, glow applies.
//   The TS line only draws after BOTH C1 AND first touch have occurred.
//+------------------------------------------------------------------+
void FindTSLevel(MqlRates &B[],int n,int pSec,bool bull,
                 int bb,int nextSameBar,datetime c1Time,
                 double poiLevel,
                 double &tsLevel,datetime &tsWickTime,
                 datetime &tsTouchTime,bool &tsTouchedBeforeC1,
                 int biasRegimeStartBar=0) // 0 = use default window
  {
   tsLevel=0.0; tsWickTime=0; tsTouchTime=0; tsTouchedBeforeC1=false;
   if(bb<0||bb>=n||c1Time==0) return;

   // Find c1Bar HTF index
   int c1BarIdx=-1;
   for(int k=n-1;k>=0;k--)
      if(B[k].time<=c1Time){c1BarIdx=k;break;}
   if(c1BarIdx<0) return;

   // TS prerequisite: skip if fewer intermediate HTF bars than the trade mode requires.
   // Derive the required minimum from the birth bar's trade window.
   int tsMinBars=0;
   TradeWindowResult birthWindow;
   if(ResolveBirthTradeWindowCurrentModel(B[bb].time,birthWindow))
      tsMinBars=birthWindow.minHTF;
   if(c1BarIdx - bb <= tsMinBars) return;

   // Determine startBar and scanEnd:
   //   Normal (biasRegimeStartBar=0): startBar = nextSameBar or bb.
   //     Scan from startBar to c1BarIdx-1 (exclusive of C1 bar).
   //   Expanding (biasRegimeStartBar>0): called during active sweep —
   //     startBar = biasRegimeStartBar (bias regime start, no left boundary).
   //     scanEnd = current LTF bar (price may have gone past original c1BarIdx).
   //     Selection changes from "nearest" to "deepest available".
   int startBar;
   int scanEnd;
   bool expanding=(biasRegimeStartBar>0);
   if(expanding)
     {
      startBar=biasRegimeStartBar;
      scanEnd =n;  // scan all loaded bars — virgin check filters non-virgins
     }
   else
     {
      startBar=bb;
      if(nextSameBar>=0&&nextSameBar<n&&nextSameBar>bb&&nextSameBar<c1BarIdx)
         startBar=nextSameBar;
      scanEnd=c1BarIdx;  // exclusive of C1 bar
     }

   // Scan HTF bars startBar → scanEnd.
   // startBar defaults to bb — birth bar's own extreme is a valid TS candidate.
   // If a newer same-bias gen exists between bb and C1, startBar = that gen's bar.
   // C1 bar excluded — its wick forms during activation, not a prior virgin wick.
   // Bull POI: bearish LOW. Bear POI: bullish HIGH. No side filter.
   // Normal: select nearest in price to POI level.
   // Expanding: select deepest available (most extreme in sweep direction).
   double bestLevel=0.0; double bestDist=DBL_MAX; datetime bestTime=0;
   for(int i=startBar;i<scanEnd;i++)
     {
      double wickLevel=bull?B[i].low:B[i].high;
      if(wickLevel<=0.0) continue;

      // Virginity check — only the relevant side needs to be virgin.
      // Always check up to c1BarIdx (the activation bar), not scanEnd.
      bool virgin=true;
      int virEnd=MathMin(c1BarIdx,n-1);
      for(int k=i+1;k<virEnd;k++)
        {
         if(bull)  // bearish low — stripped by body close at or below wickLevel
           {if(MathMin(B[k].open,B[k].close)<=wickLevel){virgin=false;break;}}
         else      // bullish high — stripped by body close at or above wickLevel
           {if(MathMax(B[k].open,B[k].close)>=wickLevel){virgin=false;break;}}
        }
      if(!virgin) continue;

      // Selection criterion:
      //   Normal: nearest in price to the active POI level.
      //   Expanding (sweeping): deepest available
      //     (most extreme: lowest low for bull, highest high for bear).
      bool betterCandidate;
      if(expanding)
         betterCandidate=(bestLevel==0.0)
                        ||(bull&&wickLevel<bestLevel)
                        ||(!bull&&wickLevel>bestLevel);
      else
        {
         double dist=MathAbs(wickLevel-poiLevel);
         betterCandidate=(dist<bestDist);
         if(betterCandidate) bestDist=dist;
        }
      if(betterCandidate)
        {
         bestLevel=wickLevel;
         // Left anchor: LTF bar of the fractal extreme on the relevant side
         bestTime=FindLTFWickBar(i,B,pSec,!bull);
        }
     }

   if(bestLevel==0.0||bestTime==0) return;
   tsLevel  =bestLevel;
   tsWickTime=bestTime;

   // Find first LTF wick touch — start scan from the bar AFTER the wick-making LTF bar.
   // Starting from B[bb].time risks finding a bar earlier than tsWickTime within the
   // same HTF bar, which draws the line backwards. The touch must be strictly after
   // the bar that made the wick extreme.
   datetime touchScanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   int ltfSecTouch=(int)PeriodSeconds(LTF());
   datetime touchScanStart=(datetime)(tsWickTime+ltfSecTouch); // strictly after wick bar
   MqlRates ltf[];
   int nl=CopyLTFWindowFromCache(touchScanStart,touchScanEnd,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),touchScanStart,touchScanEnd,ltf);
   for(int k=0;k<nl;k++)
     {
      bool touched=bull?(ltf[k].low<=tsLevel):(ltf[k].high>=tsLevel);
      if(!touched) continue;
      tsTouchTime=ltf[k].time;
      // If the touch bar is before the C1 bar opened, touch preceded C1
      tsTouchedBeforeC1=(ltf[k].time<c1Time);
      break;
     }
   // tsTouchTime=0: not yet touched (line not drawn yet)
  }

//+------------------------------------------------------------------+
// BuildBirthLists — classifies all HTF wicks and builds birth arrays
//+------------------------------------------------------------------+
void BuildBirthLists(MqlRates &B[],int n,
                     int &bullBirths[],int &bearBirths[],int &nBull,int &nBear,
                     int &mapBull[],int &mapBear[])
  {
   nBull=0;nBear=0;
   ArrayResize(bullBirths,n);ArrayResize(bearBirths,n);
   ArrayResize(mapBull,n);  ArrayResize(mapBear,n);
   for(int i=0;i<n;i++){mapBull[i]=-3;mapBear[i]=-3;}
   bool bsB[],bsE[];
   ArrayResize(bsB,n);ArrayResize(bsE,n);
   ArrayInitialize(bsB,false);ArrayInitialize(bsE,false);
   for(int i=0;i<n-1;i++)
     {
      int bb=ClassifyClosed(B,n,i,true); mapBull[i]=bb;
      int be=ClassifyClosed(B,n,i,false);mapBear[i]=be;
      if(bb>=0&&!bsB[bb]){bsB[bb]=true;bullBirths[nBull++]=bb;}
      if(be>=0&&!bsE[be]){bsE[be]=true;bearBirths[nBear++]=be;}
     }
   mapBull[n-1]=mapBear[n-1]=-1;
  }

//+------------------------------------------------------------------+
// NextGenBirth — first birth bar index strictly after afterBar
//+------------------------------------------------------------------+
int NextGenBirth(int &births[],int cnt,int afterBar)
  {for(int x=0;x<cnt;x++) if(births[x]>afterBar) return births[x]; return -1;}

//+------------------------------------------------------------------+
// SiblingCount — number of virgin wicks subsumed by birth bar bb
//+------------------------------------------------------------------+
int SiblingCount(MqlRates &B[],int n,int bb,bool bull)
  {
   int cnt=0;
   for(int i=0;i<n-1;i++)
      if(ClassifyClosed(B,n,i,bull)==bb)
         cnt++;
   return cnt;
  }


#endif // CCT_SCANNER_MQH
