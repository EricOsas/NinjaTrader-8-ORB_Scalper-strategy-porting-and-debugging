// CRT_Confirm.cs — rolling LTF tracker that feeds CISD + IFVG detection.
// Adapted from the CCT IFVG scanner (see CRT/03-MQL5-IMPLEMENTATION.md §CCT lifts).
// Keeps a small ring of recent LTF bars and maintains the most relevant
// unfilled FVG in the trade direction plus the CISD reference level.
using System;
using System.Collections.Generic;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public struct LtfBar
    {
        public DateTime Time;
        public double Open, High, Low, Close;
    }

    // A 3-candle fair-value gap.
    public class Fvg
    {
        public bool IsBullish;    // bullish gap = imbalance to the upside
        public double Upper;      // gap upper edge
        public double Lower;      // gap lower edge
        public DateTime Time;     // time of the middle (gap) candle
        public bool Inverted;     // has price closed through it against its origin?
    }

    public class CrtConfirmTracker
    {
        private readonly List<LtfBar> _bars = new List<LtfBar>();
        private readonly int _maxBars;

        // Most recent qualifying FVG in view (candidate for inversion).
        public Fvg ActiveGap { get; private set; }

        // CISD reference: the origin level of the displacement leg that produced
        // the C2 sweep. Set by the structure driver when a sweep is detected.
        public double CisdLevel { get; set; }

        public CrtConfirmTracker(int maxBars = 200)
        {
            _maxBars = Math.Max(10, maxBars);
        }

        public void Reset()
        {
            _bars.Clear();
            ActiveGap = null;
            CisdLevel = 0;
        }

        // Push a freshly CLOSED LTF bar. Recomputes the latest FVG and inversion.
        public void OnLtfBarClosed(LtfBar bar, bool wantBullish)
        {
            _bars.Add(bar);
            if (_bars.Count > _maxBars) _bars.RemoveAt(0);
            if (_bars.Count < 3) return;

            DetectNewFvg(wantBullish);
            UpdateInversion(bar);
        }

        // A bullish FVG forms when low[0] > high[2] (gap between candle -2 high and
        // candle 0 low). Bearish is the mirror: high[0] < low[2].
        private void DetectNewFvg(bool wantBullish)
        {
            int n = _bars.Count;
            LtfBar c0 = _bars[n - 1];   // newest
            LtfBar c2 = _bars[n - 3];   // two bars back

            if (wantBullish && c0.Low > c2.High)
            {
                ActiveGap = new Fvg
                {
                    IsBullish = true,
                    Upper = c0.Low,
                    Lower = c2.High,
                    Time = _bars[n - 2].Time,
                    Inverted = false
                };
            }
            else if (!wantBullish && c0.High < c2.Low)
            {
                ActiveGap = new Fvg
                {
                    IsBullish = false,
                    Upper = c2.Low,
                    Lower = c0.High,
                    Time = _bars[n - 2].Time,
                    Inverted = false
                };
            }
        }

        // An FVG becomes INVERTED when a later candle closes through it against its
        // origin. A bearish gap inverted to the upside (close above Upper) confirms
        // a long; a bullish gap inverted to the downside confirms a short.
        private void UpdateInversion(LtfBar bar)
        {
            if (ActiveGap == null) return;

            if (!ActiveGap.IsBullish && bar.Close > ActiveGap.Upper)
                ActiveGap.Inverted = true;   // former resistance reclaimed -> long
            else if (ActiveGap.IsBullish && bar.Close < ActiveGap.Lower)
                ActiveGap.Inverted = true;   // former support broken -> short
        }

        // Convenience accessors for the structure driver.
        public bool HasInvertedGap(bool isLong)
        {
            if (ActiveGap == null || !ActiveGap.Inverted) return false;
            // long wants a former-bearish gap now inverted; short the mirror.
            return isLong ? !ActiveGap.IsBullish : ActiveGap.IsBullish;
        }

        public double GapProximal(bool isLong)
        {
            if (ActiveGap == null) return 0;
            // proximal = the edge price re-enters from (entry reference)
            return isLong ? ActiveGap.Upper : ActiveGap.Lower;
        }

        public double GapDistal(bool isLong)
        {
            if (ActiveGap == null) return 0;
            return isLong ? ActiveGap.Lower : ActiveGap.Upper;
        }
    }
}
