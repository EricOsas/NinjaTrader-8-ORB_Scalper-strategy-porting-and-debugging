using System;
using System.Collections.Generic;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // CRT_HourFilter — CCT-style CSV of allowed NY hours for the EXECUTION
    // candle (C3). Port of CCT's AppendHourSlots / HasHour semantics.
    //   e.g. "3,7,10" → only C1→C2→C3 sequences whose C3 OPENS at NY 03:00,
    //   07:00 or 10:00 may execute. Empty string = allow all hours.
    //======================================================================
    public class CRT_HourFilter
    {
        private readonly HashSet<int> hours = new HashSet<int>();
        private bool allowAll = true;

        public CRT_HourFilter(string csv)
        {
            Parse(csv);
        }

        public void Parse(string csv)
        {
            hours.Clear();
            if (string.IsNullOrWhiteSpace(csv)) { allowAll = true; return; }

            foreach (string tok in csv.Split(','))
            {
                string t = tok.Trim();
                if (t.Length == 0) continue;
                if (int.TryParse(t, out int h) && h >= 0 && h <= 23)
                    hours.Add(h);
            }
            allowAll = hours.Count == 0;
        }

        // When the filter is disabled by the strategy, callers simply skip
        // this check. When enabled with an empty list, allow all (safe default).
        public bool IsAllowed(int nyHour)
        {
            if (allowAll) return true;
            return hours.Contains(nyHour);
        }
    }
}
