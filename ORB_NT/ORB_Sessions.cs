using System;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public enum SessionPhase
    {
        Waiting,
        RangeForming,
        TradingWindow,
        Closed
    }

    public enum SessionType
    {
        Intraday,
        Daily,
        Weekly
    }

    public class SlotState
    {
        public int SlotIndex { get; private set; }
        public bool IsEnabled { get; set; }
        public SessionType Type { get; set; }
        public SessionPhase Phase { get; set; }
        
        public DateTime RangeStartTimeUTC { get; set; }
        public DateTime RangeEndTimeUTC { get; set; }
        public DateTime CutoffTimeUTC { get; set; }
        
        public double RangeHigh { get; set; }
        public double RangeLow { get; set; }
        public bool IsRangeLocked { get; set; }
        
        // Tracking whether orders have been placed for this slot
        public bool LongOrderPlaced { get; set; }
        public bool ShortOrderPlaced { get; set; }
        
        public string SessionKey { get; set; }
        
        public SlotState(int index)
        {
            SlotIndex = index;
            Phase = SessionPhase.Waiting;
            IsRangeLocked = false;
            RangeHigh = double.MinValue;  // must match Reset() sentinels so UpdateRange() works from tick 1
            RangeLow  = double.MaxValue;  // real prices never satisfy (low < MaxValue) until set correctly
        }
        
        public void Reset()
        {
            Phase = SessionPhase.Waiting;
            RangeHigh = double.MinValue;
            RangeLow = double.MaxValue;
            IsRangeLocked = false;
            LongOrderPlaced = false;
            ShortOrderPlaced = false;
        }
        
        public void UpdateRange(double high, double low)
        {
            if (high > RangeHigh || RangeHigh == double.MinValue) RangeHigh = high;
            if (low < RangeLow || RangeLow == double.MaxValue) RangeLow = low;
        }
    }
    
    public static class SessionLogic
    {
        public static void UpdateSlotPhase(SlotState slot, DateTime time0UTC)
        {
            if (!slot.IsEnabled) return;
            
            if (time0UTC < slot.RangeStartTimeUTC)
            {
                slot.Phase = SessionPhase.Waiting;
            }
            else if (time0UTC >= slot.RangeStartTimeUTC && time0UTC < slot.RangeEndTimeUTC)
            {
                slot.Phase = SessionPhase.RangeForming;
            }
            else if (time0UTC >= slot.RangeEndTimeUTC && time0UTC < slot.CutoffTimeUTC)
            {
                slot.Phase = SessionPhase.TradingWindow;
            }
            else if (time0UTC >= slot.CutoffTimeUTC)
            {
                slot.Phase = SessionPhase.Closed;
            }
        }
    }
}
