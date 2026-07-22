#ifndef CRT_NOTIFY_MQH
#define CRT_NOTIFY_MQH

//======================================================================
// CRT_Notify.mqh — Discord & Telegram notifications for CRT EA.
//
// Adapted from CCT_Notify.mqh (same HTTP patterns), simplified to the
// four events needed by the CRT system:
//   1. Setup armed  (C2 confirmed, awaiting C3 entry)
//   2. Entry fill   (market or limit filled)
//   3. Exit         (TP / SL)
//   4. Cancelled    (50% invalidation / limit cancelled)
//
// DISCORD SETUP
//   Create a webhook in your channel and paste its URL into the
//   Inp_DiscordWebhook input. Add https://discord.com to the MT5
//   WebRequest whitelist (Tools → Options → Expert Advisors).
//
// TELEGRAM SETUP
//   1. Create a bot via @BotFather, copy the token.
//   2. Add the bot to your channel/group as admin.
//   3. Get the chat_id from @userinfobot.
//   4. Set Inp_TelegramToken and Inp_TelegramChatId.
//   5. Add https://api.telegram.org to the WebRequest whitelist.
//======================================================================

#include "CRT_Globals.mqh"
#include "CRT_Time.mqh"

// Inputs declared in CRT_EA.mq5
extern bool   Inp_NotifyEnabled;
extern bool   Inp_DiscordEnabled;
extern string Inp_DiscordWebhook;
extern bool   Inp_TelegramEnabled;
extern string Inp_TelegramToken;
extern string Inp_TelegramChatId;

//----------------------------------------------------------------------
// Helpers
//----------------------------------------------------------------------
string CrtNotifyJsonEscape(const string value)
{
    string out = "";
    int len = StringLen(value);
    for (int i = 0; i < len; i++)
    {
        ushort ch = StringGetCharacter(value, i);
        if (ch == '\\') out += "\\\\";
        else if (ch == '"')  out += "\\\"";
        else if (ch == '\r') out += "\\r";
        else if (ch == '\n') out += "\\n";
        else out += ShortToString(ch);
    }
    return out;
}

string CrtNotifyHtmlEscape(const string value)
{
    string out = value;
    StringReplace(out, "&", "&amp;");
    StringReplace(out, "<", "&lt;");
    StringReplace(out, ">", "&gt;");
    StringReplace(out, "\"", "&quot;");
    return out;
}

string CrtNotifyPriceStr(double price)
{
    if (price <= 0.0) return "-";
    return DoubleToString(price, _Digits);
}

// Freshness gate: suppress notifications for events that pre-date the
// EA's runtime start (replayed historical records on reload/VPS reboot).
bool CrtNotifyIsFresh(datetime eventTime)
{
    if (g_crtRuntimeStart <= 0) return true;
    if (eventTime <= 0) return false;
    return (eventTime >= g_crtRuntimeStart);
}

bool CrtNotifySuppressed()
{
    if ((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE))
        return true;
    if (!Inp_NotifyEnabled) return true;
    return (!Inp_DiscordEnabled && !Inp_TelegramEnabled);
}

//----------------------------------------------------------------------
// HTTP send helpers
//----------------------------------------------------------------------
bool CrtSendDiscord(const string message)
{
    if (!Inp_DiscordEnabled || Inp_DiscordWebhook == "") return false;
    string payload = "{\"content\":\"" + CrtNotifyJsonEscape(message) + "\"}";
    uchar  body[], result[];
    string headers = "Content-Type: application/json\r\n";
    StringToCharArray(payload, body, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(body, ArraySize(body) - 1); // strip null terminator
    int code = WebRequest("POST", Inp_DiscordWebhook, headers, 5000, body, result, headers);
    return (code == 200 || code == 204);
}

bool CrtSendTelegram(const string message)
{
    if (!Inp_TelegramEnabled || Inp_TelegramToken == "" || Inp_TelegramChatId == "") return false;
    string url = "https://api.telegram.org/bot" + Inp_TelegramToken + "/sendMessage";
    string text = CrtNotifyHtmlEscape(message);
    string payload = "{\"chat_id\":\"" + CrtNotifyJsonEscape(Inp_TelegramChatId) +
                     "\",\"text\":\"" + CrtNotifyJsonEscape(text) +
                     "\",\"parse_mode\":\"HTML\"}";
    uchar body[], result[];
    string headers = "Content-Type: application/json\r\n";
    StringToCharArray(payload, body, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(body, ArraySize(body) - 1);
    int code = WebRequest("POST", url, headers, 5000, body, result, headers);
    return (code == 200);
}

void CrtNotifySend(const string message)
{
    if (CrtNotifySuppressed()) return;
    if (Inp_DiscordEnabled)  CrtSendDiscord(message);
    if (Inp_TelegramEnabled) CrtSendTelegram(message);
}

//----------------------------------------------------------------------
// Event formatters
//----------------------------------------------------------------------

// Setup armed: C2 confirmed — waiting for C3 entry.
void CrtNotifySetupArmed(const CrtSetup &setup, ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf)
{
    if (!CrtNotifyIsFresh(setup.c2CloseTime)) return;
    string dir  = (setup.bias == CRT_BIAS_LONG) ? "LONG" : "SHORT";
    string slotL = CrtSlotLabel(slot, intradayTf);
    string msg = StringFormat(
        "[CRT] %s %s %s\n"
        "Setup armed — C2 confirmed\n"
        "C1: %.5f – %.5f  EQ: %.5f\n"
        "SL: %.5f  TP (EQ): %.5f\n"
        "Session: %s | %s",
        dir, _Symbol, slotL,
        setup.c1Low, setup.c1High, setup.c1EQ,
        setup.slLevel, setup.c1EQ,
        setup.sessionKey,
        CrtNYClockStr(TimeCurrent())
    );
    CrtNotifySend(msg);
}

// Entry fill.
void CrtNotifyFill(const CrtTrade &trade, const CrtSetup &setup,
                   ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf)
{
    if (!CrtNotifyIsFresh(trade.entryTime)) return;
    string dir   = trade.isLong ? "LONG" : "SHORT";
    string slotL = CrtSlotLabel(slot, intradayTf);
    string msg = StringFormat(
        "[CRT] FILL %s %s %s\n"
        "Entry: %.5f  Lots: %.2f\n"
        "SL: %.5f  TP: %.5f\n"
        "Session: %s | %s",
        dir, _Symbol, slotL,
        trade.entryPrice, trade.lots,
        trade.slPrice, trade.tpPrice,
        trade.sessionKey,
        CrtNYClockStr(trade.entryTime)
    );
    CrtNotifySend(msg);
}

// Exit (TP or SL).
void CrtNotifyExit(const CrtTrade &trade, double exitPrice,
                   const string exitReason, double pnl,
                   ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf)
{
    string dir   = trade.isLong ? "LONG" : "SHORT";
    string slotL = CrtSlotLabel(slot, intradayTf);
    string sign  = (pnl >= 0.0) ? "+" : "";
    string msg = StringFormat(
        "[CRT] EXIT %s %s %s\n"
        "Reason: %s\n"
        "Entry: %.5f  Exit: %.5f\n"
        "PnL: %s%.2f  Lots: %.2f\n"
        "Session: %s | %s",
        dir, _Symbol, slotL,
        exitReason,
        trade.entryPrice, exitPrice,
        sign, pnl, trade.lots,
        trade.sessionKey,
        CrtNYClockStr(TimeCurrent())
    );
    CrtNotifySend(msg);
}

// Limit cancelled (50% reached before fill, or manual invalidation).
void CrtNotifyCancelled(const CrtSetup &setup,
                        ENUM_CRT_SLOT slot, ENUM_CRT_INTRADAY_TF intradayTf,
                        const string reason)
{
    if (!CrtNotifyIsFresh(TimeCurrent())) return;
    string dir   = (setup.bias == CRT_BIAS_LONG) ? "LONG" : "SHORT";
    string slotL = CrtSlotLabel(slot, intradayTf);
    string msg = StringFormat(
        "[CRT] CANCELLED %s %s %s\n"
        "Reason: %s\n"
        "Session: %s | %s",
        dir, _Symbol, slotL,
        reason,
        setup.sessionKey,
        CrtNYClockStr(TimeCurrent())
    );
    CrtNotifySend(msg);
}

#endif // CRT_NOTIFY_MQH
