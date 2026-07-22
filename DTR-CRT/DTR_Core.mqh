//+------------------------------------------------------------------+
//|                                                     DTR_Core.mqh |
//| Core Time, Bias, and Session Logic (18:00 NY Anchored)           |
//+------------------------------------------------------------------+
#ifndef DTR_CORE_MQH
#define DTR_CORE_MQH

#define DTR_TESTER_DEFAULT_SERVER_UTC  8

//+------------------------------------------------------------------+
//| ENUMS & STRUCTS                                                  |
//+------------------------------------------------------------------+
enum ENUM_DTR_BIAS
{
    BIAS_NONE     = 0,
    BIAS_LONG     = 1,
    BIAS_SHORT    = 2,
    BIAS_NEUTRAL  = 3,
    BIAS_NOTRADE  = 4
};

enum ENUM_DTR_SESSION
{
    SESSION_LONDON = 0,
    SESSION_NY     = 1
};

struct DTR_SyntheticCandle
{
    datetime time; // Open time
    double   open;
    double   high;
    double   low;
    double   close;
    long     tick_volume;
    double   eq() const { return low + (high - low) / 2.0; }
};

struct DTR_SessionRange
{
    datetime openTime;
    datetime closeTime;
    double   high;
    double   low;
    bool     locked;
};

//+------------------------------------------------------------------+
//| GLOBALS & PERSISTENT STATE                                       |
//+------------------------------------------------------------------+
DTR_SyntheticCandle g_nyCandleA;
DTR_SyntheticCandle g_nyCandleB;
DTR_SyntheticCandle g_londonCandleA;
DTR_SyntheticCandle g_londonCandleB;
DTR_SyntheticCandle g_priorTrueDay;

bool g_nyBiasReady     = false;
bool g_londonBiasReady = false;
bool g_priorDayReady   = false;

ENUM_DTR_BIAS g_nyBias     = BIAS_NONE;
ENUM_DTR_BIAS g_londonBias = BIAS_NONE;

DTR_SessionRange g_liveLondonRange;
DTR_SessionRange g_liveNYRange;

double g_priorDayLondonHigh = 0.0, g_priorDayLondonLow = 0.0;
double g_priorDayNYHigh = 0.0,     g_priorDayNYLow = 0.0;
double g_priorTrueDayHigh = 0.0,   g_priorTrueDayLow = 0.0;

bool g_sweptPriorLondon[2] = {false, false};
bool g_sweptPriorNY[2]     = {false, false};
bool g_sweptAsia[2]        = {false, false};
bool g_sweptCurrentLondon[2]= {false, false};
bool g_sweptPriorTrueDay[2]= {false, false};

datetime g_lastTrueDayRollover = 0;

//+------------------------------------------------------------------+
//| TIME CONVERSIONS                                                 |
//+------------------------------------------------------------------+
datetime MakeDateTime(int year,int mon,int day,int hour,int minute,int sec)
{
    MqlDateTime dt;
    ZeroMemory(dt);
    dt.year=year; dt.mon=mon; dt.day=day;
    dt.hour=hour; dt.min=minute; dt.sec=sec;
    return StructToTime(dt);
}

int NthSunday(int year,int mon,int nth)
{
    int count=0;
    for(int d=1; d<=31; d++)
    {
        MqlDateTime probe;
        TimeToStruct(MakeDateTime(year,mon,d,0,0,0),probe);
        if(probe.mon!=mon) break;
        if(probe.day_of_week==0)
        {
            count++;
            if(count==nth) return d;
        }
    }
    return 1;
}

bool IsNYDSTDate(int year,int mon,int day)
{
    if(!Inp_UseNewYorkDST) return false;
    if(mon<3 || mon>11) return false;
    if(mon>3 && mon<11) return true;
    if(mon==3) return day>=NthSunday(year,3,2);
    if(mon==11) return day<NthSunday(year,11,1);
    return false;
}

int NthSundayOfMonthUTC(int year,int month,int nth)
{
    if(nth < 1) return 1;
    MqlDateTime dt; ZeroMemory(dt);
    dt.year=year; dt.mon=month; dt.day=1;
    datetime firstDay=StructToTime(dt);
    TimeToStruct(firstDay,dt);
    int firstDow=dt.day_of_week;            
    int firstSunday=1 + ((7-firstDow)%7);
    return firstSunday + (nth-1)*7;
}

int NYUTCOffsetSec(datetime utcTime)
{
    if(!Inp_UseNewYorkDST) return -5*3600;
    MqlDateTime utc; TimeToStruct(utcTime,utc);
    int year=utc.year;

    int marchSunday    = NthSundayOfMonthUTC(year,3,2);
    int novemberSunday = NthSundayOfMonthUTC(year,11,1);

    MqlDateTime startUtc; ZeroMemory(startUtc);
    startUtc.year=year; startUtc.mon=3;  startUtc.day=marchSunday;    startUtc.hour=7;
    MqlDateTime endUtc;   ZeroMemory(endUtc);
    endUtc.year=year;   endUtc.mon=11; endUtc.day=novemberSunday;   endUtc.hour=6;

    datetime dstStart=StructToTime(startUtc);
    datetime dstEnd  =StructToTime(endUtc);
    return (utcTime>=dstStart && utcTime<dstEnd) ? -4*3600 : -5*3600;
}

int TesterWeekAnchorOffsetSec()
{
    static int  cached = -999999;
    static bool done   = false;
    if(done) return cached;

    if(iTime(_Symbol, PERIOD_H1, 1) <= 0) return -999999;

    datetime newer = 0;
    for(int i = 1; i < 500; i++)
    {
        datetime t = iTime(_Symbol, PERIOD_H1, i);
        if(t <= 0) break;
        if(newer > 0 && (newer - t) >= 40*3600)
        {
            datetime weekOpenServer = newer;          
            datetime weekCloseServer = t;             

            MqlDateTime co; TimeToStruct(weekCloseServer, co);
            MqlDateTime op; TimeToStruct(weekOpenServer,  op);
            bool closeIsFri = (co.day_of_week == 5);
            bool openIsSunMon = (op.day_of_week == 0 || op.day_of_week == 1);
            if(!closeIsFri || !openIsSunMon) { newer = t; continue; }

            int srvSecDay     = (int)((long)weekOpenServer % 86400);
            int nyOpenSecDay  = 18*3600;                          
            int diff          = srvSecDay - nyOpenSecDay;         
            while(diff >  12*3600) diff -= 86400;
            while(diff < -12*3600) diff += 86400;
            int off = (int)(MathRound((double)diff/3600.0)*3600.0);  

            if(off < -2*3600 || off > 10*3600) { newer = t; continue; }

            cached = off;   
            done   = true;
            if(!Inp_StealthMode)
                PrintFormat("[DTR TIME] anchor: weekendBarServer=%s srvSecDay=%d nyOpenSecDay=%d -> serverNYoffset=%dh",
                            TimeToString(weekOpenServer, TIME_DATE|TIME_MINUTES),
                            srvSecDay, nyOpenSecDay, off/3600);
            return cached;
        }
        newer = t;
    }
    done = true;     
    return cached;
}

int ServerNYOffsetSec()
{
    int correction = Inp_ServerUTCOffsetHours * 3600;   
    int autoOff;

    if((bool)MQLInfoInteger(MQL_TESTER))
    {
        int anchored = TesterWeekAnchorOffsetSec();
        if(anchored != -999999)
            autoOff = anchored;
        else
            autoOff = DTR_TESTER_DEFAULT_SERVER_UTC*3600;
        return autoOff + correction;
    }

    datetime serverNow = TimeCurrent();
    datetime tradeNow  = TimeTradeServer();
    datetime gmtNow    = TimeGMT();

    int currentOff = (int)(serverNow - gmtNow);
    int tradeOff   = (tradeNow > 0) ? (int)(tradeNow - gmtNow) : 0;

    int rawUTC = 0;
    if(tradeNow > 0)                   rawUTC = tradeOff;
    else if(MathAbs(currentOff) >= 60) rawUTC = currentOff;
    int serverUTC = (int)(MathRound((double)rawUTC / 3600.0) * 3600.0);

    autoOff = serverUTC - NYUTCOffsetSec(gmtNow);
    return autoOff + correction;
}

int ServerUTCOffsetSec()
{
    datetime nowSrv = TimeCurrent();
    datetime approxUTC = nowSrv - ServerNYOffsetSec() - NYUTCOffsetSec(nowSrv);
    return ServerNYOffsetSec() + NYUTCOffsetSec(approxUTC);
}

datetime ServerToUTC(datetime serverTime) { return serverTime - ServerUTCOffsetSec(); }
datetime UTCToServer(datetime utcTime) { return utcTime + ServerUTCOffsetSec(); }
datetime ServerToNY(datetime serverTime) { return serverTime - ServerNYOffsetSec(); }

bool NYIsDST(datetime serverTime)
{
    datetime ny  = ServerToNY(serverTime);
    datetime utc = ny + NYUTCOffsetSec(ny);   
    return (NYUTCOffsetSec(utc) == -4*3600);
}

datetime NYLocalToServer(int year,int mon,int day,int hour,int minute,int sec)
{
    datetime nyWall = MakeDateTime(year,mon,day,hour,minute,sec);
    return nyWall + ServerNYOffsetSec();
}

string CurrentNYSessionKey(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(ServerToNY(serverTime),ny);
    return StringFormat("%04d%02d%02d",ny.year,ny.mon,ny.day);
}

//+------------------------------------------------------------------+
//| DTR 18:00 NY ANCHOR (TRUE DAY OPEN)                              |
//+------------------------------------------------------------------+
datetime DTRNYTrueDayOpenForServerTime(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(ServerToNY(serverTime), ny);
    
    // The True Day opens at 18:00 NY. 
    if(ny.hour < 18)
    {
        datetime priorDay = MakeDateTime(ny.year, ny.mon, ny.day, 0, 0, 0) - 86400;
        TimeToStruct(priorDay, ny);
    }
    return NYLocalToServer(ny.year, ny.mon, ny.day, 18, 0, 0);
}

//+------------------------------------------------------------------+
//| HTF BIAS EVALUATION                                              |
//+------------------------------------------------------------------+
ENUM_DTR_BIAS EvaluateBias(const DTR_SyntheticCandle &candleA, const DTR_SyntheticCandle &candleB)
{
    bool sweptHigh = (candleB.high > candleA.high);
    bool sweptLow  = (candleB.low < candleA.low);
    
    if(!sweptHigh && !sweptLow) return BIAS_NEUTRAL;
    
    if(sweptHigh && sweptLow)
    {
        if(candleB.close > candleA.eq()) return BIAS_LONG;
        if(candleB.close < candleA.eq()) return BIAS_SHORT;
        return BIAS_NEUTRAL;
    }
    
    if(sweptHigh && !sweptLow)
    {
        if(candleB.close <= candleA.high) return BIAS_SHORT;
        return BIAS_NOTRADE; 
    }
    
    if(!sweptHigh && sweptLow)
    {
        if(candleB.close >= candleA.low) return BIAS_LONG;
        return BIAS_NOTRADE; 
    }
    return BIAS_NONE;
}

datetime GetCandleAnchor(datetime serverTime, ENUM_DTR_SESSION session, int candleIndex)
{
    datetime trueDayOpen = DTRNYTrueDayOpenForServerTime(serverTime);
    MqlDateTime dt;
    TimeToStruct(ServerToNY(trueDayOpen), dt); 
    
    if(session == SESSION_NY)
    {
        if(candleIndex == 0)
            return NYLocalToServer(dt.year, dt.mon, dt.day, 18, 0, 0);
        else 
            return NYLocalToServer(dt.year, dt.mon, dt.day, 18, 0, 0) + 7*3600; 
    }
    else 
    {
        if(candleIndex == 0) 
            return NYLocalToServer(dt.year, dt.mon, dt.day, 18, 0, 0);
        else 
            return NYLocalToServer(dt.year, dt.mon, dt.day, 18, 0, 0) + 3*3600 + 1800; 
    }
}

bool BuildSyntheticCandle(datetime anchorStart, int durationSeconds, DTR_SyntheticCandle &outCandle)
{
    outCandle.time = 0;
    if(TimeCurrent() < anchorStart + durationSeconds) return false;
        
    MqlRates src[];
    int copied = CopyRates(_Symbol, PERIOD_M5, anchorStart, anchorStart + durationSeconds - 1, src);
    if(copied <= 0) return false;
    
    outCandle.time = anchorStart;
    outCandle.open = src[0].open;
    outCandle.high = src[0].high;
    outCandle.low  = src[0].low;
    outCandle.close = src[copied-1].close;
    outCandle.tick_volume = 0;
    
    for(int i=0; i<copied; i++)
    {
        if(src[i].high > outCandle.high) outCandle.high = src[i].high;
        if(src[i].low < outCandle.low)   outCandle.low = src[i].low;
        outCandle.tick_volume += src[i].tick_volume;
    }
    return true;
}

bool BuildPriorTrueDay(datetime serverTime, DTR_SyntheticCandle &outCandle)
{
    datetime currentTrueDayOpen = DTRNYTrueDayOpenForServerTime(serverTime);
    
    MqlDateTime dt;
    TimeToStruct(ServerToNY(currentTrueDayOpen), dt);
    datetime priorWall = MakeDateTime(dt.year, dt.mon, dt.day, 18, 0, 0) - 86400;
    TimeToStruct(priorWall, dt);
    datetime priorTrueDayOpen = NYLocalToServer(dt.year, dt.mon, dt.day, 18, 0, 0);
    
    int durationSec = (int)(currentTrueDayOpen - priorTrueDayOpen);
    return BuildSyntheticCandle(priorTrueDayOpen, durationSec, outCandle);
}

void UpdateBiasState(datetime serverTime)
{
    datetime lonA_Start = GetCandleAnchor(serverTime, SESSION_LONDON, 0);
    datetime lonB_Start = GetCandleAnchor(serverTime, SESSION_LONDON, 1);
    
    if(BuildSyntheticCandle(lonA_Start, 3*3600 + 1800, g_londonCandleA) && 
       BuildSyntheticCandle(lonB_Start, 3*3600 + 1800, g_londonCandleB))
    {
        g_londonBiasReady = true;
        g_londonBias = EvaluateBias(g_londonCandleA, g_londonCandleB);
    }
    else
    {
        g_londonBiasReady = false;
        g_londonBias = BIAS_NONE;
    }
    
    datetime nyA_Start = GetCandleAnchor(serverTime, SESSION_NY, 0);
    datetime nyB_Start = GetCandleAnchor(serverTime, SESSION_NY, 1);
    
    if(BuildSyntheticCandle(nyA_Start, 7*3600, g_nyCandleA) && 
       BuildSyntheticCandle(nyB_Start, 7*3600, g_nyCandleB))
    {
        g_nyBiasReady = true;
        g_nyBias = EvaluateBias(g_nyCandleA, g_nyCandleB);
    }
    else
    {
        g_nyBiasReady = false;
        g_nyBias = BIAS_NONE;
    }
    
    g_priorDayReady = BuildPriorTrueDay(serverTime, g_priorTrueDay);
}

//+------------------------------------------------------------------+
//| SESSION MANAGER                                                  |
//+------------------------------------------------------------------+
void ResetSweptFlags()
{
    for(int i=0; i<2; i++)
    {
        g_sweptPriorLondon[i] = false;
        g_sweptPriorNY[i]     = false;
        g_sweptAsia[i]        = false;
        g_sweptCurrentLondon[i]= false;
        g_sweptPriorTrueDay[i]= false;
    }
}

void CheckTrueDayRollover(datetime serverTime)
{
    datetime currentTrueDayOpen = DTRNYTrueDayOpenForServerTime(serverTime);
    if(currentTrueDayOpen != g_lastTrueDayRollover)
    {
        g_priorDayLondonHigh = g_liveLondonRange.high;
        g_priorDayLondonLow  = g_liveLondonRange.low;
        g_priorDayNYHigh     = g_liveNYRange.high;
        g_priorDayNYLow      = g_liveNYRange.low;
        
        ZeroMemory(g_liveLondonRange);
        ZeroMemory(g_liveNYRange);
        
        ResetSweptFlags();
        g_lastTrueDayRollover = currentTrueDayOpen;
    }
}

string ConsumedKey(ENUM_DTR_SESSION session, bool isLong)
{
    string side = isLong ? "LONG" : "SHORT";
    string sessName = (session == SESSION_LONDON) ? "LONDON" : "NY";
    return StringFormat("DTR_CONSUMED_%s_%s_%d", sessName, side, (int)g_lastTrueDayRollover);
}

bool SideConsumed(ENUM_DTR_SESSION session, bool isLong)
{
    string key = ConsumedKey(session, isLong);
    return GlobalVariableCheck(key) && (GlobalVariableGet(key) == 1.0);
}

void MarkSideConsumed(ENUM_DTR_SESSION session, bool isLong)
{
    string key = ConsumedKey(session, isLong);
    GlobalVariableSet(key, 1.0);
}

bool IsInRangeWindow(datetime serverTime, ENUM_DTR_SESSION session)
{
    MqlDateTime dt;
    TimeToStruct(ServerToNY(serverTime), dt);
    
    datetime openNY = NYLocalToServer(dt.year, dt.mon, dt.day, (session==SESSION_LONDON)?1:8, 12, 0);
    datetime closeNY= NYLocalToServer(dt.year, dt.mon, dt.day, (session==SESSION_LONDON)?2:9, 12, 0);
    
    return (serverTime >= openNY && serverTime < closeNY);
}

bool IsInTradingWindow(datetime serverTime, ENUM_DTR_SESSION session)
{
    MqlDateTime dt;
    TimeToStruct(ServerToNY(serverTime), dt);
    
    datetime openNY, closeNY;
    if(session == SESSION_LONDON)
    {
        openNY = NYLocalToServer(dt.year, dt.mon, dt.day, 2, 12, 0);
        closeNY= NYLocalToServer(dt.year, dt.mon, dt.day, 4, 0, 0);
    }
    else 
    {
        openNY = NYLocalToServer(dt.year, dt.mon, dt.day, 9, 30, 0);
        closeNY= NYLocalToServer(dt.year, dt.mon, dt.day, 10, 30, 0);
    }
    
    return (serverTime >= openNY && serverTime < closeNY);
}

void ManageLiveRanges(datetime serverTime, MqlRates &m1Tick)
{
    CheckTrueDayRollover(serverTime);
    
    // London
    if(IsInRangeWindow(serverTime, SESSION_LONDON))
    {
        if(!g_liveLondonRange.locked)
        {
            if(g_liveLondonRange.openTime == 0)
            {
                g_liveLondonRange.openTime = serverTime;
                g_liveLondonRange.high = m1Tick.high;
                g_liveLondonRange.low = m1Tick.low;
            }
            else
            {
                if(m1Tick.high > g_liveLondonRange.high) g_liveLondonRange.high = m1Tick.high;
                if(m1Tick.low < g_liveLondonRange.low)   g_liveLondonRange.low = m1Tick.low;
            }
        }
    }
    else if(g_liveLondonRange.openTime > 0 && !g_liveLondonRange.locked)
    {
        g_liveLondonRange.locked = true;
        g_liveLondonRange.closeTime = serverTime;
    }
    
    // NY
    if(IsInRangeWindow(serverTime, SESSION_NY))
    {
        if(!g_liveNYRange.locked)
        {
            if(g_liveNYRange.openTime == 0)
            {
                g_liveNYRange.openTime = serverTime;
                g_liveNYRange.high = m1Tick.high;
                g_liveNYRange.low = m1Tick.low;
            }
            else
            {
                if(m1Tick.high > g_liveNYRange.high) g_liveNYRange.high = m1Tick.high;
                if(m1Tick.low < g_liveNYRange.low)   g_liveNYRange.low = m1Tick.low;
            }
        }
    }
    else if(g_liveNYRange.openTime > 0 && !g_liveNYRange.locked)
    {
        g_liveNYRange.locked = true;
        g_liveNYRange.closeTime = serverTime;
    }
}

#endif // DTR_CORE_MQH
