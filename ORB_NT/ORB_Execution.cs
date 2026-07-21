using System;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript.Strategies;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public enum TrailMode
    {
        Continuous = 0,  // trail per-tick after activation
        Step = 1         // re-lock only each full threshold advance
    }

    public static class ORB_Execution
    {
        // Faithful port of MT5 ManageTrailingStops() target computation.
        // All distances in PRICE units. Reads the trade's frozen snapshot
        // geometry; returns the new target SL, or 0 when no move is due.
        //
        //   Continuous: profit(bid-based) >= thresh → SL = price ∓ effGap,
        //               following every tick afterward.
        //   Step:       SL re-locks only per WHOLE threshold advance:
        //               steps = floor(profit / thresh) →
        //               SL = entry ± (steps*thresh − effGap).
        //   Spread comp: effGap = max(tick, gap − entrySpread) so the
        //               closeable (bid/ask) stop distance matches the chart gap.
        public static double ComputeTrailTarget(ActiveTrade t, double bid, double ask,
            double tickSize, DateTime nowUTC)
        {
            if (t == null || t.EntryPrice <= 0) return 0;
            if (t.SnapBehavior == 2) return 0; // Off

            double spread = Math.Max(0, ask - bid);
            double thresh = t.SnapThreshPrice;
            double gap = t.SnapGapPrice;
            if (thresh <= 0) return 0;

            // MIN-TRAIL gate: applies to ACTIVATION only; once trailing, keep following
            if (!t.TrailingActivated && t.SnapMinTrailSec > 0 &&
                (nowUTC - t.EntryTime).TotalSeconds < t.SnapMinTrailSec)
                return 0;

            // ── Breakeven-only: one move to entry ± costs, then hands-off ──
            if (t.SnapBehavior == 1)
            {
                if (t.BreakevenSet) return 0;
                double profBE = t.IsLong ? bid - t.EntryPrice : t.EntryPrice - bid;
                if (profBE < thresh) return 0;
                double cost = t.SnapSpreadComp ? spread + t.SnapBECostPrice : 0;
                return t.IsLong ? t.EntryPrice + cost : t.EntryPrice - cost;
            }

            // ── Full trailing ──
            double effGap = gap;
            double entrySpread = t.SnapEntrySpread > 0 ? t.SnapEntrySpread : spread;
            if (t.SnapSpreadComp) effGap = Math.Max(tickSize, gap - entrySpread);

            if (t.IsLong)
            {
                double profit = bid - t.EntryPrice;    // real closeable profit
                if (profit < thresh) return 0;

                double targetSL = bid - effGap;        // continuous follow
                if (t.SnapTrailMode == (int)TrailMode.Step)
                {
                    int steps = (int)Math.Floor(profit / thresh);
                    if (steps < 1) return 0;
                    targetSL = t.EntryPrice + (steps * thresh - effGap);
                }
                // Forward-only
                if (t.TrailingActivated && targetSL <= t.VirtualSL) return 0;
                if (!t.TrailingActivated && targetSL <= t.VirtualSL + tickSize) return 0;
                return targetSL;
            }
            else
            {
                double profit = t.EntryPrice - bid;
                if (profit < thresh) return 0;

                double targetSL = ask + effGap;
                if (t.SnapTrailMode == (int)TrailMode.Step)
                {
                    int steps = (int)Math.Floor(profit / thresh);
                    if (steps < 1) return 0;
                    targetSL = t.EntryPrice - (steps * thresh - effGap);
                }
                if (t.TrailingActivated && targetSL >= t.VirtualSL) return 0;
                if (!t.TrailingActivated && targetSL >= t.VirtualSL - tickSize) return 0;
                return targetSL;
            }
        }

        // Breakout entries (normal mode) or fade entries (Reverse_Orders mode,
        // MT5 parity: "sell high / buy low" — SELL LIMIT at rangeHigh, BUY
        // LIMIT at rangeLow). Returns (buySideOrder, sellSideOrder) — in
        // reverse mode the BUY order sits at the LOW and the SELL at the HIGH.
        public static (Order longOrder, Order shortOrder) PlacePendingEntryOCO(Strategy strategy, double rangeHigh, double rangeLow,
            int contracts, string ocoGroup, bool useStopLimit = true, bool reverseOrders = false)
        {
            Order longOrder, shortOrder;
            if (reverseOrders)
            {
                // Fade the range: buy the low, sell the high (plain limits).
                longOrder  = strategy.SubmitOrderUnmanaged(0, OrderAction.Buy,       OrderType.Limit, contracts, rangeLow,  0, ocoGroup, "LongEntry");
                shortOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.Limit, contracts, rangeHigh, 0, ocoGroup, "ShortEntry");
            }
            else if (useStopLimit)
            {
                // StopLimit: stop triggers at the level, limit = same level.
                // BUY: fills only when Ask <= RangeHigh (i.e. Bid has genuinely reached the level).
                // SELL: fills only when Bid >= RangeLow (i.e. Ask has genuinely reached the level).
                // Risk: on a fast spike-through the limit may not be hit and the fill is missed.
                longOrder  = strategy.SubmitOrderUnmanaged(0, OrderAction.Buy,       OrderType.StopLimit,  contracts, rangeHigh, rangeHigh, ocoGroup, "LongEntry");
                shortOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.StopLimit,  contracts, rangeLow,  rangeLow,  ocoGroup, "ShortEntry");
            }
            else
            {
                // StopMarket: guaranteed fill on breakout, pays the spread on entry.
                longOrder  = strategy.SubmitOrderUnmanaged(0, OrderAction.Buy,       OrderType.StopMarket, contracts, 0, rangeHigh, ocoGroup, "LongEntry");
                shortOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.StopMarket, contracts, 0, rangeLow,  ocoGroup, "ShortEntry");
            }
            return (longOrder, shortOrder);
        }

        // Single-side pending entry — used when the consumed-ledger blocks one
        // side (already triggered this session) but the other must still arm.
        public static Order PlacePendingEntrySide(Strategy strategy, bool buySide, double level,
            int contracts, string ocoGroup, bool useStopLimit, bool reverseOrders)
        {
            if (reverseOrders)
            {
                // Fade mode: BUY LIMIT at the low, SELL LIMIT at the high
                return buySide
                    ? strategy.SubmitOrderUnmanaged(0, OrderAction.Buy,       OrderType.Limit, contracts, level, 0, ocoGroup, "LongEntry")
                    : strategy.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.Limit, contracts, level, 0, ocoGroup, "ShortEntry");
            }
            if (useStopLimit)
            {
                return buySide
                    ? strategy.SubmitOrderUnmanaged(0, OrderAction.Buy,       OrderType.StopLimit, contracts, level, level, ocoGroup, "LongEntry")
                    : strategy.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.StopLimit, contracts, level, level, ocoGroup, "ShortEntry");
            }
            return buySide
                ? strategy.SubmitOrderUnmanaged(0, OrderAction.Buy,       OrderType.StopMarket, contracts, 0, level, ocoGroup, "LongEntry")
                : strategy.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.StopMarket, contracts, 0, level, ocoGroup, "ShortEntry");
        }

        // Limit price for a protective stop when a hard slip cap is in force.
        //   slSlipCapPoints <= 0  → 0  (caller submits a plain StopMarket).
        //   Long  position  → Sell stop: accept fills down to stop − cap.
        //   Short position  → BuyToCover stop: accept fills up to stop + cap.
        // Returning 0 signals "no limit / market". Any positive value makes the
        // stop a StopLimit whose worst fill is bounded — never a market order.
        public static double SlLimitPrice(bool isLong, double stopPrice, double slSlipCapPoints,
            NinjaTrader.Cbi.MasterInstrument mi)
        {
            if (slSlipCapPoints <= 0) return 0;
            double lim = isLong ? stopPrice - slSlipCapPoints : stopPrice + slSlipCapPoints;
            return mi.RoundToTickSize(lim);
        }

        // slSlipCapPoints > 0  → the protective stop is submitted as a StopLimit
        //   capped at that many points of slippage (no market fallback).
        // slSlipCapPoints == 0 → legacy StopMarket (guaranteed exit, pays slip).
        public static (Order slOrder, Order tpOrder) PlaceBracketOrders(Strategy strategy, bool isLong, double fillPrice, int contracts, double slDistancePoints, double tpDistancePoints, string ocoGroup, double slSlipCapPoints = 0)
        {
            // Custom-point distances (e.g. 0.01-based on a 0.10-tick contract)
            // can land off the exchange grid — always snap to the REAL tick.
            var mi = strategy.Instrument.MasterInstrument;
            Order slOrder, tpOrder;
            if (isLong)
            {
                double slPrice = mi.RoundToTickSize(fillPrice - slDistancePoints);
                double tpPrice = mi.RoundToTickSize(fillPrice + tpDistancePoints);
                double slLimit = SlLimitPrice(true, slPrice, slSlipCapPoints, mi);
                slOrder = slLimit > 0
                    ? strategy.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.StopLimit, contracts, slLimit, slPrice, ocoGroup, "LongSL")
                    : strategy.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.StopMarket, contracts, 0, slPrice, ocoGroup, "LongSL");
                tpOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.Limit, contracts, tpPrice, 0, ocoGroup, "LongTP");
            }
            else
            {
                double slPrice = mi.RoundToTickSize(fillPrice + slDistancePoints);
                double tpPrice = mi.RoundToTickSize(fillPrice - tpDistancePoints);
                double slLimit = SlLimitPrice(false, slPrice, slSlipCapPoints, mi);
                slOrder = slLimit > 0
                    ? strategy.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.StopLimit, contracts, slLimit, slPrice, ocoGroup, "ShortSL")
                    : strategy.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.StopMarket, contracts, 0, slPrice, ocoGroup, "ShortSL");
                tpOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.Limit, contracts, tpPrice, 0, ocoGroup, "ShortTP");
            }
            return (slOrder, tpOrder);
        }

    }
}
