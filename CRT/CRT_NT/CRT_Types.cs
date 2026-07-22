// CRT_Types.cs — shared enums, value types, and the ActiveTrade record.
// See CRT/01-STRATEGY-SPEC.md and CRT/02-NT8-IMPLEMENTATION.md.
using System;
using NinjaTrader.Cbi;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    // ── Slot / timeframe model (strategy spec §2) ────────────────────────
    public enum SlotType { Intraday = 0, Daily = 1, Weekly = 2, Monthly = 3 }

    // Intraday sub-slot C1 timeframe (only the Intraday slot exposes this).
    public enum C1TF { M15 = 0, M30 = 1, H1 = 2, H2 = 3, H4 = 4 }

    // ── Trigger models (strategy spec §4–6) ──────────────────────────────
    public enum TriggerMode { CISD = 0, IFVG = 1, CISD_AND_IFVG = 2 }

    // CISD reference origin (strategy spec §5.3)
    public enum CISDMode { RunOrigin = 0, SingleCandle = 1 }

    public enum TriggerKind { None = 0, Cisd = 1, Ifvg = 2, Both = 3 }

    // ── Setup lifecycle (strategy spec §8) ───────────────────────────────
    public enum SetupState
    {
        Idle = 0,
        RangeLocked = 1,
        Swept = 2,
        Triggered = 3,
        WorkingLimit = 4,
        Live = 5,
        ClosedTP = 6,
        ClosedSL = 7,
        Invalid = 8,
        Expired = 9
    }

    // Minimal OHLC snapshot used by the CISD/FVG detectors so the logic is
    // testable independent of NinjaScript's BarsArray indexing.
    public struct Candle
    {
        public DateTime TimeUTC;
        public double Open, High, Low, Close;

        public bool IsBull => Close > Open;
        public bool IsBear => Close < Open;
        public bool IsDoji => Close == Open;

        public Candle(DateTime tUtc, double o, double h, double l, double c)
        {
            TimeUTC = tUtc; Open = o; High = h; Low = l; Close = c;
        }
    }

    //======================================================================
    // ActiveTrade — the single live/working CRT position (concurrency is
    // one-at-a-time globally, spec §9). Snapshot geometry is frozen at fill
    // exactly like ORB_NT so mid-trade input changes never move the stop.
    //======================================================================
    public class ActiveTrade
    {
        public Order EntryOrder { get; set; }
        public Order SlOrder { get; set; }
        public Order TpOrder { get; set; }
        public bool IsLong { get; set; }
        public double EntryPrice { get; set; }
        public DateTime EntryTime { get; set; }
        public double VirtualSL { get; set; }
        public double TpPrice { get; set; }          // = EQ of C1
        public double ManipExtreme { get; set; }      // SL anchor (spec §7.1)
        public bool TrailingActivated { get; set; }
        public bool BreakevenSet { get; set; }
        public int Contracts { get; set; }
        public string OcoGroup { get; set; }
        public int SlotIndex { get; set; }
        public string C1Key { get; set; }             // consumed-ledger identity

        // ── Snapshot geometry frozen at fill (ORB parity) ──
        public int SnapTrailMode { get; set; }        // 0=Continuous 1=Step
        public int SnapBehavior { get; set; }         // 0=Trail 1=BE-only 2=Off
        public double SnapThreshPrice { get; set; }
        public double SnapGapPrice { get; set; }
        public int SnapMinTrailSec { get; set; }
        public bool SnapSpreadComp { get; set; }
        public double SnapEntrySpread { get; set; }
        public double SnapBECostPrice { get; set; }
    }
}
