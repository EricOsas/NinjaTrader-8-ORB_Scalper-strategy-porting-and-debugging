// CRT_NT_Inputs.cs — user-facing NinjaScript properties (partial class).
// Grouped by function; see CRT/02-NT8-IMPLEMENTATION.md §Inputs.
#region Using declarations
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using NinjaTrader.NinjaScript;
#endregion

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    public partial class CRT_NT : Strategy
    {
        // ---------------- Reference-candle (C1) slots ----------------------
        [NinjaScriptProperty]
        [Display(Name = "Enable Intraday", GroupName = "1. CRT Slots", Order = 0)]
        public bool EnableIntraday { get; set; } = true;

        // Intraday C1 size. Sub-slots: 15m / 30m / 1h / 2h / 4h.
        [NinjaScriptProperty]
        [Display(Name = "Intraday C1 (minutes: 15/30/60/120/240)", GroupName = "1. CRT Slots", Order = 1)]
        public int IntradayC1Minutes { get; set; } = 60;

        [NinjaScriptProperty]
        [Display(Name = "Enable Daily", GroupName = "1. CRT Slots", Order = 2)]
        public bool EnableDaily { get; set; } = false;

        [NinjaScriptProperty]
        [Display(Name = "Enable Weekly", GroupName = "1. CRT Slots", Order = 3)]
        public bool EnableWeekly { get; set; } = false;

        [NinjaScriptProperty]
        [Display(Name = "Enable Monthly", GroupName = "1. CRT Slots", Order = 4)]
        public bool EnableMonthly { get; set; } = false;

        // ---------------- Execution (LTF) timeframe ------------------------
        // Single override field. If > 0, this LTF (in minutes) is used for ALL
        // slots. If 0 (blank), the per-slot derived LTF is used:
        //   1H->M5, Daily->M15, Weekly->H1, Monthly->H4 (see CRT_Slots.DeriveLtf).
        [NinjaScriptProperty]
        [Display(Name = "LTF Override (minutes, 0 = auto per slot)", GroupName = "2. Execution", Order = 0)]
        public int LtfOverrideMinutes { get; set; } = 0;

        // ---------------- CRT confirmation ---------------------------------
        [NinjaScriptProperty]
        [Display(Name = "Require CISD", GroupName = "3. Confirmation", Order = 0)]
        public bool RequireCisd { get; set; } = true;

        [NinjaScriptProperty]
        [Display(Name = "Require IFVG", GroupName = "3. Confirmation", Order = 1)]
        public bool RequireIfvg { get; set; } = true;

        [NinjaScriptProperty]
        [Display(Name = "Sweep buffer (ticks)", GroupName = "3. Confirmation", Order = 2)]
        public int SweepBufferTicks { get; set; } = 0;

        // ---------------- C3 hour filter (CCT-style) -----------------------
        [NinjaScriptProperty]
        [Display(Name = "Enable C3 Hour Filter", GroupName = "4. C3 Hour Filter", Order = 0)]
        public bool EnableHourFilter { get; set; } = false;

        // CSV of NY-local hours allowed to host C3, e.g. "3,7,10".
        [NinjaScriptProperty]
        [Display(Name = "Allowed C3 hours (NY, CSV e.g. 3,7,10)", GroupName = "4. C3 Hour Filter", Order = 1)]
        public string AllowedC3HoursCsv { get; set; } = "";

        // ---------------- Risk ---------------------------------------------
        [NinjaScriptProperty]
        [Display(Name = "Risk % per trade", GroupName = "5. Risk", Order = 0)]
        public double RiskPercent { get; set; } = 0.5;

        [NinjaScriptProperty]
        [Display(Name = "Contract mode (Micro/Mini)", GroupName = "5. Risk", Order = 1)]
        public ContractSizeMode ContractMode { get; set; } = ContractSizeMode.Micro;

        [NinjaScriptProperty]
        [Display(Name = "Max contracts", GroupName = "5. Risk", Order = 2)]
        public int MaxContracts { get; set; } = 10;

        [NinjaScriptProperty]
        [Display(Name = "Stop buffer (ticks beyond manipulation)", GroupName = "5. Risk", Order = 3)]
        public int StopBufferTicks { get; set; } = 2;

        // ---------------- Targets ------------------------------------------
        [NinjaScriptProperty]
        [Display(Name = "Take partial at 0.5 equilibrium", GroupName = "6. Targets", Order = 0)]
        public bool PartialAtEquilibrium { get; set; } = true;

        [NinjaScriptProperty]
        [Display(Name = "Move to breakeven after partial", GroupName = "6. Targets", Order = 1)]
        public bool BreakevenAfterPartial { get; set; } = true;

        // ---------------- Dashboard ----------------------------------------
        [NinjaScriptProperty]
        [Display(Name = "Show Dashboard", GroupName = "7. Dashboard", Order = 0)]
        public bool ShowDashboard { get; set; } = true;
    }
}
