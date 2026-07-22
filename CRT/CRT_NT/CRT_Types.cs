using System;
using NinjaTrader.Cbi;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    // ── Enums ────────────────────────────────────────────────────────────
    public enum IntradayTF { M15, M30, H1, H2, H4 }

    public enum EntryTriggerModel { CISD, IFVG, CISD_IFVG }

    public enum CisdRefMode { SingleCandle, ConsecutiveSequence }

    public enum SlotType { Intraday, Daily, Weekly, Monthly }

    // Setup lifecycle per reference candle (C1)
    //   C2 is STRICTLY the manipulation candle — it never triggers/executes.
    //   The liquidity sweep can only occur in C2; execution only in C3.
    public enum SetupPhase
    {
        WaitC1,          // waiting for a C1 to close
        C2Watch,         // C1 locked; C2 forming — watch sweep + scan CISD/IFVG (provisional)
        C2ClosedArmed,   // C2 closed with valid bias — decide market/limit at C2-close / C3-open boundary
        C3Window,        // inside C3 — keep scanning trigger (if no C2 carry) / manage resting limit
        LimitWorking,    // a 1:1 limit is resting — PERSISTS beyond C3 close; dies on fill or 50% touch
        Filled,          // an entry filled — position live
        Done             // invalidated (50% taken) / TP hit / no valid setup
    }

    public enum TradeBias { None, Long, Short }

    // ── A closed candle (LTF or HTF) ─────────────────────────────────────
    public struct Candle
    {
        public DateTime T;
        public double O, H, L, C;
        public Candle(DateTime t, double o, double h, double l, double c) { T = t; O = o; H = h; L = l; C = c; }
        public bool Bull => C > O;
        public bool Bear => C < O;
        public double Mid => (H + L) * 0.5;
    }

    // ── Fair Value Gap zone (3-candle) ───────────────────────────────────
    public class FvgZone
    {
        public bool Bullish;      // bullish FVG (gap up) vs bearish FVG (gap down)
        public double Near;       // boundary nearest candle3 (entry side)
        public double Far;        // boundary nearest candle1 (inversion side)
        public DateTime BornT;    // time of candle3 (when the gap completed)
        public bool Inverted;     // set true once a candle closes through Far
    }

    // ── Per-slot CRT setup state ─────────────────────────────────────────
    public class CrtSetup
    {
        public int SlotIndex;
        public SlotType Type;
        public IntradayTF IntradayTf;   // only meaningful for Intraday
        public SetupPhase Phase = SetupPhase.WaitC1;

        // C1 range
        public DateTime C1Time;
        public double C1High, C1Low, C1EQ;
        public bool C1Locked;

        // C2 / sweep
        public DateTime C2OpenUTC, C2CloseUTC, C3OpenUTC, C3CloseUTC;
        public bool SweptHigh, SweptLow;
        // C2 (manipulation-candle) running extremes — the SL anchor lives here.
        // C2RunHigh = highest high of C2 (SL anchor for shorts);
        // C2RunLow  = lowest low  of C2 (SL anchor for longs). See SweepExtreme().
        public double C2RunHigh = double.MinValue, C2RunLow = double.MaxValue;

        public TradeBias Bias = TradeBias.None;
        public bool FiftyGuardDead;     // true if price already took 50% of C1 before entry

        // Trigger carry-over (a C2 confirmation is PROVISIONAL until the C2-close/C3-open boundary)
        public bool TriggerFired;
        public bool TriggerFiredInC2;   // provenance: did the trigger fire inside C2?
        public bool CarryToC3;
        public double ConfirmClose;     // close price of the confirming candle
        public double SlLevel;          // resolved SL — FIXED at the C2 extreme (C2_High/Low) ± buffer

        // Resting 1:1 limit lifecycle — persists beyond C3 close; only fill or a 50% touch ends it.
        public bool LimitResting;       // a 1:1 limit is currently working
        public double LimitPrice;       // its price = (C1_EQ + SlLevel)/2
        public bool Invalidated;        // set when price touches 50% (C1_EQ) before a fill
        public string InvalidReason = "";

        public string SessionKey = "";  // slot + C1 time (identity)

        // Per-setup sweep-scan start (UTC). Gates "FVG born during/after the
        // sweep" for IFVG detection. Rolling model → one value per lane.
        public DateTime SweepStartUTC = DateTime.MinValue;

        // Optional C1 displacement filter, evaluated at C1 lock against the
        // prior HTF candle. A bearish setup needs C2 to sweep C1_High then close
        // back inside; if C1 ITSELF closed ABOVE the prior candle's high there is
        // a bullish gap/displacement → C1 is invalid for shorts. Mirror for longs.
        public bool C1ValidBearish = true;   // false if C1 closed above prev high
        public bool C1ValidBullish = true;   // false if C1 closed below prev low

        // Rolling-model bookkeeping.
        public bool OrderPlaced;   // an entry has been submitted (guard vs double-entry)
        public bool Dead;          // lane fully complete/invalidated → prune

        public void ResetSweepScan()
        {
            SweptHigh = SweptLow = false;
            C2RunHigh = double.MinValue;
            C2RunLow = double.MaxValue;
            Bias = TradeBias.None;
            FiftyGuardDead = false;
            TriggerFired = false;
            TriggerFiredInC2 = false;
            CarryToC3 = false;
            ConfirmClose = 0;
            SlLevel = 0;
            LimitResting = false;
            LimitPrice = 0;
            Invalidated = false;
            InvalidReason = "";
            SweepStartUTC = DateTime.MinValue;
            OrderPlaced = false;
        }
    }

    // ── Active trade (one per concurrent lane; positions net at broker) ──
    public class ActiveTrade
    {
        public Order EntryOrder;
        public Order SlOrder;
        public Order TpOrder;
        public bool IsLong;
        public double EntryPrice;
        public DateTime EntryTime;
        public double SlPrice;
        public double TpPrice;
        public int Contracts;
        public int SlotIndex;
        public string SessionKey = "";
    }
}
