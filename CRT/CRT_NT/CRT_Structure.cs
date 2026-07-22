using System;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // CRT_Structure — pure helpers for the C1→C2→C3 model. Stateless; all
    // state lives on the CrtSetup instance owned by the strategy.
    //======================================================================
    public static class CRT_Structure
    {
        // Lock a freshly-closed HTF candle as C1. 'prev' is the HTF candle
        // immediately before C1, used for the optional displacement filter.
        public static void LockC1(CrtSetup s, Candle c1, Candle prev, string sessionKey)
        {
            s.C1Time = c1.T;
            s.C1High = c1.H;
            s.C1Low = c1.L;
            s.C1EQ = (c1.H + c1.L) * 0.5;
            s.C1Locked = true;
            s.SessionKey = sessionKey;
            s.ResetSweepScan();

            // Directional displacement validity vs the prior candle:
            //   C1 closed ABOVE prev.High → bullish gap → invalid for SHORTS.
            //   C1 closed BELOW prev.Low  → bearish gap → invalid for LONGS.
            s.C1ValidBearish = !(c1.C > prev.H);
            s.C1ValidBullish = !(c1.C < prev.L);

            s.Phase = SetupPhase.C2Watch;
        }

        // Optional C1 displacement filter gate for a resolved bias. Only
        // consulted by the strategy when the filter input is enabled.
        public static bool C1FilterAllows(CrtSetup s, TradeBias bias)
        {
            if (bias == TradeBias.Short) return s.C1ValidBearish;
            if (bias == TradeBias.Long)  return s.C1ValidBullish;
            return false;
        }

        // Update the running C2 extreme and sweep flags from a forming LTF bar
        // (or the C2 HTF bar itself). The sweep can ONLY occur in C2 — this must
        // never be called during the C3 window. Returns true if a NEW sweep was
        // detected. The C2 extreme tracked here (C2RunHigh / C2RunLow) is the
        // FIXED anchor for the SL (§7) and is independent of the 50% calc.
        public static bool UpdateSweep(CrtSetup s, double high, double low)
        {
            bool newlySwept = false;
            if (high > s.C2RunHigh) s.C2RunHigh = high;
            if (low < s.C2RunLow) s.C2RunLow = low;

            if (!s.SweptHigh && s.C2RunHigh > s.C1High) { s.SweptHigh = true; newlySwept = true; }
            if (!s.SweptLow && s.C2RunLow < s.C1Low)   { s.SweptLow = true; newlySwept = true; }

            // The manipulation-candle extreme on the swept side (used verbatim as
            // the SL anchor). For an eventual short it is the highest high; for a
            // long it is the lowest low. Bias is resolved at C2 close, so we keep
            // both running extremes and pick the correct one in SweepExtreme().
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

        // The C2 (manipulation-candle) extreme used as the FIXED SL anchor:
        // highest high for shorts, lowest low for longs. This is the farthest
        // C2 reached before closing back inside C1. It is INDEPENDENT of the 50%
        // calc — C1_EQ never uses this value.
        public static double SweepExtreme(CrtSetup s)
        {
            return s.Bias == TradeBias.Short ? s.C2RunHigh : s.C2RunLow;
        }

        // Resolve the actual SL price = C2 extreme ± buffer (short: above the
        // high; long: below the low). bufferPx is in price units.
        public static double SlFromC2Extreme(CrtSetup s, double bufferPx)
        {
            double ext = SweepExtreme(s);
            return s.Bias == TradeBias.Short ? ext + bufferPx : ext - bufferPx;
        }

        // 50% guard / invalidation trigger: has price reached C1_EQ (50% of C1)
        // on the trade side? Live for the ENTIRE setup life, including while a
        // 1:1 limit rests after C3 close. A true result invalidates the setup.
        public static bool FiftyTaken(CrtSetup s, double priceHigh, double priceLow)
        {
            if (s.Bias == TradeBias.Short) return priceLow <= s.C1EQ;   // dropped to EQ already
            if (s.Bias == TradeBias.Long)  return priceHigh >= s.C1EQ;  // rose to EQ already
            return false;
        }
    }
}
