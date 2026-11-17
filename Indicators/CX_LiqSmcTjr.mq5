//+------------------------------------------------------------------+
//| CX_LiqSmcTjr.mq5                                                 |
//| CX Liquidity · SMC Lite · TJR · IMFVG : quatre indicateurs       |
//| TradingView portés fidèlement en MQL5 (version TradingView :     |
//| Pine/CX_LiqSmcTjr.pine, mêmes codes d'origine).                  |
//|  1. Liquidity Swings & Sweeps (© OutofOptions, MPL 2.0)          |
//|  2. TJR Swing High/Low + BOS (Tom Brown, 1.3.1-dev)              |
//|  3. FluidTrades - SMC Lite (© Pmgjiv, MPL 2.0) : textes SUPPLY,  |
//|     DEMAND, POI et BOS masqués par défaut sur MT5.               |
//|  4. FVG Instantaneous Mitigation Signals [LuxAlgo]              |
//|     (CC BY-NC-SA 4.0 : usage personnel, non commercial).         |
//| Calcul bougie par bougie comme TradingView : bougies clôturées   |
//| une fois, bougie en cours recalculée sur une copie de l'état.    |
//| Limite de 500 objets par type pour chaque partie, comme quatre   |
//| indicateurs TradingView séparés. Dessin CCanvas, Trebuchet MS ;  |
//| couleur des bougies et trailing stop de l'IMFVG en tracés MT5.   |
//+------------------------------------------------------------------+
#property copyright   "CX Liquidity · SMC Lite · TJR · IMFVG"
#property version     "1.00"
#property description "Liquidity Swings & Sweeps + TJR Swing High/Low + BOS + FluidTrades SMC Lite + FVG Instantaneous Mitigation Signals, affichage TradingView."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   2
//--- barcolor de l'IMFVG : bougies recolorées (mêmes largeurs que celles du graphique)
#property indicator_label1  "IMFVG barcolor"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  C'8,153,129',C'242,54,69'
//--- plot « Trailing Stop » de l'IMFVG
#property indicator_label2  "Trailing Stop"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  C'8,153,129',C'242,54,69'
#property indicator_width2  1

#include <Canvas\Canvas.mqh>

enum ENUM_LSTYLE  { sol = 0, dsh = 1, dot = 2 };
enum ENUM_TSIZE   { tiny = 0, small = 1, normal = 2 };
enum ENUM_EXT     { ext1 = 1, ext2 = 2, ext3 = 3 };
enum ENUM_TSRESET { EverySignals = 0,  // Every Signals
                    InverseSignals = 1 // Inverse Signals
                  };

//--- 1. Liquidity Swings & Sweeps
input group "Liquidity Swings & Sweeps · Settings"
input bool        LsOn     = true;              // Afficher Liquidity Swings & Sweeps
input int         LsLeft   = 5;                 // Swing Sensitivity (Left)
input int         LsRight  = 2;                 // Swing Sensitivity (Right)
input bool        LsMax    = true;              // Find Maximum Liquidity
input group "Liquidity Swings & Sweeps · Appearance"
input color       LsUpCol  = C'242,54,69';      // High Liquidity Line Color
input int         LsUpT    = 35;                // High · transparence
input color       LsDnCol  = C'8,153,129';      // Low Liquidity Line Color
input int         LsDnT    = 35;                // Low · transparence
input int         LsWidth  = 1;                 // Line Width
input bool        LsLabel  = true;              // Show Liquidity Sweep Label/Rating
input group "Liquidity Swings & Sweeps · Alert on Liquidity Sweep (à la clôture)"
input bool        LsAlA    = false;             // ❄️ Weak
input bool        LsAlB    = false;             // ✅ Ok
input bool        LsAlC    = true;              // 🔥 Strong
input bool        LsAlD    = true;              // 💥 Very Strong
input string      LsAlMsg  = "Liquidity Sweep: "; // Alert Message Prefix
input bool        AlPopup  = true;              // Fenêtre et son MT5
input bool        AlPush   = true;              // Notification mobile (MetaQuotes ID)

//--- 2. FluidTrades - SMC Lite
input group "FluidTrades - SMC Lite · Settings"
input bool        FtOn        = true;           // Afficher SMC Lite
input int         FtSwing     = 10;             // Swing High/Low Length
input int         FtHistory   = 20;             // History To Keep
input double      FtBoxWidth  = 2.5;            // Supply/Demand Box Width
input group "FluidTrades - SMC Lite · Visual Settings"
input bool        FtZigzag    = false;          // Show Zig Zag
input bool        FtPaLabels  = false;          // Show Price Action Labels
input color       FtSupply    = C'237,237,237'; // Supply
input int         FtSupplyT   = 70;             // Supply · transparence
input color       FtSupplyOut = clrWhite;       // Supply · Outline
input int         FtSupplyOutT= 75;             // Supply · Outline · transparence
input color       FtDemand    = C'0,255,255';   // Demand
input int         FtDemandT   = 70;             // Demand · transparence
input color       FtDemandOut = clrWhite;       // Demand · Outline
input int         FtDemandOutT= 75;             // Demand · Outline · transparence
input color       FtBosLabel  = clrWhite;       // BOS Label
input color       FtPoiLabel  = clrWhite;       // POI Label
input color       FtSwingType = C'54,58,69';    // Price Action Label
input color       FtZzColor   = C'0,0,0';       // Zig Zag
input bool        FtTexts     = false;          // Textes SUPPLY, DEMAND, POI et BOS

//--- 3. TJR Swing High/Low + BOS
input group "TJR · Most Recent Swing High & Low"
input bool        TjShowSwings = true;          // Show Swings
input color       TjShCol   = C'242,54,69';     // Swing High · Colour
input int         TjShOp    = 100;              // Swing High · Opacity (100 = fully visible)
input ENUM_LSTYLE TjShStyle = sol;              // Swing High · Line style
input int         TjShWidth = 2;                // Swing High · Thickness
input color       TjSlCol   = C'242,54,69';     // Swing Low · Colour
input int         TjSlOp    = 100;              // Swing Low · Opacity (100 = fully visible)
input ENUM_LSTYLE TjSlStyle = sol;              // Swing Low · Line style
input int         TjSlWidth = 2;                // Swing Low · Thickness
input group "TJR · Break of Structure"
input bool        TjShowBos  = true;            // Show BOS
input color       TjBosCol   = C'242,54,69';    // Most Recent BOS · Colour
input int         TjBosOp    = 100;             // Most Recent BOS · Opacity
input ENUM_LSTYLE TjBosStyle = sol;             // Most Recent BOS · Line style
input int         TjBosWidth = 1;               // Most Recent BOS · Thickness
input ENUM_EXT    TjBosExt   = ext2;            // Most Recent BOS · Extend past BOS candle (bars)
input color       TjBos1Col  = C'120,123,134';  // BOS -1 Ago · Colour
input int         TjBos1Op   = 50;              // BOS -1 Ago · Opacity
input ENUM_LSTYLE TjBos1Style= sol;             // BOS -1 Ago · Line style
input int         TjBos1Width= 1;               // BOS -1 Ago · Thickness
input ENUM_EXT    TjBos1Ext  = ext2;            // BOS -1 Ago · Extend past BOS candle (bars)
input group "TJR · Swing High/Low Extension + Trigger Line"
input bool        TjShowExt  = true;            // Show Extension + Trigger Line
input color       TjExtCol   = C'255,152,0';    // Extension · Colour
input int         TjExtOp    = 100;             // Extension · Opacity
input ENUM_LSTYLE TjExtStyle = dot;             // Extension · Line style
input int         TjExtWidth = 1;               // Extension · Thickness
input ENUM_EXT    TjExtExt   = ext2;            // Extend past current candle (bars)
input color       TjCdCol    = C'255,152,0';    // Countdown Text Colour
input color       TjPbCol    = C'255,152,0';    // Potential BOS · Colour
input int         TjPbOp     = 100;             // Potential BOS · Opacity
input ENUM_LSTYLE TjPbStyle  = sol;             // Potential BOS · Line style
input int         TjPbWidth  = 2;               // Potential BOS · Thickness

//--- 4. FVG Instantaneous Mitigation Signals [LuxAlgo]
input group "FVG Instantaneous Mitigation Signals"
input bool         ImOn       = true;           // Afficher FVG Instantaneous Mitigation Signals
input double       ImFilter   = 0.0;            // FVG Width Filter
input group "IMFVG · TP/SL"
input bool         ImShowTp   = false;          // TP Area
input double       ImTpMult   = 4.0;            // TP · Multiplier
input color        ImTpCss    = C'91,156,246';  // TP · couleur
input int          ImTpT      = 80;             // TP · transparence
input bool         ImShowSl   = false;          // SL Area
input double       ImSlMult   = 2.0;            // SL · Multiplier
input color        ImSlCss    = C'120,123,134'; // SL · couleur
input int          ImSlT      = 80;             // SL · transparence
input group "IMFVG · Trailing Stop"
input ENUM_TSRESET ImTsReset  = EverySignals;   // Reset Trailing Stop
input double       ImTsMult   = 3.0;            // Multiplier
input bool         ImPlotTs   = true;           // Tracer le Trailing Stop
input group "IMFVG · Style"
input bool         ImShowBull = true;           // Bullish IMFVG
input color        ImBullCss  = C'8,153,129';   // Bullish · couleur
input bool         ImBullAvg  = true;           // Bullish · Average
input bool         ImShowBear = true;           // Bearish IMFVG
input color        ImBearCss  = C'242,54,69';   // Bearish · couleur
input bool         ImBearAvg  = true;           // Bearish · Average
input bool         ImBarColor = true;           // Couleur des bougies (barcolor)

input group "MT5"
input int    InpMaxBars = 5000;                 // Bougies calculées (TradingView : 5 000)
input string InpFont    = "Trebuchet MS";       // Police (celle de TradingView)

#define NA        EMPTY_VALUE
#define NAI       -1
#define MAX_OBJ   500
#define CD_MARK   "\x01CD"                      // texte remplacé par le compte à rebours au dessin

enum ENUM_LBLSTYLE { LS_DOWN = 0, LS_UP = 1, LS_LEFT = 2, LS_CENTER = 3 };
enum ENUM_PART     { P_LS = 0, P_FT = 1, P_TJ = 2, P_IM = 3 };

//--- Alertes : collectées pendant le calcul d'une bougie clôturée en direct, envoyées ensemble
bool   gAlertLive = false;
string gAlertBuf  = "";
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

//--- Objets dessinés (line, box, label de Pine). x : indice local de bougie.
struct DLine  { double x1; double y1; double x2; double y2; uint clr; int style; int width; int part; bool alive; };
struct DBox   { double x1; double top; double x2; double bot; uint bg; uint bd; bool ext; string text; uint tc;
                int tsize; bool tleft; int part; bool alive; };
struct DLabel { double x; double y; string text; uint tc; int style; int size; int part; bool alive; };

//--- Liquidity Swings & Sweeps : liquidity (time = indice de bougie, -1 = non défini) et HL
struct SLiq { double price; int time; bool broken; int drawLine; int breakLine; int breakLabel; int brokenTime; bool current; };
struct SHiLo  { double price; int time; };

template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
template<typename T> void CopyArr(T &d[], const T &s[])
  {
   int n = ArraySize(s);
   ArrayResize(d, n, 64);
   for(int i = 0; i < n; i++) d[i] = s[i];
  }
//--- array.unshift : insertion en tête
template<typename T> void Unshift(T &a[], const T &v)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1, 64);
   for(int i = n; i > 0; i--) a[i] = a[i - 1];
   a[0] = v;
  }
template<typename T> void RemoveAt(T &a[], int k)
  {
   int n = ArraySize(a);
   for(int i = k; i < n - 1; i++) a[i] = a[i + 1];
   ArrayResize(a, n - 1, 64);
  }
//--- f_array_add_pop de FluidTrades : insertion en tête, dernier retiré (scalaires)
void AddPopD(double &a[], double v) { int n = ArraySize(a); for(int i = n - 1; i > 0; i--) a[i] = a[i - 1]; a[0] = v; }
void AddPopI(int &a[], int v)       { int n = ArraySize(a); for(int i = n - 1; i > 0; i--) a[i] = a[i - 1]; a[0] = v; }

//+------------------------------------------------------------------+
//| État complet des trois scripts (variables « var » et objets)     |
//+------------------------------------------------------------------+
class CState
  {
public:
   DLine  lines[];  DBox boxes[];  DLabel labels[];
   int    liveL[4];
   int    oldL[4];
   int    liveB[4];
   int    oldB[4];
   int    liveT[4];
   int    oldT[4];
   //--- Liquidity Swings & Sweeps : réservoir d'objets liquidity, tableaux d'indices, HL mineurs
   SLiq   lsPool[];
   int    lsBear[];
   int    lsBull[];
   SHiLo    lsHLA[];
   SHiLo    lsLLA[];
   //--- IMFVG
   int    imBullLine, imBearLine, imOs, imOsPrev;
   bool   imBullLvl, imBearLvl, imTsReached;
   double imTs;
   int    imTp[];
   int    imSl[];
   bool   imReached[];
   //--- FluidTrades
   double ftShV[];
   double ftSlV[];
   int    ftShB[];
   int    ftSlB[];
   int    ftSupBox[];
   int    ftDemBox[];
   int    ftSupPoi[];
   int    ftDemPoi[];
   int    ftSupBos[];
   int    ftDemBos[];
   bool   zzDirUp;
   double zzLastLow, zzLastHigh;
   int    zzTimeLow, zzTimeHigh, zzLi;
   bool   zzInit;
   //--- TJR
   bool   tjHasPrev, tjPrevBull;
   double tjPrevH, tjPrevL;
   int    tjPrevBar, tjShCur, tjSlCur, tjTrend;
   double tjShP, tjSlP;
   int    tjShBar, tjSlBar, tjBosLine, tjBosPrev, tjBosBar, tjBosPrevBar;
   int    tjExtSh, tjExtSl, tjPbSh, tjPbSl, tjCdSh, tjCdSl;

   void Reset()
     {
      ArrayFree(lines); ArrayFree(boxes); ArrayFree(labels);
      for(int p = 0; p < 4; p++) { liveL[p] = oldL[p] = liveB[p] = oldB[p] = liveT[p] = oldT[p] = 0; }
      ArrayFree(lsPool); ArrayFree(lsBear); ArrayFree(lsBull); ArrayFree(lsHLA); ArrayFree(lsLLA);
      imBullLine = imBearLine = NAI; imOs = 0; imOsPrev = 0; imBullLvl = imBearLvl = false; imTsReached = false; imTs = NA;
      ArrayResize(imTp, 2); ArrayResize(imSl, 2); ArrayResize(imReached, 2);
      ArrayInitialize(imTp, NAI); ArrayInitialize(imSl, NAI); ArrayInitialize(imReached, false);
      ArrayResize(ftShV, 5); ArrayResize(ftSlV, 5); ArrayResize(ftShB, 5); ArrayResize(ftSlB, 5);
      ArrayResize(ftSupBos, 5); ArrayResize(ftDemBos, 5);
      ArrayInitialize(ftShV, 0.0); ArrayInitialize(ftSlV, 0.0); ArrayInitialize(ftShB, 0); ArrayInitialize(ftSlB, 0);
      ArrayInitialize(ftSupBos, NAI); ArrayInitialize(ftDemBos, NAI);
      int h = MathMax(1, FtHistory);
      ArrayResize(ftSupBox, h); ArrayResize(ftDemBox, h); ArrayResize(ftSupPoi, h); ArrayResize(ftDemPoi, h);
      ArrayInitialize(ftSupBox, NAI); ArrayInitialize(ftDemBox, NAI); ArrayInitialize(ftSupPoi, NAI); ArrayInitialize(ftDemPoi, NAI);
      zzDirUp = false; zzLastLow = NA; zzLastHigh = 0.0; zzTimeLow = 0; zzTimeHigh = 0; zzLi = NAI; zzInit = false;
      tjHasPrev = false; tjPrevBull = false; tjPrevH = tjPrevL = NA; tjPrevBar = NAI;
      tjShCur = tjSlCur = NAI; tjTrend = 0; tjShP = tjSlP = NA; tjShBar = tjSlBar = NAI;
      tjBosLine = tjBosPrev = NAI; tjBosBar = tjBosPrevBar = NAI;
      tjExtSh = tjExtSl = tjPbSh = tjPbSl = tjCdSh = tjCdSl = NAI;
     }

   void CopyFrom(const CState &o)
     {
      CopyArr(lines, o.lines); CopyArr(boxes, o.boxes); CopyArr(labels, o.labels);
      for(int p = 0; p < 4; p++)
        { liveL[p] = o.liveL[p]; oldL[p] = o.oldL[p]; liveB[p] = o.liveB[p]; oldB[p] = o.oldB[p]; liveT[p] = o.liveT[p]; oldT[p] = o.oldT[p]; }
      CopyArr(lsPool, o.lsPool); CopyArr(lsBear, o.lsBear); CopyArr(lsBull, o.lsBull); CopyArr(lsHLA, o.lsHLA); CopyArr(lsLLA, o.lsLLA);
      imBullLine = o.imBullLine; imBearLine = o.imBearLine; imOs = o.imOs; imOsPrev = o.imOsPrev;
      imBullLvl = o.imBullLvl; imBearLvl = o.imBearLvl; imTsReached = o.imTsReached; imTs = o.imTs;
      CopyArr(imTp, o.imTp); CopyArr(imSl, o.imSl); CopyArr(imReached, o.imReached);
      CopyArr(ftShV, o.ftShV); CopyArr(ftSlV, o.ftSlV); CopyArr(ftShB, o.ftShB); CopyArr(ftSlB, o.ftSlB);
      CopyArr(ftSupBos, o.ftSupBos); CopyArr(ftDemBos, o.ftDemBos);
      CopyArr(ftSupBox, o.ftSupBox); CopyArr(ftDemBox, o.ftDemBox); CopyArr(ftSupPoi, o.ftSupPoi); CopyArr(ftDemPoi, o.ftDemPoi);
      zzDirUp = o.zzDirUp; zzLastLow = o.zzLastLow; zzLastHigh = o.zzLastHigh; zzTimeLow = o.zzTimeLow; zzTimeHigh = o.zzTimeHigh; zzLi = o.zzLi; zzInit = o.zzInit;
      tjHasPrev = o.tjHasPrev; tjPrevBull = o.tjPrevBull; tjPrevH = o.tjPrevH; tjPrevL = o.tjPrevL; tjPrevBar = o.tjPrevBar;
      tjShCur = o.tjShCur; tjSlCur = o.tjSlCur; tjTrend = o.tjTrend; tjShP = o.tjShP; tjSlP = o.tjSlP; tjShBar = o.tjShBar; tjSlBar = o.tjSlBar;
      tjBosLine = o.tjBosLine; tjBosPrev = o.tjBosPrev; tjBosBar = o.tjBosBar; tjBosPrevBar = o.tjBosPrevBar;
      tjExtSh = o.tjExtSh; tjExtSl = o.tjExtSl; tjPbSh = o.tjPbSh; tjPbSl = o.tjPbSl; tjCdSh = o.tjCdSh; tjCdSl = o.tjCdSl;
     }

   //--- TradingView efface le plus ancien objet au-delà de 500 par type, ici pour chaque partie
   int LineNew(int part, double x1, double y1, double x2, double y2, uint clr, int style, int width)
     {
      DLine l; l.x1 = x1; l.y1 = y1; l.x2 = x2; l.y2 = y2; l.clr = clr; l.style = style; l.width = width; l.part = part; l.alive = true;
      Push(lines, l); liveL[part]++;
      while(liveL[part] > MAX_OBJ && oldL[part] < ArraySize(lines))
        { if(lines[oldL[part]].alive && lines[oldL[part]].part == part) { lines[oldL[part]].alive = false; liveL[part]--; } oldL[part]++; }
      return ArraySize(lines) - 1;
     }
   int BoxNew(int part, double x1, double top_, double x2, double bot_, uint bg, uint bd, bool ext, string text, uint tc, int tsize, bool tleft)
     {
      DBox b; b.x1 = x1; b.top = top_; b.x2 = x2; b.bot = bot_; b.bg = bg; b.bd = bd; b.ext = ext; b.text = text; b.tc = tc;
      b.tsize = tsize; b.tleft = tleft; b.part = part; b.alive = true;
      Push(boxes, b); liveB[part]++;
      while(liveB[part] > MAX_OBJ && oldB[part] < ArraySize(boxes))
        { if(boxes[oldB[part]].alive && boxes[oldB[part]].part == part) { boxes[oldB[part]].alive = false; liveB[part]--; } oldB[part]++; }
      return ArraySize(boxes) - 1;
     }
   int LabelNew(int part, double x, double y, string text, uint tc, int style, int size)
     {
      DLabel t; t.x = x; t.y = y; t.text = text; t.tc = tc; t.style = style; t.size = size; t.part = part; t.alive = true;
      Push(labels, t); liveT[part]++;
      while(liveT[part] > MAX_OBJ && oldT[part] < ArraySize(labels))
        { if(labels[oldT[part]].alive && labels[oldT[part]].part == part) { labels[oldT[part]].alive = false; liveT[part]--; } oldT[part]++; }
      return ArraySize(labels) - 1;
     }
   bool LOk(int id) { return id >= 0 && id < ArraySize(lines) && lines[id].alive; }
   bool BOk(int id) { return id >= 0 && id < ArraySize(boxes) && boxes[id].alive; }
   bool TOk(int id) { return id >= 0 && id < ArraySize(labels) && labels[id].alive; }
   void LineDel(int id)  { if(LOk(id)) { lines[id].alive = false; liveL[lines[id].part]--; } }
   void BoxDel(int id)   { if(BOk(id)) { boxes[id].alive = false; liveB[boxes[id].part]--; } }
   void LabelDel(int id) { if(TOk(id)) { labels[id].alive = false; liveT[labels[id].part]--; } }
   //--- box.copy : nouvel objet avec les mêmes propriétés
   int BoxCopy(int id)
     {
      if(!BOk(id)) return NAI;
      DBox b = boxes[id];
      return BoxNew(b.part, b.x1, b.top, b.x2, b.bot, b.bg, b.bd, b.ext, b.text, b.tc, b.tsize, b.tleft);
     }
   //--- box.get_top / get_bottom / get_left : na pour un objet absent ou effacé
   double BTop(int id)  { return BOk(id) ? boxes[id].top : NA; }
   double BBot(int id)  { return BOk(id) ? boxes[id].bot : NA; }
   double BLeft(int id) { return BOk(id) ? boxes[id].x1 : NA; }
  };

//--- Données du graphique (fenêtre de InpMaxBars bougies, indice 0 = la plus ancienne)
double   gO[], gH[], gL[], gC[], gAtr[], gAtr200[];
double   gImTs[];
int      gImBar[], gImTsClr[];
//--- tampons MT5 : bougies recolorées (barcolor) et trailing stop (plot) de l'IMFVG
double   bO[], bH[], bL[], bC[], bClr[], bTs[], bTsClr[];
datetime gT[];
int      gN = 0, gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
CState   gCommit, gWork;
double   gDpi = 1.0;

//--- Canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0, gLastWork = 0, gLastCd = 0;
bool     gDirty = false;

int OnInit()
  {
   if(LsLeft < 1 || LsRight < 1 || FtSwing < 1 || FtHistory < 1 || FtBoxWidth <= 0 || InpMaxBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXST_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Liquidity · SMC Lite · TJR · IMFVG");
   SetIndexBuffer(0, bO, INDICATOR_DATA); SetIndexBuffer(1, bH, INDICATOR_DATA);
   SetIndexBuffer(2, bL, INDICATOR_DATA); SetIndexBuffer(3, bC, INDICATOR_DATA);
   SetIndexBuffer(4, bClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5, bTs, INDICATOR_DATA); SetIndexBuffer(6, bTsClr, INDICATOR_COLOR_INDEX);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, ImBullCss); PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, ImBearCss);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, ImBullCss); PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, ImBearCss);
   PlotIndexSetInteger(0, PLOT_SHOW_DATA, false);
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

//--- ta.atr de Pine (RMA amorcée par une moyenne simple), de la bougie from à la fin
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

//+------------------------------------------------------------------+
//| 1. Liquidity Swings & Sweeps (© OutofOptions, MPL 2.0)           |
//+------------------------------------------------------------------+
//--- heure de New York (changement d'heure compris) d'une heure du serveur, pour TF() de Pine
datetime NthSunday(int year, int mon, int nth)      // nth = 0 : dernier dimanche du mois
  {
   MqlDateTime d; d.year = year; d.mon = mon; d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
   datetime first = StructToTime(d);
   MqlDateTime f; TimeToStruct(first, f);
   int sun = (7 - f.day_of_week) % 7;
   if(nth > 0) return first + (sun + 7 * (nth - 1)) * 86400;
   datetime t = first + sun * 86400;
   MqlDateTime n;
   while(true) { TimeToStruct(t + 7 * 86400, n); if(n.mon != mon) break; t += 7 * 86400; }
   return t;
  }
string LsTF(int idx)
  {
   if(idx < 0 || idx >= gN) return "";
   int offset = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 1800.0) * 1800;
   datetime utc = gT[idx] - offset;
   MqlDateTime u; TimeToStruct(utc, u);
   bool dst = utc >= NthSunday(u.year, 3, 2) + 7 * 3600 && utc < NthSunday(u.year, 11, 1) + 6 * 3600;
   return TimeToString(utc + (dst ? -4 : -5) * 3600, TIME_SECONDS);
  }

//--- ta.pivothigh(high, gauche, droite) : à égalité, c'est la plus à gauche
bool PivotHighLR(int t, int left, int right)
  {
   int c = t - right;
   if(c - left < 0) return false;
   for(int i = 1; i <= left; i++)  if(gH[c - i] >= gH[c]) return false;
   for(int i = 1; i <= right; i++) if(gH[c + i] > gH[c]) return false;
   return true;
  }
bool PivotLowLR(int t, int left, int right)
  {
   int c = t - right;
   if(c - left < 0) return false;
   for(int i = 1; i <= left; i++)  if(gL[c - i] <= gL[c]) return false;
   for(int i = 1; i <= right; i++) if(gL[c + i] < gL[c]) return false;
   return true;
  }

//--- liquidity.new : objet du réservoir (les objets Pine sont des références)
int LsNew(CState &S, double price, int time)
  {
   SLiq q; q.price = price; q.time = time; q.broken = false; q.drawLine = NAI; q.breakLine = NAI; q.breakLabel = NAI;
   q.brokenTime = NAI; q.current = false;
   Push(S.lsPool, q);
   return ArraySize(S.lsPool) - 1;
  }

//--- CD : efface les dessins d'un swing
void LsCD(CState &S, int q)
  {
   S.LineDel(S.lsPool[q].drawLine);
   S.LineDel(S.lsPool[q].breakLine);
   S.LabelDel(S.lsPool[q].breakLabel);
  }

//--- findSubSwing : plus haut / plus bas mineur (pivots 1/1) balayé avant le swing
void LsFindSubSwing(CState &S, SHiLo &list[], bool bullish, int swing, int lb, int maxTime)
  {
   int b = ArraySize(list) - 1;
   while(b > 0)
     {
      SHiLo c = list[b];
      b -= 1;
      if(S.lsPool[lb].time >= 0 && c.time > S.lsPool[lb].time)
        { RemoveAt(list, b + 1); continue; }
      if(c.time >= S.lsPool[swing].time)
         continue;
      if(maxTime > c.time || (bullish ? c.price >= S.lsPool[swing].price : c.price <= S.lsPool[swing].price))
         break;
      if(S.lsPool[lb].price == NA || (bullish ? c.price >= S.lsPool[lb].price : c.price <= S.lsPool[lb].price))
        {
         RemoveAt(list, b + 1);
         S.lsPool[lb].time = c.time;
         S.lsPool[lb].price = c.price;
         S.lsPool[lb].brokenTime = S.lsPool[swing].time;
        }
     }
  }

//--- render : ligne de liquidité en cours, balayage pointillé et note du sweep
void LsRender(CState &S, int &arr[], bool bullish, int t)
  {
   int  n = ArraySize(arr) - 1;
   uint clr = bullish ? A(LsUpCol, LsUpT) : A(LsDnCol, LsDnT);
   while(n > 0)
     {
      int  swing = arr[n];
      bool validSwing = bullish ? (S.lsPool[swing].price >= gH[t]) : (S.lsPool[swing].price <= gL[t]);
      if(!validSwing)
        {
         if(!S.lsPool[swing].broken)
           {
            S.lsPool[swing].broken = true;
            S.lsPool[swing].brokenTime = t;
            if(S.lsPool[swing].current) LsCD(S, swing);
           }
         n -= 1;
         continue;
        }
      if(!S.lsPool[swing].current)
        {
         S.lsPool[swing].current = true;
         S.lsPool[swing].drawLine = S.LineNew(P_LS, S.lsPool[swing].time, S.lsPool[swing].price, t, S.lsPool[swing].price, clr, sol, LsWidth);
         int prev = NAI, lb = NAI;
         while(n > 0)
           {
            n -= 1;
            prev = arr[n];
            if(bullish ? (S.lsPool[prev].price > S.lsPool[swing].price) : (S.lsPool[swing].price > S.lsPool[prev].price))
               break;
            if(lb == NAI) lb = prev;
            else if(bullish ? (S.lsPool[prev].price >= S.lsPool[lb].price) : (S.lsPool[prev].price <= S.lsPool[lb].price))
               lb = prev;
            if(S.lsPool[lb].current)
              {
               LsCD(S, lb);
               if(S.lsPool[swing].time >= S.lsPool[lb].time) RemoveAt(arr, n);
              }
           }
         if(LsMax)
           {
            if(lb == NAI) lb = LsNew(S, NA, NAI);
            int maxTime = prev == NAI ? NAI : S.lsPool[prev].time;
            if(bullish) LsFindSubSwing(S, S.lsHLA, bullish, swing, lb, maxTime);
            else        LsFindSubSwing(S, S.lsLLA, bullish, swing, lb, maxTime);
           }
         if(lb != NAI && S.lsPool[lb].price != NA && S.lsPool[lb].price != S.lsPool[swing].price)
           {
            int bt = S.lsPool[lb].brokenTime >= 0 ? S.lsPool[lb].brokenTime : S.lsPool[swing].time;
            S.lsPool[swing].breakLine = S.LineNew(P_LS, S.lsPool[lb].time, S.lsPool[lb].price, bt, S.lsPool[lb].price, clr, dsh, LsWidth);
            if(LsLabel && S.lsPool[lb].time >= 0)
              {
               bool   doAlert = false;
               double timeD = MathRound((double)(gT[bt] - gT[S.lsPool[lb].time]) / 60.0 * 100.0) / 100.0;   // minutes
               int    hours = 0;
               double pd = bullish ? S.lsPool[swing].price - S.lsPool[lb].price : S.lsPool[lb].price - S.lsPool[swing].price;
               string rating = "❄️";
               if(timeD >= 60)      { hours = (int)MathFloor(timeD / 60); timeD -= hours * 60; rating = "💥"; doAlert = LsAlD; }
               else if(timeD >= 15) { rating = "🔥"; doAlert = LsAlC; }
               else if(timeD >= 5)  { rating = pd >= 10 ? "🔥" : "✅"; doAlert = LsAlB; }
               else if(pd >= 10)    { rating = "✅"; doAlert = LsAlB; }
               else                 doAlert = LsAlA;
               string tip = DoubleToString(S.lsPool[lb].price, _Digits) + " @ " + LsTF(S.lsPool[lb].time) + " swept @ " + LsTF(bt)
                            + " in " + (hours > 0 ? IntegerToString(hours) + "h" : "") + DoubleToString(timeD, timeD == MathRound(timeD) ? 0 : 2) + "m";
               if(doAlert && t - bt < 5)
                  Ev(true, LsAlMsg + rating + " " + tip);
               double dbars = (double)(gT[bt] - gT[S.lsPool[lb].time]) / gPer;
               int xpos = dbars > 30 ? bt - 10 : (int)MathRound((S.lsPool[lb].time + bt) / 2.0);
               //--- sur le graphique, symboles monochromes que MT5 affiche bien (l'alerte garde les emojis) :
               //    ❄️ faible → ❄ · ✅ correct → ✔ · 🔥 fort → ★ · 💥 très fort → ✹
               string mark = rating == "💥" ? "✹" : rating == "🔥" ? "★" : rating == "✅" ? "✔" : "❄";
               S.lsPool[swing].breakLabel = S.LabelNew(P_LS, xpos, S.lsPool[lb].price, mark, clr, LS_CENTER, small);
              }
           }
        }
      else if(S.LOk(S.lsPool[swing].drawLine))
         S.lines[S.lsPool[swing].drawLine].x2 = t;
      break;
     }
  }

void LssBar(CState &S, int t, bool doRender)
  {
   if(LsMax)
     {
      if(PivotHighLR(t, 1, 1)) { SHiLo h; h.price = gH[t - 1]; h.time = t - 1; Push(S.lsHLA, h); }
      if(PivotLowLR(t, 1, 1))  { SHiLo l; l.price = gL[t - 1]; l.time = t - 1; Push(S.lsLLA, l); }
     }
   if(PivotHighLR(t, LsLeft, LsRight)) { int q = LsNew(S, gH[t - LsRight], t - LsRight); Push(S.lsBear, q); }
   if(PivotLowLR(t, LsLeft, LsRight))  { int q = LsNew(S, gL[t - LsRight], t - LsRight); Push(S.lsBull, q); }
   if(doRender)                                  // barstate.islast
     {
      LsRender(S, S.lsBear, true, t);
      LsRender(S, S.lsBull, false, t);
     }
  }

//+------------------------------------------------------------------+
//| 4. FVG Instantaneous Mitigation Signals [LuxAlgo]                |
//+------------------------------------------------------------------+
//--- tpsl : zones TP / SL (désactivées par défaut) et état « atteint »
bool ImTpsl(CState &S, int k, bool cond, bool opp, double level, bool isLong, double atr, int t)
  {
   if(cond)
     {
      if(isLong)
        {
         if(ImShowTp) S.imTp[k] = S.BoxNew(P_IM, t, level + atr * ImTpMult, t, level, A(ImTpCss, ImTpT), 0, false, "", 0, small, false);
         if(ImShowSl) S.imSl[k] = S.BoxNew(P_IM, t, level, t, level - atr * ImSlMult, A(ImSlCss, ImSlT), 0, false, "", 0, small, false);
        }
      else
        {
         if(ImShowTp) S.imTp[k] = S.BoxNew(P_IM, t, level, t, level - atr * ImTpMult, A(ImTpCss, ImTpT), 0, false, "", 0, small, false);
         if(ImShowSl) S.imSl[k] = S.BoxNew(P_IM, t, level + atr * ImSlMult, t, level, A(ImSlCss, ImSlT), 0, false, "", 0, small, false);
        }
      S.imReached[k] = false;
     }
   else if(opp)
      S.imReached[k] = true;
   if(!S.imReached[k])
     {
      if(S.BOk(S.imTp[k])) S.boxes[S.imTp[k]].x2 = t;
      if(S.BOk(S.imSl[k])) S.boxes[S.imSl[k]].x2 = t;
      double tpT = S.BTop(S.imTp[k]), tpB = S.BBot(S.imTp[k]), slT = S.BTop(S.imSl[k]), slB = S.BBot(S.imSl[k]);
      if(isLong)
        { if((tpT != NA && gH[t] > tpT) || (slB != NA && gL[t] < slB)) S.imReached[k] = true; }
      else
        { if((tpB != NA && gL[t] < tpB) || (slT != NA && gH[t] > slT)) S.imReached[k] = true; }
     }
   return S.imReached[k];
  }

void ImfvgBar(CState &S, int t)
  {
   gImBar[t] = -1; gImTs[t] = NA; gImTsClr[t] = -1;
   if(t < 3) return;
   double atr = gAtr200[t] == NA ? 0.0 : gAtr200[t];        // nz(ta.atr(200))
   uint bullC = A(ImBullCss, 0), bearC = A(ImBearCss, 0);
   bool bull = gL[t - 3] > gH[t - 1] && gC[t - 2] < gL[t - 3] && gC[t] > gL[t - 3] && gL[t - 3] - gH[t - 1] > atr * ImFilter && ImShowBull;
   if(bull)
     {
      S.BoxNew(P_IM, t - 3, gL[t - 3], t, gH[t - 1], A(ImBullCss, 50), 0, false, "", 0, small, false);
      double avg = (gL[t - 3] + gH[t - 1]) / 2;
      if(ImBullAvg) S.imBullLine = S.LineNew(P_IM, t, avg, t, avg, bullC, dsh, 1);
      S.LabelNew(P_IM, t, gL[t], "▲", bullC, LS_UP, small);
      S.imOs = 1;
      S.imBullLvl = false;
     }
   bool bear = gL[t - 1] > gH[t - 3] && gC[t - 2] > gH[t - 3] && gC[t] < gH[t - 3] && gL[t - 1] - gH[t - 3] > atr * ImFilter && ImShowBear;
   if(bear)
     {
      S.BoxNew(P_IM, t - 3, gL[t - 1], t, gH[t - 3], A(ImBearCss, 50), 0, false, "", 0, small, false);
      double avg = (gL[t - 1] + gH[t - 3]) / 2;
      if(ImBearAvg) S.imBearLine = S.LineNew(P_IM, t, avg, t, avg, bearC, dsh, 1);
      S.LabelNew(P_IM, t, gH[t], "▼", bearC, LS_DOWN, small);
      S.imOs = 0;
      S.imBearLvl = false;
     }
   if(!S.imBullLvl && S.LOk(S.imBullLine)) S.lines[S.imBullLine].x2 = t;
   if(!S.imBearLvl && S.LOk(S.imBearLine)) S.lines[S.imBearLine].x2 = t;
   if(S.LOk(S.imBullLine) && gC[t] < S.lines[S.imBullLine].y2) S.imBullLvl = true;
   if(S.LOk(S.imBearLine) && gC[t] > S.lines[S.imBearLine].y2) S.imBearLvl = true;

   bool bullReached = ImTpsl(S, 0, bull, bear, (gL[t - 3] + gH[t - 1]) / 2, true, atr, t);
   bool bearReached = ImTpsl(S, 1, bear, bull, (gL[t - 1] + gH[t - 3]) / 2, false, atr, t);

   //--- trailing stop
   bool reset = ImTsReset == EverySignals ? (bull || bear) : S.imOs != S.imOsPrev;
   if(reset)
     {
      S.imTs = S.imOs == 1 ? gC[t] - atr * ImTsMult : gC[t] + atr * ImTsMult;
      S.imTsReached = false;
     }
   else
     {
      if(S.imTs != NA)
        {
         if(S.imOs == 1) S.imTs = gC[t] - S.imTs > atr * ImTsMult ? gC[t] - atr * ImTsMult : S.imTs;
         else            S.imTs = S.imTs - gC[t] > atr * ImTsMult ? gC[t] + atr * ImTsMult : S.imTs;
         if(gC[t] < S.imTs && S.imOs == 1)      S.imTsReached = true;
         else if(gC[t] > S.imTs && S.imOs == 0) S.imTsReached = true;
        }
     }
   S.imOsPrev = S.imOs;
   //--- barcolor et plot du trailing stop
   gImBar[t] = S.imTsReached ? -1 : (S.imOs == 1 && !bullReached) ? 0 : (S.imOs == 0 && !bearReached) ? 1 : -1;
   gImTs[t]    = S.imTs;
   gImTsClr[t] = (S.imTsReached || bull || bear) ? -1 : (S.imOs == 1 ? 0 : 1);
  }

//+------------------------------------------------------------------+
//| 2. FluidTrades - SMC Lite                                        |
//+------------------------------------------------------------------+
//--- f_sh_sl_labels : HH / LH au-dessus du swing haut, HL / LL sous le swing bas
void FtLabels(CState &S, const double &arr[], int swingType, int t)
  {
   string txt;
   if(swingType == 1)
     {
      txt = arr[0] >= arr[1] ? "HH" : "LH";
      S.LabelNew(P_FT, t - FtSwing, arr[0], txt, A(FtSwingType, 0), LS_DOWN, tiny);
     }
   else
     {
      txt = arr[0] >= arr[1] ? "HL" : "LL";
      S.LabelNew(P_FT, t - FtSwing, arr[0], txt, A(FtSwingType, 0), LS_UP, tiny);
     }
  }

//--- f_check_overlapping : pas de nouvelle zone à moins de 2 ATR du POI d'une zone existante
bool FtCheckOverlap(CState &S, double newPoi, const int &boxArr[], double atr)
  {
   if(newPoi == NA || atr == NA) return true;
   double thr = atr * 2;
   for(int i = 0; i < ArraySize(boxArr); i++)
     {
      double top = S.BTop(boxArr[i]), bot = S.BBot(boxArr[i]);
      if(top == NA || bot == NA) continue;
      double poi = (top + bot) / 2;
      if(newPoi >= poi - thr && newPoi <= poi + thr) return false;
     }
   return true;
  }

//--- f_supply_demand : zone d'offre (1) ou de demande (-1) et son POI
void FtSupplyDemand(CState &S, const double &vals[], const int &bns[], int &boxArr[], int &poiArr[], int boxType, double atr, int t)
  {
   double buf = atr == NA ? NA : atr * (FtBoxWidth / 10.0);
   int    left = bns[0];
   double top, bot;
   if(boxType == 1) { top = vals[0]; bot = buf == NA ? NA : top - buf; }
   else             { bot = vals[0]; top = buf == NA ? NA : bot + buf; }
   double poi = (top == NA || bot == NA) ? NA : (top + bot) / 2;
   if(!FtCheckOverlap(S, poi, boxArr, atr)) return;
   int last = ArraySize(boxArr) - 1;
   uint poiC = A(FtPoiLabel, 90);
   if(boxType == 1)
     {
      S.BoxDel(boxArr[last]);
      AddPopI(boxArr, S.BoxNew(P_FT, left, top, t, bot, A(FtSupply, FtSupplyT), A(FtSupplyOut, FtSupplyOutT), true, FtTexts ? "SUPPLY" : "", A(FtPoiLabel, 0), small, false));
      S.BoxDel(poiArr[last]);
      AddPopI(poiArr, S.BoxNew(P_FT, left, poi, t, poi, poiC, poiC, true, FtTexts ? "POI" : "", A(FtPoiLabel, 0), small, true));
     }
   else
     {
      S.BoxDel(boxArr[last]);
      AddPopI(boxArr, S.BoxNew(P_FT, left, top, t, bot, A(FtDemand, FtDemandT), A(FtDemandOut, FtDemandOutT), true, FtTexts ? "DEMAND" : "", A(FtPoiLabel, 0), small, false));
      S.BoxDel(poiArr[last]);
      AddPopI(poiArr, S.BoxNew(P_FT, left, poi, t, poi, poiC, poiC, true, FtTexts ? "POI" : "", A(FtPoiLabel, 0), small, true));
     }
  }

//--- f_sd_to_bos : zone cassée par une clôture → trait « BOS » au milieu de la zone
void FtSdToBos(CState &S, int &boxArr[], int &bosArr[], int &poiArr[], int zoneType, int t)
  {
   for(int i = 0; i < ArraySize(boxArr); i++)
     {
      int id = boxArr[i];
      if(!S.BOk(id)) continue;                         // get_top d'une zone effacée : na
      double level = zoneType == 1 ? S.boxes[id].top : S.boxes[id].bot;
      if(level == NA) continue;
      if(zoneType == 1 ? gC[t] >= level : gC[t] <= level)
        {
         int cp = S.BoxCopy(id);
         AddPopI(bosArr, cp);                          // le BOS sorti du tableau reste dessiné, comme dans Pine
         double mid = (S.boxes[id].top + S.boxes[id].bot) / 2;
         if(S.BOk(cp))
           {
            S.boxes[cp].top = mid; S.boxes[cp].bot = mid; S.boxes[cp].ext = false; S.boxes[cp].x2 = t;
            S.boxes[cp].text = FtTexts ? "BOS" : ""; S.boxes[cp].tc = A(FtBosLabel, 0); S.boxes[cp].tsize = small; S.boxes[cp].tleft = false;
           }
         S.BoxDel(boxArr[i]);
         S.BoxDel(poiArr[i]);
        }
     }
  }

//--- zig-zag (f_isMin / f_isMax sur une fenêtre de 2 × longueur + 1)
void FtDrawZz(CState &S)
  {
   uint c = FtZigzag ? A(FtZzColor, 0) : 0;
   S.zzLi = S.LineNew(P_FT, S.zzTimeHigh - FtSwing, S.zzLastHigh, S.zzTimeLow - FtSwing, S.zzLastLow, c, sol, 2);
  }

void FluidBar(CState &S, int t)
  {
   double atr = gAtr[t];
   int len = FtSwing;
   if(PivotHigh(t, len))
     {
      AddPopD(S.ftShV, gH[t - len]);
      AddPopI(S.ftShB, t - len);
      if(FtPaLabels) FtLabels(S, S.ftShV, 1, t);
      FtSupplyDemand(S, S.ftShV, S.ftShB, S.ftSupBox, S.ftSupPoi, 1, atr, t);
     }
   else if(PivotLow(t, len))
     {
      AddPopD(S.ftSlV, gL[t - len]);
      AddPopI(S.ftSlB, t - len);
      if(FtPaLabels) FtLabels(S, S.ftSlV, -1, t);
      FtSupplyDemand(S, S.ftSlV, S.ftSlB, S.ftDemBox, S.ftDemPoi, -1, atr, t);
     }
   FtSdToBos(S, S.ftSupBox, S.ftSupBos, S.ftSupPoi, 1, t);
   FtSdToBos(S, S.ftDemBox, S.ftDemBos, S.ftDemPoi, -1, t);
   for(int i = 0; i < ArraySize(S.ftSupBox); i++) if(S.BOk(S.ftSupBox[i])) S.boxes[S.ftSupBox[i]].x2 = t + 100;
   for(int i = 0; i < ArraySize(S.ftDemBox); i++) if(S.BOk(S.ftDemBox[i])) S.boxes[S.ftDemBox[i]].x2 = t + 100;

   //--- zig-zag
   if(!S.zzInit) { S.zzInit = true; S.zzLastLow = gH[t] * 100; S.zzLastHigh = 0.0; S.zzTimeLow = t; S.zzTimeHigh = t; }
   bool ok = t >= 2 * len;
   double hh = gH[t], ll = gL[t];
   if(ok) for(int i = t - 2 * len; i < t; i++) { hh = MathMax(hh, gH[i]); ll = MathMin(ll, gL[i]); }
   bool isMin = ok && ll == gL[t - len];
   bool isMax = ok && hh == gH[t - len];
   if(S.zzDirUp)
     {
      if(isMin && gL[t - len] < S.zzLastLow)
        { S.zzLastLow = gL[t - len]; S.zzTimeLow = t; S.LineDel(S.zzLi); FtDrawZz(S); }
      if(isMax && gH[t - len] > S.zzLastLow)
        { S.zzLastHigh = gH[t - len]; S.zzTimeHigh = t; S.zzDirUp = false; FtDrawZz(S); }
     }
   if(!S.zzDirUp)
     {
      if(isMax && gH[t - len] > S.zzLastHigh)
        { S.zzLastHigh = gH[t - len]; S.zzTimeHigh = t; S.LineDel(S.zzLi); FtDrawZz(S); }
      if(isMin && gL[t - len] < S.zzLastHigh)
        {
         S.zzLastLow = gL[t - len]; S.zzTimeLow = t; S.zzDirUp = true; FtDrawZz(S);
         if(isMax && gH[t - len] > S.zzLastLow)
           { S.zzLastHigh = gH[t - len]; S.zzTimeHigh = t; S.zzDirUp = false; FtDrawZz(S); }
        }
     }
  }

//+------------------------------------------------------------------+
//| 3. TJR Swing High/Low + BOS                                      |
//+------------------------------------------------------------------+
//--- f_track_line : ligne vivante sur le niveau surveillé (mise à jour sur place)
int TjTrack(CState &S, bool active, int originBar, double lvl, int ext, uint c, int style, int width, int existing, int t)
  {
   if(!active) { S.LineDel(existing); return NAI; }
   if(S.LOk(existing))
     {
      S.lines[existing].x1 = originBar; S.lines[existing].y1 = lvl; S.lines[existing].x2 = t + ext; S.lines[existing].y2 = lvl;
      S.lines[existing].clr = c; S.lines[existing].style = style; S.lines[existing].width = width;
      return existing;
     }
   return S.LineNew(P_TJ, originBar, lvl, t + ext, lvl, c, style, width);
  }

void TjNewBos(CState &S, int fromBar, double lvl, int t)
  {
   S.LineDel(S.tjBosPrev);
   S.tjBosPrev    = S.tjBosLine;
   S.tjBosPrevBar = S.tjBosBar;
   S.tjBosLine = S.LineNew(P_TJ, fromBar, lvl, t + (int)TjBosExt, lvl, A(TjBosCol, 100 - TjBosOp), (int)TjBosStyle, TjBosWidth);
   S.tjBosBar  = t;
   if(S.LOk(S.tjBosPrev))
     {
      S.lines[S.tjBosPrev].clr = A(TjBos1Col, 100 - TjBos1Op);
      S.lines[S.tjBosPrev].style = (int)TjBos1Style;
      S.lines[S.tjBosPrev].width = TjBos1Width;
      S.lines[S.tjBosPrev].x2 = S.tjBosPrevBar + (int)TjBos1Ext;
     }
  }

void TjrBar(CState &S, int t, bool confirmed)
  {
   bool isDoji = gC[t] == gO[t];
   bool isBull = gC[t] > gO[t];
   if(confirmed && !isDoji)
     {
      bool bullBos = false, bearBos = false;
      if(S.tjTrend == 0)
        {
         if(S.tjShP != NA && gC[t] > S.tjShP) bullBos = true;
         else if(S.tjSlP != NA && gC[t] < S.tjSlP) bearBos = true;
        }
      else if(S.tjTrend == 1)
        { if(S.tjSlP != NA && gC[t] < S.tjSlP) bearBos = true; }
      else if(S.tjTrend == -1)
        { if(S.tjShP != NA && gC[t] > S.tjShP) bullBos = true; }
      if(bullBos)
        {
         S.tjTrend = 1;
         if(TjShowBos) TjNewBos(S, S.tjShBar, S.tjShP, t);
        }
      else if(bearBos)
        {
         S.tjTrend = -1;
         if(TjShowBos) TjNewBos(S, S.tjSlBar, S.tjSlP, t);
        }
      if(S.tjHasPrev)
        {
         if(S.tjPrevBull && !isBull)
           {
            double level = MathMax(S.tjPrevH, gH[t]);
            int extIdx = S.tjPrevH >= gH[t] ? S.tjPrevBar : t;
            S.tjShP = level; S.tjShBar = extIdx;
            if(TjShowSwings)
              {
               S.LineDel(S.tjShCur);
               S.tjShCur = S.LineNew(P_TJ, extIdx, level, extIdx + 1, level, A(TjShCol, 100 - TjShOp), (int)TjShStyle, TjShWidth);
              }
           }
         else if(!S.tjPrevBull && isBull)
           {
            double level = MathMin(S.tjPrevL, gL[t]);
            int extIdx = S.tjPrevL <= gL[t] ? S.tjPrevBar : t;
            S.tjSlP = level; S.tjSlBar = extIdx;
            if(TjShowSwings)
              {
               S.LineDel(S.tjSlCur);
               S.tjSlCur = S.LineNew(P_TJ, extIdx, level, extIdx + 1, level, A(TjSlCol, 100 - TjSlOp), (int)TjSlStyle, TjSlWidth);
              }
           }
        }
      S.tjHasPrev = true; S.tjPrevBull = isBull; S.tjPrevH = gH[t]; S.tjPrevL = gL[t]; S.tjPrevBar = t;
     }

   //--- extension + ligne de déclenchement (bougie en cours comprise)
   bool watchedSh   = S.tjTrend != 1 && S.tjShP != NA;
   bool watchedSl   = S.tjTrend != -1 && S.tjSlP != NA;
   bool triggeredSh = watchedSh && gC[t] > S.tjShP;
   bool triggeredSl = watchedSl && gC[t] < S.tjSlP;
   int  ext = (int)TjExtExt;
   if(TjShowExt)
     {
      S.tjExtSh = TjTrack(S, watchedSh, S.tjShBar, S.tjShP, ext, A(TjExtCol, 100 - TjExtOp), (int)TjExtStyle, TjExtWidth, S.tjExtSh, t);
      S.tjExtSl = TjTrack(S, watchedSl, S.tjSlBar, S.tjSlP, ext, A(TjExtCol, 100 - TjExtOp), (int)TjExtStyle, TjExtWidth, S.tjExtSl, t);
      S.tjPbSh  = TjTrack(S, triggeredSh, S.tjShBar, S.tjShP, ext, A(TjPbCol, 100 - TjPbOp), (int)TjPbStyle, TjPbWidth, S.tjPbSh, t);
      S.tjPbSl  = TjTrack(S, triggeredSl, S.tjSlBar, S.tjSlP, ext, A(TjPbCol, 100 - TjPbOp), (int)TjPbStyle, TjPbWidth, S.tjPbSl, t);
      //--- compte à rebours au bout de chaque ligne surveillée : dernière bougie seulement, unités ≤ 1 h
      if(t == gN - 1)
        {
         bool tfOk = gPer <= 3600;
         S.LabelDel(S.tjCdSh); S.tjCdSh = NAI;
         if(watchedSh && tfOk) S.tjCdSh = S.LabelNew(P_TJ, t + ext, S.tjShP, CD_MARK, A(TjCdCol, 0), LS_LEFT, small);
         S.LabelDel(S.tjCdSl); S.tjCdSl = NAI;
         if(watchedSl && tfOk) S.tjCdSl = S.LabelNew(P_TJ, t + ext, S.tjSlP, CD_MARK, A(TjCdCol, 0), LS_LEFT, small);
        }
     }
   else
     {
      S.LineDel(S.tjExtSh); S.tjExtSh = NAI; S.LineDel(S.tjExtSl); S.tjExtSl = NAI;
      S.LabelDel(S.tjCdSh); S.tjCdSh = NAI; S.LabelDel(S.tjCdSl); S.tjCdSl = NAI;
      S.LineDel(S.tjPbSh); S.tjPbSh = NAI; S.LineDel(S.tjPbSl); S.tjPbSl = NAI;
     }
  }

//+------------------------------------------------------------------+
//| Une exécution des quatre scripts sur la bougie t                 |
//+------------------------------------------------------------------+
//    isLast : barstate.islast (Liquidity Swings & Sweeps ne dessine que sur la dernière bougie)
void ProcessBar(CState &S, int t, bool confirmed, bool isLast)
  {
   if(LsOn) LssBar(S, t, isLast);
   TjrBar(S, t, confirmed);
   if(FtOn) FluidBar(S, t);
   if(ImOn) ImfvgBar(S, t);
   else { gImBar[t] = -1; gImTs[t] = NA; gImTsClr[t] = -1; }
  }

void SendAlert(string msg, datetime bar)
  {
   string tf = gPer < 3600 ? "M" + IntegerToString(gPer / 60) : gPer < 86400 ? "H" + IntegerToString(gPer / 3600)
               : gPer == 86400 ? "D1" : gPer == 604800 ? "W1" : "MN1";
   string txt = _Symbol + " " + tf + " " + TimeToString(bar, TIME_MINUTES) + " · " + msg;
   if(AlPopup) Alert(txt);
   if(AlPush)  SendNotification(StringSubstr(txt, 0, 255));
  }

//--- tampons MT5 de la bougie local i (indice graphique gBase + i)
void FillBuffers(int i)
  {
   int k = gBase + i;
   bool bc = ImOn && ImBarColor && gImBar[i] >= 0;
   bO[k] = bc ? gO[i] : EMPTY_VALUE; bH[k] = bc ? gH[i] : EMPTY_VALUE; bL[k] = bc ? gL[i] : EMPTY_VALUE; bC[k] = bc ? gC[i] : EMPTY_VALUE;
   bClr[k] = bc ? gImBar[i] : 0;
   bool ts = ImOn && ImPlotTs && gImTsClr[i] >= 0 && gImTs[i] != NA;
   bTs[k] = ts ? gImTs[i] : EMPTY_VALUE;
   bTsClr[k] = ts ? gImTsClr[i] : 0;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < 100)
      return 0;
   gPer = PeriodSeconds(PERIOD_CURRENT);
   bool full = prev_calculated == 0 || gProcessed == -1 || rates_total < gTotal || rates_total - gTotal > 1;
   int from = 0;
   if(full)
     {
      gBase = MathMax(0, rates_total - InpMaxBars);
      gN = rates_total - gBase;
     }
   else
     {
      from = gN - 1;
      gN = rates_total - gBase;
     }
   ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gT, gN);
   ArrayResize(gImBar, gN); ArrayResize(gImTs, gN); ArrayResize(gImTsClr, gN);
   for(int i = from; i < gN; i++)
     {
      gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i];
      gT[i] = time[gBase + i];
     }
   Atr(gAtr, 50, from);
   Atr(gAtr200, 200, from);
   gTotal = rates_total;
   if(full)
     {
      gCommit.Reset();
      gProcessed = 0;
      for(int k = 0; k < rates_total; k++)
        { bO[k] = bH[k] = bL[k] = bC[k] = EMPTY_VALUE; bClr[k] = 0; bTs[k] = EMPTY_VALUE; bTsClr[k] = 0; }
     }
   bool newBar = false;
   int  fillFrom = gProcessed;
   while(gProcessed < gN - 1)
     {
      //--- bougie qui clôture en direct : elle était la dernière (barstate.islast) ; historique : non
      gAlertLive = !full && gProcessed >= gN - 3;
      gAlertBuf = "";
      ProcessBar(gCommit, gProcessed, true, !full);
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
      ProcessBar(gWork, gN - 1, false, true);
      gLastWork = now;
      Render(gWork);
      gLastRender = now;
     }
   for(int i = MathMax(0, fillFrom - 1); i < gN; i++)
      FillBuffers(i);
   return rates_total;
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_CHART_CHANGE || gN <= 0 || gProcessed < 0)
      return;
   gDirty = true;
   if(GetTickCount() - gLastRender >= 40)
      Render(gWork);               // sinon la minuterie redessine (défilement rapide)
  }

void OnTimer()
  {
   if(gProcessed < 0) return;
   //--- compte à rebours TJR : redessin chaque seconde
   if((gWork.TOk(gWork.tjCdSh) || gWork.TOk(gWork.tjCdSl)) && GetTickCount() - gLastCd >= 1000)
     {
      gLastCd = GetTickCount();
      gDirty = true;
     }
   if(gDirty)
      Render(gWork);
  }

//--- f_countdown_hms : « 47s », « 04m 47s », « 19h 54m 00s »
string Countdown()
  {
   long closeT = (long)gT[gN - 1] + gPer;
   long total  = MathMax(0, closeT - (long)TimeTradeServer());
   long h = total / 3600, m = (total % 3600) / 60, s = total % 60;
   if(h > 0) return StringFormat("%02dh %02dm %02ds", (int)h, (int)m, (int)s);
   if(m > 0) return StringFormat("%02dm %02ds", (int)m, (int)s);
   return StringFormat("%02ds", (int)s);
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

//--- tailles de texte de TradingView (mesurées sur les captures), en dixièmes de point
void SetFont(int size, bool sym)
  {
   int s = size == tiny ? -45 : size == small ? -60 : -75;
   gCv.FontSet(sym ? "Arial" : InpFont, s);
  }

//--- étiquette sans fond (comme les labels transparents des trois scripts)
//    LS_DOWN : texte au-dessus du point · LS_UP : au-dessous · LS_LEFT : à droite du point
//    LS_CENTER : centré sur le point (label.style_text_outline, note du sweep)
void DrawLabel(const DLabel &lb, string text)
  {
   double ax = XofBar(lb.x);
   if(ax < -300 || ax > gW + 300) return;
   double ay = YofPrice(lb.y);
   if(ay < -100 || ay > gHh + 100) return;
   int tw = 0, th = 0;
   bool sym = text == "▲" || text == "▼";
   SetFont(lb.size, sym);
   if(lb.style == LS_CENTER) gCv.FontSet("Segoe UI Symbol", lb.size == tiny ? -45 : lb.size == small ? -60 : -75);
   gCv.TextSize(text, tw, th);
   int ph = Px(3);
   int ix = (int)MathRound(ax), iy = (int)MathRound(ay);
   if(lb.style == LS_CENTER)
      gCv.TextOut(ix, iy, text, lb.tc, TA_CENTER | TA_VCENTER);
   else if(lb.style == LS_LEFT)
      gCv.TextOut(ix + ph, iy, text, lb.tc, TA_LEFT | TA_VCENTER);
   else if(lb.style == LS_UP)
      gCv.TextOut(ix, iy + ph, text, lb.tc, TA_CENTER | TA_TOP);
   else
      gCv.TextOut(ix, iy - ph, text, lb.tc, TA_CENTER | TA_BOTTOM);
  }

//--- boîte de Pine : fond, bord de 1 px, extension à droite, texte centré ou à gauche.
//    Une boîte de hauteur nulle (POI, BOS) se voit par son bord : un trait horizontal.
void DrawBox(const DBox &b, int lw)
  {
   if(b.x1 == NA || b.x2 == NA || b.top == NA || b.bot == NA) return;
   int x1 = (int)MathRound(XofBar(b.x1));
   int x2 = b.ext ? gW : (int)MathRound(XofBar(b.x2));
   if(x2 < x1) { int s = x1; x1 = x2; x2 = s; }
   if(x2 < 0 || x1 > gW) return;
   int y1 = (int)MathRound(YofPrice(MathMax(b.top, b.bot)));
   int y2 = (int)MathRound(YofPrice(MathMin(b.top, b.bot)));
   if(y2 < -50 || y1 > gHh + 50) return;
   bool border = ((b.bd >> 24) & 0xFF) > 0;
   if(y1 == y2)
     {
      if(border) FillRect(x1, y1, x2, y1 + lw - 1, b.bd);
     }
   else if(border)
     {
      FillRect(x1 + lw, y1 + lw, x2 - lw, y2 - lw, b.bg);
      FillRect(x1, y1, x2, y1 + lw - 1, b.bd);
      FillRect(x1, y2 - lw + 1, x2, y2, b.bd);
      FillRect(x1, y1 + lw, x1 + lw - 1, y2 - lw, b.bd);
      if(!b.ext) FillRect(x2 - lw + 1, y1 + lw, x2, y2 - lw, b.bd);
     }
   else
      FillRect(x1, y1, x2, y2, b.bg);
   if(b.text != "" && ((b.tc >> 24) & 0xFF) > 0)
     {
      SetFont(b.tsize, false);
      int yc = (y1 + y2) / 2;
      if(b.tleft)
         gCv.TextOut((int)MathRound(XofBar(b.x1)) + Px(3), yc, b.text, b.tc, TA_LEFT | TA_VCENTER);
      else
        {
         //--- centré entre les coordonnées de la boîte (l'extension à droite n'en fait pas partie)
         int xa = (int)MathRound(XofBar(b.x1)), xb = (int)MathRound(XofBar(b.x2));
         gCv.TextOut((xa + xb) / 2, yc, b.text, b.tc, TA_CENTER | TA_VCENTER);
        }
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

   //--- boîtes (zones de sweep, offre / demande, POI, BOS)
   for(int i = 0; i < ArraySize(S.boxes); i++)
      if(S.boxes[i].alive) DrawBox(S.boxes[i], lw);
   //--- lignes (niveaux, traits de sweep, zig-zag, swings et BOS TJR)
   for(int i = 0; i < ArraySize(S.lines); i++)
     {
      if(!S.lines[i].alive || ((S.lines[i].clr >> 24) & 0xFF) == 0) continue;
      if(S.lines[i].x1 == NA || S.lines[i].x2 == NA || S.lines[i].y1 == NA || S.lines[i].y2 == NA) continue;
      double x1 = MathRound(XofBar(S.lines[i].x1)), x2 = MathRound(XofBar(S.lines[i].x2));
      double y1 = MathRound(YofPrice(S.lines[i].y1)), y2 = MathRound(YofPrice(S.lines[i].y2));
      if((y1 < -50 && y2 < -50) || (y1 > H + 50 && y2 > H + 50)) continue;
      DrawLine(x1, y1, x2, y2, S.lines[i].style, Wpx(S.lines[i].width), S.lines[i].clr);
     }
   //--- étiquettes (HH / LH / HL / LL, compte à rebours TJR)
   for(int i = 0; i < ArraySize(S.labels); i++)
     {
      if(!S.labels[i].alive) continue;
      DrawLabel(S.labels[i], S.labels[i].text == CD_MARK ? Countdown() : S.labels[i].text);
     }
   gCv.Update(true);
   gLastRender = GetTickCount();
   gDirty = false;
  }
//+------------------------------------------------------------------+
