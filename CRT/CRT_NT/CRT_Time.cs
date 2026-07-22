using System;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public static class CRT_Time
    {
        //+------------------------------------------------------------------+
        //| Chart/platform timezone bridge                                   |
        //+------------------------------------------------------------------+
        // NT8 bar times (Time[0], Times[1][i]) are in the PLATFORM timezone
        // (Tools > Options > General > Time zone), NOT Windows-local time.
        // .ToLocalTime()/.ToUniversalTime() convert against Windows and skew
        // every anchor by (platformTZ - windowsTZ) hours. Always bridge
        // through the platform TimeZoneInfo instead.
        private static TimeZoneInfo PlatformTZ
        {
            get
            {
                try { return NinjaTrader.Core.Globals.GeneralOptions.TimeZoneInfo ?? TimeZoneInfo.Local; }
                catch { return TimeZoneInfo.Local; }
            }
        }

        // Bar/platform time → UTC
        public static DateTime ChartToUTC(DateTime chartTime)
        {
            return TimeZoneInfo.ConvertTimeToUtc(
                DateTime.SpecifyKind(chartTime, DateTimeKind.Unspecified), PlatformTZ);
        }

        // UTC → bar/platform time (use for ALL Draw.* time anchors)
        public static DateTime UTCToChart(DateTime utcTime)
        {
            return TimeZoneInfo.ConvertTimeFromUtc(
                DateTime.SpecifyKind(utcTime, DateTimeKind.Utc), PlatformTZ);
        }

        // "Now" in chart/platform time (Draw.* right edges)
        public static DateTime NowChart()
        {
            return UTCToChart(DateTime.UtcNow);
        }

        //+------------------------------------------------------------------+
        //| Core Time Conversions (Pure Calendar Math)                       |
        //+------------------------------------------------------------------+
        // This is ported verbatim from the MT5 version to maintain 
        // broker/platform-independent control over DST transitions.
        
        public static int NthSunday(int year, int mon, int nth)
        {
            int count = 0;
            int daysInMonth = DateTime.DaysInMonth(year, mon);
            
            for (int d = 1; d <= daysInMonth; d++)
            {
                DateTime probe = new DateTime(year, mon, d, 0, 0, 0, DateTimeKind.Utc);
                if (probe.DayOfWeek == DayOfWeek.Sunday)
                {
                    count++;
                    if (count == nth)
                        return d;
                }
            }
            return 1;
        }

        public static bool IsNYDSTDate(int year, int mon, int day)
        {
            // Always assume use NY DST since this is specific to US Futures logic
            if (mon < 3 || mon > 11) return false;
            if (mon > 3 && mon < 11) return true;

            int transDay;
            if (mon == 3)
            {
                transDay = NthSunday(year, 3, 2);
                return (day >= transDay);
            }
            if (mon == 11)
            {
                transDay = NthSunday(year, 11, 1);
                return (day < transDay);
            }
            return false;
        }

        // Returns the exact UTC instant of the DST transition.
        // Spring forward: 2nd Sunday March 02:00 local (07:00 UTC)
        // Fall back: 1st Sunday Nov 02:00 local (06:00 UTC)
        public static DateTime NthSundayOfMonthUTC(int year, int mon, int nth, int hourUTC)
        {
            int d = NthSunday(year, mon, nth);
            return new DateTime(year, mon, d, hourUTC, 0, 0, DateTimeKind.Utc);
        }

        // Returns NY offset in hours (-4 or -5).
        // Uses the exact UTC timestamp to detect the hour-level transition.
        public static int NYUTCOffsetHours(DateTime utcTime)
        {
            int y = utcTime.Year;
            DateTime marchTrans = NthSundayOfMonthUTC(y, 3, 2, 7); // 07:00 UTC = 02:00 EST
            DateTime novTrans = NthSundayOfMonthUTC(y, 11, 1, 6);  // 06:00 UTC = 02:00 EDT

            if (utcTime >= marchTrans && utcTime < novTrans)
            {
                return -4; // EDT
            }
            return -5; // EST
        }
        
        public static DateTime UTCToNY(DateTime utcTime)
        {
            int offsetHours = NYUTCOffsetHours(utcTime);
            return utcTime.AddHours(offsetHours);
        }

        public static DateTime NYToUTC(DateTime nyTime)
        {
            // Guess offset based on NY date
            bool isDst = IsNYDSTDate(nyTime.Year, nyTime.Month, nyTime.Day);
            int guessOffset = isDst ? -4 : -5;
            DateTime approxUTC = nyTime.AddHours(-guessOffset);
            
            // Refine with exact UTC offset
            int exactOffset = NYUTCOffsetHours(approxUTC);
            return nyTime.AddHours(-exactOffset);
        }
        
        //+------------------------------------------------------------------+
        //| Anchor and Session Math for NinjaScript                          |
        //+------------------------------------------------------------------+
        
        // NY True Day Open is typically 18:00 ET the prior calendar day.
        // Maintenance break typically 17:00-18:00 ET.
        public static DateTime GetCurrentNYTrueDayOpen(DateTime time0UTC)
        {
            DateTime nyTime = UTCToNY(time0UTC);
            
            // If it's before 18:00 NY, the "true" day started yesterday at 18:00
            // If it's 18:00 NY or later, the "true" day started today at 18:00
            DateTime trueDayOpenNY;
            if (nyTime.Hour < 18)
            {
                DateTime yesterday = nyTime.Date.AddDays(-1);
                trueDayOpenNY = new DateTime(yesterday.Year, yesterday.Month, yesterday.Day, 18, 0, 0);
            }
            else
            {
                trueDayOpenNY = new DateTime(nyTime.Year, nyTime.Month, nyTime.Day, 18, 0, 0);
            }
            
            // Adjust for weekends (if Monday before 18:00 or Sunday after 18:00, it opens Sunday 18:00)
            if (trueDayOpenNY.DayOfWeek == DayOfWeek.Saturday)
            {
                 trueDayOpenNY = trueDayOpenNY.AddDays(-1); // Shift Friday 18:00
            }
            
            return NYToUTC(trueDayOpenNY);
        }
        
        public static DateTime GetCurrentNYTrueWeekOpen(DateTime time0UTC)
        {
            DateTime nyTime = UTCToNY(time0UTC);
            DateTime weekStartNY = nyTime.Date;
            
            // Find preceding Sunday
            while (weekStartNY.DayOfWeek != DayOfWeek.Sunday)
            {
                weekStartNY = weekStartNY.AddDays(-1);
            }
            
            DateTime trueWeekOpenNY = new DateTime(weekStartNY.Year, weekStartNY.Month, weekStartNY.Day, 18, 0, 0);
            return NYToUTC(trueWeekOpenNY);
        }

        // Returns true if the current time falls inside the CME maintenance gap (17:00-18:00 NY)
        public static bool IsMaintenanceGap(DateTime time0UTC)
        {
            DateTime nyTime = UTCToNY(time0UTC);
            return (nyTime.Hour == 17);
        }

        // True Month Open — prior calendar day's 18:00 NY of the 1st of the
        // month, mirrors MT5's GetCurrentNYTrueMonthOpen (used by Slot 5).
        public static DateTime GetCurrentNYTrueMonthOpen(DateTime time0UTC)
        {
            DateTime nyTime = UTCToNY(time0UTC);

            DateTime firstOfMonthNY = new DateTime(nyTime.Year, nyTime.Month, 1, 0, 0, 0);
            DateTime openNY = firstOfMonthNY.AddDays(-1);
            openNY = new DateTime(openNY.Year, openNY.Month, openNY.Day, 18, 0, 0);

            if (nyTime < openNY)
            {
                DateTime prevFirst = firstOfMonthNY.AddMonths(-1);
                DateTime prevOpen = prevFirst.AddDays(-1);
                openNY = new DateTime(prevOpen.Year, prevOpen.Month, prevOpen.Day, 18, 0, 0);
            }

            return NYToUTC(openNY);
        }

        // Compute the session open instant given a specific NY hour/minute
        public static DateTime GetSessionOpenUTC(DateTime time0UTC, int openNYHour, int openNYMinute)
        {
            DateTime nyTime = UTCToNY(time0UTC);
            DateTime sessionOpenNY = new DateTime(nyTime.Year, nyTime.Month, nyTime.Day, openNYHour, openNYMinute, 0);
            
            // If NY time is past midnight but before the true day open (e.g. 02:00 for London),
            // and the session hour is large (e.g. Asia at 20:00), we must look back.
            // Vice versa for early hours during late day.
            
            if (openNYHour > 17 && nyTime.Hour < 17)
            {
                sessionOpenNY = sessionOpenNY.AddDays(-1); // Shift to yesterday
            }
            else if (openNYHour < 17 && nyTime.Hour > 17)
            {
                sessionOpenNY = sessionOpenNY.AddDays(1); // Shift to tomorrow
            }
            
            return NYToUTC(sessionOpenNY);
        }
    }
}
