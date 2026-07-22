//+------------------------------------------------------------------+
//| CCT_Visual.mqh  v6.0  Phase 3                                    |
//| Draw primitives (upsert+cache), generation renderer,             |
//| virgin/candidate processor, per-tick glow/hint/opacity driver.   |
//| Phase 3: seconds anchoring, FVG grey->bias transition,           |
//|          IFVG colours (dark blue / maroon), candidate opacity.   |
//+------------------------------------------------------------------+
#ifndef CCT_VISUAL_MQH
#define CCT_VISUAL_MQH

#include "CCT_Scanner.mqh"

#define FVG_TRANS_SEC  7.0            // grey → bias transition duration in seconds

//+------------------------------------------------------------------+
// Glow helpers
//+------------------------------------------------------------------+
color GlowColor(color dimClr,color brightClr,double t)
  {
   if(t<0.0)t=0.0; if(t>1.0)t=1.0;
   int r1=dimClr&0xFF,    g1=(dimClr>>8)&0xFF,    b1=(dimClr>>16)&0xFF;
   int r2=brightClr&0xFF, g2=(brightClr>>8)&0xFF, b2=(brightClr>>16)&0xFF;
   int r=(int)(r1+t*(r2-r1)),g=(int)(g1+t*(g2-g1)),b=(int)(b1+t*(b2-b1));
   if(r>255)r=255; if(g>255)g=255; if(b>255)b=255;
   return (color)(r|(g<<8)|(b<<16));
  }

double GlowPulse()
  {
   uint periodMs=(uint)(Inp_GlowPulseSec*1000);
   if(periodMs<1) periodMs=1000;
   double phase=(double)(GetTickCount()%periodMs)/(double)periodMs;
   return 0.5+0.5*MathSin(phase*2.0*CCT_PI);
  }

// Near-invisible colour used to "hide" a line without deleting it.
// Matches a very dark chart background.
color HiddenClr() {return (color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);}

color POIStateColor(const SIB_STATE st,const bool bull)
  {
   if(st==SS_TP_HIT) return Inp_ClrPOITP;
   if(st==SS_SL_HIT) return Inp_ClrPOISL;
   if(st==SS_BE_HIT) return Inp_ClrPOIBE;
   if(st==SS_TRIGGERED) return bull?Inp_ClrPOITriggeredBull:Inp_ClrPOITriggeredBear;
   if(st==SS_ACTIVE) return bull?Inp_ClrPOIActiveBull:Inp_ClrPOIActiveBear;
   if(st==SS_INACTIVE) return bull?Inp_ClrPOIInactiveBull:Inp_ClrPOIInactiveBear;
   if(st==SS_DORMANT) return bull?Inp_ClrPOIDormantBull:Inp_ClrPOIDormantBear;
   return Inp_ClrPOIDead;
  }

ENUM_LINE_STYLE POIStateStyle(const SIB_STATE st)
  {
   if(st==SS_TP_HIT || st==SS_SL_HIT || st==SS_BE_HIT)
      return CCTLineStyle(Inp_StyPOIResolved);
   if(st==SS_TRIGGERED)
      return CCTLineStyle(Inp_StyPOITriggered);
   if(st==SS_ACTIVE)
      return CCTLineStyle(Inp_StyPOIActive);
   if(st==SS_INACTIVE)
      return CCTLineStyle(Inp_StyPOIInactive);
   if(st==SS_DORMANT)
      return CCTLineStyle(Inp_StyPOIDormant);
   return CCTLineStyle(Inp_StyPOIDead);
  }

int POIStateWidth(const SIB_STATE st)
  {
   if(st==SS_TP_HIT || st==SS_SL_HIT || st==SS_BE_HIT)
      return CCTLineWidth(Inp_WidPOIResolved);
   if(st==SS_TRIGGERED)
      return CCTLineWidth(Inp_WidPOITriggered);
   if(st==SS_ACTIVE)
      return CCTLineWidth(Inp_WidPOIActive);
   if(st==SS_INACTIVE)
      return CCTLineWidth(Inp_WidPOIInactive);
   if(st==SS_DORMANT)
      return CCTLineWidth(Inp_WidPOIDormant);
   return CCTLineWidth(Inp_WidPOIDead);
  }

string ExtractExecGenKey(string nm)
  {
  string prefixes[]={"HNT_S_","HNT_T_","HNT_B_","BOX_SL_","BOX_TP_","TRIG_","COTR_"};
   int    lens[]    ={6,       6,       6,       7,        7,        5,      5};
   for(int i=0;i<ArraySize(prefixes);i++)
     {
      string probe=PFX+prefixes[i];
      int pos=StringFind(nm,probe);
      if(pos<0) continue;
      return StringSubstr(nm,pos+StringLen(PFX)+lens[i]);
     }
   return "";
  }

void DeleteNamedObject(string nm)
  {
   if(ObjectFind(0,nm)>=0)
      ObjectDelete(0,nm);
   string tipNm=nm+"_TIP";
   if(ObjectFind(0,tipNm)>=0)
      ObjectDelete(0,tipNm);
  }

string CandidateVisualBase(bool bull,datetime wickTime)
  {
   return PFX+"CA_"+(bull?"BU":"BE")+"_"+IntegerToString((int)wickTime);
  }

string CandidatePillarVisualName(bool bull,datetime wickTime)
  {
   return PFX+"CAP_"+(bull?"BU":"BE")+"_"+IntegerToString((int)wickTime);
  }

string VirginVisualBase(bool bull,datetime wickTime)
  {
   return PFX+"VW_"+(bull?"BU":"BE")+"_"+IntegerToString((int)wickTime);
  }

void DeleteCandidateVisualFamily(bool bull,datetime wickTime,int legacyIdx=-1)
  {
   string baseNm=CandidateVisualBase(bull,wickTime);
   DeleteNamedObject(baseNm);
   DeleteNamedObject(baseNm+"_LTF");
   DeleteNamedObject(CandidatePillarVisualName(bull,wickTime));

   if(legacyIdx<0) return;
   string side=(bull?"BU":"BE");
   string legacyBase=PFX+"CA_"+side+"_"+IntegerToString(legacyIdx);
   DeleteNamedObject(legacyBase);
   DeleteNamedObject(legacyBase+"_LTF");
   DeleteNamedObject(PFX+"CAP_"+side+"_"+IntegerToString(legacyIdx));
  }

void DeleteVirginVisualFamily(bool bull,datetime wickTime,int legacyIdx=-1)
  {
   string baseNm=VirginVisualBase(bull,wickTime);
   DeleteNamedObject(baseNm);
   DeleteNamedObject(baseNm+"_LTF");

   if(legacyIdx<0) return;
   string side=(bull?"BU":"BE");
   string legacyBase=PFX+"VW_"+side+"_"+IntegerToString(legacyIdx);
   DeleteNamedObject(legacyBase);
   DeleteNamedObject(legacyBase+"_LTF");
  }

bool GetChartPriceRange(double &pMin,double &pMax)
  {
   pMin=ChartGetDouble(0,CHART_PRICE_MIN,0);
   pMax=ChartGetDouble(0,CHART_PRICE_MAX,0);
   if(pMax>pMin) return true;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0.0) bid=SymbolInfoDouble(_Symbol,SYMBOL_LAST);
   double pad=MathMax(100*_Point,MathAbs(bid)*0.01);
   pMin=bid-pad;
   pMax=bid+pad;
   return (pMax>pMin);
  }

void DeleteSiblingVisualFamily(bool bull,datetime birthTime,datetime wickTime)
  {
   string side=(bull?"BU":"BE");
   string wickKey=IntegerToString((int)wickTime);
   string poiBase=PFX+"POI_"+side+"_"+wickKey;
   DeleteNamedObject(poiBase);
   DeleteNamedObject(poiBase+"_LTF");

   string genKey=side+"_"+IntegerToString((int)birthTime);
   string tsBase=PFX+"TS_"+genKey+"_"+wickKey;
   DeleteNamedObject(tsBase);
   DeleteNamedObject(tsBase+"_HTF");
  }

string FVGVisualName(bool bull,datetime birthTime,datetime t1,datetime t3)
  {
   return PFX+"FVG_"+(bull?"BU":"BE")+"_"+IntegerToString((int)birthTime)
          +"_"+IntegerToString((int)t1)+"_"+IntegerToString((int)t3);
  }

void DeleteFVGVisualBox(bool bull,datetime birthTime,datetime t1,datetime t3,int legacyBirthIdx=-1,int legacyFIdx=-1)
  {
   DeleteNamedObject(FVGVisualName(bull,birthTime,t1,t3));
   if(legacyBirthIdx>=0 && legacyFIdx>=0)
     {
      string legacyNm=PFX+"FVG_"+(bull?"BU":"BE")+"_"+IntegerToString(legacyBirthIdx)+"_"+IntegerToString(legacyFIdx);
      DeleteNamedObject(legacyNm);
     }
  }

void DeleteExecutionVisualFamily(string genKey)
  {
   if(genKey=="") return;
   string parts[]={"HNT_S_","HNT_T_","HNT_B_","COTR_","BOX_SL_","BOX_TP_","TRIG_"};
   for(int i=0;i<ArraySize(parts);i++)
      DeleteNamedObject(PFX+parts[i]+genKey);
   UnregisterExecFamilyTrack(genKey);
  }

void DeleteGenerationVisuals(bool bull,datetime birthTime,SibInfo &sibs[],int nSibs)
  {
   string genKey=(bull?"BU":"BE")+"_"+IntegerToString((int)birthTime);
   for(int i=0;i<nSibs;i++)
      DeleteSiblingVisualFamily(bull,birthTime,sibs[i].wickTime);
   DeleteExecutionVisualFamily(genKey);
   DeleteNamedObject(PFX+"AP_"+genKey);
  }

datetime ExtractActionPillarBirthTime(const string nm)
  {
   string baseNm=nm;
   int len=StringLen(baseNm);
   if(len>=4 && StringSubstr(baseNm,len-4)=="_TIP")
      baseNm=StringSubstr(baseNm,0,len-4);

   string prefix=PFX+"AP_";
   if(StringFind(baseNm,prefix)!=0)
      return 0;

   string key=StringSubstr(baseNm,StringLen(prefix));
   int sep=StringFind(key,"_");
   if(sep<0)
      return 0;

   string birthPart=StringSubstr(key,sep+1);
   if(birthPart=="")
      return 0;
   return (datetime)StringToInteger(birthPart);
  }

bool PruneStaleActionPillars(const datetime todayOpen)
  {
   if(todayOpen<=0) return false;
   bool removed=false;
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
     {
      string nm=ObjectName(0,i,-1,-1);
      if(nm=="") continue;
      int len=StringLen(nm);
      if(len>=4 && StringSubstr(nm,len-4)=="_TIP")
         continue;
      if(StringFind(nm,PFX+"AP_")!=0)
         continue;

      datetime birthTime=ExtractActionPillarBirthTime(nm);
      if(birthTime<=0 || birthTime>=todayOpen)
         continue;

      DeleteNamedObject(nm);
      removed=true;
     }
   return removed;
  }

void PruneStaleExecutionVisualFamilies()
  {
   string staleKeys[];
   int staleN=0;
   int total=ObjectsTotal(0);
   for(int i=0;i<total;i++)
     {
      string nm=ObjectName(0,i);
      string genKey=ExtractExecGenKey(nm);
      if(genKey=="") continue;

      bool seen=false;
      for(int k=0;k<staleN;k++)
        {
         if(staleKeys[k]==genKey)
           {
            seen=true;
            break;
           }
        }
      if(seen) continue;

      datetime familyTime=0;
      int trackIdx=FindExecFamilyTrack(genKey);
      if(trackIdx>=0)
         familyTime=g_execFamilies[trackIdx].triggerTime;
      if(familyTime<=0)
         familyTime=(datetime)StringToInteger(StringSubstr(genKey,3));

      if(!IsRecentExecutionVisualTime(familyTime))
        {
         ArrayResize(staleKeys,staleN+1);
         staleKeys[staleN++]=genKey;
        }
     }

   for(int i=0;i<staleN;i++)
      DeleteExecutionVisualFamily(staleKeys[i]);
  }

bool ExecFamilyHasVisuals(string genKey)
  {
   if(genKey=="") return false;
   string parts[]={"HNT_S_","HNT_T_","HNT_B_","COTR_","BOX_SL_","BOX_TP_","TRIG_"};
   for(int i=0;i<ArraySize(parts);i++)
      if(ObjectFind(0,PFX+parts[i]+genKey)>=0)
         return true;
   return false;
  }

int FindGenerationOwnerSibling(SibInfo &sibs[],int nSibs)
  {
   int fallbackIdx=-1;
   int bestScore=-1;
   for(int s=0;s<nSibs;s++)
     {
      if(sibs[s].state==SS_TRIGGERED
         || sibs[s].state==SS_TP_HIT
         || sibs[s].state==SS_SL_HIT
         || sibs[s].state==SS_BE_HIT)
         return s;

      int score=0;
      if(sibs[s].c1Time>0) score=1;
      if(sibs[s].c2Time>0) score=2;
      if(sibs[s].c3Time>0) score=3;
      if(score>bestScore)
        {
         bestScore=score;
         fallbackIdx=s;
        }
     }
   return fallbackIdx;
  }

bool UpdateExecObjRightEdge(const string nm,datetime targetR)
  {
   if(ObjectFind(0,nm)<0) return false;
   datetime finalR=targetR;
   long capEncoded=ObjectGetInteger(0,nm,OBJPROP_ZORDER);
   datetime cap=(capEncoded>0)?(datetime)capEncoded:0;
   if(cap>0 && cap<finalR)
      finalR=cap;
   bool changed=SetObjIntIfChanged(nm,OBJPROP_TIME,(long)finalR,1);
   int len=StringLen(nm);
   bool isTip=(len>=4 && StringSubstr(nm,len-4)=="_TIP");
   if(!isTip)
     {
      string tipNm=nm+"_TIP";
      if(ObjectFind(0,tipNm)>=0)
         if(SetObjIntIfChanged(tipNm,OBJPROP_TIME,(long)finalR,1))
            changed=true;
     }
   return changed;
  }

bool LockExecFamilyRightEdge(string genKey,datetime targetR,bool includeCO=true)
  {
   bool changed=false;
   string parts[]={"HNT_S_","HNT_T_","HNT_B_","BOX_SL_","BOX_TP_","TRIG_"};
   for(int i=0;i<ArraySize(parts);i++)
      if(UpdateExecObjRightEdge(PFX+parts[i]+genKey,targetR))
         changed=true;
   if(includeCO && UpdateExecObjRightEdge(PFX+"COTR_"+genKey,targetR))
      changed=true;
   return changed;
  }

bool SetObjIntIfChanged(const string nm,ENUM_OBJECT_PROPERTY_INTEGER prop,long value,int modifier=-1)
  {
   long current=(modifier>=0)
                ?ObjectGetInteger(0,nm,prop,modifier)
                :ObjectGetInteger(0,nm,prop);
   if(current==value) return false;
   return (modifier>=0)
          ?ObjectSetInteger(0,nm,prop,modifier,value)
          :ObjectSetInteger(0,nm,prop,value);
  }

bool SetObjDblIfChanged(const string nm,ENUM_OBJECT_PROPERTY_DOUBLE prop,double value,int modifier=-1)
  {
   double current=(modifier>=0)
                  ?ObjectGetDouble(0,nm,prop,modifier)
                  :ObjectGetDouble(0,nm,prop);
   if(current==value) return false;
   return (modifier>=0)
          ?ObjectSetDouble(0,nm,prop,modifier,value)
          :ObjectSetDouble(0,nm,prop,value);
  }

bool SetCandidatePillarVisual(const string nm,color clr)
  {
   bool changed=false;
   if(ObjectFind(0,nm)>=0)
     {
      if(SetObjIntIfChanged(nm,OBJPROP_COLOR,(long)clr))
         changed=true;
      if(SetObjIntIfChanged(nm,OBJPROP_STYLE,(long)CCTLineStyle(Inp_StyCandidatePillar)))
         changed=true;
      if(SetObjIntIfChanged(nm,OBJPROP_WIDTH,(long)CCTLineWidth(Inp_WidCandidatePillar)))
         changed=true;
     }

   string tipNm=nm+"_TIP";
   if(ObjectFind(0,tipNm)>=0)
     {
      if(SetObjIntIfChanged(tipNm,OBJPROP_COLOR,(long)clr))
         changed=true;
      if(SetObjIntIfChanged(tipNm,OBJPROP_STYLE,(long)CCTLineStyle(Inp_StyCandidatePillar)))
         changed=true;
      if(SetObjIntIfChanged(tipNm,OBJPROP_WIDTH,(long)CCTLineWidth(Inp_WidCandidatePillar)))
         changed=true;
     }

   return changed;
  }

void UpsertExecTooltipCarrier(const string baseNm,
                              datetime t1,double p1,
                              datetime t2,double p2,
                              const string tip,
                              long tff=-1,
                              bool back=false,
                              int wid=4)
  {
   if(tff<0) tff=LTFMaxTFs();
   string tipNm=baseNm+"_TIP";
   ObjCacheRegister(tipNm);
   bool isNew=(ObjectFind(0,tipNm)<0);
   if(isNew)
      ObjectCreate(0,tipNm,OBJ_TREND,0,t1,p1,t2,p2);
   if(isNew || (datetime)ObjectGetInteger(0,tipNm,OBJPROP_TIME,0)!=t1)
      ObjectSetInteger(0,tipNm,OBJPROP_TIME,0,t1);
   if(isNew || (datetime)ObjectGetInteger(0,tipNm,OBJPROP_TIME,1)!=t2)
      ObjectSetInteger(0,tipNm,OBJPROP_TIME,1,t2);
   if(isNew || ObjectGetDouble(0,tipNm,OBJPROP_PRICE,0)!=p1)
      ObjectSetDouble(0,tipNm,OBJPROP_PRICE,0,p1);
   if(isNew || ObjectGetDouble(0,tipNm,OBJPROP_PRICE,1)!=p2)
      ObjectSetDouble(0,tipNm,OBJPROP_PRICE,1,p2);
   if(isNew || (color)ObjectGetInteger(0,tipNm,OBJPROP_COLOR)!=HiddenClr())
      ObjectSetInteger(0,tipNm,OBJPROP_COLOR,HiddenClr());
   if(isNew || (ENUM_LINE_STYLE)ObjectGetInteger(0,tipNm,OBJPROP_STYLE)!=STYLE_SOLID)
      ObjectSetInteger(0,tipNm,OBJPROP_STYLE,STYLE_SOLID);
   if(isNew || (int)ObjectGetInteger(0,tipNm,OBJPROP_WIDTH)!=wid)
      ObjectSetInteger(0,tipNm,OBJPROP_WIDTH,wid);
   SetObjIntIfChanged(tipNm,OBJPROP_RAY_RIGHT,false);
   SetObjIntIfChanged(tipNm,OBJPROP_RAY_LEFT,false);
   SetObjIntIfChanged(tipNm,OBJPROP_SELECTABLE,false);
   SetObjIntIfChanged(tipNm,OBJPROP_BACK,true);
   SetObjIntIfChanged(tipNm,OBJPROP_TIMEFRAMES,tff);
   string fitTip=TooltipFit(tip);
   if(ObjectGetString(0,tipNm,OBJPROP_TOOLTIP)!=fitTip)
      ObjectSetString(0,tipNm,OBJPROP_TOOLTIP,fitTip);
  }

//+------------------------------------------------------------------+
// Draw primitives — all upsert (create-if-not-exists, always update).
// Each primitive registers its name with ObjCacheRegister so stale
// objects are pruned at end of Draw(). DrawHints tick objects must NOT
// call these — they manage objects directly.
//+------------------------------------------------------------------+
void DrawVLine(string nm,datetime t,color clr,ENUM_LINE_STYLE sty,int wid,
               bool back,string tip="",long tff=OBJ_ALL_PERIODS)
  {
   ObjCacheRegister(nm);
   bool isNewVL=(ObjectFind(0,nm)<0);
   if(isNewVL) ObjectCreate(0,nm,OBJ_VLINE,0,t,0);
   if(isNewVL||(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0)!=t)  ObjectSetInteger(0,nm,OBJPROP_TIME,0,t);
   SetObjIntIfChanged(nm,OBJPROP_COLOR,(long)clr);
   SetObjIntIfChanged(nm,OBJPROP_STYLE,(long)sty);
   SetObjIntIfChanged(nm,OBJPROP_WIDTH,(long)wid);
   SetObjIntIfChanged(nm,OBJPROP_SELECTABLE,0);
   SetObjIntIfChanged(nm,OBJPROP_BACK,back?1:0);
   SetObjIntIfChanged(nm,OBJPROP_TIMEFRAMES,tff);
   if(tip!="")
     {
      string fitTip=TooltipFit(tip);
      if(ObjectGetString(0,nm,OBJPROP_TOOLTIP)!=fitTip)
         ObjectSetString(0,nm,OBJPROP_TOOLTIP,fitTip);
     }

   string tipNm=nm+"_TIP";
   double pMin=0.0,pMax=0.0;
   if(GetChartPriceRange(pMin,pMax))
     {
      ObjCacheRegister(tipNm);
      bool isNewTip=(ObjectFind(0,tipNm)<0);
      if(isNewTip) ObjectCreate(0,tipNm,OBJ_TREND,0,t,pMax,t,pMin);
      if(isNewTip||(datetime)ObjectGetInteger(0,tipNm,OBJPROP_TIME,0)!=t)
         ObjectSetInteger(0,tipNm,OBJPROP_TIME,0,t);
      if(isNewTip||(datetime)ObjectGetInteger(0,tipNm,OBJPROP_TIME,1)!=t)
         ObjectSetInteger(0,tipNm,OBJPROP_TIME,1,t);
      if(isNewTip||ObjectGetDouble(0,tipNm,OBJPROP_PRICE,0)!=pMax)
         ObjectSetDouble(0,tipNm,OBJPROP_PRICE,0,pMax);
      if(isNewTip||ObjectGetDouble(0,tipNm,OBJPROP_PRICE,1)!=pMin)
         ObjectSetDouble(0,tipNm,OBJPROP_PRICE,1,pMin);
      if(isNewTip||(color)ObjectGetInteger(0,tipNm,OBJPROP_COLOR)!=clr)
         ObjectSetInteger(0,tipNm,OBJPROP_COLOR,clr);
      if(isNewTip||(ENUM_LINE_STYLE)ObjectGetInteger(0,tipNm,OBJPROP_STYLE)!=sty)
         ObjectSetInteger(0,tipNm,OBJPROP_STYLE,sty);
      int tipWid=MathMax(wid,1);
      if(isNewTip||(int)ObjectGetInteger(0,tipNm,OBJPROP_WIDTH)!=tipWid)
         ObjectSetInteger(0,tipNm,OBJPROP_WIDTH,tipWid);
      if(isNewTip||(bool)ObjectGetInteger(0,tipNm,OBJPROP_RAY_RIGHT)!=false)
         ObjectSetInteger(0,tipNm,OBJPROP_RAY_RIGHT,false);
      if(isNewTip||(bool)ObjectGetInteger(0,tipNm,OBJPROP_RAY_LEFT)!=false)
         ObjectSetInteger(0,tipNm,OBJPROP_RAY_LEFT,false);
      if(isNewTip||(bool)ObjectGetInteger(0,tipNm,OBJPROP_SELECTABLE)!=false)
         ObjectSetInteger(0,tipNm,OBJPROP_SELECTABLE,false);
      if(isNewTip||(bool)ObjectGetInteger(0,tipNm,OBJPROP_BACK)!=back)
         ObjectSetInteger(0,tipNm,OBJPROP_BACK,back);
      if(isNewTip||(long)ObjectGetInteger(0,tipNm,OBJPROP_TIMEFRAMES)!=tff)
         ObjectSetInteger(0,tipNm,OBJPROP_TIMEFRAMES,tff);
      if(tip!="")
        {
         string fitTip=TooltipFit(tip);
         if(ObjectGetString(0,tipNm,OBJPROP_TOOLTIP)!=fitTip)
            ObjectSetString(0,tipNm,OBJPROP_TOOLTIP,fitTip);
        }
     }
  }

void _Seg(string nm,datetime t1,datetime t2,double px,
          color clr,ENUM_LINE_STYLE sty,int wid,long tff,string tip)
  {
   ObjCacheRegister(nm);
   bool isNew=(ObjectFind(0,nm)<0);
   if(isNew) ObjectCreate(0,nm,OBJ_TREND,0,t1,px,t2,px);
   // Only update properties when values change — prevents per-bar flicker
   if(isNew||(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0)!=t1)
      ObjectSetInteger(0,nm,OBJPROP_TIME,0,t1);
   if(isNew||ObjectGetDouble(0,nm,OBJPROP_PRICE,0)!=px)
      ObjectSetDouble(0,nm,OBJPROP_PRICE,0,px);
   if(isNew||(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1)!=t2)
      ObjectSetInteger(0,nm,OBJPROP_TIME,1,t2);
   if(isNew||ObjectGetDouble(0,nm,OBJPROP_PRICE,1)!=px)
      ObjectSetDouble(0,nm,OBJPROP_PRICE,1,px);
   if(isNew||(color)ObjectGetInteger(0,nm,OBJPROP_COLOR)!=clr)
      ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   if(isNew||(ENUM_LINE_STYLE)ObjectGetInteger(0,nm,OBJPROP_STYLE)!=sty)
      ObjectSetInteger(0,nm,OBJPROP_STYLE,sty);
   if(isNew||(int)ObjectGetInteger(0,nm,OBJPROP_WIDTH)!=wid)
      ObjectSetInteger(0,nm,OBJPROP_WIDTH,wid);
   SetObjIntIfChanged(nm,OBJPROP_RAY_RIGHT,0);
   SetObjIntIfChanged(nm,OBJPROP_RAY_LEFT,0);
   SetObjIntIfChanged(nm,OBJPROP_SELECTABLE,0);
   SetObjIntIfChanged(nm,OBJPROP_BACK,0);
   SetObjIntIfChanged(nm,OBJPROP_TIMEFRAMES,tff);
   string fitTip=TooltipFit(tip);
   if(ObjectGetString(0,nm,OBJPROP_TOOLTIP)!=fitTip)
      ObjectSetString (0,nm,OBJPROP_TOOLTIP,fitTip);
  }

void DrawPOIDual(string nm,datetime htfA,datetime ltfA,datetime segEnd,double px,
                 color clr,ENUM_LINE_STYLE sty,int wid,string tip)
  {
   // HTF version: anchored to HTF bar open (htfA) — renders cleanly on H1/H4/D1 charts.
   // LTF version: anchored to exact wick LTF bar (ltfA) — precise on M1/M5/M15 charts.
   // Two separate anchor times are intentional and correct for each zoom level.
   _Seg(nm,        htfA,segEnd,px,clr,sty,wid,AboveHTFFlag(), tip);
   _Seg(nm+"_LTF", ltfA,segEnd,px,clr,sty,wid,LTFOnlyFlag(),  tip);
  }

void DrawCOLine(string nm,datetime t1,double px,datetime t2,color clr,string tip)
  {_Seg(nm,t1,t2,px,clr,CCTLineStyle(Inp_StyExecCO),CCTLineWidth(Inp_WidExecCO),LTFMaxTFs(),tip);}

void DrawConfirmedActionPillarForGeneration(MqlRates &B[],int n,int pSec,bool bull,int bb,
                                            int &bullBirths[],int nBull,int &bearBirths[],int nBear,
                                            int poiCount)
  {
   string nm=PFX+"AP_"+(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
   datetime pt=(bb+1<n)?B[bb+1].time:(datetime)(B[bb].time+pSec);
   if(pt<ActionPillarVisualStart())
     {
      DeleteNamedObject(nm);
      return;
     }

   int apNextSame=bull?NextGenBirth(bullBirths,nBull,bb):NextGenBirth(bearBirths,nBear,bb);
   int apNextCounter=bull?NextGenBirth(bearBirths,nBear,bb):NextGenBirth(bullBirths,nBull,bb);
   datetime apNextSameTime=(apNextSame>=0&&apNextSame<n)?B[apNextSame].time:0;
   datetime apNextCtrTime=(apNextCounter>=0&&apNextCounter<n)?B[apNextCounter].time:0;
   bool apDormant=(apNextSameTime>0);
   bool apCounterBiasDormant=(apDormant && apNextCtrTime>0);
   string apState=(apDormant?(apCounterBiasDormant?"Ctr dorm":"In-bias dorm")
                            :"Active");
   TradeWindowResult apBirthWindow;
   if(ResolveBirthTradeWindowCurrentModel(B[bb].time,apBirthWindow) && apBirthWindow.minHTF>0)
     {
      string genKey=(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
      datetime trackedTrigger=0;
      int execIdx=FindExecFamilyTrack(genKey);
      if(execIdx>=0)
         trackedTrigger=g_execFamilies[execIdx].triggerTime;
      else
        {
         datetime liveTrigger=0;
         double entryPx=0.0,slPx=0.0,tpPx=0.0;
         if(GetOpenPositionExecGeometry(genKey,liveTrigger,entryPx,slPx,tpPx))
            trackedTrigger=liveTrigger;
        }
      datetime intendedExecOpen=(bb+1+apBirthWindow.minHTF<n)
                                ?B[bb+1+apBirthWindow.minHTF].time
                                :(datetime)(pt+apBirthWindow.minHTF*pSec);
      if(trackedTrigger>0 && intendedExecOpen>0 && trackedTrigger<intendedExecOpen)
         apState="Consumed in dev bar";
     }

   string apTip="Action Pillar  "+(bull?"▲":"▼")
               +"\nPOIs: "+IntegerToString(poiCount)
               +"\nBirth: "+NYStr(B[bb].time)
               +"\nClose: "+NYStr((datetime)(B[bb].time+pSec-1))
               +"\nExec: "+NYStr(pt)
               +"\nState: "+apState;
   DrawVLine(nm,pt,Inp_ClrActionPillar,CCTLineStyle(Inp_StyActionPillar),
             CCTLineWidth(Inp_WidActionPillar),false,apTip,FullContentTFs()|DaySepOnlyTFs());
  }

// DrawTSLine — draws Turtle Soup line as two objects:
//   LTF object: exact LTF timestamps (tsWickTime → tsTouchTime+ltfSec-1) — renders correctly on M1
//   HTF object: HTF bar-aligned timestamps — renders as a clean segment on H1/H4
//   This avoids MT5's object-placement-by-LTF-position problem on HTF charts.
void DrawTSLine(string nm,datetime tsWickTime,datetime tsTouchTime,
                double tsLevel,bool bull,bool triggered,string tip,
                MqlRates &B[],int n,int pSec)
  {
   int      ltfSec=(int)PeriodSeconds(LTF());
   datetime tR=(datetime)(tsTouchTime+ltfSec-1);
   color clr=bull?Inp_ClrTSBull:Inp_ClrTSBear;
   ENUM_LINE_STYLE tsty=triggered?CCTLineStyle(Inp_StyTSTriggered):CCTLineStyle(Inp_StyTSPending);

   // LTF object — exact tick-precision anchors, visible only on LTF
   ObjCacheRegister(nm);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TREND,0,tsWickTime,tsLevel,tR,tsLevel);
   if((datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0)!=tsWickTime) ObjectSetInteger(0,nm,OBJPROP_TIME,0,tsWickTime);
   if((datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,1)!=tR)         ObjectSetInteger(0,nm,OBJPROP_TIME,1,tR);
   ObjectSetDouble (0,nm,OBJPROP_PRICE,     0,tsLevel);
   ObjectSetDouble (0,nm,OBJPROP_PRICE,     1,tsLevel);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,     tsty);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidTS));
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0,nm,OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,LTFOnlyFlag());
   ObjectSetString (0,nm,OBJPROP_TOOLTIP,   TooltipFit(tip));

   // HTF object — bar-aligned anchors: from start of wick's HTF bar to end of touch's HTF bar
   // This renders as a clean horizontal on HTF charts without LTF-position artefacts.
   string nmHTF=nm+"_HTF";
   datetime htfL=0,htfR=0;
   for(int k=n-1;k>=0;k--)
     {
      if(B[k].time<=tsWickTime && htfL==0) htfL=B[k].time;
      if(B[k].time<=tsTouchTime && htfR==0) htfR=(datetime)(B[k].time+pSec-1);
      if(htfL>0&&htfR>0) break;
     }
   if(htfL==0) htfL=tsWickTime;
   if(htfR==0) htfR=tR;
   ObjCacheRegister(nmHTF);
   if(ObjectFind(0,nmHTF)<0) ObjectCreate(0,nmHTF,OBJ_TREND,0,htfL,tsLevel,htfR,tsLevel);
   if((datetime)ObjectGetInteger(0,nmHTF,OBJPROP_TIME,0)!=htfL) ObjectSetInteger(0,nmHTF,OBJPROP_TIME,0,htfL);
   if((datetime)ObjectGetInteger(0,nmHTF,OBJPROP_TIME,1)!=htfR) ObjectSetInteger(0,nmHTF,OBJPROP_TIME,1,htfR);
   ObjectSetDouble (0,nmHTF,OBJPROP_PRICE,     0,tsLevel);
   ObjectSetDouble (0,nmHTF,OBJPROP_PRICE,     1,tsLevel);
   ObjectSetInteger(0,nmHTF,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,nmHTF,OBJPROP_STYLE,     tsty);
   ObjectSetInteger(0,nmHTF,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidTS));
   ObjectSetInteger(0,nmHTF,OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0,nmHTF,OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0,nmHTF,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nmHTF,OBJPROP_BACK,      false);
   ObjectSetInteger(0,nmHTF,OBJPROP_TIMEFRAMES,AboveHTFFlag());
   ObjectSetString (0,nmHTF,OBJPROP_TOOLTIP,   TooltipFit(tip));
  }

void DrawArrow(string nm,datetime t,double px,color clr,int arrowCode,string tip)
  {
   ObjCacheRegister(nm);
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_ARROW,0,t,px);
   ObjectSetInteger(0,nm,OBJPROP_TIME,      0,t);
   ObjectSetDouble (0,nm,OBJPROP_PRICE,     0,px);
   ObjectSetInteger(0,nm,OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     1);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
   ObjectSetString (0,nm,OBJPROP_TOOLTIP,   TooltipFit(tip));
  }

void PrimeBrokerExecutionForGeneration(MqlRates &B[],int n,int pSec,bool bull,int bb,
                                      SibInfo &sibs[],int nSibs,datetime supersedeAfterTime,datetime lockAfterTime,
                                      int &bullBirths[],int nBull,int &bearBirths[],int nBear)
  {
   if(Inp_BrokerExecution!=BROKER_EXEC_ON) return;
   if(bb<0 || bb>=n || bb+1>=n || nSibs<1) return;

   string execGenKey=(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
   if(HasCachedBrokerTradePresence(execGenKey))
      return;
   datetime pillarOpen=(bb+1<n)?B[bb+1].time:B[bb].time+pSec;

   int nextSame,nextCounter;
   if(bull)
     {
      nextSame=NextGenBirth(bullBirths,nBull,bb);
      nextCounter=NextGenBirth(bearBirths,nBear,bb);
     }
   else
     {
      nextSame=NextGenBirth(bearBirths,nBear,bb);
      nextCounter=NextGenBirth(bullBirths,nBull,bb);
     }

   datetime nextSameTime=(nextSame>=0&&nextSame<n)?B[nextSame].time:0;
   datetime nextCtrTime =(nextCounter>=0&&nextCounter<n)?B[nextCounter].time:0;
   datetime ctrBiasFrom =(nextCtrTime>0)?nextCtrTime:0;

   bool coLocked=false;
   datetime coTime=0,coEndTime=0;
   double coPx=FindCorrectionOrigin(B,n,pSec,sibs[0].level,bull,
                                    bb,nextSame,nextCounter,
                                    coLocked,coTime,coEndTime);

   TradeWindowResult birthWindow;
   datetime todayOpen=TodayOpenAt(MarketReferenceTime());
   if(B[bb].time<todayOpen || !ResolveBirthTradeWindowCurrentModel(B[bb].time,birthWindow))
      return;

   datetime firstExecOpen=0,firstExecEnd=0;
   string firstExecLabel="";
   bool openPositionExists=HasOpenCCTPositionForGenKey(execGenKey);
   bool generationHasTradeBacking=HasExecutionVisualBacking(execGenKey);
   bool generationAlreadyLive=(FindExecFamilyTrack(execGenKey)>=0
                               || ExecFamilyHasVisuals(execGenKey)
                               || openPositionExists
                               || generationHasTradeBacking);
   if(!ResolveFirstExecutionWindowForBirth(B[bb].time,firstExecOpen,firstExecEnd,firstExecLabel))
      return;
   if(!generationAlreadyLive && firstExecEnd>0 && MarketReferenceTime()>firstExecEnd)
      return;

   datetime minActivateTime=0;
   datetime maxActivateTime=0;
   if(!ResolveGenerationActivationWindow(B,n,pSec,bb,pillarOpen,minActivateTime,maxActivateTime))
      return;

   FVGInfo fvgs[];
   int nFvgs=0;
   int c3FvgIdx=-1;
   datetime triggerTime=0;
   bool coVisible=false;
   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
   ScanGeneration(coTime,coPx,bull,sibs,nSibs,scanEnd,pillarOpen,
                  ctrBiasFrom,supersedeAfterTime,lockAfterTime,pSec,
                  minActivateTime,maxActivateTime,nextSameTime,
                  fvgs,nFvgs,c3FvgIdx,triggerTime,coVisible);

   if(triggerTime<=0 || c3FvgIdx<0 || c3FvgIdx>=nFvgs)
      return;

   int ltfSec=(int)PeriodSeconds(LTF());

   MqlRates trigBar[];
   if(CopyRates(_Symbol,LTF(),triggerTime,1,trigBar)<=0)
      return;

   double trigClose=trigBar[0].close;
   if(trigClose<=0.0)
      return;

   double sweepProbe=ScanExtremeBetween(fvgs[c3FvgIdx].t3,triggerTime,bull);
   if(sweepProbe<=0.0) sweepProbe=trigClose;

   FVGInfo cfvg=fvgs[c3FvgIdx];
   double aA=(Inp_FibMode==FIB_MODE_STANDARD)?cfvg.c1Ext:trigClose;
   double aB=cfvg.c2c3Extreme;
   ENUM_SL_BRANCH branchLocked=DetectSLBranch(cfvg,bull,sweepProbe);
   double slRawLocked=CalcFibSL(aA,aB,bull,branchLocked);
   double tpLocked=CalcTPRaw(bull,trigClose,slRawLocked,coPx);
   double riskLocked=MathAbs(trigClose-slRawLocked);
   double rrLocked=(riskLocked>_Point)?(MathAbs(tpLocked-trigClose)/riskLocked):0.0;
   datetime expiryTime=PendingExecHardExpiry(triggerTime);
   string execModelLabel="CCT";
   TradeWindowResult triggerExecWindow;
   datetime triggerExecOpen=0,triggerExecEnd=0;
   string triggerExecHuman="";
   int triggerExecKey=-1;
   if(ResolveExecutionWindowForTrigger(triggerTime,
                                       triggerExecWindow,
                                       triggerExecOpen,
                                       triggerExecEnd,
                                       triggerExecHuman,
                                       triggerExecKey,
                                       B[bb].time))
      execModelLabel=TradeWindowShortLabelForOffset(triggerExecWindow.maxHTF+1);
   else if(birthWindow.valid)
      execModelLabel=TradeWindowShortLabelForOffset(birthWindow.maxHTF+1);
   int trigSibIdx=-1;
   for(int sx=0;sx<nSibs;sx++)
     {
      if(sibs[sx].state==SS_TRIGGERED
         || sibs[sx].state==SS_TP_HIT
         || sibs[sx].state==SS_SL_HIT
         || sibs[sx].state==SS_BE_HIT
         || sibs[sx].c3Time>0)
        {
         trigSibIdx = sx;
         execModelLabel=ResolveTriggerModelLabelForSibling(sibs[sx],B[bb].time,triggerTime,execModelLabel);
         break;
        }
     }
   datetime trigC1Time = (trigSibIdx>=0 && trigSibIdx<nSibs) ? sibs[trigSibIdx].c1Time : 0;
   RegisterPendingExec(bull,trigClose,slRawLocked,tpLocked,rrLocked,coPx,triggerTime,B[bb].time,expiryTime,execModelLabel,trigC1Time);
  }

void DrawFVGBox(string nm,datetime tL,datetime tR,double pLo,double pHi,
                 color clr,string tip)
{
   ObjCacheRegister(nm);
   bool isNew=(ObjectFind(0,nm)<0);
   if(isNew) ObjectCreate(0,nm,OBJ_RECTANGLE,0,tL,pHi,tR,pLo);
   if(isNew||(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME, 0)!=tL) ObjectSetInteger(0,nm,OBJPROP_TIME, 0,tL);
   if(isNew||ObjectGetDouble(0,nm,OBJPROP_PRICE,0)!=pHi)            ObjectSetDouble (0,nm,OBJPROP_PRICE,0,pHi);
   if(isNew||(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME, 1)!=tR) ObjectSetInteger(0,nm,OBJPROP_TIME, 1,tR);
   if(isNew||ObjectGetDouble(0,nm,OBJPROP_PRICE,1)!=pLo)            ObjectSetDouble (0,nm,OBJPROP_PRICE,1,pLo);
   if(isNew||(color)ObjectGetInteger(0,nm,OBJPROP_COLOR)!=clr)      ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
   if(isNew) { ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
               ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
               ObjectSetInteger(0,nm,OBJPROP_ZORDER,0); }
  SetObjIntIfChanged(nm,OBJPROP_STYLE,CCTLineStyle(Inp_StyIFVGBox));
  SetObjIntIfChanged(nm,OBJPROP_WIDTH,CCTLineWidth(Inp_WidIFVGBox));
  SetObjIntIfChanged(nm,OBJPROP_FILL,true);
  SetObjIntIfChanged(nm,OBJPROP_BACK,true); // keep fills behind candles
  if(tip!="")
    {
     string fitTip=TooltipFit(tip);
     if(ObjectGetString(0,nm,OBJPROP_TOOLTIP)!=fitTip)
        ObjectSetString(0,nm,OBJPROP_TOOLTIP,fitTip);
    }
}

bool GetLTFBarHL(datetime barTime,double &hi,double &lo)
  {
   MqlRates r[];
   int n=CopyLTFWindowFromCache(barTime,barTime+(datetime)PeriodSeconds(LTF()),r);
   if(n<1)
      n=CopyRates(_Symbol,LTF(),barTime,barTime+(datetime)PeriodSeconds(LTF()),r);
   if(n<1) return false;
   hi=r[0].high; lo=r[0].low; return true;
  }

//+------------------------------------------------------------------+
// DrawGeneration — renders one complete generation.
//+------------------------------------------------------------------+
void DrawGeneration(MqlRates &B[],int n,int pSec,bool bull,int bb,
                    SibInfo &sibs[],int nSibs,
                    datetime drawFrom,int bias,
                    int &bullBirths[],int nBull,int &bearBirths[],int nBear,
                    datetime supersedeAfterTime=0,datetime lockAfterTime=0,
                    bool allowDeletes=true,bool renderVisuals=true)
  {
   if(nSibs<1) return;

   string   dir      =bull?"▲":"▼";
   string   execGenKey=(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
   datetime pillarOpen=(bb+1<n)?B[bb+1].time:B[bb].time+pSec;
   datetime segInact  =pillarOpen-1;
   // segActive: extends to end of the CURRENT live HTF bar, not just the pillar bar.
   // When 3am births a POI and 4am activates it, if 4am closes without kill/trigger,
   // the active line must extend to 5:59:59, then 6:59:59, etc. each Draw() cycle.
   // HTFBarEndOf finds the bar containing TimeCurrent() and returns its end time.
   datetime segActive =(datetime)(B[n-1].time + pSec - 1);
   int      ltfSec   =(int)PeriodSeconds(LTF());

   int nextSame,nextCounter;
   if(bull){nextSame=NextGenBirth(bullBirths,nBull,bb);nextCounter=NextGenBirth(bearBirths,nBear,bb);}
   else    {nextSame=NextGenBirth(bearBirths,nBear,bb);nextCounter=NextGenBirth(bullBirths,nBull,bb);}
   datetime nextSameTime=(nextSame>=0&&nextSame<n)?B[nextSame].time:0;
   datetime nextCtrTime =(nextCounter>=0&&nextCounter<n)?B[nextCounter].time:0;

   bool biasFlipped=(nextCtrTime>0);
   bool counterBias=biasFlipped;
   datetime ctrBiasFrom=biasFlipped?nextCtrTime:0;

   bool     coLocked=false; datetime coTime=0,coEndTime=0;
   double   coPx=FindCorrectionOrigin(B,n,pSec,sibs[0].level,bull,
                                      bb,nextSame,nextCounter,
                                      coLocked,coTime,coEndTime);

   FVGInfo  fvgs[]; int nFvgs=0;
   int      c3FvgIdx=-1; datetime triggerTime=0; bool coVisible=false;
   datetime scanEnd=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);

   // Compute min/max activation time windows using the current model's birth resolver.
   TradeWindowResult birthWindow;
   datetime todayOpen=TodayOpenAt(MarketReferenceTime());
   if(B[bb].time<todayOpen || !ResolveBirthTradeWindowCurrentModel(B[bb].time,birthWindow))
     {
      if(allowDeletes) DeleteGenerationVisuals(bull,B[bb].time,sibs,nSibs);
      return;
     }
   string execModelLabel=birthWindow.valid ? TradeWindowShortLabelForOffset(birthWindow.maxHTF+1)
                                           : "CCT";
   datetime firstExecOpen=0,firstExecEnd=0;
   string firstExecLabel="";
   bool openPositionExists=HasOpenCCTPositionForGenKey(execGenKey);
   bool generationHasTradeBacking=HasExecutionVisualBacking(execGenKey);
   bool generationAlreadyLive=(FindExecFamilyTrack(execGenKey)>=0
                               || ExecFamilyHasVisuals(execGenKey)
                               || openPositionExists
                               || generationHasTradeBacking);
   if(!ResolveFirstExecutionWindowForBirth(B[bb].time,firstExecOpen,firstExecEnd,firstExecLabel))
     {
      if(allowDeletes) DeleteGenerationVisuals(bull,B[bb].time,sibs,nSibs);
      return;
     }
   string activeExecModelLabel=execModelLabel;
   datetime activeExecRef=(datetime)SeriesInfoInteger(_Symbol,HTF(),SERIES_LASTBAR_DATE);
   TradeWindowResult activeExecWindow;
   datetime activeExecOpen=0,activeExecEnd=0;
   string activeExecHuman="";
   int activeExecKey=-1;
   if(activeExecRef>0
      && ResolveExecutionWindowForTrigger(activeExecRef,
                                          activeExecWindow,
                                          activeExecOpen,
                                          activeExecEnd,
                                          activeExecHuman,
                                          activeExecKey,
                                          B[bb].time))
      activeExecModelLabel=TradeWindowShortLabelForOffset(activeExecWindow.maxHTF+1);
   if(firstExecEnd>0 && firstExecEnd>segInact)
      segInact=firstExecEnd;
   if(!generationAlreadyLive && nextSameTime>0 && firstExecEnd>0 && MarketReferenceTime()>firstExecEnd)
     {
      if(allowDeletes) DeleteGenerationVisuals(bull,B[bb].time,sibs,nSibs);
      return;
     }

   datetime minActivateTime=0;
   datetime maxActivateTime=0;
   if(!ResolveGenerationActivationWindow(B,n,pSec,bb,pillarOpen,minActivateTime,maxActivateTime))
     {
      if(allowDeletes) DeleteGenerationVisuals(bull,B[bb].time,sibs,nSibs);
      return;
     }

   ScanGeneration(coTime,coPx,bull,sibs,nSibs,scanEnd,pillarOpen,
                  ctrBiasFrom,supersedeAfterTime,lockAfterTime,pSec,
                  minActivateTime,maxActivateTime,nextSameTime,
                  fvgs,nFvgs,c3FvgIdx,triggerTime,coVisible);

   datetime coReachTime=0;
   if(triggerTime>0&&coPx>0)
     {
      string coGenKey=(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
      double persistedCO=0.0;
      if(GetExecCOPrice(coGenKey,persistedCO) && persistedCO>0.0)
         coPx=persistedCO;
      datetime beAnchorTmp=0, beTouchTmp=0, familyExitTmp=0, coTouchTmp=0;
      double   bePriceTmp=0.0, familyExitPxTmp=0.0;
      bool     coFinalTmp=false;
      GetPOIExit(coGenKey,familyExitTmp,familyExitPxTmp);
      ResolveExecMilestones(coGenKey,bull,triggerTime,coPx,familyExitTmp,
                            beAnchorTmp,beTouchTmp,bePriceTmp,coTouchTmp,coFinalTmp);
      coReachTime=coTouchTmp;
     }

   // CO right anchor:
   //   - Accomplished (CO touched): lock to coReachTime
   //   - Active (C1 fired, awaiting C2+C3): extend to current HTF bar end
   //     so the CO line tracks forward bar-by-bar as price sits in the zone
   //   - Not yet active (coVisible=false): use coEndTime from FindCO
   datetime liveEnd=(datetime)(B[n-1].time + pSec - 1);
   datetime coRight=(coReachTime>0)?coReachTime
                   :(coVisible?liveEnd:coEndTime);

   //--- Turtle Soup lifecycle ---
   // Compute bias regime start bar: oldest in-bias birth bar after the
   // most recent counter-bias birth bar before bb.
   // Used as the left boundary for expanding TS rescans when sweeping.
   int biasRegimeStartBar=0;
   {
    // Find newest counter-bias birth bar before bb
    int lastCtrBar=-1;
    if(bull)
      {for(int bx=0;bx<nBear;bx++) if(bearBirths[bx]<bb&&bearBirths[bx]>lastCtrBar) lastCtrBar=bearBirths[bx];}
    else
      {for(int bx=0;bx<nBull;bx++) if(bullBirths[bx]<bb&&bullBirths[bx]>lastCtrBar) lastCtrBar=bullBirths[bx];}
    // First in-bias birth after that counter-bias bar (or bar 0 if none)
    biasRegimeStartBar=0;
    if(bull)
      {for(int bx=0;bx<nBull;bx++) if(bullBirths[bx]>lastCtrBar){biasRegimeStartBar=bullBirths[bx];break;}}
    else
      {for(int bx=0;bx<nBear;bx++) if(bearBirths[bx]>lastCtrBar){biasRegimeStartBar=bearBirths[bx];break;}}
   }

    for(int ts=0;ts<nSibs;ts++)
      {
       SIB_STATE tsst=sibs[ts].state;
       if(sibs[ts].c1Time==0) continue;       // no C1 yet
       if(tsst!=SS_ACTIVE) continue;          // TS is only relevant for the live active pre-trigger path
       if(tsst==SS_KILLED_SUPER) continue;    // superseded — use deeper sib
       if(tsst==SS_KILLED_CO)    continue;    // CO kill — generation dead
       if(tsst==SS_KILLED_WINDOW) continue;   // consumed window kill
      if(tsst==SS_KILLED_SIB)   continue;    // same-generation sibling kill
      if(tsst==SS_DORMANT_CTR)  continue;    // counter-bias dormant
      if(tsst==SS_TRIGGERED)    continue;    // already executed — TS scan closed

      // Expanding rescan: only when a deeper level may have been swept.
      // Gate: current price must have moved beyond the existing tsLevel.
      // This avoids re-running FindTSLevel (expensive CopyRates) every Draw().
      bool needsRescan=false;
      if(sibs[ts].tsLevel>0&&sibs[ts].tsTouchTime>0&&tsst!=SS_TRIGGERED)
        {
         double curBid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double curAsk=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         // Bull POI (bearish wick low): deeper = lower price, check if bid < tsLevel
         // Bear POI (bullish wick high): deeper = higher price, check if ask > tsLevel
         bool priceDeeper=bull?(curBid<sibs[ts].tsLevel):(curAsk>sibs[ts].tsLevel);
         if(priceDeeper)
           {
            needsRescan=true;
            sibs[ts].tsLevel=0.0; sibs[ts].tsWickTime=0;
            sibs[ts].tsTouchTime=0; sibs[ts].tsTouchedBeforeC1=false;
           }
        }

      if(sibs[ts].tsLevel>0) continue;  // already found (no rescan needed)

      FindTSLevel(B,n,pSec,bull,bb,nextSame,sibs[ts].c1Time,sibs[ts].level,
                  sibs[ts].tsLevel,sibs[ts].tsWickTime,
                  sibs[ts].tsTouchTime,sibs[ts].tsTouchedBeforeC1,
                  needsRescan?biasRegimeStartBar:0);
     }

   //--- CO line ---
   // CO is only shown POST-TRIGGER (after C2+C3 confirm). Pre-trigger CO tracks
   // in the background (for kill/lock logic) but is never drawn.
   // Post-trigger CO is drawn via COTR_ in the trigger block below.
   bool accomplished=(triggerTime>0&&coReachTime>0);
   int ownerSibIdx=FindGenerationOwnerSibling(sibs,nSibs);

   // Export active (pre-trigger) signal state for DB1.
   // Only write if there's an active sib with C1 and no trigger yet.
   if(triggerTime==0&&!counterBias)
     {
      for(int sx=0;sx<nSibs;sx++)
        {
         if(sibs[sx].state!=SS_ACTIVE) continue;
         if(sibs[sx].c1Time<=0)        continue;
         if(sibs[sx].c1Time<=g_sigTrigTime) continue; // older than current best
         g_sigTrigTime = sibs[sx].c1Time;
         g_sigC1Time   = sibs[sx].c1Time;
         g_sigBull     = bull;
         g_sigName     = CodenameFromTime(B[bb].time);
         g_sigState    = SS_ACTIVE;
         g_sigC1       = (sibs[sx].c1Time>0);
         g_sigC2       = (sibs[sx].c2Time>0);
         g_sigC3       = (sibs[sx].c3Time>0);
         g_sigBirthTime= B[bb].time;
         g_sigLevel    = sibs[sx].level;
         g_sigCoPx     = coPx;
         g_sigSlPx     = 0;
         g_sigTpPx     = 0;
         g_sigModelLabel=ActualExecutionModelLabelForSibling(sibs[sx],activeExecModelLabel,activeExecRef);
         if(g_sigC2 && g_sigC3 && c3FvgIdx>=0 && c3FvgIdx<nFvgs)
           {
            double liveBid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
            double liveAsk=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
            double signalEntry=bull?liveAsk:liveBid;
            if(signalEntry<=0.0)
               signalEntry=sibs[sx].level;
            FVGInfo cfSig=fvgs[c3FvgIdx];
            double aASig=(Inp_FibMode==FIB_MODE_STANDARD)?cfSig.c1Ext:signalEntry;
            double aBSig=cfSig.c2c3Extreme;
            datetime sigScanTo=(datetime)SeriesInfoInteger(_Symbol,LTF(),SERIES_LASTBAR_DATE);
            double sigSweepProbe=ScanExtremeBetween(cfSig.t3,sigScanTo,bull);
            if(sigSweepProbe<=0.0)
               sigSweepProbe=signalEntry;
            ENUM_SL_BRANCH sigBranch=DetectSLBranch(cfSig,bull,sigSweepProbe);
            g_sigSlPx=CalcFibSL(aASig,aBSig,bull,sigBranch);
            g_sigTpPx=CalcTPRaw(bull,signalEntry,g_sigSlPx,coPx);
           }
         break;
        }
     }

   datetime liveTriggerTime=0;
   double liveEntryPx=0.0,liveSlPx=0.0,liveTpPx=0.0;
   bool hasOpenExecGeometry=GetOpenPositionExecGeometry(execGenKey,liveTriggerTime,liveEntryPx,liveSlPx,liveTpPx);
   datetime replayTriggerTime=0;
   double replayEntryPx=0.0,replaySlPx=0.0,replayTpPx=0.0,replayCoPx=0.0;
   bool hasReplayExecGeometry=GetExecReplayRecord(execGenKey,replayTriggerTime,replayEntryPx,replaySlPx,replayTpPx,replayCoPx);
   if(triggerTime<=0)
     {
      if(hasOpenExecGeometry)
         triggerTime=liveTriggerTime;
      else if(hasReplayExecGeometry)
         triggerTime=replayTriggerTime;
     }

   if(triggerTime>0 && !IsRecentExecutionVisualTime(triggerTime))
     {
      DeleteExecutionVisualFamily(execGenKey);
      triggerTime=0;
     }

   //--- Trigger execution line (replaces arrow) ---
   // Thick 3-pixel horizontal segment at the trigger bar's closing price.
   // Spans bar open (:00:00) to bar close (:59:59). BACK=false so it sits above candles.
   // Also draws permanent SL, TP, CO tracking lines that extend bar-by-bar until hit.
     if(triggerTime>0)
     {
      int ltfSec=(int)PeriodSeconds(LTF());
      MqlRates trigBar[];
      double trigClose=(hasOpenExecGeometry && liveEntryPx>0.0)?liveEntryPx:0.0;
      if(CopyRates(_Symbol,LTF(),triggerTime,1,trigBar)>0) trigClose=trigBar[0].close;
      if(trigClose<=0.0 && liveEntryPx>0.0) trigClose=liveEntryPx;
      double sweepProbe=trigClose;
      if(c3FvgIdx>=0 && c3FvgIdx<nFvgs)
        {
         double scannedSweep=ScanExtremeBetween(fvgs[c3FvgIdx].t3,triggerTime,bull);
         if(scannedSweep>0.0)
            sweepProbe=scannedSweep;
        }

      // Queue broker execution immediately when the trigger is identified.
      // This runs before any execution visuals are built so the broker path
      // does not wait for the rest of the draw cycle to finish.
     if(c3FvgIdx>=0 && c3FvgIdx<nFvgs)
       {
         int trigSibIdx=0;
         for(int tx=0; tx<nSibs; tx++)
           {
           if(sibs[tx].state==SS_TRIGGERED
               || sibs[tx].state==SS_TP_HIT
               || sibs[tx].state==SS_SL_HIT
               || sibs[tx].state==SS_BE_HIT
               || sibs[tx].c3Time>0)
              {
               trigSibIdx=tx;
               break;
              }
           }
         execModelLabel=ResolveTriggerModelLabelForSibling(sibs[trigSibIdx],B[bb].time,triggerTime,execModelLabel);
         FVGInfo cfvg=fvgs[c3FvgIdx];
         double aA=(Inp_FibMode==FIB_MODE_STANDARD)?cfvg.c1Ext:trigClose;
         double aB=cfvg.c2c3Extreme;
         ENUM_SL_BRANCH branchLocked=DetectSLBranch(cfvg,bull,sweepProbe);
         double slRawLocked=CalcFibSL(aA,aB,bull,branchLocked);
         double tpLocked=CalcTPRaw(bull,trigClose,slRawLocked,coPx);
         double riskLocked=MathAbs(trigClose-slRawLocked);
         double rrLocked=(riskLocked>_Point)?(MathAbs(tpLocked-trigClose)/riskLocked):0.0;
         datetime expiryTime=PendingExecHardExpiry(triggerTime);
         RegisterReplayTriggeredPOI(triggerTime,trigClose,slRawLocked,tpLocked,execGenKey,coPx);
         datetime trigC1Time = (trigSibIdx>=0 && trigSibIdx<nSibs) ? sibs[trigSibIdx].c1Time : 0;
         RegisterPendingExec(bull,trigClose,slRawLocked,tpLocked,rrLocked,coPx,triggerTime,B[bb].time,expiryTime,execModelLabel,trigC1Time);
        }

      if(!renderVisuals)
         return;

      // All execution objects span from (triggerTime - 1 bar) to one full LTF bar
      // ahead of the current live bar while the trade is still unresolved.
      // This keeps the current bar's wick/body visually clear while preserving the
      // existing rule that resolved families lock back to the actual hit bar.
       // genKey must match RegisterExecutedPOI: "BU_"+birthTime or "BE_"+birthTime
       string genKey=execGenKey;
       RegisterExecFamilyTrack(genKey,bull,triggerTime,coPx);
       double persistedCO=0.0;
       if(GetExecCOPrice(genKey,persistedCO) && persistedCO>0.0)
          coPx=persistedCO;
      datetime execL   =(datetime)(triggerTime-ltfSec);             // 1 bar before trigger
      datetime execRInit=iTime(_Symbol,LTF(),0)+(datetime)(2*ltfSec-1); // NEXT bar end — live
      datetime newGenCap=0;
      datetime execR=execRInit;
      datetime actualExecR=execR;
      datetime curBarOpen=iTime(_Symbol,LTF(),0);
      execRInit=(datetime)(curBarOpen+2*ltfSec-1);
      execR=execRInit;
      actualExecR=execR;
       bool brokerTradeExists=(hasOpenExecGeometry || hasReplayExecGeometry);
       double execEntryPx=0.0;
       double execSlPx=0.0;
       double execTpPx=0.0;
       bool hasExecVisualState=false;
       if(hasOpenExecGeometry)
         {
          execEntryPx=liveEntryPx;
          execSlPx=liveSlPx;
          execTpPx=liveTpPx;
          hasExecVisualState=(execEntryPx>0.0 && execSlPx>0.0 && execTpPx>0.0);
         }
       else if(hasReplayExecGeometry)
         {
          execEntryPx=replayEntryPx;
          execSlPx=replaySlPx;
          execTpPx=replayTpPx;
          hasExecVisualState=(execEntryPx>0.0 && execSlPx>0.0 && execTpPx>0.0);
          if(replayCoPx>0.0)
             coPx=replayCoPx;
         }
       datetime familyExitTime=0;
       double   familyExitPrice=0.0;
       GetPOIExit(genKey,familyExitTime,familyExitPrice);
      datetime beAnchorTime=0;
      datetime beTouchTime=0;
      double   beVisualPx=0.0;
      datetime coTouchTime=0;
      bool     coFinalized=false;
      ResolveExecMilestones(genKey,bull,triggerTime,coPx,familyExitTime,
                            beAnchorTime,beTouchTime,beVisualPx,coTouchTime,coFinalized);
      bool hasResolvedExit=(familyExitTime>0);
      bool keepRecentResolvedVisible=(!hasResolvedExit || IsRecentExecutionVisualTime(familyExitTime));
       bool hasScannerExecGeometry=(c3FvgIdx>=0&&c3FvgIdx<nFvgs);
       bool hasBrokerExecGeometry=(hasExecVisualState && execSlPx>0.0 && execTpPx>0.0);
       bool canDrawExecGeometry=(hasScannerExecGeometry || hasBrokerExecGeometry);
      if(familyExitTime>0)
        {
         actualExecR=(datetime)(familyExitTime + ltfSec - 1);
        }
      else if(hasScannerExecGeometry)
        {
         double slPxExec=execSlPx;
         double tpPxExec=execTpPx;
         if(slPxExec<=0.0 || tpPxExec<=0.0)
           {
            FVGInfo cfExec=fvgs[c3FvgIdx];
            double aAExec=(Inp_FibMode==FIB_MODE_STANDARD)?cfExec.c1Ext:trigClose;
            double aBExec=cfExec.c2c3Extreme;
            double execSweepProbe=ScanExtremeBetween(cfExec.t3,triggerTime,bull);
            if(execSweepProbe<=0.0) execSweepProbe=trigClose;
            ENUM_SL_BRANCH branchExec=DetectSLBranch(cfExec,bull,execSweepProbe);
            slPxExec=CalcFibSL(aAExec,aBExec,bull,branchExec);
            tpPxExec=CalcTPRaw(bull,trigClose,slPxExec,coPx);
           }
         datetime trackedSlHitTime=ScanHit(triggerTime, slPxExec, bull);
         datetime trackedTpHitTime=ScanHit(triggerTime, tpPxExec, !bull);
         datetime trackedTradeEndTime=0;
         if(trackedSlHitTime > 0) trackedTradeEndTime = trackedSlHitTime;
         if(trackedTpHitTime > 0 && (trackedTradeEndTime == 0 || trackedTpHitTime < trackedTradeEndTime))
            trackedTradeEndTime = trackedTpHitTime;
         if(trackedTradeEndTime > 0)
            actualExecR=(datetime)(trackedTradeEndTime + ltfSec - 1);
        }

      // ── Entry marker: static 2-bar horizontal at trigger close ──────────────
      string trigNm=PFX+"TRIG_"+genKey;
      ObjCacheRegister(trigNm);
      SIB_STATE trigOutcome=GetPOIOutcome(genKey);
      bool trigResolved=(trigOutcome==SS_TP_HIT || trigOutcome==SS_SL_HIT || trigOutcome==SS_BE_HIT);
      datetime visibleExecR=actualExecR;
      if(trigResolved && hasResolvedExit && !keepRecentResolvedVisible)
        {
         DeleteExecutionVisualFamily(genKey);
        }
      else if(ObjectFind(0,trigNm)<0)
        {
         ObjectCreate(0,trigNm,OBJ_TREND,0,execL,trigClose,visibleExecR,trigClose);
         ObjectSetDouble (0,trigNm,OBJPROP_PRICE,0,trigClose);
         ObjectSetDouble (0,trigNm,OBJPROP_PRICE,1,trigClose);
         ObjectSetInteger(0,trigNm,OBJPROP_ZORDER,  0);
         ObjectSetInteger(0,trigNm,OBJPROP_COLOR,   Inp_ClrExecTrigger);
         ObjectSetInteger(0,trigNm,OBJPROP_STYLE,   CCTLineStyle(Inp_StyExecTrigger));
         ObjectSetInteger(0,trigNm,OBJPROP_WIDTH,   CCTLineWidth(Inp_WidExecTrigger));
         ObjectSetInteger(0,trigNm,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,trigNm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,trigNm,OBJPROP_BACK,    false);
         ObjectSetInteger(0,trigNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
         ObjectSetString (0,trigNm,OBJPROP_TOOLTIP,TooltipFit(
                         "Execution Line  "+(bull?"▲ LONG":"▼ SHORT")+"\n"
                         +"  Family: "+genKey+"\n"
                         +"  Model : "+execModelLabel+"\n"
                         +"  Price : "+DoubleToString(trigClose,_Digits)+"\n"
                         +"  Time  : "+NYStr(triggerTime)+"\n"
                         +"  Role  : Exact trigger/execution price"));
        }
      else
        {
         ObjectSetInteger(0,trigNm,OBJPROP_TIME,1,visibleExecR);
        }
      {
       string trigTip="Execution Line  "+(bull?"▲ LONG":"▼ SHORT")+"\n"
                     +"  Family: "+genKey+"\n"
                     +"  Model : "+execModelLabel+"\n"
                     +"  Price : "+DoubleToString(trigClose,_Digits)+"\n"
                     +"  Time  : "+NYStr(triggerTime)+"\n"
                     +"  Role  : Exact trigger/execution price";
       UpsertExecTooltipCarrier(trigNm,execL,trigClose,visibleExecR,trigClose,trigTip,LTFMaxTFs(),false,6);
      }

      if(canDrawExecGeometry && (!trigResolved || keepRecentResolvedVisible))
        {
         FVGInfo cf;
         ZeroMemory(cf);
         if(hasScannerExecGeometry)
            cf=fvgs[c3FvgIdx];
         double aA2=hasScannerExecGeometry ? ((Inp_FibMode==FIB_MODE_STANDARD)?cf.c1Ext:trigClose)
                                           : trigClose;
         double aB2=hasScannerExecGeometry ? cf.c2c3Extreme : trigClose;
         ENUM_SL_BRANCH slBranch=hasScannerExecGeometry ? DetectSLBranch(cf,bull,sweepProbe)
                                                        : SL_BRANCH_VSHAPE;
         double slPx=hasBrokerExecGeometry ? execSlPx
                                          : CalcFibSL(aA2,aB2,bull,slBranch);
         double risk=MathAbs(trigClose-slPx);
         double tpPx=hasBrokerExecGeometry ? execTpPx
                                          : CalcTPRaw(bull,trigClose,slPx,coPx);
         double floorTpPx = bull ? (trigClose + Inp_MinRR_Eff()*risk)
                                 : (trigClose - Inp_MinRR_Eff()*risk);
         bool   coBeyondFloor = Inp_UseCoIfFarther && coPx>0.0
                                && (bull ? (coPx>floorTpPx) : (coPx<floorTpPx));
         double rr=(risk>0)?MathAbs(tpPx-trigClose)/risk:0;
         string slConfigLabel=hasScannerExecGeometry ? ("Fib "+FibBranchLabel(slBranch))
                                                    : "Broker-backed execution";

           double sprd=0;
           if(Inp_ApplySpread)
              sprd=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
           double tpPxFinal=hasBrokerExecGeometry ? execTpPx : tpPx;
           double tpBoxBasePx=(hasExecVisualState&&execEntryPx>0.0)
                              ? execEntryPx
                              : trigClose;

            // ── SL line: red horizontal, tracks until SL touched ────────────────
            string slNm=PFX+"HNT_S_"+genKey;
            ObjCacheRegister(slNm);
            double slPxFinal = hasBrokerExecGeometry
                               ? execSlPx
                               : (bull ? slPx - sprd : slPx + sprd);
            if(ObjectFind(0,slNm)<0)
              {
                ObjectCreate(0,slNm,OBJ_TREND,0,execL,slPxFinal,visibleExecR,slPxFinal);
                ObjectSetDouble (0,slNm,OBJPROP_PRICE,0,slPxFinal);
                ObjectSetDouble (0,slNm,OBJPROP_PRICE,1,slPxFinal);
               ObjectSetInteger(0,slNm,OBJPROP_ZORDER,    0);
               ObjectSetInteger(0,slNm,OBJPROP_COLOR,     Inp_ClrExecSL);
               ObjectSetInteger(0,slNm,OBJPROP_STYLE,     CCTLineStyle(Inp_StyExecSL));
               ObjectSetInteger(0,slNm,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidExecSL));
               ObjectSetInteger(0,slNm,OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(0,slNm,OBJPROP_SELECTABLE,false);
               ObjectSetInteger(0,slNm,OBJPROP_BACK,      false);
               ObjectSetInteger(0,slNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
              ObjectSetString (0,slNm,OBJPROP_TOOLTIP,TooltipFit(
                                "■ Stop Loss\n"
                                +"  Family : "+genKey+"\n"
                                +"  Model  : "+execModelLabel+"\n"
                                +"  Level  : "+DoubleToString(slPxFinal,_Digits)+"\n"
                                +"  Risk   : "+DoubleToString(risk/_Point,0)+" pts\n"
                                +"  Risk % : "+DoubleToString(g_riskPct,2)+"%\n"
                                +"  Config : "+slConfigLabel));
              }
            else
              {
               ObjectSetInteger(0,slNm,OBJPROP_TIME,1,visibleExecR);
              }
            {
             string slTip="■ Stop Loss\n"
                         +"  Family : "+genKey+"\n"
                         +"  Model  : "+execModelLabel+"\n"
                         +"  Level  : "+DoubleToString(slPxFinal,_Digits)+"\n"
                         +"  Risk   : "+DoubleToString(risk/_Point,0)+" pts\n"
                         +"  Risk % : "+DoubleToString(g_riskPct,2)+"%\n"
                         +"  Config : "+slConfigLabel;
             UpsertExecTooltipCarrier(slNm,execL,slPxFinal,visibleExecR,slPxFinal,slTip,LTFMaxTFs(),false,6);
            }
            // Do not unconditionally update - let DrawHints handle tracking and locking

            // ── TP line: green horizontal, tracks until TP touched ───────────────
            string tpNm=PFX+"HNT_T_"+genKey;
            ObjCacheRegister(tpNm);
            if(ObjectFind(0,tpNm)<0)
              {
                ObjectCreate(0,tpNm,OBJ_TREND,0,execL,tpPxFinal,visibleExecR,tpPxFinal);
                ObjectSetDouble (0,tpNm,OBJPROP_PRICE,0,tpPxFinal);
                ObjectSetDouble (0,tpNm,OBJPROP_PRICE,1,tpPxFinal);
               ObjectSetInteger(0,tpNm,OBJPROP_ZORDER,    0);
               ObjectSetInteger(0,tpNm,OBJPROP_COLOR,     Inp_ClrExecTP);
               ObjectSetInteger(0,tpNm,OBJPROP_STYLE,     CCTLineStyle(Inp_StyExecTP));
               ObjectSetInteger(0,tpNm,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidExecTP));
               ObjectSetInteger(0,tpNm,OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(0,tpNm,OBJPROP_SELECTABLE,false);
               ObjectSetInteger(0,tpNm,OBJPROP_BACK,      false);
               ObjectSetInteger(0,tpNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
                ObjectSetString (0,tpNm,OBJPROP_TOOLTIP,TooltipFit(
                                 "▲ Take Profit\n"
                                 +"  Family : "+genKey+"\n"
                                 +"  Model  : "+execModelLabel+"\n"
                                 +"  Level  : "+DoubleToString(tpPxFinal,_Digits)+"\n"
                                 +"  R/R    : 1:"+DoubleToString(rr,2)+"\n"
                                 +"  Target : "+(hasBrokerExecGeometry?"Broker-backed execution TP":(coBeyondFloor?"CO beyond RR floor":"RR floor only"))+"\n"
                                 +"  Reward : +"+DoubleToString(g_riskPct*rr,2)+"%"));
              }
            else
              {
               ObjectSetDouble (0,tpNm,OBJPROP_PRICE,0,tpPxFinal);
               ObjectSetDouble (0,tpNm,OBJPROP_PRICE,1,tpPxFinal);
                ObjectSetInteger(0,tpNm,OBJPROP_TIME,1,visibleExecR);
              }
            {
             string tpTip="▲ Take Profit\n"
                         +"  Family : "+genKey+"\n"
                         +"  Model  : "+execModelLabel+"\n"
                         +"  Level  : "+DoubleToString(tpPxFinal,_Digits)+"\n"
                         +"  R/R    : 1:"+DoubleToString(rr,2)+"\n"
                         +"  Target : "+(hasBrokerExecGeometry?"Broker-backed execution TP":(coBeyondFloor?"CO beyond RR floor":"RR floor only"))+"\n"
                         +"  Reward : +"+DoubleToString(g_riskPct*rr,2)+"%";
             UpsertExecTooltipCarrier(tpNm,execL,tpPxFinal,visibleExecR,tpPxFinal,tpTip,LTFMaxTFs(),false,6);
            }
            // Do not unconditionally update - let DrawHints handle tracking and locking

         // BE line created dynamically by DrawHints once price reaches BE trigger %

         // ── SL box: muted grey zone entry↔SL, static 30-min span ────────────
         string slBoxNm=PFX+"BOX_SL_"+genKey;
         ObjCacheRegister(slBoxNm);
        if(ObjectFind(0,slBoxNm)<0)
          {
            double hi=MathMax(trigClose,slPxFinal), lo=MathMin(trigClose,slPxFinal);
           ObjectCreate(0,slBoxNm,OBJ_RECTANGLE,0,execL,hi,visibleExecR,lo);
          ObjectSetInteger(0,slBoxNm,OBJPROP_ZORDER,    0);
           ObjectSetInteger(0,slBoxNm,OBJPROP_COLOR,     Inp_ClrExecSLBox);
            ObjectSetInteger(0,slBoxNm,OBJPROP_FILL,      false);
            ObjectSetInteger(0,slBoxNm,OBJPROP_BACK,      false);
           ObjectSetInteger(0,slBoxNm,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidExecSLBox));
           ObjectSetInteger(0,slBoxNm,OBJPROP_STYLE,     CCTLineStyle(Inp_StyExecSLBox));
           ObjectSetInteger(0,slBoxNm,OBJPROP_RAY_RIGHT, false);
           ObjectSetInteger(0,slBoxNm,OBJPROP_SELECTABLE,false);
           ObjectSetInteger(0,slBoxNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
           ObjectSetString (0,slBoxNm,OBJPROP_TOOLTIP,"\n");
          }
        else
          {
           ObjectSetInteger(0,slBoxNm,OBJPROP_TIME,1,visibleExecR);
          }
        ObjectSetString (0,slBoxNm,OBJPROP_TOOLTIP,"\n");
        ObjectSetInteger(0,slBoxNm,OBJPROP_FILL,false);
        ObjectSetInteger(0,slBoxNm,OBJPROP_BACK,false);

          // ── TP box: muted blue zone entry↔TP, static 30-min span ────────────
          string tpBoxNm=PFX+"BOX_TP_"+genKey;
          ObjCacheRegister(tpBoxNm);
         if(ObjectFind(0,tpBoxNm)<0)
            {
             double hi=MathMax(tpBoxBasePx,tpPxFinal), lo=MathMin(tpBoxBasePx,tpPxFinal);
            ObjectCreate(0,tpBoxNm,OBJ_RECTANGLE,0,execL,hi,visibleExecR,lo);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_ZORDER,    0);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_COLOR,     Inp_ClrExecTPBox);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_FILL,      false);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_BACK,      false);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidExecTPBox));
             ObjectSetInteger(0,tpBoxNm,OBJPROP_STYLE,     CCTLineStyle(Inp_StyExecTPBox));
             ObjectSetInteger(0,tpBoxNm,OBJPROP_RAY_RIGHT, false);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_SELECTABLE,false);
             ObjectSetInteger(0,tpBoxNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
              ObjectSetString (0,tpBoxNm,OBJPROP_TOOLTIP,"\n");
            }
          else
            {
             double hi=MathMax(tpBoxBasePx,tpPxFinal), lo=MathMin(tpBoxBasePx,tpPxFinal);
             ObjectSetDouble (0,tpBoxNm,OBJPROP_PRICE,0,hi);
             ObjectSetDouble (0,tpBoxNm,OBJPROP_PRICE,1,lo);
              ObjectSetInteger(0,tpBoxNm,OBJPROP_TIME,1,visibleExecR);
            }
          ObjectSetString (0,tpBoxNm,OBJPROP_TOOLTIP,"\n");
          ObjectSetInteger(0,tpBoxNm,OBJPROP_FILL,false);
          ObjectSetInteger(0,tpBoxNm,OBJPROP_BACK,false);

          // ── CO tracking line: only when CO falls between entry and TP ────────
           double coPxFinal = coPx;
          bool coVisible2=(coPx>0&&(bull?(coPxFinal<=tpPxFinal&&coPxFinal>trigClose)
                                        :(coPxFinal>=tpPxFinal&&coPxFinal<trigClose)));
          SIB_STATE coOutcome=GetPOIOutcome(genKey);
          bool coResolvedTP=(coOutcome==SS_TP_HIT);
          bool coResolvedNoTouch=(coTouchTime<=0 && coFinalized);
          bool coTradeOpen=(!coResolvedNoTouch
                            && !coResolvedTP
                            && (coOutcome==SS_TRIGGERED || coOutcome==SS_UNKNOWN_OUTCOME));
          if(coVisible2)
            {
             string coNm=PFX+"COTR_"+genKey;
             datetime coTL=(coTime>0)?coTime:execL;
             datetime coTR=(coTouchTime>0)?(datetime)(coTouchTime+ltfSec-1)
                                         :(coTradeOpen?actualExecR:((coEndTime>0)?coEndTime:execR));
             double   coPxForObject = coPxFinal;
             ObjCacheRegister(coNm);
             if(coResolvedTP || coResolvedNoTouch || (!coTradeOpen && coTouchTime<=0))
               {
                DeleteNamedObject(coNm);
               }
             else if(ObjectFind(0,coNm)<0)
               {
                ObjectCreate(0,coNm,OBJ_TREND,0,coTL,coPxForObject,coTR,coPxForObject);
                ObjectSetDouble (0,coNm,OBJPROP_PRICE,0,coPxForObject);
                ObjectSetDouble (0,coNm,OBJPROP_PRICE,1,coPxForObject);
               ObjectSetInteger(0,coNm,OBJPROP_ZORDER,    0);
               ObjectSetInteger(0,coNm,OBJPROP_COLOR,     Inp_ClrExecCO);
               ObjectSetInteger(0,coNm,OBJPROP_STYLE,     CCTLineStyle(Inp_StyExecCO));
               ObjectSetInteger(0,coNm,OBJPROP_WIDTH,     CCTLineWidth(Inp_WidExecCO));
               ObjectSetInteger(0,coNm,OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(0,coNm,OBJPROP_SELECTABLE,false);
               ObjectSetInteger(0,coNm,OBJPROP_BACK,      false);
               ObjectSetInteger(0,coNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
              ObjectSetString (0,coNm,OBJPROP_TOOLTIP,TooltipFit(
                                "◆ Correction Origin\n"
                                +"  Family : "+genKey+"\n"
                                +"  Model  : "+execModelLabel+"\n"
                                +"  Level  : "+DoubleToString(coPx,_Digits)+"\n"
                                +"  Anchor : "+NYStr((coTime>0)?coTime:triggerTime)+"\n"
                                +"  Notes  : Latched on first post-trigger touch"));
              }
             else
               {
                ObjectSetInteger(0,coNm,OBJPROP_TIME,0,coTL);
                ObjectSetInteger(0,coNm,OBJPROP_TIME,1,coTR);
                ObjectSetDouble (0,coNm,OBJPROP_PRICE,0,coPxForObject);
                ObjectSetDouble (0,coNm,OBJPROP_PRICE,1,coPxForObject);
               }
             string coTip="◆ Correction Origin\n"
                         +"  Family : "+genKey+"\n"
                         +"  Model  : "+execModelLabel+"\n"
                         +"  Level  : "+DoubleToString(coPx,_Digits)+"\n"
                         +"  Anchor : "+NYStr((coTime>0)?coTime:triggerTime)+"\n"
                         +"  Notes  : Latched on first post-trigger touch";
             UpsertExecTooltipCarrier(coNm,coTL,coPxForObject,coTR,coPxForObject,coTip,LTFMaxTFs(),false,6);
            }
        } // end if(c3FvgIdx valid)

      // Export signal state for DB1 dashboard
      if(c3FvgIdx>=0&&triggerTime>g_sigTrigTime)
        {
         int trigSibIdx=0;
         for(int tx=0; tx<nSibs; tx++)
           {
            if(sibs[tx].state==SS_TRIGGERED
               || sibs[tx].state==SS_TP_HIT
               || sibs[tx].state==SS_SL_HIT
               || sibs[tx].state==SS_BE_HIT)
              {
               trigSibIdx=tx;
               break;
              }
           }
          FVGInfo cf2=fvgs[c3FvgIdx];
          double aA3=(Inp_FibMode==FIB_MODE_STANDARD)?cf2.c1Ext:trigClose;
          double aB3=cf2.c2c3Extreme;
          double sigSweepProbe=ScanExtremeBetween(cf2.t3,triggerTime,bull);
          if(sigSweepProbe<=0.0) sigSweepProbe=trigClose;
         ENUM_SL_BRANCH slBranch3=DetectSLBranch(cf2,bull,sigSweepProbe);
         double slPx3=CalcFibSL(aA3,aB3,bull,slBranch3);
          double tpPx3=CalcTPRaw(bull,trigClose,slPx3,coPx);
          g_sigTrigTime=triggerTime; g_sigBull=bull; g_sigName=CodenameFromTime(B[bb].time);
          g_sigState=SS_TRIGGERED;
          g_sigC1=(sibs[trigSibIdx].c1Time>0); g_sigC2=(sibs[trigSibIdx].c2Time>0); g_sigC3=(sibs[trigSibIdx].c3Time>0);
          g_sigBirthTime=B[bb].time;
          g_sigLevel=sibs[trigSibIdx].level;
          g_sigSlPx=slPx3; g_sigTpPx=tpPx3;
          g_sigCoPx=coPx;
          g_sigModelLabel=ResolveTriggerModelLabelForSibling(sibs[trigSibIdx],B[bb].time,triggerTime,execModelLabel);
          g_sigC1Time=(trigSibIdx>=0 && trigSibIdx<nSibs) ? sibs[trigSibIdx].c1Time : 0;
        }

     } // end if(triggerTime>0)

   if(!renderVisuals)
      return;


   // CO reach hint removed — CO line locks via time-based lock in DrawHints

   //--- POI lines ---
   for(int s=0;s<nSibs;s++)
     {
      int       wi=sibs[s].wickIdx;
      datetime  wt=sibs[s].wickTime;
      SIB_STATE st=sibs[s].state;
      if(B[bb].time<drawFrom) continue;
      string wickKey=IntegerToString((int)wt);
      string genKeyStyle=(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
      bool poiOwnsTrade=(ownerSibIdx==s);
      bool poiHasTradeBacking=(generationHasTradeBacking && poiOwnsTrade);
      bool poiTradeCarrier=(poiOwnsTrade
                            && (st==SS_TRIGGERED
                                || st==SS_TP_HIT
                                || st==SS_SL_HIT
                                || st==SS_BE_HIT
                                || (sibs[s].c1Time>0 && sibs[s].c2Time>0 && sibs[s].c3Time>0)));

      bool isDead      =(st==SS_KILLED_CO||st==SS_KILLED_WINDOW||st==SS_KILLED_SIB||st==SS_KILLED_SUPER||st==SS_KILLED_MIN);
      bool isDormant   =(st==SS_DORMANT);
      bool isCtrDormant=(st==SS_DORMANT_CTR);
      // Counter-bias dormant: invisible — never shown even with ShowKilled
      if(isCtrDormant)
        {
         if(allowDeletes) DeleteSiblingVisualFamily(bull,B[bb].time,wt);
         continue;
        }
      if(isDead && !(poiHasTradeBacking && poiTradeCarrier) && !Inp_ShowKilled)
        {
         if(allowDeletes) DeleteSiblingVisualFamily(bull,B[bb].time,wt);
         continue;
        }
      // In-bias dormant: controlled by per-bias toggles, hidden by default
      if(isDormant && !(poiHasTradeBacking && poiTradeCarrier)
         && !biasFlipped && !Inp_ShowDormantInBias)
        {
         if(allowDeletes) DeleteSiblingVisualFamily(bull,B[bb].time,wt);
         continue;
        }
       if(counterBias && !(poiHasTradeBacking && poiTradeCarrier) && !isDead && !isDormant && !isCtrDormant)
         {
          if(allowDeletes) DeleteSiblingVisualFamily(bull,B[bb].time,wt);
          continue;
         }

       datetime coreVisualFrom=CoreVisualStart();
       datetime resolvedPoiVisualFrom=ResolvedPOIVisualStart();
       datetime poiVisualAnchor=(triggerTime>0)?triggerTime:pillarOpen;

       // Get persistent outcome state for triggered POIs
       // genKey must match what RegisterExecutedPOI uses: "BU_"+birthTime or "BE_"+birthTime
       SIB_STATE effectiveSt = st;
       SIB_STATE outcomeSt = SS_UNKNOWN_OUTCOME;
       if(poiOwnsTrade)
          outcomeSt = GetPOIOutcome(genKeyStyle);
       if((outcomeSt == SS_TP_HIT || outcomeSt == SS_SL_HIT || outcomeSt == SS_BE_HIT)
          && poiHasTradeBacking && poiTradeCarrier)
          effectiveSt = outcomeSt;
       else if(poiOwnsTrade && (st == SS_TRIGGERED || (poiHasTradeBacking && poiTradeCarrier)))
         {
          effectiveSt = outcomeSt;
           if(effectiveSt == SS_UNKNOWN_OUTCOME) effectiveSt = st; // fall back to scanner-derived state
           if(effectiveSt == SS_CO_HIT) effectiveSt = SS_TRIGGERED;
         }

       bool resolvedTrade=(effectiveSt == SS_TP_HIT || effectiveSt == SS_SL_HIT || effectiveSt == SS_BE_HIT);
       datetime exitT = 0;
       double exitP = 0.0;
       bool hasExit=GetPOIExit(genKeyStyle, exitT, exitP);
       bool keepCoreVisible=true;
       if(isDormant || isCtrDormant)
          keepCoreVisible=true;
       else if(resolvedTrade)
          keepCoreVisible=(poiVisualAnchor>=resolvedPoiVisualFrom);
       else
          keepCoreVisible=(poiVisualAnchor>=coreVisualFrom);
      if(!keepCoreVisible)
        {
          if(allowDeletes) DeleteSiblingVisualFamily(bull,B[bb].time,wt);
          continue;
        }

        // Determine whether SS_INACTIVE sibs should display as VALID or INACTIVE.
       // VALID  = no C1 has fired anywhere in this generation (fresh, awaiting first contact).
       // INACTIVE = C1 has fired on at least one sib; remaining deeper sibs await their turn.
       bool hasAnyC1=false;
       for(int sx=0;sx<nSibs;sx++) if(sibs[sx].c1Time>0){hasAnyC1=true;break;}
       string stLbl;
       // Use effective (resolved) state for labels
       if(effectiveSt==SS_TP_HIT)         stLbl="CLOSED — TP HIT";
       else if(effectiveSt==SS_SL_HIT)    stLbl="CLOSED — SL HIT";
       else if(effectiveSt==SS_BE_HIT)    stLbl="CLOSED — BE HIT";
       else if(effectiveSt==SS_TRIGGERED) stLbl="TRIGGERED";
       else if(effectiveSt==SS_ACTIVE)    stLbl="ACTIVE — C1 confirmed, await C2+C3";
       else if(effectiveSt==SS_INACTIVE)   stLbl=hasAnyC1?"INACTIVE (post-C1 CO-return)":"VALID";
       else if(effectiveSt==SS_DORMANT)    stLbl="IN-BIAS DORMANT";
       else if(effectiveSt==SS_KILLED_CO)  stLbl="DEAD — CO reached without C2+C3";
       else if(effectiveSt==SS_KILLED_WINDOW) stLbl="DEAD — execution window already consumed";
       else if(effectiveSt==SS_KILLED_SIB) stLbl="DEAD — deeper sibling killed on same-generation trigger";
       else if(effectiveSt==SS_KILLED_MIN) stLbl="DEAD — outside session window";
       else if(effectiveSt==SS_KILLED_SUPER) stLbl="DEAD — superseded by deeper sib";
       else if(effectiveSt==SS_DORMANT_CTR) stLbl="DEAD — counter-bias flip";
       else                                stLbl="DEAD";

       string pathStr="";
       if(effectiveSt==SS_TRIGGERED)
         {
          string pathLbl=(sibs[s].c3Time<sibs[s].c2Time)?"Path A":"Path B";
          pathStr="\n"+pathLbl+" ✓  ▸ ACTIVE";
         }
       else if(effectiveSt==SS_TP_HIT)
         {
          pathStr="\n"+(sibs[s].c3Time<sibs[s].c2Time?"Path A":"Path B")+" ✓  ▸ TP HIT";
         }
       else if(effectiveSt==SS_SL_HIT)
         {
          pathStr="\n"+(sibs[s].c3Time<sibs[s].c2Time?"Path A":"Path B")+" ✓  ▸ SL HIT";
         }
       else if(effectiveSt==SS_BE_HIT)
         {
          pathStr="\n"+(sibs[s].c3Time<sibs[s].c2Time?"Path A":"Path B")+" ✓  ▸ BE HIT";
         }
        else if(effectiveSt==SS_INACTIVE&&!hasAnyC1)
          {
           pathStr="\nAwaiting activation";
          }
        else if(effectiveSt==SS_ACTIVE)
          {
           bool hC1=sibs[s].c1Time>0,hC2=sibs[s].c2Time>0,hC3=sibs[s].c3Time>0;
           if(hC1&&hC3&&!hC2)      pathStr="\nPthA: await C2";
            else if(hC1&&hC2&&!hC3) pathStr="\nPthB: await C3";
            else if(hC1&&!hC2&&!hC3)pathStr="\nC1 Acc — await C2/C3";
           }
      // Add exit info at the TOP of tooltip (before MT5 truncation) for resolved trades
      string exitLine="";
      if(effectiveSt==SS_TP_HIT || effectiveSt==SS_SL_HIT || effectiveSt==SS_BE_HIT)
        {
         if(hasExit)
           {
            string exitType="EXIT";
            if(effectiveSt==SS_TP_HIT) exitType="TP HIT";
            else if(effectiveSt==SS_SL_HIT) exitType="SL HIT";
            else if(effectiveSt==SS_BE_HIT) exitType="BE HIT";
            exitLine = "*** "+exitType+" @ "+NYStr(exitT)+" "+DoubleToString(exitP,_Digits)+" ***\n";
           }
        }
      
      string tip=exitLine+CodenameFromTime(B[wi].time)+"  "+dir+"  "+DoubleToString(sibs[s].level,_Digits)
                +"\n"+stLbl
                +"\nPOI:  "+NYStr(B[wi].time)
                +"\nBorn: "+NYStr(B[bb].time)
                +"\nWndw: "+NYStr(pillarOpen)
                +"\n— C1 Acc:  "+(sibs[s].c1Time>0?NYStr(sibs[s].c1Time):"—")
                +"\n— C2 Rec:  "+(sibs[s].c2Time>0?NYStr(sibs[s].c2Time):"—")
                +"\n— C3 IFVG: "+(sibs[s].c3Time>0
                  ?(NYStr(sibs[s].c3Time)
                    +(c3FvgIdx>=0
                      ?("  ["+DoubleToString(bull?fvgs[c3FvgIdx].c3Ext:fvgs[c3FvgIdx].c1Ext,_Digits)
                        +" — "+DoubleToString(bull?fvgs[c3FvgIdx].c1Ext:fvgs[c3FvgIdx].c3Ext,_Digits)+"]")
                      :""))
                  :"—")
                +pathStr;

      // POI line extension rules:
      // SS_ACTIVE:    extends through the current live HTF window while unresolved
      // SS_TRIGGERED: extends to current live bar end while trade is open (SL/TP/BE not hit)
      //               locks to the bar where SL/TP/BE was first hit once the trade is closed
      // All others:   ends at pillarOpen-1 (execution window end)
      datetime segEnd=segInact;
      if(effectiveSt==SS_ACTIVE)
        {
         datetime liveActiveEnd=(datetime)(B[n-1].time + pSec - 1);
         segEnd=liveActiveEnd;
         if(Inp_ShowDebug)
            PrintFormat("[CCT DBG] POI bb=%d ACTIVE c1T=%s segEnd=%s pillar=%s",
                        bb,NYStr(sibs[s].c1Time),NYStr(segEnd),NYStr(pillarOpen));
        }
      else if(effectiveSt==SS_KILLED_WINDOW)
        {
         datetime liveKilledEnd=(datetime)(B[n-1].time + pSec - 1);
         if(nextSameTime>0)
           {
            datetime nextBirthBarEnd=(datetime)(nextSameTime+pSec-1);
            if(nextBirthBarEnd<liveKilledEnd) liveKilledEnd=nextBirthBarEnd;
           }
         segEnd=liveKilledEnd;
        }
      else if(effectiveSt==SS_TRIGGERED || effectiveSt==SS_TP_HIT || effectiveSt==SS_SL_HIT || effectiveSt==SS_BE_HIT)
        {
         // A trade is "open" if its SL line's right edge is still in the current or future bar.
         // A trade is "closed" when ANY of SL/TP/BE has been time-locked (tR < curBarOpen).
         // Pick the earliest lock time among the three as the definitive close time.
         string genKey=(bull?"BU":"BE")+"_"+IntegerToString((int)B[bb].time);
         datetime curBarOpen=iTime(_Symbol,LTF(),0);
         string slNm=PFX+"HNT_S_"+genKey;
         string tpNm=PFX+"HNT_T_"+genKey;
         string beNm=PFX+"HNT_B_"+genKey;

         datetime slTR=(ObjectFind(0,slNm)>=0)?(datetime)ObjectGetInteger(0,slNm,OBJPROP_TIME,1):0;
         datetime tpTR=(ObjectFind(0,tpNm)>=0)?(datetime)ObjectGetInteger(0,tpNm,OBJPROP_TIME,1):0;
         datetime beTR=(ObjectFind(0,beNm)>=0)?(datetime)ObjectGetInteger(0,beNm,OBJPROP_TIME,1):0;

         // A line is locked (trade exit reached) when tR < curBarOpen
         bool slLocked=(slTR>0&&slTR<curBarOpen);
         bool tpLocked=(tpTR>0&&tpTR<curBarOpen);
         bool beLocked=(beTR>0&&beTR<curBarOpen);
         bool anyLocked=(slLocked||tpLocked||beLocked);

          // A trade is considered open if triggered and not yet locked by ANY execution line (SL, TP, or BE)
          bool tradeOpen = (effectiveSt==SS_TRIGGERED) && triggerTime > 0 && !anyLocked;
          if(tradeOpen)
            {
             // Trade still open — follow current bar
             datetime openEnd=(datetime)(B[n-1].time + pSec - 1);
             segEnd=openEnd;
            }
          else if(anyLocked)
            {
             // Trade closed — find earliest lock time among locked lines
             datetime firstLock=0;
             if(slLocked&&(firstLock==0||slTR<firstLock)) firstLock=slTR;
             if(tpLocked&&(firstLock==0||tpTR<firstLock)) firstLock=tpTR;
             if(beLocked&&(firstLock==0||beTR<firstLock)) firstLock=beTR;
             segEnd=HTFBarEndOf(B,n,pSec,firstLock);
            }
          else
              segEnd=segInact; // no execution lines at all — fallback (should not happen for triggered state)
         }
      if(effectiveSt==SS_TP_HIT || effectiveSt==SS_SL_HIT || effectiveSt==SS_BE_HIT)
        {
         datetime exitT=0;
         double   exitP=0.0;
         if(GetPOIExit(genKeyStyle, exitT, exitP))
           {
            datetime lockRef=exitT;
            for(int hk=0;hk<n;hk++)
              {
               if(B[hk].time!=exitT) continue;
               lockRef=exitT-1;
               break;
              }
            segEnd=HTFBarEndOf(B,n,pSec,lockRef);
           }
        }

      color           clr=POIStateColor(effectiveSt,bull);
      ENUM_LINE_STYLE sty=POIStateStyle(effectiveSt);
      int             wid=POIStateWidth(effectiveSt);

      DrawPOIDual(PFX+"POI_"+(bull?"BU":"BE")+"_"+wickKey,
                  B[wi].time,sibs[s].ltfAnchor,segEnd,sibs[s].level,clr,sty,wid,tip);

      // Turtle Soup line — only draw after BOTH C1 AND first touch have occurred.
      // If touch preceded C1 (tsTouchedBeforeC1=true): no glow, just draw the line.
      // If C1 preceded touch: register glow target; line draws when touch confirmed.
      if(sibs[s].c1Time>0&&sibs[s].tsLevel>0&&sibs[s].tsWickTime>0)
        {
         string tsNm=PFX+"TS_"+genKeyStyle+"_"+wickKey;
         bool   tsTriggered=(st==SS_TRIGGERED);
         bool   tsBothMet  =(sibs[s].tsTouchTime>0);  // touch confirmed
         if(tsBothMet)
           {
            // Line is drawable — both C1 and touch have occurred
            string tsTip="Turtle Soup  "+dir
                        +"\nLevel: "+DoubleToString(sibs[s].tsLevel,_Digits)
                        +"\nC1:    "+NYStr(sibs[s].c1Time)
                        +"\nSwept: "+NYStr(sibs[s].tsTouchTime)
                        +(tsTriggered?"\nConfirmed":"\nAwaiting C2+C3");
            DrawTSLine(tsNm,sibs[s].tsWickTime,sibs[s].tsTouchTime,
                       sibs[s].tsLevel,bull,tsTriggered,tsTip,B,n,pSec);
           }
         else if(!sibs[s].tsTouchedBeforeC1&&sibs[s].c1Time>0)
           {
            // C1 fired before touch — register glow on the TS level
            // so DrawHints can animate color on the TS line object
            // (line itself not drawn yet — only appears after touch)
            color tsClr=bull?Inp_ClrTSBull:Inp_ClrTSBear;
            ArrayResize(g_tsGlows,g_nTsGlows+1);
            g_tsGlows[g_nTsGlows].tsLevel      =sibs[s].tsLevel;
            g_tsGlows[g_nTsGlows].bull          =bull;
            g_tsGlows[g_nTsGlows].nmLine        =tsNm;
            g_tsGlows[g_nTsGlows].barHadTick    =false;
            g_tsGlows[g_nTsGlows].reached100    =false;
            g_tsGlows[g_nTsGlows].lastBarOpen   =0;
            g_tsGlows[g_nTsGlows].clrBase       =tsClr;
           g_nTsGlows++;
          }
        }
     }

   DrawConfirmedActionPillarForGeneration(B,n,pSec,bull,bb,
                                          bullBirths,nBull,bearBirths,nBear,
                                          nSibs);

   //--- FVG boxes: only show the confirmed trigger-winning IFVG ---
   if(counterBias)
     {
      for(int f=0;f<nFvgs;f++)
         DeleteFVGVisualBox(bull,B[bb].time,fvgs[f].t1,fvgs[f].t3,bb,f);
      return;
     }

   bool triggered=(triggerTime>0);
   datetime nowDraw=TimeCurrent();
   color ifvgBullClr=Inp_ClrIFVGBull;
   color ifvgBearClr=Inp_ClrIFVGBear;
   color biasClr=bull?ifvgBullClr:ifvgBearClr;

   for(int f=0;f<nFvgs;f++)
     {
      double pLo=bull?fvgs[f].c3Ext:fvgs[f].c1Ext;
      double pHi=bull?fvgs[f].c1Ext:fvgs[f].c3Ext;
      // Phase 3: FVG box right anchor ends 1s before next LTF bar open
      string fvgNm=FVGVisualName(bull,B[bb].time,fvgs[f].t1,fvgs[f].t3);

      if(triggered)
        {
          if(f!=c3FvgIdx)
            {
             DeleteFVGVisualBox(bull,B[bb].time,fvgs[f].t1,fvgs[f].t3,bb,f);
             continue;
            }
          string path="";
          for(int s=0;s<nSibs;s++)
             if(sibs[s].state==SS_TRIGGERED)
               {path=(sibs[s].c3Time<sibs[s].c2Time)?" | Path A":" | Path B";break;}
          string fibTip=(c3FvgIdx>=0)
                        ?"\nFibB: "+DoubleToString(fvgs[c3FvgIdx].c2c3Extreme,_Digits):"";
          string tip="Winning IFVG ✓  "+(bull?"Bearish":"Bullish")+"  "+dir+path
                    +"\n["+DoubleToString(pLo,_Digits)+" — "+DoubleToString(pHi,_Digits)+"]"
                    +"\nRole: Used for trigger"
                    +"\nWinner: tightest C1 to trigger close"
                    +"\nSL: shared trigger-time branch"
                    +"\nC1:   "+NYStr(fvgs[f].t1)
                    +"\nC3:   "+NYStr(fvgs[f].t3)
                    +"\nInv:  "+NYStr(fvgs[f].invTime)
                    +"\nTrig: "+NYStr(triggerTime)
                    +fibTip;
          // Right anchor: use C3 inversion time (invTime), not triggerTime.
          // For Path B, triggerTime can be later than C3 (trigger on C2 bar).
          // Box should only extend to C3 inversion candle, not beyond.
          DrawFVGBox(fvgNm,fvgs[f].t1,(datetime)(fvgs[f].invTime+ltfSec-1),
                     pLo,pHi,biasClr,tip);
          continue;
        }

      DeleteFVGVisualBox(bull,B[bb].time,fvgs[f].t1,fvgs[f].t3,bb,f);
     }
  }

//+------------------------------------------------------------------+
// ProcessVirginCand — draws virgin wicks and candidate POI lines
//+------------------------------------------------------------------+
void ProcessVirginCand(MqlRates &B[],int n,int i,bool bull,
                       datetime drawFrom,int pSec,int bias,datetime htfOpen)
  {
   WICK_STATE ws=CheckCandidate(bull?B[i].high:B[i].low,bull,htfOpen);
   TradeWindowResult currentBirthWindow;
   bool birthBarRelevant=ResolveBirthTradeWindowCurrentModel(htfOpen,currentBirthWindow);
   bool suppressOppositeCandidate=false;
   if(ws==WS_CAND_ACTIVE && bias!=0)
     {
      bool biasBull=(bias>0);
      if(bull!=biasBull)
        {
         datetime nyExecBar=ToNY(htfOpen);
         MqlDateTime execDt; TimeToStruct(nyExecBar,execDt);
         suppressOppositeCandidate=IsExecHourAllowed(execDt.hour);
        }
     }
   datetime wickTime=B[i].time;
   string nmCA_HTF=CandidateVisualBase(bull,wickTime);
   string nmCA_LTF=nmCA_HTF+"_LTF";
   string nmCAP   =CandidatePillarVisualName(bull,wickTime);
   string nmVW_HTF=VirginVisualBase(bull,wickTime);
   string nmVW_LTF=nmVW_HTF+"_LTF";
   if(ws==WS_REGULAR)
     {
      // Wick is now regular — delete any stale candidate or virgin objects
      DeleteCandidateVisualFamily(bull,wickTime,i);
      DeleteVirginVisualFamily(bull,wickTime,i);
      return;
     }
   if(ws==WS_VIRGIN)
     {
      // Wick reverted to virgin — delete stale candidate objects
      DeleteCandidateVisualFamily(bull,wickTime,i);
      if(!Inp_ShowVirgins)
        {DeleteVirginVisualFamily(bull,wickTime,i); return;}
     }
   if(ws==WS_CAND_ACTIVE)
     {
      // Wick is now candidate — delete stale virgin objects
      DeleteVirginVisualFamily(bull,wickTime,i);
      if(!birthBarRelevant)
        {
         DeleteCandidateVisualFamily(bull,wickTime,i);
         return;
        }
     }
   datetime coreVisualFrom=CoreVisualStart();
   if(ws==WS_VIRGIN)
     {
      if(B[i].time<drawFrom) return;
     }
   else
     {
      // Candidate relevance is about the current HTF bar potentially birthing
      // a POI now, not how old the original virgin wick is.
      if(htfOpen<coreVisualFrom)
        {
         DeleteCandidateVisualFamily(bull,wickTime,i);
         return;
        }
     }
   bool isCandidate=(ws==WS_CAND_ACTIVE);
   bool showCandidateLine=(isCandidate && birthBarRelevant && Inp_ShowCandidates && !suppressOppositeCandidate);
   if(isCandidate && !showCandidateLine)
     {
      DeleteCandidateVisualFamily(bull,wickTime,i);
     }

   double   level  =bull?B[i].high:B[i].low;
   string   code   =CodenameFromTime(B[i].time),dir=bull?"▲":"▼";
   datetime anticipatedExecOpen=0;
   datetime anticipatedExecEnd=0;
   string   anticipatedModel="";
   bool     hasAnticipatedWindow=(isCandidate
                                  && ResolveFirstExecutionWindowForBirth(htfOpen,
                                                                         anticipatedExecOpen,
                                                                         anticipatedExecEnd,
                                                                         anticipatedModel));
   string   nmHTF  =isCandidate?CandidateVisualBase(bull,wickTime):VirginVisualBase(bull,wickTime);
   string   nmLTF  =nmHTF+"_LTF";
   string   tip;
   if(isCandidate)
     {
      tip="Candidate POI  "+dir
         +"\nLevel: "+DoubleToString(level,_Digits)
         +"\nWick: "+NYStr(B[i].time)
         +"\nBirth close: "+NYStr((datetime)(htfOpen+pSec-1))
         +(hasAnticipatedWindow
           ? "\nExec: "+NYStr(anticipatedExecOpen)+" to "+NYStr(anticipatedExecEnd)
           : "\nExec: no enabled slot")
         +"\nRule: HTF close must break wick";
     }
   else
      tip=code+"  "+dir+"  "+DoubleToString(level,_Digits)
         +"\nLevel: "+DoubleToString(level,_Digits)
         +"\nVirgin Wick  |  "+NYStr(B[i].time);
   color           clr=isCandidate?(bull?Inp_ClrCandidateBull:Inp_ClrCandidateBear)
                                  :(bull?Inp_ClrVirginBull:Inp_ClrVirginBear);
   ENUM_LINE_STYLE sty=isCandidate?CCTLineStyle(Inp_StyCandidate):CCTLineStyle(Inp_StyVirgin);
   int             wid=isCandidate?CCTLineWidth(Inp_WidCandidate):CCTLineWidth(Inp_WidVirgin);
   datetime ltfAnchor=FindLTFWickBar(i,B,pSec,bull);
   datetime candEnd=(datetime)(htfOpen+pSec-1);
   if(hasAnticipatedWindow && anticipatedExecEnd>candEnd)
      candEnd=anticipatedExecEnd;
   // Safety: ensure candEnd is at least 1 second into the future relative to htfOpen
   if(candEnd<=htfOpen) candEnd=htfOpen+pSec-1;
   if(!isCandidate || showCandidateLine)
     {
      _Seg(nmHTF,B[i].time, candEnd,level,clr,sty,wid,AboveHTFFlag(), tip);
      _Seg(nmLTF,ltfAnchor, candEnd,level,clr,sty,wid,LTFOnlyFlag(),  tip);
     }

   if(isCandidate)
     {
      // Build pillar name — DrawHints manages visibility per quarter tick
      string nmPillar=CandidatePillarVisualName(bull,wickTime);
      datetime capTime=htfOpen+pSec;
      // Pre-create pillar object hidden — DrawHints shows/hides per quarter
      bool pillarNew=(ObjectFind(0,nmPillar)<0);
      if(pillarNew)
         ObjectCreate(0,nmPillar,OBJ_VLINE,0,capTime,0);
      if(pillarNew||(datetime)ObjectGetInteger(0,nmPillar,OBJPROP_TIME,0)!=capTime)
         ObjectSetInteger(0,nmPillar,OBJPROP_TIME,0,capTime);
      SetObjIntIfChanged(nmPillar,OBJPROP_COLOR,(long)HiddenClr());
      SetObjIntIfChanged(nmPillar,OBJPROP_STYLE,(long)CCTLineStyle(Inp_StyCandidatePillar));
      SetObjIntIfChanged(nmPillar,OBJPROP_WIDTH,(long)CCTLineWidth(Inp_WidCandidatePillar));
      SetObjIntIfChanged(nmPillar,OBJPROP_SELECTABLE,false);
      SetObjIntIfChanged(nmPillar,OBJPROP_BACK,false);
      SetObjIntIfChanged(nmPillar,OBJPROP_TIMEFRAMES,FullContentTFs()|DaySepOnlyTFs());
      string pillarTip="Candidate Action Pillar"
                      +"\nClose: "+NYStr((datetime)(htfOpen+pSec-1))
                      +"\nBar: "+NYStr(htfOpen)
                      +(hasAnticipatedWindow
                        ? "\nExec: "+NYStr(anticipatedExecOpen)+" to "+NYStr(anticipatedExecEnd)
                        : "\nExec: no enabled slot");
      string fitPillarTip=TooltipFit(pillarTip);
      if(ObjectGetString(0,nmPillar,OBJPROP_TOOLTIP)!=fitPillarTip)
         ObjectSetString(0,nmPillar,OBJPROP_TOOLTIP,fitPillarTip);
      {
       string tipNm=nmPillar+"_TIP";
       double pMin=0.0,pMax=0.0;
       if(GetChartPriceRange(pMin,pMax))
         {
          ObjCacheRegister(tipNm);
          bool tipNew=(ObjectFind(0,tipNm)<0);
          if(tipNew)
             ObjectCreate(0,tipNm,OBJ_TREND,0,capTime,pMax,capTime,pMin);
          if(tipNew||(datetime)ObjectGetInteger(0,tipNm,OBJPROP_TIME,0)!=capTime)
             ObjectSetInteger(0,tipNm,OBJPROP_TIME,0,capTime);
          if(tipNew||(datetime)ObjectGetInteger(0,tipNm,OBJPROP_TIME,1)!=capTime)
             ObjectSetInteger(0,tipNm,OBJPROP_TIME,1,capTime);
          if(tipNew||ObjectGetDouble(0,tipNm,OBJPROP_PRICE,0)!=pMax)
             ObjectSetDouble(0,tipNm,OBJPROP_PRICE,0,pMax);
          if(tipNew||ObjectGetDouble(0,tipNm,OBJPROP_PRICE,1)!=pMin)
             ObjectSetDouble(0,tipNm,OBJPROP_PRICE,1,pMin);
          SetObjIntIfChanged(tipNm,OBJPROP_COLOR,(long)HiddenClr());
          SetObjIntIfChanged(tipNm,OBJPROP_STYLE,(long)CCTLineStyle(Inp_StyCandidatePillar));
          SetObjIntIfChanged(tipNm,OBJPROP_WIDTH,(long)CCTLineWidth(Inp_WidCandidatePillar));
          SetObjIntIfChanged(tipNm,OBJPROP_RAY_RIGHT,false);
          SetObjIntIfChanged(tipNm,OBJPROP_RAY_LEFT,false);
          SetObjIntIfChanged(tipNm,OBJPROP_SELECTABLE,false);
          SetObjIntIfChanged(tipNm,OBJPROP_BACK,false);
          SetObjIntIfChanged(tipNm,OBJPROP_TIMEFRAMES,FullContentTFs()|DaySepOnlyTFs());
          if(ObjectGetString(0,tipNm,OBJPROP_TOOLTIP)!=fitPillarTip)
             ObjectSetString(0,tipNm,OBJPROP_TOOLTIP,fitPillarTip);
         }
      }
      ObjCacheRegister(nmPillar);  // prune when cand disappears
      ArrayResize(g_cands,g_nCands+1);
      g_cands[g_nCands].level             =level;
      g_cands[g_nCands].bull              =bull;
      g_cands[g_nCands].nmHTF             =nmHTF;
      g_cands[g_nCands].nmLTF             =nmLTF;
      // Carry over glow state from previous Draw() pass if this cand already existed.
      // Without this, opacity resets to 0 every M1 bar, causing the glow to blink off/on.
      g_cands[g_nCands].opacity           =0.0;
      g_cands[g_nCands].barAboveSinceOpen =false;
      g_cands[g_nCands].lastBarOpen       =0;
      // Search previous pass array for matching entry (arrays are rebuilt each Draw())
      // g_cands is cleared at pass-2 start; we search a persistent shadow array instead.
      // Simplest: search current g_cands entries already written this pass (won't find own)
      // Actually we need a shadow — use the existing object state as proxy:
      // If the candidate line object already exists and has a non-zero opacity color,
      // consider the glow already in progress and set opacity to 1.0.
      if(ObjectFind(0,nmHTF)>=0)
        {
         color existClr=(color)ObjectGetInteger(0,nmHTF,OBJPROP_COLOR);
         // If color is not the dim base color, glow was in progress — restore to full
         color dimBase=bull?Inp_ClrCandGlowBullDim:Inp_ClrCandGlowBearDim;
         if(existClr!=dimBase)
           { g_cands[g_nCands].opacity=1.0; g_cands[g_nCands].barAboveSinceOpen=true; }
        }
      // Evaluate initial pillar visibility at Draw() time — do not wait for first tick
      int    initElapsed=(int)(TimeCurrent()-htfOpen);
      int    initQ=MathMin((initElapsed*4)/pSec,3);
      bool   initTickAbove=bull?(SymbolInfoDouble(_Symbol,SYMBOL_ASK)>=level)
                               :(SymbolInfoDouble(_Symbol,SYMBOL_BID)<=level);
      bool   initShow=(initTickAbove);
      if(!initShow)
        {
         // Check if last LTF close was above — if so show
         double lastCl=iClose(_Symbol,LTF(),1);
         initShow=bull?(lastCl>=level):(lastCl<=level);
        }
      if(ObjectFind(0,nmPillar)>=0)
         SetCandidatePillarVisual(nmPillar,initShow?Inp_ClrCandidatePillar:HiddenClr());
      g_cands[g_nCands].nmPillar          =nmPillar;
      g_cands[g_nCands].pillarVisible     =initShow;
      g_cands[g_nCands].lastQuarter       =initQ;
      g_cands[g_nCands].htfOpen           =htfOpen;
      g_cands[g_nCands].pSecHtf           =pSec;
      g_nCands++;
     }
  }

//+------------------------------------------------------------------+
// DrawHints — called every tick.
//
   // FVG hints:
   //   pre-inversion (hinverted=false) → dark bias-family pulse while in proximity
   //   post-inversion (hinverted=true) → darker hint→bias blend over 7s
//
// Candidate lines:
//   Multi-state opacity driven by bar-close and tick events (spec §VI).
//+------------------------------------------------------------------+
void DrawHints()
  {
   bool anyVisualChange=false;
   double ask  =SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid  =SymbolInfoDouble(_Symbol,SYMBOL_BID);
   datetime now=TimeCurrent();
   int  ltfSec =(int)PeriodSeconds(LTF());
   double pulse=GlowPulse();

   for(int i=0;i<g_nHints;i++)
     {
      double pLo=g_hints[i].bull?g_hints[i].c3Ext:g_hints[i].c1Ext;
      double pHi=g_hints[i].bull?g_hints[i].c1Ext:g_hints[i].c3Ext;
      color  boxClr;
      datetime tR;
      color hintDim   =g_hints[i].bull?Inp_ClrHintBullDim:Inp_ClrHintBearDim;
      color hintBright=g_hints[i].bull?Inp_ClrHintBullBright:Inp_ClrHintBearBright;

      if(g_hints[i].hinverted)
        {
         // Post-inversion transition: darker hint → bias color
         double elapsed=(double)(now-g_hints[i].invFadeStart);
         double t=elapsed/FVG_TRANS_SEC;
         if(t<0.0)t=0.0; if(t>1.0)t=1.0;
         boxClr=GlowColor(hintBright,g_hints[i].biasClrFull,t);
         tR=(datetime)(g_hints[i].invFadeStart+ltfSec-1);
         if(t>=1.0) boxClr=g_hints[i].biasClrFull;
        }
      else
        {
         // Pre-inversion glow logic:
         // Glow STARTS the moment a tick reaches or crosses C1 (price inside gap).
         // Glow CONTINUES for the rest of that LTF bar even if price temporarily
         // pulls back inside the gap — but STOPS immediately if price drops back
         // below C3 (bullish) or above C3 (bearish) within the same bar.
         // On a new bar: resets. Glow only resumes if C1 is reached again.
         datetime curBarOpenFVG=iTime(_Symbol,LTF(),0);
         if(curBarOpenFVG!=g_hints[i].lastBarOpen)
           {
            g_hints[i].lastBarOpen=curBarOpenFVG;
            g_hints[i].barHadTick=false;
           }

          // Hint start uses the user-specified side of price:
          // Bullish = ASK through the bullish C1 opening.
          // Bearish = BID across/above the bearish C1 opening.
         bool atC1 = g_hints[i].bull?(ask>g_hints[i].c1Ext):(bid>=g_hints[i].c1Ext);
         bool hitC3 = g_hints[i].bull?(bid<=g_hints[i].c3Ext):(ask>=g_hints[i].c3Ext);
         if(hitC3) g_hints[i].barHadTick=false;
         if(atC1)  g_hints[i].barHadTick=true;

         if(!g_hints[i].barHadTick)
           {
            if(ObjectDelete(0,g_hints[i].nm))
               anyVisualChange=true;
            continue;
           }

         // Dark bias-family oscillation. Keeps hint status visible without the old grey/white flash.
         double bright=0.25+0.75*pulse;  // never goes fully dark or fully bright
         boxClr=GlowColor(hintDim,hintBright,bright);
         tR=(datetime)(curBarOpenFVG+ltfSec-1);
        }

      // Create or update the box object
      bool isNewHint=(ObjectFind(0,g_hints[i].nm)<0);
      if(isNewHint)
        {
         ObjectCreate(0,g_hints[i].nm,OBJ_RECTANGLE,0,g_hints[i].t1,pHi,tR,pLo);
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_STYLE,     STYLE_SOLID);
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_WIDTH,     1);      // border thickness
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_FILL,      true);
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_BACK,      false);
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_ZORDER,    0);
         ObjectSetInteger(0,g_hints[i].nm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
         ObjectSetString (0,g_hints[i].nm,OBJPROP_TOOLTIP,   "FVG — inverting (hint)");
         anyVisualChange=true;
        }
      if(SetObjIntIfChanged(g_hints[i].nm,OBJPROP_TIME,(long)tR,1))      anyVisualChange=true;
      if(SetObjIntIfChanged(g_hints[i].nm,OBJPROP_COLOR,(long)boxClr))    anyVisualChange=true;
      if(SetObjIntIfChanged(g_hints[i].nm,OBJPROP_FILL,true))             anyVisualChange=true;
      if(SetObjIntIfChanged(g_hints[i].nm,OBJPROP_BACK,true))             anyVisualChange=true;
     }


   //--- Candidate POI line opacity + action pillar visibility ---
   // Candidate objects should dim when price weakens, not vanish into the
   // chart background. The AP should read like the confirmed AP family:
   // thin, dim grey, and stable while the candidate still exists.
   double lastOpenLtf =iOpen (_Symbol,LTF(),1);
   double lastCloseLtf=iClose(_Symbol,LTF(),1);
   double lastBodyHi  =MathMax(lastOpenLtf,lastCloseLtf);
   double lastBodyLo  =MathMin(lastOpenLtf,lastCloseLtf);
   for(int i=0;i<g_nCands;i++)
     {
      double level   =g_cands[i].level;
      bool   candBull=g_cands[i].bull;

      bool   bodyValid=candBull?(lastBodyHi>=level):(lastBodyLo<=level);
      bool   tickValid=candBull?(ask>=level):(bid<=level);

      bool showCandidate=(bodyValid || tickValid);
      // Opacity
      double op;
      if(bodyValid && tickValid) op=1.00;
      else if(bodyValid)         op=0.85;
      else if(tickValid)         op=0.65;
      else                       op=0.00;
      g_cands[i].opacity=op;

      // Line color
      color dimClr   =candBull?Inp_ClrCandGlowBullDim :Inp_ClrCandGlowBearDim;
      color brightClr=candBull?Inp_ClrCandGlowBullBright:Inp_ClrCandGlowBearBright;
      double glowStrength=(op>=1.0)?(0.35+0.65*pulse):MathMax(0.20,op);
      color lineClr=showCandidate?GlowColor(dimClr,brightClr,glowStrength):HiddenClr();
      if(ObjectFind(0,g_cands[i].nmHTF)>=0)
        {
         if(SetObjIntIfChanged(g_cands[i].nmHTF,OBJPROP_COLOR,(long)lineClr))
            anyVisualChange=true;
        }
      if(ObjectFind(0,g_cands[i].nmLTF)>=0)
        {
         if(SetObjIntIfChanged(g_cands[i].nmLTF,OBJPROP_COLOR,(long)lineClr))
            anyVisualChange=true;
        }

      if(g_cands[i].nmPillar==""||g_cands[i].pSecHtf<=0) continue;
      bool showPillar=showCandidate;
      g_cands[i].pillarVisible=showPillar;

      // Apply pillar visibility
      color pillarClr=showPillar?Inp_ClrCandidatePillar:HiddenClr();
      if(SetCandidatePillarVisual(g_cands[i].nmPillar,pillarClr))
         anyVisualChange=true;
     }

   //--- Turtle Soup wick glow (after C1, before first touch) ---
   // Color-changes the TS line object to indicate price proximity.
   // Opacity states (bull POI, bear wick low):
   //   10%  — bar has had a tick touching TS level, price currently above level (bounced)
   //   20%  — bar has had a tick, price currently at/below level (still in zone)
   //   100% — first touch bar has closed (permanent, never reverts)
   for(int i=0;i<g_nTsGlows;i++)
     {
      // Skip if already at 100% — permanent
      if(g_tsGlows[i].reached100) continue;

      double tsLvl=g_tsGlows[i].tsLevel;
      bool   tsB  =g_tsGlows[i].bull;
      // Current price position relative to TS level
      // Bull POI (bearish low): price trades down toward/through it
      // Bear POI (bullish high): price trades up toward/through it
      bool   atLevel=tsB?(bid<=tsLvl):(ask>=tsLvl);

      // Detect new LTF bar
      datetime curBarTime=iTime(_Symbol,LTF(),0);
      if(curBarTime!=g_tsGlows[i].lastBarOpen)
        {
         // New bar — check if the previous bar's CLOSE crossed (100% trigger)
         double prevClose=iClose(_Symbol,LTF(),1);
         if(tsB?(prevClose<=tsLvl):(prevClose>=tsLvl))
           {g_tsGlows[i].reached100=true;}  // previous bar closed at/through level
         else if(g_tsGlows[i].barHadTick)
           {g_tsGlows[i].reached100=true;}  // previous bar had a wick touch — close or not → 100%
         g_tsGlows[i].lastBarOpen   =curBarTime;
         g_tsGlows[i].barHadTick    =atLevel;  // reset for new bar
        }
      else
        {
         // Same bar — update tick state
         if(atLevel) g_tsGlows[i].barHadTick=true;
        }

      if(g_tsGlows[i].reached100) continue; // will be handled next pass as permanent

      // Compute opacity factor
      double opac;
      if(!g_tsGlows[i].barHadTick) opac=0.0;       // no tick yet this bar
      else if(atLevel)              opac=0.20;       // tick touched, currently in zone
      else                          opac=0.10;       // tick touched, price retreated

      // Apply color to the TS line (GlowColor: 0=hidden, 1=full base color)
      color dimClr=C'20,15,5';  // near-invisible base
      color lineClr=(opac>0.0)?GlowColor(dimClr,g_tsGlows[i].clrBase,opac):dimClr;
      if(ObjectFind(0,g_tsGlows[i].nmLine)>=0)
        {
         if(SetObjIntIfChanged(g_tsGlows[i].nmLine,OBJPROP_COLOR,(long)lineClr))
            anyVisualChange=true;
        }
     }
   // Set 100%-state TS lines to full base color permanently
   for(int i=0;i<g_nTsGlows;i++)
     {
      if(!g_tsGlows[i].reached100) continue;
      if(ObjectFind(0,g_tsGlows[i].nmLine)>=0)
        {
         if(SetObjIntIfChanged(g_tsGlows[i].nmLine,OBJPROP_COLOR,(long)g_tsGlows[i].clrBase))
            anyVisualChange=true;
        }
     }

   //--- Execution-family tracking registry: keeps hot updates off the full chart object list ---
   {
    datetime curBarOpen=iTime(_Symbol,LTF(),0);
    datetime curBarEnd =(datetime)(curBarOpen+ltfSec-1);
    datetime liveProjEnd=(datetime)(curBarOpen+2*ltfSec-1);
    double   barHi=iHigh(_Symbol,LTF(),0);
    double   barLo=iLow (_Symbol,LTF(),0);
    int      nTracked=0;
    int      nLocked=0;
    int      nExtended=0;

   for(int ti=g_nExecFamilies-1;ti>=0;ti--)
      {
       string genKeyTrack=g_execFamilies[ti].genKey;
       datetime todayOpen=TodayOpenAt(MarketReferenceTime());
       if(g_execFamilies[ti].triggerTime>0 && g_execFamilies[ti].triggerTime<todayOpen)
         {
          DeleteExecutionVisualFamily(genKeyTrack);
          anyVisualChange=true;
          continue;
         }
       if(genKeyTrack=="" || !ExecFamilyHasVisuals(genKeyTrack))
         {
          UnregisterExecFamilyTrack(genKeyTrack);
          continue;
         }

       nTracked++;
       bool trackBull=g_execFamilies[ti].bull;
       string trigNm=PFX+"TRIG_"+genKeyTrack;
       string slNm  =PFX+"HNT_S_"+genKeyTrack;
       string tpNm  =PFX+"HNT_T_"+genKeyTrack;
       string beNm  =PFX+"HNT_B_"+genKeyTrack;
       string coNm  =PFX+"COTR_"+genKeyTrack;
       datetime birthTimeTrack=(datetime)StringToInteger(StringSubstr(genKeyTrack,3));
       string   execModelLabelTrack=TradeModelShortLabelForBirth(birthTimeTrack);
       string slBox =PFX+"BOX_SL_"+genKeyTrack;
       string tpBox =PFX+"BOX_TP_"+genKeyTrack;

       bool brokerTradeExists=HasOpenCCTPositionForGenKey(genKeyTrack);
       SIB_STATE trackedState=g_execFamilies[ti].outcomeLocked
                              ? g_execFamilies[ti].cachedOutcome
                              : GetPOIOutcome(genKeyTrack);
       if(!g_execFamilies[ti].outcomeLocked && IsResolvedOutcome(trackedState))
         {
          g_execFamilies[ti].cachedOutcome=trackedState;
          g_execFamilies[ti].outcomeLocked=true;
         }
       datetime trackedExitT=0;
       double trackedExitP=0.0;
       GetPOIExit(genKeyTrack,trackedExitT,trackedExitP);

       datetime triggerTrack=g_execFamilies[ti].triggerTime;
       if(triggerTrack<=0 && ObjectFind(0,trigNm)>=0)
          triggerTrack=(datetime)(ObjectGetInteger(0,trigNm,OBJPROP_TIME,0)+ltfSec);

       if(triggerTrack>0 && !IsRecentExecutionVisualTime(triggerTrack))
         {
          DeleteExecutionVisualFamily(genKeyTrack);
          anyVisualChange=true;
          nLocked++;
          continue;
         }

       if(g_execFamilies[ti].lastMilestoneBarOpen!=curBarOpen)
         {
          ResolveExecMilestones(genKeyTrack,trackBull,triggerTrack,g_execFamilies[ti].coPrice,trackedExitT,
                                g_execFamilies[ti].beAnchorTime,g_execFamilies[ti].beTouchTime,g_execFamilies[ti].bePrice,
                                g_execFamilies[ti].coTouchTime,g_execFamilies[ti].coFinalized);
          g_execFamilies[ti].lastMilestoneBarOpen=curBarOpen;
         }
       datetime trackedBEAnchorT=g_execFamilies[ti].beAnchorTime;
       datetime trackedBETouchT=g_execFamilies[ti].beTouchTime;
       double trackedBEPx=g_execFamilies[ti].bePrice;
       datetime trackedCOTouchT=g_execFamilies[ti].coTouchTime;
       bool trackedCOFinalized=g_execFamilies[ti].coFinalized;

       bool trackedResolved=(trackedState==SS_TP_HIT || trackedState==SS_SL_HIT || trackedState==SS_BE_HIT);
      bool keepRecentResolvedVisible=((trackedExitT<=0) || IsRecentExecutionVisualTime(trackedExitT));

       bool beResolvedNow=(trackedBETouchT>0 && trackedBEAnchorT>0 && trackedBEAnchorT>=trackedBETouchT);
       bool hasBEVisualMilestone=(trackedBETouchT>0);
       datetime beVisualStart=trackedBETouchT;
       if(hasBEVisualMilestone && trackedBEPx>0.0 && trackedState!=SS_TP_HIT
          && (!trackedResolved || keepRecentResolvedVisible)
          && ObjectFind(0,slNm)>=0)
         {
          datetime beTR=(trackedExitT>0)?(datetime)(trackedExitT+ltfSec-1):liveProjEnd;
          long capEncoded=(long)ObjectGetInteger(0,slNm,OBJPROP_ZORDER);
          if(capEncoded>0 && (datetime)capEncoded<beTR)
             beTR=(datetime)capEncoded;
          if(ObjectFind(0,beNm)<0)
            {
             if(ObjectCreate(0,beNm,OBJ_TREND,0,beVisualStart,trackedBEPx,beTR,trackedBEPx))
               {
                ObjectSetInteger(0,beNm,OBJPROP_COLOR,    Inp_ClrExecBE);
                ObjectSetInteger(0,beNm,OBJPROP_STYLE,    CCTLineStyle(Inp_StyExecBE));
                ObjectSetInteger(0,beNm,OBJPROP_WIDTH,    CCTLineWidth(Inp_WidExecBE));
                ObjectSetInteger(0,beNm,OBJPROP_ZORDER,   capEncoded);
                ObjectSetInteger(0,beNm,OBJPROP_RAY_RIGHT,false);
                ObjectSetInteger(0,beNm,OBJPROP_SELECTABLE,false);
                ObjectSetInteger(0,beNm,OBJPROP_BACK,     false);
                ObjectSetInteger(0,beNm,OBJPROP_TIMEFRAMES,LTFMaxTFs());
                ObjectSetString (0,beNm,OBJPROP_TOOLTIP,TooltipFit(
                                 "BE (breakeven)\n"
                                +"  Family  : "+genKeyTrack+"\n"
                                +"  Model   : "+execModelLabelTrack+"\n"
                                +"  Level   : "+DoubleToString(trackedBEPx,_Digits)+"\n"
                                +"  Move %  : "+IntegerToString((int)Inp_BE_Move)+"%\n"
                                +"  Trigger : "+IntegerToString((int)Inp_BE_Trigger)+"% of entry->TP"));
                anyVisualChange=true;
               }
            }
          else
            {
             if(SetObjIntIfChanged(beNm,OBJPROP_TIME,(long)beVisualStart,0)) anyVisualChange=true;
             if(SetObjIntIfChanged(beNm,OBJPROP_TIME,(long)beTR,1))              anyVisualChange=true;
             if(SetObjDblIfChanged(beNm,OBJPROP_PRICE,trackedBEPx,0))            anyVisualChange=true;
             if(SetObjDblIfChanged(beNm,OBJPROP_PRICE,trackedBEPx,1))            anyVisualChange=true;
            }
          string beTip="BE (breakeven)\n"
                      +"  Family  : "+genKeyTrack+"\n"
                      +"  Model   : "+execModelLabelTrack+"\n"
                      +"  Level   : "+DoubleToString(trackedBEPx,_Digits)+"\n"
                      +"  Move %  : "+IntegerToString((int)Inp_BE_Move)+"%\n"
                      +"  Trigger : "+IntegerToString((int)Inp_BE_Trigger)+"% of entry->TP";
          UpsertExecTooltipCarrier(beNm,beVisualStart,trackedBEPx,beTR,trackedBEPx,beTip,LTFMaxTFs(),false,6);
         }
       else if(ObjectFind(0,beNm)>=0)
         {
          DeleteNamedObject(beNm);
          anyVisualChange=true;
         }

      if(!brokerTradeExists && trackedExitT<=0 && beResolvedNow)
        {
          datetime beLock=(datetime)(trackedBEAnchorT+ltfSec-1);
         if(LockExecFamilyRightEdge(genKeyTrack,beLock,true))
            anyVisualChange=true;
         UpdatePOIOutcome(genKeyTrack,SS_BE_HIT,trackedBEAnchorT,trackedBEPx);
          if(ObjectFind(0,coNm)>=0 && trackedCOTouchT>0)
            {
             datetime coLock=(datetime)(trackedCOTouchT+ltfSec-1);
             if(UpdateExecObjRightEdge(coNm,coLock))
                anyVisualChange=true;
            }
          nLocked++;
          continue;
        }

      if(trackedResolved)
        {
          if(!keepRecentResolvedVisible)
            {
             DeleteExecutionVisualFamily(genKeyTrack);
             anyVisualChange=true;
             nLocked++;
             continue;
            }
          datetime familyLock=(trackedExitT>0)?(datetime)(trackedExitT+ltfSec-1)
                                                                             :(trackedState==SS_BE_HIT && trackedBEAnchorT>0)?(datetime)(trackedBEAnchorT+ltfSec-1)
                                                                             :liveProjEnd;
          if(LockExecFamilyRightEdge(genKeyTrack,familyLock,false))
             anyVisualChange=true;
          if(ObjectFind(0,coNm)>=0)
            {
             if(trackedState==SS_TP_HIT || (trackedCOTouchT<=0 && trackedCOFinalized))
               {
                DeleteNamedObject(coNm);
                anyVisualChange=true;
               }
             else if(trackedCOTouchT>0)
               {
                datetime coLock=(datetime)(trackedCOTouchT+ltfSec-1);
                if(UpdateExecObjRightEdge(coNm,coLock))
                   anyVisualChange=true;
               }
            }
          nLocked++;
          continue;
        }

      if(ObjectFind(0,coNm)>=0)
        {
          if(trackedCOFinalized && trackedCOTouchT<=0)
            {
             DeleteNamedObject(coNm);
             anyVisualChange=true;
            }
          else if(trackedCOTouchT>0)
            {
             datetime coLock=(datetime)(trackedCOTouchT+ltfSec-1);
             if(UpdateExecObjRightEdge(coNm,coLock))
                anyVisualChange=true;
            }
         }

       bool outcomeUpdated=false;
       double slPx=0.0,tpPx=0.0,bePx=trackedBEPx;
       if(ObjectFind(0,slNm)>=0) slPx=ObjectGetDouble(0,slNm,OBJPROP_PRICE,0);
       if(ObjectFind(0,tpNm)>=0) tpPx=ObjectGetDouble(0,tpNm,OBJPROP_PRICE,0);
       if(ObjectFind(0,beNm)>=0) bePx=ObjectGetDouble(0,beNm,OBJPROP_PRICE,0);

       if(!brokerTradeExists && trackedExitT<=0)
         {
          bool slHit=(slPx>0.0) ? (trackBull?(barLo<=slPx):(barHi>=slPx)) : false;
          bool tpHit=(tpPx>0.0) ? (trackBull?(barHi>=tpPx):(barLo<=tpPx)) : false;
          bool beHit=(bePx>0.0 && trackedBETouchT>0) ? (trackBull?(barLo<=bePx):(barHi>=bePx)) : false;
          if(slHit || tpHit || beHit)
            {
             SIB_STATE outcomeState=slHit?SS_SL_HIT:(tpHit?SS_TP_HIT:SS_BE_HIT);
             double hitPx=slHit?slPx:(tpHit?tpPx:bePx);
             if(LockExecFamilyRightEdge(genKeyTrack,curBarEnd,true))
                anyVisualChange=true;
             UpdatePOIOutcome(genKeyTrack,outcomeState,curBarOpen,hitPx);
             trackedState=outcomeState;
             trackedResolved=true;
             g_execFamilies[ti].cachedOutcome=outcomeState;
             g_execFamilies[ti].outcomeLocked=true;
             outcomeUpdated=true;
             nLocked++;
             if(Inp_ShowDebug)
                PrintFormat("[CCT HIT] %s locked at %s  px=%.5f",genKeyTrack,TimeToString(curBarOpen,TIME_MINUTES),hitPx);
            }
         }

       if(outcomeUpdated)
          continue;

       if(LockExecFamilyRightEdge(genKeyTrack,liveProjEnd,false))
         {
          anyVisualChange=true;
          nExtended++;
         }
       if(ObjectFind(0,coNm)>=0 && trackedCOTouchT<=0 && !trackedCOFinalized)
         {
          if(UpdateExecObjRightEdge(coNm,liveProjEnd))
             anyVisualChange=true;
         }
      }

    if(Inp_ShowDebug&&(nTracked>0||nLocked>0||nExtended>0))
       PrintFormat("[CCT TRK] curBar=%s  families=%d  locked=%d  extended=%d",
                   TimeToString(curBarOpen,TIME_MINUTES),nTracked,nLocked,nExtended);
   }

   if(anyVisualChange && !IsNonVisualTesterRun())
      ChartRedraw(0);
  }

#endif // CCT_VISUAL_MQH
