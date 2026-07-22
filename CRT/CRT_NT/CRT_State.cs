// CRT_State.cs — file-backed persistence, adapted from ORB_NT/ORB_State.cs.
//   <dir>/crt_ledger_<instrument>.csv  — append-only closed trades
//   <dir>/crt_live_<instrument>.csv    — current open trade (rewritten; max 1)
//   <dir>/crt_consumed_<instrument>.csv— consumed C1 ranges (phantom re-fire guard)
// CRT keys a "consumed" record by the C1 slot-open timestamp + side, so a restart
// mid-setup never re-arms a range that already fired. Plain CSV, culture-invariant.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    // One completed CRT trade.
    public class CrtLedgerTrade
    {
        public DateTime EntryTimeUTC;
        public DateTime ExitTimeUTC;
        public string SlotName = "";      // Intraday/Daily/Weekly/Monthly
        public DateTime C1OpenUTC;        // reference-range identity
        public bool IsLong;
        public double EntryPrice;
        public double ExitPrice;
        public int Contracts;
        public double PnL;                // net, after commission
        public string ExitReason = "";    // SL / TP / EQ / Invalidate / Manual
        public string Source = "REAL";
    }

    // Snapshot of the single live CRT position.
    public class CrtLiveSnapshot
    {
        public string SlotName = "";
        public DateTime C1OpenUTC;
        public bool IsLong;
        public double EntryPrice;
        public DateTime EntryTimeUTC;
        public double VirtualSL;
        public double TpPrice;
        public int Contracts;
        public string OcoGroup = "";
        public bool BreakevenSet;
        public bool PartialTaken;         // 0.5 equilibrium partial done?
    }

    public class CRT_State
    {
        private readonly string ledgerPath;
        private readonly string livePath;
        private readonly string consumedPath;
        private readonly object ioLock = new object();

        public CRT_State(string dir, string instrumentName)
        {
            string safe = instrumentName.Replace(" ", "_");
            ledgerPath   = Path.Combine(dir, "crt_ledger_" + safe + ".csv");
            livePath     = Path.Combine(dir, "crt_live_" + safe + ".csv");
            consumedPath = Path.Combine(dir, "crt_consumed_" + safe + ".csv");
            try { if (!Directory.Exists(dir)) Directory.CreateDirectory(dir); } catch { }
        }

        private static string F(double d)    => d.ToString("R", CultureInfo.InvariantCulture);
        private static string T(DateTime t)  => t.ToString("o", CultureInfo.InvariantCulture);
        private static double PD(string s)   => double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out double d) ? d : 0;
        private static DateTime PT(string s) => DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out DateTime t) ? t : DateTime.MinValue;
        private static string Sanitize(string s)
            => string.IsNullOrEmpty(s) ? "" : s.Replace(",", "_").Replace("\n", " ").Replace("\r", "");

        //------------------------------------------------------------------ ledger
        public void AppendClosedTrade(CrtLedgerTrade t)
        {
            lock (ioLock)
            {
                try
                {
                    bool writeHeader = !File.Exists(ledgerPath);
                    using (var sw = new StreamWriter(ledgerPath, true, Encoding.UTF8))
                    {
                        if (writeHeader)
                            sw.WriteLine("EntryTimeUTC,ExitTimeUTC,Slot,C1OpenUTC,Dir,Entry,Exit,Contracts,PnL,ExitReason,Source");
                        sw.WriteLine(string.Join(",",
                            T(t.EntryTimeUTC), T(t.ExitTimeUTC), Sanitize(t.SlotName), T(t.C1OpenUTC),
                            t.IsLong ? "LONG" : "SHORT", F(t.EntryPrice), F(t.ExitPrice),
                            t.Contracts, F(t.PnL), Sanitize(t.ExitReason),
                            Sanitize(string.IsNullOrEmpty(t.Source) ? "REAL" : t.Source)));
                    }
                }
                catch { }
            }
        }

        public List<CrtLedgerTrade> LoadLedger()
        {
            var list = new List<CrtLedgerTrade>();
            lock (ioLock)
            {
                try
                {
                    if (!File.Exists(ledgerPath)) return list;
                    string[] lines = File.ReadAllLines(ledgerPath);
                    for (int i = 1; i < lines.Length; i++)
                    {
                        string[] p = lines[i].Split(',');
                        if (p.Length < 10) continue;
                        list.Add(new CrtLedgerTrade
                        {
                            EntryTimeUTC = PT(p[0]), ExitTimeUTC = PT(p[1]),
                            SlotName = p[2], C1OpenUTC = PT(p[3]),
                            IsLong = p[4] == "LONG", EntryPrice = PD(p[5]), ExitPrice = PD(p[6]),
                            Contracts = int.TryParse(p[7], out int c) ? c : 0,
                            PnL = PD(p[8]), ExitReason = p[9],
                            Source = p.Length >= 11 ? p[10] : "LEGACY"
                        });
                    }
                }
                catch { }
            }
            return list;
        }

        //------------------------------------------------------------------ live (max 1)
        public void SaveLiveTrade(CrtLiveSnapshot t)
        {
            lock (ioLock)
            {
                try
                {
                    if (t == null) { ClearLiveTrade(); return; }
                    string tmp = livePath + ".tmp";
                    using (var sw = new StreamWriter(tmp, false, Encoding.UTF8))
                    {
                        sw.WriteLine("Slot,C1OpenUTC,Dir,Entry,EntryTimeUTC,VirtualSL,TpPrice,Contracts,OcoGroup,BE,Partial");
                        sw.WriteLine(string.Join(",",
                            Sanitize(t.SlotName), T(t.C1OpenUTC), t.IsLong ? "LONG" : "SHORT",
                            F(t.EntryPrice), T(t.EntryTimeUTC), F(t.VirtualSL), F(t.TpPrice),
                            t.Contracts, Sanitize(t.OcoGroup),
                            t.BreakevenSet ? 1 : 0, t.PartialTaken ? 1 : 0));
                    }
                    if (File.Exists(livePath)) File.Delete(livePath);
                    File.Move(tmp, livePath);
                }
                catch { }
            }
        }

        public CrtLiveSnapshot LoadLiveTrade()
        {
            lock (ioLock)
            {
                try
                {
                    if (!File.Exists(livePath)) return null;
                    string[] lines = File.ReadAllLines(livePath);
                    if (lines.Length < 2) return null;
                    string[] p = lines[1].Split(',');
                    if (p.Length < 11) return null;
                    return new CrtLiveSnapshot
                    {
                        SlotName = p[0], C1OpenUTC = PT(p[1]), IsLong = p[2] == "LONG",
                        EntryPrice = PD(p[3]), EntryTimeUTC = PT(p[4]),
                        VirtualSL = PD(p[5]), TpPrice = PD(p[6]),
                        Contracts = int.TryParse(p[7], out int c) ? c : 0,
                        OcoGroup = p[8], BreakevenSet = p[9] == "1", PartialTaken = p[10] == "1"
                    };
                }
                catch { return null; }
            }
        }

        public void ClearLiveTrade()
        {
            lock (ioLock)
            {
                try { if (File.Exists(livePath)) File.Delete(livePath); } catch { }
            }
        }

        //------------------------------------------------------------------ consumed ranges
        private HashSet<string> consumedCache;

        private void EnsureConsumedLoaded()
        {
            if (consumedCache != null) return;
            consumedCache = new HashSet<string>();
            try
            {
                if (!File.Exists(consumedPath)) return;
                DateTime cutoff = DateTime.UtcNow.AddDays(-30);
                var keep = new List<string>();
                foreach (string line in File.ReadAllLines(consumedPath))
                {
                    string[] p = line.Split(';');
                    if (p.Length < 2) continue;
                    if (PT(p[1]) < cutoff) continue;
                    consumedCache.Add(p[0]);
                    keep.Add(line);
                }
                File.WriteAllLines(consumedPath, keep);
            }
            catch { }
        }

        // Identity of a fired setup = slot name + C1 open + side.
        private static string Key(string slotName, DateTime c1OpenUTC, bool longSide)
            => Sanitize(slotName) + "@" + T(c1OpenUTC) + "|" + (longSide ? "L" : "S");

        public void MarkConsumed(string slotName, DateTime c1OpenUTC, bool longSide)
        {
            lock (ioLock)
            {
                EnsureConsumedLoaded();
                string key = Key(slotName, c1OpenUTC, longSide);
                if (!consumedCache.Add(key)) return;
                try
                {
                    using (var sw = new StreamWriter(consumedPath, true, Encoding.UTF8))
                        sw.WriteLine(key + ";" + T(DateTime.UtcNow));
                }
                catch { }
            }
        }

        public bool IsConsumed(string slotName, DateTime c1OpenUTC, bool longSide)
        {
            lock (ioLock)
            {
                EnsureConsumedLoaded();
                return consumedCache.Contains(Key(slotName, c1OpenUTC, longSide));
            }
        }
    }
}
