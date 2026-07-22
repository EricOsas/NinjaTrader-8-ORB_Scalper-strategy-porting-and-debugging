#region Using declarations
using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript;
#endregion

// CRT_NT — parameter surface (partial class of CRT_NT_Strategy).
// Contracts match the logic modules: IntradayTF, EntryTriggerModel,
// CisdRefMode (CRT_Types.cs), slot enables (CRT_Slots.cs), CSV hour filter
// (CRT_HourFilter.cs). Grouped to echo the ORB layout convention.
namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public partial class CRT_NT_Strategy : Strategy
    {
        // ---------------- 1. Timeframe / Slot ----------------
        // v1 runs ONE active C1 timeframe (see CRT_Slots). Enable exactly one
        // primary; if several are on, priority is Intraday→Daily→Weekly→Monthly.
        [NinjaScriptProperty]
        [Display(Name = "Use Intraday Slot", Order = 1, GroupName = "1. Timeframe")]
        public bool EnableIntraday { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Intraday Timeframe (C1/C2/C3)", Order = 2, GroupName = "1. Timeframe")]
        public IntradayTF IntradayTfInput { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Daily Slot", Order = 3, GroupName = "1. Timeframe")]
        public bool EnableDaily { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Weekly Slot", Order = 4, GroupName = "1. Timeframe")]
        public bool EnableWeekly { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Monthly Slot", Order = 5, GroupName = "1. Timeframe")]
        public bool EnableMonthly { get; set; }

        [NinjaScriptProperty]
        [Range(0, 240)]
        [Display(Name = "LTF Minutes Override (0 = auto)", Order = 6, GroupName = "1. Timeframe")]
        public int LtfMinutesOverride { get; set; }

        // ---------------- 2. Session ----------------
        [NinjaScriptProperty]
        [Display(Name = "Restrict To Session (Intraday only)", Order = 1, GroupName = "2. Session")]
        public bool RestrictSession { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Session Start (HH:mm, exchange tz)", Order = 2, GroupName = "2. Session")]
        public string SessionStart { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Session End (HH:mm, exchange tz)", Order = 3, GroupName = "2. Session")]
        public string SessionEnd { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Flatten At (HH:mm, exchange tz)", Order = 4, GroupName = "2. Session")]
        public string FlattenAt { get; set; }

        // ---------------- 3. CRT Model ----------------
        [NinjaScriptProperty]
        [Display(Name = "Trigger Model", Order = 1, GroupName = "3. CRT Model")]
        public EntryTriggerModel TriggerModelInput { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "CISD Reference", Order = 2, GroupName = "3. CRT Model")]
        public CisdRefMode CisdRefInput { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Require C2 Close Back Inside C1", Order = 3, GroupName = "3. CRT Model")]
        public bool RequireCloseBack { get; set; }

        [NinjaScriptProperty]
        [Range(1, 500)]
        [Display(Name = "Confirm Timeout (LTF bars in C3)", Order = 4, GroupName = "3. CRT Model")]
        public int ConfirmTimeoutBars { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Carry Trigger Into C3", Order = 5, GroupName = "3. CRT Model")]
        public bool CarryToC3 { get; set; }

        // ---------------- 4. Entry / Targets ----------------
        // Execution model is fixed per spec: market if >=1:1 at confirm close,
        // else a single 1:1 limit at the C1_EQ / risk midpoint. TP = C1_EQ.
        [NinjaScriptProperty]
        [Range(0, 100)]
        [Display(Name = "SL Buffer (ticks beyond sweep)", Order = 1, GroupName = "4. Entry")]
        public int SlBufferTicks { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Move SL to BE at 1:1", Order = 2, GroupName = "4. Entry")]
        public bool BreakevenAt1R { get; set; }

        // ---------------- 5. Risk ----------------
        [NinjaScriptProperty]
        [Range(0.01, 100.0)]
        [Display(Name = "Risk Percent Per Trade", Order = 1, GroupName = "5. Risk")]
        public double RiskPercent { get; set; }

        [NinjaScriptProperty]
        [Range(1, 100)]
        [Display(Name = "Max Trades Per Day", Order = 2, GroupName = "5. Risk")]
        public int MaxTradesPerDay { get; set; }

        [NinjaScriptProperty]
        [Range(1, 20)]
        [Display(Name = "Max Consecutive Losses", Order = 3, GroupName = "5. Risk")]
        public int MaxConsecLosses { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, 100000.0)]
        [Display(Name = "Daily Loss Limit (currency, 0=off)", Order = 4, GroupName = "5. Risk")]
        public double DailyLossLimit { get; set; }

        // ---------------- 6. NY Hour Filter (CCT-style CSV) ----------------
        [NinjaScriptProperty]
        [Display(Name = "Enable NY Hour Filter (on C3 open)", Order = 1, GroupName = "6. Hour Filter")]
        public bool EnableHourFilter { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Allowed C3 NY Hours (CSV, e.g. 2,3,9,10)", Order = 2, GroupName = "6. Hour Filter")]
        public string AllowedHoursCsv { get; set; }

        // ---------------- 7. News ----------------
        [NinjaScriptProperty]
        [Display(Name = "Enable News Filter", Order = 1, GroupName = "7. News")]
        public bool EnableNews { get; set; }

        [NinjaScriptProperty]
        [Range(0, 240)]
        [Display(Name = "News Block Minutes Before", Order = 2, GroupName = "7. News")]
        public int NewsBeforeMin { get; set; }

        [NinjaScriptProperty]
        [Range(0, 240)]
        [Display(Name = "News Block Minutes After", Order = 3, GroupName = "7. News")]
        public int NewsAfterMin { get; set; }

        // ---------------- 8. Dashboard / Visuals ----------------
        [NinjaScriptProperty]
        [Display(Name = "Show Dashboard", Order = 1, GroupName = "8. Visuals")]
        public bool ShowDashboard { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Draw CRT Boxes / Sweep / Levels", Order = 2, GroupName = "8. Visuals")]
        public bool DrawVisuals { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Enable Alerts", Order = 3, GroupName = "8. Visuals")]
        public bool EnableAlerts { get; set; }

        private void SetCrtDefaults()
        {
            Name                    = "CRT_NT_Strategy";
            Calculate               = Calculate.OnBarClose;
            EntriesPerDirection     = 1;
            IsUnmanaged             = true;   // execution module uses unmanaged orders
            BarsRequiredToTrade     = 20;

            // Timeframe / slot
            EnableIntraday          = true;
            IntradayTfInput         = IntradayTF.H1;
            EnableDaily             = false;
            EnableWeekly            = false;
            EnableMonthly           = false;
            LtfMinutesOverride      = 0;      // auto-derive from CRT_Slots

            // Session
            RestrictSession         = true;
            SessionStart            = "02:00";
            SessionEnd              = "11:30";
            FlattenAt               = "15:55";

            // CRT model
            TriggerModelInput       = EntryTriggerModel.CISD_IFVG;
            CisdRefInput            = CisdRefMode.ConsecutiveSequence;
            RequireCloseBack        = true;
            ConfirmTimeoutBars      = 60;
            CarryToC3               = true;

            // Entry
            SlBufferTicks           = 2;
            BreakevenAt1R           = false;  // spec: no trailing; BE optional

            // Risk
            RiskPercent             = 0.5;
            MaxTradesPerDay         = 3;
            MaxConsecLosses         = 3;
            DailyLossLimit          = 0.0;

            // Hour filter
            EnableHourFilter        = true;
            AllowedHoursCsv         = "2,3,4,9,10,11";

            // News
            EnableNews              = false;
            NewsBeforeMin           = 5;
            NewsAfterMin            = 5;

            // Visuals
            ShowDashboard           = true;
            DrawVisuals             = true;
            EnableAlerts            = true;
        }
    }
}
