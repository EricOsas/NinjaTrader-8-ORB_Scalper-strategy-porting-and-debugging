#ifndef ORB_TIME_MQH
#define ORB_TIME_MQH

//+------------------------------------------------------------------+
//|                                                    ORB_Time.mqh |
//| Dynamic NY Time and Session calculations for ORB Scalper EA      |
//+------------------------------------------------------------------+

// Time inputs should be defined in the main EA and referenced here, or defined here.
// For modularity, we will declare external variables that the main EA will define.
extern int             Inp_ServerUTCOffsetHours;
extern bool            Inp_UseNewYorkDST;
extern int             Inp_OpenNYHour;
extern int             Inp_OpenNYMinute;
// Active session's open (resolved by the EA from g_activeSession). The trade
// engine keys the opening range and cutoff off THIS session, so enabling
// London or Asian as the live session trades that open, not NY's.
extern int             Inp_OpenActiveHour;
extern int             Inp_OpenActiveMin;
extern int             Inp_RangeMinutes;
// Per-session cutoff durations (minutes from each session's open). The active
// session's value is resolved by the EA into Inp_CutoffActiveMin and used here
// to compute the trade-stop cutoff instant for whichever session is current.
extern int             Inp_CutoffActiveMin;
// Context bridge globals: set by SetSlotContext() before slot-sensitive calls.
// These are writable (non-input) so they can be swapped per slot at runtime.
extern ENUM_RANGE_MODE g_ctxMode;
extern int             g_ctxHour;
extern int             g_ctxMin;
extern int             g_ctxCutoffMin;
extern int             g_ctxSlotIdx;
extern int             Inp_Slot2AnchorMode;

// TESTER default server->UTC offset (hours). The weekly-open auto-anchor is
// unreliable on feeds whose week does not open at 17:00 NY (e.g. Exness), so in
// the tester we use this fixed default unless Server_UTC_Offset_Hours is set.
// Adjust here, or just set Server_UTC_Offset_Hours in inputs (it overrides this).
// Diagnostic proof: with this = 0 on the Exness tester feed, NY 09:30 maps to
// 14:30 server in winter (EST) and 13:30 in summer (EDT) - DST handled by
// NYUTCOffsetSec. Set Server_UTC_Offset_Hours in inputs to override per feed.
// NOTE: with the server->NY offset model this default is now a server->NY value
// (hours the server clock is AHEAD of New York), NOT server->UTC. FundingPips
// runs server = NY + 8h, so 8 lands 09:30 NY at server 17:30 in both seasons
// even on short windows that contain no weekend gap for the anchor to read.
#define ORB_TESTER_DEFAULT_SERVER_UTC  8

//+------------------------------------------------------------------+
//| Core Time Conversions                                            |
//+------------------------------------------------------------------+
// CROSS-BROKER TIME FIX (ported from CCT proven model):
// The previous engine trusted a single manual Inp_ServerUTCOffsetHours, so a
// broker whose server clock differs from UTC (e.g. QT server = UTC+3) drifted
// vs a broker at UTC+0 (Exness) -> dashboard/chart/tester times disagreed and
// were further skewed by DST. The fix auto-detects EACH terminal's server-to-UTC
// offset at runtime from TimeTradeServer() vs TimeGMT() (preferring the live
// trade-server clock), rounded to the nearest hour. NY DST is computed against
// UTC instants at the exact transition hours, not local-date guessing.
// Inp_ServerUTCOffsetHours is now an OVERRIDE: 0 = auto-detect (recommended),
// non-zero = force that offset.

// Cutoff is now a duration (minutes) measured from the active session's open,
// not a fixed wall-clock time. CutoffMinutes() returns that duration; the
// SessionCutoffServer() instant is the active session open + this many minutes.
// CutoffMinutes() is defined later (context-bridge version) - forward declaration only.

datetime MakeDateTime(int year,int mon,int day,int hour,int minute,int sec)
{
    MqlDateTime dt;
    ZeroMemory(dt);
    dt.year=year;
    dt.mon=mon;
    dt.day=day;
    dt.hour=hour;
    dt.min=minute;
    dt.sec=sec;
    return StructToTime(dt);
}

int NthSunday(int year,int mon,int nth)
{
    int count=0;
    for(int d=1; d<=31; d++)
    {
        MqlDateTime probe;
        TimeToStruct(MakeDateTime(year,mon,d,0,0,0),probe);
        if(probe.mon!=mon)
            break;
        if(probe.day_of_week==0)
        {
            count++;
            if(count==nth)
                return d;
        }
    }
    return 1;
}

bool IsNYDSTDate(int year,int mon,int day)
{
    if(!Inp_UseNewYorkDST)
        return false;
    if(mon<3 || mon>11)
        return false;
    if(mon>3 && mon<11)
        return true;
    if(mon==3)
        return day>=NthSunday(year,3,2);
    if(mon==11)
        return day<NthSunday(year,11,1);
    return false;
}

int NYUTCOffsetHoursForDate(int year,int mon,int day)
{
    return IsNYDSTDate(year,mon,day) ? -4 : -5;
}

//+------------------------------------------------------------------+
//| Day-of-month for the Nth / last Sunday (UTC-instant DST anchors)  |
//+------------------------------------------------------------------+
int NthSundayOfMonthUTC(int year,int month,int nth)
{
    if(nth < 1) return 1;
    MqlDateTime dt; ZeroMemory(dt);
    dt.year=year; dt.mon=month; dt.day=1;
    datetime firstDay=StructToTime(dt);
    TimeToStruct(firstDay,dt);
    int firstDow=dt.day_of_week;            // 0=Sunday
    int firstSunday=1 + ((7-firstDow)%7);
    return firstSunday + (nth-1)*7;
}

//+------------------------------------------------------------------+
//| NY UTC offset (seconds) for a UTC instant - DST-aware             |
//| EDT (-4h) between 2nd Sun Mar 07:00 UTC and 1st Sun Nov 06:00 UTC  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Auto-detect THIS terminal's server-to-UTC offset (seconds)        |
//| Prefers TimeTradeServer() (live trade-server clock) vs TimeGMT(); |
//| falls back to TimeCurrent(). Rounded to the nearest hour.         |
//| Inp_ServerUTCOffsetHours != 0 forces a manual override.           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| TESTER TIME AUTO-DETECT (weekly-open anchor)                      |
//| In the strategy tester TimeGMT() is simulated (~= server clock),  |
//| so the live auto-detect collapses to 0 and a UTC+3 feed (QT)      |
//| shows NY times +3h. The market week, however, ALWAYS opens at     |
//| Sunday 17:00 New York. Find the first H1 bar after the weekend    |
//| gap; its server-clock time reveals this feed's true UTC offset on |
//| any broker, with no manual input. 24/7 symbols (crypto) have no   |
//| weekend gap and fall through to the live method - use the manual  |
//| override on such feeds if the broker is not UTC.                  |
//+------------------------------------------------------------------+
int TesterWeekAnchorOffsetSec()
{
    static int  cached = -999999;
    static bool done   = false;
    if(done) return cached;

    // History may not be loaded on the very first call (OnInit) - retry later.
    if(iTime(_Symbol, PERIOD_H1, 1) <= 0) return -999999;

    datetime newer = 0;
    for(int i = 1; i < 500; i++)
    {
        datetime t = iTime(_Symbol, PERIOD_H1, i);
        if(t <= 0) break;
        if(newer > 0 && (newer - t) >= 40*3600)      // candidate weekend gap
        {
            datetime weekOpenServer = newer;          // first bar of the new week
            datetime weekCloseServer = t;             // last bar of the prior week

            // EXNESS +1h REGRESSION FIX: validate the gap is a TRUE Fri->Sun
            // weekend, not a holiday hole or a data gap. The bar BEFORE the gap
            // must fall on a Friday (server time, dow 5) and the bar AFTER it on
            // a Sunday or Monday (dow 0/1). A few hours of offset skew can never
            // move a Friday-evening bar off Friday, so the day-of-week test is
            // safe before the offset is even known. Reject anything else and
            // keep scanning for the next gap.
            MqlDateTime co; TimeToStruct(weekCloseServer, co);
            MqlDateTime op; TimeToStruct(weekOpenServer,  op);
            bool closeIsFri = (co.day_of_week == 5);
            bool openIsSunMon = (op.day_of_week == 0 || op.day_of_week == 1);
            if(!closeIsFri || !openIsSunMon) { newer = t; continue; }

            // The market week ALWAYS opens at 17:00 New York. Derive the
            // broker's FIXED server->UTC offset from this anchor, then let
            // NYUTCOffsetSec apply NY DST once on top (the correct model).
            //
            // CORRECT MODEL (evidence: Exness runs a FIXED UTC offset, NOT a
            // DST-following clock - a 09:30 NY range fires at 14:30 server in
            // summer and 15:30 in winter on the same UTC+1 feed). So:
            //   serverUTCoffset = weekendServerSecOfDay - weekendUTCSecOfDay
            // where the weekend's UTC second-of-day is 17:00 NY converted via
            // that weekend's OWN DST: summer (EDT,-4h) -> 21:00 UTC,
            // winter (EST,-5h) -> 22:00 UTC. The weekend DST is resolved from
            // its NY wall-clock (17:00), which is unambiguous.
            // The server stamp of the weekly-open bar IS the server->NY offset
            // directly. On FundingPips the first bar of the week is stamped
            // server 02:00 = 18:00 NY (Sunday), so server->NY = 02:00 - 18:00
            // wrapped = +8h. DST is already baked into the server clock
            // (DST-following feed), so we DO NOT re-apply NY DST on top - that
            // double-count was the 1h summer error. For a fixed-UTC feed
            // (Exness) the open bar sits at a different season-dependent server
            // time and the anchor re-derives the correct server->NY per season.
            //
            // WEEKLY-OPEN REFERENCE = 18:00 NY (not 17:00): this feed's first
            // post-weekend bar lands at 18:00 NY. Using 17:00 over-counted the
            // offset by 1h (Dec resolved 9h -> 18:30 instead of 8h -> 17:30).
            int srvSecDay     = (int)((long)weekOpenServer % 86400);
            int nyOpenSecDay  = 18*3600;                          // 18:00 NY open
            int diff          = srvSecDay - nyOpenSecDay;         // server->NY offset
            while(diff >  12*3600) diff -= 86400;
            while(diff < -12*3600) diff += 86400;
            int off = (int)(MathRound((double)diff/3600.0)*3600.0);  // snap to hour

            // PLAUSIBILITY GATE: server->NY for real feeds is roughly -2..+10.
            if(off < -2*3600 || off > 10*3600) { newer = t; continue; }

            cached = off;   // this is the FIXED server->NY offset (seconds)
            done   = true;
            // DIAGNOSTIC: surface what the anchor resolved so the tester time
            // can be verified directly (weekend bar + derived offset).
            if(!Inp_StealthMode)
                PrintFormat("[ORB TIME] anchor: weekendBarServer=%s srvSecDay=%d nyOpenSecDay=%d -> serverNYoffset=%dh",
                            TimeToString(weekOpenServer, TIME_DATE|TIME_MINUTES),
                            srvSecDay, nyOpenSecDay, off/3600);
            return cached;
        }
        newer = t;
    }
    done = true;     // scanned real history, no valid weekend gap -> sentinel
    return cached;
}

// SERVER -> NY offset (seconds), the single source of truth for time math.
// This is the number of seconds the SERVER clock is AHEAD of New York wall
// time. It is derived directly from the weekly-open anchor (Sunday 17:00 NY),
// so for a DST-following feed (FundingPips, server = NY+8h) it is a flat +8h in
// both seasons, and for a fixed-UTC feed (Exness) the anchor re-derives the
// correct value per season. DST is NOT applied a second time on top - the
//
// Server_UTC_Offset_Hours is a +/- CORRECTION DELTA added on top of the
// auto-derived value: if auto-detect lands the range 1h early, set 1 to push it
// 1h later (and -1 to pull it earlier). 0 = pure auto-detect.
int ServerNYOffsetSec()
{
    int correction = Inp_ServerUTCOffsetHours * 3600;   // +/- nudge on auto value
    int autoOff;

    // TESTER: TimeGMT() is simulated (~= server clock), so the live
    // TimeTradeServer()-vs-TimeGMT() method collapses to 0. Use the weekly-open
    // anchor instead (Sunday 17:00 NY), which yields server->NY directly,
    // guarded by a Fri->Sun day-of-week check + plausibility gate. Falls back to
    // a sane default only if no valid weekend gap is in the loaded history (a
    // sub-week window or a 24/7 crypto feed); pin it with the correction input.
    if((bool)MQLInfoInteger(MQL_TESTER))
    {
        int anchored = TesterWeekAnchorOffsetSec();
        if(anchored != -999999)
            autoOff = anchored;
        else
            // No weekend in range (sub-week window or 24/7 feed): use the
            // default DIRECTLY - it is already a server->NY value (flat NY+8h
            // for FundingPips), so it is correct in both seasons with no DST
            // term. Adding NYUTCOffsetSec here was the leftover double-count
            // that pushed summer to 12h/21:30.
            autoOff = ORB_TESTER_DEFAULT_SERVER_UTC*3600;
        return autoOff + correction;
    }

    // LIVE: server->UTC from the live trade-server clock vs GMT, then add NY's
    // UTC offset to express it as server->NY (server is AHEAD of NY by this).
    datetime serverNow = TimeCurrent();
    datetime tradeNow  = TimeTradeServer();
    datetime gmtNow    = TimeGMT();

    int currentOff = (int)(serverNow - gmtNow);
    int tradeOff   = (tradeNow > 0) ? (int)(tradeNow - gmtNow) : 0;

    int rawUTC = 0;
    if(tradeNow > 0)                   rawUTC = tradeOff;
    else if(MathAbs(currentOff) >= 60) rawUTC = currentOff;
    int serverUTC = (int)(MathRound((double)rawUTC / 3600.0) * 3600.0);

    // server->NY = server->UTC - NY->UTC  (NYUTCOffsetSec is negative, so this
    // adds the 4h/5h; e.g. UTC+0 server in winter = NY+5h).
    autoOff = serverUTC - NYUTCOffsetSec(gmtNow);
    return autoOff + correction;
}

// Back-compat shim: some callers still ask for server->UTC. Derive it from the
// server->NY offset by removing NY's own UTC offset for the given instant.
int ServerUTCOffsetSec()
{
    datetime nowSrv = TimeCurrent();
    datetime approxUTC = nowSrv - ServerNYOffsetSec() - NYUTCOffsetSec(nowSrv);
    return ServerNYOffsetSec() + NYUTCOffsetSec(approxUTC);
}

datetime ServerToUTC(datetime serverTime)
{
    return serverTime - ServerUTCOffsetSec();
}

datetime UTCToServer(datetime utcTime)
{
    return utcTime + ServerUTCOffsetSec();
}

datetime ServerToNY(datetime serverTime)
{
    // Server clock already carries DST (DST-following feed) or the anchor has
    // resolved the correct per-season offset (fixed-UTC feed). Convert directly.
    return serverTime - ServerNYOffsetSec();
}

// One-time diagnostic: prints what server clock the configured NY open maps to,
// so the correct Server_UTC_Offset_Hours is obvious from a single tester run.
// Call after the bridge is populated (OnInit).
void ORBLogTimeMapping(int nyHour,int nyMin)
{
    datetime nowSrv = TimeCurrent();
    MqlDateTime ny; TimeToStruct(ServerToNY(nowSrv), ny);
    datetime openSrv = NYLocalToServer(ny.year,ny.mon,ny.day,nyHour,nyMin,0);
    MqlDateTime os; TimeToStruct(openSrv, os);
    if(!Inp_StealthMode)
        PrintFormat("[ORB TIME EFFECTIVE] serverNYoffset=%dh | NY %02d:%02d  ->  server %02d:%02d  (Server_UTC_Offset_Hours nudges this +/- so the server time matches the real %02d:%02d-NY candle)",
                    ServerNYOffsetSec()/3600, nyHour, nyMin, os.hour, os.min, nyHour, nyMin);
}

// True while New York is on daylight time (EDT) for this server instant.
// Used by the Tokyo-anchored Asian session (Tokyo observes no DST). NY wall
// time comes straight from ServerToNY; its UTC offset for that instant tells
// us the DST state without any extra server-clock assumptions.
bool NYIsDST(datetime serverTime)
{
    datetime ny  = ServerToNY(serverTime);
    datetime utc = ny + NYUTCOffsetSec(ny);   // ny back to UTC (offset is negative)
    return (NYUTCOffsetSec(utc) == -4*3600);
}

datetime NYLocalToServer(int year,int mon,int day,int hour,int minute,int sec)
{
    // Exact inverse of ServerToNY: the server clock is AHEAD of NY wall time by
    // ServerNYOffsetSec (DST already baked into the server clock, or resolved
    // per-season by the anchor). So server = NY wall + offset, directly. No
    // UTC round trip and no second DST application - that double-count was the
    
// old 1h summer error.
    datetime nyWall = MakeDateTime(year,mon,day,hour,minute,sec);
    return nyWall + ServerNYOffsetSec();
}

string CurrentNYSessionKey(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(ServerToNY(serverTime),ny);
    return StringFormat("%04d%02d%02d",ny.year,ny.mon,ny.day);
}

datetime GetCurrentD1Open(datetime serverTime)
{
    static datetime s_d1Open = 0;
    static datetime s_lastCheck = 0;
    if(serverTime - s_lastCheck > 3600 || serverTime >= s_d1Open + 86400)
    {
        datetime t = iTime(_Symbol, PERIOD_D1, 0);
        if(t > 0) s_d1Open = t;
        s_lastCheck = serverTime;
    }
    if(s_d1Open <= 0) s_d1Open = serverTime - (serverTime % 86400); // fallback
    return s_d1Open;
}

datetime GetCurrentW1Open(datetime serverTime)
{
    static datetime s_w1Open = 0;
    static datetime s_lastCheck = 0;
    if(serverTime - s_lastCheck > 3600)
    {
        datetime t = iTime(_Symbol, PERIOD_W1, 0);
        if(t > 0) s_w1Open = t;
        s_lastCheck = serverTime;
    }
    if(s_w1Open <= 0) s_w1Open = serverTime - (serverTime % 86400); // generic fallback
    return s_w1Open;
}

datetime GetCurrentNYTrueDayOpen(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(ServerToNY(serverTime), ny);
    datetime nyMidnight = MakeDateTime(ny.year, ny.mon, ny.day, 0, 0, 0);
    datetime openNy = MakeDateTime(ny.year, ny.mon, ny.day, 18, 0, 0);
    if(ServerToNY(serverTime) < openNy)
        openNy = nyMidnight - 86400 + 18 * 3600;

    MqlDateTime op;
    TimeToStruct(openNy, op);
    return NYLocalToServer(op.year, op.mon, op.day, 18, 0, 0);
}

datetime GetCurrentNYTrueWeekOpen(datetime serverTime)
{
    MqlDateTime ny;
    datetime nyNow = ServerToNY(serverTime);
    TimeToStruct(nyNow, ny);
    datetime nyMidnight = MakeDateTime(ny.year, ny.mon, ny.day, 0, 0, 0);

    int daysBack = ny.day_of_week;
    datetime weekOpenNy = nyMidnight - (datetime)(daysBack * 86400) + 18 * 3600;
    if(nyNow < weekOpenNy) weekOpenNy -= 7 * 86400;

    MqlDateTime op;
    TimeToStruct(weekOpenNy, op);
    return NYLocalToServer(op.year, op.mon, op.day, 18, 0, 0);
}

// Session markers — slot-aware, reads context bridge globals set by SetSlotContext().
datetime SessionOpenServer(datetime serverTime)
{
    if(g_ctxMode == RANGE_DAILY)
        return (Inp_Slot2AnchorMode == 0) ? GetCurrentNYTrueDayOpen(serverTime)
                                                               : GetCurrentD1Open(serverTime);
    if(g_ctxMode == RANGE_WEEKLY)
        return (Inp_Slot2AnchorMode == 0) ? GetCurrentNYTrueWeekOpen(serverTime)
                                                               : GetCurrentW1Open(serverTime);
    if(g_ctxMode == RANGE_MONTHLY)
        return (Inp_Slot2AnchorMode == 0) ? GetCurrentNYTrueMonthOpen(serverTime)
                                                               : GetCurrentMN1Open(serverTime);

    // Intraday: use the context hour/minute (resolved per active slot)
    MqlDateTime ny;
    TimeToStruct(ServerToNY(serverTime),ny);
    return NYLocalToServer(ny.year,ny.mon,ny.day,g_ctxHour,g_ctxMin,0);
}

datetime SessionCutoffServer(datetime serverTime)
{
    datetime open = SessionOpenServer(serverTime);
    if(g_ctxMode == RANGE_MONTHLY)
    {
        // Exact calendar months logic based on Slot2_Cutoff_Periods
        MqlDateTime dt;
        TimeToStruct(open, dt);
        
        // Add cutoff periods as months
        int cutoffMonths = (g_ctxCutoffMin / 43200);
        if(cutoffMonths <= 0) cutoffMonths = 1; // Default to 1 period if 0 or fallback
        
        dt.mon += cutoffMonths;
        while(dt.mon > 12) { dt.mon -= 12; dt.year++; }
        
        return StructToTime(dt);
    }
    return open + (datetime)(CutoffMinutes()*60);
}

// CutoffMinutes reads from pre-computed context bridge (set by SetSlotContext).
int CutoffMinutes()
{
    if(g_ctxCutoffMin > 0) return g_ctxCutoffMin;
    return 90; // safety fallback
}
//+------------------------------------------------------------------+
//| Dashboard Display Helpers                                        |
//+------------------------------------------------------------------+

string DashClock(datetime srv,bool seconds=true)
{
    if(srv<=0)
        return "--:--";
    int flags = seconds ? (TIME_MINUTES|TIME_SECONDS) : TIME_MINUTES;
    return TimeToString(srv, flags);
}

string GetCountdownText(datetime targetServerTime, datetime nowServer)
{
    if(nowServer >= targetServerTime)
        return "00:00:00";
    int diff = (int)(targetServerTime - nowServer);
    int h = diff / 3600;
    int m = (diff % 3600) / 60;
    int s = diff % 60;
    
    return StringFormat("%02d:%02d:%02d", h, m, s);
}

#endif // ORB_TIME_MQH
datetime GetCurrentMN1Open(datetime serverTime)
{
    static datetime s_mn1Open = 0;
    static datetime s_lastCheck = 0;
    if(serverTime - s_lastCheck > 3600)
    {
        datetime t = iTime(_Symbol, PERIOD_MN1, 0);
        if(t > 0) s_mn1Open = t;
        s_lastCheck = serverTime;
    }
    if(s_mn1Open <= 0) s_mn1Open = serverTime - (serverTime % 86400); // generic fallback
    return s_mn1Open;
}

datetime GetCurrentNYTrueMonthOpen(datetime serverTime)
{
    MqlDateTime ny;
    datetime nyNow = ServerToNY(serverTime);
    TimeToStruct(nyNow, ny);
    
    // NY True Month opens on the last trading day of the previous calendar month at 17:00 NY time
    // For simplicity of approximation while retaining the "Sunday open" logic, NY True Month Open
    // is simply the 1st of the month's earliest NY 17:00 or similar.
    // Wait, the user said: "Use the true calendar-month boundary (via the new GetCurrentNYTrueMonthOpen/GetCurrentMN1Open helpers) rather than a fixed 30-day multiplier"
    // The calendar month boundary NY time: Day 1 of the current month.
    // Let's compute Day 1 of current month, 00:00 NY time, but shift it to previous day 17:00 NY.
    
    // NY Midnight of the 1st of current month
    datetime firstOfMonthNY = MakeDateTime(ny.year, ny.mon, 1, 0, 0, 0);
    // True NY open is typically the prior day at 17:00, but actually the first TRADING day of the month.
    // If we just use the 1st at 00:00 or prior day 17:00 NY time:
    datetime openNy = firstOfMonthNY - 86400 + 18 * 3600; // Prior day 18:00 NY time.
    if(nyNow < openNy) 
    {
        // If we are before the 18:00 open of the 1st, we belong to previous month.
        MqlDateTime prev;
        TimeToStruct(firstOfMonthNY - 86400, prev);
        datetime firstOfPrevNY = MakeDateTime(prev.year, prev.mon, 1, 0, 0, 0);
        openNy = firstOfPrevNY - 86400 + 18 * 3600;
    }
    
    MqlDateTime op;
    TimeToStruct(openNy, op);
    return NYLocalToServer(op.year, op.mon, op.day, 18, 0, 0);
}


