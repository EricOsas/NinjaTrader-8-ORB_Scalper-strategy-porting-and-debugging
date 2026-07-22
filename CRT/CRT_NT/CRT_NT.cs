#region Using declarations
using System;
using System.Collections.Generic;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;
#endregion

//
// CRT_NT.cs — Candle Range Theory strategy, main class (NinjaTrader 8 / NinjaScript).
// See CRT/01-STRATEGY-SPEC.md (logic) and CRT/02-NT8-IMPLEMENTATION.md (module map).
//
// Multi-timeframe design:
//   BarsInProgress 0 = PRIMARY chart series (execution/order plumbing, dashboard).
//   BarsInProgress 1 = HTF (Candle 1 reference series, per active slot).
//   BarsInProgress 2 = LTF (confirmation series: CISD / IFVG detection).
//
// Concurrency: ONE active CRT setup at a time (global), per design decision.
//
namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public partial class CRT_NT : Strategy
    {
        // --- module instances ------------------------------------------------
        private CRT_State state;
        private CrtHourFilter hourFilter;
        private CrtConfirmTracker confirm;

        // --- the single evolving setup + live position -----------------------
        private CrtSetup setup = new CrtSetup();
        private CrtLiveSnapshot live;

        // --- resolved timeframes ---------------------------------------------
        private int htfMinutes;   // active C1 slot size (minutes-equivalent for intraday)
        private int ltfMinutes;   // resolved execution TF
        private string activeSlotName = "Intraday";

        // data-series indices (assigned in Configure)
        private int htfSeries = 1;
        private int ltfSeries = 2;

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "CRT_NT";
                Description = "Candle Range Theory (CRT) — C1 range / C2 sweep+CISD / C3 IFVG execution.";
                Calculate = Calculate.OnBarClose;
                EntriesPerDirection = 1;
                EntryHandling = EntryHandling.AllEntries;
                IsExitOnSessionCloseStrategy = false;
                IncludeCommission = true;
                BarsRequiredToTrade = 3;
            }
            else if (State == State.Configure)
            {
                ResolveTimeframes();

                // HTF reference series (Candle 1). Intraday uses minutes; higher
                // slots use Day/Week/Month base periods.
                AddHtfSeries();

                // LTF confirmation series.
                AddDataSeries(BarsPeriodType.Minute, ltfMinutes);
            }
            else if (State == State.DataLoaded)
            {
                hourFilter = new CrtHourFilter { Enabled = EnableHourFilter };
                hourFilter.SetFromCsv(AllowedC3HoursCsv);

                confirm = new CrtConfirmTracker(300);

                string dir = System.IO.Path.Combine(
                    NinjaTrader.Core.Globals.UserDataDir, "CRT_State");
                state = new CRT_State(dir, Instrument.FullName);

                // Re-adopt a live position after a restart.
                live = state.LoadLiveTrade();
                if (live != null)
                    setup.Phase = CrtPhase.InTrade;
            }
        }

        //====================================================================
        // Timeframe resolution
        //====================================================================
        private void ResolveTimeframes()
        {
            // Pick the active slot (only ONE HTF series is added; priority order
            // Intraday > Daily > Weekly > Monthly). Multiple slots would require
            // multiple HTF series — kept single here for the skeleton, expandable.
            if (EnableIntraday)      { activeSlotName = "Intraday"; htfMinutes = IntradayC1Minutes; }
            else if (EnableDaily)    { activeSlotName = "Daily";    htfMinutes = 1440; }
            else if (EnableWeekly)   { activeSlotName = "Weekly";   htfMinutes = 10080; }
            else if (EnableMonthly)  { activeSlotName = "Monthly";  htfMinutes = 43200; }
            else                     { activeSlotName = "Intraday"; htfMinutes = 60; }

            // LTF: single override wins globally; else per-slot derivation.
            ltfMinutes = LtfOverrideMinutes > 0
                ? LtfOverrideMinutes
                : CrtSlots.DeriveLtfMinutes(activeSlotName, htfMinutes);
        }

        private void AddHtfSeries()
        {
            switch (activeSlotName)
            {
                case "Daily":   AddDataSeries(BarsPeriodType.Day, 1);   break;
                case "Weekly":  AddDataSeries(BarsPeriodType.Week, 1);  break;
                case "Monthly": AddDataSeries(BarsPeriodType.Month, 1); break;
                default:        AddDataSeries(BarsPeriodType.Minute, htfMinutes); break;
            }
        }

        //====================================================================
        // Bar routing
        //====================================================================
        protected override void OnBarUpdate()
        {
            if (CurrentBars[0] < BarsRequiredToTrade) return;

            if (BarsInProgress == htfSeries)      OnHtfBarClosed();
            else if (BarsInProgress == ltfSeries) OnLtfBarClosed();
            // BarsInProgress == 0 (primary) reserved for order/exit management
            // and dashboard refresh (implemented in execution/dashboard modules).
        }

        //--------------------------------------------------------------------
        // HTF: capture Candle 1, then track Candle 2 sweep.
        //--------------------------------------------------------------------
        private void OnHtfBarClosed()
        {
            double h = Highs[htfSeries][0];
            double l = Lows[htfSeries][0];
            DateTime openT = Times[htfSeries][1]; // just-closed bar's open time
            DateTime closeT = Times[htfSeries][0];

            switch (setup.Phase)
            {
                case CrtPhase.Idle:
                    // Only arm a fresh range when flat (one active trade globally).
                    if (live != null) return;
                    setup.Reset();
                    setup.SlotName = activeSlotName;
                    setup.Range = CrtStructure.BuildRange(
                        openT, closeT, closeT, h, l); // C2 close resolved as it forms
                    setup.Phase = CrtPhase.RangeSet;
                    break;

                case CrtPhase.RangeSet:
                    // The bar that just closed acts as Candle 2 — did it purge a side?
                    EvaluateSweep(h, l, closeT);
                    break;
            }
        }

        private void EvaluateSweep(double c2High, double c2Low, DateTime c2Close)
        {
            double buffer = SweepBufferTicks * TickSize;
            SweepSide side = CrtStructure.DetectSweep(setup.Range, c2High, c2Low, buffer);
            if (side == SweepSide.None)
            {
                // No purge this candle -> slide the reference forward (new C1).
                setup.Phase = CrtPhase.Idle;
                return;
            }

            setup.Sweep = side;
            setup.IsLong = (side == SweepSide.Low);
            setup.ManipulationExtreme = setup.IsLong ? c2Low : c2High;

            // C3 hour gate is checked at the C3 window open (== C2 close here).
            if (!hourFilter.Allows(CrtTimeToNy(c2Close)))
            {
                setup.Phase = CrtPhase.Idle; // this range cannot execute in a blocked hour
                return;
            }

            // Seed the CISD reference at the swept boundary.
            confirm.Reset();
            confirm.CisdLevel = setup.IsLong ? setup.Range.Low : setup.Range.High;
            setup.CisdLevel = confirm.CisdLevel;
            setup.Phase = CrtPhase.Swept;
        }

        //--------------------------------------------------------------------
        // LTF: run CISD + IFVG detection during Candle 3, arm the entry.
        //--------------------------------------------------------------------
        private void OnLtfBarClosed()
        {
            if (setup.Phase != CrtPhase.Swept) return;

            var bar = new LtfBar
            {
                Time  = Times[ltfSeries][0],
                Open  = Opens[ltfSeries][0],
                High  = Highs[ltfSeries][0],
                Low   = Lows[ltfSeries][0],
                Close = Closes[ltfSeries][0]
            };
            confirm.OnLtfBarClosed(bar, setup.IsLong);

            bool cisdOk = !RequireCisd || CrtStructure.IsCisd(setup.IsLong, bar.Close, setup.CisdLevel);
            if (RequireCisd && cisdOk) setup.CisdConfirmed = true;

            bool ifvgOk = !RequireIfvg || confirm.HasInvertedGap(setup.IsLong);
            if (RequireIfvg && ifvgOk) setup.IfvgConfirmed = true;

            if (cisdOk && ifvgOk)
                ArmEntry();
        }

        private void ArmEntry()
        {
            if (state.IsConsumed(setup.SlotName, setup.Range.C1OpenTime, setup.IsLong))
            {
                setup.Phase = CrtPhase.Idle;
                return;
            }

            double entry = RequireIfvg
                ? confirm.GapProximal(setup.IsLong)
                : setup.CisdLevel;
            if (entry <= 0) entry = Close[0];

            CrtStructure.ResolveOrder(setup, entry, StopBufferTicks * TickSize);

            double slDist = Math.Abs(setup.PlannedEntry - setup.PlannedStop);
            int qty = CRT_Risk.CalcContracts(
                RiskPercent, slDist, TickSize, Instrument.MasterInstrument.PointValue,
                ContractMode, MaxContracts, Account != null ? Account.Get(AccountItem.CashValue, Currency.UsDollar) : 0);
            if (qty < 1) { setup.Phase = CrtPhase.Idle; return; }

            setup.Phase = CrtPhase.Armed;
            setup.ArmedTime = Time[0];

            // Order submission handled by CRT_Execution (partial); placeholder here.
            SubmitCrtEntry(qty);

            state.MarkConsumed(setup.SlotName, setup.Range.C1OpenTime, setup.IsLong);
        }

        // NY-local conversion bridge (delegates to lifted CRT_Time engine).
        private DateTime CrtTimeToNy(DateTime platformTime)
        {
            return CRT_Time.ToNewYork(platformTime, TimeZoneInfo.Local);
        }
    }
}
