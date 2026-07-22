using System;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // CRT_Structure — pure helpers for the C1→C2→C3 model. Stateless; all
    // state lives on the CrtSetup instance owned by the strategy.
    //======================================================================
    public static class CRT_Structure
    {
        // Lock a freshly-closed HTF candle as C1.
        public static void LockC1(CrtSetup s, Candle c1, string sessionKey)
        {
            s.C1Time = c1.T;
            s.C1High = c1.H;
            s.C1Low = c1.L;
            s.C1EQ = (c1.H + c1.L) * 0.5;
            s.C1Locked = true;
            s.SessionKey = sessionKey;
            s.ResetSweepScan();
            s.Phase = SetupPhase.C2Watch;
        }

        // Update the running C2 extreme and sweep flags from a forming LTF bar
        // (or the C2 HTF bar itself). Returns true if a NEW sweep was detected.
        public static bool UpdateSweep(CrtSetup s, double high, double low)
        {
            bool newlySwept = false;
            if (high > s.C2RunHigh) s.C2RunHigh = high;
            if (low < s.C2RunLow) s.C2RunLow = low;

            if (!s.SweptHigh && s.C2RunHigh > s.C1High) { s.SweptHigh = true; newlySwept = true; }
            if (!s.SweptLow && s.C2RunLow < s.C1Low)   { s.SweptLow = true; newlySwept = true; }

            // Track the manipulation-leg extreme on the swept side (used for SL).
            if (s.SweptHigh) s.ManipExtreme = Math.Max(s.ManipExtreme <= 0 ? double.MinValue : s.ManipExtreme, s.C2RunHigh);
            if (s.SweptLow)
                s.ManipExtreme = (s.ManipExtreme <= 0) ? s.C2RunLow : Math.Min(s.ManipExtreme, s.C2RunLow);

            return newlySwept;
        }

        // Determine bias from C2's CLOSE relative to C1 (close-back-inside).
        //   High swept + close back below C1_High → SHORT
        //   Low  swept + close back above C1_Low  → LONG
        //   Close beyond the swept extreme        → invalid (breakout)
        // If both sides swept (outside bar), prefer the side that closed back in.
        public static TradeBias BiasFromC2Close(CrtSetup s, double c2Close)
        {
            bool shortValid = s.SweptHigh && c2Close < s.C1High;
            bool longValid = s.SweptLow && c2Close > s.C1Low;

            if (shortValid && longValid)
            {
                // Outside bar closing back inside both — trade the side price last
                // returned from (nearest swept extreme to the close).
                double distHigh = Math.Abs(s.C1High - c2Close);
                double distLow = Math.Abs(c2Close - s.C1Low);
                return distHigh < distLow ? TradeBias.Short : TradeBias.Long;
            }
            if (shortValid) return TradeBias.Short;
            if (longValid) return TradeBias.Long;
            return TradeBias.None; // breakout / no valid close-back-inside
        }

        // The sweep-leg extreme used for the stop (highest high for shorts,
        // lowest low for longs).
        public static double SweepExtreme(CrtSetup s)
        {
            return s.Bias == TradeBias.Short ? s.C2RunHigh : s.C2RunLow;
        }

        // 50% guard: has price already reached C1_EQ on the eventual trade side?
        public static bool FiftyTaken(CrtSetup s, double priceHigh, double priceLow)
        {
            if (s.Bias == TradeBias.Short) return priceLow <= s.C1EQ;   // dropped to EQ already
            if (s.Bias == TradeBias.Long)  return priceHigh >= s.C1EQ;  // rose to EQ already
            return false;
        }
    }
}
