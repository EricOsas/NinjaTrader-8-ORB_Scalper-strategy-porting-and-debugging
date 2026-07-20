using System;
using System.Text;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public struct ORBDashState
    {
        // Account / Compliance (Tradeify-specific)
        public double CurrentBalance;
        public double DrawdownFloor;
        public bool FloorLocked;
        public double DistanceToFloor;
        public double ConsistencyPctOfTotal;
        public double EvalProfitTarget;
        public double EvalProfitProgress;
        public int TradingDaysCompleted;
        public double FastTradePct;
        public bool ConsistencyWarning;

        // Session / Slot state
        public string ActiveSession;
        public string SessionPhase;
        public int SecsToNextPhase;
        public double RangeHigh;
        public double RangeLow;
        public bool Slot1Active;
        public bool Slot2Active;
        public string Slot2Mode;

        // Trade / Risk
        public bool InTrade;
        public string TradeDir;
        public double EntryPrice;
        public double StopLoss;
        public double TakeProfit;
        public int ContractCount;
        public string ContractMode;
        public double LiveRR;
        public bool BEActive;
        public string BEDetail;

        // News
        public bool NewsBlackoutActive;
        public string NextNewsEvent;
        public string NewsSourceMode;
    }

    public static class ORB_Dashboard
    {
        private const string PANEL_TAG = "ORB_Dashboard_Panel";
        private static string lastSignature = "";

        public static void Render(Strategy strategy, ORBDashState s)
        {
            // Build dirty signature — skip Draw call if nothing changed
            string sig = BuildSignature(s);
            if (sig == lastSignature) return;
            lastSignature = sig;

            string panel = BuildPanel(s);

            Draw.TextFixed(strategy, PANEL_TAG, panel,
                TextPosition.TopRight,
                System.Windows.Media.Brushes.WhiteSmoke,
                new NinjaTrader.Gui.Tools.SimpleFont("Consolas", 11),
                System.Windows.Media.Brushes.Transparent,
                System.Windows.Media.Brushes.Black,
                11);
        }

        private static string BuildSignature(ORBDashState s)
        {
            // Include ALL time-sensitive and state fields so the dashboard re-renders every tick when they change
            return string.Format("{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}|{19}",
                s.CurrentBalance, s.DrawdownFloor, s.FloorLocked, s.EvalProfitProgress,
                s.TradingDaysCompleted, s.ConsistencyPctOfTotal, s.FastTradePct,
                s.RangeHigh, s.RangeLow, s.Slot1Active, s.Slot2Active,
                s.InTrade, s.NewsBlackoutActive,
                // Time-sensitive fields — change every second:
                s.SecsToNextPhase,
                s.NextNewsEvent,
                s.StopLoss, s.TakeProfit,
                Math.Round(s.LiveRR, 2),
                s.BEActive, s.TradeDir);
        }

        private static string BuildPanel(ORBDashState s)
        {
            var sb = new StringBuilder();
            string phaseLine = string.Format("ORB · NinjaScript ── {0} ── {1}", s.ActiveSession, s.SessionPhase);
            sb.AppendLine(phaseLine);
            sb.AppendLine("────────────────────────────────────────");

            sb.AppendLine(string.Format("Balance      : {0,10:C}", s.CurrentBalance));
            sb.AppendLine(string.Format("DD Floor     : {0,10:C}  {1}", s.DrawdownFloor, s.FloorLocked ? "[LOCKED]" : ""));
            sb.AppendLine(string.Format("To Floor     : {0,10:C}", s.DistanceToFloor));
            sb.AppendLine(string.Format("Eval Target  : {0,8:C} / {1,8:C}", s.EvalProfitProgress, s.EvalProfitTarget));
            sb.AppendLine(string.Format("Trading Days : {0}/3", s.TradingDaysCompleted));
            sb.AppendLine(string.Format("Consistency  : {0,5:F1}% of total  {1}", s.ConsistencyPctOfTotal, s.ConsistencyWarning ? "[!]" : ""));
            sb.AppendLine(string.Format("Fast Trades  : {0,5:F1}% held <10s  {1}", s.FastTradePct, s.FastTradePct > 45 ? "[!]" : ""));

            sb.AppendLine("────────────────────────────────────────");

            sb.AppendLine(string.Format("Range H/L    : {0,10:F2} / {1,10:F2}", s.RangeHigh, s.RangeLow));
            sb.AppendLine(string.Format("Slot 1       : {0}   Slot 2 ({1}): {2}",
                s.Slot1Active ? "ON " : "OFF", s.Slot2Mode, s.Slot2Active ? "ON " : "OFF"));
            sb.AppendLine(string.Format("Next Phase   : {0}", FormatCountdown(s.SecsToNextPhase)));

            sb.AppendLine("────────────────────────────────────────");

            if (s.InTrade)
            {
                sb.AppendLine(string.Format("Position     : {0}  {1}x {2}", s.TradeDir, s.ContractCount, s.ContractMode));
                sb.AppendLine(string.Format("Entry/SL/TP  : {0,8:F2} / {1,8:F2} / {2,8:F2}", s.EntryPrice, s.StopLoss, s.TakeProfit));
                sb.AppendLine(string.Format("Live RR      : {0,5:F2}R", s.LiveRR));
                sb.AppendLine(string.Format("BE           : {0}", s.BEActive ? "ACTIVE " + s.BEDetail : "pending"));
            }
            else
            {
                sb.AppendLine("Position     : flat");
            }

            sb.AppendLine("────────────────────────────────────────");

            sb.AppendLine(string.Format("News         : {0}{1}",
                s.NewsBlackoutActive ? "[BLOCKED] " : "", s.NextNewsEvent));
            sb.Append(string.Format("News Source  : {0}", s.NewsSourceMode));

            return sb.ToString();
        }

        private static string FormatCountdown(int totalSeconds)
        {
            if (totalSeconds <= 0) return "--";
            TimeSpan ts = TimeSpan.FromSeconds(totalSeconds);
            return string.Format("{0:D2}:{1:D2}:{2:D2}", (int)ts.TotalHours, ts.Minutes, ts.Seconds);
        }
    }
}
