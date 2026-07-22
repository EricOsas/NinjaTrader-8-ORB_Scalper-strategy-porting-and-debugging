#ifndef CCT_NOTIFY_MQH
#define CCT_NOTIFY_MQH

// -----------------------------------------------------------------------------
// DISCORD SETUP
// 1. Create a Discord server named "CCT Signals" (or any name).
// 2. Create one text channel per market bucket, e.g. #forex-currencies, #crypto, #metals-energy-commodities, #indices.
// 3. For each channel: Settings -> Integrations -> Webhooks -> New Webhook -> Copy URL.
// 4. Paste each URL into the corresponding NOTIFY_DISCORD_* input.
// 5. Add https://discord.com to MT5 WebRequest whitelist.
//
// TELEGRAM SETUP
// 1. Open @BotFather in Telegram. Send /newbot. Follow prompts. Copy the token.
// 2. Create a Telegram supergroup or channel for "CCT Signals".
//    For per-asset separation: enable Topics (supergroup -> Edit -> Topics -> Enable).
//    Create one topic per asset.
// 3. Add your bot to the group/channel as admin with "Post Messages" and "Manage Topics" permissions.
// 4. Get the group chat_id from @userinfobot or getUpdates.
//    For topics, use chat_id|message_thread_id in the relevant NOTIFY_TELEGRAM_* input.
// 5. Set NOTIFY_TELEGRAM_TOKEN and the per-asset NOTIFY_TELEGRAM_* IDs.
//    Examples: "-1001234567890" for a group, "-1001234567890|12345" for a topic.
// 6. Add https://api.telegram.org to MT5 WebRequest whitelist.
// -----------------------------------------------------------------------------

enum ENUM_NOTIFY_PLATFORM
  {
   NOTIFY_PLATFORM_DISCORD = 0,
   NOTIFY_PLATFORM_TELEGRAM = 1
  };

enum ENUM_NOTIFY_FAMILY
  {
   NOTIFY_FAMILY_DEFAULT = 0,
   NOTIFY_FAMILY_XAUUSD,
   NOTIFY_FAMILY_XAGUSD,
   NOTIFY_FAMILY_NQ,
   NOTIFY_FAMILY_AUDUSD,
   NOTIFY_FAMILY_BTCUSD,
   NOTIFY_FAMILY_ENERGY,
   NOTIFY_FAMILY_COMMODITIES,
   NOTIFY_FAMILY_STOCKS,
   NOTIFY_FAMILY_BONDS
  };

#define CCT_NOTIFY_SCREENSHOT_FRAME_V1 1

void CCTNotifyDrawExecutionSnapshot(const ExecRecord &exec);

string NotifyNormalizeSymbol(const string symbol)
  {
   string out="";
   string upper=symbol;
   StringToUpper(upper);
   int len=StringLen(upper);
   for(int i=0;i<len;i++)
     {
      ushort ch=StringGetCharacter(upper,i);
      if((ch>='A' && ch<='Z') || (ch>='0' && ch<='9'))
         out+=ShortToString(ch);
     }
   return out;
  }

bool NotifySymbolStartsWithAny(const string clean,const string &variants[])
  {
   int n=ArraySize(variants);
   for(int i=0;i<n;i++)
     {
      if(StringFind(clean,variants[i])==0)
         return true;
     }
   return false;
  }

ENUM_NOTIFY_FAMILY NotifyResolveFamily(const string symbol)
  {
   string clean=NotifyNormalizeSymbol(symbol);

   string xau[]={"XAUUSD","GOLD","XAU","GCUSD","GC"};
   if(NotifySymbolStartsWithAny(clean,xau))
      return NOTIFY_FAMILY_XAUUSD;

   string xag[]={"XAGUSD","SILVER","XAG","SIUSD","SI"};
   if(NotifySymbolStartsWithAny(clean,xag))
      return NOTIFY_FAMILY_XAUUSD;

   string energy[]={"UKOIL","USOIL","BRENT","BRN","WTI","XTIUSD","XBRUSD","NATGAS","NGAS","NG"};
   if(NotifySymbolStartsWithAny(clean,energy))
      return NOTIFY_FAMILY_ENERGY;

   string commodities[]={"COPPER","XCUUSD","HG","MAIZE","CORN","WHEAT","SOYBEAN","SOY","COCOA","COFFEE","SUGAR","COTTON"};
   if(NotifySymbolStartsWithAny(clean,commodities))
      return NOTIFY_FAMILY_COMMODITIES;

   string nq[]={"USTECH","USTEC","US100","NAS100","NASDAQ","NASUSD","NDX","MNQ","NQ","US30","DJ30","DOW","SPX500","US500","SP500","GER40","DE40","DAX","UK100","FTSE","JP225","JPN225"};
   if(NotifySymbolStartsWithAny(clean,nq))
      return NOTIFY_FAMILY_NQ;

   string fx[]={
      "AUDCAD","AUDCHF","AUDJPY","AUDNZD","AUDUSD",
      "CADCHF","CADJPY","CHFJPY",
      "EURAUD","EURCAD","EURCHF","EURGBP","EURJPY","EURNZD","EURUSD",
      "GBPAUD","GBPCAD","GBPCHF","GBPJPY","GBPNZD","GBPUSD",
      "NZDCAD","NZDCHF","NZDJPY","NZDUSD",
      "USDCAD","USDCHF","USDJPY"
   };
   if(NotifySymbolStartsWithAny(clean,fx))
      return NOTIFY_FAMILY_AUDUSD;

   string btc[]={"BTCUSDT","BTCUSD","BITCOIN","XBTUSD","ETHUSD","ETHUSDT","ETH","SOLUSD","SOLUSDT","SOL","XRPUSD","XRPUSDT","XRP","BTC"};
   if(NotifySymbolStartsWithAny(clean,btc))
      return NOTIFY_FAMILY_BTCUSD;

   string stocks[]={"AAPL","TSLA","NVDA","AMZN","MSFT","META","GOOG","GOOGL","NFLX"};
   if(NotifySymbolStartsWithAny(clean,stocks))
      return NOTIFY_FAMILY_STOCKS;

   string bonds[]={"US10Y","US30Y","US02Y","US05Y","BUND","GER10Y","UK10Y"};
   if(NotifySymbolStartsWithAny(clean,bonds))
      return NOTIFY_FAMILY_BONDS;

   return NOTIFY_FAMILY_DEFAULT;
  }

string NotifyFamilyDisplayName(const string symbol)
  {
   switch(NotifyResolveFamily(symbol))
     {
      case NOTIFY_FAMILY_XAUUSD: return "Metals/Energy/Commodities";
      case NOTIFY_FAMILY_XAGUSD: return "Metals/Energy/Commodities";
      case NOTIFY_FAMILY_NQ:     return "Indices";
      case NOTIFY_FAMILY_AUDUSD: return "Forex/Currencies";
      case NOTIFY_FAMILY_BTCUSD: return "Cryptocurrencies";
      case NOTIFY_FAMILY_ENERGY: return "Metals/Energy/Commodities";
      case NOTIFY_FAMILY_COMMODITIES: return "Metals/Energy/Commodities";
      case NOTIFY_FAMILY_STOCKS: return "Stocks";
      case NOTIFY_FAMILY_BONDS:  return "Bonds/Rates";
      default:                   return "General-Access";
     }
  }

string NotifySymbolAliasIfStarts(const string clean,const string &variants[],const string alias)
  {
   if(NotifySymbolStartsWithAny(clean,variants))
      return alias;
   return "";
  }

string NotifySignalAssetName(const string symbol)
  {
   string clean=NotifyNormalizeSymbol(symbol);
   string variants[];
   string alias="";

   string gold[]={"XAUUSD","GOLD","XAU","GCUSD","GC"};
   alias=NotifySymbolAliasIfStarts(clean,gold,"GOLD");
   if(alias!="") return alias;

   string silver[]={"XAGUSD","SILVER","XAG","SIUSD","SI"};
   alias=NotifySymbolAliasIfStarts(clean,silver,"SILVER");
   if(alias!="") return alias;

   string platinum[]={"XPTUSD","PLATINUM","XPT"};
   alias=NotifySymbolAliasIfStarts(clean,platinum,"PLATINUM");
   if(alias!="") return alias;

   string palladium[]={"XPDUSD","PALLADIUM","XPD"};
   alias=NotifySymbolAliasIfStarts(clean,palladium,"PALLADIUM");
   if(alias!="") return alias;

   string copper[]={"COPPER","XCUUSD","HG"};
   alias=NotifySymbolAliasIfStarts(clean,copper,"COPPER");
   if(alias!="") return alias;

   string btc[]={"BTCUSDT","BTCUSD","BITCOIN","XBTUSD","BTC"};
   alias=NotifySymbolAliasIfStarts(clean,btc,"BTC");
   if(alias!="") return alias;

   string eth[]={"ETHUSDT","ETHUSD","ETHEREUM","ETH"};
   alias=NotifySymbolAliasIfStarts(clean,eth,"ETH");
   if(alias!="") return alias;

   string sol[]={"SOLUSDT","SOLUSD","SOLANA","SOL"};
   alias=NotifySymbolAliasIfStarts(clean,sol,"SOL");
   if(alias!="") return alias;

   string xrp[]={"XRPUSDT","XRPUSD","XRP"};
   alias=NotifySymbolAliasIfStarts(clean,xrp,"XRP");
   if(alias!="") return alias;

   string nasdaq[]={"USTECH","USTEC","US100","NAS100","NASDAQ","NASUSD","NDX","MNQ","NQ"};
   alias=NotifySymbolAliasIfStarts(clean,nasdaq,"NASDAQ");
   if(alias!="") return alias;

   string us30[]={"US30","DJ30","DOW"};
   alias=NotifySymbolAliasIfStarts(clean,us30,"US30");
   if(alias!="") return alias;

   string spx[]={"SPX500","US500","SP500"};
   alias=NotifySymbolAliasIfStarts(clean,spx,"S&P 500");
   if(alias!="") return alias;

   string ger[]={"GER40","DE40","DAX"};
   alias=NotifySymbolAliasIfStarts(clean,ger,"GER40");
   if(alias!="") return alias;

   string uk[]={"UK100","FTSE"};
   alias=NotifySymbolAliasIfStarts(clean,uk,"UK100");
   if(alias!="") return alias;

   string brent[]={"UKOIL","BRENT","BRN","XBRUSD"};
   alias=NotifySymbolAliasIfStarts(clean,brent,"BRENT OIL");
   if(alias!="") return alias;

   string wti[]={"USOIL","WTI","XTIUSD"};
   alias=NotifySymbolAliasIfStarts(clean,wti,"WTI OIL");
   if(alias!="") return alias;

   string gas[]={"NATGAS","NGAS","NG"};
   alias=NotifySymbolAliasIfStarts(clean,gas,"NATGAS");
   if(alias!="") return alias;

   string maize[]={"MAIZE","CORN"};
   alias=NotifySymbolAliasIfStarts(clean,maize,"MAIZE");
   if(alias!="") return alias;

   string wheat[]={"WHEAT"};
   alias=NotifySymbolAliasIfStarts(clean,wheat,"WHEAT");
   if(alias!="") return alias;

   string cocoa[]={"COCOA"};
   alias=NotifySymbolAliasIfStarts(clean,cocoa,"COCOA");
   if(alias!="") return alias;

   string coffee[]={"COFFEE"};
   alias=NotifySymbolAliasIfStarts(clean,coffee,"COFFEE");
   if(alias!="") return alias;

   string sugar[]={"SUGAR"};
   alias=NotifySymbolAliasIfStarts(clean,sugar,"SUGAR");
   if(alias!="") return alias;

   if(StringLen(clean)>=6)
      return StringSubstr(clean,0,6);
   if(clean!="")
      return clean;
   return symbol;
  }

string NotifyTradeTitle(const string dir)
  {
   return dir+" "+NotifySignalAssetName(_Symbol);
  }

string NotifyTargetForFamily(ENUM_NOTIFY_FAMILY family,int platform)
  {
   if(platform==NOTIFY_PLATFORM_DISCORD)
     {
      if(!NOTIFY_DISCORD_ENABLED)
         return "";
      switch(family)
        {
         case NOTIFY_FAMILY_XAUUSD: return NOTIFY_DISCORD_XAUUSD;
         case NOTIFY_FAMILY_XAGUSD: return NOTIFY_DISCORD_XAUUSD;
         case NOTIFY_FAMILY_ENERGY: return NOTIFY_DISCORD_XAUUSD;
         case NOTIFY_FAMILY_COMMODITIES: return NOTIFY_DISCORD_XAUUSD;
         case NOTIFY_FAMILY_NQ:     return NOTIFY_DISCORD_NQ;
         case NOTIFY_FAMILY_AUDUSD: return NOTIFY_DISCORD_AUDUSD;
         case NOTIFY_FAMILY_BTCUSD: return NOTIFY_DISCORD_BTCUSD;
         case NOTIFY_FAMILY_STOCKS: return NOTIFY_DISCORD_XAGUSD;
         case NOTIFY_FAMILY_BONDS:  return NOTIFY_DISCORD_XAGUSD;
         default:                   return NOTIFY_DISCORD_XAGUSD;
        }
     }

   if(platform==NOTIFY_PLATFORM_TELEGRAM)
     {
      if(!NOTIFY_TELEGRAM_ENABLED || NOTIFY_TELEGRAM_TOKEN=="")
         return "";
      switch(family)
        {
         case NOTIFY_FAMILY_XAUUSD: return NOTIFY_TELEGRAM_XAUUSD;
         case NOTIFY_FAMILY_XAGUSD: return NOTIFY_TELEGRAM_XAUUSD;
         case NOTIFY_FAMILY_ENERGY: return NOTIFY_TELEGRAM_XAUUSD;
         case NOTIFY_FAMILY_COMMODITIES: return NOTIFY_TELEGRAM_XAUUSD;
         case NOTIFY_FAMILY_NQ:     return NOTIFY_TELEGRAM_NQ;
         case NOTIFY_FAMILY_AUDUSD: return NOTIFY_TELEGRAM_AUDUSD;
         case NOTIFY_FAMILY_BTCUSD: return NOTIFY_TELEGRAM_BTCUSD;
         case NOTIFY_FAMILY_STOCKS: return NOTIFY_TELEGRAM_XAGUSD;
         case NOTIFY_FAMILY_BONDS:  return NOTIFY_TELEGRAM_XAGUSD;
         default:                   return NOTIFY_TELEGRAM_XAGUSD;
        }
     }

   return "";
  }

string NotifyResolveWebhook(string symbol,int platform)
  {
   ENUM_NOTIFY_FAMILY family=NotifyResolveFamily(symbol);
   string target=NotifyTargetForFamily(family,platform);
   if(target=="" && family!=NOTIFY_FAMILY_DEFAULT)
      target=NotifyTargetForFamily(NOTIFY_FAMILY_DEFAULT,platform);
   return target;
  }

string NotifyResolveTarget(int platform)
  {
   return NotifyResolveWebhook(_Symbol,platform);
  }

bool NotifyHasAnyConfiguredTarget()
  {
   if(NOTIFY_DISCORD_ENABLED && NotifyResolveTarget(NOTIFY_PLATFORM_DISCORD)!="")
      return true;
   if(NOTIFY_TELEGRAM_ENABLED && NOTIFY_TELEGRAM_TOKEN!="" && NotifyResolveTarget(NOTIFY_PLATFORM_TELEGRAM)!="")
      return true;
   return false;
  }

// CCT_NOTIFY_RUNTIME_FRESHNESS_GATE_V2
// Output-layer guard only: prevents stale/replayed records from sending after EA reload, parameter change, chart reinit, or VPS reboot.
datetime g_notifyRuntimeStartTime=0;

void NotifyRuntimeMarkFreshStart(const string reason)
  {
   datetime now=TimeCurrent();
   if(now<=0)
      now=TimeLocal();

   g_notifyRuntimeStartTime=now;
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT_Notify] Runtime freshness gate armed | reason=%s | start=%s",
                  reason,
                  TimeToString(g_notifyRuntimeStartTime,TIME_DATE|TIME_MINUTES|TIME_SECONDS));
  }

bool NotifyEventFreshForRuntime(datetime eventTime,const string eventType,const string genKey)
  {
   // CCT_NOTIFY_QUIET_STALE_GATE_V1
   // This is an output-layer replay guard. Stale/recovered events are simply not notification candidates.
   // Do not print one line per stale historical execution on every timer/tick; that creates log spam and hides real lifecycle faults.
   if(g_notifyRuntimeStartTime<=0)
      return true;

   if(eventTime<=0)
      return false;

   if(eventTime<g_notifyRuntimeStartTime)
      return false;

   return true;
  }

datetime NotifyBEMoveEventTime(const ExecRecord &exec,int beType)
  {
   if(beType==1 && exec.beCoTime>0)
      return exec.beCoTime;
   if(exec.beGeneralTime>0)
      return exec.beGeneralTime;
   if(exec.beTime>0)
      return exec.beTime;
   if(exec.beCoTime>0)
      return exec.beCoTime;
   return 0;
  }

bool NotifySuppressed()
  {
   if(IsNonVisualTesterRun())
      return true;
   return (!NOTIFY_DISCORD_ENABLED && !NOTIFY_TELEGRAM_ENABLED);
  }

bool NotifyValidExec(const ExecRecord &exec)
  {
   // CCT_NOTIFY_VALID_EXEC_V2
   // A valid notification record must have stable execution geometry. Ticket is preferred,
   // but some market-order paths may receive deal/fill truth before a stable position ticket is present.
   if(exec.genKey=="" || exec.triggerBarTime<=0)
      return false;
   if(exec.visualEntry<=0.0 || exec.brokerSL<=0.0 || exec.brokerTP<=0.0)
      return false;
   return (exec.ticket>0 || exec.isSynthetic || exec.brokerFill>0.0 || exec.execLots>0.0);
  }

string NotifyTFLabel(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "1M";
      case PERIOD_M5:  return "5M";
      case PERIOD_M15: return "15M";
      case PERIOD_H1:  return "1H";
      case PERIOD_H4:  return "4H";
      case PERIOD_D1:  return "1D";
      default:         return EnumToString(tf);
     }
  }

string NotifyModelLabel(ENUM_MODEL_TYPE modelType,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   return ModelTypeLabel(modelType)+" · "+NotifyTFLabel(modelHTF)+"/"+NotifyTFLabel(modelLTF);
  }

string NotifySessionAt(datetime serverTime)
  {
   MqlDateTime ny={};
   TimeToStruct(ToNY(serverTime>0 ? serverTime : CurrentServerTime()),ny);
   if(ny.hour>=2 && ny.hour<6)
      return "London";
   if(ny.hour>=7 && ny.hour<=11)
      return "NY AM";
   if(ny.hour>=20 && ny.hour<=23)
      return "Asia";
   return "Off-session";
  }

string NotifyNYClock(datetime serverTime)
  {
   if(serverTime<=0)
      return "--:-- NY";
   MqlDateTime ny={};
   TimeToStruct(ToNY(serverTime),ny);
   return StringFormat("%02d:%02d NY",ny.hour,ny.min);
  }

string NotifyBirthFromGenKey(const string genKey)
  {
   string parts[];
   if(StringSplit(genKey,'_',parts)>=3 && StringLen(parts[2])>=4)
      return StringSubstr(parts[2],0,2)+":"+StringSubstr(parts[2],2,2)+" NY";
   return "-";
  }

string NotifyPrice(double price)
  {
   if(price<=0.0)
      return "-";
   return DoubleToString(price,_Digits);
  }

string NotifySigned(double value,int digits,string suffix)
  {
   return StringFormat("%s%s%s",(value>=0.0 ? "+" : ""),DoubleToString(value,digits),suffix);
  }

double NotifyRiskR(const ExecRecord &exec,double exitPrice)
  {
   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double risk=MathAbs(entry-exec.brokerSL);
   if(entry<=0.0 || exitPrice<=0.0 || risk<=_Point)
      return 0.0;
   return exec.bull ? (exitPrice-entry)/risk : (entry-exitPrice)/risk;
  }

double NotifyPipSize()
  {
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)
      point=_Point;
   if(digits==3 || digits==5)
      return point*10.0;
   return point;
  }

double NotifyPips(const ExecRecord &exec,double exitPrice)
  {
   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double pip=NotifyPipSize();
   if(entry<=0.0 || exitPrice<=0.0 || pip<=0.0)
      return 0.0;
   return MathAbs(exitPrice-entry)/pip;
  }
// CCT_NOTIFY_SIGNED_EXIT_PIPS_V1
// NotifyPips() remains an absolute distance helper. This outcome-aware wrapper is for exit messages and report ledger rows.
double NotifySignedExitPips(const ExecRecord &exec,double exitPrice,SIB_STATE outcome)
  {
   double pips=NotifyPips(exec,exitPrice);
   double resultR=NotifyRiskR(exec,exitPrice);

   if(outcome==SS_RESOLVED_SL)
      return -MathAbs(pips);

   if(outcome==SS_RESOLVED_TP)
      return MathAbs(pips);

   if(outcome==SS_RESOLVED_BE || outcome==SS_RESOLVED_BE_CO)
     {
      if(resultR<0.0)
         return -MathAbs(pips);
      return MathAbs(pips);
     }

   if(resultR<0.0)
      return -MathAbs(pips);

   return MathAbs(pips);
  }

datetime NotifyEntryTime(const ExecRecord &exec)
  {
   if(exec.ticket>0)
     {
      datetime from=NYDayOpenForServerTime(CurrentServerTime())-86400*7;
      if(HistorySelect(from,CurrentServerTime()+86400))
        {
         for(int i=HistoryDealsTotal()-1;i>=0;i--)
           {
            ulong deal=HistoryDealGetTicket(i);
            if(deal==0)
               continue;
            if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=exec.ticket)
               continue;
            if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
               return (datetime)HistoryDealGetInteger(deal,DEAL_TIME);
           }
        }
     }
   return exec.triggerBarTime;
  }

string NotifyDuration(datetime fromTime,datetime toTime)
  {
   if(fromTime<=0 || toTime<=0 || toTime<fromTime)
      return "-";
   int minutes=(int)((toTime-fromTime)/60);
   int hours=minutes/60;
   int mins=minutes%60;
   if(hours>0)
      return StringFormat("%dh %02dm",hours,mins);
   return StringFormat("%dm",mins);
  }

string NotifyJsonEscape(const string value)
  {
   string out="";
   int len=StringLen(value);
   for(int i=0;i<len;i++)
     {
      ushort ch=StringGetCharacter(value,i);
      if(ch=='\\')
         out+="\\\\";
      else if(ch=='"')
         out+="\\\"";
      else if(ch=='\r')
         out+="\\r";
      else if(ch=='\n')
         out+="\\n";
      else
         out+=ShortToString(ch);
     }
   return out;
  }

string NotifyHtmlEscape(const string value)
  {
   string out=value;
   StringReplace(out,"&","&amp;");
   StringReplace(out,"<","&lt;");
   StringReplace(out,">","&gt;");
   StringReplace(out,"\"","&quot;");
   return out;
  }

string NotifyTelegramText(const string value)
  {
   string out=NotifyHtmlEscape(value);
   StringReplace(out,"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━","——————————————");
   return out;
  }

void NotifyAppendBytes(uchar &body[],const uchar &src[])
  {
   int old=ArraySize(body);
   int n=ArraySize(src);
   ArrayResize(body,old+n);
   for(int i=0;i<n;i++)
      body[old+i]=src[i];
  }

void NotifyAppendString(uchar &body[],const string text)
  {
   uchar bytes[];
   int copied=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(copied>0 && bytes[copied-1]==0)
      ArrayResize(bytes,copied-1);
   NotifyAppendBytes(body,bytes);
  }

bool NotifyReadFileBytes(const string filename,uchar &bytes[])
  {
   ArrayResize(bytes,0);
   int handle=FileOpen(filename,FILE_READ|FILE_BIN);
   if(handle==INVALID_HANDLE)
     {
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Screenshot read failed — file: %s err: %d",filename,GetLastError());
      return false;
     }
   int size=(int)FileSize(handle);
   if(size<=0)
     {
      FileClose(handle);
      return false;
     }
   ArrayResize(bytes,size);
   FileReadArray(handle,bytes,0,size);
   FileClose(handle);
   return (ArraySize(bytes)>0);
  }

bool NotifyChartMatches(long chartId,ENUM_TIMEFRAMES ltfPeriod)
  {
   return (ChartSymbol(chartId)==_Symbol && (ENUM_TIMEFRAMES)ChartPeriod(chartId)==ltfPeriod);
  }

bool NotifyChartHasGenerationObjects(long chartId,const string genKey)
  {
   if(genKey=="")
      return false;

   int total=ObjectsTotal(chartId,-1,-1);
   for(int i=0;i<total;i++)
     {
      string name=ObjectName(chartId,i,-1,-1);
      if(StringFind(name,"CCT_"+genKey+"_")==0 || StringFind(name,genKey)>=0)
         return true;
     }

   return false;
  }

long NotifyFindChart(ENUM_TIMEFRAMES ltfPeriod,const string genKey)
  {
   long current=ChartID();

   if(NotifyChartMatches(current,ltfPeriod) && NotifyChartHasGenerationObjects(current,genKey))
      return current;

   long chartId=ChartFirst();
   while(chartId>=0)
     {
      if(chartId!=current && NotifyChartMatches(chartId,ltfPeriod) && NotifyChartHasGenerationObjects(chartId,genKey))
         return chartId;
      chartId=ChartNext(chartId);
     }

   if(NotifyChartMatches(current,ltfPeriod))
      return current;

   chartId=ChartFirst();
   while(chartId>=0)
     {
      if(NotifyChartMatches(chartId,ltfPeriod))
         return chartId;
      chartId=ChartNext(chartId);
     }

   return current;
  }

struct NotifyChartShotState
  {
   bool              valid;
   bool              scaleFix;
   double            fixedMin;
   double            fixedMax;
   bool              shift;
   double            shiftSize;
   bool              autoScroll;
   long              scale;
  };

void NotifyAddPriceToRange(double price,double &minPrice,double &maxPrice)
  {
   if(price<=0.0)
      return;

   if(minPrice==DBL_MAX || price<minPrice)
      minPrice=price;
   if(maxPrice==-DBL_MAX || price>maxPrice)
      maxPrice=price;
  }

void NotifyAddRecentBarsToRange(ENUM_TIMEFRAMES ltfPeriod,datetime fromTime,datetime toTime,double &minPrice,double &maxPrice)
  {
   if(toTime<=0)
      toTime=CurrentServerTime();

   int ltfSec=(int)PeriodSeconds(ltfPeriod);
   if(ltfSec<=0)
      ltfSec=60;

   if(fromTime<=0 || fromTime>toTime)
      fromTime=toTime-(datetime)(ltfSec*120);
   int maxBars=(int)MathMax(40.0,(double)NOTIFY_SCREENSHOT_MAX_LTF_BARS);
   if((long)(toTime-fromTime)>(long)(ltfSec*maxBars))
      fromTime=toTime-(datetime)(ltfSec*maxBars);

   datetime paddedFrom=fromTime-(datetime)(ltfSec*10);
   datetime paddedTo=toTime+(datetime)(ltfSec*20);

   MqlRates rates[];
   int copied=CopyRates(_Symbol,ltfPeriod,paddedFrom,paddedTo,rates);
   if(copied<=0)
      return;

   for(int i=0;i<copied;i++)
     {
      NotifyAddPriceToRange(rates[i].high,minPrice,maxPrice);
      NotifyAddPriceToRange(rates[i].low,minPrice,maxPrice);
     }
  }

bool NotifyBuildScreenshotRange(const ExecRecord &exec,ENUM_TIMEFRAMES ltfPeriod,double &fixedMin,double &fixedMax)
  {
   double minPrice=DBL_MAX;
   double maxPrice=-DBL_MAX;

   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);

   NotifyAddPriceToRange(entry,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.visualEntry,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.brokerFill,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.brokerSL,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.brokerTP,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.rawSL,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.coPrice,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.anchorA,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.anchorB,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.bePrice,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.beGeneralPrice,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.beCoPrice,minPrice,maxPrice);
   NotifyAddPriceToRange(exec.exitPrice,minPrice,maxPrice);

   double reward=MathAbs(exec.brokerTP-entry);
   if(entry>0.0 && reward>_Point)
     {
      double beTrigger=entry+(exec.bull ? 1.0 : -1.0)*(g_beTriggerPct/100.0)*reward;
      double beTarget=entry+(exec.bull ? 1.0 : -1.0)*(g_beMovePct/100.0)*reward;
      double coBeTrigger=entry+(exec.bull ? 1.0 : -1.0)*(g_beCoMinProgPct/100.0)*reward;
      NotifyAddPriceToRange(beTrigger,minPrice,maxPrice);
      NotifyAddPriceToRange(beTarget,minPrice,maxPrice);
      NotifyAddPriceToRange(coBeTrigger,minPrice,maxPrice);
     }

   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick))
     {
      NotifyAddPriceToRange(tick.bid,minPrice,maxPrice);
      NotifyAddPriceToRange(tick.ask,minPrice,maxPrice);
     }

   datetime fromTime=exec.triggerBarTime;
   if(exec.c1Time>0 && (fromTime<=0 || exec.c1Time<fromTime))
      fromTime=exec.c1Time;

   datetime toTime=CurrentServerTime();
   if(exec.exitTime>0)
      toTime=exec.exitTime;
   else if(exec.beTime>0)
      toTime=exec.beTime;
   else if(exec.beGeneralTime>0)
      toTime=exec.beGeneralTime;
   else if(exec.beCoTime>0)
      toTime=exec.beCoTime;

   NotifyAddRecentBarsToRange(ltfPeriod,fromTime,toTime,minPrice,maxPrice);

   if(minPrice==DBL_MAX || maxPrice==-DBL_MAX || maxPrice<=minPrice)
      return false;

   double range=maxPrice-minPrice;
   double minPadding=120.0*_Point;
   if(minPadding<=0.0)
      minPadding=range*0.10;

   double padding=MathMax(range*0.40,minPadding);
   fixedMin=NormalizeDouble(minPrice-padding,_Digits);
   fixedMax=NormalizeDouble(maxPrice+padding,_Digits);

   if(fixedMin<0.0)
      fixedMin=0.0;

   return (fixedMax>fixedMin);
  }

bool NotifySaveChartShotState(long chartId,NotifyChartShotState &state)
  {
   state.valid=true;
   state.scaleFix=(bool)ChartGetInteger(chartId,CHART_SCALEFIX);
   state.fixedMin=ChartGetDouble(chartId,CHART_FIXED_MIN,0);
   state.fixedMax=ChartGetDouble(chartId,CHART_FIXED_MAX,0);
   state.shift=(bool)ChartGetInteger(chartId,CHART_SHIFT);
   state.shiftSize=ChartGetDouble(chartId,CHART_SHIFT_SIZE,0);
   state.autoScroll=(bool)ChartGetInteger(chartId,CHART_AUTOSCROLL);
   state.scale=(long)ChartGetInteger(chartId,CHART_SCALE);
   return true;
  }

void NotifyRestoreChartAfterScreenshot(long chartId,const NotifyChartShotState &state)
  {
   if(!state.valid)
      return;

   ChartSetInteger(chartId,CHART_SCALEFIX,state.scaleFix);
   ChartSetDouble(chartId,CHART_FIXED_MIN,state.fixedMin);
   ChartSetDouble(chartId,CHART_FIXED_MAX,state.fixedMax);
   ChartSetInteger(chartId,CHART_SHIFT,state.shift);
   ChartSetDouble(chartId,CHART_SHIFT_SIZE,state.shiftSize);
   ChartSetInteger(chartId,CHART_AUTOSCROLL,state.autoScroll);
   ChartSetInteger(chartId,CHART_SCALE,state.scale);
   ChartRedraw(chartId);
  }

bool NotifyPrepareChartForScreenshot(long chartId,const ExecRecord &exec,ENUM_TIMEFRAMES ltfPeriod,NotifyChartShotState &state)
  {
   NotifySaveChartShotState(chartId,state);

   double fixedMin=0.0;
   double fixedMax=0.0;
   bool ok=true;

   if(NotifyBuildScreenshotRange(exec,ltfPeriod,fixedMin,fixedMax))
     {
      ok=(ChartSetInteger(chartId,CHART_SCALEFIX,true) && ok);
      ok=(ChartSetDouble(chartId,CHART_FIXED_MIN,fixedMin) && ok);
      ok=(ChartSetDouble(chartId,CHART_FIXED_MAX,fixedMax) && ok);
     }

   ok=(ChartSetInteger(chartId,CHART_AUTOSCROLL,true) && ok);
   ok=(ChartSetInteger(chartId,CHART_SHIFT,true) && ok);
   ok=(ChartSetDouble(chartId,CHART_SHIFT_SIZE,40.0) && ok);
   ok=(ChartSetInteger(chartId,CHART_SCALE,3) && ok);

   ChartNavigate(chartId,CHART_END,0);
   ChartRedraw(chartId);
   Sleep(250);
   ChartNavigate(chartId,CHART_END,0);
   ChartRedraw(chartId);

   if(!ok)
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Screenshot chart framing partially failed — chart=%I64d symbol=%s err=%d",chartId,_Symbol,GetLastError());

   return ok;
  }

string NotifySafeFileToken(const string raw)
  {
   string clean=NotifyNormalizeSymbol(raw);
   if(clean=="")
      clean="SYMBOL";
   return clean;
  }

string NotifyCaptureScreenshot(const ExecRecord &exec,ENUM_TIMEFRAMES ltfPeriod,string genKey,string eventSuffix)
  {
   if(!NOTIFY_SCREENSHOT_ENABLED)
      return "";

   CCTNotifyDrawExecutionSnapshot(exec);

   long chartId=NotifyFindChart(ltfPeriod,genKey);

   NotifyChartShotState state;
   state.valid=false;

   NotifyPrepareChartForScreenshot(chartId,exec,ltfPeriod,state);

   int settleMs=(int)MathMax((double)NOTIFY_SCREENSHOT_DELAY_MS,1200.0);
   Sleep(settleMs);
   ChartNavigate(chartId,CHART_END,0);
   ChartRedraw(chartId);
   Sleep(300);

   string fileName=StringFormat("CCT_%s_%s_%s.png",NotifySafeFileToken(_Symbol),genKey,eventSuffix);
   string warmFile=StringFormat("CCT_%s_%s_%s_WARMUP.png",NotifySafeFileToken(_Symbol),genKey,eventSuffix);

   ResetLastError();
   bool warmOk=ChartScreenShot(chartId,warmFile,1920,1080,ALIGN_RIGHT);
   if(warmOk)
      FileDelete(warmFile);

   Sleep(350);
   ChartNavigate(chartId,CHART_END,0);
   ChartRedraw(chartId);
   Sleep(250);

   ResetLastError();
   bool ok=ChartScreenShot(chartId,fileName,1920,1080,ALIGN_RIGHT);

   NotifyRestoreChartAfterScreenshot(chartId,state);

   if(!ok)
     {
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Screenshot failed — symbol: %s file: %s err: %d",_Symbol,fileName,GetLastError());
      return "";
     }

   return fileName;
  }

string NotifyBuildEntryMessage(const ExecRecord &exec,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double risk=MathAbs(entry-exec.brokerSL);
   double tpProgress=MathAbs(exec.brokerTP-entry);
   double beTrigger=entry + (exec.bull ? 1.0 : -1.0)*(g_beTriggerPct/100.0)*tpProgress;
   double beTarget=entry + (exec.bull ? 1.0 : -1.0)*(g_beMovePct/100.0)*tpProgress;
   string dir=exec.bull ? "BUY" : "SELL";
   string session=NotifySessionAt(exec.triggerBarTime);
   string model=NotifyModelLabel(exec.modelType,modelHTF,modelLTF);
   double rr=(risk>_Point && tpProgress>_Point) ? tpProgress/risk : exec.lockedRR;

   string text=StringFormat("■ %s — %s | CCT\n\n",NotifyTradeTitle(dir),NotifyFamilyDisplayName(_Symbol));

   text+=StringFormat("▪  Entry     %s\n\n",NotifyPrice(entry));
   text+=StringFormat("▪  TP        %s  (RR %.2f:1)\n\n",NotifyPrice(exec.brokerTP),rr);
   text+=StringFormat("▪  SL        %s\n\n",NotifyPrice(exec.brokerSL));

   if(CCTRuntimeBEGlobalEnabled())
     {
      text+="▫  BE Trigger\n";
      text+=StringFormat("   Price      %s\n",NotifyPrice(beTrigger));
      text+=StringFormat("   Threshold  %.0f%% of TP progress\n",g_beTriggerPct);
      text+="▫  Move SL\n";
      text+=StringFormat("   Price      %s\n",NotifyPrice(beTarget));
      text+=StringFormat("   Locks      %.0f%% of TP progress\n\n",g_beMovePct);
     }

   if(CCTCOBEApplies(exec.triggerBarTime) && exec.coPrice>0.0)
     {
      double coTarget=entry + (exec.bull ? 1.0 : -1.0)*(g_beCoLockPct/100.0)*tpProgress;
      string coMove=(MathAbs(coTarget-entry)<=_Point) ? "~entry" : NotifyPrice(coTarget);
      text+=StringFormat("▫  %s\n",CCTCOBELabel());
      text+=StringFormat("   Gate       CO touch + %ds\n",g_beCoMinSec);
      text+=StringFormat("   Threshold  %.0f%% of TP progress\n",g_beCoMinProgPct);
      text+=StringFormat("   Scope      %s\n",CCTCOBEScopeText());
      text+="▫  Move SL\n";
      text+=StringFormat("   Price      %s\n",coMove);
      text+=StringFormat("   Locks      %.2f%% of TP progress\n\n",g_beCoLockPct);
     }

   text+=StringFormat("Context   Trigger %s · %s · %s\n",NotifyNYClock(exec.triggerBarTime),session,model);
   text+="Risk      Automated signal. Manage risk.";
   return text;
  }

string NotifyBuildBEMoveMessage(const ExecRecord &exec,int beType,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double tpProgress=MathAbs(exec.brokerTP-entry);
   double risk=MathAbs(entry-exec.brokerSL);
   double movedTo=(beType==1 && exec.beCoPrice>0.0) ? exec.beCoPrice :
                  ((beType==0 && exec.beGeneralPrice>0.0) ? exec.beGeneralPrice : exec.bePrice);
   string session=NotifySessionAt(CurrentServerTime());
   string label=(beType==1 ? CCTCOBELabel()+" Threshold" : "BE Threshold");
   double movePct=0.0;
   if(tpProgress>_Point)
      movePct=100.0*MathAbs(movedTo-entry)/tpProgress;

   string text=StringFormat("■ %s — %s\n\n",label,NotifySignalAssetName(_Symbol));
   text+=StringFormat("▪  Entry     %s\n\n",NotifyPrice(entry));
   text+=StringFormat("▪  SL Now    %s\n\n",NotifyPrice(movedTo));
   text+=StringFormat("▪  TP        %s\n\n",NotifyPrice(exec.brokerTP));

   if(beType==1)
     {
      text+=StringFormat("▫  %s Trigger\n",CCTCOBELabel());
      text+=StringFormat("   Threshold  %.0f%% of TP progress\n",g_beCoMinProgPct);
      text+=StringFormat("   CO Age     %ds minimum\n",g_beCoMinSec);
      text+="▫  Move SL\n";
      text+=StringFormat("   Locks      %.2f%% of TP progress\n\n",movePct);
     }
   else
     {
      text+="▫  BE Trigger\n";
      text+=StringFormat("   Threshold  %.0f%% of TP progress\n",g_beTriggerPct);
      text+="▫  Move SL\n";
      text+=StringFormat("   Locks      %.0f%% of TP progress\n\n",movePct);
     }

   text+=StringFormat("Context   Time %s · %s · %s\n",NotifyNYClock(CurrentServerTime()),session,NotifyModelLabel(exec.modelType,modelHTF,modelLTF));
   text+="Risk      Stop has been updated. Manage risk.";
   return text;
  }

string NotifyBuildExitMessage(const ExecRecord &exec,SIB_STATE outcome,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   string label="SL HIT";
   if(outcome==SS_RESOLVED_TP)
      label="TP HIT";
   else if(outcome==SS_RESOLVED_BE)
      label="BE EXIT";
   else if(outcome==SS_RESOLVED_BE_CO)
      label=CCTCOBELabel()+" EXIT";

   string session=NotifySessionAt(exec.triggerBarTime);
   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double resultR=NotifyRiskR(exec,exec.exitPrice);
   double pips=NotifySignedExitPips(exec,exec.exitPrice,outcome);

   string text=StringFormat("■ %s — %s\n\n",label,NotifySignalAssetName(_Symbol));
   text+=StringFormat("▪  Entry     %s\n\n",NotifyPrice(entry));
   text+=StringFormat("▪  Exit      %s\n\n",NotifyPrice(exec.exitPrice));
   text+=StringFormat("▪  Result    %s  (%s pips)\n\n",NotifySigned(resultR,2,"R"),NotifySigned(pips,1,""));
   text+=StringFormat("▪  Duration  %s\n\n",NotifyDuration(NotifyEntryTime(exec),exec.exitTime));
   text+=StringFormat("Context   Trigger %s · %s · %s\n",NotifyNYClock(exec.triggerBarTime),session,NotifyModelLabel(exec.modelType,modelHTF,modelLTF));
   text+="Risk      Trade resolved.";
   return text;
  }

void NotifyBuildDiscordMultipart(const string payload,const uchar &imageBytes[],uchar &body[])
  {
   ArrayResize(body,0);
   string boundary="CCTNotifyBoundary7x3q";
   NotifyAppendString(body,"--"+boundary+"\r\n");
   NotifyAppendString(body,"Content-Disposition: form-data; name=\"payload_json\"\r\n");
   NotifyAppendString(body,"Content-Type: application/json\r\n\r\n");
   NotifyAppendString(body,payload);
   NotifyAppendString(body,"\r\n--"+boundary+"\r\n");
   NotifyAppendString(body,"Content-Disposition: form-data; name=\"files[0]\"; filename=\"screenshot.png\"\r\n");
   NotifyAppendString(body,"Content-Type: image/png\r\n\r\n");
   NotifyAppendBytes(body,imageBytes);
   NotifyAppendString(body,"\r\n--"+boundary+"--\r\n");
  }

bool NotifyDispatchDiscord(const string text,const uchar &imageBytes[],bool imagePresent,int colorInt)
  {
   string target=NotifyResolveTarget(NOTIFY_PLATFORM_DISCORD);
   if(target=="")
      return false;

   string url=target;
   if(StringFind(url,"?")<0)
      url+="?wait=true";
   else if(StringFind(url,"wait=")<0)
      url+="&wait=true";

   string payload="";
   uchar body[];
   if(imagePresent)
     {
      payload=StringFormat("{\"content\":\"\",\"embeds\":[{\"description\":\"%s\",\"color\":%d,\"image\":{\"url\":\"attachment://screenshot.png\"}}]}",
                           NotifyJsonEscape(text),colorInt);
      NotifyBuildDiscordMultipart(payload,imageBytes,body);
     }
   else
     {
      payload=StringFormat("{\"content\":\"\",\"embeds\":[{\"description\":\"%s\",\"color\":%d}]}",
                           NotifyJsonEscape(text),colorInt);
      NotifyAppendString(body,payload);
     }

   uchar response[];
   string responseHeaders="";
   string headers=imagePresent ? "Content-Type: multipart/form-data; boundary=CCTNotifyBoundary7x3q\r\n" : "Content-Type: application/json\r\n";
   ResetLastError();
   int res=WebRequest("POST",url,headers,5000,body,response,responseHeaders);
   if(res==200 || res==204)
      return true;

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT_Notify] Dispatch failed — platform: Discord, code: %d, symbol: %s, err: %d",res,_Symbol,GetLastError());
   return false;
  }

void NotifySplitTelegramTarget(const string target,string &chatId,string &threadId)
  {
   chatId=target;
   threadId="";
   int sep=StringFind(target,"|");
   if(sep<0)
      sep=StringFind(target,",");
   if(sep>=0)
     {
      chatId=StringSubstr(target,0,sep);
      threadId=StringSubstr(target,sep+1);
     }
  }

void NotifyBuildTelegramMultipart(const string chatId,const string threadId,const string caption,const uchar &imageBytes[],uchar &body[])
  {
   ArrayResize(body,0);
   string boundary="CCTNotifyBoundary7x3q";
   NotifyAppendString(body,"--"+boundary+"\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n"+chatId+"\r\n");
   if(threadId!="")
      NotifyAppendString(body,"--"+boundary+"\r\nContent-Disposition: form-data; name=\"message_thread_id\"\r\n\r\n"+threadId+"\r\n");
   NotifyAppendString(body,"--"+boundary+"\r\nContent-Disposition: form-data; name=\"parse_mode\"\r\n\r\nHTML\r\n");
   NotifyAppendString(body,"--"+boundary+"\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n"+caption+"\r\n");
   NotifyAppendString(body,"--"+boundary+"\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"screenshot.png\"\r\nContent-Type: image/png\r\n\r\n");
   NotifyAppendBytes(body,imageBytes);
   NotifyAppendString(body,"\r\n--"+boundary+"--\r\n");
  }

bool NotifyTelegramSendMessage(const string chatId,const string threadId,const string text)
  {
   string url="https://api.telegram.org/bot"+NOTIFY_TELEGRAM_TOKEN+"/sendMessage";
   string payload=StringFormat("{\"chat_id\":\"%s\",\"text\":\"%s\",\"parse_mode\":\"HTML\"",
                               NotifyJsonEscape(chatId),NotifyJsonEscape(text));
   if(threadId!="")
      payload+=StringFormat(",\"message_thread_id\":%s",threadId);
   payload+="}";

   uchar body[];
   NotifyAppendString(body,payload);
   uchar response[];
   string responseHeaders="";
   ResetLastError();
   int res=WebRequest("POST",url,"Content-Type: application/json\r\n",5000,body,response,responseHeaders);
   if(res==200)
      return true;

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT_Notify] Dispatch failed — platform: Telegram sendMessage, code: %d, symbol: %s, err: %d",res,_Symbol,GetLastError());
   return false;
  }

bool NotifyTelegramSendPhoto(const string chatId,const string threadId,const string caption,const uchar &imageBytes[])
  {
   string url="https://api.telegram.org/bot"+NOTIFY_TELEGRAM_TOKEN+"/sendPhoto";
   uchar body[];
   NotifyBuildTelegramMultipart(chatId,threadId,caption,imageBytes,body);
   uchar response[];
   string responseHeaders="";
   ResetLastError();
   int res=WebRequest("POST",url,"Content-Type: multipart/form-data; boundary=CCTNotifyBoundary7x3q\r\n",5000,body,response,responseHeaders);
   if(res==200)
      return true;

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT_Notify] Dispatch failed — platform: Telegram sendPhoto, code: %d, symbol: %s, err: %d",res,_Symbol,GetLastError());
   return false;
  }

bool NotifyDispatchTelegram(const string text,const uchar &imageBytes[],bool imagePresent)
  {
   string target=NotifyResolveTarget(NOTIFY_PLATFORM_TELEGRAM);
   if(target=="" || NOTIFY_TELEGRAM_TOKEN=="")
      return false;

   string chatId="";
   string threadId="";
   NotifySplitTelegramTarget(target,chatId,threadId);
   if(chatId=="")
      return false;

   string tgText=NotifyTelegramText(text);
   if(!imagePresent)
      return NotifyTelegramSendMessage(chatId,threadId,tgText);

   if(StringLen(tgText)>1000)
     {
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Telegram caption over 1000 chars; sending text then photo — symbol: %s",_Symbol);
      bool okText=NotifyTelegramSendMessage(chatId,threadId,tgText);
      bool okPhoto=NotifyTelegramSendPhoto(chatId,threadId,"",imageBytes);
      return (okText && okPhoto);
     }

   return NotifyTelegramSendPhoto(chatId,threadId,tgText,imageBytes);
  }

bool NotifyDispatchAll(const string text,const string imagePath,int colorInt)
  {
   uchar imageBytes[];
   bool imagePresent=false;
   if(imagePath!="")
      imagePresent=NotifyReadFileBytes(imagePath,imageBytes);

   bool attempted=false;
   bool allOk=true;
   if(NOTIFY_DISCORD_ENABLED && NotifyResolveTarget(NOTIFY_PLATFORM_DISCORD)!="")
     {
      attempted=true;
      allOk=(NotifyDispatchDiscord(text,imageBytes,imagePresent,colorInt) && allOk);
     }
   if(NOTIFY_TELEGRAM_ENABLED && NotifyResolveTarget(NOTIFY_PLATFORM_TELEGRAM)!="" && NOTIFY_TELEGRAM_TOKEN!="")
     {
      attempted=true;
      allOk=(NotifyDispatchTelegram(text,imageBytes,imagePresent) && allOk);
     }

   if(imagePath!="" && ((attempted && allOk) || !attempted))
      FileDelete(imagePath);

   return (attempted && allOk);
  }

int NotifyEntryColor(const ExecRecord &exec)
  {
   return exec.bull ? 65280 : 16711680;
  }

int NotifyExitColor(SIB_STATE outcome)
  {
   if(outcome==SS_RESOLVED_TP)
      return 65280;
   if(outcome==SS_RESOLVED_BE_CO)
      return 3381759;
   if(outcome==SS_RESOLVED_BE)
      return 16776960;
   return 16711680;
  }


#define CCT_NOTIFY_REPORTS_V1 1
#define CCT_NOTIFY_LEDGER_FILE "CCT_TradeLedger.csv"

string NotifyReportCleanToken(string value)
  {
   StringReplace(value,","," ");
   StringReplace(value,"\r"," ");
   StringReplace(value,"\n"," ");
   StringReplace(value,"|"," ");
   return value;
  }

string NotifyDateKey(datetime t)
  {
   MqlDateTime dt={};
   TimeToStruct(t,dt);
   return StringFormat("%04d%02d%02d",dt.year,dt.mon,dt.day);
  }

string NotifyDateOnly(datetime t)
  {
   return TimeToString(t,TIME_DATE);
  }

string NotifyOutcomeReportLabel(SIB_STATE outcome)
  {
   if(outcome==SS_RESOLVED_TP)
      return "TP";
   if(outcome==SS_RESOLVED_SL)
      return "SL";
   if(outcome==SS_RESOLVED_BE)
      return "BE";
   if(outcome==SS_RESOLVED_BE_CO)
      return "NY_BE_CO";
   return EnumToString(outcome);
  }

string NotifyDowName(int dow)
  {
   switch(dow)
     {
      case 0: return "Sunday";
      case 1: return "Monday";
      case 2: return "Tuesday";
      case 3: return "Wednesday";
      case 4: return "Thursday";
      case 5: return "Friday";
      case 6: return "Saturday";
     }
   return "-";
  }

datetime NotifyWeekStart(datetime t)
  {
   MqlDateTime dt={};
   TimeToStruct(t,dt);
   datetime midnight=t-(dt.hour*3600+dt.min*60+dt.sec);
   int daysSinceMonday=(dt.day_of_week+6)%7;
   return midnight-(datetime)(daysSinceMonday*86400);
  }

datetime NotifyMonthStart(datetime t)
  {
   MqlDateTime dt={};
   TimeToStruct(t,dt);
   dt.day=1;
   dt.hour=0;
   dt.min=0;
   dt.sec=0;
   return StructToTime(dt);
  }

datetime NotifyPrevMonthStart(datetime currentMonthStart)
  {
   MqlDateTime dt={};
   TimeToStruct(currentMonthStart,dt);
   dt.day=1;
   dt.hour=0;
   dt.min=0;
   dt.sec=0;
   dt.mon--;
   if(dt.mon<1)
     {
      dt.mon=12;
      dt.year--;
     }
   return StructToTime(dt);
  }

void NotifyReportAccumulateKey(const string key,double r,string &keys[],double &totals[],int &counts[])
  {
   int n=ArraySize(keys);
   for(int i=0;i<n;i++)
     {
      if(keys[i]==key)
        {
         totals[i]+=r;
         counts[i]++;
         return;
        }
     }

   ArrayResize(keys,n+1);
   ArrayResize(totals,n+1);
   ArrayResize(counts,n+1);
   keys[n]=key;
   totals[n]=r;
   counts[n]=1;
  }

string NotifyReportBestWorstLine(const string label,string &keys[],double &totals[],int &counts[],bool best)
  {
   int n=ArraySize(keys);
   if(n<=0)
      return label+" -";

   int idx=0;
   for(int i=1;i<n;i++)
     {
      if(best && totals[i]>totals[idx])
         idx=i;
      if(!best && totals[i]<totals[idx])
         idx=i;
     }

   return StringFormat("%s %s (%+.2fR / %d trades)",label,keys[idx],totals[idx],counts[idx]);
  }

bool NotifyDiscordSendReportToTarget(const string target,const string text,int colorInt)
  {
   if(target=="")
      return false;

   string url=target;
   if(StringFind(url,"?")<0)
      url+="?wait=true";
   else if(StringFind(url,"wait=")<0)
      url+="&wait=true";

   string payload=StringFormat("{\"content\":\"\",\"embeds\":[{\"description\":\"%s\",\"color\":%d}]}",NotifyJsonEscape(text),colorInt);
   uchar body[];
   NotifyAppendString(body,payload);
   uchar response[];
   string responseHeaders="";
   ResetLastError();
   int res=WebRequest("POST",url,"Content-Type: application/json\r\n",5000,body,response,responseHeaders);
   if(res==200 || res==204)
      return true;

   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT_Notify] Report dispatch failed — platform: Discord, code: %d, err: %d",res,GetLastError());
   return false;
  }

string NotifyRouteLabel(ENUM_NOTIFY_FAMILY family)
  {
   switch(family)
     {
      case NOTIFY_FAMILY_AUDUSD: return "FX";
      case NOTIFY_FAMILY_BTCUSD: return "Crypto";
      case NOTIFY_FAMILY_NQ:     return "Indices";
      case NOTIFY_FAMILY_XAUUSD:
      case NOTIFY_FAMILY_XAGUSD:
      case NOTIFY_FAMILY_ENERGY:
      case NOTIFY_FAMILY_COMMODITIES: return "MEC";
      default: return "General-Access";
     }
  }

string NotifyReportRouteKey(ENUM_NOTIFY_FAMILY family)
  {
   string label=NotifyRouteLabel(family);
   StringReplace(label,"/","_");
   StringReplace(label,"-","_");
   StringReplace(label," ","_");
   return label;
  }

ENUM_NOTIFY_FAMILY NotifyRouteFamilyForReport(ENUM_NOTIFY_FAMILY family)
  {
   switch(family)
     {
      case NOTIFY_FAMILY_AUDUSD: return NOTIFY_FAMILY_AUDUSD;
      case NOTIFY_FAMILY_BTCUSD: return NOTIFY_FAMILY_BTCUSD;
      case NOTIFY_FAMILY_NQ:     return NOTIFY_FAMILY_NQ;
      case NOTIFY_FAMILY_XAUUSD:
      case NOTIFY_FAMILY_XAGUSD:
      case NOTIFY_FAMILY_ENERGY:
      case NOTIFY_FAMILY_COMMODITIES: return NOTIFY_FAMILY_XAUUSD;
      default: return NOTIFY_FAMILY_DEFAULT;
     }
  }

ENUM_NOTIFY_FAMILY NotifyReportBucketForRow(const string symbol,const string familyLabel)
  {
   ENUM_NOTIFY_FAMILY bySymbol=NotifyRouteFamilyForReport(NotifyResolveFamily(symbol));
   if(bySymbol!=NOTIFY_FAMILY_DEFAULT)
      return bySymbol;

   string label=familyLabel;
   StringToUpper(label);
   if(StringFind(label,"FOREX")>=0 || StringFind(label,"FX")>=0 || StringFind(label,"CURRENC")>=0)
      return NOTIFY_FAMILY_AUDUSD;
   if(StringFind(label,"CRYPTO")>=0)
      return NOTIFY_FAMILY_BTCUSD;
   if(StringFind(label,"INDIC")>=0 || StringFind(label,"INDEX")>=0)
      return NOTIFY_FAMILY_NQ;
   if(StringFind(label,"METAL")>=0 || StringFind(label,"ENERGY")>=0 || StringFind(label,"COMMOD")>=0)
      return NOTIFY_FAMILY_XAUUSD;

   return NOTIFY_FAMILY_DEFAULT;
  }

bool NotifyDispatchReportTextToFamily(const string text,ENUM_NOTIFY_FAMILY family)
  {
   bool attempted=false;
   bool allOk=true;

   string discordTarget=NotifyTargetForFamily(family,NOTIFY_PLATFORM_DISCORD);
   if(NOTIFY_DISCORD_ENABLED && discordTarget!="")
     {
      attempted=true;
      allOk=(NotifyDiscordSendReportToTarget(discordTarget,text,8421504) && allOk);
     }

   string telegramTarget=NotifyTargetForFamily(family,NOTIFY_PLATFORM_TELEGRAM);
   if(NOTIFY_TELEGRAM_ENABLED && NOTIFY_TELEGRAM_TOKEN!="" && telegramTarget!="")
     {
      string chatId="";
      string threadId="";
      NotifySplitTelegramTarget(telegramTarget,chatId,threadId);
      if(chatId!="")
        {
         attempted=true;
         allOk=(NotifyTelegramSendMessage(chatId,threadId,NotifyTelegramText(text)) && allOk);
        }
     }

   if(!attempted)
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Report not sent: %s Telegram/Discord report target is not configured.",NotifyRouteLabel(family));

   return (attempted && allOk);
  }

void NotifyLedgerAppendExit(const ExecRecord &exec,SIB_STATE outcome,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   if((bool)MQLInfoInteger(MQL_TESTER))
      return;
   if(!NotifyValidExec(exec))
      return;

   long account=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string dedupe=StringFormat("CCT_LDG_%I64d_%I64d_%d",account,(long)exec.ticket,(int)outcome);
   if(GlobalVariableCheck(dedupe))
      return;

   double entry=(exec.brokerFill>0.0 ? exec.brokerFill : exec.visualEntry);
   double exitPrice=exec.exitPrice;
   double resultR=NotifyRiskR(exec,exitPrice);
   double pips=NotifySignedExitPips(exec,exitPrice,outcome);
   datetime exitTime=(exec.exitTime>0 ? exec.exitTime : CurrentServerTime());
   if(exitTime<=0)
      exitTime=TimeCurrent();

   bool exists=FileIsExist(CCT_NOTIFY_LEDGER_FILE,FILE_COMMON);
   int h=FileOpen(CCT_NOTIFY_LEDGER_FILE,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE)
     {
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Could not open trade ledger: %s err=%d",CCT_NOTIFY_LEDGER_FILE,GetLastError());
      return;
     }

   if(!exists || FileSize(h)==0)
     {
      FileWriteString(h,"account,symbol,family,genKey,model,session,outcome,serverTime,exitEpoch,actualR,pips,entry,exit,sl,tp,lots,ticket\r\n");
     }

   FileSeek(h,0,SEEK_END);

   string model=NotifyModelLabel(exec.modelType,modelHTF,modelLTF);
   string session=NotifySessionAt(exec.triggerBarTime);
   string family=NotifyFamilyDisplayName(_Symbol);
   string outcomeText=NotifyOutcomeReportLabel(outcome);

   string line=StringFormat("%I64d,%s,%s,%s,%s,%s,%s,%s,%I64d,%.6f,%.2f,%s,%s,%s,%s,%.2f,%I64d",
                            account,
                            NotifyReportCleanToken(_Symbol),
                            NotifyReportCleanToken(family),
                            NotifyReportCleanToken(exec.genKey),
                            NotifyReportCleanToken(model),
                            NotifyReportCleanToken(session),
                            outcomeText,
                            NotifyReportCleanToken(TimeToString(exitTime,TIME_DATE|TIME_SECONDS)),
                            (long)exitTime,
                            resultR,
                            pips,
                            DoubleToString(entry,_Digits),
                            DoubleToString(exitPrice,_Digits),
                            DoubleToString(exec.brokerSL,_Digits),
                            DoubleToString(exec.brokerTP,_Digits),
                            exec.execLots,
                            (long)exec.ticket);

   FileWriteString(h,line+"\r\n");
   FileFlush(h);
   FileClose(h);
   GlobalVariableSet(dedupe,(double)CurrentServerTime());
  }

bool NotifyBuildRReport(const string reportName,datetime fromTime,datetime toTime,ENUM_NOTIFY_FAMILY route,bool filterByRoute,bool cumulativePackage,string &text)
  {
   int h=FileOpen(CCT_NOTIFY_LEDGER_FILE,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE)
     {
      text=StringFormat("■ CCT %s Report\n\nRoute    %s\nPeriod   %s -> %s\n\nNo ledger found yet. Reports start after new resolved trades are recorded.",
                        reportName,NotifyRouteLabel(route),NotifyDateOnly(fromTime),NotifyDateOnly(toTime));
      return true;
     }

   int trades=0;
   int wins=0;
   int tp=0;
   int sl=0;
   int be=0;
   int co=0;
   double totalR=0.0;
   double grossWin=0.0;
   double grossLoss=0.0;

   string assetKeys[];
   double assetTotals[];
   int assetCounts[];
   string dayKeys[];
   double dayTotals[];
   int dayCounts[];
   string accountKeys[];
   double accountTotals[];
   int accountCounts[];
   string marketKeys[];
   double marketTotals[];
   int marketCounts[];

   while(!FileIsEnding(h))
     {
      string line=FileReadString(h);
      if(line=="" || StringFind(line,"account,")==0)
         continue;

      string cols[];
      int n=StringSplit(line,StringGetCharacter(",",0),cols);
      if(n<17)
         continue;

      datetime exitTime=(datetime)StringToInteger(cols[8]);
      if(exitTime<fromTime || exitTime>=toTime)
         continue;

      ENUM_NOTIFY_FAMILY rowRoute=NotifyReportBucketForRow(cols[1],cols[2]);
      if(filterByRoute && rowRoute!=route)
         continue;

      double r=StringToDouble(cols[9]);
      string outcome=cols[6];

      trades++;
      totalR+=r;
      if(r>0.0)
        {
         wins++;
         grossWin+=r;
        }
      else if(r<0.0)
        {
         grossLoss+=MathAbs(r);
        }

      if(outcome=="TP")
         tp++;
      else if(outcome=="SL")
         sl++;
      else if(outcome=="BE")
         be++;
      else if(outcome=="NY_BE_CO")
         co++;

      NotifyReportAccumulateKey(cols[1],r,assetKeys,assetTotals,assetCounts);
      NotifyReportAccumulateKey(cols[0],r,accountKeys,accountTotals,accountCounts);
      NotifyReportAccumulateKey(NotifyRouteLabel(rowRoute),r,marketKeys,marketTotals,marketCounts);

      MqlDateTime dt={};
      TimeToStruct(exitTime,dt);
      NotifyReportAccumulateKey(NotifyDowName(dt.day_of_week),r,dayKeys,dayTotals,dayCounts);
     }

   FileClose(h);

   text=StringFormat("■ CCT %s Report\n\nRoute    %s\nPeriod   %s -> %s\n",
                     reportName,
                     cumulativePackage ? "General-Access cumulative" : NotifyRouteLabel(route),
                     NotifyDateOnly(fromTime),
                     NotifyDateOnly(toTime));

   if(trades<=0)
     {
      text+="\nNo resolved trades recorded for this period.";
      return true;
     }

   double winRate=100.0*(double)wins/(double)trades;
   double pf=(grossLoss>0.0 ? grossWin/grossLoss : (grossWin>0.0 ? 999.0 : 0.0));
   double expectancy=totalR/(double)trades;

   text+=StringFormat("\nTotal R  %+.2fR\n",totalR);
   text+=StringFormat("Trades   %d\n",trades);
   text+=StringFormat("Expect.  %+.3fR/trade\n",expectancy);
   text+=StringFormat("WinRate  %.1f%%\n",winRate);
   text+=StringFormat("PF       %.2f\n\n",pf);

   text+=StringFormat("Outcomes TP %d | SL %d | BE %d | %s %d\n\n",tp,sl,be,CCTCOBELabel(),co);
   if(cumulativePackage)
     {
      text+="Markets\n";
      for(int i=0;i<ArraySize(marketKeys);i++)
         text+=StringFormat("%s  %+.2fR / %d trades\n",marketKeys[i],marketTotals[i],marketCounts[i]);
      text+="\n";
     }
   else
     {
      text+=NotifyReportBestWorstLine("Best asset ",assetKeys,assetTotals,assetCounts,true)+"\n";
      text+=NotifyReportBestWorstLine("Worst asset",assetKeys,assetTotals,assetCounts,false)+"\n";
      text+=NotifyReportBestWorstLine("Best day   ",dayKeys,dayTotals,dayCounts,true)+"\n";
      text+=NotifyReportBestWorstLine("Worst day  ",dayKeys,dayTotals,dayCounts,false)+"\n";
     }

   if(ArraySize(accountKeys)>1)
     {
      text+="\nAccounts\n";
      for(int i=0;i<ArraySize(accountKeys);i++)
         text+=StringFormat("%s  %+.2fR / %d trades\n",accountKeys[i],accountTotals[i],accountCounts[i]);
     }

   return true;
  }

bool NotifyReportLockExists(const string kind,datetime fromTime,datetime toTime,ENUM_NOTIFY_FAMILY route)
  {
   string lockFile=StringFormat("CCT_ReportSent_%s_%s_%s_%s.lock",kind,NotifyReportRouteKey(route),NotifyDateKey(fromTime),NotifyDateKey(toTime));
   return FileIsExist(lockFile,FILE_COMMON);
  }

void NotifyReportCreateLock(const string kind,datetime fromTime,datetime toTime,ENUM_NOTIFY_FAMILY route)
  {
   string lockFile=StringFormat("CCT_ReportSent_%s_%s_%s_%s.lock",kind,NotifyReportRouteKey(route),NotifyDateKey(fromTime),NotifyDateKey(toTime));
   int h=FileOpen(lockFile,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h!=INVALID_HANDLE)
     {
      FileWriteString(h,TimeToString(CurrentServerTime(),TIME_DATE|TIME_SECONDS));
      FileClose(h);
     }
  }

void NotifyMaybeSendPeriodReport(const string kind,const string label,datetime fromTime,datetime toTime,ENUM_NOTIFY_FAMILY route,bool filterByRoute,bool cumulativePackage)
  {
   if(NotifyReportLockExists(kind,fromTime,toTime,route))
      return;

   string text="";
   if(!NotifyBuildRReport(label,fromTime,toTime,route,filterByRoute,cumulativePackage,text))
      return;

   NotifyReportCreateLock(kind,fromTime,toTime,route);
   NotifyDispatchReportTextToFamily(text,route);
  }

bool NotifyParseReportSendTime(int &hour,int &minute)
  {
   hour=0;
   minute=0;

   string s=NOTIFY_REPORT_SEND_TIME;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s=="")
      return false;

   StringToLower(s);
   StringReplace(s," ","");

   bool pm=(StringFind(s,"pm")>=0);
   bool am=(StringFind(s,"am")>=0);
   StringReplace(s,"am","");
   StringReplace(s,"pm","");

   string parts[];
   int n=StringSplit(s,':',parts);
   if(n<=0)
      return false;

   int h=(int)StringToInteger(parts[0]);
   int m=0;
   if(n>=2)
      m=(int)StringToInteger(parts[1]);

   if(pm && h<12)
      h+=12;
   if(am && h==12)
      h=0;

   hour=MathMax(0,MathMin(23,h));
   minute=MathMax(0,MathMin(59,m));
   return true;
  }

bool NotifyReportWeekendGateOpen(datetime now,int dueHour,int dueMinute)
  {
   datetime localTime=DisplayTZIsNY() ? ToNY(now) : ToDisplay(now);
   MqlDateTime local={};
   TimeToStruct(localTime,local);

   if(local.day_of_week!=(int)NOTIFY_REPORT_WEEKLY_DAY)
      return false;

   int localMinutes=local.hour*60+local.min;
   int dueMinutes=dueHour*60+dueMinute;
   return (localMinutes>=dueMinutes);
  }

void NotifyReportsOnTimer()
  {
   if((bool)MQLInfoInteger(MQL_TESTER))
      return;

   if(!NOTIFY_REPORTS_ENABLED && !NOTIFY_REPORT_TEST_NOW)
      return;

   if(!NOTIFY_DISCORD_ENABLED && !NOTIFY_TELEGRAM_ENABLED)
      return;

   datetime now=CurrentServerTime();
   if(now<=0)
      now=TimeCurrent();

   int dueHour=0;
   int dueMinute=0;
   bool validSendTime=NotifyParseReportSendTime(dueHour,dueMinute);
   if(!validSendTime && !NOTIFY_REPORT_TEST_NOW)
     {
      if(!CCTSuppressLiveCCTJournals())
         Print("[CCT_Notify] Report send time is blank or invalid; scheduled reports skipped.");
      return;
     }

   MqlDateTime dt={};
   TimeToStruct(now,dt);
   bool weekendGateOpen=NotifyReportWeekendGateOpen(now,dueHour,dueMinute);
   if(!weekendGateOpen && !NOTIFY_REPORT_TEST_NOW)
      return;

   if(NOTIFY_REPORT_TEST_NOW)
     {
      datetime today=now-(dt.hour*3600+dt.min*60+dt.sec);
      ENUM_NOTIFY_FAMILY testRoutes[5];
      testRoutes[0]=NOTIFY_FAMILY_DEFAULT;
      testRoutes[1]=NOTIFY_FAMILY_AUDUSD;
      testRoutes[2]=NOTIFY_FAMILY_NQ;
      testRoutes[3]=NOTIFY_FAMILY_BTCUSD;
      testRoutes[4]=NOTIFY_FAMILY_XAUUSD;

      for(int i=0;i<5;i++)
        {
         ENUM_NOTIFY_FAMILY route=testRoutes[i];
         if(NotifyReportLockExists("TEST",today,today+86400,route))
            continue;
         NotifyReportCreateLock("TEST",today,today+86400,route);
         NotifyDispatchReportTextToFamily(StringFormat("■ CCT Report Test\n\nRoute    %s\nStatus   Telegram/Discord report path is connected.",NotifyRouteLabel(route)),route);
        }
     }

   if(!NOTIFY_REPORTS_ENABLED)
      return;

   if(NOTIFY_REPORT_WEEKLY)
     {
      datetime thisWeek=NotifyWeekStart(now);
      datetime nextWeek=thisWeek+7*86400;
      NotifyMaybeSendPeriodReport("WEEKLY","Weekly FX",thisWeek,nextWeek,NOTIFY_FAMILY_AUDUSD,true,false);
      NotifyMaybeSendPeriodReport("WEEKLY","Weekly Indices",thisWeek,nextWeek,NOTIFY_FAMILY_NQ,true,false);
      NotifyMaybeSendPeriodReport("WEEKLY","Weekly Crypto",thisWeek,nextWeek,NOTIFY_FAMILY_BTCUSD,true,false);
      NotifyMaybeSendPeriodReport("WEEKLY","Weekly MEC",thisWeek,nextWeek,NOTIFY_FAMILY_XAUUSD,true,false);
      NotifyMaybeSendPeriodReport("WEEKLY","Weekly Cumulative",thisWeek,nextWeek,NOTIFY_FAMILY_DEFAULT,false,true);
      if(NOTIFY_REPORT_GENERAL_DETAILED)
         NotifyMaybeSendPeriodReport("WEEKLY_DETAIL","Weekly Detailed",thisWeek,nextWeek,NOTIFY_FAMILY_DEFAULT,false,false);
     }

   if(NOTIFY_REPORT_MONTHLY)
     {
      datetime thisMonth=NotifyMonthStart(now);
      datetime prevMonth=NotifyPrevMonthStart(thisMonth);
      NotifyMaybeSendPeriodReport("MONTHLY","Monthly FX",prevMonth,thisMonth,NOTIFY_FAMILY_AUDUSD,true,false);
      NotifyMaybeSendPeriodReport("MONTHLY","Monthly Indices",prevMonth,thisMonth,NOTIFY_FAMILY_NQ,true,false);
      NotifyMaybeSendPeriodReport("MONTHLY","Monthly Crypto",prevMonth,thisMonth,NOTIFY_FAMILY_BTCUSD,true,false);
      NotifyMaybeSendPeriodReport("MONTHLY","Monthly MEC",prevMonth,thisMonth,NOTIFY_FAMILY_XAUUSD,true,false);
      NotifyMaybeSendPeriodReport("MONTHLY","Monthly Cumulative",prevMonth,thisMonth,NOTIFY_FAMILY_DEFAULT,false,true);
      if(NOTIFY_REPORT_GENERAL_DETAILED)
         NotifyMaybeSendPeriodReport("MONTHLY_DETAIL","Monthly Detailed",prevMonth,thisMonth,NOTIFY_FAMILY_DEFAULT,false,false);
     }
  }
void NotifyInit()
  {
   NotifyRuntimeMarkFreshStart("NotifyInit");
   if(NotifySuppressed())
      return;

   if(!CCTSuppressLiveCCTJournals())
      Print("CCT_Notify: Add to MT5 WebRequest whitelist: https://discord.com, https://discordapp.com, https://api.telegram.org");
   if(NOTIFY_TELEGRAM_ENABLED && NOTIFY_TELEGRAM_TOKEN=="")
     {
      if(!CCTSuppressLiveCCTJournals())
         Print("[CCT_Notify] Telegram enabled but bot token is empty.");
     }
  }


#define CCT_NOTIFY_DEFERRED_ENTRY_V2 1
ExecRecord       g_notifyEntryQueue[];
ENUM_TIMEFRAMES  g_notifyEntryQueueHTF[];
ENUM_TIMEFRAMES  g_notifyEntryQueueLTF[];
datetime         g_notifyEntryQueueDue[];
datetime         g_notifyEntryQueueQueued[];
int              g_nNotifyEntryQueue=0;

// CCT_NOTIFY_ENTRY_LIFECYCLE_GATE_V1
// Notification-layer lifecycle filters. These do not alter execution truth.
bool NotifyOutcomeResolvedLocal(SIB_STATE st)
  {
   return (st==SS_RESOLVED_TP || st==SS_RESOLVED_SL || st==SS_RESOLVED_BE || st==SS_RESOLVED_BE_CO);
  }

bool NotifyEntryQueueEligible(const ExecRecord &exec)
  {
   if(!NotifyValidExec(exec))
      return false;

   if(NotifyOutcomeResolvedLocal(exec.outcome) || exec.exitTime>0 || exec.exitPrice>0.0)
      return false;

   if(exec.beApplied || exec.beGeneralApplied || exec.beCoApplied ||
      exec.beTime>0 || exec.beGeneralTime>0 || exec.beCoTime>0)
      return false;

   if(exec.coTouched || exec.coTouchTime>0)
      return false;

   if(exec.virtualTPTouched || exec.virtualTPTouchTime>0)
      return false;

   return (NotifyEntryTime(exec)>0);
  }

bool NotifyBEMoveEligible(const ExecRecord &exec,int beType)
  {
   if(!NotifyValidExec(exec))
      return false;
   if(NotifyOutcomeResolvedLocal(exec.outcome) || exec.exitTime>0 || exec.exitPrice>0.0)
      return false;
   return (NotifyBEMoveEventTime(exec,beType)>0);
  }

// CCT_NOTIFY_BE_SAME_CANDLE_EXIT_SUPPRESS_V1
// If the current LTF candle has already delivered TP/SL, the exit is the meaningful signal.
// Suppress BE/CO BE threshold hints so they cannot arrive instead of, or beside, the outcome.
bool NotifySameLtfCandleHitExit(const ExecRecord &exec,ENUM_TIMEFRAMES modelLTF)
  {
   if(exec.brokerTP<=0.0 || exec.brokerSL<=0.0)
      return false;

   MqlRates bar[];
   ArraySetAsSeries(bar,true);
   int copied=CopyRates(_Symbol,modelLTF,0,1,bar);
   if(copied<1)
      return false;

   double tol=MathMax(_Point,SymbolInfoDouble(_Symbol,SYMBOL_POINT));
   if(exec.bull)
      return (bar[0].high>=exec.brokerTP-tol || bar[0].low<=exec.brokerSL+tol);

   return (bar[0].low<=exec.brokerTP+tol || bar[0].high>=exec.brokerSL-tol);
  }

string NotifyEntryQueueLockName(const ExecRecord &exec)
  {
   // CCT_NOTIFY_ENTRY_LOCK_STABLE_V1
   // Lock by account+symbol+generation+trigger/entry time, not by ticket.
   // Ticket can shift from order ticket to position ticket; gen+event time must remain one entry signal forever.
   datetime entryTime=NotifyEntryTime(exec);
   return "CCT_ENTRY_Q_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+_Symbol+"_"+exec.genKey+"_"+IntegerToString((long)entryTime);
  }

void NotifyQueueEntryOnce(const ExecRecord &exec,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   if(NotifySuppressed())
      return;
   if(!NotifyEntryQueueEligible(exec))
      return;
   if(!NotifyEventFreshForRuntime(NotifyEntryTime(exec),"ENTRY_QUEUE",exec.genKey))
      return;

   string lockName=NotifyEntryQueueLockName(exec);
   if(GlobalVariableCheck(lockName))
      return;

   datetime now=CurrentServerTime();
   if(now<=0)
      now=TimeCurrent();

   int n=g_nNotifyEntryQueue;
   ArrayResize(g_notifyEntryQueue,n+1,4);
   ArrayResize(g_notifyEntryQueueHTF,n+1,4);
   ArrayResize(g_notifyEntryQueueLTF,n+1,4);
   ArrayResize(g_notifyEntryQueueDue,n+1,4);
   ArrayResize(g_notifyEntryQueueQueued,n+1,4);

   g_notifyEntryQueue[n]=exec;
   g_notifyEntryQueueHTF[n]=modelHTF;
   g_notifyEntryQueueLTF[n]=modelLTF;
   g_notifyEntryQueueQueued[n]=now;
   g_notifyEntryQueueDue[n]=now+(datetime)MathMax(1,NOTIFY_ENTRY_DEFER_SECONDS);
   g_nNotifyEntryQueue=n+1;

   GlobalVariableSet(lockName,(double)now);
   if(!CCTSuppressLiveCCTJournals())
      PrintFormat("[CCT_Notify] Entry notification queued; gen=%s ticket=%I64d synthetic=%s dueInSec=%d",exec.genKey,(long)exec.ticket,exec.isSynthetic ? "yes" : "no",NOTIFY_ENTRY_DEFER_SECONDS);
  }

void NotifyEntryQueueRemove(const int index)
  {
   if(index<0 || index>=g_nNotifyEntryQueue)
      return;

   for(int i=index;i<g_nNotifyEntryQueue-1;i++)
     {
      g_notifyEntryQueue[i]=g_notifyEntryQueue[i+1];
      g_notifyEntryQueueHTF[i]=g_notifyEntryQueueHTF[i+1];
      g_notifyEntryQueueLTF[i]=g_notifyEntryQueueLTF[i+1];
      g_notifyEntryQueueDue[i]=g_notifyEntryQueueDue[i+1];
      g_notifyEntryQueueQueued[i]=g_notifyEntryQueueQueued[i+1];
     }

   g_nNotifyEntryQueue--;
   ArrayResize(g_notifyEntryQueue,g_nNotifyEntryQueue);
   ArrayResize(g_notifyEntryQueueHTF,g_nNotifyEntryQueue);
   ArrayResize(g_notifyEntryQueueLTF,g_nNotifyEntryQueue);
   ArrayResize(g_notifyEntryQueueDue,g_nNotifyEntryQueue);
   ArrayResize(g_notifyEntryQueueQueued,g_nNotifyEntryQueue);
  }

void NotifyPendingOnTimer()
  {
   if(NotifySuppressed())
      return;
   if(g_nNotifyEntryQueue<=0)
      return;

   datetime now=CurrentServerTime();
   if(now<=0)
      now=TimeCurrent();

   for(int i=g_nNotifyEntryQueue-1;i>=0;i--)
     {
      if(g_notifyEntryQueueDue[i]>now)
         continue;

      ExecRecord exec=g_notifyEntryQueue[i];
      ENUM_TIMEFRAMES htf=g_notifyEntryQueueHTF[i];
      ENUM_TIMEFRAMES ltf=g_notifyEntryQueueLTF[i];
      datetime queuedAt=g_notifyEntryQueueQueued[i];
      datetime dueAt=g_notifyEntryQueueDue[i];

      // CCT_NOTIFY_PENDING_REVALIDATE_V1
      // Revalidate before dispatch. If a queued entry has already evolved into BE/CO/TP/SL state,
      // remove it silently; late lifecycle states must never masquerade as entry signals.
      if(!NotifyEntryQueueEligible(exec) ||
         !NotifyEventFreshForRuntime(NotifyEntryTime(exec),"ENTRY_QUEUE_SEND",exec.genKey))
        {
         NotifyEntryQueueRemove(i);
         continue;
        }

      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] Sending deferred entry notification; gen=%s ticket=%I64d queuedAt=%s dueAt=%s dispatchAt=%s waitSec=%d lateSec=%d",
                     exec.genKey,
                     (long)exec.ticket,
                     TimeToString(queuedAt,TIME_DATE|TIME_SECONDS),
                     TimeToString(dueAt,TIME_DATE|TIME_SECONDS),
                     TimeToString(now,TIME_DATE|TIME_SECONDS),
                     (int)MathMax(0,(long)(now-queuedAt)),
                     (int)MathMax(0,(long)(now-dueAt)));
      NotifyEntry(exec,htf,ltf);
      NotifyEntryQueueRemove(i);
     }
  }

string NotifyEventLockName(const ExecRecord &exec,const string eventKind)
  {
   // CCT_NOTIFY_EVENT_IDEMPOTENCY_V1
   // Final-dispatch idempotency. Chart movement/timeframe changes may replay state,
   // but the same entry/BE/exit event must not re-send screenshots/signals.
   string trigger=IntegerToString((long)exec.triggerBarTime);
   if(trigger=="0" && exec.ticket>0)
      trigger=IntegerToString((long)exec.ticket);

   string key="CCT_NS_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+
              _Symbol+"_"+eventKind+"_"+trigger+"_"+exec.genKey;

   // MT5 global variable names are finite; keep the lock compact.
   if(StringLen(key)>63)
      key=StringSubstr(key,0,63);

   return key;
  }

bool NotifyClaimEventOnce(const ExecRecord &exec,const string eventKind)
  {
   if(!NotifyValidExec(exec))
      return false;

   string lockName=NotifyEventLockName(exec,eventKind);
   if(GlobalVariableCheck(lockName))
     {
      if(CCTDebugEnabled())
         PrintFormat("[CCT_Notify] Duplicate notification suppressed; event=%s gen=%s trigger=%s ticket=%I64d synthetic=%s",
                     eventKind,
                     exec.genKey,
                     exec.triggerBarTime>0 ? TimeToString(exec.triggerBarTime,TIME_DATE|TIME_MINUTES) : "-",
                     (long)exec.ticket,
                     exec.isSynthetic ? "yes" : "no");
      return false;
     }

   datetime now=CurrentServerTime();
   if(now<=0)
      now=TimeCurrent();

   GlobalVariableSet(lockName,(double)now);
   return true;
  }

bool NotifyEventWasClaimed(const ExecRecord &exec,const string eventKind)
  {
   if(!NotifyValidExec(exec))
      return false;
   return GlobalVariableCheck(NotifyEventLockName(exec,eventKind));
  }

bool NotifyExitFreshOrLinkedEntry(const ExecRecord &exec)
  {
   // CCT_NOTIFY_RECOVERED_EXIT_AFTER_REOPEN_V1
   // A recovered old exit may still be the subscriber's missing resolution if
   // the matching entry signal had already been claimed before terminal downtime.
   if(NotifyEventFreshForRuntime(exec.exitTime,"EXIT",exec.genKey))
      return true;
   return NotifyEventWasClaimed(exec,"ENTRY");
  }

void NotifyEntry(const ExecRecord &exec,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   if(NotifySuppressed())
      return;
   if(!NotifyEntryQueueEligible(exec))
      return;
   if(!NotifyEventFreshForRuntime(NotifyEntryTime(exec),"ENTRY",exec.genKey))
      return;
   if(!NotifyHasAnyConfiguredTarget())
      return;
   if(!NotifyClaimEventOnce(exec,"ENTRY"))
      return;

   string imagePath=NotifyCaptureScreenshot(exec,modelLTF,exec.genKey,"ENTRY");
   string text=NotifyBuildEntryMessage(exec,modelHTF,modelLTF);
   bool sent=NotifyDispatchAll(text,imagePath,NotifyEntryColor(exec));
   if(CCTDebugEnabled())
      PrintFormat("[CCT_Notify] Entry dispatch complete; gen=%s sent=%s image=%s",exec.genKey,sent ? "yes" : "no",imagePath);
  }

string NotifyBEClaimKeyLocal(const ExecRecord &exec,int beType)
  {
   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   datetime eventTime=NotifyBEMoveEventTime(exec,beType);
   string key="CCT_BE_ONCE_"+IntegerToString(login)+"_"+_Symbol+"_"+exec.genKey+"_"+
              IntegerToString((long)eventTime)+"_"+IntegerToString(beType);
   return key;
  }

bool NotifyClaimBEOnceLocal(const ExecRecord &exec,int beType)
  {
   string key=NotifyBEClaimKeyLocal(exec,beType);
   if(GlobalVariableCheck(key))
      return false;
   GlobalVariableSet(key,(double)TimeCurrent());
   return true;
  }

void NotifyBEMove(const ExecRecord &exec,int beType,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   // CCT_NOTIFY_BE_TEXT_ONLY_HINTS_V3
   // BE threshold / CO BE threshold notifications are text-only. Entry and exit
   // remain the only notification types that attach chart screenshots.
   if(NotifySuppressed())
      return;
   if(!NotifyBEMoveEligible(exec,beType))
      return;
   if(NotifySameLtfCandleHitExit(exec,modelLTF))
     {
      if(!CCTSuppressLiveCCTJournals())
         PrintFormat("[CCT_Notify] BE hint suppressed: current LTF candle already touched TP/SL; gen=%s event=%s",
                     exec.genKey,
                     (beType==1 ? "BECO" : "BE"));
      return;
     }
   if(!NotifyEventFreshForRuntime(NotifyBEMoveEventTime(exec,beType),"BE_MOVE",exec.genKey))
      return;
   if(!NotifyHasAnyConfiguredTarget())
      return;

   if(!NotifyClaimBEOnceLocal(exec,beType))
      return;

   string imagePath="";

   string text=NotifyBuildBEMoveMessage(exec,beType,modelHTF,modelLTF);
   bool sent=NotifyDispatchAll(text,imagePath,16776960);
   if(CCTDebugEnabled())
      PrintFormat("[CCT_Notify] BE dispatch complete; event=%s gen=%s sent=%s image=%s screenshot=%s",
                  (beType==1 ? "BECO" : "BE"),
                  exec.genKey,
                  sent ? "yes" : "no",
                  imagePath,
                  "text-only");
  }

// CCT_NOTIFY_EXIT_ONE_SHOT_HELPERS_V2
// Self-contained exit/report one-shot lock. This prevents duplicate exit calls from multiplying report ledger rows.
string NotifyExitClaimKeyLocal(const ExecRecord &exec,SIB_STATE outcome)
  {
   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string key="CCT_EXIT_ONCE_"+IntegerToString(login)+"_"+_Symbol+"_"+exec.genKey+"_"+
              IntegerToString((long)exec.exitTime)+"_"+IntegerToString((int)outcome);
   return key;
  }

bool NotifyClaimExitOnceLocal(const ExecRecord &exec,SIB_STATE outcome)
  {
   string key=NotifyExitClaimKeyLocal(exec,outcome);
   if(GlobalVariableCheck(key))
      return false;
   GlobalVariableSet(key,(double)TimeCurrent());
   return true;
  }

void NotifyExit(const ExecRecord &exec,SIB_STATE outcome,ENUM_TIMEFRAMES modelHTF,ENUM_TIMEFRAMES modelLTF)
  {
   // CCT_NOTIFY_EXIT_CLAIM_BEFORE_LEDGER_V2
   // Exit lifecycle boundary:
   // 1) validate true resolved exit event,
   // 2) freshness-gate it,
   // 3) claim once,
   // 4) append report ledger once,
   // 5) optionally dispatch outbound TP/SL/BE-exit signal.
   if(NotifySuppressed())
      return;
   if(!NotifyValidExec(exec))
      return;
   if(!NotifyOutcomeResolvedLocal(outcome))
      return;
   if(exec.exitTime<=0)
      return;
   if(!NotifyExitFreshOrLinkedEntry(exec))
      return;

   if(!NotifyClaimExitOnceLocal(exec,outcome))
      return;

   NotifyLedgerAppendExit(exec,outcome,modelHTF,modelLTF);

   if(!NotifyHasAnyConfiguredTarget())
      return;

   string imagePath=NotifyCaptureScreenshot(exec,modelLTF,exec.genKey,"EXIT");
   string text=NotifyBuildExitMessage(exec,outcome,modelHTF,modelLTF);
   bool sent=NotifyDispatchAll(text,imagePath,NotifyExitColor(outcome));
   if(CCTDebugEnabled())
      PrintFormat("[CCT_Notify] Exit dispatch complete; outcome=%d gen=%s sent=%s image=%s",
                  (int)outcome,exec.genKey,sent ? "yes" : "no",imagePath);
  }

#endif
