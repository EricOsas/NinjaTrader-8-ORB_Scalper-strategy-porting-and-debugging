using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    //======================================================================
    // Closed-trade ledger record — one line per completed trade.
    // Feeds: weekly/monthly performance reports, consistency/fast-trade/
    // drawdown tracker rebuild after an NT restart.
    //======================================================================
    public class LedgerTrade
    {
        public DateTime EntryTimeUTC;
        public DateTime ExitTimeUTC;
        public int SlotIndex;
        public string SessionKey = "";
        public bool IsLong;
        public double EntryPrice;
        public double ExitPrice;
        public int Contracts;
        public double PnL;            // net, after commission
        public double SlipTicks;
        public string ExitReason = ""; // SL / TP / EOD / News / Manual / SlipForceClose
    }

    //======================================================================
    // Live-position snapshot — written on every fill/trail change, deleted
    // on close. On restart, if the account still holds a matching position,
    // the trade is re-adopted and managed off this snapshot (MT5 parity:
    // RegisterNewPositions + persistent vTrades).
    //======================================================================
    public class LiveTradeSnapshot
    {
        public int SlotIndex;
        public string SessionKey = "";
        public bool IsLong;
        public double EntryPrice;
        public DateTime EntryTimeUTC;
        public double VirtualSL;
        public double TpPrice;
        public int Contracts;
        public string OcoGroup = "";
        public bool TrailingActivated;
        public bool BreakevenSet;
        public double SlipTicks;
        public bool SlipForceClose;
        // Frozen trailing geometry (survives restarts with the trade)
        public int SnapTrailMode;
        public int SnapBehavior;
        public double SnapThreshPrice;
        public double SnapGapPrice;
        public int SnapMinTrailSec;
        public bool SnapSpreadComp;
        public double SnapEntrySpread;
        public double SnapBECostPrice;
    }

    //======================================================================
    // ORB_State — file-backed persistence.
    //   <dir>/orb_ledger_<instrument>.csv   — append-only closed trades
    //   <dir>/orb_live_<instrument>.csv     — current open trades (rewritten)
    //   <dir>/orb_consumed_<instrument>.csv — consumed-ledger: sides already
    //        used per session key (MT5 phantom re-fire fix #4) so a restart
    //        never re-arms a side that already triggered today.
    // Plain CSV, culture-invariant, no dependencies — robust across crashes.
    //======================================================================
    public class ORB_State
    {
        private readonly string ledgerPath;
        private readonly string livePath;
        private readonly string consumedPath;
        private readonly object ioLock = new object();

        public ORB_State(string dir, string instrumentName)
        {
            string safe = instrumentName.Replace(" ", "_");
            ledgerPath   = Path.Combine(dir, "orb_ledger_" + safe + ".csv");
            livePath     = Path.Combine(dir, "orb_live_" + safe + ".csv");
            consumedPath = Path.Combine(dir, "orb_consumed_" + safe + ".csv");
            try { if (!Directory.Exists(dir)) Directory.CreateDirectory(dir); } catch { }
        }

        private static string F(double d)   => d.ToString("R", CultureInfo.InvariantCulture);
        private static string T(DateTime t) => t.ToString("o", CultureInfo.InvariantCulture);
        private static double PD(string s)  => double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out double d) ? d : 0;
        private static DateTime PT(string s) => DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out DateTime t) ? t : DateTime.MinValue;

        //------------------------------------------------------------------
        // Closed-trade ledger (append-only)
        //------------------------------------------------------------------
        public void AppendClosedTrade(LedgerTrade t)
        {
            lock (ioLock)
            {
                try
                {
                    bool writeHeader = !File.Exists(ledgerPath);
                    using (var sw = new StreamWriter(ledgerPath, true, Encoding.UTF8))
                    {
                        if (writeHeader)
                            sw.WriteLine("EntryTimeUTC,ExitTimeUTC,Slot,SessionKey,Dir,Entry,Exit,Contracts,PnL,SlipTicks,ExitReason");
                        sw.WriteLine(string.Join(",",
                            T(t.EntryTimeUTC), T(t.ExitTimeUTC), t.SlotIndex,
                            Sanitize(t.SessionKey), t.IsLong ? "LONG" : "SHORT",
                            F(t.EntryPrice), F(t.ExitPrice), t.Contracts,
                            F(t.PnL), F(t.SlipTicks), Sanitize(t.ExitReason)));
                    }
                }
                catch { /* persistence is best-effort; never break trading */ }
            }
        }

        public List<LedgerTrade> LoadLedger()
        {
            var list = new List<LedgerTrade>();
            lock (ioLock)
            {
                try
                {
                    if (!File.Exists(ledgerPath)) return list;
                    string[] lines = File.ReadAllLines(ledgerPath);
                    for (int i = 1; i < lines.Length; i++)
                    {
                        string[] p = lines[i].Split(',');
                        if (p.Length < 11) continue;
                        list.Add(new LedgerTrade
                        {
                            EntryTimeUTC = PT(p[0]), ExitTimeUTC = PT(p[1]),
                            SlotIndex = int.TryParse(p[2], out int s) ? s : 0,
                            SessionKey = p[3], IsLong = p[4] == "LONG",
                            EntryPrice = PD(p[5]), ExitPrice = PD(p[6]),
                            Contracts = int.TryParse(p[7], out int c) ? c : 0,
                            PnL = PD(p[8]), SlipTicks = PD(p[9]), ExitReason = p[10]
                        });
                    }
                }
                catch { }
            }
            return list;
        }

        //------------------------------------------------------------------
        // Live snapshots (full rewrite each save — small file, atomic-ish)
        //------------------------------------------------------------------
        public void SaveLiveTrades(IEnumerable<LiveTradeSnapshot> trades)
        {
            lock (ioLock)
            {
                try
                {
                    string tmp = livePath + ".tmp";
                    using (var sw = new StreamWriter(tmp, false, Encoding.UTF8))
                    {
                        sw.WriteLine("Slot,SessionKey,Dir,Entry,EntryTimeUTC,VirtualSL,TpPrice,Contracts,OcoGroup,Trailing,BE,SlipTicks,SlipFC," +
                                     "TrailMode,Behavior,Thresh,Gap,MinTrailSec,SpreadComp,EntrySpread,BECost");
                        foreach (var t in trades)
                        {
                            if (t == null) continue;
                            sw.WriteLine(string.Join(",",
                                t.SlotIndex, Sanitize(t.SessionKey), t.IsLong ? "LONG" : "SHORT",
                                F(t.EntryPrice), T(t.EntryTimeUTC), F(t.VirtualSL), F(t.TpPrice),
                                t.Contracts, Sanitize(t.OcoGroup),
                                t.TrailingActivated ? 1 : 0, t.BreakevenSet ? 1 : 0,
                                F(t.SlipTicks), t.SlipForceClose ? 1 : 0,
                                t.SnapTrailMode, t.SnapBehavior, F(t.SnapThreshPrice), F(t.SnapGapPrice),
                                t.SnapMinTrailSec, t.SnapSpreadComp ? 1 : 0, F(t.SnapEntrySpread), F(t.SnapBECostPrice)));
                        }
                    }
                    if (File.Exists(livePath)) File.Delete(livePath);
                    File.Move(tmp, livePath);
                }
                catch { }
            }
        }

        public List<LiveTradeSnapshot> LoadLiveTrades()
        {
            var list = new List<LiveTradeSnapshot>();
            lock (ioLock)
            {
                try
                {
                    if (!File.Exists(livePath)) return list;
                    string[] lines = File.ReadAllLines(livePath);
                    for (int i = 1; i < lines.Length; i++)
                    {
                        string[] p = lines[i].Split(',');
                        if (p.Length < 13) continue;
                        var snap = new LiveTradeSnapshot
                        {
                            SlotIndex = int.TryParse(p[0], out int s) ? s : 0,
                            SessionKey = p[1], IsLong = p[2] == "LONG",
                            EntryPrice = PD(p[3]), EntryTimeUTC = PT(p[4]),
                            VirtualSL = PD(p[5]), TpPrice = PD(p[6]),
                            Contracts = int.TryParse(p[7], out int c) ? c : 0,
                            OcoGroup = p[8],
                            TrailingActivated = p[9] == "1", BreakevenSet = p[10] == "1",
                            SlipTicks = PD(p[11]), SlipForceClose = p[12] == "1"
                        };
                        if (p.Length >= 21)
                        {
                            snap.SnapTrailMode = int.TryParse(p[13], out int tm) ? tm : 0;
                            snap.SnapBehavior = int.TryParse(p[14], out int bh) ? bh : 0;
                            snap.SnapThreshPrice = PD(p[15]);
                            snap.SnapGapPrice = PD(p[16]);
                            snap.SnapMinTrailSec = int.TryParse(p[17], out int mt) ? mt : 0;
                            snap.SnapSpreadComp = p[18] == "1";
                            snap.SnapEntrySpread = PD(p[19]);
                            snap.SnapBECostPrice = PD(p[20]);
                        }
                        list.Add(snap);
                    }
                }
                catch { }
            }
            return list;
        }

        public void ClearLiveTrades()
        {
            lock (ioLock)
            {
                try { if (File.Exists(livePath)) File.Delete(livePath); } catch { }
            }
        }

        //------------------------------------------------------------------
        // Consumed-side ledger: "SessionKey|SIDE" entries with a timestamp.
        // Prevents phantom re-fires: a side that already triggered this
        // session must not re-arm after a restart. Pruned to 7 days.
        //------------------------------------------------------------------
        private HashSet<string> consumedCache;

        private void EnsureConsumedLoaded()
        {
            if (consumedCache != null) return;
            consumedCache = new HashSet<string>();
            try
            {
                if (!File.Exists(consumedPath)) return;
                DateTime cutoff = DateTime.UtcNow.AddDays(-7);
                var keep = new List<string>();
                foreach (string line in File.ReadAllLines(consumedPath))
                {
                    string[] p = line.Split(';');
                    if (p.Length < 2) continue;
                    if (PT(p[1]) < cutoff) continue; // prune old entries
                    consumedCache.Add(p[0]);
                    keep.Add(line);
                }
                File.WriteAllLines(consumedPath, keep);
            }
            catch { }
        }

        public void MarkSideConsumed(string sessionKey, bool longSide)
        {
            lock (ioLock)
            {
                EnsureConsumedLoaded();
                string key = sessionKey + "|" + (longSide ? "L" : "S");
                if (!consumedCache.Add(key)) return;
                try
                {
                    using (var sw = new StreamWriter(consumedPath, true, Encoding.UTF8))
                        sw.WriteLine(key + ";" + T(DateTime.UtcNow));
                }
                catch { }
            }
        }

        public bool IsSideConsumed(string sessionKey, bool longSide)
        {
            lock (ioLock)
            {
                EnsureConsumedLoaded();
                return consumedCache.Contains(sessionKey + "|" + (longSide ? "L" : "S"));
            }
        }

        private static string Sanitize(string s)
            => string.IsNullOrEmpty(s) ? "" : s.Replace(",", "_").Replace("\n", " ").Replace("\r", "");
    }

    //======================================================================
    // ORB_Reports — weekly/monthly performance summaries from the ledger
    // (ORBReportsOnTimer equivalent). Sends through ORB_Notify.
    //======================================================================
    public static class ORB_Reports
    {
        // Returns a formatted report for all ledger trades in [fromUTC, toUTC)
        public static string BuildSummary(List<LedgerTrade> ledger, DateTime fromUTC, DateTime toUTC, string title)
        {
            int wins = 0, losses = 0;
            double gross = 0, bestDay = double.MinValue, worstDay = double.MaxValue;
            var daily = new Dictionary<DateTime, double>();

            foreach (var t in ledger)
            {
                if (t.ExitTimeUTC < fromUTC || t.ExitTimeUTC >= toUTC) continue;
                gross += t.PnL;
                if (t.PnL >= 0) wins++; else losses++;
                DateTime d = t.ExitTimeUTC.Date;
                if (!daily.ContainsKey(d)) daily[d] = 0;
                daily[d] += t.PnL;
            }

            foreach (var kv in daily)
            {
                if (kv.Value > bestDay) bestDay = kv.Value;
                if (kv.Value < worstDay) worstDay = kv.Value;
            }

            int total = wins + losses;
            if (total == 0) return null; // nothing to report

            var sb = new StringBuilder();
            sb.AppendLine("**" + title + "**");
            sb.AppendLine();
            sb.AppendLine(string.Format("Trades: {0}  (W {1} / L {2}, {3:F0}%)",
                total, wins, losses, total > 0 ? 100.0 * wins / total : 0));
            sb.AppendLine(string.Format("Net PnL: {0:+0.00;-0.00}", gross));
            sb.AppendLine(string.Format("Trading days: {0}", daily.Count));
            if (daily.Count > 0)
            {
                sb.AppendLine(string.Format("Best day: {0:+0.00;-0.00}", bestDay));
                sb.Append(string.Format("Worst day: {0:+0.00;-0.00}", worstDay));
            }
            return sb.ToString();
        }
    }
}
