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
    public enum SetupPhase
    {
        WaitC1,          // waiting for a C1 to close
        C2Watch,         // C1 locked; C2 forming — watch sweep + scan CISD/IFVG
        C2ClosedArmed,   // C2 closed with valid bias — ready to place at C3 open (carry-over)
        C3Window,        // inside C3 — keep scanning trigger / manage resting limit
        Filled,          // an entry filled — position live
        Done             // window ended / invalidated / TP hit
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
        public double ManipExtreme;     // highest high (short) / lowest low (long) of the sweep leg
        public double C2RunHigh = double.MinValue, C2RunLow = double.MaxValue;

        public TradeBias Bias = TradeBias.None;
        public bool FiftyGuardDead;     // true if price already took 50% of C1 before entry

        // Trigger carry-over
        public bool TriggerFired;
        public bool CarryToC3;
        public double ConfirmClose;     // close price of the confirming candle
        public double SlLevel;          // resolved SL (sweep extreme +/- buffer)

        public string SessionKey = "";  // slot + C1 time (identity)

        public void ResetSweepScan()
        {
            SweptHigh = SweptLow = false;
            ManipExtreme = 0;
            C2RunHigh = double.MinValue;
            C2RunLow = double.MaxValue;
            Bias = TradeBias.None;
            FiftyGuardDead = false;
            TriggerFired = false;
            CarryToC3 = false;
            ConfirmClose = 0;
            SlLevel = 0;
        }
    }

    // ── Active trade (single, global) ────────────────────────────────────
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
