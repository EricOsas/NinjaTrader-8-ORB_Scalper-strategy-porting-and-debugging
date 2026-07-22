using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    //======================================================================
    // Closed-trade ledger record.
    //======================================================================
    public class CrtLedgerTrade
    {
        public DateTime EntryTimeUTC;
        public DateTime ExitTimeUTC;
        public string SessionKey = "";
        public bool IsLong;
        public double EntryPrice;
        public double ExitPrice;
        public int Contracts;
        public double PnL;
        public string ExitReason = ""; // TP / SL / Manual
    }

    //======================================================================
    // CRT_State — file-backed persistence (single active trade model).
    //   <dir>/crt_ledger_<instr>.csv    — append-only closed trades
    //   <dir>/crt_consumed_<instr>.csv  — C1 identities already used, so a
    //        restart never re-arms a done C1 (pruned to 7 days).
    //======================================================================
    public class CRT_State
    {
        private readonly string ledgerPath;
        private readonly string consumedPath;
        private readonly object ioLock = new object();
        private HashSet<string> consumedCache;

        public CRT_State(string dir, string instrumentName)
        {
            string safe = instrumentName.Replace(" ", "_");
            ledgerPath = Path.Combine(dir, "crt_ledger_" + safe + ".csv");
            consumedPath = Path.Combine(dir, "crt_consumed_" + safe + ".csv");
            try { if (!Directory.Exists(dir)) Directory.CreateDirectory(dir); } catch { }
        }

        private static string F(double d) => d.ToString("R", CultureInfo.InvariantCulture);
        private static string T(DateTime t) => t.ToString("o", CultureInfo.InvariantCulture);
        private static string San(string s) => string.IsNullOrEmpty(s) ? "" : s.Replace(",", "_").Replace("\n", " ").Replace("\r", "");
        private static DateTime PT(string s) => DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out DateTime t) ? t : DateTime.MinValue;

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
                            sw.WriteLine("EntryTimeUTC,ExitTimeUTC,SessionKey,Dir,Entry,Exit,Contracts,PnL,ExitReason");
                        sw.WriteLine(string.Join(",",
                            T(t.EntryTimeUTC), T(t.ExitTimeUTC), San(t.SessionKey),
                            t.IsLong ? "LONG" : "SHORT",
                            F(t.EntryPrice), F(t.ExitPrice), t.Contracts, F(t.PnL), San(t.ExitReason)));
                    }
                }
                catch { }
            }
        }

        //------------------------------------------------------------------
        // Consumed-C1 guard.
        //------------------------------------------------------------------
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
                    if (PT(p[1]) < cutoff) continue;
                    consumedCache.Add(p[0]);
                    keep.Add(line);
                }
                File.WriteAllLines(consumedPath, keep);
            }
            catch { }
        }

        public void MarkConsumed(string sessionKey)
        {
            lock (ioLock)
            {
                EnsureConsumedLoaded();
                if (!consumedCache.Add(sessionKey)) return;
                try
                {
                    using (var sw = new StreamWriter(consumedPath, true, Encoding.UTF8))
                        sw.WriteLine(sessionKey + ";" + T(DateTime.UtcNow));
                }
                catch { }
            }
        }

        public bool IsConsumed(string sessionKey)
        {
            lock (ioLock)
            {
                EnsureConsumedLoaded();
                return consumedCache.Contains(sessionKey);
            }
        }
    }
}
