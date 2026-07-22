using System;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript.Strategies;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // CRT_Execution — order placement. NO OCO, NO trailing (per spec).
    //   • Market entry when >= 1:1 reward available at the confirming close.
    //   • Otherwise a single 1:1 LIMIT at (C1_EQ ∓ risk).
    //   • On fill, a static SL (sweep wick ± buffer) + TP (C1_EQ) bracket.
    //======================================================================
    public static class CRT_Execution
    {
        public struct EntryPlan
        {
            public bool Skip;        // 50% guard or un-placeable stop
            public bool UseLimit;    // false = market, true = 1:1 limit
            public double EntryRef;  // market ref (confirm close) or limit price
            public double SlPrice;
            public double TpPrice;   // = C1_EQ
            public double RiskPrice; // |entry - sl| in price
            public string SkipReason;
        }

        // Build the entry plan from a confirmed setup.
        //   bias      : Long / Short
        //   confirmPx : close of the confirming candle (market ref)
        //   c1Eq      : take-profit level
        //   sweepExt  : manipulation-leg extreme (sweep wick)
        //   bufferPx  : SL buffer in price units
        //   priceNow  : current price (for the 50% guard)
        //   minStopPx : broker/exchange min stop distance (0 for futures usually)
        public static EntryPlan BuildPlan(TradeBias bias, double confirmPx, double c1Eq,
            double sweepExt, double bufferPx, double priceNow, double minStopPx,
            NinjaTrader.Cbi.MasterInstrument mi)
        {
            var p = new EntryPlan();
            bool isLong = bias == TradeBias.Long;

            // SL just past the sweep wick.
            double sl = isLong ? sweepExt - bufferPx : sweepExt + bufferPx;
            sl = mi.RoundToTickSize(sl);

            // 50% guard — price already reached EQ on the trade side.
            if ((isLong && priceNow >= c1Eq) || (!isLong && priceNow <= c1Eq))
            {
                p.Skip = true; p.SkipReason = "50% already taken"; return p;
            }

            double riskAtMarket = Math.Abs(confirmPx - sl);
            double rewardAtMarket = Math.Abs(c1Eq - confirmPx);
            if (riskAtMarket <= 0) { p.Skip = true; p.SkipReason = "zero risk distance"; return p; }

            if (rewardAtMarket >= riskAtMarket)
            {
                // >= 1:1 at market — enter now.
                p.UseLimit = false;
                p.EntryRef = confirmPx;
                p.SlPrice = sl;
                p.TpPrice = c1Eq;
                p.RiskPrice = riskAtMarket;
            }
            else
            {
                // Place a 1:1 limit: entry such that |EQ - entry| == |entry - sl|.
                // With a fixed SL level, solve entry so reward == risk:
                //   long : entry = (c1Eq + sl) / 2   (midpoint gives equal legs)
                //   short: entry = (c1Eq + sl) / 2
                double limit = mi.RoundToTickSize((c1Eq + sl) * 0.5);

                // Safety: the limit must sit between current price and EQ on the
                // trade side, otherwise the 50% guard would cancel it instantly.
                p.UseLimit = true;
                p.EntryRef = limit;
                p.SlPrice = sl;
                p.TpPrice = c1Eq;
                p.RiskPrice = Math.Abs(limit - sl);
            }

            // Un-placeable stop (inside min-stop distance) → skip.
            if (minStopPx > 0 && Math.Abs(p.EntryRef - p.SlPrice) < minStopPx)
            {
                p.Skip = true; p.SkipReason = "SL inside min-stop distance";
            }
            return p;
        }

        // Submit the entry order (unmanaged). Returns the order.
        public static Order SubmitEntry(Strategy s, TradeBias bias, EntryPlan plan, int contracts,
            string sessionKey)
        {
            bool isLong = bias == TradeBias.Long;
            string tag = "CRT_" + sessionKey;

            if (!plan.UseLimit)
            {
                return isLong
                    ? s.SubmitOrderUnmanaged(0, OrderAction.Buy, OrderType.Market, contracts, 0, 0, "", tag)
                    : s.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.Market, contracts, 0, 0, "", tag);
            }
            return isLong
                ? s.SubmitOrderUnmanaged(0, OrderAction.Buy, OrderType.Limit, contracts, plan.EntryRef, 0, "", tag)
                : s.SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.Limit, contracts, plan.EntryRef, 0, "", tag);
        }

        // Static SL + TP bracket on fill (no OCO group — managed manually).
        public static (Order sl, Order tp) PlaceBracket(Strategy s, bool isLong, int contracts,
            double slPrice, double tpPrice, string sessionKey)
        {
            var mi = s.Instrument.MasterInstrument;
            slPrice = mi.RoundToTickSize(slPrice);
            tpPrice = mi.RoundToTickSize(tpPrice);
            Order sl, tp;
            if (isLong)
            {
                sl = s.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.StopMarket, contracts, 0, slPrice, "", "CRT_SL_" + sessionKey);
                tp = s.SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.Limit, contracts, tpPrice, 0, "", "CRT_TP_" + sessionKey);
            }
            else
            {
                sl = s.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.StopMarket, contracts, 0, slPrice, "", "CRT_SL_" + sessionKey);
                tp = s.SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.Limit, contracts, tpPrice, 0, "", "CRT_TP_" + sessionKey);
            }
            return (sl, tp);
        }
    }
}
