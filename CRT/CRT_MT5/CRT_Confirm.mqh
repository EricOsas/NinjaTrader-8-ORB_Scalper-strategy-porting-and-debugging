#ifndef CRT_CONFIRM_MQH
#define CRT_CONFIRM_MQH

//======================================================================
// CRT_Confirm.mqh — LTF confirmation engine (CISD + IFVG).
//
// Direct port of CRT_Confirm.cs (C#) to MQL5. Exact same algorithm:
//
// CISD (Change In State of Delivery):
//   Short: find the up-close run immediately before the current candle;
//     reference open = SingleCandle → last up-close candle's open;
//                      ConsecutiveSequence → first up-close candle's open.
//     CISD fires when current candle's CLOSE < referenceOpen.
//   Long: mirror (down-close run; close > referenceOpen).
//
// IFVG (Inverted Fair Value Gap):
//   A 3-candle FVG (born at/after the sweep) whose FAR boundary is
//   fully closed through by the current candle.
//   Short: a BULLISH FVG (gap up) closed below its Far (c1.H of gap).
//   Long : a BEARISH FVG (gap down) closed above its Far (c1.L of gap).
//
// One CrtConfirmState per live setup. Reset via CrtConfirmReset().
//======================================================================

#include "CRT_Globals.mqh"

//----------------------------------------------------------------------
// Per-setup LTF bar window (rolling, capped at CRT_CONF_BAR_CAP bars)
//----------------------------------------------------------------------
#define CRT_CONF_BAR_CAP 600

struct CrtConfirmBar
{
    datetime t;
    double   o, h, l, c;
};

struct CrtConfirmState
{
    CrtConfirmBar bars[CRT_CONF_BAR_CAP];
    int           barCount;

    // FVG registry — we store up to CRT_MAX_FVGS in the per-setup CrtSetup,
    // but the confirm engine reads them from the setup's fvgs[] array directly.

    // Latest Evaluate() result
    bool   confirmed;
    double confirmClose;
    bool   cisdOk;
    bool   ifvgOk;
};

void CrtConfirmReset(CrtConfirmState &st)
{
    st.barCount    = 0;
    st.confirmed   = false;
    st.confirmClose= 0.0;
    st.cisdOk      = false;
    st.ifvgOk      = false;
}

// Push one closed LTF bar.
void CrtConfirmAddBar(CrtConfirmState &st, datetime t, double o, double h, double l, double c)
{
    if (st.barCount < CRT_CONF_BAR_CAP)
    {
        st.bars[st.barCount].t = t;
        st.bars[st.barCount].o = o;
        st.bars[st.barCount].h = h;
        st.bars[st.barCount].l = l;
        st.bars[st.barCount].c = c;
        st.barCount++;
    }
    else
    {
        // Shift left to drop oldest bar
        for (int i = 1; i < CRT_CONF_BAR_CAP; i++)
            st.bars[i - 1] = st.bars[i];
        st.bars[CRT_CONF_BAR_CAP - 1].t = t;
        st.bars[CRT_CONF_BAR_CAP - 1].o = o;
        st.bars[CRT_CONF_BAR_CAP - 1].h = h;
        st.bars[CRT_CONF_BAR_CAP - 1].l = l;
        st.bars[CRT_CONF_BAR_CAP - 1].c = c;
    }
}

//----------------------------------------------------------------------
// Track a newly completed 3-candle FVG on the confirm bar window and
// store it into the CrtSetup's fvgs[] array.
// Called by CrtConfirmAddBar after adding the latest bar.
//----------------------------------------------------------------------
void CrtConfirmTrackFvg(CrtConfirmState &st, CrtSetup &setup)
{
    int n = st.barCount;
    if (n < 3 || setup.nFvgs >= CRT_MAX_FVGS) return;

    CrtConfirmBar c1 = st.bars[n - 3];
    CrtConfirmBar c3 = st.bars[n - 1];

    if (c1.h < c3.l)
    {
        // Bullish FVG: gap up [c1.h (far), c3.l (near)]
        setup.fvgs[setup.nFvgs].bornTime  = c3.t;
        setup.fvgs[setup.nFvgs].farBound  = c1.h;
        setup.fvgs[setup.nFvgs].nearBound = c3.l;
        setup.fvgs[setup.nFvgs].bullish   = true;
        setup.fvgs[setup.nFvgs].inverted  = false;
        setup.nFvgs++;
    }
    else if (c1.l > c3.h)
    {
        // Bearish FVG: gap down [c1.l (far), c3.h (near)]
        setup.fvgs[setup.nFvgs].bornTime  = c3.t;
        setup.fvgs[setup.nFvgs].farBound  = c1.l;
        setup.fvgs[setup.nFvgs].nearBound = c3.h;
        setup.fvgs[setup.nFvgs].bullish   = false;
        setup.fvgs[setup.nFvgs].inverted  = false;
        setup.nFvgs++;
    }
}

//----------------------------------------------------------------------
// CISD detection.
//----------------------------------------------------------------------
bool CrtDetectCisd(CrtConfirmState &st, ENUM_CRT_BIAS bias,
                   ENUM_CRT_CISD_REF refMode, double &refOpenOut)
{
    refOpenOut = 0.0;
    int n = st.barCount;
    if (n < 2) return false;

    CrtConfirmBar last = st.bars[n - 1]; // prospective reversal candle

    if (bias == CRT_BIAS_SHORT)
    {
        // Need an up-close candle immediately before 'last'
        int i = n - 2;
        if (i < 0 || st.bars[i].c <= st.bars[i].o) return false;
        int runEnd   = i;
        int runStart = i;
        while (runStart - 1 >= 0 && st.bars[runStart - 1].c > st.bars[runStart - 1].o)
            runStart--;
        refOpenOut = (refMode == CRT_CISD_SEQUENCE) ? st.bars[runStart].o : st.bars[runEnd].o;
        return last.c < refOpenOut;
    }
    else if (bias == CRT_BIAS_LONG)
    {
        int i = n - 2;
        if (i < 0 || st.bars[i].c >= st.bars[i].o) return false;
        int runEnd   = i;
        int runStart = i;
        while (runStart - 1 >= 0 && st.bars[runStart - 1].c < st.bars[runStart - 1].o)
            runStart--;
        refOpenOut = (refMode == CRT_CISD_SEQUENCE) ? st.bars[runStart].o : st.bars[runEnd].o;
        return last.c > refOpenOut;
    }
    return false;
}

//----------------------------------------------------------------------
// IFVG detection — reads FVGs from the setup's fvgs[] array.
//----------------------------------------------------------------------
bool CrtDetectIfvg(CrtConfirmState &st, CrtSetup &setup, ENUM_CRT_BIAS bias)
{
    int n = st.barCount;
    if (n < 1) return false;
    CrtConfirmBar last = st.bars[n - 1];

    for (int i = 0; i < setup.nFvgs; i++)
    {
        if (setup.fvgs[i].inverted) continue;
        if (setup.fvgs[i].bornTime < setup.sweepStartTime) continue; // only post-sweep FVGs

        if (bias == CRT_BIAS_SHORT && setup.fvgs[i].bullish && last.c < setup.fvgs[i].farBound)
        {
            setup.fvgs[i].inverted = true;
            return true;
        }
        if (bias == CRT_BIAS_LONG && !setup.fvgs[i].bullish && last.c > setup.fvgs[i].farBound)
        {
            setup.fvgs[i].inverted = true;
            return true;
        }
    }
    return false;
}

//----------------------------------------------------------------------
// Evaluate the configured trigger model on the LATEST bar in st.
// Must be called AFTER CrtConfirmAddBar() + CrtConfirmTrackFvg().
// Returns true if the trigger fires.
//----------------------------------------------------------------------
bool CrtConfirmEvaluate(CrtConfirmState &st, CrtSetup &setup,
                        ENUM_CRT_BIAS bias, ENUM_CRT_TRIGGER model,
                        ENUM_CRT_CISD_REF refMode)
{
    st.confirmed    = false;
    st.cisdOk       = false;
    st.ifvgOk       = false;
    st.confirmClose = 0.0;
    if (bias == CRT_BIAS_NONE || st.barCount < 1) return false;

    double refOpen;
    st.cisdOk = CrtDetectCisd(st, bias, refMode, refOpen);
    st.ifvgOk = CrtDetectIfvg(st, setup, bias);

    switch (model)
    {
        case CRT_TRIGGER_CISD:      st.confirmed = st.cisdOk; break;
        case CRT_TRIGGER_IFVG:      st.confirmed = st.ifvgOk; break;
        case CRT_TRIGGER_CISD_IFVG: st.confirmed = (st.cisdOk && st.ifvgOk); break;
        default:                    st.confirmed = st.cisdOk; break;
    }

    if (st.confirmed)
        st.confirmClose = st.bars[st.barCount - 1].c;

    return st.confirmed;
}

//----------------------------------------------------------------------
// Convenience: push a bar from iTime/iOpen/etc., track FVG, evaluate.
// Returns true if the trigger fires.
//----------------------------------------------------------------------
bool CrtConfirmPushAndEvaluate(CrtConfirmState &st, CrtSetup &setup,
                               datetime t, double o, double h, double l, double c,
                               ENUM_CRT_TRIGGER model, ENUM_CRT_CISD_REF refMode)
{
    CrtConfirmAddBar(st, t, o, h, l, c);
    CrtConfirmTrackFvg(st, setup);
    return CrtConfirmEvaluate(st, setup, setup.bias, model, refMode);
}

#endif // CRT_CONFIRM_MQH
