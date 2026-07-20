using System;
using System.Collections.Generic;
using NinjaTrader.Data;

namespace NinjaTrader.NinjaScript.Strategies.ORB_NT
{
    public enum ContractSizeMode
    {
        Micro,
        Mini
    }

    public static class ORB_Risk
    {
        // Tradeify 25K Select limits
        public const int MAX_MICRO_CONTRACTS = 10;
        public const int MAX_MINI_CONTRACTS = 1;

        // Simple lookup for Day Margin per contract (e.g., $50 for MES)
        private static readonly Dictionary<string, double> MarginTable = new Dictionary<string, double>()
        {
            { "MES", 50.0 },
            { "MNQ", 100.0 },
            { "MYM", 50.0 },
            { "ES", 500.0 },
            { "NQ", 1000.0 },
            { "YM", 500.0 }
        };

        public static double GetMarginPerContract(string symbol)
        {
            // Remove expiration from symbol name if present (e.g., "MES 09-26" -> "MES")
            string baseSymbol = symbol.Split(' ')[0];
            if (MarginTable.ContainsKey(baseSymbol))
            {
                return MarginTable[baseSymbol];
            }
            // Fallback safe assumption for a micro
            return 100.0;
        }

        public static int CalcContracts(double accountBalance, double riskPercent, double slDistancePoints, double pointValue, ContractSizeMode mode, int maxContractsOverride = 0)
        {
            if (accountBalance <= 0 || riskPercent <= 0 || slDistancePoints <= 0 || pointValue <= 0)
                return 0;

            double riskMoney = accountBalance * (riskPercent / 100.0);
            double cashPerContract = slDistancePoints * pointValue;
            
            // Basic contract math
            int computedContracts = (int)Math.Floor(riskMoney / cashPerContract);
            
            // Hard cap enforcement
            int hardCap = (mode == ContractSizeMode.Micro) ? MAX_MICRO_CONTRACTS : MAX_MINI_CONTRACTS;
            if (maxContractsOverride > 0 && maxContractsOverride < hardCap)
            {
                hardCap = maxContractsOverride;
            }

            return Math.Min(computedContracts, hardCap);
        }
        
        public static double MarginBudget(double freeMargin, double maxMarginUsagePercent)
        {
            return freeMargin * (maxMarginUsagePercent / 100.0);
        }

        public static int MarginCappedContracts(int intendedContracts, double marginBudget, double marginPerContract)
        {
            int maxAffordable = (int)Math.Floor(marginBudget / marginPerContract);
            return Math.Min(intendedContracts, maxAffordable);
        }
    }
}
