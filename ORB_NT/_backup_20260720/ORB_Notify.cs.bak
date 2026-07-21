using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    //======================================================================
    // Notification queue item
    //======================================================================
    public class NotifyQueueItem
    {
        public string Text { get; set; }
        public int ColorInt { get; set; }
        public int Retries { get; set; }
    }

    //======================================================================
    // ORB_Notify — Discord/Telegram webhook layer (HttpClient-based)
    // Ports ORBNSendDiscord, ORBNSendTelegram, queue, drain, dedupe
    //======================================================================
    public class ORB_Notify
    {
        private string discordWebhookUrl;
        private string telegramBotToken;
        private string telegramChatId;
        private bool discordEnabled;
        private bool telegramEnabled;

        private Queue<NotifyQueueItem> messageQueue = new Queue<NotifyQueueItem>();
        private HashSet<string> dedupeKeys = new HashSet<string>();

        private static readonly HttpClient http = new HttpClient();

        public ORB_Notify(string discordWebhookUrl, string telegramBotToken, string telegramChatId,
            bool discordEnabled, bool telegramEnabled)
        {
            this.discordWebhookUrl = discordWebhookUrl;
            this.telegramBotToken = telegramBotToken;
            this.telegramChatId = telegramChatId;
            this.discordEnabled = discordEnabled;
            this.telegramEnabled = telegramEnabled;
        }

        //----------------------------------------------------------------------
        // Dedupe guard (equivalent to ORBNClaimOnce in MT5)
        //----------------------------------------------------------------------
        private bool ClaimOnce(string kind, long ticket, string sessionKey)
        {
            string key = string.Format("ORBN_{0}_{1}_{2}", kind, ticket, sessionKey);
            if (dedupeKeys.Contains(key))
            {
                Console.WriteLine(string.Format("[ORB] ORBNClaimOnce blocked duplicate key: {0}", key));
                return false;
            }
            dedupeKeys.Add(key);
            return true;
        }

        //----------------------------------------------------------------------
        // Enqueue a message (all notification calls go through here)
        //----------------------------------------------------------------------
        public void Enqueue(string text, int colorInt = 0x1ABC9C)
        {
            messageQueue.Enqueue(new NotifyQueueItem { Text = text, ColorInt = colorInt, Retries = 0 });
        }

        //----------------------------------------------------------------------
        // Drain one item from the queue — call from OnBarUpdate (tick cadence)
        //----------------------------------------------------------------------
        public void DrainQueue()
        {
            if (messageQueue.Count == 0) return;

            NotifyQueueItem item = messageQueue.Dequeue();
            bool ok = SendDirect(item.Text, item.ColorInt);
            if (!ok)
            {
                if (item.Retries < 3)
                {
                    item.Retries++;
                    Console.WriteLine(string.Format("[ORB] Webhook dispatch failed. Requeuing notification (Retry {0}/3).", item.Retries));
                    // Prepend back to queue (re-enqueue at front using a temporary list)
                    var temp = new List<NotifyQueueItem>(messageQueue);
                    messageQueue.Clear();
                    messageQueue.Enqueue(item);
                    foreach (var m in temp) messageQueue.Enqueue(m);
                }
                else
                {
                    Console.WriteLine("[ORB] Webhook dispatch failed permanently after 3 retries. " +
                        "Discarding notification. Check webhook URL configuration.");
                }
            }
        }

        //----------------------------------------------------------------------
        // Actual HTTP dispatch
        //----------------------------------------------------------------------
        private bool SendDirect(string text, int colorInt)
        {
            bool ok = true;
            if (discordEnabled && !string.IsNullOrEmpty(discordWebhookUrl))
                ok &= SendDiscord(text, colorInt);
            if (telegramEnabled && !string.IsNullOrEmpty(telegramBotToken) && !string.IsNullOrEmpty(telegramChatId))
                ok &= SendTelegram(text);
            return ok;
        }

        private bool SendDiscord(string text, int colorInt)
        {
            try
            {
                // Discord embed payload
                string json = string.Format(
                    "{{\"embeds\":[{{\"description\":\"{0}\",\"color\":{1}}}]}}",
                    text.Replace("\"", "\\\"").Replace("\n", "\\n"),
                    colorInt);

                using (var content = new StringContent(json, Encoding.UTF8, "application/json"))
                {
                    var response = http.PostAsync(discordWebhookUrl, content).GetAwaiter().GetResult();
                    return response.IsSuccessStatusCode;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("[ORB] Discord webhook error: {0}", ex.Message));
                return false;
            }
        }

        private bool SendTelegram(string text)
        {
            try
            {
                // Convert Discord Markdown (**bold**) to Telegram (*bold*)
                string tgText = text.Replace("**", "*");

                string tgChatId = telegramChatId;
                string tgThreadId = "";
                if (tgChatId.Contains("|"))
                {
                    string[] parts = tgChatId.Split('|');
                    tgChatId = parts[0];
                    if (parts.Length > 1) tgThreadId = parts[1];
                }

                string url = string.Format("https://api.telegram.org/bot{0}/sendMessage", telegramBotToken);
                string json = string.Format(
                    "{{\"chat_id\":\"{0}\",\"text\":\"{1}\",\"parse_mode\":\"Markdown\"{2}}}",
                    tgChatId,
                    tgText.Replace("\"", "\\\"").Replace("\n", "\\n"),
                    !string.IsNullOrEmpty(tgThreadId) ? ",\"message_thread_id\":" + tgThreadId : "");

                using (var content = new StringContent(json, Encoding.UTF8, "application/json"))
                {
                    var response = http.PostAsync(url, content).GetAwaiter().GetResult();
                    return response.IsSuccessStatusCode;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("[ORB] Telegram webhook error: {0}", ex.Message));
                return false;
            }
        }

        //----------------------------------------------------------------------
        // Convenience notification methods (named equivalent to MT5 helpers)
        //----------------------------------------------------------------------
        public void NotifySetup(long ticket, string sessionKey, bool bull, double rangeHigh, double rangeLow,
            double entryPx, double slPx, double tpPx, string sessionLabel)
        {
            if (!ClaimOnce("SETUP", ticket, sessionKey)) return;
            string dir = bull ? "BUY" : "SELL";
            string text = string.Format(
                "**{0} — {1} SETUP**\n\nRange: {2:F2} / {3:F2}\nEntry: {4:F2} | SL: {5:F2} | TP: {6:F2}",
                sessionLabel, dir, rangeHigh, rangeLow, entryPx, slPx, tpPx);
            Enqueue(text, bull ? 0x2ECC71 : 0xE74C3C);
        }

        public void NotifyFill(long ticket, string sessionKey, bool bull, double fillPx, double slPx, double tpPx, int contracts)
        {
            if (!ClaimOnce("FILL", ticket, sessionKey)) return;
            string dir = bull ? "LONG" : "SHORT";
            string text = string.Format(
                "**{0} FILLED**\n\nFill: {1:F2} | SL: {2:F2} | TP: {3:F2}\nContracts: {4}",
                dir, fillPx, slPx, tpPx, contracts);
            Enqueue(text, bull ? 0x2ECC71 : 0xE74C3C);
        }

        public void NotifyTrail(long ticket, string sessionKey, bool bull, double newSL)
        {
            if (!ClaimOnce("TRAIL", ticket, sessionKey)) return;
            string dir = bull ? "BUY" : "SELL";
            string text = string.Format("**Trail activated** — {0}\nSL moved to: {1:F2}", dir, newSL);
            Enqueue(text, 0x3498DB);
        }

        public void NotifyResult(long ticket, string sessionKey, bool bull, double pnl,
            double entryPx, double closePx, string sessionLabel, double accountBalance)
        {
            if (!ClaimOnce("RES", ticket, sessionKey)) return;
            string dir = bull ? "BUY" : "SELL";
            string sign = pnl >= 0 ? "+" : "";
            double pct = accountBalance > 0 ? (pnl / accountBalance) * 100.0 : 0;
            string text = string.Format(
                "**{0} — {1} CLOSED**\n\nEntry: {2:F2} → Exit: {3:F2}\nP&L: {4}{5:F2} ({4}{6:F2}%)",
                sessionLabel, dir, entryPx, closePx, sign, pnl, pct);
            Enqueue(text, pnl >= 0 ? 0x2ECC71 : 0xE74C3C);
        }

        public void NotifyCancelled(long ticket, string sessionKey, bool bull, double price, string reason)
        {
            if (!ClaimOnce("CAN", ticket, sessionKey)) return;
            string dir = bull ? "BUY" : "SELL";
            string text = string.Format("**{0} CANCELLED**\n@ {1:F2}\n{2}", dir, price, reason);
            Enqueue(text, 0x95A5A6);
        }

        public void PruneDedupe(TimeSpan maxAge)
        {
            // In the C# version we use an in-memory set so cleanup is session-scoped.
            // Clear is sufficient since dedupe is only meaningful within the same trading session.
            dedupeKeys.Clear();
        }
    }
}
