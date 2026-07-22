#property strict

#include "CCT_Globals.mqh"
#include "CCT_Scanner.mqh"
#include "CCT_Notify.mqh"
#include "CCT_Execution.mqh"
#include "CCT_Visual.mqh"
#include "CCT_Dashboard.mqh"

MqlRates g_htf[];
int      g_nHtf=0;
int      g_bullBirths[];
int      g_nBull=0;
int      g_bearBirths[];
int      g_nBear=0;

GenInfo  g_nvReplayGens[50];
int      g_nvReplayCount=0;
GenInfo  g_nvReplayCounterGens[50];
int      g_nvReplayCounterCount=0;
datetime g_nvReplayTime=0;
string   g_nvReplayKey="";
string   g_lastInitSymbol="";
bool     g_visualPendingInitialDraw=false;
uint     g_visualInitMs=0;
bool     g_visualPendingHistoricalReconcile=false;
uint     g_visualHistoricalReconcileMs=0;
bool     g_htfCacheReady=false;
datetime g_htfCacheLastBar=0;
int      g_htfCacheBars=0;
string   g_htfCacheKey="";

ulong    g_perfNvRefreshCalls=0;
ulong    g_perfNvThrottleSkips=0;
ulong    g_perfNvScheduleSkips=0;
ulong    g_perfNvCachedSkips=0;
ulong    g_perfNvFullReplays=0;
ulong    g_perfNvReplayMicros=0;
ulong    g_perfNvMaxReplayMicros=0;

/*
Purpose: Clear cached HTF scanner inputs when the chart context changes.
Constitution: Live execution must not reload years of HTF history every M1 close, but symbol/timeframe changes need fresh scanner truth.
Inputs: None.
Outputs: Cached HTF rates/birth lists marked stale.
*/
void CCTResetHTFScannerCache()
  {
   g_htfCacheReady=false;
   g_htfCacheLastBar=0;
   g_htfCacheBars=0;
   g_htfCacheKey="";
   g_nHtf=0;
   g_nBull=0;
   g_nBear=0;
  }

/*
Purpose: Load or reuse the multi-year HTF scanner state used for birth and virgin-wick truth.
Constitution: The 3-year lookback remains intact, but live/timer passes must reuse it until a new HTF bar or chart context requires a rebuild.
Inputs: None.
Outputs: True when g_htf and birth index arrays are ready.
*/

bool CCTLoadSyntheticDailyHTFScannerState(const int htfLookbackBars)
  {
   // CCT_SYNTH_D1_NY1700_HTF_SOURCE_V1
   // Build synthetic NY-17:00 Daily bars from M15 so the Daily model never inherits broker-native D1 opens.
   datetime htfLast=CCTCurrentHTFBarOpenMarker();
   string cacheKey=_Symbol+"|HTF=SYN_D1_NY1700|LTF="+IntegerToString((int)LTF());

   if(g_htfCacheReady &&
      g_htfCacheLastBar==htfLast &&
      g_htfCacheBars==htfLookbackBars &&
      g_htfCacheKey==cacheKey &&
      g_nHtf>=20)
      return true;

   int sourceBars=htfLookbackBars*96+384;
   if(sourceBars<2500)
      sourceBars=2500;

   MqlRates raw[];
   ArraySetAsSeries(raw,true);
   int copied=CopyRates(_Symbol,PERIOD_M15,0,sourceBars,raw);
   if(copied<500)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   MqlRates src[];
   ArrayResize(src,copied);
   ArraySetAsSeries(src,false);
   for(int i=0;i<copied;i++)
      src[i]=raw[copied-1-i];

   MqlRates daily[];
   ArrayResize(daily,0);
   ArraySetAsSeries(daily,false);

   int nDaily=0;
   datetime currentOpen=0;

   for(int i=0;i<copied;i++)
     {
      datetime dOpen=CCTNY1700DailyOpenForServerTime(src[i].time);
      if(dOpen<=0)
         continue;

      if(nDaily<=0 || dOpen!=currentOpen)
        {
         currentOpen=dOpen;
         int newSize=nDaily+1;
         ArrayResize(daily,newSize);

         daily[nDaily]=src[i];
         daily[nDaily].time=dOpen;
         nDaily=newSize;
         continue;
        }

      int idx=nDaily-1;
      if(src[i].high>daily[idx].high)
         daily[idx].high=src[i].high;
      if(src[i].low<daily[idx].low)
         daily[idx].low=src[i].low;
      daily[idx].close=src[i].close;
      daily[idx].tick_volume+=src[i].tick_volume;
      daily[idx].real_volume+=src[i].real_volume;
      daily[idx].spread=src[i].spread;
     }

   if(nDaily<20)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   int keep=(nDaily<htfLookbackBars ? nDaily : htfLookbackBars);
   ArrayResize(g_htf,keep);
   ArraySetAsSeries(g_htf,true);
   for(int j=0;j<keep;j++)
      g_htf[j]=daily[nDaily-1-j];

   g_nHtf=keep;
   if(g_nHtf<20)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   BuildBirthLists(g_htf,g_nHtf,g_bullBirths,g_nBull,g_bearBirths,g_nBear);

   g_htfCacheReady=true;
   g_htfCacheLastBar=htfLast;
   g_htfCacheBars=htfLookbackBars;
   g_htfCacheKey=cacheKey;

   return true;
  }

bool CCTLoadSynthetic4HHTFScannerState(const int htfLookbackBars)
  {
   // CCT_SYNTH_H4_NY1700_HTF_SOURCE_V1
   // Build synthetic NY-17:00 anchored H4 bars from M5 so 4H model never inherits broker-native H4 opens.
   datetime htfLast=CCTCurrentHTFBarOpenMarker();
   string cacheKey=_Symbol+"|HTF=SYN_H4_NY1700|LTF="+IntegerToString((int)LTF());

   if(g_htfCacheReady &&
      g_htfCacheLastBar==htfLast &&
      g_htfCacheBars==htfLookbackBars &&
      g_htfCacheKey==cacheKey &&
      g_nHtf>=20)
      return true;

   int sourceBars=htfLookbackBars*48+384;
   if(sourceBars<2500)
      sourceBars=2500;

   MqlRates raw[];
   ArraySetAsSeries(raw,true);
   int copied=CopyRates(_Symbol,PERIOD_M5,0,sourceBars,raw);
   if(copied<500)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   MqlRates src[];
   ArrayResize(src,copied);
   ArraySetAsSeries(src,false);
   for(int i=0;i<copied;i++)
      src[i]=raw[copied-1-i];

   MqlRates h4[];
   ArrayResize(h4,0);
   ArraySetAsSeries(h4,false);

   int nH4=0;
   datetime currentOpen=0;

   for(int i=0;i<copied;i++)
     {
      datetime hOpen=CCTModelHTFOpenForTime(src[i].time);
      if(hOpen<=0)
         continue;

      if(nH4<=0 || hOpen!=currentOpen)
        {
         currentOpen=hOpen;
         int newSize=nH4+1;
         ArrayResize(h4,newSize);

         h4[nH4]=src[i];
         h4[nH4].time=hOpen;
         nH4=newSize;
         continue;
        }

      int idx=nH4-1;
      if(src[i].high>h4[idx].high)
         h4[idx].high=src[i].high;
      if(src[i].low<h4[idx].low)
         h4[idx].low=src[i].low;
      h4[idx].close=src[i].close;
      h4[idx].tick_volume+=src[i].tick_volume;
      h4[idx].real_volume+=src[i].real_volume;
      h4[idx].spread=src[i].spread;
     }

   if(nH4<20)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   int keep=(nH4<htfLookbackBars ? nH4 : htfLookbackBars);
   ArrayResize(g_htf,keep);
   ArraySetAsSeries(g_htf,true);
   for(int j=0;j<keep;j++)
      g_htf[j]=h4[nH4-1-j];

   g_nHtf=keep;
   if(g_nHtf<20)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   BuildBirthLists(g_htf,g_nHtf,g_bullBirths,g_nBull,g_bearBirths,g_nBear);

   g_htfCacheReady=true;
   g_htfCacheLastBar=htfLast;
   g_htfCacheBars=htfLookbackBars;
   g_htfCacheKey=cacheKey;

   return true;
  }
bool CCTLoadHTFScannerState()
  {
   int htfLookbackBars=CCTVirginLookbackBars();

   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return CCTLoadSyntheticDailyHTFScannerState(htfLookbackBars);

   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return CCTLoadSynthetic4HHTFScannerState(htfLookbackBars);

   datetime htfLast=CCTCurrentHTFBarOpenMarker();
   string cacheKey=_Symbol+"|HTF="+IntegerToString((int)HTF())+"|LTF="+IntegerToString((int)LTF());

   if(g_htfCacheReady &&
      g_htfCacheLastBar==htfLast &&
      g_htfCacheBars==htfLookbackBars &&
      g_htfCacheKey==cacheKey &&
      g_nHtf>=20)
      return true;

   ArraySetAsSeries(g_htf,true);
   g_nHtf=CopyRates(_Symbol,HTF(),0,htfLookbackBars,g_htf);
   if(g_nHtf<20)
     {
      CCTResetHTFScannerCache();
      return false;
     }

   BuildBirthLists(g_htf,g_nHtf,g_bullBirths,g_nBull,g_bearBirths,g_nBear);

   g_htfCacheReady=true;
   g_htfCacheLastBar=htfLast;
   g_htfCacheBars=htfLookbackBars;
   g_htfCacheKey=cacheKey;
   return true;
  }

/*
Purpose: Return whether a generation still has any live or chart-worthy sibling state.
Constitution: Latest user clarification that valid, active, inactive, and already-activated same-day generations keep their APs visible until the generation becomes dormant.
Inputs: g - generation record.
Outputs: True when the generation has a default-visible sibling state.
*/
bool GenerationHasVisibleState(const GenInfo &g)
  {
   for(int s=0;s<g.nSibs;s++)
     {
      SIB_STATE st=g.sibs[s].state;
      if(st==SS_VALID || st==SS_ACTIVE || st==SS_INACTIVE || st==SS_TRIGGERED)
         return true;
     }
   return false;
  }

/*
Purpose: Return whether any sibling in the generation first activated during the current NY day.
Constitution: Latest user clarification that generations activated within the current day keep their APs visible by default.
Inputs: g - generation record.
Outputs: True when any C1/C2/C3 activity occurred during the current NY day.
*/
bool GenerationHasCurrentDayActivation(const GenInfo &g)
  {
   for(int s=0;s<g.nSibs;s++)
     {
      if(!g.sibs[s].hadAuthorizedC1)
         continue;
      if(IsCurrentNYDay(g.sibs[s].c1Time) || IsCurrentNYDay(g.sibs[s].c2Time) || IsCurrentNYDay(g.sibs[s].c3Time))
         return true;
     }
   return false;
  }

/*
Purpose: Return whether the generation has already produced an execution record state.
Constitution: One triggered generation is consumed forever and its execution geometry remains visible through the trading-day display lifecycle.
Inputs: g - generation record.
Outputs: True when any sibling is triggered or resolved.
*/
bool GenerationHasExecutionState(const GenInfo &g)
  {
   if(g.triggerTime>0)
      return true;

   for(int s=0;s<g.nSibs;s++)
     {
      SIB_STATE st=g.sibs[s].state;
      if(st==SS_TRIGGERED || st==SS_RESOLVED_TP || st==SS_RESOLVED_SL || st==SS_RESOLVED_BE || st==SS_RESOLVED_BE_CO)
         return true;
     }
   return false;
  }

/*
Purpose: Return whether the generation belongs to the currently configured execution-hour families.
Constitution: Ch. 29 relevance rules, Ch. 28 current-day visibility, and latest user clarification that parameter changes should immediately rebuild which births belong to the selected execution timing families.
Inputs: g - generation record.
Outputs: True when the generation structurally maps to the configured execution-hour timing families.
*/
bool GenerationMatchesConfiguredHours(const GenInfo &g)
  {
   datetime lastEnd=0;
   return ResolveGenerationLastAuthorizedEndForGeneration(g,lastEnd);
  }

/*
Purpose: Return whether a generation's live POI geometry should still extend to the current LTF bar.
Constitution: Ch. 29 execution-window ownership and latest user clarification that POIs must stop following price once their selected execution window is exhausted.
Inputs: g - generation record, nowTime - broker server timestamp to evaluate.
Outputs: True when the generation is still inside an authorized live execution span.
*/
bool GenerationShouldExtendLive(const GenInfo &g,datetime nowTime)
  {
   if(g.dormant)
      return false;

   if(!GenerationHasVisibleState(g))
      return false;

   if(!GenerationMatchesConfiguredHours(g))
      return false;

   return GenerationHasRemainingLiveWindow(g,nowTime);
  }

/*
Purpose: Return whether a generation should still show its default POIs on-chart right now.
Constitution: Ch. 28 states that VALID/ACTIVE/TRIGGERED POIs remain visible in the current-day window, and latest user clarification requires parameter changes to rebuild POI relevance from the selected execution-hour families immediately.
Inputs: g - generation record.
Outputs: True when the generation should keep its default POI lines visible.
*/
bool GenerationShouldShowDefaultPOIs(const GenInfo &g)
  {
   if(g.dormant)
      return false;

   if(GenerationHasExecutionState(g) || GenerationHasCurrentDayActivation(g))
      return true;

   if(!GenerationMatchesConfiguredHours(g))
      return false;

   return GenerationHasVisibleState(g);
  }

/*
Purpose: Resolve the current right-edge contract for one sibling line.
Constitution: Valid POIs end at the birth-bar close, C1-active structures extend to the C1 HTF close, and triggered unresolved POIs advance one HTF close at a time until resolution or bias flip.
Inputs: g - generation record, sib - sibling record, nowTime - server timestamp used for dynamic extension.
Outputs: Right-edge timestamp for POI rendering.
*/
datetime ResolveSiblingRenderEnd(const GenInfo &g,const SibInfo &sib,datetime nowTime)
  {
   datetime birthEnd=HTFBarCloseForOpen(g.birthTime);

   if(IsResolvedPOIState(sib.state) && g.exitTime>0)
      return HTFBarCloseForTime(g.exitTime);

   if(sib.state==SS_TRIGGERED && g.triggerTime>0)
     {
      if(g.exitTime>0)
         return HTFBarCloseForTime(g.exitTime);

      datetime triggeredEnd=HTFBarCloseForTime(nowTime);
      datetime counterBirth=0;
      if(FindBirthAfter(g,false,counterBirth) && counterBirth>g.triggerTime)
        {
         datetime flipClose=HTFBarCloseForOpen(counterBirth);
         if(flipClose>0 && flipClose<triggeredEnd)
            triggeredEnd=flipClose;
        }
      return triggeredEnd;
     }

   if(sib.state==SS_VALID || sib.state==SS_INACTIVE || sib.state==SS_DORMANT)
      return birthEnd;

   if(sib.state==SS_ACTIVE && sib.c1Time>0)
      return HTFBarCloseForTime(sib.c1Time);

   if(IsDeadPOIState(sib.state))
     {
      if(sib.c3Time>0)
         return HTFBarCloseForTime(sib.c3Time);
      if(sib.c2Time>0)
         return HTFBarCloseForTime(sib.c2Time);
      if(sib.c1Time>0)
         return HTFBarCloseForTime(sib.c1Time);
     }

   if(sib.c1Time>0)
      return HTFBarCloseForTime(sib.c1Time);

   return birthEnd;
  }

/*
Purpose: Return whether the generation's current TS level should be drawn.
Constitution: Latest user clarification that only current-bias TS levels are shown live, while triggered TS levels persist historically until cleanup.
Inputs: g - generation record, currentBiasBull - current HTF bias direction.
Outputs: True when the TS line should render.
*/
bool GenerationShouldShowTS(const GenInfo &g,bool currentBiasBull)
  {
   if(g.tsDisplayLevel<=0.0 || g.tsFirstTouchTime<=0)
      return false;

   if(g.triggerTime>0)
      return (g.sweepCount>0 || g.modelType==MODEL_CCT_TS || g.modelType==MODEL_CCT_TS_EXT);

   if(g.dormant)
      return false;

   if(g.bull!=currentBiasBull)
      return false;

   if(g.activeSibIdx<0 || g.activeSibIdx>=g.nSibs)
      return false;

   if(g.sibs[g.activeSibIdx].state!=SS_ACTIVE)
      return false;

   if(!g.sibs[g.activeSibIdx].hadAuthorizedC1 || g.sibs[g.activeSibIdx].c1Time<=0)
      return false;

   ENUM_CCT_AUTH_ROUTE route=g.sibs[g.activeSibIdx].authorityRoute;
   if(route!=AUTH_ROUTE_NONE &&
      route!=AUTH_ROUTE_RECORD_ONLY &&
      !g.sibs[g.activeSibIdx].authorityRecordOnly)
      return true;

   return GenerationMatchesConfiguredHours(g);
  }

/*
Purpose: Return whether the generation's CO line should be drawn.
Constitution: CO is live only while the trade is unresolved or until its first touch. TP always removes CO; SL/BE before CO touch removes CO; SL/BE after CO touch keeps the locked CO evidence.
Inputs: g - generation record, currentBiasBull - current HTF bias direction.
Outputs: True when the CO line should render.
*/
bool GenerationShouldShowCO(const GenInfo &g,bool currentBiasBull)
  {
   if(g.triggerTime<=0 || !g.coLocked || g.dormant)
      return false;

   bool outcomeTP=(g.outcome==SS_RESOLVED_TP);
   bool outcomeSLBE=(g.outcome==SS_RESOLVED_SL ||
                     g.outcome==SS_RESOLVED_BE ||
                     g.outcome==SS_RESOLVED_BE_CO);

   if(outcomeTP)
      return false;

   if(g.exitTime>0 && g.coTouchTime<=0)
      return false;

   if(outcomeSLBE && g.coTouchTime<=0)
      return false;

   bool between=g.bull ? (g.coPrice>g.visualEntry && g.coPrice<=g.rawTP)
                       : (g.coPrice<g.visualEntry && g.coPrice>=g.rawTP);
   if(!between && !Inp_UseCOTP)
      return false;

   for(int s=0;s<g.nSibs;s++)
     {
      SIB_STATE st=g.sibs[s].state;

      if(st==SS_RESOLVED_TP)
         return false;

      if((st==SS_RESOLVED_SL || st==SS_RESOLVED_BE || st==SS_RESOLVED_BE_CO) &&
         g.coTouchTime<=0)
         return false;
     }

   return true;
  }

/*
Purpose: Return whether a sibling state is terminal-dead for POI visibility decisions.
Constitution: Ch. 10 state inventory and Ch. 28 dead-state visibility.
Inputs: state - sibling state.
Outputs: True when the sibling is in any terminal dead state.
*/
bool IsDeadPOIState(SIB_STATE state)
  {
   return (state==SS_DEAD_SUPERSESSION || state==SS_DEAD_CO_VIOLATION ||
           state==SS_DEAD_WINDOW_CONSUMED || state==SS_DEAD_WINDOW_EXPIRED ||
           state==SS_DEAD_UNAUTHORIZED_C1 || state==SS_DEAD_BIAS_FLIP);
  }

/*
Purpose: Return whether a sibling state is still structurally live for default POI rendering.
Constitution: Ch. 28 visibility by state.
Inputs: state - sibling state.
Outputs: True for VALID, ACTIVE, INACTIVE, and TRIGGERED.
*/
bool IsLivePOIState(SIB_STATE state)
  {
   return (state==SS_VALID || state==SS_ACTIVE || state==SS_INACTIVE || state==SS_TRIGGERED);
  }

/*
Purpose: Return whether a sibling state is a resolved trade outcome for persistent POI rendering.
Constitution: Ch. 24 and Ch. 28 resolved-state visibility.
Inputs: state - sibling state.
Outputs: True for TP, SL, or BE resolved outcomes.
*/
bool IsResolvedPOIState(SIB_STATE state)
  {
   return (state==SS_RESOLVED_TP || state==SS_RESOLVED_SL || state==SS_RESOLVED_BE || state==SS_RESOLVED_BE_CO);
  }

/*
Purpose: Return whether a generation contains any dead sibling state.
Constitution: Ch. 28 dead-state visibility and latest user clarification that dead POI birth pillars should remain inspectable inside the scan horizon.
Inputs: g - generation record.
Outputs: True when any sibling is terminal-dead.
*/
bool GenerationHasDeadPOIs(const GenInfo &g)
  {
   for(int s=0;s<g.nSibs;s++)
     {
      if(IsDeadPOIState(g.sibs[s].state))
         return true;
     }
   return false;
  }

/*
Purpose: Return whether a dead-generation action pillar should remain visible for inspection.
Constitution: Dead APs are developer diagnostics only; plain execution-window expiry is not chart-worthy and must not leave a stale AP when all POIs are dead.
Inputs: g - generation record, allowDeadDisplay - whether dead-generation APs may be shown.
Outputs: True only for explicitly allowed non-expiry dead diagnostics.
*/
bool GenerationShouldShowDeadAP(const GenInfo &g,bool allowDeadDisplay)
  {
   if(!allowDeadDisplay || g.dormant || g.nSibs<=0)
      return false;

   if(GenerationHasVisibleState(g) || GenerationHasExecutionState(g))
      return false;

   bool hasDead=false;
   bool allWindowExpired=true;

   for(int s=0;s<g.nSibs;s++)
     {
      SIB_STATE st=g.sibs[s].state;

      if(IsDeadPOIState(st))
         hasDead=true;
      else
         allWindowExpired=false;

      if(st!=SS_DEAD_WINDOW_EXPIRED)
         allWindowExpired=false;
     }

   if(!hasDead)
      return false;

   // A generation that only timed out is not useful chart evidence.
   // Its POIs are gone, so its AP must be gone too.
   if(allWindowExpired)
      return false;

   return true;
  }

/*
Purpose: Scan one generation set through the shared Pass-2 state machine.
Constitution: Latest user clarification that all modes share one scanner truth path; this helper keeps generation reconstruction consistent for both current-bias and optional dead counter-bias display.
Inputs: gens - generation array, nGens - generation count, ltf - LTF rates, nl - bar count, isExecBarOpen - current HTF execution gate, currentHTFHourNY - current NY hour.
Outputs: gens updated in place.
*/
bool CCTSameExecutionWindow(datetime a,datetime b)
  {
   if(a<=0 || b<=0)
      return false;

   datetime ae=HTFBarCloseForTime(a);
   datetime be=HTFBarCloseForTime(b);

   if(ae<=0 || be<=0)
      return false;

   return (ae==be);
  }

/*
Purpose: Return whether a confirmed HTF birth opened a new execution epoch between two scanner events.
Constitution: After a confirmed trigger, only a later confirmed birth can re-enable trigger authority for old/current POIs.
Inputs: fromExclusive - consumed trigger time, toInclusive - later candidate event time.
Outputs: True when any bull or bear birth became effective in the interval.
*/
bool CCTConfirmedBirthEffectiveBetween(datetime fromExclusive,datetime toInclusive)
  {
   if(fromExclusive<=0 || toInclusive<=fromExclusive)
      return false;

   for(int i=0;i<g_nBull;i++)
     {
      int idx=g_bullBirths[i];
      if(idx<0 || idx>=g_nHtf)
         continue;
      datetime effective=BirthEffectiveTime(g_htf[idx].time);
      if(effective>fromExclusive && effective<=toInclusive)
         return true;
     }

   for(int i=0;i<g_nBear;i++)
     {
      int idx=g_bearBirths[i];
      if(idx<0 || idx>=g_nHtf)
         continue;
      datetime effective=BirthEffectiveTime(g_htf[idx].time);
      if(effective>fromExclusive && effective<=toInclusive)
         return true;
     }

   return false;
  }

/*
Purpose: Recover the true structural trigger time for a generation that has already spent its execution window.
Constitution: A replay-suppressed trigger still consumes authority; clearing broker trigger state must not let older dormant POIs execute later without a fresh birth.
Inputs: g - generation record.
Outputs: Trigger/consumption time, or 0 when the generation has not structurally consumed a trigger.
*/
datetime CCTGenerationConsumedTriggerTime(const GenInfo &g)
  {
   if(g.triggerTime>0)
      return g.triggerTime;

   datetime best=0;
   for(int s=0;s<g.nSibs;s++)
     {
      if(g.sibs[s].state!=SS_DEAD_WINDOW_CONSUMED)
         continue;
      if(g.sibs[s].c2Time<=0 || g.sibs[s].c3Time<=0)
         continue;

            datetime completed=(g.sibs[s].c2Time>g.sibs[s].c3Time) ? g.sibs[s].c2Time : g.sibs[s].c3Time;
      if(completed<=0)
         continue;

      // CCT_CONSUMED_TRIGGER_COUNTER_BIAS_IS_LOCAL_ONLY_V1
      // A structural completion after a counter-bias birth may clean up only
      // its own older generation siblings. It must not be exported as prior
      // execution-window consumption against newer post-flip generations.
      if(GenerationBiasIsOppositeAt(g,completed))
         continue;

      if(best<=0 || completed<best)
         best=completed;
     }

   return best;
  }

/*
Purpose: Find whether a prior generation already consumed the same execution window before this dormant activation event.
Constitution: One execution window can authorize only one broker trigger unless a new birth creates a new authorized trigger path.
Inputs: gens - generation set, stopExclusive - generations before the newly activated dormant generation, eventTime - dormant activation C1 time.
Outputs: True if a previous generation already triggered in this same execution window at or before eventTime.
*/
bool CCTPriorTriggerConsumedWindow(GenInfo &gens[],int stopExclusive,datetime eventTime,int &winnerIdx,datetime &winnerTriggerTime)
  {
   winnerIdx=-1;
   winnerTriggerTime=0;

   if(eventTime<=0)
      return false;

   // CCT_PRIOR_TRIGGER_REQUIRES_NEWER_BIRTH_CONTEXT_V1
   // A consumed trigger may block only an OLDER dormant generation.
   // A same-birth or older-birth trigger cannot consume a POI born by a newer HTF close/bias flip.
   int genCount=ArraySize(gens);
   if(stopExclusive<=0 || stopExclusive>=genCount)
      return false;

   datetime blockedBirthEffective=BirthEffectiveTime(gens[stopExclusive].birthTime);

   for(int j=0;j<stopExclusive;j++)
     {
      datetime consumedTime=CCTGenerationConsumedTriggerTime(gens[j]);
      if(consumedTime<=0)
         continue;

      if(consumedTime>eventTime)
         continue;

      datetime consumerBirthEffective=BirthEffectiveTime(gens[j].birthTime);
      if(blockedBirthEffective>0 && consumerBirthEffective>0 && consumerBirthEffective<=blockedBirthEffective)
         continue;

      // CCT_TRIGGER_CONSUMPTION_REQUIRES_BIAS_VALIDITY_V1
      // A consumed-window event is authoritative only while the consuming generation
      // remains directionally valid at its structural trigger/consumption time.
      // Counter-bias or post-bias-flip historical C3 must not poison the new generation.
      if(GenerationBiasIsOppositeAt(gens[j],consumedTime))
         continue;

      if(CCTConfirmedBirthEffectiveBetween(consumedTime,eventTime))
         continue;

      if(winnerTriggerTime<=0 || consumedTime<winnerTriggerTime)
        {
         winnerTriggerTime=consumedTime;
         winnerIdx=j;
        }
     }

   return (winnerIdx>=0);
  }

/*
Purpose: Record a dormant activation after the execution window has already been consumed, then kill it before it can reach C2/C3.
Constitution: Dormant generations behind price may be observed for structural record and sibling cleanup, but after a valid prior trigger in the same execution window they cannot broker-trigger without a new birth.
Domain label: WINDOW_CONSUMED_RECORD_ONLY, not sibling supersession and not FVG inversion supersession.
*/
/*
Purpose: Mark a dormant activation as record-only after the execution window was already consumed.
Constitution: The dormant C1 cannot broker-trigger, but it must still be monitored for C2+C3.
If its record-only C1 later completes structurally, ConsumeGenerationAfterUnauthorizedTrigger()
will spend the generation and kill the remaining siblings.
Domain label: WINDOW_CONSUMED_RECORD_ONLY_C1, not sibling supersession and not FVG inversion supersession.
*/
void CCTMarkDormantActivationRecordOnly(GenInfo &g,datetime eventTime,const string reasonLabel)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   int idx=g.activeSibIdx;

   if(idx>=0 && idx<g.nSibs)
     {
      if(!IsResolvedPOIState(g.sibs[idx].state) && !IsDeadPOIState(g.sibs[idx].state))
        {
         // Reuse the existing unauthorized structural-consume engine.
         // This prevents broker execution but still allows C2+C3 monitoring.
         g.sibs[idx].state=SS_DEAD_UNAUTHORIZED_C1;

          if(g.sibs[idx].c1Time<=0)
             g.sibs[idx].c1Time=eventTime;

          g.sibs[idx].c2Time=0;
          g.sibs[idx].c3Time=0;
          datetime htfOpen=HTFBarOpenForTime(eventTime);
          MqlDateTime ny={};
          TimeToStruct(ToExecutionNY(htfOpen),ny);
          int offset=GenerationExecutionOffset(g.birthTime,htfOpen);
          StampSiblingAuthority(g,idx,AUTH_ROUTE_RECORD_ONLY,htfOpen,ny.hour,offset,true,true,htfOpen);
         }
      }

   g.triggerTime=0;
   g.activeSibIdx=-1;
   g.dormant=false;

   if(DebugEventShouldPrint("WINDOW_CONSUMED_RECORD_ONLY_C1",genKey,-1,eventTime))
      CCTJournalLine(StringFormat("[CCT DBG] WINDOW_CONSUMED_RECORD_ONLY_C1 | gen=%s | event=%s | reason=%s",
                                  genKey,
                                  TimeToString(eventTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  reasonLabel));
  }

/*
Purpose: Continue record-only structural monitoring after a dormant C1 is blocked by a prior trigger in the same execution window.
Constitution: No broker trigger is allowed. Only C2+C3 completion is tracked so the generation can be spent and siblings killed.
*/
void CCTScanDormantRecordOnlyStructuralTrigger(GenInfo &g,MqlRates &ltf[],int nl,datetime fromTime)
  {
   int ltfCount=ArraySize(ltf);

   if(nl<=0 || ltfCount<=0 || fromTime<=0)
      return;

   if(nl>ltfCount)
      nl=ltfCount;

   for(int k=0;k<nl;k++)
     {
      TrackGenerationFVGFormation(g,ltf,nl,k);

      if(ltf[k].time<fromTime)
         continue;

      if(ScanUnauthorizedStructuralTrigger(g,ltf,nl,k))
        {
         if(DebugEventShouldPrint("WINDOW_CONSUMED_RECORD_ONLY_TRIGGER",GenKey(g.bull,g.birthTime),-1,ltf[k].time))
            CCTJournalLine(StringFormat("[CCT DBG] WINDOW_CONSUMED_RECORD_ONLY_TRIGGER | gen=%s | completed=%s",
                                        GenKey(g.bull,g.birthTime),
                                        TimeToString(ltf[k].time,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
         return;
        }

      if(AllSiblingsDead(g))
         return;
     }
  }

/*
Purpose: Find the first valid older-dormant shoot-through C1 before a newer generation's trigger.
Constitution: A newer same-bias birth owns the execution bar first, but an older dormant generation may reclaim authority if price actually C1s it first on a selected TS/Ext family bar.
Inputs: g - older generation, ltf/nl - closed LTF replay, beforeOrAt - newer trigger time ceiling, activatedIdx/barIdx - outputs.
Outputs: True when an older dormant takeover event exists before the newer trigger.
*/
bool CCTFindDormantTakeoverBefore(GenInfo &g,MqlRates &ltf[],int nl,datetime beforeOrAt,int &activatedIdx,int &barIdx)
  {
   // CCT_DORMANT_FIND_PROFILE_V1
   ulong cctDormFindStart=GetMicrosecondCount();
   ulong cctDormFindStep=0;
   ulong cctDormFindStartSeekUs=0;
   ulong cctDormFindLoopUs=0;
   ulong cctDormFindBiasUs=0;
   ulong cctDormFindAuthUs=0;
   int cctDormFindBars=0;
   int cctDormFindCrosses=0;
   int cctDormFindBiasRejects=0;
   int cctDormFindAuthRejects=0;
   bool cctDormFindResult=false;

   // CCT_DORMANT_TAKEOVER_FIND_FAST_V2
   // Same semantic gates as the original audit, but avoids brute-forcing irrelevant LTF bars.
   // The search now starts at the generation Action Pillar and tests cheap POI crossing
   // before expensive bias/authority checks.
   activatedIdx=-1;
   barIdx=-1;

   if(beforeOrAt<=0 || !g.dormant || AllSiblingsDead(g))
      return false;

   int ltfCount=ArraySize(ltf);
   if(nl<=0 || ltfCount<=0)
      return false;
   if(nl>ltfCount)
      nl=ltfCount;

   datetime pillarTime=ActionPillarTime(g.birthTime);
   int startIdx=0;

   if(pillarTime>0)
     {
      cctDormFindStep=GetMicrosecondCount();
      bool foundStart=false;
      for(int p=0;p<nl;p++)
        {
         if(ltf[p].time>=pillarTime)
           {
            startIdx=p;
            foundStart=true;
            break;
           }
        }

      if(!foundStart)
         return false;
     }

   cctDormFindStep=GetMicrosecondCount();
   for(int k=startIdx;k<nl;k++)
     {
      cctDormFindBars++;
      datetime barTime=ltf[k].time;

      if(barTime>beforeOrAt)
         break;

      // Cheap structural crossing test first. Most bars never touch the dormant POI edge.
      int idx=ShallowestCrossedSiblingEdge(g,C1PrevClose(ltf,k),ltf[k].close,false);
      if(idx<0)
         continue;
      cctDormFindCrosses++;

      // Preserve original semantic gates after the cheap crossing prefilter.
      ulong cctDormFindBiasStep=GetMicrosecondCount();
      bool cctDormFindBiasOpposite=GenerationBiasIsOppositeAt(g,barTime);
      cctDormFindBiasUs+=GetMicrosecondCount()-cctDormFindBiasStep;
      if(cctDormFindBiasOpposite)
        {
         cctDormFindBiasRejects++;
         continue;
        }

      ENUM_CCT_AUTH_ROUTE c1Route=AUTH_ROUTE_NONE;
      datetime c1HTFOpen=0;
      int c1HourNY=-1;
      int c1Offset=-1;
      ulong cctDormFindAuthStep=GetMicrosecondCount();
      bool cctDormFindAuthOk=ResolveC1AuthorityRoute(g,barTime,true,c1Route,c1HTFOpen,c1HourNY,c1Offset);
      cctDormFindAuthUs+=GetMicrosecondCount()-cctDormFindAuthStep;
      if(!cctDormFindAuthOk)
        {
         cctDormFindAuthRejects++;
         continue;
        }

      if(g.triggerTime>0 && g.triggerTime<=barTime)
         continue;

      activatedIdx=idx;
      barIdx=k;
      cctDormFindLoopUs+=GetMicrosecondCount()-cctDormFindStep;
      ulong cctDormFindTotal=GetMicrosecondCount()-cctDormFindStart;
      if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormFindTotal>250000))
         CCTJournalLine(StringFormat("[CCT DORMANT FIND PROFILE V1] symbol=%s | gen=%s | result=hit | total_us=%s | startSeek=%s | loop=%s | bars=%d | crosses=%d | biasUs=%s | biasRejects=%d | authUs=%s | authRejects=%d | nl=%d | from=%s | before=%s | hit=%s",
                                     _Symbol,
                                     GenKey(g.bull,g.birthTime),
                                     IntegerToString((long)cctDormFindTotal),
                                     IntegerToString((long)cctDormFindStartSeekUs),
                                     IntegerToString((long)cctDormFindLoopUs),
                                     cctDormFindBars,
                                     cctDormFindCrosses,
                                     IntegerToString((long)cctDormFindBiasUs),
                                     cctDormFindBiasRejects,
                                     IntegerToString((long)cctDormFindAuthUs),
                                     cctDormFindAuthRejects,
                                     nl,
                                     TimeToString(pillarTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     TimeToString(beforeOrAt,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     TimeToString(barTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
      return true;
     }

   cctDormFindLoopUs+=GetMicrosecondCount()-cctDormFindStep;
   ulong cctDormFindTotal=GetMicrosecondCount()-cctDormFindStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormFindTotal>250000))
      CCTJournalLine(StringFormat("[CCT DORMANT FIND PROFILE V1] symbol=%s | gen=%s | result=miss | total_us=%s | startSeek=%s | loop=%s | bars=%d | crosses=%d | biasUs=%s | biasRejects=%d | authUs=%s | authRejects=%d | nl=%d | from=%s | before=%s",
                                  _Symbol,
                                  GenKey(g.bull,g.birthTime),
                                  IntegerToString((long)cctDormFindTotal),
                                  IntegerToString((long)cctDormFindStartSeekUs),
                                  IntegerToString((long)cctDormFindLoopUs),
                                  cctDormFindBars,
                                  cctDormFindCrosses,
                                  IntegerToString((long)cctDormFindBiasUs),
                                  cctDormFindBiasRejects,
                                  IntegerToString((long)cctDormFindAuthUs),
                                  cctDormFindAuthRejects,
                                  nl,
                                  TimeToString(pillarTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(beforeOrAt,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
   return false;
  }

/*
Purpose: Apply an older-dormant takeover event found during the post-scan authority audit.
Constitution: The older generation becomes active, deeper siblings become inactive, and the newer frontrunner is then killed by generation supersession.
Inputs: g - older generation, ltf/nl - replay bars, activatedIdx/barIdx - event coordinates, dormantCOCutoff - optional CO freeze cutoff.
Outputs: g updated as an active generation.
*/
void CCTApplyDormantTakeoverActivation(GenInfo &g,MqlRates &ltf[],int nl,int activatedIdx,int barIdx,datetime dormantCOCutoff=0)
  {
   if(activatedIdx<0 || activatedIdx>=g.nSibs || barIdx<0 || barIdx>=nl)
      return;

   for(int s=0;s<activatedIdx;s++)
     {
      if(!IsAliveSiblingState(g.sibs[s].state))
         continue;
      g.sibs[s].state=SS_DEAD_SUPERSESSION;
      if(g.sibs[s].c1Time<=0)
         g.sibs[s].c1Time=ltf[barIdx].time;
      g.sibs[s].c2Time=0;
      g.sibs[s].c3Time=0;
     }

   g.triggerTime=0;
   g.dormant=false;
   g.sibs[activatedIdx].state=SS_ACTIVE;
   g.sibs[activatedIdx].c1Time=ltf[barIdx].time;
   ENUM_CCT_AUTH_ROUTE c1Route=AUTH_ROUTE_NONE;
   datetime c1HTFOpen=0;
   int c1HourNY=-1;
   int c1Offset=-1;
   ResolveC1AuthorityRoute(g,ltf[barIdx].time,true,c1Route,c1HTFOpen,c1HourNY,c1Offset);
   StampSiblingAuthority(g,activatedIdx,c1Route,c1HTFOpen,c1HourNY,c1Offset,true,false,c1HTFOpen);
   for(int s=activatedIdx+1;s<g.nSibs;s++)
     {
      if(g.sibs[s].state==SS_VALID || g.sibs[s].state==SS_DORMANT)
         g.sibs[s].state=SS_INACTIVE;
     }

   g.activeSibIdx=activatedIdx;
   datetime coCutoff=(dormantCOCutoff>0 && dormantCOCutoff<ltf[barIdx].time) ? dormantCOCutoff : ltf[barIdx].time;
   LockCorrectionOriginIfNeeded(g,ltf,nl,coCutoff,true);
   DebugPrintC1CO(ltf[barIdx].time,g);
  }

/*
Purpose: Apply older-dormant generation supersession at the C1 event itself.
Constitution: Dormant shoot-through C1 is the authority-transfer event. The newer shallower/frontrunning generation dies immediately at that C1; the scanner must not wait to see whether the newer generation would later trigger.
Inputs: gens - generation set newest-first, ltf/nl - closed LTF replay, scanEnd - latest scanned LTF bar time.
Outputs: gens updated so newer authorities are killed as soon as older dormant takeover C1 is found.
*/
void CCTAuditDormantTakeoverEvents(GenInfo &gens[],int nGens,MqlRates &ltf[],int nl,datetime scanEnd)
  {
   // CCT_DORMANT_AUDIT_PROFILE_V1
   ulong cctDormAuditStart=GetMicrosecondCount();
   ulong cctDormAuditStep=0;
   ulong cctDormAuditFindUs=0;
   ulong cctDormAuditApplyUs=0;
   ulong cctDormAuditReconcileUs=0;
   int cctDormAuditIterations=0;
   int cctDormAuditFindCalls=0;
   int cctDormAuditHits=0;
   int genCount=ArraySize(gens);
   if(nGens<=1 || genCount<=0 || scanEnd<=0)
      return;
   if(nGens>genCount)
      nGens=genCount;

   bool changed=true;
   while(changed)
     {
      cctDormAuditIterations++;
      changed=false;

      int bestOlder=-1;
      int bestActivated=-1;
      int bestBar=-1;
      datetime bestEvent=0;

      for(int older=1;older<nGens;older++)
        {
         if(!gens[older].dormant || AllSiblingsDead(gens[older]))
            continue;

         int activatedIdx=-1;
         int barIdx=-1;
         cctDormAuditFindCalls++;
         cctDormAuditStep=GetMicrosecondCount();
         bool cctDormAuditFindHit=CCTFindDormantTakeoverBefore(gens[older],ltf,nl,scanEnd,activatedIdx,barIdx);
         cctDormAuditFindUs+=GetMicrosecondCount()-cctDormAuditStep;
         if(!cctDormAuditFindHit)
            continue;
         cctDormAuditHits++;

         datetime eventTime=ltf[barIdx].time;
         if(bestEvent==0 || eventTime<bestEvent)
           {
            bestEvent=eventTime;
            bestOlder=older;
            bestActivated=activatedIdx;
            bestBar=barIdx;
            ulong cctDormAuditTotal=GetMicrosecondCount()-cctDormAuditStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormAuditTotal>250000))
      CCTJournalLine(StringFormat("[CCT DORMANT AUDIT PROFILE V1] symbol=%s | total_us=%s | findUs=%s | applyUs=%s | reconcileUs=%s | iterations=%d | findCalls=%d | hits=%d | nGens=%d | nl=%d | scanEnd=%s",
                                  _Symbol,
                                  IntegerToString((long)cctDormAuditTotal),
                                  IntegerToString((long)cctDormAuditFindUs),
                                  IntegerToString((long)cctDormAuditApplyUs),
                                  IntegerToString((long)cctDormAuditReconcileUs),
                                  cctDormAuditIterations,
                                  cctDormAuditFindCalls,
                                  cctDormAuditHits,
                                  nGens,
                                  nl,
                                  TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
  }
         ulong cctDormAuditTotal=GetMicrosecondCount()-cctDormAuditStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormAuditTotal>250000))
      CCTJournalLine(StringFormat("[CCT DORMANT AUDIT PROFILE V1] symbol=%s | total_us=%s | findUs=%s | applyUs=%s | reconcileUs=%s | iterations=%d | findCalls=%d | hits=%d | nGens=%d | nl=%d | scanEnd=%s",
                                  _Symbol,
                                  IntegerToString((long)cctDormAuditTotal),
                                  IntegerToString((long)cctDormAuditFindUs),
                                  IntegerToString((long)cctDormAuditApplyUs),
                                  IntegerToString((long)cctDormAuditReconcileUs),
                                  cctDormAuditIterations,
                                  cctDormAuditFindCalls,
                                  cctDormAuditHits,
                                  nGens,
                                  nl,
                                  TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
  }

      if(bestOlder<0)
         break;

      int consumedBy=-1;
      datetime consumedAt=0;
      if(CCTPriorTriggerConsumedWindow(gens,bestOlder,bestEvent,consumedBy,consumedAt))
        {
         cctDormAuditStep=GetMicrosecondCount();
         CCTApplyDormantTakeoverActivation(gens[bestOlder],ltf,nl,bestActivated,bestBar,0);
         CCTMarkDormantActivationRecordOnly(gens[bestOlder],bestEvent,"prior trigger already consumed execution window");
         CCTScanDormantRecordOnlyStructuralTrigger(gens[bestOlder],ltf,nl,bestEvent);
         cctDormAuditApplyUs+=GetMicrosecondCount()-cctDormAuditStep;
         cctDormAuditStep=GetMicrosecondCount();
         ReconcileGenerationDormancy(gens,nGens,scanEnd);
         cctDormAuditReconcileUs+=GetMicrosecondCount()-cctDormAuditStep;
         changed=true;
         continue;
         ulong cctDormAuditTotal=GetMicrosecondCount()-cctDormAuditStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormAuditTotal>250000))
      CCTJournalLine(StringFormat("[CCT DORMANT AUDIT PROFILE V1] symbol=%s | total_us=%s | findUs=%s | applyUs=%s | reconcileUs=%s | iterations=%d | findCalls=%d | hits=%d | nGens=%d | nl=%d | scanEnd=%s",
                                  _Symbol,
                                  IntegerToString((long)cctDormAuditTotal),
                                  IntegerToString((long)cctDormAuditFindUs),
                                  IntegerToString((long)cctDormAuditApplyUs),
                                  IntegerToString((long)cctDormAuditReconcileUs),
                                  cctDormAuditIterations,
                                  cctDormAuditFindCalls,
                                  cctDormAuditHits,
                                  nGens,
                                  nl,
                                  TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
  }

      datetime dormantCOCutoff=0;
      if(bestOlder>0)
         dormantCOCutoff=HTFBarCloseForOpen(gens[bestOlder-1].birthTime);

      cctDormAuditStep=GetMicrosecondCount();
      CCTApplyDormantTakeoverActivation(gens[bestOlder],ltf,nl,bestActivated,bestBar,dormantCOCutoff);
      SupersedeNewerGenerations(gens,bestOlder,bestEvent);
      ScanGenerationC1C2(gens[bestOlder],ltf,nl,true,0);
      cctDormAuditApplyUs+=GetMicrosecondCount()-cctDormAuditStep;
      cctDormAuditStep=GetMicrosecondCount();
      ReconcileGenerationDormancy(gens,nGens,scanEnd);
      cctDormAuditReconcileUs+=GetMicrosecondCount()-cctDormAuditStep;
      changed=true;
      ulong cctDormAuditTotal=GetMicrosecondCount()-cctDormAuditStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormAuditTotal>250000))
      CCTJournalLine(StringFormat("[CCT DORMANT AUDIT PROFILE V1] symbol=%s | total_us=%s | findUs=%s | applyUs=%s | reconcileUs=%s | iterations=%d | findCalls=%d | hits=%d | nGens=%d | nl=%d | scanEnd=%s",
                                  _Symbol,
                                  IntegerToString((long)cctDormAuditTotal),
                                  IntegerToString((long)cctDormAuditFindUs),
                                  IntegerToString((long)cctDormAuditApplyUs),
                                  IntegerToString((long)cctDormAuditReconcileUs),
                                  cctDormAuditIterations,
                                  cctDormAuditFindCalls,
                                  cctDormAuditHits,
                                  nGens,
                                  nl,
                                  TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
  }
   ulong cctDormAuditTotal=GetMicrosecondCount()-cctDormAuditStart;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctDormAuditTotal>250000))
      CCTJournalLine(StringFormat("[CCT DORMANT AUDIT PROFILE V1] symbol=%s | total_us=%s | findUs=%s | applyUs=%s | reconcileUs=%s | iterations=%d | findCalls=%d | hits=%d | nGens=%d | nl=%d | scanEnd=%s",
                                  _Symbol,
                                  IntegerToString((long)cctDormAuditTotal),
                                  IntegerToString((long)cctDormAuditFindUs),
                                  IntegerToString((long)cctDormAuditApplyUs),
                                  IntegerToString((long)cctDormAuditReconcileUs),
                                  cctDormAuditIterations,
                                  cctDormAuditFindCalls,
                                  cctDormAuditHits,
                                  nGens,
                                  nl,
                                  TimeToString(scanEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
  }

/*
Purpose: Scan one generation set through the shared Pass-2 state machine.
Constitution: One execution window can produce only one broker-triggered execution unless a new birth authorizes a new trigger.
Inputs: gens - generation array, nGens - generation count, ltf - LTF rates, nl - bar count, isExecBarOpen - current HTF execution gate, currentHTFHourNY - current NY hour.
Outputs: gens updated in place.
*/
void ScanGenerationSet(GenInfo &gens[],int nGens,MqlRates &ltf[],int nl,bool isExecBarOpen,int currentHTFHourNY)
  {
   int ltfCount=ArraySize(ltf);
   if(nl<=0 || ltfCount<=0)
      return;

   if(nl>ltfCount)
      nl=ltfCount;

   int genCount=ArraySize(gens);
   if(nGens<=0 || genCount<=0)
      return;

   if(nGens>genCount)
      nGens=genCount;

   datetime scanEnd=ltf[nl-1].time;
   if(scanEnd<=0)
      return;

   // CCT_SCANSET_PROFILE_V2
   // Timing-only instrumentation for ScanGenerationSet(). No behavior change.
   ulong cctScanSetStart=GetMicrosecondCount();
   ulong cctScanSetStep=cctScanSetStart;
   ulong cctScanSetPass1Us=0;
   ulong cctScanSetDormantAuditUs=0;
   ulong cctScanSetReconcile1Us=0;
   ulong cctScanSetDormantLoopStart=0;
   int cctScanSetDormantIterations=0;
   bool cctAllowDormantHistoricalWork=(isExecBarOpen || !IsNonVisualTesterRun());

   // Pass 1: scan non-dormant generations. This may discover a valid frontrunner trigger.
   cctScanSetStep=GetMicrosecondCount();
   for(int i=0;i<nGens;i++)
     {
      if(!gens[i].dormant)
         ScanGenerationC1C2(gens[i],ltf,nl,isExecBarOpen,currentHTFHourNY);
     }
   cctScanSetPass1Us=GetMicrosecondCount()-cctScanSetStep;

   cctScanSetStep=GetMicrosecondCount();
   // CCT_DORMANT_HISTORICAL_REPLAY_ON_LIVE_RELOAD_V1
   // Live/visual reloads must replay dormant takeover history even when the
   // current HTF bar is not executable; otherwise old valid/invalid POIs can
   // be misclassified until a later selected hour opens. Non-visual tester
   // keeps the lighter closed-window path.
   if(cctAllowDormantHistoricalWork)
      CCTAuditDormantTakeoverEvents(gens,nGens,ltf,nl,scanEnd);
   cctScanSetDormantAuditUs=GetMicrosecondCount()-cctScanSetStep;

   cctScanSetStep=GetMicrosecondCount();
   ReconcileGenerationDormancy(gens,nGens,scanEnd);
   cctScanSetReconcile1Us=GetMicrosecondCount()-cctScanSetStep;

   if(cctAllowDormantHistoricalWork)
     {
      cctScanSetDormantLoopStart=GetMicrosecondCount();
      bool activated=true;
      while(activated)
        {
         cctScanSetDormantIterations++;
      activated=false;

      for(int i=1;i<nGens;i++)
        {
         datetime dormantCOCutoff=0;
         if(i>0)
            dormantCOCutoff=HTFBarCloseForOpen(gens[i-1].birthTime);

         if(!ScanDormantGenerationC1(gens[i],ltf,nl,isExecBarOpen,currentHTFHourNY,dormantCOCutoff))
            continue;

         datetime eventTime=ActionPillarTime(gens[i].birthTime);
         if(gens[i].activeSibIdx>=0 && gens[i].activeSibIdx<gens[i].nSibs)
            eventTime=gens[i].sibs[gens[i].activeSibIdx].c1Time;

         // First handle the older-dormant-wins case:
         // if a newer frontrunner's trigger is AFTER this dormant activation, clear it.
         SupersedeNewerGenerations(gens,i,eventTime);

         // Then handle the opposite case:
         // if a prior generation already triggered BEFORE this dormant activation inside
         // the same execution window, the window is already consumed. This dormant activation
         // is record-only and must never be allowed to proceed into C2/C3/broker execution.
         int consumedBy=-1;
         datetime consumedAt=0;

         if(CCTPriorTriggerConsumedWindow(gens,i,eventTime,consumedBy,consumedAt))
           {
            string winnerKey=GenKey(gens[consumedBy].bull,gens[consumedBy].birthTime);
            string loserKey=GenKey(gens[i].bull,gens[i].birthTime);

            if(DebugEventShouldPrint("WINDOW_CONSUMED_BY_PRIOR_TRIGGER",loserKey,-1,eventTime))
               CCTJournalLine(StringFormat("[CCT DBG] WINDOW_CONSUMED_BY_PRIOR_TRIGGER | blocked=%s event=%s | winner=%s trigger=%s",
                                           loserKey,
                                           TimeToString(eventTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                           winnerKey,
                                           TimeToString(consumedAt,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));

            CCTMarkDormantActivationRecordOnly(gens[i],eventTime,"prior trigger already consumed execution window");
            CCTScanDormantRecordOnlyStructuralTrigger(gens[i],ltf,nl,eventTime);
            ReconcileGenerationDormancy(gens,nGens,scanEnd);
            activated=true;
            break;
           }

         // Only if the window was not already consumed may the dormant generation continue
         // from C1 into C2/C3.
         ScanGenerationC1C2(gens[i],ltf,nl,isExecBarOpen,currentHTFHourNY);
         ReconcileGenerationDormancy(gens,nGens,scanEnd);

         activated=true;
         break;
        }
     }

     }

   cctScanSetStep=GetMicrosecondCount();
   ReconcileGenerationDormancy(gens,nGens,scanEnd);
   SweepDormantPassiveDeaths(gens,nGens,ltf,nl,scanEnd);
   ReconcileGenerationDormancy(gens,nGens,scanEnd);
   cctScanSetReconcile1Us+=GetMicrosecondCount()-cctScanSetStep;

   ulong cctScanSetTotalUs=GetMicrosecondCount()-cctScanSetStart;
   ulong cctScanSetDormantLoopUs=(cctScanSetDormantLoopStart>0 ? GetMicrosecondCount()-cctScanSetDormantLoopStart : 0);
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctScanSetTotalUs>500000))
      CCTJournalLine(StringFormat("[CCT SCANSET PROFILE V2] symbol=%s | total_us=%s | pass1=%s | dormantAudit=%s | reconcile1=%s | dormantLoop=%s | dormantIterations=%s | nGens=%s | nl=%s | currentHTFHourNY=%s | execOpen=%s",
                                  _Symbol,
                                  IntegerToString((long)cctScanSetTotalUs),
                                  IntegerToString((long)cctScanSetPass1Us),
                                  IntegerToString((long)cctScanSetDormantAuditUs),
                                  IntegerToString((long)cctScanSetReconcile1Us),
                                  IntegerToString((long)cctScanSetDormantLoopUs),
                                  IntegerToString(cctScanSetDormantIterations),
                                  IntegerToString(nGens),
                                  IntegerToString(nl),
                                  IntegerToString(currentHTFHourNY),
                                  isExecBarOpen ? "yes" : "no"));
  }


/*
Purpose: Draw one generation's POI lines under an explicit visibility policy.
Constitution: Ch. 28 visibility by state plus latest user clarification that dead counter-bias POIs may be exposed only through an explicit developer-facing option.
Inputs: g - generation record, allowDefaultVisible - permit current default live/resolved rendering, allowDormant - permit dormant masking, allowDead - permit dead-state rendering, keep - keep-list array, keepCount - keep count.
Outputs: Generation POIs drawn or removed and tracked for pruning.
*/
void DrawGenerationPOIs(const GenInfo &g,bool allowDefaultVisible,bool allowDormant,bool allowDead,string &keep[],int &keepCount)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   datetime nowTime=CurrentServerTime();
   datetime generationWindowEnd=0;
   if(!ResolveGenerationLastAuthorizedEndForGeneration(g,generationWindowEnd))
      generationWindowEnd=HTFBarCloseForOpen(ActionPillarTime(g.birthTime));

   for(int s=0;s<g.nSibs;s++)
     {
      datetime poiHtfLeftAnchor=(g.sibs[s].wickTime>0) ? g.sibs[s].wickTime : g.birthTime;
      datetime poiLtfLeftAnchor=(g.sibs[s].ltfAnchor>0) ? g.sibs[s].ltfAnchor : poiHtfLeftAnchor;
      SIB_STATE visualState=(g.dormant && allowDormant) ? SS_DORMANT : g.sibs[s].state;
      bool deadState=IsDeadPOIState(visualState);
      bool liveState=IsLivePOIState(visualState);
      bool resolvedState=IsResolvedPOIState(visualState);
      bool shouldRender=(visualState==SS_DORMANT && allowDormant) ||
                        (deadState && allowDead) ||
                        ((liveState || resolvedState) && allowDefaultVisible);
      if(!shouldRender)
        {
         DeleteObj(ObjN(genKey,"POI_"+IntegerToString(s)+"_H"));
         DeleteObj(ObjN(genKey,"POI_"+IntegerToString(s)+"_L"));
         continue;
         }

      bool extendLive=false;
      datetime rightAnchorLocked=ResolveSiblingRenderEnd(g,g.sibs[s],nowTime);
      if(rightAnchorLocked<=0)
         rightAnchorLocked=generationWindowEnd;

      if(rightAnchorLocked<=poiHtfLeftAnchor)
         rightAnchorLocked=poiHtfLeftAnchor+CCTModelHTFSeconds();

      datetime tooltipTriggerTime=(visualState==SS_TRIGGERED || IsResolvedPOIState(visualState)) ? g.triggerTime : 0;
      DrawPOILine(genKey,s,g.sibs[s].level,g.bull,visualState,
                  poiHtfLeftAnchor,poiLtfLeftAnchor,rightAnchorLocked,extendLive,
                  g.sibs[s].c1Time,tooltipTriggerTime);

      KeepObj(ObjN(genKey,"POI_"+IntegerToString(s)+"_H"),keep,keepCount);
      KeepObj(ObjN(genKey,"POI_"+IntegerToString(s)+"_L"),keep,keepCount);
     }
  }

/*
Purpose: Draw the TS overlay that belongs to one generation.
Constitution: TS is opposing-side virgin wick liquidity information and must not be coupled to CO drawing.
Inputs: g - generation record, currentBiasBull - current HTF bias direction, keep - keep-list array, keepCount - keep count.
Outputs: TS line drawn or removed and tracked for pruning.
*/
void DrawGenerationTSOverlay(const GenInfo &g,bool currentBiasBull,string &keep[],int &keepCount)
  {
   string genKey=GenKey(g.bull,g.birthTime);

   bool showTS=GenerationShouldShowTS(g,currentBiasBull);
   DrawTSLevel(genKey,g.bull,g.tsDisplayLevel,g.tsDisplayWickTime,g.tsDisplayLtfAnchor,g.tsFirstTouchTime,g.tsConfirmed,showTS);
   if(showTS)
      KeepObj(ObjN(genKey,"TS"),keep,keepCount);
  }

/*
Purpose: Draw the CO overlay that belongs to one in-bias generation.
Constitution: CO uses in-bias virgin wick structure only and stays independent from TS hint/level rendering.
Inputs: g - generation record, currentBiasBull - current HTF bias direction, keep - keep-list array, keepCount - keep count.
Outputs: CO line drawn or removed and tracked for pruning.
*/
void DrawGenerationCOOverlay(const GenInfo &g,bool currentBiasBull,string &keep[],int &keepCount)
  {
   string genKey=GenKey(g.bull,g.birthTime);

   bool showCO=GenerationShouldShowCO(g,currentBiasBull);
   DrawCOLine(genKey,g.bull,g.coPrice,g.coTime,g.coLtfAnchor,g.triggerTime,g.coTouchTime,showCO);
   if(showCO)
      KeepObj(ObjN(genKey,"CO"),keep,keepCount);
  }

/*
Purpose: Draw scanner evidence and locked synthetic execution geometry for one generation.
Constitution: FVG/IFVG, fib anchors, and execution boxes must reflect scanner truth rather than a separate visual guess.
Inputs: g - generation record, keep - keep-list array, keepCount - keep count.
Outputs: FVG boxes and synthetic execution objects drawn and tracked for pruning.
*/
void DrawGenerationFVGAndExecution(GenInfo &g,string &keep[],int &keepCount)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   datetime fvgFloor=GenerationFVGScanFloor(g);

   // CCT_PRETRIGGER_C3_IFVG_TOGGLE_V2
   // false: trigger-only behavior. true: show only active scanner-selected C3 IFVG after C1 and before final trigger.
   bool confirmedIFVG=(g.triggerTime>0);
   bool showFVGs=(!g.dormant && g.c3FvgIdx>=0 && (confirmedIFVG || Inp_ShowPreTriggerC3IFVG));

   for(int f=0;f<g.nFvgs;f++)
     {
      bool relevant=showFVGs && f==g.c3FvgIdx && g.fvgs[f].t1>=fvgFloor;
      bool activeTrigger=(g.c3FvgIdx==f);
      DrawFVGBox(genKey,f,g.fvgs[f],g.bull,activeTrigger,relevant,confirmedIFVG);
      if(relevant && !g.fvgs[f].stale && !g.fvgs[f].superseded && !g.fvgs[f].invalidInv)
         KeepObj(ObjN(genKey,"FVG_"+IntegerToString(f)),keep,keepCount);
     }

   bool showExec=(g.triggerTime>0 && g.visualEntry>0.0 && g.rawSL>0.0 && g.rawTP>0.0);
   DrawSyntheticExecutionObjects(genKey,g.bull,g.triggerTime,g.visualEntryTime,g.visualEntry,g.rawSL,g.rawTP,
                                 g.anchorATime,g.anchorBTime,g.anchorA,g.anchorB,g.slBranch,g.modelType,g.sweepCount,
                                 g.outcome,g.exitTime,g.coPrice,g.coTouchTime,
                                 g.beGeneralApplied,g.beCoApplied,g.bePrice,g.beLeftAnchorTime,g.beTriggerTime,
                                 g.beGeneralPrice,g.beGeneralLeftAnchorTime,g.beGeneralTime,
                                 g.beCoPrice,g.beCoLeftAnchorTime,g.beCoTime,g.fibRawSL);
   if(showExec)
     {
      KeepObj(ObjN(genKey,"EXEC_ENTRY"),keep,keepCount);
      KeepObj(ObjN(genKey,"EXEC_SL_BOX"),keep,keepCount);
      KeepObj(ObjN(genKey,"EXEC_TP_BOX"),keep,keepCount);
      KeepObj(ObjN(genKey,"EXEC_BE"),keep,keepCount);
      KeepObj(ObjN(genKey,"EXEC_BE_CO"),keep,keepCount);
      KeepObj(ObjN(genKey,"EXEC_BE_GLOBAL_THR"),keep,keepCount);
      KeepObj(ObjN(genKey,"EXEC_BE_CO_THR"),keep,keepCount);
      if(Inp_ShowFibExtensions)
        {
         KeepObj(ObjN(genKey,"EXEC_FIB_SHALLOW"),keep,keepCount);
         KeepObj(ObjN(genKey,"EXEC_FIB_DEEP"),keep,keepCount);
         KeepObj(ObjN(genKey,"EXEC_FIB_RAW"),keep,keepCount);
        }
     }
  }

/*
Purpose: Draw one generation-owned action pillar using generation visibility rather than raw birth-list visibility.
Constitution: AP visibility must follow the generation's visible POI/execution lifecycle; an expired-only generation must not leave a stale AP.
Inputs: g - generation record, allowDeadDisplay - whether dead-generation APs may be shown, keep - keep-list array, keepCount - keep count.
Outputs: Generation AP drawn or removed and tracked for pruning.
*/
void DrawGenerationActionPillar(const GenInfo &g,bool allowDeadDisplay,string &keep[],int &keepCount)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   bool relevant=false;
   string stateLabel="Hidden";

   int validCount=0;
   int activeCount=0;
   int inactiveCount=0;
   int triggeredCount=0;
   int resolvedCount=0;
   int deadCount=0;
   datetime primaryC1=0;

   bool allWindowExpired=(g.nSibs>0);

   for(int s=0;s<g.nSibs;s++)
     {
      SIB_STATE st=g.sibs[s].state;

      if(st==SS_VALID)
         validCount++;
      else if(st==SS_ACTIVE)
         activeCount++;
      else if(st==SS_INACTIVE)
         inactiveCount++;
      else if(st==SS_TRIGGERED)
         triggeredCount++;
      else if(IsResolvedPOIState(st))
         resolvedCount++;
      else if(IsDeadPOIState(st))
         deadCount++;

      if(st!=SS_DEAD_WINDOW_EXPIRED)
         allWindowExpired=false;

      if(g.sibs[s].c1Time>0 && (primaryC1<=0 || g.sibs[s].c1Time<primaryC1))
         primaryC1=g.sibs[s].c1Time;
     }

   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs && g.sibs[g.activeSibIdx].c1Time>0)
      primaryC1=g.sibs[g.activeSibIdx].c1Time;

   // Hard cleanup: if every POI in the generation died only by window expiry,
   // there is no chart-worthy AP left to show.
   if(g.nSibs<=0 || allWindowExpired)
     {
      DrawActionPillar(genKey,g.birthTime,ActionPillarTime(g.birthTime),false,stateLabel,
                       g.bull,g.nSibs,validCount,activeCount,inactiveCount,triggeredCount,
                       resolvedCount,deadCount,g.activeSibIdx,primaryC1,g.triggerTime,
                       ModelTypeLabel(g.modelType));
      return;
     }

   if(!g.dormant)
     {
      bool configVisible=GenerationMatchesConfiguredHours(g);
      bool executionVisible=(GenerationHasExecutionState(g) && configVisible);
      bool liveVisible=(GenerationHasVisibleState(g) && configVisible);
      bool currentDayActivation=(GenerationHasCurrentDayActivation(g) && !allWindowExpired && configVisible);
      bool deadVisible=GenerationShouldShowDeadAP(g,allowDeadDisplay);

      relevant=executionVisible || liveVisible || currentDayActivation || deadVisible;

      if(executionVisible)
         stateLabel="Triggered";
      else if(activeCount>0)
         stateLabel="Active";
      else if(triggeredCount>0)
         stateLabel="Triggered";
      else if(liveVisible && validCount>0)
         stateLabel="Valid";
      else if(liveVisible && inactiveCount>0)
         stateLabel="Inactive";
      else if(currentDayActivation)
         stateLabel="Activated";
      else if(deadVisible)
         stateLabel="Dead";
     }

   DrawActionPillar(genKey,g.birthTime,ActionPillarTime(g.birthTime),relevant,stateLabel,
                    g.bull,g.nSibs,validCount,activeCount,inactiveCount,triggeredCount,
                    resolvedCount,deadCount,g.activeSibIdx,primaryC1,g.triggerTime,
                    ModelTypeLabel(g.modelType));

   if(relevant)
      KeepObj(ObjN(genKey,"AP"),keep,keepCount);
  }


bool CCTCandidateGateDebugShouldPrint(const string key)
  {
   static string printedKeys[];
   static int printedCount=0;

   if(key=="")
      return true;

   for(int i=0;i<printedCount;i++)
      if(printedKeys[i]==key)
         return false;

   if(printedCount>512)
     {
      ArrayResize(printedKeys,0);
      printedCount=0;
     }

   ArrayResize(printedKeys,printedCount+1,64);
   printedKeys[printedCount]=key;
   printedCount++;
   return true;
  }

void CCTDebugCandidateVisualGates(WickInfo &bulls[],int nBull,WickInfo &bears[],int nBear,bool currentBiasBull,datetime candidateBarTime,MqlRates &ltf[],int nl)
  {
   // CCT_CANDIDATE_VISUAL_GATE_DEBUG_V1
   // Debug-only visual gate telemetry. No behavior change.
   if(!CCTDebugEnabled())
      return;

   int bullRaw=0;
   int bearRaw=0;
   int bullBiasOk=0;
   int bearBiasOk=0;
   int bullAuthOk=0;
   int bearAuthOk=0;
   int bullLineOk=0;
   int bearLineOk=0;
   int bullKeepOk=0;
   int bearKeepOk=0;
   int bullApOk=0;
   int bearApOk=0;

   bool authOk=(candidateBarTime>0 && GenerationHasAuthorizedExec(candidateBarTime));

   for(int i=0;i<nBull;i++)
     {
      if(bulls[i].state!=WS_CANDIDATE)
         continue;

      bullRaw++;
      if(currentBiasBull)
         bullBiasOk++;
      if(currentBiasBull && authOk)
         bullAuthOk++;
      bool lineOk=CandidateLineActiveFromLTF(true,bulls[i].level,candidateBarTime,ltf,nl);
      if(currentBiasBull && authOk && lineOk)
         bullLineOk++;
      if(currentBiasBull && authOk && lineOk && Inp_ShowCandidates)
         bullKeepOk++;
      if(currentBiasBull && CandidateAPQuarterActiveFromLTF(true,bulls[i].level,candidateBarTime,ltf,nl))
         bullApOk++;
     }

   for(int i=0;i<nBear;i++)
     {
      if(bears[i].state!=WS_CANDIDATE)
         continue;

      bearRaw++;
      if(!currentBiasBull)
         bearBiasOk++;
      if(!currentBiasBull && authOk)
         bearAuthOk++;
      bool lineOk=CandidateLineActiveFromLTF(false,bears[i].level,candidateBarTime,ltf,nl);
      if(!currentBiasBull && authOk && lineOk)
         bearLineOk++;
      if(!currentBiasBull && authOk && lineOk && Inp_ShowCandidates)
         bearKeepOk++;
      if(!currentBiasBull && CandidateAPQuarterActiveFromLTF(false,bears[i].level,candidateBarTime,ltf,nl))
         bearApOk++;
     }

   string key=StringFormat("%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d",
                           _Symbol,
                           TimeToString(candidateBarTime,TIME_DATE|TIME_MINUTES),
                           currentBiasBull ? 1 : 0,
                           Inp_ShowCandidates ? 1 : 0,
                           authOk ? 1 : 0,
                           bullRaw,bearRaw,bullKeepOk,bearKeepOk,bullApOk,bearApOk);

   if(!CCTCandidateGateDebugShouldPrint(key))
      return;

   CCTJournalLine(StringFormat("[CCT CANDIDATE VISUAL GATE] symbol=%s | bias=%s | showCandidates=%s | candidateBar=%s | auth=%s | nBull=%d raw=%d biasOk=%d authOk=%d lineOk=%d keepOk=%d apOk=%d | nBear=%d raw=%d biasOk=%d authOk=%d lineOk=%d keepOk=%d apOk=%d",
                               _Symbol,
                               currentBiasBull ? "bull" : "bear",
                               Inp_ShowCandidates ? "true" : "false",
                               candidateBarTime>0 ? TimeToString(ToNY(candidateBarTime),TIME_DATE|TIME_MINUTES) : "-",
                               authOk ? "true" : "false",
                               nBull,bullRaw,bullBiasOk,bullAuthOk,bullLineOk,bullKeepOk,bullApOk,
                               nBear,bearRaw,bearBiasOk,bearAuthOk,bearLineOk,bearKeepOk,bearApOk));
  }
/*
Purpose: Draw default-visible candidate action pillars for every live candidate POI.
Constitution: Latest user clarification that candidate POI APs show by default alongside candidate POIs.
Inputs: cands - candidate/virgin wick array, n - count, bull - direction, candidateBarTime - current HTF candidate bar open time, keep - keep-list array, keepCount - keep count.
Outputs: Candidate APs drawn and tracked for pruning.
*/
void DrawCandidateActionPillars(WickInfo &cands[],int n,bool bull,datetime candidateBarTime,MqlRates &ltf[],int nl,string &keep[],int &keepCount)
  {
   int candidateCount=0;
   int firstIdx=-1;
   for(int i=0;i<n;i++)
     {
      if(cands[i].state==WS_CANDIDATE &&
         CandidateAPQuarterActiveFromLTF(bull,cands[i].level,candidateBarTime,ltf,nl))
        {
         if(firstIdx<0)
            firstIdx=i;
         candidateCount++;
        }
     }

   bool relevant=(Inp_ShowCandidates && candidateBarTime>0 && GenerationHasAuthorizedExec(candidateBarTime) &&
                  candidateCount>0 && firstIdx>=0);
   if(relevant)
     {
      DrawCandidateActionPillar(bull,cands[firstIdx].barTime,candidateBarTime,cands[firstIdx].level,true,1,candidateCount);
      KeepObj(ObjN(GenKey(bull,candidateBarTime),"CAP"),keep,keepCount);
      return;
     }

   DrawCandidateActionPillar(bull,candidateBarTime,candidateBarTime,0.0,false,0,0);
  }

/*
Purpose: Return whether this EA currently owns an open broker position on this symbol.
Constitution: Non-visual tester performance helper only; keeps management scans alive while a real tester position is open.
Inputs: None.
Outputs: True when an open position belongs to this EA symbol/magic pair.
*/
bool CCTTesterHasOpenPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      string sym=PositionGetSymbol(i);
      if(sym!=_Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC)==CCTEffectiveMagic())
         return true;
     }

   return false;
  }

/*
Purpose: Return whether a closed LTF bar is the final LTF bar of its containing HTF candle.
Constitution: Non-visual tester must still rebuild on HTF boundaries so births, bias flips, and execution-window expiry remain chronological.
Inputs: ltfClosedBar - closed LTF bar open time.
Outputs: True when the next LTF open reaches or passes the containing HTF close.
*/
bool CCTTesterIsHTFBoundary(datetime ltfClosedBar)
  {
   if(ltfClosedBar<=0)
      return false;

   int ltfSec=(int)PeriodSeconds(LTF());
   int htfSec=CCTModelHTFSeconds();
   if(ltfSec<=0 || htfSec<=0)
      return false;

   datetime htfOpen=HTFBarOpenForTime(ltfClosedBar);
   if(htfOpen<=0)
      return false;

   long barOpen=(long)ltfClosedBar;
   long barClose=barOpen+(long)ltfSec;
   long htfClose=(long)htfOpen+(long)htfSec;

   return (barClose>=htfClose);
  }

/*
Purpose: Return whether a closed LTF bar belongs to a selected execution hour or immediate C1 carry span.
Constitution: C1 must be detected inside selected execution ownership; C2/C3 may complete in the following HTF carry span after authorized C1.
Inputs: ltfClosedBar - closed LTF bar open time.
Outputs: True when non-visual tester should perform the full scanner replay for this bar.
*/
bool CCTTesterIsExecOrCarryBar(datetime ltfClosedBar)
  {
   if(ltfClosedBar<=0)
      return false;

   if(!Inp_SessionFilter)
      return true;

   MqlDateTime ny={};
   TimeToStruct(ToNY(ltfClosedBar),ny);

   int htfHours=(int)(CCTModelHTFSeconds()/3600);
   if(htfHours<1)
      htfHours=1;

   int carrySpan=htfHours*2;
   if(carrySpan<1)
      carrySpan=1;

   for(int offset=0;offset<carrySpan;offset++)
     {
      datetime candidateTime=ltfClosedBar-(datetime)(offset*3600);
      if(CCTModelAnyAuthAllows(candidateTime))
         return true;
     }

   return false;
  }

/*
Purpose: Gate expensive full-state rebuilds during non-visual strategy tests.
Constitution: Live charts and visual tester retain full behaviour; non-visual tester runs the scanner only on HTF boundaries, execution/carry spans, and open-position management.
Inputs: ltfClosedBar - latest closed LTF bar being considered.
Outputs: True when RefreshState should perform the expensive full replay.
*/
bool CCTShouldRunNonVisualTesterScan(datetime ltfClosedBar)
  {
   if(!IsNonVisualTesterRun())
      return true;

   if(ltfClosedBar<=0)
      return false;

   if(CCTTesterIsHTFBoundary(ltfClosedBar))
      return true;

   if(CCTTesterIsExecOrCarryBar(ltfClosedBar))
      return true;

   // Broker position management is handled on every tick by CCTUpdatePositionBE()
   // and OnTradeTransaction(); it does not need a full historical scanner replay
   // outside birth, execution, and carry-over bars in non-visual tester mode.
   return false;
  }

string CCTNonVisualReplayKey()
  {
   return _Symbol+"|LTF="+IntegerToString((int)LTF())+"|HTF="+IntegerToString((int)HTF());
  }

bool CCTNonVisualCachedBarEdge(double &prevCls,double &cls)
  {
   datetime current=iTime(_Symbol,LTF(),1);
   if(current<=0)
      return false;

   cls=iClose(_Symbol,LTF(),1);
   prevCls=iClose(_Symbol,LTF(),2);
   if(prevCls<=0.0)
      prevCls=iOpen(_Symbol,LTF(),1);

   return (cls>0.0 && prevCls>0.0);
  }

bool CCTNonVisualCachedGenerationNeedsScan(const GenInfo &g,datetime ltfClosedBar,double prevCls,double cls)
  {
   if(AllSiblingsDead(g))
      return false;

   if(IsGenerationWindowExpired(g,ltfClosedBar))
      return true;

   if(GenerationBiasIsOppositeAt(g,ltfClosedBar))
      return true;

   if(g.triggerTime>0)
      return false;

   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs && g.sibs[g.activeSibIdx].state==SS_ACTIVE)
      return true;

   bool carry=GenerationHasAuthorizedC1Carry(g);
   if(carry)
      return true;

   for(int s=0;s<g.nSibs;s++)
     {
      SIB_STATE st=g.sibs[s].state;
      bool eligible=(st==SS_VALID || st==SS_DORMANT || st==SS_INACTIVE);
      if(!eligible)
         continue;

      if(IsC1EdgeCross(g.bull,prevCls,cls,g.sibs[s].level))
         return true;
     }

   return false;
  }

bool CCTNonVisualCachedReplayNeedsScan(datetime ltfClosedBar)
  {
   if(ltfClosedBar<=0)
      return false;

   if(CCTTesterIsHTFBoundary(ltfClosedBar))
      return true;

   string key=CCTNonVisualReplayKey();
   if(g_nvReplayCount<=0 || g_nvReplayKey!=key)
      return true;

   double prevCls=0.0;
   double cls=0.0;
   if(!CCTNonVisualCachedBarEdge(prevCls,cls))
      return true;

   int n=g_nvReplayCount;
   if(n>ArraySize(g_nvReplayGens))
      n=ArraySize(g_nvReplayGens);
   for(int i=0;i<n;i++)
     {
      if(CCTNonVisualCachedGenerationNeedsScan(g_nvReplayGens[i],ltfClosedBar,prevCls,cls))
         return true;
     }

   int nc=g_nvReplayCounterCount;
   if(nc>ArraySize(g_nvReplayCounterGens))
      nc=ArraySize(g_nvReplayCounterGens);
   for(int i=0;i<nc;i++)
     {
      if(CCTNonVisualCachedGenerationNeedsScan(g_nvReplayCounterGens[i],ltfClosedBar,prevCls,cls))
         return true;
     }

   return false;
  }

/*
Purpose: Identify no-BE/no-management research tester runs where per-tick broker management is unnecessary.
Constitution: Non-visual tester may suppress scheduling work only; scanner truth, broker SL/TP, and research telemetry must remain shared.
Inputs: None.
Outputs: True when only closed-bar scanner pulses and MT5-native SL/TP handling are needed.
*/
bool CCTNonVisualTesterCanSkipIntrabarManagement()
  {
   if(!IsNonVisualTesterRun())
      return false;

   if(CCTRuntimeBEGlobalEnabled() || CCTRuntimeBECOEnabled())
      return false;

   if(CCTEffectiveMinOpenTPEnabled())
      return false;

   if(CCTEffectiveDailyLossGuard() || CCTEffectiveNewsFilter() || Inp_WeekendGuard)
      return false;

   return true;
  }

void CCTStoreNonVisualReplayCache(GenInfo &gens[],int nGens,datetime ltfClosedBar)
  {
   int cap=ArraySize(g_nvReplayGens);
   g_nvReplayCount=nGens;
   if(g_nvReplayCount>cap)
      g_nvReplayCount=cap;
   for(int i=0;i<g_nvReplayCount;i++)
      g_nvReplayGens[i]=gens[i];

   g_nvReplayTime=ltfClosedBar;
   g_nvReplayKey=CCTNonVisualReplayKey();
  }

void CCTStoreNonVisualCounterReplayCache(GenInfo &gens[],int nGens)
  {
   int cap=ArraySize(g_nvReplayCounterGens);
   g_nvReplayCounterCount=nGens;
   if(g_nvReplayCounterCount>cap)
      g_nvReplayCounterCount=cap;
     for(int i=0;i<g_nvReplayCounterCount;i++)
        g_nvReplayCounterGens[i]=gens[i];
  }

/*
Purpose: Apply persisted execution/resolution truth to a rebuilt generation set before it is cached or re-used.
Constitution: Once a generation has triggered or resolved, later replay passes must not rediscover a newer C1/C2/C3 path for the same generation key.
Inputs: gens - generation array, nGens - generation count.
Outputs: gens updated from execution records when records exist.
*/
void CCTApplyExecutionRecordsToSet(GenInfo &gens[],int nGens)
  {
   int cap=ArraySize(gens);
   if(nGens>cap)
      nGens=cap;

   for(int i=0;i<nGens;i++)
      CCTApplyExecutionRecordToGeneration(gens[i]);
  }

/*
Purpose: Preserve terminal sibling outcomes across tester full rebuilds.
Constitution: A POI killed or resolved at an earlier closed-bar edge cannot mutate into a later synthetic/window-consumed state just because the scanner rebuilt history at an HTF boundary.
Inputs: gens - freshly rebuilt generations, cached - prior closed-bar scanner truth.
Outputs: Terminal sibling states copied into the rebuilt generation set.
*/
void CCTMergeCachedTerminalStates(GenInfo &gens[],int nGens,GenInfo &cached[],int nCached,datetime scanEnd)
  {
   if(nGens<=0 || nCached<=0)
      return;

   int genCap=ArraySize(gens);
   int cacheCap=ArraySize(cached);
   if(nGens>genCap)
      nGens=genCap;
   if(nCached>cacheCap)
      nCached=cacheCap;

   double tol=MathMax(_Point,1e-8);

   for(int i=0;i<nGens;i++)
     {
      string dstKey=GenKey(gens[i].bull,gens[i].birthTime);
      for(int j=0;j<nCached;j++)
        {
         if(dstKey!=GenKey(cached[j].bull,cached[j].birthTime))
            continue;

         if(cached[j].triggerTime>0 && gens[i].triggerTime!=cached[j].triggerTime)
           {
            gens[i].triggerTime=cached[j].triggerTime;
            gens[i].activeSibIdx=cached[j].activeSibIdx;
            gens[i].dormant=false;
            gens[i].modelType=cached[j].modelType;
            gens[i].sweepCount=cached[j].sweepCount;
            gens[i].visualEntry=cached[j].visualEntry;
            gens[i].visualEntryTime=cached[j].visualEntryTime;
            gens[i].rawSL=cached[j].rawSL;
            gens[i].rawTP=cached[j].rawTP;
            gens[i].outcome=cached[j].outcome;
            gens[i].exitTime=cached[j].exitTime;
            gens[i].exitPrice=cached[j].exitPrice;
           }

         // CCT_IFVG_CACHE_MERGE_VISUAL_V1
         // IFVG visuals are scanner-owned: DrawGenerationFVGAndExecution requires triggerTime, c3FvgIdx, nFvgs, and fvgs[].
         // When cached trigger/execution truth is merged back into a rebuilt generation, preserve the winning IFVG state too.
         if(cached[j].triggerTime>0 && cached[j].c3FvgIdx>=0)
           {
            int genFvgCap=ArraySize(gens[i].fvgs);
            int cachedFvgCap=ArraySize(cached[j].fvgs);
            int copyFvgs=cached[j].nFvgs;
            if(copyFvgs>genFvgCap)
               copyFvgs=genFvgCap;
            if(copyFvgs>cachedFvgCap)
               copyFvgs=cachedFvgCap;
            if(copyFvgs<0)
               copyFvgs=0;

            gens[i].nFvgs=copyFvgs;
            for(int cf=0;cf<copyFvgs;cf++)
               gens[i].fvgs[cf]=cached[j].fvgs[cf];

            gens[i].c3FvgIdx=cached[j].c3FvgIdx;
            if(gens[i].c3FvgIdx<0 || gens[i].c3FvgIdx>=gens[i].nFvgs)
               gens[i].c3FvgIdx=-1;
           }

         for(int s=0;s<gens[i].nSibs;s++)
           {
            for(int cs=0;cs<cached[j].nSibs;cs++)
              {
               if(MathAbs(gens[i].sibs[s].level-cached[j].sibs[cs].level)>tol)
                  continue;

               SIB_STATE cachedState=cached[j].sibs[cs].state;
               if(!IsDeadPOIState(cachedState) && !IsResolvedPOIState(cachedState) && cachedState!=SS_TRIGGERED)
                  continue;

               bool currentExecuted=(gens[i].sibs[s].state==SS_TRIGGERED || IsResolvedPOIState(gens[i].sibs[s].state));
               bool cachedDead=IsDeadPOIState(cachedState);

               if(cachedDead)
                 {
                  datetime terminalTime=cached[j].sibs[cs].c3Time;
                  if(terminalTime<=0)
                     terminalTime=cached[j].sibs[cs].c2Time;
                  if(terminalTime<=0)
                     terminalTime=cached[j].sibs[cs].c1Time;

                  // CCT_CACHE_DEAD_MUST_BE_STRICTLY_PRIOR_TO_SCAN_EDGE_V3
                  // Cached dead state is historical authority only if it ended strictly
                  // before this scan edge. Same-edge cached death must not pre-kill
                  // the current scan before a valid trigger can execute.
                  if(!currentExecuted && scanEnd>0 && (terminalTime<=0 || terminalTime>=scanEnd))
                     continue;

                  // CCT_CACHE_DEAD_MUST_NOT_OVERRIDE_SAME_EDGE_TRIGGER_V2
                  // If the current generation already has a trigger/resolution, cached
                  // death may override only if the cached terminal event was strictly
                  // before the current trigger.
                  if(currentExecuted && gens[i].triggerTime>0 && (terminalTime<=0 || gens[i].triggerTime<=terminalTime))
                     continue;
                 }

                datetime preciseWickTime=gens[i].sibs[s].wickTime;
                datetime preciseLtfAnchor=gens[i].sibs[s].ltfAnchor;
                gens[i].sibs[s]=cached[j].sibs[cs];
                if(preciseWickTime>0)
                   gens[i].sibs[s].wickTime=preciseWickTime;
                if(preciseLtfAnchor>0)
                   gens[i].sibs[s].ltfAnchor=preciseLtfAnchor;

               if(cachedDead)
                 {
                  if(gens[i].activeSibIdx==s)
                     gens[i].activeSibIdx=-1;

                  if(currentExecuted)
                    {
                     gens[i].triggerTime=0;
                     gens[i].visualEntry=0.0;
                     gens[i].visualEntryTime=0;
                     gens[i].rawSL=0.0;
                     gens[i].rawTP=0.0;
                     gens[i].outcome=SS_UNKNOWN_OUTCOME;
                     gens[i].exitTime=0;
                     gens[i].exitPrice=0.0;
                    }
                 }

               break;
              }
           }

         break;
        }
     }
  }

/*
Purpose: Advance cached non-visual tester scanner state without rebuilding HTF births.
Constitution: Non-visual tester uses the same scanner truth, but active/crossing generations may be advanced from the cached generation set between HTF boundary rebuilds.
Inputs: ltfEnd - latest closed LTF bar to process.
Outputs: True when the cached scanner pulse handled the bar and RefreshState should skip a full rebuild.
*/
/*
Purpose: Return the minimal LTF window needed for cached non-visual scanner pulses.
Constitution: Cached tester pulses must advance existing scanner truth without repeatedly replaying the whole retained NY-day horizon.
Inputs: ltfEnd - latest closed LTF bar.
Outputs: Server-time scan start for the incremental cached pulse.
*/
datetime CCTNonVisualCachedPulseScanStart(datetime ltfEnd)
  {
   // CCT_NV_CACHED_PULSE_INCREMENTAL_WINDOW_V1
   datetime floor=GenerationScanStart();
   if(ltfEnd<=0)
      return floor;

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;

   // Keep enough left context for C1 previous-close edge logic and 3-candle FVG formation.
   datetime start=(g_nvReplayTime>0) ? (g_nvReplayTime-(datetime)(ltfSec*4)) : (ltfEnd-(datetime)(ltfSec*8));

   if(start<floor)
      start=floor;
   if(start>ltfEnd)
      start=ltfEnd;

   return start;
  }

bool CCTRunNonVisualCachedScannerPulse(datetime ltfEnd)
  {
   if(ltfEnd<=0)
      return false;

   string key=CCTNonVisualReplayKey();
   if(g_nvReplayCount<=0 || g_nvReplayKey!=key)
      return false;

   MqlRates ltf[];
   datetime cachedPulseStart=CCTNonVisualCachedPulseScanStart(ltfEnd);
      int nl=CopyLTFWindow(cachedPulseStart,ltfEnd,ltf);
   ArraySetAsSeries(ltf,false);

   int actual=ArraySize(ltf);
   if(nl<=0 || actual<=0)
      return false;
   if(nl>actual)
      nl=actual;

   datetime htfCurrent=iTime(_Symbol,HTF(),0);
   MqlDateTime htfNY={};
   TimeToStruct(ToNY(htfCurrent),htfNY);
   bool isExecBarOpen=CCTModelAnyAuthAllows(htfCurrent);

   ScanGenerationSet(g_nvReplayGens,g_nvReplayCount,ltf,nl,isExecBarOpen,htfNY.hour);
   if(g_nvReplayCounterCount>0)
      ScanGenerationSet(g_nvReplayCounterGens,g_nvReplayCounterCount,ltf,nl,isExecBarOpen,htfNY.hour);
   CCTApplyExecutionRecordsToSet(g_nvReplayGens,g_nvReplayCount);
   CCTApplyExecutionRecordsToSet(g_nvReplayCounterGens,g_nvReplayCounterCount);

   for(int i=0;i<g_nvReplayCount;i++)
     {
      if(CCTDebugEnabled() && g_nvReplayGens[i].triggerTime==ltfEnd)
         CCTJournalLine(StringFormat("[CCT DBG] NV CACHED TRIGGER | main gen=%s trigger=%s",
                                     GenKey(g_nvReplayGens[i].bull,g_nvReplayGens[i].birthTime),
                                     TimeToString(ToNY(ltfEnd),TIME_DATE|TIME_MINUTES)));
       CCTTryExecuteGeneration(g_nvReplayGens[i],ltfEnd);
      }

   CCTApplyExecutionRecordsToSet(g_nvReplayGens,g_nvReplayCount);
   CCTApplyExecutionRecordsToSet(g_nvReplayCounterGens,g_nvReplayCounterCount);
   CCTStoreNonVisualReplayCache(g_nvReplayGens,g_nvReplayCount,ltfEnd);
   CCTStoreNonVisualCounterReplayCache(g_nvReplayCounterGens,g_nvReplayCounterCount);

   return true;
  }

bool CCTIsVisualTesterRun()
  {
   return ((bool)MQLInfoInteger(MQL_TESTER) && (bool)MQLInfoInteger(MQL_VISUAL_MODE));
  }

bool CCTEventFallsInClosedLTFBar(datetime eventTime,datetime ltfClosedBar)
  {
   if(eventTime<=0 || ltfClosedBar<=0)
      return false;

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      return (eventTime==ltfClosedBar);

   return (eventTime>=ltfClosedBar && eventTime<ltfClosedBar+(datetime)ltfSec);
  }

bool CCTGenerationHasVisualEventAt(GenInfo &g,datetime ltfClosedBar)
  {
   if(CCTEventFallsInClosedLTFBar(g.triggerTime,ltfClosedBar) ||
      CCTEventFallsInClosedLTFBar(g.visualEntryTime,ltfClosedBar) ||
      CCTEventFallsInClosedLTFBar(g.exitTime,ltfClosedBar) ||
      CCTEventFallsInClosedLTFBar(g.coTouchTime,ltfClosedBar) ||
      CCTEventFallsInClosedLTFBar(g.beTriggerTime,ltfClosedBar))
      return true;

   for(int s=0;s<g.nSibs;s++)
     {
      if(CCTEventFallsInClosedLTFBar(g.sibs[s].c1Time,ltfClosedBar) ||
         CCTEventFallsInClosedLTFBar(g.sibs[s].c2Time,ltfClosedBar) ||
         CCTEventFallsInClosedLTFBar(g.sibs[s].c3Time,ltfClosedBar))
         return true;
     }

   return false;
  }

bool CCTGenerationSetHasVisualEventAt(GenInfo &gens[],int nGens,datetime ltfClosedBar)
  {
   for(int i=0;i<nGens;i++)
     {
      if(CCTGenerationHasVisualEventAt(gens[i],ltfClosedBar))
         return true;
     }
   return false;
  }

/*
Purpose: Throttle visual tester redraws without throttling scanner or broker trigger truth.
Constitution: Visual tester may render less often, but scanner state must still be rebuilt on each closed LTF bar that OnTick processes.
Inputs: ltfClosedBar - latest closed LTF bar, gens/counterGens - freshly scanned generation sets.
Outputs: True when the expensive chart-object reconstruction should run.
*/
bool CCTVisualTesterRenderDue(datetime ltfClosedBar,GenInfo &gens[],int nGens,GenInfo &counterGens[],int nCounterGens)
  {
   if(!CCTIsVisualTesterRun())
      return true;

   if(ltfClosedBar<=0)
      return false;

   static datetime s_lastVisualTesterRender=0;
   bool due=false;

   if(s_lastVisualTesterRender<=0)
      due=true;
   else if(CCTTesterIsHTFBoundary(ltfClosedBar))
      due=true;
   else if(CCTGenerationSetHasVisualEventAt(gens,nGens,ltfClosedBar) ||
           CCTGenerationSetHasVisualEventAt(counterGens,nCounterGens,ltfClosedBar))
      due=true;
   else
     {
      int ltfSec=(int)PeriodSeconds(LTF());
      if(ltfSec<=0)
         ltfSec=60;
      int intervalBars=CCTTesterIsExecOrCarryBar(ltfClosedBar) ? 5 : 120;
      if((long)(ltfClosedBar-s_lastVisualTesterRender)>=(long)ltfSec*intervalBars)
         due=true;
     }

   if(due)
      s_lastVisualTesterRender=ltfClosedBar;
   return due;
  }

/*
Purpose: Rebuild scanner state and optionally render chart objects from the shared live/tester truth path.
Constitution: Ch. 26, Ch. 27, Ch. 29, tester-performance rules, and latest user clarification that live, visual tester, and non-visual tester must share one scanner truth path.
Inputs: renderVisuals - when true, create/update chart objects; when false, run scanner logic only.
Outputs: None.
*/
void RefreshState(bool renderVisuals)
  {
   if(renderVisuals && IsNonVisualTesterRun())
      return;

   if(renderVisuals && g_cctDeinitRenderPurgeModeV1)
     {
      // CCT_DEINIT_RENDER_PURGE_NO_REDRAW_OBJECTS_V1
      // Run the visual reconciler's destructive side only: empty keep-list,
      // prune owned objects, clear dashboard resources, redraw, and return
      // before scanner/draw code can recreate any CCT object.
      string keep[];
      int keepCount=0;
      PruneCCTObjects(keep,keepCount);
      g_dashCleared=false;
      ClearDashboards();
      ChartRedraw(0);
      return;
     }

   bool perfNonVisual=(!renderVisuals && IsNonVisualTesterRun());
   if(perfNonVisual)
      g_perfNvRefreshCalls++;

   datetime ltfEnd=iTime(_Symbol,LTF(),1);
   if(ltfEnd<=0)
      ltfEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE)-(datetime)PeriodSeconds(LTF());

   // Tester closed-bar throttle:
   // The scanner is closed-bar driven. Rebuilding on every tester tick is wasteful and
   // was the main reason a one-month non-visual test took minutes instead of seconds.
   static datetime s_lastTesterLogicClosed=0;
   static datetime s_lastTesterVisualClosed=0;
   static string   s_lastTesterLogicKey="";
   static string   s_lastTesterVisualKey="";

   bool testerRun=(MQLInfoInteger(MQL_TESTER)!=0);
   if(testerRun && ltfEnd>0)
     {
      string scanKey=_Symbol+"|LTF="+IntegerToString((int)LTF())+"|HTF="+IntegerToString((int)HTF());

      if(renderVisuals)
        {
         if(s_lastTesterVisualClosed==ltfEnd && s_lastTesterVisualKey==scanKey)
            return;
         s_lastTesterVisualClosed=ltfEnd;
         s_lastTesterVisualKey=scanKey;
        }
      else
        {
         if(s_lastTesterLogicClosed==ltfEnd && s_lastTesterLogicKey==scanKey)
           {
            if(perfNonVisual)
               g_perfNvThrottleSkips++;
            return;
           }
         s_lastTesterLogicClosed=ltfEnd;
         s_lastTesterLogicKey=scanKey;
        }
     }

   if(!renderVisuals && !CCTTesterIsHTFBoundary(ltfEnd) &&
      g_nvReplayCount>0 && g_nvReplayKey==CCTNonVisualReplayKey())
     {
      if(CCTNonVisualCachedReplayNeedsScan(ltfEnd))
        {
         if(CCTRunNonVisualCachedScannerPulse(ltfEnd))
            return;
        }
      else
        {
         g_perfNvCachedSkips++;
         return;
        }
     }

   if(!CCTShouldRunNonVisualTesterScan(ltfEnd))
     {
      if(perfNonVisual)
         g_perfNvScheduleSkips++;
      return;
     }

   if(!renderVisuals && !CCTNonVisualCachedReplayNeedsScan(ltfEnd))
     {
      if(perfNonVisual)
         g_perfNvCachedSkips++;
      return;
     }

   ulong perfReplayStart=0;
   if(perfNonVisual)
     {
      g_perfNvFullReplays++;
      perfReplayStart=GetMicrosecondCount();
     }

   // CCT_REFRESH_PROFILE_V3
   // Timing-only instrumentation for RefreshState(false). No behavior change.
   ulong cctProfStart=GetMicrosecondCount();
   ulong cctProfStep=cctProfStart;
   ulong cctProfLoadHtf=0;
   ulong cctProfCopyLtf=0;
   ulong cctProfPreScan=0;
   ulong cctProfScan=0;
   ulong cctProfPostScan=0;

   // CCT_VISUAL_PHASE_PROFILE_V1
   // Timing-only instrumentation for RefreshState(true). No behavior change.
   ulong cctVisStep=0;
   ulong cctVisClassify=0;
   ulong cctVisCounterScan=0;
   ulong cctVisRefreshExec=0;
   ulong cctVisDraw=0;
   ulong cctVisPruneRedraw=0;

   // CCT_DRAW_INNER_PROFILE_V1
   // Timing-only instrumentation for the visual draw block. No behavior change.
   ulong cctDrawStep=0;
   ulong cctDrawCandidates=0;
   ulong cctDrawMainGens=0;
   ulong cctDrawCounterGens=0;
   ulong cctDrawDays=0;

// --- CCT SIGNAL EXPORT RESET ---
// Reset before every scanner pass so stale triggered/resolved generations do not ghost in the dashboard.
   g_sigBirthTime   = 0;
   g_sigBull        = true;
   g_sigState       = SS_UNKNOWN_OUTCOME;
   g_sigC1          = false;
   g_sigC2          = false;
   g_sigC3          = false;
   g_sigC1Time      = 0;
   g_sigC2Time      = 0;
   g_sigC3Time      = 0;
   g_sigLevel       = 0.0;
   g_sigEntryPx     = 0.0;
   g_sigSlPx        = 0.0;
   g_sigTpPx        = 0.0;
   g_sigModelLabel  = "";
   g_sigSLDistPips  = 0.0;
// --- END CCT SIGNAL EXPORT RESET ---


   cctProfStep=GetMicrosecondCount();
   if(!CCTLoadHTFScannerState())
      return;
   cctProfLoadHtf=GetMicrosecondCount()-cctProfStep;

   WickInfo bulls[];
   WickInfo bears[];
   int nBull=0;
   int nBear=0;
   if(renderVisuals)
     {
      cctVisStep=GetMicrosecondCount();
      ArrayResize(bulls,g_nHtf);
      ArrayResize(bears,g_nHtf);
      ClassifyWicks(g_htf,g_nHtf,bulls,nBull,bears,nBear);
      cctVisClassify=GetMicrosecondCount()-cctVisStep;
     }

      MqlRates ltf[];
   cctProfStep=GetMicrosecondCount();
   int nl=CopyLTFWindow(GenerationScanStart(),ltfEnd,ltf);
   ArraySetAsSeries(ltf,false);

   // CCT RUNTIME GUARD: CopyLTFWindow count clamp.
   // Tester memory pressure or a partial CopyRates path can leave nl greater than ArraySize(ltf).
   int ltfActual=ArraySize(ltf);
   if(nl<=0 || ltfActual<=0)
      return;
   if(nl>ltfActual)
      nl=ltfActual;

   cctProfCopyLtf=GetMicrosecondCount()-cctProfStep;
   cctProfStep=GetMicrosecondCount();

   datetime latestBullBirth=0;
   for(int i=0;i<g_nBull;i++)
     {
      int idx=g_bullBirths[i];
      if(idx<0 || idx>=g_nHtf)
         continue;

      datetime effective=BirthEffectiveTime(g_htf[idx].time);
      if(effective>0 && effective<=ltfEnd && effective>latestBullBirth)
         latestBullBirth=effective;
     }

   datetime latestBearBirth=0;
   for(int i=0;i<g_nBear;i++)
     {
      int idx=g_bearBirths[i];
      if(idx<0 || idx>=g_nHtf)
         continue;

      datetime effective=BirthEffectiveTime(g_htf[idx].time);
      if(effective>0 && effective<=ltfEnd && effective>latestBearBirth)
         latestBearBirth=effective;
     }

    bool haveBull=(latestBullBirth>0);
    bool haveBear=(latestBearBirth>0);
    bool currentBiasBull=haveBull && (!haveBear || latestBullBirth>=latestBearBirth);
    bool nonVisualTester=IsNonVisualTesterRun();
    bool haveBothBiases=(haveBull && haveBear);
    bool showCounterBiasDead=(!nonVisualTester && Inp_ShowKilled && Inp_ShowCounterBiasDead && haveBothBiases);
    GenInfo gens[50];
    int nGens=0;
    if(haveBull || haveBear)
      {
      if(currentBiasBull)
         BuildInBiasGenerations(g_htf,g_nHtf,g_bullBirths,g_nBull,true,gens,nGens,ltfEnd,renderVisuals);
       else
          BuildInBiasGenerations(g_htf,g_nHtf,g_bearBirths,g_nBear,false,gens,nGens,ltfEnd,renderVisuals);
      }

    GenInfo counterGens[50];
    int nCounterGens=0;
    bool buildCounterForLogic=(!renderVisuals && haveBothBiases);
    if((renderVisuals && !nonVisualTester && haveBothBiases) || buildCounterForLogic)
      {
        if(currentBiasBull)
            BuildInBiasGenerations(g_htf,g_nHtf,g_bearBirths,g_nBear,false,counterGens,nCounterGens,ltfEnd,renderVisuals);
         else
            BuildInBiasGenerations(g_htf,g_nHtf,g_bullBirths,g_nBull,true,counterGens,nCounterGens,ltfEnd,renderVisuals);
        }

    if(g_nvReplayKey==CCTNonVisualReplayKey())
      {
       // A bias flip moves a generation between the main and counter-bias
       // arrays. Preserve terminal states across that handoff so executed
       // POIs cannot rebuild as fresh stale structures.
       CCTMergeCachedTerminalStates(gens,nGens,g_nvReplayGens,g_nvReplayCount,ltfEnd);
       CCTMergeCachedTerminalStates(gens,nGens,g_nvReplayCounterGens,g_nvReplayCounterCount,ltfEnd);
       CCTMergeCachedTerminalStates(counterGens,nCounterGens,g_nvReplayGens,g_nvReplayCount,ltfEnd);
       CCTMergeCachedTerminalStates(counterGens,nCounterGens,g_nvReplayCounterGens,g_nvReplayCounterCount,ltfEnd);
      }

   bool debugFullState=CCTDebugEnabled();
   if(debugFullState && !CCTTesterIsHTFBoundary(ltfEnd))
      debugFullState=false;

   if(debugFullState)
     {
      CCTJournalLine(StringFormat("[CCT DBG] Births bull=%d bear=%d | bias=%s | nGens=%d",
                                  g_nBull,
                                  g_nBear,
                                  currentBiasBull ? "bull" : "bear",
                                  nGens));
      for(int _i=0;_i<nGens;_i++)
        {
         CCTJournalLine(StringFormat("[CCT DBG] Gen[%d] birth=%s dormant=%s nSibs=%d",
                                     _i,
                                     TimeToString(ToNY(gens[_i].birthTime),TIME_DATE|TIME_MINUTES),
                                     gens[_i].dormant ? "yes" : "no",
                                     gens[_i].nSibs));
        }
     }

   datetime htfCurrent=iTime(_Symbol,HTF(),0);
   MqlDateTime htfNY={};
   TimeToStruct(ToNY(htfCurrent),htfNY);
   bool isExecBarOpen=CCTModelAnyAuthAllows(htfCurrent);
   // CCT_VISUAL_LIVE_HISTORICAL_RECONSTRUCTION_V3_MAIN_SCAN
   // Render passes rebuild old bars for drawing only. Broker execution
   // remains protected by CCTTryExecuteGeneration fresh-trigger checks.
   bool cctPrevHistoricalReplay=g_cctAllowHistoricalReplayTriggers;
   // CCT_HISTORICAL_TRIGGER_REPLAY_WINDOW_EXPIRED_DEFER_V5_MAIN_SCAN
   g_cctAllowHistoricalReplayTriggers=(renderVisuals && !nonVisualTester);

   cctProfPreScan=GetMicrosecondCount()-cctProfStep;
   cctProfStep=GetMicrosecondCount();

   ScanGenerationSet(gens,nGens,ltf,nl,isExecBarOpen,htfNY.hour);
   if(!renderVisuals && nCounterGens>0)
      ScanGenerationSet(counterGens,nCounterGens,ltf,nl,isExecBarOpen,htfNY.hour);

   cctProfScan=GetMicrosecondCount()-cctProfStep;
   cctProfStep=GetMicrosecondCount();

   g_cctAllowHistoricalReplayTriggers=cctPrevHistoricalReplay;

   CCTApplyExecutionRecordsToSet(gens,nGens);
   CCTApplyExecutionRecordsToSet(counterGens,nCounterGens);
   if(perfNonVisual && perfReplayStart>0)
     {
      ulong elapsed=GetMicrosecondCount()-perfReplayStart;
      g_perfNvReplayMicros+=elapsed;
      if(elapsed>g_perfNvMaxReplayMicros)
         g_perfNvMaxReplayMicros=elapsed;
     }
   for(int i=0;i<nGens;i++)
      CCTTryExecuteGeneration(gens[i],ltfEnd);

   CCTApplyExecutionRecordsToSet(gens,nGens);
   CCTApplyExecutionRecordsToSet(counterGens,nCounterGens);
   CCTStoreNonVisualReplayCache(gens,nGens,ltfEnd);
   CCTStoreNonVisualCounterReplayCache(counterGens,nCounterGens);

   if(debugFullState)
     {
      DebugPrintScanSummary(currentBiasBull,g_nBull,g_nBear,gens,nGens);
      DebugPrintSiblingStates(gens,nGens);
      if(!renderVisuals && nCounterGens>0)
        {
         CCTJournalLine(StringFormat("[CCT DBG] Counter-bias gens=%d",nCounterGens));
         DebugPrintSiblingStates(counterGens,nCounterGens);
        }
     }

   cctProfPostScan=GetMicrosecondCount()-cctProfStep;

   if(!renderVisuals)
     {
      ulong cctProfTotal=GetMicrosecondCount()-cctProfStart;
      if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctProfTotal>500000))
         CCTJournalLine(StringFormat("[CCT REFRESH PROFILE V3] symbol=%s | ltf=%s | total_us=%s | loadHtf=%s | copyLtf=%s | preScan=%s | scan=%s | postScan=%s | nHtf=%d | nBull=%d | nBear=%d | nGens=%d | nCounter=%d | nl=%d",
                                     _Symbol,
                                     TimeToString(ltfEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     IntegerToString((long)cctProfTotal),
                                     IntegerToString((long)cctProfLoadHtf),
                                     IntegerToString((long)cctProfCopyLtf),
                                     IntegerToString((long)cctProfPreScan),
                                     IntegerToString((long)cctProfScan),
                                     IntegerToString((long)cctProfPostScan),
                                     g_nHtf,
                                     g_nBull,
                                     g_nBear,
                                     nGens,
                                     nCounterGens,
                                     nl));
      return;
     }

   if(nonVisualTester)
      return;

   if(renderVisuals && CCTIsVisualTesterRun() && !CCTVisualTesterRenderDue(ltfEnd,gens,nGens,counterGens,nCounterGens))
      return;

   if(!nonVisualTester && nCounterGens>0)
     {
      cctVisStep=GetMicrosecondCount();
      // CCT_VISUAL_LIVE_HISTORICAL_RECONSTRUCTION_V3_COUNTER_SCAN
      bool cctPrevHistoricalReplayCounter=g_cctAllowHistoricalReplayTriggers;
      // CCT_HISTORICAL_TRIGGER_REPLAY_WINDOW_EXPIRED_DEFER_V5_MAIN_SCAN
   g_cctAllowHistoricalReplayTriggers=(renderVisuals && !nonVisualTester);

      ScanGenerationSet(counterGens,nCounterGens,ltf,nl,isExecBarOpen,htfNY.hour);

      g_cctAllowHistoricalReplayTriggers=cctPrevHistoricalReplayCounter;
      cctVisCounterScan=GetMicrosecondCount()-cctVisStep;
     }

         // CCT_REFRESHEXEC_INNER_PROFILE_V1
   ulong cctVisExecBlockStart=GetMicrosecondCount();
   ulong cctVisExecStep=0;
   ulong cctVisExecTsMain=0;
   ulong cctVisExecApplyMain=0;
   ulong cctVisExecSynthMain=0;
   ulong cctVisExecEnsureMain=0;
   ulong cctVisExecCoMain=0;
   ulong cctVisExecTsCounter=0;
   ulong cctVisExecApplyCounter=0;
   ulong cctVisExecSynthCounter=0;
   ulong cctVisExecEnsureCounter=0;
   ulong cctVisExecCoCounter=0;
   int cctVisExecMainCount=0;
   int cctVisExecCounterCount=0;

   cctVisStep=cctVisExecBlockStart;
   // CCT_VISUAL_REFRESHEXEC_DEDUP_V1
   // Visual execution-state refresh: run each expensive TS/CO refresh once per generation per draw.
   for(int i=0;i<nGens;i++)
     {
      cctVisExecMainCount++;

      cctVisExecStep=GetMicrosecondCount();
      RefreshGenerationTSState(gens[i],g_htf,g_nHtf,ltf,nl,ltfEnd);
      cctVisExecTsMain+=GetMicrosecondCount()-cctVisExecStep;

      cctVisExecStep=GetMicrosecondCount();
      CCTApplyExecutionRecordToGeneration(gens[i]);
      cctVisExecApplyMain+=GetMicrosecondCount()-cctVisExecStep;

      cctVisExecStep=GetMicrosecondCount();
      RefreshSyntheticExecutionOutcome(gens[i],ltf,nl,ltfEnd);
      cctVisExecSynthMain+=GetMicrosecondCount()-cctVisExecStep;

      cctVisExecStep=GetMicrosecondCount();
      CCTEnsureSyntheticRecordFromGeneration(gens[i]);
      cctVisExecEnsureMain+=GetMicrosecondCount()-cctVisExecStep;

      cctVisExecStep=GetMicrosecondCount();
      CCTApplyExecutionRecordToGeneration(gens[i]);
      cctVisExecApplyMain+=GetMicrosecondCount()-cctVisExecStep;

      cctVisExecStep=GetMicrosecondCount();
      RefreshGenerationCOState(gens[i],g_htf,g_nHtf,ltf,nl,ltfEnd);
      cctVisExecCoMain+=GetMicrosecondCount()-cctVisExecStep;
     }

   if(!nonVisualTester && nCounterGens>0)
     {
      for(int i=0;i<nCounterGens;i++)
        {
         cctVisExecCounterCount++;

         cctVisExecStep=GetMicrosecondCount();
         RefreshGenerationTSState(counterGens[i],g_htf,g_nHtf,ltf,nl,ltfEnd);
         cctVisExecTsCounter+=GetMicrosecondCount()-cctVisExecStep;

         cctVisExecStep=GetMicrosecondCount();
         CCTApplyExecutionRecordToGeneration(counterGens[i]);
         cctVisExecApplyCounter+=GetMicrosecondCount()-cctVisExecStep;

         cctVisExecStep=GetMicrosecondCount();
         RefreshSyntheticExecutionOutcome(counterGens[i],ltf,nl,ltfEnd);
         cctVisExecSynthCounter+=GetMicrosecondCount()-cctVisExecStep;

         cctVisExecStep=GetMicrosecondCount();
         CCTEnsureSyntheticRecordFromGeneration(counterGens[i]);
         cctVisExecEnsureCounter+=GetMicrosecondCount()-cctVisExecStep;

         cctVisExecStep=GetMicrosecondCount();
         CCTApplyExecutionRecordToGeneration(counterGens[i]);
         cctVisExecApplyCounter+=GetMicrosecondCount()-cctVisExecStep;

         cctVisExecStep=GetMicrosecondCount();
         RefreshGenerationCOState(counterGens[i],g_htf,g_nHtf,ltf,nl,ltfEnd);
         cctVisExecCoCounter+=GetMicrosecondCount()-cctVisExecStep;
        }
     }

   cctVisRefreshExec=GetMicrosecondCount()-cctVisStep;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctVisRefreshExec>250000))
      CCTJournalLine(StringFormat("[CCT REFRESHEXEC PROFILE V1] symbol=%s | ltf=%s | total_us=%s | mainCount=%s | counterCount=%s | tsMain=%s | applyMain=%s | synthMain=%s | ensureMain=%s | coMain=%s | tsCounter=%s | applyCounter=%s | synthCounter=%s | ensureCounter=%s | coCounter=%s",
                                  _Symbol,
                                  TimeToString(ltfEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  IntegerToString((long)cctVisRefreshExec),
                                  IntegerToString(cctVisExecMainCount),
                                  IntegerToString(cctVisExecCounterCount),
                                  IntegerToString((long)cctVisExecTsMain),
                                  IntegerToString((long)cctVisExecApplyMain),
                                  IntegerToString((long)cctVisExecSynthMain),
                                  IntegerToString((long)cctVisExecEnsureMain),
                                  IntegerToString((long)cctVisExecCoMain),
                                  IntegerToString((long)cctVisExecTsCounter),
                                  IntegerToString((long)cctVisExecApplyCounter),
                                  IntegerToString((long)cctVisExecSynthCounter),
                                  IntegerToString((long)cctVisExecEnsureCounter),
                                  IntegerToString((long)cctVisExecCoCounter)));

   if(!renderVisuals)
      return;

   cctVisStep=GetMicrosecondCount();

   string keep[];
   int keepCount=0;

   datetime seenDays[];
   int seenDayCount=0;
   datetime scanStart=GenerationScanStart();
   datetime candidateBarTime=(g_nHtf>0) ? g_htf[0].time : 0;

      cctDrawStep=GetMicrosecondCount();
CCTDebugCandidateVisualGates(bulls,nBull,bears,nBear,currentBiasBull,candidateBarTime,ltf,nl);

   for(int i=0;i<nBull;i++)
     {
      WICK_STATE visualState=currentBiasBull ? bulls[i].state : WS_STRIPPED;
      if(visualState==WS_CANDIDATE && !GenerationHasAuthorizedExec(candidateBarTime))
         visualState=WS_STRIPPED;
      if(visualState==WS_CANDIDATE &&
         !CandidateLineActiveFromLTF(true,bulls[i].level,candidateBarTime,ltf,nl))
         visualState=Inp_ShowVirgins ? WS_VIRGIN : WS_STRIPPED;
            // CCT_SKIP_INVISIBLE_CANDIDATE_DRAW_V2
      // Only visible candidate/virgin wick families need per-object draw/update calls.
      // Invisible/stripped families are left out of keep[] and removed by the final prune pass.
      bool drawBullWick=((visualState==WS_VIRGIN && Inp_ShowVirgins) ||
                         (visualState==WS_CANDIDATE && Inp_ShowCandidates));
      if(drawBullWick)
        {
         if(visualState==WS_CANDIDATE || (visualState==WS_VIRGIN && Inp_ShowVirgins))
            bulls[i].ltfAnchor=FindLTFExtremeBar(bulls[i].barTime,true);
         DrawVirginWick(true,bulls[i].barTime,bulls[i].ltfAnchor,bulls[i].level,visualState,
                        (visualState==WS_CANDIDATE) ? candidateBarTime : 0);
        }
      if(drawBullWick)
        {
         string vwName=ObjN(GenKey(true,bulls[i].barTime),"VW");
         if(visualState==WS_CANDIDATE)
           {
            KeepObj(vwName+"_GLOW",keep,keepCount);
            KeepObj(vwName+"_GLOW_LTF",keep,keepCount);
           }
         KeepObj(vwName,keep,keepCount);
         KeepObj(vwName+"_LTF",keep,keepCount);
        }
     }
   if(currentBiasBull)
      DrawCandidateActionPillars(bulls,nBull,true,candidateBarTime,ltf,nl,keep,keepCount);

   for(int i=0;i<nBear;i++)
     {
      WICK_STATE visualState=currentBiasBull ? WS_STRIPPED : bears[i].state;
      if(visualState==WS_CANDIDATE && !GenerationHasAuthorizedExec(candidateBarTime))
         visualState=WS_STRIPPED;
      if(visualState==WS_CANDIDATE &&
         !CandidateLineActiveFromLTF(false,bears[i].level,candidateBarTime,ltf,nl))
         visualState=Inp_ShowVirgins ? WS_VIRGIN : WS_STRIPPED;
            // CCT_SKIP_INVISIBLE_CANDIDATE_DRAW_V2
      // Only visible candidate/virgin wick families need per-object draw/update calls.
      // Invisible/stripped families are left out of keep[] and removed by the final prune pass.
      bool drawBearWick=((visualState==WS_VIRGIN && Inp_ShowVirgins) ||
                         (visualState==WS_CANDIDATE && Inp_ShowCandidates));
      if(drawBearWick)
        {
         if(visualState==WS_CANDIDATE || (visualState==WS_VIRGIN && Inp_ShowVirgins))
            bears[i].ltfAnchor=FindLTFExtremeBar(bears[i].barTime,false);
         DrawVirginWick(false,bears[i].barTime,bears[i].ltfAnchor,bears[i].level,visualState,
                        (visualState==WS_CANDIDATE) ? candidateBarTime : 0);
        }
      if(drawBearWick)
        {
         string vwName=ObjN(GenKey(false,bears[i].barTime),"VW");
         if(visualState==WS_CANDIDATE)
           {
            KeepObj(vwName+"_GLOW",keep,keepCount);
            KeepObj(vwName+"_GLOW_LTF",keep,keepCount);
           }
         KeepObj(vwName,keep,keepCount);
         KeepObj(vwName+"_LTF",keep,keepCount);
        }
     }
   if(!currentBiasBull)
      DrawCandidateActionPillars(bears,nBear,false,candidateBarTime,ltf,nl,keep,keepCount);
   cctDrawCandidates=GetMicrosecondCount()-cctDrawStep;

       cctDrawStep=GetMicrosecondCount();
for(int i=0;i<nGens;i++)
      {
       DrawGenerationPOIs(gens[i],GenerationShouldShowDefaultPOIs(gens[i]),Inp_ShowDormant,Inp_ShowKilled,keep,keepCount);
       DrawGenerationActionPillar(gens[i],Inp_ShowKilled,keep,keepCount);
       DrawGenerationTSOverlay(gens[i],currentBiasBull,keep,keepCount);
       DrawGenerationCOOverlay(gens[i],currentBiasBull,keep,keepCount);
       DrawGenerationFVGAndExecution(gens[i],keep,keepCount);
      }
   cctDrawMainGens=GetMicrosecondCount()-cctDrawStep;

       cctDrawStep=GetMicrosecondCount();
if(!nonVisualTester && nCounterGens>0)
      {
       for(int i=0;i<nCounterGens;i++)
         {
           bool counterExec=GenerationHasExecutionState(counterGens[i]);
           bool counterDead=GenerationHasDeadPOIs(counterGens[i]) && (Inp_ShowKilled || showCounterBiasDead);
           DrawGenerationPOIs(counterGens[i],counterExec,false,(Inp_ShowKilled || showCounterBiasDead),keep,keepCount);
           if(counterExec || counterDead)
              DrawGenerationActionPillar(counterGens[i],(Inp_ShowKilled || showCounterBiasDead),keep,keepCount);
           DrawGenerationTSOverlay(counterGens[i],currentBiasBull,keep,keepCount);
           DrawGenerationCOOverlay(counterGens[i],currentBiasBull,keep,keepCount);
           DrawGenerationFVGAndExecution(counterGens[i],keep,keepCount);
         }
      }
   cctDrawCounterGens=GetMicrosecondCount()-cctDrawStep;

      cctDrawStep=GetMicrosecondCount();
for(int i=0;i<g_nHtf;i++)
     {
      datetime dayOpen=CCTVisualDayOpenForServerTime(g_htf[i].time);
      if(dayOpen<scanStart)
         continue;

      bool alreadySeen=false;
      for(int j=0;j<seenDayCount;j++)
        {
         if(seenDays[j]==dayOpen)
           {
            alreadySeen=true;
            break;
           }
        }
      if(alreadySeen)
         continue;

      int newSize=seenDayCount+1;
      ArrayResize(seenDays,newSize);
      seenDays[seenDayCount]=dayOpen;
      seenDayCount=newSize;

      DrawDailySeparator(dayOpen,true);
      KeepObj(DaySepName(dayOpen),keep,keepCount);
     }

   datetime currentDayOpen=CCTVisualTodayOpen();
   DrawDailySeparator(currentDayOpen,true);
   KeepObj(DaySepName(currentDayOpen),keep,keepCount);

   datetime nextDayOpen=CCTVisualNextDayOpen(currentDayOpen);
   if(nextDayOpen>0)
     {
      DrawDailySeparator(nextDayOpen,true);
      KeepObj(DaySepName(nextDayOpen),keep,keepCount);
     }
   cctDrawDays=GetMicrosecondCount()-cctDrawStep;

   cctVisDraw=GetMicrosecondCount()-cctVisStep;
   if(renderVisuals && CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctVisDraw>250000))
      CCTJournalLine(StringFormat("[CCT DRAW PROFILE V1] symbol=%s | ltf=%s | total_us=%s | candidates=%s | mainGens=%s | counterGens=%s | days=%s | nBull=%d | nBear=%d | nGens=%d | nCounter=%d | keep=%d",
                                  _Symbol,
                                  TimeToString(ltfEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  IntegerToString((long)cctVisDraw),
                                  IntegerToString((long)cctDrawCandidates),
                                  IntegerToString((long)cctDrawMainGens),
                                  IntegerToString((long)cctDrawCounterGens),
                                  IntegerToString((long)cctDrawDays),
                                  nBull,
                                  nBear,
                                  nGens,
                                  nCounterGens,
                                  keepCount));
   cctVisStep=GetMicrosecondCount();

   // AP/POI companions must not outlive their generation visibility. Visual
   // tester rendering is already throttled above, so pruning on render frames is
   // safer than letting stale APs survive until deinit.
   PruneCCTObjects(keep,keepCount);
   ChartRedraw();
   cctVisPruneRedraw=GetMicrosecondCount()-cctVisStep;

   if(renderVisuals)
     {
      ulong cctVisTotal=GetMicrosecondCount()-cctProfStart;
      if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || cctVisTotal>250000))
         CCTJournalLine(StringFormat("[CCT VISUAL PROFILE V1] symbol=%s | ltf=%s | total_us=%s | classify=%s | loadHtf=%s | copyLtf=%s | preScan=%s | mainScan=%s | postScan=%s | counterScan=%s | refreshExec=%s | draw=%s | pruneRedraw=%s | nHtf=%d | nBull=%d | nBear=%d | nGens=%d | nCounter=%d | nl=%d | keep=%d",
                                     _Symbol,
                                     TimeToString(ltfEnd,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     IntegerToString((long)cctVisTotal),
                                     IntegerToString((long)cctVisClassify),
                                     IntegerToString((long)cctProfLoadHtf),
                                     IntegerToString((long)cctProfCopyLtf),
                                     IntegerToString((long)cctProfPreScan),
                                     IntegerToString((long)cctProfScan),
                                     IntegerToString((long)cctProfPostScan),
                                     IntegerToString((long)cctVisCounterScan),
                                     IntegerToString((long)cctVisRefreshExec),
                                     IntegerToString((long)cctVisDraw),
                                     IntegerToString((long)cctVisPruneRedraw),
                                     g_nHtf,
                                     nBull,
                                     nBear,
                                     nGens,
                                     nCounterGens,
                                     nl,
                                     keepCount));
     }
  }

/*
Purpose: Run the shared scanner truth path with chart rendering enabled.
Constitution: Ch. 26 visual ownership, Ch. 29 action-pillar rendering, and tester-performance rules.
Inputs: None.
Outputs: None.
*/
void Draw()
  {
   RefreshState(true);
  }

bool g_cctDeinitRenderPurgeModeV1=false;

/*
Purpose: Draw the latest execution-state geometry immediately before notification screenshots.
Constitution: Notification screenshots need current post-fill/post-resolution execution visuals, while execution truth remains owned by ExecRecord.
Inputs: exec - persisted execution record.
Outputs: Current chart execution objects refreshed from post-fill truth only.
*/
void CCTDrawExecutionSnapshotCore(const ExecRecord &exec,const bool redraw)
  {
   // CCT_NOTIFY_EXECUTION_SNAPSHOT_BRIDGE_V1
   if(IsNonVisualTesterRun())
      return;

   if(exec.genKey=="")
      return;

   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double sl=(exec.brokerSL>0.0 ? exec.brokerSL : exec.rawSL);
   double tp=exec.brokerTP;

   if(exec.triggerBarTime<=0 || entry<=0.0 || sl<=0.0 || tp<=0.0)
      return;

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;

   datetime entryTime=(exec.c3Time>0) ? (exec.c3Time+(datetime)ltfSec) : 0;
   if(entryTime<=0 && exec.triggerBarTime>0)
      entryTime=exec.triggerBarTime+(datetime)ltfSec;
   if(entryTime<=0)
      entryTime=exec.triggerBarTime;

   double fibRaw=(exec.rawSL>0.0 ? exec.rawSL : sl);

   DrawSyntheticExecutionObjects(exec.genKey,
                                 exec.bull,
                                 exec.triggerBarTime,
                                 entryTime,
                                 entry,
                                 sl,
                                 tp,
                                 exec.anchorATime,
                                 exec.anchorBTime,
                                 exec.anchorA,
                                 exec.anchorB,
                                 exec.slBranch,
                                 exec.modelType,
                                 exec.sweepCount,
                                 exec.outcome,
                                 exec.exitTime,
                                 exec.coPrice,
                                 exec.coTouchTime,
                                 exec.beGeneralApplied,
                                 exec.beCoApplied,
                                 exec.bePrice,
                                 exec.beLeftAnchorTime,
                                 exec.beTime,
                                 exec.beGeneralPrice,
                                 exec.beGeneralLeftAnchorTime,
                                 exec.beGeneralTime,
                                 exec.beCoPrice,
                                 exec.beCoLeftAnchorTime,
                                 exec.beCoTime,
                                 fibRaw);

   if(redraw)
      ChartRedraw(0);
  }

void CCTNotifyDrawExecutionSnapshot(const ExecRecord &exec)
  {
   CCTDrawExecutionSnapshotCore(exec,true);
  }

/*
Purpose: Initialize the pass-1 EA shell and timer-driven draw loop.
Constitution: Ch. 34 orchestration-only main file and tester-performance rules.
Inputs: None.
Outputs: INIT_SUCCEEDED when setup completes.
*/
/*
Purpose: Detect MT5 soft reinitialization events where existing CCT visuals should survive until the next full redraw.
Constitution: Timeframe changes and parameter changes must not wipe valid prior-day/weekend execution drawings before the scanner redraws.
Inputs: reason - OnDeinit reason code.
Outputs: True for soft reinit reasons.
*/
bool CCTSoftReinitReason(const int reason)
  {
   // CCT_SOFT_REINIT_REASON_V2
   return (reason==REASON_CHARTCHANGE || reason==REASON_PARAMETERS);
  }

/*
Purpose: Count chart objects owned by the CCT namespace for lifecycle diagnostics.
Inputs: prefix - object-name prefix.
Outputs: Number of chart objects with the prefix.
*/
int CCTObjectCountByPrefix(const string prefix)
  {
   int total=ObjectsTotal(0,-1,-1);
   int count=0;

   for(int i=0;i<total;i++)
     {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,prefix)==0)
         count++;
     }

   return count;
  }

/*
Purpose: Convert MT5 OnDeinit reason code to readable text for Expert-log diagnostics.
Inputs: reason - OnDeinit reason code.
Outputs: Human-readable reason name.
*/
string CCTDeinitReasonName(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return "REASON_PROGRAM";
      case REASON_REMOVE:      return "REASON_REMOVE";
      case REASON_RECOMPILE:   return "REASON_RECOMPILE";
      case REASON_CHARTCHANGE: return "REASON_CHARTCHANGE";
      case REASON_CHARTCLOSE:  return "REASON_CHARTCLOSE";
      case REASON_PARAMETERS:  return "REASON_PARAMETERS";
      case REASON_ACCOUNT:     return "REASON_ACCOUNT";
      case REASON_TEMPLATE:    return "REASON_TEMPLATE";
      case REASON_INITFAILED:  return "REASON_INITFAILED";
      case REASON_CLOSE:       return "REASON_CLOSE";
     }

   return "REASON_UNKNOWN_"+IntegerToString(reason);
  }

/*
Purpose: Convert MT5 chart event id to readable text for lifecycle diagnostics.
Inputs: id - OnChartEvent id.
Outputs: Human-readable event name.
*/
string CCTChartEventName(const int id)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      return "CHARTEVENT_CHART_CHANGE";

   if(id>=CHARTEVENT_CUSTOM)
      return "CHARTEVENT_CUSTOM_OR_GREATER_"+IntegerToString(id);

   return "CHARTEVENT_OTHER_"+IntegerToString(id);
  }

/*
Purpose: Print compact lifecycle diagnostics to the MT5 Experts log.
Inputs: eventName - lifecycle event; detail - contextual details.
Outputs: Expert-log line only.
*/
void CCTLifecycleLog(const string eventName,const string detail)
  {
   // CCT_LIFECYCLE_LOG_HELPERS_V1
   if(CCTSuppressLiveCCTJournals())
      return;

   int totalObjects=ObjectsTotal(0,-1,-1);
   int cctObjects=CCTObjectCountByPrefix("CCT_");
   string tester=(MQLInfoInteger(MQL_TESTER)!=0 ? "true" : "false");

   PrintFormat("[CCT LIFECYCLE] %s | chart=%I64d | symbol=%s | period=%s | tester=%s | cctObjects=%d | totalObjects=%d | detail=%s",
               eventName,
               ChartID(),
               _Symbol,
               EnumToString(_Period),
               tester,
               cctObjects,
               totalObjects,
               detail);
  }

/*
Purpose: Count CCT-owned chart objects for lifecycle diagnostics.
Constitution: Diagnostic only; does not alter lifecycle, scanner, visual, or execution behavior.
Inputs: prefix - object-name prefix.
Outputs: Matching object count.
*/
int CCTDiagObjectCountByPrefix(const string prefix)
  {
   int count=0;

   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,prefix)==0)
         count++;
     }

   return count;
  }

/*
Purpose: Convert MT5 deinit reason to a readable lifecycle diagnostic label.
Constitution: Diagnostic only.
Inputs: reason - MT5 OnDeinit reason.
Outputs: Readable reason name.
*/
string CCTDiagDeinitReasonName(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return "REASON_PROGRAM";
      case REASON_REMOVE:      return "REASON_REMOVE";
      case REASON_RECOMPILE:   return "REASON_RECOMPILE";
      case REASON_CHARTCHANGE: return "REASON_CHARTCHANGE";
      case REASON_CHARTCLOSE:  return "REASON_CHARTCLOSE";
      case REASON_PARAMETERS:  return "REASON_PARAMETERS";
      case REASON_ACCOUNT:     return "REASON_ACCOUNT";
      case REASON_TEMPLATE:    return "REASON_TEMPLATE";
      case REASON_INITFAILED:  return "REASON_INITFAILED";
      case REASON_CLOSE:       return "REASON_CLOSE";
     }

   return "REASON_UNKNOWN_"+IntegerToString(reason);
  }

/*
Purpose: Print compact MT5 lifecycle diagnostics.
Constitution: Diagnostic only; no behavior changes.
Inputs: eventName - event label; detail - detail string.
Outputs: Expert-log line.
*/
void CCTDiagLifecycleLog(const string eventName,const string detail)
  {
   // CCT_LIFECYCLE_DIAG_HELPERS_V1
   if(CCTSuppressLiveCCTJournals())
      return;

   PrintFormat("[CCT LIFECYCLE DIAG] %s | chart=%I64d | symbol=%s | period=%s | tester=%s | cctObjects=%d | totalObjects=%d | detail=%s",
               eventName,
               ChartID(),
               _Symbol,
               EnumToString(_Period),
               (MQLInfoInteger(MQL_TESTER)!=0 ? "true" : "false"),
               CCTDiagObjectCountByPrefix("CCT_"),
               ObjectsTotal(0),
               detail);
  }

/*
Purpose: Force chart visual/dashboard lifecycle to be deterministic across symbol, timeframe, parameter, and template reinitialization.
Constitution: Visual lifecycle only; does not alter scanner state, POI truth, trigger logic, execution rules, or tester asset universe.
Problem fixed: A chart switched from GC/XAUUSD to NQ/USTEC could retain stale CCT_/CCTD_ objects and draw differently from a fresh NQ/USTEC launch.
*/
int CCTHardVisualResetCountPrefixV1(const string prefix)
  {
   int count=0;

   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,prefix)==0)
         count++;
     }

   return count;
  }

int CCTHardVisualResetDeletePrefixV1(const string prefix)
  {
   int deleted=0;

   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);

      if(StringFind(name,prefix)!=0)
         continue;

      if(ObjectDelete(0,name))
         deleted++;
     }

   return deleted;
  }

bool CCTOwnedChartObjectNameV1(const string name)
  {
   // CCT_DEINIT_OWNERSHIP_BROAD_MATCH_V1
   // Deinit must clean both the current CCT_ namespace and older/diagnostic
   // generation-style objects that may not be counted by the narrow prefix pass.
   return CCTDeinitFinalOwnsObjectName(name);
  }

int CCTDeleteAllOwnedChartObjectsV1()
  {
   int deleted=0;

   for(int pass=0;pass<4;pass++)
     {
      int passDeleted=0;
      for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
        {
         string name=ObjectName(0,i,-1,-1);
         if(!CCTOwnedChartObjectNameV1(name))
            continue;

         if(ObjectDelete(0,name))
            passDeleted++;
        }

      deleted+=passDeleted;
      if(passDeleted<=0)
         break;
     }

   return deleted;
  }

int CCTDeleteOwnedPrefixesBulkV1()
  {
   // CCT_DEINIT_BULK_PREFIX_DELETE_V1
   // Use MT5's native prefix deletion as a second path. ObjectDelete can report
   // zero during unload even when the object table is immediately emptied.
   int deleted=0;
   int n=ObjectsDeleteAll(0,"CCT");
   if(n>0)
      deleted+=n;

   n=ObjectsDeleteAll(0,"BU_");
   if(n>0)
      deleted+=n;

   n=ObjectsDeleteAll(0,"BE_");
   if(n>0)
      deleted+=n;

   return deleted;
  }

void CCTHardVisualResetOnReinitV1(const string reason,const bool redraw)
  {
   // CCT_HARD_VISUAL_RESET_ON_REINIT_HELPERS_V1
   int cctBefore=CCTHardVisualResetCountPrefixV1("CCT_");
   int dashBefore=CCTHardVisualResetCountPrefixV1("CCTD_");
   int metaBefore=CCTHardVisualResetCountPrefixV1("CCTM_");

   int totalDeleted=CCTDeleteAllOwnedChartObjectsV1();
   int bulkDeleted=CCTDeleteOwnedPrefixesBulkV1();
   int cctAfter=CCTHardVisualResetCountPrefixV1("CCT_");
   int dashAfter=CCTHardVisualResetCountPrefixV1("CCTD_");
   int metaAfter=CCTHardVisualResetCountPrefixV1("CCTM_");

   if(redraw)
      ChartRedraw(ChartID());

   if(!CCTSuppressLiveCCTJournals() &&
      (cctBefore>0 || dashBefore>0 || metaBefore>0 || cctAfter>0 || dashAfter>0 || metaAfter>0))
     {
      PrintFormat("[CCT HARD VISUAL RESET] reason=%s | symbol=%s | period=%s | cctBefore=%d dashBefore=%d metaBefore=%d | totalDeleted=%d | bulkDeleted=%d | cctAfter=%d dashAfter=%d metaAfter=%d",
                   reason,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),
                   cctBefore,dashBefore,metaBefore,totalDeleted,bulkDeleted,cctAfter,dashAfter,metaAfter);
     }
  }

/*
Purpose: Return the hidden chart-owner object name used to detect symbol switches safely.
Constitution: Visual lifecycle safety; object ownership must not contaminate a newly selected symbol.
Inputs: None.
Outputs: Stable metadata object name.
*/
string CCTLifecycleOwnerObjectName()
  {
   return "CCTM_OWNER";
  }

/*
Purpose: Read the symbol that last owned this chart's CCT visual namespace.
Constitution: Visual lifecycle safety; symbol switching must be equivalent to a fresh attach.
Inputs: None.
Outputs: Prior owner symbol, or empty string when no marker exists.
*/
string CCTReadLifecycleOwnerSymbol()
  {
   string name=CCTLifecycleOwnerObjectName();
   if(ObjectFind(0,name)<0)
      return "";
   string owner=ObjectGetString(0,name,OBJPROP_TOOLTIP);
   if(owner!="")
      return owner;
   return ObjectGetString(0,name,OBJPROP_TEXT);
  }

/*
Purpose: Store the current symbol as the owner of this chart's CCT visual namespace.
Constitution: Visual lifecycle safety; soft parameter/timeframe reinitialization must not wipe valid drawings.
Inputs: None.
Outputs: Hidden chart marker updated with the current symbol.
*/
void CCTWriteLifecycleOwnerSymbol()
  {
   string name=CCTLifecycleOwnerObjectName();
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
     }
   // Store the owner symbol without painting a visible red asset label above the dashboard.
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,50000);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,50000);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,1);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrNONE);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,_Symbol);
   ObjectSetString(0,name,OBJPROP_TEXT,"");
  }

/*
Purpose: Clear symbol-scoped runtime caches when the chart moves to a different symbol.
Constitution: Execution records and replay caches are symbol-specific; genKeys alone are not globally unique.
Inputs: None.
Outputs: In-memory execution links and non-visual replay caches are purged.
*/
void CCTClearSymbolScopedRuntimeState()
  {
   ArrayResize(g_execRecords,0);
   g_nExecRecords=0;
   ArrayResize(g_pendingExecLinks,0);
   g_nPendingExecLinks=0;
   ArrayResize(g_rejectedExecKeys,0);
   ArrayResize(g_rejectedExecTriggers,0);
   g_nRejectedExecs=0;
   g_nvReplayCount=0;
   g_nvReplayCounterCount=0;
   g_nvReplayTime=0;
   g_nvReplayKey="";
   CCTResetHTFScannerCache();
  }
// CCT_DEINIT_EVENT_LATCH_V1
// Prevent timer/tick/chart-event work from running once deinit starts.
// This is lifecycle-only and does not alter strategy or broker execution logic.
bool g_cctDeinitEventLatchV1=false;

bool CCTDeinitHardUnloadReasonV1(const int reason)
  {
   return (reason==REASON_REMOVE || reason==REASON_CHARTCLOSE || reason==REASON_CLOSE || reason==REASON_PROGRAM);
  }

string CCTDeinitLifecycleGVNameV1()
  {
   return "CCT_LAST_HARD_UNLOAD_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+IntegerToString((long)ChartID())+"_"+_Symbol+"_"+IntegerToString((int)_Period);
  }

void CCTSetDeinitEventLatchV1(const int reason)
  {
   g_cctDeinitEventLatchV1=true;
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT EVENT LATCH SET] reason=%d | hardUnload=%s | symbol=%s | period=%s | chart=%s",
                  reason,
                  CCTDeinitHardUnloadReasonV1(reason) ? "yes" : "no",
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  IntegerToString((long)ChartID()));
  }

void CCTClearDeinitEventLatchV1(const string where)
  {
   if(g_cctDeinitEventLatchV1 && !CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT EVENT LATCH CLEAR] where=%s | symbol=%s | period=%s | chart=%s",
                  where,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),IntegerToString((long)ChartID()));
   g_cctDeinitEventLatchV1=false;
  }

bool CCTBlockLifecycleEventDuringDeinitV1(const string handler)
  {
   if(!g_cctDeinitEventLatchV1)
      return false;

   static datetime lastPrint=0;
   datetime now=TimeCurrent();
   if(now-lastPrint>=1 && !CCTSuppressLiveCCTJournals())
     {
      lastPrint=now;
      PrintFormat("[CCT LIFECYCLE EVENT BLOCKED DURING DEINIT] handler=%s | symbol=%s | period=%s | chart=%s",
                  handler,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),IntegerToString((long)ChartID()));
     }
   return true;
  }

void CCTMarkHardUnloadDeinitV1(const int reason,const int totalAfter)
  {
   if(!CCTDeinitHardUnloadReasonV1(reason))
      return;
   string gv=CCTDeinitLifecycleGVNameV1();
   GlobalVariableSet(gv,(double)TimeCurrent());
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT HARD UNLOAD MARK] reason=%d | symbol=%s | period=%s | chart=%s | totalAfter=%d | gv=%s",
                  reason,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),IntegerToString((long)ChartID()),totalAfter,gv);
  }

void CCTCheckRecentHardUnloadReinitV1()
  {
   string gv=CCTDeinitLifecycleGVNameV1();
   if(!GlobalVariableCheck(gv))
      return;
   datetime last=(datetime)GlobalVariableGet(gv);
   datetime now=TimeCurrent();
   if(last<=0 || now<=0)
      return;
   int ageSec=(int)(now-last);
   if(ageSec>=0 && ageSec<=120 && !CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT REINIT AFTER HARD UNLOAD WARNING] symbol=%s | period=%s | chart=%s | ageSec=%d | note=EA reinitialized shortly after hard unload; visible objects after this point are from a new instance/redraw, not leftover deinit objects.",
                  _Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),IntegerToString((long)ChartID()),ageSec);
  }

void CCTConfirmHardUnloadVisualPurgeV1(const int reason)
  {
   if(!CCTDeinitHardUnloadReasonV1(reason))
      return;
   ChartRedraw(0);
   int total=ObjectsTotal(0,-1,-1);
   string sample="";
   int added=0;
   for(int i=total-1;i>=0 && added<8;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(sample!="") sample+=" | ";
      sample+=name;
      added++;
     }
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT HARD UNLOAD VISUAL PURGE CONFIRM] reason=%d | symbol=%s | period=%s | totalObjects=%d | sample=%s",
                  reason,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),total,sample);
  }


int OnInit()
  {
   // CCT_DEINIT_LATCH_CLEAR_ONINIT_V1
   CCTCheckRecentHardUnloadReinitV1();
   CCTClearDeinitEventLatchV1("OnInit");
   // CCT_ONINIT_SYMBOL_OWNER_CLEANUP_V1
   string priorOwner=CCTReadLifecycleOwnerSymbol();
   bool symbolChanged=((priorOwner!="" && priorOwner!=_Symbol) ||
                       (g_lastInitSymbol!="" && g_lastInitSymbol!=_Symbol));
   if(symbolChanged)
     {
      ObjectsDeleteAll(0,"CCT_");
      ObjectsDeleteAll(0,"CCTD_");
      ObjectsDeleteAll(0,"CCTM_");
      CCTClearSymbolScopedRuntimeState();
      ChartRedraw(ChartID());
     }
   g_lastInitSymbol=_Symbol;
   CCTWriteLifecycleOwnerSymbol();
   // CCT_LIFECYCLE_DIAG_ONINIT_ENTER_V1
   // CCT_LIFECYCLE_ONINIT_ENTER_V1
   g_accMode=(int)Inp_AccMode;
   g_riskPct=ResolveRiskPresetValue(Inp_RiskPreset,Inp_RiskCustomPct);
   g_custBal=MathMax(0.0,Inp_CustBal);
   g_rrPreset=ResolveRRPresetValue(Inp_RRPreset,Inp_RRCustom);
   g_beTriggerPct=ResolvePercentPresetValue(Inp_BETriggerPreset,Inp_BETriggerCustomPct);
   g_beMovePct=ResolvePercentPresetValue(Inp_BEMovePreset,Inp_BEMoveCustomPct);
   g_beCoMinSec=ResolveSecondsPresetValue(Inp_BECOMinSecPreset,Inp_BECOMinSecCustom);
   g_beCoMinProgPct=ResolvePercentPresetValue(Inp_BECOMinProgPreset,Inp_BECOMinProgCustomPct);
   g_beCoLockPct=ResolveBECOLockPresetValue(Inp_BECOLockPreset,Inp_BECOLockCustomPct);
   RefreshExecutionHourCache();
   CCTInitPropFirmState();
   CCTWarmPropFirmSafetyCache(true);
   InitDashboards();
   NotifyInit();

   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      CCTTesterJournalInit();
      CCTClearTesterPersistentState();
      CCTJournalLine(StringFormat("[CCT INIT EFFECTIVE] tester=true | timeModel=%s | serverOffsetSec=%d | execNYShiftSec=%d | noBEBaseline=%s | rawBE=%s | rawCOBE=%s | runtimeBE=%s | runtimeCOBE=%s | model=%s | rr=%.2f | fibMode=%d | fibCfg=%d | tsFilter=%s | useCOTP=%s | riskPct=%.2f | CCT=%s | TS=%s | EXT=%s | MFE_MAE=on",
                                  CCTTesterTimeModelLabel(),
                                  ServerUTCOffsetSec(CurrentServerTime()),
                                  CCTTesterExecutionNYShiftSec(),
                                  CCTTesterNoBEBaseline() ? "true" : "false",
                                  Inp_BEGlobal ? "true" : "false",
                                  Inp_BENYCOEnabled ? "true" : "false",
                                  CCTRuntimeBEGlobalEnabled() ? "true" : "false",
                                  CCTRuntimeBECOEnabled() ? "true" : "false",
                                  CCTTimeframeModelLabel(),
                                  g_rrPreset,
                                  (int)Inp_FibMode,
                                  (int)Inp_FibCfg,
                                  Inp_TSFilter ? "true" : "false",
                                  Inp_UseCOTP ? "true" : "false",
                                  g_riskPct,
                                  InpCCTOnly,
                                  InpCCTTS,
                                  InpCCTTSExt));
     }

   if(IsNonVisualTesterRun())
      return INIT_SUCCEEDED;

   int timerMs=(bool)MQLInfoInteger(MQL_TESTER) ? 1500 : 250;
   EventSetMillisecondTimer(timerMs);

   // CCT_DEFER_INITIAL_VISUAL_DRAW_V1
   // Paint the dashboard first; the heavy candle-object scanner runs on the timer
   // after execution reconciliation, so init and dashboard clicks do not freeze.
   g_visualPendingInitialDraw=true;
   g_visualInitMs=GetTickCount();
   UpdateDashboards();
   ChartRedraw(ChartID());

   // CCT_LIFECYCLE_ONINIT_EXIT_V1
   return INIT_SUCCEEDED;
  }

/*
Purpose: Clear owned objects and stop the timer when the EA is removed.
Constitution: Ch. 26.5 immediate EA-removal cleanup.
Inputs: reason - deinitialization reason code.
Outputs: None.
*/
// CCT_DEINIT_DIAG_V1
// Diagnostic-only helpers. They do not delete or preserve anything.
string CCTDeinitDiagReasonName(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return "REASON_PROGRAM";
      case REASON_REMOVE:      return "REASON_REMOVE";
      case REASON_RECOMPILE:   return "REASON_RECOMPILE";
      case REASON_CHARTCHANGE: return "REASON_CHARTCHANGE";
      case REASON_CHARTCLOSE:  return "REASON_CHARTCLOSE";
      case REASON_PARAMETERS:  return "REASON_PARAMETERS";
      case REASON_ACCOUNT:     return "REASON_ACCOUNT";
      case REASON_TEMPLATE:    return "REASON_TEMPLATE";
      case REASON_INITFAILED:  return "REASON_INITFAILED";
      case REASON_CLOSE:       return "REASON_CLOSE";
     }
   return "REASON_"+IntegerToString(reason);
  }

void CCTDeinitDiagObjectCounts(int &total,int &cctPrefix,int &dashPrefix,int &metaPrefix,int &otherObjects)
  {
   total=ObjectsTotal(0,-1,-1);
   cctPrefix=0;
   dashPrefix=0;
   metaPrefix=0;
   otherObjects=0;

   for(int i=total-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      bool isCct=(StringFind(name,"CCT_")==0);
      bool isDash=(StringFind(name,"CCTD_")==0 || StringFind(name,"CCT_DASH")==0 || StringFind(name,"CCT_Dashboard")==0 || StringFind(name,"CCT_DASHBOARD")==0 || StringFind(name,"CCT_DB")==0);
      bool isMeta=(StringFind(name,"CCTM_")==0 || StringFind(name,"CCT_META")==0 || StringFind(name,"CCT_VISUAL_META")==0);

      if(isCct)
         cctPrefix++;
      if(isDash)
         dashPrefix++;
      if(isMeta)
         metaPrefix++;
      if(!isCct && !isDash && !isMeta)
         otherObjects++;
     }
  }

// CCT_DEINIT_FINAL_OWNED_CLEANUP_V1
// Final OnDeinit hardening: delete residual CCT-owned chart objects and print sample names.
// This runs after the normal hard reset path and does not touch broker/trade logic.
bool CCTDeinitFinalOwnsObjectName(string name)
  {
   string n=name;
   StringToUpper(n);

   if(StringFind(n,"CCT")==0)
      return true;
   if(StringFind(n,"CCT_")>=0 || StringFind(n,"_CCT")>=0)
      return true;

   if(StringLen(n)>=3)
     {
      string p3=StringSubstr(n,0,3);
      if(p3=="BU_" || p3=="BE_")
         return true;
     }

   if(StringFind(n,"_POI_")>=0 ||
      StringFind(n,"_FVG_")>=0 ||
      StringFind(n,"_EXEC_")>=0 ||
      StringFind(n,"_VW")>=0 ||
      StringFind(n,"_AP")>=0 ||
      StringFind(n,"_CAP")>=0 ||
      StringFind(n,"_DASH")>=0 ||
      StringFind(n,"DASHBOARD")>=0 ||
      StringFind(n,"ACTIONPILLAR")>=0)
      return true;

   return false;
  }

string CCTDeinitLogSafeString(string value,const int maxLen)
  {
   StringReplace(value,"\r"," ");
   StringReplace(value,"\n"," ");
   StringReplace(value,"\t"," ");
   if(maxLen>0 && StringLen(value)>maxLen)
      return StringSubstr(value,0,maxLen)+"...";
   return value;
  }

string CCTDeinitObjectDetail(const string name)
  {
   ResetLastError();
   long objType=ObjectGetInteger(0,name,OBJPROP_TYPE);
   long tfMask=ObjectGetInteger(0,name,OBJPROP_TIMEFRAMES);
   long hidden=ObjectGetInteger(0,name,OBJPROP_HIDDEN);
   long back=ObjectGetInteger(0,name,OBJPROP_BACK);
   string text=CCTDeinitLogSafeString(ObjectGetString(0,name,OBJPROP_TEXT),40);
   string tip=CCTDeinitLogSafeString(ObjectGetString(0,name,OBJPROP_TOOLTIP),70);

   return name+
          "{type="+EnumToString((ENUM_OBJECT)objType)+
          ",tf="+IntegerToString((long)tfMask)+
          ",hidden="+IntegerToString((long)hidden)+
          ",back="+IntegerToString((long)back)+
          ",text="+text+
          ",tip="+tip+"}";
  }

string CCTDeinitDetailedObjectSample(const int mode,const int maxSamples)
  {
   // mode: 0=all, 1=CCT-owned, 2=non-owned.
   string sample="";
   int added=0;
   int total=ObjectsTotal(0,-1,-1);

   for(int i=total-1;i>=0 && added<maxSamples;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      bool owned=CCTDeinitFinalOwnsObjectName(name);
      if(mode==1 && !owned)
         continue;
      if(mode==2 && owned)
         continue;

      if(sample!="")
         sample+=" | ";
      sample+=CCTDeinitObjectDetail(name);
      added++;
     }

   return sample;
  }

string CCTDeinitIndicatorSample(const int maxSamples)
  {
   string sample="";
   int added=0;
   int windows=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   for(int w=0;w<windows && added<maxSamples;w++)
     {
      int n=ChartIndicatorsTotal(0,w);
      for(int i=0;i<n && added<maxSamples;i++)
        {
         string name=ChartIndicatorName(0,w,i);
         if(sample!="")
            sample+=" | ";
         sample+="win"+IntegerToString(w)+":"+name;
         added++;
        }
     }
   return sample;
  }

void CCTDeinitFinalCountObjects(int &total,int &owned,int &other)
  {
   total=ObjectsTotal(0,-1,-1);
   owned=0;
   other=0;

   for(int i=total-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(CCTDeinitFinalOwnsObjectName(name))
         owned++;
      else
         other++;
     }
  }

string CCTDeinitFinalSampleObjects(const bool ownedOnly,const int maxSamples)
  {
   string sample="";
   int added=0;
   int total=ObjectsTotal(0,-1,-1);

   for(int i=total-1;i>=0 && added<maxSamples;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      bool owned=CCTDeinitFinalOwnsObjectName(name);
      if(ownedOnly && !owned)
         continue;
      if(!ownedOnly && owned)
         continue;

      if(sample!="")
         sample+=" | ";
      sample+=name;
      added++;
     }

   return sample;
  }

void CCTDeinitFinalDeleteOwnedPass(const int pass,int &attempted,int &deleted,int &failed)
  {
   attempted=0;
   deleted=0;
   failed=0;

   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(!CCTDeinitFinalOwnsObjectName(name))
         continue;

      attempted++;
      ResetLastError();
      if(ObjectDelete(0,name))
         deleted++;
      else
        {
         failed++;
         int err=GetLastError();
         if(!CCTSuppressLiveCCTJournals())
            PrintFormat("[CCT DEINIT FINAL CLEANUP FAIL] pass=%d | name=%s | err=%d",pass,name,err);
        }
     }
  }

void CCTFinalDeinitCleanup(const int reason)
  {
   int totalBefore=0,ownedBefore=0,otherBefore=0;
   CCTDeinitFinalCountObjects(totalBefore,ownedBefore,otherBefore);

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT FINAL CLEANUP START] reason=%d | symbol=%s | period=%s | totalBefore=%d | ownedBefore=%d | otherBefore=%d | ownedSample=%s | otherSample=%s",
                  reason,
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  totalBefore,
                  ownedBefore,
                  otherBefore,
                  CCTDeinitFinalSampleObjects(true,8),
                  CCTDeinitFinalSampleObjects(false,8));

   int totalAttempted=0;
   int totalDeleted=0;
   int totalFailed=0;

   for(int pass=1;pass<=3;pass++)
     {
      int attempted=0,deleted=0,failed=0;
      CCTDeinitFinalDeleteOwnedPass(pass,attempted,deleted,failed);
      totalAttempted+=attempted;
      totalDeleted+=deleted;
      totalFailed+=failed;
      if(attempted<=0)
         break;
     }

   ChartRedraw(0);

   int totalAfter=0,ownedAfter=0,otherAfter=0;
   CCTDeinitFinalCountObjects(totalAfter,ownedAfter,otherAfter);

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT FINAL CLEANUP END] reason=%d | symbol=%s | period=%s | attempted=%d | deleted=%d | failed=%d | totalAfter=%d | ownedAfter=%d | otherAfter=%d | ownedSample=%s | otherSample=%s",
                  reason,
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  totalAttempted,
                  totalDeleted,
                  totalFailed,
                  totalAfter,
                  ownedAfter,
                  otherAfter,
                  CCTDeinitFinalSampleObjects(true,8),
                  CCTDeinitFinalSampleObjects(false,8));
  }

// CCT_DEINIT_PREBLANK_RENDER_INVALIDATION_V1
// Hide owned objects before deletion so MT5's renderer gets a visible invalidation even if deletion itself reports success.
void CCTPreblankOwnedObjectsForDeinitV1(const int reason)
  {
   int total=ObjectsTotal(0,-1,-1);
   int touched=0;
   string sample="";

   for(int i=total-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(!CCTDeinitFinalOwnsObjectName(name))
         continue;

      if(sample=="")
         sample=name;
      else if(StringLen(sample)<220)
         sample+=" | "+name;

      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,0);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrNONE);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrNONE);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrNONE);
      ObjectSetString(0,name,OBJPROP_TEXT,"");
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"");
      touched++;
     }

   ChartRedraw(0);

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT PREBLANK RENDER INVALIDATION] reason=%d | symbol=%s | period=%s | totalBefore=%d | touched=%d | sample=%s",
                  reason,
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  total,
                  touched,
                  sample);
  }

void CCTFastHardUnloadEraseV1(const int reason)
  {
   if(!CCTDeinitHardUnloadReasonV1(reason))
      return;

   int totalBefore=ObjectsTotal(0,-1,-1);
   bool diag=(!CCTSuppressLiveCCTJournals() && CCTDebugEnabled());
   string ownedSample=diag ? CCTDeinitDetailedObjectSample(1,8) : "";
   string otherSample=diag ? CCTDeinitDetailedObjectSample(2,8) : "";
   string indicators=diag ? CCTDeinitIndicatorSample(8) : "";
   long tradeLevels=diag ? (long)ChartGetInteger(0,CHART_SHOW_TRADE_LEVELS) : 0;

   CCTPreblankOwnedObjectsForDeinitV1(reason);
   g_dashCleared=false;
   ClearDashboards();
   int deleted=CCTDeleteAllOwnedChartObjectsV1();
   int bulkDeleted=CCTDeleteOwnedPrefixesBulkV1();
   ResourceFree(DashResName());
   ObjectsDeleteAll(0,"CCT_");
   ObjectsDeleteAll(0,"CCTD_");
   ObjectsDeleteAll(0,"CCTM_");
   ObjectsDeleteAll(0,"BU_");
   ObjectsDeleteAll(0,"BE_");
   ChartRedraw(0);

   int totalAfter=ObjectsTotal(0,-1,-1);
   if(diag)
      PrintFormat("[CCT DEINIT FAST HARD ERASE] reason=%d:%s | symbol=%s | period=%s | chart=%s | totalBefore=%d | totalAfter=%d | deleted=%d | bulkDeleted=%d | tradeLevels=%s | ownedSample=%s | otherSample=%s | indicators=%s",
                  reason,
                  CCTDeinitDiagReasonName(reason),
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  IntegerToString((long)ChartID()),
                  totalBefore,
                  totalAfter,
                  deleted,
                  bulkDeleted,
                  tradeLevels ? "on" : "off",
                  ownedSample,
                  otherSample,
                  indicators);
  }

void OnDeinit(const int reason)
  {
   // CCT_DEINIT_LATCH_SET_ONDEINIT_V1
   CCTSetDeinitEventLatchV1(reason);
   EventKillTimer();
   bool softReinit=CCTSoftReinitReason(reason);
   if(!softReinit)
     {
      g_cctDeinitRenderPurgeModeV1=true;
      RefreshState(true);
      g_cctDeinitRenderPurgeModeV1=false;
      CCTFastHardUnloadEraseV1(reason);
      if(CCTDeinitHardUnloadReasonV1(reason))
        {
         CCTFinalDeinitCleanup(reason);
         ChartRedraw(0);
         CCTMarkHardUnloadDeinitV1(reason,ObjectsTotal(0,-1,-1));
         return;
        }
     }

   // CCT_DEINIT_DIAG_START_V1
   ulong cctDeinitDiagStartUs=GetMicrosecondCount();
   int cctDeinitTotalBefore=0;
   int cctDeinitPrefixBefore=0;
   int cctDeinitDashBefore=0;
   int cctDeinitMetaBefore=0;
   int cctDeinitOtherBefore=0;
   CCTDeinitDiagObjectCounts(cctDeinitTotalBefore,cctDeinitPrefixBefore,cctDeinitDashBefore,cctDeinitMetaBefore,cctDeinitOtherBefore);
   if(!CCTSuppressLiveCCTJournals())
     {
      PrintFormat("[CCT DEINIT DIAG START] reason=%d:%s | symbol=%s | period=%s | chart=%s | account=%s | stopped=%s | tester=%s | visualTester=%s | totalBefore=%d | cctBefore=%d | dashBefore=%d | metaBefore=%d | otherBefore=%d",
                  reason,
                  CCTDeinitDiagReasonName(reason),
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  IntegerToString((long)ChartID()),
                  IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
                  IsStopped() ? "yes" : "no",
                  MQLInfoInteger(MQL_TESTER) ? "yes" : "no",
                  MQLInfoInteger(MQL_VISUAL_MODE) ? "yes" : "no",
                  cctDeinitTotalBefore,
                  cctDeinitPrefixBefore,
                  cctDeinitDashBefore,
                  cctDeinitMetaBefore,
                  cctDeinitOtherBefore);
      PrintFormat("[CCT DEINIT DIAG SAMPLE] phase=start | reason=%d | symbol=%s | period=%s | chart=%s | ownedSample=%s | otherSample=%s | indicators=%s",
                  reason,
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  IntegerToString((long)ChartID()),
                  CCTDeinitDetailedObjectSample(1,8),
                  CCTDeinitDetailedObjectSample(2,8),
                  CCTDeinitIndicatorSample(8));
     }
   // CCT_LIFECYCLE_DIAG_ONDEINIT_ENTER_V1
   // CCT_LIFECYCLE_ONDEINIT_ENTER_V1
   EventKillTimer();

   // CCT MFE/MAE RESEARCH HOOK: tester-only telemetry; no execution logic changed.
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      CCTResearchUpdateOpenRecords();
      CCTResearchEmitResolvedRecords();
     }

   if(IsNonVisualTesterRun())
     {
      double avgMs=(g_perfNvFullReplays>0) ? ((double)g_perfNvReplayMicros/(double)g_perfNvFullReplays/1000.0) : 0.0;
      double maxMs=(double)g_perfNvMaxReplayMicros/1000.0;
      CCTJournalLine(StringFormat("[CCT PERF] nonvisual refreshCalls=%s fullReplays=%s cachedSkips=%s scheduleSkips=%s throttleSkips=%s avgReplayMs=%.3f maxReplayMs=%.3f",
                                  IntegerToString((long)g_perfNvRefreshCalls),
                                  IntegerToString((long)g_perfNvFullReplays),
                                  IntegerToString((long)g_perfNvCachedSkips),
                                  IntegerToString((long)g_perfNvScheduleSkips),
                                  IntegerToString((long)g_perfNvThrottleSkips),
                                  avgMs,
                                  maxMs));
     }

   CCTTesterJournalClose();
  
   
   // CCT_DEINIT_FINAL_CLEANUP_CALL_V1
   CCTFinalDeinitCleanup(reason);

   // CCT_DEINIT_HARD_UNLOAD_PURGE_CONFIRM_CALL_V1
   CCTConfirmHardUnloadVisualPurgeV1(reason);
   // CCT_DEINIT_DIAG_END_V1
   int cctDeinitTotalAfter=0;
   int cctDeinitPrefixAfter=0;
   int cctDeinitDashAfter=0;
   int cctDeinitMetaAfter=0;
   int cctDeinitOtherAfter=0;
   CCTDeinitDiagObjectCounts(cctDeinitTotalAfter,cctDeinitPrefixAfter,cctDeinitDashAfter,cctDeinitMetaAfter,cctDeinitOtherAfter);
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT DIAG SAMPLE] phase=end | reason=%d | symbol=%s | period=%s | chart=%s | allSample=%s | indicators=%s",
                  reason,
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  IntegerToString((long)ChartID()),
                  CCTDeinitDetailedObjectSample(0,8),
                  CCTDeinitIndicatorSample(8));

   // CCT_DEINIT_HARD_UNLOAD_MARK_CALL_V1
   CCTMarkHardUnloadDeinitV1(reason,cctDeinitTotalAfter);
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT DEINIT DIAG END] reason=%d:%s | symbol=%s | period=%s | elapsed_us=%s | totalAfter=%d | cctAfter=%d | dashAfter=%d | metaAfter=%d | otherAfter=%d | deltaCct=%d | deltaTotal=%d",
                  reason,
                  CCTDeinitDiagReasonName(reason),
                  _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period),
                  IntegerToString((long)(GetMicrosecondCount()-cctDeinitDiagStartUs)),
                  cctDeinitTotalAfter,
                  cctDeinitPrefixAfter,
                  cctDeinitDashAfter,
                  cctDeinitMetaAfter,
                  cctDeinitOtherAfter,
                  cctDeinitPrefixAfter-cctDeinitPrefixBefore,
                  cctDeinitTotalAfter-cctDeinitTotalBefore);
}

/*
Purpose: Return the latest closed LTF bar used by the execution pulse.
Constitution: Broker execution must be separated from visual refresh and must run from both tick and timer events.
Inputs: None.
Outputs: Latest closed LTF bar open time, or 0 when unavailable.
*/
datetime CCTLastClosedLTFBarForExecution()
  {
   datetime lastClosed=iTime(_Symbol,LTF(),1);
   if(lastClosed>0)
      return lastClosed;

   int ltfSec=(int)PeriodSeconds(LTF());
   datetime currentOpen=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   if(currentOpen>0 && ltfSec>0)
      return currentOpen-(datetime)ltfSec;

   return 0;
  }

/*
Purpose: Detect the final seconds of the forming LTF candle so caches can be warmed before a possible closed-bar trigger.
Constitution: Pre-close warming is allowed; broker entry before C3 close is not allowed.
Inputs: None.
Outputs: True once per forming LTF bar when the pre-close warmup window is reached.
*/
bool CCTPreCloseWarmupDue()
  {
   if((bool)MQLInfoInteger(MQL_TESTER))
      return false;

   static datetime s_lastPreCloseWarm=0;

   datetime liveLtfOpen=iTime(_Symbol,LTF(),0);
   int ltfSec=(int)PeriodSeconds(LTF());
   datetime now=CurrentServerTime();

   if(liveLtfOpen>0 && ltfSec>0 &&
      now>=(liveLtfOpen+(datetime)ltfSec-2) &&
      s_lastPreCloseWarm!=liveLtfOpen)
     {
      s_lastPreCloseWarm=liveLtfOpen;
      return true;
     }

   return false;
  }

/*
Purpose: Run the broker-critical execution path without dashboard or chart-object work.
Constitution: Execution, safety, and BE management must be first-class and must not wait for visual rendering.
Inputs: forceWarmup - when true, refresh scanner state even if the closed LTF bar has not advanced.
Outputs: None.
*/
void CCTExecutionPulse(bool forceWarmup=false)
  {
   static datetime s_lastLtfClosed=0;
   static datetime s_lastHtfBar=0;

   datetime lastLtfClosed=CCTLastClosedLTFBarForExecution();
   datetime htfBar=CCTCurrentHTFBarOpenMarker();

   if(lastLtfClosed<=0)
      return;
bool htfAdvanced=(htfBar!=s_lastHtfBar);
   bool advanced=(lastLtfClosed!=s_lastLtfClosed || htfAdvanced);

   // In non-visual tester, entries are closed-bar scanner events. Repeated
   // intra-bar ticks only need management when BE, virtual TP, or safety guards
   // are enabled; no-BE research runs let MT5 handle broker SL/TP directly.
   if(IsNonVisualTesterRun() && !advanced && !forceWarmup &&
      (!CCTTesterHasOpenPosition() || CCTNonVisualTesterCanSkipIntrabarManagement()))
      return;

   if(!CCTNonVisualTesterCanSkipIntrabarManagement())
     {
      CCTReconcileBrokerDeals(false);
      CCTManageSafetyGuards();
      CCTUpdatePositionBE();
      CCTReconcileBrokerDeals(false);
     }

   if(!advanced && !forceWarmup)
      return;

   if(advanced)
     {
      s_lastLtfClosed=lastLtfClosed;
      s_lastHtfBar=htfBar;
     }

   CCTWarmPropFirmSafetyCache(forceWarmup);
   ulong scanStartUs=GetMicrosecondCount();
   g_cctExecPulseSeenLtf=lastLtfClosed;
   g_cctExecPulseSeenServer=CurrentServerTime();
   if(g_cctExecPulseSeenServer<=0)
      g_cctExecPulseSeenServer=TimeCurrent();
   g_cctExecPulseScanStartUs=scanStartUs;
   g_cctExecPulseScanEndUs=0;
   g_cctExecPulseSource=forceWarmup ? "warmup" : (htfAdvanced ? "htf_advanced" : "closed_bar");
   RefreshState(false);
   g_cctExecPulseScanEndUs=GetMicrosecondCount();

   // CCT_VISUAL_REFRESH_AFTER_SCANNER_V1
   // Execution scanner truth has advanced; request visual reconciliation on the timer side.
   // This does not wait for visuals and does not delay broker execution.
   if(!IsNonVisualTesterRun())
      CCTRequestVisualRefreshAfterScanner(forceWarmup ? "execution_warmup" : (htfAdvanced ? "execution_htf" : "execution_scan"),lastLtfClosed);

   ulong scanElapsedUs=g_cctExecPulseScanEndUs-scanStartUs;
   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || scanElapsedUs>60000))
      CCTJournalLine(StringFormat("[CCT EXEC SCAN TIMING] symbol=%s | ltf=%s | elapsed_us=%s | force=%s | htfAdvanced=%s",
                                  _Symbol,
                                  TimeToString(lastLtfClosed,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  IntegerToString((long)scanElapsedUs),
                                  forceWarmup ? "true" : "false",
                                  htfAdvanced ? "true" : "false"));
  }


bool     g_cctVisualRefreshPending=false;
datetime g_cctVisualRefreshRequestedLtf=0;
string   g_cctVisualRefreshReason="";
uint     g_cctVisualRefreshRequestedMs=0;
int      g_cctVisualRefreshPriority=0;

datetime g_cctVisualLastCompletedLtf=0;
string   g_cctVisualLastCompletedReason="";
uint     g_cctVisualLastCompletedMs=0;
int      g_cctVisualLastCompletedPriority=0;

int CCTVisualRefreshReasonPriority(const string reason)
  {
   // CCT_VISUAL_REFRESH_COALESCE_V1
   if(reason=="execution_htf")
      return 4;
   if(reason=="execution_warmup")
      return 3;
   if(reason=="initial")
      return 2;
   if(reason=="historical_reconcile")
      return 2;
   if(reason=="execution_scan")
      return 1;
   if(reason=="execution_ltf_bar")
      return 1;
   return 1;
  }

void CCTRequestVisualRefreshAfterScanner(const string reason,datetime ltfClosed)
  {
   // CCT_VISUAL_PLAIN_SCAN_THROTTLE_V1
   // Coalesce duplicate visual requests and throttle ordinary scan/warmup redraws.
   // Broker execution/scanner work remains first; visuals stay timer-side.
   if(IsNonVisualTesterRun())
      return;

   if(ltfClosed<=0)
      ltfClosed=CCTLastClosedLTFBarForExecution();

   if(ltfClosed<=0)
      return;

   uint nowMs=GetTickCount();
   int priority=CCTVisualRefreshReasonPriority(reason);

   // CCT_NO_WARMUP_FULL_VISUAL_REDRAW_V1
   // Warmup pulses are broker/safety-side scanner pulses. They must not, by themselves,
   // queue a full RefreshState(true) visual rebuild and freeze the dashboard.
   // HTF transitions and normal execution_scan requests remain governed by the existing coalescer.
   if(reason=="execution_warmup")
     {
      if(CCTDebugEnabled())
         CCTJournalLine(StringFormat("[CCT VISUAL REQUEST SKIP] symbol=%s | reason=%s | requested=%s | completed=%s | gate=warmup_no_full_draw",
                                     _Symbol,
                                     reason,
                                     TimeToString(ltfClosed,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     TimeToString(g_cctVisualLastCompletedLtf,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
      return;
     }

   // Already drawn LTF state: ordinary scan/warmup must not redraw it again.
   if(g_cctVisualLastCompletedLtf>0 && ltfClosed<=g_cctVisualLastCompletedLtf && priority<4)
     {
      if(CCTDebugEnabled())
         CCTJournalLine(StringFormat("[CCT VISUAL REQUEST SKIP] symbol=%s | reason=%s | requested=%s | completed=%s | gate=already_drawn",
                                     _Symbol,
                                     reason,
                                     TimeToString(ltfClosed,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     TimeToString(g_cctVisualLastCompletedLtf,TIME_DATE|TIME_MINUTES|TIME_SECONDS)));
      return;
     }

   // Plain scan redraws are coalesced but no longer held for minutes; live
   // object tracking has its own fast path and structural visuals get a timely reconcile.
   if(priority<4 && g_cctVisualLastCompletedMs>0 && (uint)(nowMs-g_cctVisualLastCompletedMs)<1500)
     {
      if(CCTDebugEnabled())
         CCTJournalLine(StringFormat("[CCT VISUAL REQUEST SKIP] symbol=%s | reason=%s | requested=%s | completed=%s | gate=recent_full_draw | age_ms=%d",
                                     _Symbol,
                                     reason,
                                     TimeToString(ltfClosed,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     TimeToString(g_cctVisualLastCompletedLtf,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     (int)(nowMs-g_cctVisualLastCompletedMs)));
      return;
     }

   // If a same/newer visual refresh is already pending, keep only the higher-priority request.
   if(g_cctVisualRefreshPending)
     {
      if(ltfClosed<g_cctVisualRefreshRequestedLtf)
         return;

      if(ltfClosed==g_cctVisualRefreshRequestedLtf && priority<=g_cctVisualRefreshPriority)
         return;
     }

   g_cctVisualRefreshPending=true;
   g_cctVisualRefreshRequestedLtf=ltfClosed;
   g_cctVisualRefreshReason=reason;
   g_cctVisualRefreshRequestedMs=nowMs;
   g_cctVisualRefreshPriority=priority;
  }

void CCTFastLiveExecutionVisualPulse()
  {
   // CCT_FAST_EXEC_VISUAL_PULSE_V1
   // Keep live execution geometry moving without forcing a full scanner redraw.
   if(IsNonVisualTesterRun())
      return;

   ulong pulseStartUs=GetMicrosecondCount();
   int drawn=0;
   for(int i=0;i<g_nExecRecords;i++)
     {
      if(g_execRecords[i].genKey=="")
         continue;
      CCTSyncExecRecordOutcomeFromGlobal(i,true);
      if(g_execRecords[i].exitTime>0 || CCTResolvedState(g_execRecords[i].outcome))
         continue;
      if(g_execRecords[i].triggerBarTime<=0)
         continue;
      if(Inp_SessionFilter)
        {
         datetime triggerHTF=HTFBarOpenForTime(g_execRecords[i].triggerBarTime);
         datetime authTime=(Inp_TimeframeModel==CCT_TFM_D1_M15) ? g_execRecords[i].triggerBarTime : triggerHTF;
         if(authTime<=0 || !CCTModelAnyAuthAllows(authTime))
            continue;
        }

      CCTDrawExecutionSnapshotCore(g_execRecords[i],false);
      drawn++;
     }

   if(drawn>0)
      ChartRedraw(0);

   ulong pulseElapsedUs=GetMicrosecondCount()-pulseStartUs;
   if(drawn>0 && CCTProfileTimingEnabled() && (CCTDebugEnabled() || pulseElapsedUs>80000))
      CCTJournalLine(StringFormat("[CCT FAST VISUAL TIMING] symbol=%s | liveExec=%d | elapsed_us=%s",
                                  _Symbol,
                                  drawn,
                                  IntegerToString((long)pulseElapsedUs)));
  }
/*
Purpose: Run visual/dashboard work after the execution pulse, never before it.
Constitution: Chart rendering is secondary to broker execution and must not block the entry path.
Inputs: None.
Outputs: None.
*/
void CCTVisualPulse()
  {
   if(IsNonVisualTesterRun())
      return;

   static datetime s_lastVisualLtfClosed=0;
   static uint s_lastDashboardMs=0;
   static uint s_lastGlowMs=0;
   static uint s_lastFastExecMs=0;

   uint nowMs=GetTickCount();

   if(s_lastFastExecMs==0 || (uint)(nowMs-s_lastFastExecMs)>=500)
     {
      s_lastFastExecMs=nowMs;
      CCTFastLiveExecutionVisualPulse();
     }

   // Cheap heartbeat first: dashboard/clock stays responsive without forcing scanner redraw.
   if(s_lastDashboardMs==0 || (uint)(nowMs-s_lastDashboardMs)>=1000)
     {
      s_lastDashboardMs=nowMs;
      UpdateDashboards();
     }

   // Candidate glow remains lightweight and independent of full redraw cadence.
   if(s_lastGlowMs==0 || (uint)(nowMs-s_lastGlowMs)>=500)
     {
      s_lastGlowMs=nowMs;
      PulseCandidateGlowObjects();
     }

   if(g_visualPendingInitialDraw &&
      (uint)(nowMs-g_visualInitMs)>=1500 &&
      (g_dashLastInteractionMs==0 || (uint)(nowMs-g_dashLastInteractionMs)>=2000))
     {
      // CCT_VISUAL_PLAIN_SCAN_THROTTLE_V1
      // Initial draw is a full visual reconcile. Stamp this LTF state as complete
      // so scan/warmup does not immediately redraw the same state.
      g_visualPendingInitialDraw=false;

      datetime initLtfClosed=CCTLastClosedLTFBarForExecution();
      if(initLtfClosed>0)
         s_lastVisualLtfClosed=initLtfClosed;

      g_cctVisualRefreshPending=false;
      g_cctVisualRefreshRequestedLtf=0;
      g_cctVisualRefreshReason="";
      g_cctVisualRefreshRequestedMs=0;
      g_cctVisualRefreshPriority=0;

      ulong visualStartUs=GetMicrosecondCount();
      bool prevFastInitial=g_cctFastInitialVisualMode;
      g_cctFastInitialVisualMode=true;
      RefreshState(true);
      g_cctFastInitialVisualMode=prevFastInitial;
      ulong visualElapsedUs=GetMicrosecondCount()-visualStartUs;

      if(initLtfClosed>0)
         g_cctVisualLastCompletedLtf=initLtfClosed;
      g_cctVisualLastCompletedReason="initial";
      g_cctVisualLastCompletedMs=GetTickCount();
      g_cctVisualLastCompletedPriority=CCTVisualRefreshReasonPriority("initial");

      g_cctVisualRefreshPending=false;
      g_cctVisualRefreshRequestedLtf=0;
      g_cctVisualRefreshReason="";
      g_cctVisualRefreshRequestedMs=0;
      g_cctVisualRefreshPriority=0;
      g_visualPendingHistoricalReconcile=true;
      g_visualHistoricalReconcileMs=GetTickCount();

      if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || visualElapsedUs>250000))
         CCTJournalLine(StringFormat("[CCT VISUAL TIMING] symbol=%s | phase=initial | ltf=%s | elapsed_us=%s",
                                     _Symbol,
                                     TimeToString(initLtfClosed,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                     IntegerToString((long)visualElapsedUs)));
      UpdateDashboards();
      return;
     }

   datetime lastLtfClosed=CCTLastClosedLTFBarForExecution();

   // Preserve dashboard interaction protection; pending visual refresh is not discarded.
   if(g_dashLastInteractionMs>0 && (uint)(nowMs-g_dashLastInteractionMs)<2000)
      return;

   if(g_visualPendingHistoricalReconcile &&
      (uint)(nowMs-g_visualHistoricalReconcileMs)>=60000 &&
      (g_dashLastInteractionMs==0 || (uint)(nowMs-g_dashLastInteractionMs)>=15000))
     {
      g_visualPendingHistoricalReconcile=false;
      g_cctVisualRefreshPending=true;
      g_cctVisualRefreshRequestedLtf=lastLtfClosed;
      g_cctVisualRefreshReason="historical_reconcile";
      g_cctVisualRefreshRequestedMs=nowMs;
      g_cctVisualRefreshPriority=CCTVisualRefreshReasonPriority("historical_reconcile");
     }

   bool forcedRefresh=g_cctVisualRefreshPending;
   bool newClosedBar=(lastLtfClosed>0 && lastLtfClosed!=s_lastVisualLtfClosed);
   string refreshReason=g_cctVisualRefreshReason;
   datetime requestedLtf=g_cctVisualRefreshRequestedLtf;
   int requestedPriority=g_cctVisualRefreshPriority;

   if(newClosedBar && !forcedRefresh)
     {
      forcedRefresh=true;
      refreshReason="execution_ltf_bar";
      requestedLtf=lastLtfClosed;
      requestedPriority=CCTVisualRefreshReasonPriority(refreshReason);
     }

   if(!forcedRefresh)
      return;

   if(refreshReason=="")
      refreshReason="execution_ltf_bar";
   if(requestedLtf<=0)
      requestedLtf=lastLtfClosed;
   if(requestedPriority<=0)
      requestedPriority=CCTVisualRefreshReasonPriority(refreshReason);

   g_cctVisualRefreshPending=false;
   g_cctVisualRefreshRequestedLtf=0;
   g_cctVisualRefreshReason="";
   g_cctVisualRefreshRequestedMs=0;
   g_cctVisualRefreshPriority=0;

   if(lastLtfClosed>0)
      s_lastVisualLtfClosed=lastLtfClosed;

   ulong visualStartUs=GetMicrosecondCount();
   RefreshState(true);
   ulong visualElapsedUs=GetMicrosecondCount()-visualStartUs;

   datetime completedLtf=(lastLtfClosed>0 ? lastLtfClosed : requestedLtf);
   if(completedLtf>0)
      g_cctVisualLastCompletedLtf=completedLtf;
   g_cctVisualLastCompletedReason=refreshReason;
   g_cctVisualLastCompletedMs=GetTickCount();
   g_cctVisualLastCompletedPriority=requestedPriority;

   if(CCTProfileTimingEnabled() && (CCTDebugEnabled() || visualElapsedUs>250000))
      CCTJournalLine(StringFormat("[CCT VISUAL TIMING] symbol=%s | phase=forced | ltf=%s | requested=%s | reason=%s | priority=%d | elapsed_us=%s",
                                  _Symbol,
                                  TimeToString(lastLtfClosed,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(requestedLtf,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  refreshReason,
                                  requestedPriority,
                                  IntegerToString((long)visualElapsedUs)));
   UpdateDashboards();
  }

/*
Purpose: Timer event now services execution first, then visuals.
Constitution: Broker execution cannot depend only on chart ticks when the event queue is busy.
Inputs: None.
Outputs: None.
*/
void OnTimer()
  {
   // CCT_DEINIT_LATCH_BLOCK_ONTIMER_V1
   if(CCTBlockLifecycleEventDuringDeinitV1("OnTimer"))
      return;

   bool warmup=CCTPreCloseWarmupDue();
   CCTExecutionPulse(warmup);

   // CCT_NOTIFY_TIMER_SERVICE_AFTER_EXEC_V2
   // Service queued messages only after broker-critical execution/management.
   NotifyPendingOnTimer();
   NotifyReportsOnTimer();

   // CCT MFE/MAE RESEARCH HOOK: tester-only telemetry; no execution logic changed.
   CCTResearchUpdateOpenRecords();
   CCTResearchEmitResolvedRecords();

   CCTVisualPulse();
  }

/*
Purpose: Tick event now services execution only; visuals are timer-side.
Constitution: New-tick broker execution must not be delayed by dashboard or chart-object refresh.
Inputs: None.
Outputs: None.
*/
void OnTick()
  {
   // CCT_DEINIT_LATCH_BLOCK_ONTICK_V1
   if(CCTBlockLifecycleEventDuringDeinitV1("OnTick"))
      return;

   CCTExecutionPulse(false);

   if(CCTPreCloseWarmupDue())
      CCTExecutionPulse(true);

   // CCT MFE/MAE RESEARCH HOOK: tester-only telemetry; no execution logic changed.
   CCTResearchUpdateOpenRecords();
   CCTResearchEmitResolvedRecords();
  }

void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp)
  {
   // CCT_DEINIT_LATCH_BLOCK_ONCHARTEVENT_V1
   if(CCTBlockLifecycleEventDuringDeinitV1("OnChartEvent"))
      return;
   // CCT_CHART_EVENT_DASHBOARD_ONLY_NO_FORCED_REBUILD_V2
   HandleDashboardEvent(id,lp,dp,sp);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // CCT MFE/MAE RESEARCH HOOK: tester-only telemetry; no execution logic changed.
   CCTResearchUpdateOpenRecords();

   CCTHandleTradeTransaction(trans);
   CCTResearchEmitResolvedRecords();
  }

double OnTester()
  {
   return TesterStatistics(STAT_PROFIT);
  }
