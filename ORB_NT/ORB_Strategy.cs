using System;
using System.ComponentModel.DataAnnotations;
using System.IO;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.NinjaScript.Strategies;

// ============================================================================
// ORB_Scalper — NinjaTrader 8 port
// Target: Tradeify Select $25,000 / MES (Micro E-Mini S&P 500)
//
// File layout:
//   ORB_Strategy.cs  — this file: NinjaScript Strategy class (lifecycle + wiring)
//   ORB_NT.cs        — DrawdownTracker, ConsistencyTracker, FastTradeTracker, ActiveTrade
//   ORB_Time.cs      — DST/UTC math
//   ORB_Sessions.cs  — SlotState, SessionLogic
//   ORB_Risk.cs      — contract sizing and margin
//   ORB_Execution.cs — trail/BE math helpers
//   ORB_News.cs      — news guard (live FF feed + historical CSV)
//   ORB_Dashboard.cs — corner-pinned TextFixed panel
//   ORB_Visuals.cs   — Draw.* wrappers
//   ORB_Notify.cs    — Discord/Telegram webhook layer
// ============================================================================

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public class ORB_Strategy : Strategy
    {
        //======================================================================
        // ── INPUTS ──
        //======================================================================
        #region Risk & Sizing
        [Display(Name = "Risk Percent", Order = 1, GroupName = "1 · Risk")]
        public double Risk_Percent { get; set; } = 1.0;

        [Display(Name = "Starting Balance", Order = 2, GroupName = "1 · Risk")]
        public double Starting_Balance { get; set; } = 25000.0;

        [Display(Name = "Drawdown Amount", Order = 3, GroupName = "1 · Risk")]
        public double Drawdown_Amount { get; set; } = 1500.0;  // Confirm with Tradeify for exact 25K figure

        [Display(Name = "Contract Mode", Order = 4, GroupName = "1 · Risk")]
        public ContractSizeMode Contract_Mode { get; set; } = ContractSizeMode.Micro;

        [Display(Name = "Max Contracts Override (0=auto)", Order = 5, GroupName = "1 · Risk")]
        public int Max_Contracts_Override { get; set; } = 0;

        [Display(Name = "Commission Per Contract Round Turn", Order = 6, GroupName = "1 · Risk")]
        public double Commission_Per_Contract { get; set; } = 4.0;  // Typical Rithmic/Tradovate rate
        #endregion

        #region Evaluation
        [Display(Name = "Eval Profit Target", Order = 1, GroupName = "2 · Evaluation")]
        public double Eval_Profit_Target { get; set; } = 1500.0;

        [Display(Name = "Enforce Consistency Rule", Order = 2, GroupName = "2 · Evaluation")]
        public bool Enforce_Consistency_Rule { get; set; } = false;  // Display-only by default

        [Display(Name = "Enable Daily Loss Limit", Order = 3, GroupName = "2 · Evaluation")]
        public bool Enable_Daily_Loss_Limit { get; set; } = false;

        [Display(Name = "Daily Loss Limit Amount", Order = 4, GroupName = "2 · Evaluation")]
        public double Daily_Loss_Limit_Amount { get; set; } = 500.0;
        #endregion

        #region Sessions
        [Display(Name = "Session Open Hour (NY)", Order = 1, GroupName = "3 · Sessions")]
        public int Session_Open_Hour_NY { get; set; } = 8;

        [Display(Name = "Session Open Minute (NY)", Order = 2, GroupName = "3 · Sessions")]
        public int Session_Open_NY_Min { get; set; } = 30;

        [Display(Name = "Range Minutes", Order = 3, GroupName = "3 · Sessions")]
        public int Range_Minutes { get; set; } = 120;

        [Display(Name = "Cutoff Minutes After Open", Order = 4, GroupName = "3 · Sessions")]
        public int Cutoff_Minutes { get; set; } = 660;

        [Display(Name = "Enable Slot 2 (Daily/Weekly)", Order = 5, GroupName = "3 · Sessions")]
        public bool Slot2_Enabled { get; set; } = false;

        [Display(Name = "Slot 2 Type", Order = 6, GroupName = "3 · Sessions")]
        public SessionType Slot2_Type { get; set; } = SessionType.Daily;
        #endregion

        #region Trade Management
        [Display(Name = "Fixed SL Ticks", Order = 1, GroupName = "4 ─ Trade Management")]
        public double Fixed_SL_Points { get; set; } = 40.0;  // Number of ticks (instrument-agnostic)

        [Display(Name = "Fixed TP Ticks", Order = 2, GroupName = "4 ─ Trade Management")]
        public double Fixed_TP_Points { get; set; } = 30.0;  // Number of ticks (instrument-agnostic)

        [Display(Name = "Trail Threshold Points", Order = 3, GroupName = "4 · Trade Management")]
        public double Trail_Threshold_Points { get; set; } = 12.0;

        [Display(Name = "Trail Gap Points", Order = 4, GroupName = "4 · Trade Management")]
        public double Trail_Gap_Points { get; set; } = 10.0;

        [Display(Name = "Breakeven Cost Points", Order = 5, GroupName = "4 · Trade Management")]
        public double BE_Cost_Points { get; set; } = 2.0;

        [Display(Name = "Trail Behavior", Order = 6, GroupName = "4 · Trade Management")]
        public TrailBehavior Trail_Behavior { get; set; } = TrailBehavior.Trail;

        [Display(Name = "Use OCO (cancel sibling on fill)", Order = 7, GroupName = "4 · Trade Management")]
        public bool Use_OCO { get; set; } = true;

        [Display(Name = "Use StopLimit Orders (buy at Bid / sell at Ask)", Order = 8, GroupName = "4 · Trade Management")]
        public bool Use_StopLimit_Orders { get; set; } = true;

        [Display(Name = "Use TP Slippage Pad (N/A for NT8 Unmanaged, kept for parity)", Order = 10, GroupName = "4 · Trade Management")]
        public bool Use_TP_Slippage_Pad { get; set; } = false;

        [Display(Name = "TP Slippage Pad Pct", Order = 11, GroupName = "4 · Trade Management")]
        public double TP_Slippage_Pad_Pct { get; set; } = 15.0;

        [Display(Name = "Flat by 4:59 PM ET", Order = 9, GroupName = "4 · Trade Management")]
        public bool Auto_Flat_EOD { get; set; } = true;
        #endregion

        #region News Guard
        [Display(Name = "News Guard Mode", Order = 1, GroupName = "5 · News Guard")]
        public NewsGuardMode News_Guard_Mode { get; set; } = NewsGuardMode.RedOnly;

        [Display(Name = "Block Minutes Before News", Order = 2, GroupName = "5 · News Guard")]
        public int News_Block_Before_Mins { get; set; } = 5;

        [Display(Name = "Block Minutes After News", Order = 3, GroupName = "5 · News Guard")]
        public int News_Block_After_Mins { get; set; } = 3;

        [Display(Name = "Freeze Trail During News", Order = 4, GroupName = "5 · News Guard")]
        public bool News_Freeze_Trail { get; set; } = true;

        [Display(Name = "Flatten Before News", Order = 5, GroupName = "5 · News Guard")]
        public bool News_Flatten_Before { get; set; } = false;

        [Display(Name = "Cancel Pending During News", Order = 6, GroupName = "5 · News Guard")]
        public bool News_Cancel_Pending { get; set; } = false;
        // Gate B strict mode activates when News_Guard_Mode != Off AND News_Flatten_Before AND News_Cancel_Pending are all true.
        #endregion

        #region Notifications
        [Display(Name = "Discord Webhook URL", Order = 1, GroupName = "6 · Notifications")]
        public string Discord_Webhook_URL { get; set; } = "https://discord.com/api/webhooks/1504886282730602526/1uncyB7UhyAFW8OfA8l8BAH_XulCLUVG_m4yLsWCKQqp7TvKZLTfBnKrSL9n1gGvTioR";

        [Display(Name = "Discord Enabled", Order = 2, GroupName = "6 · Notifications")]
        public bool Discord_Enabled { get; set; } = true;

        [Display(Name = "Telegram Bot Token", Order = 3, GroupName = "6 · Notifications")]
        public string Telegram_Bot_Token { get; set; } = "8858207904:AAHhhNSrZTdURzCIXNDMAz_ZChrzme3xjvc";

        [Display(Name = "Telegram Chat ID", Order = 4, GroupName = "6 · Notifications")]
        public string Telegram_Chat_ID { get; set; } = "-1003996863325|5";

        [Display(Name = "Telegram Enabled", Order = 5, GroupName = "6 · Notifications")]
        public bool Telegram_Enabled { get; set; } = true;
        #endregion

        //======================================================================
        // ── RUNTIME STATE ──
        //======================================================================
        private DrawdownTracker ddTracker;
        private ConsistencyTracker consistencyTracker;
        private FastTradeTracker fastTradeTracker;
        private ORB_News newsEngine;
        private ORB_Notify notifier;
        private SlotState slot1;
        private SlotState slot2;
        private ActiveTrade activeTrade;
        private bool isHalted = false;
        private int tradingDaysCompleted = 0;
        private DateTime lastDayClosedUTC = DateTime.MinValue;
        private double dailyStartBalance = 0;
        private PriorDayOHLC priorDayOhlc;
        private double dailyLoss = 0;
        // Seed with epoch seconds so OCO IDs are unique across strategy restarts/reloads
        private int ocoCounter = (int)(DateTime.UtcNow - new DateTime(2020, 1, 1)).TotalSeconds;

        // ── StopLimit Monitor State ──
        private bool slMonitorHigh = false;
        private bool slTrigDetHigh = false;
        private DateTime slTrigTimeHigh = DateTime.MinValue;
        private bool sl100CheckedHigh = false;
        private bool slWaitWatchHigh = false;
        private bool pendingMarketHigh = false;

        private bool slMonitorLow = false;
        private bool slTrigDetLow = false;
        private DateTime slTrigTimeLow = DateTime.MinValue;
        private bool sl100CheckedLow = false;
        private bool slWaitWatchLow = false;
        private bool pendingMarketLow = false;

        // ── Gate B strict-mode re-arm tracking ──
        private bool strictSweepDone   = false;  // one-shot guard per activation
        private bool strictRearmLong   = false;  // buy side cancelled unfilled → re-arm on clear
        private bool strictRearmShort  = false;  // sell side cancelled unfilled → re-arm on clear

        //======================================================================
        // ── NINJASCRIPT LIFECYCLE ──
        //======================================================================
        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "ORB_Scalper";
                Description = "Opening Range Breakout Scalper — NinjaTrader 8 port";
                Calculate = Calculate.OnEachTick;
                IsUnmanaged = true;
                IsExitOnSessionCloseStrategy = false; // We handle EOD flattening manually
            }
            else if (State == State.Configure)
            {
                // No additional data series needed for this build.
            }
            else if (State == State.DataLoaded)
            {
                if (Slot2_Enabled && Slot2_Type == SessionType.Daily)
                {
                    priorDayOhlc = PriorDayOHLC();
                }
                InitModules();
            }
            else if (State == State.Realtime)
            {
                // ── On every live start/reload, sweep any orphaned strategy orders ──
                // This handles the case where the strategy terminated mid-session and
                // left pending entry, SL, or TP orders the broker still holds.
                CancelAllStrategyOrders();
            }
            else if (State == State.Terminated)
            {
                CancelAllStrategyOrders();
            }
        }

        private void InitModules()
        {
            ddTracker = new DrawdownTracker(Starting_Balance, Drawdown_Amount);
            consistencyTracker = new ConsistencyTracker(Eval_Profit_Target);
            fastTradeTracker = new FastTradeTracker();

            slot1 = new SlotState(0) { IsEnabled = true, Type = SessionType.Intraday };
            slot2 = new SlotState(1) { IsEnabled = Slot2_Enabled, Type = Slot2_Type };

            bool isHistorical = (State == State.Historical);
            string strategyDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "NinjaTrader 8", "bin", "Custom", "Strategies", "ORB_NT");
            string historicalCsv = Path.Combine(strategyDir, "historical_calendar.csv");
            string liveCache = Path.Combine(strategyDir, "live_news_cache.json");

            newsEngine = new ORB_News(historicalCsv, liveCache, isHistorical);
            newsEngine.Initialize();

            notifier = new ORB_Notify(
                Discord_Webhook_URL, Telegram_Bot_Token, Telegram_Chat_ID,
                Discord_Enabled, Telegram_Enabled);

            dailyStartBalance = Account.Get(AccountItem.CashValue, Currency.UsDollar);
        }

        //======================================================================
        // ── ON BAR UPDATE (equivalent to OnTick in MT5) ──
        //======================================================================
        protected override void OnBarUpdate()
        {
            if (BarsInProgress != 0) return; // Only process primary series

            // In historical replay only run session range building — skip execution, risk, and visuals
            if (State == State.Historical)
            {
                UpdateSessionPhases(Time[0].ToUniversalTime());
                return;
            }

            DateTime currentUTC = Time[0].ToUniversalTime();
            double currentPrice = Close[0];
            double bid = GetCurrentBid();
            double ask = GetCurrentAsk();

            if (isHalted)
            {
                // Still drain notifications even when halted
                notifier?.DrainQueue();
                return;
            }

            // Refresh live news feed if needed (once per day, no-op for historical)
            newsEngine?.RefreshIfNeeded(currentUTC);

            // --- EOD Flatten Check (4:59 PM ET = 21:59 UTC in EDT, 22:59 UTC in EST) ---
            if (Auto_Flat_EOD) CheckEODFlatten(currentUTC);

            // --- Drawdown Circuit Breaker ---
            double liveCash = Account.Get(AccountItem.CashValue, Currency.UsDollar);
            if (ddTracker.IsBreach(liveCash))
            {
                Log("[ORB] DRAWDOWN FLOOR BREACHED! Halting strategy and flattening all positions.", LogLevel.Alert);
                FlattenAll("DrawdownBreach");
                isHalted = true;
                return;
            }

            // --- Daily Loss Limit ---
            if (Enable_Daily_Loss_Limit)
            {
                dailyLoss = dailyStartBalance - liveCash;
                if (dailyLoss >= Daily_Loss_Limit_Amount)
                {
                    Log("[ORB] Daily Loss Limit reached. Halting for today.", LogLevel.Warning);
                    FlattenAll("DailyLossLimit");
                    isHalted = true; // Will reset on next day session
                    return;
                }
            }

            // --- News: Flatten before event if configured ---
            if (News_Flatten_Before && newsEngine.IsNewsFlattening(currentUTC, News_Block_Before_Mins))
            {
                if (activeTrade != null) FlattenAll("NewsFlatten");
            }

            // --- Manage active trade (trail, BE) ---
            if (activeTrade != null)
                ManageTrade(currentUTC, bid, ask);

            // --- Session state machine ---
            UpdateSessionPhases(currentUTC);

            // --- Place breakout orders if conditions met ---
            PlaceBreakoutOrdersIfReady(currentUTC, bid, ask);
            
            // --- Monitor post-trigger stop-limit logic ---
            StopLimitMonitor(currentUTC, bid, ask);

            // --- Dashboard ---
            RenderDashboard(currentUTC, liveCash, bid, ask);

            // --- Drain notification queue ---
            notifier?.DrainQueue();
        }

        //======================================================================
        // ── ORDER CALLBACKS ──
        //======================================================================
        protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice,
            int quantity, int filled, double averageFillPrice,
            OrderState orderState, DateTime time, ErrorCode error, string nativeError)
        {
            if (error != ErrorCode.NoError)
            {
                Log(string.Format("[ORB] Order error: {0} / {1} on {2}", error, nativeError, order.Name), LogLevel.Error);

                // If an OCO submission fails, cancel everything to avoid orphaned orders
                if (orderState == OrderState.Rejected)
                {
                    Log("[ORB] Order rejected — sweeping all pending strategy orders to prevent duplicates.", LogLevel.Warning);
                    CancelAllStrategyOrders();
                    // Reset slot flags so orders can be re-placed next tick
                    if (slot1 != null) { slot1.LongOrderPlaced = false; slot1.ShortOrderPlaced = false; }
                    if (slot2 != null) { slot2.LongOrderPlaced = false; slot2.ShortOrderPlaced = false; }
                    activeTrade = null;
                }
            }

            // ── StopLimit Monitor: Cancel-then-Market execution guarantee ──
            if (orderState == OrderState.Cancelled && activeTrade != null)
            {
                if (order == activeTrade.EntryOrder && pendingMarketHigh)
                {
                    pendingMarketHigh = false;
                    activeTrade.EntryOrder = SubmitOrderUnmanaged(0, OrderAction.Buy, OrderType.Market, activeTrade.Contracts, 0, 0, activeTrade.OcoGroup, "LongEntryMkt");
                    Log("[ORB] Cancel confirmed. Submitted fallback Market Buy.", LogLevel.Information);
                }
                else if (order == activeTrade.OtherEntryOrder && pendingMarketLow)
                {
                    pendingMarketLow = false;
                    activeTrade.OtherEntryOrder = SubmitOrderUnmanaged(0, OrderAction.SellShort, OrderType.Market, activeTrade.Contracts, 0, 0, activeTrade.OcoGroup, "ShortEntryMkt");
                    Log("[ORB] Cancel confirmed. Submitted fallback Market SellShort.", LogLevel.Information);
                }
            }
        }

        protected override void OnExecutionUpdate(Execution execution, string executionId, double price,
            int quantity, MarketPosition marketPosition, string orderId, DateTime time)
        {
            // If an entry was filled, set up the position record and SL/TP brackets
            // Match against EITHER entry order since we don't know which side breaks out first
            bool longFilled  = activeTrade != null && execution.Order == activeTrade.EntryOrder      && execution.Order.OrderState == OrderState.Filled;
            bool shortFilled = activeTrade != null && execution.Order == activeTrade.OtherEntryOrder && execution.Order.OrderState == OrderState.Filled;

            if (longFilled || shortFilled)
            {
                // Normalize: EntryOrder = the filled one, OtherEntryOrder = the one to cancel
                if (shortFilled)
                {
                    var tmp = activeTrade.EntryOrder;
                    activeTrade.EntryOrder      = activeTrade.OtherEntryOrder;
                    activeTrade.OtherEntryOrder = tmp;
                }

                // Cancel the opposing entry order immediately — do NOT rely on NT's OCO mechanism
                if (activeTrade.OtherEntryOrder != null &&
                    activeTrade.OtherEntryOrder.OrderState != OrderState.Cancelled &&
                    activeTrade.OtherEntryOrder.OrderState != OrderState.Filled)
                {
                    CancelOrder(activeTrade.OtherEntryOrder);
                    Log("[ORB] Opposing entry order cancelled after fill.", LogLevel.Information);
                }

                double fillPx = execution.Price;
                bool isLong = (marketPosition == MarketPosition.Long);
                activeTrade.IsLong = isLong;
                activeTrade.EntryPrice = fillPx;
                activeTrade.EntryTime = time.ToUniversalTime();

                double intendedEntry = isLong ? (activeTrade.SlotIndex == 0 ? slot1.RangeHigh : slot2.RangeHigh) : 
                                                (activeTrade.SlotIndex == 0 ? slot1.RangeLow : slot2.RangeLow);
                
                double slipPts = Math.Abs(fillPx - intendedEntry) / TickSize;
                double slDistance = Fixed_SL_Points * TickSize;
                double tpDistance = Fixed_TP_Points * TickSize;

                Log(string.Format("[ORB] Fill at {0:F5} (slip={1:F1} ticks). Brackets set to standard geometry.", fillPx, slipPts), LogLevel.Information);

                double slPx = isLong ? fillPx - slDistance : fillPx + slDistance;
                double tpPx = isLong ? fillPx + tpDistance : fillPx - tpDistance;
                
                activeTrade.VirtualSL = slPx;

                ORB_Execution.PlaceBracketOrders(this, isLong, fillPx, execution.Quantity,
                    slDistance, tpDistance, activeTrade.OcoGroup);

                // Draw SL and TP lines on the chart
                if (State == State.Realtime)
                {
                    string tag = activeTrade.OcoGroup;
                    ORB_Visuals.DrawHLine(this, tag + "_SL", slPx,
                        isLong ? System.Windows.Media.Brushes.OrangeRed  : System.Windows.Media.Brushes.LimeGreen,
                        DashStyleHelper.Solid);
                    ORB_Visuals.DrawHLine(this, tag + "_TP", tpPx,
                        isLong ? System.Windows.Media.Brushes.LimeGreen : System.Windows.Media.Brushes.OrangeRed,
                        DashStyleHelper.Solid);
                    // NT8 Draw.Text: (owner, tag, isAutoScale, text, barsAgo, y, yOffset, brush, font, alignment, areaBrush, areaOutline, opacity)
                    Draw.Text(this, tag + "_SL_Label", false,
                        string.Format("SL {0:F2}", slPx), 0, slPx, -12,
                        System.Windows.Media.Brushes.OrangeRed,
                        new NinjaTrader.Gui.Tools.SimpleFont("Arial", 9) { Bold = true },
                        System.Windows.TextAlignment.Right,
                        System.Windows.Media.Brushes.Transparent,
                        System.Windows.Media.Brushes.Transparent, 0);
                    Draw.Text(this, tag + "_TP_Label", false,
                        string.Format("TP {0:F2}", tpPx), 0, tpPx, 12,
                        System.Windows.Media.Brushes.LimeGreen,
                        new NinjaTrader.Gui.Tools.SimpleFont("Arial", 9) { Bold = true },
                        System.Windows.TextAlignment.Right,
                        System.Windows.Media.Brushes.Transparent,
                        System.Windows.Media.Brushes.Transparent, 0);
                }

                notifier?.NotifyFill(execution.Order.Id, slot1.SessionKey, isLong, fillPx, slPx, tpPx, execution.Quantity);
                Log(string.Format("[ORB] Entry filled: {0} @ {1:F2}, SL={2:F2}, TP={3:F2}",
                    isLong ? "LONG" : "SHORT", fillPx, slPx, tpPx), LogLevel.Information);
            }

            // Position closed (SL or TP hit)
            if (activeTrade != null &&
                (execution.Order == activeTrade.SlOrder || execution.Order == activeTrade.TpOrder) &&
                execution.Order.OrderState == OrderState.Filled)
            {
                double pnl = Position.GetUnrealizedProfitLoss(PerformanceUnit.Currency, execution.Price);
                DateTime closeUTC = time.ToUniversalTime();
                double holdSecs = (closeUTC - activeTrade.EntryTime).TotalSeconds;

                consistencyTracker.RecordTrade(closeUTC.Date, pnl);
                fastTradeTracker.RecordTrade(holdSecs, pnl);

                if (closeUTC.Date > lastDayClosedUTC.Date)
                {
                    tradingDaysCompleted++;
                    ddTracker.OnDayClose(Account.Get(AccountItem.CashValue, Currency.UsDollar));
                    lastDayClosedUTC = closeUTC;
                }

                notifier?.NotifyResult(execution.Order.Id, slot1.SessionKey, activeTrade.IsLong,
                    pnl, activeTrade.EntryPrice, execution.Price, slot1.SessionKey,
                    Account.Get(AccountItem.CashValue, Currency.UsDollar));

                activeTrade = null;
            }
        }

        //======================================================================
        // ── SESSION STATE MACHINE ──
        //======================================================================
        private void UpdateSessionPhases(DateTime currentUTC)
        {
            // Compute slot1 window times from session open
            DateTime sessionOpenUTC = ORB_Time.GetSessionOpenUTC(currentUTC, Session_Open_Hour_NY, Session_Open_NY_Min);
            slot1.RangeStartTimeUTC = sessionOpenUTC;
            slot1.RangeEndTimeUTC = sessionOpenUTC.AddMinutes(Range_Minutes);
            slot1.CutoffTimeUTC = sessionOpenUTC.AddMinutes(Cutoff_Minutes);
            slot1.SessionKey = string.Format("NY{0:yyyyMMdd}", ORB_Time.UTCToNY(currentUTC));

            SessionLogic.UpdateSlotPhase(slot1, currentUTC);

            // In the range window, update high/low
            if (slot1.Phase == SessionPhase.RangeForming && !slot1.IsRangeLocked)
            {
                slot1.UpdateRange(High[0], Low[0]);
            }

            // Lock range when window closes
            if (slot1.Phase == SessionPhase.TradingWindow && !slot1.IsRangeLocked)
            {
                slot1.IsRangeLocked = true;
                Log(string.Format("[ORB] Range locked: H={0:F2} L={1:F2}", slot1.RangeHigh, slot1.RangeLow),
                    LogLevel.Information);
            }

            // Draw range box every tick once locked — persists across reloads and timeframe changes
            if (slot1.IsRangeLocked && slot1.RangeHigh > 0 && slot1.RangeLow > 0 && State == State.Realtime)
            {
                ORB_Visuals.DrawRangeBox(this, "RangeBox_Slot0",
                    slot1.RangeStartTimeUTC, slot1.RangeEndTimeUTC,
                    slot1.RangeHigh, slot1.RangeLow,
                    System.Windows.Media.Brushes.DodgerBlue, System.Windows.Media.Brushes.SteelBlue, true);
                ORB_Visuals.DrawHLine(this, "RangeHigh_Line_Slot0", slot1.RangeHigh,
                    System.Windows.Media.Brushes.LimeGreen, DashStyleHelper.Dash);
                ORB_Visuals.DrawHLine(this, "RangeLow_Line_Slot0", slot1.RangeLow,
                    System.Windows.Media.Brushes.OrangeRed, DashStyleHelper.Dash);
            }

            // Reset slot at end of trading window
            if (slot1.Phase == SessionPhase.Closed && slot1.IsRangeLocked)
            {
                slot1.Reset();
            }

            // CME maintenance gap guard
            if (ORB_Time.IsMaintenanceGap(currentUTC))
            {
                slot1.Phase = SessionPhase.Waiting;
            }

            if (slot2.IsEnabled && slot2.Type == SessionType.Daily)
            {
                sessionOpenUTC = ORB_Time.GetSessionOpenUTC(currentUTC, Session_Open_Hour_NY, Session_Open_NY_Min);
                slot2.RangeStartTimeUTC = sessionOpenUTC;
                slot2.RangeEndTimeUTC = sessionOpenUTC; // Formed immediately
                slot2.CutoffTimeUTC = sessionOpenUTC.AddMinutes(Cutoff_Minutes); 
                slot2.SessionKey = string.Format("D{0:yyyyMMdd}", ORB_Time.UTCToNY(currentUTC));
                
                SessionLogic.UpdateSlotPhase(slot2, currentUTC);
                
                if (slot2.Phase == SessionPhase.TradingWindow && !slot2.IsRangeLocked)
                {
                    if (priorDayOhlc != null && priorDayOhlc.PriorHigh.IsValidDataPoint(0))
                    {
                        slot2.RangeHigh = priorDayOhlc.PriorHigh[0];
                        slot2.RangeLow = priorDayOhlc.PriorLow[0];
                        slot2.IsRangeLocked = true;
                        Log(string.Format("[ORB] Slot 2 (Daily) Range locked: H={0:F2} L={1:F2}", slot2.RangeHigh, slot2.RangeLow), LogLevel.Information);
                    }
                }

                // Draw slot2 range box every tick once locked
                if (slot2.IsRangeLocked && slot2.RangeHigh > 0 && slot2.RangeLow > 0 && State == State.Realtime)
                {
                    ORB_Visuals.DrawRangeBox(this, "RangeBox_Slot1",
                        slot2.RangeStartTimeUTC, slot2.RangeEndTimeUTC,
                        slot2.RangeHigh, slot2.RangeLow,
                        System.Windows.Media.Brushes.Gold, System.Windows.Media.Brushes.DarkGoldenrod, true);
                    ORB_Visuals.DrawHLine(this, "RangeHigh_Line_Slot1", slot2.RangeHigh,
                        System.Windows.Media.Brushes.Gold, DashStyleHelper.Dash);
                    ORB_Visuals.DrawHLine(this, "RangeLow_Line_Slot1", slot2.RangeLow,
                        System.Windows.Media.Brushes.Goldenrod, DashStyleHelper.Dash);
                }
                
                if (slot2.Phase == SessionPhase.Closed && slot2.IsRangeLocked)
                {
                    slot2.Reset();
                }

                if (ORB_Time.IsMaintenanceGap(currentUTC))
                {
                    slot2.Phase = SessionPhase.Waiting;
                }
            }
        }

        //======================================================================
        // ── ORDER PLACEMENT ──
        //======================================================================
        private void PlaceBreakoutOrdersIfReady(DateTime currentUTC, double bid, double ask)
        {
            if (activeTrade != null) return; // Already in a trade
            
            SlotState activeSlot = null;
            if (slot1.IsEnabled && slot1.Phase == SessionPhase.TradingWindow && slot1.IsRangeLocked && (!slot1.LongOrderPlaced || !slot1.ShortOrderPlaced))
                activeSlot = slot1;
            else if (slot2.IsEnabled && slot2.Phase == SessionPhase.TradingWindow && slot2.IsRangeLocked && (!slot2.LongOrderPlaced || !slot2.ShortOrderPlaced))
                activeSlot = slot2;

            if (activeSlot == null) return;

            // Guard: range must be valid before placing orders
            if (activeSlot.RangeHigh <= 0 || activeSlot.RangeLow <= 0 ||
                activeSlot.RangeHigh == double.MinValue || activeSlot.RangeLow == double.MaxValue ||
                activeSlot.RangeHigh <= activeSlot.RangeLow)
            {
                Log(string.Format("[ORB] Slot {0} range invalid (H={1:F2} L={2:F2}) — skipping order placement.",
                    activeSlot == slot1 ? 1 : 2, activeSlot.RangeHigh, activeSlot.RangeLow), LogLevel.Warning);
                return;
            }

            // News blackout check
            if (News_Guard_Mode != NewsGuardMode.Off && newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins))
            {
                return;
            }

            double liveCash = Account.Get(AccountItem.CashValue, Currency.UsDollar);
            if (liveCash <= 0) liveCash = Starting_Balance; // Fallback for historical/Sim

            double pointValue = Instrument.MasterInstrument.PointValue;
            // Fixed_SL_Points is in ticks; CalcContracts expects SL in points (price units)
            double slPriceDistance = Fixed_SL_Points * TickSize;
            int contracts = ORB_Risk.CalcContracts(
                liveCash, Risk_Percent,
                slPriceDistance,
                pointValue,
                Contract_Mode, Max_Contracts_Override);

            if (contracts < 1 && Max_Contracts_Override > 0)
                contracts = Max_Contracts_Override;

            double marginPerContract = ORB_Risk.GetMarginPerContract(Instrument.MasterInstrument.Name);
            double freeMargin = Account.Get(AccountItem.ExcessIntradayMargin, Currency.UsDollar);
            if (freeMargin > 0)
            {
                double marginBudget = ORB_Risk.MarginBudget(freeMargin, 90.0);
                contracts = ORB_Risk.MarginCappedContracts(contracts, marginBudget, marginPerContract);
            }

            if (contracts < 1) 
            {
                Log("[ORB] Skipping orders: computed contracts < 1. Check Risk Percent, Margin, and Max Contracts.", LogLevel.Warning);
                return;
            }

            string ocoGroup = string.Format("ORB_OCO_{0}", ++ocoCounter);
            activeTrade = new ActiveTrade
            {
                OcoGroup = ocoGroup,
                Contracts = contracts,
                IsLong = false,
                EntryPrice = 0,
                VirtualSL = 0,
                TrailingActivated = false,
                BreakevenSet = false,
                EntryTime = DateTime.MinValue,
                EntryOrder = null,
                SlOrder = null,
                SlotIndex = activeSlot == slot1 ? 0 : 1
            };

            var (longOrder, shortOrder) = ORB_Execution.PlacePendingEntryOCO(this, activeSlot.RangeHigh, activeSlot.RangeLow, contracts, ocoGroup, Use_StopLimit_Orders);
            // Store both pending entry references so we can cancel the losing side explicitly when one fills
            activeTrade.EntryOrder      = longOrder;   // will be corrected in OnExecutionUpdate to whichever fills
            activeTrade.OtherEntryOrder = shortOrder;  // will be corrected on fill too
            activeSlot.LongOrderPlaced = true;
            activeSlot.ShortOrderPlaced = true;

            notifier?.NotifySetup(ocoCounter, activeSlot.SessionKey, true,
                activeSlot.RangeHigh, activeSlot.RangeLow, activeSlot.RangeHigh, 0, 0, "NY");

            Log(string.Format("[ORB] Pending OCO placed for Slot {0}: RangeH={1:F2}, RangeL={2:F2}, Contracts={3}",
                (activeSlot == slot1 ? 1 : 2), activeSlot.RangeHigh, activeSlot.RangeLow, contracts), LogLevel.Information);
        }

        // NOTE (Gap-1): deliberately matches both Working StopLimit (pre-trigger) and any
        // other Working state (post-trigger, now a resting limit).  Gate B sweeps ALL working
        // entry orders regardless of phase — a triggered-but-unfilled order mid-wait-and-watch
        // is "pending/unfilled" for re-arm purposes, exactly like one that never triggered.
        private void StopLimitMonitor(DateTime currentUTC, double bid, double ask)
        {
            if (!Use_StopLimit_Orders || activeTrade == null) return;

            bool isStrictMode = News_Guard_Mode != NewsGuardMode.Off
                                && News_Flatten_Before && News_Cancel_Pending
                                && newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins)
                                && newsEngine.IsNewsFlattening(currentUTC, News_Block_Before_Mins);

            // ── Gate B: strict mode ────────────────────────────────────────────────────
            if (isStrictMode)
            {
                if (!strictSweepDone)
                {
                    strictSweepDone  = true;
                    strictRearmLong  = false;
                    strictRearmShort = false;

                    // Cancel all working entry orders (pre- and post-trigger, Gap-1)
                    Order[] allOrders = new[] { activeTrade.EntryOrder, activeTrade.OtherEntryOrder };
                    foreach (var ord in allOrders)
                    {
                        if (ord == null) continue;
                        if (ord.OrderState != OrderState.Working && ord.OrderState != OrderState.Accepted) continue;
                        bool isBuy = ord.OrderAction == OrderAction.Buy;
                        // Mark re-arm BEFORE cancel
                        if (isBuy)   strictRearmLong  = true;
                        else         strictRearmShort = true;
                        CancelOrder(ord);
                        SLResetSideState(isBuy);  // Gap-2: wipe phase flags immediately
                        Log(string.Format("[ORB] Gate B sweep: cancelled {0} entry order (news strict mode).",
                                          isBuy ? "BUY" : "SELL"), LogLevel.Warning);
                    }

                    // Flatten all open positions
                    if (Position.MarketPosition != MarketPosition.Flat)
                    {
                        bool wasLong = Position.MarketPosition == MarketPosition.Long;
                        // Filled-then-flattened → stays consumed: clear the re-arm flag
                        if (wasLong) strictRearmLong  = false;
                        else         strictRearmShort = false;
                        FlattenAll("GateBNewsFlat");
                        Log("[ORB] Gate B sweep: flattened position (news strict mode).", LogLevel.Warning);
                    }

                    Log(string.Format("[ORB] Gate B sweep complete. Re-arm Long={0} Short={1}.",
                                      strictRearmLong, strictRearmShort), LogLevel.Information);
                }
                return; // Gate B active — no further evaluation
            }
            else if (strictSweepDone)
            {
                // Gate B just cleared — apply re-arm if flagged, then reset guard
                if (strictRearmLong  && slot1 != null) { slot1.LongOrderPlaced  = false; Log("[ORB] Gate B cleared: re-arming Long side.",  LogLevel.Information); }
                if (strictRearmShort && slot1 != null) { slot1.ShortOrderPlaced = false; Log("[ORB] Gate B cleared: re-arming Short side.", LogLevel.Information); }
                activeTrade        = null;  // drop the trade handle so PlaceBreakoutOrdersIfReady re-arms
                strictSweepDone  = false;
                strictRearmLong  = false;
                strictRearmShort = false;
            }

            // ── Gate A: EA must not act; resting orders can still fill naturally ────────
            bool gateA = (News_Freeze_Trail && newsEngine.IsNewsFreezingTrail(currentUTC, News_Block_Before_Mins, News_Block_After_Mins))
                      || (News_Guard_Mode != NewsGuardMode.Off && newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins));
            if (gateA) return;

            // ── Normal per-side evaluation ───────────────────────────────────────────────────
            if (activeTrade.EntryOrder == null && activeTrade.OtherEntryOrder == null) return;

            Order buyOrder  = (activeTrade.EntryOrder?.OrderAction == OrderAction.Buy)       ? activeTrade.EntryOrder :
                             (activeTrade.OtherEntryOrder?.OrderAction == OrderAction.Buy    ? activeTrade.OtherEntryOrder : null);
            Order sellOrder = (activeTrade.EntryOrder?.OrderAction == OrderAction.SellShort) ? activeTrade.EntryOrder :
                             (activeTrade.OtherEntryOrder?.OrderAction == OrderAction.SellShort ? activeTrade.OtherEntryOrder : null);

            if (buyOrder != null && buyOrder.OrderState == OrderState.Working)
            {
                if (!slMonitorHigh) slMonitorHigh = true;
                StopLimitMonitorLogic(true, buyOrder, currentUTC, bid, ask);
                // Log OnOrderUpdate state for observability (per user requirement)
                Log(string.Format("[ORB] [SL Monitor] BUY order state: {0}", buyOrder.OrderState), LogLevel.Information);
            }
            else slMonitorHigh = false;

            if (sellOrder != null && sellOrder.OrderState == OrderState.Working)
            {
                if (!slMonitorLow) slMonitorLow = true;
                StopLimitMonitorLogic(false, sellOrder, currentUTC, bid, ask);
                Log(string.Format("[ORB] [SL Monitor] SELL order state: {0}", sellOrder.OrderState), LogLevel.Information);
            }
            else slMonitorLow = false;
        }

        private void StopLimitMonitorLogic(bool isHigh, Order order, DateTime currentUTC, double bid, double ask)
        {
            double stopPx = isHigh ? (activeTrade.SlotIndex == 0 ? slot1.RangeHigh : slot2.RangeHigh) : (activeTrade.SlotIndex == 0 ? slot1.RangeLow : slot2.RangeLow);
            double tpDist = Fixed_TP_Points * TickSize;
            double pct10 = isHigh ? stopPx + 0.10 * tpDist : stopPx - 0.10 * tpDist;
            double pct25 = isHigh ? stopPx + 0.25 * tpDist : stopPx - 0.25 * tpDist;
            double pct50 = isHigh ? stopPx + 0.50 * tpDist : stopPx - 0.50 * tpDist;
            double priceFwd = isHigh ? ask : bid;

            bool trigDet = isHigh ? slTrigDetHigh : slTrigDetLow;
            DateTime trigTime = isHigh ? slTrigTimeHigh : slTrigTimeLow;
            bool done100 = isHigh ? sl100CheckedHigh : sl100CheckedLow;
            bool waitWatch = isHigh ? slWaitWatchHigh : slWaitWatchLow;

            // Detect trigger by crossing StopPrice
            if (!trigDet)
            {
                bool triggered = isHigh ? (priceFwd >= stopPx) : (priceFwd <= stopPx);
                if (triggered)
                {
                    trigDet = true;
                    trigTime = currentUTC;
                    if (isHigh) { slTrigDetHigh = true; slTrigTimeHigh = trigTime; }
                    else { slTrigDetLow = true; slTrigTimeLow = trigTime; }
                    Log(string.Format("[ORB] {0} StopLimit crossed stopPx ({1:F2}) @ {2:F2}. Monitoring 100ms.", isHigh ? "High" : "Low", stopPx, priceFwd), LogLevel.Information);
                }
            }

            if (trigDet)
            {
                bool past50 = isHigh ? (priceFwd >= pct50) : (priceFwd <= pct50);
                if (past50)
                {
                    Log(string.Format("[ORB] {0} price {1:F2} hit 50% zone. Cancelling order and skipping.", isHigh ? "High" : "Low", priceFwd), LogLevel.Information);
                    CancelOrder(order);
                    if (isHigh) slMonitorHigh = false; else slMonitorLow = false;
                    return;
                }

                if (!done100 && (currentUTC - trigTime).TotalMilliseconds >= 100)
                {
                    if (isHigh) sl100CheckedHigh = true; else sl100CheckedLow = true;
                    bool past25 = isHigh ? (priceFwd >= pct25) : (priceFwd <= pct25);
                    if (!past25)
                    {
                        Log(string.Format("[ORB] {0} unfilled at 100ms, price {1:F2} < 25% zone. Forcing Market.", isHigh ? "High" : "Low", priceFwd), LogLevel.Information);
                        ForceMarketExecution(isHigh, order);
                        return;
                    }
                    else
                    {
                        Log(string.Format("[ORB] {0} unfilled at 100ms, price {1:F2} in 25-50% zone. Waiting.", isHigh ? "High" : "Low", priceFwd), LogLevel.Information);
                        if (isHigh) slWaitWatchHigh = true; else slWaitWatchLow = true;
                    }
                }

                if (done100 && waitWatch)
                {
                    bool backTo10 = isHigh ? (priceFwd <= pct10) : (priceFwd >= pct10);
                    if (backTo10)
                    {
                        Log(string.Format("[ORB] {0} retraced to 10% zone @ {1:F2}. Forcing Market.", isHigh ? "High" : "Low", priceFwd), LogLevel.Information);
                        ForceMarketExecution(isHigh, order);
                    }
                }
            }
        }

        // ── Reset all per-side state machine flags to clean "never started" state (Gap-2) ────
        private void SLResetSideState(bool isLong)
        {
            if (isLong)  { slMonitorHigh = false; slTrigDetHigh = false; slTrigTimeHigh = DateTime.MinValue; sl100CheckedHigh = false; slWaitWatchHigh = false; pendingMarketHigh = false; }
            else         { slMonitorLow  = false; slTrigDetLow  = false; slTrigTimeLow  = DateTime.MinValue; sl100CheckedLow  = false; slWaitWatchLow  = false; pendingMarketLow  = false; }
        }

        private void ForceMarketExecution(bool isHigh, Order order)
        {
            CancelOrder(order);
            if (isHigh)
            {
                pendingMarketHigh = true;
                slMonitorHigh = false;
            }
            else
            {
                pendingMarketLow = true;
                slMonitorLow = false;
            }
        }

        //======================================================================
        // ── TRAIL / BE MANAGEMENT ──
        //======================================================================
        private void ManageTrade(DateTime currentUTC, double bid, double ask)
        {
            if (activeTrade == null) return;
            if (activeTrade.SlOrder == null) return;

            // Freeze trailing during news if configured
            if (News_Freeze_Trail && newsEngine.IsNewsFreezingTrail(currentUTC, News_Block_Before_Mins, News_Block_After_Mins))
                return;

            double currentPrice = activeTrade.IsLong ? bid : ask;
            double newSL = activeTrade.VirtualSL;

            if (Trail_Behavior == TrailBehavior.Trail)
            {
                newSL = ORB_Execution.CalculateTrailingStop(
                    activeTrade.IsLong, currentPrice, activeTrade.EntryPrice,
                    activeTrade.VirtualSL,
                    Trail_Threshold_Points * TickSize,
                    Trail_Gap_Points * TickSize,
                    TickSize);
            }
            else if (Trail_Behavior == TrailBehavior.Breakeven && !activeTrade.BreakevenSet)
            {
                newSL = ORB_Execution.CalculateBreakevenStop(
                    activeTrade.IsLong, currentPrice, activeTrade.EntryPrice,
                    activeTrade.VirtualSL,
                    Trail_Threshold_Points * TickSize,
                    BE_Cost_Points * TickSize,
                    TickSize);
            }

            // If SL improved, submit the modification
            bool improved = activeTrade.IsLong
                ? newSL > activeTrade.VirtualSL + TickSize
                : newSL < activeTrade.VirtualSL - TickSize;

            if (improved && activeTrade.SlOrder != null && activeTrade.SlOrder.OrderState == OrderState.Working)
            {
                ChangeOrder(activeTrade.SlOrder, activeTrade.SlOrder.Quantity, 0, newSL);
                bool firstTrail = !activeTrade.TrailingActivated;
                activeTrade.VirtualSL = newSL;
                activeTrade.TrailingActivated = true;
                if (Trail_Behavior == TrailBehavior.Breakeven) activeTrade.BreakevenSet = true;

                if (firstTrail)
                {
                    notifier?.NotifyTrail(activeTrade.EntryOrder?.Id ?? 0, slot1.SessionKey,
                        activeTrade.IsLong, newSL);
                    Log(string.Format("[ORB] Trail activated: SL moved to {0:F2}", newSL), LogLevel.Information);
                }
            }
        }

        //======================================================================
        // ── EOD FLATTEN ──
        //======================================================================
        private void CheckEODFlatten(DateTime currentUTC)
        {
            DateTime nyTime = ORB_Time.UTCToNY(currentUTC);
            // 4:59 PM ET = flatten time
            bool isEOD = nyTime.Hour == 16 && nyTime.Minute >= 59;
            if (isEOD && activeTrade != null)
            {
                Log("[ORB] EOD flatten: closing position at 4:59 PM ET.", LogLevel.Information);
                FlattenAll("EOD");
            }

            // Also reset daily tracking variables at session start (6:00 PM ET)
            bool isNewDay = nyTime.Hour == 18 && nyTime.Minute == 0;
            if (isNewDay)
            {
                dailyStartBalance = Account.Get(AccountItem.CashValue, Currency.UsDollar);
                dailyLoss = 0;
                isHalted = false; // Re-enable after DLL halt
                ddTracker.OnDayClose(dailyStartBalance);
            }
        }

        //======================================================================
        // ── HELPERS ──
        //======================================================================
        private static readonly string[] OrbSignalNames = { "LongEntry", "ShortEntry", "LongSL", "LongTP", "ShortSL", "ShortTP" };

        private void CancelAllStrategyOrders()
        {
            // 1. Cancel all orders in THIS strategy instance's Orders collection (fast path)
            foreach (Order o in Orders)
            {
                if (o.OrderState == OrderState.Working  ||
                    o.OrderState == OrderState.Accepted ||
                    o.OrderState == OrderState.Submitted ||
                    o.OrderState == OrderState.PartFilled)
                {
                    try { CancelOrder(o); } catch { }
                }
            }

            // 2. Sweep account-level orders by signal name to catch orphans from crashed instances
            //    This is the key fix: previous strategy instances leave behind working orders
            //    that are invisible to the new instance's Orders collection.
            foreach (Order o in Account.Orders)
            {
                if (o.Instrument != Instrument) continue;
                if (o.OrderState != OrderState.Working  &&
                    o.OrderState != OrderState.Accepted &&
                    o.OrderState != OrderState.Submitted &&
                    o.OrderState != OrderState.PartFilled) continue;

                // Match by signal name (all ORB orders use known names)
                foreach (string sigName in OrbSignalNames)
                {
                    if (o.Name == sigName)
                    {
                        try { CancelOrder(o); } catch { }
                        break;
                    }
                }
            }

            // 3. Explicitly cancel from activeTrade references as a final safety net
            if (activeTrade != null)
            {
                TryCancelOrder(activeTrade.EntryOrder);
                TryCancelOrder(activeTrade.OtherEntryOrder);
                TryCancelOrder(activeTrade.SlOrder);
                TryCancelOrder(activeTrade.TpOrder);
            }
        }

        private void TryCancelOrder(Order o)
        {
            if (o == null) return;
            if (o.OrderState == OrderState.Working   ||
                o.OrderState == OrderState.Accepted  ||
                o.OrderState == OrderState.Submitted ||
                o.OrderState == OrderState.PartFilled)
            {
                try { CancelOrder(o); } catch { }
            }
        }

        private void FlattenAll(string reason)
        {
            if (Position.MarketPosition != MarketPosition.Flat)
            {
                CloseStrategy(reason);
                Log(string.Format("[ORB] Flattened all positions. Reason: {0}", reason), LogLevel.Warning);
            }
            activeTrade = null;
        }

        //======================================================================
        // ── DASHBOARD ──
        //======================================================================
        private void RenderDashboard(DateTime currentUTC, double liveCash, double bid, double ask)
        {
            if (State == State.Historical) return;

            double evalProgress = consistencyTracker.TotalProfit;
            double currentPrice = activeTrade != null ? (activeTrade.IsLong ? bid : ask) : 0;

            double liveRR = 0;
            if (activeTrade != null && activeTrade.EntryPrice > 0)
            {
                double profitPts = activeTrade.IsLong
                    ? (currentPrice - activeTrade.EntryPrice) / TickSize
                    : (activeTrade.EntryPrice - currentPrice) / TickSize;
                liveRR = Fixed_SL_Points > 0 ? profitPts / Fixed_SL_Points : 0;
            }

            int secsToNext = 0;
            if (slot1.Phase == SessionPhase.Waiting)
                secsToNext = (int)(slot1.RangeStartTimeUTC - currentUTC).TotalSeconds;
            else if (slot1.Phase == SessionPhase.RangeForming)
                secsToNext = (int)(slot1.RangeEndTimeUTC - currentUTC).TotalSeconds;
            else if (slot1.Phase == SessionPhase.TradingWindow)
                secsToNext = (int)(slot1.CutoffTimeUTC - currentUTC).TotalSeconds;

            var dashState = new ORBDashState
            {
                CurrentBalance = liveCash,
                DrawdownFloor = ddTracker.CurrentFloor,
                FloorLocked = ddTracker.IsFloorLocked,
                DistanceToFloor = liveCash - ddTracker.CurrentFloor,
                ConsistencyPctOfTotal = consistencyTracker.ConsistencyPctOfTotal,
                EvalProfitTarget = Eval_Profit_Target,
                EvalProfitProgress = evalProgress,
                TradingDaysCompleted = tradingDaysCompleted,
                FastTradePct = fastTradeTracker.FastTradePct,
                ConsistencyWarning = consistencyTracker.IsConsistencyWarning,

                ActiveSession = "NY",
                SessionPhase = slot1.Phase.ToString(),
                SecsToNextPhase = Math.Max(0, secsToNext),
                RangeHigh = slot1.RangeHigh == double.MinValue ? 0 : slot1.RangeHigh,
                RangeLow = slot1.RangeLow == double.MaxValue ? 0 : slot1.RangeLow,
                Slot1Active = slot1.IsEnabled && slot1.Phase != SessionPhase.Closed,
                Slot2Active = slot2.IsEnabled,
                Slot2Mode = Slot2_Type.ToString(),

                InTrade = activeTrade != null,
                TradeDir = activeTrade != null ? (activeTrade.IsLong ? "LONG" : "SHORT") : "",
                EntryPrice = activeTrade?.EntryPrice ?? 0,
                StopLoss = activeTrade?.VirtualSL ?? 0,
                TakeProfit = activeTrade != null && activeTrade.EntryPrice > 0
                    ? (activeTrade.IsLong
                        ? activeTrade.EntryPrice + Fixed_TP_Points * TickSize
                        : activeTrade.EntryPrice - Fixed_TP_Points * TickSize)
                    : 0,
                ContractCount = activeTrade?.Contracts ?? 0,
                ContractMode = Contract_Mode.ToString(),
                LiveRR = liveRR,
                BEActive = activeTrade?.BreakevenSet ?? false,
                BEDetail = activeTrade?.BreakevenSet == true ? "@ entry" : "",

                NewsBlackoutActive = News_Guard_Mode != NewsGuardMode.Off && newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins),
                NextNewsEvent = newsEngine.GetNextEventDescription(currentUTC),
                NewsSourceMode = State == State.Historical ? "Historical (Backtest)" : "Live (FF)"
            };

            ORB_Dashboard.Render(this, dashState);
        }
    }

    //======================================================================
    // Supporting enums referenced from strategy inputs
    //======================================================================
    public enum TrailBehavior
    {
        Trail,
        Breakeven,
        Off
    }
}
