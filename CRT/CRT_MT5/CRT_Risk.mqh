#ifndef CRT_RISK_MQH
#define CRT_RISK_MQH

//======================================================================
// CRT_Risk.mqh — Position sizing for CRT EA.
// Lifted and simplified from ORB risk engine. Sizes by risk% of the
// configured capital source. Hard lot caps prevent oversizing.
//======================================================================

#include "CRT_Globals.mqh"

// Inputs declared in CRT_EA.mq5
extern ENUM_CRT_ACC_MODE Inp_AccMode;
extern double            Inp_CustomCapital;
extern double            Inp_RiskPct;       // effective risk % (resolved from preset or custom)
extern double            Inp_MaxLotsGlobal;

//----------------------------------------------------------------------
// Resolved capital for risk calculations.
//----------------------------------------------------------------------
double CrtRiskCapital()
{
    switch (Inp_AccMode)
    {
        case CRT_ACC_EQUITY:  return AccountInfoDouble(ACCOUNT_EQUITY);
        case CRT_ACC_CUSTOM:  return (Inp_CustomCapital > 0.0) ? Inp_CustomCapital
                                                                : AccountInfoDouble(ACCOUNT_BALANCE);
        case CRT_ACC_BALANCE:
        default:              return AccountInfoDouble(ACCOUNT_BALANCE);
    }
}

//----------------------------------------------------------------------
// Lot size for a given SL distance (in price units) and risk %.
// Returns the largest conforming lot size rounded to the broker step,
// capped at Inp_MaxLotsGlobal and broker max.
//----------------------------------------------------------------------
double CrtCalcLots(double slDistancePrice, double riskPct)
{
    if (slDistancePrice <= 0.0 || riskPct <= 0.0) return 0.0;

    double capital    = CrtRiskCapital();
    double riskAmount = capital * riskPct / 100.0;

    double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

    double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if (lotStep <= 0.0) lotStep = 0.01;

    // Risk per lot = (slDistancePrice / tickSize) * tickValue
    double riskPerLot = (slDistancePrice / tickSize) * tickValue;
    if (riskPerLot <= 0.0) return 0.0;

    double rawLots = riskAmount / riskPerLot;

    // Floor to broker lot step
    double lots = MathFloor(rawLots / lotStep) * lotStep;
    lots = MathMax(lots, minLot);
    lots = MathMin(lots, maxLot);
    if (Inp_MaxLotsGlobal > 0.0) lots = MathMin(lots, Inp_MaxLotsGlobal);

    return lots;
}

//----------------------------------------------------------------------
// Quick margin check: can we afford the computed lot size?
// Returns the adjusted (affordable) lot if margin is tight, or 0 if
// no lot is affordable at all.
//----------------------------------------------------------------------
double CrtAffordableLots(double lots)
{
    if (lots <= 0.0) return 0.0;
    double margin;
    if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
        return 0.0;
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if (margin <= freeMargin) return lots;

    // Try to find the largest lot that fits.
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    while (lots >= minLot)
    {
        lots -= lotStep;
        lots = MathMax(lots, 0.0);
        if (lots < minLot) return 0.0;
        if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots,
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
            return 0.0;
        if (margin <= freeMargin) return lots;
    }
    return 0.0;
}

// Normalise a price to symbol tick size.
double CrtRound(double price)
{
    double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tick <= 0.0) return price;
    return MathRound(price / tick) * tick;
}

// Minimum stop distance (price units) required by the broker.
double CrtMinStopPx()
{
    long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    return (double)stopsLevel * point;
}

#endif // CRT_RISK_MQH
