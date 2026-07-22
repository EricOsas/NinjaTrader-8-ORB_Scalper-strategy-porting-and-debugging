//+------------------------------------------------------------------+
//| CCT_EA_v6.mq5  v6.2                                              |
//| CCT Technical Constitution — split-file architecture.            |
//| v6.2 changes:                                                    |
//|   - Debug prints gated behind Inp_ShowDebug                     |
//|   - CHART_CHANGE only logs on TF change (never on scroll/zoom)  |
//|   - Timer flush log suppressed unless ShowDebug                  |
//|   - Dashboard init / update / event wired in                    |
//|   - g_riskPct initialised from Inp_DefaultRiskPct               |
//+------------------------------------------------------------------+
#property copyright "CCT Systems"
#property version   "6.20"
#property strict

#include "CCT_Globals.mqh"
#include "CCT_Scanner.mqh"
#include "CCT_Visual.mqh"
#include "CCT_Dashboard.mqh"
#include "CCT_Execution.mqh"

uint g_attachTick=0;
uint g_lastTickMs=0;
uint g_lastDashboardUpdateMs=0;
bool g_resettingOwnedState=false;

struct PeriodTipCache
  {
   datetime startTime;
   datetime boundaryTime;
   string   tip;
   uint     builtMs;
  };

PeriodTipCache g_dayTipCache[];
int            g_nDayTipCache=0;
PeriodTipCache g_weekTipCache[];
int            g_nWeekTipCache=0;

bool DashboardRuntimeEnabled()
  {
   return (Inp_ShowDashboard && !IsNonVisualTesterRun());
  }

uint DashboardUpdateIntervalMs()
  {
   if(IsNonVisualTesterRun()) return 1000;
   if(IsVisualTesterRun()) return 200;
   return 200;
  }

bool DashboardUpdateDue(uint nowMs)
  {
   if(!DashboardRuntimeEnabled()) return false;
   uint intervalMs=DashboardUpdateIntervalMs();
   if(intervalMs==0) return true;
   if(g_lastDashboardUpdateMs==0 || nowMs-g_lastDashboardUpdateMs>=intervalMs)
     {
      g_lastDashboardUpdateMs=nowMs;
      return true;
     }
   return false;
  }

uint RuntimeTimerIntervalMs()
  {
   if(IsNonVisualTesterRun()) return 1000;
   if(IsVisualTesterRun()) return 500;
   return 200;
  }

bool AllowTickIntrabarFastDraw(uint nowMs)
  {
   if(IsNonVisualTesterRun())
      return false;
   if(IsVisualTesterRun())
     {
      static uint s_lastTesterFastDraw=0;
      if(s_lastTesterFastDraw!=0 && nowMs-s_lastTesterFastDraw<250)
         return false;
      s_lastTesterFastDraw=nowMs;
     }
   return true;
  }

string CachedPeriodTooltip(PeriodTipCache &cache[],int &count,datetime trackedStart,datetime boundaryTime,bool isWeek)
  {
   uint nowMs=GetTickCount();
   bool mutablePeriod=(boundaryTime>TimeCurrent());
   uint refreshMs=mutablePeriod?250:60000;
   for(int i=0;i<count;i++)
     {
      if(cache[i].startTime!=trackedStart || cache[i].boundaryTime!=boundaryTime)
         continue;
      if(cache[i].tip!="" && (!mutablePeriod || nowMs-cache[i].builtMs<refreshMs))
         return cache[i].tip;
      break;
     }

   string tip;
   if(isWeek)
     {
      DaySeparatorStats stats;
      BuildPeriodSeparatorStats(trackedStart,boundaryTime,stats);
      double base=EffectiveAccountBase();
      double pnlPct=(base>0.0)?(stats.pnlCash/base)*100.0:0.0;
      int openTotal=stats.bullOpen+stats.bearOpen;
      int closedTotal=stats.tpCount+stats.slCount+stats.beCount;
      string status=(openTotal>0)?"Open until remaining trades resolve":"Closed";
      string pnlStr=(pnlPct>=0.0?"+":"")+DoubleToString(pnlPct,2)+"%";
      tip="Week Separator"
          +"\nTracks week from: "+WrittenDayDate(trackedStart)
          +"\nBoundary: "+WrittenDayDateTime(boundaryTime)
          +"\nBull triggered: "+IntegerToString(stats.bullTriggered)
          +"\nBear triggered: "+IntegerToString(stats.bearTriggered)
          +"\nOpen from week: "+IntegerToString(openTotal)
          +" ("+IntegerToString(stats.bullOpen)+" bull, "+IntegerToString(stats.bearOpen)+" bear)"
          +"\nClosed: "+IntegerToString(closedTotal)
          +" | TP "+IntegerToString(stats.tpCount)
          +" | SL "+IntegerToString(stats.slCount)
          +" | BE "+IntegerToString(stats.beCount)
          +"\nNet: "+pnlStr
          +"  ("+DoubleToString(stats.pnlCash,2)+")"
          +"\nStatus: "+status
          +"\nTrades owned by trigger week only"
          +"\nHorizon: action/day recent window";
     }
   else
     {
      DaySeparatorStats stats;
      BuildDaySeparatorStats(trackedStart,boundaryTime,stats);
      double base=EffectiveAccountBase();
      double pnlPct=(base>0.0)?(stats.pnlCash/base)*100.0:0.0;
      int openTotal=stats.bullOpen+stats.bearOpen;
      int closedTotal=stats.tpCount+stats.slCount+stats.beCount;
      string status=(openTotal>0)?"Open until remaining trades resolve":"Closed";
      string pnlStr=(pnlPct>=0.0?"+":"")+DoubleToString(pnlPct,2)+"%";
      tip="Day Separator"
          +"\nTracks: "+WrittenDayDate(trackedStart)
          +"\nBoundary: "+WrittenDayDateTime(boundaryTime)
          +"\nBull triggered: "+IntegerToString(stats.bullTriggered)
          +"\nBear triggered: "+IntegerToString(stats.bearTriggered)
          +"\nOpen from day: "+IntegerToString(openTotal)
          +" ("+IntegerToString(stats.bullOpen)+" bull, "+IntegerToString(stats.bearOpen)+" bear)"
          +"\nClosed: "+IntegerToString(closedTotal)
          +" | TP "+IntegerToString(stats.tpCount)
          +" | SL "+IntegerToString(stats.slCount)
          +" | BE "+IntegerToString(stats.beCount)
          +"\nNet: "+pnlStr
          +"  ("+DoubleToString(stats.pnlCash,2)+")"
          +"\nStatus: "+status
          +"\nTrades owned by trigger day only"
          +"\nHorizon: action/day recent window";
     }

   int slot=-1;
   for(int i=0;i<count;i++)
     {
      if(cache[i].startTime==trackedStart && cache[i].boundaryTime==boundaryTime)
        {
         slot=i;
         break;
        }
     }
   if(slot<0)
     {
      ArrayResize(cache,count+1);
      slot=count++;
     }
   cache[slot].startTime=trackedStart;
   cache[slot].boundaryTime=boundaryTime;
   cache[slot].tip=TooltipFit(tip,230);
   cache[slot].builtMs=nowMs;
   return tip;
  }

string MonthNameShort(const int month)
  {
   string months[]={"January","February","March","April","May","June",
                    "July","August","September","October","November","December"};
   if(month<1 || month>12)
      return "";
   return months[month-1];
  }

string WrittenDayDate(datetime serverTime)
  {
   MqlDateTime dt;
   TimeToStruct(serverTime,dt);
   return IntegerToString(dt.day)+" "+MonthNameShort(dt.mon)+" "+IntegerToString(dt.year);
  }

string WrittenDayDateTime(datetime serverTime)
  {
   MqlDateTime dt;
   TimeToStruct(serverTime,dt);
   string hh=(dt.hour<10?"0":"")+IntegerToString(dt.hour);
   string mm=(dt.min<10?"0":"")+IntegerToString(dt.min);
   return WrittenDayDate(serverTime)+" "+hh+":"+mm;
  }

string DaySeparatorTooltip(datetime trackedDayStart,datetime boundaryTime)
  {
   return CachedPeriodTooltip(g_dayTipCache,g_nDayTipCache,trackedDayStart,boundaryTime,false);
  }

string WeekSeparatorTooltip(datetime trackedWeekStart,datetime boundaryTime)
  {
   return CachedPeriodTooltip(g_weekTipCache,g_nWeekTipCache,trackedWeekStart,boundaryTime,true);
  }

bool IsOwnedChartObjectName(const string &nm)
  {
   return (StringFind(nm,PFX)==0
          || StringFind(nm,"CCTW_")==0);
  }

void AddOwnedChartObjectName(string &ownedNames[],int &ownedCount,const string nm)
  {
   if(nm=="" || !IsOwnedChartObjectName(nm))
      return;
   for(int i=0; i<ownedCount; i++)
      if(ownedNames[i]==nm)
         return;
   ArrayResize(ownedNames,ownedCount+1);
   ownedNames[ownedCount++]=nm;
  }

int ChartWindowTotalSafe()
  {
   long windows=ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   if(windows<1)
      return 1;
   return (int)windows;
  }

int CollectOwnedChartObjectNames(string &ownedNames[])
  {
   ArrayResize(ownedNames,0);
   int ownedCount=0;
   for(int i=0; i<g_objCurrN; i++)
      AddOwnedChartObjectName(ownedNames,ownedCount,g_objCurr[i]);
   for(int i=0; i<g_objPrevN; i++)
      AddOwnedChartObjectName(ownedNames,ownedCount,g_objPrev[i]);
   for(int i=0; i<g_nHints; i++)
      AddOwnedChartObjectName(ownedNames,ownedCount,g_hints[i].nm);
   for(int i=0; i<g_nCands; i++)
     {
      AddOwnedChartObjectName(ownedNames,ownedCount,g_cands[i].nmHTF);
      AddOwnedChartObjectName(ownedNames,ownedCount,g_cands[i].nmLTF);
      AddOwnedChartObjectName(ownedNames,ownedCount,g_cands[i].nmPillar);
      AddOwnedChartObjectName(ownedNames,ownedCount,g_cands[i].nmPillar+"_TIP");
     }
   for(int i=0; i<g_nTsGlows; i++)
      AddOwnedChartObjectName(ownedNames,ownedCount,g_tsGlows[i].nmLine);
   for(int i=0; i<g_nExecFamilies; i++)
     {
      string genKey=g_execFamilies[i].genKey;
      if(genKey=="")
         continue;
      string familyNames[]={
         PFX+"TRIG_"+genKey,
         PFX+"HNT_S_"+genKey,
         PFX+"HNT_T_"+genKey,
         PFX+"HNT_B_"+genKey,
         PFX+"BOX_SL_"+genKey,
         PFX+"BOX_TP_"+genKey,
         PFX+"COTR_"+genKey
      };
      for(int j=0; j<ArraySize(familyNames); j++)
        {
         AddOwnedChartObjectName(ownedNames,ownedCount,familyNames[j]);
         AddOwnedChartObjectName(ownedNames,ownedCount,familyNames[j]+"_TIP");
        }
     }
   int aggTotal=ObjectsTotal(0,-1,-1);
   for(int i=aggTotal-1; i>=0; i--)
     {
      string aggName=ObjectName(0,i,-1,-1);
      AddOwnedChartObjectName(ownedNames,ownedCount,aggName);
     }
   int windows=ChartWindowTotalSafe();
   for(int wnd=0; wnd<windows; wnd++)
     {
      int total=ObjectsTotal(0,wnd,-1);
      for(int i=total-1; i>=0; i--)
        {
         string nm=ObjectName(0,i,wnd,-1);
         AddOwnedChartObjectName(ownedNames,ownedCount,nm);
        }
     }
   return ownedCount;
  }

int CountOwnedChartObjects()
  {
   string ownedNames[];
   return CollectOwnedChartObjectNames(ownedNames);
  }

bool DeleteOwnedByKnownPrefixes()
  {
   bool removed=false;
   string prefixes[]={
      PFX,
      "CCTW_",
      PFX+"POI_",
      PFX+"TS_",
      PFX+"FVG_",
      PFX+"SLHNT_",
      PFX+"CA_",
      PFX+"CAP_",
      PFX+"VW_",
      PFX+"AP_",
      PFX+"DAY_",
      PFX+"WEEK_",
      PFX+"HNT_S_",
      PFX+"HNT_T_",
      PFX+"HNT_B_",
      PFX+"BOX_SL_",
      PFX+"BOX_TP_",
      PFX+"TRIG_",
      PFX+"COTR_"
   };
   for(int i=0;i<ArraySize(prefixes);i++)
      if(ObjectsDeleteAll(0,prefixes[i],-1,-1)>0)
         removed=true;
   return removed;
  }

bool DeleteOwnedChartObjectsPass()
  {
   bool removed=false;
   string ownedNames[];
   int ownedCount=CollectOwnedChartObjectNames(ownedNames);
   for(int i=0; i<ownedCount; i++)
     {
      string nm=ownedNames[i];
      if(ObjectDelete(0,nm))
         removed=true;
     }
   if(DeleteOwnedByKnownPrefixes())
      removed=true;
   return removed;
  }

bool DeleteOwnedChartObjectsLiveSweep()
  {
   bool removed=false;
   string ownedNames[];
   int ownedCount=CollectOwnedChartObjectNames(ownedNames);
   for(int i=0; i<ownedCount; i++)
     {
      if(ObjectDelete(0,ownedNames[i]))
         removed=true;
     }
   if(DeleteOwnedByKnownPrefixes())
      removed=true;
   return removed;
  }

bool DeleteOwnedChartObjectsBruteForce()
  {
   bool removed=false;
   string ownedNames[];
   int ownedCount=CollectOwnedChartObjectNames(ownedNames);
   for(int i=0; i<ownedCount; i++)
      if(ObjectDelete(0,ownedNames[i]))
         removed=true;
   if(DeleteOwnedByKnownPrefixes())
      removed=true;
   return removed;
  }

void DeleteBiasDirectionVisuals(const bool bull)
  {
   string dir=bull?"BU":"BE";
   ObjectsDeleteAll(0,PFX+"POI_"+dir,-1,-1);
   ObjectsDeleteAll(0,PFX+"AP_"+dir,-1,-1);
   ObjectsDeleteAll(0,PFX+"CO_"+dir,-1,-1);
   ObjectsDeleteAll(0,PFX+"TS_"+dir,-1,-1);
   ObjectsDeleteAll(0,PFX+"IFVG_"+dir,-1,-1);
   for(int i=g_nExecFamilies-1;i>=0;i--)
     {
     if(StringFind(g_execFamilies[i].genKey,dir+"_")==0)
        UnregisterExecFamilyTrack(g_execFamilies[i].genKey);
     }
  }

bool BuildGenerationSiblings(MqlRates &B[],int n,int pSec,bool genBull,int bb,
                             int &mapBull[],int &mapBear[],
                             SibInfo &sibs[],int &nSibs)
  {
   nSibs=0;
   ArrayResize(sibs,0);
   if(bb<0 || bb>=n) return false;

   int mapN=genBull?ArraySize(mapBull):ArraySize(mapBear);
   int upper=MathMin(n-1,mapN);
   if(upper<=0) return false;

   int sibCap=0;
   for(int i=0;i<upper;i++)
     {
      int bbCheck=genBull?mapBull[i]:mapBear[i];
      if(bbCheck==bb)
         sibCap++;
     }
   if(sibCap<1) return false;
   if(ArrayResize(sibs,sibCap)!=sibCap) return false;

   for(int i=0;i<upper;i++)
     {
      int bbCheck=genBull?mapBull[i]:mapBear[i];
      if(bbCheck!=bb) continue;
      if(nSibs>=sibCap) break;
      sibs[nSibs].wickIdx=i;
      sibs[nSibs].wickTime=B[i].time;
      sibs[nSibs].level=genBull?B[i].high:B[i].low;
      sibs[nSibs].ltfAnchor=FindLTFWickBar(i,B,pSec,genBull);
      sibs[nSibs].state=SS_INACTIVE;
      sibs[nSibs].c1Time=sibs[nSibs].c2Time=sibs[nSibs].c3Time=0;
      sibs[nSibs].tsLevel=0.0;
      sibs[nSibs].tsWickTime=0;
      sibs[nSibs].tsTouchTime=0;
      sibs[nSibs].tsTouchedBeforeC1=false;
      nSibs++;
     }

   if(nSibs<1)
     {
      ArrayResize(sibs,0);
      return false;
     }
   if(nSibs<sibCap)
      ArrayResize(sibs,nSibs);
   return true;
  }

void ResetSignalSnapshot()
  {
   g_sigTrigTime=0;
   g_sigBull=true;
   g_sigName="";
   g_sigState=SS_INACTIVE;
   g_sigC1=false;
   g_sigC2=false;
   g_sigC3=false;
   g_sigBirthTime=0;
   g_sigLevel=0.0;
   g_sigSlPx=0.0;
   g_sigTpPx=0.0;
   g_sigCoPx=0.0;
   g_sigModelLabel="";
   g_sigC1Time=0;
  }

void ClearTransientVisualState()
  {
   ArrayResize(g_hints,0); g_nHints=0;
   ArrayResize(g_cands,0); g_nCands=0;
   ArrayResize(g_tsGlows,0); g_nTsGlows=0;
  }

bool LoadNonVisualScannerBars(const bool fastMode,
                              MqlRates &B[],int &n,int &pSec,
                              int &bullBirths[],int &nBull,
                              int &bearBirths[],int &nBear,
                              int &mapBull[],int &mapBear[])
  {
   bool htfSynced=(bool)SeriesInfoInteger(_Symbol,HTF(),SERIES_SYNCHRONIZED);
   bool ltfSynced=(bool)SeriesInfoInteger(_Symbol,LTF(),SERIES_SYNCHRONIZED);
   if(!htfSynced || !ltfSynced)
     {
      SeriesInfoInteger(_Symbol,HTF(),SERIES_BARS_COUNT);
      SeriesInfoInteger(_Symbol,LTF(),SERIES_BARS_COUNT);
     }

   int barsToLoad=RecentFullProcessingBars();
   if(barsToLoad<2) barsToLoad=2;

   datetime currentHtfBar=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
   bool needReload=(!fastMode
                    || g_htfDrawCacheN<2
                    || g_htfDrawCacheLastBar!=currentHtfBar
                    || g_htfDrawCacheBars<barsToLoad);
   if(needReload)
     {
      int loaded=CopyRates(_Symbol,HTF(),0,barsToLoad,g_htfDrawCache);
      if(loaded<2)
         return false;
      g_htfDrawCacheN=loaded;
      g_htfDrawCacheLastBar=currentHtfBar;
      g_htfDrawCacheBars=barsToLoad;
     }

   n=g_htfDrawCacheN;
   ArrayResize(B,n);
   for(int bi=0; bi<n; bi++)
      B[bi]=g_htfDrawCache[bi];
   if(n<2)
      return false;

   datetime oldest=B[0].time;
   datetime ltfFirst=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_FIRSTDATE);
   if(ltfFirst==0)
     {
      MqlRates temp[];
      CopyRates(_Symbol,LTF(),oldest,1,temp);
      return false;
     }
   if(ltfFirst>oldest)
     {
      int firstUsable=0;
      while(firstUsable<n && B[firstUsable].time<ltfFirst)
         firstUsable++;
      int trimmedCount=n-firstUsable;
      if(trimmedCount<2)
        {
         MqlRates temp[];
         CopyRates(_Symbol,LTF(),oldest,1,temp);
         return false;
        }
      MqlRates trimmed[];
      ArrayResize(trimmed,trimmedCount);
      for(int bi=0; bi<trimmedCount; bi++)
         trimmed[bi]=B[firstUsable+bi];
      ArrayResize(B,trimmedCount);
      for(int bi=0; bi<trimmedCount; bi++)
         B[bi]=trimmed[bi];
      n=trimmedCount;
      oldest=B[0].time;
     }

   pSec=(int)PeriodSeconds(HTF());
   if(pSec<=0)
      return false;

   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   datetime ltfSupportFrom=PriorDaySupportStart();
   datetime ltfCacheFrom=(ltfSupportFrom>oldest)?ltfSupportFrom:oldest;
   PrepareLTFWindowCache(ltfCacheFrom,(datetime)(scanEnd+PeriodSeconds(LTF())));

   BuildBirthLists(B,n,bullBirths,bearBirths,nBull,nBear,mapBull,mapBear);
   return (n>=2);
  }

void ProcessNonVisualTesterState(const bool fastMode=false)
  {
   MqlRates B[];
   int n=0;
   int pSec=0;
   int bullBirths[],bearBirths[],mapBull[],mapBear[];
   int nBull=0,nBear=0;
   if(!LoadNonVisualScannerBars(fastMode,B,n,pSec,bullBirths,nBull,bearBirths,nBear,mapBull,mapBear))
      return;

   ClearTransientVisualState();
   ResetSignalSnapshot();

   datetime marketNow=MarketReferenceTime();
   datetime todayOpen=TodayOpenAt(marketNow);
   datetime structuralFrom=RecentFullProcessingStart();
   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);

   datetime trigTimeBull[]; ArrayResize(trigTimeBull,n); ArrayInitialize(trigTimeBull,0);
   datetime trigTimeBear[]; ArrayResize(trigTimeBear,n); ArrayInitialize(trigTimeBear,0);
   datetime ownerC1Bull[]; ArrayResize(ownerC1Bull,n); ArrayInitialize(ownerC1Bull,0);
   datetime ownerC1Bear[]; ArrayResize(ownerC1Bear,n); ArrayInitialize(ownerC1Bear,0);
   bool scannedBull[]; ArrayResize(scannedBull,n); ArrayInitialize(scannedBull,false);
   bool scannedBear[]; ArrayResize(scannedBear,n); ArrayInitialize(scannedBear,false);

   for(int x=0;x<nBull+nBear;x++)
     {
      bool genBull=(x<nBull);
      int  bb=genBull?bullBirths[x]:bearBirths[x-nBull];
      if(bb<0 || bb>=n || bb+1>=n)
         continue;
      if(genBull)
        {
         if(scannedBull[bb]) continue;
         scannedBull[bb]=true;
        }
      else
        {
         if(scannedBear[bb]) continue;
         scannedBear[bb]=true;
        }

      TradeWindowResult birthWindow;
      if(B[bb].time<todayOpen || !ResolveBirthTradeWindowCurrentModel(B[bb].time,birthWindow))
         continue;

      SibInfo sibs[]; int nSibs=0;
      if(!BuildGenerationSiblings(B,n,pSec,genBull,bb,mapBull,mapBear,sibs,nSibs))
         continue;
      SortSiblings(sibs,nSibs,genBull);

      int nextSame=genBull?NextGenBirth(bullBirths,nBull,bb):NextGenBirth(bearBirths,nBear,bb);
      int nextCounter=genBull?NextGenBirth(bearBirths,nBear,bb):NextGenBirth(bullBirths,nBull,bb);
      datetime nextSameTime=(nextSame>=0&&nextSame<n)?B[nextSame].time:0;
      datetime nextCtrTime=(nextCounter>=0&&nextCounter<n)?B[nextCounter].time:0;
      datetime ctrBiasFrom=(nextCtrTime>0)?nextCtrTime:0;
      datetime pillarOpen=B[bb+1].time;

      bool coLocked=false;
      datetime coTime=0,coEndTime=0;
      double coPx=FindCorrectionOrigin(B,n,pSec,sibs[0].level,genBull,
                                       bb,nextSame,nextCounter,
                                       coLocked,coTime,coEndTime);
      if(coLocked && coEndTime<coTime)
         coEndTime=coTime;

      datetime minActivateTime=0;
      datetime maxActivateTime=0;
      if(!ResolveGenerationActivationWindow(B,n,pSec,bb,pillarOpen,minActivateTime,maxActivateTime))
         continue;

      FVGInfo fvgs[]; int nFvgs=0; int c3Idx=-1;
      datetime trig=0; bool coVis=false;
      ScanGeneration(coTime,coPx,genBull,sibs,nSibs,scanEnd,pillarOpen,
                     ctrBiasFrom,0,0,pSec,minActivateTime,maxActivateTime,nextSameTime,
                     fvgs,nFvgs,c3Idx,trig,coVis);
      if(c3Idx<0 && coVis)
         coVis=false;

      datetime ownerC1=0;
      for(int os=0; os<nSibs; os++)
        {
         if(sibs[os].c1Time<=0) continue;
         SIB_STATE ownSt=sibs[os].state;
         bool owns=(ownSt==SS_ACTIVE || ownSt==SS_TRIGGERED
                    || ownSt==SS_TP_HIT || ownSt==SS_SL_HIT || ownSt==SS_BE_HIT);
         if(!owns) continue;
         ownerC1=sibs[os].c1Time;
         break;
        }

      if(genBull)
        {
         trigTimeBull[bb]=trig;
         ownerC1Bull[bb]=ownerC1;
        }
      else
        {
         trigTimeBear[bb]=trig;
         ownerC1Bear[bb]=ownerC1;
        }
     }

   bool primedBull[]; ArrayResize(primedBull,n); ArrayInitialize(primedBull,false);
   bool primedBear[]; ArrayResize(primedBear,n); ArrayInitialize(primedBear,false);

   for(int x=0;x<nBull+nBear;x++)
     {
      bool genBull=(x<nBull);
      int  bb=genBull?bullBirths[x]:bearBirths[x-nBull];
      if(bb<0 || bb>=n || bb+1>=n)
         continue;
      if(genBull)
        {
         if(primedBull[bb]) continue;
         primedBull[bb]=true;
        }
      else
        {
         if(primedBear[bb]) continue;
         primedBear[bb]=true;
        }
      if(B[bb].time<structuralFrom)
         continue;

      SibInfo sibs[]; int nSibs=0;
      if(!BuildGenerationSiblings(B,n,pSec,genBull,bb,mapBull,mapBear,sibs,nSibs))
         continue;
      SortSiblings(sibs,nSibs,genBull);

      datetime supersedeAfterTime=0;
      datetime lockAfterTime=0;
      int nextSame=genBull?NextGenBirth(bullBirths,nBull,bb):NextGenBirth(bearBirths,nBear,bb);
      int nextCounter=genBull?NextGenBirth(bearBirths,nBear,bb):NextGenBirth(bullBirths,nBull,bb);
      datetime nextSameTime=(nextSame>=0&&nextSame<n)?B[nextSame].time:0;
      datetime nextCtrTime=(nextCounter>=0&&nextCounter<n)?B[nextCounter].time:0;
      datetime ctrBiasFrom=(nextCtrTime>0)?nextCtrTime:0;
      if(nextSame>=0 && nextSame<n)
        {
         datetime newerTrig=genBull?trigTimeBull[nextSame]:trigTimeBear[nextSame];
         if(newerTrig>0)
            lockAfterTime=newerTrig;
        }
      int sameCount=genBull?nBull:nBear;
      for(int ox=0; ox<sameCount; ox++)
        {
         int bbOlder=genBull?bullBirths[ox]:bearBirths[ox];
         if(bbOlder<0 || bbOlder>=n || bbOlder>=bb) continue;
         datetime olderOwnerC1=genBull?ownerC1Bull[bbOlder]:ownerC1Bear[bbOlder];
         if(olderOwnerC1<=B[bb].time) continue;
         if(supersedeAfterTime==0 || olderOwnerC1<supersedeAfterTime)
            supersedeAfterTime=olderOwnerC1;
        }

      bool coLocked=false;
      datetime coTime=0,coEndTime=0;
      double coPx=FindCorrectionOrigin(B,n,pSec,sibs[0].level,genBull,
                                       bb,nextSame,nextCounter,
                                       coLocked,coTime,coEndTime);
      if(coLocked && coEndTime<coTime)
         coEndTime=coTime;

      TradeWindowResult birthWindow;
      if(B[bb].time<todayOpen || !ResolveBirthTradeWindowCurrentModel(B[bb].time,birthWindow))
         continue;
      string activeExecModelLabel=TradeWindowShortLabelForOffset(birthWindow.maxHTF+1);
      datetime activeExecRef=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
      TradeWindowResult activeExecWindow;
      datetime activeExecOpen=0,activeExecEnd=0;
      string activeExecHuman="";
      int activeExecKey=-1;
      if(activeExecRef>0
         && ResolveExecutionWindowForTrigger(activeExecRef,
                                             activeExecWindow,
                                             activeExecOpen,
                                             activeExecEnd,
                                             activeExecHuman,
                                             activeExecKey,
                                             B[bb].time))
         activeExecModelLabel=TradeWindowShortLabelForOffset(activeExecWindow.maxHTF+1);
      if(activeExecEnd<activeExecOpen)
         activeExecEnd=activeExecOpen;
      if(activeExecHuman=="")
         activeExecHuman=activeExecModelLabel;
      if(activeExecKey<0)
         activeExecKey=0;

      datetime firstExecOpen=0,firstExecEnd=0;
      string firstExecLabel="";
      if(!ResolveFirstExecutionWindowForBirth(B[bb].time,firstExecOpen,firstExecEnd,firstExecLabel))
         continue;
      if(firstExecOpen<=0)
         firstExecOpen=(datetime)(B[bb].time+pSec);
      if(firstExecLabel=="")
         firstExecLabel=activeExecModelLabel;
      bool generationAlreadyLive=(HasOpenCCTPositionForGenKey((genBull?"BU_":"BE_")+IntegerToString((int)B[bb].time))
                                  || HasCachedBrokerTradePresence((genBull?"BU_":"BE_")+IntegerToString((int)B[bb].time)));
      if(!generationAlreadyLive && firstExecEnd>0 && marketNow>firstExecEnd)
         continue;

      datetime pillarOpen=B[bb+1].time;
      datetime minActivateTime=0;
      datetime maxActivateTime=0;
      if(!ResolveGenerationActivationWindow(B,n,pSec,bb,pillarOpen,minActivateTime,maxActivateTime))
         continue;

      FVGInfo fvgs[]; int nFvgs=0; int c3FvgIdx=-1;
      datetime triggerTime=0; bool coVisible=false;
      ScanGeneration(coTime,coPx,genBull,sibs,nSibs,scanEnd,pillarOpen,
                     ctrBiasFrom,supersedeAfterTime,lockAfterTime,pSec,
                     minActivateTime,maxActivateTime,nextSameTime,
                     fvgs,nFvgs,c3FvgIdx,triggerTime,coVisible);

      bool counterBias=(ctrBiasFrom>0);
      if(triggerTime==0 && !counterBias)
        {
         for(int sx=0;sx<nSibs;sx++)
           {
            if(sibs[sx].state!=SS_ACTIVE || sibs[sx].c1Time<=0) continue;
            if(sibs[sx].c1Time<=g_sigTrigTime) continue;
            g_sigTrigTime=sibs[sx].c1Time;
            g_sigBull=genBull;
            g_sigName=CodenameFromTime(B[bb].time);
            g_sigState=SS_ACTIVE;
            g_sigC1=(sibs[sx].c1Time>0);
            g_sigC2=(sibs[sx].c2Time>0);
            g_sigC3=(sibs[sx].c3Time>0);
            g_sigBirthTime=B[bb].time;
            g_sigLevel=sibs[sx].level;
            g_sigCoPx=coPx;
            g_sigSlPx=0.0;
            g_sigTpPx=0.0;
            g_sigModelLabel=ActualExecutionModelLabelForSibling(sibs[sx],activeExecModelLabel,activeExecRef);
            if(g_sigC2 && g_sigC3 && c3FvgIdx>=0 && c3FvgIdx<nFvgs)
              {
               double liveBid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
               double liveAsk=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
               double signalEntry=genBull?liveAsk:liveBid;
               if(signalEntry<=0.0)
                  signalEntry=sibs[sx].level;
               FVGInfo cfSig=fvgs[c3FvgIdx];
               double aASig=(Inp_FibMode==FIB_MODE_STANDARD)?cfSig.c1Ext:signalEntry;
               double aBSig=cfSig.c2c3Extreme;
               double sigSweepProbe=ScanExtremeBetween(cfSig.t3,scanEnd,genBull);
               if(sigSweepProbe<=0.0)
                  sigSweepProbe=signalEntry;
               ENUM_SL_BRANCH sigBranch=DetectSLBranch(cfSig,genBull,sigSweepProbe);
               g_sigSlPx=CalcFibSL(aASig,aBSig,genBull,sigBranch);
               g_sigTpPx=CalcTPRaw(genBull,signalEntry,g_sigSlPx,coPx);
              }
            break;
           }
        }

      if(triggerTime<=0 || c3FvgIdx<0 || c3FvgIdx>=nFvgs)
         continue;

      MqlRates trigBar[];
      if(CopyRates(_Symbol,LTF(),triggerTime,1,trigBar)<=0)
         continue;
      double trigClose=trigBar[0].close;
      if(trigClose<=0.0)
         continue;

      int trigSibIdx=0;
      for(int tx=0; tx<nSibs; tx++)
        {
         if(sibs[tx].state==SS_TRIGGERED
            || sibs[tx].state==SS_TP_HIT
            || sibs[tx].state==SS_SL_HIT
            || sibs[tx].state==SS_BE_HIT
            || sibs[tx].c3Time>0)
           {
            trigSibIdx=tx;
            break;
           }
        }

      double sweepProbe=ScanExtremeBetween(fvgs[c3FvgIdx].t3,triggerTime,genBull);
      if(sweepProbe<=0.0)
         sweepProbe=trigClose;
      FVGInfo cfvg=fvgs[c3FvgIdx];
      double aA=(Inp_FibMode==FIB_MODE_STANDARD)?cfvg.c1Ext:trigClose;
      double aB=cfvg.c2c3Extreme;
      ENUM_SL_BRANCH branchLocked=DetectSLBranch(cfvg,genBull,sweepProbe);
      double slRawLocked=CalcFibSL(aA,aB,genBull,branchLocked);
      double tpLocked=CalcTPRaw(genBull,trigClose,slRawLocked,coPx);
      double riskLocked=MathAbs(trigClose-slRawLocked);
      double rrLocked=(riskLocked>_Point)?(MathAbs(tpLocked-trigClose)/riskLocked):0.0;
      datetime expiryTime=PendingExecHardExpiry(triggerTime);

      string execModelLabel=activeExecModelLabel;
      TradeWindowResult triggerExecWindow;
      datetime triggerExecOpen=0,triggerExecEnd=0;
      string triggerExecHuman="";
      int triggerExecKey=-1;
      if(ResolveExecutionWindowForTrigger(triggerTime,
                                          triggerExecWindow,
                                          triggerExecOpen,
                                          triggerExecEnd,
                                          triggerExecHuman,
                                          triggerExecKey,
                                          B[bb].time))
         execModelLabel=TradeWindowShortLabelForOffset(triggerExecWindow.maxHTF+1);
      if(triggerExecEnd<triggerExecOpen)
         triggerExecEnd=triggerExecOpen;
      if(triggerExecHuman=="")
         triggerExecHuman=execModelLabel;
      if(triggerExecKey<0)
         triggerExecKey=0;
      execModelLabel=ResolveTriggerModelLabelForSibling(sibs[trigSibIdx],B[bb].time,triggerTime,execModelLabel);

      string execGenKey=(genBull?"BU_":"BE_")+IntegerToString((int)B[bb].time);
      RegisterReplayTriggeredPOI(triggerTime,trigClose,slRawLocked,tpLocked,execGenKey,coPx);
      datetime trigC1Time = (trigSibIdx>=0 && trigSibIdx<nSibs) ? sibs[trigSibIdx].c1Time : 0;
      RegisterPendingExec(genBull,trigClose,slRawLocked,tpLocked,rrLocked,coPx,
                          triggerTime,B[bb].time,expiryTime,execModelLabel,trigC1Time);

      if(triggerTime>g_sigTrigTime)
        {
         g_sigTrigTime=triggerTime;
         g_sigBull=genBull;
         g_sigName=CodenameFromTime(B[bb].time);
         g_sigState=SS_TRIGGERED;
         g_sigC1=(sibs[trigSibIdx].c1Time>0);
         g_sigC2=(sibs[trigSibIdx].c2Time>0);
         g_sigC3=(sibs[trigSibIdx].c3Time>0);
         g_sigBirthTime=B[bb].time;
         g_sigLevel=sibs[trigSibIdx].level;
         g_sigSlPx=slRawLocked;
         g_sigTpPx=tpLocked;
         g_sigCoPx=coPx;
         g_sigModelLabel=execModelLabel;
         g_sigC1Time=(sibs[trigSibIdx].c1Time>0)?sibs[trigSibIdx].c1Time:0;
        }
     }
  }

//+------------------------------------------------------------------+
// Draw — full redraw on new LTF bar.
//
// Two-pass approach for one-execution-per-window:
//   Pass 1 (scan only): collect trigger times for every generation.
//   Pass 2 (draw):      for each generation, compute lockAfterTime
//                       from any newer same-bias triggered generation,
//                       then call DrawGeneration with that gate.
//+------------------------------------------------------------------+
void Draw(bool fastMode=false)
   {
    bool renderVisuals=!IsNonVisualTesterRun();
    datetime drawTodayOpen=TodayOpen();
    if(renderVisuals)
       PruneStaleActionPillars(drawTodayOpen);

    // Pre-warm both series, but do not hard-block the draw solely on the
    // synchronized flags. On attach/reload MT5 can report unsynchronized for
    // several seconds even when CopyRates can already provide enough data to
    // render scanner state and dashboard signal details.
    bool htfSynced=(bool)SeriesInfoInteger(_Symbol,HTF(),SERIES_SYNCHRONIZED);
    bool ltfSynced=(bool)SeriesInfoInteger(_Symbol,LTF(),SERIES_SYNCHRONIZED);
    if(!htfSynced || !ltfSynced)
      {
       SeriesInfoInteger(_Symbol,HTF(),SERIES_BARS_COUNT);
       SeriesInfoInteger(_Symbol,LTF(),SERIES_BARS_COUNT);
       if(g_objPrevN==0)
          g_needsRedraw = true;
      }

    int recentBarsToLoad = RecentFullProcessingBars();
    int wideBarsToLoad = MathMax(recentBarsToLoad,VirginVisualBars());
    if(wideBarsToLoad<2) wideBarsToLoad=2;

    datetime currentHtfBar=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
    bool needWideReload=(!fastMode
                         || g_htfDrawCacheN<2
                         || g_htfDrawCacheLastBar!=currentHtfBar
                         || g_htfDrawCacheBars<wideBarsToLoad);
    if(needWideReload)
      {
       int loaded=CopyRates(_Symbol,HTF(),0,wideBarsToLoad,g_htfDrawCache);
       if(loaded<2) { g_needsRedraw = true; return; }
       g_htfDrawCacheN=loaded;
       g_htfDrawCacheLastBar=currentHtfBar;
       g_htfDrawCacheBars=wideBarsToLoad;
      }

    MqlRates B[]; int n=g_htfDrawCacheN;
    ArrayResize(B,n);
    for(int bi=0; bi<n; bi++)
       B[bi]=g_htfDrawCache[bi];
    if(n<2) { g_needsRedraw = true; return; }
    
    datetime oldest = B[0].time;
    datetime ltf_first = (datetime)SeriesInfoInteger(_Symbol, LTF(), SERIES_FIRSTDATE);
    if (ltf_first == 0)
      {
       // Trigger background data download for LTF
       MqlRates temp[];
       CopyRates(_Symbol, LTF(), oldest, 1, temp);
       g_needsRedraw = true;
       return;
      }
    if (ltf_first > oldest)
      {
       // Do not starve the scanner just because the broker/local cache does not
       // yet have LTF data for the oldest requested HTF bars. Trim the HTF
       // working set to the LTF-ready range and draw what is actually available.
       int firstUsable = 0;
       while(firstUsable < n && B[firstUsable].time < ltf_first)
          firstUsable++;
       int trimmedCount = n - firstUsable;
       if(trimmedCount < 2)
         {
          MqlRates temp[];
          CopyRates(_Symbol, LTF(), oldest, 1, temp);
          g_needsRedraw = true;
          return;
         }
       MqlRates trimmed[];
       ArrayResize(trimmed, trimmedCount);
       for(int bi=0; bi<trimmedCount; bi++)
          trimmed[bi] = B[firstUsable + bi];
       ArrayResize(B, trimmedCount);
       for(int bi=0; bi<trimmedCount; bi++)
          B[bi] = trimmed[bi];
       n = trimmedCount;
       oldest = B[0].time;
      }

    // If the terminal still reports unsynchronized after we have enough usable
    // HTF/LTF history, keep the redraw request alive for later refinement but
    // do not defer the initial render and state propagation any longer.
    if(!htfSynced || !ltfSynced)
       g_needsRedraw = (g_objPrevN==0);

    // Reset pending exec queue — DrawGeneration repopulates each pass

   datetime structuralFrom=RecentFullProcessingStart();
   datetime actionVisualFrom=RecentVisualStart();
   int  pSec=(int)PeriodSeconds(HTF());
   int  bias=(n>=2)?GetBias(B,n):0;
   if(g_currentBias!=0 && bias!=0 && bias!=g_currentBias)
      DeleteBiasDirectionVisuals(g_currentBias>0);
   if(bias!=0)
      g_currentBias=bias;
   datetime htfOpen=B[n-1].time;

   int bullBirths[],bearBirths[],nBull=0,nBear=0,mapBull[],mapBear[];
   BuildBirthLists(B,n,bullBirths,bearBirths,nBull,nBear,mapBull,mapBear);
   int todayBullBirthCount=0,todayBearBirthCount=0;
   datetime todayStart=TodayOpen();
   datetime nextDayStart=(datetime)(todayStart+86400);
   TradeWindowResult dayOpenBirthWindow;
   bool dayOpenBirthValid=ResolveBirthTradeWindowCurrentModel(todayStart,dayOpenBirthWindow);
   for(int bi=0; bi<nBull; bi++)
     {
      int bb=bullBirths[bi];
      if(bb<0 || bb>=n) continue;
      datetime bt=B[bb].time;
      if(bt<todayStart || bt>=nextDayStart) continue;
      TradeWindowResult tw;
      if(ResolveBirthTradeWindowCurrentModel(bt,tw))
         todayBullBirthCount++;
     }
   for(int bi=0; bi<nBear; bi++)
     {
      int bb=bearBirths[bi];
      if(bb<0 || bb>=n) continue;
      datetime bt=B[bb].time;
      if(bt<todayStart || bt>=nextDayStart) continue;
      TradeWindowResult tw;
      if(ResolveBirthTradeWindowCurrentModel(bt,tw))
         todayBearBirthCount++;
     }
   bool edgeGenerationDemand=false;

   // ----------------------------------------------------------------
   // Pass 1 — collect trigger times (scan without drawing)
   // ----------------------------------------------------------------
   datetime trigTimeBull[]; ArrayResize(trigTimeBull,n); ArrayInitialize(trigTimeBull,0);
   datetime trigTimeBear[]; ArrayResize(trigTimeBear,n); ArrayInitialize(trigTimeBear,0);
   datetime ownerC1Bull[]; ArrayResize(ownerC1Bull,n); ArrayInitialize(ownerC1Bull,0);
   datetime ownerC1Bear[]; ArrayResize(ownerC1Bear,n); ArrayInitialize(ownerC1Bear,0);

    bool drawnBull1[],drawnBear1[];
    bool isDormantBull[],isDormantBear[];
    ArrayResize(drawnBull1,n); ArrayInitialize(drawnBull1,false);
    ArrayResize(drawnBear1,n); ArrayInitialize(drawnBear1,false);
    ArrayResize(isDormantBull,n); ArrayInitialize(isDormantBull,false);
    ArrayResize(isDormantBear,n); ArrayInitialize(isDormantBear,false);

    datetime scanEndP1=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
    datetime ltfSupportFrom=PriorDaySupportStart();
    datetime ltfCacheFrom=(ltfSupportFrom>oldest)?ltfSupportFrom:oldest;
    PrepareLTFWindowCache(ltfCacheFrom,(datetime)(scanEndP1+PeriodSeconds(LTF())));

   for(int x=0;x<nBull+nBear;x++)
     {
       bool genBull=(x<nBull);
       int  bb=genBull?bullBirths[x]:bearBirths[x-nBull];
       if(bb<0 || bb>=n) continue;
       if(genBull){if(drawnBull1[bb])continue;drawnBull1[bb]=true;}
       else        {if(drawnBear1[bb])continue;drawnBear1[bb]=true;}

       if(bb+1>=n) continue;

       SibInfo sibs[]; int nSibs=0;
       if(!BuildGenerationSiblings(B,n,pSec,genBull,bb,mapBull,mapBear,sibs,nSibs))
          continue;
       SortSiblings(sibs,nSibs,genBull);

       datetime pillarOpen=B[bb+1].time;
       int nextSame   =genBull?NextGenBirth(bullBirths,nBull,bb):NextGenBirth(bearBirths,nBear,bb);
       int nextCounter=genBull?NextGenBirth(bearBirths,nBear,bb):NextGenBirth(bullBirths,nBull,bb);
       datetime nextCtrTime=(nextCounter>=0&&nextCounter<n)?B[nextCounter].time:0;
      bool ctrBias=(nextCtrTime>0);
      datetime ctrBiasFrom=ctrBias?nextCtrTime:0;

       TradeWindowResult p1BirthWindow;
       if(B[bb].time<TodayOpenAt(MarketReferenceTime()) || !ResolveBirthTradeWindowCurrentModel(B[bb].time,p1BirthWindow))
          continue;

       bool coLocked=false; datetime coTime=0,coEndTime=0;
       double coPx=FindCorrectionOrigin(B,n,pSec,sibs[0].level,genBull,
                                        bb,nextSame,nextCounter,
                                        coLocked,coTime,coEndTime);

       datetime nextSameTime=(nextSame>=0&&nextSame<n)?B[nextSame].time:0;
       if(genBull) isDormantBull[bb] = (nextSameTime > 0);
       else        isDormantBear[bb] = (nextSameTime > 0);

       datetime minActivateTime=0;
       datetime maxActivateTime=0;
       if(!ResolveGenerationActivationWindow(B,n,pSec,bb,pillarOpen,minActivateTime,maxActivateTime))
          continue;

       FVGInfo fvgs[]; int nFvgs=0; int c3Idx=-1;
       datetime trig=0; bool coVis=false;
       ScanGeneration(coTime,coPx,genBull,sibs,nSibs,scanEndP1,pillarOpen,
                      ctrBiasFrom,0,0,pSec,minActivateTime,maxActivateTime,nextSameTime,
                      fvgs,nFvgs,c3Idx,trig,coVis);

       datetime ownerC1=0;
       for(int os=0; os<nSibs; os++)
         {
          SIB_STATE ownSt=sibs[os].state;
          if(sibs[os].c1Time<=0) continue;
          bool owns=(ownSt==SS_ACTIVE || ownSt==SS_TRIGGERED
                     || ownSt==SS_TP_HIT || ownSt==SS_SL_HIT || ownSt==SS_BE_HIT);
          if(!owns) continue;
          ownerC1=sibs[os].c1Time;
          break;
         }

       if(genBull) trigTimeBull[bb]=trig;
       else        trigTimeBear[bb]=trig;
       if(genBull) ownerC1Bull[bb]=ownerC1;
       else        ownerC1Bear[bb]=ownerC1;
     }

   // ----------------------------------------------------------------
   // Pre-dispatch pass — if broker execution is enabled, queue/send
   // broker orders before any visible chart objects are rebuilt.
   // ----------------------------------------------------------------
   if(Inp_BrokerExecution==BROKER_EXEC_ON)
     {
      bool primedBull[],primedBear[];
      ArrayResize(primedBull,n); ArrayInitialize(primedBull,false);
      ArrayResize(primedBear,n); ArrayInitialize(primedBear,false);

      for(int x=0;x<nBull+nBear;x++)
        {
         bool genBull=(x<nBull);
         int  bb=genBull?bullBirths[x]:bearBirths[x-nBull];
         if(bb<0 || bb>=n) continue;
         if(genBull){if(primedBull[bb])continue;primedBull[bb]=true;}
         else       {if(primedBear[bb])continue;primedBear[bb]=true;}
         if(B[bb].time<structuralFrom) continue;
         if(bb+1>=n) continue;

         SibInfo sibs[]; int nSibs=0;
         if(!BuildGenerationSiblings(B,n,pSec,genBull,bb,mapBull,mapBear,sibs,nSibs))
            continue;
         SortSiblings(sibs,nSibs,genBull);

         datetime supersedeAfterTime=0;
         datetime lockAfterTime=0;
         int nextSame=genBull?NextGenBirth(bullBirths,nBull,bb):NextGenBirth(bearBirths,nBear,bb);
         if(nextSame>=0 && nextSame<n)
           {
            datetime tNewer=genBull?trigTimeBull[nextSame]:trigTimeBear[nextSame];
            if(tNewer>0) lockAfterTime=tNewer;
           }
         int nSB=genBull?nBull:nBear;
         for(int ox=0; ox<nSB; ox++)
           {
            int bbOlder=genBull?bullBirths[ox]:bearBirths[ox];
            if(bbOlder<0 || bbOlder>=n || bbOlder>=bb) continue;
            datetime olderOwnerC1=genBull?ownerC1Bull[bbOlder]:ownerC1Bear[bbOlder];
            if(olderOwnerC1<=B[bb].time) continue;
            if(supersedeAfterTime==0 || olderOwnerC1<supersedeAfterTime)
               supersedeAfterTime=olderOwnerC1;
           }

         PrimeBrokerExecutionForGeneration(B,n,pSec,genBull,bb,sibs,nSibs,supersedeAfterTime,lockAfterTime,
                                           bullBirths,nBull,bearBirths,nBear);
        }
     }

   // ----------------------------------------------------------------
   // Pass 2 — draw all generations with lockAfterTime gate
   // ----------------------------------------------------------------
   g_objCurrN=0; ArrayResize(g_objCurr,0);
   ObjCacheSeedCarryForward();
   g_nHints=0; ArrayResize(g_hints,0);
   g_nCands=0; ArrayResize(g_cands,0);
   g_nTsGlows=0; ArrayResize(g_tsGlows,0);
   // Reset signal export — DrawGeneration will re-populate with freshest active/triggered POI
   g_sigTrigTime=0; g_sigBull=true; g_sigName=""; g_sigState=SS_INACTIVE;
   g_sigC1=false; g_sigC2=false; g_sigC3=false; g_sigBirthTime=0; g_sigLevel=0;
   g_sigSlPx=0; g_sigTpPx=0; g_sigCoPx=0; g_sigModelLabel="";

   MqlRates visB[]; int visN=n;
   ArrayResize(visB,n);
   for(int vi=0;vi<n;vi++)
      visB[vi]=B[vi];

   // Day separators
   if(renderVisuals)
   {
    if(Inp_Model==MODEL_D1_15M)
      {
       datetime prevWeek=0;
       for(int i=0;i<visN;i++)
         {
         if(visB[i].time<actionVisualFrom) continue;
          datetime weekStart=NYWeekOpen(visB[i].time);
          if(weekStart==prevWeek) continue; prevWeek=weekStart;
          if(weekStart<actionVisualFrom) continue;
          datetime nextWeekStart=(datetime)(weekStart+7*86400);
          DrawVLine(PFX+"WEEK_"+IntegerToString((int)nextWeekStart),
                    nextWeekStart,Inp_ClrWeekSeparator,CCTLineStyle(Inp_StyWeekSeparator),CCTLineWidth(Inp_WidWeekSeparator),true,
                    WeekSeparatorTooltip(weekStart,nextWeekStart),
                    FullContentTFs()|DaySepOnlyTFs());
         }

       datetime curWeekStart=NYWeekOpen(TimeCurrent());
       datetime nextWeekStart=(datetime)(curWeekStart+7*86400);
       if(curWeekStart>=actionVisualFrom)
         {
         DrawVLine(PFX+"WEEK_"+IntegerToString((int)nextWeekStart),
                    nextWeekStart,Inp_ClrWeekSeparator,CCTLineStyle(Inp_StyWeekSeparator),CCTLineWidth(Inp_WidWeekSeparator),true,
                    WeekSeparatorTooltip(curWeekStart,nextWeekStart),
                    FullContentTFs()|DaySepOnlyTFs());
         }
      }
    else
      {
       datetime prevDay=0;
       for(int i=0;i<visN;i++)
         {
          if(visB[i].time<actionVisualFrom) continue;
          int nyOff=NYOffsetSec(visB[i].time);
          datetime nyMid=visB[i].time+nyOff;
          MqlDateTime dt; TimeToStruct(nyMid,dt);
          dt.hour=0;dt.min=0;dt.sec=0;
          datetime nyDayStartLocal=StructToTime(dt);
          datetime nyDayStartServer=nyDayStartLocal-nyOff;
          if(nyDayStartServer==prevDay) continue; prevDay=nyDayStartServer;
          datetime trackedDayStart=(datetime)(nyDayStartServer-86400);
          if(trackedDayStart<actionVisualFrom) continue;
          string dayTip=(nyDayStartServer>MarketReferenceTime())
                        ? NYStr(nyDayStartServer)
                        : DaySeparatorTooltip(trackedDayStart,nyDayStartServer);
          DrawVLine(PFX+"DAY_"+IntegerToString((int)nyDayStartServer),
                    nyDayStartServer,Inp_ClrDaySeparator,CCTLineStyle(Inp_StyDaySeparator),CCTLineWidth(Inp_WidDaySeparator),true,
                    dayTip,
                    FullContentTFs()|DaySepOnlyTFs());
         }

       string todayOpenTip="Today Open\n"+NYStr(todayStart);
       todayOpenTip+="\nBirth slot: "+(dayOpenBirthValid?TradeModelShortLabelForBirth(todayStart):"none");
       todayOpenTip+="\nPOIs born: "+IntegerToString(todayBullBirthCount+todayBearBirthCount);
       todayOpenTip+="\nBull/Bear: "+IntegerToString(todayBullBirthCount)+"/"+IntegerToString(todayBearBirthCount);
       DrawVLine(PFX+"DAY_OPEN_"+IntegerToString((int)todayStart),
                 todayStart,Inp_ClrDaySeparator,CCTLineStyle(Inp_StyDaySeparator),CCTLineWidth(Inp_WidDaySeparator),true,
                 todayOpenTip,
                 FullContentTFs()|DaySepOnlyTFs());
       if(todayStart>=actionVisualFrom)
         {
          string nextDayTip=(nextDayStart>MarketReferenceTime())
                            ? NYStr(nextDayStart)
                            : DaySeparatorTooltip(todayStart,nextDayStart);
          DrawVLine(PFX+"DAY_"+IntegerToString((int)nextDayStart),
                    nextDayStart,Inp_ClrDaySeparator,CCTLineStyle(Inp_StyDaySeparator),CCTLineWidth(Inp_WidDaySeparator),true,
                    nextDayTip,
                    FullContentTFs()|DaySepOnlyTFs());
         }
      }
   }

   bool drawnBull2[],drawnBear2[];
   ArrayResize(drawnBull2,n); ArrayInitialize(drawnBull2,false);
   ArrayResize(drawnBear2,n); ArrayInitialize(drawnBear2,false);

   for(int x=0;x<nBull+nBear;x++)
     {
      bool genBull=(x<nBull);
      int  bb=genBull?bullBirths[x]:bearBirths[x-nBull];
      if(bb<0 || bb>=n) continue;
      if(genBull){if(drawnBull2[bb])continue;drawnBull2[bb]=true;}
      else         {if(drawnBear2[bb])continue;drawnBear2[bb]=true;}
      if(B[bb].time<structuralFrom) continue;

      if(Inp_ShowDebug)
         PrintFormat("[CCT DBG] Pass2 gen bb=%d %s born=%s sibs=%d",
                     bb, genBull?"BULL":"BEAR", NYStr(B[bb].time), 0);

      SibInfo sibs[]; int nSibs=0;
      if(!BuildGenerationSiblings(B,n,pSec,genBull,bb,mapBull,mapBear,sibs,nSibs))
         continue;
      SortSiblings(sibs,nSibs,genBull);

      int nextSame=(genBull?NextGenBirth(bullBirths,nBull,bb):NextGenBirth(bearBirths,nBear,bb));
      datetime nextSameTime=(nextSame>=0&&nextSame<n)?B[nextSame].time:0;
      datetime pillarOpen=(bb+1<n)?B[bb+1].time:B[bb].time+pSec;
      datetime supersedeAfterTime=0;
      datetime lockAfterTime=0;
      {
       int nSB=genBull?nBull:nBear;
       for(int sx=0;sx<nSB;sx++)
         {
          int bb2=genBull?bullBirths[sx]:bearBirths[sx];
          if(bb2<=bb) continue; // only newer same-bias generations may consume this window on redraw
          datetime trig2=genBull?trigTimeBull[bb2]:trigTimeBear[bb2];
          if(trig2==0) continue;
          if(trig2<pillarOpen) continue;
          int nextAfterTrig=genBull?NextGenBirth(bullBirths,nBull,bb2):NextGenBirth(bearBirths,nBear,bb2);
          datetime reopenTime=0;
          if(nextAfterTrig>=0&&nextAfterTrig<n)
            {
             if(nextAfterTrig+1<n) reopenTime=B[nextAfterTrig+1].time;
             else                  reopenTime=(datetime)(B[nextAfterTrig].time+pSec);
            }
          if(reopenTime>0 && reopenTime<=scanEndP1) continue;
          if(Inp_ShowDebug)
             PrintFormat("[CCT DBG] WINDOW LOCK gen=%s birth=%s lockFromTrig=%s reopen=%s",
                         genBull?"BULL":"BEAR",
                         TimeToString(B[bb].time,TIME_MINUTES),
                         TimeToString(trig2,TIME_MINUTES),
                         reopenTime>0?TimeToString(reopenTime,TIME_MINUTES):"-");
          if(lockAfterTime==0||trig2<lockAfterTime)
            {
             lockAfterTime=trig2;
            }
         }
       for(int ox=0; ox<nSB; ox++)
         {
          int bbOlder=genBull?bullBirths[ox]:bearBirths[ox];
          if(bbOlder<0 || bbOlder>=n || bbOlder>=bb) continue;
          datetime olderOwnerC1=genBull?ownerC1Bull[bbOlder]:ownerC1Bear[bbOlder];
          if(olderOwnerC1<=B[bb].time) continue;
          if(supersedeAfterTime==0 || olderOwnerC1<supersedeAfterTime)
             supersedeAfterTime=olderOwnerC1;
         }
      }

      DrawGeneration(B,n,pSec,genBull,bb,sibs,nSibs,structuralFrom,bias,
                     bullBirths,nBull,bearBirths,nBear,supersedeAfterTime,lockAfterTime,
                     !fastMode,renderVisuals);
     }

   datetime virginDrawFrom=VirginVisualStart();
   if(renderVisuals)
     {
      for(int i=0;i<=n-2;i++)
        {
         if(ClassifyClosed(B,n,i,true)==-2) ProcessVirginCand(B,n,i,true, virginDrawFrom,pSec,bias,htfOpen);
         else if(!fastMode)
           {
            DeleteCandidateVisualFamily(true,B[i].time,i);
            DeleteVirginVisualFamily(true,B[i].time,i);
           }
         if(ClassifyClosed(B,n,i,false)==-2) ProcessVirginCand(B,n,i,false,virginDrawFrom,pSec,bias,htfOpen);
         else if(!fastMode)
           {
            DeleteCandidateVisualFamily(false,B[i].time,i);
            DeleteVirginVisualFamily(false,B[i].time,i);
           }
        }
     }

    if(!fastMode)
       ObjCachePrune();
    g_needsRedraw = false; // Reset redraw flag after successful draw
   if(!fastMode && !IsNonVisualTesterRun())
      ChartRedraw(0);
  }

void ClearOwnedObjects()
  {
   g_resettingOwnedState=true;
   g_chartChangePending=false;
   g_needsRedraw=false;
   g_currentBias=0;
   g_lastTickMs=0;
   g_lastDashboardUpdateMs=0;
    g_sigTrigTime=0; g_sigBull=true; g_sigName=""; g_sigState=SS_INACTIVE;
    g_sigC1=false; g_sigC2=false; g_sigC3=false; g_sigBirthTime=0; g_sigLevel=0;
    g_sigSlPx=0; g_sigTpPx=0; g_sigCoPx=0; g_sigModelLabel="";
    ArrayResize(g_hints,0); g_nHints=0;
    ArrayResize(g_cands,0); g_nCands=0;
    ArrayResize(g_tsGlows,0); g_nTsGlows=0;
    ResetExecFamilyTracks();
    ResetLTFWindowCache();
    ResetHTFDrawCache();
    ResetExecutionRuntimeState();
    ObjCacheFullReset();
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);
   ClearDashboards();
   for(int pass=0; pass<24; pass++)
     {
      int ownedBefore=CountOwnedChartObjects();
      bool removed=DeleteOwnedChartObjectsPass();
      if(DeleteOwnedChartObjectsLiveSweep())
         removed=true;
      int ownedAfter=CountOwnedChartObjects();
      if(ownedAfter<=0)
         break;
      if(removed || ownedAfter<ownedBefore)
        {
         ChartRedraw(0);
         Sleep(10);
        }
      if(!removed && ownedAfter>=ownedBefore)
         break;
     }
   uint finalDeadline=GetTickCount()+2000;
   while(CountOwnedChartObjects()>0 && GetTickCount()<finalDeadline)
     {
      bool removed=DeleteOwnedChartObjectsPass();
      if(DeleteOwnedChartObjectsLiveSweep())
         removed=true;
      ChartRedraw(0);
      if(!removed)
        {
         Sleep(25);
         if(!DeleteOwnedChartObjectsLiveSweep())
            break;
        }
      Sleep(25);
     }
   string finalOwnedNames[];
   int finalOwnedCount=CollectOwnedChartObjectNames(finalOwnedNames);
    for(int i=0; i<finalOwnedCount; i++)
       ObjectDelete(0,finalOwnedNames[i]);
    DeleteOwnedByKnownPrefixes();
    DeleteOwnedChartObjectsLiveSweep();
    int finalAggTotal=ObjectsTotal(0,-1,-1);
    for(int i=finalAggTotal-1;i>=0;i--)
      {
       string aggName=ObjectName(0,i,-1,-1);
       if(aggName!="" && IsOwnedChartObjectName(aggName))
          ObjectDelete(0,aggName);
      }
    uint bruteDeadline=GetTickCount()+1500;
    while(GetTickCount()<bruteDeadline)
      {
       if(!DeleteOwnedChartObjectsBruteForce())
          break;
       ChartRedraw(0);
       Sleep(20);
      }
    ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,true);
    ChartRedraw(0);
    g_resettingOwnedState=false;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   ObjectsDeleteAll(0,PFX,-1,-1);
   ObjectsDeleteAll(0,"CCTW_",-1,-1);
   g_resettingOwnedState=true;
   g_attachTick=GetTickCount();
   // Initialise runtime risk from input (overridden by GV if it exists)
   g_riskPct = Inp_DefaultRiskPct;
   // Initialise custom balance to account balance at attach time.
   // Users can override this in the dashboard (Risk tab → Cst field).
   // Using a GlobalVariable so the value survives timeframe switches.
   if(!GlobalVariableCheck("CCT_CBAL")||GlobalVariableGet("CCT_CBAL")<=0.0)
      g_custBal = AccountInfoDouble(ACCOUNT_BALANCE);
   // Reset all session hour caches so new input values take effect immediately
   ResetTradeWindowCache();
   ResetExecFamilyTracks();
   ResetLTFWindowCache();
   ResetExecutionRuntimeState();
   ObjCacheFullReset();
   g_currentBias=0;
   g_chartChangePending=false;
   g_needsRedraw=false;
   g_lastTickMs=0;
   g_lastDashboardUpdateMs=0;
   ResetSignalSnapshot();
   ClearTransientVisualState();
   InitResearchExport();

   Print("[CCT v6.0] Init");
   ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,false);
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,DashboardRuntimeEnabled());

   EventKillTimer();
   EventSetMillisecondTimer((int)RuntimeTimerIntervalMs());

   if(IsNonVisualTesterRun())
      ProcessNonVisualTesterState();
   else
      Draw();
   if(DashboardRuntimeEnabled())
     {
      InitDashboards();
      UpdateDashboards();
     }
   else
      ClearDashboards();
   g_resettingOwnedState=false;
   g_chartChangePending=true;
   g_chartChangeTick=GetTickCount();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(Inp_ShowDebug)
      PrintFormat("[CCT DBG] OnDeinit reason=%d (CHARTCHANGE=%d REMOVE=%d RECOMPILE=%d)",
                  reason, REASON_CHARTCHANGE, REASON_REMOVE, REASON_RECOMPILE);
   ClearOwnedObjects();
   uint bruteDeadline=GetTickCount()+1500;
   while(GetTickCount()<bruteDeadline)
     {
      if(!DeleteOwnedChartObjectsBruteForce())
         break;
      ChartRedraw(0);
      Sleep(20);
     }
   ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,true);
   ChartRedraw(0);
   if(Inp_ShowDebug)
      PrintFormat("[CCT DBG] OnDeinit complete - %d owned objects remaining",
                  CountOwnedChartObjects());
  }

void OnTick()
  {
   if(g_resettingOwnedState) return;
   CheckLiveTrigger();
   ProcessPending();
   ManagePositions();
   uint nowMs=GetTickCount();
   g_lastTickMs=nowMs;
   if(IsNonVisualTesterRun())
     {
      static datetime s_lastLtfNonVisual=0;
      static datetime s_lastHtfNonVisual=0;
      datetime ltfBarNonVisual=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
      datetime htfBarNonVisual=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
      if(ltfBarNonVisual!=s_lastLtfNonVisual)
        {
         bool needFull=(g_htfDrawCacheN<2 || htfBarNonVisual!=s_lastHtfNonVisual);
         s_lastLtfNonVisual=ltfBarNonVisual;
         s_lastHtfNonVisual=htfBarNonVisual;
         ProcessNonVisualTesterState(!needFull);
        }
      ProcessPending();
      return;
     }
   static datetime s_lastLtf=0;
   static datetime s_lastHtf=0;
   datetime ltfBar=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   datetime htfBar=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
   bool liveRefresh=(g_nPending>0 || g_nHints>0 || g_nTsGlows>0 || HasOpenCCTPosition()
                     || g_sigState==SS_ACTIVE || g_sigState==SS_TRIGGERED);
   bool intrabarStateActive=(g_nHints>0 || g_nTsGlows>0 || g_nPending>0 || HasOpenCCTPosition()
                             || g_sigState==SS_ACTIVE || g_sigState==SS_TRIGGERED);
   if(ltfBar!=s_lastLtf)
     {
      s_lastLtf=ltfBar;
      bool needFullDraw=(g_objPrevN==0 || htfBar!=s_lastHtf);
      s_lastHtf=htfBar;
      if(needFullDraw) Draw();
      else             Draw(true);
     }
   else if(liveRefresh && intrabarStateActive)
     {
     if(AllowTickIntrabarFastDraw(nowMs))
         Draw(true);
     }
   ProcessPending();
   if(!IsNonVisualTesterRun())
      DrawHints();
   if(DashboardUpdateDue(nowMs))
      UpdateDashboards();
  }

// Timer fires every 200ms regardless of price activity.
// Flushes pending chart-change redraws so objects reappear promptly
// after scrolling or TF switches even when ticks are sparse (M5, M15).
void OnTimer()
  {
   if(g_resettingOwnedState) return;
   if(IsNonVisualTesterRun()) return;
   static uint s_lastScannerRecoveryDraw=0;
   static uint s_lastIntrabarStateDraw=0;
   uint nowMs=GetTickCount();
   bool canRenderChart=!IsNonVisualTesterRun();
   bool testerVisual=IsVisualTesterRun();
   bool liveRefresh=(g_nPending>0 || g_nHints>0 || g_nTsGlows>0 || HasOpenCCTPosition()
                     || g_sigState==SS_ACTIVE || g_sigState==SS_TRIGGERED);
   bool scannerWarmupNeeded=(g_objPrevN==0 && (nowMs-g_attachTick)<12000);
   bool intrabarStateActive=(g_nHints>0 || g_nTsGlows>0 || g_nPending>0 || HasOpenCCTPosition()
                             || g_sigState==SS_ACTIVE || g_sigState==SS_TRIGGERED);
   bool tickFlowStalled=(g_lastTickMs==0 || nowMs-g_lastTickMs>=300);
   if(canRenderChart && (g_chartChangePending || g_needsRedraw))
     {
      uint elapsed=GetTickCount()-g_chartChangeTick;
      if(elapsed >= 200 || g_needsRedraw)
        {
         if(Inp_ShowDebug)
            PrintFormat("[CCT DBG] OnTimer FLUSH | elapsed=%dms | obj=%d",
                        (int)elapsed, ObjectsTotal(0,0,-1));
         g_chartChangePending=false;
         g_needsRedraw=false;
         Draw();
         ProcessPending();
         if(canRenderChart) DrawHints();
         ManagePositions();
         if(DashboardUpdateDue(nowMs)) UpdateDashboards();
        }
     }
   else if(scannerWarmupNeeded && !testerVisual)
     {
      if(s_lastScannerRecoveryDraw==0 || nowMs-s_lastScannerRecoveryDraw>=2500)
        {
         Draw();
         s_lastScannerRecoveryDraw=nowMs;
        }
      ProcessPending();
      if(canRenderChart) DrawHints();
      ManagePositions();
      if(DashboardUpdateDue(nowMs)) UpdateDashboards();
     }
   else if(liveRefresh && !testerVisual)
     {
      if(tickFlowStalled && intrabarStateActive
         && (s_lastIntrabarStateDraw==0 || nowMs-s_lastIntrabarStateDraw>=250))
        {
         Draw(true);
         s_lastIntrabarStateDraw=nowMs;
        }
      ProcessPending();
      if(canRenderChart) DrawHints();
      ManagePositions();
      if(DashboardUpdateDue(nowMs)) UpdateDashboards();
     }
  }

void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp)
   {
    if(g_resettingOwnedState) return;
    // Always route to dashboard handler first (drag, collapse, edit fields)
   if(DashboardRuntimeEnabled())
      HandleDashboardEvent(id,lp,dp,sp);

    if(id==CHARTEVENT_CHART_CHANGE)
      {
       static ENUM_TIMEFRAMES s_lastPeriod=PERIOD_CURRENT;
       static string s_lastSymbol="";
       ENUM_TIMEFRAMES curPeriod=ChartPeriod(0);
       string curSymbol=ChartSymbol(0);
       bool tfChanged=(curPeriod!=s_lastPeriod);
       bool symbolChanged=(s_lastSymbol!="" && s_lastSymbol!=curSymbol);
       if(tfChanged) s_lastPeriod=curPeriod;
       s_lastSymbol=curSymbol;

       // Only log when the timeframe actually changed, not on every
       // scroll/zoom (which fires CHART_CHANGE 20-30 times per second).
       if(Inp_ShowDebug&&tfChanged)
          PrintFormat("[CCT DBG] CHART_CHANGE | TF=%s | obj=%d",
                      EnumToString(curPeriod), ObjectsTotal(0,0,-1));

        if(tfChanged || symbolChanged)
           return;

        if(g_attachTick>0 && GetTickCount()-g_attachTick<600)
           return;

        g_chartChangePending=true;
       g_chartChangeTick   =GetTickCount();
      }

    // Handle chart symbol/timeframe change — detect symbol change by comparing current symbol
    
   }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   HandleTradeTransaction(trans);
  }

double OnTester()
  {
   return TesterStatistics(STAT_PROFIT);
  }
