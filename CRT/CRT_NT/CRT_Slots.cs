using System;
using NinjaTrader.Data;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // CRT_Slots — HTF/LTF timeframe resolution.
    //
    // NinjaScript needs data series declared up-front in State.Configure, so
    // v1 runs ONE active C1 timeframe at a time: Intraday (if enabled) drives
    // the HTF series, otherwise the first enabled HTF slot (Daily→Weekly→
    // Monthly). The single-active-trade rule makes this the pragmatic default;
    // running several HTF slots at once is a documented v2 extension.
    //======================================================================
    public static class CRT_Slots
    {
        // Intraday timeframe → minutes
        public static int IntradayMinutes(IntradayTF tf)
        {
            switch (tf)
            {
                case IntradayTF.M15: return 15;
                case IntradayTF.M30: return 30;
                case IntradayTF.H1:  return 60;
                case IntradayTF.H2:  return 120;
                case IntradayTF.H4:  return 240;
                default:             return 60;
            }
        }

        // HTF BarsPeriod for the active slot.
        public static BarsPeriod HtfBarsPeriod(SlotType type, IntradayTF tf)
        {
            switch (type)
            {
                case SlotType.Daily:   return new BarsPeriod { BarsPeriodType = BarsPeriodType.Day,   Value = 1 };
                case SlotType.Weekly:  return new BarsPeriod { BarsPeriodType = BarsPeriodType.Week,  Value = 1 };
                case SlotType.Monthly: return new BarsPeriod { BarsPeriodType = BarsPeriodType.Month, Value = 1 };
                default:               return new BarsPeriod { BarsPeriodType = BarsPeriodType.Minute, Value = IntradayMinutes(tf) };
            }
        }

        // LTF minutes: explicit override (>0) wins globally, else auto-derive.
        public static int ResolveLtfMinutes(SlotType type, IntradayTF tf, int overrideMinutes)
        {
            if (overrideMinutes > 0) return overrideMinutes;

            switch (type)
            {
                case SlotType.Daily:   return 15;
                case SlotType.Weekly:  return 60;
                case SlotType.Monthly: return 240;
                default:
                    switch (tf)
                    {
                        case IntradayTF.M15: return 1;
                        case IntradayTF.M30: return 1;
                        case IntradayTF.H1:  return 5;
                        case IntradayTF.H2:  return 5;
                        case IntradayTF.H4:  return 15;
                        default:             return 5;
                    }
            }
        }

        // Human label for the active C1 timeframe (dashboard/logs).
        public static string TfLabel(SlotType type, IntradayTF tf)
        {
            switch (type)
            {
                case SlotType.Daily:   return "Daily";
                case SlotType.Weekly:  return "Weekly";
                case SlotType.Monthly: return "Monthly";
                default:
                    switch (tf)
                    {
                        case IntradayTF.M15: return "15m";
                        case IntradayTF.M30: return "30m";
                        case IntradayTF.H1:  return "1H";
                        case IntradayTF.H2:  return "2H";
                        case IntradayTF.H4:  return "4H";
                        default:             return "1H";
                    }
            }
        }
    }
}
