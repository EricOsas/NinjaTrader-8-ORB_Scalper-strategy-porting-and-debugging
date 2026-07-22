//+------------------------------------------------------------------+
//|                                                   DTR_Engine.mqh |
//| Core Execution Engine: Scanner, Risk, and Trade Placement        |
//+------------------------------------------------------------------+
#ifndef DTR_ENGINE_MQH
#define DTR_ENGINE_MQH

#include <Trade\Trade.mqh>
#include "DTR_Core.mqh"


//+------------------------------------------------------------------+
//| STRUCTS & GLOBALS                                                |
//+------------------------------------------------------------------+
struct FVGInfo
{
    datetime          t1;
    datetime          t2;
    datetime          t3;
    double            c1Ext;
    double            c3Ext;
    double            c2c3Extreme;
    datetime          c2c3ExtremeTime;
    double            clusterExtreme;
    bool              inverted;
    datetime          invTime;
    bool              invalidInv;
    bool              stale;
    bool              superseded;
    bool              isBullish;
};

struct ManipulationLeg
{
    bool     active;
    bool     isUpsideSweep; 
    double   extremePrice;
    datetime extremeTime;
    
    // CISD tracking
    bool     cisdActive;
    double   cisdLevel;
    datetime cisdTime;
    datetime lastOpposingCandleTime;
    
    // FVG Memory
    FVGInfo  fvgs[50];
    int      fvgCount;
};

ManipulationLeg g_londonLeg;
ManipulationLeg g_nyLeg;

struct PendingRetest
{
    bool     active;
    bool     isLong;
    double   entryPrice;
    double   slPrice;
    double   tpPrice;
    double   volume;
    datetime expiryTime;
    
    int      fvgIndex;
    datetime c3Time;
};

PendingRetest g_activeRetest;

struct DTR_TradePosition
{
    ulong  ticket;
    bool   isLong;
    double entryPrice;
    double tpPrice;
    double slPrice;
    double volume;
    bool   beTriggered;
};

DTR_TradePosition g_activeTrades[];
int g_activeTradesCount = 0;

CTrade g_trade;

//+------------------------------------------------------------------+
//| RISK LOGIC                                                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePoints)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (Inp_Risk_Percent / 100.0);
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue == 0 || tickSize == 0 || slDistancePoints <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    double lossPerLot = slDistancePoints * (tickValue / tickSize);
    if(lossPerLot <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    double lots = riskAmount / lossPerLot;
    if(lots > Inp_Max_Lots_Global) lots = Inp_Max_Lots_Global;
    
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lots = MathRound(lots / step) * step;
    
    double minLots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(lots < minLots) lots = minLots;
    
    return lots;
}

double ResolveSL(bool isLong, double entryPrice, double tpPrice, double fixedSLPrice)
{
    if(Inp_SL_Mode == SL_FIXED) return fixedSLPrice;

    double fixedSlDist = MathAbs(entryPrice - fixedSLPrice);
    double tpDist = MathAbs(tpPrice - entryPrice);
    
    if(fixedSlDist <= 0) return fixedSLPrice;
    
    double naturalRR = tpDist / fixedSlDist;
    
    if(naturalRR >= Inp_MinRR)
    {
        return fixedSLPrice;
    }
    else
    {
        double requiredSlDist = tpDist / Inp_MinRR;
        double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double minSanityPriceDist = Inp_Min_SL_Sanity_Distance * pointSize;
        
        if(requiredSlDist < minSanityPriceDist)
        {
            PrintFormat("Dynamic SL calculation (%.5f) is too tight (< %d pts). Trade skipped.", requiredSlDist, Inp_Min_SL_Sanity_Distance);
            return -1.0; 
        }
        else
        {
            return isLong ? (entryPrice - requiredSlDist) : (entryPrice + requiredSlDist);
        }
    }
}

void CheckBreakEvenTick(double currentBid, double currentAsk)
{
    for(int i=0; i<g_activeTradesCount; i++)
    {
        if(g_activeTrades[i].beTriggered) continue; 
        
        double currentPrice = g_activeTrades[i].isLong ? currentBid : currentAsk;
        double entryToTPDist = MathAbs(g_activeTrades[i].tpPrice - g_activeTrades[i].entryPrice);
        
        if(entryToTPDist <= 0) continue; 
        
        double currentDistInTradeDir = g_activeTrades[i].isLong ? 
                                       (currentPrice - g_activeTrades[i].entryPrice) : 
                                       (g_activeTrades[i].entryPrice - currentPrice);
                                       
        if(currentDistInTradeDir <= 0) continue; 
        
        double progressPercent = (currentDistInTradeDir / entryToTPDist) * 100.0;
        
        if(progressPercent >= Inp_BE_TriggerPercent)
        {
            double lockDist = entryToTPDist * (Inp_BE_LockPercent / 100.0);
            double newSL = g_activeTrades[i].isLong ? 
                           (g_activeTrades[i].entryPrice + lockDist) : 
                           (g_activeTrades[i].entryPrice - lockDist);
                           
            if(g_trade.PositionModify(g_activeTrades[i].ticket, newSL, g_activeTrades[i].tpPrice))
            {
                g_activeTrades[i].beTriggered = true;
                PrintFormat("Break-Even triggered for ticket %llu at %.2f%% progress.", g_activeTrades[i].ticket, progressPercent);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| EXECUTION HOOKS                                                  |
//+------------------------------------------------------------------+
void ExecuteIFVGEntry(bool isLong, double slPrice, double tpPrice)
{
    double entryPrice = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double finalSL = ResolveSL(isLong, entryPrice, tpPrice, slPrice);
    if(finalSL < 0) return;
    
    double lots = CalculateLotSize(MathAbs(entryPrice - finalSL) / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
    
    PrintFormat("Executing IFVG Market %s: Entry %.5f, SL %.5f, TP %.5f, Lots %.2f", 
                isLong ? "Buy" : "Sell", entryPrice, finalSL, tpPrice, lots);
                
    if(isLong)
    {
        if(g_trade.Buy(lots, _Symbol, entryPrice, finalSL, tpPrice, "IFVG Market Buy"))
        {
            int idx = g_activeTradesCount++;
            ArrayResize(g_activeTrades, g_activeTradesCount);
            g_activeTrades[idx].ticket = g_trade.ResultOrder();
            g_activeTrades[idx].isLong = true;
            g_activeTrades[idx].entryPrice = entryPrice;
            g_activeTrades[idx].slPrice = finalSL;
            g_activeTrades[idx].tpPrice = tpPrice;
            g_activeTrades[idx].volume = lots;
            g_activeTrades[idx].beTriggered = false;
        }
    }
    else
    {
        if(g_trade.Sell(lots, _Symbol, entryPrice, finalSL, tpPrice, "IFVG Market Sell"))
        {
            int idx = g_activeTradesCount++;
            ArrayResize(g_activeTrades, g_activeTradesCount);
            g_activeTrades[idx].ticket = g_trade.ResultOrder();
            g_activeTrades[idx].isLong = false;
            g_activeTrades[idx].entryPrice = entryPrice;
            g_activeTrades[idx].slPrice = finalSL;
            g_activeTrades[idx].tpPrice = tpPrice;
            g_activeTrades[idx].volume = lots;
            g_activeTrades[idx].beTriggered = false;
        }
    }
}

void SetupFVGRetestEntry(bool isLong, double limitPrice, double slPrice, double tpPrice, datetime expiry, int fvgIdx, datetime c3Time)
{
    double finalSL = ResolveSL(isLong, limitPrice, tpPrice, slPrice);
    if(finalSL < 0) return;
    
    double lots = CalculateLotSize(MathAbs(limitPrice - finalSL) / SymbolInfoDouble(_Symbol, SYMBOL_POINT));

    
    g_activeRetest.active = true;
    g_activeRetest.isLong = isLong;
    g_activeRetest.entryPrice = limitPrice;
    g_activeRetest.slPrice = finalSL;
    g_activeRetest.tpPrice = tpPrice;
    g_activeRetest.volume = lots;
    g_activeRetest.expiryTime = expiry;
    g_activeRetest.fvgIndex = fvgIdx;
    g_activeRetest.c3Time = c3Time;
    
    PrintFormat("Placed FVG Retest Virtual Limit %s: Entry %.5f, SL %.5f, TP %.5f", 
                isLong ? "Buy" : "Sell", limitPrice, finalSL, tpPrice);
}

void CheckPendingRetestFills(double currentBid, double currentAsk)
{
    if(!g_activeRetest.active) return;
    
    bool filled = false;
    
    if(g_activeRetest.isLong)
    {
        if(currentAsk <= g_activeRetest.entryPrice) filled = true;
    }
    else
    {
        if(currentBid >= g_activeRetest.entryPrice) filled = true;
    }
    
    if(filled)
    {
        Print("FVG Retest Filled!");
        
        if(g_activeRetest.isLong)
        {
            if(g_trade.Buy(g_activeRetest.volume, _Symbol, currentAsk, g_activeRetest.slPrice, g_activeRetest.tpPrice, "Virtual Retest Fill"))
            {
                int idx = g_activeTradesCount++;
                ArrayResize(g_activeTrades, g_activeTradesCount);
                g_activeTrades[idx].ticket = g_trade.ResultOrder();
                g_activeTrades[idx].isLong = true;
                g_activeTrades[idx].entryPrice = currentAsk;
                g_activeTrades[idx].slPrice = g_activeRetest.slPrice;
                g_activeTrades[idx].tpPrice = g_activeRetest.tpPrice;
                g_activeTrades[idx].volume = g_activeRetest.volume;
                g_activeTrades[idx].beTriggered = false;
            }
        }
        else
        {
            if(g_trade.Sell(g_activeRetest.volume, _Symbol, currentBid, g_activeRetest.slPrice, g_activeRetest.tpPrice, "Virtual Retest Fill"))
            {
                int idx = g_activeTradesCount++;
                ArrayResize(g_activeTrades, g_activeTradesCount);
                g_activeTrades[idx].ticket = g_trade.ResultOrder();
                g_activeTrades[idx].isLong = false;
                g_activeTrades[idx].entryPrice = currentBid;
                g_activeTrades[idx].slPrice = g_activeRetest.slPrice;
                g_activeTrades[idx].tpPrice = g_activeRetest.tpPrice;
                g_activeTrades[idx].volume = g_activeRetest.volume;
                g_activeTrades[idx].beTriggered = false;
            }
        }
        
        g_activeRetest.active = false;
    }
    else if(TimeCurrent() >= g_activeRetest.expiryTime)
    {
        Print("FVG Retest Expired.");
        g_activeRetest.active = false;
    }
}

//+------------------------------------------------------------------+
//| SCANNER ENGINE                                                   |
//+------------------------------------------------------------------+
void TickMandatoryScanner(datetime serverTime, MqlRates &m1Tick, ENUM_DTR_SESSION activeSession)
{
    if(g_priorDayLondonHigh > 0)
    {
        if(m1Tick.high > g_priorDayLondonHigh) g_sweptPriorLondon[0] = true;
        if(m1Tick.low  < g_priorDayLondonLow)  g_sweptPriorLondon[1] = true;
    }
    if(g_priorDayNYHigh > 0)
    {
        if(m1Tick.high > g_priorDayNYHigh) g_sweptPriorNY[0] = true;
        if(m1Tick.low  < g_priorDayNYLow)  g_sweptPriorNY[1] = true;
    }
    if(g_nyCandleA.time > 0)
    {
        if(m1Tick.high > g_nyCandleA.high) g_sweptAsia[0] = true;
        if(m1Tick.low  < g_nyCandleA.low)  g_sweptAsia[1] = true;
    }
    if(g_liveLondonRange.locked)
    {
        if(m1Tick.high > g_liveLondonRange.high) g_sweptCurrentLondon[0] = true;
        if(m1Tick.low  < g_liveLondonRange.low)  g_sweptCurrentLondon[1] = true;
    }
    if(g_priorTrueDay.time > 0)
    {
        if(m1Tick.high > g_priorTrueDay.high) g_sweptPriorTrueDay[0] = true;
        if(m1Tick.low  < g_priorTrueDay.low)  g_sweptPriorTrueDay[1] = true;
    }
    
    if(activeSession == SESSION_LONDON && g_liveLondonRange.locked && IsInTradingWindow(serverTime, SESSION_LONDON))
    {
        if(g_londonBias == BIAS_SHORT || g_londonBias == BIAS_NEUTRAL)
        {
            if(m1Tick.high > g_liveLondonRange.high)
            {
                if(!g_londonLeg.active || (g_londonLeg.active && !g_londonLeg.isUpsideSweep))
                {
                    g_londonLeg.active = true;
                    g_londonLeg.isUpsideSweep = true;
                    g_londonLeg.extremePrice = m1Tick.high;
                    g_londonLeg.extremeTime = serverTime;
                }
                else if(m1Tick.high > g_londonLeg.extremePrice)
                {
                    g_londonLeg.extremePrice = m1Tick.high;
                    g_londonLeg.extremeTime = serverTime;
                }
            }
        }
        if(g_londonBias == BIAS_LONG || g_londonBias == BIAS_NEUTRAL)
        {
            if(m1Tick.low < g_liveLondonRange.low)
            {
                if(!g_londonLeg.active || (g_londonLeg.active && g_londonLeg.isUpsideSweep))
                {
                    g_londonLeg.active = true;
                    g_londonLeg.isUpsideSweep = false;
                    g_londonLeg.extremePrice = m1Tick.low;
                    g_londonLeg.extremeTime = serverTime;
                }
                else if(m1Tick.low < g_londonLeg.extremePrice)
                {
                    g_londonLeg.extremePrice = m1Tick.low;
                    g_londonLeg.extremeTime = serverTime;
                }
            }
        }
    }
    
    if(activeSession == SESSION_NY && g_liveNYRange.locked && IsInTradingWindow(serverTime, SESSION_NY))
    {
        if(g_nyBias == BIAS_SHORT || g_nyBias == BIAS_NEUTRAL)
        {
            if(m1Tick.high > g_liveNYRange.high)
            {
                if(!g_nyLeg.active || (g_nyLeg.active && !g_nyLeg.isUpsideSweep))
                {
                    g_nyLeg.active = true;
                    g_nyLeg.isUpsideSweep = true;
                    g_nyLeg.extremePrice = m1Tick.high;
                    g_nyLeg.extremeTime = serverTime;
                }
                else if(m1Tick.high > g_nyLeg.extremePrice)
                {
                    g_nyLeg.extremePrice = m1Tick.high;
                    g_nyLeg.extremeTime = serverTime;
                }
            }
        }
        if(g_nyBias == BIAS_LONG || g_nyBias == BIAS_NEUTRAL)
        {
            if(m1Tick.low < g_liveNYRange.low)
            {
                if(!g_nyLeg.active || (g_nyLeg.active && g_nyLeg.isUpsideSweep))
                {
                    g_nyLeg.active = true;
                    g_nyLeg.isUpsideSweep = false;
                    g_nyLeg.extremePrice = m1Tick.low;
                    g_nyLeg.extremeTime = serverTime;
                }
                else if(m1Tick.low < g_nyLeg.extremePrice)
                {
                    g_nyLeg.extremePrice = m1Tick.low;
                    g_nyLeg.extremeTime = serverTime;
                }
            }
        }
    }
}

bool ShouldRunCachedScanner(datetime serverTime, ENUM_TIMEFRAMES tf)
{
    static datetime lastScannedBar[2] = {0, 0}; 
    datetime currentBarOpen = iTime(_Symbol, tf, 0);
    int idx = (tf == PERIOD_M1) ? 0 : 1;
    
    if(currentBarOpen > lastScannedBar[idx])
    {
        lastScannedBar[idx] = currentBarOpen;
        return true;
    }
    return false;
}

void ScanForFVGs(ManipulationLeg &leg, MqlRates &rates[], int copied)
{
    if(copied < 4) return;
    
    double c1High = rates[3].high;
    double c1Low = rates[3].low;
    double c3High = rates[1].high;
    double c3Low = rates[1].low;
    
    bool isBullishFVG = c1High < c3Low;
    bool isBearishFVG = c1Low > c3High;
    
    if(isBullishFVG || isBearishFVG)
    {
        bool exists = false;
        for(int i=0; i<leg.fvgCount; i++)
        {
            if(leg.fvgs[i].t2 == rates[2].time) { exists = true; break; }
        }
        if(!exists && leg.fvgCount < 50)
        {
            leg.fvgs[leg.fvgCount].t1 = rates[3].time;
            leg.fvgs[leg.fvgCount].t2 = rates[2].time;
            leg.fvgs[leg.fvgCount].t3 = rates[1].time;
            leg.fvgs[leg.fvgCount].isBullish = isBullishFVG;
            leg.fvgs[leg.fvgCount].c1Ext = isBullishFVG ? c1High : c1Low;
            leg.fvgs[leg.fvgCount].c3Ext = isBullishFVG ? c3Low : c3High;
            leg.fvgs[leg.fvgCount].inverted = false;
            leg.fvgCount++;
        }
    }
}

void CheckFVGInversions(ManipulationLeg &leg, MqlRates &rates[])
{
    double closePx = rates[1].close;
    
    for(int i=0; i<leg.fvgCount; i++)
    {
        if(leg.fvgs[i].inverted) continue;
        
        if(leg.fvgs[i].isBullish)
        {
            if(closePx < leg.fvgs[i].c1Ext)
            {
                leg.fvgs[i].inverted = true;
                leg.fvgs[i].invTime = rates[1].time;
            }
        }
        else 
        {
            if(closePx > leg.fvgs[i].c1Ext)
            {
                leg.fvgs[i].inverted = true;
                leg.fvgs[i].invTime = rates[1].time;
            }
        }
    }
}

void CheckCISD(ManipulationLeg &leg, MqlRates &rates[], int copied)
{
    if(leg.cisdActive || copied < 2) return;
    
    // Find CISD reference level (Mode A: Single Candle for now)
    // For upside sweep (Short bias), looking for bearish CISD (close below last bullish candle low)
    if(leg.isUpsideSweep)
    {
        if(rates[1].close < rates[1].open) // Current closed candle is bearish
        {
            // Find last bullish candle
            for(int i=2; i<copied; i++)
            {
                if(rates[i].close > rates[i].open)
                {
                    leg.cisdLevel = rates[i].low;
                    leg.lastOpposingCandleTime = rates[i].time;
                    break;
                }
            }
        }
        if(leg.cisdLevel > 0 && rates[1].close < leg.cisdLevel)
        {
            leg.cisdActive = true;
            leg.cisdTime = rates[1].time;
        }
    }
    // For downside sweep (Long bias), looking for bullish CISD (close above last bearish candle high)
    else
    {
        if(rates[1].close > rates[1].open) // Current closed candle is bullish
        {
            // Find last bearish candle
            for(int i=2; i<copied; i++)
            {
                if(rates[i].close < rates[i].open)
                {
                    leg.cisdLevel = rates[i].high;
                    leg.lastOpposingCandleTime = rates[i].time;
                    break;
                }
            }
        }
        if(leg.cisdLevel > 0 && rates[1].close > leg.cisdLevel)
        {
            leg.cisdActive = true;
            leg.cisdTime = rates[1].time;
        }
    }
}

void ProcessScannerForLeg(ENUM_DTR_SESSION activeSession, ManipulationLeg &leg, datetime serverTime, ENUM_TIMEFRAMES tf)
{
    if(!leg.active) return;
    
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, tf, 0, 50, rates);
    if(copied < 4) return;
    
    ScanForFVGs(leg, rates, copied);
    CheckFVGInversions(leg, rates);
    CheckCISD(leg, rates, copied);
    
    // IFVG Entry Trigger Logic
    if(Inp_Entry_Model == ENTRY_IFVG || Inp_Entry_Model == ENTRY_BOTH)
    {
        for(int i=0; i<leg.fvgCount; i++)
        {
            if(leg.fvgs[i].inverted && leg.fvgs[i].invTime == rates[1].time)
            {
                // Verify the FVG was opposing the intended direction
                if((leg.isUpsideSweep && leg.fvgs[i].isBullish) || (!leg.isUpsideSweep && !leg.fvgs[i].isBullish))
                {
                    double tpPrice = leg.isUpsideSweep ? ((activeSession == SESSION_LONDON) ? g_liveLondonRange.low : g_liveNYRange.low) 
                                                       : ((activeSession == SESSION_LONDON) ? g_liveLondonRange.high : g_liveNYRange.high);
                    
                    // Fixed SL at extreme
                    double slPrice = leg.extremePrice;
                    
                    ExecuteIFVGEntry(!leg.isUpsideSweep, slPrice, tpPrice);
                    leg.active = false; // Stop tracking this leg after entry
                    return;
                }
            }
        }
    }
    
    // Check for FVG limit order invalidation
    if(g_activeRetest.active && g_activeRetest.fvgIndex >= 0 && g_activeRetest.fvgIndex < leg.fvgCount)
    {
        double closePx = rates[1].close;
        bool invalidated = false;
        if(leg.fvgs[g_activeRetest.fvgIndex].isBullish && closePx < leg.fvgs[g_activeRetest.fvgIndex].c1Ext) invalidated = true;
        if(!leg.fvgs[g_activeRetest.fvgIndex].isBullish && closePx > leg.fvgs[g_activeRetest.fvgIndex].c1Ext) invalidated = true;
        
        if(invalidated)
        {
            Print("Active FVG Retest Limit Invalidated: Price closed completely through the FVG.");
            g_activeRetest.active = false;
        }
        else if(Inp_Force_Market_After_Next_Candle && rates[1].time > g_activeRetest.c3Time)
        {
            Print("Force Market Trigger: 1stPFVG unfilled after next candle closed. Executing Market.");
            ExecuteIFVGEntry(g_activeRetest.isLong, g_activeRetest.slPrice, g_activeRetest.tpPrice);
            g_activeRetest.active = false;
            leg.active = false;
            return;
        }
    }

    // FVG Retest Entry Trigger Logic
    if((Inp_Entry_Model == ENTRY_FVG_RETEST || Inp_Entry_Model == ENTRY_BOTH) && leg.cisdActive && !g_activeRetest.active)
    {
        for(int i=0; i<leg.fvgCount; i++)
        {
            // We want an aligned FVG that formed at or after CISD
            if(leg.fvgs[i].t3 >= leg.cisdTime)
            {
                if((leg.isUpsideSweep && !leg.fvgs[i].isBullish) || (!leg.isUpsideSweep && leg.fvgs[i].isBullish))
                {
                    double tpPrice = leg.isUpsideSweep ? ((activeSession == SESSION_LONDON) ? g_liveLondonRange.low : g_liveNYRange.low) 
                                                       : ((activeSession == SESSION_LONDON) ? g_liveLondonRange.high : g_liveNYRange.high);
                    double slPrice = leg.extremePrice;
                    
                    if(Inp_Retest_Mode == RETEST_MARKET_C3)
                    {
                        ExecuteIFVGEntry(!leg.isUpsideSweep, slPrice, tpPrice);
                        leg.active = false;
                        return;
                    }
                    
                    double limitPrice = 0;
                    if(Inp_Retest_Mode == RETEST_EDGE) // Edge touch
                    {
                        limitPrice = leg.fvgs[i].c3Ext;
                    }
                    else // Fill percent
                    {
                        double gapSize = MathAbs(leg.fvgs[i].c1Ext - leg.fvgs[i].c3Ext);
                        double fillAmt = gapSize * (Inp_FVG_FillPercent / 100.0);
                        limitPrice = leg.isUpsideSweep ? (leg.fvgs[i].c3Ext + fillAmt) : (leg.fvgs[i].c3Ext - fillAmt);
                    }
                    // Expiry at end of session
                    datetime expiry = (activeSession == SESSION_LONDON) ? g_liveLondonRange.closeTime : g_liveNYRange.closeTime;
                    
                    SetupFVGRetestEntry(!leg.isUpsideSweep, limitPrice, slPrice, tpPrice, expiry, i, leg.fvgs[i].t3);
                    break;
                }
            }
        }
    }
}

void RunCachedScanner(datetime serverTime, ENUM_TIMEFRAMES tf, ENUM_DTR_SESSION activeSession)
{
    if(!ShouldRunCachedScanner(serverTime, tf)) return;
    
    if(activeSession == SESSION_LONDON) ProcessScannerForLeg(activeSession, g_londonLeg, serverTime, tf);
    else ProcessScannerForLeg(activeSession, g_nyLeg, serverTime, tf);
}

void EnforceSessionCutoffs(datetime serverTime)
{
    if(g_londonLeg.active && !IsInTradingWindow(serverTime, SESSION_LONDON))
    {
        g_londonLeg.active = false;
        Print("London Trading Window ended. Scanner deactivated.");
    }
    
    if(g_nyLeg.active && !IsInTradingWindow(serverTime, SESSION_NY))
    {
        g_nyLeg.active = false;
        Print("NY Trading Window ended. Scanner deactivated.");
    }
    
    if(g_activeRetest.active && serverTime >= g_activeRetest.expiryTime)
    {
        Print("Active FVG Retest Limit Expired due to Session End.");
        g_activeRetest.active = false;
    }
}

#endif // DTR_ENGINE_MQH
