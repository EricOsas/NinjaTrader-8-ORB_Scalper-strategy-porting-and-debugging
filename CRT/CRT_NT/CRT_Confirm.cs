using System;
using System.Collections.Generic;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // CRT_Confirm — LTF confirmation engine.
    //
    // Maintains a rolling window of CLOSED LTF candles collected since the
    // sweep began, and evaluates the two trigger primitives defined in
    // 01-STRATEGY-SPEC §5:
    //   • CISD  — Change in State of Delivery (close beyond the reference
    //             open of the pre-reversal same-delivery run)
    //   • IFVG  — an FVG (born during/after the sweep) closed fully through
    //             its far boundary
    //
    // One instance per live setup; Reset() when a new C1 is locked or the
    // setup is discarded.
    //======================================================================
    public class CRT_Confirm
    {
        private readonly List<Candle> ltf = new List<Candle>();
        private readonly List<FvgZone> fvgs = new List<FvgZone>();

        // Result of the most recent Evaluate()
        public bool Confirmed { get; private set; }
        public double ConfirmClose { get; private set; }
        public bool CisdOk { get; private set; }
        public bool IfvgOk { get; private set; }

        public void Reset()
        {
            ltf.Clear();
            fvgs.Clear();
            Confirmed = false;
            ConfirmClose = 0;
            CisdOk = false;
            IfvgOk = false;
        }

        public int BarCount => ltf.Count;

        // Push one CLOSED LTF candle, then (re)detect FVGs on the newest triplet.
        public void AddBar(Candle c)
        {
            ltf.Add(c);
            if (ltf.Count > 600) ltf.RemoveAt(0); // cap memory
            TrackFvg();
        }

        //------------------------------------------------------------------
        // FVG registration on the latest 3-candle triplet.
        //   Bullish FVG: c1.H < c3.L   → gap [c1.H (far), c3.L (near)]
        //   Bearish FVG: c1.L > c3.H   → gap [c1.L (far), c3.H (near)]
        //------------------------------------------------------------------
        private void TrackFvg()
        {
            int n = ltf.Count;
            if (n < 3) return;
            Candle c1 = ltf[n - 3], c3 = ltf[n - 1];

            if (c1.H < c3.L)
                fvgs.Add(new FvgZone { Bullish = true, Far = c1.H, Near = c3.L, BornT = c3.T });
            else if (c1.L > c3.H)
                fvgs.Add(new FvgZone { Bullish = false, Far = c1.L, Near = c3.H, BornT = c3.T });

            if (fvgs.Count > 200) fvgs.RemoveAt(0);
        }

        //------------------------------------------------------------------
        // CISD — close beyond the reference open of the pre-reversal run.
        //   Short (bias=Short, after C1_High sweep): find the up-close run
        //     that drove price up; reference open = SingleCandle → last
        //     up-close candle's open; ConsecutiveSequence → first candle's
        //     open in the uninterrupted up-close run. CISD when a later
        //     candle Close < referenceOpen.
        //   Long: mirror (down-close run below C1_Low; Close > referenceOpen).
        //------------------------------------------------------------------
        private bool DetectCisd(TradeBias bias, CisdRefMode mode, out double refOpen)
        {
            refOpen = 0;
            int n = ltf.Count;
            if (n < 2) return false;

            Candle last = ltf[n - 1]; // the prospective confirming (reversal) candle

            if (bias == TradeBias.Short)
            {
                // Find the end of the up-close run immediately before 'last'.
                int i = n - 2;
                if (i < 0 || !ltf[i].Bull) return false; // need an up-close run right before
                int runEnd = i;              // most recent up-close candle
                int runStart = i;            // walk back through consecutive up-close candles
                while (runStart - 1 >= 0 && ltf[runStart - 1].Bull) runStart--;

                refOpen = (mode == CisdRefMode.ConsecutiveSequence) ? ltf[runStart].O : ltf[runEnd].O;
                return last.C < refOpen;
            }
            else if (bias == TradeBias.Long)
            {
                int i = n - 2;
                if (i < 0 || !ltf[i].Bear) return false;
                int runEnd = i;
                int runStart = i;
                while (runStart - 1 >= 0 && ltf[runStart - 1].Bear) runStart--;

                refOpen = (mode == CisdRefMode.ConsecutiveSequence) ? ltf[runStart].O : ltf[runEnd].O;
                return last.C > refOpen;
            }
            return false;
        }

        //------------------------------------------------------------------
        // IFVG — an FVG (opposite to trade direction, born during the sweep)
        // whose FAR boundary the latest candle closes fully through.
        //   Short setup: a BULLISH FVG closed below its Far (c1.H).
        //   Long setup : a BEARISH FVG closed above its Far (c1.L).
        //------------------------------------------------------------------
        private bool DetectIfvg(TradeBias bias, DateTime sweepStart)
        {
            int n = ltf.Count;
            if (n < 1) return false;
            Candle last = ltf[n - 1];

            foreach (var g in fvgs)
            {
                if (g.Inverted) continue;
                if (g.BornT < sweepStart) continue; // only gaps born during/after the sweep

                if (bias == TradeBias.Short && g.Bullish && last.C < g.Far)
                {
                    g.Inverted = true;
                    return true;
                }
                if (bias == TradeBias.Long && !g.Bullish && last.C > g.Far)
                {
                    g.Inverted = true;
                    return true;
                }
            }
            return false;
        }

        //------------------------------------------------------------------
        // Evaluate the configured model on the current (latest) candle.
        // Call once per closed LTF bar, after AddBar().
        //------------------------------------------------------------------
        public bool Evaluate(TradeBias bias, EntryTriggerModel model, CisdRefMode refMode, DateTime sweepStart)
        {
            Confirmed = false;
            CisdOk = false;
            IfvgOk = false;
            if (bias == TradeBias.None || ltf.Count < 1) return false;

            double refOpen;
            CisdOk = DetectCisd(bias, refMode, out refOpen);
            IfvgOk = DetectIfvg(bias, sweepStart);

            switch (model)
            {
                case EntryTriggerModel.CISD:      Confirmed = CisdOk; break;
                case EntryTriggerModel.IFVG:      Confirmed = IfvgOk; break;
                case EntryTriggerModel.CISD_IFVG: Confirmed = CisdOk && IfvgOk; break;
            }

            if (Confirmed) ConfirmClose = ltf[ltf.Count - 1].C;
            return Confirmed;
        }
    }
}
