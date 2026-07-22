#region Using declarations
using System;
using System.Windows.Media;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
#endregion

// CRT_NT — chart visuals. Thin wrapper over NinjaTrader Draw.* so the strategy
// file stays focused on logic. All tags are prefixed so RemoveDrawObjects is scoped.
namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public static class CRT_Visuals
    {
        private const string P = "CRT_";

        // Draw the C1 range box (the "candle range" / dealing range).
        public static void DrawRangeBox(Strategy s, int c1StartBarsAgo, int c1EndBarsAgo,
            double hi, double lo, bool bullishBias)
        {
            if (s == null) return;
            string tag = P + "range_" + s.CurrentBars[0];
            Brush area = bullishBias ? Brushes.SeaGreen : Brushes.IndianRed;
            s.Draw.Rectangle(s, tag, false, c1StartBarsAgo, hi, c1EndBarsAgo, lo,
                Brushes.DimGray, area, 12);
        }

        // Mark the manipulation sweep (the wick that took liquidity beyond C1).
        public static void DrawSweep(Strategy s, int barsAgo, double price, bool sweepHigh)
        {
            if (s == null) return;
            string tag = P + "sweep_" + s.CurrentBars[0];
            if (sweepHigh)
                s.Draw.ArrowDown(s, tag, false, barsAgo, price, Brushes.Orange);
            else
                s.Draw.ArrowUp(s, tag, false, barsAgo, price, Brushes.Orange);
        }

        // Draw the FVG / IFVG confirmation zone.
        public static void DrawFvg(Strategy s, int startBarsAgo, int endBarsAgo,
            double top, double bottom, bool inverted)
        {
            if (s == null) return;
            string tag = P + (inverted ? "ifvg_" : "fvg_") + s.CurrentBars[0];
            Brush fill = inverted ? Brushes.MediumPurple : Brushes.SteelBlue;
            s.Draw.Rectangle(s, tag, false, startBarsAgo, top, endBarsAgo, bottom,
                Brushes.Transparent, fill, 25);
        }

        // Entry / SL / TP lines for a trade. Keyed by 'key' (the lane session
        // key) so overlapping concurrent setups each keep their own levels.
        public static void DrawTradeLevels(Strategy s, string key, double entry, double sl, double tp)
        {
            if (s == null) return;
            string k = Safe(key);
            s.Draw.HorizontalLine(s, P + "entry_" + k, entry, Brushes.Gold, DashStyleHelper.Solid, 1);
            s.Draw.HorizontalLine(s, P + "sl_" + k, sl, Brushes.IndianRed, DashStyleHelper.Dash, 1);
            s.Draw.HorizontalLine(s, P + "tp_" + k, tp, Brushes.SeaGreen, DashStyleHelper.Dash, 1);
        }

        public static void ClearTradeLevels(Strategy s, string key)
        {
            if (s == null) return;
            string k = Safe(key);
            s.RemoveDrawObject(P + "entry_" + k);
            s.RemoveDrawObject(P + "sl_" + k);
            s.RemoveDrawObject(P + "tp_" + k);
        }

        // NinjaTrader draw tags must be simple identifiers; strip separators.
        private static string Safe(string key)
            => string.IsNullOrEmpty(key) ? "x" : key.Replace("#", "_").Replace(":", "_").Replace(" ", "_");
    }
}
