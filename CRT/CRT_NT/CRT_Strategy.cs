#region Using declarations
using System;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript;
using SharpDX.Direct2D1;
#endregion

//======================================================================
// CRT_NT_Strategy — main orchestrator (partial class; parameters live in
// CRT_Inputs.cs). Realises 01-STRATEGY-SPEC.md on NinjaTrader 8.
//
// Authoritative rules enforced here (see spec §1.1):
//   • C1 defines the range (High/Low/EQ) and nothing else.
//   • C2 is STRICTLY the manipulation candle — it can NEVER trigger or
//     execute. The liquidity sweep can ONLY occur in C2.
//   • CISD / IFVG may occur in C2 or C3. A C2 confirmation is PROVISIONAL
//     and only actioned at the C2-close / C3-open boundary (§1.2).
//   • Execution can ONLY occur in C3: a market order at the boundary
//     (>=1:1) or a 1:1 limit at (C1_EQ + SL)/2.
//   • The 1:1 limit PERSISTS beyond C3 close. It dies only on fill or when
//     price touches 50% (C1_EQ) — the latter also invalidates the setup.
//   • SL is FIXED at the C2 (manipulation-candle) extreme ± buffer and is
//     independent of the 50% (C1_EQ) calc.
//======================================================================
namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public partial class CRT_NT_Strategy : Strategy
    {
        // Added-series indices (see State.Configure).
        private const int HTF = 1;   // C1/C2/C3 timeframe
        private const int LTF = 2;   // sweep / CISD / IFVG detection

        // Active slot resolution (v1 runs one primary C1 timeframe).
        private SlotType activeSlot;
        private IntradayTF activeTf;

        // The single live setup + confirm engine.
        private CrtSetup setup;
        private CRT_Confirm confirm;

        // Rolling HTF window bookkeeping. htfClosesSinceC1:
        //   after C1 locks → 0 (C2 forming); at C2 close → 1; at C3 close → 2.
        private int htfClosesSinceC1;
        private DateTime sweepStartUTC = DateTime.MinValue;

        // Single global active-trade lock (position OR working limit).
        private ActiveTrade activeTrade;

        // Support modules.
        private CRT_HourFilter hourFilter;
        private CRT_State stateStore;
        private CRT_News news;
        private CRT_Notify notify;

        // Risk / daily-guard counters.
        private int tradesToday;
        private int consecLosses;
        private double dayStartBalance;
        private DateTime currentNyDay = DateTime.MinValue;

        //==================================================================
        // Lifecycle
        //==================================================================
        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                SetCrtDefaults();
            }
            else if (State == State.Configure)
            {
                ResolveActiveSlot();

                // HTF series (C1/C2/C3).
                var htfBp = CRT_Slots.HtfBarsPeriod(activeSlot, activeTf);
                AddDataSeries(htfBp.BarsPeriodType, htfBp.Value);

                // LTF series (sweep / CISD / IFVG).
                int ltfMin = CRT_Slots.ResolveLtfMinutes(activeSlot, activeTf, LtfMinutesOverride);
                AddDataSeries(BarsPeriodType.Minute, ltfMin);
            }
            else if (State == State.DataLoaded)
            {
                setup = new CrtSetup
                {
                    Type = activeSlot,
                    IntradayTf = activeTf,
                    Phase = SetupPhase.WaitC1
                };
                confirm = new CRT_Confirm();

                hourFilter = new CRT_HourFilter(AllowedHoursCsv);
                stateStore = new CRT_State(
                    NinjaTrader.Core.Globals.UserDataDir + "CRT", Instrument.FullName);

                if (EnableNews)
                {
                    news = new CRT_News(null, NinjaTrader.Core.Globals.UserDataDir + "CRT\\ff_cache.json",
                        State == State.Historical);
                    news.Initialize();
                }
            }
            else if (State == State.Terminated)
            {
                CRT_Dashboard.Clear(this);
            }
        }

        private void ResolveActiveSlot()
        {
            // Priority Intraday → Daily → Weekly → Monthly (§CRT_Slots note).
            if (EnableIntraday) { activeSlot = SlotType.Intraday; activeTf = IntradayTfInput; }
            else if (EnableDaily) { activeSlot = SlotType.Daily; }
            else if (EnableWeekly) { activeSlot = SlotType.Weekly; }
            else if (EnableMonthly) { activeSlot = SlotType.Monthly; }
            else { activeSlot = SlotType.Intraday; activeTf = IntradayTfInput; }
        }

        //==================================================================
        // Bar processing
        //==================================================================
        protected override void OnBarUpdate()
        {
            if (CurrentBars[HTF] < 2 || CurrentBars[LTF] < 3) return;

            if (BarsInProgress == HTF) OnHtfClose();
            else if (BarsInProgress == LTF) OnLtfClose();
            else if (BarsInProgress == 0) PublishDashboard();
        }

        //------------------------------------------------------------------
        // HTF bar close — advances the C1 → C2 → C3 window.
        //------------------------------------------------------------------
        private void OnHtfClose()
        {
            RollDailyCounters();

            var closed = new Candle(
                Times[HTF][0], Opens[HTF][0], Highs[HTF][0], Lows[HTF][0], Closes[HTF][0]);

            switch (setup.Phase)
            {
                case SetupPhase.WaitC1:
                    TryLockC1(closed);
                    break;

                case SetupPhase.C2Watch:
                    // The just-closed HTF bar IS C2. Resolve bias + decide entry.
                    htfClosesSinceC1 = 1;
                    OnC2Closed(closed);
                    break;

                case SetupPhase.C2ClosedArmed:
                case SetupPhase.C3Window:
                    // The just-closed HTF bar IS C3. The MARKET-entry window is
                    // now over, but a resting 1:1 limit PERSISTS (do NOT cancel).
                    htfClosesSinceC1 = 2;
                    OnC3Closed(closed);
                    break;

                case SetupPhase.LimitWorking:
                    // Limit outlives C3 — a new HTF close does NOT cancel it.
                    // Roll the closed bar in as the next C1 candidate only if no
                    // active trade/limit exists (handled by single-trade lock).
                    break;
            }
        }

        private void TryLockC1(Candle c1)
        {
            // Respect the single-active-trade lock: don't arm while busy.
            if (activeTrade != null || setup.LimitResting) return;

            string key = SessionKeyFor(c1.T);
            if (stateStore != null && stateStore.IsConsumed(key)) return;

            CRT_Structure.LockC1(setup, c1, key);
            confirm.Reset();
            htfClosesSinceC1 = 0;
            sweepStartUTC = DateTime.MinValue;

            // C2 window opens now (C2 is the forming HTF bar).
            setup.C2OpenUTC = CRT_Time.ChartToUTC(c1.T);
        }

        private void OnC2Closed(Candle c2)
        {
            // Fold the C2 HTF bar into the running extremes (belt & braces —
            // LTF bars already tracked it) and resolve bias from the CLOSE.
            CRT_Structure.UpdateSweep(setup, c2.H, c2.L);

            // The sweep can ONLY be satisfied in C2. If C1 was never swept in
            // C2, there is no setup.
            if (!setup.SweptHigh && !setup.SweptLow) { CompleteSetup("no sweep in C2"); return; }

            TradeBias bias = CRT_Structure.BiasFromC2Close(setup, c2.C);
            if (bias == TradeBias.None) { CompleteSetup("C2 closed outside C1 (breakout)"); return; }
            setup.Bias = bias;

            // SL fixed at the C2 extreme ± buffer (independent of the 50% calc).
            double bufferPx = SlBufferTicks * TickSize;
            setup.SlLevel = CRT_Structure.SlFromC2Extreme(setup, bufferPx);

            setup.Phase = SetupPhase.C2ClosedArmed;

            // Re-validate a PROVISIONAL C2 confirmation at this boundary (§1.2)
            // and, if valid, decide market vs 1:1 limit. C2 itself never fills —
            // any order placed here is attributed to C3.
            if (setup.TriggerFired && CarryToC3)
                DecideEntry(refPrice: c2.C, atC3Open: true);

            // Move into the C3 window (forming HTF bar) regardless, so a fresh
            // C3 trigger can still fire when there was no C2 carry-over.
            setup.C3OpenUTC = CRT_Time.ChartToUTC(c2.T);
            if (setup.Phase == SetupPhase.C2ClosedArmed)
                setup.Phase = SetupPhase.C3Window;
        }

        private void OnC3Closed(Candle c3)
        {
            // Market-entry opportunity ends here. If a limit is resting it keeps
            // working (phase already LimitWorking). Otherwise the setup is done.
            if (setup.LimitResting)
            {
                setup.Phase = SetupPhase.LimitWorking;
                return;
            }
            if (activeTrade != null) return; // filled; managed by callbacks
            CompleteSetup("C3 closed with no entry");
        }

        //------------------------------------------------------------------
        // LTF bar close — sweep (C2 only), confirmation, 50% guard, limit mgmt.
        //------------------------------------------------------------------
        private void OnLtfClose()
        {
            double hi = Highs[LTF][0], lo = Lows[LTF][0];
            var bar = new Candle(Times[LTF][0], Opens[LTF][0], hi, lo, Closes[LTF][0]);

            // 50% guard / invalidation is LIVE for the whole setup life,
            // including while a limit rests after C3 close.
            if (setup.Bias != TradeBias.None &&
                (setup.Phase == SetupPhase.C3Window || setup.Phase == SetupPhase.LimitWorking ||
                 setup.Phase == SetupPhase.C2ClosedArmed))
            {
                if (CRT_Structure.FiftyTaken(setup, hi, lo))
                {
                    InvalidateOnFifty();
                    return;
                }
            }

            switch (setup.Phase)
            {
                case SetupPhase.C2Watch:
                    // C2 window: track sweep, then scan for a PROVISIONAL trigger.
                    bool newly = CRT_Structure.UpdateSweep(setup, hi, lo);
                    if (newly && sweepStartUTC == DateTime.MinValue)
                        sweepStartUTC = CRT_Time.ChartToUTC(bar.T);

                    if (setup.SweptHigh || setup.SweptLow)
                    {
                        // Provisional bias for confirmation scanning (finalised at
                        // C2 close). Use the sweep side.
                        TradeBias provBias = setup.SweptHigh ? TradeBias.Short : TradeBias.Long;
                        confirm.AddBar(bar);
                        if (confirm.Evaluate(provBias, TriggerModelInput, CisdRefInput, sweepStartUTC))
                        {
                            // A trigger achieved INSIDE C2 — provisional; carried
                            // to the C2-close boundary. C2 never executes.
                            setup.TriggerFired = true;
                            setup.TriggerFiredInC2 = true;
                            setup.ConfirmClose = confirm.ConfirmClose;
                        }
                    }
                    break;

                case SetupPhase.C3Window:
                    // No C2 carry-over → keep scanning for a C3 trigger.
                    if (!setup.TriggerFired && setup.Bias != TradeBias.None)
                    {
                        confirm.AddBar(bar);
                        if (confirm.Evaluate(setup.Bias, TriggerModelInput, CisdRefInput, sweepStartUTC))
                        {
                            setup.TriggerFired = true;
                            setup.ConfirmClose = confirm.ConfirmClose;
                            DecideEntry(refPrice: bar.C, atC3Open: false);
                        }
                    }
                    break;

                case SetupPhase.LimitWorking:
                    // Only the 50% touch (handled above) can end the resting limit
                    // before it fills. No time-based cancel.
                    break;
            }
        }

        //==================================================================
        // Entry decision (market vs 1:1 limit) — always attributed to C3.
        //==================================================================
        private void DecideEntry(double refPrice, bool atC3Open)
        {
            if (activeTrade != null || setup.LimitResting) return;
            if (setup.Bias == TradeBias.None) return;

            // Optional hour filter — gate on C3-open NY hour.
            if (EnableHourFilter)
            {
                int nyHour = CRT_Time.UTCToNY(setup.C3OpenUTC == DateTime.MinValue
                    ? DateTime.UtcNow : setup.C3OpenUTC).Hour;
                if (!hourFilter.IsAllowed(nyHour)) { CompleteSetup("hour filter"); return; }
            }

            // News block — no new entries inside a blackout window.
            if (EnableNews && news != null &&
                news.IsNewsBlocked(DateTime.UtcNow, NewsBeforeMin, NewsAfterMin, true, false, false))
            { CompleteSetup("news blackout"); return; }

            // Daily risk guards.
            if (tradesToday >= MaxTradesPerDay) { CompleteSetup("max trades/day"); return; }
            if (consecLosses >= MaxConsecLosses) { CompleteSetup("max consec losses"); return; }
            if (DailyLossLimit > 0 && (dayStartBalance - AccountBalance()) >= DailyLossLimit)
            { CompleteSetup("daily loss limit"); return; }

            var mi = Instrument.MasterInstrument;
            double sweepExt = CRT_Structure.SweepExtreme(setup);
            double bufferPx = SlBufferTicks * TickSize;

            var plan = CRT_Execution.BuildPlan(
                setup.Bias, refPrice, setup.C1EQ, sweepExt, bufferPx,
                priceNow: Closes[0][0], minStopPx: 0, mi: mi);

            if (plan.Skip) { CompleteSetup("skip: " + plan.SkipReason); return; }

            int contracts = SizePosition(plan.RiskPrice);
            if (contracts <= 0) { CompleteSetup("size = 0"); return; }

            Order entry = CRT_Execution.SubmitEntry(this, setup.Bias, plan, contracts, setup.SessionKey);

            setup.SlLevel = plan.SlPrice;
            if (plan.UseLimit)
            {
                setup.LimitResting = true;
                setup.LimitPrice = plan.EntryRef;
                setup.Phase = SetupPhase.LimitWorking; // persists beyond C3 close
            }

            activeTrade = new ActiveTrade
            {
                EntryOrder = entry,
                IsLong = setup.Bias == TradeBias.Long,
                SlPrice = plan.SlPrice,
                TpPrice = plan.TpPrice,
                Contracts = contracts,
                SlotIndex = setup.SlotIndex,
                SessionKey = setup.SessionKey
            };

            if (DrawVisuals)
                CRT_Visuals.DrawTradeLevels(this, plan.EntryRef, plan.SlPrice, plan.TpPrice);
        }

        //==================================================================
        // Order / execution callbacks
        //==================================================================
        protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice,
            int quantity, int filled, double averageFillPrice, OrderState orderState, DateTime time,
            ErrorCode error, string nativeError)
        {
            if (activeTrade == null || order != activeTrade.EntryOrder) return;

            if (orderState == OrderState.Filled)
            {
                setup.LimitResting = false;
                setup.Phase = SetupPhase.Filled;

                activeTrade.EntryPrice = averageFillPrice;
                activeTrade.EntryTime = CRT_Time.ChartToUTC(time);

                var (sl, tp) = CRT_Execution.PlaceBracket(this, activeTrade.IsLong,
                    activeTrade.Contracts, activeTrade.SlPrice, activeTrade.TpPrice, setup.SessionKey);
                activeTrade.SlOrder = sl;
                activeTrade.TpOrder = tp;

                tradesToday++;
                if (stateStore != null) stateStore.MarkConsumed(setup.SessionKey);
                if (notify != null)
                    notify.NotifyFill(0, setup.SessionKey, activeTrade.IsLong, averageFillPrice,
                        activeTrade.SlPrice, activeTrade.TpPrice, activeTrade.Contracts);
            }
            else if (orderState == OrderState.Rejected)
            {
                activeTrade = null;
                CompleteSetup("entry rejected: " + nativeError);
            }
        }

        protected override void OnExecutionUpdate(Execution execution, string executionId,
            double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
        {
            if (activeTrade == null) return;

            bool isExit = (activeTrade.SlOrder != null && execution.Order == activeTrade.SlOrder) ||
                          (activeTrade.TpOrder != null && execution.Order == activeTrade.TpOrder);
            if (!isExit) return;

            bool tpHit = activeTrade.TpOrder != null && execution.Order == activeTrade.TpOrder;
            double pnl = (price - activeTrade.EntryPrice) * (activeTrade.IsLong ? 1 : -1)
                         * activeTrade.Contracts * Instrument.MasterInstrument.PointValue;

            if (pnl < 0) consecLosses++; else consecLosses = 0;

            if (stateStore != null)
                stateStore.AppendClosedTrade(new CrtLedgerTrade
                {
                    EntryTimeUTC = activeTrade.EntryTime,
                    ExitTimeUTC = CRT_Time.ChartToUTC(time),
                    SessionKey = activeTrade.SessionKey,
                    IsLong = activeTrade.IsLong,
                    EntryPrice = activeTrade.EntryPrice,
                    ExitPrice = price,
                    Contracts = activeTrade.Contracts,
                    PnL = pnl,
                    ExitReason = tpHit ? "TP" : "SL"
                });

            if (notify != null)
                notify.NotifyResult(0, activeTrade.SessionKey, activeTrade.IsLong, pnl, 0, tpHit ? "TP" : "SL");

            // Cancel the sibling protective order, if still working.
            CancelSibling(tpHit ? activeTrade.SlOrder : activeTrade.TpOrder);

            activeTrade = null;
            CompleteSetup(tpHit ? "TP hit" : "SL hit");
        }

        private void CancelSibling(Order o)
        {
            if (o != null && (o.OrderState == OrderState.Working || o.OrderState == OrderState.Accepted))
                CancelOrder(o);
        }

        //==================================================================
        // Invalidation / completion
        //==================================================================
        private void InvalidateOnFifty()
        {
            // Price touched 50% (C1_EQ) before the limit filled → cancel the
            // resting limit AND invalidate the setup (§6.1/§6.2).
            if (setup.LimitResting && activeTrade != null &&
                activeTrade.EntryOrder != null &&
                (activeTrade.EntryOrder.OrderState == OrderState.Working ||
                 activeTrade.EntryOrder.OrderState == OrderState.Accepted))
            {
                CancelOrder(activeTrade.EntryOrder);
                if (notify != null)
                    notify.NotifyCancelled(0, setup.SessionKey, setup.Bias == TradeBias.Long,
                        setup.C1EQ, "50% reached before limit fill");
            }

            setup.Invalidated = true;
            setup.InvalidReason = "50% (C1_EQ) taken";
            activeTrade = null;
            CompleteSetup("invalidated: 50% taken");
        }

        private void CompleteSetup(string reason)
        {
            if (stateStore != null && setup.C1Locked)
                stateStore.MarkConsumed(setup.SessionKey);

            setup.Phase = SetupPhase.WaitC1;
            setup.C1Locked = false;
            setup.ResetSweepScan();
            confirm.Reset();
            htfClosesSinceC1 = 0;
            sweepStartUTC = DateTime.MinValue;
            if (DrawVisuals) CRT_Visuals.ClearTradeLevels(this);
        }

        //==================================================================
        // Helpers
        //==================================================================
        private string SessionKeyFor(DateTime c1ChartTime)
        {
            return CRT_Slots.TfLabel(activeSlot, activeTf) + "#" +
                   CRT_Time.ChartToUTC(c1ChartTime).ToString("yyyyMMddHHmm");
        }

        private double AccountBalance()
        {
            try { return Account.Get(AccountItem.CashValue, Currency.UsDollar); }
            catch { return 0; }
        }

        private int SizePosition(double slDistancePrice)
        {
            double bal = AccountBalance();
            double pointValue = Instrument.MasterInstrument.PointValue;
            var mode = pointValue < 10 ? ContractSizeMode.Micro : ContractSizeMode.Mini;
            return CRT_Risk.CalcContracts(bal, RiskPercent, slDistancePrice, pointValue, mode);
        }

        private void RollDailyCounters()
        {
            DateTime nyDay = CRT_Time.UTCToNY(DateTime.UtcNow).Date;
            if (nyDay != currentNyDay)
            {
                currentNyDay = nyDay;
                tradesToday = 0;
                dayStartBalance = AccountBalance();
            }
        }

        //==================================================================
        // Dashboard / render
        //==================================================================
        private void PublishDashboard()
        {
            if (!ShowDashboard) return;

            var st = new CrtDashState
            {
                SlotLabel = "CRT " + CRT_Slots.TfLabel(activeSlot, activeTf),
                NYClock = CRT_Time.UTCToNY(DateTime.UtcNow).ToString("HH:mm:ss"),
                Phase = setup.Phase.ToString(),
                CurrentBalance = AccountBalance(),
                Bias = setup.Bias == TradeBias.Long ? "LONG" : setup.Bias == TradeBias.Short ? "SHORT" : "--",
                C1High = setup.C1High,
                C1Low = setup.C1Low,
                C1EQ = setup.C1EQ,
                Sweep = setup.SweptHigh ? "High" : setup.SweptLow ? "Low" : "none",
                TriggerModel = TriggerModelInput.ToString(),
                CisdStatus = confirm.CisdOk ? "armed" : "watch",
                IfvgStatus = confirm.IfvgOk ? "armed" : "watch",
                EntryInfo = setup.LimitResting ? "limit @ " + setup.LimitPrice.ToString("0.##") :
                            activeTrade != null ? "market @ " + activeTrade.EntryPrice.ToString("0.##") : "--",
                InTrade = activeTrade != null && setup.Phase == SetupPhase.Filled,
                TradeDir = activeTrade != null ? (activeTrade.IsLong ? "LONG" : "SHORT") : "--",
                EntryPrice = activeTrade != null ? activeTrade.EntryPrice : 0,
                StopLoss = activeTrade != null ? activeTrade.SlPrice : 0,
                TakeProfit = activeTrade != null ? activeTrade.TpPrice : 0,
                ContractCount = activeTrade != null ? activeTrade.Contracts : 0,
                InstrumentName = Instrument.FullName,
                TickSize = TickSize,
                NewsBlackoutActive = EnableNews && news != null &&
                    news.IsNewsBlocked(DateTime.UtcNow, NewsBeforeMin, NewsAfterMin, true, false, false)
            };
            CRT_Dashboard.Publish(this, st);
        }

        public override void OnRenderTargetChanged() { }

        protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
        {
            base.OnRender(chartControl, chartScale);
            if (ShowDashboard)
                CRT_Dashboard.Render(this, ChartControl, RenderTarget);
        }
    }
}
