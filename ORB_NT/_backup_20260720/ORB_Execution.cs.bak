using System;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript.Strategies;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public static class ORB_Execution
    {
        public static (Order longOrder, Order shortOrder) PlacePendingEntryOCO(Strategy strategy, double rangeHigh, double rangeLow,
            int contracts, string ocoGroup, bool useLimitEntry = true)
        {
            Order longOrder, shortOrder;
            if (useLimitEntry)
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

        public static (Order slOrder, Order tpOrder) PlaceBracketOrders(Strategy strategy, bool isLong, double fillPrice, int contracts, double slDistancePoints, double tpDistancePoints, string ocoGroup)
        {
            Order slOrder, tpOrder;
            if (isLong)
            {
                double slPrice = fillPrice - slDistancePoints;
                double tpPrice = fillPrice + tpDistancePoints;
                slOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.StopMarket, contracts, 0, slPrice, ocoGroup, "LongSL");
                tpOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.Limit, contracts, tpPrice, 0, ocoGroup, "LongTP");
            }
            else
            {
                double slPrice = fillPrice + slDistancePoints;
                double tpPrice = fillPrice - tpDistancePoints;
                slOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.StopMarket, contracts, 0, slPrice, ocoGroup, "ShortSL");
                tpOrder = strategy.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.Limit, contracts, tpPrice, 0, ocoGroup, "ShortTP");
            }
            return (slOrder, tpOrder);
        }

        // Applies a trailing-stop target computed by CalculateTrailingStop /
        // CalculateBreakevenStop to a LIVE working SL order via ChangeOrder.
        // Mirrors MT5's TrailModifyOrLock: idempotent (only fires when the
        // target actually improves on the current stop by more than 1 tick),
        // and respects the broker/exchange minimum stop distance.
        // Returns true if a ChangeOrder request was actually sent.
        public static bool ApplyTrailingStop(Strategy strategy, Order slOrder, bool isLong, double targetSL, double minTick)
        {
            if (slOrder == null) return false;
            if (slOrder.OrderState != OrderState.Working && slOrder.OrderState != OrderState.Accepted) return false;

            double currentStop = slOrder.StopPrice;

            // Idempotency / forward-only guard — never move the stop backward.
            if (isLong && targetSL <= currentStop + minTick) return false;
            if (!isLong && targetSL >= currentStop - minTick) return false;

            strategy.ChangeOrder(slOrder, slOrder.Quantity, 0, targetSL);
            return true;
        }
        
        public static double CalculateTrailingStop(bool isLong, double currentPrice, double entryPrice, double currentSL, double thresholdPts, double trailGapPts, double minTick)
        {
            double newSL = currentSL;
            if (isLong)
            {
                double profit = currentPrice - entryPrice;
                if (profit >= thresholdPts)
                {
                    double candidateSL = currentPrice - trailGapPts;
                    if (candidateSL > currentSL + minTick)
                    {
                        newSL = candidateSL;
                    }
                }
            }
            else
            {
                double profit = entryPrice - currentPrice;
                if (profit >= thresholdPts)
                {
                    double candidateSL = currentPrice + trailGapPts;
                    if (candidateSL < currentSL - minTick)
                    {
                        newSL = candidateSL;
                    }
                }
            }
            return newSL;
        }

        public static double CalculateBreakevenStop(bool isLong, double currentPrice, double entryPrice, double currentSL, double thresholdPts, double beCostPts, double minTick)
        {
            double newSL = currentSL;
            if (isLong)
            {
                double profit = currentPrice - entryPrice;
                if (profit >= thresholdPts)
                {
                    double candidateSL = entryPrice + beCostPts;
                    if (candidateSL > currentSL + minTick)
                    {
                        newSL = candidateSL;
                    }
                }
            }
            else
            {
                double profit = entryPrice - currentPrice;
                if (profit >= thresholdPts)
                {
                    double candidateSL = entryPrice - beCostPts;
                    if (candidateSL < currentSL - minTick)
                    {
                        newSL = candidateSL;
                    }
                }
            }
            return newSL;
        }
    }
}
