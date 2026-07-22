#region Using declarations
using System;
using System.Collections.Generic;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies;
#endregion

// ORB_NT_Strategy.cs — orchestrator, now covering all 6 slots
// (0=NY, 1=London, 2=Asian intraday; 3=Daily, 4=Weekly, 5=Monthly HTF)
// plus live trailing-stop management via ORB_Execution.ApplyTrailingStop.
//
// Slot mapping and cutoff/anchor rules mirror ORB_Scalper.mq5's
// SetSlotContext()/SessionOpenServer()/SessionCutoffServer():
//   - Slots 0-2: intraday, own hour/minute, cutoff = 18:00 NY same/next day.
//   - Slot 3 (Daily):   anchor = GetCurrentNYTrueDayOpen,   cutoff = +N days.
//   - Slot 4 (Weekly):  anchor = GetCurrentNYTrueWeekOpen,  cutoff = +N weeks.
//   - Slot 5 (Monthly): anchor = GetCurrentNYTrueMonthOpen, cutoff = +N months.

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public class ORB_NT_Strategy : Strategy
    {
        #region Inputs

        [NinjaScriptProperty] public double RiskPercent { get; set; } = 1.0;

        [NinjaScriptProperty] public bool EnableNYSession { get; set; } = true;
        [NinjaScriptProperty] public int OpeningHourNY { get; set; } = 9;
        [NinjaScriptProperty] public int OpeningMinuteNY { get; set; } = 30;

        [NinjaScriptProperty] public bool EnableLondonSession { get; set; } = false;
        [NinjaScriptProperty] public int LondonHourNY { get; set; } = 3;
        [NinjaScriptProperty] public int LondonMinuteNY { get; set; } = 0;

        [NinjaScriptProperty] public bool EnableAsianSession { get; set; } = false;
        [NinjaScriptProperty] public int AsianHourNY { get; set; } = 18;
        [NinjaScriptProperty] public int AsianMinuteNY { get; set; } = 0;

        [NinjaScriptProperty] public bool EnableDailyRange { get; set; } = false;
        [NinjaScriptProperty] public bool EnableWeeklyRange { get; set; } = false;
        [NinjaScriptProperty] public bool EnableMonthlyRange { get; set; } = false;
        [NinjaScriptProperty] public int HtfCutoffPeriods { get; set; } = 1;

        [NinjaScriptProperty] public int RangeMinutes { get; set; } = 15;

        [NinjaScriptProperty] public bool ReverseOrders { get; set; } = false;
        [NinjaScriptProperty] public bool UseLimitEntry { get; set; } = false;

        [NinjaScriptProperty] public double FixedSLPoints { get; set; } = 200.0;
        [NinjaScriptProperty] public double FixedTPPoints { get; set; } = 200.0;

        [NinjaScriptProperty] public double TrailThresholdPoints { get; set; } = 120.0;
        [NinjaScriptProperty] public double TrailGapPoints { get; set; } = 100.0;
        [NinjaScriptProperty] public bool TrailBreakevenOnly { get; set; } = false;

        [NinjaScriptProperty] public bool ShowVisuals { get; set; } = true;
        [NinjaScriptProperty] public bool ShowDashboard { get; set; } = true;

        [NinjaScriptProperty] public ContractSizeMode ContractMode { get; set; } = ContractSizeMode.Micro;

        #endregion

        private const int SLOT_COUNT = 6;
        private SlotState[] slots;
        private ActiveTrade[] activeTrades;
        private Order[] pendingLong, pendingShort;
        private string[] ocoGroups;
        private string configSig = "";

        private double pointValue;
        private double tickSize;

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Description = "ORB Scalper — NinjaTrader port (6-slot orchestrator)";
                Name = "ORB_NT_Strategy";
                Calculate = Calculate.OnEachTick;
                EntriesPerDirection = 1;
                EntryHandling = EntryHandling.AllEntries;
                IsExitOnSessionCloseStrategy = false;
                IsUnmanaged = true;
                BarsRequiredToTrade = 1;
            }
            else if (State == State.Configure)
            {
                AddDataSeries(BarsPeriodType.Minute, 1); // BIP1: M1 series drives range building
            }
            else if (State == State.DataLoaded)
            {
                tickSize = Instrument.MasterInstrument.TickSize;
                pointValue = Instrument.MasterInstrument.PointValue;

                slots = new SlotState[SLOT_COUNT];
                activeTrades = new ActiveTrade[SLOT_COUNT];
                pendingLong = new Order[SLOT_COUNT];
                pendingShort = new Order[SLOT_COUNT];
                ocoGroups = new string[SLOT_COUNT];

                slots[0] = new SlotState(0) { IsEnabled = EnableNYSession, Type = SessionType.Intraday };
                slots[1] = new SlotState(1) { IsEnabled = EnableLondonSession, Type = SessionType.Intraday };
                slots[2] = new SlotState(2) { IsEnabled = EnableAsianSession, Type = SessionType.Intraday };
                slots[3] = new SlotState(3) { IsEnabled = EnableDailyRange, Type = SessionType.Daily };
                slots[4] = new SlotState(4) { IsEnabled = EnableWeeklyRange, Type = SessionType.Weekly };
                // ORB_Sessions.SessionType has no Monthly member; slot index 5
                // is distinguished by SlotIndex, not by Type, everywhere below.
                slots[5] = new SlotState(5) { IsEnabled = EnableMonthlyRange, Type = SessionType.Weekly };

                configSig = BuildConfigSignature();
            }
            else if (State == State.Terminated)
            {
                CancelAllWorkingOrders("EA terminated");
            }
        }

        protected override void OnBarUpdate()
        {
            if (BarsInProgress != 1) return;
            if (CurrentBars[1] < 2) return;

            DateTime nowUTC = Time[0].ToUniversalTime();

            string newSig = BuildConfigSignature();
            if (newSig != configSig)
            {
                configSig = newSig;
                CancelAllWorkingOrders("Config changed — fresh setup");
                for (int s = 0; s < SLOT_COUNT; s++)
                {
                    slots[s].Reset();
                    if (ShowVisuals) ORB_Visuals.ClearAllVisuals(this, "S" + s);
                }
            }

            for (int s = 0; s < SLOT_COUNT; s++)
            {
                if (!slots[s].IsEnabled) continue;
                RunSlot(s, nowUTC);
            }

            for (int s = 0; s < SLOT_COUNT; s++)
                ManageTrailingForSlot(s);

            if (ShowDashboard) RenderDashboard(nowUTC);
        }

        // ---------------------------------------------------------------
        private void RunSlot(int s, DateTime nowUTC)
        {
            SlotState slot = slots[s];
            bool isIntraday = (s == 0 || s == 1 || s == 2);

            DateTime rangeStartUTC, rangeEndUTC, cutoffUTC;
            string sessionKey;

            if (isIntraday)
            {
                int hh = s == 0 ? OpeningHourNY : s == 1 ? LondonHourNY : AsianHourNY;
                int mm = s == 0 ? OpeningMinuteNY : s == 1 ? LondonMinuteNY : AsianMinuteNY;

                rangeEndUTC = ORB_Time.GetSessionOpenUTC(nowUTC, hh, mm);
                rangeStartUTC = rangeEndUTC.AddMinutes(-RangeMinutes);
                cutoffUTC = ComputeIntradayCutoff(rangeEndUTC);
                sessionKey = string.Format("S{0}_{1:yyyyMMdd}_{2:D2}{3:D2}", s, ORB_Time.UTCToNY(rangeEndUTC), hh, mm);
            }
            else
            {
                DateTime anchor = s == 3 ? ORB_Time.GetCurrentNYTrueDayOpen(nowUTC)
                                 : s == 4 ? ORB_Time.GetCurrentNYTrueWeekOpen(nowUTC)
                                          : ORB_Time.GetCurrentNYTrueMonthOpen(nowUTC);
                rangeEndUTC = anchor;
                rangeStartUTC = s == 3 ? anchor.AddDays(-1) : s == 4 ? anchor.AddDays(-7) : anchor.AddMonths(-1);
                cutoffUTC = s == 3 ? anchor.AddDays(HtfCutoffPeriods)
                          : s == 4 ? anchor.AddDays(7 * HtfCutoffPeriods)
                                   : anchor.AddMonths(HtfCutoffPeriods);
                sessionKey = string.Format("S{0}_HTF_{1:yyyyMMddHHmm}", s, anchor);
            }

            if (slot.SessionKey != sessionKey)
            {
                slot.SessionKey = sessionKey;
                slot.RangeStartTimeUTC = rangeStartUTC;
                slot.RangeEndTimeUTC = rangeEndUTC;
                slot.CutoffTimeUTC = cutoffUTC;
                slot.Reset();
                if (ShowVisuals) ORB_Visuals.ClearAllVisuals(this, "S" + s);

                if (!isIntraday)
                {
                    if (TryLoadHtfRange(s, out double hi, out double lo))
                    {
                        slot.UpdateRange(hi, lo);
                        slot.IsRangeLocked = true;
                        slot.Phase = SessionPhase.TradingWindow;
                        if (ShowVisuals)
                            ORB_Visuals.DrawRangeBox(this, "S" + s + "_RangeBox",
                                slot.RangeStartTimeUTC.ToLocalTime(), slot.RangeEndTimeUTC.ToLocalTime(),
                                slot.RangeHigh, slot.RangeLow, ORB_Visuals.ClrRangeBoxDaily);
                        Print(string.Format("[ORB] {0} HTF range locked: Hi={1:F5} Lo={2:F5}", sessionKey, hi, lo));
                    }
                    else
                    {
                        Print(string.Format("[ORB] {0}: HTF prior bar unavailable — waiting for more history.", sessionKey));
                    }
                }
            }

            if (isIntraday) SessionLogic.UpdateSlotPhase(slot, nowUTC);

            if (nowUTC >= slot.CutoffTimeUTC)
            {
                if (slot.Phase != SessionPhase.Closed)
                {
                    CancelSlotWorkingOrders(s, "Cutoff reached");
                    slot.Phase = SessionPhase.Closed;
                }
                return;
            }

            if (isIntraday && slot.Phase == SessionPhase.RangeForming)
            {
                slot.UpdateRange(Highs[1][0], Lows[1][0]);
                if (ShowVisuals && slot.RangeHigh > double.MinValue && slot.RangeLow < double.MaxValue)
                {
                    ORB_Visuals.DrawRangeBox(this, "S" + s + "_RangeBox",
                        slot.RangeStartTimeUTC.ToLocalTime(), slot.RangeEndTimeUTC.ToLocalTime(),
                        slot.RangeHigh, slot.RangeLow, ORB_Visuals.ClrRangeBoxNY, 20);
                }
                return;
            }

            if (isIntraday && slot.Phase == SessionPhase.TradingWindow && !slot.IsRangeLocked)
            {
                if (slot.RangeHigh == double.MinValue || slot.RangeLow == double.MaxValue)
                {
                    Print(string.Format("[ORB] {0}: range never formed — skipping.", slot.SessionKey));
                    slot.IsRangeLocked = true;
                    return;
                }
                slot.IsRangeLocked = true;
                if (ShowVisuals)
                    ORB_Visuals.DrawRangeBox(this, "S" + s + "_RangeBox",
                        slot.RangeStartTimeUTC.ToLocalTime(), slot.RangeEndTimeUTC.ToLocalTime(),
                        slot.RangeHigh, slot.RangeLow, ORB_Visuals.ClrRangeBoxNY);
                Print(string.Format("[ORB] {0} Range locked: Hi={1:F5} Lo={2:F5}", slot.SessionKey, slot.RangeHigh, slot.RangeLow));
            }

            bool tradable = isIntraday ? slot.Phase == SessionPhase.TradingWindow : slot.IsRangeLocked;
            if (!tradable) return;
            if (activeTrades[s] != null) return;

            PlaceEntriesIfNeeded(s);
        }

        // Approximates the HTF prior-period bar from the M1 series over the
        // exact [rangeStart, rangeEnd) window (equivalent to MT5's
        // LoadRangeWindow fallback), since a 3rd BarsArray for D1/W1/MN1
        // would need declaring in State.Configure ahead of time.
        private bool TryLoadHtfRange(int s, out double hi, out double lo)
        {
            hi = double.MinValue; lo = double.MaxValue;
            SlotState slot = slots[s];
            DateTime startLocal = slot.RangeStartTimeUTC.ToLocalTime();
            DateTime endLocal = slot.RangeEndTimeUTC.ToLocalTime();

            for (int i = 0; i < CurrentBars[1] && i < 50000; i++)
            {
                DateTime t = Times[1][i];
                if (t < startLocal) break;
                if (t >= endLocal) continue;
                if (Highs[1][i] > hi) hi = Highs[1][i];
                if (Lows[1][i] < lo) lo = Lows[1][i];
            }
            return hi > double.MinValue && lo < double.MaxValue;
        }

        private DateTime ComputeIntradayCutoff(DateTime sessionOpenUTC)
        {
            DateTime openNY = ORB_Time.UTCToNY(sessionOpenUTC);
            DateTime cutoffNY = new DateTime(openNY.Year, openNY.Month, openNY.Day, 18, 0, 0);
            if (cutoffNY <= openNY) cutoffNY = cutoffNY.AddDays(1);
            return ORB_Time.NYToUTC(cutoffNY);
        }

        // ---------------------------------------------------------------
        private void PlaceEntriesIfNeeded(int s)
        {
            SlotState slot = slots[s];
            if (slot.LongOrderPlaced && slot.ShortOrderPlaced) return;

            double slPointsPrice = FixedSLPoints * tickSize;
            int contracts = ORB_Risk.CalcContracts(GetAccountBalance(), RiskPercent, slPointsPrice, pointValue, ContractMode);

            if (contracts <= 0)
            {
                Print(string.Format("[ORB] S{0}: CalcContracts=0 — risk/margin too tight. No order placed.", s));
                slot.LongOrderPlaced = true;
                slot.ShortOrderPlaced = true;
                return;
            }

            ocoGroups[s] = "ORB_S" + s + "_" + slot.SessionKey;

            var (longOrder, shortOrder) = ORB_Execution.PlacePendingEntryOCO(
                this, slot.RangeHigh, slot.RangeLow, contracts, ocoGroups[s], UseLimitEntry);

            pendingLong[s] = longOrder;
            pendingShort[s] = shortOrder;
            slot.LongOrderPlaced = true;
            slot.ShortOrderPlaced = true;

            Print(string.Format("[ORB] S{0} {1} orders placed. Hi={2:F5} Lo={3:F5} contracts={4}",
                s, slot.SessionKey, slot.RangeHigh, slot.RangeLow, contracts));
        }

        // ---------------------------------------------------------------
        protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice,
            int quantity, int filled, double averageFillPrice,
            OrderState orderState, DateTime time, ErrorCode error, string comment)
        {
            if (orderState != OrderState.Filled) return;

            int s = FindSlotForEntryOrder(order);
            if (s < 0) return;
            if (activeTrades[s] != null) return;

            bool isLong = (order == pendingLong[s]);
            Order other = isLong ? pendingShort[s] : pendingLong[s];
            if (other != null && other.OrderState != OrderState.Filled && other.OrderState != OrderState.Cancelled)
                CancelOrder(other);

            var (slOrder, tpOrder) = ORB_Execution.PlaceBracketOrders(
                this, isLong, averageFillPrice, quantity,
                FixedSLPoints * tickSize, FixedTPPoints * tickSize, ocoGroups[s] + "_BRK");

            activeTrades[s] = new ActiveTrade
            {
                EntryOrder = order,
                OtherEntryOrder = other,
                SlOrder = slOrder,
                TpOrder = tpOrder,
                IsLong = isLong,
                EntryPrice = averageFillPrice,
                EntryTime = time,
                VirtualSL = isLong ? averageFillPrice - FixedSLPoints * tickSize
                                   : averageFillPrice + FixedSLPoints * tickSize,
                Contracts = quantity,
                OcoGroup = ocoGroups[s],
                SlotIndex = s
            };

            Print(string.Format("[ORB] S{0} filled {1} @ {2:F5} x{3}. Bracket placed.",
                s, isLong ? "LONG" : "SHORT", averageFillPrice, quantity));
        }

        private int FindSlotForEntryOrder(Order order)
        {
            for (int s = 0; s < SLOT_COUNT; s++)
                if (order == pendingLong[s] || order == pendingShort[s]) return s;
            return -1;
        }

        // ---------------------------------------------------------------
        // Trailing / breakeven management — mirrors MT5's
        // ManageTrailingStops(): compute the target from each trade's own
        // geometry, only ChangeOrder when it genuinely improves the stop.
        // ---------------------------------------------------------------
        private void ManageTrailingForSlot(int s)
        {
            ActiveTrade trade = activeTrades[s];
            if (trade == null) return;
            if (trade.SlOrder == null) return;
            if (trade.SlOrder.OrderState == OrderState.Filled || trade.SlOrder.OrderState == OrderState.Cancelled)
            {
                activeTrades[s] = null;
                return;
            }

            double bid = GetCurrentBid();
            double ask = GetCurrentAsk();

            // Populate the snapshot fields that ComputeTrailTarget needs, using
            // the flat inputs from the strategy's input properties.
            trade.SnapBehavior    = TrailBreakevenOnly ? 1 : 2;  // 1=BE-only, 2=full trail; 0=off
            trade.SnapThreshPrice = TrailThresholdPoints * tickSize;
            trade.SnapGapPrice    = TrailGapPoints       * tickSize;
            trade.SnapSpreadComp  = false;
            trade.SnapTrailMode   = (int)TrailMode.Continuous;

            // Re-arm to 2 (full) in case TrailBreakevenOnly was flipped off mid-trade.
            if (!TrailBreakevenOnly && trade.SnapBehavior == 1) trade.SnapBehavior = 2;

            double targetSL = ORB_Execution.ComputeTrailTarget(trade, bid, ask, tickSize, DateTime.UtcNow);
            if (targetSL == 0 || targetSL == trade.VirtualSL) return;

            // Apply: ChangeOrder moves the working stop.  Forward-only guard is
            // already inside ComputeTrailTarget; double-check here for safety.
            bool improves = trade.IsLong ? targetSL > trade.VirtualSL : targetSL < trade.VirtualSL;
            if (!improves) return;

            bool sent = false;
            try
            {
                ChangeOrder(trade.SlOrder, trade.Contracts, 0, targetSL);
                sent = true;
            }
            catch { }
            if (sent)
            {
                bool firstTrail = !trade.TrailingActivated;
                trade.VirtualSL = targetSL;
                trade.TrailingActivated = true;
                if (TrailBreakevenOnly) trade.BreakevenSet = true;

                Print(string.Format("[ORB] S{0} {1}: {2} moved to {3:F5}{4}",
                    s, trade.IsLong ? "LONG" : "SHORT",
                    TrailBreakevenOnly ? "Breakeven" : "Trail",
                    targetSL, firstTrail ? " (first move)" : ""));
            }
        }

        protected override void OnExecutionUpdate(Execution execution, string executionId, double price,
            int quantity, MarketPosition marketPosition, string orderId, DateTime time)
        {
            for (int s = 0; s < SLOT_COUNT; s++)
            {
                var t = activeTrades[s];
                if (t == null) continue;

                bool slDone = t.SlOrder == null || t.SlOrder.OrderState == OrderState.Filled || t.SlOrder.OrderState == OrderState.Cancelled;
                bool tpDone = t.TpOrder == null || t.TpOrder.OrderState == OrderState.Filled || t.TpOrder.OrderState == OrderState.Cancelled;
                bool anyFilled = (t.SlOrder != null && t.SlOrder.OrderState == OrderState.Filled)
                               || (t.TpOrder != null && t.TpOrder.OrderState == OrderState.Filled);

                if (slDone && tpDone && anyFilled)
                {
                    Print(string.Format("[ORB] S{0} position closed @ {1:F5}.", s, price));
                    activeTrades[s] = null;
                    pendingLong[s] = null;
                    pendingShort[s] = null;
                }
            }
        }

        private void CancelSlotWorkingOrders(int s, string reason)
        {
            if (pendingLong[s] != null && (pendingLong[s].OrderState == OrderState.Working || pendingLong[s].OrderState == OrderState.Accepted))
                CancelOrder(pendingLong[s]);
            if (pendingShort[s] != null && (pendingShort[s].OrderState == OrderState.Working || pendingShort[s].OrderState == OrderState.Accepted))
                CancelOrder(pendingShort[s]);
            Print(string.Format("[ORB] S{0}: {1}", s, reason));
        }

        private void CancelAllWorkingOrders(string reason)
        {
            foreach (Order o in Account.Orders)
            {
                if (o.Instrument != Instrument) continue;
                if (o.OrderState == OrderState.Working || o.OrderState == OrderState.Accepted)
                    CancelOrder(o);
            }
            Print("[ORB] " + reason + " — cancelled all working orders.");
        }

        private double GetAccountBalance() => Account.Get(AccountItem.CashValue, Currency.UsDollar);

        // Bid/Ask helpers for trail computation — fall back to Close[0] when
        // the Instrument hasn't updated the market data yet (e.g. backtester).
        private double GetCurrentBid()
        {
            try { return GetCurrentBid(Instrument); }
            catch { return Close[0]; }
        }
        private double GetCurrentAsk()
        {
            try { return GetCurrentAsk(Instrument); }
            catch { return Close[0]; }
        }

        private string BuildConfigSignature()
        {
            return string.Format("R{0}:RM{1}:REV{2}:LIM{3}:SL{4}:TP{5}:TH{6}:GP{7}:BE{8}:" +
                                  "NY{9}:{10}:{11}:LO{12}:{13}:{14}:AS{15}:{16}:{17}:D{18}:W{19}:M{20}:HC{21}",
                RiskPercent, RangeMinutes, ReverseOrders, UseLimitEntry, FixedSLPoints, FixedTPPoints,
                TrailThresholdPoints, TrailGapPoints, TrailBreakevenOnly,
                EnableNYSession, OpeningHourNY, OpeningMinuteNY,
                EnableLondonSession, LondonHourNY, LondonMinuteNY,
                EnableAsianSession, AsianHourNY, AsianMinuteNY,
                EnableDailyRange, EnableWeeklyRange, EnableMonthlyRange, HtfCutoffPeriods);
        }

        private void RenderDashboard(DateTime nowUTC)
        {
            SlotState primary = slots[0];
            ActiveTrade t = activeTrades[0];

            // Compose a human-readable intraday-slots label for the dashboard.
            var intradayParts = new System.Collections.Generic.List<string>();
            if (EnableNYSession)     intradayParts.Add("NY");
            if (EnableLondonSession) intradayParts.Add("London");
            if (EnableAsianSession)  intradayParts.Add("Asian");
            string intradayLabel = intradayParts.Count > 0 ? string.Join(" · ", intradayParts) : "--";

            var htfParts = new System.Collections.Generic.List<string>();
            if (EnableDailyRange)   htfParts.Add("Daily");
            if (EnableWeeklyRange)  htfParts.Add("Weekly");
            if (EnableMonthlyRange) htfParts.Add("Monthly");
            string htfLabel = htfParts.Count > 0 ? string.Join(" · ", htfParts) : "";

            var st = new ORBDashState
            {
                CurrentBalance    = GetAccountBalance(),
                ActiveSession     = intradayLabel,
                SessionPhase      = primary.Phase.ToString(),
                NYClock           = ORB_Time.UTCToNY(nowUTC).ToString("HH:mm:ss"),
                SessionCountdownLabel = "Cutoff",
                SecsToNextPhase   = primary.CutoffTimeUTC > nowUTC
                                        ? (int)(primary.CutoffTimeUTC - nowUTC).TotalSeconds : 0,
                RangeHigh         = primary.RangeHigh == double.MinValue ? 0 : primary.RangeHigh,
                RangeLow          = primary.RangeLow  == double.MaxValue ? 0 : primary.RangeLow,
                SlotsIntraday     = intradayLabel,
                SlotsHtf          = htfLabel,
                InTrade           = t != null,
                TradeDir          = t != null ? (t.IsLong ? "LONG" : "SHORT") : "",
                EntryPrice        = t?.EntryPrice  ?? 0,
                StopLoss          = t?.VirtualSL   ?? 0,
                TakeProfit        = t?.TpOrder != null ? (t.TpOrder.LimitPrice > 0 ? t.TpOrder.LimitPrice : 0) : 0,
                ContractCount     = t?.Contracts   ?? 0,
                ContractMode      = ContractMode.ToString(),
                BEActive          = t?.TrailingActivated ?? false,
                InstrumentName    = Instrument.FullName,
                TickSize          = tickSize,
                PointValue        = pointValue
            };

            // Publish then trigger OnRender via chart invalidation — the actual
            // Direct2D draw happens in OnRender (see override below).
            ORB_Dashboard.Publish(this, st);
        }

        public override void OnRenderTargetChanged() { }

        protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
        {
            base.OnRender(chartControl, chartScale);
            if (ShowDashboard)
                ORB_Dashboard.Render(this, chartControl, RenderTarget);
        }
    }
}
