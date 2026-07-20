#region Using declarations
using System;
using System.Collections.Generic;
using System.Text;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
#endregion

//
// ORB_NT.cs — Main strategy class
// Replaces: OnInit, OnTick, OnTimer, OnDeinit, OnTradeTransaction
//
namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    //======================================================================
    // Drawdown Tracker — Tradeify EOD trailing drawdown enforcement
    //======================================================================
    public class DrawdownTracker
    {
        private double startingBalance;
        private double drawdownAmount;   // Firm-specific drawdown for account size
        private double highestEODBalance;
        private bool isFloorLocked;

        public double CurrentFloor { get; private set; }
        public bool IsFloorLocked => isFloorLocked;
        public double HighestEODBalance => highestEODBalance;

        public DrawdownTracker(double startingBalance, double drawdownAmount)
        {
            this.startingBalance = startingBalance;
            this.drawdownAmount = drawdownAmount;
            this.highestEODBalance = startingBalance;
            this.CurrentFloor = startingBalance - drawdownAmount;
            this.isFloorLocked = false;
        }

        /// <summary>
        /// Call once per day at 4:59 PM ET (session close) with end-of-day account balance.
        /// </summary>
        public void OnDayClose(double endOfDayBalance)
        {
            if (isFloorLocked) return; // Floor is permanently locked, no more movement

            if (endOfDayBalance > highestEODBalance)
            {
                highestEODBalance = endOfDayBalance;
                CurrentFloor = highestEODBalance - drawdownAmount;

                // Lock check: once highestEOD >= startingBalance + drawdownAmount + 100,
                // floor locks permanently at startingBalance + 100 per Tradeify rules.
                if (highestEODBalance >= startingBalance + drawdownAmount + 100.0)
                {
                    isFloorLocked = true;
                    CurrentFloor = startingBalance + 100.0;
                }
            }
        }

        /// <summary>
        /// Call on every tick with live account cash value.
        /// Returns true if the account is in breach and must be halted.
        /// </summary>
        public bool IsBreach(double liveCashValue)
        {
            return liveCashValue < CurrentFloor;
        }
    }

    //======================================================================
    // Consistency Tracker — Tradeify 40% single-day profit rule
    //======================================================================
    public class ConsistencyTracker
    {
        private Dictionary<DateTime, double> dailyPnL = new Dictionary<DateTime, double>();
        private double evalTarget;

        public bool IsConsistencyWarning { get; private set; }
        public double ConsistencyPctOfTotal { get; private set; }
        public double TotalProfit => ComputeTotalProfit();

        public ConsistencyTracker(double evalTarget)
        {
            this.evalTarget = evalTarget;
        }

        public void RecordTrade(DateTime tradeDate, double pnl)
        {
            DateTime key = tradeDate.Date;
            if (!dailyPnL.ContainsKey(key))
                dailyPnL[key] = 0;
            dailyPnL[key] += pnl;
            Refresh();
        }

        private double ComputeTotalProfit()
        {
            double total = 0;
            foreach (var kv in dailyPnL) total += kv.Value;
            return total;
        }

        private void Refresh()
        {
            double total = ComputeTotalProfit();
            if (total <= 0) { ConsistencyPctOfTotal = 0; IsConsistencyWarning = false; return; }

            double maxSingleDay = 0;
            foreach (var kv in dailyPnL)
                if (kv.Value > maxSingleDay) maxSingleDay = kv.Value;

            ConsistencyPctOfTotal = (maxSingleDay / total) * 100.0;
            // Warn at 32% (approaching the hard 40% cap)
            IsConsistencyWarning = (ConsistencyPctOfTotal > 32.0);
        }
    }

    //======================================================================
    // Fast Trade Tracker — Tradeify anti-HFT >50% held <10s rule
    //======================================================================
    public class FastTradeTracker
    {
        private int totalTrades = 0;
        private int fastTrades = 0;
        private double totalProfit = 0;
        private double fastProfit = 0;

        public int TotalTrades => totalTrades;
        public double FastTradePct { get; private set; }
        public bool IsFastTradeWarning => FastTradePct > 45.0; // warn at 45%

        public void RecordTrade(double holdSeconds, double pnl)
        {
            totalTrades++;
            totalProfit += pnl;
            bool isFast = holdSeconds < 10.0;
            if (isFast) { fastTrades++; fastProfit += pnl; }

            if (totalTrades > 0)
                FastTradePct = ((double)fastTrades / totalTrades) * 100.0;
        }
    }

    //======================================================================
    // Trade Record — per-position state managed in unmanaged approach
    //======================================================================
    public class ActiveTrade
    {
        public Order EntryOrder { get; set; }       // The side that triggered
        public Order OtherEntryOrder { get; set; }  // The opposing pending entry to cancel on fill
        public Order SlOrder { get; set; }
        public Order TpOrder { get; set; }
        public bool IsLong { get; set; }
        public double EntryPrice { get; set; }
        public DateTime EntryTime { get; set; }
        public double VirtualSL { get; set; }   // tracks virtual SL for comparison
        public bool TrailingActivated { get; set; }
        public bool BreakevenSet { get; set; }
        public int Contracts { get; set; }
        public string OcoGroup { get; set; }
        public int SlotIndex { get; set; }
    }
}
