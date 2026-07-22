#ifndef CRT_TIME_MQH
#define CRT_TIME_MQH

//======================================================================
// CRT_Time.mqh — NY-DST-aware time utilities for CRT EA.
// Lifted and adapted from ORB_Time.mqh (proven, field-tested model).
//
// Key model: every call resolves server → NY via ServerNYOffsetSec(),
// which is auto-detected from the weekly-open anchor (Sunday 18:00 NY).
// DST is applied correctly once; Inp_ServerUTCOffsetHours is a nudge
// delta (+/- hours) rather than an absolute override.
//======================================================================

#include "CRT_Globals.mqh"

// Inputs referenced here — declared in CRT_EA.mq5
extern int  Inp_ServerUTCOffsetHours; // 0 = auto-detect
extern bool Inp_UseNewYorkDST;

//----------------------------------------------------------------------
// Low-level date helpers
//----------------------------------------------------------------------
datetime CrtMakeDateTime(int year, int mon, int day, int hour, int minute, int sec)
{
    MqlDateTime dt; ZeroMemory(dt);
    dt.year = year; dt.mon = mon; dt.day = day;
    dt.hour = hour; dt.min = minute; dt.sec = sec;
    return StructToTime(dt);
}

int CrtNthSundayOfMonth(int year, int month, int nth)
{
    if (nth < 1) return 1;
    MqlDateTime dt; ZeroMemory(dt);
    dt.year = year; dt.mon = month; dt.day = 1;
    datetime firstDay = StructToTime(dt);
    TimeToStruct(firstDay, dt);
    int firstDow = dt.day_of_week; // 0 = Sunday
    int firstSunday = 1 + ((7 - firstDow) % 7);
    return firstSunday + (nth - 1) * 7;
}

// NY UTC offset (seconds) for a UTC instant — DST-aware.
// EDT (-4h) between 2nd Sun Mar 07:00 UTC and 1st Sun Nov 06:00 UTC.
int CrtNYUTCOffsetSec(datetime utcTime)
{
    if (!Inp_UseNewYorkDST) return -5 * 3600;
    MqlDateTime u; TimeToStruct(utcTime, u);
    int year = u.year;

    int marSun = CrtNthSundayOfMonth(year, 3, 2);
    int novSun = CrtNthSundayOfMonth(year, 11, 1);

    MqlDateTime dstStart; ZeroMemory(dstStart);
    dstStart.year = year; dstStart.mon = 3; dstStart.day = marSun; dstStart.hour = 7;
    MqlDateTime dstEnd; ZeroMemory(dstEnd);
    dstEnd.year = year; dstEnd.mon = 11; dstEnd.day = novSun; dstEnd.hour = 6;

    datetime ds = StructToTime(dstStart);
    datetime de = StructToTime(dstEnd);
    return (utcTime >= ds && utcTime < de) ? -4 * 3600 : -5 * 3600;
}

//----------------------------------------------------------------------
// Weekly-open anchor (tester: derives server→NY offset from the first
// post-weekend bar, expected at Sunday 18:00 NY).
//----------------------------------------------------------------------
int CrtTesterWeekAnchorOffsetSec()
{
    static int  cached = -999999;
    static bool done   = false;
    if (done) return cached;
    if (iTime(_Symbol, PERIOD_H1, 1) <= 0) return -999999;

    datetime newer = 0;
    for (int i = 1; i < 500; i++)
    {
        datetime t = iTime(_Symbol, PERIOD_H1, i);
        if (t <= 0) break;
        if (newer > 0 && (newer - t) >= 40 * 3600)
        {
            MqlDateTime co; TimeToStruct(t, co);
            MqlDateTime op; TimeToStruct(newer, op);
            if (co.day_of_week != 5 || (op.day_of_week != 0 && op.day_of_week != 1))
            {
                newer = t; continue;
            }
            int srvSecDay    = (int)((long)newer % 86400);
            int nyOpenSecDay = 18 * 3600; // 18:00 NY
            int diff = srvSecDay - nyOpenSecDay;
            while (diff >  12 * 3600) diff -= 86400;
            while (diff < -12 * 3600) diff += 86400;
            int off = (int)(MathRound((double)diff / 3600.0) * 3600.0);
            if (off < -2 * 3600 || off > 10 * 3600) { newer = t; continue; }
            cached = off;
            done   = true;
            if (!g_crtStealthMode)
                PrintFormat("[CRT_Time] Anchor: weekBar=%s srvSecDay=%d nyOpen=%d -> serverNY=%dh",
                            TimeToString(newer, TIME_DATE | TIME_MINUTES),
                            srvSecDay, nyOpenSecDay, off / 3600);
            return cached;
        }
        newer = t;
    }
    done = true;
    return cached;
}

// Server → NY offset (seconds). Auto-detected or nudged by input.
int CrtServerNYOffsetSec()
{
    int correction = Inp_ServerUTCOffsetHours * 3600;
    int autoOff;

    if ((bool)MQLInfoInteger(MQL_TESTER))
    {
        int anchored = CrtTesterWeekAnchorOffsetSec();
        autoOff = (anchored != -999999) ? anchored : 8 * 3600; // FundingPips default
        return autoOff + correction;
    }

    datetime serverNow = TimeCurrent();
    datetime tradeNow  = TimeTradeServer();
    datetime gmtNow    = TimeGMT();
    int tradeOff       = (tradeNow > 0) ? (int)(tradeNow - gmtNow) : 0;
    int currentOff     = (int)(serverNow - gmtNow);
    int rawUTC = (tradeNow > 0) ? tradeOff : (MathAbs(currentOff) >= 60 ? currentOff : 0);
    int serverUTC = (int)(MathRound((double)rawUTC / 3600.0) * 3600.0);
    autoOff = serverUTC - CrtNYUTCOffsetSec(gmtNow);
    return autoOff + correction;
}

//----------------------------------------------------------------------
// Public conversions
//----------------------------------------------------------------------
datetime CrtServerToNY(datetime serverTime)
{
    return serverTime - CrtServerNYOffsetSec();
}

datetime CrtNYToServer(int year, int mon, int day, int hour, int minute, int sec)
{
    datetime nyWall = CrtMakeDateTime(year, mon, day, hour, minute, sec);
    return nyWall + CrtServerNYOffsetSec();
}

// Returns NY wall time for TimeCurrent().
datetime CrtNowNY()
{
    return CrtServerToNY(TimeCurrent());
}

// NY hour (0-23) for a server timestamp.
int CrtNYHour(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(CrtServerToNY(serverTime), ny);
    return ny.hour;
}

// Format NY clock string "HH:mm:ss NY"
string CrtNYClockStr(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(CrtServerToNY(serverTime), ny);
    return StringFormat("%02d:%02d:%02d NY", ny.hour, ny.min, ny.sec);
}

// NY-day session key "YYYYMMDD" — used for daily-guard and state-store keys.
string CrtNYDayKey(datetime serverTime)
{
    MqlDateTime ny;
    TimeToStruct(CrtServerToNY(serverTime), ny);
    return StringFormat("%04d%02d%02d", ny.year, ny.mon, ny.day);
}

//----------------------------------------------------------------------
// HTF period helpers: resolve the ENUM_TIMEFRAMES for C1 candles.
//----------------------------------------------------------------------
ENUM_TIMEFRAMES CrtHtfPeriod(ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf)
{
    switch (slot)
    {
        case CRT_SLOT_INTRADAY:
            switch ((int)intradayTf)
            {
                case 15:  return PERIOD_M15;
                case 30:  return PERIOD_M30;
                case 60:  return PERIOD_H1;
                case 120: return PERIOD_H2;
                case 240: return PERIOD_H4;
                default:  return PERIOD_H1;
            }
        case CRT_SLOT_DAILY:   return PERIOD_D1;
        case CRT_SLOT_WEEKLY:  return PERIOD_W1;
        case CRT_SLOT_MONTHLY: return PERIOD_MN1;
        default: return PERIOD_H1;
    }
}

// Auto-derive LTF period in minutes. Spec pairings:
//   1H→M5, 4H→M15, 1D→M15, 1W→H1, 1M→H4
// Override = 0 → auto.
ENUM_TIMEFRAMES CrtLtfPeriod(ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf, int ltfOverrideMin)
{
    if (ltfOverrideMin > 0)
    {
        switch (ltfOverrideMin)
        {
            case 1:   return PERIOD_M1;
            case 5:   return PERIOD_M5;
            case 15:  return PERIOD_M15;
            case 30:  return PERIOD_M30;
            case 60:  return PERIOD_H1;
            case 240: return PERIOD_H4;
            default:  return PERIOD_M5;
        }
    }
    switch (slot)
    {
        case CRT_SLOT_DAILY:   return PERIOD_M15;
        case CRT_SLOT_WEEKLY:  return PERIOD_H1;
        case CRT_SLOT_MONTHLY: return PERIOD_H4;
        case CRT_SLOT_INTRADAY:
        default:
            switch ((int)intradayTf)
            {
                case 15:  return PERIOD_M1;
                case 30:  return PERIOD_M5;
                case 60:  return PERIOD_M5;
                case 120: return PERIOD_M15;
                case 240: return PERIOD_M15;
                default:  return PERIOD_M5;
            }
    }
}

// Human-readable label for the slot (used in dashboard + session keys).
string CrtSlotLabel(ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf)
{
    switch (slot)
    {
        case CRT_SLOT_DAILY:   return "D1";
        case CRT_SLOT_WEEKLY:  return "W1";
        case CRT_SLOT_MONTHLY: return "MN1";
        case CRT_SLOT_INTRADAY:
        default:
            switch ((int)intradayTf)
            {
                case 15:  return "M15";
                case 30:  return "M30";
                case 60:  return "H1";
                case 120: return "H2";
                case 240: return "H4";
                default:  return "H1";
            }
    }
}

// Build a unique session key: "<slotLabel>#<yyyymmddhhmm_UTC>"
string CrtSessionKey(ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf, datetime c1ServerTime)
{
    MqlDateTime u; TimeToStruct(c1ServerTime, u);
    return StringFormat("%s#%04d%02d%02d%02d%02d",
                        CrtSlotLabel(slot, intradayTf),
                        u.year, u.mon, u.day, u.hour, u.min);
}

//----------------------------------------------------------------------
// CSV hour-filter (CCT-style): parse "2,3,9,10" → check if a given NY
// hour is in the allowed set.
//----------------------------------------------------------------------
#define CRT_MAX_ALLOWED_HOURS 24
int g_crtAllowedHours[CRT_MAX_ALLOWED_HOURS];
int g_crtAllowedHoursCount = 0;

void CrtParseHourFilter(const string csv)
{
    g_crtAllowedHoursCount = 0;
    if (csv == "" || csv == "0") return;
    string parts[];
    int n = StringSplit(csv, ',', parts);
    for (int i = 0; i < n && g_crtAllowedHoursCount < CRT_MAX_ALLOWED_HOURS; i++)
    {
        string s = parts[i];
        StringTrimLeft(s); StringTrimRight(s);
        int h = (int)StringToInteger(s);
        if (h >= 0 && h <= 23)
            g_crtAllowedHours[g_crtAllowedHoursCount++] = h;
    }
}

bool CrtHourAllowed(int nyHour)
{
    if (g_crtAllowedHoursCount == 0) return true; // empty = all hours
    for (int i = 0; i < g_crtAllowedHoursCount; i++)
        if (g_crtAllowedHours[i] == nyHour) return true;
    return false;
}

#endif // CRT_TIME_MQH
