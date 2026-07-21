#ifndef ORB_NOTIFY_MQH
#define ORB_NOTIFY_MQH

//+------------------------------------------------------------------+
//|                                                  ORB_Notify.mqh  |
//| Standalone Discord/Telegram webhook notifier for ORB Scalper.    |
//| CCT-inspired, but fully self-contained: no CCT framework deps.   |
//+------------------------------------------------------------------+

enum ENUM_ORBN_FAMILY
{
    ORBN_FAM_DEFAULT = 0,
    ORBN_FAM_INDEX,
    ORBN_FAM_METAL,
    ORBN_FAM_CRYPTO
};

enum ENUM_NEWS_GUARD_MODE
{
    NEWS_GUARD_DISABLED   = 0, // Disabled
    NEWS_GUARD_RED        = 1, // Red-folder only
    NEWS_GUARD_RED_YELLOW = 2, // Red-folder and Yellow-folder only
    NEWS_GUARD_ALL        = 3  // All (Red, Yellow, White)
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "             "
input group "==========  8b - News Engine  =========="
input ENUM_NEWS_GUARD_MODE News_Guard_Mode = NEWS_GUARD_RED; // News guard impact
input int    News_Block_Before_Min  = 30;            // Block window: N minutes BEFORE event
input int    News_Block_After_Min   = 15;            // Block window: N minutes AFTER event
input bool   News_Block_Entries     = true;          // Blackout: block new orders
input bool   News_Cancel_Pending    = false;         // Blackout: cancel existing pending orders
input bool   News_Freeze_Trail      = true;          // Blackout: pause trailing modifications
input bool   News_Flatten_Before    = false;         // Blackout: close positions before event
input int    News_Flatten_Min       = 5;             // Flatten: minutes before event to close
input bool   News_Signals_Enabled   = false;         // Send news event alerts to Discord/Telegram

input group "              "
input group "==========  8c - Notifications (Discord / Telegram)  =========="
input bool   ORBN_Discord_Enabled   = false;  // Enable Discord webhooks
input string ORBN_Discord_Index     = "";     // Discord webhook: Indices (NQ/SPX)
input string ORBN_Discord_Metal     = "";     // Discord webhook: Metals (Gold)
input string ORBN_Discord_Crypto    = "";     // Discord webhook: Crypto (BTC)
input string ORBN_Discord_Default   = "";     // Discord webhook: fallback
input bool   ORBN_Telegram_Enabled  = false;  // Enable Telegram
input string ORBN_Telegram_Token    = "";     // Telegram bot token
input string ORBN_Telegram_Index    = "";     // Telegram chat(|thread): Indices
input string ORBN_Telegram_Metal    = "";     // Telegram chat(|thread): Metals
input string ORBN_Telegram_Crypto   = "";     // Telegram chat(|thread): Crypto
input string ORBN_Telegram_Default  = "";     // Telegram chat(|thread): fallback
input bool   ORBN_Performance_Reports_Enabled      = false;  // Send periodic (daily/weekly/monthly) performance summary reports
input int    ORBN_Report_Hour          = 2;      // Report send hour (New York time)
input bool   ORBN_Monthly_On_Last_Day  = true;   // true=last day of month | false=1st of next month
input bool   ORBN_Attach_Chart_Screenshots          = false;  // Attach a chart screenshot to entry notifications

//+------------------------------------------------------------------+
//| Symbol -> family                                                 |
//+------------------------------------------------------------------+
string ORBNClean(const string sym)
{
    string u=sym; StringToUpper(u); string o="";
    for(int i=0;i<StringLen(u);i++){ ushort c=StringGetCharacter(u,i); if((c>='A'&&c<='Z')||(c>='0'&&c<='9')) o+=ShortToString(c); }
    return o;
}
bool ORBNStarts(const string clean,const string &v[])
{ for(int i=0;i<ArraySize(v);i++) if(StringFind(clean,v[i])==0) return true; return false; }
ENUM_ORBN_FAMILY ORBNFamily(const string sym)
{
    string c=ORBNClean(sym);
    string idx[]={"NDX","NAS100","NASDAQ","NASDAQ100","NQ","US100","USTEC","USTECH","NDQ","NQ100","MNQ",
                  "SPX","SP500","US500","ES","SPY","ES1","MES","SPXUSD",
                  "US30","DJI","DJ30","DOW","DOWJONES","YM","DJA","DJIA","US30USD","USDJIA",
                  "DAX","GER30","GER40","DE30","DE40","FDAX","GRX30","GRX40",
                  "UK100","FTSE","FTSE100","UKX","Z",
                  "JP225","NI225","JPN225","N225","NKY",
                  "FRA40","CAC40","CAC","FCAC",
                  "AUS200","ASX200","AP200",
                  "US2000","RUT","R2K","VIX","VIXY"};
    if(ORBNStarts(c,idx)) return ORBN_FAM_INDEX;
    
    string met[]={"XAU","GOLD","XAG","SILVER","XPT","PLATINUM","XPD","PALLADIUM","OIL","USOIL","XTI","WTI","CRUDE","BRENT","UKOIL","XBR"};
    if(ORBNStarts(c,met)) return ORBN_FAM_METAL;
    
    string cry[]={"BTC","XBT","ETH","XRP","SOL","LTC","ADA","DOGE"};
    if(ORBNStarts(c,cry)) return ORBN_FAM_CRYPTO;
    
    return ORBN_FAM_DEFAULT;
}
string ORBNAssetName(const string sym)
{
    string c=ORBNClean(sym);
    switch(ORBNFamily(sym))
    {
        case ORBN_FAM_INDEX: 
        { 
            string spx[]={"SPX","SP500","US500","ES","SPY","ES1","MES","SPXUSD"};
            if(ORBNStarts(c,spx)) return "SPX";
            string dow[]={"US30","DJI","DJ30","DOW","YM","DJA","USDJIA"};
            if(ORBNStarts(c,dow)) return "DOW";
            string dax[]={"DAX","GER","DE3","DE4","FDAX","GRX"};
            if(ORBNStarts(c,dax)) return "DAX";
            string ftse[]={"UK100","FTSE","UKX","Z"};
            if(ORBNStarts(c,ftse)) return "FTSE";
            string nikkei[]={"JP225","NI225","JPN225","N225","NKY"};
            if(ORBNStarts(c,nikkei)) return "NIKKEI";
            string asx[]={"AUS200","ASX200","AP200"};
            if(ORBNStarts(c,asx)) return "ASX";
            string cac[]={"FRA40","CAC","FCAC"};
            if(ORBNStarts(c,cac)) return "CAC";
            string rut[]={"US2000","RUT","R2K"};
            if(ORBNStarts(c,rut)) return "RUT";
            string vix[]={"VIX"};
            if(ORBNStarts(c,vix)) return "VIX";
            return "NASDAQ"; 
        }
        case ORBN_FAM_METAL: 
        {
            string ag[]={"XAG","SILVER"};
            if(ORBNStarts(c,ag)) return "SILVER";
            string pt[]={"XPT","PLATINUM"};
            if(ORBNStarts(c,pt)) return "PLATINUM";
            string pd[]={"XPD","PALLADIUM"};
            if(ORBNStarts(c,pd)) return "PALLADIUM";
            string oil[]={"OIL","USOIL","WTI","XTI","BRENT","UKOIL","XBR","CRUDE"};
            if(ORBNStarts(c,oil)) return "OIL";
            return "GOLD";
        }
        case ORBN_FAM_CRYPTO: 
        {
            if(StringFind(c,"ETH")==0) return "ETH";
            if(StringFind(c,"XRP")==0) return "XRP";
            if(StringFind(c,"SOL")==0) return "SOL";
            if(StringFind(c,"LTC")==0) return "LTC";
            if(StringFind(c,"ADA")==0) return "ADA";
            if(StringFind(c,"DOGE")==0) return "DOGE";
            return "BTC";
        }
        default: return sym;
    }
}
string ORBNFamilyName(const string sym)
{
    switch(ORBNFamily(sym))
    { case ORBN_FAM_INDEX: return "Indices"; case ORBN_FAM_METAL: return "Metals"; case ORBN_FAM_CRYPTO: return "Crypto"; default: return "General"; }
}

//+------------------------------------------------------------------+
//| Target resolvers                                                 |
//+------------------------------------------------------------------+
string ORBNDiscordTarget(const string sym)
{
    string t="";
    switch(ORBNFamily(sym)){ case ORBN_FAM_INDEX: t=ORBN_Discord_Index; break; case ORBN_FAM_METAL: t=ORBN_Discord_Metal; break; case ORBN_FAM_CRYPTO: t=ORBN_Discord_Crypto; break; }
    if(t=="") t=ORBN_Discord_Default; return t;
}
string ORBNTelegramTarget(const string sym)
{
    string t="";
    switch(ORBNFamily(sym)){ case ORBN_FAM_INDEX: t=ORBN_Telegram_Index; break; case ORBN_FAM_METAL: t=ORBN_Telegram_Metal; break; case ORBN_FAM_CRYPTO: t=ORBN_Telegram_Crypto; break; }
    if(t=="") t=ORBN_Telegram_Default; return t;
}

//+------------------------------------------------------------------+
//| Byte / JSON helpers                                              |
//+------------------------------------------------------------------+
string ORBNJson(const string v)
{
    string o="";
    for(int i=0;i<StringLen(v);i++){ ushort c=StringGetCharacter(v,i); if(c=='\\') o+="\\\\"; else if(c=='"') o+="\\\""; else if(c=='\n') o+="\\n"; else if(c=='\r') o+="\\r"; else o+=ShortToString(c); }
    return o;
}
void ORBNAppend(uchar &body[],const string text)
{
    uchar b[]; int n=StringToCharArray(text,b,0,WHOLE_ARRAY,CP_UTF8);
    if(n>0&&b[n-1]==0) n--;
    int old=ArraySize(body); ArrayResize(body,old+n);
    for(int i=0;i<n;i++) body[old+i]=b[i];
}
void ORBNAppendBytes(uchar &body[],const uchar &src[])
{
    int old=ArraySize(body),n=ArraySize(src); ArrayResize(body,old+n);
    for(int i=0;i<n;i++) body[old+i]=src[i];
}

//+------------------------------------------------------------------+
//| Dispatchers                                                      |
//+------------------------------------------------------------------+
bool ORBNSendDiscord(const string text,int colorInt,const uchar &imgBytes[],bool hasImg)
{
    string url=ORBNDiscordTarget(_Symbol);
    if(url=="") return false;
    if(StringFind(url,"?")<0) url+="?wait=true"; else if(StringFind(url,"wait=")<0) url+="&wait=true";
    uchar body[]; string headers;
    if(hasImg)
    {
        string b="ORBNotifyBnd9z2";
        string payload=StringFormat("{\"embeds\":[{\"description\":\"%s\",\"color\":%d,\"image\":{\"url\":\"attachment://shot.png\"}}]}",ORBNJson(text),colorInt);
        ORBNAppend(body,"--"+b+"\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n");
        ORBNAppend(body,payload);
        ORBNAppend(body,"\r\n--"+b+"\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\n");
        ORBNAppendBytes(body,imgBytes);
        ORBNAppend(body,"\r\n--"+b+"--\r\n");
        headers="Content-Type: multipart/form-data; boundary="+b+"\r\n";
    }
    else
    {
        string p=StringFormat("{\"embeds\":[{\"description\":\"%s\",\"color\":%d}]}",ORBNJson(text),colorInt);
        ORBNAppend(body,p); headers="Content-Type: application/json\r\n";
    }
    uchar resp[]; string rh=""; ResetLastError();
    int r=WebRequest("POST",url,headers,5000,body,resp,rh);
    if(r==200||r==204) return true;
    static int s_discFail = 0;
    if(!Inp_StealthMode) { if(GetLastError() == 4014) { if(s_discFail++ < 3) Print("[ORB_Notify] Discord failed err=4014. Please add URL to Tools->Options->Expert Advisors. Muting further 4014 errors."); } else Print(StringFormat("[ORB_Notify] Discord failed code=%d err=%d",r,GetLastError())); }
    return false;
}
bool ORBNSendTelegram(const string text,const uchar &imgBytes[],bool hasImg)
{
    string target=ORBNTelegramTarget(_Symbol);
    if(target==""||ORBN_Telegram_Token=="") return false;
    string chatId=target,thread=""; int sep=StringFind(target,"|");
    if(sep>=0){ chatId=StringSubstr(target,0,sep); thread=StringSubstr(target,sep+1); }
    uchar body[]; string headers,url;
    if(hasImg)
    {
        url="https://api.telegram.org/bot"+ORBN_Telegram_Token+"/sendPhoto";
        string b="ORBNotifyBnd9z2";
        ORBNAppend(body,"--"+b+"\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n"+chatId+"\r\n");
        if(thread!="") ORBNAppend(body,"--"+b+"\r\nContent-Disposition: form-data; name=\"message_thread_id\"\r\n\r\n"+thread+"\r\n");
        ORBNAppend(body,"--"+b+"\r\nContent-Disposition: form-data; name=\"parse_mode\"\r\n\r\nMarkdown\r\n");
        ORBNAppend(body,"--"+b+"\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n"+text+"\r\n");
        ORBNAppend(body,"--"+b+"\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\n");
        ORBNAppendBytes(body,imgBytes);
        ORBNAppend(body,"\r\n--"+b+"--\r\n");
        headers="Content-Type: multipart/form-data; boundary="+b+"\r\n";
    }
    else
    {
        url="https://api.telegram.org/bot"+ORBN_Telegram_Token+"/sendMessage";
        string tgText = text;
        StringReplace(tgText, "**", "*");
        string p=StringFormat("{\"chat_id\":\"%s\",\"text\":\"%s\",\"parse_mode\":\"Markdown\"",ORBNJson(chatId),ORBNJson(tgText));
        if(thread!="") p+=StringFormat(",\"message_thread_id\":%s",thread);
        p+="}"; ORBNAppend(body,p); headers="Content-Type: application/json\r\n";
    }
    uchar resp[]; string rh=""; ResetLastError();
    int r=WebRequest("POST",url,headers,5000,body,resp,rh);
    if(r==200) return true;
    static int s_tgFail = 0;
    if(!Inp_StealthMode) { if(GetLastError() == 4014) { if(s_tgFail++ < 3) Print("[ORB_Notify] Telegram failed err=4014. Please add URL to Tools->Options->Expert Advisors. Muting further 4014 errors."); } else Print(StringFormat("[ORB_Notify] Telegram failed code=%d err=%d",r,GetLastError())); }
    return false;
}
bool ORBNSuppressed()
{ if((bool)MQLInfoInteger(MQL_TESTER)) return true; return (!ORBN_Discord_Enabled&&!ORBN_Telegram_Enabled); }

//+------------------------------------------------------------------+
//| Screenshot capture (ported from CCT_Notify, self-contained)      |
//+------------------------------------------------------------------+
struct ORBNChartState { bool valid,scaleFix,autoScroll,shift; double fixedMin,fixedMax,shiftSize; long scale; };
void ORBNSaveChartState(ORBNChartState &s)
{
    s.valid=true; s.scaleFix=(bool)ChartGetInteger(0,CHART_SCALEFIX);
    s.fixedMin=ChartGetDouble(0,CHART_FIXED_MIN); s.fixedMax=ChartGetDouble(0,CHART_FIXED_MAX);
    s.autoScroll=(bool)ChartGetInteger(0,CHART_AUTOSCROLL); s.shift=(bool)ChartGetInteger(0,CHART_SHIFT);
    s.shiftSize=ChartGetDouble(0,CHART_SHIFT_SIZE); s.scale=ChartGetInteger(0,CHART_SCALE);
}
void ORBNRestoreChartState(const ORBNChartState &s)
{
    if(!s.valid) return;
    ChartSetInteger(0,CHART_SCALEFIX,s.scaleFix); ChartSetDouble(0,CHART_FIXED_MIN,s.fixedMin);
    ChartSetDouble(0,CHART_FIXED_MAX,s.fixedMax); ChartSetInteger(0,CHART_AUTOSCROLL,s.autoScroll);
    ChartSetInteger(0,CHART_SHIFT,s.shift); ChartSetDouble(0,CHART_SHIFT_SIZE,s.shiftSize);
    ChartSetInteger(0,CHART_SCALE,s.scale); ChartRedraw(0);
}
string ORBNCaptureScreenshot(double rangeHigh,double rangeLow,double entryPx,double slPx,double tpPx)
{
    if(!ORBN_Attach_Chart_Screenshots||(bool)MQLInfoInteger(MQL_TESTER)) return "";
    ORBNChartState saved; ORBNSaveChartState(saved);
    double minP=DBL_MAX,maxP=-DBL_MAX;
    double pts[]={rangeHigh,rangeLow,entryPx,slPx,tpPx};
    for(int i=0;i<5;i++){ if(pts[i]<=0.0) continue; if(pts[i]<minP) minP=pts[i]; if(pts[i]>maxP) maxP=pts[i]; }
    MqlRates bars[]; ArraySetAsSeries(bars,true);
    int bc=CopyRates(_Symbol,PERIOD_CURRENT,0,80,bars);
    for(int i=0;i<bc;i++){ if(bars[i].high>maxP) maxP=bars[i].high; if(bars[i].low<minP) minP=bars[i].low; }
    if(minP<DBL_MAX&&maxP>-DBL_MAX&&maxP>minP)
    {
        double rng=maxP-minP,pad=MathMax(rng*0.40,120.0*_Point);
        ChartSetInteger(0,CHART_SCALEFIX,true);
        ChartSetDouble(0,CHART_FIXED_MIN,NormalizeDouble(minP-pad,_Digits));
        ChartSetDouble(0,CHART_FIXED_MAX,NormalizeDouble(maxP+pad,_Digits));
    }
    ChartSetInteger(0,CHART_AUTOSCROLL,true); ChartSetInteger(0,CHART_SHIFT,true);
    ChartSetDouble(0,CHART_SHIFT_SIZE,40.0); ChartSetInteger(0,CHART_SCALE,3);
    ChartNavigate(0,CHART_END,0); ChartRedraw(0); Sleep(300);
    ChartNavigate(0,CHART_END,0); ChartRedraw(0); Sleep(1200);
    string fname=StringFormat("ORB_%s_%I64d.png",ORBNClean(_Symbol),(long)TimeCurrent());
    string warm="ORB_warm_"+fname;
    ChartScreenShot(0,warm,1920,1080,ALIGN_RIGHT); FileDelete(warm); Sleep(300);
    ChartNavigate(0,CHART_END,0); ChartRedraw(0); Sleep(250);
    bool ok=ChartScreenShot(0,fname,1920,1080,ALIGN_RIGHT);
    ORBNRestoreChartState(saved);
    if(!ok){ if(!Inp_StealthMode) Print("[ORB_Notify] Screenshot failed err="+IntegerToString(GetLastError())); return ""; }
    return fname;
}

//+------------------------------------------------------------------+
//| Webhook queue & dispatcher                                       |
//+------------------------------------------------------------------+
struct ORBNQItem { string text; int clr; double rh; double rl; double ep; double sl; double tp; bool shot; int retries; };
ORBNQItem g_nfyQ[];
int g_nfyQLen=0;

bool ORBNWebhookDirect(const string text,int colorInt,double rangeHigh,double rangeLow,
                       double entryPx,double slPx,double tpPx,bool shot)
{
    string f="";
    if(shot) f=ORBNCaptureScreenshot(rangeHigh,rangeLow,entryPx,slPx,tpPx);
    bool hasImg=(f!=""); uchar img[];
    if(hasImg) { int h=FileOpen(f,FILE_READ|FILE_BIN); if(h!=INVALID_HANDLE){ FileReadArray(h,img); FileClose(h); FileDelete(f); } else hasImg=false; }
    
    // Convert Discord Markdown to Telegram Markdown
    string tgText=text;
    StringReplace(tgText, "**", "*");
    
    bool dOk = true;
    bool tOk = true;
    if(ORBN_Discord_Enabled) dOk = ORBNSendDiscord(text,colorInt,img,hasImg);
    if(ORBN_Telegram_Enabled) tOk = ORBNSendTelegram(tgText,img,hasImg);
    
    if(ORBN_Discord_Enabled && !dOk) return false;
    if(ORBN_Telegram_Enabled && !tOk) return false;
    return true;
}

void ORBNotifyWebhook(const string text,int colorInt,double rangeHigh=0.0,double rangeLow=0.0,
                      double entryPx=0.0,double slPx=0.0,double tpPx=0.0,bool shot=false)
{
    if(ArraySize(g_nfyQ)<=g_nfyQLen) ArrayResize(g_nfyQ,g_nfyQLen+5);
    g_nfyQ[g_nfyQLen].text=text; g_nfyQ[g_nfyQLen].clr=colorInt;
    g_nfyQ[g_nfyQLen].rh=rangeHigh; g_nfyQ[g_nfyQLen].rl=rangeLow;
    g_nfyQ[g_nfyQLen].ep=entryPx; g_nfyQ[g_nfyQLen].sl=slPx;
    g_nfyQ[g_nfyQLen].tp=tpPx; g_nfyQ[g_nfyQLen].shot=shot; g_nfyQ[g_nfyQLen].retries=0;
    g_nfyQLen++;
}

void ORBNDrainQueue()
{
    if(g_nfyQLen<=0) return;
    ORBNQItem item=g_nfyQ[0];
    for(int i=1;i<g_nfyQLen;i++) g_nfyQ[i-1]=g_nfyQ[i];
    g_nfyQLen--;
    if(g_nfyQLen==0) ArrayResize(g_nfyQ,0);
    
    bool ok = ORBNWebhookDirect(item.text,item.clr,item.rh,item.rl,item.ep,item.sl,item.tp,item.shot);
    if(!ok)
    {
        if(item.retries < 3)
        {
            item.retries++;
            ORBLog(StringFormat("[ORB] Webhook dispatch failed. Requeuing notification (Retry %d/3).", item.retries));
            if(ArraySize(g_nfyQ)<=g_nfyQLen) ArrayResize(g_nfyQ,g_nfyQLen+5);
            for(int i=g_nfyQLen;i>0;i--) g_nfyQ[i]=g_nfyQ[i-1];
            g_nfyQ[0] = item;
            g_nfyQLen++;
        }
        else
        {
            ORBLog("[ORB] Webhook dispatch failed permanently after 3 retries. Discarding notification. Check Terminal -> Tools -> Options -> Expert Advisors -> Allowed URLs.");
        }
    }
}

//+------------------------------------------------------------------+
//| Glyph helpers                                                    |
//+------------------------------------------------------------------+
string ORBNSq()  { return ShortToString(0x25A0); }
string ORBNSqS() { return ShortToString(0x25AB); }
string ORBNBull(){ return ShortToString(0x25B2); }
string ORBNBear(){ return ShortToString(0x25BC); }

//+------------------------------------------------------------------+
//| Dedupe helpers                                                   |
//+------------------------------------------------------------------+
bool ORBNClaimOnce(const string kind,ulong ticket,const string sessionKey)
{
    string k=StringFormat("ORBN_%s_%I64d_%s",kind,(long)ticket,sessionKey);
    if(GlobalVariableCheck(k))
    {
        ORBLog(StringFormat("[ORB] ORBNClaimOnce blocked duplicate key: %s", k));
        return false;
    }
    GlobalVariableSet(k,(double)TimeCurrent()); return true;
}
void ORBNPruneDedupe()
{
    datetime cutoff=TimeCurrent()-3*86400;
    int total=GlobalVariablesTotal();
    for(int i=total-1;i>=0;i--)
    { string nm=GlobalVariableName(i); if(StringFind(nm,"ORBN_")==0&&(datetime)GlobalVariableGet(nm)<cutoff) GlobalVariableDel(nm); }
}

string SessionLabelFromKey(const string key)
{
    if(StringFind(key,"_DAILY_") >=0) return "Daily";
    if(StringFind(key,"_WEEKLY_")>=0) return "Weekly";
    int len=StringLen(key);
    if(len>=4){ string t=StringSubstr(key,len-4,4);
        string hh=StringSubstr(t,0,2),mm=StringSubstr(t,2,2);
        long hv=StringToInteger(hh),mv=StringToInteger(mm);
        if(hv>=0&&hv<=23&&mv>=0&&mv<=59) return hh+":"+mm; }
    return "Setup";
}

//+------------------------------------------------------------------+
//| Signal 1 - Armed (paired pending, once per session)              |
//+------------------------------------------------------------------+
void ORBNotifyArmed(const string sessionKey, const string sessionLabel,
                    double rangeHigh, double rangeLow,
                    string buyLbl, string sellLbl,
                    double bE, double bS, double bT,
                    double sE, double sS, double sT,
                    double thrRaw, double gapRaw, int trailMode)
{
    if(ORBNSuppressed()) return;
    string dk=StringFormat("ORBN_ARMED_%s_%s",_Symbol,sessionKey);
    if(GlobalVariableCheck(dk)) return;
    GlobalVariableSet(dk,(double)TimeCurrent());
    string asset=ORBNAssetName(_Symbol), t="";
    
    t+=StringFormat("**%s - %s SETUP**\n\n", asset, sessionLabel);
    
    if(bE>0.0)
    {
        t+=StringFormat("**%s**\n**Entry:**   %s\n**SL:**      %s\n**TP:**      %s\n",
                        buyLbl, DoubleToString(bE,_Digits),DoubleToString(bS,_Digits),DoubleToString(bT,_Digits));
    }
    if(bE>0.0&&sE>0.0) t+="\n";
    if(sE>0.0)
    {
        t+=StringFormat("**%s**\n**Entry:**   %s\n**SL:**      %s\n**TP:**      %s\n",
                        sellLbl, DoubleToString(sE,_Digits),DoubleToString(sS,_Digits),DoubleToString(sT,_Digits));
    }
    
    t+="\n_Automated signal. Manage risk._";
    ORBNotifyWebhook(t,8421504,rangeHigh,rangeLow,0,0,0,true);
}

//+------------------------------------------------------------------+
//| Signal 2 - Triggered: suppressed ("no entry signal" per spec)    |
//+------------------------------------------------------------------+
void ORBNotifyTriggered(ulong ticket,const string sessionKey,
                        bool bull,double fillPx,double slPx,double tpPx)
{ /* Suppressed: Armed signal is the only pre-trade alert. */ }

//+------------------------------------------------------------------+
//| Signal 3 - Resolution                                            |
//+------------------------------------------------------------------+
void ORBNotifyResolution(ulong ticket,const string sessionKey,
                         bool bull,double entryPx,double exitPx,double pnl,
                         int trailCount,bool stepMode,double trailGapRaw,
                         double trailThreshRaw,double lastSL,double accountBalance)
{
    if(ORBNSuppressed()) return;
    if(!ORBNClaimOnce("RES",ticket,sessionKey)) return;
    string asset=ORBNAssetName(_Symbol);
    string dir=bull?"BUY":"SELL";
    string lbl=SessionLabelFromKey(sessionKey);
    string sign=(pnl>=0.0)?"+":"-";
    double pct=(accountBalance>0.0)?(pnl/accountBalance)*100.0:0.0;
    
    string t=StringFormat("**%s - %s SETUP**\n\n",asset,lbl);
    t+=StringFormat("**%s CLOSED** P/L: %s$%.2f (%s%.2f%%)",dir,sign,MathAbs(pnl),sign,MathAbs(pct));
    
    ORBNotifyWebhook(t,(pnl>=0.0)?5763719:15548997,0,0,entryPx,lastSL,0,true);
}

//+------------------------------------------------------------------+
//| Signal 4 - Trail (first stop-move only, deduped per ticket)      |
//+------------------------------------------------------------------+
void ORBNotifyTrail(ulong ticket,const string sessionKey,
                    bool bull,double newSL,
                    const string sessionLabel,int trailMode,double trailGapRaw)
{
    if(ORBNSuppressed()) return;
    if(!ORBNClaimOnce("TRAIL",ticket,sessionKey)) return;
    string asset=ORBNAssetName(_Symbol); string dir=bull?"BUY":"SELL";
    double np=NormPoint(); double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    if(tick<=0.0) tick=_Point;
    
    string t=StringFormat("**%s - %s SETUP**\n\n",asset,sessionLabel);
    t+=StringFormat("**TRAIL %s**\n**Stop moved to:** %s\n\n",dir,DoubleToString(newSL,_Digits));
    
    if(trailMode==1)
    {
        double gp=(np>0.0)?trailGapRaw/np:0.0;
        double nx=NormalizeDouble(bull?newSL+trailGapRaw:newSL-trailGapRaw,_Digits);
        t+=StringFormat("Next trail: %s (+%.0f points)\n",DoubleToString(nx,_Digits),gp);
        t+=StringFormat("Move stop every %.0f Points.",gp);
    }
    else
    {
        double nx=NormalizeDouble(bull?newSL+tick:newSL-tick,_Digits);
        t+=StringFormat("Next trail: %s (+1 tick)\n",DoubleToString(nx,_Digits));
        t+="Move stop every Tick.";
    }
    
    t+="\n\n";
    ORBNotifyWebhook(t,16776960);
}
//+------------------------------------------------------------------+
//| Legacy stubs â€” kept so existing call sites compile               |
//+------------------------------------------------------------------+
void ORBNotifyEntry(bool bull,double price,double sl,double tp) { /* suppressed */ }
void ORBNotifyExit(bool bull,double pnl)                       { /* suppressed */ }

//+------------------------------------------------------------------+
//| Cutoff-cancel acknowledgment                                     |
//+------------------------------------------------------------------+
void ORBNotifyCutoffCancel(const string sessionKey,bool hadBuy,bool hadSell)
{
    if(ORBNSuppressed()) return;
    string dk=StringFormat("ORBN_CUT_%s_%s",_Symbol,sessionKey);
    if(GlobalVariableCheck(dk)) return;
    GlobalVariableSet(dk,(double)TimeCurrent());
    string sides=(hadBuy&&hadSell)?"BUY + SELL":(hadBuy?"BUY":(hadSell?"SELL":"")); if(sides=="") return;
    string t=StringFormat("%s %s  cutoff reached\n%s\n\nPending %s order%s cancelled.",
                          ORBNSqS(),ORBNAssetName(_Symbol),TimeToString(TimeCurrent(),TIME_DATE),
                          sides,(hadBuy&&hadSell)?"s":"");
    ORBNotifyWebhook(t,6710886);
}

//+------------------------------------------------------------------+
//| Cancelled-order signal (brief, per-ticket)                       |
//| Called when a pending order is deleted outside the cutoff path     |
//| (news blackout, session change, deinit).                         |
//+------------------------------------------------------------------+
void ORBNotifyOrderCancelled(ulong ticket,const string sessionKey,bool bull,double price,const string reason)
{
    if(ORBNSuppressed()) return;
    if(!ORBNClaimOnce("CAN",ticket,sessionKey)) return;
    string t=StringFormat("%s %s %s cancelled\n%s\n\n@ %s\n%s",
                          ORBNSqS(),bull?"BUY":"SELL",ORBNAssetName(_Symbol),
                          TimeToString(TimeCurrent(),TIME_DATE),
                          DoubleToString(price,_Digits),reason);
    ORBNotifyWebhook(t,6710886);
}

//+------------------------------------------------------------------+
//| News Engine                                                      |
//+------------------------------------------------------------------+
struct ORBNewsEvent { datetime time; string description,currencies; int importance; bool signalSent; };
ORBNewsEvent g_newsCache[];
datetime     g_newsCacheTime=0;
bool         g_newsCacheValid=false;
datetime     g_newsCacheDay=0;

bool ORBNIsIsoCurrency(const string ccy)
{
    string known[]; ArrayResize(known,8);
    known[0]="USD"; known[1]="EUR"; known[2]="GBP"; known[3]="JPY";
    known[4]="AUD"; known[5]="CAD"; known[6]="CHF"; known[7]="NZD";
    string c=ccy; StringToUpper(c);
    for(int i=0;i<ArraySize(known);i++) if(c==known[i]) return true;
    return false;
}
void ORBNAddCurrency(string &out[], string ccy)
{
    StringTrimLeft(ccy); StringTrimRight(ccy); StringToUpper(ccy);
    if(!ORBNIsIsoCurrency(ccy)) return;
    for(int i=0;i<ArraySize(out);i++) if(out[i]==ccy) return;
    int n=ArraySize(out); ArrayResize(out,n+1); out[n]=ccy;
}
void ORBNAutoCurrencies(string &out[])
{
    ArrayResize(out,0);
    ORBNAddCurrency(out,SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE));
    ORBNAddCurrency(out,SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT));
    ORBNAddCurrency(out,SymbolInfoString(_Symbol,SYMBOL_CURRENCY_MARGIN));

    string s=ORBNClean(_Symbol);
    for(int i=0;i<StringLen(s)-2;i++)
        ORBNAddCurrency(out,StringSubstr(s,i,3));

    if(ArraySize(out)==0)
    {
        string usdRoots[]; ArrayResize(usdRoots,18);
        usdRoots[0]="XAU"; usdRoots[1]="XAG"; usdRoots[2]="GOLD"; usdRoots[3]="SILVER";
        usdRoots[4]="US100"; usdRoots[5]="USTEC"; usdRoots[6]="NAS"; usdRoots[7]="NDX";
        usdRoots[8]="US500"; usdRoots[9]="SPX"; usdRoots[10]="US30"; usdRoots[11]="DJ";
        usdRoots[12]="BTC"; usdRoots[13]="ETH"; usdRoots[14]="XRP"; usdRoots[15]="SOL";
        usdRoots[16]="LTC"; usdRoots[17]="CRYPTO";
        for(int i=0;i<ArraySize(usdRoots);i++)
            if(StringFind(s,usdRoots[i])>=0) { ORBNAddCurrency(out,"USD"); break; }
    }
    if(ArraySize(out)==0) ORBNAddCurrency(out,"USD");
}
bool ORBNCurrencyMatch(const string eventCcy,string &watchList[])
{
    if(ArraySize(watchList)==0) return true;
    string ev=eventCcy; StringToUpper(ev);
    for(int i=0;i<ArraySize(watchList);i++) if(ev==watchList[i]) return true;
    return false;
}

bool ORBNNewsEnabled()
{
    return (News_Guard_Mode != NEWS_GUARD_DISABLED);
}

int ORBNFFAdjustedImportance(const string eventName, int importance)
{
    string n = eventName;
    StringToUpper(n);
    if(StringFind(n, "NEW HOME SALES") >= 0) return CALENDAR_IMPORTANCE_MODERATE;
    if(StringFind(n, "EXISTING HOME SALES") >= 0) return CALENDAR_IMPORTANCE_MODERATE;
    if(StringFind(n, "PENDING HOME SALES") >= 0) return CALENDAR_IMPORTANCE_MODERATE;
    if(StringFind(n, "CRUDE OIL") >= 0) return CALENDAR_IMPORTANCE_MODERATE;
    if(StringFind(n, "EIA") >= 0 && StringFind(n, "STOCK") >= 0) return CALENDAR_IMPORTANCE_MODERATE;
    if(StringFind(n, "OIL STOCK") >= 0) return CALENDAR_IMPORTANCE_MODERATE;
    return importance;
}

bool ORBNNewsImpactAllowed(int importance)
{
    if(News_Guard_Mode == NEWS_GUARD_DISABLED) return false;
    if(News_Guard_Mode == NEWS_GUARD_ALL) return true;
    if(importance == CALENDAR_IMPORTANCE_HIGH) return true;
    if(News_Guard_Mode == NEWS_GUARD_RED_YELLOW && importance == CALENDAR_IMPORTANCE_MODERATE) return true;
    return false;
}

string ORBNNewsModeLabel()
{
    switch(News_Guard_Mode)
    {
        case NEWS_GUARD_DISABLED:   return "disabled";
        case NEWS_GUARD_RED:        return "red-folder";
        case NEWS_GUARD_RED_YELLOW: return "red/yellow-folder";
        case NEWS_GUARD_ALL:        return "all-impact";
    }
    return "red-folder";
}

string ORBNImpactLabel(int importance)
{
    if(importance == CALENDAR_IMPORTANCE_HIGH) return "red";
    if(importance == CALENDAR_IMPORTANCE_MODERATE) return "yellow";
    return "white";
}

void ORBNLoadNewsCache(datetime now)
{
    datetime day=now-(now%86400);
    if(g_newsCacheValid&&g_newsCacheDay==day) return;
    g_newsCacheValid=true; g_newsCacheTime=now; g_newsCacheDay=day; ArrayResize(g_newsCache,0);
    if(!ORBNNewsEnabled()) return;
    int bef=News_Block_Before_Min*60,aft=News_Block_After_Min*60;
    datetime from=day-aft-3600,to=day+86400+bef+3600;
    string watchList[]; ORBNAutoCurrencies(watchList);
    MqlCalendarValue vals[];
    if(CalendarValueHistory(vals,from,to,NULL,NULL)>0)
        for(int i=0;i<ArraySize(vals);i++)
        {
            MqlCalendarEvent ev; if(!CalendarEventById(vals[i].event_id,ev)) continue;
            int impact = ORBNFFAdjustedImportance(ev.name, (int)ev.importance);
            if(!ORBNNewsImpactAllowed(impact)) continue;
            MqlCalendarCountry country; if(!CalendarCountryById(ev.country_id,country)) continue;
            if(!ORBNCurrencyMatch(country.currency,watchList)) continue;
            int idx=ArraySize(g_newsCache); ArrayResize(g_newsCache,idx+1);
            g_newsCache[idx].time=vals[i].time; g_newsCache[idx].description=ev.name;
            g_newsCache[idx].currencies=country.currency; g_newsCache[idx].importance=impact; g_newsCache[idx].signalSent=false;
        }
    if(!Inp_StealthMode)
    {
        // Terminal-wide (not per-instance) dedup key: deliberately keyed by
        // symbol + day only, so two instances on the SAME asset only print
        // this recap once between them, while two instances on DIFFERENT
        // assets each still print their own (genuinely different information).
        string newsLogDedupKey = StringFormat("ORB_NEWSLOG_%s_%s", _Symbol, TimeToString(day, TIME_DATE));
        if(!GlobalVariableCheck(newsLogDedupKey))
        {
        GlobalVariableSet(newsLogDedupKey, (double)TimeCurrent());
        string cList="";
        for(int i=0;i<ArraySize(watchList);i++)
        {
            if(i>0) cList+=",";
            cList+=watchList[i];
        }
        PrintFormat("[ORB NEWS] %s auto-watch currencies: %s | guard=%s | events found: %d",
                    TimeToString(day,TIME_DATE), cList, ORBNNewsModeLabel(), ArraySize(g_newsCache));
        for(int i=0;i<ArraySize(g_newsCache);i++)
        {
            datetime ev=g_newsCache[i].time;
            datetime start=ev-bef;
            datetime finish=ev+aft;
            PrintFormat("[ORB NEWS] %s %s | impact=%s | event=%s server / %s NY | blackout=%s -> %s server (%d before, %d after)",
                        g_newsCache[i].currencies,
                        g_newsCache[i].description,
                        ORBNImpactLabel(g_newsCache[i].importance),
                        TimeToString(ev,TIME_DATE|TIME_MINUTES),
                        TimeToString(ServerToNY(ev),TIME_DATE|TIME_MINUTES),
                        TimeToString(start,TIME_DATE|TIME_MINUTES),
                        TimeToString(finish,TIME_DATE|TIME_MINUTES),
                        News_Block_Before_Min,
                        News_Block_After_Min);
        }
        }
    }
}
bool IsNewsBlocked(datetime now)
{
    if(!ORBNNewsEnabled()||!News_Block_Entries) return false;
    static datetime lastEval = 0;
    static bool cachedRes = false;
    if(now == lastEval) return cachedRes;
    
    ORBNLoadNewsCache(now);
    int bef=News_Block_Before_Min*60,aft=News_Block_After_Min*60;
    cachedRes = false;
    for(int i=0;i<ArraySize(g_newsCache);i++){ datetime ev=g_newsCache[i].time; if(now>=ev-bef&&now<=ev+aft) { cachedRes=true; break; } }
    lastEval = now;
    return cachedRes;
}
bool IsNewsFreezingTrail(datetime now)
{
    if(!ORBNNewsEnabled()||!News_Freeze_Trail) return false;
    static datetime lastEval = 0;
    static bool cachedRes = false;
    if(now == lastEval) return cachedRes;
    
    ORBNLoadNewsCache(now);
    int bef=News_Block_Before_Min*60,aft=News_Block_After_Min*60;
    cachedRes = false;
    for(int i=0;i<ArraySize(g_newsCache);i++){ datetime ev=g_newsCache[i].time; if(now>=ev-bef&&now<=ev+aft) { cachedRes=true; break; } }
    lastEval = now;
    return cachedRes;
}
bool IsNewsFlattening(datetime now)
{
    if(!ORBNNewsEnabled()||!News_Flatten_Before) return false;
    static datetime lastEval = 0;
    static bool cachedRes = false;
    if(now == lastEval) return cachedRes;
    
    ORBNLoadNewsCache(now);
    int flatSec=News_Flatten_Min*60;
    cachedRes = false;
    for(int i=0;i<ArraySize(g_newsCache);i++){ datetime ev=g_newsCache[i].time; if(now>=ev-flatSec&&now<ev) { cachedRes=true; break; } }
    lastEval = now;
    return cachedRes;
}
// Gate B (strict mode): true only when ALL three flags are enabled AND the current time falls
// inside the overlapping window where Block_Entries, Cancel_Pending, AND Flatten_Before are
// simultaneously active for the same news event.  When only a subset of flags is on, the
// granular per-flag behaviour applies unchanged â€” this derived predicate must NOT be used as
// a substitute for any individual flag check elsewhere in the codebase.
bool IsNewsStrictMode(datetime now)
{
    if(!ORBNNewsEnabled()) return false;
    if(!News_Block_Entries || !News_Cancel_Pending || !News_Flatten_Before) return false;
    static datetime lastEval = 0;
    static bool cachedRes = false;
    if(now == lastEval) return cachedRes;
    
    ORBNLoadNewsCache(now);
    int bef=News_Block_Before_Min*60, aft=News_Block_After_Min*60, flatSec=News_Flatten_Min*60;
    cachedRes = false;
    for(int i=0;i<ArraySize(g_newsCache);i++)
    {
        datetime ev=g_newsCache[i].time;
        bool blocked   = (now>=ev-bef   && now<=ev+aft);    // Block_Entries window
        bool flattening = (now>=ev-flatSec && now<ev);       // Flatten_Before window
        if(blocked && flattening) { cachedRes=true; break; }
    }
    lastEval = now;
    return cachedRes;
}
void ORBNewsOnTimer()
{
    if(!ORBNNewsEnabled()||!News_Signals_Enabled||ORBNSuppressed()) return;
    static datetime lastNewsTimer=0; datetime now=TimeCurrent();
    if(now-lastNewsTimer<60) return; lastNewsTimer=now;
    ORBNLoadNewsCache(now);
    int bef=News_Block_Before_Min*60;
    for(int i=0;i<ArraySize(g_newsCache);i++)
    {
        if(g_newsCache[i].signalSent) continue;
        datetime ev=g_newsCache[i].time;
        if(now>=ev-bef&&now<ev)
        {
            g_newsCache[i].signalSent=true;
            int minLeft=(int)((ev-now)/60);
            string t=StringFormat("%s NEWS  %s\n%s\n\n%s in %d min\nCurrencies: %s\nTrading paused during blackout.",
                                  ORBNSqS(),ORBNAssetName(_Symbol),TimeToString(now,TIME_DATE),
                                  g_newsCache[i].description,minLeft,g_newsCache[i].currencies);
            ORBNotifyWebhook(t,16776960);
        }
    }
}

//+------------------------------------------------------------------+
//| Weekly / Monthly Reports                                         |
//+------------------------------------------------------------------+
#define ORBN_LEDGER_FILE "ORB_TradeLedger.csv"
struct ORBClassStats{string n;int t,w;double pnl,gw,gl,best,worst;};
void   ORBSInit(ORBClassStats&s,const string nm){s.n=nm;s.t=0;s.w=0;s.pnl=0;s.gw=0;s.gl=0;s.best=0;s.worst=0;}
void   ORBSAdd(ORBClassStats&s,double p){s.t++;s.pnl+=p;if(p>0){s.w++;s.gw+=p;if(p>s.best)s.best=p;}else{s.gl+=MathAbs(p);if(p<s.worst)s.worst=p;}}
bool   ORBSHas(const ORBClassStats&s){return s.t>0;}
double ORBSWr(const ORBClassStats&s){return s.t>0?100.0*s.w/s.t:0.0;}
double ORBSPF(const ORBClassStats&s){return s.gl>0?s.gw/s.gl:(s.gw>0?999.0:0.0);}
string ORBNFamilyLabel(const string sym)
{ switch(ORBNFamily(sym)){case ORBN_FAM_INDEX:return"Indices";case ORBN_FAM_METAL:return"Metals";case ORBN_FAM_CRYPTO:return"Crypto";default:return"Forex";} }
void ORBReportLedgerAppend(bool bull,double pnl)
{
    if((bool)MQLInfoInteger(MQL_TESTER)) return;
    int h=FileOpen(ORBN_LEDGER_FILE,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
    if(h==INVALID_HANDLE) return;
    if(FileSize(h)==0) FileWriteString(h,"epoch,date,symbol,family,side,pnl\r\n");
    FileSeek(h,0,SEEK_END); datetime t=TimeCurrent();
    FileWriteString(h,StringFormat("%I64d,%s,%s,%s,%s,%.2f\r\n",(long)t,TimeToString(t,TIME_DATE),_Symbol,ORBNFamilyLabel(_Symbol),bull?"BUY":"SELL",pnl));
    FileClose(h);
}
string ORBNFmtDate(datetime t){MqlDateTime d;TimeToStruct(t,d);
    string m[12];m[0]="Jan";m[1]="Feb";m[2]="Mar";m[3]="Apr";m[4]="May";m[5]="Jun";
                 m[6]="Jul";m[7]="Aug";m[8]="Sep";m[9]="Oct";m[10]="Nov";m[11]="Dec";
    return StringFormat("%s %d",m[d.mon-1],d.day);}
string ORBNSection(const ORBClassStats&s){
    if(!ORBSHas(s))return"";double pf=ORBSPF(s);string sign=(s.pnl>=0)?"+":"";
    string o=StringFormat("â”€â”€ %s (%d trade%s) â”€â”€\nNet P/L: %s$%.2f\nWin: %d  -  Loss: %d  -  Rate: %.0f%%",
                          s.n,s.t,s.t==1?"":"s",sign,s.pnl,s.w,s.t-s.w,ORBSWr(s));
    if(s.best>0) o+=StringFormat("  -  Best: +$%.2f",s.best);
    if(s.worst<0)o+=StringFormat("  -  Worst: -$%.2f",MathAbs(s.worst));
    if(pf<999)   o+=StringFormat("  -  PF: %.2f",pf); else o+="  -  PF: âˆž";
    return o;}
string ORBBuildReport(const string label,datetime fromT,datetime toT,const string dateRange)
{
    ORBClassStats idx,met,cry,fx;
    ORBSInit(idx,"Indices");ORBSInit(met,"Metals");ORBSInit(cry,"Crypto");ORBSInit(fx,"Forex");
    int h=FileOpen(ORBN_LEDGER_FILE,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
    if(h!=INVALID_HANDLE){while(!FileIsEnding(h)){string line=FileReadString(h);
        if(line==""||StringFind(line,"epoch,")==0)continue;
        string c[];int nc=StringSplit(line,',',c);if(nc<5)continue;
        datetime t=(datetime)StringToInteger(c[0]);if(t<fromT||t>=toT)continue;
        string fam;double p;if(nc>=6){fam=c[3];p=StringToDouble(c[5]);}else{fam=ORBNFamilyLabel(c[2]);p=StringToDouble(c[4]);}
             if(fam=="Indices")ORBSAdd(idx,p);else if(fam=="Metals")ORBSAdd(met,p);
        else if(fam=="Crypto") ORBSAdd(cry,p);else ORBSAdd(fx,p);}FileClose(h);}
    ORBClassStats all;ORBSInit(all,"Total");
    ORBClassStats cls[4];cls[0]=idx;cls[1]=met;cls[2]=cry;cls[3]=fx;int nc2=0;
    for(int i=0;i<4;i++)if(ORBSHas(cls[i])){nc2++;all.t+=cls[i].t;all.w+=cls[i].w;
        all.pnl+=cls[i].pnl;all.gw+=cls[i].gw;all.gl+=cls[i].gl;
        if(cls[i].best>all.best)all.best=cls[i].best;if(cls[i].worst<all.worst)all.worst=cls[i].worst;}
    string header=StringFormat("ORB â€” %s Report\n%s",label,dateRange);
    if(!ORBSHas(all))return header+"\n\nNo trades recorded this period.";
    string body="";
    for(int i=0;i<4;i++){string s2=ORBNSection(cls[i]);if(s2!="")body+="\n\n"+s2;}
    if(nc2>1){string sign=(all.pnl>=0)?"+":"";double pf=ORBSPF(all);
        body+=StringFormat("\n\nâ”€â”€ TOTAL (%d trades) â”€â”€\nNet P/L: %s$%.2f\nWin: %d  -  Loss: %d  -  Rate: %.0f%%",
                           all.t,sign,all.pnl,all.w,all.t-all.w,ORBSWr(all));
        if(pf<999)body+=StringFormat("  -  PF: %.2f",pf);else body+="  -  PF: âˆž";}
    return header+body;
}
void ORBReportsOnTimer()
{
    if(!ORBN_Performance_Reports_Enabled||(bool)MQLInfoInteger(MQL_TESTER)) return;
    if(!ORBN_Discord_Enabled&&!ORBN_Telegram_Enabled) return;
    static datetime lastChk=0; datetime now=TimeCurrent();
    if(now-lastChk<60) return; lastChk=now;
    datetime nyNow=ServerToNY(now); MqlDateTime dtNY; TimeToStruct(nyNow,dtNY);
    if(dtNY.hour<ORBN_Report_Hour) return;
    int svOff=(int)(now-nyNow); datetime nyDay=nyNow-(nyNow%86400);
    if(dtNY.day_of_week==6){
        datetime wF=(nyDay-5*86400)+svOff,wT=nyDay+svOff;
        string rng=StringFormat("%s â€“ %s",ORBNFmtDate(wF),ORBNFmtDate(wT-86400));
        string lk=StringFormat("ORB_RPT_W_%s",TimeToString(wF,TIME_DATE));
        if(!GlobalVariableCheck(lk)){GlobalVariableSet(lk,(double)now);ORBNotifyWebhook(ORBBuildReport("Weekly",wF,wT,rng),5592575);}}
    datetime mF=0,mT=0;string mR="",mL="";
    if(ORBN_Monthly_On_Last_Day){
        datetime nyTm=nyNow+86400;MqlDateTime dtTm;TimeToStruct(nyTm,dtTm);
        if(dtTm.mon==dtNY.mon&&dtTm.year==dtNY.year)return;
        datetime mSN=nyDay-(datetime)((dtNY.day-1)*86400);
        mF=mSN+svOff;mT=nyDay+svOff;
        mR=StringFormat("%s â€“ %s",ORBNFmtDate(mF),ORBNFmtDate(mT-1));
        mL=StringFormat("ORB_RPT_M_%04d%02d",dtNY.year,dtNY.mon);
    }else{
        if(dtNY.day!=1)return;
        datetime pvL=nyDay-86400;MqlDateTime pvS;TimeToStruct(pvL,pvS);
        datetime pvN=pvL-(datetime)((pvS.day-1)*86400);
        mF=pvN+svOff;mT=nyDay+svOff;
        mR=StringFormat("%s â€“ %s",ORBNFmtDate(mF),ORBNFmtDate(mT-1));
        mL=StringFormat("ORB_RPT_M_%04d%02d",pvS.year,pvS.mon);}
    if(mL!=""&&!GlobalVariableCheck(mL)){GlobalVariableSet(mL,(double)now);ORBNotifyWebhook(ORBBuildReport("Monthly",mF,mT,mR),5592575);}
}

#endif // ORB_NOTIFY_MQH
