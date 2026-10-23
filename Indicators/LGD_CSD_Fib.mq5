//+------------------------------------------------------------------+
//| LGD_CSD_Fib.mq5                                                  |
//| Portage MT5 de « Liquidity Grab, CSD & Focused Fibonacci »       |
//| (TradingView, Pine v6, licence MPL 2.0).                         |
//| Même calcul, bougie par bougie ; dessin en CCanvas (ARGB) pour   |
//| retrouver la transparence et les étiquettes de TradingView.      |
//+------------------------------------------------------------------+
#property copyright   "MPL 2.0 — portage de l'indicateur TradingView LGD+CSD+Fib"
#property version     "1.02"
#property description "Liquidity Grab, CSD & Focused Fibonacci (LGD+CSD+Fib), affichage au style TradingView."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

input group "Logic Settings"
input int             pivotLen     = 5;          // Pivot Lookback
input int             maxGrabs     = 1;          // Max Grabs per Level
input int             levelExpiry  = 300;        // Liquidity Level Expiry (Bars)
input int             csdLookback  = 10;         // CSD Max Bars
input int             csdWait      = 4;          // Wait After CSD (Bars)
input int             zoneExpiry   = 50;         // Zone Expiry (Bars) (sans effet, comme dans le Pine)
input int             maxZoneWidth = 20;         // Max Zone Width (Bars)
input bool            oteSetting   = false;      // Optimal Trade Entry (OTE) Only
input bool            useHtfOb     = false;      // Filter by HTF Order Block
input ENUM_TIMEFRAMES htf          = PERIOD_H1;  // HTF Timeframe

input group "Style Settings"
input bool            showFVG      = true;               // Show Imbalances (FVG)
input bool            showBreaker  = true;               // Show Breaker Blocks
input bool            showFib      = true;               // Show Fibonacci on Pullback (sans effet, comme dans le Pine)
input color           bullColor    = C'8,153,129';       // Bullish Color
input color           bearColor    = C'242,54,69';       // Bearish Color
input color           levelColor   = C'120,123,134';     // Level Color

input group "MT5"
input int             InpMaxBars   = 5000;       // Bougies calculées
input string          InpFont      = "Trebuchet MS"; // Police (celle de TradingView)

#define C_GOLD   C'255,215,0'
#define C_GRAY   C'120,123,134'
#define MAX_OBJ  500
#define NA_ID    -1
#define GONE_ID  -2

enum ENUM_LSTYLE { ST_SOLID = 0, ST_DASHED = 1, ST_DOTTED = 2 };
enum ENUM_LKIND { LB_DOT = 0, LB_CSD = 1, LB_ENTRY = 2, LB_SL = 3, LB_TP = 4 };
enum ENUM_LPOS { LS_CENTER = 0, LS_UP = 1, LS_DOWN = 2, LS_NONE = 3 };
enum ENUM_LSIZE { SZ_TINY = 0, SZ_SMALL = 1 };
enum ENUM_ZTYPE { ZT_BB = 0, ZT_FVG = 1 };

struct SLine  { int x1; double y1; int x2; double y2; uint clr; int width; int style; bool alive; };
struct SBox   { int x1; double top; int x2; double bot; uint bg; uint border; int text; uint textClr; bool alive; };
struct SLabel { int x; double y; int kind; uint bg; uint textClr; int style; int size; bool alive; };
struct SLevel { double price; int lineId; bool isHigh; int creationBar; int grabCount; bool active; };
struct SPend  { double grabPrice; int grabBar; bool isBull; int expiryBar; bool active; };
struct SZone  { int boxId; double top; double bottom; bool isBull; int grabBar; double grabPrice; int csdBar; int creationBar;
                bool active; bool touched; double extPrice; bool drawn; int zoneType; bool isGolden; };

template<typename T> void Push(T &arr[], const T &v)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1, 256);
   arr[n] = v;
  }

template<typename T> void CopyArr(T &dst[], const T &src[])
  {
   int n = ArraySize(src);
   ArrayResize(dst, n, 256);
   for(int i = 0; i < n; i++)
      dst[i] = src[i];
  }

template<typename T> void DropFirst(T &arr[], int k)
  {
   int n = ArraySize(arr);
   if(k <= 0)
      return;
   if(k > n)
      k = n;
   for(int i = k; i < n; i++)
      arr[i - k] = arr[i];
   ArrayResize(arr, n - k, 256);
  }

uint Argb(const color c, const int transp)
  {
   return ColorToARGB(c, (uchar)MathRound(255.0 * (100 - transp) / 100.0));
  }

//--- État du script Pine (variables « var » et objets dessinés)
class CState
  {
public:
   SLine             lines[];
   SBox              boxes[];
   SLabel            labels[];
   int               liveL, oldL, liveB, oldB, liveT, oldT;
   SLevel            levels[];
   SPend             pend[];
   SZone             zones[];
   double            bullH, bullL, bearH, bearL;

   void              Reset()
     {
      ArrayFree(lines); ArrayFree(boxes); ArrayFree(labels);
      ArrayFree(levels); ArrayFree(pend); ArrayFree(zones);
      liveL = oldL = liveB = oldB = liveT = oldT = 0;
      bullH = bullL = bearH = bearL = EMPTY_VALUE;
     }

   void              CopyFrom(const CState &o)
     {
      CopyArr(lines, o.lines); CopyArr(boxes, o.boxes); CopyArr(labels, o.labels);
      CopyArr(levels, o.levels); CopyArr(pend, o.pend); CopyArr(zones, o.zones);
      liveL = o.liveL; oldL = o.oldL; liveB = o.liveB; oldB = o.oldB; liveT = o.liveT; oldT = o.oldT;
      bullH = o.bullH; bullL = o.bullL; bearH = o.bearH; bearL = o.bearL;
     }

   // TradingView efface le plus ancien objet au-delà de 500 par type
   int               NewLine(int x1, double y1, int x2, double y2, uint clr, int width, int style)
     {
      SLine l; l.x1 = x1; l.y1 = y1; l.x2 = x2; l.y2 = y2; l.clr = clr; l.width = width; l.style = style; l.alive = true;
      Push(lines, l);
      liveL++;
      while(liveL > MAX_OBJ && oldL < ArraySize(lines))
        {
         if(lines[oldL].alive) { lines[oldL].alive = false; liveL--; }
         oldL++;
        }
      return ArraySize(lines) - 1;
     }

   int               NewBox(int x1, double top, int x2, double bot, uint bg, uint border, int text, uint textClr)
     {
      SBox b; b.x1 = x1; b.top = top; b.x2 = x2; b.bot = bot; b.bg = bg; b.border = border; b.text = text; b.textClr = textClr; b.alive = true;
      Push(boxes, b);
      liveB++;
      while(liveB > MAX_OBJ && oldB < ArraySize(boxes))
        {
         if(boxes[oldB].alive) { boxes[oldB].alive = false; liveB--; }
         oldB++;
        }
      return ArraySize(boxes) - 1;
     }

   void              NewLabel(int x, double y, int kind, uint bg, uint textClr, int style, int size)
     {
      SLabel t; t.x = x; t.y = y; t.kind = kind; t.bg = bg; t.textClr = textClr; t.style = style; t.size = size; t.alive = true;
      Push(labels, t);
      liveT++;
      while(liveT > MAX_OBJ && oldT < ArraySize(labels))
        {
         if(labels[oldT].alive) { labels[oldT].alive = false; liveT--; }
         oldT++;
        }
     }

   void              DeleteLine(int id)
     {
      if(id >= 0 && lines[id].alive) { lines[id].alive = false; liveL--; }
     }

   // Retire les objets effacés en tête de liste (sinon les tableaux grossissent sans fin en temps réel)
   void              Compact()
     {
      if(oldL > 1000)
        {
         int k = oldL;
         DropFirst(lines, k); oldL = 0;
         for(int i = 0; i < ArraySize(levels); i++)
            if(levels[i].lineId >= 0) levels[i].lineId = (levels[i].lineId < k) ? GONE_ID : levels[i].lineId - k;
        }
      if(oldB > 1000)
        {
         int k = oldB;
         DropFirst(boxes, k); oldB = 0;
         for(int i = 0; i < ArraySize(zones); i++)
            if(zones[i].boxId >= 0) zones[i].boxId = (zones[i].boxId < k) ? GONE_ID : zones[i].boxId - k;
        }
      if(oldT > 1000)
        {
         DropFirst(labels, oldT); oldT = 0;
        }
     }
  };

//--- Données
double   gO[], gH[], gL[], gC[];
datetime gT[];
int      gTotal = 0, gStart = 0, gProcessed = -1;
CState   gCommit, gWork;
double   gDpi = 1.0;

//--- Canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(pivotLen < 1 || maxGrabs < 1 || levelExpiry < 1 || csdLookback < 1 || csdWait < 0 || maxZoneWidth < 1 || InpMaxBars < 50)
     {
      Print("LGD+CSD+Fib : paramètre hors limites");
      return INIT_PARAMETERS_INCORRECT;
     }
   gDpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;
   if(gDpi < 1.0)
      gDpi = 1.0;
   gName = "LGDCSD_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "LGD+CSD+Fib " + IntegerToString(pivotLen) + " " + IntegerToString(maxGrabs) + " " +
                      IntegerToString(levelExpiry) + " " + IntegerToString(csdLookback) + " " + IntegerToString(csdWait) + " " +
                      IntegerToString(zoneExpiry) + " " + IntegerToString(maxZoneWidth));
   gProcessed = -1;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(gCvOk)
      gCv.Destroy();
   gCvOk = false;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| ta.pivothigh / ta.pivotlow : à égalité, c'est le plus à gauche   |
//+------------------------------------------------------------------+
bool IsPivotHigh(int c)
  {
   for(int i = 1; i <= pivotLen; i++)
      if(gH[c - i] >= gH[c] || gH[c + i] > gH[c])
         return false;
   return true;
  }

bool IsPivotLow(int c)
  {
   for(int i = 1; i <= pivotLen; i++)
      if(gL[c - i] <= gL[c] || gL[c + i] < gL[c])
         return false;
   return true;
  }

//+------------------------------------------------------------------+
//| getHtfOB() via request.security(..., lookahead_on)               |
//+------------------------------------------------------------------+
bool HtfOB(datetime t, double &obH, double &obL, bool &bS, bool &rS)
  {
   obH = EMPTY_VALUE; obL = EMPTY_VALUE; bS = false; rS = false;
   int sh = iBarShift(_Symbol, htf, t, false);
   if(sh < 0)
      return false;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, htf, sh, 12, r);
   if(n < 0)
      return false;
   if(n < 7)
      return true;
   double hh0 = r[1].high, hh1 = r[2].high, ll0 = r[1].low, ll1 = r[2].low;
   for(int i = 2; i <= 5; i++) { hh0 = MathMax(hh0, r[i].high); ll0 = MathMin(ll0, r[i].low); }
   for(int i = 3; i <= 6; i++) { hh1 = MathMax(hh1, r[i].high); ll1 = MathMin(ll1, r[i].low); }
   bS = r[0].close > hh0 && r[1].close <= hh1;
   rS = r[0].close < ll0 && r[1].close >= ll1;
   for(int i = 1; i <= 10 && i < n; i++)
     {
      if(bS && r[i].close < r[i].open) { obH = r[i].high; obL = r[i].low; break; }
      if(rS && r[i].close > r[i].open) { obH = r[i].high; obL = r[i].low; break; }
     }
   return true;
  }

bool InRange(double v, double lo, double hi)
  {
   return lo != EMPTY_VALUE && hi != EMPTY_VALUE && v >= lo && v <= hi;
  }

//+------------------------------------------------------------------+
//| Une exécution du script Pine sur la bougie t                     |
//+------------------------------------------------------------------+
bool ProcessBar(CState &S, int t)
  {
//--- HTF Order Block
   if(useHtfOb)
     {
      double h, l;
      bool b, r;
      if(!HtfOB(gT[t], h, l, b, r))
         return false;
      if(b) { S.bullH = h; S.bullL = l; }
      if(r) { S.bearH = h; S.bearL = l; }
     }

//--- Level Creation
   int c = t - pivotLen;
   if(c - pivotLen >= 0)
     {
      if(IsPivotHigh(c))
        {
         SLevel lv; lv.price = gH[c]; lv.isHigh = true; lv.creationBar = c; lv.grabCount = 0; lv.active = true;
         lv.lineId = S.NewLine(c, gH[c], t, gH[c], Argb(levelColor, 50), 1, ST_DASHED);
         Push(S.levels, lv);
        }
      if(IsPivotLow(c))
        {
         SLevel lv; lv.price = gL[c]; lv.isHigh = false; lv.creationBar = c; lv.grabCount = 0; lv.active = true;
         lv.lineId = S.NewLine(c, gL[c], t, gL[c], Argb(levelColor, 50), 1, ST_DASHED);
         Push(S.levels, lv);
        }
     }

//--- Level Processing
   for(int i = ArraySize(S.levels) - 1; i >= 0; i--)
     {
      if(!S.levels[i].active)
         continue;
      int id = S.levels[i].lineId;
      double price = S.levels[i].price;
      if(t - S.levels[i].creationBar > levelExpiry)
        {
         S.levels[i].active = false;
         S.DeleteLine(id);
         continue;
        }
      if(id >= 0)
         S.lines[id].x2 = t;
      if(S.levels[i].isHigh)
        {
         if(gH[t] > price && gC[t] <= price)
           {
            bool inHtfOb = !useHtfOb || InRange(gH[t], S.bearL, S.bearH);
            if(inHtfOb)
              {
               S.levels[i].grabCount++;
               SPend p; p.grabPrice = gH[t]; p.grabBar = t; p.isBull = false; p.expiryBar = t + csdLookback; p.active = true;
               Push(S.pend, p);
               if(S.levels[i].grabCount >= maxGrabs)
                  S.levels[i].active = false;
              }
           }
         else if(gC[t] > price)
           {
            S.levels[i].active = false;
            if(id >= 0) S.lines[id].clr = Argb(levelColor, 85);
           }
        }
      else
        {
         if(gL[t] < price && gC[t] >= price)
           {
            bool inHtfOb = !useHtfOb || InRange(gL[t], S.bullL, S.bullH);
            if(inHtfOb)
              {
               S.levels[i].grabCount++;
               SPend p; p.grabPrice = gL[t]; p.grabBar = t; p.isBull = true; p.expiryBar = t + csdLookback; p.active = true;
               Push(S.pend, p);
               if(S.levels[i].grabCount >= maxGrabs)
                  S.levels[i].active = false;
              }
           }
         else if(gC[t] < price)
           {
            S.levels[i].active = false;
            if(id >= 0) S.lines[id].clr = Argb(levelColor, 85);
           }
        }
     }

//--- CSD & Focused Zone Creation
   for(int i = ArraySize(S.pend) - 1; i >= 0; i--)
     {
      if(!S.pend[i].active)
         continue;
      SPend p = S.pend[i];
      int g = p.grabBar;
      double csdTrigger = p.isBull ? gH[g] : gL[g];
      bool confirmed = p.isBull ? gC[t] > csdTrigger : gC[t] < csdTrigger;
      if(confirmed)
        {
         double bbTop = 0, bbBot = 0;
         bool hasBB = false;
         if(showBreaker && g - 1 >= 0)
           {
            if(p.isBull && gC[g - 1] > gO[g - 1])       { bbTop = gH[g - 1]; bbBot = gL[g - 1]; hasBB = true; }
            else if(!p.isBull && gC[g - 1] < gO[g - 1]) { bbTop = gH[g - 1]; bbBot = gL[g - 1]; hasBB = true; }
           }
         bool hasGoldenOverlap = false;
         if(hasBB)
            for(int k = g + 1; k <= t; k++)
              {
               if(k - 2 < 0)
                  continue;
               if(p.isBull && gL[k] > gH[k - 2])
                 {
                  if(gL[k] > bbBot && gH[k - 2] < bbTop) { hasGoldenOverlap = true; break; }
                 }
               else if(!p.isBull && gH[k] < gL[k - 2])
                 {
                  if(gH[k] < bbTop && gL[k - 2] > bbBot) { hasGoldenOverlap = true; break; }
                 }
              }
         if(oteSetting && !hasGoldenOverlap)
           {
            S.pend[i].active = false;
            continue;
           }
         color dirColor = p.isBull ? bullColor : bearColor;
         if(!oteSetting)
           {
            S.NewLabel(g, p.grabPrice, LB_DOT, 0, Argb(dirColor, 0), LS_CENTER, SZ_SMALL);
            S.NewLabel(t, p.isBull ? gL[t] : gH[t], LB_CSD, Argb(dirColor, 0), 0, p.isBull ? LS_UP : LS_DOWN, SZ_TINY);
           }
         for(int k = g; k <= t; k++)
           {
            if(showBreaker && k == g && hasBB)
              {
               color zCol = hasGoldenOverlap ? C_GOLD : dirColor;
               int bId = NA_ID;
               if(!oteSetting)
                  bId = S.NewBox(k - 1, bbTop, t, bbBot, Argb(zCol, 75), Argb(zCol, 0), ZT_BB, Argb(dirColor, 0));
               SZone z;
               z.boxId = bId; z.top = bbTop; z.bottom = bbBot; z.isBull = p.isBull; z.grabBar = g; z.grabPrice = p.grabPrice;
               z.csdBar = t; z.creationBar = t; z.active = true; z.touched = false; z.extPrice = 0.0; z.drawn = !oteSetting;
               z.zoneType = ZT_BB; z.isGolden = hasGoldenOverlap;
               Push(S.zones, z);
              }
            if(showFVG && k >= 2 && k > g)
              {
               double fvgTop = 0, fvgBot = 0;
               bool hasFvg = false;
               if(p.isBull && gL[k] > gH[k - 2])       { fvgTop = gL[k]; fvgBot = gH[k - 2]; hasFvg = true; }
               else if(!p.isBull && gH[k] < gL[k - 2]) { fvgTop = gH[k]; fvgBot = gL[k - 2]; hasFvg = true; }
               if(hasFvg)
                 {
                  bool overlaps = hasBB && fvgTop > bbBot && fvgBot < bbTop;
                  color zCol = overlaps ? C_GOLD : dirColor;
                  int bId = NA_ID;
                  if(!oteSetting)
                     bId = S.NewBox(k - 2, fvgTop, t, fvgBot, Argb(zCol, 75), Argb(zCol, 0), ZT_FVG, Argb(dirColor, 0));
                  SZone z;
                  z.boxId = bId; z.top = fvgTop; z.bottom = fvgBot; z.isBull = p.isBull; z.grabBar = g; z.grabPrice = p.grabPrice;
                  z.csdBar = t; z.creationBar = t; z.active = true; z.touched = false; z.extPrice = 0.0; z.drawn = !oteSetting;
                  z.zoneType = ZT_FVG; z.isGolden = overlaps;
                  Push(S.zones, z);
                 }
              }
           }
         S.pend[i].active = false;
        }
      if(t >= p.expiryBar)
         S.pend[i].active = false;
     }

//--- Zone Management & Fibonacci Pullback
   for(int i = ArraySize(S.zones) - 1; i >= 0; i--)
     {
      if(!S.zones[i].active)
         continue;
      SZone z = S.zones[i];
      if(z.boxId >= 0)
        {
         int currentWidth = t - S.boxes[z.boxId].x1;
         if(currentWidth < maxZoneWidth)
            S.boxes[z.boxId].x2 = t;
        }
      if(!z.drawn && t >= z.csdBar + csdWait)
        {
         if(!z.touched)
           {
            bool touch = z.isBull ? gL[t] <= z.top : gH[t] >= z.bottom;
            if(touch)
              {
               z.touched = true;
               double ext = z.isBull ? gH[z.csdBar] : gL[z.csdBar];
               for(int j = z.csdBar; j <= t; j++)
                 {
                  if(z.isBull) { if(gH[j] > ext) ext = gH[j]; }
                  else         { if(gL[j] < ext) ext = gL[j]; }
                 }
               z.extPrice = ext;
              }
           }
         if(z.touched)
           {
            bool shouldPlot = oteSetting ? (z.isBull ? gC[t] > z.extPrice : gC[t] < z.extPrice) : true;
            if(shouldPlot && z.boxId == NA_ID)
              {
               color dirColor = z.isBull ? bullColor : bearColor;
               color zCol = z.isGolden ? C_GOLD : dirColor;
               int x1 = z.zoneType == ZT_BB ? z.csdBar - 1 : z.creationBar - 2;
               z.boxId = S.NewBox(x1, z.top, t, z.bottom, Argb(zCol, 75), Argb(zCol, 0), z.zoneType, Argb(dirColor, 0));
               bool firstZone = true;
               for(int q = 0; q < ArraySize(S.zones); q++)
                  if(S.zones[q].csdBar == z.csdBar && S.zones[q].drawn) { firstZone = false; break; }
               if(firstZone)
                 {
                  color oppColor = z.isBull ? bearColor : bullColor;
                  S.NewLabel(z.grabBar, z.grabPrice, LB_DOT, 0, Argb(dirColor, 0), LS_CENTER, SZ_SMALL);
                  S.NewLabel(z.csdBar, z.isBull ? gL[z.csdBar] : gH[z.csdBar], LB_CSD, Argb(dirColor, 0), 0, z.isBull ? LS_UP : LS_DOWN, SZ_TINY);
                  S.NewLine(t, gC[t], t + 10, gC[t], Argb(dirColor, 0), 2, ST_SOLID);
                  S.NewLabel(t + 10, gC[t], LB_ENTRY, 0, Argb(dirColor, 0), LS_NONE, SZ_SMALL);
                  S.NewLine(t, z.grabPrice, t + 10, z.grabPrice, Argb(oppColor, 0), 2, ST_DASHED);
                  S.NewLabel(t + 10, z.grabPrice, LB_SL, 0, Argb(oppColor, 0), LS_NONE, SZ_SMALL);
                  double risk = MathAbs(gC[t] - z.grabPrice);
                  double tpPrice = z.isBull ? gC[t] + risk * 2 : gC[t] - risk * 2;
                  S.NewLine(t, tpPrice, t + 10, tpPrice, Argb(C'8,153,129', 0), 2, ST_DOTTED);
                  S.NewLabel(t + 10, tpPrice, LB_TP, 0, Argb(C'8,153,129', 0), LS_NONE, SZ_SMALL);
                 }
              }
           }
         if(z.boxId >= 0)
           {
            S.boxes[z.boxId].bg = Argb(C_GRAY, 95);
            S.boxes[z.boxId].border = Argb(C_GRAY, 95);
           }
        }
      S.zones[i] = z;
     }

//--- Clean Up
   if(ArraySize(S.levels) > 100)
      DropFirst(S.levels, 1);
   if(ArraySize(S.zones) > 50)
      DropFirst(S.zones, 1);
   return true;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < 2 * pivotLen + 3)
      return 0;
   bool full = (prev_calculated == 0 || rates_total < gTotal || gProcessed < 0);
   int from = full ? 0 : MathMax(prev_calculated - 1, 0);
   ArrayResize(gO, rates_total); ArrayResize(gH, rates_total); ArrayResize(gL, rates_total);
   ArrayResize(gC, rates_total); ArrayResize(gT, rates_total);
   for(int i = from; i < rates_total; i++)
     {
      gO[i] = open[i]; gH[i] = high[i]; gL[i] = low[i]; gC[i] = close[i]; gT[i] = time[i];
     }
   gTotal = rates_total;
   if(full)
     {
      gCommit.Reset();
      gStart = MathMax(0, rates_total - InpMaxBars);
      gProcessed = gStart;
     }
   bool newBar = false;
   while(gProcessed < rates_total - 1)
     {
      if(!ProcessBar(gCommit, gProcessed))
        {
         gProcessed = -1;   // données HTF pas prêtes : on recommence au prochain tick
         return 0;
        }
      gProcessed++;
      newBar = true;
     }
   if(newBar)
      gCommit.Compact();
// la bougie en cours est recalculée à chaque tick, comme TradingView
   gWork.CopyFrom(gCommit);
   if(!ProcessBar(gWork, rates_total - 1))
      return prev_calculated;
   uint now = GetTickCount();
   if(full || newBar || now - gLastRender >= 200)
     {
      Render(gWork);
      gLastRender = now;
     }
   return rates_total;
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE && gTotal > 0)
      Render(gWork);
  }

//+------------------------------------------------------------------+
//| Dessin                                                           |
//+------------------------------------------------------------------+
double gX0 = 0, gSp = 1, gY0 = 0, gKy = 0, gPMax = 0;
int    gT0 = 0;

int Px(double v) { return (int)MathRound(v * gDpi); }
// épaisseur de trait : TradingView arrondit à l'entier inférieur (1 px reste 1 px à 125 % et 150 %)
int Wpx(int w) { return MathMax(1, (int)MathFloor(w * gDpi)); }
double XofBar(int t) { return gX0 + (t - gT0) * gSp; }
double YofPrice(double p) { return gY0 + (gPMax - p) * gKy; }

void BlendPx(int x, int y, uint c, double cov)
  {
   if(x < 0 || y < 0 || x >= gW || y >= gHh)
      return;
   double sa = ((c >> 24) & 0xFF) / 255.0 * cov;
   if(sa <= 0.0)
      return;
   uint d = gCv.PixelGet(x, y);
   double da = ((d >> 24) & 0xFF) / 255.0;
   double oa = sa + da * (1.0 - sa);
   if(oa <= 0.0)
      return;
   double k = da * (1.0 - sa);
   uint r = (uint)MathRound((((c >> 16) & 0xFF) * sa + ((d >> 16) & 0xFF) * k) / oa);
   uint g = (uint)MathRound((((c >> 8) & 0xFF) * sa + ((d >> 8) & 0xFF) * k) / oa);
   uint b = (uint)MathRound(((c & 0xFF) * sa + (d & 0xFF) * k) / oa);
   uint a = (uint)MathRound(oa * 255.0);
   gCv.PixelSet(x, y, (a << 24) | (r << 16) | (g << 8) | b);
  }

void FillRect(int x1, int y1, int x2, int y2, uint c)
  {
   int xa = MathMax(MathMin(x1, x2), 0), xb = MathMin(MathMax(x1, x2), gW - 1);
   int ya = MathMax(MathMin(y1, y2), 0), yb = MathMin(MathMax(y1, y2), gHh - 1);
   for(int y = ya; y <= yb; y++)
      for(int x = xa; x <= xb; x++)
         BlendPx(x, y, c, 1.0);
  }

void HLine(int x1, int x2, int y, int w, int style, uint c)
  {
   if(x2 < x1) { int s = x1; x1 = x2; x2 = s; }
   int on = 0, off = 0;
   if(style == ST_DASHED) { on = Px(4); off = Px(4); }
   if(style == ST_DOTTED) { on = MathMax(w, 1); off = MathMax(w, 1) * 2; }
   int ytop = y - (w - 1) / 2;
   int xa = MathMax(x1, 0), xb = MathMin(x2, gW - 1);
   for(int x = xa; x <= xb; x++)
     {
      if(style != ST_SOLID && ((x - x1) % (on + off)) >= on)
         continue;
      for(int k = 0; k < w; k++)
         BlendPx(x, ytop + k, c, 1.0);
     }
  }

void FillCircle(double cx, double cy, double rad, uint c)
  {
   for(int y = (int)MathFloor(cy - rad - 1); y <= (int)MathCeil(cy + rad + 1); y++)
      for(int x = (int)MathFloor(cx - rad - 1); x <= (int)MathCeil(cx + rad + 1); x++)
        {
         double d = MathSqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy));
         double cov = MathMax(0.0, MathMin(1.0, rad + 0.5 - d));
         if(cov > 0.0)
            BlendPx(x, y, c, cov);
        }
  }

void FillRoundRect(int x1, int y1, int x2, int y2, double rad, uint c)
  {
   for(int y = y1; y < y2; y++)
      for(int x = x1; x < x2; x++)
        {
         double px = x + 0.5, py = y + 0.5;
         double qx = MathMax(MathMax(x1 + rad - px, px - (x2 - rad)), 0.0);
         double qy = MathMax(MathMax(y1 + rad - py, py - (y2 - rad)), 0.0);
         double cov = 1.0;
         if(qx > 0.0 && qy > 0.0)
            cov = MathMax(0.0, MathMin(1.0, rad + 0.5 - MathSqrt(qx * qx + qy * qy)));
         if(cov > 0.0)
            BlendPx(x, y, c, cov);
        }
  }

// Pointe de l'étiquette : sommet (ax, ay), base à ay + dir*h
void FillPointer(double ax, int ay, int h, double halfW, int dir, uint c)
  {
   for(int j = 0; j < h; j++)
     {
      double half = halfW * (j + 0.5) / h;
      int y = ay + dir * j - (dir < 0 ? 1 : 0);
      for(int x = (int)MathFloor(ax - half - 1); x <= (int)MathCeil(ax + half + 1); x++)
        {
         double cov = MathMax(0.0, MathMin(1.0, half + 0.5 - MathAbs(x + 0.5 - ax)));
         if(cov > 0.0)
            BlendPx(x, y, c, cov);
        }
     }
  }

void SetFont(int size)
  {
// tailles mesurées sur les captures TradingView ; taille négative = dixièmes de point, suit l'échelle de Windows
   gCv.FontSet(InpFont, size == SZ_TINY ? -45 : -60);
  }

string LabelText(const SLabel &lb)
  {
   if(lb.kind == LB_CSD)   return "CSD";
   if(lb.kind == LB_ENTRY) return "Entry: " + DoubleToString(lb.y, _Digits);
   if(lb.kind == LB_SL)    return "SL: " + DoubleToString(lb.y, _Digits);
   if(lb.kind == LB_TP)    return "TP (1:2): " + DoubleToString(lb.y, _Digits);
   return "";
  }

void Render(CState &S)
  {
   int W = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int H = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(W <= 0 || H <= 0 || gTotal < 2)
      return;
   if(!gCvOk)
     {
      if(!gCv.CreateBitmapLabel(0, 0, gName, 0, 0, W, H, COLOR_FORMAT_ARGB_NORMALIZE))
         return;
      gCvOk = true;
      ObjectSetInteger(0, gName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, gName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, gName, OBJPROP_BACK, false);
     }
   else if(gCv.Width() != W || gCv.Height() != H)
      gCv.Resize(W, H);
   gW = W; gHh = H;
   gCv.Erase(0);

//--- correspondance bougie/prix -> pixels
   int firstShift = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   if(firstShift > gTotal - 1) firstShift = gTotal - 1;
   if(firstShift < 1) firstShift = 1;
   gT0 = gTotal - 1 - firstShift;
   double pMax = ChartGetDouble(0, CHART_PRICE_MAX, 0), pMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   if(pMax <= pMin)
      return;
   int xa, ya, xb, yb;
   if(!ChartTimePriceToXY(0, 0, gT[gT0], pMax, xa, ya) || !ChartTimePriceToXY(0, 0, gT[gT0 + 1], pMin, xb, yb))
      return;
   gX0 = xa;
   gSp = xb - xa;
   if(gSp <= 0) gSp = 1 << (int)ChartGetInteger(0, CHART_SCALE);
   gPMax = pMax; gY0 = ya; gKy = (double)(yb - ya) / (pMax - pMin);

   uint bgArgb = ColorToARGB((color)ChartGetInteger(0, CHART_COLOR_BACKGROUND), 255);
   int bw = Wpx(1);

//--- boîtes
   SetFont(SZ_TINY);
   for(int i = 0; i < ArraySize(S.boxes); i++)
     {
      if(!S.boxes[i].alive)
         continue;
      int x1 = (int)MathRound(XofBar(S.boxes[i].x1)), x2 = (int)MathRound(XofBar(S.boxes[i].x2));
      if(x2 < 0 || x1 > W)
         continue;
      int y1 = (int)MathRound(YofPrice(MathMax(S.boxes[i].top, S.boxes[i].bot)));
      int y2 = (int)MathRound(YofPrice(MathMin(S.boxes[i].top, S.boxes[i].bot)));
      if(y2 < 0 || y1 > H)
         continue;
      FillRect(x1 + bw, y1 + bw, x2 - bw, y2 - bw, S.boxes[i].bg);
      FillRect(x1, y1, x2, y1 + bw - 1, S.boxes[i].border);
      FillRect(x1, y2 - bw + 1, x2, y2, S.boxes[i].border);
      FillRect(x1, y1 + bw, x1 + bw - 1, y2 - bw, S.boxes[i].border);
      FillRect(x2 - bw + 1, y1 + bw, x2, y2 - bw, S.boxes[i].border);
      gCv.TextOut((x1 + x2) / 2, (y1 + y2) / 2, S.boxes[i].text == ZT_BB ? "BB" : "FVG", S.boxes[i].textClr, TA_CENTER | TA_VCENTER);
     }

//--- lignes (toutes horizontales dans cet indicateur)
   for(int i = 0; i < ArraySize(S.lines); i++)
     {
      if(!S.lines[i].alive)
         continue;
      int x1 = (int)MathRound(XofBar(S.lines[i].x1)), x2 = (int)MathRound(XofBar(S.lines[i].x2));
      if(x2 < 0 || x1 > W)
         continue;
      int y = (int)MathRound(YofPrice(S.lines[i].y1));
      HLine(x1, x2, y, Wpx(S.lines[i].width), S.lines[i].style, S.lines[i].clr);
     }

//--- étiquettes
   for(int i = 0; i < ArraySize(S.labels); i++)
     {
      if(!S.labels[i].alive)
         continue;
      double ax = XofBar(S.labels[i].x);
      if(ax < -100 || ax > W + 100)
         continue;
      double ay = YofPrice(S.labels[i].y);
      if(S.labels[i].kind == LB_DOT)
        {
         FillCircle(ax, ay, 2.5 * gDpi, S.labels[i].textClr);
         continue;
        }
      string txt = LabelText(S.labels[i]);
      SetFont(S.labels[i].size);
      if(S.labels[i].style == LS_NONE)
        {
         gCv.TextOut((int)MathRound(ax), (int)MathRound(ay), txt, S.labels[i].textClr, TA_CENTER | TA_VCENTER);
         continue;
        }
      int tw = 0, th = 0;
      gCv.TextSize(txt, tw, th);
      int padX = Px(3), padY = Px(1), ph = Px(3);
      int w = (int)tw + 2 * padX, h = (int)th + 2 * padY;
      int iy = (int)MathRound(ay);
      int x1 = (int)MathRound(ax - w / 2.0);
      int top = S.labels[i].style == LS_UP ? iy + ph : iy - ph - h;
      FillPointer(ax, iy, ph + 1, ph, S.labels[i].style == LS_UP ? 1 : -1, S.labels[i].bg);
      FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, S.labels[i].bg);
      gCv.TextOut(x1 + w / 2, top + h / 2, txt, bgArgb, TA_CENTER | TA_VCENTER);
     }

   gCv.Update(true);
  }
//+------------------------------------------------------------------+
