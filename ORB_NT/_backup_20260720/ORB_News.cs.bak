using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.Strategies;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public enum NewsGuardMode
    {
        Off = 0,
        RedOnly = 1,
        RedAndOrange = 2,
        All = 3
    }

    public class NewsEvent
    {
        public DateTime TimeUTC { get; set; }
        public string Currency { get; set; }
        public string Impact { get; set; }
        public string Title { get; set; }
    }

    public class ORB_News
    {
        private List<NewsEvent> events = new List<NewsEvent>();
        private DateTime lastFetchedUTC = DateTime.MinValue;
        private string cacheFilePath;
        private string historicalCsvPath;
        private bool isHistoricalMode;

        private static readonly HttpClient http = new HttpClient();
        private const string FF_URL = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";

        public ORB_News(string historicalCsvPath, string cacheFilePath, bool isHistoricalMode)
        {
            this.historicalCsvPath = historicalCsvPath;
            this.cacheFilePath = cacheFilePath;
            this.isHistoricalMode = isHistoricalMode;
        }

        //----------------------------------------------------------------------
        // Public entry point — call from State.DataLoaded or OnBarUpdate
        //----------------------------------------------------------------------
        public void Initialize()
        {
            if (isHistoricalMode)
                LoadHistoricalCsv();
            else
                FetchLiveFeed();
        }

        public void RefreshIfNeeded(DateTime currentUTC)
        {
            if (isHistoricalMode) return; // Static, no refresh needed

            // Only re-fetch once per session (once daily is sufficient)
            if (currentUTC.Date > lastFetchedUTC.Date)
                FetchLiveFeed();
        }

        //----------------------------------------------------------------------
        // Live FF JSON feed
        //----------------------------------------------------------------------
        private void FetchLiveFeed()
        {
            try
            {
                string json = http.GetStringAsync(FF_URL).GetAwaiter().GetResult();
                ParseFFJson(json);
                lastFetchedUTC = DateTime.UtcNow;

                // Write to local cache
                string dir = Path.GetDirectoryName(cacheFilePath);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                File.WriteAllText(cacheFilePath, json);
            }
            catch (Exception)
            {
                // Fail safe: use last cached file if available
                if (File.Exists(cacheFilePath))
                {
                    string cached = File.ReadAllText(cacheFilePath);
                    ParseFFJson(cached);
                }
                // If no cache, leave events empty — fail safe means don't trade if unknown
            }
        }

        private void ParseFFJson(string json)
        {
            events.Clear();
            // Manual parse: fields: title, country, date, impact, forecast, previous
            // FF date format: "2026-01-03T13:30:00+00:00"
            var items = Regex.Matches(json, @"\{[^{}]+\}");
            foreach (Match item in items)
            {
                string block = item.Value;
                string country = GetJsonField(block, "country");
                string impact = GetJsonField(block, "impact");
                if (!country.Equals("USD", StringComparison.OrdinalIgnoreCase)) continue;
                if (!impact.Equals("High", StringComparison.OrdinalIgnoreCase)) continue;

                string dateStr = GetJsonField(block, "date");
                string title = GetJsonField(block, "title");

                if (DateTime.TryParseExact(dateStr.Substring(0, 19), "yyyy-MM-ddTHH:mm:ss",
                        null, System.Globalization.DateTimeStyles.AssumeUniversal, out DateTime eventTime))
                {
                    events.Add(new NewsEvent
                    {
                        TimeUTC = eventTime.ToUniversalTime(),
                        Currency = country,
                        Impact = impact,
                        Title = title
                    });
                }
            }
        }

        private static string GetJsonField(string json, string field)
        {
            var match = Regex.Match(json, "\"" + field + "\":\\s*\"([^\"]+)\"");
            return match.Success ? match.Groups[1].Value : string.Empty;
        }

        //----------------------------------------------------------------------
        // Historical CSV feed
        //----------------------------------------------------------------------
        private void LoadHistoricalCsv()
        {
            events.Clear();
            if (!File.Exists(historicalCsvPath)) return;

            string[] lines = File.ReadAllLines(historicalCsvPath);
            for (int i = 1; i < lines.Length; i++) // Skip header
            {
                string[] parts = lines[i].Split(',');
                if (parts.Length < 5) continue;

                // CSV: Date,Time_ET,Currency,Impact,Title
                string dateStr = parts[0].Trim();
                string timeStr = parts[1].Trim();
                string currency = parts[2].Trim();
                string impact = parts[3].Trim();
                string title = parts[4].Trim();

                if (!currency.Equals("USD", StringComparison.OrdinalIgnoreCase)) continue;
                if (!impact.Equals("High", StringComparison.OrdinalIgnoreCase)) continue;

                if (DateTime.TryParse(dateStr + " " + timeStr, out DateTime eventTimeET))
                {
                    // Convert ET to UTC
                    DateTime eventTimeUTC = ORB_Time.NYToUTC(eventTimeET);
                    events.Add(new NewsEvent
                    {
                        TimeUTC = eventTimeUTC,
                        Currency = currency,
                        Impact = impact,
                        Title = title
                    });
                }
            }
        }

        //----------------------------------------------------------------------
        // Query methods — call these from strategy logic
        //----------------------------------------------------------------------
        public bool IsNewsBlocked(DateTime currentUTC, int blockMinutesBefore, int blockMinutesAfter)
        {
            foreach (var ev in events)
            {
                DateTime windowStart = ev.TimeUTC.AddMinutes(-blockMinutesBefore);
                DateTime windowEnd = ev.TimeUTC.AddMinutes(blockMinutesAfter);
                if (currentUTC >= windowStart && currentUTC <= windowEnd)
                    return true;
            }
            return false;
        }

        public bool IsNewsFreezingTrail(DateTime currentUTC, int freezeMinutesBefore, int freezeMinutesAfter)
        {
            return IsNewsBlocked(currentUTC, freezeMinutesBefore, freezeMinutesAfter);
        }

        public bool IsNewsFlattening(DateTime currentUTC, int flattenMinutesBefore)
        {
            return IsNewsBlocked(currentUTC, flattenMinutesBefore, 0);
        }

        public string GetNextEventDescription(DateTime currentUTC)
        {
            NewsEvent next = null;
            TimeSpan shortest = TimeSpan.MaxValue;

            foreach (var ev in events)
            {
                if (ev.TimeUTC > currentUTC)
                {
                    TimeSpan diff = ev.TimeUTC - currentUTC;
                    if (diff < shortest) { shortest = diff; next = ev; }
                }
            }

            if (next == null) return "--";
            return string.Format("{0} in {1:hh\\:mm\\:ss}", next.Title, shortest);
        }
    }
}
