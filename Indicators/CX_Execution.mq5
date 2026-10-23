//+------------------------------------------------------------------+
//| CX_Execution.mq5                                                 |
//| Portage MT5 de « CX Écran 2 · Exécution » (TradingView, Pine).   |
//| Mêmes calculs, bougie par bougie, mêmes objets que le Pine :     |
//|  - SMC TradingFinder : BoS / ChoCh Major (Minor masquée) et      |
//|    lignes de liquidité (bibliothèque TFlab LiquidityFinder)      |
//|  - EQH / EQL (SMC LuxAlgo)                                       |
//|  - IMFVG (LuxAlgo)                                               |
//|  - Liquidity Defense Zones (JPT)                                 |
//|  - FVG Sessions (LuxAlgo)                                        |
//|  - ICT HTF FVGs (fadi)                                           |
//| Licences d'origine : MPL 2.0 (TradingFinder, JPT, fadi) et       |
//| CC BY-NC-SA 4.0 (LuxAlgo). Dessin en CCanvas : transparence,     |
//| police Trebuchet MS et limite de 500 objets par type comme       |
//| TradingView.                                                     |
//+------------------------------------------------------------------+
#property copyright   "Portage de CX Écran 2 · Exécution (TradingFinder, LuxAlgo, JPT, fadi)"
#property version     "1.02"
#property description "CX Exécution : structure, liquidité, EQH/EQL, IMFVG, LDZ, FVG Sessions et ICT HTF FVGs, au rendu TradingView."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

enum ENUM_ONOFF  { On = 1, Off = 0 };
enum ENUM_LSTYLE { sol = 0, dsh = 1, dot = 2 };
enum ENUM_EQMODE { Historical = 0, Present = 1 };
enum ENUM_EQSTYLE { Colored = 0, Monochrome = 1 };
enum ENUM_TSIZE  { tiny = 0, small = 1, normal = 2 };
enum ENUM_MITIG  { None = 0, Wick_filled = 1, Body_filled = 2, Wick_filled_half = 3, Body_filled_half = 4 };

input group "Logic Parameter"
input int    PP   = 5;               // Pivot Period (BoS / ChoCh)
input group "Liquidity"
input bool   ShowSHLL = true;        // Show Statics High Liquidity Line
input bool   ShowSLLL = true;        // Show Statics Low Liquidity Line
input bool   ShowDHLL = true;        // Show Dynamics High Liquidity Line
input bool   ShowDLLL = true;        // Show Dynamics Low Liquidity Line
input int    SPP  = 8;               // Statics Period Pivot
input int    DPP  = 3;               // Dynamics Period Pivot
input double SLLS = 0.30;            // Statics Liquidity Line Sensitivity
input double DLLS = 1.00;            // Dynamics Liquidity Line Sensitivity
input group "BoS / ChoCh Lines"
input ENUM_ONOFF  MajorBuBoS_Show   = On;   // Show Major Bullish BoS Lines
input ENUM_LSTYLE MajorBuBoS_Style  = dsh;  // Style Major Bullish BoS Lines
input color       MajorBuBoS_Color  = C'54,58,69'; // Color Major Bullish BoS Lines
input ENUM_ONOFF  MajorBeBoS_Show   = On;   // Show Major Bearish BoS Lines
input ENUM_LSTYLE MajorBeBoS_Style  = dsh;  // Style Major Bearish BoS Lines
input color       MajorBeBoS_Color  = C'54,58,69'; // Color Major Bearish BoS Lines
input ENUM_ONOFF  MinorBuBoS_Show   = Off;  // Show Minor Bullish BoS Lines
input ENUM_LSTYLE MinorBuBoS_Style  = dot;  // Style Minor Bullish BoS Lines
input color       MinorBuBoS_Color  = C'54,58,69'; // Color Minor Bullish BoS Lines
input ENUM_ONOFF  MinorBeBoS_Show   = Off;  // Show Minor Bearish BoS Lines
input ENUM_LSTYLE MinorBeBoS_Style  = dot;  // Style Minor Bearish BoS Lines
input color       MinorBeBoS_Color  = C'54,58,69'; // Color Minor Bearish BoS Lines
input ENUM_ONOFF  MajorBuChoCh_Show = On;   // Show Major Bullish ChoCh Lines
input ENUM_LSTYLE MajorBuChoCh_Style = dsh; // Style Major Bullish ChoCh Lines
input color       MajorBuChoCh_Color = C'54,58,69'; // Color Major Bullish ChoCh Lines
input ENUM_ONOFF  MajorBeChoCh_Show = On;   // Show Major Bearish ChoCh Lines
input ENUM_LSTYLE MajorBeChoCh_Style = dsh; // Style Major Bearish ChoCh Lines
input color       MajorBeChoCh_Color = C'54,58,69'; // Color Major Bearish ChoCh Lines
input ENUM_ONOFF  MinorBuChoCh_Show = Off;  // Show Minor Bullish ChoCh Lines
input ENUM_LSTYLE MinorBuChoCh_Style = dot; // Style Minor Bullish ChoCh Lines
input color       MinorBuChoCh_Color = C'54,58,69'; // Color Minor Bullish ChoCh Lines
input ENUM_ONOFF  MinorBeChoCh_Show = Off;  // Show Minor Bearish ChoCh Lines
input ENUM_LSTYLE MinorBeChoCh_Style = dot; // Style Minor Bearish ChoCh Lines
input color       MinorBeChoCh_Color = C'54,58,69'; // Color Minor Bearish ChoCh Lines
input group "Last Support / Resistance Lines"
input ENUM_ONOFF  LastMajSup_Show   = Off;  // Show Last Major Support Line
input ENUM_LSTYLE LastMajSup_Style  = sol;  // Style Last Major Support Line
input color       LastMajSup_Color  = C'54,58,69'; // Color Last Major Support Line
input ENUM_ONOFF  LastMajRes_Show   = Off;  // Show Last Major Resistance Line
input ENUM_LSTYLE LastMajRes_Style  = sol;  // Style Last Major Resistance Line
input color       LastMajRes_Color  = C'54,58,69'; // Color Last Major Resistance Line
input ENUM_ONOFF  LastMinSup_Show   = Off;  // Show Last Minor Support Line
input ENUM_LSTYLE LastMinSup_Style  = dsh;  // Style Last Minor Support Line
input color       LastMinSup_Color  = C'54,58,69'; // Color Last Minor Support Line
input ENUM_ONOFF  LastMinRes_Show   = Off;  // Show Last Minor Resistance Line
input ENUM_LSTYLE LastMinRes_Style  = dsh;  // Style Last Minor Resistance Line
input color       LastMinRes_Color  = C'54,58,69'; // Color Last Minor Resistance Line
input group "Smart Money Concepts · EQH/EQL"
input ENUM_EQMODE  modeInput   = Historical;  // Mode
input ENUM_EQSTYLE styleInput  = Colored;     // Style
input color  swingBullColorInput = C'8,153,129';  // Swing Bullish Color
input color  swingBearColorInput = C'242,54,69';  // Swing Bearish Color
input bool   showEqualHighsLowsInput = true;      // Equal High/Low
input int    eqLengthInput    = 3;                // Bars Confirmation
input double eqThresholdInput = 0.1;              // Threshold
input ENUM_TSIZE eqSizeInput  = tiny;             // Label Size
input group "IMFVG"
input double filterWidth  = 0.0;     // FVG Width Filter
input bool   imfvgOnClose = true;    // Signaux validés à la clôture de bougie (sans scintillement)
input bool   showBull = false;       // Bullish IMFVG
input color  bullCss  = C'8,153,129';  // Bullish IMFVG color
input bool   bullAvg  = false;       // Bullish Moyenne
input bool   showBear = false;       // Bearish IMFVG
input color  bearCss  = C'242,54,69';  // Bearish IMFVG color
input bool   bearAvg  = false;       // Bearish Moyenne
input group "Liquidity Engine"
input int    ldz_pivotLen    = 28;   // Pivot Strength
input int    ldz_atrLen      = 14;   // ATR Longueur
input double ldz_zoneAtrMult = 0.20; // Zone Thickness (ATR)
input int    ldz_maxZones    = 15;   // Maximum Zones Per Side
input group "Display Settings"
input bool   ldz_showZones   = true; // Show Liquidity Zones
input bool   ldz_showLabels  = true; // Show BSL / SSL Labels
input bool   ldz_showSweeps  = true; // Show Sweep Signals
input bool   ldz_extendZones = true; // Extend Active Zones
input group "Reversal Confirmation"
input bool   ldz_requireCandleColor = true; // Require Reversal Candle
input bool   ldz_showReversals      = true; // Show Reversal Signals
input group "FVG Sessions"
input color  fs_bullCss      = C'8,153,129';   // FVG Level (bull)
input int    fs_bullAreaT    = 50;              // Area transparency (bull)
input int    fs_bullMitT     = 80;              // Mitigated transparency (bull)
input color  fs_bearCss      = C'242,54,69';   // FVG Level (bear)
input int    fs_bearAreaT    = 50;              // Area transparency (bear)
input int    fs_bearMitT     = 80;              // Mitigated transparency (bear)
input group "ICT HTF FVGs"
input bool            htf1_show = true;       // HTF 1
input ENUM_TIMEFRAMES htf1      = PERIOD_M5;  // HTF 1 timeframe
input int             htf1_max  = 20;         // HTF 1 maximum
input bool            htf2_show = true;       // HTF 2
input ENUM_TIMEFRAMES htf2      = PERIOD_M15; // HTF 2 timeframe
input int             htf2_max  = 20;         // HTF 2 maximum
input bool            htf3_show = true;       // HTF 3
input ENUM_TIMEFRAMES htf3      = PERIOD_H1;  // HTF 3 timeframe
input int             htf3_max  = 20;         // HTF 3 maximum
input bool            htf4_show = true;       // HTF 4
input ENUM_TIMEFRAMES htf4      = PERIOD_H4;  // HTF 4 timeframe
input int             htf4_max  = 10;         // HTF 4 maximum
input bool            htf5_show = true;       // HTF 5
input ENUM_TIMEFRAMES htf5      = PERIOD_D1;  // HTF 5 timeframe
input int             htf5_max  = 10;         // HTF 5 maximum
input bool            htf6_show = true;       // HTF 6
input ENUM_TIMEFRAMES htf6      = PERIOD_W1;  // HTF 6 timeframe
input int             htf6_max  = 2;          // HTF 6 maximum
input color  htf_color_bull = C'76,175,80';   // Bullish FVG color (color.green)
input color  htf_color_bear = C'41,98,255';   // Bearish FVG color (color.blue)
input int    htf_transp     = 90;             // FVG transparency
input bool   ltf_hide       = true;           // Hide Lower Timeframes
input bool   Border_show    = false;          // Show Border
input bool   mitigated_show = false;          // Show Mitigated
input color  mitigated_color = C'120,123,134';// Mitigated color (color.gray)
input int    mitigated_transp = 95;           // Mitigated transparency
input ENUM_MITIG mitigated_type = Wick_filled;// When
input bool   CE_show        = true;           // Show C.E.
input color  CE_color       = C'54,58,69';    // C.E. color
input int    CE_transp      = 60;             // C.E. transparency
input ENUM_LSTYLE CE_style  = dsh;            // C.E. style
input bool   label_show     = true;           // Show Label
input color  label_color    = C'54,58,69';    // Label color
input int    label_transp   = 10;             // Label transparency
input ENUM_TSIZE label_size = small;          // Label size
input int    padding        = 4;              // Distance from current candle
input int    buffer_sp      = 6;              // Spacing between timeframes
input group "Alertes (à la clôture de la bougie)"
input bool   AlPopup     = true;   // Fenêtre et son MT5
input bool   AlPush      = true;   // Notification mobile (MetaQuotes ID)
input bool   AlHtfNew    = true;   // ICT HTF : nouveau FVG
input bool   AlHtfTouch  = true;   // ICT HTF : prix entre dans un FVG affiché
input bool   AlHtfMitig  = true;   // ICT HTF : FVG affiché comblé
input bool   AlSweep     = true;   // LDZ : BSL / SSL SWEEP
input bool   AlReversal  = true;   // LDZ : signal BUY / SELL
input bool   AlEqual     = true;   // EQH / EQL
input bool   AlFvgSess   = true;   // FVG Sessions : nouveau, comblé, prix dedans, moyenne croisée
input group "MT5"
input int    InpMaxBars = 5000;               // Bougies calculées (TradingView : 5 000)
input string InpFont    = "Trebuchet MS";     // Police (celle de TradingView)

//--- Couleurs Pine v5
#define PC_RED    C'242,54,69'
#define PC_LIME   C'0,230,118'
#define PC_GREEN  C'76,175,80'
#define PC_AQUA   C'0,188,212'
#define PC_ORANGE C'255,152,0'
#define PC_GRAY   C'120,123,134'
#define PC_BLACK  C'54,58,69'
#define PC_WHITE  C'255,255,255'
#define LIQ_BLUE  C'18,123,184'
#define LIQ_PURP  C'162,10,233'
#define MONO_BULL C'178,181,190'
#define MONO_BEAR C'93,96,107'

#define NA     EMPTY_VALUE
#define NAI    -2147483647
#define MAX_OBJ 500

enum ENUM_LBLSTYLE { LS_DOWN = 0, LS_UP = 1, LS_LEFT = 2 };
enum ENUM_TRI { TR_NA = -1, TR_FALSE = 0, TR_TRUE = 1 };
enum ENUM_TREND { TREND_NO = 0, TREND_UP = 1, TREND_DOWN = 2 };

//--- Alertes : collectées pendant le calcul d'une bougie clôturée en direct, envoyées ensemble
bool   gAlertLive = false;
string gAlertBuf  = "";
int    gCurBar    = 0;
string Px2(double p) { return DoubleToString(p, _Digits); }
void   Ev(bool on, string msg)
  {
   if(!on || !gAlertLive) return;
   if(StringFind(gAlertBuf, msg) >= 0) return;
   gAlertBuf += (gAlertBuf == "" ? "" : " · ") + msg;
  }

uint A(const color c, const int transp)
  {
   return ColorToARGB(c, (uchar)MathRound(255.0 * (100 - MathMax(0, MathMin(100, transp))) / 100.0));
  }

//--- Objets dessinés (line, box, label de Pine). x : indice de bougie, ou heure si xt.
struct DLine  { double x1; double y1; double x2; double y2; uint clr; int style; bool xt; bool alive; };
struct DBox   { double x1; double top; double x2; double bot; uint bg; uint bd; int bw; bool xt; bool ext; bool alive; };
struct DLabel { double x; double y; string text; uint bg; uint tc; int style; int size; bool xt; bool sym; bool alive; };
//--- Imbalance de l'ICT HTF FVGs
struct SImb   { double open_time; double open; double middle; double close; bool mitigated; double mit_time; int line; int lbl; int box; bool touched; int born; };

template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
template<typename T> void PushV(T &a[], T v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
template<typename T> void RemoveAt(T &a[], int i)
  {
   int n = ArraySize(a);
   if(i < 0 || i >= n) return;
   for(int k = i; k < n - 1; k++) a[k] = a[k + 1];
   ArrayResize(a, n - 1, 64);
  }
template<typename T> void InsertV(T &a[], int i, T v)
  {
   int n = ArraySize(a);
   if(i < 0 || i > n) return;
   ArrayResize(a, n + 1, 64);
   for(int k = n; k > i; k--) a[k] = a[k - 1];
   a[i] = v;
  }
void InsertImb(SImb &a[], const SImb &v)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1, 64);
   for(int k = n; k > 0; k--) a[k] = a[k - 1];
   a[0] = v;
  }
template<typename T> void CopyArr(T &d[], const T &s[])
  {
   int n = ArraySize(s);
   ArrayResize(d, n, 64);
   for(int i = 0; i < n; i++) d[i] = s[i];
  }

//+------------------------------------------------------------------+
//| État complet du script (variables « var » et objets)             |
//+------------------------------------------------------------------+
class CState
  {
public:
   //--- objets
   DLine  lines[];  DBox boxes[];  DLabel labels[];
   int    liveL, oldL, liveB, oldB, liveT, oldT;
   //--- SMC : zigzag
   string AT[];  double AV[];  int AI[];
   string ATA[]; double AVA[]; int AIA[];
   double hv, lv; int hi, li;           // ta.valuewhen des pivots
   double MajHL, MajLL; int MajHI, MajLI;
   double MinHL, MinLL; int MinHI, MinLI;
   int    LockDet; bool Lock0, Lock1;
   double prev589; bool has589;
   string prev590; bool has590;
   string prev595; bool has595;
   int    LockBreak_M, LockBreak_m, ExtTrend, IntTrend;
   double pMajHL, pMajLL; int pMajHI, pMajLI, pMinHI, pMinLI;
   int    ResMaj, SupMaj, ResMin, SupMin, pResMaj, pSupMaj, pResMin, pSupMin;
   //--- bibliothèque de liquidité
   double sh_v0, sh_v1, sl_v0, sl_v1, dh_v0, dh_v1, dl_v0, dl_v1;
   int    sh_i0, sh_i1, sl_i0, sl_i1, dh_i0, dh_i1, dl_i0, dl_i1;
   int    sHLL, sLLL, dHLL, dLLL, sHLLl, sLLLl, dHLLl, dLLLl;
   int    psHLL, psLLL, pdHLL, pdLLL, psHLLl, psLLLl, pdHLLl, pdLLLl;
   //--- EQH / EQL
   int    leg, prevLeg; bool hasLeg;
   double eqH_cur, eqH_last, eqH_time; int eqH_idx;
   double eqL_cur, eqL_last, eqL_time; int eqL_idx;
   int    eqH_line, eqH_lbl, eqL_line, eqL_lbl;
   //--- IMFVG
   int    bull_line, bear_line, bull_reached, bear_reached;
   //--- LDZ
   int    bslBox[]; double bslPrice[]; bool bslActive[];
   int    sslBox[]; double sslPrice[]; bool sslActive[];
   //--- FVG Sessions
   double fs_top, fs_btm; int fs_mitigated; bool fs_isnew; int fs_isbull; int fs_lvl, fs_area;
   int    fs_max, fs_min;
   //--- ICT HTF FVGs
   SImb   imb0[], imb1[], imb2[], imb3[], imb4[], imb5[];
   int    vis[6];

   void Reset(double t0)
     {
      ArrayFree(lines); ArrayFree(boxes); ArrayFree(labels);
      liveL = oldL = liveB = oldB = liveT = oldT = 0;
      ArrayFree(AT); ArrayFree(AV); ArrayFree(AI); ArrayFree(ATA); ArrayFree(AVA); ArrayFree(AIA);
      hv = lv = NA; hi = li = NAI;
      MajHL = MajLL = MinHL = MinLL = NA; MajHI = MajLI = MinHI = MinLI = NAI;
      LockDet = 0; Lock0 = Lock1 = true;
      prev589 = 0; has589 = false; prev590 = ""; has590 = false; prev595 = ""; has595 = false;
      LockBreak_M = LockBreak_m = 0; ExtTrend = IntTrend = TREND_NO;
      pMajHL = pMajLL = NA; pMajHI = pMajLI = pMinHI = pMinLI = NAI;
      ResMaj = SupMaj = ResMin = SupMin = pResMaj = pSupMaj = pResMin = pSupMin = -1;
      sh_v0 = sh_v1 = sl_v0 = sl_v1 = dh_v0 = dh_v1 = dl_v0 = dl_v1 = NA;
      sh_i0 = sh_i1 = sl_i0 = sl_i1 = dh_i0 = dh_i1 = dl_i0 = dl_i1 = NAI;
      sHLL = sLLL = dHLL = dLLL = sHLLl = sLLLl = dHLLl = dLLLl = -1;
      psHLL = psLLL = pdHLL = pdLLL = psHLLl = psLLLl = pdHLLl = pdLLLl = -1;
      leg = 0; prevLeg = 0; hasLeg = false;
      eqH_cur = eqH_last = eqL_cur = eqL_last = NA; eqH_time = eqL_time = t0; eqH_idx = eqL_idx = 0;
      eqH_line = eqH_lbl = eqL_line = eqL_lbl = -1;
      bull_line = bear_line = -1; bull_reached = bear_reached = TR_NA;
      ArrayFree(bslBox); ArrayFree(bslPrice); ArrayFree(bslActive);
      ArrayFree(sslBox); ArrayFree(sslPrice); ArrayFree(sslActive);
      fs_top = fs_btm = NA; fs_mitigated = TR_NA; fs_isnew = true; fs_isbull = TR_NA; fs_lvl = fs_area = -1;
      fs_max = fs_min = -1;
      ArrayFree(imb0); ArrayFree(imb1); ArrayFree(imb2); ArrayFree(imb3); ArrayFree(imb4); ArrayFree(imb5);
      for(int i = 0; i < 6; i++) vis[i] = 0;
     }

   void CopyFrom(const CState &o)
     {
      CopyArr(lines, o.lines); CopyArr(boxes, o.boxes); CopyArr(labels, o.labels);
      liveL = o.liveL; oldL = o.oldL; liveB = o.liveB; oldB = o.oldB; liveT = o.liveT; oldT = o.oldT;
      CopyArr(AT, o.AT); CopyArr(AV, o.AV); CopyArr(AI, o.AI); CopyArr(ATA, o.ATA); CopyArr(AVA, o.AVA); CopyArr(AIA, o.AIA);
      hv = o.hv; lv = o.lv; hi = o.hi; li = o.li;
      MajHL = o.MajHL; MajLL = o.MajLL; MajHI = o.MajHI; MajLI = o.MajLI;
      MinHL = o.MinHL; MinLL = o.MinLL; MinHI = o.MinHI; MinLI = o.MinLI;
      LockDet = o.LockDet; Lock0 = o.Lock0; Lock1 = o.Lock1;
      prev589 = o.prev589; has589 = o.has589; prev590 = o.prev590; has590 = o.has590; prev595 = o.prev595; has595 = o.has595;
      LockBreak_M = o.LockBreak_M; LockBreak_m = o.LockBreak_m; ExtTrend = o.ExtTrend; IntTrend = o.IntTrend;
      pMajHL = o.pMajHL; pMajLL = o.pMajLL; pMajHI = o.pMajHI; pMajLI = o.pMajLI; pMinHI = o.pMinHI; pMinLI = o.pMinLI;
      ResMaj = o.ResMaj; SupMaj = o.SupMaj; ResMin = o.ResMin; SupMin = o.SupMin;
      pResMaj = o.pResMaj; pSupMaj = o.pSupMaj; pResMin = o.pResMin; pSupMin = o.pSupMin;
      sh_v0 = o.sh_v0; sh_v1 = o.sh_v1; sl_v0 = o.sl_v0; sl_v1 = o.sl_v1; dh_v0 = o.dh_v0; dh_v1 = o.dh_v1; dl_v0 = o.dl_v0; dl_v1 = o.dl_v1;
      sh_i0 = o.sh_i0; sh_i1 = o.sh_i1; sl_i0 = o.sl_i0; sl_i1 = o.sl_i1; dh_i0 = o.dh_i0; dh_i1 = o.dh_i1; dl_i0 = o.dl_i0; dl_i1 = o.dl_i1;
      sHLL = o.sHLL; sLLL = o.sLLL; dHLL = o.dHLL; dLLL = o.dLLL; sHLLl = o.sHLLl; sLLLl = o.sLLLl; dHLLl = o.dHLLl; dLLLl = o.dLLLl;
      psHLL = o.psHLL; psLLL = o.psLLL; pdHLL = o.pdHLL; pdLLL = o.pdLLL; psHLLl = o.psHLLl; psLLLl = o.psLLLl; pdHLLl = o.pdHLLl; pdLLLl = o.pdLLLl;
      leg = o.leg; prevLeg = o.prevLeg; hasLeg = o.hasLeg;
      eqH_cur = o.eqH_cur; eqH_last = o.eqH_last; eqH_time = o.eqH_time; eqH_idx = o.eqH_idx;
      eqL_cur = o.eqL_cur; eqL_last = o.eqL_last; eqL_time = o.eqL_time; eqL_idx = o.eqL_idx;
      eqH_line = o.eqH_line; eqH_lbl = o.eqH_lbl; eqL_line = o.eqL_line; eqL_lbl = o.eqL_lbl;
      bull_line = o.bull_line; bear_line = o.bear_line; bull_reached = o.bull_reached; bear_reached = o.bear_reached;
      CopyArr(bslBox, o.bslBox); CopyArr(bslPrice, o.bslPrice); CopyArr(bslActive, o.bslActive);
      CopyArr(sslBox, o.sslBox); CopyArr(sslPrice, o.sslPrice); CopyArr(sslActive, o.sslActive);
      fs_top = o.fs_top; fs_btm = o.fs_btm; fs_mitigated = o.fs_mitigated; fs_isnew = o.fs_isnew; fs_isbull = o.fs_isbull;
      fs_lvl = o.fs_lvl; fs_area = o.fs_area; fs_max = o.fs_max; fs_min = o.fs_min;
      CopyArr(imb0, o.imb0); CopyArr(imb1, o.imb1); CopyArr(imb2, o.imb2); CopyArr(imb3, o.imb3); CopyArr(imb4, o.imb4); CopyArr(imb5, o.imb5);
      for(int i = 0; i < 6; i++) vis[i] = o.vis[i];
     }

   //--- TradingView efface le plus ancien objet au-delà de 500 par type
   int LineNew(double x1, double y1, double x2, double y2, uint clr, int style, bool xt)
     {
      DLine l; l.x1 = x1; l.y1 = y1; l.x2 = x2; l.y2 = y2; l.clr = clr; l.style = style; l.xt = xt; l.alive = true;
      Push(lines, l); liveL++;
      while(liveL > MAX_OBJ && oldL < ArraySize(lines)) { if(lines[oldL].alive) { lines[oldL].alive = false; liveL--; } oldL++; }
      return ArraySize(lines) - 1;
     }
   int BoxNew(double x1, double top, double x2, double bot, uint bg, uint bd, int bw, bool xt, bool ext)
     {
      DBox b; b.x1 = x1; b.top = top; b.x2 = x2; b.bot = bot; b.bg = bg; b.bd = bd; b.bw = bw; b.xt = xt; b.ext = ext; b.alive = true;
      Push(boxes, b); liveB++;
      while(liveB > MAX_OBJ && oldB < ArraySize(boxes)) { if(boxes[oldB].alive) { boxes[oldB].alive = false; liveB--; } oldB++; }
      return ArraySize(boxes) - 1;
     }
   int LabelNew(double x, double y, string text, uint bg, uint tc, int style, int size, bool xt, bool sym)
     {
      DLabel t; t.x = x; t.y = y; t.text = text; t.bg = bg; t.tc = tc; t.style = style; t.size = size; t.xt = xt; t.sym = sym; t.alive = true;
      Push(labels, t); liveT++;
      while(liveT > MAX_OBJ && oldT < ArraySize(labels)) { if(labels[oldT].alive) { labels[oldT].alive = false; liveT--; } oldT++; }
      return ArraySize(labels) - 1;
     }
   bool LOk(int id) { return id >= 0 && id < ArraySize(lines) && lines[id].alive; }
   bool BOk(int id) { return id >= 0 && id < ArraySize(boxes) && boxes[id].alive; }
   bool TOk(int id) { return id >= 0 && id < ArraySize(labels) && labels[id].alive; }
   void LineDel(int id)  { if(LOk(id)) { lines[id].alive = false; liveL--; } }
   void BoxDel(int id)   { if(BOk(id)) { boxes[id].alive = false; liveB--; } }
   void LabelDel(int id) { if(TOk(id)) { labels[id].alive = false; liveT--; } }
   double LX1(int id) { return LOk(id) ? lines[id].x1 : NA; }
   double LX2(int id) { return LOk(id) ? lines[id].x2 : NA; }
   double LY1(int id) { return LOk(id) ? lines[id].y1 : NA; }
   double LY2(int id) { return LOk(id) ? lines[id].y2 : NA; }
  };

//+------------------------------------------------------------------+
//| Données des unités supérieures                                   |
//+------------------------------------------------------------------+
class CHtf
  {
public:
   ENUM_TIMEFRAMES tf;
   datetime T[]; double O[], H[], L[], C[]; double atr[];
   int      n;
   bool     ok;
   //--- need : heure de la première bougie du graphique, que ces données doivent couvrir
   bool Load(datetime from, datetime need)
     {
      MqlRates r[];
      int k = CopyRates(_Symbol, tf, from, TimeCurrent() + PeriodSeconds(tf), r);
      if(k <= 0) return false;           // données pas prêtes : on garde les précédentes
      n = k;
      ArrayResize(T, n); ArrayResize(O, n); ArrayResize(H, n); ArrayResize(L, n); ArrayResize(C, n); ArrayResize(atr, n);
      for(int i = 0; i < n; i++) { T[i] = r[i].time; O[i] = r[i].open; H[i] = r[i].high; L[i] = r[i].low; C[i] = r[i].close; }
      //--- ta.atr(14) de Pine (moyenne de Wilder amorcée par une moyenne simple)
      double sum = 0, prev = NA;
      for(int i = 0; i < n; i++)
        {
         double tr = (i == 0) ? H[i] - L[i] : MathMax(H[i] - L[i], MathMax(MathAbs(H[i] - C[i - 1]), MathAbs(L[i] - C[i - 1])));
         if(i < 13) { sum += tr; atr[i] = NA; continue; }
         if(i == 13) { sum += tr; prev = sum / 14.0; }
         else prev = (prev * 13.0 + tr) / 14.0;
         atr[i] = prev;
        }
      ok = true;
      //--- historique encore en téléchargement : le terminal n'a que les bougies récentes
      if(T[0] > need)
        {
         datetime first = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_FIRSTDATE);
         if(first == 0 || first < need)
            return false;
        }
      return true;
     }
   //--- bougie contenant t (dernière dont l'ouverture est <= t)
   int Find(datetime t)
     {
      if(n <= 0 || t < T[0]) return -1;
      int lo = 0, hi2 = n - 1;
      while(lo < hi2) { int m = (lo + hi2 + 1) / 2; if(T[m] <= t) lo = m; else hi2 = m - 1; }
      return lo;
     }
   //--- request.security sans lookahead : la bougie supérieure ne compte qu'à la clôture de la
   //    dernière bougie du graphique qui la compose ; avant, c'est la précédente.
   int Applied(datetime t, int per)
     {
      int k = Find(t);
      if(k < 0) return -1;
      datetime close_t = T[k] + PeriodSeconds(tf);
      if(k + 1 < n && T[k + 1] < close_t) close_t = T[k + 1];
      return (t + per >= close_t) ? k : k - 1;
     }
  };

//--- Données du graphique (fenêtre de InpMaxBars bougies, indice 0 = la plus ancienne)
double   gO[], gH[], gL[], gC[], gATR14[], gATR55[], gATR200[];
datetime gT[];
char     gBuy[], gSell[];
int      gN = 0, gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
CState   gCommit, gWork;
CHtf     gHtf[6];
CHtf     gD1, gMN1;
double   gDpi = 1.0;
bool     gHtfOk = false;

//--- Canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0, gLastWork = 0;
bool     gDirty = false;

//+------------------------------------------------------------------+
bool             HtfShow(int k) { return k == 0 ? htf1_show : k == 1 ? htf2_show : k == 2 ? htf3_show : k == 3 ? htf4_show : k == 4 ? htf5_show : htf6_show; }
ENUM_TIMEFRAMES  HtfTf(int k)   { return k == 0 ? htf1 : k == 1 ? htf2 : k == 2 ? htf3 : k == 3 ? htf4 : k == 4 ? htf5 : htf6; }
int              HtfMax(int k)  { return k == 0 ? htf1_max : k == 1 ? htf2_max : k == 2 ? htf3_max : k == 3 ? htf4_max : k == 4 ? htf5_max : htf6_max; }

string HtfText(ENUM_TIMEFRAMES tf)
  {
   int s = PeriodSeconds(tf);
   if(s < 60) return IntegerToString(s) + "s";
   if(s / 60 < 60) return IntegerToString(s / 60) + "m";
   if(s / 3600 < 24) return IntegerToString(s / 3600) + "H";
   if(tf == PERIOD_D1) return "1D";
   if(tf == PERIOD_W1) return "1W";
   if(tf == PERIOD_MN1) return "1M";
   return IntegerToString(s / 86400) + "D";
  }

int StyleOf(ENUM_LSTYLE s) { return (int)s; }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(PP < 1 || SPP < 1 || DPP < 1 || eqLengthInput < 1 || ldz_pivotLen < 2 || ldz_atrLen < 1 || ldz_maxZones < 1 || InpMaxBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXEXE_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Exécution");
   for(int k = 0; k < 6; k++) gHtf[k].tf = HtfTf(k);
   gD1.tf = PERIOD_D1;
   gMN1.tf = PERIOD_MN1;
   gProcessed = -1;
   EventSetMillisecondTimer(100);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(gCvOk) gCv.Destroy();
   gCvOk = false;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Outils de calcul                                                 |
//+------------------------------------------------------------------+
//--- ta.pivothigh / ta.pivotlow : à égalité, c'est la plus à gauche
bool PivotHigh(int t, int len)
  {
   int c = t - len;
   if(c - len < 0) return false;
   for(int i = 1; i <= len; i++)
      if(gH[c - i] >= gH[c] || gH[c + i] > gH[c]) return false;
   return true;
  }
bool PivotLow(int t, int len)
  {
   int c = t - len;
   if(c - len < 0) return false;
   for(int i = 1; i <= len; i++)
      if(gL[c - i] <= gL[c] || gL[c + i] < gL[c]) return false;
   return true;
  }

//--- ta.atr de Pine sur la fenêtre du graphique, de la bougie from à la fin
void Atr(double &out[], int len, int from)
  {
   ArrayResize(out, gN);
   for(int i = from; i < gN; i++)
     {
      double tr = (i == 0) ? gH[i] - gL[i] : MathMax(gH[i] - gL[i], MathMax(MathAbs(gH[i] - gC[i - 1]), MathAbs(gL[i] - gC[i - 1])));
      if(i < len - 1) { out[i] = NA; continue; }
      if(i == len - 1)
        {
         double s = 0;
         for(int k = 0; k < len; k++)
            s += (k == 0) ? gH[k] - gL[k] : MathMax(gH[k] - gL[k], MathMax(MathAbs(gH[k] - gC[k - 1]), MathAbs(gL[k] - gC[k - 1])));
         out[i] = s / len;
        }
      else
         out[i] = (out[i - 1] * (len - 1) + tr) / len;
     }
  }

bool IsNa(double v) { return v == NA; }
bool Gt(double a, double b) { return a != NA && b != NA && a > b; }
bool Lt(double a, double b) { return a != NA && b != NA && a < b; }

//+------------------------------------------------------------------+
//| SMC TradingFinder : zigzag, niveaux Major / Minor, BoS / ChoCh   |
//+------------------------------------------------------------------+
string TL(CState &S) { int n = ArraySize(S.AT); return n > 2 ? (S.AV[n - 2] < S.lv ? "HL" : "LL") : "L"; }
string TH(CState &S) { int n = ArraySize(S.AT); return n > 2 ? (S.AV[n - 2] < S.hv ? "HH" : "LH") : "H"; }
void   Push3(CState &S, string ty, double v, int i) { PushV(S.AT, ty); PushV(S.AV, v); PushV(S.AI, i); }
void   Pop3(CState &S) { int n = ArraySize(S.AT); RemoveAt(S.AT, n - 1); RemoveAt(S.AV, n - 1); RemoveAt(S.AI, n - 1); }

void ZigZag(CState &S, int t, bool hp, bool lp)
  {
   int n = ArraySize(S.AT);
   double HP = hp ? S.hv : NA, LP = lp ? S.lv : NA;
   if(hp && lp)
     {
      if(n == 0)
         return;                                      // PASS
      string last = S.AT[n - 1];
      double lv = S.AV[n - 1];
      if(last == "L" || last == "LL")
        {
         if(LP < lv) { Pop3(S); Push3(S, TL(S), S.lv, S.li); }
         else Push3(S, TH(S), S.hv, S.hi);
        }
      else if(last == "H" || last == "HH")
        {
         if(HP > lv) { Pop3(S); Push3(S, TH(S), S.hv, S.hi); }
         else Push3(S, TL(S), S.lv, S.li);
        }
      else if(last == "LH")
        {
         if(HP < lv) Push3(S, TL(S), S.lv, S.li);
         else if(HP > lv)
           {
            if(gC[t] < lv) { Pop3(S); Push3(S, TH(S), S.hv, S.hi); }
            else if(gC[t] > lv) Push3(S, TL(S), S.lv, S.li);
           }
        }
      else if(last == "HL")
        {
         if(LP > lv) Push3(S, TH(S), S.hv, S.hi);
         else if(LP < lv)
           {
            if(gC[t] > lv) { Pop3(S); Push3(S, TL(S), S.lv, S.li); }
            else if(gC[t] < lv) Push3(S, TH(S), S.hv, S.hi);
           }
        }
     }
   else if(hp)
     {
      if(n == 0) { InsertV(S.AT, 0, "H"); InsertV(S.AV, 0, S.hv); InsertV(S.AI, 0, S.hi); }
      else
        {
         string last = S.AT[n - 1];
         if(last == "L" || last == "HL" || last == "LL")
           {
            if(HP > S.AV[n - 1]) Push3(S, TH(S), S.hv, S.hi);
            else if(HP < S.AV[n - 1]) { Pop3(S); Push3(S, TL(S), S.lv, S.li); }
           }
         else if(last == "H" || last == "HH" || last == "LH")
           {
            if(S.AV[n - 1] < S.hv) { Pop3(S); Push3(S, TH(S), S.hv, S.hi); }
           }
        }
     }
   else if(lp)
     {
      if(n == 0) { InsertV(S.AT, 0, "L"); InsertV(S.AV, 0, S.lv); InsertV(S.AI, 0, S.li); }
      else
        {
         string last = S.AT[n - 1];
         if(last == "H" || last == "HH" || last == "LH")
           {
            if(LP < S.AV[n - 1]) Push3(S, TL(S), S.lv, S.li);
            else if(LP > S.AV[n - 1]) { Pop3(S); Push3(S, TH(S), S.hv, S.hi); }
           }
         else if(last == "L" || last == "HL" || last == "LL")
           {
            if(S.AV[n - 1] > S.lv) { Pop3(S); Push3(S, TL(S), S.lv, S.li); }
           }
        }
     }
  }

string AdvT(CState &S, int fromEnd) { int n = ArraySize(S.ATA); return (n - fromEnd >= 0) ? S.ATA[n - fromEnd] : ""; }
double AdvV(CState &S, int fromEnd) { int n = ArraySize(S.AVA); return (n - fromEnd >= 0) ? S.AVA[n - fromEnd] : NA; }
int    AdvI(CState &S, int fromEnd) { int n = ArraySize(S.AIA); return (n - fromEnd >= 0) ? S.AIA[n - fromEnd] : NAI; }
string ZzT(CState &S, int fromEnd)  { int n = ArraySize(S.AT);  return (n - fromEnd >= 0) ? S.AT[n - fromEnd] : ""; }
void   SetAdvT(CState &S, int fromEnd, string v) { int n = ArraySize(S.ATA); if(n - fromEnd >= 0) S.ATA[n - fromEnd] = v; }
//--- remove(size - k) puis insert(size - k) : le type change en place
void   ReplaceAdvT(CState &S, int fromEnd, string v) { int n = ArraySize(S.ATA); int i = n - fromEnd; if(i < 0) return; RemoveAt(S.ATA, i); InsertV(S.ATA, ArraySize(S.AVA) - fromEnd, v); }

int    Pos(string s, string c) { int p = StringFind(s, c); return p; }

void MajorMinor(CState &S, int t)
  {
   double close = gC[t];
   int n = ArraySize(S.AT);
//--- first Major & Minor Detector
   if(n == 2)
     {
      if(S.AT[0] == "H") { S.MajHL = S.AV[0]; S.MajLL = S.AV[1]; S.MajHI = S.AI[0]; S.MajLI = S.AI[1]; }
      else if(S.AT[0] == "L") { S.MajHL = S.AV[1]; S.MajLL = S.AV[0]; S.MajHI = S.AI[1]; S.MajLI = S.AI[0]; }
     }
//--- Making Copies of Arrays
   if(ArraySize(S.AV) == 1 && S.Lock0)
     {
      InsertV(S.ATA, 0, "M" + S.AT[0]); InsertV(S.AVA, 0, S.AV[0]); InsertV(S.AIA, 0, S.AI[0]);
      S.Lock0 = false;
     }
   if(ArraySize(S.AV) == 2 && S.Lock1)
     {
      InsertV(S.ATA, 1, "M" + S.AT[1]); InsertV(S.AVA, 1, S.AV[1]); InsertV(S.AIA, 1, S.AI[1]);
      S.Lock1 = false;
     }
   if(n > 1)
     {
      double lastV = S.AV[n - 1];
      bool changed = S.has589 && S.prev589 != lastV;
      S.prev589 = lastV; S.has589 = true;
      if(changed)
        {
         string cur = S.AT[n - 1];
         int    L = StringLen(cur);
         string p590 = S.prev590; bool h590 = S.has590;
         S.prev590 = cur; S.has590 = true;
         //--- comparaison avec na (première exécution) : fausse, comme dans Pine
         if(h590 && StringSubstr(p590, MathMin(L - 1, StringLen(p590))) != StringSubstr(cur, L - 1))
           {
            PushV(S.ATA, "m" + cur); PushV(S.AVA, S.AV[n - 1]); PushV(S.AIA, S.AI[n - 1]);
           }
         else
           {
            string p595 = S.prev595; bool h595 = S.has595;
            S.prev595 = cur; S.has595 = true;
            if(h595 && StringSubstr(p595, MathMin(L - 1, StringLen(p595))) == StringSubstr(cur, L - 1))
              {
               int m = ArraySize(S.AVA);
               RemoveAt(S.AVA, m - 1); RemoveAt(S.AIA, m - 1);
               PushV(S.AVA, S.AV[n - 1]); PushV(S.AIA, S.AI[n - 1]);
              }
           }
        }
     }

//--- All Major & Minor Pivot Detector
   if(ArraySize(S.AVA) > 1)
     {
      //--- High Major Detector
      if(Gt(close, S.MajHL))
        {
         string l1 = AdvT(S, 1);
         if(l1 == "mL")
           { SetAdvT(S, 1, "ML"); S.MajLL = AdvV(S, 1); S.MajLI = AdvI(S, 1); }
         else if(l1 == "mHL" || l1 == "mLL")
           { SetAdvT(S, 1, "M" + ZzT(S, 1)); S.MajLL = AdvV(S, 1); S.MajLI = AdvI(S, 1); }
         else if(l1 == "mLH" || l1 == "mHH" || l1 == "MLH" || l1 == "MHH")
           {
            string l2 = AdvT(S, 2);
            if(l2 == "mHL" || l2 == "mLL")
              { ReplaceAdvT(S, 2, "M" + ZzT(S, 2)); S.MajLL = AdvV(S, 2); S.MajLI = AdvI(S, 2); }
           }
        }
      if(Gt(AdvV(S, 1), S.MajHL))
        {
         string l1 = AdvT(S, 1);
         if(l1 == "mH")
           { SetAdvT(S, 1, "MH"); S.MajHL = AdvV(S, 1); S.MajHI = AdvI(S, 1); }
         else if(l1 == "mLH" || l1 == "mHH" || l1 == "MHH")
           { SetAdvT(S, 1, "M" + ZzT(S, 1)); S.MajHL = AdvV(S, 1); S.MajHI = AdvI(S, 1); }
        }
      //--- Low Major Detector
      if(Lt(close, S.MajLL))
        {
         string l1 = AdvT(S, 1);
         if(l1 == "mH")
           { SetAdvT(S, 1, "MH"); S.MajHL = AdvV(S, 1); S.MajHI = AdvI(S, 1); }
         else if(l1 == "mLH" || l1 == "mHH")
           { SetAdvT(S, 1, "M" + ZzT(S, 1)); S.MajHL = AdvV(S, 1); S.MajHI = AdvI(S, 1); }
         else if(l1 == "mHL" || l1 == "mLL" || l1 == "MHL" || l1 == "MLL")
           {
            string l2 = AdvT(S, 2);
            if(l2 == "mLH" || l2 == "mHH")
              { ReplaceAdvT(S, 2, "M" + ZzT(S, 2)); S.MajHL = AdvV(S, 2); S.MajHI = AdvI(S, 2); }
           }
        }
      if(Lt(AdvV(S, 1), S.MajLL))
        {
         string l1 = AdvT(S, 1);
         if(l1 == "mL")
           { SetAdvT(S, 1, "ML"); S.MajLL = AdvV(S, 1); S.MajLI = AdvI(S, 1); }
         else if(l1 == "mHL" || l1 == "mLL" || l1 == "MLL")
           { SetAdvT(S, 1, "M" + ZzT(S, 1)); S.MajLL = AdvV(S, 1); S.MajLI = AdvI(S, 1); }
        }
     }

//--- Detecte Minor level
   if(ArraySize(S.ATA) > 2)
     {
      S.LockDet = 1;
      string a1 = AdvT(S, 1), a2 = AdvT(S, 2), a3 = AdvT(S, 3);
      if(Pos(a1, "m") == 0 && Pos(a2, "m") == 0 && Pos(a3, "M") == 0)
        {
         if(Pos(a1, "H") == 2)
           { S.MinHL = AdvV(S, 1); S.MinLL = AdvV(S, 2); S.MinHI = AdvI(S, 1); S.MinLI = AdvI(S, 2); }
         else if(Pos(a1, "L") == 2)
           { S.MinHL = AdvV(S, 2); S.MinLL = AdvV(S, 1); S.MinHI = AdvI(S, 2); S.MinLI = AdvI(S, 1); }
        }
      if(S.LockDet == 1)
        {
         //--- High Minor Detector
         if(Gt(close, S.MinHL))
           {
            if(a1 == "mHL" || a1 == "mLL") { S.MinLL = AdvV(S, 1); S.MinLI = AdvI(S, 1); }
            else if(a1 == "mLH" || a1 == "mHH")
              {
               if(a2 == "mHL" || a2 == "mLL") { S.MinLL = AdvV(S, 2); S.MinLI = AdvI(S, 2); }
              }
           }
         if(Gt(AdvV(S, 1), S.MinHL))
           {
            if(a1 == "mLH" || a1 == "mHH")
              { S.MinHL = AdvV(S, 1); S.MinHI = AdvI(S, 1); S.MinLL = AdvV(S, 2); S.MinLI = AdvI(S, 2); }
           }
         //--- Low Minor Detector
         if(Lt(close, S.MinLL))
           {
            if(a1 == "mLH" || a1 == "mHH") { S.MinHL = AdvV(S, 1); S.MinHI = AdvI(S, 1); }
            else if(a1 == "mHL" || a1 == "mLL")
              {
               if(a2 == "mLH" || a2 == "mHH") { S.MinHL = AdvV(S, 2); S.MinHI = AdvI(S, 2); }
              }
           }
         if(Lt(AdvV(S, 1), S.MinLL))
           {
            if(a1 == "mHL" || a1 == "mLL")
              { S.MinLL = AdvV(S, 1); S.MinLI = AdvI(S, 1); S.MinHL = AdvV(S, 2); S.MinHI = AdvI(S, 2); }
           }
        }
      //--- Reset Minor Levels
      if(Pos(a1, "M") == 0)
        {
         S.LockDet = 0;
         S.MinHL = S.MinLL = NA; S.MinHI = S.MinLI = NAI;
         S.IntTrend = TREND_NO;
        }
     }
  }

void BosChoch(CState &S, int t)
  {
   double close = gC[t];
//--- Major
   bool crossUp = Gt(close, S.MajHL) && t > 0 && S.pMajHL != NA && gC[t - 1] <= S.pMajHL;
   if(crossUp && S.LockBreak_M != S.MajHI)
     {
      if(S.ExtTrend == TREND_NO || S.ExtTrend == TREND_UP)
        {
         S.LockBreak_M = S.MajHI; S.ExtTrend = TREND_UP;
         if(MajorBuBoS_Show == On)
           {
            S.LineNew(S.MajHI, S.MajHL, t, S.MajHL, A(MajorBuBoS_Color, 0), StyleOf(MajorBuBoS_Style), false);
            S.LabelNew((S.MajHI + t) / 2, S.MajHL, "BoS", 0, A(PC_BLACK, 0), LS_DOWN, tiny, false, false);
           }
        }
      else if(S.ExtTrend == TREND_DOWN)
        {
         S.LockBreak_M = S.MajHI; S.ExtTrend = TREND_UP;
         if(MajorBuChoCh_Show == On)
           {
            S.LineNew(S.MajHI, S.MajHL, t, S.MajHL, A(MajorBuChoCh_Color, 0), StyleOf(MajorBuChoCh_Style), false);
            S.LabelNew((S.MajHI + t) / 2, S.MajHL, "ChoCh", 0, A(PC_BLACK, 0), LS_DOWN, tiny, false, false);
           }
        }
     }
   bool crossDn = Lt(close, S.MajLL) && t > 0 && S.pMajLL != NA && gC[t - 1] >= S.pMajLL;
   if(crossDn && S.LockBreak_M != S.MajLI)
     {
      if(S.ExtTrend == TREND_NO || S.ExtTrend == TREND_DOWN)
        {
         S.LockBreak_M = S.MajLI; S.ExtTrend = TREND_DOWN;
         if(MajorBeBoS_Show == On)
           {
            S.LineNew(S.MajLI, S.MajLL, t, S.MajLL, A(MajorBeBoS_Color, 0), StyleOf(MajorBeBoS_Style), false);
            S.LabelNew((S.MajLI + t) / 2, S.MajLL, "BoS", 0, A(PC_BLACK, 0), LS_UP, tiny, false, false);
           }
        }
      else if(S.ExtTrend == TREND_UP)
        {
         S.LockBreak_M = S.MajLI; S.ExtTrend = TREND_DOWN;
         if(MajorBeChoCh_Show == On)
           {
            S.LineNew(S.MajLI, S.MajLL, t, S.MajLL, A(MajorBeChoCh_Color, 0), StyleOf(MajorBeChoCh_Style), false);
            S.LabelNew((S.MajLI + t) / 2, S.MajLL, "ChoCh", 0, A(PC_BLACK, 0), LS_UP, tiny, false, false);
           }
        }
     }
//--- Minor
   if(Lt(S.MinHL, close) && S.LockBreak_m != S.MinHI)
     {
      if(S.IntTrend == TREND_NO || S.IntTrend == TREND_UP)
        {
         S.LockBreak_m = S.MinHI; S.IntTrend = TREND_UP;
         if(MinorBuBoS_Show == On)
           {
            S.LineNew(S.MinHI, S.MinHL, t, S.MinHL, A(MinorBuBoS_Color, 0), StyleOf(MinorBuBoS_Style), false);
            S.LabelNew((S.MinHI + t) / 2, S.MinHL, "BoS", 0, A(PC_BLACK, 0), LS_DOWN, tiny, false, false);
           }
        }
      else if(S.IntTrend == TREND_DOWN)
        {
         S.LockBreak_m = S.MinHI; S.IntTrend = TREND_UP;
         if(MinorBuChoCh_Show == On)
           {
            S.LineNew(S.MinHI, S.MinHL, t, S.MinHL, A(MinorBuChoCh_Color, 0), StyleOf(MinorBuChoCh_Style), false);
            S.LabelNew((S.MinHI + t) / 2, S.MinHL, "ChoCh", 0, A(PC_BLACK, 0), LS_DOWN, tiny, false, false);
           }
        }
     }
   if(Gt(S.MinLL, close) && S.LockBreak_m != S.MinLI)
     {
      if(S.IntTrend == TREND_NO || S.IntTrend == TREND_DOWN)
        {
         S.LockBreak_m = S.MinLI; S.IntTrend = TREND_DOWN;
         if(MinorBeBoS_Show == On)
           {
            S.LineNew(S.MinLI, S.MinLL, t, S.MinLL, A(MinorBeBoS_Color, 0), StyleOf(MinorBeBoS_Style), false);
            S.LabelNew((S.MinLI + t) / 2, S.MinLL, "Minor BoS", 0, A(PC_BLACK, 0), LS_UP, tiny, false, false);
           }
        }
      else if(S.IntTrend == TREND_UP)
        {
         S.LockBreak_m = S.MinLI; S.IntTrend = TREND_DOWN;
         if(MinorBeChoCh_Show == On)
           {
            S.LineNew(S.MinLI, S.MinLL, t, S.MinLL, A(MinorBeChoCh_Color, 0), StyleOf(MinorBeChoCh_Style), false);
            S.LabelNew((S.MinLI + t) / 2, S.MinLL, "Minor ChoCh", 0, A(PC_BLACK, 0), LS_UP, tiny, false, false);
           }
        }
     }
  }

//--- Lignes du dernier support / de la dernière résistance (masquées par défaut)
void SupRes(CState &S, int t)
  {
   string a1 = ArraySize(S.ATA) > 0 ? AdvT(S, 1) : "";
   //--- Major Resistance
   if(S.MajHI != S.pMajHI && LastMajRes_Show == On && S.MajHI != NAI)
     {
      S.ResMaj = S.LineNew(S.MajHI, S.MajHL, S.MajHI + 1, S.MajHL, A(LastMajRes_Color, 0), StyleOf(LastMajRes_Style), false);
      S.LineDel(S.pResMaj);
     }
   if(S.MajHI == S.pMajHI && Lt(gH[t], S.MajHL)) { if(S.LOk(S.ResMaj)) S.lines[S.ResMaj].x2 = t + 1; }
   else if(S.MajHI == S.pMajHI && Gt(gH[t], S.MajHL)) S.LineDel(S.ResMaj);
   //--- Major Support
   if(S.MajLI != S.pMajLI && LastMajSup_Show == On && S.MajLI != NAI)
     {
      S.SupMaj = S.LineNew(S.MajLI, S.MajLL, S.MajLI + 1, S.MajLL, A(LastMajSup_Color, 0), StyleOf(LastMajSup_Style), false);
      S.LineDel(S.pSupMaj);
     }
   if(S.MajLI == S.pMajLI && Gt(gL[t], S.MajLL)) { if(S.LOk(S.SupMaj)) S.lines[S.SupMaj].x2 = t + 1; }
   else if(S.MajLI == S.pMajLI && Lt(gL[t], S.MajLL)) S.LineDel(S.SupMaj);
   //--- Minor Resistance
   if(S.MinHI != S.pMinHI && LastMinRes_Show == On && S.MinHI != NAI)
     {
      S.ResMin = S.LineNew(S.MinHI, S.MinHL, S.MinHI + 1, S.MinHL, A(LastMinRes_Color, 0), StyleOf(LastMinRes_Style), false);
      S.LineDel(S.pResMin);
     }
   if(S.MinHI == S.pMinHI && Lt(gH[t], S.MinHL)) { if(S.LOk(S.ResMin)) S.lines[S.ResMin].x2 = t + 1; }
   else if(S.MinHI == S.pMinHI && Gt(gH[t], S.MinHL)) S.LineDel(S.ResMin);
   else if(Pos(a1, "M") == 0) S.LineDel(S.ResMin);
   //--- Minor Support
   if(S.MinLI != S.pMinLI && LastMinSup_Show == On && S.MinLI != NAI)
     {
      S.SupMin = S.LineNew(S.MinLI, S.MinLL, S.MinLI + 1, S.MinLL, A(LastMinSup_Color, 0), StyleOf(LastMinSup_Style), false);
      S.LineDel(S.pSupMin);
     }
   if(S.MinLI == S.pMinLI && Gt(gL[t], S.MinLL)) { if(S.LOk(S.SupMin)) S.lines[S.SupMin].x2 = t + 1; }
   else if(S.MinLI == S.pMinLI && Lt(gL[t], S.MinLL)) S.LineDel(S.SupMin);
   else if(Pos(a1, "M") == 0) S.LineDel(S.SupMin);
  }

void Smc(CState &S, int t)
  {
   bool hp = PivotHigh(t, PP), lp = PivotLow(t, PP);
   if(hp) { S.hv = gH[t - PP]; S.hi = t - PP; }
   if(lp) { S.lv = gL[t - PP]; S.li = t - PP; }
   ZigZag(S, t, hp, lp);
   MajorMinor(S, t);
   BosChoch(S, t);
   SupRes(S, t);
   //--- valeurs de fin de bougie, lues avec [1] à la bougie suivante
   S.pMajHL = S.MajHL; S.pMajLL = S.MajLL; S.pMajHI = S.MajHI; S.pMajLI = S.MajLI;
   S.pMinHI = S.MinHI; S.pMinLI = S.MinLI;
   S.pResMaj = S.ResMaj; S.pSupMaj = S.SupMaj; S.pResMin = S.ResMin; S.pSupMin = S.SupMin;
  }

//+------------------------------------------------------------------+
//| Bibliothèque TFlab LiquidityFinderLibrary : Llf()                |
//+------------------------------------------------------------------+
void Llf(CState &S, int t)
  {
   double atr = gATR55[t];
   bool newSH = false, newSL = false, newDH = false, newDL = false;
   if(PivotHigh(t, SPP)) { S.sh_v1 = S.sh_v0; S.sh_i1 = S.sh_i0; S.sh_v0 = gH[t - SPP]; S.sh_i0 = t - SPP; newSH = S.sh_i1 != NAI; }
   if(PivotLow(t, SPP))  { S.sl_v1 = S.sl_v0; S.sl_i1 = S.sl_i0; S.sl_v0 = gL[t - SPP]; S.sl_i0 = t - SPP; newSL = S.sl_i1 != NAI; }
   if(PivotHigh(t, DPP)) { S.dh_v1 = S.dh_v0; S.dh_i1 = S.dh_i0; S.dh_v0 = gH[t - DPP]; S.dh_i0 = t - DPP; newDH = S.dh_i1 != NAI; }
   if(PivotLow(t, DPP))  { S.dl_v1 = S.dl_v0; S.dl_i1 = S.dl_i0; S.dl_v0 = gL[t - DPP]; S.dl_i0 = t - DPP; newDL = S.dl_i1 != NAI; }
   double atrS = (t - SPP >= 0) ? gATR55[t - SPP] : NA;
   double atrD = (t - DPP >= 0) ? gATR55[t - DPP] : NA;
//--- STATICS
   if(newSH && S.sh_v0 <= S.sh_v1 && (S.sh_i0 - S.sh_i1) >= 8 && ShowSHLL && atrS != NA && atrS > 0)
      if(MathAbs((S.sh_v1 - S.sh_v0) / atrS) <= SLLS)
        {
         S.sHLL  = S.LineNew(S.sh_i1, S.sh_v1, S.sh_i0, S.sh_v1, A(LIQ_BLUE, 43), dot, false);
         S.sHLLl = S.LabelNew((int)MathRound((S.sh_i1 + S.sh_i0) / 2.0), atr != NA ? S.sh_v1 - atr / 2 : S.sh_v1, "2 Top Liq", 0, A(LIQ_BLUE, 0), LS_DOWN, small, false, false);
        }
   if(newSL && S.sl_v0 >= S.sl_v1 && (S.sl_i0 - S.sl_i1) >= 8 && ShowSLLL && atrS != NA && atrS > 0)
      if(MathAbs((S.sl_v1 - S.sl_v0) / atrS) <= SLLS)
        {
         S.sLLL  = S.LineNew(S.sl_i1, S.sl_v1, S.sl_i0, S.sl_v1, A(LIQ_PURP, 45), dot, false);
         S.sLLLl = S.LabelNew((int)MathRound((S.sl_i1 + S.sl_i0) / 2.0), atr != NA ? S.sl_v1 + atr / 2 : S.sl_v1, "2 Bottom Liq", 0, A(LIQ_PURP, 0), LS_UP, small, false, false);
        }
//--- DYNAMICS
   if(newDH && S.dh_v0 <= S.dh_v1 && (S.dh_i0 - S.dh_i1) >= 4 && ShowDHLL && atrD != NA && atrD > 0)
     {
      double r = MathAbs((S.dh_v1 - S.dh_v0) / atrD);
      if(r >= DLLS && r <= 1.95)
        {
         S.dHLL  = S.LineNew(S.dh_i1, S.dh_v1, S.dh_i0, S.dh_v0, A(LIQ_BLUE, 44), dot, false);
         S.dHLLl = S.LabelNew((int)MathRound((S.dh_i1 + S.dh_i0) / 2.0) + 2, atr != NA ? (S.dh_v1 + S.dh_v0) / 2 - atr / 4 : (S.dh_v1 + S.dh_v0) / 2, "DLiq", 0, A(LIQ_BLUE, 0), LS_DOWN, small, false, false);
        }
     }
   if(newDL && S.dl_v0 >= S.dl_v1 && (S.dl_i0 - S.dl_i1) >= 4 && ShowDLLL && atrD != NA && atrD > 0)
     {
      double r = MathAbs((S.dl_v1 - S.dl_v0) / atrD);
      if(r >= DLLS && r <= 1.95)
        {
         S.dLLL  = S.LineNew(S.dl_i1, S.dl_v1, S.dl_i0, S.dl_v0, A(LIQ_PURP, 45), dot, false);
         S.dLLLl = S.LabelNew((int)MathRound((S.dl_i1 + S.dl_i0) / 2.0) + 2, atr != NA ? (S.dl_v1 + S.dl_v1) / 2 + atr / 4 : S.dl_v1, "DLiq", 0, A(LIQ_PURP, 0), LS_UP, small, false, false);
        }
     }
//--- Enchaînements : deux lignes qui se touchent n'en font qu'une (« 3 Top Liq »)
   double a = S.LX2(S.psHLL), b = S.LX1(S.sHLL);
   if(a != NA && b != NA && MathAbs(a - b) <= 2)
     {
      S.LineDel(S.sHLL);
      S.LabelDel(S.psHLLl);
      if(S.LOk(S.psHLL)) S.lines[S.psHLL].x2 = S.sh_i0;
      if(S.TOk(S.sHLLl)) { S.labels[S.sHLLl].text = "3 Top Liq"; if(S.LOk(S.psHLL)) S.labels[S.sHLLl].x = MathAbs((int)((S.LX1(S.psHLL) + S.LX2(S.psHLL)) / 2)); }
     }
   a = S.LX2(S.psLLL); b = S.LX1(S.sLLL);
   if(a != NA && b != NA && MathAbs(a - b) <= 2)
     {
      S.LineDel(S.sLLL);
      S.LabelDel(S.psLLLl);
      if(S.LOk(S.psLLL)) S.lines[S.psLLL].x2 = S.sl_i0;
      if(S.TOk(S.sLLLl)) { S.labels[S.sLLLl].text = "3 Top Liq"; if(S.LOk(S.psLLL)) S.labels[S.sLLLl].x = MathAbs((int)((S.LX1(S.psLLL) + S.LX2(S.psLLL)) / 2)); }
     }
   a = S.LX2(S.pdHLL); b = S.LX1(S.dHLL);
   if(a != NA && b != NA && MathAbs(a - b) <= DPP * 2 + 1)
     {
      S.LineDel(S.dHLL);
      S.LabelDel(S.pdHLLl);
      if(S.LOk(S.pdHLL)) { S.lines[S.pdHLL].x2 = S.dh_i0; S.lines[S.pdHLL].y2 = S.dh_v0; }
      if(S.TOk(S.dHLLl) && S.LOk(S.pdHLL))
        {
         S.labels[S.dHLLl].x = MathAbs((int)((S.LX1(S.pdHLL) + S.LX2(S.pdHLL)) / 2) + 2);
         S.labels[S.dHLLl].y = (S.LY1(S.pdHLL) + S.LY2(S.pdHLL)) / 2;
        }
     }
   a = S.LX2(S.pdLLL); b = S.LX1(S.dLLL);
   if(a != NA && b != NA && MathAbs(a - b) <= DPP * 2 + 1)
     {
      S.LineDel(S.dLLL);
      S.LabelDel(S.pdLLLl);
      if(S.LOk(S.pdLLL)) { S.lines[S.pdLLL].x2 = S.dl_i0; S.lines[S.pdLLL].y2 = S.dl_v0; }
      if(S.TOk(S.dLLLl) && S.LOk(S.pdLLL))
        {
         S.labels[S.dLLLl].x = MathAbs((int)((S.LX1(S.pdLLL) + S.LX2(S.pdLLL)) / 2) + 2);
         S.labels[S.dLLLl].y = (S.LY1(S.pdLLL) + S.LY2(S.pdLLL)) / 2;
        }
     }
   S.psHLL = S.sHLL; S.psLLL = S.sLLL; S.pdHLL = S.dHLL; S.pdLLL = S.dLLL;
   S.psHLLl = S.sHLLl; S.psLLLl = S.sLLLl; S.pdHLLl = S.dHLLl; S.pdLLLl = S.dLLLl;
  }

//+------------------------------------------------------------------+
//| EQH / EQL (SMC LuxAlgo)                                          |
//+------------------------------------------------------------------+
void EqualHL(CState &S, int t)
  {
   int size = eqLengthInput;
   if(t - size < 0) return;
   double hh = gH[t], ll = gL[t];
   for(int i = t - size + 1; i <= t; i++) { hh = MathMax(hh, gH[i]); ll = MathMin(ll, gL[i]); }
   if(gH[t - size] > hh) S.leg = 0;
   else if(gL[t - size] < ll) S.leg = 1;
   int ch = S.hasLeg ? S.leg - S.prevLeg : 0;
   S.prevLeg = S.leg; S.hasLeg = true;
   if(ch == 0) return;
   color bullC = styleInput == Monochrome ? MONO_BULL : swingBullColorInput;
   color bearC = styleInput == Monochrome ? MONO_BEAR : swingBearColorInput;
   double atr = gATR200[t];
   if(ch == 1)
     {
      double lvl = gL[t - size];
      if(showEqualHighsLowsInput && S.eqL_cur != NA && atr != NA && MathAbs(S.eqL_cur - lvl) < eqThresholdInput * atr)
        {
         if(modeInput == Present) { S.LineDel(S.eqL_line); S.LabelDel(S.eqL_lbl); }
         S.eqL_line = S.LineNew(S.eqL_time, S.eqL_cur, (double)gT[t - size], lvl, A(bullC, 0), dot, true);
         S.eqL_lbl  = S.LabelNew((int)MathRound(0.5 * (S.eqL_idx + t - size)), lvl, "EQL", 0, A(bullC, 0), LS_UP, eqSizeInput, false, false);
         Ev(AlEqual, "EQL " + Px2(lvl));
        }
      S.eqL_last = S.eqL_cur; S.eqL_cur = lvl; S.eqL_time = (double)gT[t - size]; S.eqL_idx = t - size;
     }
   else if(ch == -1)
     {
      double lvl = gH[t - size];
      if(showEqualHighsLowsInput && S.eqH_cur != NA && atr != NA && MathAbs(S.eqH_cur - lvl) < eqThresholdInput * atr)
        {
         if(modeInput == Present) { S.LineDel(S.eqH_line); S.LabelDel(S.eqH_lbl); }
         S.eqH_line = S.LineNew(S.eqH_time, S.eqH_cur, (double)gT[t - size], lvl, A(bearC, 0), dot, true);
         S.eqH_lbl  = S.LabelNew((int)MathRound(0.5 * (S.eqH_idx + t - size)), lvl, "EQH", 0, A(bearC, 0), LS_DOWN, eqSizeInput, false, false);
         Ev(AlEqual, "EQH " + Px2(lvl));
        }
      S.eqH_last = S.eqH_cur; S.eqH_cur = lvl; S.eqH_time = (double)gT[t - size]; S.eqH_idx = t - size;
     }
  }

//+------------------------------------------------------------------+
//| IMFVG (LuxAlgo)                                                  |
//+------------------------------------------------------------------+
void Imfvg(CState &S, int t, bool confirmed)
  {
   if(t < 3) return;
   double atr = gATR200[t] == NA ? 0 : gATR200[t];
   bool ok = !imfvgOnClose || confirmed;
   bool bull = gL[t - 3] > gH[t - 1] && gC[t - 2] < gL[t - 3] && gC[t] > gL[t - 3] && (gL[t - 3] - gH[t - 1] > atr * filterWidth) && showBull && ok;
   if(bull)
     {
      S.BoxNew(t - 3, gL[t - 3], t, gH[t - 1], A(bullCss, 50), 0, 0, false, false);
      double avg = (gL[t - 3] + gH[t - 1]) / 2;
      if(bullAvg) S.bull_line = S.LineNew(t, avg, t, avg, A(bullCss, 0), dsh, false);
      S.LabelNew(t, gL[t], "▲", 0, A(bullCss, 0), LS_UP, small, false, true);
      S.bull_reached = TR_FALSE;
     }
   bool bear = gL[t - 1] > gH[t - 3] && gC[t - 2] > gH[t - 3] && gC[t] < gH[t - 3] && (gL[t - 1] - gH[t - 3] > atr * filterWidth) && showBear && ok;
   if(bear)
     {
      S.BoxNew(t - 3, gL[t - 1], t, gH[t - 3], A(bearCss, 50), 0, 0, false, false);
      double avg = (gL[t - 1] + gH[t - 3]) / 2;
      if(bearAvg) S.bear_line = S.LineNew(t, avg, t, avg, A(bearCss, 0), dsh, false);
      S.LabelNew(t, gH[t], "▼", 0, A(bearCss, 0), LS_DOWN, small, false, true);
      S.bear_reached = TR_FALSE;
     }
   if(S.bull_reached == TR_FALSE && S.LOk(S.bull_line)) S.lines[S.bull_line].x2 = t;
   if(S.bear_reached == TR_FALSE && S.LOk(S.bear_line)) S.lines[S.bear_line].x2 = t;
   if(S.LOk(S.bull_line) && gC[t] < S.LY2(S.bull_line)) S.bull_reached = TR_TRUE;
   if(S.LOk(S.bear_line) && gC[t] > S.LY2(S.bear_line)) S.bear_reached = TR_TRUE;
  }

//+------------------------------------------------------------------+
//| Liquidity Defense Zones (JPT)                                    |
//+------------------------------------------------------------------+
double AtrLdz(int t) { return gATR14[t]; }   // ta.atr(ldz_atrLen)

void Ldz(CState &S, int t)
  {
   int L = ldz_pivotLen;
//--- 4. Buy-side liquidity zones
   if(PivotHigh(t, L) && t - L >= 0 && AtrLdz(t - L) != NA)
     {
      double level = gH[t - L], th = AtrLdz(t - L) * ldz_zoneAtrMult;
      int z = S.BoxNew(t - L, level + th, t, level - th, ldz_showZones ? A(PC_RED, 88) : A(PC_RED, 100), ldz_showZones ? A(PC_RED, 0) : A(PC_RED, 100), 1, false, ldz_extendZones);
      PushV(S.bslBox, z); PushV(S.bslPrice, level); bool act = true; PushV(S.bslActive, act);
      if(ldz_showLabels) S.LabelNew(t - L, level + th, "BSL", A(PC_RED, 0), A(PC_WHITE, 0), LS_DOWN, tiny, false, false);
      if(ArraySize(S.bslBox) > ldz_maxZones)
        {
         S.BoxDel(S.bslBox[0]);
         RemoveAt(S.bslBox, 0); RemoveAt(S.bslPrice, 0); RemoveAt(S.bslActive, 0);
        }
     }
//--- 5. Sell-side liquidity zones
   if(PivotLow(t, L) && t - L >= 0 && AtrLdz(t - L) != NA)
     {
      double level = gL[t - L], th = AtrLdz(t - L) * ldz_zoneAtrMult;
      int z = S.BoxNew(t - L, level + th, t, level - th, ldz_showZones ? A(PC_LIME, 88) : A(PC_LIME, 100), ldz_showZones ? A(PC_LIME, 0) : A(PC_LIME, 100), 1, false, ldz_extendZones);
      PushV(S.sslBox, z); PushV(S.sslPrice, level); bool act = true; PushV(S.sslActive, act);
      if(ldz_showLabels) S.LabelNew(t - L, level - th, "SSL", A(PC_GREEN, 0), A(PC_WHITE, 0), LS_UP, tiny, false, false);
      if(ArraySize(S.sslBox) > ldz_maxZones)
        {
         S.BoxDel(S.sslBox[0]);
         RemoveAt(S.sslBox, 0); RemoveAt(S.sslPrice, 0); RemoveAt(S.sslActive, 0);
        }
     }
//--- 6. Sweep engine
   bool bullSweep = false, bearSweep = false;
   for(int i = 0; i < ArraySize(S.bslBox); i++)
     {
      if(!S.bslActive[i]) continue;
      int z = S.bslBox[i];
      if(!S.BOk(z)) continue;
      double top = S.boxes[z].top, level = S.bslPrice[i];
      if(gH[t] > top && gC[t] < level)
        {
         bearSweep = true; S.bslActive[i] = false;
         Ev(AlSweep, "BSL SWEEP " + Px2(level));
         S.boxes[z].ext = false; S.boxes[z].x2 = t; S.boxes[z].bg = A(PC_ORANGE, 82); S.boxes[z].bd = A(PC_ORANGE, 0);
         if(ldz_showSweeps) S.LabelNew(t, gH[t], "BSL SWEEP", A(PC_ORANGE, 0), A(PC_WHITE, 0), LS_DOWN, small, false, false);
        }
      else if(gC[t] > top)
        {
         S.bslActive[i] = false;
         S.boxes[z].ext = false; S.boxes[z].x2 = t; S.boxes[z].bg = A(PC_GRAY, 90); S.boxes[z].bd = A(PC_GRAY, 0);
        }
     }
   for(int i = 0; i < ArraySize(S.sslBox); i++)
     {
      if(!S.sslActive[i]) continue;
      int z = S.sslBox[i];
      if(!S.BOk(z)) continue;
      double btm = S.boxes[z].bot, level = S.sslPrice[i];
      if(gL[t] < btm && gC[t] > level)
        {
         bullSweep = true; S.sslActive[i] = false;
         Ev(AlSweep, "SSL SWEEP " + Px2(level));
         S.boxes[z].ext = false; S.boxes[z].x2 = t; S.boxes[z].bg = A(PC_AQUA, 82); S.boxes[z].bd = A(PC_AQUA, 0);
         if(ldz_showSweeps) S.LabelNew(t, gL[t], "SSL SWEEP", A(PC_AQUA, 0), A(PC_BLACK, 0), LS_UP, small, false, false);
        }
      else if(gC[t] < btm)
        {
         S.sslActive[i] = false;
         S.boxes[z].ext = false; S.boxes[z].x2 = t; S.boxes[z].bg = A(PC_GRAY, 90); S.boxes[z].bd = A(PC_GRAY, 0);
        }
     }
//--- 7-8. Reversal signals (plotshape)
   bool buy  = bullSweep && (!ldz_requireCandleColor || gC[t] > gO[t]);
   bool sell = bearSweep && (!ldz_requireCandleColor || gC[t] < gO[t]);
   if(buy)  Ev(AlReversal, "BUY (retournement LDZ) " + Px2(gC[t]));
   if(sell) Ev(AlReversal, "SELL (retournement LDZ) " + Px2(gC[t]));
   gBuy[t]  = (char)(ldz_showReversals && buy);
   gSell[t] = (char)(ldz_showReversals && sell);
  }

//+------------------------------------------------------------------+
//| FVG Sessions (LuxAlgo)                                           |
//+------------------------------------------------------------------+
void FsSetFvg(CState &S, int t, int offset, uint bg, uint lc)
  {
   double avg = (S.fs_top + S.fs_btm) / 2;
   S.fs_area = S.BoxNew(t - offset, S.fs_top, t, S.fs_btm, bg, 0, 0, false, false);
   S.fs_lvl  = S.LineNew(t - offset, avg, t, avg, lc, dsh, false);
  }

void FvgSessions(CState &S, int t)
  {
   bool dtf = false;
   if(t > 0 && gD1.ok)
      dtf = gD1.Find(gT[t]) != gD1.Find(gT[t - 1]);
   bool bull_fvg = t >= 2 && gL[t] > gH[t - 2] && gC[t - 1] > gH[t - 2];
   bool bear_fvg = t >= 2 && gH[t] < gL[t - 2] && gC[t - 1] < gL[t - 2];
   if(dtf)
     {
      uint cc = A(PC_BLACK, 50);
      S.fs_max = S.LineNew(t, gH[t], t, gH[t], cc, sol, false);
      S.fs_min = S.LineNew(t, gL[t], t, gL[t], cc, sol, false);
      S.fs_isnew = true;
      if(S.fs_lvl >= 0)
        {
         if(S.LOk(S.fs_lvl)) S.lines[S.fs_lvl].x2 = t - 2;
         if(S.BOk(S.fs_area)) S.boxes[S.fs_area].x2 = t - 2;
        }
     }
   else if(S.fs_max >= 0)
     {
      double mx = MathMax(gH[t], S.LY2(S.fs_max) == NA ? gH[t] : S.LY2(S.fs_max));
      double mn = MathMin(gL[t], S.LY2(S.fs_min) == NA ? gL[t] : S.LY2(S.fs_min));
      if(S.LOk(S.fs_max)) { S.lines[S.fs_max].x2 = t; S.lines[S.fs_max].y2 = mx; S.lines[S.fs_max].y1 = mx; }
      if(S.LOk(S.fs_min)) { S.lines[S.fs_min].x2 = t; S.lines[S.fs_min].y2 = mn; S.lines[S.fs_min].y1 = mn; }
      uint c = A(S.fs_isbull == TR_TRUE ? fs_bullCss : fs_bearCss, 0);
      if(S.LOk(S.fs_max)) S.lines[S.fs_max].clr = c;
      if(S.LOk(S.fs_min)) S.lines[S.fs_min].clr = c;
     }
   if(bull_fvg && S.fs_isnew)
     {
      S.fs_top = gL[t]; S.fs_btm = gH[t - 2]; S.fs_mitigated = TR_FALSE; S.fs_isnew = false; S.fs_isbull = TR_TRUE;
      FsSetFvg(S, t, 2, A(fs_bullCss, fs_bullAreaT), A(fs_bullCss, 0));
      Ev(AlFvgSess, "FVG de séance haussier " + Px2(S.fs_btm) + "-" + Px2(S.fs_top));
     }
   else if(bear_fvg && S.fs_isnew)
     {
      S.fs_top = gL[t - 2]; S.fs_btm = gH[t]; S.fs_mitigated = TR_FALSE; S.fs_isnew = false; S.fs_isbull = TR_FALSE;
      FsSetFvg(S, t, 2, A(fs_bearCss, fs_bearAreaT), A(fs_bearCss, 0));
      Ev(AlFvgSess, "FVG de séance baissier " + Px2(S.fs_btm) + "-" + Px2(S.fs_top));
     }
   if(S.fs_mitigated == TR_FALSE)
     {
      if(S.fs_isbull == TR_TRUE && gC[t] < S.fs_btm)
        { FsSetFvg(S, t, 1, A(fs_bullCss, fs_bullMitT), A(fs_bullCss, 0)); S.fs_mitigated = TR_TRUE; Ev(AlFvgSess, "FVG de séance haussier comblé"); }
      else if(S.fs_isbull != TR_TRUE && gC[t] > S.fs_top)
        { FsSetFvg(S, t, 1, A(fs_bearCss, fs_bearMitT), A(fs_bearCss, 0)); S.fs_mitigated = TR_TRUE; Ev(AlFvgSess, "FVG de séance baissier comblé"); }
     }
   if(!S.fs_isnew)
     {
      if(S.LOk(S.fs_lvl)) S.lines[S.fs_lvl].x2 = t;
      if(S.BOk(S.fs_area)) S.boxes[S.fs_area].x2 = t;
      //--- alertes du Pine : prix dans le FVG (à l'entrée), moyenne croisée
      if(t > 0 && S.fs_top != NA && S.fs_btm != NA)
        {
         bool inNow = gC[t] >= S.fs_btm && gC[t] <= S.fs_top, inPrev = gC[t - 1] >= S.fs_btm && gC[t - 1] <= S.fs_top;
         string side = S.fs_isbull == TR_TRUE ? "haussier" : "baissier";
         if(inNow && !inPrev) Ev(AlFvgSess, "Prix dans le FVG de séance " + side);
         double avg = (S.fs_top + S.fs_btm) / 2;
         if((gC[t] > avg && gC[t - 1] <= avg) || (gC[t] < avg && gC[t - 1] >= avg))
            Ev(AlFvgSess, "Moyenne du FVG de séance " + side + " croisée " + Px2(avg));
        }
     }
  }

//+------------------------------------------------------------------+
//| ICT HTF FVGs (fadi)                                              |
//+------------------------------------------------------------------+
double ProximityDaily(int t)
  {
   int j = gD1.ok ? gD1.Applied(gT[t], gPer) : -1;
   return (j >= 0) ? gD1.atr[j] : NA;
  }
double ProximityMonthly(int t)
  {
   int j = gMN1.ok ? gMN1.Applied(gT[t], gPer) : -1;
   return (j >= 0) ? gMN1.atr[j] : NA;
  }

void ImbDelete(CState &S, SImb &m)
  {
   if(m.box >= 0) { S.BoxDel(m.box); S.LineDel(m.line); S.LabelDel(m.lbl); }
  }

bool AddZone(CState &S, SImb &m, int step, int k, int t, double buf)
  {
   bool visible = true;
   if(HtfShow(k))
     {
      bool bull = m.open < m.close;
      uint cBull = A(htf_color_bull, htf_transp), cBear = A(htf_color_bear, htf_transp);
      uint mBull = A(mitigated_color, mitigated_transp);
      if(m.box < 0)
        {
         uint bd = Border_show ? (bull ? A(htf_color_bull, htf_transp / 3) : A(htf_color_bear, htf_transp / 3)) : 0;
         m.box = S.BoxNew(m.open_time, m.open, buf, m.close, bull ? cBull : cBear, bd, Border_show ? 1 : 0, true, false);
         if(label_show)
            m.lbl = S.LabelNew(buf, m.middle, HtfText(HtfTf(k)), 0, A(label_color, label_transp), LS_LEFT, label_size, true, false);
         if(CE_show)
            m.line = S.LineNew(m.open_time, m.middle, buf, m.middle, A(CE_color, CE_transp), StyleOf(CE_style), true);
        }
      else
        {
         double r = m.mitigated ? m.mit_time : buf;
         if(S.BOk(m.box))
           {
            S.boxes[m.box].x2 = r;
            S.boxes[m.box].bg = bull ? (m.mitigated ? mBull : cBull) : (m.mitigated ? mBull : cBear);
            S.boxes[m.box].bd = Border_show ? A(mitigated_color, mitigated_transp / 3) : 0;
           }
         if(S.TOk(m.lbl)) S.labels[m.lbl].x = r;
         if(CE_show && S.LOk(m.line)) S.lines[m.line].x2 = r;
        }
      if(m.mitigated && !mitigated_show)
         if(m.box >= 0) { ImbDelete(S, m); visible = false; }
     }
   return visible;
  }

void AddImbalance(CState &S, SImb &arr[], double o, double c, double ot)
  {
   SImb m;
   m.open_time = ot; m.open = o; m.middle = (o + c) / 2; m.close = c; m.mitigated = false; m.mit_time = 0;
   m.line = -1; m.lbl = -1; m.box = -1; m.touched = false; m.born = gCurBar;
   InsertImb(arr, m);
   if(ArraySize(arr) > 100)
     {
      int last = ArraySize(arr) - 1;
      ImbDelete(S, arr[last]);
      RemoveAt(arr, last);
     }
  }

void CheckMitigated(CState &S, SImb &arr[], int t, int k)
  {
   for(int i = ArraySize(arr) - 1; i >= 0; i--)
     {
      if(arr[i].mitigated) continue;
      double o = arr[i].open, c = arr[i].close, md = arr[i].middle;
      bool mit = false;
      if(mitigated_type == Wick_filled)           mit = o <= c ? gL[t] <= o : gH[t] >= o;
      else if(mitigated_type == Body_filled)      mit = o < c ? MathMin(gO[t], gC[t]) <= o : MathMax(gO[t], gC[t]) >= o;
      else if(mitigated_type == Wick_filled_half) mit = o <= c ? gL[t] <= md : gH[t] >= md;
      else if(mitigated_type == Body_filled_half) mit = o <= c ? MathMin(gO[t], gC[t]) <= md : MathMax(gO[t], gC[t]) >= md;
      arr[i].mitigated = mit;
      if(mit)
        {
         if(S.BOk(arr[i].box))
            Ev(AlHtfMitig, "FVG " + HtfText(HtfTf(k)) + (o < c ? " haussier" : " baissier") + " comblé " + Px2(MathMin(o, c)) + "-" + Px2(MathMax(o, c)));
         if(!mitigated_show) { ImbDelete(S, arr[i]); RemoveAt(arr, i); }
         else arr[i].mit_time = (double)gT[t];
        }
     }
  }

void AdjustMargins(CState &S, SImb &arr[], int step, int k, int t)
  {
   if(ArraySize(arr) == 0 || t < 1) return;
   double buf = (double)gT[t] + (double)(gT[t] - gT[t - 1]) * (padding + 1 + buffer_sp * (step - 1));
   double rl = 0, rh = 0;
   if(gPer < PeriodSeconds(PERIOD_D1))
     {
      double d = ProximityDaily(t);
      rl = d == NA ? NA : gC[t] - d; rh = d == NA ? NA : gC[t] + d;
     }
   else if(gPer < PeriodSeconds(PERIOD_W1))
     {
      double m = ProximityMonthly(t);
      rl = m == NA ? NA : gC[t] - m * 3; rh = m == NA ? NA : gC[t] + m * 3;
     }
   else if(gPer < PeriodSeconds(PERIOD_MN1))
     {
      double m = ProximityMonthly(t);
      rl = m == NA ? NA : gC[t] - m * 12; rh = m == NA ? NA : gC[t] + m * 12;
     }
   int count = 0;
   for(int i = 0; i < ArraySize(arr); i++)
     {
      bool inRange = rl != NA && rh != NA && MathMax(arr[i].open, arr[i].close) > rl && MathMin(arr[i].open, arr[i].close) < rh;
      if(inRange && count < HtfMax(k))
        {
         if(AddZone(S, arr[i], step, k, t, buf)) count++;
        }
      else
         ImbDelete(S, arr[i]);
     }
  }

int ProcessHtf(CState &S, SImb &arr[], int k, int t)
  {
   if(HtfShow(k))
     {
      bool valid = gPer < PeriodSeconds(HtfTf(k));
      if(!ltf_hide || valid)
        {
         int j = gHtf[k].ok ? gHtf[k].Applied(gT[t], gPer) : -1;
         if(j - 3 >= 0)
           {
            //--- [open[1]…], [open[2]…], [open[3]…] de la bougie supérieure j
            double hh = gHtf[k].H[j - 1], ll = gHtf[k].L[j - 1];
            double h2 = gHtf[k].H[j - 3], l2 = gHtf[k].L[j - 3];
            double t2 = (double)gHtf[k].T[j - 3];
            if(hh < l2 || ll > h2)
              {
               double o = hh < l2 ? l2 : h2;
               double c = hh < l2 ? hh : ll;
               if(ArraySize(arr) == 0 || arr[0].open_time < t2)
                 {
                  AddImbalance(S, arr, o, c, t2);
                  Ev(AlHtfNew, "Nouveau FVG " + HtfText(HtfTf(k)) + (o < c ? " haussier " : " baissier ") + Px2(MathMin(o, c)) + "-" + Px2(MathMax(o, c)));
                 }
              }
           }
         S.vis[k] = 1;
        }
      CheckMitigated(S, arr, t, k);
      //--- prix qui entre dans un FVG affiché (une fois par FVG)
      for(int i = 0; i < ArraySize(arr); i++)
        {
         if(arr[i].touched || arr[i].mitigated || arr[i].born >= t) continue;
         double lo = MathMin(arr[i].open, arr[i].close), hi = MathMax(arr[i].open, arr[i].close);
         if(gL[t] <= hi && gH[t] >= lo)
           {
            arr[i].touched = true;
            if(S.BOk(arr[i].box))
               Ev(AlHtfTouch, "Prix dans le FVG " + HtfText(HtfTf(k)) + (arr[i].open < arr[i].close ? " haussier " : " baissier ") + Px2(lo) + "-" + Px2(hi));
           }
        }
     }
   return S.vis[k];
  }

void IctHtf(CState &S, int t)
  {
   int step = 0;
   step += ProcessHtf(S, S.imb0, 0, t); AdjustMargins(S, S.imb0, step, 0, t);
   step += ProcessHtf(S, S.imb1, 1, t); AdjustMargins(S, S.imb1, step, 1, t);
   step += ProcessHtf(S, S.imb2, 2, t); AdjustMargins(S, S.imb2, step, 2, t);
   step += ProcessHtf(S, S.imb3, 3, t); AdjustMargins(S, S.imb3, step, 3, t);
   step += ProcessHtf(S, S.imb4, 4, t); AdjustMargins(S, S.imb4, step, 4, t);
   step += ProcessHtf(S, S.imb5, 5, t); AdjustMargins(S, S.imb5, step, 5, t);
  }

//+------------------------------------------------------------------+
//| Une exécution du script sur la bougie t                          |
//+------------------------------------------------------------------+
void ProcessBar(CState &S, int t, bool confirmed)
  {
   gBuy[t] = 0; gSell[t] = 0;
   gCurBar = t;
   Smc(S, t);
   Llf(S, t);
   EqualHL(S, t);
   Imfvg(S, t, confirmed);
   Ldz(S, t);
   FvgSessions(S, t);
   IctHtf(S, t);
  }

//+------------------------------------------------------------------+
bool LoadHtf()
  {
   datetime from = gT[0];
   bool ok = true;
   for(int k = 0; k < 6; k++)
      if(HtfShow(k) && (!ltf_hide || gPer < PeriodSeconds(HtfTf(k))))
         ok = gHtf[k].Load(from - 40 * PeriodSeconds(HtfTf(k)), from) && ok;
   ok = gD1.Load(from - 60 * 86400, from) && ok;
   if(gPer >= PeriodSeconds(PERIOD_D1))
      ok = gMN1.Load(from - 40 * 31 * 86400, from) && ok;
   return ok;
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < 100)
      return 0;
   gPer = PeriodSeconds(PERIOD_CURRENT);
   bool full = prev_calculated == 0 || gProcessed == -1 || rates_total < gTotal || rates_total - gTotal > 1;
   if(full)
     {
      gBase = MathMax(0, rates_total - InpMaxBars);
      gN = rates_total - gBase;
      ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gT, gN);
      ArrayResize(gBuy, gN); ArrayResize(gSell, gN);
      for(int i = 0; i < gN; i++)
        {
         gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i]; gT[i] = time[gBase + i];
         gBuy[i] = 0; gSell[i] = 0;
        }
      Atr(gATR14, ldz_atrLen, 0); Atr(gATR55, 55, 0); Atr(gATR200, 200, 0);
      gTotal = rates_total;
      if(!LoadHtf())
        {
         gProcessed = -2;              // unités supérieures en téléchargement : la minuterie recommence
         if(gCvOk) { gCv.Erase(0); gCv.Update(true); }   // pas de dessin périmé en attendant
         return rates_total;
        }
      gCommit.Reset((double)gT[0]);
      gProcessed = 0;
     }
   else
     {
      int from = gN - 1;
      gN = rates_total - gBase;
      ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gT, gN);
      ArrayResize(gBuy, gN); ArrayResize(gSell, gN);
      for(int i = from; i < gN; i++)
        {
         gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i]; gT[i] = time[gBase + i];
         if(i > from) { gBuy[i] = 0; gSell[i] = 0; }
        }
      Atr(gATR14, ldz_atrLen, from); Atr(gATR55, 55, from); Atr(gATR200, 200, from);
      if(gProcessed == -2)
        {
         gTotal = rates_total;
         return rates_total;           // calcul complet en attente des données (OnTimer)
        }
      if(gN - 1 > gProcessed)
         LoadHtf();                    // nouvelle bougie : bougies supérieures clôturées à jour
     }
   gTotal = rates_total;
   bool newBar = false;
   while(gProcessed < gN - 1)
     {
      //--- alertes seulement pour les bougies qui clôturent en direct, pas pour l'historique
      gAlertLive = !full && gProcessed >= gN - 3;
      gAlertBuf = "";
      ProcessBar(gCommit, gProcessed, true);
      gAlertLive = false;
      if(gAlertBuf != "")
         SendAlert(gAlertBuf, gT[gProcessed]);
      gProcessed++;
      newBar = true;
     }
//--- bougie en cours : recalculée sur une copie de l'état, comme TradingView à chaque tick
   uint now = GetTickCount();
   if(full || newBar || now - gLastWork >= 250)
     {
      gWork.CopyFrom(gCommit);
      ProcessBar(gWork, gN - 1, false);
      gLastWork = now;
      Render(gWork);
      gLastRender = now;
     }
   return rates_total;
  }

void SendAlert(string msg, datetime bar)
  {
   string tf = gPer < 3600 ? "M" + IntegerToString(gPer / 60) : gPer < 86400 ? "H" + IntegerToString(gPer / 3600)
               : gPer == 86400 ? "D1" : gPer == 604800 ? "W1" : "MN1";
   string txt = "CX Exécution " + _Symbol + " " + tf + " " + TimeToString(bar, TIME_MINUTES) + " : " + msg;
   if(AlPopup) Alert(txt);
   if(AlPush)  SendNotification(StringSubstr(txt, 0, 255));
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_CHART_CHANGE || gN <= 0 || gProcessed < 0)
      return;
   gDirty = true;
   if(GetTickCount() - gLastRender >= 40)
      Render(gWork);               // sinon la minuterie redessine (défilement rapide)
  }

//--- Données des unités supérieures arrivées après le premier calcul (week-end, premier lancement) :
//    calcul complet sans attendre un tick.
void OnTimer()
  {
   if(gDirty && gProcessed >= 0)
      Render(gWork);
   static uint lastTry = 0;
   if(gProcessed != -2 || gN < 100 || GetTickCount() - lastTry < 1000)
      return;
   lastTry = GetTickCount();
   if(!LoadHtf())
      return;
   gCommit.Reset((double)gT[0]);
   for(gProcessed = 0; gProcessed < gN - 1; gProcessed++)
      ProcessBar(gCommit, gProcessed, true);
   gWork.CopyFrom(gCommit);
   ProcessBar(gWork, gN - 1, false);
   gLastWork = GetTickCount();
   Render(gWork);
  }

//+------------------------------------------------------------------+
//| Dessin                                                           |
//+------------------------------------------------------------------+
double gX0 = 0, gSp = 1, gY0 = 0, gKy = 0, gPMax = 0;
int    gT0 = 0;

int    Px(double v)  { return (int)MathRound(v * gDpi); }
int    Wpx(int w)    { return MathMax(1, (int)MathFloor(w * gDpi)); }
double XofBar(double b) { return gX0 + (b - gT0) * gSp; }
double YofPrice(double p) { return gY0 + (gPMax - p) * gKy; }

//--- heure -> abscisse : bougie qui contient l'heure, ou prolongement au-delà de la dernière
double XofTime(double tm)
  {
   if(gN <= 0) return 0;
   if(tm >= (double)gT[gN - 1]) return XofBar(gN - 1 + (tm - (double)gT[gN - 1]) / gPer);
   if(tm < (double)gT[0]) return XofBar((tm - (double)gT[0]) / gPer);
   int lo = 0, hi2 = gN - 1;
   while(lo < hi2) { int m = (lo + hi2 + 1) / 2; if((double)gT[m] <= tm) lo = m; else hi2 = m - 1; }
   return XofBar(lo);
  }
double Xof(double x, bool xt) { return xt ? XofTime(x) : XofBar(x); }

//--- mélange « par-dessus » en entiers : les grandes zones se redessinent vite au défilement
void BlendPx(int x, int y, uint c, double cov)
  {
   if(x < 0 || y < 0 || x >= gW || y >= gHh) return;
   uint sa = (uint)(((c >> 24) & 0xFF) * (cov >= 1.0 ? 1.0 : cov));
   if(sa == 0) return;
   uint d = gCv.PixelGet(x, y);
   uint da = (d >> 24) & 0xFF;
   if(sa >= 255 || da == 0) { gCv.PixelSet(x, y, (sa << 24) | (c & 0xFFFFFF)); return; }
   uint k  = da * (255 - sa) / 255;
   uint oa = sa + k;
   uint r = ((((c >> 16) & 0xFF) * sa) + (((d >> 16) & 0xFF) * k)) / oa;
   uint g = ((((c >> 8) & 0xFF) * sa) + (((d >> 8) & 0xFF) * k)) / oa;
   uint b = (((c & 0xFF) * sa) + ((d & 0xFF) * k)) / oa;
   gCv.PixelSet(x, y, (oa << 24) | (r << 16) | (g << 8) | b);
  }

void FillRect(int x1, int y1, int x2, int y2, uint c)
  {
   int xa = MathMax(MathMin(x1, x2), 0), xb = MathMin(MathMax(x1, x2), gW - 1);
   int ya = MathMax(MathMin(y1, y2), 0), yb = MathMin(MathMax(y1, y2), gHh - 1);
   for(int y = ya; y <= yb; y++)
      for(int x = xa; x <= xb; x++)
         BlendPx(x, y, c, 1.0);
  }

void FillRoundRect(int x1, int y1, int x2, int y2, double rad, uint c)
  {
   for(int y = MathMax(y1, 0); y < MathMin(y2, gHh); y++)
      for(int x = MathMax(x1, 0); x < MathMin(x2, gW); x++)
        {
         double px = x + 0.5, py = y + 0.5;
         double qx = MathMax(MathMax(x1 + rad - px, px - (x2 - rad)), 0.0);
         double qy = MathMax(MathMax(y1 + rad - py, py - (y2 - rad)), 0.0);
         double cov = 1.0;
         if(qx > 0.0 && qy > 0.0) cov = MathMax(0.0, MathMin(1.0, rad + 0.5 - MathSqrt(qx * qx + qy * qy)));
         if(cov > 0.0) BlendPx(x, y, c, cov);
        }
  }

//--- trait de 1 px (plein, tirets, points), horizontal, vertical ou oblique
void DrawLine(double x1, double y1, double x2, double y2, int style, int w, uint c)
  {
   //--- découpe à la zone visible pour ne pas parcourir des milliers de pixels hors écran
   double m = 2000;
   if(MathMax(x1, x2) < -m || MathMin(x1, x2) > gW + m) return;
   double len = MathSqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
   int on = 0, off = 0;
   if(style == dsh) { on = Px(4); off = Px(4); }
   if(style == dot) { on = MathMax(w, 1); off = MathMax(w, 1) * 2; }
   if(len < 1.0) { BlendPx((int)MathRound(x1), (int)MathRound(y1), c, 1.0); return; }
   double s0 = 0, s1 = len;
   if(x2 != x1)
     {
      double ta = (0 - x1) / (x2 - x1) * len, tb = (gW - x1) / (x2 - x1) * len;
      s0 = MathMax(0.0, MathMin(ta, tb) - 2); s1 = MathMin(len, MathMax(ta, tb) + 2);
     }
   int lx = -100000, ly = -100000;
   for(double s = s0; s <= s1; s += 1.0)
     {
      if(style != sol && ((int)s % (on + off)) >= on) continue;
      int x = (int)MathRound(x1 + (x2 - x1) * s / len), y = (int)MathRound(y1 + (y2 - y1) * s / len);
      if(x == lx && y == ly) continue;
      lx = x; ly = y;
      for(int k = 0; k < w; k++)
        {
         if(MathAbs(x2 - x1) >= MathAbs(y2 - y1)) BlendPx(x, y - (w - 1) / 2 + k, c, 1.0);
         else BlendPx(x - (w - 1) / 2 + k, y, c, 1.0);
        }
     }
  }

void FillPointer(double ax, int ay, int h, double halfW, int dir, uint c)
  {
   for(int j = 0; j < h; j++)
     {
      double half = halfW * (j + 0.5) / h;
      int y = ay + dir * j - (dir < 0 ? 1 : 0);
      for(int x = (int)MathFloor(ax - half - 1); x <= (int)MathCeil(ax + half + 1); x++)
        {
         double cov = MathMax(0.0, MathMin(1.0, half + 0.5 - MathAbs(x + 0.5 - ax)));
         if(cov > 0.0) BlendPx(x, y, c, cov);
        }
     }
  }
void FillPointerH(int ax, double ay, int w, double halfH, uint c)
  {
   for(int j = 0; j < w; j++)
     {
      double half = halfH * (j + 0.5) / w;
      int x = ax + j;
      for(int y = (int)MathFloor(ay - half - 1); y <= (int)MathCeil(ay + half + 1); y++)
        {
         double cov = MathMax(0.0, MathMin(1.0, half + 0.5 - MathAbs(y + 0.5 - ay)));
         if(cov > 0.0) BlendPx(x, y, c, cov);
        }
     }
  }

//--- tailles de texte de TradingView (mesurées sur les captures), en dixièmes de point
void SetFont(int size, bool sym)
  {
   int s = size == tiny ? -45 : size == small ? -60 : -75;
   gCv.FontSet(sym ? "Arial" : InpFont, s);
  }

void DrawLabel(const DLabel &lb)
  {
   double ax = Xof(lb.x, lb.xt);
   if(ax < -300 || ax > gW + 300) return;
   double ay = YofPrice(lb.y);
   if(ay < -100 || ay > gHh + 100) return;
   SetFont(lb.size, lb.sym);
   int tw = 0, th = 0;
   gCv.TextSize(lb.text, tw, th);
   int padX = Px(3), padY = Px(1), ph = Px(3);
   int w = tw + 2 * padX, h = th + 2 * padY;
   int iy = (int)MathRound(ay), ix = (int)MathRound(ax);
   bool bg = ((lb.bg >> 24) & 0xFF) > 0;
   int x1, top;
   if(lb.style == LS_LEFT)
     {
      x1 = ix + ph; top = iy - h / 2;
      if(bg) { FillPointerH(ix, ay, ph + 1, ph, lb.bg); FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, lb.bg); }
     }
   else
     {
      x1 = (int)MathRound(ax - w / 2.0);
      top = lb.style == LS_UP ? iy + ph : iy - ph - h;
      if(bg) { FillPointer(ax, iy, ph + 1, ph, lb.style == LS_UP ? 1 : -1, lb.bg); FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, lb.bg); }
     }
   gCv.TextOut(x1 + w / 2, top + h / 2, lb.text, lb.tc, TA_CENTER | TA_VCENTER);
  }

//--- plotshape(shape.cross) avec son texte
void DrawCross(int x, int y, uint c)
  {
   int r = Px(6), w = MathMax(1, Px(1.5));
   for(int k = 0; k < w; k++)
     {
      DrawLine(x - r, y - (w - 1) / 2 + k, x + r, y - (w - 1) / 2 + k, sol, 1, c);
      DrawLine(x - (w - 1) / 2 + k, y - r, x - (w - 1) / 2 + k, y + r, sol, 1, c);
     }
  }

void Render(CState &S)
  {
   int W = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int H = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(W <= 0 || H <= 0 || gN < 2) return;
   if(!gCvOk)
     {
      if(!gCv.CreateBitmapLabel(0, 0, gName, 0, 0, W, H, COLOR_FORMAT_ARGB_NORMALIZE)) return;
      gCvOk = true;
      ObjectSetInteger(0, gName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, gName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, gName, OBJPROP_BACK, false);
     }
   else if(gCv.Width() != W || gCv.Height() != H)
      gCv.Resize(W, H);
   gW = W; gHh = H;
   gCv.Erase(0);

   //--- correspondance bougie/prix -> pixels, depuis la première bougie visible
   int firstShift = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   firstShift = MathMax(1, MathMin(firstShift, bars - 1));
   double pMax = ChartGetDouble(0, CHART_PRICE_MAX, 0), pMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   int xa, ya, xb, yb;
   if(pMax <= pMin || !ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, firstShift), pMax, xa, ya)
      || !ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, firstShift - 1), pMin, xb, yb))
     { gCv.Update(true); return; }
   gT0 = (gN - 1) - firstShift;                   // indice local de la première bougie visible
   gX0 = xa;
   gSp = xb - xa;
   if(gSp <= 0) gSp = 1 << (int)ChartGetInteger(0, CHART_SCALE);
   gPMax = pMax; gY0 = ya; gKy = (double)(yb - ya) / (pMax - pMin);
   int lw = Wpx(1);

   //--- boîtes
   for(int i = 0; i < ArraySize(S.boxes); i++)
     {
      if(!S.boxes[i].alive) continue;
      int x1 = (int)MathRound(Xof(S.boxes[i].x1, S.boxes[i].xt));
      int x2 = S.boxes[i].ext ? W + 10 : (int)MathRound(Xof(S.boxes[i].x2, S.boxes[i].xt));
      if(x2 < x1) { int s = x1; x1 = x2; x2 = s; }
      if(x2 < 0 || x1 > W) continue;
      int y1 = (int)MathRound(YofPrice(MathMax(S.boxes[i].top, S.boxes[i].bot)));
      int y2 = (int)MathRound(YofPrice(MathMin(S.boxes[i].top, S.boxes[i].bot)));
      if(y2 < 0 || y1 > H) continue;
      bool border = S.boxes[i].bw > 0 && ((S.boxes[i].bd >> 24) & 0xFF) > 0;
      if(border)
        {
         FillRect(x1 + lw, y1 + lw, x2 - lw, y2 - lw, S.boxes[i].bg);
         FillRect(x1, y1, x2, y1 + lw - 1, S.boxes[i].bd);
         FillRect(x1, y2 - lw + 1, x2, y2, S.boxes[i].bd);
         FillRect(x1, y1 + lw, x1 + lw - 1, y2 - lw, S.boxes[i].bd);
         FillRect(x2 - lw + 1, y1 + lw, x2, y2 - lw, S.boxes[i].bd);
        }
      else
         FillRect(x1, y1, x2, y2, S.boxes[i].bg);
     }
   //--- lignes
   for(int i = 0; i < ArraySize(S.lines); i++)
     {
      if(!S.lines[i].alive) continue;
      double x1 = MathRound(Xof(S.lines[i].x1, S.lines[i].xt)), x2 = MathRound(Xof(S.lines[i].x2, S.lines[i].xt));
      double y1 = MathRound(YofPrice(S.lines[i].y1)), y2 = MathRound(YofPrice(S.lines[i].y2));
      if((y1 < -50 && y2 < -50) || (y1 > H + 50 && y2 > H + 50)) continue;
      DrawLine(x1, y1, x2, y2, S.lines[i].style, lw, S.lines[i].clr);
     }
   //--- étiquettes
   for(int i = 0; i < ArraySize(S.labels); i++)
      if(S.labels[i].alive) DrawLabel(S.labels[i]);
   //--- signaux BUY / SELL (plotshape)
   for(int t = MathMax(0, gT0 - 2); t < gN; t++)
     {
      if(gBuy[t] == 0 && gSell[t] == 0) continue;
      int x = (int)MathRound(XofBar(t));
      if(x < -50 || x > W + 50) continue;
      SetFont(small, false);
      if(gBuy[t] != 0)
        {
         int y = (int)MathRound(YofPrice(gL[t]));
         gCv.TextOut(x, y + Px(42), "BUY", A(PC_BLACK, 0), TA_CENTER | TA_VCENTER);
         DrawCross(x, y + Px(58), A(PC_LIME, 0));
        }
      if(gSell[t] != 0)
        {
         int y = (int)MathRound(YofPrice(gH[t]));
         gCv.TextOut(x, y - Px(42), "SELL", A(PC_WHITE, 0), TA_CENTER | TA_VCENTER);
         DrawCross(x, y - Px(58), A(PC_RED, 0));
        }
     }
   gCv.Update(true);
   gLastRender = GetTickCount();
   gDirty = false;
  }
//+------------------------------------------------------------------+
