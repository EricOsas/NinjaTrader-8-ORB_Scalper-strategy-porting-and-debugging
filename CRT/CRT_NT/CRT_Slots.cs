// CRT_Slots.cs — resolves each slot's C1/C2/C3 windows (UTC) and the
// execution LTF in minutes. Strategy spec §2 & §3; NT8 spec §3.
using System;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public static class CRT_Slots
    {
        // Minutes-per-C1-candle for the Intraday sub-slot timeframes.
        public static int C1TfMinutes(C1TF tf)
        {
            switch (tf)
            {
                case C1TF.M15: return 15;
                case C1TF.M30: return 30;
                case C1TF.H1:  return 60;
                case C1TF.H2:  return 120;
                case C1TF.H4:  return 240;
                default:       return 60;
            }
        }

        // Execution LTF in minutes (strategy spec §2.2).
        //   overrideMinutes > 0  → that value for EVERY slot (global override).
        //   overrideMinutes == 0 → auto-derive per slot/C1TF.
        public static int ResolveLtfMinutes(SlotType slot, C1TF c1tf, int overrideMinutes)
        {
            if (overrideMinutes > 0) return overrideMinutes;

            switch (slot)
            {
                case SlotType.Intraday:
                    switch (c1tf)
                    {
                        case C1TF.M15: return 1;
                        case C1TF.M30: return 1;
                        case C1TF.H1:  return 5;
                        case C1TF.H2:  return 5;
                        case C1TF.H4:  return 15;
                        default:       return 5;
                    }
                case SlotType.Daily:   return 15;
                case SlotType.Weekly:  return 60;
                case SlotType.Monthly: return 240;
                default:               return 5;
            }
        }

        //------------------------------------------------------------------
        // C1 window resolution. Returns the [start,end) UTC of the most
        // recent CLOSED C1 candle for the slot, given "now". C2 = the candle
        // immediately after C1; C3 = the candle after C2.
        //------------------------------------------------------------------
        public static void ResolveWindows(
            SlotType slot, C1TF c1tf, DateTime nowUTC,
            out DateTime c1Start, out DateTime c1End,
            out DateTime c2End, out DateTime c3End)
        {
            if (slot == SlotType.Intraday)
            {
                int m = C1TfMinutes(c1tf);
                // Grid the intraday candle to the NY trading day so H1/H2/H4
                // boundaries align with NY session structure (not broker 00:00).
                DateTime dayOpenUTC = CRT_Time.GetCurrentNYTrueDayOpen(nowUTC);
                double sinceOpenMin = (nowUTC - dayOpenUTC).TotalMinutes;
                int idxCurrent = (int)Math.Floor(sinceOpenMin / m);   // current forming candle index
                // C1 = the last CLOSED candle => idxCurrent - 1.
                int idxC1 = idxCurrent - 1;
                c1Start = dayOpenUTC.AddMinutes((double)idxC1 * m);
                c1End   = c1Start.AddMinutes(m);
                c2End   = c1End.AddMinutes(m);
                c3End   = c2End.AddMinutes(m);
                return;
            }

            if (slot == SlotType.Daily)
            {
                DateTime open = CRT_Time.GetCurrentNYTrueDayOpen(nowUTC);
                c1End = open; c1Start = open.AddDays(-1);
                c2End = open.AddDays(1); c3End = open.AddDays(2);
                return;
            }
            if (slot == SlotType.Weekly)
            {
                DateTime open = CRT_Time.GetCurrentNYTrueWeekOpen(nowUTC);
                c1End = open; c1Start = open.AddDays(-7);
                c2End = open.AddDays(7); c3End = open.AddDays(14);
                return;
            }
            // Monthly
            {
                DateTime open = CRT_Time.GetCurrentNYTrueMonthOpen(nowUTC);
                c1End = open; c1Start = open.AddMonths(-1);
                c2End = open.AddMonths(1); c3End = open.AddMonths(2);
            }
        }

        // Stable identity for a C1 candle → consumed-ledger key (spec §13).
        public static string C1Key(int slotIndex, DateTime c1StartUTC)
            => "S" + slotIndex + "_C1_" + c1StartUTC.ToString("yyyyMMddHHmm");
    }
}
