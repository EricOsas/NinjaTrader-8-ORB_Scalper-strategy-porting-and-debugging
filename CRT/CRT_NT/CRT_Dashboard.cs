using System;
using System.Collections.Generic;
using NinjaTrader.Gui.Chart;
using NinjaTrader.NinjaScript.Strategies;
using SharpDX;
using SharpDX.Direct2D1;
using SharpDX.DirectWrite;

namespace NinjaTrader.NinjaScript.Strategies.CRT_NT
{
    // Snapshot of what the dashboard shows (published each pulse).
    public struct CrtDashState
    {
        // Header / session
        public string SlotLabel;     // "Intraday 1H" / "Daily" ...
        public string NYClock;
        public string Phase;         // WaitC1 / C2Watch / ...
        public double CurrentBalance;

        // CRT structure
        public string Bias;          // LONG / SHORT / --
        public double C1High, C1Low, C1EQ;
        public string Sweep;         // High / Low / none
        public string TriggerModel;  // CISD / IFVG / CISD+IFVG
        public string CisdStatus;    // watch / armed
        public string IfvgStatus;    // watch / armed
        public string EntryInfo;     // "market @ 5123.5" / "limit @ 5120.0" / "--"

        // Position
        public bool InTrade;
        public string TradeDir;
        public double EntryPrice, StopLoss, TakeProfit;
        public int ContractCount;
        public double LiveR;

        // Instrument / news
        public string InstrumentName;
        public double TickSize;
        public bool NewsBlackoutActive;
        public string NextNewsEvent;
    }

    //======================================================================
    // CRT_Dashboard — liquid-glass Direct2D panel (movable + collapsible).
    // Reuses the ORB_NT rendering approach; publish state each pulse, render
    // from the strategy's OnRender override.
    //======================================================================
    public static class CRT_Dashboard
    {
        private class PanelState
        {
            public CrtDashState S;
            public bool HasState;
            public float OffX, OffY;
            public bool Collapsed;
            public bool Dragging;
            public float DragDX, DragDY;
            public RectangleF PanelRect, HeaderRect, BtnRect;
        }

        private static readonly Dictionary<Strategy, PanelState> panels = new Dictionary<Strategy, PanelState>();
        private static readonly object sync = new object();

        private static PanelState Get(Strategy s)
        {
            if (!panels.TryGetValue(s, out PanelState p)) { p = new PanelState(); panels[s] = p; }
            return p;
        }

        public static void Publish(Strategy s, CrtDashState st)
        {
            lock (sync) { var p = Get(s); p.S = st; p.HasState = true; }
        }

        public static void Clear(Strategy s) { lock (sync) { panels.Remove(s); } }

        // ── mouse interaction ──
        public static bool OnMouseDown(Strategy s, float x, float y)
        {
            lock (sync)
            {
                var p = Get(s);
                if (!p.HasState) return false;
                if (Contains(p.BtnRect, x, y)) { p.Collapsed = !p.Collapsed; return true; }
                if (Contains(p.HeaderRect, x, y)) { p.Dragging = true; p.DragDX = x - p.PanelRect.X; p.DragDY = y - p.PanelRect.Y; return true; }
                return false;
            }
        }
        public static bool OnMouseMove(Strategy s, float x, float y)
        {
            lock (sync)
            {
                var p = Get(s);
                if (!p.Dragging) return false;
                p.OffX += (x - p.DragDX) - p.PanelRect.X;
                p.OffY += (y - p.DragDY) - p.PanelRect.Y;
                return true;
            }
        }
        public static bool OnMouseUp(Strategy s)
        {
            lock (sync) { var p = Get(s); if (!p.Dragging) return false; p.Dragging = false; return true; }
        }

        private static bool Contains(RectangleF r, float x, float y)
            => x >= r.X && x <= r.X + r.Width && y >= r.Y && y <= r.Y + r.Height;

        // ── palette ──
        private static readonly Color4 GlassBase   = Rgba(15, 19, 28, 0.94f);
        private static readonly Color4 GlassSheen  = Rgba(255, 255, 255, 0.07f);
        private static readonly Color4 GlassSheen2 = Rgba(255, 255, 255, 0.02f);
        private static readonly Color4 HairLine    = Rgba(255, 255, 255, 0.22f);
        private static readonly Color4 TxtPrimary  = Rgba(240, 244, 250, 0.96f);
        private static readonly Color4 TxtMuted    = Rgba(165, 178, 200, 0.85f);
        private static readonly Color4 TxtFaint    = Rgba(140, 152, 175, 0.65f);
        private static readonly Color4 AccentBlue  = Rgba(95, 170, 255, 1.0f);
        private static readonly Color4 AccentGreen = Rgba(88, 214, 141, 1.0f);
        private static readonly Color4 AccentRed   = Rgba(255, 105, 97, 1.0f);
        private static readonly Color4 AccentGold  = Rgba(230, 195, 120, 1.0f);

        private static Color4 Rgba(byte r, byte g, byte b, float a) => new Color4(r / 255f, g / 255f, b / 255f, a);

        private const float PanelW = 320f, Pad = 14f, Radius = 18f, LineH = 19f, SectionGap = 10f, HeaderH = 60f;

        public static void Render(Strategy strategy, ChartControl chartControl, RenderTarget rt)
        {
            PanelState p; CrtDashState s; bool collapsed; float offX, offY;
            lock (sync)
            {
                p = Get(strategy);
                if (!p.HasState) return;
                s = p.S; collapsed = p.Collapsed; offX = p.OffX; offY = p.OffY;
            }

            float height;
            if (collapsed) height = HeaderH + 6f;
            else
            {
                int bodyLines = 1        // balance
                              + 4        // C1 high/low/eq/sweep
                              + 3        // trigger/cisd/ifvg
                              + 1        // entry
                              + (s.InTrade ? 3 : 1)
                              + 2;       // footer
                height = HeaderH + bodyLines * LineH + 4 * (SectionGap * 1.4f) + Pad * 2 + 6f;
            }

            float left = (float)chartControl.CanvasRight - 12f - PanelW + offX;
            float top = 12f + offY;

            var panel = new RoundedRectangle { Rect = new RectangleF(left, top, PanelW, height), RadiusX = Radius, RadiusY = Radius };

            using (var dw = new SharpDX.DirectWrite.Factory())
            using (var baseBrush = new SolidColorBrush(rt, GlassBase))
            {
                rt.FillRoundedRectangle(panel, baseBrush);
                using (var sheen = new LinearGradientBrush(rt,
                    new LinearGradientBrushProperties { StartPoint = new Vector2(left, top), EndPoint = new Vector2(left, top + height * 0.5f) },
                    new GradientStopCollection(rt, new[]
                    {
                        new GradientStop { Position = 0f, Color = GlassSheen },
                        new GradientStop { Position = 1f, Color = GlassSheen2 }
                    })))
                { rt.FillRoundedRectangle(panel, sheen); }

                using (var border = new SolidColorBrush(rt, HairLine))
                    rt.DrawRoundedRectangle(panel, border, 1.2f);

                using (var fHead = new TextFormat(dw, "Segoe UI Semibold", FontWeight.SemiBold, FontStyle.Normal, 14f))
                using (var fMono = new TextFormat(dw, "Consolas", FontWeight.Normal, FontStyle.Normal, 12.5f))
                using (var fMonoB = new TextFormat(dw, "Consolas", FontWeight.Bold, FontStyle.Normal, 12.5f))
                using (var fHero = new TextFormat(dw, "Segoe UI", FontWeight.Light, FontStyle.Normal, 26f))
                using (var fSmall = new TextFormat(dw, "Segoe UI", FontWeight.Normal, FontStyle.Normal, 10.5f))
                {
                    float x = left + Pad, w = PanelW - Pad * 2, y = top + 10f;

                    var btn = new RectangleF(x, top + 12f, 14f, 14f);
                    using (var dot = new SolidColorBrush(rt, collapsed ? AccentGold : AccentBlue))
                        rt.FillEllipse(new Ellipse(new Vector2(btn.X + 7f, btn.Y + 7f), 6f, 6f), dot);

                    DrawText(rt, dw, "CRT · " + s.SlotLabel, fHead, x + 22f, top + 8f, w - 130f, TxtPrimary);
                    Color4 pill = s.InTrade ? AccentGreen : s.NewsBlackoutActive ? AccentRed : AccentBlue;
                    DrawText(rt, dw, s.Phase, fSmall, x + 22f, top + 32f, w - 130f, pill);
                    DrawTextRight(rt, dw, "NY TIME", fSmall, x, top + 8f, w, TxtFaint);
                    DrawTextRight(rt, dw, s.NYClock, fHero, x, top + 20f, w, AccentBlue);

                    y = top + HeaderH;
                    lock (sync)
                    {
                        p.PanelRect = new RectangleF(left, top, PanelW, height);
                        p.HeaderRect = new RectangleF(left, top, PanelW, HeaderH);
                        p.BtnRect = new RectangleF(btn.X - 5f, btn.Y - 5f, btn.Width + 10f, btn.Height + 10f);
                    }
                    if (collapsed) return;

                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "Balance", string.Format("{0:C0}", s.CurrentBalance), TxtPrimary);
                    y += SectionGap * 0.6f; DrawDivider(rt, x, y, w); y += SectionGap * 0.8f;

                    // ── CRT structure ──
                    Color4 biasClr = s.Bias == "LONG" ? AccentGreen : s.Bias == "SHORT" ? AccentRed : TxtFaint;
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "Bias", string.IsNullOrEmpty(s.Bias) ? "--" : s.Bias, biasClr);
                    if (s.C1High > 0 && s.C1Low > 0)
                    {
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "C1 High", string.Format("{0:F2}", s.C1High), AccentGreen);
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "C1 Low", string.Format("{0:F2}", s.C1Low), AccentRed);
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "C1 EQ (TP)", string.Format("{0:F2}", s.C1EQ), AccentGold);
                    }
                    else
                    {
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "C1 High", "forming…", TxtFaint);
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "C1 Low", "forming…", TxtFaint);
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "C1 EQ (TP)", "--", TxtFaint);
                    }
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "Sweep", string.IsNullOrEmpty(s.Sweep) ? "none" : s.Sweep, AccentBlue);
                    y += SectionGap * 0.6f; DrawDivider(rt, x, y, w); y += SectionGap * 0.8f;

                    // ── triggers ──
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "Model", s.TriggerModel, TxtMuted);
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "CISD", s.CisdStatus, s.CisdStatus == "armed" ? AccentGreen : TxtFaint);
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "IFVG", s.IfvgStatus, s.IfvgStatus == "armed" ? AccentGreen : TxtFaint);
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, "Entry", string.IsNullOrEmpty(s.EntryInfo) ? "--" : s.EntryInfo, TxtPrimary);
                    y += SectionGap * 0.6f; DrawDivider(rt, x, y, w); y += SectionGap * 0.8f;

                    // ── position ──
                    if (s.InTrade)
                    {
                        Color4 dirClr = s.TradeDir == "LONG" ? AccentGreen : AccentRed;
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "Position", string.Format("{0}  x{1}", s.TradeDir, s.ContractCount), dirClr);
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "Entry->SL/TP", string.Format("{0:F2} -> {1:F2} / {2:F2}", s.EntryPrice, s.StopLoss, s.TakeProfit), TxtPrimary);
                        y = Row(rt, dw, fMono, fMonoB, x, y, w, "Live R", string.Format("{0:F2}R", s.LiveR), s.LiveR >= 0 ? AccentGreen : AccentRed);
                    }
                    else y = Row(rt, dw, fMono, fMonoB, x, y, w, "Position", "flat", TxtFaint);

                    y += SectionGap * 0.6f; DrawDivider(rt, x, y, w); y += SectionGap * 0.8f;

                    y = Row(rt, dw, fMono, fMonoB, x, y, w, s.InstrumentName, string.Format("tick {0}", s.TickSize), TxtFaint);
                    y = Row(rt, dw, fMono, fMonoB, x, y, w, s.NewsBlackoutActive ? "News (blk)" : "News", Truncate(s.NextNewsEvent, 30), s.NewsBlackoutActive ? AccentRed : TxtMuted);
                }
            }
        }

        // ── helpers ──
        private static float Row(RenderTarget rt, SharpDX.DirectWrite.Factory dw, TextFormat label, TextFormat value,
            float x, float y, float w, string k, string v, Color4 vClr)
        {
            DrawText(rt, dw, k, label, x, y, w * 0.5f, TxtFaint);
            DrawTextRight(rt, dw, v, value, x, y, w, vClr);
            return y + LineH;
        }

        private static void DrawText(RenderTarget rt, SharpDX.DirectWrite.Factory dw, string text, TextFormat fmt, float x, float y, float w, Color4 clr)
        {
            if (string.IsNullOrEmpty(text)) return;
            using (var layout = new TextLayout(dw, text, fmt, w, LineH + 24f))
            using (var b = new SolidColorBrush(rt, clr))
                rt.DrawTextLayout(new Vector2(x, y), layout, b);
        }

        private static void DrawTextRight(RenderTarget rt, SharpDX.DirectWrite.Factory dw, string text, TextFormat fmt, float x, float y, float w, Color4 clr)
        {
            if (string.IsNullOrEmpty(text)) return;
            using (var layout = new TextLayout(dw, text, fmt, w, LineH + 24f))
            {
                layout.TextAlignment = TextAlignment.Trailing;
                using (var b = new SolidColorBrush(rt, clr))
                    rt.DrawTextLayout(new Vector2(x, y), layout, b);
            }
        }

        private static void DrawDivider(RenderTarget rt, float x, float y, float w)
        {
            using (var b = new SolidColorBrush(rt, HairLine))
                rt.DrawLine(new Vector2(x, y), new Vector2(x + w, y), b, 0.6f);
        }

        private static string Truncate(string s, int n)
            => string.IsNullOrEmpty(s) ? "--" : (s.Length <= n ? s : s.Substring(0, n - 1) + "…");
    }
}
