using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.IO;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies;

// ============================================================================
// ORB_Scalper — NinjaTrader 8 port of ORB_Scalper.mq5 (full 6-slot engine)
//
// Slot mapping mirrors MT5 SetSlotContext()/SlotEnabled():
//   0 = NY intraday   1 = London intraday   2 = Asian intraday
//   3 = Daily HTF     4 = Weekly HTF        5 = Monthly HTF
//
// Defaults match "GC-Daily-London-NY-ORB.set" (MT5 GC profile):
//   NY 8:00 + London 0:00 enabled, Daily HTF enabled, 120-min trigger candle,
//   Instant Market Execution ON (max entry slippage 10 ticks),
//   SL 40 / TP 35 ticks, trail 12/10 ticks, slip force-close at +2 ticks,
//   news: RedOnly 5/5, cancel-pending + freeze-trail + flatten-before ON,
//   Discord/Telegram OFF by default.
//   (MT5 "points" on GC are $0.01 price units; NT GC tick = $0.10 → ÷10.)
//
// Key MT5-parity subsystems in this file:
//   - Instant Market Execution: tick-triggered market entry at the range
//     level, SKIPPED (never chased) when price has slipped beyond
//     Instant_Max_Entry_Slippage_Ticks. This is the reason for the NT8 port.
//   - Slip force-close: fills beyond Max_Slippage_Ticks keep their brackets
//     but trailing is replaced by close-at-market once profit reaches
//     Slip_ForceClose_Profit_Ticks (never at a loss).
//   - Restart adoption: live positions snapshotted to disk on every change;
//     on NT restart the snapshot is matched against the account position and
//     the trade is re-adopted with fresh brackets (RegisterNewPositions).
//   - Consumed-side ledger: a side that triggered this session never re-arms
//     after a restart (phantom re-fire fix #4).
//   - Closed-trade ledger on disk → weekly/monthly reports + tracker rebuild.
//   - Rejection resilience: RealtimeErrorHandling=IgnoreAllErrors; we sweep,
//     count, back off, and halt arming ourselves instead of NT disabling us.
// ============================================================================

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public class ORB_Strategy : Strategy
    {
        private const int SLOT_COUNT = 6;

        //======================================================================
        // ── INPUTS (defaults = GC-Daily-London-NY-ORB.set) ──
        //======================================================================
        #region Risk & Sizing
        [Display(Name = "Risk Percent", Order = 1, GroupName = "1 · Risk")]
        public double Risk_Percent { get; set; } = 1.0;

        [Display(Name = "Starting Balance", Order = 2, GroupName = "1 · Risk")]
        public double Starting_Balance { get; set; } = 25000.0;

        [Display(Name = "Drawdown Amount", Order = 3, GroupName = "1 · Risk")]
        public double Drawdown_Amount { get; set; } = 1500.0;

        [Display(Name = "Contract Mode", Order = 4, GroupName = "1 · Risk")]
        public ContractSizeMode Contract_Mode { get; set; } = ContractSizeMode.Micro;

        [Display(Name = "Max Contracts Override (0=use mode cap)", Order = 5, GroupName = "1 · Risk")]
        public int Max_Contracts_Override { get; set; } = 0;

        [Display(Name = "Commission Per Contract Round Turn", Order = 6, GroupName = "1 · Risk")]
        public double Commission_Per_Contract { get; set; } = 4.0;

        [Display(Name = "Max Margin Usage Percent", Order = 7, GroupName = "1 · Risk")]
        public double Max_Margin_Usage_Percent { get; set; } = 100.0;
        #endregion

        #region Evaluation
        [Display(Name = "Eval Profit Target", Order = 1, GroupName = "2 · Evaluation")]
        public double Eval_Profit_Target { get; set; } = 1500.0;

        [Display(Name = "Enable Daily Loss Limit", Order = 2, GroupName = "2 · Evaluation")]
        public bool Enable_Daily_Loss_Limit { get; set; } = false;

        [Display(Name = "Daily Loss Limit Amount", Order = 3, GroupName = "2 · Evaluation")]
        public double Daily_Loss_Limit_Amount { get; set; } = 500.0;
        #endregion

        #region Sessions
        [Display(Name = "NY | Enable", Order = 1, GroupName = "3 · Sessions")]
        public bool Enable_NY_Session { get; set; } = true;

        [Display(Name = "NY | Open Hour (NY time)", Order = 2, GroupName = "3 · Sessions")]
        public int Opening_Hour_NY { get; set; } = 8;

        [Display(Name = "NY | Open Minute", Order = 3, GroupName = "3 · Sessions")]
        public int Opening_Minute_NY { get; set; } = 0;

        [Display(Name = "London | Enable", Order = 4, GroupName = "3 · Sessions")]
        public bool Enable_London_Session { get; set; } = true;

        [Display(Name = "London | Open Hour (NY time)", Order = 5, GroupName = "3 · Sessions")]
        public int London_Hour_NY { get; set; } = 0;

        [Display(Name = "London | Open Minute", Order = 6, GroupName = "3 · Sessions")]
        public int London_Minute_NY { get; set; } = 0;

        [Display(Name = "Asian | Enable", Order = 7, GroupName = "3 · Sessions")]
        public bool Enable_Asian_Session { get; set; } = false;

        [Display(Name = "Asian | Open Hour (NY time)", Order = 8, GroupName = "3 · Sessions")]
        public int Asian_Hour_NY { get; set; } = 18;

        [Display(Name = "Asian | Open Minute", Order = 9, GroupName = "3 · Sessions")]
        public int Asian_Minute_NY { get; set; } = 0;
        #endregion

        #region Range Slots
        [Display(Name = "Intraday | Trigger candle minutes", Order = 1, GroupName = "4 · Range Slots")]
        public int Range_Minutes { get; set; } = 120;

        [Display(Name = "HTF | Enable Daily range (prior D1)", Order = 2, GroupName = "4 · Range Slots")]
        public bool Enable_Daily_Range { get; set; } = true;

        [Display(Name = "HTF | Enable Weekly range (prior W1)", Order = 3, GroupName = "4 · Range Slots")]
        public bool Enable_Weekly_Range { get; set; } = false;

        [Display(Name = "HTF | Enable Monthly range (prior MN1)", Order = 4, GroupName = "4 · Range Slots")]
        public bool Enable_Monthly_Range { get; set; } = false;

        [Display(Name = "HTF | Expiry (periods)", Order = 5, GroupName = "4 · Range Slots")]
        public int Slot2_Cutoff_Periods { get; set; } = 1;
        #endregion

        #region Trade Geometry
        [Display(Name = "Custom Point Size (price per point, 0 = tick size)", Order = 0, GroupName = "5 · Trade Geometry",
            Description = "MT5 Custom_Point_Multiplier parity. 0.01 on gold: xxxx.x1 = 1 point, xxxx.10 = 10 points — the same SL/TP/trail numbers work in both platforms. 0 = distances are in instrument ticks.")]
        public double Custom_Point_Value { get; set; } = 0.01;

        [Display(Name = "Reverse Orders (sell high / buy low)", Order = 1, GroupName = "5 · Trade Geometry")]
        public bool Reverse_Orders { get; set; } = false;

        [Display(Name = "Instant Market Execution (replace pendings)", Order = 2, GroupName = "5 · Trade Geometry")]
        public bool Use_Instant_Market_Execution { get; set; } = true;

        [Display(Name = "Instant | Max Entry Slippage Points (skip beyond)", Order = 3, GroupName = "5 · Trade Geometry")]
        public double Instant_Max_Entry_Slippage_Ticks { get; set; } = 100.0;

        [Display(Name = "Use StopLimit Orders (pending mode)", Order = 4, GroupName = "5 · Trade Geometry")]
        public bool Use_StopLimit_Orders { get; set; } = false;

        [Display(Name = "Fixed SL Points", Order = 5, GroupName = "5 · Trade Geometry")]
        public double Fixed_SL_Ticks { get; set; } = 400.0;   // 400 pts × 0.01 = $4.00 of price (MT5 parity)

        [Display(Name = "Fixed TP Points", Order = 6, GroupName = "5 · Trade Geometry")]
        public double Fixed_TP_Ticks { get; set; } = 350.0;

        [Display(Name = "Max Fill Slippage Points (0=off)", Order = 7, GroupName = "5 · Trade Geometry")]
        public double Max_Slippage_Ticks { get; set; } = 100.0;

        [Display(Name = "SlipFC | Close excess-slip trade at +N points", Order = 8, GroupName = "5 · Trade Geometry")]
        public double Slip_ForceClose_Profit_Ticks { get; set; } = 20.0;

        // Hard slippage cap for the protective / trailing stop. When > 0 the
        // stop is submitted as a StopLimit that will NOT fill worse than this
        // many points past the stop — there is NO market fallback, so a gap
        // straight through the band can leave the stop unfilled and the
        // position running. Set to 0 to revert to a guaranteed StopMarket exit.
        [Display(Name = "Stop Slip Cap Points (0=StopMarket)", Order = 8, GroupName = "5 · Trade Geometry")]
        public double Stop_Slip_Cap_Ticks { get; set; } = 20.0;

        [Display(Name = "Trail Mode (Continuous / Step)", Order = 9, GroupName = "5 · Trade Geometry")]
        public TrailMode Trail_Mode { get; set; } = TrailMode.Continuous;

        [Display(Name = "Trail Behavior", Order = 10, GroupName = "5 · Trade Geometry")]
        public TrailBehavior Trail_Behavior { get; set; } = TrailBehavior.Trail;

        [Display(Name = "Trail Threshold Points", Order = 11, GroupName = "5 · Trade Geometry")]
        public double Trail_Threshold_Ticks { get; set; } = 120.0;

        [Display(Name = "Trail Gap Points", Order = 12, GroupName = "5 · Trade Geometry")]
        public double Trail_Gap_Ticks { get; set; } = 100.0;

        [Display(Name = "Use Spread Compensation (gap/BE minus entry spread + commission)", Order = 13, GroupName = "5 · Trade Geometry")]
        public bool Use_Spread_Compensation { get; set; } = false;

        [Display(Name = "Min Trail Minutes (0 = immediate)", Order = 14, GroupName = "5 · Trade Geometry")]
        public double Min_Trail_Minutes { get; set; } = 0.0;

        [Display(Name = "Breakeven Cost Points (manual BE cushion)", Order = 15, GroupName = "5 · Trade Geometry")]
        public double BE_Cost_Ticks { get; set; } = 20.0;

        [Display(Name = "Flat by 4:59 PM ET (intraday slots)", Order = 16, GroupName = "5 · Trade Geometry")]
        public bool Auto_Flat_EOD { get; set; } = true;
        #endregion

        #region News Guard
        [Display(Name = "News Guard Mode", Order = 1, GroupName = "6 · News Guard")]
        public NewsGuardMode News_Guard_Mode { get; set; } = NewsGuardMode.RedOnly;

        [Display(Name = "Block Minutes Before News", Order = 2, GroupName = "6 · News Guard")]
        public int News_Block_Before_Mins { get; set; } = 5;

        [Display(Name = "Block Minutes After News", Order = 3, GroupName = "6 · News Guard")]
        public int News_Block_After_Mins { get; set; } = 5;

        [Display(Name = "Freeze Trail During News", Order = 4, GroupName = "6 · News Guard")]
        public bool News_Freeze_Trail { get; set; } = true;

        [Display(Name = "Flatten Before News", Order = 5, GroupName = "6 · News Guard")]
        public bool News_Flatten_Before { get; set; } = true;

        [Display(Name = "Cancel Pending During News", Order = 6, GroupName = "6 · News Guard")]
        public bool News_Cancel_Pending { get; set; } = true;
        #endregion

        #region Notifications
        [Display(Name = "Discord Webhook URL", Order = 1, GroupName = "7 · Notifications")]
        public string Discord_Webhook_URL { get; set; } = "https://discord.com/api/webhooks/1504886282730602526/1uncyB7UhyAFW8OfA8l8BAH_XulCLUVG_m4yLsWCKQqp7TvKZLTfBnKrSL9n1gGvTioR";

        [Display(Name = "Discord Enabled", Order = 2, GroupName = "7 · Notifications")]
        public bool Discord_Enabled { get; set; } = false;

        [Display(Name = "Telegram Bot Token", Order = 3, GroupName = "7 · Notifications")]
        public string Telegram_Bot_Token { get; set; } = "8858207904:AAHhhNSrZTdURzCIXNDMAz_ZChrzme3xjvc";

        [Display(Name = "Telegram Chat ID", Order = 4, GroupName = "7 · Notifications")]
        public string Telegram_Chat_ID { get; set; } = "-1003996863325|5";

        [Display(Name = "Telegram Enabled", Order = 5, GroupName = "7 · Notifications")]
        public bool Telegram_Enabled { get; set; } = false;

        [Display(Name = "Performance Reports Enabled", Order = 6, GroupName = "7 · Notifications")]
        public bool Reports_Enabled { get; set; } = false;

        [Display(Name = "Report Hour (NY time)", Order = 7, GroupName = "7 · Notifications")]
        public int Report_Hour { get; set; } = 2;
        #endregion

        #region Display
        [Display(Name = "Show Dashboard", Order = 1, GroupName = "8 · Display")]
        public bool Show_Dashboard { get; set; } = true;

        [Display(Name = "Show Visuals (range boxes / lines)", Order = 2, GroupName = "8 · Display")]
        public bool Show_Visuals { get; set; } = true;
        #endregion

        //======================================================================
        // ── RUNTIME STATE ──
        //======================================================================
        private DrawdownTracker ddTracker;
        private ConsistencyTracker consistencyTracker;
        private FastTradeTracker fastTradeTracker;
        private ORB_News newsEngine;
        private ORB_Notify notifier;
        private ORB_State state;

        private SlotState[] slots;
        private ActiveTrade[] activeTrades;   // per-slot trade record (null = idle)
        private bool isHalted = false;
        private int tradingDaysCompleted = 0;
        private DateTime lastDayClosedUTC = DateTime.MinValue;
        private double dailyStartBalance = 0;
        private double dailyLoss = 0;
        private DateTime lastDailyResetNYDate = DateTime.MinValue;
        private int ocoCounter = (int)(DateTime.UtcNow - new DateTime(2020, 1, 1)).TotalSeconds;

        // ── Rejection resilience ──
        private int totalRejections = 0;
        private readonly int[] slotRejections = new int[SLOT_COUNT];
        private const int MAX_SLOT_REJECTIONS = 3;   // per-slot arming stops after this
        private const int MAX_TOTAL_REJECTIONS = 10; // global halt after this
        private bool venueBlocked = false;           // data-feed / permission style rejection seen

        // ── 1-second UI/management pulse (EventSetTimer(1) equivalent) ──
        private System.Timers.Timer secTimer;

        // ── Gate B strict-mode re-arm tracking (news strict sweep) ──
        private bool strictSweepDone = false;
        private bool[] strictRearmLong;
        private bool[] strictRearmShort;

        // ── Reports throttle ──
        private DateTime lastWeeklyReportNYDate = DateTime.MinValue;
        private DateTime lastMonthlyReportNYDate = DateTime.MinValue;

        // ── Adoption ──
        private bool adoptionDone = false;
        private bool wasRealtime = false;   // persistence only for live sessions (never backtests)
        private bool isAnalyzer = false;    // Strategy Analyzer run (never transitions to Realtime)
        private bool isSimOrPlayback = false; // Sim101 / Playback / Replay account — NOT broker-executed

        private static readonly string[] SlotNames = { "NY", "London", "Asian", "Daily", "Weekly", "Monthly" };

        // ── Custom point system (MT5 Custom_Point_Multiplier parity) ──
        // ALL user distances (SL/TP/trail/slippage/BE) are expressed in
        // POINTS of this size. 0.01 on gold → xxxx.x1 = 1 pt, xxxx.10 = 10 pt,
        // so the MT5 numbers (SL 400 = $4.00) transfer verbatim. Order prices
        // are still rounded to the instrument's REAL tick grid at submission.
        private double PointSize
        {
            get
            {
                if (Custom_Point_Value > 0) return Custom_Point_Value;
                return TickSize > 0 ? TickSize : 0.01;
            }
        }

        //======================================================================
        // ── NINJASCRIPT LIFECYCLE ──
        //======================================================================
        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "ORB_Scalper";
                Description = "Opening Range Breakout Scalper — NT8 port, 6-slot engine (NY/London/Asian + D/W/M)";
                Calculate = Calculate.OnEachTick;
                IsUnmanaged = true;
                IsExitOnSessionCloseStrategy = false;
                BarsRequiredToTrade = 1;
                // WE own error handling: one venue rejection must not let NT8
                // disable the whole strategy (the default StopCancelClose does).
                RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
            }
            else if (State == State.Configure)
            {
                // M1 series drives all range building regardless of chart timeframe
                AddDataSeries(BarsPeriodType.Minute, 1);
            }
            else if (State == State.DataLoaded)
            {
                // Strategy Analyzer runs on the "Backtest" account and never
                // reaches State.Realtime. Historical order simulation is ONLY
                // for the Analyzer — on a live chart the backfill must never
                // trade (those sims were the source of NT's phantom execution
                // arrows and the fake eval numbers).
                try { isAnalyzer = Account != null && Account.Name != null && Account.Name.StartsWith("Backtest"); }
                catch { isAnalyzer = false; }
                // Sim101 / Playback / Replay accounts reach State.Realtime (so the
                // wasRealtime gate alone lets them through) but are NOT genuine
                // broker fills — they must never feed Eval Profit / consistency /
                // fast-trade / traded-day trackers or the on-disk REAL ledger.
                try
                {
                    string an = Account != null && Account.Name != null ? Account.Name : "";
                    isSimOrPlayback = an == "Sim101"
                        || an.StartsWith("Backtest") || an.StartsWith("Playback")
                        || an.StartsWith("Replay") || an.StartsWith("Sim");
                }
                catch { isSimOrPlayback = false; }
                InitModules();
            }
            else if (State == State.Realtime)
            {
                wasRealtime = true;

                // Purge ALL ORB-owned draw objects (this build's tags AND
                // legacy tags from older builds — e.g. the July-16 arrows that
                // persisted in the workspace). Fresh state redraws in seconds.
                ORB_Visuals.PurgeAllOrbObjects(this);

                // Best-effort: switch the CHART's execution-marker plotting off
                // (property name varies across NT8 builds → reflection, so a
                // rename can never break compilation). Our trade tools are the
                // sole execution visuals.
                var ccPlot = ChartControl;
                if (ccPlot != null)
                {
                    ccPlot.Dispatcher.InvokeAsync(() =>
                    {
                        try
                        {
                            var props = ccPlot.Properties;
                            var pi = props?.GetType().GetProperty("PlotExecutions");
                            if (pi != null && pi.PropertyType.IsEnum)
                            {
                                object off = Enum.Parse(pi.PropertyType, "DoNotPlot");
                                pi.SetValue(props, off, null);
                                ccPlot.InvalidateVisual();
                            }
                        }
                        catch { }
                    });
                }

                // Adopt live positions from a previous run BEFORE sweeping —
                // the sweep would otherwise cancel brackets we want to reuse.
                AdoptFromSnapshots();

                // Sweep orphaned entry orders (adopted trades get fresh brackets)
                CancelAllStrategyOrders(excludeAdoptedBrackets: true);

                secTimer = new System.Timers.Timer(1000);
                secTimer.AutoReset = true;
                secTimer.Elapsed += (o, e) =>
                {
                    try { TriggerCustomEvent(OnSecondPulse, null); } catch { }
                };
                secTimer.Start();

                // Dashboard drag/collapse: hook chart mouse events (UI thread)
                var ccMouse = ChartControl;
                if (ccMouse != null)
                {
                    ccMouse.Dispatcher.InvokeAsync(() =>
                    {
                        try
                        {
                            ccMouse.MouseLeftButtonDown += OnChartMouseDown;
                            ccMouse.MouseMove += OnChartMouseMove;
                            ccMouse.MouseLeftButtonUp += OnChartMouseUp;
                        }
                        catch { }
                    });
                }
            }
            else if (State == State.Terminated)
            {
                var ccMouse = ChartControl;
                if (ccMouse != null)
                {
                    try
                    {
                        ccMouse.Dispatcher.InvokeAsync(() =>
                        {
                            try
                            {
                                ccMouse.MouseLeftButtonDown -= OnChartMouseDown;
                                ccMouse.MouseMove -= OnChartMouseMove;
                                ccMouse.MouseLeftButtonUp -= OnChartMouseUp;
                            }
                            catch { }
                        });
                    }
                    catch { }
                }
                if (secTimer != null)
                {
                    secTimer.Stop();
                    secTimer.Dispose();
                    secTimer = null;
                }
                // If the broker position is already flat (e.g. manually closed by
                // the user) there is nothing to protect and nothing to adopt on
                // the next launch.  Clear the live-trade file now so re-enabling
                // the strategy does not attempt to cancel orders that never existed,
                // which is what produces the "Strategy was not started" dialog.
                bool posFlat = (Position == null || Position.MarketPosition == MarketPosition.Flat);
                if (posFlat)
                {
                    state?.ClearLiveTrades();
                    Log("[ORB] Terminated with flat position — live-trade snapshot cleared. Safe to re-enable.", LogLevel.Information);
                }
                else
                {
                    // Persist live trades so the next launch can adopt them,
                    // then cancel only our pending ENTRY orders (brackets stay
                    // working at the broker to protect the open position).
                    SaveLiveSnapshots();
                }
                CancelEntryOrdersOnly();
                ORB_Dashboard.Clear(this);
            }
        }

        private void InitModules()
        {
            ddTracker = new DrawdownTracker(Starting_Balance, Drawdown_Amount);
            consistencyTracker = new ConsistencyTracker(Eval_Profit_Target);
            fastTradeTracker = new FastTradeTracker();

            slots = new SlotState[SLOT_COUNT];
            activeTrades = new ActiveTrade[SLOT_COUNT];
            strictRearmLong = new bool[SLOT_COUNT];
            strictRearmShort = new bool[SLOT_COUNT];

            slots[0] = new SlotState(0) { IsEnabled = Enable_NY_Session,     Type = SessionType.Intraday };
            slots[1] = new SlotState(1) { IsEnabled = Enable_London_Session, Type = SessionType.Intraday };
            slots[2] = new SlotState(2) { IsEnabled = Enable_Asian_Session,  Type = SessionType.Intraday };
            slots[3] = new SlotState(3) { IsEnabled = Enable_Daily_Range,    Type = SessionType.Daily };
            slots[4] = new SlotState(4) { IsEnabled = Enable_Weekly_Range,   Type = SessionType.Weekly };
            slots[5] = new SlotState(5) { IsEnabled = Enable_Monthly_Range,  Type = SessionType.Monthly };

            bool isHistorical = (State == State.Historical);
            string strategyDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "NinjaTrader 8", "bin", "Custom", "Strategies", "ORB_NT");

            newsEngine = new ORB_News(
                Path.Combine(strategyDir, "historical_calendar.csv"),
                Path.Combine(strategyDir, "live_news_cache.json"),
                isHistorical);
            newsEngine.Initialize();

            notifier = new ORB_Notify(
                Discord_Webhook_URL, Telegram_Bot_Token, Telegram_Chat_ID,
                Discord_Enabled, Telegram_Enabled);

            state = new ORB_State(Path.Combine(strategyDir, "state"), Instrument.MasterInstrument.Name);

            // Rebuild trackers from the closed-trade ledger so consistency %,
            // fast-trade % and trading-day count survive NT restarts.
            var ledger = state.LoadLedger();
            var seenDays = new HashSet<DateTime>();
            foreach (var t in ledger)
            {
                // Any prior trade (real, legacy, or sim) for a session means that
                // session already resolved — suppress its synthetic preview so a
                // restart can't redraw a synthetic over a session that traded.
                if (!string.IsNullOrEmpty(t.SessionKey)) resolvedSessionKeys.Add(t.SessionKey);

                // Eval Profit / consistency / fast-trade / traded-days count ONLY
                // genuinely broker-executed trades. Legacy rows (pre-Source column)
                // and any sim rows are skipped so historical simulations can never
                // inflate the dashboard's eval PnL.
                if (t.Source != "REAL") continue;
                consistencyTracker.RecordTrade(t.ExitTimeUTC.Date, t.PnL);
                fastTradeTracker.RecordTrade((t.ExitTimeUTC - t.EntryTimeUTC).TotalSeconds, t.PnL);
                seenDays.Add(t.ExitTimeUTC.Date);
                if (t.ExitTimeUTC > lastDayClosedUTC) lastDayClosedUTC = t.ExitTimeUTC;
            }
            tradingDaysCompleted = seenDays.Count;
            if (ledger.Count > 0)
                Log(string.Format("[ORB] Ledger loaded: {0} closed trades across {1} days.", ledger.Count, seenDays.Count), LogLevel.Information);

            dailyStartBalance = Account.Get(AccountItem.CashValue, Currency.UsDollar);
        }

        //======================================================================
        // ── RESTART ADOPTION (RegisterNewPositions parity) ──
        //======================================================================
        private void AdoptFromSnapshots()
        {
            if (adoptionDone) return;
            adoptionDone = true;

            var snapshots = state.LoadLiveTrades();
            if (snapshots.Count == 0) return;

            // ── Position accumulation fix ──────────────────────────────────────
            // Guard how many contracts of the REAL broker position have already
            // been claimed by prior snapshots this loop.  Without this gate,
            // every snapshot whose direction matches "Position.Quantity >= snap.Contracts"
            // gets adopted independently, so N stale snapshots each place fresh
            // brackets and issue SlipForceClose market orders for N×qty contracts.
            int claimedLong  = 0;
            int claimedShort = 0;
            int brokerLong   = (Position.MarketPosition == MarketPosition.Long)  ? Position.Quantity : 0;
            int brokerShort  = (Position.MarketPosition == MarketPosition.Short) ? Position.Quantity : 0;

            // If broker is flat there is nothing to adopt; clear the stale file
            // and return so a re-enable after a manual close never hits "was not started".
            if (brokerLong == 0 && brokerShort == 0)
            {
                state.ClearLiveTrades();
                Log("[ORB] AdoptFromSnapshots: broker position is flat — stale live-trade file cleared.", LogLevel.Information);
                return;
            }

            foreach (var snap in snapshots)
            {
                if (snap.SlotIndex < 0 || snap.SlotIndex >= SLOT_COUNT) continue;

                // Does the account still hold enough un-claimed contracts?
                int available = snap.IsLong ? (brokerLong - claimedLong) : (brokerShort - claimedShort);
                bool match = available >= snap.Contracts;

                if (!match)
                {
                    // Either closed while offline, or we have already claimed all
                    // available broker contracts with prior snapshots.
                    Log(string.Format("[ORB] Snapshot S{0} {1} {2} x{3}: no available broker contracts ({4} remaining) — closed while offline or duplicate. Side stays consumed.",
                        snap.SlotIndex, SlotNames[snap.SlotIndex], snap.IsLong ? "LONG" : "SHORT", snap.Contracts, available), LogLevel.Warning);
                    continue;
                }

                // Claim these contracts so the next snapshot in the list cannot
                // adopt the same broker lots a second time.
                if (snap.IsLong) claimedLong  += snap.Contracts;
                else             claimedShort += snap.Contracts;

                var trade = new ActiveTrade
                {
                    SlotIndex = snap.SlotIndex,
                    SessionKey = snap.SessionKey,
                    IsLong = snap.IsLong,
                    EntryPrice = snap.EntryPrice,
                    EntryTime = snap.EntryTimeUTC,
                    VirtualSL = snap.VirtualSL,
                    TpPrice = snap.TpPrice,
                    Contracts = snap.Contracts,
                    OcoGroup = snap.OcoGroup + "_A" + (++ocoCounter),
                    TrailingActivated = snap.TrailingActivated,
                    BreakevenSet = snap.BreakevenSet,
                    SlipTicks = snap.SlipTicks,
                    SlipForceClose = snap.SlipForceClose,
                    Adopted = true,
                    // Restore the frozen trailing geometry; older snapshot files
                    // (SnapThreshPrice == 0) fall back to current inputs.
                    SnapTrailMode = snap.SnapTrailMode,
                    SnapBehavior = snap.SnapBehavior,
                    SnapThreshPrice = snap.SnapThreshPrice > 0 ? snap.SnapThreshPrice : Trail_Threshold_Ticks * PointSize,
                    SnapGapPrice = snap.SnapGapPrice > 0 ? snap.SnapGapPrice : Trail_Gap_Ticks * PointSize,
                    SnapMinTrailSec = snap.SnapMinTrailSec,
                    SnapSpreadComp = snap.SnapSpreadComp,
                    SnapEntrySpread = snap.SnapEntrySpread,
                    SnapBECostPrice = snap.SnapBECostPrice
                };

                // Fresh brackets from the snapshot's own geometry (old bracket
                // objects can't be re-bound to this instance's Orders anyway,
                // so any survivors are cancelled by the sweep right after).
                double slDist = Math.Abs(trade.EntryPrice - trade.VirtualSL);
                double tpDist = Math.Abs(trade.TpPrice - trade.EntryPrice);
                if (slDist <= 0) slDist = Fixed_SL_Ticks * PointSize;
                if (tpDist <= 0) tpDist = Fixed_TP_Ticks * PointSize;

                double adoptCap = SlipCapPoints(trade);
                var (slOrder, tpOrder) = ORB_Execution.PlaceBracketOrders(this, trade.IsLong,
                    trade.EntryPrice, trade.Contracts, slDist, tpDist, trade.OcoGroup + "_BRK", adoptCap);
                // PlaceBracketOrders anchors off fill price; re-anchor SL to the
                // snapshot's trailed level if it had moved (move the StopLimit's
                // limit with it so the slip cap survives adoption).
                if (slOrder != null && Math.Abs(slOrder.StopPrice - trade.VirtualSL) > TickSize / 2)
                {
                    double adoptStop = Instrument.MasterInstrument.RoundToTickSize(trade.VirtualSL);
                    double adoptLimit = ORB_Execution.SlLimitPrice(trade.IsLong, adoptStop, adoptCap, Instrument.MasterInstrument);
                    ChangeOrder(slOrder, slOrder.Quantity, adoptLimit, adoptStop);
                }

                trade.SlOrder = slOrder;
                trade.TpOrder = tpOrder;
                activeTrades[snap.SlotIndex] = trade;

                // Block this slot from re-arming this session
                state.MarkSideConsumed(snap.SessionKey, snap.IsLong);

                Log(string.Format("[ORB] ADOPTED S{0} {1} {2} x{3} @ {4:F2} — SL {5:F2} / TP {6:F2} re-placed.",
                    snap.SlotIndex, SlotNames[snap.SlotIndex], trade.IsLong ? "LONG" : "SHORT",
                    trade.Contracts, trade.EntryPrice, trade.VirtualSL, trade.TpPrice), LogLevel.Information);
                notifier?.Enqueue(string.Format("**ADOPTED after restart** — {0} {1} x{2} @ {3:F2}\nSL {4:F2} / TP {5:F2}",
                    SlotNames[snap.SlotIndex], trade.IsLong ? "LONG" : "SHORT", trade.Contracts,
                    trade.EntryPrice, trade.VirtualSL, trade.TpPrice), 0x3498DB);
            }

            SaveLiveSnapshots();
        }

        private void SaveLiveSnapshots()
        {
            if (state == null || activeTrades == null) return;
            if (!wasRealtime) return; // backtests must not touch live persistence
            var list = new List<LiveTradeSnapshot>();
            for (int s = 0; s < SLOT_COUNT; s++)
            {
                var t = activeTrades[s];
                if (t == null || t.EntryPrice <= 0) continue;
                list.Add(new LiveTradeSnapshot
                {
                    SlotIndex = s,
                    SessionKey = t.SessionKey ?? slots[s].SessionKey,
                    IsLong = t.IsLong,
                    EntryPrice = t.EntryPrice,
                    EntryTimeUTC = t.EntryTime,
                    VirtualSL = t.VirtualSL,
                    TpPrice = t.TpPrice,
                    Contracts = t.Contracts,
                    OcoGroup = t.OcoGroup,
                    TrailingActivated = t.TrailingActivated,
                    BreakevenSet = t.BreakevenSet,
                    SlipTicks = t.SlipTicks,
                    SlipForceClose = t.SlipForceClose,
                    SnapTrailMode = t.SnapTrailMode,
                    SnapBehavior = t.SnapBehavior,
                    SnapThreshPrice = t.SnapThreshPrice,
                    SnapGapPrice = t.SnapGapPrice,
                    SnapMinTrailSec = t.SnapMinTrailSec,
                    SnapSpreadComp = t.SnapSpreadComp,
                    SnapEntrySpread = t.SnapEntrySpread,
                    SnapBECostPrice = t.SnapBECostPrice
                });
            }
            if (list.Count == 0) state.ClearLiveTrades();
            else state.SaveLiveTrades(list);
        }

        //======================================================================
        // ── SLOT SCHEDULE ──
        //======================================================================
        private int SlotOpenHour(int s)   => s == 1 ? London_Hour_NY   : s == 2 ? Asian_Hour_NY   : Opening_Hour_NY;
        private int SlotOpenMinute(int s) => s == 1 ? London_Minute_NY : s == 2 ? Asian_Minute_NY : Opening_Minute_NY;
        private bool SlotIsIntraday(int s) => s <= 2;

        private void RecomputeSlotTimes(int s, DateTime nowUTC)
        {
            SlotState slot = slots[s];

            if (SlotIsIntraday(s))
            {
                DateTime openUTC = ORB_Time.GetSessionOpenUTC(nowUTC, SlotOpenHour(s), SlotOpenMinute(s));
                slot.RangeStartTimeUTC = openUTC.AddMinutes(-Range_Minutes);
                slot.RangeEndTimeUTC   = openUTC;
                slot.CutoffTimeUTC     = ComputeCutoff1800NY(openUTC);
                slot.SessionKey = string.Format("S{0}_{1:yyyyMMdd}_{2:D2}{3:D2}",
                    s, ORB_Time.UTCToNY(openUTC), SlotOpenHour(s), SlotOpenMinute(s));
            }
            else
            {
                DateTime anchor = s == 3 ? ORB_Time.GetCurrentNYTrueDayOpen(nowUTC)
                                : s == 4 ? ORB_Time.GetCurrentNYTrueWeekOpen(nowUTC)
                                         : ORB_Time.GetCurrentNYTrueMonthOpen(nowUTC);
                slot.RangeEndTimeUTC   = anchor;
                slot.RangeStartTimeUTC = s == 3 ? anchor.AddDays(-1)
                                       : s == 4 ? anchor.AddDays(-7)
                                                : anchor.AddMonths(-1);
                // Weekend gap: a Sunday/Monday daily anchor would give a window
                // with no bars (Sat/Sun closed) — widen the scan back to catch
                // Friday's session. Box drawing anchors to ACTUAL bars found,
                // so the visual stays tight regardless of window width.
                if (s == 3)
                {
                    DayOfWeek anchorDowNY = ORB_Time.UTCToNY(anchor).DayOfWeek;
                    if (anchorDowNY == DayOfWeek.Sunday)
                        slot.RangeStartTimeUTC = anchor.AddDays(-3); // reach back to Thu 18:00 → Friday session
                    else if (anchorDowNY == DayOfWeek.Monday)
                        slot.RangeStartTimeUTC = anchor.AddDays(-2); // skip dead Saturday
                }
                slot.CutoffTimeUTC = s == 3 ? anchor.AddDays(Slot2_Cutoff_Periods)
                                   : s == 4 ? anchor.AddDays(7 * Slot2_Cutoff_Periods)
                                            : anchor.AddMonths(Slot2_Cutoff_Periods);
                slot.SessionKey = string.Format("S{0}_HTF_{1:yyyyMMddHHmm}", s, anchor);
            }
        }

        private DateTime ComputeCutoff1800NY(DateTime sessionOpenUTC)
        {
            DateTime openNY = ORB_Time.UTCToNY(sessionOpenUTC);
            DateTime cutoffNY = new DateTime(openNY.Year, openNY.Month, openNY.Day, 18, 0, 0);
            if (cutoffNY <= openNY) cutoffNY = cutoffNY.AddDays(1);
            return ORB_Time.NYToUTC(cutoffNY);
        }

        //======================================================================
        // ── 1-SECOND PULSE ──
        //======================================================================
        private void OnSecondPulse(object unused)
        {
            if (State != State.Realtime) return;

            DateTime nowUTC = DateTime.UtcNow;
            double bid = GetCurrentBid();
            double ask = GetCurrentAsk();
            double liveCash = Account.Get(AccountItem.CashValue, Currency.UsDollar);

            for (int s = 0; s < SLOT_COUNT; s++)
            {
                if (!slots[s].IsEnabled) continue;
                string prevKey = slots[s].SessionKey;
                RecomputeSlotTimes(s, nowUTC);
                if (SlotIsIntraday(s)) SessionLogic.UpdateSlotPhase(slots[s], nowUTC);

                // ── TIMER-DRIVEN CUTOVER ──
                // Session rolled (new key) or cutoff passed: reset the slot and
                // clear ALL of its visuals right now. Previously this only ran
                // on M1 bar updates, so a quiet feed at 18:00 left stale exec
                // objects/lines up (and the Daily box outdated) until a manual
                // timeframe change forced a refresh.
                bool rolled = prevKey != slots[s].SessionKey && !string.IsNullOrEmpty(prevKey);
                bool pastCutoff = slots[s].IsRangeLocked && nowUTC >= slots[s].CutoffTimeUTC;
                if (rolled || pastCutoff)
                {
                    SweepUnfilledSlot(s, rolled ? "Session rolled (timer)" : "Cutoff (timer)");
                    slots[s].Reset();
                    if (pastCutoff && !rolled) slots[s].Phase = SessionPhase.Closed;
                    if (Show_Visuals)
                        ORB_Visuals.ClearAllVisuals(this, "S" + s);
                    Log(string.Format("[ORB] S{0} {1}: slot reset + visuals cleared ({2}).",
                        s, SlotNames[s], rolled ? "session rolled" : "cutoff"), LogLevel.Information);
                }
            }

            newsEngine?.RefreshIfNeeded(nowUTC);

            if (!isHalted)
            {
                if (Auto_Flat_EOD) CheckEODFlatten(nowUTC);
                for (int s = 0; s < SLOT_COUNT; s++)
                    if (activeTrades[s] != null) ManageTrade(s, nowUTC, bid, ask);
            }

            if (Reports_Enabled) CheckScheduledReports(nowUTC);

            // ── Visual pulse: redraw ranges + trade lines every second.
            // Ranges lock during HISTORICAL backfill where drawing is
            // suppressed, so a one-shot draw-at-lock never appears. Tag-based
            // Draw.* updates in place — redrawing each second is cheap and is
            // the same fix the MT5 EA needed in its OnTimer.
            RenderVisualsPulse(nowUTC);

            if (Show_Dashboard) RenderDashboard(nowUTC, liveCash, bid, ask);
            notifier?.DrainQueue();
        }

        //======================================================================
        // ── VISUAL PULSE + RETROACTIVE SYNTHETIC EXECUTIONS ──
        //======================================================================
        private DateTime lastSyntheticDrawUTC = DateTime.MinValue;

        private void RenderVisualsPulse(DateTime nowUTC)
        {
            if (!Show_Visuals || State != State.Realtime) return;

            for (int s = 0; s < SLOT_COUNT; s++)
            {
                SlotState slot = slots[s];
                if (!slot.IsEnabled) continue;

                bool showRange = slot.Phase == SessionPhase.RangeForming ||
                                 slot.Phase == SessionPhase.TradingWindow ||
                                 (!SlotIsIntraday(s) && slot.IsRangeLocked && nowUTC < slot.CutoffTimeUTC);
                if (showRange)
                    DrawSlotRange(s);

                // Live trade → TradingView-style long/short tool, right edge = now
                var t = activeTrades[s];
                if (t != null && t.EntryPrice > 0)
                {
                    DateTime levelTime = t.LevelTime != DateTime.MinValue ? t.LevelTime
                        : (slot.RangeEndBarTime != DateTime.MinValue ? slot.RangeEndBarTime : ORB_Time.UTCToChart(t.EntryTime));
                    double levelPx = t.LevelPx > 0 ? t.LevelPx : t.EntryPrice;

                    ORB_Visuals.DrawTradeTool(this, "S" + s + "_LIVE", t.IsLong,
                        t.EntryPrice, t.VirtualSL, t.TpPrice,
                        levelPx, levelTime, ORB_Time.UTCToChart(t.EntryTime), ORB_Time.NowChart(),
                        t.TrailingActivated, t.TrailStartTime, false);
                }
            }

            // Synthetic executions refresh every 30s: unresolved ones extend
            // their right edge; anchors are exact-bar so redrawing is stable.
            if ((nowUTC - lastSyntheticDrawUTC).TotalSeconds >= 30)
            {
                lastSyntheticDrawUTC = nowUTC;
                try { DrawRetroactiveExecutions(nowUTC); }
                catch (Exception ex) { Log("[ORB] Retro-draw error: " + ex.Message, LogLevel.Warning); }
            }
        }

        // Retroactive synthetic executions — same fidelity rules as live:
        //   - Scope: the CURRENT NY trading day only (18:00 prior → 18:00).
        //   - Anchors: exact first-touch M1 bar (never padded into empty time).
        //   - Trailing DERIVED: the sim walks bar-by-bar applying the same
        //     Continuous/Step trail math a live trade would run, so the drawn
        //     outcome (trail-stop exit, SL, or TP) matches what WOULD have
        //     happened, trail line included.
        private void DrawRetroactiveExecutions(DateTime nowUTC)
        {
            if (!Show_Visuals) return;

            for (int s = 0; s < SLOT_COUNT; s++)
            {
                SlotState slot = slots[s];
                if (!slot.IsEnabled || !slot.IsRangeLocked) continue;
                if (slot.RangeHigh <= slot.RangeLow) continue;
                // Scope guard — ALL slots: only the CURRENT window is ever
                // simulated or drawn (intraday+daily = this NY day, weekly =
                // this week, monthly = this month). Past cutoff: nothing.
                if (nowUTC >= slot.CutoffTimeUTC) continue;
                if (activeTrades[s] != null && activeTrades[s].EntryPrice > 0) continue;

                SimAndDrawSynthetic(s, true);
                SimAndDrawSynthetic(s, false);
            }
        }

        // Resolved synthetics are final — draw and log once, never re-simulate.
        private readonly HashSet<string> syntheticFinal = new HashSet<string>();

        // Every SessionKey that has EVER produced a real (broker-executed) trade,
        // active OR already closed. Seeded from the on-disk ledger at startup and
        // appended on every close. The synthetic-preview simulator gates on THIS
        // (not the live activeTrade reference) so a resolved session can never be
        // redrawn as a synthetic after its real trade closed and nulled the slot
        // — the "duplicate broker + synthetic execution object" bug.
        private readonly HashSet<string> resolvedSessionKeys = new HashSet<string>();

        // Trail modify debounce: never re-send a stop modify faster than this,
        // and never while one is still in flight (see ActiveTrade.ModifyInFlight).
        private const double MinModifyIntervalMs = 150.0;
        // If a submitted modify never confirms Working within this window, treat
        // it as lost and allow a resend so the trail can never freeze permanently.
        private const double ModifyInFlightTimeoutMs = 2000.0;

        // Bar-by-bar forward simulation with full trail derivation.
        // Bid/ask are approximated by bar H/L (conservative: within a bar,
        // adverse extreme is applied to the stop BEFORE the favorable extreme
        // advances the trail — a sim can never claim a better exit than real).
        private void SimAndDrawSynthetic(int s, bool highSide)
        {
            SlotState slot = slots[s];
            double level = highSide ? slot.RangeHigh : slot.RangeLow;
            bool goLong = Reverse_Orders ? !highSide : highSide;

            DateTime trigTime = highSide ? slot.FirstTouchHighTime : slot.FirstTouchLowTime;
            if (trigTime == DateTime.MinValue) return; // never touched
            if (CurrentBars.Length < 2 || CurrentBars[1] < 1) return;

            // Resolved once = final forever (no re-sim, no re-log, no redraw)
            string finalKey = slot.SessionKey + "|" + (highSide ? "H" : "L");
            if (syntheticFinal.Contains(finalKey)) return;

            // Ledger-backed gate (MT5 SimulateSyntheticExecutions parity): if this
            // SessionKey EVER produced a real trade — active OR already closed —
            // never draw a synthetic for it. This deliberately does NOT look at the
            // live activeTrades[] reference, so it still holds after the real trade
            // closes and nulls the slot (the 24s-later synthetic redraw bug). Any
            // lingering _SYN_ object is removed here as belt-and-suspenders.
            if (!string.IsNullOrEmpty(slot.SessionKey) && resolvedSessionKeys.Contains(slot.SessionKey))
            {
                ORB_Visuals.ClearAllVisuals(this, "S" + s + "_SYN_" + (highSide ? "H" : "L"));
                syntheticFinal.Add(finalKey);
                return;
            }

            // Validity window: the first-touch must fall INSIDE this session's
            // own window (range end → cutoff). Anything else is a stale touch
            // from a previous window (weekend/rollover artifacts) — never
            // simulated, never drawn.
            DateTime windowStart = slot.RangeEndBarTime != DateTime.MinValue
                ? slot.RangeEndBarTime : ORB_Time.UTCToChart(slot.RangeEndTimeUTC);
            DateTime cutoffLocalGuard = ORB_Time.UTCToChart(slot.CutoffTimeUTC);
            if (trigTime < windowStart || trigTime >= cutoffLocalGuard)
            {
                // Clear the bogus marker so it can re-arm cleanly if a real touch comes
                if (highSide) slot.FirstTouchHighTime = DateTime.MinValue;
                else slot.FirstTouchLowTime = DateTime.MinValue;
                return;
            }

            // Simulation clock must stay inside this slot's session window
            DateTime cutoffLocal = ORB_Time.UTCToChart(slot.CutoffTimeUTC);

            double entryPx = level;
            double slDist = Fixed_SL_Ticks * PointSize;
            double tpDist = Fixed_TP_Ticks * PointSize;
            double vSL = goLong ? entryPx - slDist : entryPx + slDist;
            double tpPx = goLong ? entryPx + tpDist : entryPx - tpDist;

            // Trail geometry identical to a live fill's snapshot
            double thresh = Trail_Threshold_Ticks * PointSize;
            double gap = Trail_Gap_Ticks * PointSize;
            bool trailOn = Trail_Behavior != TrailBehavior.Off && thresh > 0;
            bool beOnly = Trail_Behavior == TrailBehavior.Breakeven;
            int minTrailSec = (int)Math.Max(0, Min_Trail_Minutes * 60.0);

            // Locate the trigger bar (barsAgo index of trigTime)
            int maxScan = Math.Min(CurrentBars[1], 60000);
            int trigIdx = -1;
            for (int i = 0; i <= maxScan; i++)
            {
                if (Times[1][i] <= trigTime) { trigIdx = i; break; }
            }
            if (trigIdx < 0) trigIdx = 0;

            bool trailing = false;
            DateTime trailStart = DateTime.MinValue;
            int resIdx = -1;
            string exitKind = null; // "TP" | "SL" | "TRAIL"

            for (int i = trigIdx; i >= 0; i--)
            {
                DateTime bt = Times[1][i];
                if (bt > cutoffLocal) { break; } // session over, trade would EOD-flatten
                double hiB = Highs[1][i], loB = Lows[1][i];

                // 1) Adverse side first: does this bar tag the current stop?
                bool stopHit = goLong ? loB <= vSL : hiB >= vSL;
                if (stopHit)
                {
                    resIdx = i;
                    exitKind = trailing ? "TRAIL" : "SL";
                    break;
                }

                // 2) TP (only meaningful while not trailing past it)
                bool tpHit = goLong ? hiB >= tpPx : loB <= tpPx;
                if (tpHit) { resIdx = i; exitKind = "TP"; break; }

                // 3) Favorable extreme advances the trail (same math as live)
                if (trailOn && (bt - trigTime).TotalSeconds >= minTrailSec)
                {
                    double favor = goLong ? hiB : loB;                 // best price this bar
                    double profit = goLong ? favor - entryPx : entryPx - favor;
                    if (profit >= thresh)
                    {
                        double target;
                        if (beOnly)
                        {
                            if (trailing) target = vSL; // BE is one-shot
                            else target = goLong ? entryPx + BE_Cost_Ticks * PointSize
                                                 : entryPx - BE_Cost_Ticks * PointSize;
                        }
                        else if (Trail_Mode == TrailMode.Step)
                        {
                            int steps = (int)Math.Floor(profit / thresh);
                            target = goLong ? entryPx + (steps * thresh - gap)
                                            : entryPx - (steps * thresh - gap);
                        }
                        else
                        {
                            target = goLong ? favor - gap : favor + gap;
                        }

                        bool improves = goLong ? target > vSL : target < vSL;
                        if (improves)
                        {
                            vSL = target;
                            if (!trailing) { trailing = true; trailStart = bt; }
                        }
                    }
                }
            }

            DateTime rightTime = resIdx >= 0 ? Times[1][resIdx]
                : (ORB_Time.NowChart() < cutoffLocal ? ORB_Time.NowChart() : cutoffLocal);
            DateTime levelTime = slot.RangeEndBarTime != DateTime.MinValue
                ? slot.RangeEndBarTime : ORB_Time.UTCToChart(slot.RangeEndTimeUTC);

            ORB_Visuals.DrawTradeTool(this, "S" + s + "_SYN_" + (highSide ? "H" : "L"), goLong,
                entryPx, vSL, tpPx,
                level, levelTime, trigTime, rightTime,
                trailing, trailStart, true);

            if (resIdx >= 0)
            {
                syntheticFinal.Add(finalKey); // freeze: log + draw exactly once
                Log(string.Format("[ORB] S{0} synthetic {1}: trig {2:F2} @ {3:HH:mm} → {4} @ {5:HH:mm}{6}",
                    s, goLong ? "LONG" : "SHORT", entryPx, trigTime, exitKind, rightTime,
                    trailing ? string.Format(" (trailed, SL {0:F2})", vSL) : ""), LogLevel.Information);
            }
        }

        //======================================================================
        // ── ON BAR UPDATE ──
        //======================================================================
        protected override void OnBarUpdate()
        {
            if (BarsInProgress == 1)
            {
                DateTime m1UTC = ORB_Time.ChartToUTC(Times[1][0]);
                for (int s = 0; s < SLOT_COUNT; s++)
                {
                    if (!slots[s].IsEnabled) continue;
                    RunSlotSession(s, m1UTC);
                }
                return;
            }

            if (BarsInProgress != 0) return;

            // Historical execution is Strategy-Analyzer-only. On a live chart
            // the backfill must never simulate trades (they'd plot NT's
            // execution arrows and skew every number derived from fills).
            if (State == State.Historical && !isAnalyzer) return;

            DateTime currentUTC = ORB_Time.ChartToUTC(Time[0]);
            double bid = GetCurrentBid();
            double ask = GetCurrentAsk();
            // Historical / Strategy Analyzer: no live book — use bar close
            if (bid <= 0) bid = Close[0];
            if (ask <= 0) ask = Close[0];

            if (isHalted)
            {
                notifier?.DrainQueue();
                return;
            }

            double liveCash = Account.Get(AccountItem.CashValue, Currency.UsDollar);
            if (ddTracker.IsBreach(liveCash))
            {
                Log("[ORB] DRAWDOWN FLOOR BREACHED! Halting strategy and flattening all positions.", LogLevel.Alert);
                FlattenEverything("DrawdownBreach");
                isHalted = true;
                return;
            }

            if (Enable_Daily_Loss_Limit)
            {
                dailyLoss = dailyStartBalance - liveCash;
                if (dailyLoss >= Daily_Loss_Limit_Amount)
                {
                    Log("[ORB] Daily Loss Limit reached. Halting for today.", LogLevel.Warning);
                    FlattenEverything("DailyLossLimit");
                    isHalted = true;
                    return;
                }
            }

            NewsGates(currentUTC);

            for (int s = 0; s < SLOT_COUNT; s++)
            {
                if (!slots[s].IsEnabled) continue;
                if (activeTrades[s] != null) ManageTrade(s, currentUTC, bid, ask);

                if (Use_Instant_Market_Execution)
                    InstantEntryWatch(s, currentUTC, bid, ask);
                else
                    PlacePendingEntriesIfReady(s, currentUTC);
            }
        }

        //======================================================================
        // ── PER-SLOT SESSION STATE MACHINE ──
        //======================================================================
        private void RunSlotSession(int s, DateTime nowUTC)
        {
            SlotState slot = slots[s];
            string prevKey = slot.SessionKey;
            RecomputeSlotTimes(s, nowUTC);

            if (prevKey != slot.SessionKey && !string.IsNullOrEmpty(prevKey))
            {
                slot.Reset();
                SweepUnfilledSlot(s, "New session window");
                if (Show_Visuals && State == State.Realtime)
                    ORB_Visuals.ClearAllVisuals(this, "S" + s);
            }

            if (SlotIsIntraday(s))
            {
                SessionLogic.UpdateSlotPhase(slot, nowUTC);

                if (slot.Phase == SessionPhase.RangeForming && !slot.IsRangeLocked)
                {
                    if (ComputeRangeFromM1(slot.RangeStartTimeUTC, slot.RangeEndTimeUTC, out double hi, out double lo,
                        out DateTime fb, out DateTime lb))
                    {
                        slot.RangeHigh = hi;
                        slot.RangeLow = lo;
                        slot.RangeStartBarTime = fb;
                        slot.RangeEndBarTime = lb;
                    }
                }

                if (slot.Phase == SessionPhase.TradingWindow && !slot.IsRangeLocked)
                {
                    if (ComputeRangeFromM1(slot.RangeStartTimeUTC, slot.RangeEndTimeUTC, out double hi, out double lo,
                        out DateTime fb, out DateTime lb) && hi > lo)
                    {
                        slot.RangeHigh = hi;
                        slot.RangeLow = lo;
                        slot.RangeStartBarTime = fb;
                        slot.RangeEndBarTime = lb;
                        slot.IsRangeLocked = true;
                        // Backfill precise first-touch times from M1 history
                        slot.FirstTouchHighTime = FindFirstTouchM1(slot.RangeEndTimeUTC, hi, true);
                        slot.FirstTouchLowTime = FindFirstTouchM1(slot.RangeEndTimeUTC, lo, false);
                        ApplyConsumedSides(s);
                        if (State == State.Realtime) // historical backfill re-locks constantly — don't spam
                            Log(string.Format("[ORB] S{0} {1} range locked: H={2:F2} L={3:F2} ({4} pts)",
                                s, SlotNames[s], hi, lo, Math.Round((hi - lo) / PointSize)), LogLevel.Information);
                    }
                }

                // Live first-touch tracking after lock (newest M1 bar)
                if (slot.IsRangeLocked)
                {
                    if (slot.FirstTouchHighTime == DateTime.MinValue && Highs[1][0] >= slot.RangeHigh)
                        slot.FirstTouchHighTime = Times[1][0];
                    if (slot.FirstTouchLowTime == DateTime.MinValue && Lows[1][0] <= slot.RangeLow)
                        slot.FirstTouchLowTime = Times[1][0];
                }
            }
            else
            {
                if (nowUTC >= slot.CutoffTimeUTC)
                {
                    if (slot.Phase != SessionPhase.Closed)
                    {
                        SweepUnfilledSlot(s, "HTF cutoff reached");
                        slot.Phase = SessionPhase.Closed;
                    }
                    return;
                }

                if (!slot.IsRangeLocked)
                {
                    if (ComputeRangeFromM1(slot.RangeStartTimeUTC, slot.RangeEndTimeUTC, out double hi, out double lo,
                        out DateTime fb, out DateTime lb) && hi > lo)
                    {
                        slot.RangeHigh = hi;
                        slot.RangeLow = lo;
                        slot.RangeStartBarTime = fb;
                        slot.RangeEndBarTime = lb;
                        slot.IsRangeLocked = true;
                        slot.Phase = SessionPhase.TradingWindow;
                        slot.FirstTouchHighTime = FindFirstTouchM1(slot.RangeEndTimeUTC, hi, true);
                        slot.FirstTouchLowTime = FindFirstTouchM1(slot.RangeEndTimeUTC, lo, false);
                        ApplyConsumedSides(s);
                        if (State == State.Realtime)
                            Log(string.Format("[ORB] S{0} {1} HTF range locked: H={2:F2} L={3:F2}",
                                s, SlotNames[s], hi, lo), LogLevel.Information);
                    }
                    else
                    {
                        slot.Phase = SessionPhase.Waiting;
                    }
                }
                else
                {
                    slot.Phase = SessionPhase.TradingWindow;
                    if (slot.FirstTouchHighTime == DateTime.MinValue && Highs[1][0] >= slot.RangeHigh)
                        slot.FirstTouchHighTime = Times[1][0];
                    if (slot.FirstTouchLowTime == DateTime.MinValue && Lows[1][0] <= slot.RangeLow)
                        slot.FirstTouchLowTime = Times[1][0];
                }
            }

            if (slot.Phase == SessionPhase.Closed && slot.IsRangeLocked)
            {
                SweepUnfilledSlot(s, "Session cutoff");
                // Past the close: intraday drawings are done for the day —
                // clear everything for this slot (ledger CSVs keep the record).
                if (Show_Visuals && State == State.Realtime && SlotIsIntraday(s))
                    ORB_Visuals.ClearAllVisuals(this, "S" + s);
                slot.Reset();
                slot.Phase = SessionPhase.Closed;
            }

            if (SlotIsIntraday(s) && ORB_Time.IsMaintenanceGap(nowUTC))
                slot.Phase = SessionPhase.Waiting;
        }

        // Consumed-ledger: block sides that already triggered this session
        // (survives restarts — MT5 phantom re-fire fix #4).
        private void ApplyConsumedSides(int s)
        {
            SlotState slot = slots[s];
            if (state.IsSideConsumed(slot.SessionKey, true))
            {
                slot.LongOrderPlaced = true;
                Log(string.Format("[ORB] S{0}: LONG side already consumed this session — not re-arming.", s), LogLevel.Information);
            }
            if (state.IsSideConsumed(slot.SessionKey, false))
            {
                slot.ShortOrderPlaced = true;
                Log(string.Format("[ORB] S{0}: SHORT side already consumed this session — not re-arming.", s), LogLevel.Information);
            }
        }

        private static readonly Brush[] SlotBoxBrush = {
            ORB_Visuals.ClrRangeBoxNY, ORB_Visuals.ClrRangeBoxLondon, ORB_Visuals.ClrRangeBoxAsian,
            ORB_Visuals.ClrRangeBoxDaily, ORB_Visuals.ClrRangeBoxWeekly, ORB_Visuals.ClrRangeBoxWeekly };

        private void DrawSlotRange(int s)
        {
            if (!Show_Visuals || State != State.Realtime) return;
            SlotState slot = slots[s];
            if (slot.RangeHigh == double.MinValue || slot.RangeLow == double.MaxValue) return;
            if (slot.RangeHigh <= slot.RangeLow) return;

            // Anchor to ACTUAL bars in the window — never the theoretical
            // window times (weekends/maintenance would stretch the box).
            DateTime t1 = slot.RangeStartBarTime != DateTime.MinValue ? slot.RangeStartBarTime : ORB_Time.UTCToChart(slot.RangeStartTimeUTC);
            DateTime t2 = slot.RangeEndBarTime != DateTime.MinValue ? slot.RangeEndBarTime : ORB_Time.UTCToChart(slot.RangeEndTimeUTC);

            // MT5 style: filled box, NO border, behind candles
            ORB_Visuals.DrawRangeBox(this, "S" + s + "_RangeBox", t1, t2,
                slot.RangeHigh, slot.RangeLow, SlotBoxBrush[s], slot.IsRangeLocked ? 40 : 25);

            // Level lines: bounded, from the LEFT edge of the range box →
            // the precise first touch (or → now, dashed, while untouched)
            if (slot.IsRangeLocked)
            {
                DateTime nowLocal = ORB_Time.NowChart();
                bool tradable = slot.Phase == SessionPhase.TradingWindow;

                if (slot.FirstTouchHighTime != DateTime.MinValue)
                    ORB_Visuals.DrawBoundedLine(this, "S" + s + "_PendHigh",
                        t1, slot.RangeHigh, slot.FirstTouchHighTime, slot.RangeHigh,
                        ORB_Visuals.ClrEntryLine, DashStyleHelper.Solid, 2);
                else if (tradable)
                    ORB_Visuals.DrawPendingLine(this, "S" + s + "_PendHigh", slot.RangeHigh, t1, nowLocal);

                if (slot.FirstTouchLowTime != DateTime.MinValue)
                    ORB_Visuals.DrawBoundedLine(this, "S" + s + "_PendLow",
                        t1, slot.RangeLow, slot.FirstTouchLowTime, slot.RangeLow,
                        ORB_Visuals.ClrEntryLine, DashStyleHelper.Solid, 2);
                else if (tradable)
                    ORB_Visuals.DrawPendingLine(this, "S" + s + "_PendLow", slot.RangeLow, t1, nowLocal);
            }
        }

        private bool ComputeRangeFromM1(DateTime startUTC, DateTime endUTC, out double hi, out double lo,
            out DateTime firstBarLocal, out DateTime lastBarLocal)
        {
            hi = double.MinValue;
            lo = double.MaxValue;
            firstBarLocal = DateTime.MinValue;
            lastBarLocal = DateTime.MinValue;
            if (CurrentBars.Length < 2 || CurrentBars[1] < 1) return false;

            DateTime startLocal = ORB_Time.UTCToChart(startUTC);
            DateTime endLocal = ORB_Time.UTCToChart(endUTC);

            int maxScan = Math.Min(CurrentBars[1], 60000);
            for (int i = 0; i <= maxScan; i++)
            {
                DateTime t = Times[1][i];
                if (t <= startLocal) break;
                if (t > endLocal) continue;
                if (Highs[1][i] > hi) hi = Highs[1][i];
                if (Lows[1][i] < lo) lo = Lows[1][i];
                if (t > lastBarLocal) lastBarLocal = t;      // newest bar in window
                firstBarLocal = t;                            // loop ends on oldest in window
            }
            return hi > double.MinValue && lo < double.MaxValue;
        }

        // First M1 bar AFTER the range end whose H/L tags the level — the
        // precise historical first-touch (right anchor of the entry line).
        private DateTime FindFirstTouchM1(DateTime rangeEndUTC, double level, bool highSide)
        {
            if (CurrentBars.Length < 2 || CurrentBars[1] < 1) return DateTime.MinValue;
            DateTime endLocal = ORB_Time.UTCToChart(rangeEndUTC);
            int maxScan = Math.Min(CurrentBars[1], 60000);
            // Walk oldest→newest after the window: descending barsAgo
            for (int i = maxScan; i >= 0; i--)
            {
                if (i > CurrentBars[1]) continue;
                DateTime t = Times[1][i];
                if (t <= endLocal) continue;
                bool touched = highSide ? Highs[1][i] >= level : Lows[1][i] <= level;
                if (touched) return t;
            }
            return DateTime.MinValue;
        }

        //======================================================================
        // ── SIZING (shared by both entry modes) ──
        //======================================================================
        private int ComputeContracts(int s)
        {
            if (venueBlocked) return 0;
            if (slotRejections[s] >= MAX_SLOT_REJECTIONS) return 0;

            double liveCash = Account.Get(AccountItem.CashValue, Currency.UsDollar);
            if (liveCash <= 0) liveCash = Starting_Balance;

            double pointValue = Instrument.MasterInstrument.PointValue;
            double slPriceDistance = Fixed_SL_Ticks * PointSize;
            int contracts = ORB_Risk.CalcContracts(
                liveCash, Risk_Percent, slPriceDistance, pointValue,
                Contract_Mode, Max_Contracts_Override);

            double marginPerContract = ORB_Risk.GetMarginPerContract(Instrument.MasterInstrument.Name);
            double freeMargin = Account.Get(AccountItem.ExcessIntradayMargin, Currency.UsDollar);
            if (freeMargin > 0)
            {
                double marginBudget = ORB_Risk.MarginBudget(freeMargin, Max_Margin_Usage_Percent);
                contracts = ORB_Risk.MarginCappedContracts(contracts, marginBudget, marginPerContract);
            }

            if (contracts < 1 && Max_Contracts_Override > 0) contracts = 1;
            return contracts;
        }

        private bool SlotReadyToArm(int s, DateTime currentUTC)
        {
            SlotState slot = slots[s];
            if (activeTrades[s] != null) return false;
            if (slot.Phase != SessionPhase.TradingWindow || !slot.IsRangeLocked) return false;
            if (slot.LongOrderPlaced && slot.ShortOrderPlaced) return false;
            if (slot.RangeHigh <= 0 || slot.RangeLow <= 0 ||
                slot.RangeHigh == double.MinValue || slot.RangeLow == double.MaxValue ||
                slot.RangeHigh <= slot.RangeLow) return false;
            if (News_Guard_Mode != NewsGuardMode.Off &&
                newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins, News_Guard_Mode)) return false;
            return true;
        }

        //======================================================================
        // ── INSTANT MARKET EXECUTION (Use_Instant_Market_Execution) ──
        // Tick-triggered market entry at the range level. If price has already
        // slipped beyond Instant_Max_Entry_Slippage_Ticks past the level, the
        // entry is SKIPPED and the side marked consumed — never chased.
        //======================================================================
        private void InstantEntryWatch(int s, DateTime currentUTC, double bid, double ask)
        {
            if (!SlotReadyToArm(s, currentUTC)) return;
            SlotState slot = slots[s];
            if (bid <= 0 || ask <= 0) return;

            // ── STALE-LEVEL GUARD (MT5 XAUUSD 2026-07-20 bug class) ──
            // On the FIRST evaluation after this slot arms, any level price has
            // already breached is consumed WITHOUT execution — even if price
            // later drifts back inside the slippage gate. A breakout that
            // happened while we weren't watching is not our trade.
            if (!slot.InstantArmed)
            {
                slot.InstantArmed = true;
                bool highBreached = ask >= slot.RangeHigh;
                bool lowBreached = bid <= slot.RangeLow;
                if (highBreached)
                {
                    bool longSide = !Reverse_Orders;
                    if (longSide) slot.LongOrderPlaced = true; else slot.ShortOrderPlaced = true;
                    if (wasRealtime) state.MarkSideConsumed(slot.SessionKey, longSide);
                    Log(string.Format("[ORB] S{0} HIGH level STALE: already breached before arming (level={1:F2} ask={2:F2}) — side consumed, no execution.",
                        s, slot.RangeHigh, ask), LogLevel.Warning);
                }
                if (lowBreached)
                {
                    bool longSide = Reverse_Orders;
                    if (longSide) slot.LongOrderPlaced = true; else slot.ShortOrderPlaced = true;
                    if (wasRealtime) state.MarkSideConsumed(slot.SessionKey, longSide);
                    Log(string.Format("[ORB] S{0} LOW level STALE: already breached before arming (level={1:F2} bid={2:F2}) — side consumed, no execution.",
                        s, slot.RangeLow, bid), LogLevel.Warning);
                }
                Log(string.Format("[ORB] S{0} {1} instant exec ARMED: HIGH={2:F2} LOW={3:F2} | bid={4:F2} ask={5:F2} | maxSlip={6:F0} pts = {7:F2} price (point={8})",
                    s, SlotNames[s], slot.RangeHigh, slot.RangeLow, bid, ask,
                    Instant_Max_Entry_Slippage_Ticks, Instant_Max_Entry_Slippage_Ticks * PointSize, PointSize), LogLevel.Information);
                if (highBreached || lowBreached) return;
            }

            double maxSlip = Instant_Max_Entry_Slippage_Ticks * PointSize;

            // Which physical side triggered? (high breakout / low breakdown)
            bool highTrig = ask >= slot.RangeHigh;
            bool lowTrig  = bid <= slot.RangeLow;
            if (!highTrig && !lowTrig) return;

            // Direction depends on Reverse_Orders:
            //   normal : high → BUY,  low → SELL
            //   reverse: high → SELL, low → BUY
            bool sideIsHigh = highTrig; // if both fire on one tick, high wins deterministically
            double level = sideIsHigh ? slot.RangeHigh : slot.RangeLow;
            bool goLong = Reverse_Orders ? !sideIsHigh : sideIsHigh;

            // Side already used?
            bool sideFlag = goLong ? slot.LongOrderPlaced : slot.ShortOrderPlaced;
            if (sideFlag) return;

            // Slippage gate: distance of the actionable price PAST the level
            double slip = sideIsHigh ? (ask - level) : (level - bid);
            if (slip > maxSlip)
            {
                // Skip, never chase — consume the side for this session
                if (goLong) slot.LongOrderPlaced = true; else slot.ShortOrderPlaced = true;
                if (wasRealtime) state.MarkSideConsumed(slot.SessionKey, goLong);
                Log(string.Format("[ORB] S{0} {1}: INSTANT ENTRY SKIPPED — price {2:F2} is {3:F1} pts ({4:F2} price) past level {5:F2}; max allowed {6:F0} pts ({7:F2} price). Never chased.",
                    s, SlotNames[s], sideIsHigh ? ask : bid, slip / PointSize, slip, level,
                    Instant_Max_Entry_Slippage_Ticks, maxSlip), LogLevel.Warning);
                notifier?.NotifyCancelled(ocoCounter, slot.SessionKey, goLong, sideIsHigh ? ask : bid,
                    string.Format("Instant entry skipped: {0:F1} pts slippage past {1:F2}", slip / PointSize, level));
                return;
            }

            int contracts = ComputeContracts(s);
            if (contracts < 1)
            {
                slot.LongOrderPlaced = true;
                slot.ShortOrderPlaced = true;
                Log(string.Format("[ORB] S{0}: contracts < 1 — slot disarmed for this session.", s), LogLevel.Warning);
                return;
            }

            string ocoGroup = string.Format("ORB_S{0}_{1}", s, ++ocoCounter);
            var trade = new ActiveTrade
            {
                OcoGroup = ocoGroup,
                Contracts = contracts,
                SlotIndex = s,
                SessionKey = slot.SessionKey,
                IsLong = goLong,
                EntryPrice = 0, // set on fill
                VirtualSL = 0,
                EntryTime = DateTime.MinValue
            };
            // IntendedLevel for slip calc + entry-line drawing
            trade.LevelPx = level;
            trade.LevelTime = slot.RangeEndBarTime != DateTime.MinValue
                ? slot.RangeEndBarTime : ORB_Time.UTCToChart(slot.RangeEndTimeUTC);

            trade.EntryOrder = SubmitOrderUnmanaged(0,
                goLong ? OrderAction.Buy : OrderAction.SellShort,
                OrderType.Market, contracts, 0, 0, ocoGroup,
                goLong ? "LongEntry" : "ShortEntry");
            activeTrades[s] = trade;

            if (goLong) slot.LongOrderPlaced = true; else slot.ShortOrderPlaced = true;

            Log(string.Format("[ORB] S{0} {1} INSTANT {2} x{3} @ ~{4:F2} (level {5:F2}, slip {6:F1}t)",
                s, SlotNames[s], goLong ? "BUY" : "SELL", contracts,
                sideIsHigh ? ask : bid, level, slip / PointSize), LogLevel.Information);
        }

        //======================================================================
        // ── PENDING-ORDER MODE (classic stop / stop-limit / reverse limit) ──
        //======================================================================
        private void PlacePendingEntriesIfReady(int s, DateTime currentUTC)
        {
            if (!SlotReadyToArm(s, currentUTC)) return;
            SlotState slot = slots[s];

            int contracts = ComputeContracts(s);
            if (contracts < 1)
            {
                slot.LongOrderPlaced = true;
                slot.ShortOrderPlaced = true;
                Log(string.Format("[ORB] S{0}: contracts < 1 — slot disarmed for this session.", s), LogLevel.Warning);
                return;
            }

            string ocoGroup = string.Format("ORB_S{0}_{1}", s, ++ocoCounter);
            var trade = new ActiveTrade
            {
                OcoGroup = ocoGroup,
                Contracts = contracts,
                SlotIndex = s,
                SessionKey = slot.SessionKey,
                EntryPrice = 0,
                EntryTime = DateTime.MinValue
            };

            bool armLong = !slot.LongOrderPlaced;
            bool armShort = !slot.ShortOrderPlaced;

            if (armLong && armShort)
            {
                var (buySide, sellSide) = ORB_Execution.PlacePendingEntryOCO(
                    this, slot.RangeHigh, slot.RangeLow, contracts, ocoGroup,
                    Use_StopLimit_Orders, Reverse_Orders);
                trade.EntryOrder = buySide;
                trade.OtherEntryOrder = sellSide;
            }
            else if (armLong)
            {
                double level = Reverse_Orders ? slot.RangeLow : slot.RangeHigh;
                trade.EntryOrder = ORB_Execution.PlacePendingEntrySide(this, true, level, contracts, ocoGroup, Use_StopLimit_Orders, Reverse_Orders);
            }
            else
            {
                double level = Reverse_Orders ? slot.RangeHigh : slot.RangeLow;
                trade.OtherEntryOrder = ORB_Execution.PlacePendingEntrySide(this, false, level, contracts, ocoGroup, Use_StopLimit_Orders, Reverse_Orders);
            }

            activeTrades[s] = trade;
            slot.LongOrderPlaced = true;
            slot.ShortOrderPlaced = true;

            notifier?.NotifySetup(ocoCounter, slot.SessionKey, true,
                slot.RangeHigh, slot.RangeLow, slot.RangeHigh, 0, 0, SlotNames[s]);

            Log(string.Format("[ORB] S{0} {1} pending {2} placed: H={3:F2} L={4:F2} x{5}{6}",
                s, SlotNames[s], armLong && armShort ? "OCO" : "single-side",
                slot.RangeHigh, slot.RangeLow, contracts,
                Reverse_Orders ? " (REVERSE: fade)" : ""), LogLevel.Information);
        }

        private void SweepUnfilledSlot(int s, string reason)
        {
            var t = activeTrades[s];
            if (t == null) return;
            if (t.EntryPrice > 0) return;

            TryCancelOrder(t.EntryOrder);
            TryCancelOrder(t.OtherEntryOrder);
            activeTrades[s] = null;
            Log(string.Format("[ORB] S{0} {1}: unfilled entries cancelled ({2}).", s, SlotNames[s], reason), LogLevel.Information);
        }

        //======================================================================
        // ── NEWS GATES ──
        //======================================================================
        private void NewsGates(DateTime currentUTC)
        {
            bool newsOn = News_Guard_Mode != NewsGuardMode.Off;

            if (newsOn && News_Flatten_Before && newsEngine.IsNewsFlattening(currentUTC, News_Block_Before_Mins, News_Guard_Mode))
            {
                for (int s = 0; s < SLOT_COUNT; s++)
                {
                    var t = activeTrades[s];
                    if (t != null && t.EntryPrice > 0)
                    {
                        CloseSlotPosition(s, "NewsFlatten");
                        Log(string.Format("[ORB] News flatten: closed S{0} position.", s), LogLevel.Warning);
                    }
                }
            }

            bool strictActive = newsOn && News_Cancel_Pending
                && newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins, News_Guard_Mode);

            if (strictActive)
            {
                if (!strictSweepDone)
                {
                    strictSweepDone = true;
                    for (int s = 0; s < SLOT_COUNT; s++)
                    {
                        strictRearmLong[s] = false;
                        strictRearmShort[s] = false;
                        var t = activeTrades[s];
                        if (t == null) continue;
                        if (t.EntryPrice > 0) continue;

                        if (IsWorkingOrder(t.EntryOrder))      { strictRearmLong[s] = true;  TryCancelOrder(t.EntryOrder); }
                        if (IsWorkingOrder(t.OtherEntryOrder)) { strictRearmShort[s] = true; TryCancelOrder(t.OtherEntryOrder); }
                        activeTrades[s] = null;
                        Log(string.Format("[ORB] News sweep: S{0} pending entries cancelled.", s), LogLevel.Warning);
                    }
                }
            }
            else if (strictSweepDone)
            {
                strictSweepDone = false;
                for (int s = 0; s < SLOT_COUNT; s++)
                {
                    if (strictRearmLong[s])  { slots[s].LongOrderPlaced = false;  strictRearmLong[s] = false; }
                    if (strictRearmShort[s]) { slots[s].ShortOrderPlaced = false; strictRearmShort[s] = false; }
                }
                Log("[ORB] News window cleared: swept slots re-armed.", LogLevel.Information);
            }
        }

        //======================================================================
        // ── ORDER CALLBACKS ──
        //======================================================================
        private int FindSlotForEntryOrder(Order order)
        {
            for (int s = 0; s < SLOT_COUNT; s++)
            {
                var t = activeTrades[s];
                if (t == null) continue;
                if (order == t.EntryOrder || order == t.OtherEntryOrder) return s;
            }
            return -1;
        }

        private int FindSlotForExitOrder(Order order)
        {
            for (int s = 0; s < SLOT_COUNT; s++)
            {
                var t = activeTrades[s];
                if (t == null) continue;
                if (order == t.SlOrder || order == t.TpOrder) return s;
            }
            return -1;
        }

        protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice,
            int quantity, int filled, double averageFillPrice,
            OrderState orderState, DateTime time, ErrorCode error, string nativeError)
        {
            // Trail debounce release: the instant a tracked protective stop reports
            // back Working (or Accepted), its modify has landed at the broker, so we
            // allow the next trail move. Clearing on ANY other state (ChangeSubmitted,
            // CancelSubmitted, ...) would let a second modify race the first — the
            // exact overlapping-modify churn that caused the stale-stop leak.
            if ((orderState == OrderState.Working || orderState == OrderState.Accepted)
                && error == ErrorCode.NoError && activeTrades != null)
            {
                for (int i = 0; i < SLOT_COUNT; i++)
                {
                    var at = activeTrades[i];
                    if (at != null && at.ModifyInFlight && ReferenceEquals(at.SlOrder, order))
                    {
                        at.ModifyInFlight = false;
                        break;
                    }
                }
            }

            if (error == ErrorCode.NoError && orderState != OrderState.Rejected) return;

            if (orderState == OrderState.Rejected)
            {
                totalRejections++;
                Log(string.Format("[ORB] Order REJECTED ({0}/{1}): {2} — {3} / {4}",
                    totalRejections, MAX_TOTAL_REJECTIONS, order.Name, error, nativeError), LogLevel.Error);

                // Data-feed / permission rejections poison every subsequent
                // order — stop arming entirely instead of spraying retries.
                string ne = (nativeError ?? "").ToLowerInvariant();
                if (ne.Contains("not subscribed") || ne.Contains("data feed") ||
                    ne.Contains("permission") || ne.Contains("not authorized"))
                {
                    venueBlocked = true;
                    Log("[ORB] VENUE BLOCKED: data-feed/permission rejection detected. " +
                        "Arming suspended — fix the data subscription (or use Playback/other feed) and re-enable the strategy.", LogLevel.Alert);
                }

                int s = FindSlotForEntryOrder(order);
                if (s >= 0)
                {
                    slotRejections[s]++;
                    var t = activeTrades[s];
                    TryCancelOrder(t.EntryOrder);
                    TryCancelOrder(t.OtherEntryOrder);
                    activeTrades[s] = null;

                    if (slotRejections[s] < MAX_SLOT_REJECTIONS && !venueBlocked)
                    {
                        // Re-arm for a retry next tick
                        slots[s].LongOrderPlaced = false;
                        slots[s].ShortOrderPlaced = false;
                        Log(string.Format("[ORB] S{0} entry rejected — will retry (attempt {1}/{2}).",
                            s, slotRejections[s], MAX_SLOT_REJECTIONS), LogLevel.Warning);
                    }
                    else
                    {
                        slots[s].LongOrderPlaced = true;
                        slots[s].ShortOrderPlaced = true;
                        Log(string.Format("[ORB] S{0} disarmed after {1} rejections.", s, slotRejections[s]), LogLevel.Alert);
                    }
                }
                else
                {
                    s = FindSlotForExitOrder(order);
                    if (s >= 0)
                    {
                        var t = activeTrades[s];
                        Log(string.Format("[ORB] S{0} BRACKET REJECTED — position may be unprotected! Attempting one re-place.", s), LogLevel.Alert);
                        // One re-place attempt with fresh OCO group
                        if (t != null && t.EntryPrice > 0 && !venueBlocked)
                        {
                            double slDist = Math.Abs(t.EntryPrice - t.VirtualSL);
                            double tpDist = Math.Abs(t.TpPrice > 0 ? t.TpPrice - t.EntryPrice : Fixed_TP_Ticks * PointSize);
                            if (slDist <= 0) slDist = Fixed_SL_Ticks * PointSize;
                            // Deliberate exception: this is the "bracket rejected,
                            // position possibly unprotected" recovery path. A slip
                            // cap could leave a re-placed stop unfilled on a gap, so
                            // here we force a guaranteed StopMarket exit (cap = 0).
                            var (slO, tpO) = ORB_Execution.PlaceBracketOrders(this, t.IsLong, t.EntryPrice, t.Contracts,
                                slDist, Math.Abs(tpDist), t.OcoGroup + "_R" + (++ocoCounter), 0);
                            t.SlOrder = slO;
                            t.TpOrder = tpO;
                        }
                    }
                }

                if (totalRejections >= MAX_TOTAL_REJECTIONS)
                {
                    isHalted = true;
                    Log("[ORB] HALTED: too many order rejections. Check data subscription / account permissions, then re-enable the strategy.", LogLevel.Alert);
                    notifier?.Enqueue("**ORB HALTED** — too many order rejections. Check data feed / account permissions.", 0xE74C3C);
                }
            }
            else if (error != ErrorCode.NoError)
            {
                Log(string.Format("[ORB] Order error: {0} / {1} on {2}", error, nativeError, order.Name), LogLevel.Error);
            }
        }

        protected override void OnExecutionUpdate(Execution execution, string executionId, double price,
            int quantity, MarketPosition marketPosition, string orderId, DateTime time)
        {
            // ── Entry fills ──
            int s = FindSlotForEntryOrder(execution.Order);
            if (s >= 0 && execution.Order.OrderState == OrderState.Filled)
            {
                var trade = activeTrades[s];
                bool shortFilled = execution.Order == trade.OtherEntryOrder;

                if (shortFilled)
                {
                    var tmp = trade.EntryOrder;
                    trade.EntryOrder = trade.OtherEntryOrder;
                    trade.OtherEntryOrder = tmp;
                }

                if (trade.OtherEntryOrder != null &&
                    trade.OtherEntryOrder.OrderState != OrderState.Cancelled &&
                    trade.OtherEntryOrder.OrderState != OrderState.Filled)
                {
                    CancelOrder(trade.OtherEntryOrder);
                }

                // Order.AverageFillPrice / Order.Filled are the VWAP and cumulative
                // quantity across ALL slices of a partially-filled entry. Reading
                // execution.Price/.Quantity would only see the last slice and size
                // the bracket + notification to a fraction of the real position.
                double fillPx = execution.Order.AverageFillPrice;
                int filledQty = execution.Order.Filled;
                bool isLong = (marketPosition == MarketPosition.Long);

                // Intended level: instant mode stashed it in VirtualSL pre-fill;
                // pending mode derives it from the range and direction.
                double intendedLevel = trade.LevelPx > 0 ? trade.LevelPx
                    : (isLong != Reverse_Orders ? slots[s].RangeHigh : slots[s].RangeLow);
                double slipTicks = TickSize > 0 ? Math.Abs(fillPx - intendedLevel) / PointSize : 0;
                if (trade.LevelPx <= 0)
                {
                    trade.LevelPx = intendedLevel;
                    trade.LevelTime = slots[s].RangeEndBarTime != DateTime.MinValue
                        ? slots[s].RangeEndBarTime : ORB_Time.UTCToChart(slots[s].RangeEndTimeUTC);
                }

                trade.IsLong = isLong;
                trade.EntryPrice = fillPx;
                trade.EntryTime = ORB_Time.ChartToUTC(time);
                trade.SlipTicks = slipTicks;
                trade.SessionKey = slots[s].SessionKey;

                // ── Excess-slip detection (Max_Slippage_Ticks) ──
                // SL/TP are still recentred on the actual fill, but trailing is
                // replaced by force-close-at-profit (never at a loss).
                if (Max_Slippage_Ticks > 0 && slipTicks > Max_Slippage_Ticks)
                {
                    trade.SlipForceClose = true;
                    Log(string.Format("[ORB] S{0}: EXCESS SLIP {1:F1} pts (max {2:F0}). Trailing disabled — will close at +{3:F0} pts profit.",
                        s, slipTicks, Max_Slippage_Ticks, Slip_ForceClose_Profit_Ticks), LogLevel.Warning);
                }

                double slDistance = Fixed_SL_Ticks * PointSize;
                double tpDistance = Fixed_TP_Ticks * PointSize;
                double slPx = isLong ? fillPx - slDistance : fillPx + slDistance;
                double tpPx = isLong ? fillPx + tpDistance : fillPx - tpDistance;
                trade.VirtualSL = slPx;
                trade.TpPrice = tpPx;

                // ── Freeze trailing geometry (MT5 snapshot parity): changing
                //    inputs mid-trade never affects an already-open position.
                double curBid = GetCurrentBid(), curAsk = GetCurrentAsk();
                trade.SnapTrailMode = (int)Trail_Mode;
                trade.SnapBehavior = Trail_Behavior == TrailBehavior.Trail ? 0
                                   : Trail_Behavior == TrailBehavior.Breakeven ? 1 : 2;
                trade.SnapThreshPrice = Trail_Threshold_Ticks * PointSize;
                trade.SnapGapPrice = Trail_Gap_Ticks * PointSize;
                trade.SnapMinTrailSec = (int)Math.Max(0, Min_Trail_Minutes * 60.0);
                trade.SnapSpreadComp = Use_Spread_Compensation;
                trade.SnapEntrySpread = curAsk > 0 && curBid > 0 ? Math.Max(0, curAsk - curBid) : 0;
                trade.SnapBECostPrice = Use_Spread_Compensation
                    ? (Commission_Per_Contract / Math.Max(1e-9, Instrument.MasterInstrument.PointValue))
                    : BE_Cost_Ticks * PointSize;

                // Record the true position size and bracket the WHOLE position;
                // a StopLimit slip cap keeps the protective stop from filling
                // worse than Stop_Slip_Cap_Ticks past its trigger (0 = StopMarket).
                trade.Contracts = filledQty;
                double slipCap = SlipCapPoints(trade);
                var (slOrder, tpOrder) = ORB_Execution.PlaceBracketOrders(this, isLong, fillPx, filledQty,
                    slDistance, tpDistance, trade.OcoGroup + "_BRK", slipCap);
                trade.SlOrder = slOrder;
                trade.TpOrder = tpOrder;

                // Consumed-side ledger: this side never re-arms this session
                if (wasRealtime) state.MarkSideConsumed(trade.SessionKey, isLong);
                SaveLiveSnapshots();

                // A real fill supersedes the synthetic PREVIEW for BOTH sides of
                // this slot (the OCO cancels the opposing pending entry anyway).
                // Remove the synthetic execution boxes and freeze their keys so
                // the retro simulator never redraws them — otherwise the broker
                // box S{s}_LIVE and the synthetic box S{s}_SYN_* coexist, which is
                // the "duplicate synthetic + broker-backed object" on the chart.
                ORB_Visuals.ClearAllVisuals(this, "S" + s + "_SYN_H");
                ORB_Visuals.ClearAllVisuals(this, "S" + s + "_SYN_L");
                syntheticFinal.Add(slots[s].SessionKey + "|H");
                syntheticFinal.Add(slots[s].SessionKey + "|L");
                // Persistent gate: this session is now resolved for the whole
                // run, so the retro simulator won't redraw it once the slot nulls.
                if (!string.IsNullOrEmpty(slots[s].SessionKey))
                    resolvedSessionKeys.Add(slots[s].SessionKey);
                // (trade tool is drawn by the 1s visual pulse from here on)

                notifier?.NotifyFill(ocoCounter, trade.SessionKey, isLong, fillPx, slPx, tpPx, filledQty);
                Log(string.Format("[ORB] S{0} {1} filled: {2} @ {3:F2} (slip {4:F1}pt), SL={5:F2}, TP={6:F2} x{7}",
                    s, SlotNames[s], isLong ? "LONG" : "SHORT", fillPx, slipTicks, slPx, tpPx, filledQty), LogLevel.Information);
                return;
            }

            // ── Exit fills (SL / TP / force-close) ──
            s = FindSlotForExitOrder(execution.Order);
            if (s < 0 && activeTrades != null)
            {
                // Force-close market orders carry the slot in their signal name
                for (int i = 0; i < SLOT_COUNT; i++)
                {
                    var t2 = activeTrades[i];
                    if (t2 != null && t2.EntryPrice > 0 &&
                        execution.Order.Name.StartsWith("CloseS" + i + "_"))
                    { s = i; break; }
                }
            }
            if (s >= 0 && execution.Order.OrderState == OrderState.Filled)
            {
                var trade = activeTrades[s];
                if (trade == null) return;

                string reason = execution.Order == trade.SlOrder ? "SL"
                              : execution.Order == trade.TpOrder ? "TP"
                              : execution.Order.Name.Contains("_") ? execution.Order.Name.Substring(execution.Order.Name.IndexOf('_') + 1)
                              : "Close";

                // Use the exit order's VWAP and cumulative fill so a sliced
                // TP/SL books the whole position's realized PnL, not the last
                // slice — this is the +$350-vs-+$62 notification bug.
                FinalizeClosedTrade(s, execution.Order.AverageFillPrice, execution.Order.Filled,
                    ORB_Time.ChartToUTC(time), reason);

                if (execution.Order == trade.SlOrder) TryCancelOrder(trade.TpOrder);
                else if (execution.Order == trade.TpOrder) TryCancelOrder(trade.SlOrder);
                else { TryCancelOrder(trade.SlOrder); TryCancelOrder(trade.TpOrder); }

                if (State == State.Realtime && Show_Visuals)
                {
                    // Freeze the live tool into a resolved one: right edge = exit
                    ORB_Visuals.DrawTradeTool(this, "S" + s + "_LIVE", trade.IsLong,
                        trade.EntryPrice, trade.VirtualSL, trade.TpPrice,
                        trade.LevelPx > 0 ? trade.LevelPx : trade.EntryPrice,
                        trade.LevelTime != DateTime.MinValue ? trade.LevelTime : ORB_Time.UTCToChart(trade.EntryTime),
                        ORB_Time.UTCToChart(trade.EntryTime), ORB_Time.UTCToChart(ORB_Time.ChartToUTC(time)),
                        trade.TrailingActivated, trade.TrailStartTime, false);
                }

                activeTrades[s] = null;
                SaveLiveSnapshots();
            }
        }

        // Book a closed trade: trackers + ledger + notification.
        private void FinalizeClosedTrade(int s, double exitPrice, int quantity, DateTime closeUTC, string reason)
        {
            var trade = activeTrades[s];
            if (trade == null || trade.EntryPrice <= 0) return;

            double direction = trade.IsLong ? 1.0 : -1.0;
            double pnl = (exitPrice - trade.EntryPrice) * direction
                         * Instrument.MasterInstrument.PointValue * quantity
                         - Commission_Per_Contract * quantity;

            double holdSecs = (closeUTC - trade.EntryTime).TotalSeconds;

            // This session has now produced a resolved trade — suppress any
            // future synthetic preview for it (survives the slot being nulled).
            if (!string.IsNullOrEmpty(trade.SessionKey)) resolvedSessionKeys.Add(trade.SessionKey);

            // BROKER-BACKED ONLY: the trackers feeding the dashboard (eval
            // profit, consistency, quick-trades, traded days) count REAL
            // executions exclusively. Historical backfill, Strategy Analyzer,
            // AND Sim101 / Playback / Replay accounts (which DO reach
            // State.Realtime) were leaking in here and showing phantom eval PnL.
            if (wasRealtime && !isSimOrPlayback)
            {
                consistencyTracker.RecordTrade(closeUTC.Date, pnl);
                fastTradeTracker.RecordTrade(holdSecs, pnl);

                if (closeUTC.Date > lastDayClosedUTC.Date)
                {
                    tradingDaysCompleted++;
                    ddTracker.OnDayClose(Account.Get(AccountItem.CashValue, Currency.UsDollar));
                    lastDayClosedUTC = closeUTC;
                }
            }

            if (wasRealtime && !isSimOrPlayback) // backtests AND sim/playback must not pollute the live ledger
                state.AppendClosedTrade(new LedgerTrade
                {
                    EntryTimeUTC = trade.EntryTime,
                    ExitTimeUTC = closeUTC,
                    SlotIndex = s,
                    SessionKey = trade.SessionKey ?? "",
                    IsLong = trade.IsLong,
                    EntryPrice = trade.EntryPrice,
                    ExitPrice = exitPrice,
                    Contracts = quantity,
                    PnL = pnl,
                    SlipTicks = trade.SlipTicks,
                    ExitReason = reason,
                    Source = "REAL" // wasRealtime-gated: broker-executed only
                });

            notifier?.NotifyResult(ocoCounter, trade.SessionKey, trade.IsLong,
                pnl, trade.EntryPrice, exitPrice, SlotNames[s],
                Account.Get(AccountItem.CashValue, Currency.UsDollar));

            Log(string.Format("[ORB] S{0} {1} closed @ {2:F2} ({3}). PnL={4:+0.00;-0.00}",
                s, SlotNames[s], exitPrice, reason, pnl), LogLevel.Information);
        }

        // Slip cap (price points) for a trade's protective/trailing stop.
        // 0 → the stop stays a guaranteed StopMarket. A positive value makes it
        // a StopLimit bounded to that slippage (no market fallback). Excess-slip
        // trades intentionally exit at market, so they never get a cap.
        private double SlipCapPoints(ActiveTrade trade)
        {
            if (trade != null && trade.SlipForceClose) return 0;
            return Stop_Slip_Cap_Ticks > 0 ? Stop_Slip_Cap_Ticks * PointSize : 0;
        }

        //======================================================================
        // ── TRAIL / BE / SLIP-FORCE-CLOSE MANAGEMENT ──
        //======================================================================
        private void ManageTrade(int s, DateTime currentUTC, double bid, double ask)
        {
            var trade = activeTrades[s];
            if (trade == null || trade.EntryPrice <= 0) return;

            double currentPrice = trade.IsLong ? bid : ask;
            if (currentPrice <= 0) return;

            // ── Slip force-close: excess-slip trades close at market once
            //    profit reaches the threshold — never at a loss, no trailing.
            if (trade.SlipForceClose)
            {
                double profitTicks = (trade.IsLong ? currentPrice - trade.EntryPrice
                                                   : trade.EntryPrice - currentPrice) / PointSize;
                if (profitTicks >= Slip_ForceClose_Profit_Ticks)
                {
                    Log(string.Format("[ORB] S{0}: slip force-close at +{1:F1} pts.", s, profitTicks), LogLevel.Information);
                    CloseSlotPosition(s, "SlipForceClose");
                }
                return;
            }

            if (trade.SlOrder == null) return;

            // Snapshot-driven (MT5 parity): the trade's frozen geometry decides
            // everything — live inputs are never consulted after the fill.
            if (trade.SnapBehavior == 2) return; // Off

            if (News_Freeze_Trail && newsEngine.IsNewsFreezingTrail(currentUTC, News_Block_Before_Mins, News_Block_After_Mins, News_Guard_Mode))
                return;

            double newSL = ORB_Execution.ComputeTrailTarget(trade, bid, ask, TickSize, currentUTC);
            if (newSL <= 0) return;

            // ── Modify debounce (fixes the self-inflicted trailed-exit leak) ──
            // Without this, a "better" target every tick fires a fresh ChangeOrder
            // while the previous one is still resolving, so the resting stop never
            // settles and lands several ticks stale when price finally hits it.
            if (trade.ModifyInFlight)
            {
                // Still waiting on a prior modify to confirm Working — but never
                // wait forever: a lost confirmation must not freeze the trail.
                if ((currentUTC - trade.LastModifyAttempt).TotalMilliseconds < ModifyInFlightTimeoutMs)
                    return;
                trade.ModifyInFlight = false; // stale in-flight modify → allow resend
            }
            if ((currentUTC - trade.LastModifyAttempt).TotalMilliseconds < MinModifyIntervalMs)
                return; // rate-cap: at most one trail modify per MinModifyIntervalMs

            if (trade.SlOrder.OrderState == OrderState.Working || trade.SlOrder.OrderState == OrderState.Accepted)
            {
                double newStop = Instrument.MasterInstrument.RoundToTickSize(newSL);
                // A StopLimit trail must move its limit alongside the stop, or the
                // stale limit blocks the fill. limit=0 keeps a plain StopMarket.
                double newLimit = ORB_Execution.SlLimitPrice(trade.IsLong, newStop,
                    SlipCapPoints(trade), Instrument.MasterInstrument);
                // Mark in-flight BEFORE submitting: OnOrderUpdate clears this the
                // moment THIS stop reports back Working (confirmed live at broker).
                trade.LastModifyAttempt = currentUTC;
                trade.ModifyInFlight = true;
                ChangeOrder(trade.SlOrder, trade.SlOrder.Quantity, newLimit, newStop);
                bool firstTrail = !trade.TrailingActivated;
                trade.VirtualSL = newSL;
                trade.TrailingActivated = true;
                trade.TrailCount++;
                if (firstTrail) trade.TrailStartTime = ORB_Time.NowChart();
                if (trade.SnapBehavior == 1) trade.BreakevenSet = true; // BE-only: once, then hands-off
                SaveLiveSnapshots();
                // (trail line is drawn by the 1s visual pulse)

                if (firstTrail)
                {
                    notifier?.NotifyTrail(ocoCounter, trade.SessionKey, trade.IsLong, newSL);
                    Log(string.Format("[ORB] S{0} {1} activated ({2}): SL → {3:F2}", s,
                        trade.SnapBehavior == 1 ? "breakeven" : "trail",
                        trade.SnapTrailMode == (int)TrailMode.Step ? "Step" : "Continuous",
                        newSL), LogLevel.Information);
                }
            }
        }

        //======================================================================
        // ── EOD FLATTEN + DAILY RESET ──
        //======================================================================
        private void CheckEODFlatten(DateTime currentUTC)
        {
            DateTime nyTime = ORB_Time.UTCToNY(currentUTC);

            bool isEOD = nyTime.Hour == 16 && nyTime.Minute >= 59;
            if (isEOD)
            {
                for (int s = 0; s <= 2; s++)
                {
                    var t = activeTrades[s];
                    if (t != null && t.EntryPrice > 0)
                    {
                        Log(string.Format("[ORB] EOD flatten: closing S{0} at 4:59 PM ET.", s), LogLevel.Information);
                        CloseSlotPosition(s, "EOD");
                    }
                }
            }

            if (nyTime.Hour >= 18 && nyTime.Date > lastDailyResetNYDate)
            {
                lastDailyResetNYDate = nyTime.Date;
                dailyStartBalance = Account.Get(AccountItem.CashValue, Currency.UsDollar);
                dailyLoss = 0;
                isHalted = false;
                for (int s = 0; s < SLOT_COUNT; s++) slotRejections[s] = 0;
                totalRejections = 0;
                ddTracker.OnDayClose(dailyStartBalance);
                Log("[ORB] Daily rollover: trackers and rejection counters reset.", LogLevel.Information);
            }
        }

        //======================================================================
        // ── WEEKLY / MONTHLY REPORTS (ORBReportsOnTimer parity) ──
        //======================================================================
        private void CheckScheduledReports(DateTime currentUTC)
        {
            DateTime ny = ORB_Time.UTCToNY(currentUTC);

            // Weekly: Sunday at/after Report_Hour, once per week
            if (ny.DayOfWeek == DayOfWeek.Sunday && ny.Hour >= Report_Hour && ny.Date > lastWeeklyReportNYDate)
            {
                lastWeeklyReportNYDate = ny.Date;
                var ledger = state.LoadLedger();
                string report = ORB_Reports.BuildSummary(ledger,
                    currentUTC.AddDays(-7), currentUTC,
                    string.Format("ORB Weekly Report — {0} — w/e {1:yyyy-MM-dd}", Instrument.MasterInstrument.Name, ny));
                if (report != null) notifier?.Enqueue(report, 0x9B59B6);
            }

            // Monthly: last day of month at/after Report_Hour, once per month
            bool lastDayOfMonth = ny.Day == DateTime.DaysInMonth(ny.Year, ny.Month);
            if (lastDayOfMonth && ny.Hour >= Report_Hour && ny.Date > lastMonthlyReportNYDate)
            {
                lastMonthlyReportNYDate = ny.Date;
                var ledger = state.LoadLedger();
                DateTime monthStartNY = new DateTime(ny.Year, ny.Month, 1);
                string report = ORB_Reports.BuildSummary(ledger,
                    ORB_Time.NYToUTC(monthStartNY), currentUTC,
                    string.Format("ORB Monthly Report — {0} — {1:MMMM yyyy}", Instrument.MasterInstrument.Name, ny));
                if (report != null) notifier?.Enqueue(report, 0x9B59B6);
            }
        }

        //======================================================================
        // ── HELPERS ──
        //======================================================================
        private static readonly string[] OrbEntryNames = { "LongEntry", "ShortEntry" };
        private static readonly string[] OrbSignalNames = { "LongEntry", "ShortEntry", "LongSL", "LongTP", "ShortSL", "ShortTP" };

        private bool IsWorkingOrder(Order o)
        {
            return o != null &&
                (o.OrderState == OrderState.Working  ||
                 o.OrderState == OrderState.Accepted ||
                 o.OrderState == OrderState.Submitted ||
                 o.OrderState == OrderState.PartFilled);
        }

        private void TryCancelOrder(Order o)
        {
            if (IsWorkingOrder(o))
            {
                try { CancelOrder(o); } catch { }
            }
        }

        private void CancelAllStrategyOrders(bool excludeAdoptedBrackets = false)
        {
            var keep = new HashSet<Order>();
            if (excludeAdoptedBrackets && activeTrades != null)
            {
                for (int s = 0; s < SLOT_COUNT; s++)
                {
                    var t = activeTrades[s];
                    if (t == null || !t.Adopted) continue;
                    if (t.SlOrder != null) keep.Add(t.SlOrder);
                    if (t.TpOrder != null) keep.Add(t.TpOrder);
                }
            }

            foreach (Order o in Orders)
            {
                if (keep.Contains(o)) continue;
                TryCancelOrder(o);
            }

            foreach (Order o in Account.Orders)
            {
                if (o.Instrument != Instrument) continue;
                if (!IsWorkingOrder(o)) continue;
                if (keep.Contains(o)) continue;
                foreach (string sigName in OrbSignalNames)
                {
                    if (o.Name == sigName)
                    {
                        try { CancelOrder(o); } catch { }
                        break;
                    }
                }
            }
        }

        // On Terminated: cancel ONLY entry orders — leave SL/TP working at the
        // broker so an open position stays protected until the next launch adopts it.
        private void CancelEntryOrdersOnly()
        {
            foreach (Order o in Orders)
            {
                if (!IsWorkingOrder(o)) continue;
                foreach (string n in OrbEntryNames)
                {
                    if (o.Name == n) { try { CancelOrder(o); } catch { } break; }
                }
            }
        }

        // Close one slot's live position at market (books via OnExecutionUpdate)
        private void CloseSlotPosition(int s, string reason)
        {
            var t = activeTrades[s];
            if (t == null) return;

            TryCancelOrder(t.EntryOrder);
            TryCancelOrder(t.OtherEntryOrder);
            TryCancelOrder(t.SlOrder);
            TryCancelOrder(t.TpOrder);

            if (t.EntryPrice > 0 && Position.MarketPosition != MarketPosition.Flat)
            {
                int qty = Math.Min(t.Contracts, Position.Quantity);
                if (qty > 0)
                {
                    SubmitOrderUnmanaged(0,
                        t.IsLong ? OrderAction.Sell : OrderAction.BuyToCover,
                        OrderType.Market, qty, 0, 0, "", "CloseS" + s + "_" + reason);
                    return; // OnExecutionUpdate finalizes + clears the slot
                }
            }
            activeTrades[s] = null;
            SaveLiveSnapshots();
        }

        private void FlattenEverything(string reason)
        {
            CancelAllStrategyOrders();
            if (Position.MarketPosition == MarketPosition.Long)
                SubmitOrderUnmanaged(0, OrderAction.Sell, OrderType.Market, Position.Quantity, 0, 0, "", "FlattenAll_" + reason);
            else if (Position.MarketPosition == MarketPosition.Short)
                SubmitOrderUnmanaged(0, OrderAction.BuyToCover, OrderType.Market, Position.Quantity, 0, 0, "", "FlattenAll_" + reason);
            for (int s = 0; s < SLOT_COUNT; s++) activeTrades[s] = null;
            SaveLiveSnapshots();
            Log(string.Format("[ORB] FLATTENED EVERYTHING. Reason: {0}", reason), LogLevel.Warning);
        }

        //======================================================================
        // ── DASHBOARD ──
        //======================================================================
        private void RenderDashboard(DateTime currentUTC, double liveCash, double bid, double ask)
        {
            if (State == State.Historical || !Show_Dashboard) return;
            if (slots == null || newsEngine == null) return;

            int dispSlot = -1;
            bool dispLive = false;
            DateTime dispOpenUTC = DateTime.MinValue;
            {
                DateTime bestOpen = DateTime.MinValue;
                DateTime nextOpen = DateTime.MaxValue;
                int next = -1;
                for (int s = 0; s <= 2; s++)
                {
                    if (!slots[s].IsEnabled) continue;
                    DateTime openUTC = slots[s].RangeEndTimeUTC;
                    DateTime cutoff = slots[s].CutoffTimeUTC;
                    bool liveNow = currentUTC >= openUTC && currentUTC < cutoff;
                    if (liveNow && openUTC > bestOpen) { dispSlot = s; bestOpen = openUTC; dispLive = true; }
                    if (!liveNow && openUTC > currentUTC && openUTC < nextOpen) { next = s; nextOpen = openUTC; }
                }
                if (!dispLive && next >= 0) { dispSlot = next; dispOpenUTC = nextOpen; }
                else if (dispLive) dispOpenUTC = bestOpen;
                if (dispSlot < 0)
                    for (int s = 0; s <= 2; s++) if (slots[s].IsEnabled) { dispSlot = s; break; }
            }

            SlotState primary = dispSlot >= 0 ? slots[dispSlot] : slots[0];

            // ── Hero countdown target: next intraday open; if no intraday
            //    slot is enabled, fall back to the next Daily/Weekly/Monthly
            //    window start.
            int secsToNext = 0;
            string countdownLabel = "Next open";
            {
                DateTime soonest = DateTime.MaxValue;
                int soonestSlot = -1;
                for (int s = 0; s <= 2; s++)
                {
                    if (!slots[s].IsEnabled) continue;
                    DateTime openUTC = slots[s].RangeEndTimeUTC;
                    if (openUTC <= currentUTC)
                        openUTC = ORB_Time.GetSessionOpenUTC(currentUTC.AddDays(1), SlotOpenHour(s), SlotOpenMinute(s));
                    if (openUTC > currentUTC && openUTC < soonest) { soonest = openUTC; soonestSlot = s; }
                }
                if (soonestSlot < 0)
                {
                    for (int s = 3; s < SLOT_COUNT; s++)
                    {
                        if (!slots[s].IsEnabled) continue;
                        DateTime openUTC = slots[s].RangeEndTimeUTC > currentUTC
                            ? slots[s].RangeEndTimeUTC : slots[s].CutoffTimeUTC;
                        if (openUTC > currentUTC && openUTC < soonest) { soonest = openUTC; soonestSlot = s; }
                    }
                }
                if (soonestSlot >= 0)
                {
                    countdownLabel = SlotNames[soonestSlot] + " opens in";
                    secsToNext = (int)(soonest - currentUTC).TotalSeconds;
                }
            }

            // ── Secondary: the live session's cutoff (minor row, not the hero)
            string cutoffText = "--";
            if (dispSlot >= 0 && dispLive && primary.Phase == SessionPhase.TradingWindow)
            {
                int cutSecs = (int)(primary.CutoffTimeUTC - currentUTC).TotalSeconds;
                if (cutSecs > 0)
                    cutoffText = string.Format("{0} · {1:D2}:{2:D2}:{3:D2}",
                        SlotNames[dispSlot], cutSecs / 3600, (cutSecs % 3600) / 60, cutSecs % 60);
            }

            ActiveTrade shownTrade = dispSlot >= 0 ? activeTrades[dispSlot] : null;
            int shownSlot = dispSlot;
            if (shownTrade == null || shownTrade.EntryPrice <= 0)
            {
                for (int s = 0; s < SLOT_COUNT; s++)
                    if (activeTrades[s] != null && activeTrades[s].EntryPrice > 0) { shownTrade = activeTrades[s]; shownSlot = s; break; }
            }
            bool inPosition = shownTrade != null && shownTrade.EntryPrice > 0;
            bool ordersPending = false;
            for (int s = 0; s < SLOT_COUNT; s++)
                if (activeTrades[s] != null && activeTrades[s].EntryPrice <= 0) { ordersPending = true; break; }

            double currentPrice = inPosition ? (shownTrade.IsLong ? bid : ask) : 0;
            double liveRR = 0;
            if (inPosition && currentPrice > 0 && Fixed_SL_Ticks > 0)
            {
                double profitTicks = shownTrade.IsLong
                    ? (currentPrice - shownTrade.EntryPrice) / PointSize
                    : (shownTrade.EntryPrice - currentPrice) / PointSize;
                liveRR = profitTicks / Fixed_SL_Ticks;
            }

            string status;
            if (venueBlocked) status = "VENUE BLOCKED (data feed)";
            else if (isHalted) status = "HALTED";
            else if (inPosition) status = "In Trade (" + SlotNames[shownSlot] + ")" + (shownTrade.Adopted ? " [adopted]" : "");
            else if (ordersPending) status = "Orders Pending";
            else if (Use_Instant_Market_Execution && dispSlot >= 0 && primary.Phase == SessionPhase.TradingWindow)
                status = "Watching (instant)";
            else if (dispSlot >= 0) status = primary.Phase.ToString();
            else status = "No sessions enabled";


            // Range display source: the display slot when its range is valid,
            // else the MOST RECENTLY formed/locked range across all slots —
            // "forming…" only shows when genuinely nothing has formed yet.
            SlotState rangeSrc = null;
            {
                bool primaryValid = primary != null && primary.IsRangeLocked &&
                    primary.RangeHigh != double.MinValue && primary.RangeLow != double.MaxValue &&
                    primary.RangeHigh > primary.RangeLow;
                if (primaryValid) rangeSrc = primary;
                else
                {
                    DateTime newest = DateTime.MinValue;
                    for (int s = 0; s < SLOT_COUNT; s++)
                    {
                        SlotState sl = slots[s];
                        if (!sl.IsEnabled || !sl.IsRangeLocked) continue;
                        if (sl.RangeHigh == double.MinValue || sl.RangeLow == double.MaxValue) continue;
                        if (sl.RangeHigh <= sl.RangeLow) continue;
                        if (sl.RangeEndTimeUTC > newest) { newest = sl.RangeEndTimeUTC; rangeSrc = sl; }
                    }
                }
            }

            // Slot rows: intraday and HTF listed separately (HTF row hidden
            // when no HTF slot is enabled — the panel resizes dynamically)
            var intradaySb = new System.Text.StringBuilder();
            for (int s = 0; s <= 2; s++)
            {
                if (!slots[s].IsEnabled) continue;
                if (intradaySb.Length > 0) intradaySb.Append("  ·  ");
                intradaySb.Append(SlotNames[s]);
            }
            var htfSb = new System.Text.StringBuilder();
            for (int s = 3; s < SLOT_COUNT; s++)
            {
                if (!slots[s].IsEnabled) continue;
                if (htfSb.Length > 0) htfSb.Append("  ·  ");
                htfSb.Append(SlotNames[s]);
            }

            var dashState = new ORBDashState
            {
                CurrentBalance = liveCash,
                DrawdownFloor = ddTracker.CurrentFloor,
                FloorLocked = ddTracker.IsFloorLocked,
                DistanceToFloor = liveCash - ddTracker.CurrentFloor,
                ConsistencyPctOfTotal = consistencyTracker.ConsistencyPctOfTotal,
                EvalProfitTarget = Eval_Profit_Target,
                EvalProfitProgress = consistencyTracker.TotalProfit,
                TradingDaysCompleted = tradingDaysCompleted,
                FastTradePct = fastTradeTracker.FastTradePct,
                ConsistencyWarning = consistencyTracker.IsConsistencyWarning,

                ActiveSession = dispSlot >= 0 ? SlotNames[dispSlot] : "-",
                SessionPhase = status,
                NYClock = ORB_Time.UTCToNY(currentUTC).ToString("HH:mm:ss"),
                SessionCountdownLabel = countdownLabel,
                SecsToNextPhase = Math.Max(0, secsToNext),
                CutoffText = cutoffText,
                RangeHigh = rangeSrc != null ? rangeSrc.RangeHigh : 0,
                RangeLow = rangeSrc != null ? rangeSrc.RangeLow : 0,
                SlotsIntraday = intradaySb.ToString(),
                SlotsHtf = htfSb.ToString(),

                InTrade = inPosition,
                TradeDir = inPosition ? (shownTrade.IsLong ? "LONG" : "SHORT") : "",
                EntryPrice = inPosition ? shownTrade.EntryPrice : 0,
                StopLoss = inPosition ? shownTrade.VirtualSL : 0,
                TakeProfit = inPosition ? shownTrade.TpPrice : 0,
                ContractCount = shownTrade?.Contracts ?? 0,
                ContractMode = Contract_Mode.ToString(),
                LiveRR = liveRR,
                BEActive = shownTrade?.BreakevenSet ?? false,
                BEDetail = shownTrade?.BreakevenSet == true ? "@ entry" : "",

                InstrumentName = Instrument.MasterInstrument.Name,
                TickSize = TickSize,
                PointSize = PointSize,
                PointValue = Instrument.MasterInstrument.PointValue,

                NewsBlackoutActive = News_Guard_Mode != NewsGuardMode.Off && newsEngine.IsNewsBlocked(currentUTC, News_Block_Before_Mins, News_Block_After_Mins, News_Guard_Mode),
                NextNewsEvent = newsEngine.GetNextEventDescription(currentUTC, News_Guard_Mode),
                NewsSourceMode = "Live (FF)"
            };

            ORB_Dashboard.Publish(this, dashState);
            // Request a chart repaint so the D2D panel refreshes at 1 Hz even
            // when no ticks arrive (must marshal to the chart's UI thread).
            var cc = ChartControl;
            if (cc != null)
            {
                try { cc.Dispatcher.InvokeAsync(() => cc.InvalidateVisual()); }
                catch { }
            }
        }

        //======================================================================
        // ── DASHBOARD MOUSE (drag / collapse) ──
        //======================================================================
        // WPF units → device pixels (the D2D render target works in pixels)
        private System.Windows.Point ToDevice(System.Windows.Point pt)
        {
            try
            {
                var src = System.Windows.PresentationSource.FromVisual(ChartControl);
                if (src?.CompositionTarget != null)
                    return src.CompositionTarget.TransformToDevice.Transform(pt);
            }
            catch { }
            return pt;
        }

        private void OnChartMouseDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            var cc = ChartControl;
            if (cc == null) return;
            var pt = ToDevice(e.GetPosition(cc));
            if (ORB_Dashboard.OnMouseDown(this, (float)pt.X, (float)pt.Y))
            {
                e.Handled = true;
                cc.InvalidateVisual();
            }
        }

        private void OnChartMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
        {
            var cc = ChartControl;
            if (cc == null) return;
            var pt = ToDevice(e.GetPosition(cc));
            if (ORB_Dashboard.OnMouseMove(this, (float)pt.X, (float)pt.Y))
            {
                e.Handled = true;
                cc.InvalidateVisual();
            }
        }

        private void OnChartMouseUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            if (ORB_Dashboard.OnMouseUp(this))
                ChartControl?.InvalidateVisual();
        }

        //======================================================================
        // ── D2D RENDER (Liquid-Glass dashboard) ──
        //======================================================================
        protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
        {
            base.OnRender(chartControl, chartScale);
            if (!Show_Dashboard || State != State.Realtime) return;
            // Draw objects (range lines/boxes) live on their own layer ABOVE a
            // strategy's default render layer — the glass looked transparent to
            // them regardless of opacity. Force this strategy's render pass to
            // the very top of the z-stack so the panel truly covers them.
            try { if (ZOrder != int.MaxValue) ZOrder = int.MaxValue; } catch { }
            try { ORB_Dashboard.Render(this, chartControl, RenderTarget); }
            catch { /* never let a render fault kill the strategy */ }
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
