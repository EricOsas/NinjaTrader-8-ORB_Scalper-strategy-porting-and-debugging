// CRT_HourFilter.cs — optional C3 (execution candle) hour gate.
// Modeled on the CCT bot's multi-intraday hour selection (see
// CRT/03-MQL5-IMPLEMENTATION.md). OFF by default -> trades 24h.
// When enabled, a CRT setup may only ARM if the C3 window opens on one of the
// selected NY-local hours (e.g. {3,7,10} => only 03:00, 07:00, 10:00 hosts C3).
using System;
using System.Collections.Generic;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public class CrtHourFilter
    {
        public bool Enabled = false;

        // NY-local hours (0-23) allowed to host Candle 3 / execution.
        private readonly HashSet<int> _hours = new HashSet<int>();

        public void SetHours(IEnumerable<int> hours)
        {
            _hours.Clear();
            if (hours == null) return;
            foreach (var h in hours)
                if (h >= 0 && h <= 23) _hours.Add(h);
        }

        // Parse a CSV string like "3,7,10" from a NinjaScript input.
        public void SetFromCsv(string csv)
        {
            _hours.Clear();
            if (string.IsNullOrWhiteSpace(csv)) return;
            foreach (var tok in csv.Split(','))
            {
                int h;
                if (int.TryParse(tok.Trim(), out h) && h >= 0 && h <= 23)
                    _hours.Add(h);
            }
        }

        // c3OpenNy = the NY-local timestamp at which the C3 window opens.
        public bool Allows(DateTime c3OpenNy)
        {
            if (!Enabled) return true;          // 24h default
            if (_hours.Count == 0) return true; // enabled but nothing selected -> no gate
            return _hours.Contains(c3OpenNy.Hour);
        }

        public string DescribeHours()
        {
            if (!Enabled) return "24h";
            if (_hours.Count == 0) return "24h (none set)";
            var list = new List<int>(_hours);
            list.Sort();
            return string.Join(",", list.ConvertAll(x => x.ToString("00")));
        }
    }
}
