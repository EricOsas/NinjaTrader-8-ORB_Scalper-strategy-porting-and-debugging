using System;
using System.Windows.Media;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public static class ORB_Visuals
    {
        private const double MIN_WIDTH_BARS = 3.0; // Minimum visible width for range box when resolved

        //----------------------------------------------------------------------
        // Draw / update the range formation box
        //----------------------------------------------------------------------
        public static void DrawRangeBox(Strategy strategy, string tag, DateTime startBar, DateTime endBar,
            double rangeHigh, double rangeLow, Brush outlineBrush, Brush fillBrush, bool isLocked)
        {
            if (strategy.State == State.Historical || strategy.State == State.Undefined) return;
            if (rangeHigh <= rangeLow) return;

            // Calling Draw.Rectangle with the same tag updates the existing object
            Draw.Rectangle(strategy, tag, false, startBar, rangeHigh, endBar, rangeLow,
                outlineBrush, fillBrush, 20 /* opacity 0-100 */);
        }

        //----------------------------------------------------------------------
        // Draw entry / execution horizontal line
        //----------------------------------------------------------------------
        public static void DrawExecLine(Strategy strategy, string tag, DateTime startBar, DateTime endBar,
            double price, Brush lineBrush, DashStyleHelper dashStyle = DashStyleHelper.Solid, int width = 1)
        {
            if (strategy.State == State.Historical) return;
            Draw.Line(strategy, tag, false, startBar, price, endBar, price, lineBrush, dashStyle, width);
        }

        //----------------------------------------------------------------------
        // Draw a single text label on the chart
        //----------------------------------------------------------------------
        public static void DrawLabel(Strategy strategy, string tag, DateTime barTime, double price, string text, Brush textBrush)
        {
            if (strategy.State == State.Historical) return;
            Draw.Text(strategy, tag, text, 0, price, textBrush);
        }

        //----------------------------------------------------------------------
        // Remove a specific visual object
        //----------------------------------------------------------------------
        public static void RemoveObject(Strategy strategy, string tag)
        {
            strategy.RemoveDrawObject(tag);
        }

        //----------------------------------------------------------------------
        // Clear all ORB visuals (called on session reset)
        //----------------------------------------------------------------------
        public static void ClearAllVisuals(Strategy strategy, string sessionPrefix)
        {
            // Remove all objects whose tag starts with the session prefix
            // NinjaScript doesn't expose a direct "delete by prefix" API but we can
            // enumerate common tags we use and remove them explicitly.
            string[] suffixes = new[] { "_RangeBox", "_LevelHigh", "_LevelLow", "_LongEntry", "_ShortEntry", "_SL", "_TP" };
            foreach (string suffix in suffixes)
            {
                strategy.RemoveDrawObject(sessionPrefix + suffix);
            }
        }

        //----------------------------------------------------------------------
        // Convenience: draw a horizontal level line (e.g. range high/low)
        //----------------------------------------------------------------------
        public static void DrawHLine(Strategy strategy, string tag, double price, Brush lineBrush, DashStyleHelper dashStyle = DashStyleHelper.Dash)
        {
            if (strategy.State == State.Historical) return;
            // Extend from current bar minus 10 bars (visual anchor) to far right
            Draw.HorizontalLine(strategy, tag, price, lineBrush, dashStyle, 1);
        }
    }
}
