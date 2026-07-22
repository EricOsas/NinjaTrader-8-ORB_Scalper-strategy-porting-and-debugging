//+------------------------------------------------------------------+
//|                                                   DTR_Inputs.mqh |
//| Enumerations and Inputs for DTR-CRT                              |
//+------------------------------------------------------------------+
#ifndef DTR_INPUTS_MQH
#define DTR_INPUTS_MQH

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_CISD_MODE
{
    CISD_SINGLE = 0,
    CISD_CONSECUTIVE = 1
};

enum ENUM_ENTRY_MODEL
{
    ENTRY_IFVG = 0,
    ENTRY_FVG_RETEST = 1,
    ENTRY_BOTH = 2
};

enum ENUM_FVG_RETEST_MODE
{
    RETEST_EDGE = 0,
    RETEST_SHALLOW = 1,
    RETEST_MARKET_C3 = 2
};

enum ENUM_SL_MODE
{
    SL_FIXED = 0,
    SL_DYNAMIC = 1
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== 1. Time & Orchestration ==="
input int    Inp_ServerUTCOffsetHours  = 0;     
input bool   Inp_UseNewYorkDST         = true;  

input group "=== 2. Strategy Parameters ==="
input ENUM_TIMEFRAMES Inp_London_LTF   = PERIOD_M4;
input ENUM_TIMEFRAMES Inp_NY_LTF       = PERIOD_M1;
input ENUM_CISD_MODE Inp_CISD_Mode     = CISD_SINGLE;
input ENUM_ENTRY_MODEL Inp_Entry_Model = ENTRY_IFVG;
input ENUM_FVG_RETEST_MODE Inp_Retest_Mode = RETEST_SHALLOW;
input double Inp_FVG_FillPercent       = 50.0;
input bool   Inp_Force_Market_After_Next_Candle = false;
input bool   Inp_Require_BPR           = false;

input group "=== 3. Confluence Gates ==="
input bool   Inp_Require_PriorSession  = false; 
input bool   Inp_Require_PriorDays     = false; 

input group "=== 4. Risk & Trade Management ==="
input ENUM_SL_MODE Inp_SL_Mode         = SL_DYNAMIC;
input double Inp_MinRR                 = 3.0;
input int    Inp_Min_SL_Sanity_Distance= 50;    
input double Inp_Risk_Percent          = 1.0;
input double Inp_Max_Lots_Global       = 4.0;
input double Inp_Margin_Usage_Percent  = 90.0;
input double Inp_BE_TriggerPercent     = 50.0;
input double Inp_BE_LockPercent        = 5.0;

input group "=== 5. Visuals & Dashboard ==="
input bool   Inp_ShowVisuals           = true;
input bool   Inp_ShowDashboard         = true;
input int    Inp_DashTheme             = 0;
input bool   Inp_Show_Range_Box        = true;
input color  Inp_ClrRangeBox           = C'25,35,45';
input color  Inp_ClrEntryLine          = clrYellow;
input color  Inp_ClrSLLine             = C'55,57,68';
input color  Inp_ClrTPLine             = C'22,55,120';
input color  Inp_ClrTrailingStop       = clrSilver;
input bool   Inp_StealthMode           = false;

#endif // DTR_INPUTS_MQH
