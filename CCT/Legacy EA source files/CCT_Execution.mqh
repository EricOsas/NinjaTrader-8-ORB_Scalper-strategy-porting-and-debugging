//+------------------------------------------------------------------+
//| CCT_Execution.mqh  v6.2                                          |
//| Execution engine: lot sizing, TP, SL (Fibonacci), spread,       |
//| breakeven (% of TP distance), position management.              |
//+------------------------------------------------------------------+
#ifndef CCT_EXECUTION_MQH
#define CCT_EXECUTION_MQH

#include "CCT_Globals.mqh"
#include <Trade\Trade.mqh>

//--- Pending execution queue ----------------------------------------
struct PendingExec
  {
   bool     bull;
   double   entryPrice;   // Locked trigger-close entry reference
   double   slRaw;        // Locked raw SL before spread widening
   double   tpRaw;        // Locked raw TP from trigger geometry
   double   rrLocked;     // Locked RR ratio from trigger-time geometry
   double   coPrice;      // Locked CO price for diagnostics/future use
   datetime triggerTime;
   datetime birthTime;
   datetime expiryTime;
   datetime nextAttemptTime;
   int      failCount;
   string   modelLabel;
  };

PendingExec g_pendingExec[];
int         g_nPending=0;

struct ExecRecord { datetime triggerTime; bool bull; };
ExecRecord g_execRecords[];
int        g_nExecRecords=0;

enum ENUM_TERMINAL_TRIGGER_REASON
  {
   TR_TERM_NONE=0,
   TR_TERM_EXECUTED,
   TR_TERM_WINDOW_BLOCK,
   TR_TERM_WINDOW_CLOSED,
   TR_TERM_EXPIRED,
   TR_TERM_STALE
  };

struct TerminalTriggerRecord
  {
   datetime triggerTime;
   datetime birthTime;
   bool     bull;
   ENUM_TERMINAL_TRIGGER_REASON reason;
  };

TerminalTriggerRecord g_terminalTriggers[];
int                   g_nTerminalTriggers=0;

struct BrokerExecPresenceRecord
  {
   string genKey;
  };

BrokerExecPresenceRecord g_brokerExecPresence[];
int                      g_nBrokerExecPresence=0;

struct CommissionEstimateRecord
  {
   string symbol;
   double roundTurnPerLot;
   int    sampleCount;
   datetime lastBootstrapAttempt;
  };

CommissionEstimateRecord g_commissionEstimates[];
int                      g_nCommissionEstimates=0;

struct ExecVisualRecord
  {
   string genKey;
   datetime triggerTime;
   double entryPrice;
   double slPrice;
   double tpPrice;
   double coPrice;
  };

ExecVisualRecord g_execVisuals[];
int              g_nExecVisuals=0;

struct ExecTouchRecord
  {
   string   genKey;
   datetime beAnchorTime;
   datetime beTouchTime;
   double   bePrice;
   datetime coTouchTime;
   bool     coFinalized;
   bool     immutable;
  };

ExecTouchRecord g_execTouches[];
int             g_nExecTouches=0;

struct OutcomeRecord
  {
   string    genKey;
   SIB_STATE state;
   datetime  exitTime;
   double    exitPrice;
   bool      immutable;
  };

OutcomeRecord g_outcomes[];
int           g_nOutcomes=0;

struct ExecMilestoneCache
  {
   string   genKey;
   bool     bull;
   datetime triggerTime;
   double   coPrice;
   datetime familyEndTime;
   datetime scanEnd;
   datetime beAnchorTime;
   datetime beTouchTime;
   double   bePrice;
   datetime coTouchTime;
   bool     coFinalized;
  };

ExecMilestoneCache g_execMilestones[];
int                g_nExecMilestones=0;

struct DaySeparatorStats
  {
   int bullTriggered;
   int bearTriggered;
   int bullOpen;
   int bearOpen;
   int tpCount;
   int slCount;
   int beCount;
   double pnlCash;
  };

struct ResearchTradeExportRecord
  {
   string genKey;
   ulong  positionId;
  };

ResearchTradeExportRecord g_researchExports[];
int                      g_nResearchExports=0;

struct ResearchEntrySnapshot
  {
   ulong    positionId;
   string   genKey;
   bool     bull;
   datetime entryTime;
   double   entryPrice;
   double   entryVolume;
   string   entryComment;
  };

ResearchEntrySnapshot g_researchEntries[];
int                   g_nResearchEntries=0;

struct ResearchPendingEntryLink
  {
   string   genKey;
   bool     bull;
   double   entryPrice;
   double   entryVolume;
   string   entryComment;
   datetime createdAt;
  };

ResearchPendingEntryLink g_researchPendingEntries[];
int                      g_nResearchPendingEntries=0;

void ResetExecutionRuntimeState()
  {
   ArrayResize(g_pendingExec,0);   g_nPending=0;
   ArrayResize(g_execRecords,0);   g_nExecRecords=0;
   ArrayResize(g_terminalTriggers,0); g_nTerminalTriggers=0;
   ArrayResize(g_brokerExecPresence,0); g_nBrokerExecPresence=0;
   ArrayResize(g_commissionEstimates,0); g_nCommissionEstimates=0;
   ArrayResize(g_execVisuals,0);   g_nExecVisuals=0;
   ArrayResize(g_execTouches,0);   g_nExecTouches=0;
   ArrayResize(g_outcomes,0);      g_nOutcomes=0;
   ArrayResize(g_execMilestones,0); g_nExecMilestones=0;
   ArrayResize(g_researchExports,0); g_nResearchExports=0;
   ArrayResize(g_researchEntries,0); g_nResearchEntries=0;
   ArrayResize(g_researchPendingEntries,0); g_nResearchPendingEntries=0;
  }

int FindBrokerExecPresenceRecord(string genKey)
  {
   for(int i=0;i<g_nBrokerExecPresence;i++)
      if(g_brokerExecPresence[i].genKey==genKey)
         return i;
   return -1;
  }

int FindTerminalTriggerRecord(datetime triggerTime,bool bull,datetime birthTime)
  {
   for(int i=0;i<g_nTerminalTriggers;i++)
      if(g_terminalTriggers[i].triggerTime==triggerTime
         && g_terminalTriggers[i].bull==bull
         && g_terminalTriggers[i].birthTime==birthTime)
         return i;
   return -1;
  }

bool IsTerminalTrigger(datetime triggerTime,bool bull,datetime birthTime)
  {
   return (FindTerminalTriggerRecord(triggerTime,bull,birthTime)>=0);
  }

void MarkTerminalTrigger(datetime triggerTime,bool bull,datetime birthTime,ENUM_TERMINAL_TRIGGER_REASON reason)
  {
   if(triggerTime<=0 || birthTime<=0)
      return;
   int idx=FindTerminalTriggerRecord(triggerTime,bull,birthTime);
   if(idx<0)
     {
      ArrayResize(g_terminalTriggers,g_nTerminalTriggers+1,32);
      idx=g_nTerminalTriggers++;
      g_terminalTriggers[idx].triggerTime=triggerTime;
      g_terminalTriggers[idx].bull=bull;
      g_terminalTriggers[idx].birthTime=birthTime;
     }
   g_terminalTriggers[idx].reason=reason;
  }

datetime CurrentExecutionReferenceTime()
  {
   datetime now=MarketReferenceTime();
   if(now<=0)
      now=TimeCurrent();
   if(now<=0)
      now=TimeTradeServer();
   return now;
  }

string ExecGenKeyFromBirth(bool bull,datetime birthTime)
  {
   return (bull?"BU_":"BE_")+IntegerToString((int)birthTime);
  }

bool ResearchExportEnabled()
  {
   if(!Inp_ResearchExport)
      return false;
   return ((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION));
  }

string TrimSpaces(string value)
  {
   while(StringLen(value)>0 && StringGetCharacter(value,0)==' ')
      value=StringSubstr(value,1);
   while(StringLen(value)>0 && StringGetCharacter(value,StringLen(value)-1)==' ')
      value=StringSubstr(value,0,StringLen(value)-1);
   return value;
  }

string SafeResearchToken(string value)
  {
   string out=value;
   if(out=="")
      return "";
   for(int i=0;i<StringLen(out);i++)
     {
      ushort ch=(ushort)StringGetCharacter(out,i);
      bool ok=((ch>='0' && ch<='9')
            || (ch>='A' && ch<='Z')
            || (ch>='a' && ch<='z')
            || ch=='_'
            || ch=='-');
      if(!ok)
         StringSetCharacter(out,i,'_');
     }
   return out;
  }

string ResearchRunTag()
  {
   string tag=SafeResearchToken(TrimSpaces(Inp_ResearchRunTag));
   if(tag!="")
      return tag;
   return SafeResearchToken(_Symbol+"_"+TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES));
  }

string ResearchCommonDir()        { return "CCT_Research"; }
string ResearchTradesPath()       { return ResearchCommonDir()+"\\trades_"+ResearchRunTag()+".csv"; }
string ResearchSummaryPath()      { return ResearchCommonDir()+"\\summary_"+ResearchRunTag()+".csv"; }

void EnsureResearchFolders()
  {
   if(!ResearchExportEnabled())
      return;
   FolderCreate(ResearchCommonDir(),FILE_COMMON);
  }

string CsvEscape(string value)
  {
   string out=value;
   StringReplace(out,"\"","\"\"");
   return "\""+out+"\"";
  }

string CsvBool(bool value)
  {
   return value?"true":"false";
  }

string CsvPrice(double value,const string symbol="")
  {
   string sym=(symbol!="")?symbol:_Symbol;
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   if(digits<0) digits=_Digits;
   return DoubleToString(value,digits);
  }

string CsvDouble4(double value)
  {
   return DoubleToString(value,4);
  }

string CsvDouble2(double value)
  {
   return DoubleToString(value,2);
  }

string CsvDateTime(datetime value)
  {
   if(value<=0)
      return "";
   return TimeToString(value,TIME_DATE|TIME_SECONDS);
  }

bool AppendResearchCsvLine(const string relPath,const string header,const string line)
  {
   if(!ResearchExportEnabled())
      return false;
   EnsureResearchFolders();
   int flags=FILE_COMMON|FILE_TXT|FILE_ANSI|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE;
   int handle=FileOpen(relPath,flags);
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("[CCT RESEARCH] FileOpen failed path=%s err=%d",relPath,GetLastError());
      return false;
     }
   int size=(int)FileSize(handle);
   if(size<=0 && header!="")
      FileWriteString(handle,header+"\r\n");
   FileSeek(handle,0,SEEK_END);
   FileWriteString(handle,line+"\r\n");
   FileClose(handle);
   return true;
  }

int FindCommissionEstimateRecord(const string symbol)
  {
   for(int i=0;i<g_nCommissionEstimates;i++)
      if(g_commissionEstimates[i].symbol==symbol)
         return i;
   return -1;
  }

void UpdateCommissionEstimate(const string symbol,double roundTurnPerLot)
  {
   if(symbol=="" || roundTurnPerLot<=0.0 || !MathIsValidNumber(roundTurnPerLot))
      return;
   int idx=FindCommissionEstimateRecord(symbol);
   if(idx<0)
     {
      ArrayResize(g_commissionEstimates,g_nCommissionEstimates+1);
      idx=g_nCommissionEstimates++;
      g_commissionEstimates[idx].symbol=symbol;
      g_commissionEstimates[idx].roundTurnPerLot=0.0;
      g_commissionEstimates[idx].sampleCount=0;
      g_commissionEstimates[idx].lastBootstrapAttempt=0;
     }
   if(g_commissionEstimates[idx].sampleCount<=0 || g_commissionEstimates[idx].roundTurnPerLot<=0.0)
     {
      g_commissionEstimates[idx].roundTurnPerLot=roundTurnPerLot;
      g_commissionEstimates[idx].sampleCount=1;
      return;
     }
   int samples=MathMin(g_commissionEstimates[idx].sampleCount,31);
   g_commissionEstimates[idx].roundTurnPerLot=
      ((g_commissionEstimates[idx].roundTurnPerLot*samples)+roundTurnPerLot)/(samples+1);
   g_commissionEstimates[idx].sampleCount=samples+1;
  }

int FindExecMilestoneCache(string genKey)
  {
   for(int i=0;i<g_nExecMilestones;i++)
      if(g_execMilestones[i].genKey==genKey)
         return i;
   return -1;
  }

void ResetDaySeparatorStats(DaySeparatorStats &stats)
  {
   stats.bullTriggered=0;
   stats.bearTriggered=0;
   stats.bullOpen=0;
   stats.bearOpen=0;
   stats.tpCount=0;
   stats.slCount=0;
   stats.beCount=0;
   stats.pnlCash=0.0;
  }

bool IsResolvedOutcome(SIB_STATE state)
  {
   return (state==SS_TP_HIT || state==SS_SL_HIT || state==SS_BE_HIT);
  }

bool IsValidExecPrice(double price)
  {
   return (MathIsValidNumber(price) && price>0.0);
  }

double CCTDailyRealizedPnL(datetime dayStart,datetime dayEnd)
  {
   if(dayEnd<=dayStart) return 0.0;
   if(!HistorySelect(dayStart,dayEnd))
      return 0.0;

   double total=0.0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;

      double pnl = HistoryDealGetDouble(ticket,DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket,DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket,DEAL_SWAP)
                 + HistoryDealGetDouble(ticket,DEAL_FEE);
      total+=pnl;
     }
   return total;
  }

double DailyLossCapCash()
  {
   if(!Inp_DailyLossStop || Inp_DailyLossMaxLosses<=0.0 || g_riskPct<=0.0)
      return 0.0;
   return EffectiveAccountBase()*(g_riskPct/100.0)*Inp_DailyLossMaxLosses;
  }

bool GetSymbolRiskModel(const string symbol,double &tickVal,double &tickSz,double &lotStep,double &minLot,double &maxLot)
  {
   tickVal=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   tickSz =SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   lotStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   minLot =SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   maxLot =SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(lotStep<=0.0) lotStep=0.01;
   return (tickVal>0.0 && tickSz>0.0 && minLot>0.0 && maxLot>0.0);
  }

double EstimateCashLossPerLot(const string symbol,double entry,double sl)
  {
   double slDist=MathAbs(entry-sl);
   if(slDist<_Point) return 0.0;

   ENUM_ORDER_TYPE orderType=(sl<entry)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double brokerProfit=0.0;
   if(OrderCalcProfit(orderType,symbol,1.0,entry,sl,brokerProfit))
     {
      brokerProfit=MathAbs(brokerProfit);
      if(MathIsValidNumber(brokerProfit) && brokerProfit>0.0)
         return brokerProfit;
     }

   double tickVal=0.0,tickSz=0.0,lotStep=0.0,minLot=0.0,maxLot=0.0;
   if(!GetSymbolRiskModel(symbol,tickVal,tickSz,lotStep,minLot,maxLot))
      return 0.0;
   return slDist/tickSz*tickVal;
  }

double EstimateRoundTurnCommissionPerLot(const string symbol)
  {
   int cachedIdx=FindCommissionEstimateRecord(symbol);
   if(cachedIdx>=0 && g_commissionEstimates[cachedIdx].roundTurnPerLot>0.0)
      return g_commissionEstimates[cachedIdx].roundTurnPerLot;

   datetime now=TimeCurrent();
   if(cachedIdx>=0
      && g_commissionEstimates[cachedIdx].lastBootstrapAttempt>0
      && now-g_commissionEstimates[cachedIdx].lastBootstrapAttempt<86400)
      return 0.0;
   if(cachedIdx<0)
     {
      ArrayResize(g_commissionEstimates,g_nCommissionEstimates+1);
      cachedIdx=g_nCommissionEstimates++;
      g_commissionEstimates[cachedIdx].symbol=symbol;
      g_commissionEstimates[cachedIdx].roundTurnPerLot=0.0;
      g_commissionEstimates[cachedIdx].sampleCount=0;
      g_commissionEstimates[cachedIdx].lastBootstrapAttempt=0;
     }
   g_commissionEstimates[cachedIdx].lastBootstrapAttempt=now;
   datetime from=now-30*86400;
   if(!HistorySelect(from,now+1))
      return 0.0;

   double totalCommPerDeal=0.0;
   double totalVolPerDeal=0.0;
   int    sampleDeals=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=symbol) continue;

      double vol=HistoryDealGetDouble(ticket,DEAL_VOLUME);
      if(vol<=0.0) continue;

      double comm=MathAbs(HistoryDealGetDouble(ticket,DEAL_COMMISSION))
                + MathAbs(HistoryDealGetDouble(ticket,DEAL_FEE));
      if(comm<=0.0) continue;

      totalCommPerDeal+=comm;
      totalVolPerDeal +=vol;
      sampleDeals++;
      if(sampleDeals>=24)
         break;
     }

   if(totalVolPerDeal<=0.0)
      return 0.0;

   double perDealPerLot=totalCommPerDeal/totalVolPerDeal;
   double estimate=perDealPerLot*2.0;
   UpdateCommissionEstimate(symbol,estimate);
   return estimate;
  }

double EstimateTradeWorstLossCash(const string symbol,double entry,double sl,double lots)
  {
   if(lots<=0.0) return 0.0;
   double priceLoss=EstimateCashLossPerLot(symbol,entry,sl)*lots;
   double commissionLoss=EstimateRoundTurnCommissionPerLot(symbol)*lots;
   return priceLoss+commissionLoss;
  }

double EstimateCommissionPriceOffset(const string symbol,double refPrice)
  {
   double commPerLot=EstimateRoundTurnCommissionPerLot(symbol);
   if(commPerLot<=0.0 || refPrice<=0.0)
      return 0.0;

   double tickSz=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSz<=0.0)
      tickSz=_Point;
   if(tickSz<=0.0)
      return 0.0;

   double downLoss=EstimateCashLossPerLot(symbol,refPrice,refPrice-tickSz);
   double upLoss  =EstimateCashLossPerLot(symbol,refPrice,refPrice+tickSz);
   double perTickLoss=MathMax(downLoss,upLoss);
   if(perTickLoss<=0.0)
      return 0.0;

   double cashPerPriceUnit=perTickLoss/tickSz;
   if(cashPerPriceUnit<=0.0)
      return 0.0;

   return commPerLot/cashPerPriceUnit;
  }

double NormalizeLotsDown(const string symbol,double lots)
  {
   double tickVal=0.0,tickSz=0.0,lotStep=0.0,minLot=0.0,maxLot=0.0;
   if(!GetSymbolRiskModel(symbol,tickVal,tickSz,lotStep,minLot,maxLot))
      return 0.0;
   if(lots<minLot) return 0.0;
   lots=MathMin(maxLot,lots);
   lots=MathFloor((lots+1e-12)/lotStep)*lotStep;
   int volDigits=(int)MathRound(-MathLog10(lotStep));
   if(volDigits<0) volDigits=0;
   if(volDigits>8) volDigits=8;
   lots=NormalizeDouble(lots,volDigits);
   if(lots+1e-12<minLot) return 0.0;
   return lots;
  }

double EstimateMarginPerLot(const string symbol,bool bull,double entryPrice)
  {
   if(entryPrice<=0.0)
      return 0.0;
   double margin=0.0;
   ENUM_ORDER_TYPE orderType=bull?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcMargin(orderType,symbol,1.0,entryPrice,margin))
      return 0.0;
   if(!MathIsValidNumber(margin) || margin<=0.0)
      return 0.0;
   return margin;
  }

double FitLotsToFreeMargin(const string symbol,bool bull,double entryPrice,double desiredLots,double &marginPerLot,double reserveFrac=0.98)
  {
   marginPerLot=EstimateMarginPerLot(symbol,bull,entryPrice);
   double lots=NormalizeLotsDown(symbol,desiredLots);
   if(lots<=0.0)
      return 0.0;
   if(marginPerLot<=0.0)
      return lots;

   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(!MathIsValidNumber(freeMargin) || freeMargin<=0.0)
      return 0.0;

   double usableMargin=freeMargin*MathMax(0.10,MathMin(1.0,reserveFrac));
   double fitLots=NormalizeLotsDown(symbol,usableMargin/marginPerLot);
   if(fitLots<=0.0)
      return 0.0;
   return MathMin(lots,fitLots);
  }

bool IsMarginHeavyAsset(const string symbol)
  {
   string sym=symbol;
   StringToUpper(sym);
   if(StringFind(sym,"XAU")>=0
      || StringFind(sym,"XAG")>=0
      || StringFind(sym,"OIL")>=0
      || StringFind(sym,"NAS")>=0
      || StringFind(sym,"NQ")>=0
      || StringFind(sym,"GER")>=0
      || StringFind(sym,"USTEC")>=0
      || StringFind(sym,"US30")>=0
      || StringFind(sym,"DJ")>=0
      || StringFind(sym,"SPX")>=0
      || StringFind(sym,"WTI")>=0
      || StringFind(sym,"BRENT")>=0)
      return true;

   ENUM_SYMBOL_CALC_MODE calcMode=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE);
   switch(calcMode)
     {
      case SYMBOL_CALC_MODE_CFD:
      case SYMBOL_CALC_MODE_CFDINDEX:
      case SYMBOL_CALC_MODE_CFDLEVERAGE:
      case SYMBOL_CALC_MODE_EXCH_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS:
         return true;
      default:
         break;
     }
   return false;
  }

double MarginSafetyTargetPercent(const string symbol="")
  {
   string riskSymbol=(symbol!="")?symbol:_Symbol;
   double target=IsMarginHeavyAsset(riskSymbol)?200.0:300.0;
   long soMode=AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   if(soMode==ACCOUNT_STOPOUT_MODE_PERCENT)
     {
      double soCall=AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
      double soStop=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
      if(soCall>0.0) target=MathMax(target,soCall*2.0);
      if(soStop>0.0) target=MathMax(target,soStop*3.0);
     }
   return target;
  }

double FitLotsToMarginSafety(const string symbol,double desiredLots,double marginPerLot)
  {
   double lots=NormalizeLotsDown(symbol,desiredLots);
   if(lots<=0.0 || marginPerLot<=0.0)
      return lots;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double usedMargin=AccountInfoDouble(ACCOUNT_MARGIN);
   if(!MathIsValidNumber(equity) || equity<=0.0)
      return 0.0;

   long soMode=AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   double addMargin=0.0;
   if(soMode==ACCOUNT_STOPOUT_MODE_PERCENT)
     {
      double target=MarginSafetyTargetPercent(symbol);
      double maxTotalMargin=(equity*100.0)/target;
      addMargin=maxTotalMargin-usedMargin;
     }
   else
     {
      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double reserve=MathMax(500.0,MathMax(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL),
                                           AccountInfoDouble(ACCOUNT_MARGIN_SO_SO))*3.0);
      addMargin=freeMargin-reserve;
     }

   if(!MathIsValidNumber(addMargin) || addMargin<=0.0)
      return 0.0;

   double fitLots=NormalizeLotsDown(symbol,addMargin/marginPerLot);
   if(fitLots<=0.0)
      return 0.0;
   return MathMin(lots,fitLots);
  }

double CalcLotsForRiskCash(const string symbol,double entry,double sl,double riskAmt)
  {
   if(riskAmt<=0.0) return 0.0;
   double perLotLoss=EstimateTradeWorstLossCash(symbol,entry,sl,1.0);
   if(perLotLoss<=0.0) return 0.0;
   return NormalizeLotsDown(symbol,riskAmt/perLotLoss);
  }

bool DailyLossGateHit(double &realizedPnL,double &lossUsed,double &lossCap,double &lossLeft)
  {
   realizedPnL=0.0;
   lossUsed=0.0;
   lossCap=0.0;
   lossLeft=0.0;
   if(!Inp_DailyLossStop)
      return false;

   lossCap=DailyLossCapCash();
   if(lossCap<=0.0)
      return false;

   datetime dayStart=BrokerDayOpen();
   datetime dayEnd=TimeCurrent()+1;
   realizedPnL=CCTDailyRealizedPnL(dayStart,dayEnd);
   lossUsed=MathMax(0.0,-realizedPnL);
   lossLeft=MathMax(0.0,lossCap-lossUsed);
   return (lossUsed+1e-8>=lossCap);
  }

string ExecVisualGVStem(string genKey)  { return "CCT_EXEC_"+_Symbol+"_"+genKey; }
string ExecVisualTrigGV(string genKey)  { return ExecVisualGVStem(genKey)+"_G"; }
string ExecVisualEntryGV(string genKey) { return ExecVisualGVStem(genKey)+"_E"; }
string ExecVisualSLGV(string genKey)    { return ExecVisualGVStem(genKey)+"_S"; }
string ExecVisualTPGV(string genKey)    { return ExecVisualGVStem(genKey)+"_T"; }
string ExecVisualCOGV(string genKey)    { return ExecVisualGVStem(genKey)+"_C"; }
string BrokerExecPresenceGV(string genKey){ return "CCT_EXECP_"+_Symbol+"_"+genKey; }
string ExecTouchGVStem(string genKey)   { return "CCT_TOUCH_"+_Symbol+"_"+genKey; }
string ExecTouchBEAnchorGV(string genKey){ return ExecTouchGVStem(genKey)+"_BA"; }
string ExecTouchBETimeGV(string genKey) { return ExecTouchGVStem(genKey)+"_BT"; }
string ExecTouchBEPriceGV(string genKey){ return ExecTouchGVStem(genKey)+"_BP"; }
string ExecTouchCOTimeGV(string genKey) { return ExecTouchGVStem(genKey)+"_CT"; }
string ExecTouchCOFinalGV(string genKey){ return ExecTouchGVStem(genKey)+"_CF"; }
string ExecTouchImmutableGV(string genKey){ return ExecTouchGVStem(genKey)+"_I"; }

string OutcomeGVStem(string genKey)  { return "CCT_OUT_"+_Symbol+"_"+genKey; }
string OutcomeStateGV(string genKey) { return OutcomeGVStem(genKey)+"_S"; }
string OutcomeTimeGV(string genKey)  { return OutcomeGVStem(genKey)+"_T"; }
string OutcomePriceGV(string genKey) { return OutcomeGVStem(genKey)+"_P"; }
string OutcomeImmutableGV(string genKey) { return OutcomeGVStem(genKey)+"_I"; }

void MarkBrokerTradePresence(string genKey)
  {
   if(genKey=="")
      return;
   if(FindBrokerExecPresenceRecord(genKey)<0)
     {
      ArrayResize(g_brokerExecPresence,g_nBrokerExecPresence+1);
      g_brokerExecPresence[g_nBrokerExecPresence].genKey=genKey;
      g_nBrokerExecPresence++;
     }
   GlobalVariableSet(BrokerExecPresenceGV(genKey),1.0);
  }

bool HasCachedBrokerTradePresence(string genKey)
  {
   if(genKey=="")
      return false;
   if(FindBrokerExecPresenceRecord(genKey)>=0)
      return true;
   if(!GlobalVariableCheck(BrokerExecPresenceGV(genKey)))
      return false;
   MarkBrokerTradePresence(genKey);
   return true;
  }

void ClearPersistedExecVisualRecord(string genKey)
  {
   GlobalVariableDel(ExecVisualTrigGV(genKey));
   GlobalVariableDel(ExecVisualEntryGV(genKey));
   GlobalVariableDel(ExecVisualSLGV(genKey));
   GlobalVariableDel(ExecVisualTPGV(genKey));
   GlobalVariableDel(ExecVisualCOGV(genKey));
  }

bool IsValidReplayGeometry(string genKey,datetime triggerTime,double entryPrice,double slPrice,double tpPrice)
  {
   if(triggerTime<=0) return false;
   if(!IsValidExecPrice(entryPrice) || !IsValidExecPrice(slPrice) || !IsValidExecPrice(tpPrice))
      return false;

   datetime now=MarketReferenceTime();
   datetime oldest=(datetime)(StructuralPrefetchStart()-31*86400);
   if(triggerTime>now+86400 || triggerTime<oldest)
      return false;

   double tol=MathMax(_Point,1e-8);
   bool bull=(StringFind(genKey,"BU_")==0);
   if(bull)
      return (slPrice<entryPrice-tol && tpPrice>entryPrice+tol);
   return (slPrice>entryPrice+tol && tpPrice<entryPrice-tol);
  }

bool GetBrokerExecGeometry(string genKey,datetime &triggerTime,double &entryPrice,double &slPrice,double &tpPrice)
  {
   triggerTime=0;
   entryPrice=0.0;
   slPrice=0.0;
   tpPrice=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      string matchedGenKey="";
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
      if(matchedGenKey!=genKey) continue;

      triggerTime=(datetime)PositionGetInteger(POSITION_TIME);
      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      slPrice=PositionGetDouble(POSITION_SL);
      tpPrice=PositionGetDouble(POSITION_TP);
      return IsValidReplayGeometry(genKey,triggerTime,entryPrice,slPrice,tpPrice);
     }

   datetime tradeTime=(datetime)StringToInteger(StringSubstr(genKey,3));
   if(tradeTime<=0)
      tradeTime=MarketReferenceTime();
   HistorySelect(tradeTime-86400*30,MarketReferenceTime()+86400);

   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;

      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      string matchedGenKey="";
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
      if(matchedGenKey!=genKey) continue;

      triggerTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      entryPrice=HistoryDealGetDouble(ticket,DEAL_PRICE);
      slPrice=HistoryDealGetDouble(ticket,DEAL_SL);
      tpPrice=HistoryDealGetDouble(ticket,DEAL_TP);
      if(IsValidReplayGeometry(genKey,triggerTime,entryPrice,slPrice,tpPrice))
         return true;
     }

   triggerTime=0;
   entryPrice=0.0;
   slPrice=0.0;
   tpPrice=0.0;
   return false;
  }

bool GetOpenPositionExecGeometry(string genKey,datetime &triggerTime,double &entryPrice,double &slPrice,double &tpPrice)
  {
   triggerTime=0;
   entryPrice=0.0;
   slPrice=0.0;
   tpPrice=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      string matchedGenKey="";
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
      if(matchedGenKey!=genKey) continue;

      triggerTime=(datetime)PositionGetInteger(POSITION_TIME);
      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      slPrice=PositionGetDouble(POSITION_SL);
      tpPrice=PositionGetDouble(POSITION_TP);
      return IsValidReplayGeometry(genKey,triggerTime,entryPrice,slPrice,tpPrice);
     }

   return false;
  }

int EncodeOutcomeState(SIB_STATE state)
  {
   if(state==SS_TP_HIT) return 1;
   if(state==SS_SL_HIT) return 2;
   if(state==SS_BE_HIT) return 3;
   return 0;
  }

SIB_STATE DecodeOutcomeState(int code)
  {
   if(code==1) return SS_TP_HIT;
   if(code==2) return SS_SL_HIT;
   if(code==3) return SS_BE_HIT;
   return SS_UNKNOWN_OUTCOME;
  }

void ClearPersistedOutcome(string genKey)
  {
   GlobalVariableDel(OutcomeStateGV(genKey));
   GlobalVariableDel(OutcomeTimeGV(genKey));
   GlobalVariableDel(OutcomePriceGV(genKey));
   GlobalVariableDel(OutcomeImmutableGV(genKey));
  }

void PersistOutcomeRecord(string genKey,SIB_STATE state,datetime exitTime,double exitPrice,bool immutable)
  {
   if(!IsResolvedOutcome(state))
     {
      ClearPersistedOutcome(genKey);
      return;
     }
   GlobalVariableSet(OutcomeStateGV(genKey),(double)EncodeOutcomeState(state));
   GlobalVariableSet(OutcomeTimeGV(genKey),(double)((long)exitTime));
   GlobalVariableSet(OutcomePriceGV(genKey),exitPrice);
   GlobalVariableSet(OutcomeImmutableGV(genKey),immutable?1.0:0.0);
  }

bool LoadPersistedOutcome(string genKey,SIB_STATE &state,datetime &exitTime,double &exitPrice,bool &immutable)
  {
   immutable=false;
   if(!GlobalVariableCheck(OutcomeStateGV(genKey)))
      return false;
   state=DecodeOutcomeState((int)GlobalVariableGet(OutcomeStateGV(genKey)));
   if(!IsResolvedOutcome(state))
      return false;
   exitTime=GlobalVariableCheck(OutcomeTimeGV(genKey))
           ? (datetime)((long)GlobalVariableGet(OutcomeTimeGV(genKey)))
           : 0;
   exitPrice=GlobalVariableCheck(OutcomePriceGV(genKey))
            ? GlobalVariableGet(OutcomePriceGV(genKey))
            : 0.0;
   immutable=GlobalVariableCheck(OutcomeImmutableGV(genKey))
            ? (GlobalVariableGet(OutcomeImmutableGV(genKey))>0.5)
            : false;
   return true;
  }

void PersistExecVisualRecord(string genKey,datetime triggerTime,double entryPrice,double slPrice,double tpPrice,double coPrice=0.0)
  {
   if(triggerTime>0) GlobalVariableSet(ExecVisualTrigGV(genKey),(double)((long)triggerTime));
   if(entryPrice>0.0) GlobalVariableSet(ExecVisualEntryGV(genKey),entryPrice);
   if(slPrice>0.0)    GlobalVariableSet(ExecVisualSLGV(genKey),slPrice);
   if(tpPrice>0.0)    GlobalVariableSet(ExecVisualTPGV(genKey),tpPrice);
   if(coPrice>0.0)    GlobalVariableSet(ExecVisualCOGV(genKey),coPrice);
  }

bool LoadPersistedExecVisualRecord(string genKey,datetime &triggerTime,double &entryPrice,double &slPrice,double &tpPrice,double &coPrice)
  {
   bool hasTrig=GlobalVariableCheck(ExecVisualTrigGV(genKey));
   bool hasEntry=GlobalVariableCheck(ExecVisualEntryGV(genKey));
   bool hasSL=GlobalVariableCheck(ExecVisualSLGV(genKey));
   bool hasTP=GlobalVariableCheck(ExecVisualTPGV(genKey));
   bool hasCO=GlobalVariableCheck(ExecVisualCOGV(genKey));
   if(!hasTrig && !hasEntry && !hasSL && !hasTP && !hasCO)
      return false;
   triggerTime=hasTrig?(datetime)((long)GlobalVariableGet(ExecVisualTrigGV(genKey))):0;
   entryPrice=hasEntry?GlobalVariableGet(ExecVisualEntryGV(genKey)):0.0;
   slPrice=hasSL?GlobalVariableGet(ExecVisualSLGV(genKey)):0.0;
   tpPrice=hasTP?GlobalVariableGet(ExecVisualTPGV(genKey)):0.0;
   coPrice=hasCO?GlobalVariableGet(ExecVisualCOGV(genKey)):0.0;
   if((hasTrig || hasEntry || hasSL || hasTP)
      && !IsValidReplayGeometry(genKey,triggerTime,entryPrice,slPrice,tpPrice))
     {
      PrintFormat("[CCT EXEC] DROP persisted replay genKey=%s trig=%I64d entry=%.5f sl=%.5f tp=%.5f",
                  genKey,(long)triggerTime,entryPrice,slPrice,tpPrice);
      ClearPersistedExecVisualRecord(genKey);
      triggerTime=0;
      entryPrice=0.0;
      slPrice=0.0;
      tpPrice=0.0;
      coPrice=0.0;
      return false;
     }
   return (triggerTime>0 || entryPrice>0.0 || slPrice>0.0 || tpPrice>0.0 || coPrice>0.0);
  }

int FindOutcomeRecord(string genKey)
  {
   for(int i=0;i<g_nOutcomes;i++)
      if(g_outcomes[i].genKey==genKey)
         return i;
   return -1;
  }

int FindExecVisualRecord(string genKey)
  {
   for(int i=0;i<g_nExecVisuals;i++)
      if(g_execVisuals[i].genKey==genKey)
         return i;
   return -1;
  }

int FindExecTouchRecord(string genKey)
  {
   for(int i=0;i<g_nExecTouches;i++)
      if(g_execTouches[i].genKey==genKey)
         return i;
   return -1;
  }

void ClearPersistedExecTouchRecord(string genKey)
  {
   GlobalVariableDel(ExecTouchBEAnchorGV(genKey));
   GlobalVariableDel(ExecTouchBETimeGV(genKey));
   GlobalVariableDel(ExecTouchBEPriceGV(genKey));
   GlobalVariableDel(ExecTouchCOTimeGV(genKey));
   GlobalVariableDel(ExecTouchCOFinalGV(genKey));
   GlobalVariableDel(ExecTouchImmutableGV(genKey));
  }

void PersistExecTouchRecord(string genKey,datetime beAnchorTime,datetime beTouchTime,double bePrice,datetime coTouchTime,bool coFinalized,bool immutable)
  {
   ClearPersistedExecTouchRecord(genKey);
   if(beAnchorTime>0) GlobalVariableSet(ExecTouchBEAnchorGV(genKey),(double)((long)beAnchorTime));
   if(beTouchTime>0) GlobalVariableSet(ExecTouchBETimeGV(genKey),(double)((long)beTouchTime));
   if(bePrice>0.0)   GlobalVariableSet(ExecTouchBEPriceGV(genKey),bePrice);
   if(coTouchTime>0) GlobalVariableSet(ExecTouchCOTimeGV(genKey),(double)((long)coTouchTime));
   GlobalVariableSet(ExecTouchCOFinalGV(genKey),coFinalized?1.0:0.0);
   GlobalVariableSet(ExecTouchImmutableGV(genKey),immutable?1.0:0.0);
  }

bool LoadPersistedExecTouchRecord(string genKey,datetime &beAnchorTime,datetime &beTouchTime,double &bePrice,datetime &coTouchTime,bool &coFinalized,bool &immutable)
  {
   bool hasAny=false;
   beAnchorTime=0;
   beTouchTime=0;
   bePrice=0.0;
   coTouchTime=0;
   coFinalized=false;
   immutable=false;
   if(GlobalVariableCheck(ExecTouchBEAnchorGV(genKey)))
     {
      beAnchorTime=(datetime)((long)GlobalVariableGet(ExecTouchBEAnchorGV(genKey)));
      hasAny=true;
     }
   if(GlobalVariableCheck(ExecTouchBETimeGV(genKey)))
     {
      beTouchTime=(datetime)((long)GlobalVariableGet(ExecTouchBETimeGV(genKey)));
      hasAny=true;
     }
   if(GlobalVariableCheck(ExecTouchBEPriceGV(genKey)))
     {
      bePrice=GlobalVariableGet(ExecTouchBEPriceGV(genKey));
      hasAny=true;
     }
   if(GlobalVariableCheck(ExecTouchCOTimeGV(genKey)))
     {
      coTouchTime=(datetime)((long)GlobalVariableGet(ExecTouchCOTimeGV(genKey)));
      hasAny=true;
     }
   if(GlobalVariableCheck(ExecTouchCOFinalGV(genKey)))
     {
      coFinalized=(GlobalVariableGet(ExecTouchCOFinalGV(genKey))>0.5);
      hasAny=true;
     }
   if(GlobalVariableCheck(ExecTouchImmutableGV(genKey)))
     {
      immutable=(GlobalVariableGet(ExecTouchImmutableGV(genKey))>0.5);
      hasAny=true;
     }
   return hasAny;
  }

void SetExecTouchRecord(string genKey,datetime beAnchorTime,datetime beTouchTime,double bePrice,datetime coTouchTime,bool coFinalized,bool immutable)
  {
   int idx=FindExecTouchRecord(genKey);
   if(idx<0)
     {
      ArrayResize(g_execTouches,g_nExecTouches+1);
      idx=g_nExecTouches++;
      g_execTouches[idx].genKey=genKey;
      g_execTouches[idx].beAnchorTime=0;
      g_execTouches[idx].beTouchTime=0;
      g_execTouches[idx].bePrice=0.0;
      g_execTouches[idx].coTouchTime=0;
      g_execTouches[idx].coFinalized=false;
      g_execTouches[idx].immutable=false;
     }
   g_execTouches[idx].beAnchorTime=beAnchorTime;
   g_execTouches[idx].beTouchTime=beTouchTime;
   g_execTouches[idx].bePrice=bePrice;
   g_execTouches[idx].coTouchTime=coTouchTime;
   g_execTouches[idx].coFinalized=coFinalized;
   g_execTouches[idx].immutable=immutable;
   PersistExecTouchRecord(genKey,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized,immutable);
  }

bool GetExecTouchRecord(string genKey,datetime &beAnchorTime,datetime &beTouchTime,double &bePrice,datetime &coTouchTime,bool &coFinalized,bool &immutable)
  {
   beAnchorTime=0;
   beTouchTime=0;
   bePrice=0.0;
   coTouchTime=0;
   coFinalized=false;
   immutable=false;

   int idx=FindExecTouchRecord(genKey);
   if(idx>=0)
     {
      beAnchorTime=g_execTouches[idx].beAnchorTime;
      beTouchTime=g_execTouches[idx].beTouchTime;
      bePrice=g_execTouches[idx].bePrice;
      coTouchTime=g_execTouches[idx].coTouchTime;
      coFinalized=g_execTouches[idx].coFinalized;
      immutable=g_execTouches[idx].immutable;
      return (beAnchorTime>0 || beTouchTime>0 || coTouchTime>0 || coFinalized);
     }

   if(LoadPersistedExecTouchRecord(genKey,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized,immutable))
     {
      SetExecTouchRecord(genKey,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized,immutable);
      return true;
     }

   return false;
  }

void UpdateExecVisualRecord(string genKey,double entryPrice,double slPrice,double tpPrice,double coPrice=0.0)
  {
   if(entryPrice<=0.0 && slPrice<=0.0 && tpPrice<=0.0 && coPrice<=0.0)
      return;
   int idx=FindExecVisualRecord(genKey);
   if(idx<0)
     {
      ArrayResize(g_execVisuals,g_nExecVisuals+1);
      idx=g_nExecVisuals++;
      g_execVisuals[idx].genKey=genKey;
      g_execVisuals[idx].triggerTime=0;
      g_execVisuals[idx].entryPrice=0.0;
      g_execVisuals[idx].slPrice=0.0;
      g_execVisuals[idx].tpPrice=0.0;
      g_execVisuals[idx].coPrice=0.0;
     }
   if(entryPrice>0.0) g_execVisuals[idx].entryPrice=entryPrice;
   if(slPrice>0.0)    g_execVisuals[idx].slPrice=slPrice;
   if(tpPrice>0.0)    g_execVisuals[idx].tpPrice=tpPrice;
   if(coPrice>0.0)    g_execVisuals[idx].coPrice=coPrice;
   PersistExecVisualRecord(genKey,g_execVisuals[idx].triggerTime,g_execVisuals[idx].entryPrice,g_execVisuals[idx].slPrice,g_execVisuals[idx].tpPrice,g_execVisuals[idx].coPrice);
  }

void UpdateExecReplayRecord(string genKey,datetime triggerTime,double entryPrice,double slPrice,double tpPrice,double coPrice=0.0,bool overwriteGeometry=false)
  {
   if(triggerTime<=0 || entryPrice<=0.0 || slPrice<=0.0 || tpPrice<=0.0)
      return;
   int idx=FindExecVisualRecord(genKey);
   if(idx<0)
     {
      ArrayResize(g_execVisuals,g_nExecVisuals+1);
      idx=g_nExecVisuals++;
      g_execVisuals[idx].genKey=genKey;
      g_execVisuals[idx].triggerTime=0;
      g_execVisuals[idx].entryPrice=0.0;
      g_execVisuals[idx].slPrice=0.0;
      g_execVisuals[idx].tpPrice=0.0;
      g_execVisuals[idx].coPrice=0.0;
     }
   bool replaceNow=overwriteGeometry
                || g_execVisuals[idx].triggerTime<=0
                || triggerTime<g_execVisuals[idx].triggerTime
                || g_execVisuals[idx].entryPrice<=0.0
                || g_execVisuals[idx].slPrice<=0.0
                || g_execVisuals[idx].tpPrice<=0.0;
   if(g_execVisuals[idx].triggerTime<=0 || triggerTime<g_execVisuals[idx].triggerTime)
      g_execVisuals[idx].triggerTime=triggerTime;
   if(replaceNow)
     {
      g_execVisuals[idx].entryPrice=entryPrice;
      g_execVisuals[idx].slPrice=slPrice;
      g_execVisuals[idx].tpPrice=tpPrice;
     }
   if(coPrice>0.0)
      g_execVisuals[idx].coPrice=coPrice;
   PersistExecVisualRecord(genKey,g_execVisuals[idx].triggerTime,g_execVisuals[idx].entryPrice,g_execVisuals[idx].slPrice,g_execVisuals[idx].tpPrice,g_execVisuals[idx].coPrice);
  }

bool GetExecVisualRecord(string genKey,double &entryPrice,double &slPrice,double &tpPrice)
  {
   entryPrice=0.0;
   slPrice=0.0;
   tpPrice=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      string matchedGenKey;
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
      if(matchedGenKey!=genKey) continue;

      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      slPrice=PositionGetDouble(POSITION_SL);
      tpPrice=PositionGetDouble(POSITION_TP);
      UpdateExecVisualRecord(genKey,entryPrice,slPrice,tpPrice);
      return true;
     }

   int idx=FindExecVisualRecord(genKey);
   if(idx>=0)
     {
      entryPrice=g_execVisuals[idx].entryPrice;
      slPrice=g_execVisuals[idx].slPrice;
      tpPrice=g_execVisuals[idx].tpPrice;
      return (entryPrice>0.0 || slPrice>0.0 || tpPrice>0.0);
     }

   datetime brokerTriggerTime=0;
   if(GetBrokerExecGeometry(genKey,brokerTriggerTime,entryPrice,slPrice,tpPrice))
     {
      UpdateExecReplayRecord(genKey,brokerTriggerTime,entryPrice,slPrice,tpPrice,0.0,false);
      return true;
     }

   datetime triggerTime=0;
   double coPrice=0.0;
   if(LoadPersistedExecVisualRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice))
     {
      UpdateExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice,false);
      return true;
     }

   return false;
  }

bool GetExecCOPrice(string genKey,double &coPrice)
  {
   coPrice=0.0;
   int idx=FindExecVisualRecord(genKey);
   if(idx>=0 && g_execVisuals[idx].coPrice>0.0)
     {
      coPrice=g_execVisuals[idx].coPrice;
      return true;
     }
   datetime triggerTime=0;
   double entryPrice=0.0, slPrice=0.0, tpPrice=0.0;
   if(LoadPersistedExecVisualRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice))
     {
      UpdateExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice,false);
      return (coPrice>0.0);
     }
   return false;
  }

bool GetExecReplayRecord(string genKey,datetime &triggerTime,double &entryPrice,double &slPrice,double &tpPrice,double &coPrice)
  {
   triggerTime=0;
   entryPrice=0.0;
   slPrice=0.0;
   tpPrice=0.0;
   coPrice=0.0;

   int idx=FindExecVisualRecord(genKey);
   if(idx>=0)
     {
      triggerTime=g_execVisuals[idx].triggerTime;
      entryPrice=g_execVisuals[idx].entryPrice;
      slPrice=g_execVisuals[idx].slPrice;
      tpPrice=g_execVisuals[idx].tpPrice;
      coPrice=g_execVisuals[idx].coPrice;
      if(triggerTime>0 && entryPrice>0.0 && slPrice>0.0 && tpPrice>0.0)
         return true;
     }

   if(GetBrokerExecGeometry(genKey,triggerTime,entryPrice,slPrice,tpPrice))
     {
      UpdateExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,0.0,false);
      return true;
     }

   if(LoadPersistedExecVisualRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice))
     {
      UpdateExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice,false);
      return (triggerTime>0 && entryPrice>0.0 && slPrice>0.0 && tpPrice>0.0);
     }

   return false;
  }

bool HasExecutionVisualBacking(string genKey)
  {
   if(genKey=="")
      return false;

   datetime triggerTime=0;
   double entryPrice=0.0,slPrice=0.0,tpPrice=0.0,coPrice=0.0;
   bool hasReplayRecord=GetExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice);

   double visualEntry=0.0,visualSL=0.0,visualTP=0.0;
   bool hasVisualRecord=GetExecVisualRecord(genKey,visualEntry,visualSL,visualTP);
   if((entryPrice<=0.0 || slPrice<=0.0 || tpPrice<=0.0) && hasVisualRecord)
     {
      if(entryPrice<=0.0) entryPrice=visualEntry;
      if(slPrice<=0.0)    slPrice=visualSL;
      if(tpPrice<=0.0)    tpPrice=visualTP;
     }

   datetime liveTriggerTime=0;
   double liveEntry=0.0,liveSL=0.0,liveTP=0.0;
   bool hasOpenGeometry=GetOpenPositionExecGeometry(genKey,liveTriggerTime,liveEntry,liveSL,liveTP);
   if((entryPrice<=0.0 || slPrice<=0.0 || tpPrice<=0.0) && hasOpenGeometry)
     {
      if(triggerTime<=0)  triggerTime=liveTriggerTime;
      if(entryPrice<=0.0) entryPrice=liveEntry;
      if(slPrice<=0.0)    slPrice=liveSL;
      if(tpPrice<=0.0)    tpPrice=liveTP;
     }

   bool hasGeometry=(entryPrice>0.0 && slPrice>0.0 && tpPrice>0.0);
   if(!hasGeometry)
      return false;

   if(hasOpenGeometry)
      return true;

   datetime exitTime=0;
   double exitPrice=0.0;
   if(GetPOIExit(genKey,exitTime,exitPrice) && IsRecentExecutionVisualTime(exitTime))
      return true;

   if(hasReplayRecord && HasBrokerTradePresence(genKey))
      return (triggerTime>0 && IsRecentExecutionVisualTime(triggerTime));

   return (triggerTime>0 && IsRecentExecutionVisualTime(triggerTime));
  }

bool ResolveExecMilestones(string genKey,bool bull,datetime triggerTime,double coPrice,datetime familyEndTime,
                           datetime &beAnchorTime,datetime &beTouchTime,double &bePrice,datetime &coTouchTime,bool &coFinalized)
  {
   bool brokerBacked=HasBrokerTradePresence(genKey);
   bool immutableTouch=false;
   GetExecTouchRecord(genKey,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized,immutableTouch);

   double entryPrice=0.0, slPrice=0.0, tpPrice=0.0;
   if(!GetExecVisualRecord(genKey,entryPrice,slPrice,tpPrice) || entryPrice<=0.0 || tpPrice<=0.0 || triggerTime<=0)
      return (beAnchorTime>0 || beTouchTime>0 || coTouchTime>0 || coFinalized);

   double tpDist=MathAbs(tpPrice-entryPrice);
   if(tpDist<=_Point)
      return (beAnchorTime>0 || beTouchTime>0 || coTouchTime>0 || coFinalized);

   double dir=bull?1.0:-1.0;
   double beTrigPx=entryPrice + dir*((double)Inp_BE_Trigger/100.0)*tpDist;
   double beMovePx=entryPrice + dir*((double)Inp_BE_Move/100.0)*tpDist;
   if(bePrice<=0.0) bePrice=beMovePx;

   datetime scanEnd=(familyEndTime>0)?familyEndTime:(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   if(scanEnd<triggerTime)
      return (beAnchorTime>0 || beTouchTime>0 || coTouchTime>0 || coFinalized);

   int cacheIdx=FindExecMilestoneCache(genKey);
   if(cacheIdx>=0
      && g_execMilestones[cacheIdx].bull==bull
      && g_execMilestones[cacheIdx].triggerTime==triggerTime
      && g_execMilestones[cacheIdx].familyEndTime==familyEndTime
      && g_execMilestones[cacheIdx].scanEnd==scanEnd
      && MathAbs(g_execMilestones[cacheIdx].coPrice-coPrice)<=_Point)
     {
      beAnchorTime=g_execMilestones[cacheIdx].beAnchorTime;
      beTouchTime =g_execMilestones[cacheIdx].beTouchTime;
      bePrice     =g_execMilestones[cacheIdx].bePrice;
      coTouchTime =g_execMilestones[cacheIdx].coTouchTime;
      coFinalized =g_execMilestones[cacheIdx].coFinalized;
      return (beAnchorTime>0 || beTouchTime>0 || coTouchTime>0 || coFinalized);
     }

   MqlRates ltf[];
   datetime scanTo=(datetime)(scanEnd+(datetime)PeriodSeconds(LTF()));
   int nl=CopyLTFWindowFromCache(triggerTime,scanTo,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),triggerTime,scanTo,ltf);
   if(nl<1)
      return (beTouchTime>0 || coTouchTime>0 || coFinalized);

   bool changed=false;
   for(int k=0;k<nl;k++)
     {
      datetime barTime=ltf[k].time;
      if(beTouchTime==0)
        {
         bool beAnchorTouched=bull?(ltf[k].low<=beMovePx):(ltf[k].high>=beMovePx);
         if(beAnchorTouched)
           {
            beAnchorTime=barTime;
            changed=true;
           }
         bool beTouched=bull?(ltf[k].high>=beTrigPx):(ltf[k].low<=beTrigPx);
         if(beTouched)
           {
            beTouchTime=barTime;
            if(beAnchorTime<=0) beAnchorTime=barTime;
            bePrice=beMovePx;
            changed=true;
           }
        }
      if(coPrice>0.0 && coTouchTime==0 && !coFinalized)
        {
         bool coTouched=bull?(ltf[k].high>=coPrice):(ltf[k].low<=coPrice);
         if(coTouched)
           {
            coTouchTime=barTime;
            coFinalized=true;
            changed=true;
           }
        }
     }

   if(familyEndTime>0 && coTouchTime==0 && !coFinalized)
     {
      coFinalized=true;
      changed=true;
     }

   if(changed || FindExecTouchRecord(genKey)<0 || !brokerBacked || immutableTouch!=brokerBacked)
      SetExecTouchRecord(genKey,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized,brokerBacked);

   if(cacheIdx<0)
     {
      ArrayResize(g_execMilestones,g_nExecMilestones+1);
      cacheIdx=g_nExecMilestones++;
      g_execMilestones[cacheIdx].genKey=genKey;
     }
   g_execMilestones[cacheIdx].bull=bull;
   g_execMilestones[cacheIdx].triggerTime=triggerTime;
   g_execMilestones[cacheIdx].coPrice=coPrice;
   g_execMilestones[cacheIdx].familyEndTime=familyEndTime;
   g_execMilestones[cacheIdx].scanEnd=scanEnd;
   g_execMilestones[cacheIdx].beAnchorTime=beAnchorTime;
   g_execMilestones[cacheIdx].beTouchTime=beTouchTime;
   g_execMilestones[cacheIdx].bePrice=bePrice;
   g_execMilestones[cacheIdx].coTouchTime=coTouchTime;
   g_execMilestones[cacheIdx].coFinalized=coFinalized;

   return (beAnchorTime>0 || beTouchTime>0 || coTouchTime>0 || coFinalized);
  }

string BuildTradeComment(bool bull,datetime birthTime,datetime triggerTime,string modelLabel)
  {
   string modelSuffix="";
   if(modelLabel=="CCT+TS")
      modelSuffix=" TS";
   else if(modelLabel=="CCT+TS Ext")
      modelSuffix=" TS Ext";
   else if(modelLabel!="" && modelLabel!="CCT")
      modelSuffix=" "+modelLabel;

   string triggerNY=TimeToString(ToNY(triggerTime),TIME_DATE|TIME_MINUTES);
   return StringFormat("CCT %s%s NY:%s B:%s",
                       bull?"BUY":"SELL",
                       modelSuffix,
                       triggerNY,
                       TimeToString(birthTime,TIME_DATE|TIME_MINUTES));
  }

int ExecModelLabelRank(string modelLabel)
  {
   if(modelLabel=="CCT+TS Ext")
      return 2;
   if(modelLabel=="CCT+TS")
      return 1;
   return 0;
  }

string MergeExecModelLabel(string existingLabel,string incomingLabel)
  {
   string existing=(existingLabel!="")?existingLabel:"CCT";
   string incoming=(incomingLabel!="")?incomingLabel:"CCT";
   if(ExecModelLabelRank(incoming)>ExecModelLabelRank(existing))
      return incoming;
   return existing;
  }

bool TryGenKeyFromComment(string comment,string &outGenKey,bool &outBull)
  {
   outGenKey="";
   outBull=false;
   if(StringFind(comment,"CCT ")<0) return false;

   int birthIdx=StringFind(comment,"B:");
   if(birthIdx<0) return false;

   string birthStr=TrimSpaces(StringSubstr(comment,birthIdx+2));
   if(StringLen(birthStr)<16) return false;
   if(StringGetCharacter(birthStr,4)!='.' || StringGetCharacter(birthStr,7)!='.'
      || StringGetCharacter(birthStr,10)!=' ' || StringGetCharacter(birthStr,13)!=':')
      return false;
   datetime birthTime=StringToTime(birthStr);
   if(birthTime<=0) return false;

   outBull=(StringFind(comment,"CCT BUY")>=0);
   outGenKey=(outBull?"BU_":"BE_")+IntegerToString((int)birthTime);
   return true;
  }

string ResearchModelLabelFromComment(string comment)
  {
   int nyIdx=StringFind(comment," NY:");
   if(nyIdx<0)
      return "";
   string prefix=StringSubstr(comment,0,nyIdx);
   if(StringFind(prefix,"CCT BUY")==0)
      prefix=StringSubstr(prefix,StringLen("CCT BUY"));
   else if(StringFind(prefix,"CCT SELL")==0)
      prefix=StringSubstr(prefix,StringLen("CCT SELL"));
   else
      return "";
   prefix=TrimSpaces(prefix);
   if(prefix=="")
      return "CCT";
   if(prefix=="TS")
      return "CCT+TS";
   if(prefix=="TS Ext")
      return "CCT+TS Ext";
   return prefix;
  }

string ResearchOutcomeLabel(SIB_STATE state)
  {
   if(state==SS_TP_HIT) return "TP";
   if(state==SS_SL_HIT) return "SL";
   if(state==SS_BE_HIT) return "BE";
   if(state==SS_TRIGGERED) return "OPEN";
   return "UNKNOWN";
  }

string ResearchDealReasonLabel(ENUM_DEAL_REASON reason)
  {
   if(reason==DEAL_REASON_TP) return "TP";
   if(reason==DEAL_REASON_SL) return "SL";
   if(reason==DEAL_REASON_EXPERT) return "EXPERT";
   if(reason==DEAL_REASON_SO) return "STOP_OUT";
   if(reason==DEAL_REASON_VMARGIN) return "VMARGIN";
   return IntegerToString((int)reason);
  }

string ResearchWeekdayLabel(int dow)
  {
   if(dow==1) return "Mon";
   if(dow==2) return "Tue";
   if(dow==3) return "Wed";
   if(dow==4) return "Thu";
   if(dow==5) return "Fri";
   if(dow==6) return "Sat";
   return "Sun";
  }

bool HasOpenCCTPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"CCT ")<0) continue;
      return true;
     }
   return false;
  }

bool HasOpenCCTPositionForGenKey(string genKey)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600) continue;
      string comment=PositionGetString(POSITION_COMMENT);
      string matchedGenKey="";
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
     if(matchedGenKey==genKey)
        return true;
     }
   return false;
  }

bool HasHistoryCCTEntryForGenKey(string genKey)
  {
   if(genKey=="") return false;
   datetime tradeTime=(datetime)StringToInteger(StringSubstr(genKey,3));
   if(tradeTime<=0)
      tradeTime=TimeCurrent();
   HistorySelect(tradeTime-86400*30,TimeCurrent()+86400);
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      string matchedGenKey="";
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
      if(matchedGenKey==genKey)
        {
         MarkBrokerTradePresence(genKey);
         return true;
        }
     }
   return false;
  }

bool HasBrokerTradePresence(string genKey)
  {
   if(genKey=="")
      return false;
   if(HasOpenCCTPositionForGenKey(genKey))
     {
      MarkBrokerTradePresence(genKey);
      return true;
     }
   if(HasCachedBrokerTradePresence(genKey))
      return true;
   return HasHistoryCCTEntryForGenKey(genKey);
  }

double RealizedPositionPnLCash(ulong positionId)
  {
   double pnl=0.0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      pnl += HistoryDealGetDouble(ticket,DEAL_PROFIT)
           + HistoryDealGetDouble(ticket,DEAL_COMMISSION)
           + HistoryDealGetDouble(ticket,DEAL_SWAP)
           + HistoryDealGetDouble(ticket,DEAL_FEE);
     }
   return pnl;
  }

int FindResearchExportRecord(const string genKey,ulong positionId)
  {
   for(int i=0;i<g_nResearchExports;i++)
      if(g_researchExports[i].genKey==genKey && g_researchExports[i].positionId==positionId)
         return i;
   return -1;
  }

void MarkResearchExportRecord(const string genKey,ulong positionId)
  {
   if(FindResearchExportRecord(genKey,positionId)>=0)
      return;
   ArrayResize(g_researchExports,g_nResearchExports+1);
   g_researchExports[g_nResearchExports].genKey=genKey;
   g_researchExports[g_nResearchExports].positionId=positionId;
   g_nResearchExports++;
  }

int FindResearchEntrySnapshot(const ulong positionId)
  {
   for(int i=0;i<g_nResearchEntries;i++)
      if(g_researchEntries[i].positionId==positionId)
         return i;
   return -1;
  }

void CacheResearchEntrySnapshot(const ulong positionId,
                                const string genKey,
                                const bool bull,
                                const datetime entryTime,
                                const double entryPrice,
                                const double entryVolume,
                                const string entryComment)
  {
   if(positionId==0)
      return;
   int idx=FindResearchEntrySnapshot(positionId);
   if(idx<0)
     {
      ArrayResize(g_researchEntries,g_nResearchEntries+1);
      idx=g_nResearchEntries++;
      g_researchEntries[idx].positionId=positionId;
      g_researchEntries[idx].genKey="";
      g_researchEntries[idx].bull=false;
      g_researchEntries[idx].entryTime=0;
      g_researchEntries[idx].entryPrice=0.0;
      g_researchEntries[idx].entryVolume=0.0;
      g_researchEntries[idx].entryComment="";
     }
   bool newSnapshot=(entryTime>0 && entryTime!=g_researchEntries[idx].entryTime);
   if(newSnapshot)
     {
      g_researchEntries[idx].genKey="";
      g_researchEntries[idx].bull=bull;
      g_researchEntries[idx].entryComment="";
     }
   if(genKey!="")
      g_researchEntries[idx].genKey=genKey;
   g_researchEntries[idx].bull=bull;
   if(entryTime>0)
      g_researchEntries[idx].entryTime=entryTime;
   if(entryPrice>0.0)
      g_researchEntries[idx].entryPrice=entryPrice;
   if(entryVolume>0.0)
      g_researchEntries[idx].entryVolume=entryVolume;
   if(entryComment!="")
      g_researchEntries[idx].entryComment=entryComment;
  }

bool GetResearchEntrySnapshot(const ulong positionId,
                              string &genKey,
                              bool &bull,
                              datetime &entryTime,
                              double &entryPrice,
                              double &entryVolume,
                              string &entryComment)
  {
   genKey="";
   bull=false;
   entryTime=0;
   entryPrice=0.0;
   entryVolume=0.0;
   entryComment="";
   int idx=FindResearchEntrySnapshot(positionId);
   if(idx<0)
      return false;
   genKey=g_researchEntries[idx].genKey;
   bull=g_researchEntries[idx].bull;
   entryTime=g_researchEntries[idx].entryTime;
   entryPrice=g_researchEntries[idx].entryPrice;
   entryVolume=g_researchEntries[idx].entryVolume;
   entryComment=g_researchEntries[idx].entryComment;
   return (entryTime>0 && entryPrice>0.0 && entryVolume>0.0);
  }

void QueueResearchPendingEntryLink(const string genKey,
                                   const bool bull,
                                   const double entryPrice,
                                   const double entryVolume,
                                   const string entryComment)
  {
   if(genKey=="" || entryPrice<=0.0 || entryVolume<=0.0)
      return;
   ArrayResize(g_researchPendingEntries,g_nResearchPendingEntries+1);
   g_researchPendingEntries[g_nResearchPendingEntries].genKey=genKey;
   g_researchPendingEntries[g_nResearchPendingEntries].bull=bull;
   g_researchPendingEntries[g_nResearchPendingEntries].entryPrice=entryPrice;
   g_researchPendingEntries[g_nResearchPendingEntries].entryVolume=entryVolume;
   g_researchPendingEntries[g_nResearchPendingEntries].entryComment=entryComment;
   g_researchPendingEntries[g_nResearchPendingEntries].createdAt=TimeCurrent();
   g_nResearchPendingEntries++;
  }

bool ConsumeResearchPendingEntryLink(const bool bull,
                                     const double entryPrice,
                                     const double entryVolume,
                                     string &genKey,
                                     string &entryComment)
  {
   genKey="";
   entryComment="";
   if(entryPrice<=0.0 || entryVolume<=0.0)
      return false;
   double priceTol=MathMax(_Point*50.0,0.05);
   double volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double volTol=(volStep>0.0)?(volStep*0.5):0.0000001;
   for(int i=g_nResearchPendingEntries-1;i>=0;i--)
     {
      if(g_researchPendingEntries[i].bull!=bull)
         continue;
      if(MathAbs(g_researchPendingEntries[i].entryPrice-entryPrice)>priceTol)
         continue;
      if(MathAbs(g_researchPendingEntries[i].entryVolume-entryVolume)>volTol)
         continue;
      genKey=g_researchPendingEntries[i].genKey;
      entryComment=g_researchPendingEntries[i].entryComment;
      for(int j=i;j<g_nResearchPendingEntries-1;j++)
         g_researchPendingEntries[j]=g_researchPendingEntries[j+1];
      g_nResearchPendingEntries--;
      ArrayResize(g_researchPendingEntries,g_nResearchPendingEntries);
      return (genKey!="");
     }
   return false;
  }

bool GetEntryDealSnapshotByPositionId(ulong positionId,datetime &entryTime,double &entryPrice,double &entryVolume,string &entryComment)
  {
   entryTime=0;
   entryPrice=0.0;
   entryVolume=0.0;
   entryComment="";
   string cachedGenKey="";
   bool cachedBull=false;
   if(GetResearchEntrySnapshot(positionId,cachedGenKey,cachedBull,entryTime,entryPrice,entryVolume,entryComment))
      return true;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      entryTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      entryPrice=HistoryDealGetDouble(ticket,DEAL_PRICE);
      entryVolume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
      entryComment=HistoryDealGetString(ticket,DEAL_COMMENT);
      return true;
     }
   return false;
  }

double ResearchCashAtPrice(bool bull,double lots,double entryPrice,double refPrice)
  {
   if(lots<=0.0 || entryPrice<=0.0 || refPrice<=0.0)
      return 0.0;
   double pnl=0.0;
   ENUM_ORDER_TYPE orderType=bull?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(OrderCalcProfit(orderType,_Symbol,lots,entryPrice,refPrice,pnl))
      return pnl;
   return 0.0;
  }

datetime ResearchNYWeekStart(datetime serverTime)
  {
   datetime nyTime=ToNY(serverTime);
   MqlDateTime dt;
   TimeToStruct(nyTime,dt);
   int shift=(dt.day_of_week==0)?6:(dt.day_of_week-1);
   datetime start=nyTime-(shift*86400);
   MqlDateTime sdt;
   TimeToStruct(start,sdt);
   sdt.hour=0;
   sdt.min=0;
   sdt.sec=0;
   return StructToTime(sdt);
  }

void ComputeResearchExcursionsM1(bool bull,datetime entryTime,datetime exitTime,double entryPrice,double exitPrice,
                                 double riskPrice,SIB_STATE state,
                                 double &mfePrice,double &maePrice,datetime &mfeTime,datetime &maeTime)
  {
   mfePrice=entryPrice;
   maePrice=entryPrice;
   mfeTime=entryTime;
   maeTime=entryTime;
   if(entryTime<=0 || exitTime<=0 || exitTime<entryTime || entryPrice<=0.0 || riskPrice<=_Point)
      return;

   MqlRates ltf[];
   datetime scanTo=(datetime)(exitTime+(datetime)PeriodSeconds(LTF()));
   int nl=CopyLTFWindowFromCache(entryTime,scanTo,ltf);
   if(nl<1)
      nl=CopyRates(_Symbol,LTF(),entryTime,scanTo,ltf);
   if(nl<1)
     {
      mfePrice=exitPrice;
      maePrice=exitPrice;
      mfeTime=exitTime;
      maeTime=exitTime;
      return;
     }

   double bestPx=entryPrice;
   double worstPx=entryPrice;
   for(int i=0;i<nl;i++)
     {
      double barHigh=ltf[i].high;
      double barLow =ltf[i].low;
      if(ltf[i].time<=exitTime && ltf[i].time+(datetime)PeriodSeconds(LTF())>exitTime)
        {
         if(state==SS_TP_HIT)
           {
            if(bull) barHigh=MathMin(barHigh,exitPrice);
            else     barLow =MathMax(barLow,exitPrice);
           }
         else if(state==SS_SL_HIT || state==SS_BE_HIT)
           {
            if(bull) barLow =MathMax(barLow,exitPrice);
            else     barHigh=MathMin(barHigh,exitPrice);
           }
        }

      if(bull)
        {
         if(barHigh>bestPx)
           {
            bestPx=barHigh;
            mfeTime=ltf[i].time;
           }
         if(barLow<worstPx)
           {
            worstPx=barLow;
            maeTime=ltf[i].time;
           }
        }
      else
        {
         if(barLow<bestPx)
           {
            bestPx=barLow;
            mfeTime=ltf[i].time;
           }
         if(barHigh>worstPx)
           {
            worstPx=barHigh;
            maeTime=ltf[i].time;
           }
        }
     }

   mfePrice=bestPx;
   maePrice=worstPx;
  }

bool ExportResearchTrade(ulong positionId,string genKey,bool isBull,SIB_STATE state,ENUM_DEAL_REASON reason,datetime exitTime,double exitPrice)
  {
   if(!ResearchExportEnabled() || genKey=="" || positionId==0 || !IsResolvedOutcome(state))
      return false;
   if(FindResearchExportRecord(genKey,positionId)>=0)
      return true;

   datetime entryTime=0;
   double entryPrice=0.0, entryVolume=0.0;
   string entryComment="";
   if(!GetEntryDealSnapshotByPositionId(positionId,entryTime,entryPrice,entryVolume,entryComment))
      return false;

   datetime triggerTime=0;
   double slPrice=0.0, tpPrice=0.0, coPrice=0.0;
   GetExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice);
   if(triggerTime<=0)
      triggerTime=entryTime;

   double riskPrice=MathAbs(entryPrice-slPrice);
   if(riskPrice<=_Point)
      return false;

   string modelLabel=ResearchModelLabelFromComment(entryComment);
   if(modelLabel=="")
      modelLabel="CCT";

   double mfePrice=entryPrice, maePrice=entryPrice;
   datetime mfeTime=entryTime, maeTime=entryTime;
   ComputeResearchExcursionsM1(isBull,entryTime,exitTime,entryPrice,exitPrice,riskPrice,state,mfePrice,maePrice,mfeTime,maeTime);

   double realizedR=isBull?((exitPrice-entryPrice)/riskPrice):((entryPrice-exitPrice)/riskPrice);
   double tpR=MathAbs(tpPrice-entryPrice)/riskPrice;
   double mfeR=isBull?((mfePrice-entryPrice)/riskPrice):((entryPrice-mfePrice)/riskPrice);
   double maeR=isBull?((entryPrice-maePrice)/riskPrice):((maePrice-entryPrice)/riskPrice);
   if(mfeR<0.0) mfeR=0.0;
   if(maeR<0.0) maeR=0.0;

   double realizedCash=RealizedPositionPnLCash(positionId);
   if(MathAbs(realizedCash)<=0.0000001)
      realizedCash=ResearchCashAtPrice(isBull,entryVolume,entryPrice,exitPrice);
   double mfeCash=ResearchCashAtPrice(isBull,entryVolume,entryPrice,mfePrice);
   double maeCash=ResearchCashAtPrice(isBull,entryVolume,entryPrice,maePrice);

   datetime beAnchorTime=0, beTouchTime=0, coTouchTime=0;
   double bePrice=0.0;
   bool coFinalized=false, immutableTouch=false;
   GetExecTouchRecord(genKey,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized,immutableTouch);

   datetime birthTime=(datetime)StringToInteger(StringSubstr(genKey,3));
   datetime triggerNy=ToNY(triggerTime);
   datetime entryNy=ToNY(entryTime);
   datetime exitNy=ToNY(exitTime);
   datetime birthNy=ToNY(birthTime);
   datetime mfeNy=ToNY(mfeTime);
   datetime maeNy=ToNY(maeTime);
   datetime beAnchorNy=(beAnchorTime>0)?ToNY(beAnchorTime):0;
   datetime beTouchNy=(beTouchTime>0)?ToNY(beTouchTime):0;
   datetime coTouchNy=(coTouchTime>0)?ToNY(coTouchTime):0;
   datetime weekStartNy=ResearchNYWeekStart(triggerTime);
   MqlDateTime triggerDt;
   TimeToStruct(triggerNy,triggerDt);
   string monthNy=StringFormat("%04d-%02d",triggerDt.year,triggerDt.mon);

   string header=
      "run_tag,symbol,gen_key,model_label,direction,session,trigger_time_server,trigger_time_ny,entry_time_server,entry_time_ny,exit_time_server,exit_time_ny,"
      "birth_time_server,birth_time_ny,trigger_hour_ny,trigger_weekday_ny,trigger_weekday_label_ny,trigger_week_start_ny,trigger_month_ny,"
      "lots,entry_price,sl_price,tp_price,co_price,initial_risk_price,tp_r,exit_state,exit_reason,exit_price,realized_r,realized_cash,"
      "mfe_price,mfe_r,mfe_cash,mfe_time_server,mfe_time_ny,mae_price,mae_r,mae_cash,mae_time_server,mae_time_ny,"
      "be_anchor_time_server,be_anchor_time_ny,be_touch_time_server,be_touch_time_ny,be_price,co_touch_time_server,co_touch_time_ny,co_touched,co_finalized,trade_comment";

   string line=
      CsvEscape(ResearchRunTag())+","+
      CsvEscape(_Symbol)+","+
      CsvEscape(genKey)+","+
      CsvEscape(modelLabel)+","+
      CsvEscape(isBull?"BUY":"SELL")+","+
      CsvEscape(GetCurrentSessionAt(triggerTime))+","+
      CsvEscape(CsvDateTime(triggerTime))+","+
      CsvEscape(CsvDateTime(triggerNy))+","+
      CsvEscape(CsvDateTime(entryTime))+","+
      CsvEscape(CsvDateTime(entryNy))+","+
      CsvEscape(CsvDateTime(exitTime))+","+
      CsvEscape(CsvDateTime(exitNy))+","+
      CsvEscape(CsvDateTime(birthTime))+","+
      CsvEscape(CsvDateTime(birthNy))+","+
      IntegerToString(triggerDt.hour)+","+
      IntegerToString(triggerDt.day_of_week)+","+
      CsvEscape(ResearchWeekdayLabel(triggerDt.day_of_week))+","+
      CsvEscape(CsvDateTime(weekStartNy))+","+
      CsvEscape(monthNy)+","+
      CsvDouble2(entryVolume)+","+
      CsvPrice(entryPrice)+","+
      CsvPrice(slPrice)+","+
      CsvPrice(tpPrice)+","+
      CsvPrice(coPrice)+","+
      CsvPrice(riskPrice)+","+
      CsvDouble4(tpR)+","+
      CsvEscape(ResearchOutcomeLabel(state))+","+
      CsvEscape(ResearchDealReasonLabel(reason))+","+
      CsvPrice(exitPrice)+","+
      CsvDouble4(realizedR)+","+
      CsvDouble2(realizedCash)+","+
      CsvPrice(mfePrice)+","+
      CsvDouble4(mfeR)+","+
      CsvDouble2(mfeCash)+","+
      CsvEscape(CsvDateTime(mfeTime))+","+
      CsvEscape(CsvDateTime(mfeNy))+","+
      CsvPrice(maePrice)+","+
      CsvDouble4(maeR)+","+
      CsvDouble2(maeCash)+","+
      CsvEscape(CsvDateTime(maeTime))+","+
      CsvEscape(CsvDateTime(maeNy))+","+
      CsvEscape(CsvDateTime(beAnchorTime))+","+
      CsvEscape(CsvDateTime(beAnchorNy))+","+
      CsvEscape(CsvDateTime(beTouchTime))+","+
      CsvEscape(CsvDateTime(beTouchNy))+","+
      CsvPrice(bePrice)+","+
      CsvEscape(CsvDateTime(coTouchTime))+","+
      CsvEscape(CsvDateTime(coTouchNy))+","+
      CsvBool(coTouchTime>0)+","+
      CsvBool(coFinalized)+","+
      CsvEscape(entryComment);

   if(!AppendResearchCsvLine(ResearchTradesPath(),header,line))
      return false;
   MarkResearchExportRecord(genKey,positionId);
   return true;
  }

void InitResearchExport()
  {
   if(!ResearchExportEnabled())
      return;
   EnsureResearchFolders();
  }

void WriteResearchRunSummary()
  {
   if(!ResearchExportEnabled())
      return;

   double initialDeposit=TesterStatistics(STAT_INITIAL_DEPOSIT);
   double profit=TesterStatistics(STAT_PROFIT);
   double trades=TesterStatistics(STAT_TRADES);
   double winTrades=TesterStatistics(STAT_PROFIT_TRADES);
   double lossTrades=TesterStatistics(STAT_LOSS_TRADES);
   double profitFactor=TesterStatistics(STAT_PROFIT_FACTOR);
   double expectedPayoff=TesterStatistics(STAT_EXPECTED_PAYOFF);
   double recoveryFactor=TesterStatistics(STAT_RECOVERY_FACTOR);
   double balanceDd=TesterStatistics(STAT_BALANCE_DD);
   double balanceDdPct=TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   double endBalance=initialDeposit+profit;

   string header=
      "run_tag,symbol,initial_deposit,profit,end_balance,trades,win_trades,loss_trades,profit_factor,expected_payoff,recovery_factor,balance_dd,balance_dd_pct";
   string line=
      CsvEscape(ResearchRunTag())+","+
      CsvEscape(_Symbol)+","+
      CsvDouble2(initialDeposit)+","+
      CsvDouble2(profit)+","+
      CsvDouble2(endBalance)+","+
      IntegerToString((int)trades)+","+
      IntegerToString((int)winTrades)+","+
      IntegerToString((int)lossTrades)+","+
      CsvDouble4(profitFactor)+","+
      CsvDouble4(expectedPayoff)+","+
      CsvDouble4(recoveryFactor)+","+
      CsvDouble2(balanceDd)+","+
      CsvDouble4(balanceDdPct);
   AppendResearchCsvLine(ResearchSummaryPath(),header,line);
  }

bool BuildPeriodSeparatorStats(datetime periodStart,datetime periodEnd,DaySeparatorStats &stats)
  {
   ResetDaySeparatorStats(stats);
   datetime historyFrom=periodStart-86400;
   datetime historyTo=TimeCurrent()+86400;
   if(!HistorySelect(historyFrom,historyTo))
      return false;

   ulong seenPositionIds[];
   int seenCount=0;
   int totalDeals=HistoryDealsTotal();
   for(int i=totalDeals-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;

      datetime entryTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      if(entryTime<periodStart || entryTime>=periodEnd) continue;

      ulong positionId=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      if(positionId==0) continue;
      bool seen=false;
      for(int s=0;s<seenCount;s++)
        {
         if(seenPositionIds[s]==positionId)
           {
            seen=true;
            break;
           }
        }
      if(seen) continue;
      ArrayResize(seenPositionIds,seenCount+1);
      seenPositionIds[seenCount++]=positionId;

      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      string genKey="";
      bool bull=false;
      if(!TryGenKeyFromComment(comment,genKey,bull))
         continue;

      if(bull) stats.bullTriggered++;
      else     stats.bearTriggered++;

      if(HasOpenCCTPositionForGenKey(genKey))
        {
         if(bull) stats.bullOpen++;
         else     stats.bearOpen++;
         continue;
        }

      datetime exitTime=0;
      double exitPrice=0.0;
      SIB_STATE state=GetPOIOutcome(genKey);
      if(!GetPOIExit(genKey,exitTime,exitPrice))
        {
         if(bull) stats.bullOpen++;
         else     stats.bearOpen++;
         continue;
        }

      if(state==SS_TP_HIT) stats.tpCount++;
      else if(state==SS_SL_HIT) stats.slCount++;
      else if(state==SS_BE_HIT) stats.beCount++;

     stats.pnlCash += RealizedPositionPnLCash(positionId);
     }
   return true;
  }

bool BuildDaySeparatorStats(datetime dayStart,datetime dayEnd,DaySeparatorStats &stats)
  {
   return BuildPeriodSeparatorStats(dayStart,dayEnd,stats);
  }

bool IsAlreadyExecuted(datetime triggerTime,bool bull)
  {
   for(int i=0;i<g_nExecRecords;i++)
      if(g_execRecords[i].triggerTime==triggerTime && g_execRecords[i].bull==bull)
         return true;
   return false;
  }

bool IsTriggerExecutionWindowClosed(datetime triggerTime,datetime birthTime,datetime &windowEndServer)
  {
   windowEndServer=0;
   if(triggerTime<=0 || birthTime<=0)
      return false;

   TradeWindowResult execWindow;
   datetime windowOpenServer=0;
   string windowLabel="";
   int execKey=-1;
   if(!ResolveExecutionWindowForTrigger(triggerTime,execWindow,windowOpenServer,windowEndServer,windowLabel,execKey,birthTime))
      return false;

   datetime now=CurrentExecutionReferenceTime();
   return (windowEndServer>0 && now>windowEndServer);
  }

double FindPositionEntryPriceFromHistory(ulong positionId)
  {
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      return HistoryDealGetDouble(ticket,DEAL_PRICE);
     }
   return 0.0;
  }

datetime FindPositionEntryTimeFromHistory(ulong positionId)
  {
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      return (datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
     }
   return 0;
  }

bool TryGenKeyFromPositionIdHistory(ulong positionId,string &outGenKey,bool &outBull)
  {
   outGenKey="";
   outBull=false;
   datetime entryTime=0;
   double entryPrice=0.0, entryVolume=0.0;
   string entryComment="";
   if(GetResearchEntrySnapshot(positionId,outGenKey,outBull,entryTime,entryPrice,entryVolume,entryComment) && outGenKey!="")
      return true;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      if(TryGenKeyFromComment(comment,outGenKey,outBull))
         return true;
     }
   return false;
  }

SIB_STATE DetermineResolvedOutcome(string genKey,bool isBull,ulong positionId,ENUM_DEAL_REASON reason,double exitPrice,double profit,datetime exitTime)
  {
   double entryPrice=FindPositionEntryPriceFromHistory(positionId);
   datetime entryTime=FindPositionEntryTimeFromHistory(positionId);
   datetime triggerTime=0;
   double execEntry=0.0, execSL=0.0, execTP=0.0;
   GetExecVisualRecord(genKey,execEntry,execSL,execTP);
   double replayCoPrice=0.0;
   GetExecReplayRecord(genKey,triggerTime,execEntry,execSL,execTP,replayCoPrice);
   if(execEntry>0.0) entryPrice=execEntry;
   double tol=MathMax(_Point*3.0,_Point);

   if(reason==DEAL_REASON_TP)
      return SS_TP_HIT;
   if(reason==DEAL_REASON_SL)
     {
      datetime beAnchorTime=0, beTouchTime=0, coTouchTime=0;
      double bePrice=0.0, coPrice=0.0;
      bool coFinalized=false;
      if(replayCoPrice>0.0) coPrice=replayCoPrice;
      else GetExecCOPrice(genKey,coPrice);
      ResolveExecMilestones(genKey,isBull,(triggerTime>0?triggerTime:entryTime),coPrice,exitTime,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized);
      if(beTouchTime>0 && bePrice>0.0 && entryPrice>0.0)
        {
         if(isBull && exitPrice>=bePrice-tol) return SS_BE_HIT;
         if(!isBull && exitPrice<=bePrice+tol) return SS_BE_HIT;
        }
      return SS_SL_HIT;
     }

   datetime beAnchorTime=0, beTouchTime=0, coTouchTime=0;
   double bePrice=0.0, coPrice=0.0;
   bool coFinalized=false;
   if(replayCoPrice>0.0) coPrice=replayCoPrice;
   else GetExecCOPrice(genKey,coPrice);
   ResolveExecMilestones(genKey,isBull,(triggerTime>0?triggerTime:entryTime),coPrice,exitTime,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized);

   if(execTP>0.0 && MathAbs(exitPrice-execTP)<=tol)
      return SS_TP_HIT;
   if(beTouchTime>0 && exitTime>=beTouchTime && bePrice>0.0 && MathAbs(exitPrice-bePrice)<=tol)
      return SS_BE_HIT;

   if(execSL>0.0 && MathAbs(exitPrice-execSL)<=tol)
      return SS_SL_HIT;
   return (profit>0.0)?SS_TP_HIT:SS_SL_HIT;
  }

bool ResolveBrokerTradeRecord(string genKey,SIB_STATE &outState,datetime &outExitTime,double &outExitPrice)
  {
   outState=SS_UNKNOWN_OUTCOME;
   outExitTime=0;
   outExitPrice=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      string matchedGenKey;
      bool isBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,isBull)) continue;
      if(matchedGenKey!=genKey) continue;

      outState=SS_TRIGGERED;
      return true;
     }

   datetime tradeTime=(datetime)StringToInteger(StringSubstr(genKey,3));
   HistorySelect(tradeTime-86400*30,TimeCurrent()+86400);

   ulong positionId=0;
   bool isBull=(StringFind(genKey,"BU_")==0);
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;

      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      string matchedGenKey;
      bool entryBull=false;
      if(!TryGenKeyFromComment(comment,matchedGenKey,entryBull)) continue;
      if(matchedGenKey!=genKey) continue;

      positionId=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      isBull=entryBull;
      break;
     }

   if(positionId==0)
      return false;

   outState=SS_TRIGGERED;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;

      outExitTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      outExitPrice=HistoryDealGetDouble(ticket,DEAL_PRICE);
      ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(ticket,DEAL_REASON);
      double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      outState=DetermineResolvedOutcome(genKey,isBull,positionId,reason,outExitPrice,profit,outExitTime);
      return true;
     }

   return false;
  }

bool HasBrokerTradeRecord(string genKey)
  {
   SIB_STATE st=SS_UNKNOWN_OUTCOME;
   datetime exitT=0;
   double exitP=0.0;
   return ResolveBrokerTradeRecord(genKey,st,exitT,exitP);
  }

bool ResolveSyntheticTradeRecord(string genKey,SIB_STATE &outState,datetime &outExitTime,double &outExitPrice)
  {
   outState=SS_UNKNOWN_OUTCOME;
   outExitTime=0;
   outExitPrice=0.0;

   datetime triggerTime=0;
   double entryPrice=0.0, slPrice=0.0, tpPrice=0.0, coPrice=0.0;
   if(!GetExecReplayRecord(genKey,triggerTime,entryPrice,slPrice,tpPrice,coPrice))
      return false;

   if(triggerTime<=0 || !IsRecentExecutionVisualTime(triggerTime))
      return false;

   if(entryPrice<=0.0 || slPrice<=0.0 || tpPrice<=0.0)
      return false;

   outState=SS_TRIGGERED;

   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   if(scanEnd<triggerTime)
      return true;

   double tpDist=MathAbs(tpPrice-entryPrice);
   double dir=(StringFind(genKey,"BU_")==0)?1.0:-1.0;
   bool bull=(dir>0.0);
   bool beEnabled=(Inp_BE_Enabled && tpDist>_Point);
   double beTrigPx=entryPrice + dir*((double)Inp_BE_Trigger/100.0)*tpDist;
   double beMovePx=entryPrice + dir*((double)Inp_BE_Move/100.0)*tpDist;

   MqlRates ltf[];
   int nl=CopyRates(_Symbol,LTF(),triggerTime,scanEnd+(datetime)PeriodSeconds(LTF()),ltf);
   if(nl<1)
      return true;

   bool coReached=(coPrice<=0.0);
   bool beArmed=false;
   for(int k=0;k<nl;k++)
     {
      if(!coReached && coPrice>0.0)
        {
         bool coHit=bull?(ltf[k].high>=coPrice):(ltf[k].low<=coPrice);
         if(coHit) coReached=true;
        }

      if(beEnabled && coReached && !beArmed)
        {
         bool beTrigHit=bull?(ltf[k].high>=beTrigPx):(ltf[k].low<=beTrigPx);
         if(beTrigHit) beArmed=true;
        }

      if(beArmed)
        {
         bool beHit=bull?(ltf[k].low<=beMovePx):(ltf[k].high>=beMovePx);
         bool tpHit=bull?(ltf[k].high>=tpPrice):(ltf[k].low<=tpPrice);
         if(beHit)
           {
            outState=SS_BE_HIT;
            outExitTime=ltf[k].time;
            outExitPrice=beMovePx;
            return true;
           }
         if(tpHit)
           {
            outState=SS_TP_HIT;
            outExitTime=ltf[k].time;
            outExitPrice=tpPrice;
            return true;
           }
        }
      else
        {
         bool slHit=bull?(ltf[k].low<=slPrice):(ltf[k].high>=slPrice);
         bool tpHit=bull?(ltf[k].high>=tpPrice):(ltf[k].low<=tpPrice);
         if(slHit)
           {
            outState=SS_SL_HIT;
            outExitTime=ltf[k].time;
            outExitPrice=slPrice;
            return true;
           }
         if(tpHit)
           {
            outState=SS_TP_HIT;
            outExitTime=ltf[k].time;
            outExitPrice=tpPrice;
            return true;
           }
        }
     }

   return true;
  }

bool ResolveTradeState(string genKey,SIB_STATE &outState,datetime &outExitTime,double &outExitPrice)
  {
   outState=SS_UNKNOWN_OUTCOME;
   outExitTime=0;
   outExitPrice=0.0;

   bool hasLiveBrokerPosition=HasOpenCCTPositionForGenKey(genKey);

   int cached=FindOutcomeRecord(genKey);
   if(cached>=0
      && IsResolvedOutcome(g_outcomes[cached].state)
      && (g_outcomes[cached].immutable || !hasLiveBrokerPosition))
     {
      if(Inp_ShowDebug)
         PrintFormat("[CCT DBG] TRADE TRUTH cache genKey=%s state=%d",genKey,(int)g_outcomes[cached].state);
      outState=g_outcomes[cached].state;
      outExitTime=g_outcomes[cached].exitTime;
      outExitPrice=g_outcomes[cached].exitPrice;
      return true;
     }

   bool persistedImmutable=false;
   if(LoadPersistedOutcome(genKey,outState,outExitTime,outExitPrice,persistedImmutable)
      && IsResolvedOutcome(outState))
     {
      if(Inp_ShowDebug)
         PrintFormat("[CCT DBG] TRADE TRUTH persisted genKey=%s state=%d",genKey,(int)outState);
      if(persistedImmutable || !hasLiveBrokerPosition)
        {
         UpdatePOIOutcome(genKey,outState,outExitTime,outExitPrice,persistedImmutable);
         return true;
        }
     }

   if(ResolveBrokerTradeRecord(genKey,outState,outExitTime,outExitPrice))
     {
      if(Inp_ShowDebug)
         PrintFormat("[CCT DBG] TRADE TRUTH broker-first genKey=%s state=%d",genKey,(int)outState);
      if(IsResolvedOutcome(outState))
        {
         int idx=FindOutcomeRecord(genKey);
         bool needsWrite=(idx<0
                          || g_outcomes[idx].state!=outState
                          || g_outcomes[idx].exitTime!=outExitTime
                          || MathAbs(g_outcomes[idx].exitPrice-outExitPrice)>_Point);
        if(needsWrite)
            UpdatePOIOutcome(genKey,outState,outExitTime,outExitPrice,true);
        }
      return true;
     }

   if(ResolveSyntheticTradeRecord(genKey,outState,outExitTime,outExitPrice))
     {
      if(Inp_ShowDebug)
         PrintFormat("[CCT DBG] TRADE TRUTH synthetic genKey=%s state=%d",genKey,(int)outState);
      if(IsResolvedOutcome(outState))
         UpdatePOIOutcome(genKey,outState,outExitTime,outExitPrice,false);
      else
         ClearPOIOutcome(genKey,false);
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
// POI State Tracking — checks positions directly
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// CheckPositionOutcome — check if position is open or was closed
// Returns: SS_TRIGGERED (open), SS_TP_HIT, SS_SL_HIT, SS_UNKNOWN
//+------------------------------------------------------------------+
SIB_STATE CheckPositionOutcome(string genKey, datetime &outExitTime, double &outExitPrice)
   {
    SIB_STATE state=SS_UNKNOWN_OUTCOME;
    ResolveTradeState(genKey,state,outExitTime,outExitPrice);
    return state;
   }

//+------------------------------------------------------------------+
// GetPOIOutcome — get outcome state for a generation key
//+------------------------------------------------------------------+
SIB_STATE GetPOIOutcome(string genKey)
   {
    datetime t=0;
    double   p=0.0;
    SIB_STATE st=SS_UNKNOWN_OUTCOME;
    ResolveTradeState(genKey,st,t,p);
    return st;
   }

//+------------------------------------------------------------------+
// GetPOIExit — check if trade has closed
//+------------------------------------------------------------------+
bool GetPOIExit(string genKey, datetime &exitTime, double &exitPrice)
   {
    SIB_STATE state = SS_UNKNOWN_OUTCOME;
    ResolveTradeState(genKey,state,exitTime,exitPrice);
    if(state == SS_TP_HIT || state == SS_SL_HIT || state == SS_BE_HIT)
      {
       return true;
      }
    return false;
   }

//+------------------------------------------------------------------+
// UpdatePOIOutcome — log when hit detected
//+------------------------------------------------------------------+
void ClearPOIOutcome(string genKey,bool clearImmutable=false)
   {
    int idx=FindOutcomeRecord(genKey);
    if(idx>=0 && (!g_outcomes[idx].immutable || clearImmutable))
      {
       for(int j=idx;j<g_nOutcomes-1;j++)
          g_outcomes[j]=g_outcomes[j+1];
       g_nOutcomes--;
       ArrayResize(g_outcomes,g_nOutcomes);
      }

    SIB_STATE pst=SS_UNKNOWN_OUTCOME;
    datetime  pt=0;
    double    pp=0.0;
    bool      pImmutable=false;
    if(LoadPersistedOutcome(genKey,pst,pt,pp,pImmutable) && (!pImmutable || clearImmutable))
       ClearPersistedOutcome(genKey);
   }

void UpdatePOIOutcome(string genKey, SIB_STATE newOutcome, datetime exitTime, double exitPrice, bool immutable)
   {
    if(newOutcome==SS_CO_HIT)
       return;
    int idx=FindOutcomeRecord(genKey);
    if(idx>=0)
      {
       if(g_outcomes[idx].immutable && !immutable)
          return; // never let synthetic updates overwrite broker-backed truth

       bool sameState=(g_outcomes[idx].state==newOutcome);
       bool sameTime=(g_outcomes[idx].exitTime==exitTime);
       bool samePrice=(MathAbs(g_outcomes[idx].exitPrice-exitPrice)<=_Point);
       bool sameOrStrongerImmutability=(g_outcomes[idx].immutable || g_outcomes[idx].immutable==immutable);
       if(sameState && sameTime && samePrice && sameOrStrongerImmutability)
          return; // suppress duplicate spam and redundant persistence
      }
    if(idx<0)
      {
       ArrayResize(g_outcomes,g_nOutcomes+1);
       idx=g_nOutcomes++;
       g_outcomes[idx].genKey=genKey;
       g_outcomes[idx].immutable=false;
      }
    g_outcomes[idx].state=newOutcome;
    g_outcomes[idx].exitTime=exitTime;
    g_outcomes[idx].exitPrice=exitPrice;
    g_outcomes[idx].immutable=immutable;
    PersistOutcomeRecord(genKey,newOutcome,exitTime,exitPrice,immutable);

    string outcomeStr="UNKNOWN";
    if(newOutcome==SS_SL_HIT) outcomeStr="SL HIT";
    else if(newOutcome==SS_TP_HIT) outcomeStr="TP HIT";
    else if(newOutcome==SS_BE_HIT) outcomeStr="BE HIT";
    string sourceTag=immutable?"[CCT TRADE HIT]":"[CCT POI SYNTH]";
    PrintFormat("%s genKey='%s' resolved to %s at %s",
                sourceTag, genKey, outcomeStr, NYStr(exitTime));
   }

void UpdatePOIOutcome(string genKey, SIB_STATE newOutcome, datetime exitTime, double exitPrice)
   {
    UpdatePOIOutcome(genKey,newOutcome,exitTime,exitPrice,false);
   }

void HandleTradeTransaction(const MqlTradeTransaction &trans)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0)
      return;
  ulong ticket=trans.deal;
  if(!HistoryDealSelect(ticket))
      return;
  if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=202600) return;
  if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) return;
  double dealVol=HistoryDealGetDouble(ticket,DEAL_VOLUME);
  double dealComm=MathAbs(HistoryDealGetDouble(ticket,DEAL_COMMISSION))
                + MathAbs(HistoryDealGetDouble(ticket,DEAL_FEE));
  if(dealVol>0.0 && dealComm>0.0)
     UpdateCommissionEstimate(_Symbol,(dealComm/dealVol)*2.0);
  long dealEntry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
  if(dealEntry==DEAL_ENTRY_IN)
    {
      ulong positionId=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      string entryGenKey="";
      bool entryBull=false;
      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      datetime entryTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      double entryPrice=HistoryDealGetDouble(ticket,DEAL_PRICE);
      entryBull=(HistoryDealGetInteger(ticket,DEAL_TYPE)==DEAL_TYPE_BUY);
      string linkedComment="";
      if(ConsumeResearchPendingEntryLink(entryBull,entryPrice,dealVol,entryGenKey,linkedComment))
        {
         if(linkedComment!="")
            comment=linkedComment;
        }
      else if(TryGenKeyFromComment(comment,entryGenKey,entryBull))
        {
         MarkBrokerTradePresence(entryGenKey);
        }
      CacheResearchEntrySnapshot(positionId,entryGenKey,entryBull,entryTime,entryPrice,dealVol,comment);
      if(entryGenKey!="")
         MarkBrokerTradePresence(entryGenKey);
      return;
     }
   if(dealEntry!=DEAL_ENTRY_OUT) return;

   ulong positionId=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
   string genKey;
   bool isBull=false;
   if(!TryGenKeyFromPositionIdHistory(positionId,genKey,isBull))
      return;

   datetime exitTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
   double exitPrice=HistoryDealGetDouble(ticket,DEAL_PRICE);
   double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
   ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(ticket,DEAL_REASON);
   SIB_STATE state=DetermineResolvedOutcome(genKey,isBull,positionId,reason,exitPrice,profit,exitTime);
   UpdatePOIOutcome(genKey,state,exitTime,exitPrice,true);
   PersistOutcomeRecord(genKey,state,exitTime,exitPrice,true);
   if(!ExportResearchTrade(positionId,genKey,isBull,state,reason,exitTime,exitPrice) && ResearchExportEnabled())
      PrintFormat("[CCT RESEARCH] export skipped genKey=%s pos=%I64u state=%d reason=%d",genKey,positionId,(int)state,(int)reason);
  }

//+------------------------------------------------------------------+
// RegisterExecutedPOI — called when order placed
//+------------------------------------------------------------------+
void RegisterExecutedPOI(datetime trigTime,bool bull,double entry,double sl,double tp,string genKey,double coPrice)
   {
    UpdateExecReplayRecord(genKey,trigTime,entry,sl,tp,coPrice,true);
    MarkBrokerTradePresence(genKey);
    ClearPOIOutcome(genKey,false);
     PrintFormat("[CCT POI REG] genKey='%s' trig=%s entry=%.5f sl=%.5f tp=%.5f",
                 genKey, NYStr(trigTime), entry, sl, tp);
   }

void RegisterReplayTriggeredPOI(datetime trigTime,double entry,double sl,double tp,string genKey,double coPrice)
  {
   UpdateExecReplayRecord(genKey,trigTime,entry,sl,tp,coPrice,false);
  }

//+------------------------------------------------------------------+
// RegisterPendingExec
//+------------------------------------------------------------------+
void RegisterPendingExec(bool bull,double entryPrice,double slRaw,double tpRaw,
                         double rrLocked,double coPrice,datetime trigTime,datetime birthTime,
                         datetime expiryTime,string modelLabel="",datetime c1TimeServer=0)
  {
   if(entryPrice<=0.0 || slRaw<=0.0 || tpRaw<=0.0 || rrLocked<=0.0) return;
   string execGenKey=ExecGenKeyFromBirth(bull,birthTime);
   if(HasCachedBrokerTradePresence(execGenKey)) return;
   if(IsTerminalTrigger(trigTime,bull,birthTime)) return;
   TradeWindowResult execWindow;
   datetime execOpenServer=0,execEndServer=0;
   string execLabel="";
   int execKey=-1;
   if(!ResolveExecutionWindowForTrigger(trigTime,execWindow,execOpenServer,execEndServer,execLabel,execKey,birthTime,c1TimeServer))
     {
      MarkTerminalTrigger(trigTime,bull,birthTime,TR_TERM_WINDOW_BLOCK);
      PrintFormat("[CCT EXEC BLOCK] %s trig=%s ny=%s reason=outside allowed execution window",
                  bull?"BUY":"SELL",
                  TimeToString(trigTime,TIME_SECONDS),
                  NYStr(trigTime));
      return;
     }
   datetime execRefNow=CurrentExecutionReferenceTime();
   if(execEndServer>0 && execRefNow>execEndServer)
     {
      MarkTerminalTrigger(trigTime,bull,birthTime,TR_TERM_WINDOW_CLOSED);
      PrintFormat("[CCT EXEC] EXPIRED %s trig=%s reason=execution window already closed",
                  bull?"BUY":"SELL",
                  NYStr(trigTime));
      return;
     }
   string resolvedModelLabel=(modelLabel!="")?modelLabel
                                            :TradeWindowShortLabelForOffset(execWindow.maxHTF+1);
   if(IsAlreadyExecuted(trigTime,bull)) return;
   for(int i=0;i<g_nPending;i++)
      if(g_pendingExec[i].triggerTime==trigTime
         && g_pendingExec[i].bull==bull
         && g_pendingExec[i].birthTime==birthTime)
        {
         g_pendingExec[i].modelLabel=MergeExecModelLabel(g_pendingExec[i].modelLabel,resolvedModelLabel);
         return;
        }
   ArrayResize(g_pendingExec,g_nPending+1,32);
   g_pendingExec[g_nPending].bull        = bull;
   g_pendingExec[g_nPending].entryPrice  = entryPrice;
   g_pendingExec[g_nPending].slRaw       = slRaw;
    g_pendingExec[g_nPending].tpRaw       = tpRaw;
   g_pendingExec[g_nPending].rrLocked    = rrLocked;
   g_pendingExec[g_nPending].coPrice     = coPrice;
   g_pendingExec[g_nPending].triggerTime = trigTime;
   g_pendingExec[g_nPending].birthTime   = birthTime;
   g_pendingExec[g_nPending].expiryTime  = expiryTime;
   g_pendingExec[g_nPending].nextAttemptTime = 0;
   g_pendingExec[g_nPending].failCount = 0;
   g_pendingExec[g_nPending].modelLabel = resolvedModelLabel;
   g_nPending++;
   ProcessPending();
  }

bool ShouldKillStalePendingExec(const PendingExec &pe,double entryNow,double slPx,double tpPx,string &reason)
  {
   reason="";
   double liveRisk=MathAbs(entryNow-slPx);
   if(liveRisk<=_Point)
     {
      reason="risk collapsed at send";
      return true;
     }

   double remainingReward=pe.bull?(tpPx-entryNow):(entryNow-tpPx);
   if(remainingReward<=_Point)
     {
      reason="price already at or beyond locked TP";
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
// CalcLots — uses g_riskPct and EffectiveAccountBase()
//+------------------------------------------------------------------+
double CalcLots(double entry, double sl)
  {
   double accBase = EffectiveAccountBase();
   double riskAmt = accBase * (g_riskPct / 100.0);
   if(riskAmt <= 0.0) return 0.0;
   // Price-only loss: commission is overhead, not a lot-sizing input.
   // User intent: risk % controls SL-distance risk exclusively.
   double perLotLoss = EstimateCashLossPerLot(_Symbol, entry, sl);
   if(perLotLoss <= 0.0) return 0.0;
   return NormalizeLotsDown(_Symbol, riskAmt / perLotLoss);
  }

datetime PendingExecHardExpiry(datetime triggerTime)
  {
   int ltfSec=(int)PeriodSeconds(LTF());
   if(ltfSec<=0 || triggerTime<=0)
      return triggerTime;
   int barsToKeep=4;
   ENUM_TIMEFRAMES htf=HTF();
   if(htf==PERIOD_H4 || htf==PERIOD_D1)
      barsToKeep=8;
   return (datetime)(triggerTime + barsToKeep*ltfSec);
  }

void CheckLiveTrigger()
  {
   if(Inp_BrokerExecution!=BROKER_EXEC_ON) return;
   if(g_sigState!=SS_ACTIVE) return;
   if(!g_sigC1 || !g_sigC2 || !g_sigC3) return;
   if(g_sigBirthTime<=0 || g_sigLevel<=0.0 || g_sigSlPx<=0.0 || g_sigTpPx<=0.0) return;

   datetime liveBar=iTime(_Symbol,LTF(),0);
   if(liveBar<=0) return;
   if(IsAlreadyExecuted(liveBar,g_sigBull)) return;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0.0 || ask<=0.0) return;

   bool triggerNow=g_sigBull ? (bid>=g_sigLevel) : (ask<=g_sigLevel);
   if(!triggerNow) return;

   double entryNow=g_sigBull ? ask : bid;
   double risk=MathAbs(entryNow-g_sigSlPx);
   double rrLocked=(risk>_Point)?(MathAbs(g_sigTpPx-entryNow)/risk):0.0;
   datetime expiryTime=PendingExecHardExpiry(liveBar);
   RegisterPendingExec(g_sigBull,entryNow,g_sigSlPx,g_sigTpPx,rrLocked,g_sigCoPx,
                       liveBar,g_sigBirthTime,expiryTime,g_sigModelLabel,g_sigC1Time);
  }

// CalcTPRaw is defined in CCT_Globals.mqh so both CCT_Visual.mqh and
// CCT_Execution.mqh can use it without circular includes.

//+------------------------------------------------------------------+
// ProcessPending — place market orders from queue
//+------------------------------------------------------------------+
void ProcessPending()
  {
   if(g_nPending==0) return;
   if(Inp_BrokerExecution!=BROKER_EXEC_ON) return;
   CTrade trade;
   trade.SetExpertMagicNumber(202600);
   trade.SetDeviationInPoints(IsTesterRun()?0:10);
   trade.SetTypeFillingBySymbol(_Symbol);

   int  writeIdx=0;

   for(int i=0;i<g_nPending;i++)
     {
      // *** FIX: local copy — MQL5 forbids array-element references ***
      PendingExec pe = g_pendingExec[i];
      string execGenKey=ExecGenKeyFromBirth(pe.bull,pe.birthTime);
      if(IsAlreadyExecuted(pe.triggerTime,pe.bull))
         continue;
      if(HasCachedBrokerTradePresence(execGenKey))
         continue;
      if(IsTerminalTrigger(pe.triggerTime,pe.bull,pe.birthTime))
         continue;

      if(pe.nextAttemptTime>0 && TimeCurrent()<pe.nextAttemptTime)
        {
         g_pendingExec[writeIdx++]=pe;
         continue;
        }

      datetime hardExpiry=PendingExecHardExpiry(pe.triggerTime);
      datetime effectiveExpiry=pe.expiryTime;
      if(hardExpiry>0 && (effectiveExpiry<=0 || hardExpiry<effectiveExpiry))
         effectiveExpiry=hardExpiry;

      if(effectiveExpiry>0 && TimeCurrent()>effectiveExpiry)
        {
         MarkTerminalTrigger(pe.triggerTime,pe.bull,pe.birthTime,TR_TERM_EXPIRED);
         PrintFormat("[CCT EXEC] EXPIRED %s trig=%s reason=trigger snapshot aged out",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime));
         continue;
        }

      datetime execWindowEnd=0;
      if(IsTriggerExecutionWindowClosed(pe.triggerTime,pe.birthTime,execWindowEnd))
        {
         MarkTerminalTrigger(pe.triggerTime,pe.bull,pe.birthTime,TR_TERM_WINDOW_CLOSED);
         PrintFormat("[CCT EXEC] EXPIRED %s trig=%s reason=execution window already closed",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime));
         continue;
        }

      double dayPnL=0.0, dayLoss=0.0, dayCap=0.0, dayLeft=0.0;
      if(DailyLossGateHit(dayPnL,dayLoss,dayCap,dayLeft))
        {
         PrintFormat("[CCT EXEC] DAILY LOSS BLOCK %s trig=%s loss=%.2f cap=%.2f day=%s",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime),
                     dayLoss,
                     dayCap,
                     NYStr(BrokerDayOpen()));
         continue;
        }

      double curBid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double curAsk = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(curBid<=0.0 || curAsk<=0.0)
        {
         g_pendingExec[writeIdx++]=pe;
         continue;
        }

      double liveSpread = curAsk-curBid;
      double sl = pe.slRaw;
      if(Inp_ApplySpread)
         sl = pe.bull?(pe.slRaw-liveSpread):(pe.slRaw+liveSpread);

      double entryNow = pe.bull ? curAsk : curBid;
      
      // Recalculate TP from live entry using locked RR ratio (spec s1.2).
      // This ensures broker-side RR always equals pe.rrLocked regardless of slippage.
      double liveRisk = MathAbs(entryNow - sl);
      double tp = (liveRisk > _Point)
                  ? (pe.bull ? entryNow + pe.rrLocked * liveRisk
                             : entryNow - pe.rrLocked * liveRisk)
                  : pe.tpRaw; // fallback to locked raw if risk has collapsed (edge case)
      string staleReason="";
      if(ShouldKillStalePendingExec(pe,entryNow,sl,tp,staleReason))
        {
         MarkTerminalTrigger(pe.triggerTime,pe.bull,pe.birthTime,TR_TERM_STALE);
         PrintFormat("[CCT EXEC] STALE KILL %s trig=%s reason=%s",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime),
                     staleReason);
         continue;
        }

      double risk = MathAbs(entryNow-sl);
      if(risk<=_Point) continue;

      double lotsBase = CalcLots(entryNow,sl);
      if(lotsBase<=0.0) continue;

      double lots=lotsBase;
      if(Inp_DailyLossStop && dayCap>0.0)
        {
         double projectedLossBase=EstimateTradeWorstLossCash(_Symbol,entryNow,sl,lotsBase);
         if(projectedLossBase<=0.0)
           {
            PrintFormat("[CCT EXEC] DAILY LOSS BLOCK %s trig=%s reason=projected loss unavailable",
                        pe.bull?"BUY":"SELL",
                        NYStr(pe.triggerTime));
            continue;
           }

         if(projectedLossBase>dayLeft+1e-8)
           {
            double fitLots=CalcLotsForRiskCash(_Symbol,entryNow,sl,dayLeft);
            if(fitLots<=0.0)
              {
               PrintFormat("[CCT EXEC] DAILY LOSS BLOCK %s trig=%s reason=remaining budget %.2f below minimum tradable loss",
                           pe.bull?"BUY":"SELL",
                           NYStr(pe.triggerTime),
                           dayLeft);
               continue;
              }

            double fitLoss=EstimateTradeWorstLossCash(_Symbol,entryNow,sl,fitLots);
            if(fitLoss<=0.0 || fitLoss>dayLeft+1e-8)
              {
               PrintFormat("[CCT EXEC] DAILY LOSS BLOCK %s trig=%s reason=budget-fit sizing failed",
                           pe.bull?"BUY":"SELL",
                           NYStr(pe.triggerTime));
               continue;
              }

            lots=fitLots;
            PrintFormat("[CCT EXEC] DAILY LOSS FIT %s trig=%s baseLots=%.2f fitLots=%.2f lossUsed=%.2f cap=%.2f nextWorst=%.2f",
                        pe.bull?"BUY":"SELL",
                        NYStr(pe.triggerTime),
                        lotsBase,
                        lots,
                        dayLoss,
                        dayCap,
                        fitLoss);
           }
        }

      if(lots<=0.0) continue;

      double marginPerLot=0.0;
      double marginFitLots=FitLotsToFreeMargin(_Symbol,pe.bull,entryNow,lots,marginPerLot,0.98);
      if(marginFitLots<=0.0)
        {
         pe.failCount++;
         pe.nextAttemptTime=TimeCurrent()+MathMin(300,15*MathMax(1,pe.failCount));
         double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         double minLotMargin=(marginPerLot>0.0 && minLot>0.0)?(marginPerLot*minLot):0.0;
         PrintFormat("[CCT EXEC] MARGIN WAIT %s trig=%s free=%.2f minLotMargin=%.2f desiredLots=%.2f retryIn=%ds",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime),
                     freeMargin,
                     minLotMargin,
                     lots,
                     (int)(pe.nextAttemptTime-TimeCurrent()));
         g_pendingExec[writeIdx++]=pe;
         continue;
        }
      if(marginFitLots+1e-12<lots)
        {
         PrintFormat("[CCT EXEC] MARGIN FIT %s trig=%s baseLots=%.2f fitLots=%.2f marginPerLot=%.2f free=%.2f",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime),
                     lots,
                     marginFitLots,
                     marginPerLot,
                     AccountInfoDouble(ACCOUNT_MARGIN_FREE));
         lots=marginFitLots;
        }

      double safetyFitLots=FitLotsToMarginSafety(_Symbol,lots,marginPerLot);
      if(safetyFitLots<=0.0)
        {
         pe.failCount++;
         pe.nextAttemptTime=TimeCurrent()+MathMin(300,15*MathMax(1,pe.failCount));
         PrintFormat("[CCT EXEC] MARGIN SAFE WAIT %s trig=%s equity=%.2f margin=%.2f free=%.2f targetML=%.0f%% retryIn=%ds",
                     pe.bull?"BUY":"SELL",
                     NYStr(pe.triggerTime),
                     AccountInfoDouble(ACCOUNT_EQUITY),
                     AccountInfoDouble(ACCOUNT_MARGIN),
                     AccountInfoDouble(ACCOUNT_MARGIN_FREE),
                     MarginSafetyTargetPercent(_Symbol),
                     (int)(pe.nextAttemptTime-TimeCurrent()));
         g_pendingExec[writeIdx++]=pe;
         continue;
        }
      if(safetyFitLots+1e-12<lots)
        {
         PrintFormat("[CCT EXEC] MARGIN SAFE FIT %s trig=%s baseLots=%.2f fitLots=%.2f targetML=%.0f%%",
                     pe.bull?"BUY":"SELL",
                        NYStr(pe.triggerTime),
                        lots,
                        safetyFitLots,
                        MarginSafetyTargetPercent(_Symbol));
         lots=safetyFitLots;
        }

      string modelLabel=pe.modelLabel;
      if(modelLabel=="")
        {
         TradeWindowResult execWindowNow;
         datetime execOpenNow=0,execEndNow=0;
         string execLabelNow="";
         int execKeyNow=-1;
         if(ResolveExecutionWindowForTrigger(pe.triggerTime,execWindowNow,execOpenNow,execEndNow,execLabelNow,execKeyNow,pe.birthTime))
            modelLabel=TradeWindowShortLabelForOffset(execWindowNow.maxHTF+1);
         else
            modelLabel="CCT";
        }
      string comment = BuildTradeComment(pe.bull,pe.birthTime,pe.triggerTime,modelLabel);
      bool ok;
      ResetLastError();
      if(pe.bull) ok=trade.Buy (lots,_Symbol,0.0,sl,tp,comment);
      else        ok=trade.Sell(lots,_Symbol,0.0,sl,tp,comment);

      if(ok)
        {
         double actual_entry = trade.ResultPrice();
         if(actual_entry<=0.0)
            actual_entry=entryNow;
         if(MathAbs(actual_entry-entryNow)>_Point && !trade.PositionModify(_Symbol,sl,tp))
            PrintFormat("[CCT EXEC] broker-sync modify failed retcode=%u lasterr=%d",
                        trade.ResultRetcode(), GetLastError());

          ArrayResize(g_execRecords,g_nExecRecords+1,32);
          g_execRecords[g_nExecRecords].triggerTime = pe.triggerTime;
          g_execRecords[g_nExecRecords].bull         = pe.bull;
          g_nExecRecords++;
          MarkTerminalTrigger(pe.triggerTime,pe.bull,pe.birthTime,TR_TERM_EXECUTED);
          // genKey must match what execution objects use: "BU_"+birthTime or "BE_"+birthTime
          string genKey = execGenKey;
          RegisterExecutedPOI(pe.triggerTime, pe.bull, actual_entry, sl, tp, genKey, pe.coPrice);
          QueueResearchPendingEntryLink(genKey,pe.bull,actual_entry,lots,comment);
          ulong resultDeal=trade.ResultDeal();
          if(resultDeal>0 && HistoryDealSelect(resultDeal))
            {
             ulong positionId=(ulong)HistoryDealGetInteger(resultDeal,DEAL_POSITION_ID);
             datetime dealTime=(datetime)HistoryDealGetInteger(resultDeal,DEAL_TIME);
             double dealPrice=HistoryDealGetDouble(resultDeal,DEAL_PRICE);
             double dealVolume=HistoryDealGetDouble(resultDeal,DEAL_VOLUME);
             if(positionId>0)
                CacheResearchEntrySnapshot(positionId,genKey,pe.bull,dealTime,dealPrice,dealVolume,comment);
            }
          PrintFormat("[CCT EXEC] %s trig=%s lots=%.2f entry=%.5f sl=%.5f tp=%.5f RR=%.2f",
                      pe.bull?"BUY":"SELL",NYStr(pe.triggerTime),lots,actual_entry,sl,tp,pe.rrLocked);
        }
      else
        {
         PrintFormat("[CCT EXEC] FAILED %s retcode=%u lasterr=%d trig=%s",
                     pe.bull?"BUY":"SELL",
                     trade.ResultRetcode(),
                     GetLastError(),
                     NYStr(pe.triggerTime));
         if(trade.ResultRetcode()==10019)
           {
            pe.failCount++;
            pe.nextAttemptTime=TimeCurrent()+MathMin(300,30*MathMax(1,pe.failCount));
           }
         g_pendingExec[writeIdx++]=pe;
        }
     }
   g_nPending=writeIdx;
   ArrayResize(g_pendingExec,writeIdx);
  }

//+------------------------------------------------------------------+
// ManagePositions — breakeven, called every tick
//
// Applies only when a BE layer is enabled.
// NY BE at CO is the separate NY-only layer.
// Trigger: when price reaches Inp_BE_Trigger % of (entry -> TP)
// Move:    SL to Inp_BE_Move % of (entry -> TP) from entry
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(Inp_BrokerExecution!=BROKER_EXEC_ON) return;
   if(!Inp_BE_Enabled && !Inp_BE_NYAfterCO) return;
   const int beGraceSec=10;
   CTrade trade; trade.SetExpertMagicNumber(202600);

   double trigPct = (double)Inp_BE_Trigger / 100.0;
   double movePct = (double)Inp_BE_Move    / 100.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)    continue;
      if(PositionGetInteger(POSITION_MAGIC)!=202600)      continue;

      bool   isBuy  = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      datetime posOpenTime=(datetime)PositionGetInteger(POSITION_TIME);
      double curPx  = isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                           :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double liveSpread=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
      string comment=PositionGetString(POSITION_COMMENT);
      string genKey="";
      bool   posBull=false;
      TryGenKeyFromComment(comment,genKey,posBull);
      if(curTP<=0.0) continue;
      datetime triggerTime=0;
      double replayEntry=0.0,replaySL=0.0,replayTP=0.0,replayCO=0.0;
      if(genKey!="")
         GetExecReplayRecord(genKey,triggerTime,replayEntry,replaySL,replayTP,replayCO);
      double tpDist = MathAbs(curTP-openPx);
      if(tpDist<=0.0) continue;
      double trigPx = isBuy?(openPx+trigPct*tpDist):(openPx-trigPct*tpDist);
      double newSL = isBuy?(openPx+movePct*tpDist):(openPx-movePct*tpDist);
      bool alreadyMoved = isBuy?(curSL>=newSL-_Point):(!isBuy&&curSL>0&&curSL<=newSL+_Point);
      bool reachedTrigger = isBuy?(curPx>=trigPx-_Point):(curPx<=trigPx+_Point);
      bool beGracePassed=(posOpenTime<=0 || TimeCurrent()>=(datetime)(posOpenTime+beGraceSec));
      datetime sessionRef=(triggerTime>0)?triggerTime:(datetime)PositionGetInteger(POSITION_TIME);
      bool   nyAMTrade=(genKey!="" && IsNYAMSessionAt(sessionRef));
      if(Inp_BE_NYAfterCO && nyAMTrade && genKey!="" && beGracePassed)
        {
         double coPrice=0.0;
         if(GetExecCOPrice(genKey,coPrice) && coPrice>0.0)
           {
            datetime beAnchorTime=0, beTouchTime=0, coTouchTime=0;
            double bePrice=0.0;
            bool coFinalized=false;
            datetime triggerAnchor=(triggerTime>0)?triggerTime:(datetime)PositionGetInteger(POSITION_TIME);
            ResolveExecMilestones(genKey,isBuy,triggerAnchor,coPrice,0,beAnchorTime,beTouchTime,bePrice,coTouchTime,coFinalized);
            bool coReachedAfterEntry=(coTouchTime>0 && (posOpenTime<=0 || coTouchTime>posOpenTime));
            if(!coReachedAfterEntry)
              {
               if(Inp_ShowDebug)
                  PrintFormat("[CCT DBG] BE WAIT CO genKey=%s posOpen=%s coTouch=%s",
                              genKey,
                              CsvDateTime(posOpenTime),
                              CsvDateTime(coTouchTime));
              }
            else
              {
               // Guard A: CO touch must be at least Inp_BE_CO_MinWaitSec seconds after position open.
               // Prevents same-bar and first-minute CO touches from arming costSL.
               bool coWaitPassed = (Inp_BE_CO_MinWaitSec <= 0
                                    || posOpenTime <= 0
                                    || (coTouchTime - posOpenTime) >= (datetime)Inp_BE_CO_MinWaitSec);

               // Guard B: Current price must have progressed at least Inp_BE_CO_MinProgressPct
               // of the TP distance beyond entry before costSL is placed.
               // Prevents the case where CO was touched by a wick but price is barely in profit.
               double progressPct = isBuy ? ((curPx - openPx) / tpDist * 100.0)
                                           : ((openPx - curPx) / tpDist * 100.0);
               bool minProgressReached = (Inp_BE_CO_MinProgressPct <= 0
                                           || progressPct >= (double)Inp_BE_CO_MinProgressPct);

               if(coWaitPassed && minProgressReached)
                 {
                  double commissionPad = EstimateCommissionPriceOffset(_Symbol, openPx);
                  double costSL = isBuy ? (openPx + liveSpread + commissionPad)
                                        : (openPx - liveSpread - commissionPad);
                  bool costAlreadyMoved = isBuy?(curSL>=costSL-_Point):(!isBuy&&curSL>0&&curSL<=costSL+_Point);
                  bool costInProfit = isBuy?(costSL<curPx-_Point):(costSL>curPx+_Point);
                  bool regularAlreadyBetter = isBuy?(curSL>costSL+_Point):(!isBuy&&curSL>0&&curSL<costSL-_Point);
                  if(!costAlreadyMoved && !regularAlreadyBetter && costInProfit)
                    {
                     if(trade.PositionModify(ticket,costSL,curTP))
                       {
                        curSL=costSL;
                        alreadyMoved = isBuy?(curSL>=newSL-_Point):(!isBuy&&curSL>0&&curSL<=newSL+_Point);
                        if(Inp_ShowDebug)
                           PrintFormat("[CCT DBG] NY BE-AT-CO APPLY genKey=%s ticket=%I64u SL->%.5f wait=%ds progress=%.1f%%",
                                       genKey,ticket,costSL,
                                       (int)(coTouchTime-posOpenTime),progressPct);
                       }
                    }
                 }
               else if(Inp_ShowDebug)
                 {
                  PrintFormat("[CCT DBG] NY BE-AT-CO WAIT genKey=%s waitPassed=%s progressPct=%.1f minPct=%d",
                              genKey,coWaitPassed?"Y":"N",progressPct,Inp_BE_CO_MinProgressPct);
                 }
              }
           }
        }
      if(!Inp_BE_Enabled) continue;
      if(!beGracePassed) continue;

      // Regular BE: move SL to preset % of (entry→TP) once profit % reached
      // Ignored if position already in profit beyond move level.
      {
       if(!alreadyMoved && reachedTrigger)
         {
          if(trade.PositionModify(ticket,newSL,curTP))
             {
              if(Inp_ShowDebug)
                 PrintFormat("[CCT DBG] BE APPLY genKey=%s ticket=%I64u SL->%.5f",genKey,ticket,newSL);
             }
         }
      }
     }
  }

#endif // CCT_EXECUTION_MQH
