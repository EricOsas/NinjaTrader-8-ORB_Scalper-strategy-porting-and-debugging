#ifndef CCT_EXECUTION_MQH
#define CCT_EXECUTION_MQH

#include <Trade/Trade.mqh>
#include "CCT_Globals.mqh"

ExecRecord g_execRecords[];
int        g_nExecRecords=0;

struct CCTPendingExecLink
  {
   ulong             order;
   string            genKey;
   bool              bull;
   datetime          setTime;
  };

CCTPendingExecLink g_pendingExecLinks[];
int                g_nPendingExecLinks=0;
string             g_rejectedExecKeys[];
datetime           g_rejectedExecTriggers[];
int                g_nRejectedExecs=0;

/*
Purpose: Return the dedicated magic used only by the disabled-by-default demo execution probe.
Constitution: Live/funded trading must never be touched by diagnostics unless explicitly enabled on demo.
Inputs: None.
Outputs: Probe-only magic number.
*/

/*
Purpose: Check whether the demo execution probe is allowed to run on this account.
Constitution: Execution diagnostics must be impossible on real/funded accounts by default.
Inputs: None.
Outputs: True only for explicit demo-account probe runs.
*/

/*
Purpose: Find an open probe position owned by the demo latency probe on the current symbol.
Constitution: Diagnostics may only manage their own probe position, never strategy or manual trades.
Inputs: ticket - receives the position ticket.
Outputs: True when a matching probe position exists.
*/

/*
Purpose: Send and close a tiny demo-only order to measure broker fill/close recognition latency.
Constitution: Diagnostics must be disabled by default, demo-only, and isolated from strategy orders.
Inputs: None.
Outputs: Probe order may be sent/closed when explicitly enabled on a demo account.
*/

/*
Purpose: Return the index of a generation execution record.
Constitution: Execution truth is generation-keyed and must survive scanner redraw/rebuild passes.
Inputs: genKey - immutable generation key.
Outputs: Record index or -1.
*/
int CCTFindExecRecord(const string genKey)
  {
   for(int i=0;i<g_nExecRecords;i++)
      if(g_execRecords[i].genKey==genKey)
         return i;
   return -1;
  }

/*
Purpose: Return whether a broker-rejected trigger has already been handled this session.
Constitution: Rejected orders must not create normal execution records or repeatedly redraw stale execution objects.
Inputs: genKey - generation key, triggerTime - trigger bar time.
Outputs: True when this rejected execution is already known.
*/
bool CCTRejectedExecKnown(const string genKey,datetime triggerTime)
  {
   for(int i=0;i<g_nRejectedExecs;i++)
      if(g_rejectedExecKeys[i]==genKey && g_rejectedExecTriggers[i]==triggerTime)
         return true;
   return false;
  }

/*
Purpose: Remember a broker-rejected trigger without promoting it to a normal execution record.
Constitution: Failed broker orders are diagnostics only; they must not become synthetic trades or live-extending visuals.
Inputs: genKey - generation key, triggerTime - trigger bar time.
Outputs: In-memory rejected-trigger guard updated.
*/
void CCTRememberRejectedExec(const string genKey,datetime triggerTime)
  {
   if(genKey=="" || triggerTime<=0 || CCTRejectedExecKnown(genKey,triggerTime))
      return;

   ArrayResize(g_rejectedExecKeys,g_nRejectedExecs+1,8);
   ArrayResize(g_rejectedExecTriggers,g_nRejectedExecs+1,8);
   g_rejectedExecKeys[g_nRejectedExecs]=genKey;
   g_rejectedExecTriggers[g_nRejectedExecs]=triggerTime;
   g_nRejectedExecs++;
  }

bool CCTResolvedState(SIB_STATE st)
  {
   return (st==SS_RESOLVED_TP || st==SS_RESOLVED_SL || st==SS_RESOLVED_BE || st==SS_RESOLVED_BE_CO);
  }

bool CCTExecRecordMatchesTrigger(const ExecRecord &rec,datetime triggerTime)
  {
   return (triggerTime>0 && rec.triggerBarTime==triggerTime);
  }

bool CCTExecRecordConsumesGeneration(const ExecRecord &rec)
  {
   return (rec.triggerBarTime>0 &&
           (rec.visualEntry>0.0 || rec.brokerFill>0.0 || rec.ticket>0 ||
            rec.isSynthetic || CCTResolvedState(rec.outcome)));
  }

string CCTRecordModelTag()
  {
   if(Inp_TimeframeModel==CCT_TFM_4H_M5)
      return "4H5M";
   if(Inp_TimeframeModel==CCT_TFM_D1_M15)
      return "D1M15";
   return "1H1M";
  }

string CCTOutcomeStem(const string genKey)
  {
   return "CCT_OUT_"+_Symbol+"_"+CCTRecordModelTag()+"_"+genKey;
  }

string CCTOutcomeStemLegacy(const string genKey)
  {
   return "CCT_OUT_"+_Symbol+"_"+genKey;
  }

string CCTExecStem(const string genKey)
  {
   return "CCT_EXEC_"+_Symbol+"_"+CCTRecordModelTag()+"_"+genKey;
  }

string CCTExecStemLegacy(const string genKey)
  {
   return "CCT_EXEC_"+_Symbol+"_"+genKey;
  }

void CCTPersistOutcome(const string genKey,datetime triggerTime,SIB_STATE state,datetime exitTime,double exitPrice)
  {
   if(genKey=="" || triggerTime<=0 || !CCTResolvedState(state))
      return;
   GlobalVariableSet(CCTOutcomeStem(genKey)+"_G",(double)triggerTime);
   GlobalVariableSet(CCTOutcomeStem(genKey)+"_S",(double)state);
   GlobalVariableSet(CCTOutcomeStem(genKey)+"_T",(double)exitTime);
   GlobalVariableSet(CCTOutcomeStem(genKey)+"_P",exitPrice);
  }

bool CCTLoadOutcome(const string genKey,datetime triggerTime,SIB_STATE &state,datetime &exitTime,double &exitPrice)
  {
   state=SS_UNKNOWN_OUTCOME;
   exitTime=0;
   exitPrice=0.0;
   string stem=CCTOutcomeStem(genKey);
   if(triggerTime<=0)
      return false;
   if(!GlobalVariableCheck(stem+"_G") || !GlobalVariableCheck(stem+"_S"))
     {
      if(Inp_TimeframeModel!=CCT_TFM_1H_M1)
         return false;
      stem=CCTOutcomeStemLegacy(genKey);
      if(!GlobalVariableCheck(stem+"_G") || !GlobalVariableCheck(stem+"_S"))
         return false;
     }
   datetime storedTrigger=(datetime)(long)GlobalVariableGet(stem+"_G");
   if(storedTrigger!=triggerTime)
      return false;
   state=(SIB_STATE)(int)GlobalVariableGet(stem+"_S");
   exitTime=(datetime)(long)GlobalVariableGet(stem+"_T");
   exitPrice=GlobalVariableGet(stem+"_P");
   return CCTResolvedState(state);
  }

bool CCTSyncExecRecordOutcomeFromGlobal(const int idx,const bool persist=true)
  {
   // CCT_EXEC_RECORD_OUTCOME_SYNC_V1
   // Full scanner redraws may recover resolved outcome globals before the
   // cached execution record is updated. Keep the record in sync so fast
   // visual pulses cannot stretch old resolved objects back to live time.
   if(idx<0 || idx>=g_nExecRecords)
      return false;
   if(g_execRecords[idx].genKey=="" || g_execRecords[idx].triggerBarTime<=0)
      return false;

   SIB_STATE state=SS_UNKNOWN_OUTCOME;
   datetime exitTime=0;
   double exitPrice=0.0;
   if(!CCTLoadOutcome(g_execRecords[idx].genKey,g_execRecords[idx].triggerBarTime,state,exitTime,exitPrice))
      return false;

   bool changed=((int)g_execRecords[idx].outcome!=(int)state ||
                 g_execRecords[idx].exitTime!=exitTime ||
                 MathAbs(g_execRecords[idx].exitPrice-exitPrice)>_Point*0.1);
   if(!changed)
      return CCTResolvedState(g_execRecords[idx].outcome);

   g_execRecords[idx].outcome=state;
   g_execRecords[idx].exitTime=exitTime;
   g_execRecords[idx].exitPrice=exitPrice;
   if(persist)
      CCTPersistExecRecord(g_execRecords[idx]);

   return true;
  }

void CCTPersistExecRecord(const ExecRecord &rec)
  {
   if(rec.genKey=="")
      return;
   string stem=CCTExecStem(rec.genKey);
   GlobalVariableSet(stem+"_B",rec.bull ? 1.0 : 0.0);
   GlobalVariableSet(stem+"_G",(double)rec.triggerBarTime);
   GlobalVariableSet(stem+"_E",rec.visualEntry);
   GlobalVariableSet(stem+"_F",rec.brokerFill);
   GlobalVariableSet(stem+"_SP",rec.triggerSpread);
   GlobalVariableSet(stem+"_S",rec.brokerSL);
   GlobalVariableSet(stem+"_T",rec.brokerTP);
   GlobalVariableSet(stem+"_C",rec.coPrice);
   GlobalVariableSet(stem+"_R",rec.lockedRR);
   ENUM_MODEL_TYPE persistModel=CCTModelTypeForSweepTruth(rec.modelType,rec.sweepCount,0);
   GlobalVariableSet(stem+"_MT",(double)persistModel);
   GlobalVariableSet(stem+"_SW",(double)rec.sweepCount);
   GlobalVariableSet(stem+"_Y",rec.ticket);
   GlobalVariableSet(stem+"_L",rec.execLots);
   GlobalVariableSet(stem+"_SI",(double)rec.sibIndex);
   GlobalVariableSet(stem+"_C1",(double)rec.c1Time);
   GlobalVariableSet(stem+"_C2",(double)rec.c2Time);
   GlobalVariableSet(stem+"_C3",(double)rec.c3Time);
   GlobalVariableSet(stem+"_BA",rec.beApplied ? 1.0 : 0.0);
   GlobalVariableSet(stem+"_BG",rec.beGeneralApplied ? 1.0 : 0.0);
   GlobalVariableSet(stem+"_BC",rec.beCoApplied ? 1.0 : 0.0);

   // Compatibility/active visible BE channel.
   GlobalVariableSet(stem+"_BP",rec.bePrice);
   GlobalVariableSet(stem+"_BT",(double)rec.beTime);
   GlobalVariableSet(stem+"_BL",(double)rec.beLeftAnchorTime);

   // Independent BE channels.
   GlobalVariableSet(stem+"_BGP",rec.beGeneralPrice);
   GlobalVariableSet(stem+"_BGT",(double)rec.beGeneralTime);
   GlobalVariableSet(stem+"_BGL",(double)rec.beGeneralLeftAnchorTime);
   GlobalVariableSet(stem+"_BCP",rec.beCoPrice);
   GlobalVariableSet(stem+"_BCT",(double)rec.beCoTime);
   GlobalVariableSet(stem+"_BCL",(double)rec.beCoLeftAnchorTime);

   GlobalVariableSet(stem+"_MP",rec.maxProgressPct);
   GlobalVariableSet(stem+"_CO",rec.coTouched ? 1.0 : 0.0);
   GlobalVariableSet(stem+"_CT",(double)rec.coTouchTime);
   GlobalVariableSet(stem+"_VTA",rec.virtualTPActive ? 1.0 : 0.0);
   GlobalVariableSet(stem+"_VTT",rec.virtualTPTouched ? 1.0 : 0.0);
   GlobalVariableSet(stem+"_VTM",(double)rec.virtualTPTouchTime);
  }


bool CCTLoadExecRecord(const string genKey,ExecRecord &rec)
  {
   ZeroMemory(rec);
   rec.sibIndex=-1;
   string stem=CCTExecStem(genKey);
   if(!GlobalVariableCheck(stem+"_G"))
     {
      // CCT_EXEC_RECORD_MODEL_NAMESPACE_V1
      // Old records were symbol+generation keyed only, so 4H/D1 instances
      // could accidentally import another model's setup. Keep legacy recovery
      // only for the original 1H/1m namespace.
      if(Inp_TimeframeModel!=CCT_TFM_1H_M1)
         return false;
      stem=CCTExecStemLegacy(genKey);
      if(!GlobalVariableCheck(stem+"_G"))
         return false;
     }

   rec.genKey=genKey;
   rec.bull=(GlobalVariableGet(stem+"_B")>0.5);
   rec.triggerBarTime=(datetime)(long)GlobalVariableGet(stem+"_G");
   rec.visualEntry=GlobalVariableGet(stem+"_E");
   rec.brokerFill=GlobalVariableGet(stem+"_F");
   if(GlobalVariableCheck(stem+"_SP"))
      rec.triggerSpread=GlobalVariableGet(stem+"_SP");
   rec.brokerSL=GlobalVariableGet(stem+"_S");
   rec.brokerTP=GlobalVariableGet(stem+"_T");
   rec.coPrice=GlobalVariableGet(stem+"_C");
   rec.lockedRR=GlobalVariableGet(stem+"_R");
   if(GlobalVariableCheck(stem+"_MT"))
      rec.modelType=(ENUM_MODEL_TYPE)(int)GlobalVariableGet(stem+"_MT");
   if(GlobalVariableCheck(stem+"_SW"))
      rec.sweepCount=(int)GlobalVariableGet(stem+"_SW");
   rec.ticket=(ulong)GlobalVariableGet(stem+"_Y");
   if(GlobalVariableCheck(stem+"_L"))
      rec.execLots=GlobalVariableGet(stem+"_L");
   if(GlobalVariableCheck(stem+"_SI"))
      rec.sibIndex=(int)GlobalVariableGet(stem+"_SI");
   if(GlobalVariableCheck(stem+"_C1"))
      rec.c1Time=(datetime)(long)GlobalVariableGet(stem+"_C1");
   if(GlobalVariableCheck(stem+"_C2"))
      rec.c2Time=(datetime)(long)GlobalVariableGet(stem+"_C2");
   if(GlobalVariableCheck(stem+"_C3"))
      rec.c3Time=(datetime)(long)GlobalVariableGet(stem+"_C3");

   if(GlobalVariableCheck(stem+"_BA"))
      rec.beApplied=(GlobalVariableGet(stem+"_BA")>0.5);
   bool hasBEGeneral=GlobalVariableCheck(stem+"_BG");
   bool hasBECO=GlobalVariableCheck(stem+"_BC");
   if(hasBEGeneral)
      rec.beGeneralApplied=(GlobalVariableGet(stem+"_BG")>0.5);
   if(hasBECO)
      rec.beCoApplied=(GlobalVariableGet(stem+"_BC")>0.5);

   if(GlobalVariableCheck(stem+"_BP"))
      rec.bePrice=GlobalVariableGet(stem+"_BP");
   if(GlobalVariableCheck(stem+"_BT"))
      rec.beTime=(datetime)(long)GlobalVariableGet(stem+"_BT");
   if(GlobalVariableCheck(stem+"_BL"))
      rec.beLeftAnchorTime=(datetime)(long)GlobalVariableGet(stem+"_BL");

   if(GlobalVariableCheck(stem+"_BGP"))
      rec.beGeneralPrice=GlobalVariableGet(stem+"_BGP");
   if(GlobalVariableCheck(stem+"_BGT"))
      rec.beGeneralTime=(datetime)(long)GlobalVariableGet(stem+"_BGT");
   if(GlobalVariableCheck(stem+"_BGL"))
      rec.beGeneralLeftAnchorTime=(datetime)(long)GlobalVariableGet(stem+"_BGL");
   if(GlobalVariableCheck(stem+"_BCP"))
      rec.beCoPrice=GlobalVariableGet(stem+"_BCP");
   if(GlobalVariableCheck(stem+"_BCT"))
      rec.beCoTime=(datetime)(long)GlobalVariableGet(stem+"_BCT");
   if(GlobalVariableCheck(stem+"_BCL"))
      rec.beCoLeftAnchorTime=(datetime)(long)GlobalVariableGet(stem+"_BCL");

   if(GlobalVariableCheck(stem+"_MP"))
      rec.maxProgressPct=GlobalVariableGet(stem+"_MP");
   if(GlobalVariableCheck(stem+"_CO"))
      rec.coTouched=(GlobalVariableGet(stem+"_CO")>0.5);
   if(GlobalVariableCheck(stem+"_CT"))
      rec.coTouchTime=(datetime)(long)GlobalVariableGet(stem+"_CT");

   // Legacy compatibility: older records only had one BE price/time/anchor.
   if(rec.beApplied && !hasBEGeneral && !hasBECO)
     {
      rec.beCoApplied=rec.coTouched;
      rec.beGeneralApplied=!rec.coTouched;
     }
   if(rec.beApplied && !rec.beGeneralApplied && !rec.beCoApplied)
     {
      rec.beCoApplied=rec.coTouched;
      rec.beGeneralApplied=!rec.coTouched;
     }
   if(rec.beGeneralApplied && rec.beGeneralPrice<=0.0 && rec.bePrice>0.0)
     {
      rec.beGeneralPrice=rec.bePrice;
      rec.beGeneralTime=rec.beTime;
      rec.beGeneralLeftAnchorTime=rec.beLeftAnchorTime;
     }
   if(rec.beCoApplied && rec.beCoPrice<=0.0 && rec.bePrice>0.0)
     {
      rec.beCoPrice=rec.bePrice;
      rec.beCoTime=rec.beTime;
      rec.beCoLeftAnchorTime=rec.beLeftAnchorTime;
     }

   // Compatibility/active visible channel follows Global if present, otherwise NY BE-CO.
   if(rec.beGeneralApplied && rec.beGeneralPrice>0.0)
     {
      rec.bePrice=rec.beGeneralPrice;
      rec.beTime=rec.beGeneralTime;
      rec.beLeftAnchorTime=rec.beGeneralLeftAnchorTime;
     }
   else if(rec.beCoApplied && rec.beCoPrice>0.0)
     {
      rec.bePrice=rec.beCoPrice;
      rec.beTime=rec.beCoTime;
      rec.beLeftAnchorTime=rec.beCoLeftAnchorTime;
     }

   if(GlobalVariableCheck(stem+"_VTA"))
      rec.virtualTPActive=(GlobalVariableGet(stem+"_VTA")>0.5);
   if(GlobalVariableCheck(stem+"_VTT"))
      rec.virtualTPTouched=(GlobalVariableGet(stem+"_VTT")>0.5);
   if(GlobalVariableCheck(stem+"_VTM"))
      rec.virtualTPTouchTime=(datetime)(long)GlobalVariableGet(stem+"_VTM");

   rec.modelType=CCTModelTypeForSweepTruth(rec.modelType,rec.sweepCount,0);

   return (rec.triggerBarTime>0 && rec.visualEntry>0.0 && rec.brokerSL>0.0 && rec.brokerTP>0.0);
  }


int CCTEnsureExecRecord(const string genKey)
  {
   int idx=CCTFindExecRecord(genKey);
   if(idx>=0)
      return idx;

   ExecRecord loaded;
   if(CCTLoadExecRecord(genKey,loaded))
     {
      ArrayResize(g_execRecords,g_nExecRecords+1,16);
      g_execRecords[g_nExecRecords]=loaded;
      return g_nExecRecords++;
     }

   ArrayResize(g_execRecords,g_nExecRecords+1,16);
   ZeroMemory(g_execRecords[g_nExecRecords]);
   g_execRecords[g_nExecRecords].genKey=genKey;
   g_execRecords[g_nExecRecords].sibIndex=-1;
   return g_nExecRecords++;
  }

/*
Purpose: Reset tester-only persistent execution/research state for the active symbol before a new Strategy Tester run.
Constitution: Tester runs must be independent; stale global variables from older runs must never pre-consume, resolve, or resurrect POIs.
Inputs: None.
Outputs: Deletes CCT execution/outcome/MFE-MAE globals for _Symbol and clears in-memory execution link arrays.
*/
void CCTClearTesterPersistentState()
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return;

   string execPrefix="CCT_EXEC_"+_Symbol+"_";
   string outPrefix="CCT_OUT_"+_Symbol+"_";
   string mmPrefix="CCT_MM_"+_Symbol+"_";
   int deleted=0;
   int total=GlobalVariablesTotal();

   for(int i=total-1;i>=0;i--)
     {
      string name=GlobalVariableName(i);
      if(StringFind(name,execPrefix)==0 ||
         StringFind(name,outPrefix)==0 ||
         StringFind(name,mmPrefix)==0)
        {
         if(GlobalVariableDel(name))
            deleted++;
        }
     }

   ArrayResize(g_execRecords,0);
   g_nExecRecords=0;
   ArrayResize(g_pendingExecLinks,0);
   g_nPendingExecLinks=0;
   ArrayResize(g_rejectedExecKeys,0);
   ArrayResize(g_rejectedExecTriggers,0);
   g_nRejectedExecs=0;

   CCTJournalLine(StringFormat("[CCT INIT] tester persistent state cleared | symbol=%s | deleted=%d",
                               _Symbol,deleted));
  }

int CCTAddPendingExecLink(const string genKey,bool bull)
  {
   ArrayResize(g_pendingExecLinks,g_nPendingExecLinks+1,4);
   int idx=g_nPendingExecLinks++;
   g_pendingExecLinks[idx].order=0;
   g_pendingExecLinks[idx].genKey=genKey;
   g_pendingExecLinks[idx].bull=bull;
   g_pendingExecLinks[idx].setTime=CurrentServerTime();
   return idx;
  }

void CCTRemovePendingExecLinkByIndex(int idx)
  {
   if(idx<0 || idx>=g_nPendingExecLinks)
      return;
   for(int i=idx;i<g_nPendingExecLinks-1;i++)
      g_pendingExecLinks[i]=g_pendingExecLinks[i+1];
   g_nPendingExecLinks--;
   ArrayResize(g_pendingExecLinks,g_nPendingExecLinks);
  }

void CCTUpdatePendingExecOrder(int idx,ulong order,const string genKey)
  {
   if(idx<0 || idx>=g_nPendingExecLinks || order==0)
      return;
   if(g_pendingExecLinks[idx].genKey==genKey)
      g_pendingExecLinks[idx].order=order;
  }

bool CCTTakePendingExecLink(ulong order,string &genKey,bool &bull)
  {
   datetime now=CurrentServerTime();
   for(int pass=0;pass<2;pass++)
     {
      for(int i=g_nPendingExecLinks-1;i>=0;i--)
        {
         bool match=(pass==0 && order>0 && g_pendingExecLinks[i].order==order);
         if(!match && pass==1)
            match=(g_pendingExecLinks[i].order==0 && now-g_pendingExecLinks[i].setTime<=300);
         if(!match)
            continue;
         genKey=g_pendingExecLinks[i].genKey;
         bull=g_pendingExecLinks[i].bull;
         CCTRemovePendingExecLinkByIndex(i);
         return (genKey!="");
        }
     }
   return false;
  }

ulong CCTKnownPositionIdForGenKey(const string genKey)
  {
   int idx=CCTFindExecRecord(genKey);
   if(idx>=0 && g_execRecords[idx].ticket>0)
      return g_execRecords[idx].ticket;

   ExecRecord rec;
   if(CCTLoadExecRecord(genKey,rec) && rec.ticket>0)
      return rec.ticket;

   return 0;
  }

bool CCTFindGenKeyByPositionId(ulong positionId,string &genKey,bool &bull)
  {
   genKey="";
   bull=false;

   if(positionId==0)
      return false;

   // First: in-memory records for the current EA session.
   for(int i=0;i<g_nExecRecords;i++)
     {
      if(g_execRecords[i].ticket!=positionId)
         continue;

      genKey=g_execRecords[i].genKey;
      bull=g_execRecords[i].bull;
      return (genKey!="");
     }

   // Second: persisted execution records from previous terminal/EA sessions.
   string prefix=CCTExecStem(""); // CCT_EXEC_<symbol>_
   int prefixLen=StringLen(prefix);
   int total=GlobalVariablesTotal();

   for(int gv=total-1;gv>=0;gv--)
     {
      string name=GlobalVariableName(gv);

      if(StringFind(name,prefix)!=0)
         continue;

      int nameLen=StringLen(name);
      if(nameLen<=prefixLen+2)
         continue;

      if(StringSubstr(name,nameLen-2,2)!="_Y")
         continue;

      ulong storedPosition=(ulong)GlobalVariableGet(name);
      if(storedPosition!=positionId)
         continue;

      string key=StringSubstr(name,prefixLen,nameLen-prefixLen-2);
      ExecRecord rec;

      if(!CCTLoadExecRecord(key,rec))
         continue;

      genKey=key;
      bull=rec.bull;

      if(CCTFindExecRecord(key)<0)
        {
         ArrayResize(g_execRecords,g_nExecRecords+1,16);
         g_execRecords[g_nExecRecords]=rec;
         g_nExecRecords++;
        }

      return true;
     }

   return false;
  }


double CCTCurrentSpreadPx()
  {
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(ask>bid && bid>0.0)
      return NormalizeDouble(ask-bid,_Digits);
   return 0.0;
  }

int CCTVolumeDigitsFromStep(double step)
  {
   if(step<=0.0)
      return 2;

   double scaled=step;
   for(int digits=0;digits<=8;digits++)
     {
      if(MathAbs(scaled-MathRound(scaled))<1e-8)
         return digits;
      scaled*=10.0;
     }

   return 8;
  }

double CCTCashLossPerLot(const string symbol,bool bull,double entry,double sl)
  {
   if(entry<=0.0 || sl<=0.0 || MathAbs(entry-sl)<=_Point*0.1)
      return 0.0;
   double profit=0.0;
   ENUM_ORDER_TYPE type=bull ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(type,symbol,1.0,entry,sl,profit))
     {
      profit=MathAbs(profit);
      if(MathIsValidNumber(profit) && profit>0.0)
         return profit;
     }

   double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0.0 || tickSize<=0.0)
      return 0.0;
   return MathAbs(entry-sl)/tickSize*tickValue;
  }

double CCTNormalizeLotsDown(const string symbol,double lots,bool allowMinFallback)
  {
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0.0 || maxLot<=0.0)
      return 0.0;
   if(step<=0.0)
      step=0.01;

   if(lots<minLot)
      return allowMinFallback ? minLot : 0.0;
   lots=MathMin(lots,maxLot);
   lots=MathFloor((lots+1e-12)/step)*step;
   int digits=CCTVolumeDigitsFromStep(step);
   lots=NormalizeDouble(lots,digits);
   if(lots<minLot && allowMinFallback)
      lots=minLot;
   if(lots<minLot)
      return 0.0;
   return MathMin(lots,maxLot);
  }

double CCTLotsForRisk(const string symbol,bool bull,double entry,double sl)
  {
   double riskCash=EffectiveAccountBase()*(g_riskPct/100.0);
   double perLot=CCTCashLossPerLot(symbol,bull,entry,sl);
   if(riskCash<=0.0 || perLot<=0.0)
      return 0.0;
   return CCTNormalizeLotsDown(symbol,riskCash/perLot,false);
  }

string CCTRiskSizingAuditLine(const string symbol,
                              bool bull,
                              double entry,
                              double sl,
                              double riskCash,
                              double perLot,
                              double desiredLots,
                              double rawLots,
                              double afterMargin,
                              double afterRiskCap,
                              double afterProp,
                              const string marginReason,
                              const string propReason)
  {
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double contractSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   return StringFormat("[CCT SIZING AUDIT] symbol=%s | side=%s | accountCcy=%s | accMode=%d | effectiveBase=%.2f | inputRiskPreset=%d | inputRiskCustom=%.4f | runtimeRiskPct=%.4f | targetRisk=%.2f | entry=%.5f | sl=%.5f | cashPerLot=%.5f | desiredLots=%.8f | rawLots=%.8f | afterMargin=%.8f | afterRiskCap=%.8f | afterProp=%.8f | minLot=%.8f | maxLot=%.8f | step=%.8f | tickValue=%.8f | tickSize=%.8f | contractSize=%.8f | maxLotMode=%d | maxCrypto=%.2f | maxExposurePct=%.2f | maxRiskIdeaPct=%.2f | marginReason=%s | propReason=%s",
                       symbol,
                       bull ? "BUY" : "SELL",
                       AccountInfoString(ACCOUNT_CURRENCY),
                       (int)CCTEffectiveAccMode(),
                       EffectiveAccountBase(),
                       (int)Inp_RiskPreset,
                       Inp_RiskCustomPct,
                       g_riskPct,
                       riskCash,
                       entry,
                       sl,
                       perLot,
                       desiredLots,
                       rawLots,
                       afterMargin,
                       afterRiskCap,
                       afterProp,
                       minLot,
                       maxLot,
                       step,
                       tickValue,
                       tickSize,
                       contractSize,
                       (int)Inp_MaxLotMode,
                       Inp_MaxLots_Crypto,
                       Inp_MaxExposurePct,
                       Inp_MaxRiskPerIdeaPct,
                       marginReason=="" ? "-" : marginReason,
                       propReason=="" ? "-" : propReason);
  }

bool CCTSymbolNameHas(const string upperSymbol,const string token)
  {
   return (StringFind(upperSymbol,token)>=0);
  }

ENUM_CCT_ASSET_CLASS CCTAssetClassForSymbol(const string symbol)
  {
   string s=symbol;
   StringToUpper(s);

   if(CCTSymbolNameHas(s,"BTC") || CCTSymbolNameHas(s,"ETH") ||
      CCTSymbolNameHas(s,"LTC") || CCTSymbolNameHas(s,"XRP") ||
      CCTSymbolNameHas(s,"BCH") || CCTSymbolNameHas(s,"SOL") ||
      CCTSymbolNameHas(s,"DOGE") || CCTSymbolNameHas(s,"ADA") ||
      CCTSymbolNameHas(s,"DOT"))
      return ASSET_CLASS_CRYPTO;

   if(CCTSymbolNameHas(s,"XAU") || CCTSymbolNameHas(s,"XAG") ||
      CCTSymbolNameHas(s,"GOLD") || CCTSymbolNameHas(s,"SILVER"))
      return ASSET_CLASS_METALS;

   if(CCTSymbolNameHas(s,"USTEC") || CCTSymbolNameHas(s,"US100") ||
      CCTSymbolNameHas(s,"NAS") || CCTSymbolNameHas(s,"NDX") ||
      CCTSymbolNameHas(s,"NQ") || CCTSymbolNameHas(s,"US500") ||
      CCTSymbolNameHas(s,"SPX") || CCTSymbolNameHas(s,"SP500") ||
      CCTSymbolNameHas(s,"US30") || CCTSymbolNameHas(s,"DJ") ||
      CCTSymbolNameHas(s,"GER") || CCTSymbolNameHas(s,"DE40") ||
      CCTSymbolNameHas(s,"DAX") || CCTSymbolNameHas(s,"UK100") ||
      CCTSymbolNameHas(s,"FTSE") || CCTSymbolNameHas(s,"JP225") ||
      CCTSymbolNameHas(s,"NI225") || CCTSymbolNameHas(s,"HK50") ||
      CCTSymbolNameHas(s,"EU50") || CCTSymbolNameHas(s,"AUS200"))
      return ASSET_CLASS_INDICES;

   if(CCTSymbolNameHas(s,"XTI") || CCTSymbolNameHas(s,"XBR") ||
      CCTSymbolNameHas(s,"USOIL") || CCTSymbolNameHas(s,"UKOIL") ||
      CCTSymbolNameHas(s,"BRENT") || CCTSymbolNameHas(s,"WTI") ||
      CCTSymbolNameHas(s,"NGAS") || CCTSymbolNameHas(s,"NATGAS") ||
      CCTSymbolNameHas(s,"COPPER") || CCTSymbolNameHas(s,"COCOA") ||
      CCTSymbolNameHas(s,"COFFEE") || CCTSymbolNameHas(s,"SUGAR"))
      return ASSET_CLASS_COMMODITY;

   long calcMode=SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE);
   if(calcMode==SYMBOL_CALC_MODE_FOREX || calcMode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)
      return ASSET_CLASS_FX;
   if(calcMode==SYMBOL_CALC_MODE_CFDINDEX)
      return ASSET_CLASS_INDICES;

   string base=SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
   string profit=SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base)==3 && StringLen(profit)==3)
      return ASSET_CLASS_FX;

   return ASSET_CLASS_OTHER;
  }

string CCTAssetClassLabel(ENUM_CCT_ASSET_CLASS cls)
  {
   switch(cls)
     {
      case ASSET_CLASS_FX:        return "FX";
      case ASSET_CLASS_METALS:    return "METALS";
      case ASSET_CLASS_COMMODITY: return "COMMODITY";
      case ASSET_CLASS_INDICES:   return "INDICES";
      case ASSET_CLASS_CRYPTO:    return "CRYPTO";
      default:                    return "OTHER";
     }
  }

double CCTConfiguredMaxLotsForClass(ENUM_CCT_ASSET_CLASS cls)
  {
   if(Inp_MaxLotMode==MAX_LOTS_OFF)
      return 0.0;
   if(Inp_MaxLotMode==MAX_LOTS_GLOBAL)
      return MathMax(0.0,Inp_MaxLots);

   switch(cls)
     {
      case ASSET_CLASS_FX:        return MathMax(0.0,Inp_MaxLots_FX);
      case ASSET_CLASS_METALS:    return MathMax(0.0,Inp_MaxLots_Metals);
      case ASSET_CLASS_COMMODITY: return MathMax(0.0,Inp_MaxLots_Commodity);
      case ASSET_CLASS_INDICES:   return MathMax(0.0,Inp_MaxLots_Indices);
      case ASSET_CLASS_CRYPTO:    return MathMax(0.0,Inp_MaxLots_Crypto);
      default:                    return MathMax(0.0,Inp_MaxLots);
     }
  }

double CCTEstimatedRoundTurnCommissionPerLot(const string symbol)
  {
   datetime now=TimeCurrent();
   if(!HistorySelect(now-90*86400,now+1))
      return 0.0;

   double total=0.0;
   double volume=0.0;
   int samples=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=symbol)
         continue;
      double vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
      double cost=MathAbs(HistoryDealGetDouble(deal,DEAL_COMMISSION))+
                  MathAbs(HistoryDealGetDouble(deal,DEAL_FEE));
      if(vol<=0.0 || cost<=0.0)
         continue;
      total+=cost;
      volume+=vol;
      samples++;
      if(samples>=40)
         break;
     }

   if(total<=0.0 || volume<=0.0)
      return 0.0;
   return 2.0*total/volume;
  }

double CCTAdverseSlippageCashPerLot(const string symbol,bool bull,double entry)
  {
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0.0)
      point=_Point;
   double slip=MathMax(0,Inp_MaxDeviationPoints)*point;
   if(entry<=0.0 || slip<=0.0)
      return 0.0;

   double worse=bull ? entry+slip : entry-slip;
   if(worse<=0.0)
      return 0.0;
   return CCTCashLossPerLot(symbol,bull,worse,entry);
  }

double CCTProjectedTradeExposureCash(const string symbol,bool bull,double entry,double sl,double lots)
  {
   if(entry<=0.0 || sl<=0.0 || lots<=0.0)
      return 0.0;
   double perLot=CCTCashLossPerLot(symbol,bull,entry,sl);
   if(perLot<=0.0)
      return 0.0;
   perLot+=CCTEstimatedRoundTurnCommissionPerLot(symbol);
   perLot+=CCTAdverseSlippageCashPerLot(symbol,bull,entry);
   return perLot*lots;
  }

double CCTPositionExposureCash()
  {
   string symbol=PositionGetString(POSITION_SYMBOL);
   long type=PositionGetInteger(POSITION_TYPE);
   bool bull=(type==POSITION_TYPE_BUY);
   double openPx=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double lots=PositionGetDouble(POSITION_VOLUME);
   double risk=0.0;
   if(openPx>0.0 && sl>0.0 && lots>0.0)
      risk=CCTProjectedTradeExposureCash(symbol,bull,openPx,sl,lots);

   double floating=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   double floatingLoss=(floating<0.0) ? -floating : 0.0;
   if(risk<=0.0)
      risk=CCTEstimatedRoundTurnCommissionPerLot(symbol)*lots;
   return MathMax(risk,floatingLoss);
  }

double CCTOpenLotsByAssetClass(ENUM_CCT_ASSET_CLASS cls)
  {
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(CCTAssetClassForSymbol(PositionGetString(POSITION_SYMBOL))!=cls)
         continue;
      total+=PositionGetDouble(POSITION_VOLUME);
     }
   return total;
  }

double CCTOpenIdeaExposureCash(const string symbol,bool bull)
  {
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if((bull && type!=POSITION_TYPE_BUY) || (!bull && type!=POSITION_TYPE_SELL))
         continue;
      total+=CCTPositionExposureCash();
     }
   return total;
  }

double CCTAccountOpenExposureCash()
  {
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      total+=CCTPositionExposureCash();
     }
   return total;
  }

double CCTMaxLotsForExposureCash(const string symbol,bool bull,double entry,double sl,double remainingCash)
  {
   if(remainingCash<=0.0 || entry<=0.0 || sl<=0.0)
      return 0.0;
   double perLot=CCTProjectedTradeExposureCash(symbol,bull,entry,sl,1.0);
   if(perLot<=0.0)
      return 0.0;
   return CCTNormalizeLotsDown(symbol,remainingCash/perLot,false);
  }

double CCTClampLotsToPropCaps(const string symbol,bool bull,double entry,double sl,double lots,string &reason)
  {
   reason="";
   if(lots<=0.0)
      return 0.0;
   if(sl<=0.0 || entry<=0.0)
     {
      reason="prop exposure guard requires a valid SL before entry";
      return 0.0;
     }

   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0.0)
      return 0.0;
   if(step<=0.0)
      step=0.01;

   ENUM_CCT_ASSET_CLASS cls=CCTAssetClassForSymbol(symbol);
   double classCap=CCTConfiguredMaxLotsForClass(cls);
   if(classCap>0.0)
     {
      double classOpen=CCTOpenLotsByAssetClass(cls);
      double remainingLots=classCap-classOpen;
      if(remainingLots<minLot-1e-9)
        {
         reason=StringFormat("max lots exhausted for %s %.2f/%.2f",CCTAssetClassLabel(cls),classOpen,classCap);
         return 0.0;
        }
      lots=MathMin(lots,remainingLots);
     }

   double base=EffectiveAccountBase();
   if(Inp_MaxRiskPerIdeaPct>0.0 && base>0.0)
     {
      double cap=base*MathMax(0.0,Inp_MaxRiskPerIdeaPct)/100.0;
      double used=CCTOpenIdeaExposureCash(symbol,bull);
      double remaining=cap-used;
      double riskLots=CCTMaxLotsForExposureCash(symbol,bull,entry,sl,remaining);
      if(riskLots<minLot-1e-9)
        {
         reason=StringFormat("risk-per-idea exhausted %.2f/%.2f",used,cap);
         return 0.0;
        }
      lots=MathMin(lots,riskLots);
     }

   if(Inp_MaxExposurePct>0.0 && base>0.0)
     {
      double cap=base*MathMax(0.0,Inp_MaxExposurePct)/100.0;
      double used=CCTAccountOpenExposureCash();
      double remaining=cap-used;
      double exposureLots=CCTMaxLotsForExposureCash(symbol,bull,entry,sl,remaining);
      if(exposureLots<minLot-1e-9)
        {
         reason=StringFormat("account exposure exhausted %.2f/%.2f",used,cap);
         return 0.0;
        }
      lots=MathMin(lots,exposureLots);
     }

   lots=CCTNormalizeLotsDown(symbol,lots,false);
   if(lots<minLot)
     {
      reason=StringFormat("prop caps reduced lots below broker minimum %.2f",minLot);
      return 0.0;
     }

   return lots;
  }

string CCTPropCapAudit(const string symbol,bool bull,double entry,double sl,double lots)
  {
   ENUM_CCT_ASSET_CLASS cls=CCTAssetClassForSymbol(symbol);
   double classCap=CCTConfiguredMaxLotsForClass(cls);
   double classOpen=CCTOpenLotsByAssetClass(cls);
   double base=EffectiveAccountBase();
   double ideaCap=(Inp_MaxRiskPerIdeaPct>0.0 && base>0.0) ? base*Inp_MaxRiskPerIdeaPct/100.0 : 0.0;
   double exposureCap=(Inp_MaxExposurePct>0.0 && base>0.0) ? base*Inp_MaxExposurePct/100.0 : 0.0;
   double ideaUsed=CCTOpenIdeaExposureCash(symbol,bull);
   double exposureUsed=CCTAccountOpenExposureCash();
   double projected=CCTProjectedTradeExposureCash(symbol,bull,entry,sl,lots);
   return StringFormat("assetClass=%s | maxLotMode=%d | classOpenLots=%.2f | classCap=%.2f | ideaUsed=%.2f | ideaCap=%.2f | exposureUsed=%.2f | exposureCap=%.2f | projectedExposure=%.2f",
                       CCTAssetClassLabel(cls),
                       (int)Inp_MaxLotMode,
                       classOpen,
                       classCap,
                       ideaUsed,
                       ideaCap,
                       exposureUsed,
                       exposureCap,
                       projected);
  }

/*
Purpose: Enforce a hard maximum cash-risk cap after lot-step rounding, margin fitting, and safety-entry sizing.
Constitution: Broker execution must prefer under-risk over over-risk. If the symbol minimum lot would exceed the configured risk cap, the trade is skipped instead of forced.
Inputs: symbol - trade symbol, bull - direction, entry - risk-side entry assumption, sl - broker SL, lots - candidate lots.
Outputs: Largest broker-valid lot whose projected cash loss is <= configured risk cash, or 0.
*/
double CCTClampLotsToRiskCap(const string symbol,bool bull,double entry,double sl,double lots)
  {
   double riskCash=EffectiveAccountBase()*(g_riskPct/100.0);
   double perLot=CCTCashLossPerLot(symbol,bull,entry,sl);
   if(riskCash<=0.0 || perLot<=0.0 || lots<=0.0)
      return 0.0;

   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0.0)
      return 0.0;
   if(step<=0.0)
      step=0.01;

   lots=CCTNormalizeLotsDown(symbol,lots,false);

   int digits=CCTVolumeDigitsFromStep(step);

   while(lots>=minLot)
     {
      double projected=perLot*lots;
      if(projected<=riskCash+0.0001)
         return NormalizeDouble(lots,digits);

      lots=NormalizeDouble(lots-step,digits);
     }

   return 0.0;
  }

/*
Purpose: Fit a risk-sized lot to available margin and explain any broker-size skip.
Constitution: Broker execution must not force trades that cannot survive account margin constraints.
Inputs: symbol - trade symbol, bull - direction, entry - executable quote, desiredLots - risk-sized lots, reason - diagnostic output.
Outputs: Broker-normalized lots that fit margin, or 0 when the minimum tradable lot cannot fit.
*/
double CCTFitLotsToMargin(const string symbol,bool bull,double entry,double desiredLots,string &reason)
  {
   reason="";

   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0)
      step=0.01;

   double lots=CCTNormalizeLotsDown(symbol,desiredLots,false);
   if(lots<=0.0)
     {
      reason=StringFormat("risk size %.8f lots is below broker minimum %.8f lots for %s",
                          desiredLots,minLot,symbol);
      return 0.0;
     }

   double margin=0.0;
   ENUM_ORDER_TYPE type=bull ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(type,symbol,1.0,entry,margin) || margin<=0.0)
     {
      reason=StringFormat("margin check unavailable for %s at %.5f; using risk-sized %.8f lots",
                          symbol,entry,lots);
      return lots;
     }

   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string accCcy=AccountInfoString(ACCOUNT_CURRENCY);
   double minMargin=margin*minLot;
   if(freeMargin+0.0001<minMargin)
     {
      if(Inp_NoMoneyUseMaxAffordableLot)
        {
         reason=StringFormat("NO_MONEY_LOCAL_SKIP: broker minimum %.8f lots on %s needs %.2f %s, free %.2f %s; no order sent",
                             minLot,symbol,minMargin,accCcy,freeMargin,accCcy);
         return 0.0;
        }
      reason=StringFormat("account margin may be insufficient for broker minimum %.8f lots on %s: need %.2f %s, free %.2f %s; sending risk-sized order for broker-side rejection record",
                          minLot,symbol,minMargin,accCcy,freeMargin,accCcy);
      return lots;
     }

   if(margin*lots<=freeMargin+0.0001)
      return lots;

   if(Inp_NoMoneyUseMaxAffordableLot)
     {
      double affordable=CCTNormalizeLotsDown(symbol,freeMargin/margin,false);
      if(affordable>=minLot)
        {
         reason=StringFormat("NO_MONEY_FIT: reduced %.8f lots to max affordable %.8f lots on %s: estimated need %.2f %s, free %.2f %s",
                             lots,affordable,symbol,margin*lots,accCcy,freeMargin,accCcy);
         return affordable;
        }

      reason=StringFormat("NO_MONEY_LOCAL_SKIP: max affordable lot is below broker minimum %.8f on %s: estimated free %.2f %s",
                          minLot,symbol,freeMargin,accCcy);
      return 0.0;
     }

   reason=StringFormat("account margin may be insufficient for %.8f lots on %s: estimated need %.2f %s, free %.2f %s; sending risk-sized order for broker-side rejection record",
                       lots,symbol,margin*lots,accCcy,freeMargin,accCcy);
   return lots;
  }

double CCTFitLotsToMargin(const string symbol,bool bull,double entry,double desiredLots)
  {
   string reason="";
   return CCTFitLotsToMargin(symbol,bull,entry,desiredLots,reason);
  }

double CCTCommissionPriceOffset(const string symbol,double refPrice)
  {
   datetime now=TimeCurrent();
   if(!HistorySelect(now-30*86400,now+1))
      return 0.0;

   double totalComm=0.0;
   double totalVol=0.0;
   int samples=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=symbol)
         continue;
      double vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
      double comm=MathAbs(HistoryDealGetDouble(deal,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(deal,DEAL_FEE));
      if(vol<=0.0 || comm<=0.0)
         continue;
      totalComm+=comm;
      totalVol+=vol;
      samples++;
      if(samples>=24)
         break;
     }
   if(totalComm<=0.0 || totalVol<=0.0)
      return 0.0;

   double roundTurnPerLot=(totalComm/totalVol)*2.0;
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0)
      tickSize=_Point;
   double oneTickLoss=CCTCashLossPerLot(symbol,true,refPrice,refPrice-tickSize);
   if(oneTickLoss<=0.0)
      oneTickLoss=CCTCashLossPerLot(symbol,false,refPrice,refPrice+tickSize);
   if(oneTickLoss<=0.0)
      return 0.0;
   return NormalizeDouble((roundTurnPerLot/oneTickLoss)*tickSize,_Digits);
  }

string CCTBuildTradeComment(datetime triggerTime,ENUM_MODEL_TYPE modelType,const string genKey="")
  {
   if(Inp_HideTradeComments || Inp_PrivacyMode!=PRIVACY_NORMAL)
      return "";

   // MT5/broker comments are commonly truncated to roughly 31 chars.
   // Keep genKey first for restart recovery, and keep model compact so CCT+TS survives.
   string head=(genKey!="") ? genKey : "CCT";
   string hh="--";
   if(triggerTime>0)
     {
      MqlDateTime dt;
       TimeToStruct(ToExecutionNY(triggerTime),dt);
      hh=StringFormat("%02d",dt.hour);
     }
   return head+"|"+hh+"|"+ModelTypeLabel(modelType);
  }


string CCTJournalSide(bool bull)
  {
   return bull ? "BUY" : "SELL";
  }

string CCTJournalState(SIB_STATE state)
  {
   string out=EnumToString(state);
   StringReplace(out,"SS_","");
   StringReplace(out,"RESOLVED_","");
   StringReplace(out,"_","/");
   return out;
  }

string CCTJournalTimeOrDash(datetime t)
  {
   return (t>0) ? CCTJournalTimeStamp(t) : "-";
  }

string CCTAuditTimeOrDash(datetime t)
  {
   return (t>0) ? CCTLocalDateTime(ToNY(t),true,true) : "-";
  }

string CCTAuditHourOrDash(datetime t)
  {
   if(t<=0)
      return "--:--";
   MqlDateTime ny={};
   TimeToStruct(ToExecutionNY(t),ny);
   return StringFormat("%02d:00",ny.hour);
  }

string CCTAuditGlobalBELabel(const GenInfo &g,double entry,double tp)
  {
   if(!CCTRuntimeBEGlobalEnabled() || entry<=0.0 || tp<=0.0)
      return "-";

   double span=MathAbs(tp-entry);
   if(span<=_Point*0.1)
      return "-";

   double be=NormalizeDouble(entry + (g.bull ? 1.0 : -1.0)*(g_beMovePct/100.0)*span,_Digits);
   return DoubleToString(be,_Digits);
  }

string CCTGuardAuditLabel()
  {
   string daily=CCTEffectiveDailyLossGuard() ? (g_propGuardCacheReady ? StringFormat("%.2f/%.2f",g_propCachedLossUsed,g_propCachedLossCap) : "warming") : "off";
   string news=CCTEffectiveNewsFilter() ? ((g_propCachedEntryNewsBlocked || g_propCachedMgmtNewsBlocked) ? "blocked" : "clear") : "off";
   string weekend=Inp_WeekendGuard ? ((g_propCachedEntryWeekendBlocked || g_propCachedMgmtWeekendBlocked) ? "blocked" : "clear") : "off";
   string minTP=CCTEffectiveMinOpenTPEnabled() ? StringFormat("%d min",CCTEffectiveMinOpenMinutes()) : "off";
   return StringFormat("guards DL=%s | News=%s | Weekend=%s | MinTP=%s",daily,news,weekend,minTP);
  }

string CCTExecutionAudit(const GenInfo &g,int sibIdx,double entry,double sl,double tp,double lots,string reason,string comment)
  {
   string sibLine="sib=- | poi=-";
   string c1="-";
   string c2="-";
   string c3="-";
   if(sibIdx>=0 && sibIdx<g.nSibs)
     {
      sibLine=StringFormat("sib=%d | poi=%.5f",sibIdx+1,g.sibs[sibIdx].level);
      c1=CCTAuditTimeOrDash(g.sibs[sibIdx].c1Time);
      c2=CCTAuditTimeOrDash(g.sibs[sibIdx].c2Time);
      c3=CCTAuditTimeOrDash(g.sibs[sibIdx].c3Time);
     }

   return StringFormat("TZ NY | Hour %s | %s %s | gen=%s\nbirth=%s | AP=%s | %s\nC1=%s | C2=%s | C3=%s | entryTime=%s\nentry=%.5f | SL=%.5f | TP=%.5f | lots=%.2f | BE=%s\n%s\nreason=%s | comment=%s",
                       CCTAuditHourOrDash(g.triggerTime),
                       CCTJournalSide(g.bull),
                       ModelTypeLabel(g.modelType),
                       GenKey(g.bull,g.birthTime),
                       CCTAuditTimeOrDash(g.birthTime),
                       CCTAuditTimeOrDash(ActionPillarTime(g.birthTime)),
                       sibLine,
                       c1,
                       c2,
                       c3,
                       CCTAuditTimeOrDash((g.visualEntryTime>0) ? g.visualEntryTime : (g.triggerTime+(datetime)PeriodSeconds(LTF()))),
                       entry,
                       sl,
                       tp,
                       lots,
                       CCTAuditGlobalBELabel(g,entry,tp),
                       CCTGuardAuditLabel(),
                        reason,
                        comment);
  }

void CCTInitPropFirmState()
  {
   g_propInitialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   g_propDayOpen=CCTTodayStructuralOpen();
   g_propDayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   g_propDayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_propDailyBreached=false;
   g_propLastDailyJournal=0;
   g_propLastNewsJournal=0;
   g_propLastWeekendJournal=0;
   g_propLastVirtualTPJournal=0;
  }

void CCTRefreshPropFirmDay()
  {
   datetime dayOpen=CCTTodayStructuralOpen();
   if(dayOpen<=0)
      return;
   if(g_propDayOpen!=dayOpen)
     {
      g_propDayOpen=dayOpen;
      g_propDayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      g_propDayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_propDailyBreached=false;
      g_propLastDailyJournal=0;
      g_propLastNewsJournal=0;
      g_propLastWeekendJournal=0;
      g_propLastVirtualTPJournal=0;
      g_propGuardCacheReady=false;
      g_propGuardCacheTime=0;
     }
   if(g_propInitialBalance<=0.0)
      g_propInitialBalance=AccountInfoDouble(ACCOUNT_BALANCE);
  }

double CCTDailyLossReferenceBalance()
  {
   if(CCTEffectiveDailyLossBasis()==DAILY_LOSS_CUSTOM && CCTEffectiveDailyLossCustomBalance()>0.0)
      return CCTEffectiveDailyLossCustomBalance();
   if(CCTEffectiveDailyLossBasis()==DAILY_LOSS_NY_DAY_START && g_propDayStartEquity>0.0)
      return g_propDayStartEquity;
   if(g_propInitialBalance>0.0)
      return g_propInitialBalance;
   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

bool CCTDealMatchesPropScope(ulong deal,ENUM_CCT_PROP_SCOPE scope)
  {
   if(deal==0)
      return false;
   if(scope==PROP_SCOPE_ACCOUNT)
      return true;
   long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
   string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
   if(scope==PROP_SCOPE_EA_MAGIC)
      return (magic==CCTEffectiveMagic());
   return (symbol==_Symbol && magic==CCTEffectiveMagic());
  }

bool CCTPositionMatchesPropScope(ENUM_CCT_PROP_SCOPE scope,bool managedOnly)
  {
   string symbol=PositionGetString(POSITION_SYMBOL);
   long magic=PositionGetInteger(POSITION_MAGIC);
   if(managedOnly && magic!=CCTEffectiveMagic())
      return false;
   if(scope==PROP_SCOPE_ACCOUNT)
      return true;
   if(scope==PROP_SCOPE_EA_MAGIC)
      return (magic==CCTEffectiveMagic());
   return (symbol==_Symbol && (!managedOnly || magic==CCTEffectiveMagic()));
  }

double CCTDailyRealizedPnL(datetime dayStart,datetime dayEnd,ENUM_CCT_PROP_SCOPE scope)
  {
   if(dayStart<=0 || dayEnd<=dayStart || !HistorySelect(dayStart,dayEnd))
      return 0.0;
   double total=0.0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT)
         continue;
      if(!CCTDealMatchesPropScope(deal,scope))
         continue;
      total+=HistoryDealGetDouble(deal,DEAL_PROFIT)+
             HistoryDealGetDouble(deal,DEAL_SWAP)+
             HistoryDealGetDouble(deal,DEAL_COMMISSION)+
             HistoryDealGetDouble(deal,DEAL_FEE);
     }
   return total;
  }

double CCTFloatingPnL(ENUM_CCT_PROP_SCOPE scope)
  {
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(!CCTPositionMatchesPropScope(scope,false))
         continue;
      total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

double CCTOpenRiskCash(ENUM_CCT_PROP_SCOPE scope)
  {
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(!CCTPositionMatchesPropScope(scope,false))
         continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      long type=PositionGetInteger(POSITION_TYPE);
      bool bull=(type==POSITION_TYPE_BUY);
      double openPx=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double lots=PositionGetDouble(POSITION_VOLUME);
      if(openPx<=0.0 || sl<=0.0 || lots<=0.0)
         continue;
      double perLot=CCTCashLossPerLot(symbol,bull,openPx,sl);
      if(perLot>0.0)
         total+=perLot*lots;
     }
   return total;
  }

bool CCTDailyLossStats(double &pnl,double &lossUsed,double &cap,double &lossLeft)
  {
   pnl=0.0;
   lossUsed=0.0;
   cap=0.0;
   lossLeft=0.0;
   if(!CCTEffectiveDailyLossGuard())
      return false;

   CCTRefreshPropFirmDay();
   double basis=CCTDailyLossReferenceBalance();
   cap=basis*MathMax(0.0,CCTEffectiveDailyLossLimitPct())/100.0;
   if(cap<=0.0)
      return false;

   datetime dayStart=(g_propDayOpen>0) ? g_propDayOpen : CCTTodayStructuralOpen();
   datetime now=CurrentServerTime();
   pnl=CCTDailyRealizedPnL(dayStart,now+1,Inp_DailyLossScope)+CCTFloatingPnL(Inp_DailyLossScope);
   lossUsed=MathMax(0.0,-pnl);
   lossLeft=MathMax(0.0,cap-lossUsed);
   return (lossUsed+0.01>=cap);
  }

int CCTPropGuardCacheTTL()
  {
   return (bool)MQLInfoInteger(MQL_TESTER) ? 30 : 5;
  }

int CCTPropManagementCacheTTL()
  {
   return (bool)MQLInfoInteger(MQL_TESTER) ? 5 : 1;
  }

bool CCTPropGuardCacheFresh(int maxAgeSec=0)
  {
   if(maxAgeSec<=0)
      maxAgeSec=CCTPropGuardCacheTTL();
   datetime now=CurrentServerTime();
   return (g_propGuardCacheReady && g_propGuardCacheTime>0 && now>=g_propGuardCacheTime && now-g_propGuardCacheTime<=maxAgeSec);
  }

bool CCTCachedDailyLossStats(double &pnl,double &lossUsed,double &cap,double &lossLeft,bool &breached)
  {
   if(!CCTPropGuardCacheFresh())
     {
      breached=CCTDailyLossStats(pnl,lossUsed,cap,lossLeft);
      return CCTEffectiveDailyLossGuard();
     }
   pnl=g_propCachedPnl;
   lossUsed=g_propCachedLossUsed;
   cap=g_propCachedLossCap;
   lossLeft=g_propCachedLossLeft;
   breached=g_propCachedDailyBreached;
   return CCTEffectiveDailyLossGuard();
  }

bool CCTDailyLossEntryBlocked(bool bull,double entry,double sl,double lots,string &reason)
  {
   double pnl=0.0,lossUsed=0.0,cap=0.0,lossLeft=0.0;
   bool breached=false;
   CCTCachedDailyLossStats(pnl,lossUsed,cap,lossLeft,breached);
   if(breached)
     {
      reason=StringFormat("daily loss guard breached %.2f/%.2f",lossUsed,cap);
      g_propDailyBreached=true;
      return true;
     }

   if(!CCTEffectiveDailyLossGuard() || cap<=0.0)
      return false;

   double projected=0.0;
   if(entry>0.0 && sl>0.0 && lots>0.0)
      projected=CCTCashLossPerLot(_Symbol,bull,entry,sl)*lots;
   double openRisk=CCTOpenRiskCash(Inp_DailyLossScope);
   if(lossUsed+openRisk+projected+0.01>=cap)
     {
      reason=StringFormat("daily loss guard projected %.2f/%.2f",lossUsed+openRisk+projected,cap);
      return true;
     }
   return false;
  }

string CCTUpper(string value)
  {
   string out=value;
   StringToUpper(out);
   return out;
  }

bool CCTCurrencyMatchesList(const string currency,const string csv)
  {
   string cur=CCTUpper(TrimSpaces(currency));
   if(cur=="")
      return false;
   string parts[];
   int n=StringSplit(csv,',',parts);
   for(int i=0;i<n;i++)
     {
      string token=CCTUpper(TrimSpaces(parts[i]));
      if(token==cur)
         return true;
     }
   return false;
  }

string CCTRelevantNewsCurrencies()
  {
   string out="";
   string base=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE);
   string profit=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   if(base!="")
      out=base;
   if(profit!="" && !CCTCurrencyMatchesList(profit,out))
      out+=(out=="" ? "" : ",")+profit;

   string sym=CCTUpper(_Symbol);
   if(StringFind(sym,"XAU")>=0 || StringFind(sym,"XAG")>=0 ||
      StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
      StringFind(sym,"USTEC")>=0 || StringFind(sym,"NAS")>=0 ||
      StringFind(sym,"NQ")>=0 || StringFind(sym,"US30")>=0 ||
      StringFind(sym,"DJ")>=0 || StringFind(sym,"SPX")>=0 ||
      StringFind(sym,"US500")>=0)
     {
      if(!CCTCurrencyMatchesList("USD",out))
         out+=(out=="" ? "" : ",")+"USD";
     }

   string manual=Inp_NewsManualCurrencies;
   string parts[];
   int n=StringSplit(manual,',',parts);
   for(int i=0;i<n;i++)
     {
      string token=CCTUpper(TrimSpaces(parts[i]));
      if(token!="" && !CCTCurrencyMatchesList(token,out))
         out+=(out=="" ? "" : ",")+token;
     }
   return out;
  }

ENUM_CCT_NEWS_IMPACT CCTEffectiveNewsImpactFilter()
  {
   if(g_cctDashNewsImpactOverride>=0 && g_cctDashNewsImpactOverride<=2)
      return (ENUM_CCT_NEWS_IMPACT)g_cctDashNewsImpactOverride;

   return Inp_NewsImpactFilter;
  }

string CCTNewsImpactDashboardLabel()
  {
   ENUM_CCT_NEWS_IMPACT m=CCTEffectiveNewsImpactFilter();

   if(m==NEWS_IMPACT_HIGH)
      return "HIGH";
   if(m==NEWS_IMPACT_MED_HIGH)
      return "MED+HIGH";

   return "LOW+MED+HIGH";
  }

void CCTCycleNewsImpactDashboard()
  {
   int cur=(int)CCTEffectiveNewsImpactFilter();

   if(cur<0 || cur>2)
      cur=(int)Inp_NewsImpactFilter;

   cur++;
   if(cur>2)
      cur=0;

   g_cctDashNewsImpactOverride=cur;
   CCTWarmPropFirmSafetyCache(true,1);
  }
bool CCTNewsImpactAllowed(int importance)
  {
   if(CCTEffectiveNewsImpactFilter()==NEWS_IMPACT_ALL)
      return true;
   if(CCTEffectiveNewsImpactFilter()==NEWS_IMPACT_MED_HIGH)
      return (importance>=CALENDAR_IMPORTANCE_MODERATE);
   return (importance>=CALENDAR_IMPORTANCE_HIGH);
  }

datetime CCTNYLocalToServer(datetime nyLocal)
  {
   if(nyLocal<=0)
      return 0;
   int nyOffset=NYUTCOffsetSec(nyLocal+(datetime)(5*3600));
   datetime utc=nyLocal-nyOffset;
   return utc+ServerUTCOffsetSecForUTC(utc);
  }

bool CCTFindManualNews(datetime fromTime,datetime toTime,datetime &eventTime,string &eventLabel)
  {
   eventTime=0;
   eventLabel="";
   string src=Inp_NewsManualEvents;
   if(TrimSpaces(src)=="")
      return false;
   string currencies=CCTRelevantNewsCurrencies();
   string events[];
   int n=StringSplit(src,';',events);
   for(int i=0;i<n;i++)
     {
      string token=TrimSpaces(events[i]);
      if(StringLen(token)<16)
         continue;
      string dtText=StringSubstr(token,0,16);
      datetime nyLocal=StringToTime(dtText);
      datetime srv=CCTNYLocalToServer(nyLocal);
      if(srv<fromTime || srv>toTime)
         continue;
      string cur=CCTUpper(TrimSpaces(StringSubstr(token,16)));
      if(cur!="" && !CCTCurrencyMatchesList(cur,currencies))
         continue;
      if(eventTime==0 || srv<eventTime)
        {
         eventTime=srv;
         eventLabel=(cur!="" ? cur+" " : "")+"manual";
        }
     }
   return (eventTime>0);
  }

bool CCTFindCalendarNews(datetime fromTime,datetime toTime,datetime &eventTime,string &eventLabel)
  {
   eventTime=0;
   eventLabel="";
   string currencies=CCTRelevantNewsCurrencies();
   string parts[];
   int nCur=StringSplit(currencies,',',parts);
   for(int c=0;c<nCur;c++)
     {
      string cur=CCTUpper(TrimSpaces(parts[c]));
      if(cur=="")
         continue;
      MqlCalendarValue values[];
      int n=CalendarValueHistory(values,fromTime,toTime,"",cur);
      if(n<=0)
         continue;
      for(int i=0;i<n;i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id,ev))
            continue;
         if(!CCTNewsImpactAllowed((int)ev.importance))
            continue;
         datetime t=values[i].time;
         if(t<fromTime || t>toTime)
            continue;
         if(eventTime==0 || t<eventTime)
           {
            eventTime=t;
            eventLabel=cur+" "+ev.name;
           }
        }
     }
   return (eventTime>0);
  }

bool CCTFindRelevantNews(datetime fromTime,datetime toTime,datetime &eventTime,string &eventLabel)
  {
   eventTime=0;
   eventLabel="";
   datetime t1=0,t2=0;
   string l1="",l2="";
   bool m=CCTFindManualNews(fromTime,toTime,t1,l1);
   bool c=CCTFindCalendarNews(fromTime,toTime,t2,l2);
   if(m && (!c || t1<=t2))
     {
      eventTime=t1;
      eventLabel=l1;
      return true;
     }
   if(c)
     {
      eventTime=t2;
      eventLabel=l2;
      return true;
     }
   return false;
  }

double CCTNewsWindowSeconds()
  {
   double mins=MathMax(1.0,MathMin(30.0,CCTEffectiveNewsBlackoutMinutes()));
   return mins*60.0;
  }

bool CCTNewsBlackoutActive(bool forModification,string &reason)
  {
   reason="";
   if(!CCTEffectiveNewsFilter())
      return false;
   if(forModification && !CCTEffectiveNewsBlockModifications())
      return false;
   if(!forModification && !CCTEffectiveNewsBlockEntries())
      return false;

   datetime now=CurrentServerTime();
   int window=(int)MathRound(CCTNewsWindowSeconds());
   datetime eventTime=0;
   string label="";
   if(CCTFindRelevantNews(now-(datetime)window,now+(datetime)window,eventTime,label))
     {
      reason=StringFormat("news blackout %s at %s",label,CCTJournalTimeStamp(eventTime));
      return true;
     }
   return false;
  }

uint CCTNewsTextHash(const string text)
  {
   uint h=2166136261;
   int n=StringLen(text);

   for(int i=0;i<n;i++)
     {
      uint c=(uint)StringGetCharacter(text,i);
      h=(h^c)*16777619;
     }

   return h;
  }

string CCTNewsLatchKey(datetime eventTime,const string label,int bucket)
  {
   uint h=CCTNewsTextHash(label);
   string account=IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
   string t=IntegerToString((long)eventTime);
   string b=IntegerToString(bucket);
   string hs=IntegerToString((long)(h & 0x7FFFFFFF));

   return "CCT_NEWS_"+account+"_"+t+"_"+b+"_"+hs;
  }

bool CCTShouldJournalNewsAlert(datetime eventTime,const string label,int bucket)
  {
   string key=CCTNewsLatchKey(eventTime,label,bucket);

   if(GlobalVariableCheck(key))
      return false;

   GlobalVariableSet(key,(double)CurrentServerTime());
   return true;
  }

void CCTClearDashboardNewsState()
  {
   g_cctNewsDashLabel="";
   g_cctNewsDashTime=0;
   g_cctNewsDashMinutes=-1;
   g_cctNewsDashBucket=0;
   g_cctNewsDashLastSeen=0;
  }

void CCTMaybeJournalNewsAlert()
  {
   if(!CCTEffectiveNewsFilter())
     {
      CCTClearDashboardNewsState();
      return;
     }

   datetime now=CurrentServerTime();
   datetime eventTime=0;
   string label="";

   if(!CCTFindRelevantNews(now,now+(datetime)(15*60),eventTime,label))
     {
      CCTClearDashboardNewsState();
      return;
     }

   int secs=(int)(eventTime-now);
   if(secs<0)
      secs=0;

   int mins=(int)MathCeil((double)secs/60.0);
   int bucket=(secs<=(5*60)) ? 5 : 15;

   g_cctNewsDashLabel=label;
   g_cctNewsDashTime=eventTime;
   g_cctNewsDashMinutes=mins;
   g_cctNewsDashBucket=bucket;
   g_cctNewsDashLastSeen=now;

   if(!CCTShouldJournalNewsAlert(eventTime,label,bucket))
      return;

   PrintFormat("[CCT NEWS] %d-min alert | %s | event=%s",bucket,CCTJournalTimeStamp(eventTime),label);
   g_propLastNewsJournal=now;
  }

datetime CCTWeekendCutoffServer()
  {
   datetime nowSrv=CurrentServerTime();
   datetime nowNy=ToNY(nowSrv);
   MqlDateTime ny={};
   TimeToStruct(nowNy,ny);
   int daysToFriday=5-ny.day_of_week;
   datetime fridayNyMidnight=StructToTime(ny) - (datetime)(ny.hour*3600+ny.min*60+ny.sec) + (datetime)(daysToFriday*86400);
   datetime cutoffNy=fridayNyMidnight + (datetime)(MathMax(0,MathMin(23,Inp_WeekendFridayHour))*3600 + MathMax(0,MathMin(59,Inp_WeekendFridayMinute))*60);
   return CCTNYLocalToServer(cutoffNy);
  }

bool CCTWeekendGuardActive(bool forModification,string &reason)
  {
   reason="";
   if(!Inp_WeekendGuard)
      return false;
   if(forModification && !Inp_WeekendBlockModifications)
      return false;
   if(!forModification && !Inp_WeekendBlockEntries)
      return false;

   datetime now=CurrentServerTime();
   MqlDateTime ny={};
   TimeToStruct(ToNY(now),ny);
   if(ny.day_of_week==0 || ny.day_of_week==6)
     {
      reason="weekend guard active";
      return true;
     }
   if(ny.day_of_week==5)
     {
      datetime cutoff=CCTWeekendCutoffServer()-(datetime)(MathMax(0,Inp_WeekendCloseMinutesBefore)*60);
      if(now>=cutoff)
        {
         reason=StringFormat("weekend guard after %s",CCTJournalTimeStamp(cutoff));
         return true;
        }
     }
   return false;
  }
void CCTWarmPropFirmSafetyCache(bool force=false,int ttlOverride=0)
  {
   datetime now=CurrentServerTime();
   int ttl=(ttlOverride>0) ? ttlOverride : CCTPropGuardCacheTTL();
   if(!force && CCTPropGuardCacheFresh(ttl))
      return;

   CCTRefreshPropFirmDay();
   g_propCachedDailyBreached=CCTDailyLossStats(g_propCachedPnl,
                                               g_propCachedLossUsed,
                                               g_propCachedLossCap,
                                               g_propCachedLossLeft);

   g_propCachedEntryNewsReason="";
   g_propCachedMgmtNewsReason="";
   g_propCachedEntryWeekendReason="";
   g_propCachedMgmtWeekendReason="";
   g_propCachedEntryNewsBlocked=CCTNewsBlackoutActive(false,g_propCachedEntryNewsReason);
   g_propCachedMgmtNewsBlocked=CCTNewsBlackoutActive(true,g_propCachedMgmtNewsReason);
   g_propCachedEntryWeekendBlocked=CCTWeekendGuardActive(false,g_propCachedEntryWeekendReason);
   g_propCachedMgmtWeekendBlocked=CCTWeekendGuardActive(true,g_propCachedMgmtWeekendReason);
   g_propGuardCacheTime=now;
   g_propGuardCacheReady=true;
  }

bool CCTTradeManagementBlocked(string &reason)
  {
   reason="";
   int ttl=CCTPropManagementCacheTTL();
   if(!CCTPropGuardCacheFresh(ttl))
      CCTWarmPropFirmSafetyCache(false,ttl);

   double pnl=0.0,lossUsed=0.0,cap=0.0,left=0.0;
   bool breached=false;
   CCTCachedDailyLossStats(pnl,lossUsed,cap,left,breached);
   if(Inp_DailyLossBlockManagement && breached)
     {
      reason=StringFormat("daily loss guard breached %.2f/%.2f",lossUsed,cap);
      return true;
     }
   bool cacheFresh=CCTPropGuardCacheFresh(ttl);
   if(cacheFresh && g_propCachedMgmtNewsBlocked)
     {
      reason=g_propCachedMgmtNewsReason;
      return true;
     }
   if(!cacheFresh && CCTNewsBlackoutActive(true,reason))
      return true;
   cacheFresh=CCTPropGuardCacheFresh(ttl);
   if(cacheFresh && g_propCachedMgmtWeekendBlocked)
     {
      reason=g_propCachedMgmtWeekendReason;
      return true;
     }
   if(!cacheFresh && CCTWeekendGuardActive(true,reason))
      return true;
   return false;
  }

bool CCTEntryBlockedBySafety(const GenInfo &g,double entry,double sl,double lots,string &reason)
  {
   reason="";
   if(sl<=0.0 || entry<=0.0)
     {
      reason="prop exposure guard requires a valid SL before entry";
      return true;
     }
   double projected=CCTProjectedTradeExposureCash(_Symbol,g.bull,entry,sl,lots);
   double base=EffectiveAccountBase();
   if(Inp_MaxRiskPerIdeaPct>0.0 && base>0.0)
     {
      double cap=base*Inp_MaxRiskPerIdeaPct/100.0;
      double used=CCTOpenIdeaExposureCash(_Symbol,g.bull);
      if(used+projected>cap+0.01)
        {
         reason=StringFormat("risk-per-idea projected %.2f/%.2f",used+projected,cap);
         return true;
        }
     }
   if(Inp_MaxExposurePct>0.0 && base>0.0)
     {
      double cap=base*Inp_MaxExposurePct/100.0;
      double used=CCTAccountOpenExposureCash();
      if(used+projected>cap+0.01)
        {
         reason=StringFormat("account exposure projected %.2f/%.2f",used+projected,cap);
         return true;
        }
     }
   ENUM_CCT_ASSET_CLASS cls=CCTAssetClassForSymbol(_Symbol);
   double classCap=CCTConfiguredMaxLotsForClass(cls);
   if(classCap>0.0)
     {
      double classOpen=CCTOpenLotsByAssetClass(cls);
      if(classOpen+lots>classCap+1e-9)
        {
         reason=StringFormat("max lots projected for %s %.2f/%.2f",CCTAssetClassLabel(cls),classOpen+lots,classCap);
         return true;
        }
     }

   int ttl=CCTPropGuardCacheTTL();
   if(!CCTPropGuardCacheFresh(ttl))
      CCTWarmPropFirmSafetyCache(false,ttl);
   if(CCTDailyLossEntryBlocked(g.bull,entry,sl,lots,reason))
      return true;
   bool cacheFresh=CCTPropGuardCacheFresh(ttl);
   if(cacheFresh && g_propCachedEntryNewsBlocked)
     {
      reason=g_propCachedEntryNewsReason;
      return true;
     }
   if(!cacheFresh && CCTNewsBlackoutActive(false,reason))
      return true;
   cacheFresh=CCTPropGuardCacheFresh(ttl);
   if(cacheFresh && g_propCachedEntryWeekendBlocked)
     {
      reason=g_propCachedEntryWeekendReason;
      return true;
     }
   if(!cacheFresh && CCTWeekendGuardActive(false,reason))
      return true;
   return false;
  }

void CCTCloseManagedPositions(ENUM_CCT_PROP_SCOPE scope,const string reason)
  {
   CTrade trade;
   trade.SetExpertMagicNumber(CCTEffectiveMagic());
   trade.SetDeviationInPoints(MathMax(0,Inp_MaxDeviationPoints));
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(!CCTPositionMatchesPropScope(scope,true))
         continue;
      if(!trade.PositionClose(ticket))
        {
         datetime now=CurrentServerTime();
         if(now-g_propLastDailyJournal>=30)
           {
            PrintFormat("[CCT SAFETY CLOSE FAIL] pos=%I64u reason=%s retcode=%u err=%d",
                        ticket,reason,trade.ResultRetcode(),GetLastError());
            g_propLastDailyJournal=now;
           }
        }
      else
         PrintFormat("[CCT SAFETY CLOSE] pos=%I64u reason=%s",ticket,reason);
     }
  }

void CCTManageSafetyGuards()
  {
   static datetime s_lastManage=0;
   datetime now=CurrentServerTime();
   int cadence=(bool)MQLInfoInteger(MQL_TESTER) ? 5 : 1;
   if(s_lastManage>0 && now-s_lastManage<cadence)
      return;
   s_lastManage=now;

   CCTWarmPropFirmSafetyCache(false);
   CCTMaybeJournalNewsAlert();

   double pnl=0.0,lossUsed=0.0,cap=0.0,left=0.0;
   bool breached=false;
   CCTCachedDailyLossStats(pnl,lossUsed,cap,left,breached);
   if(breached)
     {
      if(!g_propDailyBreached || now-g_propLastDailyJournal>=60)
        {
         PrintFormat("[CCT DAILY LOSS GUARD] breached loss=%.2f cap=%.2f pnl=%.2f scope=%s",
                     lossUsed,cap,pnl,EnumToString(Inp_DailyLossScope));
         g_propLastDailyJournal=now;
        }
      g_propDailyBreached=true;
      if(Inp_DailyLossClosePositions)
         CCTCloseManagedPositions(Inp_DailyLossScope,"daily loss guard");
     }

   string weekendReason="";
   bool weekendActive=CCTPropGuardCacheFresh() ? g_propCachedEntryWeekendBlocked : CCTWeekendGuardActive(false,weekendReason);
   if(CCTPropGuardCacheFresh())
      weekendReason=g_propCachedEntryWeekendReason;
   if(Inp_WeekendClosePositions && weekendActive)
     {
      if(now-g_propLastWeekendJournal>=60)
        {
         PrintFormat("[CCT WEEKEND GUARD] %s",weekendReason);
         g_propLastWeekendJournal=now;
        }
      CCTCloseManagedPositions(Inp_WeekendScope,"weekend guard");
     }
  }

bool CCTTryGenKeyFromComment(string comment,string &genKey,bool &bull)
  {
   int bu=StringFind(comment,"BU_");
   int be=StringFind(comment,"BE_");
   int start=-1;
   if(bu>=0 && (be<0 || bu<be))
     {
      start=bu;
      bull=true;
     }
   else if(be>=0)
     {
      start=be;
      bull=false;
     }
   if(start<0)
      return false;

   int end=start;
   while(end<StringLen(comment))
     {
      ushort ch=StringGetCharacter(comment,end);
      bool valid=(ch=='_' || (ch>='0' && ch<='9') || (ch>='A' && ch<='Z'));
      if(!valid)
         break;
      end++;
     }

   string token=StringSubstr(comment,start,end-start);
   string payload=StringSubstr(token,3);
   bool legacyDigits=(StringLen(payload)>=9);
   for(int i=0;i<StringLen(payload);i++)
     {
      ushort ch=StringGetCharacter(payload,i);
      if(ch<'0' || ch>'9')
        {
         legacyDigits=false;
         break;
        }
     }

   if(legacyDigits)
     {
      datetime legacyBirth=(datetime)(long)StringToInteger(payload);
      if(legacyBirth>0)
         token=GenKey(bull,legacyBirth);
     }

   genKey=token;
   return (StringLen(genKey)>3);
  }

bool CCTHasOpenPositionForGenKey(const string genKey)
  {
   ulong knownPositionId=CCTKnownPositionIdForGenKey(genKey);
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=CCTEffectiveMagic())
         continue;
      string key="";
      bool bull=false;
      if(CCTTryGenKeyFromComment(PositionGetString(POSITION_COMMENT),key,bull) && key==genKey)
         return true;
      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(knownPositionId>0 && (knownPositionId==positionId || knownPositionId==ticket))
         return true;
     }
   return false;
  }

bool CCTHasHistoricalEntryForGenKey(const string genKey)
  {
   ulong knownPositionId=CCTKnownPositionIdForGenKey(genKey);
   datetime from=CCTStructuralDayOpenForTime(CurrentServerTime())-86400;
   if(!HistorySelect(from,CurrentServerTime()+86400))
      return false;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=CCTEffectiveMagic() || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)
         continue;
      string key="";
      bool bull=false;
      if(CCTTryGenKeyFromComment(HistoryDealGetString(deal,DEAL_COMMENT),key,bull) && key==genKey)
         return true;
      if(knownPositionId>0 && (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)==knownPositionId)
         return true;
     }
   return false;
  }

// CCT_LIVE_EXEC_KNOWN_REQUIRES_BROKER_TRUTH_V1
// Live duplicate-send blocking must be based on broker truth only.
// Visual-only, synthetic-only, and rejected-send diagnostics must not mark a fresh live trigger as broker-executed.
// CCT_PERSISTENT_TRADE_EXEC_AUDIT_V1
// Persistent execution audit. Writes to MQL5\Files and survives terminal shutdown.
string g_cctTradeExecAuditRuntimeKeys[];

string CCTTradeExecAuditFileName()
  {
   return StringFormat("CCT_trade_execution_audit_%I64d_%s.log",
                       (long)AccountInfoInteger(ACCOUNT_LOGIN),
                       _Symbol);
  }

string CCTTradeExecAuditTime(datetime t)
  {
   if(t<=0)
      return "-";
   return TimeToString(t,TIME_DATE|TIME_SECONDS);
  }

bool CCTTradeExecAuditRuntimeClaim(const string key)
  {
   int n=ArraySize(g_cctTradeExecAuditRuntimeKeys);
   for(int i=0;i<n;i++)
     {
      if(g_cctTradeExecAuditRuntimeKeys[i]==key)
         return false;
     }

   ArrayResize(g_cctTradeExecAuditRuntimeKeys,n+1);
   g_cctTradeExecAuditRuntimeKeys[n]=key;
   return true;
  }

string CCTTradeExecAuditPersistentKey(const string eventName,const string genKey,datetime eventTime)
  {
   // CCT_EXEC_AUDIT_PERSISTENT_DEDUP_V1
   // Compact cross-restart lock: the same account/symbol/event/generation/time should not
   // write repeated audit rows just because memory and disk were both inspected.
   string eventCode=eventName;
   if(eventName=="SYNTHETIC_OR_VISUAL_RECORD_NO_BROKER_TRIGGER")
      eventCode="NO_BRK";
   else if(eventName=="EXEC_ALREADY_KNOWN_BROKER_TRUTH_MEMORY" ||
           eventName=="EXEC_ALREADY_KNOWN_BROKER_TRUTH_DISK")
      eventCode="BRK_TRUTH";
   else if(eventName=="EXEC_ALREADY_KNOWN_OPEN_POSITION")
      eventCode="OPEN_POS";

   string key="CCT_AUD_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+
              _Symbol+"_"+eventCode+"_"+genKey+"_"+IntegerToString((long)eventTime);
   if(StringLen(key)>63)
      key=StringSubstr(key,0,63);
   return key;
  }

bool CCTTradeExecAuditPersistentClaim(const string eventName,const string genKey,datetime eventTime)
  {
   string key=CCTTradeExecAuditPersistentKey(eventName,genKey,eventTime);
   if(GlobalVariableCheck(key))
      return false;
   GlobalVariableSet(key,(double)CurrentServerTime());
   return true;
  }

void CCTTradeExecAuditLine(const string eventName,const string genKey,datetime eventTime,const string detail)
  {
   string fileName=CCTTradeExecAuditFileName();
   int handle=FileOpen(fileName,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);

   string line=StringFormat("%s | local=%s | account=%I64d | symbol=%s | period=%s | event=%s | gen=%s | eventTime=%s | %s",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                            TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
                            (long)AccountInfoInteger(ACCOUNT_LOGIN),
                            _Symbol,
                            EnumToString((ENUM_TIMEFRAMES)_Period),
                            eventName,
                            genKey,
                            CCTTradeExecAuditTime(eventTime),
                            detail);

   if(handle==INVALID_HANDLE)
     {
      int err=GetLastError();
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT TRADE AUDIT FILE ERROR] file=%s err=%d line=%s",fileName,err,line);
      return;
     }

   string duplicateToken=StringFormat("| event=%s | gen=%s | eventTime=%s |",
                                      eventName,
                                      genKey,
                                      CCTTradeExecAuditTime(eventTime));
   FileSeek(handle,0,SEEK_SET);
   while(!FileIsEnding(handle))
     {
      string existing=FileReadString(handle);
      if(StringFind(existing,duplicateToken)>=0)
        {
         FileClose(handle);
         return;
        }
     }

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT TRADE AUDIT] %s",line);

   FileSeek(handle,0,SEEK_END);
   FileWriteString(handle,line+"\r\n");
   FileClose(handle);
  }

void CCTTradeExecAuditOnce(const string eventName,const string genKey,datetime eventTime,const string detailKey,const string detail)
  {
   string key=eventName+"|"+genKey+"|"+IntegerToString((long)eventTime)+"|"+detailKey;
   if(!CCTTradeExecAuditRuntimeClaim(key))
      return;
   if(!CCTTradeExecAuditPersistentClaim(eventName,genKey,eventTime))
      return;
   CCTTradeExecAuditLine(eventName,genKey,eventTime,detail);
  }

string CCTTradeExecRecordAuditDetail(const ExecRecord &rec)
  {
   return StringFormat("recordTrigger=%s | ticket=%I64d | synthetic=%s | brokerFill=%.5f | execLots=%.2f | visualEntry=%.5f | outcome=%d",
                       CCTTradeExecAuditTime(rec.triggerBarTime),
                       (long)rec.ticket,
                       rec.isSynthetic ? "yes" : "no",
                       rec.brokerFill,
                       rec.execLots,
                       rec.visualEntry,
                       (int)rec.outcome);
  }

bool CCTExecRecordHasBrokerSendTruth(const ExecRecord &rec)
  {
   if(rec.triggerBarTime<=0)
      return false;

   if(rec.ticket>0)
      return true;

   if(rec.brokerFill>0.0 && rec.execLots>0.0)
      return true;

   if(!rec.isSynthetic && rec.brokerFill>0.0)
      return true;

   return false;
  }

bool CCTExecRecordBrokerTruthMatchesTrigger(const ExecRecord &rec,datetime triggerTime)
  {
   return (triggerTime>0 && rec.triggerBarTime==triggerTime && CCTExecRecordHasBrokerSendTruth(rec));
  }

bool CCTExecutionAlreadyKnown(const string genKey,datetime triggerTime)
  {
   // CCT_LIVE_EXEC_ALREADY_KNOWN_BROKER_TRUTH_ONLY_V2
   // In live mode, only confirmed broker truth may block a fresh broker send.
   // This version also writes a persistent audit when a visual/synthetic record exists without broker-send truth.
   if(!(bool)MQLInfoInteger(MQL_TESTER))
     {
      if(CCTHasOpenPositionForGenKey(genKey))
        {
         CCTTradeExecAuditOnce("EXEC_ALREADY_KNOWN_OPEN_POSITION",genKey,triggerTime,"open_position","open broker position exists for generation");
         return true;
        }

      int idx=CCTFindExecRecord(genKey);
      if(idx>=0)
        {
         if(CCTExecRecordBrokerTruthMatchesTrigger(g_execRecords[idx],triggerTime))
           {
            CCTTradeExecAuditOnce("EXEC_ALREADY_KNOWN_BROKER_TRUTH_MEMORY",genKey,triggerTime,"memory_broker_truth",CCTTradeExecRecordAuditDetail(g_execRecords[idx]));
            return true;
           }

         if(CCTExecRecordMatchesTrigger(g_execRecords[idx],triggerTime) && !CCTExecRecordHasBrokerSendTruth(g_execRecords[idx]))
           {
            CCTTradeExecAuditOnce("SYNTHETIC_OR_VISUAL_RECORD_NO_BROKER_TRIGGER",genKey,triggerTime,"memory_no_broker",CCTTradeExecRecordAuditDetail(g_execRecords[idx]));
           }
        }

      ExecRecord rec;
      if(CCTLoadExecRecord(genKey,rec))
        {
         if(CCTExecRecordBrokerTruthMatchesTrigger(rec,triggerTime))
           {
            CCTTradeExecAuditOnce("EXEC_ALREADY_KNOWN_BROKER_TRUTH_DISK",genKey,triggerTime,"disk_broker_truth",CCTTradeExecRecordAuditDetail(rec));
            return true;
           }

         if(CCTExecRecordMatchesTrigger(rec,triggerTime) && !CCTExecRecordHasBrokerSendTruth(rec))
           {
            CCTTradeExecAuditOnce("SYNTHETIC_OR_VISUAL_RECORD_NO_BROKER_TRIGGER",genKey,triggerTime,"disk_no_broker",CCTTradeExecRecordAuditDetail(rec));
           }
        }

      return false;
     }

   // Tester/replay behavior remains unchanged: rejected attempts, synthetic replay records,
   // and historical broker entries still prevent duplicate tester entries across rebuilds.
   if(CCTRejectedExecKnown(genKey,triggerTime))
      return true;

   int idx=CCTFindExecRecord(genKey);
   if(idx>=0)
     {
      if(CCTExecRecordConsumesGeneration(g_execRecords[idx]))
         return true;
      if(CCTExecRecordMatchesTrigger(g_execRecords[idx],triggerTime))
         return true;
     }

   ExecRecord rec;
   if(CCTLoadExecRecord(genKey,rec))
     {
      if(CCTExecRecordConsumesGeneration(rec))
         return true;
      if(CCTExecRecordMatchesTrigger(rec,triggerTime))
         return true;
     }

   if(CCTHasOpenPositionForGenKey(genKey))
      return true;

   if((bool)MQLInfoInteger(MQL_TESTER))
      return CCTHasHistoricalEntryForGenKey(genKey);

   return false;
  }

/*
Purpose: Recover the maximum favorable progress since broker entry for NY CO BE gating.
Constitution: The CO BE minimum progress threshold is based on MFE reached before the CO retrace, not the current CO-touch price.
Inputs: bull - trade direction, fromTime - broker entry time, entry - broker fill, tp - broker target, curPx - current bid/ask.
Outputs: Maximum favorable progress as percent of entry-to-TP distance.
*/
double CCTMaxProgressSinceEntry(bool bull,datetime fromTime,double entry,double tp,double curPx)
  {
   double span=MathAbs(tp-entry);
   if(span<=_Point)
      return 0.0;

   double maxFavorable=bull ? (curPx-entry) : (entry-curPx);
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=0;
   if(fromTime>0)
      copied=CopyRates(_Symbol,LTF(),fromTime,CurrentServerTime(),rates);
   for(int i=0;i<copied;i++)
     {
      double favorable=bull ? (rates[i].high-entry) : (entry-rates[i].low);
      if(favorable>maxFavorable)
         maxFavorable=favorable;
     }

   if(maxFavorable<=0.0)
      return 0.0;
   return 100.0*maxFavorable/span;
  }

datetime CCTFindBrokerBELeftAnchor(datetime fromTime,datetime toTime,double bePrice)
  {
   if(fromTime<=0 || toTime<=0 || toTime<fromTime || bePrice<=0.0)
      return toTime;

   MqlRates ltf[];
   ArraySetAsSeries(ltf,false);
   int copied=CopyRates(_Symbol,LTF(),fromTime,toTime,ltf);
   if(copied<=0)
      return toTime;

   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0)
      tick=_Point;
   double tol=MathMax(_Point,tick)*2.0;

   datetime anchor=0;
   for(int i=copied-1;i>=0;i--)
     {
      if(ltf[i].time<fromTime || ltf[i].time>toTime)
         continue;

      if(bePrice>=ltf[i].low-tol && bePrice<=ltf[i].high+tol)
        {
         anchor=ltf[i].time;
         break;
        }
     }

   return (anchor>0) ? anchor : toTime;
  }



bool CCTManageVirtualTP(int idx,
                        ulong ticket,
                        bool bull,
                        datetime posOpen,
                        double curSL,
                        double brokerTP,
                        double targetTP,
                        double curPx,
                        CTrade &trade,
                        bool managementBlocked,
                        const string blockReason)
  {
   if(idx<0 || idx>=g_nExecRecords || !g_execRecords[idx].virtualTPActive || targetTP<=0.0)
      return false;

   datetime now=CurrentServerTime();
   int minSec=MathMax(0,CCTEffectiveMinOpenMinutes())*60;
   bool matured=(minSec<=0 || (posOpen>0 && now-posOpen>=minSec));
   bool tpHit=bull ? (curPx>=targetTP) : (curPx<=targetTP);

   if(tpHit && !g_execRecords[idx].virtualTPTouched)
     {
      g_execRecords[idx].virtualTPTouched=true;
      g_execRecords[idx].virtualTPTouchTime=now;
      CCTPersistExecRecord(g_execRecords[idx]);
      if(!matured && CCTLifecycleJournalEnabled())
         PrintFormat("[CCT VIRTUAL TP DELAY] %s | touch=%s | minOpen=%d min",
                     g_execRecords[idx].genKey,CCTJournalTimeStamp(now),CCTEffectiveMinOpenMinutes());
     }

   if(!matured)
      return false;

   if(managementBlocked)
     {
      if((tpHit || g_execRecords[idx].virtualTPTouched) && now-g_propLastVirtualTPJournal>=30)
        {
         PrintFormat("[CCT VIRTUAL TP BLOCK] %s | %s",g_execRecords[idx].genKey,blockReason);
         g_propLastVirtualTPJournal=now;
        }
      return false;
     }

   if(tpHit || g_execRecords[idx].virtualTPTouched)
     {
      if(trade.PositionClose(ticket))
        {
         PrintFormat("[CCT VIRTUAL TP CLOSE] %s | target=%.5f | price=%.5f | minOpen=%d min",
                     g_execRecords[idx].genKey,targetTP,curPx,CCTEffectiveMinOpenMinutes());
         return true;
        }
      if(now-g_propLastVirtualTPJournal>=30)
        {
         PrintFormat("[CCT VIRTUAL TP CLOSE FAIL] %s | retcode=%u err=%d",
                     g_execRecords[idx].genKey,trade.ResultRetcode(),GetLastError());
         g_propLastVirtualTPJournal=now;
        }
      return false;
     }

   if(brokerTP<=0.0 && targetTP>0.0)
     {
      if(trade.PositionModify(ticket,curSL,targetTP))
        {
         g_execRecords[idx].virtualTPActive=false;
         CCTPersistExecRecord(g_execRecords[idx]);
         if(CCTLifecycleJournalEnabled())
            PrintFormat("[CCT VIRTUAL TP ARMED BROKER] %s | TP=%.5f | minOpen=%d min",
                        g_execRecords[idx].genKey,targetTP,CCTEffectiveMinOpenMinutes());
         return true;
        }
      else if(now-g_propLastVirtualTPJournal>=30)
        {
         PrintFormat("[CCT VIRTUAL TP ARM FAIL] %s | retcode=%u err=%d",
                     g_execRecords[idx].genKey,trade.ResultRetcode(),GetLastError());
         g_propLastVirtualTPJournal=now;
        }
     }

   return false;
  }

/*
Purpose: Throttle repeated stale-replay execution skip debug rows.
Constitution: Historical/pre-init triggers may be reconstructed for visuals/records, but must not spam logs or broker-execute repeatedly.
Inputs: genKey - generation key, triggerTime - historical trigger time.
Outputs: True once per generation/trigger per EA session when debug logging is enabled.
*/
bool CCTStaleReplayExecSkipShouldPrint(const string genKey,const datetime triggerTime)
  {
   // CCT_STALE_REPLAY_EXEC_SKIP_THROTTLE_V1
   if(!CCTDebugEnabled())
      return false;

   static string printedKeys[];
   static int printedCount=0;

   string key=genKey+"|"+IntegerToString((long)triggerTime);

   for(int i=0;i<printedCount;i++)
     {
      if(printedKeys[i]==key)
         return false;
     }

   if(printedCount>=1024)
     {
      ArrayResize(printedKeys,0);
      printedCount=0;
     }

   ArrayResize(printedKeys,printedCount+1);
   printedKeys[printedCount]=key;
   printedCount++;

   return true;
  }


bool CCTExecGateDebugShouldPrint(const string key)
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

string CCTExecGateTimeLabel(datetime t)
  {
   if(t<=0)
      return "-";
   return TimeToString(ToNY(t),TIME_DATE|TIME_SECONDS);
  }

void CCTExecGateDebug(const string gate,const string genKey,datetime triggerTime,datetime freshTriggerTime,const string detail="")
  {
   // CCT_EXEC_GATE_DEBUG_V3
   // Debug-only execution skip telemetry. No behavior change; no sleeps; no screenshots; no WebRequest.
   if(!CCTDebugEnabled())
      return;

   string key=gate+"|"+genKey+"|"+IntegerToString((long)triggerTime)+"|"+IntegerToString((long)freshTriggerTime)+"|"+detail;
   if(!CCTExecGateDebugShouldPrint(key))
      return;

   CCTJournalLine(StringFormat("[CCT EXEC GATE] gen=%s | trigger=%s | fresh=%s | gate=%s | detail=%s",
                               genKey,
                               CCTExecGateTimeLabel(triggerTime),
                               CCTExecGateTimeLabel(freshTriggerTime),
                               gate,
                               detail));
  }
/*
Purpose: Place the broker market order for a freshly confirmed generation trigger.
Constitution: Market orders only, immediate trigger, spread-widened SL, TP from locked RR and final broker risk distance.
Inputs: g - triggered generation, freshTriggerTime - last closed LTF trigger time eligible for live sending.
Outputs: Broker order sent once per generation or skipped with debug log.
*/
void CCTTryExecuteGeneration(const GenInfo &g,datetime freshTriggerTime)
  {
   string genKey=GenKey(g.bull,g.birthTime);

   if(Inp_BrokerExecution!=BROKER_EXEC_ON)
     {
      CCTExecGateDebug("broker_off",genKey,g.triggerTime,freshTriggerTime,"Inp_BrokerExecution!=BROKER_EXEC_ON");
      return;
     }
   if(freshTriggerTime<=0 || g.triggerTime<=0)
     {
      CCTExecGateDebug("invalid_trigger_time",genKey,g.triggerTime,freshTriggerTime,"freshTriggerTime<=0 || triggerTime<=0");
      return;
     }

   if(CCTExecutionAlreadyKnown(genKey,g.triggerTime))
     {
      CCTExecGateDebug("already_known",genKey,g.triggerTime,freshTriggerTime,"CCTExecutionAlreadyKnown=true");
      return;
     }

   if(g.triggerTime!=freshTriggerTime)
     {
      CCTExecGateDebug("stale_replay",genKey,g.triggerTime,freshTriggerTime,"triggerTime!=freshTriggerTime");
      if(CCTStaleReplayExecSkipShouldPrint(genKey,g.triggerTime))
         CCTJournalLine(StringFormat("[CCT DBG] EXEC SKIP | %s | trigger=%s fresh=%s | reason=stale replay trigger",
                                     genKey,
                                     TimeToString(ToNY(g.triggerTime),TIME_DATE|TIME_MINUTES),
                                     TimeToString(ToNY(freshTriggerTime),TIME_DATE|TIME_MINUTES)));
      return;
     }
   if(g.activeSibIdx<0 || g.activeSibIdx>=g.nSibs)
     {
      CCTExecGateDebug("invalid_active_sibling",genKey,g.triggerTime,freshTriggerTime,StringFormat("activeIdx=%d nSibs=%d",g.activeSibIdx,g.nSibs));
      if(CCTDebugEnabled() && EventIsCurrentLTF(g.triggerTime))
         CCTJournalLine(StringFormat("[CCT DBG] EXEC SKIP | %s | trigger=%s | activeIdx=%d nSibs=%d | reason=invalid active sibling",
                                     GenKey(g.bull,g.birthTime),
                                     TimeToString(ToNY(g.triggerTime),TIME_DATE|TIME_MINUTES),
                                     g.activeSibIdx,
                                     g.nSibs));
      return;
     }
   if(g.sibs[g.activeSibIdx].state!=SS_TRIGGERED)
     {
      CCTExecGateDebug("active_sibling_not_triggered",genKey,g.triggerTime,freshTriggerTime,EnumToString(g.sibs[g.activeSibIdx].state));
      if(CCTDebugEnabled() && EventIsCurrentLTF(g.triggerTime))
         CCTJournalLine(StringFormat("[CCT DBG] EXEC SKIP | %s | trigger=%s | state=%s | reason=active sibling not triggered",
                                     GenKey(g.bull,g.birthTime),
                                     TimeToString(ToNY(g.triggerTime),TIME_DATE|TIME_MINUTES),
                                     EnumToString(g.sibs[g.activeSibIdx].state)));
      return;
     }

   datetime c1Time=g.sibs[g.activeSibIdx].c1Time;
   bool brokerAuthorizedC1=(g.sibs[g.activeSibIdx].authorityRoute!=AUTH_ROUTE_NONE &&
                            g.sibs[g.activeSibIdx].authorityRoute!=AUTH_ROUTE_RECORD_ONLY &&
                            !g.sibs[g.activeSibIdx].authorityRecordOnly);
   if(!g.sibs[g.activeSibIdx].hadAuthorizedC1 ||
      c1Time<=0 ||
      !brokerAuthorizedC1)
       {
       CCTExecGateDebug("unauthorized_c1",genKey,g.triggerTime,freshTriggerTime,StringFormat("hadAuth=%s route=%d recOnly=%s c1=%s",g.sibs[g.activeSibIdx].hadAuthorizedC1 ? "yes" : "no",(int)g.sibs[g.activeSibIdx].authorityRoute,g.sibs[g.activeSibIdx].authorityRecordOnly ? "yes" : "no",c1Time>0 ? TimeToString(ToNY(c1Time),TIME_DATE|TIME_MINUTES) : "-"));
      if(CCTDebugEnabled() && EventIsCurrentLTF(g.triggerTime))
         CCTJournalLine(StringFormat("[CCT DBG] EXEC SKIP | %s | trigger=%s | hadAuth=%s route=%d recOnly=%s c1=%s | reason=unauthorized C1",
                                     genKey,
                                     TimeToString(ToNY(g.triggerTime),TIME_DATE|TIME_MINUTES),
                                     g.sibs[g.activeSibIdx].hadAuthorizedC1 ? "yes" : "no",
                                     (int)g.sibs[g.activeSibIdx].authorityRoute,
                                     g.sibs[g.activeSibIdx].authorityRecordOnly ? "yes" : "no",
                                     c1Time>0 ? TimeToString(ToNY(c1Time),TIME_DATE|TIME_MINUTES) : "-"));
      if(CCTLifecycleJournalEnabled())
         PrintFormat("[CCT TRIGGER REJECT]\n%s",
                     CCTExecutionAudit(g,g.activeSibIdx,0.0,0.0,0.0,0.0,"unauthorized C1 execution hour","-"));
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0.0 || tick.ask<=0.0)
     {
      CCTExecGateDebug("invalid_tick",genKey,g.triggerTime,freshTriggerTime,"SymbolInfoTick failed or bid/ask<=0");
      return;
     }

   double quoteEntry=g.bull ? tick.ask : tick.bid;
   double spread=NormalizeDouble((g.triggerSpread>0.0) ? g.triggerSpread : (tick.ask-tick.bid),_Digits);
   double entry=NormalizeDouble((g.visualEntry>0.0) ? g.visualEntry : quoteEntry,_Digits);
   double sl=NormalizeDouble((g.rawSL>0.0) ? g.rawSL : ((g.fibRawSL>0.0) ? g.fibRawSL : 0.0),_Digits);
   double tp=NormalizeDouble((g.rawTP>0.0) ? g.rawTP : CalcTPRaw(g.bull,entry,sl,g.coPrice,g.lockedRR,Inp_UseCOTP),_Digits);
   if(entry<=0.0 || quoteEntry<=0.0 || sl<=0.0 || tp<=0.0 || MathAbs(entry-sl)<=_Point*0.1)
     {
      CCTExecGateDebug("invalid_geometry",genKey,g.triggerTime,freshTriggerTime,StringFormat("entry=%.5f quote=%.5f sl=%.5f tp=%.5f",entry,quoteEntry,sl,tp));
      return;
     }

   double maxSlipPx=MathMax(0,Inp_MaxDeviationPoints)*_Point;
   double adverseSlipPx=g.bull ? (quoteEntry-entry) : (entry-quoteEntry);
   if(adverseSlipPx>maxSlipPx+_Point*0.1)
     {
      CCTExecGateDebug("slippage_guard",genKey,g.triggerTime,freshTriggerTime,StringFormat("entry=%.5f quote=%.5f adverse=%.5f max=%.5f",entry,quoteEntry,adverseSlipPx,maxSlipPx));
      if(CCTLifecycleJournalEnabled())
         PrintFormat("[CCT ORDER SKIP]\n%s",
                     CCTExecutionAudit(g,g.activeSibIdx,quoteEntry,sl,tp,0.0,
                                       "current quote exceeded locked-entry slippage guard","-"));
      return;
     }

   double sizingEntry=quoteEntry; // CCT RISK FIX: size from executable Bid/Ask quote, not visual/synthetic entry.

   double sizingRiskCash=EffectiveAccountBase()*(g_riskPct/100.0);
   double sizingPerLot=CCTCashLossPerLot(_Symbol,g.bull,sizingEntry,sl);
   double desiredLots=(sizingRiskCash>0.0 && sizingPerLot>0.0) ? sizingRiskCash/sizingPerLot : 0.0;
   string marginFitReason="";
   double rawRiskLots=CCTLotsForRisk(_Symbol,g.bull,sizingEntry,sl);
   double lotsAfterMargin=CCTFitLotsToMargin(_Symbol,g.bull,sizingEntry,rawRiskLots,marginFitReason);
   double lotsAfterRiskCap=CCTClampLotsToRiskCap(_Symbol,g.bull,sizingEntry,sl,lotsAfterMargin);
   string propCapReason="";
   double lots=CCTClampLotsToPropCaps(_Symbol,g.bull,sizingEntry,sl,lotsAfterRiskCap,propCapReason);
   if(lots<=0.0)
     {
      CCTExecGateDebug("lots_zero",genKey,g.triggerTime,freshTriggerTime,propCapReason!="" ? propCapReason : marginFitReason);
      if(StringFind(marginFitReason,"NO_MONEY_LOCAL_SKIP")>=0)
         CCTRememberRejectedExec(genKey,g.triggerTime);

      if(CCTLifecycleJournalEnabled())
        {
         CCTJournalLine(CCTRiskSizingAuditLine(_Symbol,g.bull,sizingEntry,sl,
                                               sizingRiskCash,sizingPerLot,desiredLots,rawRiskLots,
                                               lotsAfterMargin,lotsAfterRiskCap,lots,
                                               marginFitReason,propCapReason));
         PrintFormat("[CCT ORDER SKIP]\n%s",
                     CCTExecutionAudit(g,g.activeSibIdx,entry,sl,tp,0.0,
                                       propCapReason!="" ? propCapReason : (marginFitReason!="" ? marginFitReason : "lots unavailable or would exceed risk/lot/exposure cap"),
                                       "-"));
        }
      return;
     }

   string safetyReason="";
   if(CCTEntryBlockedBySafety(g,entry,sl,lots,safetyReason))
     {
      CCTExecGateDebug("safety_block",genKey,g.triggerTime,freshTriggerTime,safetyReason);
      CCTTradeExecAuditOnce("BROKER_SEND_BLOCKED",genKey,g.triggerTime,"safety_block",
                            CCTExecutionAudit(g,g.activeSibIdx,entry,sl,tp,lots,safetyReason,"-"));
      if(CCTLifecycleJournalEnabled())
         PrintFormat("[CCT ORDER BLOCK]\n%s",
                     CCTExecutionAudit(g,g.activeSibIdx,entry,sl,tp,lots,safetyReason,"-"));
      return;
     }

   CTrade trade;
   trade.SetExpertMagicNumber(CCTEffectiveMagic());
   trade.SetDeviationInPoints(MathMax(0,Inp_MaxDeviationPoints));
   trade.SetTypeFillingBySymbol(_Symbol);

   string comment=CCTBuildTradeComment(c1Time,g.modelType,genKey);
   bool useVirtualTP=(CCTEffectiveMinOpenTPEnabled() && CCTEffectiveMinOpenMinutes()>0);
   double orderTP=useVirtualTP ? 0.0 : tp;
   int pendingIdx=CCTAddPendingExecLink(genKey,g.bull);
   ResetLastError();
   ulong orderStartUs=GetMicrosecondCount();
   double sendPrice=0.0; // Market order: let MT5 use current Ask/Bid instead of stale visual entry.
   bool ok=g.bull ? trade.Buy(lots,_Symbol,sendPrice,sl,orderTP,comment)
                  : trade.Sell(lots,_Symbol,sendPrice,sl,orderTP,comment);
   ulong orderElapsedUs=GetMicrosecondCount()-orderStartUs;
   int orderErr=GetLastError();

   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0)
      ltfSec=60;
   datetime c3CloseTime=g.triggerTime+(datetime)ltfSec-1;
   long c3ToPulseSec=(g_cctExecPulseSeenServer>0 && c3CloseTime>0) ? (long)(g_cctExecPulseSeenServer-c3CloseTime) : 0;
   CCTTradeExecAuditLine("TRIGGER_TO_BROKER_SEND_TIMING",
                         genKey,
                         g.triggerTime,
                         StringFormat("c3Close=%s | pulseSeenLtf=%s | pulseSeenServer=%s | pulseSource=%s | c3ToPulseSec=%d | scanStartUs=%s | scanEndUs=%s | orderStartUs=%s | orderElapsedUs=%s | retcode=%u | err=%d | resultPx=%.5f | lots=%.2f | entry=%.5f | sl=%.5f | tp=%.5f",
                                      CCTTradeExecAuditTime(c3CloseTime),
                                      CCTTradeExecAuditTime(g_cctExecPulseSeenLtf),
                                      CCTTradeExecAuditTime(g_cctExecPulseSeenServer),
                                      g_cctExecPulseSource,
                                      (int)c3ToPulseSec,
                                      IntegerToString((long)g_cctExecPulseScanStartUs),
                                      IntegerToString((long)g_cctExecPulseScanEndUs),
                                      IntegerToString((long)orderStartUs),
                                      IntegerToString((long)orderElapsedUs),
                                      trade.ResultRetcode(),
                                      orderErr,
                                      trade.ResultPrice(),
                                      lots,
                                      entry,
                                      sl,
                                      tp));

   if(CCTLifecycleJournalEnabled())
      CCTJournalLine(StringFormat("[CCT ORDER TIMING] %s | dir=%s | elapsed_us=%s | retcode=%u | err=%d | reqPx=mkt | resultPx=%.5f",
                                  genKey,
                                  g.bull ? "BUY" : "SELL",
                                  IntegerToString((long)orderElapsedUs),
                                  trade.ResultRetcode(),
                                  orderErr,
                                  trade.ResultPrice()));
   if(ok)
      CCTUpdatePendingExecOrder(pendingIdx,trade.ResultOrder(),genKey);
   else
     {
      CCTRemovePendingExecLinkByIndex(pendingIdx);
      CCTRememberRejectedExec(genKey,g.triggerTime);
      CCTExecGateDebug("broker_rejected",genKey,g.triggerTime,freshTriggerTime,StringFormat("retcode=%u err=%d",trade.ResultRetcode(),GetLastError()));
      CCTTradeExecAuditOnce("BROKER_SEND_REJECTED",genKey,g.triggerTime,"retcode",
                            StringFormat("retcode=%u | err=%d | lots=%.2f | entry=%.5f | sl=%.5f | tp=%.5f | comment=%s",
                                         trade.ResultRetcode(),GetLastError(),lots,entry,sl,tp,comment));

      CCTJournalLine(StringFormat("[CCT ORDER FAIL] retcode=%u err=%d\n%s",
                                  trade.ResultRetcode(),GetLastError(),
                                  CCTExecutionAudit(g,g.activeSibIdx,entry,sl,tp,lots,"broker rejected order; no execution record created",comment)));

      if(CCTDebugEnabled())
         CCTJournalLine(StringFormat("[CCT EXEC] send failed %s retcode=%u err=%d entry=%.5f sl=%.5f tp=%.5f",
                                     genKey,trade.ResultRetcode(),GetLastError(),entry,sl,tp));
      return;
     }

   int idx=CCTEnsureExecRecord(genKey);
   g_execRecords[idx].genKey=genKey;
   g_execRecords[idx].bull=g.bull;
   g_execRecords[idx].triggerBarTime=g.triggerTime;
   g_execRecords[idx].visualEntry=entry;
   g_execRecords[idx].triggerSpread=spread;
   g_execRecords[idx].brokerFill=trade.ResultPrice();
   if(g_execRecords[idx].brokerFill<=0.0)
      g_execRecords[idx].brokerFill=quoteEntry;
   g_execRecords[idx].brokerSL=sl;
   g_execRecords[idx].brokerTP=tp;

   if(CCTLifecycleJournalEnabled())
     {
      double targetRiskCash=EffectiveAccountBase()*(g_riskPct/100.0);
      double plannedRiskCash=CCTCashLossPerLot(_Symbol,g.bull,sizingEntry,sl)*lots;
      double fillRiskCash=CCTCashLossPerLot(_Symbol,g.bull,g_execRecords[idx].brokerFill,sl)*lots;

      CCTJournalLine(StringFormat("[CCT RISK AUDIT] %s | target=%.2f | lots=%.2f | sizingEntry=%.5f | quoteEntry=%.5f | brokerFill=%.5f | SL=%.5f | plannedRisk=%.2f | fillRiskAtSL=%.2f | spread=%.5f",
                                  genKey,
                                  targetRiskCash,
                                  lots,
                                  sizingEntry,
                                  quoteEntry,
                                  g_execRecords[idx].brokerFill,
                                  sl,
                                  plannedRiskCash,
                                  fillRiskCash,
                                  spread));
      CCTJournalLine(CCTRiskSizingAuditLine(_Symbol,g.bull,sizingEntry,sl,
                                            sizingRiskCash,sizingPerLot,desiredLots,rawRiskLots,
                                            lotsAfterMargin,lotsAfterRiskCap,lots,
                                            marginFitReason,propCapReason));
      CCTJournalLine(StringFormat("[CCT PROP AUDIT] %s | %s",
                                  genKey,
                                  CCTPropCapAudit(_Symbol,g.bull,sizingEntry,sl,lots)));
     }
   g_execRecords[idx].coPrice=g.coPrice;
   g_execRecords[idx].anchorA=g.anchorA;
   g_execRecords[idx].anchorATime=g.anchorATime;
   g_execRecords[idx].anchorB=g.anchorB;
   g_execRecords[idx].anchorBTime=g.anchorBTime;
   g_execRecords[idx].rawSL=(g.fibRawSL>0.0) ? g.fibRawSL : sl;
   g_execRecords[idx].lockedRR=g.lockedRR;
   g_execRecords[idx].slBranch=g.slBranch;
   g_execRecords[idx].modelType=CCTModelTypeForSweepTruth(g.modelType,g.sweepCount,g.tsPostBirthSweepCount);
   g_execRecords[idx].sweepCount=g.sweepCount;
   g_execRecords[idx].execLots=lots;
   g_execRecords[idx].sibIndex=g.activeSibIdx;
   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs)
     {
      g_execRecords[idx].c1Time=g.sibs[g.activeSibIdx].c1Time;
      g_execRecords[idx].c2Time=g.sibs[g.activeSibIdx].c2Time;
      g_execRecords[idx].c3Time=g.sibs[g.activeSibIdx].c3Time;
     }
   g_execRecords[idx].beApplied=false;
   g_execRecords[idx].beGeneralApplied=false;
   g_execRecords[idx].beCoApplied=false;
   g_execRecords[idx].bePrice=0.0;
   g_execRecords[idx].beTime=0;
   g_execRecords[idx].beLeftAnchorTime=0;
   g_execRecords[idx].beGeneralPrice=0.0;
   g_execRecords[idx].beGeneralTime=0;
   g_execRecords[idx].beGeneralLeftAnchorTime=0;
   g_execRecords[idx].beCoPrice=0.0;
   g_execRecords[idx].beCoTime=0;
   g_execRecords[idx].beCoLeftAnchorTime=0;
   g_execRecords[idx].maxProgressPct=0.0;
   g_execRecords[idx].coTouched=false;
   g_execRecords[idx].coTouchTime=0;
   g_execRecords[idx].virtualTPActive=useVirtualTP;
   g_execRecords[idx].virtualTPTouched=false;
   g_execRecords[idx].virtualTPTouchTime=0;
   g_execRecords[idx].outcome=SS_TRIGGERED;
   g_execRecords[idx].ticket=trade.ResultOrder();
   g_execRecords[idx].isSynthetic=false;
   CCTPersistExecRecord(g_execRecords[idx]);

   CCTJournalLine(StringFormat("[CCT ORDER ACCEPT]\n%s",
                               CCTExecutionAudit(g,g.activeSibIdx,entry,sl,tp,lots,
                                                 useVirtualTP ? "broker order placed; virtual TP armed" : "broker order placed",
                                                 comment)));

   if(CCTDebugEnabled())
     {
      CCTJournalLine(StringFormat("[CCT EXEC] sent %s lots=%.2f sizingEntry=%.5f fill=%.5f sl=%.5f tp=%.5f riskCashCap=%.2f projectedRisk=%.2f spread=%.5f",
                                  genKey,lots,sizingEntry,g_execRecords[idx].brokerFill,sl,tp,
                                  EffectiveAccountBase()*(g_riskPct/100.0),
                                  CCTCashLossPerLot(_Symbol,g.bull,sizingEntry,sl)*lots,
                                  spread));
     }

   CCTReconcileBrokerDeals(true);
  }

/*
Purpose: Let persisted broker execution truth override rebuilt scanner geometry/outcome.
Constitution: Broker fill and broker outcome are authoritative once present.
Inputs: g - generation to update in place.
Outputs: Generation geometry/outcome updated from execution records when available.
*/
int CCTRecordedExecutionSiblingIndex(const GenInfo &g,const ExecRecord &rec)
  {
   if(g.nSibs<=0)
      return -1;

   if(rec.sibIndex>=0 && rec.sibIndex<g.nSibs)
      return rec.sibIndex;

   if(rec.c1Time>0)
      for(int i=0;i<g.nSibs;i++)
         if(g.sibs[i].c1Time==rec.c1Time)
            return i;

   if(rec.c2Time>0)
      for(int i=0;i<g.nSibs;i++)
         if(g.sibs[i].c2Time==rec.c2Time)
            return i;

   if(rec.c3Time>0)
      for(int i=0;i<g.nSibs;i++)
         if(g.sibs[i].c3Time==rec.c3Time)
            return i;

   if(g.activeSibIdx>=0 && g.activeSibIdx<g.nSibs)
      return g.activeSibIdx;

   for(int i=0;i<g.nSibs;i++)
      if(g.sibs[i].state==SS_TRIGGERED || CCTResolvedState(g.sibs[i].state))
         return i;

   for(int i=0;i<g.nSibs;i++)
      if(IsAliveSiblingState(g.sibs[i].state))
         return i;

   return 0;
  }

bool CCTExecutionRecordAllowedByCurrentInputs(const GenInfo &g,const ExecRecord &rec)
  {
   // CCT_EXEC_RECORD_CURRENT_PARAM_GATE_V1
   // Persisted broker/synthetic evidence must not force chart drawings back
   // onto the chart after the user removes the C1 execution hour/session.
   // This is visual/scanner replay authority only; broker history remains
   // preserved in the record/audit layer.
   if(!Inp_SessionFilter)
      return true;

   if(rec.triggerBarTime<=0)
      return false;

   datetime triggerHTF=HTFBarOpenForTime(rec.triggerBarTime);
   datetime triggerAuthTime=(Inp_TimeframeModel==CCT_TFM_D1_M15) ? rec.triggerBarTime : triggerHTF;
   if(triggerAuthTime<=0 || !CCTModelAnyAuthAllows(triggerAuthTime))
      return false;

   datetime c1=(rec.c1Time>0) ? rec.c1Time : rec.triggerBarTime;
   if(c1<=0)
      return false;

   ENUM_CCT_AUTH_ROUTE route=AUTH_ROUTE_NONE;
   datetime htfOpen=0;
   int nyHour=-1;
   int offset=-1;
   if(ResolveC1AuthorityRoute(g,c1,false,route,htfOpen,nyHour,offset))
      return true;

   route=AUTH_ROUTE_NONE;
   htfOpen=0;
   nyHour=-1;
   offset=-1;
   if(ResolveC1AuthorityRoute(g,c1,true,route,htfOpen,nyHour,offset))
      return true;

   return false;
  }

void CCTApplyExecutionRecordToGeneration(GenInfo &g)
  {
   string genKey=GenKey(g.bull,g.birthTime);
   int idx=CCTFindExecRecord(genKey);
   if(idx<0)
     {
       ExecRecord rec;
       if(CCTLoadExecRecord(genKey,rec))
         {
         idx=CCTEnsureExecRecord(genKey);
          g_execRecords[idx]=rec;
         }
     }

   if(idx>=0)
      CCTSyncExecRecordOutcomeFromGlobal(idx,true);

   if(idx>=0 &&
      CCTExecRecordConsumesGeneration(g_execRecords[idx]) &&
      !CCTExecRecordHasBrokerSendTruth(g_execRecords[idx]) &&
      (g.triggerTime<=0 || !CCTExecRecordMatchesTrigger(g_execRecords[idx],g.triggerTime)))
     {
      if(CCTDebugEnabled())
         CCTJournalLine(StringFormat("[CCT EXEC RECORD SYNTHETIC HIDDEN] gen=%s | recordTrigger=%s | scannerTrigger=%s | reason=synthetic/no-broker record no longer matches rebuilt scanner truth",
                                     genKey,
                                     CCTJournalTimeStamp(g_execRecords[idx].triggerBarTime),
                                     CCTJournalTimeStamp(g.triggerTime)));
      return;
     }

   if(idx>=0 &&
      CCTExecRecordConsumesGeneration(g_execRecords[idx]) &&
      !CCTExecutionRecordAllowedByCurrentInputs(g,g_execRecords[idx]))
     {
      if(CCTDebugEnabled())
         CCTJournalLine(StringFormat("[CCT EXEC RECORD PARAM HIDDEN] gen=%s | trigger=%s | c1=%s | reason=current model/session inputs no longer authorize this execution",
                                     genKey,
                                     CCTJournalTimeStamp(g_execRecords[idx].triggerBarTime),
                                     CCTJournalTimeStamp(g_execRecords[idx].c1Time)));
      return;
     }

   if(idx>=0 && CCTExecRecordConsumesGeneration(g_execRecords[idx]))
     {
      ExecRecord rec=g_execRecords[idx];
      g.triggerTime=rec.triggerBarTime;
      g.dormant=false;
      g.sweepCount=rec.sweepCount;
      g.modelType=CCTModelTypeForSweepTruth(rec.modelType,rec.sweepCount,g.tsPostBirthSweepCount);
      int recSib=CCTRecordedExecutionSiblingIndex(g,rec);
      if(recSib>=0 && recSib<g.nSibs)
        {
         g.activeSibIdx=recSib;
         if(rec.c1Time>0)
            g.sibs[recSib].c1Time=rec.c1Time;
         if(rec.c2Time>0)
            g.sibs[recSib].c2Time=rec.c2Time;
         if(rec.c3Time>0)
            g.sibs[recSib].c3Time=rec.c3Time;

         SIB_STATE lockedState=CCTResolvedState(rec.outcome) ? rec.outcome : SS_TRIGGERED;
         g.sibs[recSib].state=lockedState;
         g.outcome=lockedState;
         g.exitTime=rec.exitTime;
         g.exitPrice=rec.exitPrice;
         ConsumeInactiveSiblingsOnTrigger(g,recSib,g.triggerTime);
        }
     }

   if(g.triggerTime<=0)
      return;

   if(idx>=0)
     {
      ExecRecord rec=g_execRecords[idx];
      if(CCTExecRecordMatchesTrigger(rec,g.triggerTime))
        {
         if(rec.exitTime>0 && !rec.coTouched && CCTRecoverExecRecordCOTouch(rec,rec.exitTime))
         {
            g_execRecords[idx]=rec;
            CCTPersistExecRecord(g_execRecords[idx]);
           }

         double brokerEntry=(rec.brokerFill>0.0) ? rec.brokerFill : rec.visualEntry;
         if(brokerEntry>0.0)
            g.visualEntry=brokerEntry;
         if(g.visualEntryTime<=0)
           {
            int ltfSec=(int)PeriodSeconds(LTF());
            if(ltfSec<=0)
               ltfSec=60;
            datetime entryTime=(rec.c3Time>0) ? (rec.c3Time+(datetime)ltfSec) : 0;
            if(entryTime<=0 && rec.triggerBarTime>0)
               entryTime=rec.triggerBarTime+(datetime)ltfSec;
            if(entryTime>0)
               g.visualEntryTime=entryTime;
           }
         if(rec.triggerSpread>0.0)
            g.triggerSpread=rec.triggerSpread;
         if(rec.brokerSL>0.0)
            g.rawSL=rec.brokerSL;
         if(rec.brokerTP>0.0)
            g.rawTP=rec.brokerTP;
         if(rec.anchorA>0.0)
            g.anchorA=rec.anchorA;
         if(rec.anchorATime>0)
            g.anchorATime=rec.anchorATime;
         if(rec.anchorB>0.0)
            g.anchorB=rec.anchorB;
         if(rec.anchorBTime>0)
            g.anchorBTime=rec.anchorBTime;
         if(rec.rawSL>0.0)
            g.fibRawSL=rec.rawSL;
         if(rec.lockedRR>0.0)
            g.lockedRR=rec.lockedRR;
         g.slBranch=rec.slBranch;

         if(rec.beApplied || rec.beGeneralApplied || rec.beCoApplied)
           {
            if(rec.beGeneralApplied && rec.beGeneralPrice<=0.0 && rec.bePrice>0.0)
              {
               rec.beGeneralPrice=rec.bePrice;
               rec.beGeneralTime=rec.beTime;
               rec.beGeneralLeftAnchorTime=rec.beLeftAnchorTime;
              }
            if(rec.beCoApplied && rec.beCoPrice<=0.0 && rec.bePrice>0.0)
              {
               rec.beCoPrice=rec.bePrice;
               rec.beCoTime=rec.beTime;
               rec.beCoLeftAnchorTime=rec.beLeftAnchorTime;
              }

            if(rec.beGeneralApplied && rec.beGeneralLeftAnchorTime<=0 && rec.beGeneralTime>0 && rec.beGeneralPrice>0.0)
               rec.beGeneralLeftAnchorTime=CCTFindBrokerBELeftAnchor((g.triggerTime>0 ? g.triggerTime : g.visualEntryTime),rec.beGeneralTime,rec.beGeneralPrice);
            if(rec.beCoApplied && rec.beCoLeftAnchorTime<=0 && rec.beCoTime>0 && rec.beCoPrice>0.0)
               rec.beCoLeftAnchorTime=CCTFindBrokerBELeftAnchor((g.triggerTime>0 ? g.triggerTime : g.visualEntryTime),rec.beCoTime,rec.beCoPrice);

            g.beApplied=true;
            g.beGeneralApplied=rec.beGeneralApplied;
            g.beCoApplied=rec.beCoApplied;

            g.beGeneralPrice=rec.beGeneralPrice;
            g.beGeneralTime=rec.beGeneralTime;
            g.beGeneralLeftAnchorTime=rec.beGeneralLeftAnchorTime;
            g.beCoPrice=rec.beCoPrice;
            g.beCoTime=rec.beCoTime;
            g.beCoLeftAnchorTime=rec.beCoLeftAnchorTime;

            if(rec.beGeneralApplied && rec.beGeneralPrice>0.0)
              {
               g.bePrice=rec.beGeneralPrice;
               g.beTriggerTime=rec.beGeneralTime;
               g.beLeftAnchorTime=rec.beGeneralLeftAnchorTime;
              }
            else if(rec.beCoApplied && rec.beCoPrice>0.0)
              {
               g.bePrice=rec.beCoPrice;
               g.beTriggerTime=rec.beCoTime;
               g.beLeftAnchorTime=rec.beCoLeftAnchorTime;
              }
            else
              {
               g.bePrice=rec.bePrice;
               g.beTriggerTime=rec.beTime;
               g.beLeftAnchorTime=rec.beLeftAnchorTime;
              }

            }

          if(rec.coTouched)
            {
             g.coTouchTime=rec.coTouchTime;
             g.coFreezeTime=rec.coTouchTime;
             g.coFrozen=(rec.coTouchTime>0);
            }
         }
     }

   SIB_STATE state=SS_UNKNOWN_OUTCOME;
   datetime exitTime=0;
   double exitPrice=0.0;
   if(CCTLoadOutcome(genKey,g.triggerTime,state,exitTime,exitPrice))
     {
      // CCT_RESOLVED_OUTCOME_REPLAY_WITHOUT_ACTIVE_SIB_V1
      // Historical rebuilds can briefly lose activeSibIdx for old resolved
      // records. Apply the outcome by saved execution geometry first so later
      // visual refreshes do not stretch resolved objects back to live time.
      int outcomeSib=g.activeSibIdx;
      if(outcomeSib<0 || outcomeSib>=g.nSibs)
        {
         if(idx>=0)
            outcomeSib=CCTRecordedExecutionSiblingIndex(g,g_execRecords[idx]);
        }

      if(outcomeSib>=0 && outcomeSib<g.nSibs)
        {
         g.activeSibIdx=outcomeSib;
         g.sibs[outcomeSib].state=state;
        }

      g.outcome=state;
      g.exitTime=exitTime;
      g.exitPrice=exitPrice;
      if(idx>=0)
        {
         bool changed=((int)g_execRecords[idx].outcome!=(int)state ||
                       g_execRecords[idx].exitTime!=exitTime ||
                       MathAbs(g_execRecords[idx].exitPrice-exitPrice)>_Point*0.1);
         g_execRecords[idx].outcome=state;
         g_execRecords[idx].exitTime=exitTime;
         g_execRecords[idx].exitPrice=exitPrice;
         if(changed)
            CCTPersistExecRecord(g_execRecords[idx]);
        }
     }
  }

/*
Purpose: Persist a synthetic trigger/resolution so visual rebuilds cannot remap the same generation to a later trigger.
Constitution: One confirmed trigger consumes a generation forever; broker-off visual evidence must obey the same terminal lock as broker executions.
Inputs: g - generation containing a confirmed synthetic trigger.
Outputs: Synthetic execution record saved for future scanner rebuilds.
*/
void CCTEnsureSyntheticRecordFromGeneration(const GenInfo &g)
  {
   // CCT_SYNTH_VISUAL_RECORD_SIGNAL_LABEL_V1
   // This function is called after CCTTryExecuteGeneration has already had the broker-send opportunity.
   // Broker execution must never wait for notifications/screenshots.
   // If broker execution fails/skips but synthetic execution geometry is valid, persist visual/audit evidence.
   // Signals are still allowed for fresh no-broker records, but Notify labels them as model/no-broker basis.
   if(g.triggerTime<=0 || g.activeSibIdx<0 || g.activeSibIdx>=g.nSibs)
      return;
   if(g.visualEntry<=0.0 || g.rawSL<=0.0 || g.rawTP<=0.0)
      return;

   string genKey=GenKey(g.bull,g.birthTime);
   int idx=CCTEnsureExecRecord(genKey);
   if(CCTExecRecordConsumesGeneration(g_execRecords[idx]) && g_execRecords[idx].triggerBarTime>0)
     {
      if(g_execRecords[idx].triggerBarTime!=g.triggerTime)
         return;

      // CCT_SYNTHETIC_RESOLVED_RECORD_IMMUTABLE_V1
      // A later visual rebuild can reconstruct the same generation as live
      // before the historical outcome is re-applied. Do not let that pass
      // stretch already-resolved execution boxes back out to live price time.
      if(CCTResolvedState(g_execRecords[idx].outcome) || g_execRecords[idx].exitTime>0)
         return;

      // A same-trigger real broker record is authoritative and already queues entry notification after fill.
      // Do not convert it into a synthetic record.
      if(!g_execRecords[idx].isSynthetic)
         return;
     }

   g_execRecords[idx].genKey=genKey;
   g_execRecords[idx].bull=g.bull;
   g_execRecords[idx].triggerBarTime=g.triggerTime;
   g_execRecords[idx].visualEntry=g.visualEntry;
   g_execRecords[idx].triggerSpread=g.triggerSpread;
   g_execRecords[idx].brokerFill=0.0;
   g_execRecords[idx].brokerSL=g.rawSL;
   g_execRecords[idx].brokerTP=g.rawTP;
   g_execRecords[idx].coPrice=g.coPrice;
   g_execRecords[idx].anchorA=g.anchorA;
   g_execRecords[idx].anchorATime=g.anchorATime;
   g_execRecords[idx].anchorB=g.anchorB;
   g_execRecords[idx].anchorBTime=g.anchorBTime;
   g_execRecords[idx].rawSL=g.fibRawSL>0.0 ? g.fibRawSL : g.rawSL;
   g_execRecords[idx].lockedRR=g.lockedRR;
   g_execRecords[idx].slBranch=g.slBranch;
   g_execRecords[idx].modelType=CCTModelTypeForSweepTruth(g.modelType,g.sweepCount,g.tsPostBirthSweepCount);
   g_execRecords[idx].sweepCount=g.sweepCount;
   g_execRecords[idx].execLots=0.0;
   g_execRecords[idx].sibIndex=g.activeSibIdx;
   g_execRecords[idx].c1Time=g.sibs[g.activeSibIdx].c1Time;
   g_execRecords[idx].c2Time=g.sibs[g.activeSibIdx].c2Time;
   g_execRecords[idx].c3Time=g.sibs[g.activeSibIdx].c3Time;
   g_execRecords[idx].outcome=g.outcome;
   g_execRecords[idx].exitTime=g.exitTime;
   g_execRecords[idx].exitPrice=g.exitPrice;
   g_execRecords[idx].beApplied=g.beApplied;
   g_execRecords[idx].beGeneralApplied=g.beGeneralApplied;
   g_execRecords[idx].beCoApplied=g.beCoApplied;
   g_execRecords[idx].bePrice=g.bePrice;
   g_execRecords[idx].beTime=g.beTriggerTime;
   g_execRecords[idx].beLeftAnchorTime=g.beLeftAnchorTime;
   g_execRecords[idx].beGeneralPrice=g.beGeneralPrice;
   g_execRecords[idx].beGeneralTime=g.beGeneralTime;
   g_execRecords[idx].beGeneralLeftAnchorTime=g.beGeneralLeftAnchorTime;
   g_execRecords[idx].beCoPrice=g.beCoPrice;
   g_execRecords[idx].beCoTime=g.beCoTime;
   g_execRecords[idx].beCoLeftAnchorTime=g.beCoLeftAnchorTime;
   g_execRecords[idx].coTouched=(g.coTouchTime>0);
   g_execRecords[idx].coTouchTime=g.coTouchTime;
   g_execRecords[idx].ticket=0;
   g_execRecords[idx].isSynthetic=true;
   CCTPersistExecRecord(g_execRecords[idx]);
   CCTTradeExecAuditOnce("SYNTHETIC_RECORD_CREATED_NO_BROKER_TRIGGER",genKey,g.triggerTime,"synthetic_created",
                         CCTTradeExecRecordAuditDetail(g_execRecords[idx]));

   NotifyQueueEntryOnce(g_execRecords[idx],HTF(),LTF());

   if(CCTResolvedState(g.outcome))
     {
      CCTPersistOutcome(genKey,g.triggerTime,g.outcome,g.exitTime,g.exitPrice);
      NotifyExit(g_execRecords[idx],g.outcome,HTF(),LTF());
     }
  }


double CCTBEStopMinDistancePx()
  {
   int stopLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(_Point,(double)MathMax(stopLevel,freezeLevel)*_Point);
  }

bool CCTBEStopNonLossSide(bool bull,double targetSL,double entryPx)
  {
   if(targetSL<=0.0 || entryPx<=0.0)
      return false;
   return bull ? (targetSL>=entryPx-_Point*0.1) : (targetSL<=entryPx+_Point*0.1);
  }

bool CCTBEStopCandidateSafeForMove(bool bull,double targetSL,double currentSL,double currentPx,double entryPx,string &reason)
  {
   if(targetSL<=0.0 || currentPx<=0.0)
     {
      reason="invalid_target_or_price";
      return false;
     }

   if(!CCTBEStopNonLossSide(bull,targetSL,entryPx))
     {
      reason="loss_side_of_entry";
      return false;
     }

   double minDist=CCTBEStopMinDistancePx();
   if(bull)
     {
      if(targetSL>currentPx-minDist)
        {
         reason=StringFormat("stop_freeze_distance min=%.5f",minDist);
         return false;
        }
      if(currentSL>0.0 && targetSL<=currentSL+_Point)
        {
         reason="not_more_protective";
         return false;
        }
      reason="";
      return true;
     }

   if(targetSL<currentPx+minDist)
     {
      reason=StringFormat("stop_freeze_distance min=%.5f",minDist);
      return false;
     }
   if(currentSL>0.0 && targetSL>=currentSL-_Point)
     {
      reason="not_more_protective";
      return false;
     }

   reason="";
   return true;
  }

bool CCTBEStopCanImprove(bool bull,double targetSL,double currentSL,double currentPx,double entryPx)
  {
   string reason="";
   return CCTBEStopCandidateSafeForMove(bull,targetSL,currentSL,currentPx,entryPx,reason);
  }

bool CCTBEStopMoreProtective(bool bull,double candidateSL,double existingSL)
  {
   if(candidateSL<=0.0)
      return false;
   if(existingSL<=0.0)
      return true;
   return bull ? (candidateSL>existingSL+_Point) : (candidateSL<existingSL-_Point);
  }

string CCTBEPlanAuditDetail(const string moveKind,double plannedTarget,double currentSL,double currentPx,double entryPx,double initialRisk,double tpDistance,double acceptedSL,uint retcode,int err,const string reason)
  {
   return StringFormat("kind=%s | plannedTarget=%.5f | currentSL=%.5f | currentPx=%.5f | entry=%.5f | initialRisk=%.5f | tpDistance=%.5f | acceptedSL=%.5f | retcode=%u | err=%d | reason=%s",
                       moveKind,
                       plannedTarget,
                       currentSL,
                       currentPx,
                       entryPx,
                       initialRisk,
                       tpDistance,
                       acceptedSL,
                       retcode,
                       err,
                       reason);
  }

void CCTUpdatePositionBE()
  {
   if(Inp_BrokerExecution!=BROKER_EXEC_ON)
      return;

   CTrade trade;
   trade.SetExpertMagicNumber(CCTEffectiveMagic());
   trade.SetDeviationInPoints(MathMax(0,Inp_MaxDeviationPoints));
   trade.SetTypeFillingBySymbol(_Symbol);
   string managementBlockReason="";
   bool managementBlocked=CCTTradeManagementBlocked(managementBlockReason);
   static datetime s_lastMgmtBlockJournal=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=CCTEffectiveMagic())
         continue;

      string genKey="";
      bool bull=false;
      if(!CCTTryGenKeyFromComment(PositionGetString(POSITION_COMMENT),genKey,bull))
        {
         ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(!CCTFindGenKeyByPositionId(positionId,genKey,bull) &&
            !CCTFindGenKeyByPositionId(ticket,genKey,bull))
            continue;
        }

      int idx=CCTEnsureExecRecord(genKey);
      double openPx=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double brokerTP=PositionGetDouble(POSITION_TP);
      double targetTP=(brokerTP>0.0) ? brokerTP : g_execRecords[idx].brokerTP;
      if(openPx<=0.0 || targetTP<=0.0)
         continue;

      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double curPx=bull ? bid : ask;
      double tpDist=MathAbs(targetTP-openPx);
      if(tpDist<=_Point)
         continue;
      double favorable=bull ? (curPx-openPx) : (openPx-curPx);
      double progressPct=100.0*favorable/tpDist;
      if(progressPct>g_execRecords[idx].maxProgressPct)
        {
         double oldMax=g_execRecords[idx].maxProgressPct;
         bool crossed=(oldMax<g_beCoMinProgPct && progressPct>=g_beCoMinProgPct) ||
                      (oldMax<g_beTriggerPct && progressPct>=g_beTriggerPct);
         g_execRecords[idx].maxProgressPct=progressPct;
         if(crossed)
            CCTPersistExecRecord(g_execRecords[idx]);
        }

      datetime posOpen=(datetime)PositionGetInteger(POSITION_TIME);
      datetime now=CurrentServerTime();
      bool coBEAllowedNow=CCTCOBEApplies(now);

      if(CCTManageVirtualTP(idx,ticket,bull,posOpen,curSL,brokerTP,targetTP,curPx,trade,managementBlocked,managementBlockReason))
         continue;

      int coMinAge=MathMax(g_beCoMinSec,(int)PeriodSeconds(LTF()));
      bool coAgeOk=(now-posOpen)>=coMinAge;
      bool coProgressOk=(g_execRecords[idx].maxProgressPct>=g_beCoMinProgPct);
      bool recordChanged=false;
      bool coHit=false;
      if(coBEAllowedNow && g_execRecords[idx].coPrice>0.0 && coAgeOk)
        {
         coHit=bull ? (curPx>=g_execRecords[idx].coPrice) : (curPx<=g_execRecords[idx].coPrice);
         if(coHit && !coProgressOk)
           {
            double recovered=CCTMaxProgressSinceEntry(bull,posOpen,openPx,targetTP,curPx);
            if(recovered>g_execRecords[idx].maxProgressPct)
              {
               double oldMax=g_execRecords[idx].maxProgressPct;
               g_execRecords[idx].maxProgressPct=recovered;
               if((oldMax<g_beCoMinProgPct && recovered>=g_beCoMinProgPct) ||
                  (oldMax<g_beTriggerPct && recovered>=g_beTriggerPct))
                  recordChanged=true;
              }
            coProgressOk=(g_execRecords[idx].maxProgressPct>=g_beCoMinProgPct);
           }
         if(coHit && !g_execRecords[idx].coTouched)
           {
            g_execRecords[idx].coTouched=true;
            g_execRecords[idx].coTouchTime=now;
            recordChanged=true;
           }
        }

      double globalSL=0.0;
      bool globalCandidate=false;
      string globalSkipReason="";
      if(CCTRuntimeBEGlobalEnabled())
        {
         globalSL=NormalizeDouble(openPx + (bull ? 1.0 : -1.0)*(g_beMovePct/100.0)*tpDist,_Digits);
         if(g_execRecords[idx].maxProgressPct<g_beTriggerPct && CCTBEStopCanImprove(bull,globalSL,curSL,curPx,openPx))
           {
            double recovered=CCTMaxProgressSinceEntry(bull,posOpen,openPx,targetTP,curPx);
            if(recovered>g_execRecords[idx].maxProgressPct)
              {
               double oldMax=g_execRecords[idx].maxProgressPct;
               g_execRecords[idx].maxProgressPct=recovered;
               if((oldMax<g_beCoMinProgPct && recovered>=g_beCoMinProgPct) ||
                  (oldMax<g_beTriggerPct && recovered>=g_beTriggerPct))
                  recordChanged=true;
              }
           }
         if(!g_execRecords[idx].beGeneralApplied && g_execRecords[idx].maxProgressPct>=g_beTriggerPct)
            globalCandidate=CCTBEStopCandidateSafeForMove(bull,globalSL,curSL,curPx,openPx,globalSkipReason);
        }

      double coSL=0.0;
      bool coCandidate=false;
      string coSkipReason="";
      double initialSL=(g_execRecords[idx].brokerSL>0.0) ? g_execRecords[idx].brokerSL : curSL;
      double initialRisk=MathAbs(openPx-initialSL);
      if(coBEAllowedNow && !g_execRecords[idx].beCoApplied && g_execRecords[idx].coPrice>0.0 &&
         coAgeOk && coProgressOk && g_execRecords[idx].coTouched && initialRisk>_Point)
        {
         // CCT_CO_BE_LOCK_USES_TP_DISTANCE_V1
         // CO BE lock percent is a portion of the planned TP profit distance,
         // not the initial SL risk. Example: 5% of $93.50 locks $4.675.
         coSL=NormalizeDouble(openPx + (bull ? 1.0 : -1.0)*(g_beCoLockPct/100.0)*tpDist,_Digits);
         coCandidate=CCTBEStopCandidateSafeForMove(bull,coSL,curSL,curPx,openPx,coSkipReason);
        }

      double candidateSL=0.0;
      bool candidateGlobal=false;
      bool candidateCO=false;
      if(coCandidate)
        {
         candidateSL=coSL;
         candidateCO=true;
        }
      if(globalCandidate && CCTBEStopMoreProtective(bull,globalSL,candidateSL))
        {
         candidateSL=globalSL;
         candidateGlobal=true;
         candidateCO=false;
        }

      if(recordChanged)
         CCTPersistExecRecord(g_execRecords[idx]);

      if(!globalCandidate && globalSL>0.0 && !g_execRecords[idx].beGeneralApplied && g_execRecords[idx].maxProgressPct>=g_beTriggerPct &&
         (globalSkipReason=="loss_side_of_entry" || StringFind(globalSkipReason,"stop_freeze_distance")>=0))
        {
         CCTTradeExecAuditOnce("BE_GLOBAL_MOVE_SKIPPED_NO_SAFE_TARGET",
                               genKey,
                               (g_execRecords[idx].triggerBarTime>0 ? g_execRecords[idx].triggerBarTime : posOpen),
                               "global_no_safe_target",
                               CCTBEPlanAuditDetail("Global BE",globalSL,curSL,curPx,openPx,initialRisk,tpDist,0.0,0,0,globalSkipReason));
        }

      if(!coCandidate && coSL>0.0 && !g_execRecords[idx].beCoApplied && coAgeOk && coProgressOk && g_execRecords[idx].coTouched &&
         (coSkipReason=="loss_side_of_entry" || StringFind(coSkipReason,"stop_freeze_distance")>=0))
        {
         CCTTradeExecAuditOnce("BE_CO_MOVE_SKIPPED_NO_SAFE_TARGET",
                               genKey,
                               (g_execRecords[idx].coTouchTime>0 ? g_execRecords[idx].coTouchTime : (g_execRecords[idx].triggerBarTime>0 ? g_execRecords[idx].triggerBarTime : posOpen)),
                               "co_no_safe_target",
                               CCTBEPlanAuditDetail(CCTCOBELabel(),coSL,curSL,curPx,openPx,initialRisk,tpDist,0.0,0,0,coSkipReason));
        }

      if(managementBlocked)
        {
         if(now-s_lastMgmtBlockJournal>=30)
           {
            PrintFormat("[CCT MGMT BLOCK] %s",managementBlockReason);
            s_lastMgmtBlockJournal=now;
           }
         continue;
        }

      if(candidateSL>0.0)
        {
         ResetLastError();
         bool modified=trade.PositionModify(ticket,candidateSL,brokerTP);
         int modifyErr=GetLastError();
         uint modifyRetcode=trade.ResultRetcode();
         if(!modified)
           {
            CCTTradeExecAuditOnce(candidateCO ? "BE_CO_MOVE_REJECTED" : "BE_GLOBAL_MOVE_REJECTED",
                                  genKey,
                                  (candidateCO && g_execRecords[idx].coTouchTime>0) ? g_execRecords[idx].coTouchTime : (g_execRecords[idx].triggerBarTime>0 ? g_execRecords[idx].triggerBarTime : posOpen),
                                  candidateCO ? "co_modify_rejected" : "global_modify_rejected",
                                  CCTBEPlanAuditDetail(candidateCO ? CCTCOBELabel() : "Global BE",candidateSL,curSL,curPx,openPx,initialRisk,tpDist,0.0,modifyRetcode,modifyErr,"broker_rejected_modify"));
            continue;
           }

         double acceptedSL=candidateSL;
         if(PositionSelectByTicket(ticket))
            acceptedSL=PositionGetDouble(POSITION_SL);
         if(acceptedSL<=0.0)
            acceptedSL=candidateSL;

         if(!CCTBEStopNonLossSide(bull,acceptedSL,openPx))
           {
            CCTTradeExecAuditOnce(candidateCO ? "BE_CO_MOVE_REJECTED_UNSAFE_ACCEPTED_SL" : "BE_GLOBAL_MOVE_REJECTED_UNSAFE_ACCEPTED_SL",
                                  genKey,
                                  (candidateCO && g_execRecords[idx].coTouchTime>0) ? g_execRecords[idx].coTouchTime : (g_execRecords[idx].triggerBarTime>0 ? g_execRecords[idx].triggerBarTime : posOpen),
                                  candidateCO ? "co_unsafe_accepted" : "global_unsafe_accepted",
                                  CCTBEPlanAuditDetail(candidateCO ? CCTCOBELabel() : "Global BE",candidateSL,curSL,curPx,openPx,initialRisk,tpDist,acceptedSL,modifyRetcode,modifyErr,"accepted_sl_loss_side_of_entry"));
            continue;
           }

         datetime beEventTime=now;
         datetime anchorFrom=(g_execRecords[idx].triggerBarTime>0) ? g_execRecords[idx].triggerBarTime : posOpen;

         datetime acceptedAnchor=CCTFindBrokerBELeftAnchor(anchorFrom,beEventTime,acceptedSL);
         if(acceptedAnchor<=0)
            acceptedAnchor=beEventTime;

         g_execRecords[idx].beApplied=true;

         if(candidateCO)
           {
            g_execRecords[idx].beCoApplied=true;
            g_execRecords[idx].beCoPrice=acceptedSL;
            g_execRecords[idx].beCoTime=beEventTime;
            g_execRecords[idx].beCoLeftAnchorTime=acceptedAnchor;

            // Compatibility/active visible channel follows the currently active BE line.
            g_execRecords[idx].bePrice=acceptedSL;
            g_execRecords[idx].beTime=beEventTime;
            g_execRecords[idx].beLeftAnchorTime=acceptedAnchor;
           }

         if(candidateGlobal)
           {
            g_execRecords[idx].beGeneralApplied=true;
            g_execRecords[idx].beGeneralPrice=acceptedSL;
            g_execRecords[idx].beGeneralTime=beEventTime;
            g_execRecords[idx].beGeneralLeftAnchorTime=acceptedAnchor;

            // Global BE replaces NY BE-CO as the active visible line once applied.
            g_execRecords[idx].bePrice=acceptedSL;
            g_execRecords[idx].beTime=beEventTime;
            g_execRecords[idx].beLeftAnchorTime=acceptedAnchor;
           }

         CCTPersistExecRecord(g_execRecords[idx]);
         CCTTradeExecAuditOnce(candidateCO ? "BE_CO_MOVE_CONFIRMED" : "BE_GLOBAL_MOVE_CONFIRMED",
                               genKey,
                               beEventTime,
                               candidateCO ? "co_confirmed" : "global_confirmed",
                               CCTBEPlanAuditDetail(candidateCO ? CCTCOBELabel() : "Global BE",candidateSL,curSL,curPx,openPx,initialRisk,tpDist,acceptedSL,modifyRetcode,modifyErr,"confirmed"));
         NotifyBEMove(g_execRecords[idx],candidateCO ? 1 : 0,HTF(),LTF());
        }
     }
  }

SIB_STATE CCTClassifyExitByDeal(const string genKey,bool bull,ENUM_DEAL_REASON reason,double exitPrice)
  {
   if(reason==DEAL_REASON_TP)
      return SS_RESOLVED_TP;

   int idx=CCTFindExecRecord(genKey);
   if(idx>=0 && g_execRecords[idx].brokerTP>0.0 &&
      (g_execRecords[idx].virtualTPTouched ||
       (g_execRecords[idx].virtualTPActive && (bull ? (exitPrice>=g_execRecords[idx].brokerTP-_Point) : (exitPrice<=g_execRecords[idx].brokerTP+_Point)))))
      return SS_RESOLVED_TP;

   if(idx>=0 && g_execRecords[idx].beApplied)
     {
      double tol=MathMax(_Point*10.0,_Point);
      if(g_execRecords[idx].beGeneralApplied && g_execRecords[idx].beGeneralPrice>0.0 && MathAbs(exitPrice-g_execRecords[idx].beGeneralPrice)<=tol)
         return SS_RESOLVED_BE;
      if(g_execRecords[idx].beCoApplied && g_execRecords[idx].beCoPrice>0.0 && MathAbs(exitPrice-g_execRecords[idx].beCoPrice)<=tol)
         return SS_RESOLVED_BE_CO;
      if(g_execRecords[idx].bePrice>0.0 && MathAbs(exitPrice-g_execRecords[idx].bePrice)<=tol)
         return g_execRecords[idx].beGeneralApplied ? SS_RESOLVED_BE : SS_RESOLVED_BE_CO;
     }

   if(reason==DEAL_REASON_SL && idx>=0 && g_execRecords[idx].beApplied)
      return g_execRecords[idx].beGeneralApplied ? SS_RESOLVED_BE : SS_RESOLVED_BE_CO;

   return SS_RESOLVED_SL;
  }

bool CCTRecoverExecRecordCOTouch(ExecRecord &rec,datetime throughTime)
  {
   if(rec.coTouched && rec.coTouchTime>0)
      return true;
   if(rec.coPrice<=0.0 || rec.triggerBarTime<=0)
      return false;

   datetime from=rec.triggerBarTime;
   datetime to=(throughTime>0) ? throughTime : CurrentServerTime();
   if(to<from)
      return false;

   MqlRates rates[];
   int copied=CopyRates(_Symbol,LTF(),from,to,rates);
   if(copied<=0)
      return false;
   ArraySetAsSeries(rates,false);

   int n=ArraySize(rates);
   for(int i=0;i<n;i++)
     {
      if(rates[i].time<from)
         continue;
      if(rates[i].time>to)
         break;

      bool touched=rec.bull ? (rates[i].high>=rec.coPrice) : (rates[i].low<=rec.coPrice);
      if(!touched)
         continue;

      rec.coTouched=true;
      rec.coTouchTime=rates[i].time;
      return true;
     }

   return false;
  }


bool CCTFindEntryGenKeyByPosition(ulong positionId,string &genKey,bool &bull)
  {
   if(positionId==0)
      return false;
   if(CCTFindGenKeyByPositionId(positionId,genKey,bull))
      return true;
   datetime from=CCTStructuralDayOpenForTime(CurrentServerTime())-86400*3;
   if(!HistorySelect(from,CurrentServerTime()+86400))
      return false;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=positionId)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=CCTEffectiveMagic() || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)
         continue;
      if(CCTTryGenKeyFromComment(HistoryDealGetString(deal,DEAL_COMMENT),genKey,bull))
         return true;
     }
    return false;
  }

/*
Purpose: Return the expected broker-side exit price used for slippage auditing.
Constitution: Risk, fill, and exit truth must be separated so tester/live reports can distinguish planned geometry from actual broker result.
Inputs: rec - execution record, state - resolved outcome.
Outputs: Expected exit price for TP/SL/BE, or 0 when unknown.
*/
double CCTExpectedExitAuditPrice(const ExecRecord &rec,SIB_STATE state)
  {
   if(state==SS_RESOLVED_TP)
      return rec.brokerTP;

   if(state==SS_RESOLVED_BE)
     {
      if(rec.beGeneralPrice>0.0)
         return rec.beGeneralPrice;
      if(rec.bePrice>0.0)
         return rec.bePrice;
     }

   if(state==SS_RESOLVED_BE_CO)
     {
      if(rec.beCoPrice>0.0)
         return rec.beCoPrice;
      if(rec.bePrice>0.0)
         return rec.bePrice;
     }

   if(state==SS_RESOLVED_SL)
      return rec.brokerSL;

   return 0.0;
  }

/*
Purpose: Emit parseable exit audit telemetry for live/demo/tester reconciliation.
Constitution: Planned risk, fill risk, actual exit result, slippage, commission, swap, and fees must be auditable as separate quantities.
Inputs: rec - execution record, state - outcome, reason - MT5 deal reason, exitTime/exitPrice - broker exit, volume - deal volume, gross/swap/commission/fee - broker deal components.
Outputs: [CCT EXIT AUDIT] journal row.
*/
void CCTPrintExitAudit(const ExecRecord &rec,SIB_STATE state,ENUM_DEAL_REASON reason,datetime exitTime,double exitPrice,double volume,double gross,double swap,double commission,double fee)
  {
   if(rec.genKey=="")
      return;

   double lots=(rec.execLots>0.0) ? rec.execLots : volume;
   double plannedRisk=(rec.visualEntry>0.0 && rec.brokerSL>0.0 && lots>0.0) ? CCTCashLossPerLot(_Symbol,rec.bull,rec.visualEntry,rec.brokerSL)*lots : 0.0;
   double fillRisk=(rec.brokerFill>0.0 && rec.brokerSL>0.0 && lots>0.0) ? CCTCashLossPerLot(_Symbol,rec.bull,rec.brokerFill,rec.brokerSL)*lots : 0.0;
   double expectedExit=CCTExpectedExitAuditPrice(rec,state);
   double entrySlip=(rec.visualEntry>0.0 && rec.brokerFill>0.0) ? (rec.bull ? (rec.brokerFill-rec.visualEntry) : (rec.visualEntry-rec.brokerFill)) : 0.0;
   double exitSlip=(expectedExit>0.0) ? (rec.bull ? (exitPrice-expectedExit) : (expectedExit-exitPrice)) : 0.0;
   double net=gross+swap+commission+fee;
   double actualR=(fillRisk>0.0) ? net/fillRisk : 0.0;

   CCTJournalLine(StringFormat("[CCT EXIT AUDIT] %s | %s | outcome=%s | reason=%s | plannedRisk=%.2f | fillRiskAtSL=%.2f | actualNet=%.2f | actualR=%.4f | gross=%.2f | swap=%.2f | commission=%.2f | fee=%.2f | visualEntry=%.5f | brokerFill=%.5f | entrySlip=%.5f | expectedExit=%.5f | actualExit=%.5f | exitSlip=%.5f | lots=%.2f | exitTime=%s",
                               rec.genKey,
                               CCTJournalSide(rec.bull),
                               CCTJournalState(state),
                               EnumToString(reason),
                               plannedRisk,
                               fillRisk,
                               net,
                               actualR,
                               gross,
                               swap,
                               commission,
                               fee,
                               rec.visualEntry,
                               rec.brokerFill,
                               entrySlip,
                               expectedExit,
                               exitPrice,
                               exitSlip,
                               lots,
                               CCTJournalTimeStamp(exitTime)));
  }

void CCTHandleTradeTransaction(const MqlTradeTransaction &trans)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=CCTEffectiveMagic() || HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol)
      return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry==DEAL_ENTRY_IN)
     {
      CCTApplyEntryDeal(trans.deal,false);
      return;
     }
   if(entry!=DEAL_ENTRY_OUT)
      return;

   CCTApplyExitDeal(trans.deal,false);
  }

bool CCTMapEntryDealToGenKey(ulong deal,string &genKey,bool &bull)
  {
   genKey="";
   bull=false;
   string comment=HistoryDealGetString(deal,DEAL_COMMENT);
   if(CCTTryGenKeyFromComment(comment,genKey,bull))
      return true;

   ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
   if(CCTTakePendingExecLink(order,genKey,bull))
      return true;

   ulong positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   if(CCTFindGenKeyByPositionId(positionId,genKey,bull))
      return true;

   return false;
  }

bool CCTApplyEntryDeal(ulong deal,bool recovered)
  {
   string genKey="";
   bool bull=false;
   if(!CCTMapEntryDealToGenKey(deal,genKey,bull))
      return false;

   int idx=CCTEnsureExecRecord(genKey);
   ulong positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   double fill=HistoryDealGetDouble(deal,DEAL_PRICE);
   double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
   datetime dealTime=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);

   bool already=(g_execRecords[idx].brokerFill>0.0 &&
                 g_execRecords[idx].ticket==positionId &&
                 g_execRecords[idx].execLots>0.0);

   g_execRecords[idx].genKey=genKey;
   g_execRecords[idx].bull=bull;
   if(fill>0.0)
      g_execRecords[idx].brokerFill=fill;
   if(positionId>0)
      g_execRecords[idx].ticket=positionId;
   if(volume>0.0)
      g_execRecords[idx].execLots=volume;
   CCTPersistExecRecord(g_execRecords[idx]);

   // CCT_NOTIFY_ENTRY_AFTER_BROKER_FILL_V1
   // Normal entry signals are queued only after broker deal/fill truth is known.
   NotifyQueueEntryOnce(g_execRecords[idx],HTF(),LTF());

   if(!already)
     {
      string tag=recovered ? "[CCT ENTRY RECOVER]" : "[CCT ENTRY]";
      int lag=(int)MathMax(0,(long)(CurrentServerTime()-dealTime));
      CCTJournalLine(StringFormat("%s %s %s | %s | fill=%.5f lots=%.2f pos=%I64u lagSec=%d comment=%s",
                                  tag,genKey,CCTJournalSide(bull),CCTJournalTimeStamp(dealTime),
                                  g_execRecords[idx].brokerFill,volume,g_execRecords[idx].ticket,lag,
                                  HistoryDealGetString(deal,DEAL_COMMENT)));
     }

   return true;
  }

bool CCTApplyExitDeal(ulong deal,bool recovered)
  {
   ulong positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   string genKey="";
   bool bull=false;
   if(!CCTFindEntryGenKeyByPosition(positionId,genKey,bull))
      return false;

   int idx=CCTEnsureExecRecord(genKey);
   if(CCTResolvedState(g_execRecords[idx].outcome))
     {
      if(!g_execRecords[idx].coTouched && CCTRecoverExecRecordCOTouch(g_execRecords[idx],g_execRecords[idx].exitTime))
         CCTPersistExecRecord(g_execRecords[idx]);
      NotifyExit(g_execRecords[idx],g_execRecords[idx].outcome,HTF(),LTF());
      return true;
     }

   datetime exitTime=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
   double exitPrice=HistoryDealGetDouble(deal,DEAL_PRICE);
   ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON);
   SIB_STATE state=CCTClassifyExitByDeal(genKey,bull,reason,exitPrice);
   double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
   double gross=HistoryDealGetDouble(deal,DEAL_PROFIT);
   double swap=HistoryDealGetDouble(deal,DEAL_SWAP);
   double commission=HistoryDealGetDouble(deal,DEAL_COMMISSION);
   double fee=HistoryDealGetDouble(deal,DEAL_FEE);
   double profit=gross+swap+commission+fee;

   CCTPersistOutcome(genKey,g_execRecords[idx].triggerBarTime,state,exitTime,exitPrice);
   g_execRecords[idx].outcome=state;
   g_execRecords[idx].exitTime=exitTime;
   g_execRecords[idx].exitPrice=exitPrice;
   g_execRecords[idx].ticket=positionId;
   if(g_execRecords[idx].execLots<=0.0 && volume>0.0)
      g_execRecords[idx].execLots=volume;
   CCTRecoverExecRecordCOTouch(g_execRecords[idx],exitTime);
   CCTPersistExecRecord(g_execRecords[idx]);

   string tag=recovered ? "[CCT EXIT RECOVER]" : "[CCT EXIT]";
   int lag=(int)MathMax(0,(long)(CurrentServerTime()-exitTime));
   CCTJournalLine(StringFormat("%s %s %s | %s | outcome=%s reason=%s exit=%.5f lots=%.2f pnl=%.2f pos=%I64u lagSec=%d",
                               tag,genKey,CCTJournalSide(bull),CCTJournalTimeStamp(exitTime),
                               CCTJournalState(state),EnumToString(reason),exitPrice,volume,profit,positionId,lag));
   CCTPrintExitAudit(g_execRecords[idx],state,reason,exitTime,exitPrice,volume,gross,swap,commission,fee);
   // CCT_NOTIFY_EXIT_ON_RECOVERED_FRESH_V1
   // If OnTradeTransaction was missed but the recovered broker exit is still fresh
   // for this runtime, NotifyExit's freshness/one-shot gates decide safely.
   NotifyExit(g_execRecords[idx],state,HTF(),LTF());
   return true;
  }

void CCTReconcileBrokerDeals(bool force=false)
  {
   if(Inp_BrokerExecution!=BROKER_EXEC_ON)
      return;

   static datetime s_lastRun=0;
   datetime now=CurrentServerTime();
   if(!force && s_lastRun>0 && now-s_lastRun<1)
      return;
   s_lastRun=now;

   datetime from=now-2*86400;
   if(!HistorySelect(from,now+60))
      return;

   long magic=CCTEffectiveMagic();
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic)
         continue;

      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_IN)
         CCTApplyEntryDeal(deal,true);
      else if(entry==DEAL_ENTRY_OUT)
         CCTApplyExitDeal(deal,true);
     }
  }

/*
Purpose: Tester-only MFE/MAE research telemetry.
This does not change execution, SL, TP, BE, scanner state, or visual state.
It only observes post-fill execution records and prints parseable research rows.
*/
string CCTResearchModelText(ENUM_MODEL_TYPE mt)
  {
   return ModelTypeLabel(mt);
  }

string CCTResearchOutcomeText(SIB_STATE st)
  {
   if(st==SS_RESOLVED_TP)
      return "TP";
   if(st==SS_RESOLVED_SL)
      return "SL";
   if(st==SS_RESOLVED_BE)
      return "BE";
   if(st==SS_RESOLVED_BE_CO)
      return "BE_CO";
   return "UNKNOWN";
  }

string CCTResearchStem(const string genKey)
  {
   return "CCT_MM_"+_Symbol+"_"+genKey;
  }

double CCTResearchRiskCash(const ExecRecord &rec)
  {
   if(rec.brokerFill<=0.0 || rec.brokerSL<=0.0 || rec.execLots<=0.0)
      return 0.0;

   double oneLotLoss=CCTCashLossPerLot(_Symbol,rec.bull,rec.brokerFill,rec.brokerSL);

   if(oneLotLoss<=0.0)
      return 0.0;

   return oneLotLoss*rec.execLots;
  }

void CCTResearchInitIfNeeded(const ExecRecord &rec)
  {
   if(rec.genKey=="")
      return;

   string stem=CCTResearchStem(rec.genKey);

   if(GlobalVariableCheck(stem+"_INIT"))
      return;

   double riskCash=CCTResearchRiskCash(rec);
   datetime now=CurrentServerTime();

   GlobalVariableSet(stem+"_INIT",1.0);
   GlobalVariableSet(stem+"_RISK",riskCash);

   GlobalVariableSet(stem+"_MFE_CASH",0.0);
   GlobalVariableSet(stem+"_MFE_R",0.0);
   GlobalVariableSet(stem+"_MFE_PRICE",rec.brokerFill);
   GlobalVariableSet(stem+"_MFE_TIME",(double)now);

   GlobalVariableSet(stem+"_MAE_CASH",0.0);
   GlobalVariableSet(stem+"_MAE_R",0.0);
   GlobalVariableSet(stem+"_MAE_PRICE",rec.brokerFill);
   GlobalVariableSet(stem+"_MAE_TIME",(double)now);
  }

bool CCTResearchHasOpenPosition()
  {
   if(!MQLInfoInteger(MQL_TESTER))
      return false;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC)==CCTEffectiveMagic())
         return true;
     }

   return false;
  }

void CCTResearchUpdateOpenRecords()
  {
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   if(!CCTResearchHasOpenPosition())
      return;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return;

   datetime now=CurrentServerTime();

   for(int i=0;i<g_nExecRecords;i++)
     {
      if(g_execRecords[i].genKey=="" ||
         CCTResolvedState(g_execRecords[i].outcome) ||
         g_execRecords[i].brokerFill<=0.0 ||
         g_execRecords[i].brokerSL<=0.0 ||
         g_execRecords[i].execLots<=0.0)
         continue;

      CCTResearchInitIfNeeded(g_execRecords[i]);

      double closePrice=g_execRecords[i].bull ? tick.bid : tick.ask;
      ENUM_ORDER_TYPE typ=g_execRecords[i].bull ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double profit=0.0;

      if(!OrderCalcProfit(typ,_Symbol,g_execRecords[i].execLots,g_execRecords[i].brokerFill,closePrice,profit))
         continue;

      string stem=CCTResearchStem(g_execRecords[i].genKey);
      double riskCash=GlobalVariableGet(stem+"_RISK");
      double mfeCash=GlobalVariableGet(stem+"_MFE_CASH");
      double maeCash=GlobalVariableGet(stem+"_MAE_CASH");

      if(profit>mfeCash)
        {
         GlobalVariableSet(stem+"_MFE_CASH",profit);
         GlobalVariableSet(stem+"_MFE_R",(riskCash>0.0 ? profit/riskCash : 0.0));
         GlobalVariableSet(stem+"_MFE_PRICE",closePrice);
         GlobalVariableSet(stem+"_MFE_TIME",(double)now);
        }

      if(profit<maeCash)
        {
         GlobalVariableSet(stem+"_MAE_CASH",profit);
         GlobalVariableSet(stem+"_MAE_R",(riskCash>0.0 ? profit/riskCash : 0.0));
         GlobalVariableSet(stem+"_MAE_PRICE",closePrice);
         GlobalVariableSet(stem+"_MAE_TIME",(double)now);
        }
     }
  }

void CCTResearchEmitResolvedRecords()
  {
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   for(int i=0;i<g_nExecRecords;i++)
     {
      if(g_execRecords[i].genKey=="" || !CCTResolvedState(g_execRecords[i].outcome))
         continue;

      string stem=CCTResearchStem(g_execRecords[i].genKey);

      if(GlobalVariableCheck(stem+"_PRINTED"))
         continue;

      CCTResearchInitIfNeeded(g_execRecords[i]);

      double riskCash=GlobalVariableGet(stem+"_RISK");
      double mfeCash=GlobalVariableGet(stem+"_MFE_CASH");
      double mfeR=GlobalVariableGet(stem+"_MFE_R");
      double mfePrice=GlobalVariableGet(stem+"_MFE_PRICE");
      datetime mfeTime=(datetime)(long)GlobalVariableGet(stem+"_MFE_TIME");

      double maeCash=GlobalVariableGet(stem+"_MAE_CASH");
      double maeR=GlobalVariableGet(stem+"_MAE_R");
      double maePrice=GlobalVariableGet(stem+"_MAE_PRICE");
      datetime maeTime=(datetime)(long)GlobalVariableGet(stem+"_MAE_TIME");

      CCTJournalLine(StringFormat("[CCT MFE MAE] gen=%s | symbol=%s | side=%s | model=%s | sweepCount=%d | lots=%.2f | entry=%.5f | sl=%.5f | tp=%.5f | exit=%.5f | outcome=%s | riskCash=%.2f | mfeCash=%.2f | mfeR=%.4f | mfePrice=%.5f | mfeTime=%s | maeCash=%.2f | maeR=%.4f | maePrice=%.5f | maeTime=%s | c1=%s | c2=%s | c3=%s",
                                  g_execRecords[i].genKey,
                                  _Symbol,
                                  g_execRecords[i].bull ? "BUY" : "SELL",
                                  CCTResearchModelText(g_execRecords[i].modelType),
                                  g_execRecords[i].sweepCount,
                                  g_execRecords[i].execLots,
                                  g_execRecords[i].brokerFill,
                                  g_execRecords[i].brokerSL,
                                  g_execRecords[i].brokerTP,
                                  g_execRecords[i].exitPrice,
                                  CCTResearchOutcomeText(g_execRecords[i].outcome),
                                  riskCash,
                                  mfeCash,
                                  mfeR,
                                  mfePrice,
                                  TimeToString(mfeTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  maeCash,
                                  maeR,
                                  maePrice,
                                  TimeToString(maeTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(g_execRecords[i].c1Time,TIME_DATE|TIME_MINUTES),
                                  TimeToString(g_execRecords[i].c2Time,TIME_DATE|TIME_MINUTES),
                                  TimeToString(g_execRecords[i].c3Time,TIME_DATE|TIME_MINUTES)));

      GlobalVariableSet(stem+"_PRINTED",1.0);
     }
  }

#endif
