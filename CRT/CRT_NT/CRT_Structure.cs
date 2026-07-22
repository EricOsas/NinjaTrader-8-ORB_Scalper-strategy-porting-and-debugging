// CRT_Structure.cs — the core Candle Range Theory state machine.
// Platform-agnostic logic described in CRT/01-STRATEGY-SPEC.md §3-§6.
// This module is HTF-driven (Candle 1 = reference range) and consumes LTF bars
// for the CISD / IFVG confirmation. It holds NO NinjaScript API calls so the
// same logic can be mirrored 1:1 into MQL5 (CRT_Structure.mqh).
using System;
using System.Collections.Generic;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    // Phase of a single CRT setup as it develops across C1 -> C2 -> C3.
    public enum CrtPhase
    {
        Idle,            // no reference range yet
        RangeSet,        // C1 range captured, waiting for C2 to sweep a side
        Swept,           // C2 has purged one side of C1, waiting for CISD/IFVG on LTF
        Armed,           // confirmation printed, entry order working
        InTrade,         // position live (handled by execution module)
        Done             // setup resolved (filled+closed or invalidated)
    }

    public enum SweepSide
    {
        None,
        High,   // C2 purged C1 high -> look for SHORT (bearish CRT)
        Low     // C2 purged C1 low  -> look for LONG  (bullish CRT)
    }

    // Immutable snapshot of the Candle 1 reference range.
    public class CrtRange
    {
        public DateTime C1OpenTime;   // slot-open timestamp of the reference candle
        public DateTime C1CloseTime;  // when C1 closed / C2 window opened
        public DateTime C2CloseTime;  // when C2 window closes / C3 window opens
        public double High;           // C1 high  (the "1.0" line on the chart)
        public double Low;            // C1 low   (the "0.0" line)
        public double Mid;            // 0.5 equilibrium
        public double Range;          // High - Low

        public double Eq { get { return (High + Low) * 0.5; } }
    }

    // One evolving CRT setup. There is at most ONE non-Done setup at a time
    // (global one-active-trade concurrency, per user decision).
    public class CrtSetup
    {
        public CrtPhase Phase = CrtPhase.Idle;
        public SweepSide Sweep = SweepSide.None;
        public bool IsLong;                 // derived from Sweep (Low->long, High->short)

        public CrtRange Range;

        // Manipulation extreme = the furthest point C2 reached beyond C1 on the swept
        // side. This is the protected swing -> stop-loss anchor.
        public double ManipulationExtreme;

        // CISD / IFVG confirmation levels captured on the LTF.
        public double CisdLevel;            // close-through level that confirms intent
        public bool CisdConfirmed;
        public double IfvgProximal;         // inverted-FVG near edge (entry reference)
        public double IfvgDistal;           // inverted-FVG far edge
        public bool IfvgConfirmed;

        // Resolved order parameters once Armed.
        public double PlannedEntry;
        public double PlannedStop;
        public double PlannedTarget;        // primary TP (opposite C1 boundary by default)

        public string SlotName = "";        // Intraday/Daily/Weekly/Monthly for dashboard
        public DateTime ArmedTime;

        public void Reset()
        {
            Phase = CrtPhase.Idle;
            Sweep = SweepSide.None;
            IsLong = false;
            Range = null;
            ManipulationExtreme = 0;
            CisdLevel = 0; CisdConfirmed = false;
            IfvgProximal = 0; IfvgDistal = 0; IfvgConfirmed = false;
            PlannedEntry = PlannedStop = PlannedTarget = 0;
            ArmedTime = DateTime.MinValue;
        }
    }

    // Detection helpers. Pure functions where possible so they port cleanly.
    public static class CrtStructure
    {
        // --- Phase 1: capture the C1 reference range -----------------------------
        // Called when a C1 slot candle has just CLOSED. highs/lows are the C1 OHLC.
        public static CrtRange BuildRange(DateTime c1Open, DateTime c1Close, DateTime c2Close,
                                          double high, double low)
        {
            return new CrtRange
            {
                C1OpenTime = c1Open,
                C1CloseTime = c1Close,
                C2CloseTime = c2Close,
                High = high,
                Low = low,
                Mid = (high + low) * 0.5,
                Range = high - low
            };
        }

        // --- Phase 2: sweep / purge detection during C2 --------------------------
        // Returns which side (if any) has been purged by the given bar extreme.
        // A purge requires trading BEYOND the C1 boundary (strict), configurable
        // buffer in ticks handled by caller.
        public static SweepSide DetectSweep(CrtRange r, double barHigh, double barLow,
                                            double bufferPrice)
        {
            if (r == null) return SweepSide.None;
            if (barHigh > r.High + bufferPrice) return SweepSide.High; // -> short bias
            if (barLow < r.Low - bufferPrice) return SweepSide.Low;   // -> long bias
            return SweepSide.None;
        }

        // --- Phase 3: CISD (Change In State of Delivery) on the LTF --------------
        // Bearish CISD (after a HIGH sweep): an LTF candle CLOSES below the low of
        // the up-move that made the high (approximated by prevSwingLow level supplied
        // by the caller's rolling tracker). Bullish CISD is the mirror.
        public static bool IsCisd(bool isLong, double ltfClose, double cisdLevel)
        {
            if (cisdLevel <= 0) return false;
            return isLong ? ltfClose > cisdLevel   // bullish: close back above the down-move origin
                          : ltfClose < cisdLevel;  // bearish: close back below the up-move origin
        }

        // --- Phase 3b: IFVG (Inverted Fair Value Gap) confirmation ---------------
        // An FVG is a 3-candle imbalance. It becomes "inverted" when price closes
        // through it in the opposite direction, turning it into a support/resistance
        // that we use as the entry zone. Returns true when the supplied LTF close
        // inverts the tracked gap in the trade direction.
        public static bool IsIfvgInverted(bool isLong, double ltfClose,
                                          double gapProximal, double gapDistal)
        {
            if (gapProximal <= 0 || gapDistal <= 0) return false;
            // For a long we need a former bearish FVG (gap below) to be reclaimed:
            // price closes above the gap's upper (proximal) edge.
            // For a short, mirror.
            return isLong ? ltfClose > Math.Max(gapProximal, gapDistal)
                          : ltfClose < Math.Min(gapProximal, gapDistal);
        }

        // --- Phase 4: resolve order params once confirmed ------------------------
        // Entry: default = IFVG proximal edge (or CISD level if IFVG disabled).
        // Stop : beyond the manipulation extreme + buffer.
        // Target: opposite C1 boundary (bullish -> C1 high; bearish -> C1 low),
        //         with optional 0.5 equilibrium partial handled by execution module.
        public static void ResolveOrder(CrtSetup s, double entry, double stopBuffer)
        {
            s.PlannedEntry = entry;
            if (s.IsLong)
            {
                s.PlannedStop = s.ManipulationExtreme - stopBuffer;
                s.PlannedTarget = s.Range.High;
            }
            else
            {
                s.PlannedStop = s.ManipulationExtreme + stopBuffer;
                s.PlannedTarget = s.Range.Low;
            }
        }
    }
}
