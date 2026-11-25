//+------------------------------------------------------------------+
//| CX_Press.mq5                                                     |
//| CX Pression Achat / Vente · Force & Direction de tendance        |
//| Portage MT5 de Pine/CX_Pressure.pine (même calcul), dans un      |
//| panneau inférieur avec les tracés natifs de MT5 (comme Volumes). |
//|   • histogramme vert  = pression acheteuse (≈ +200 = normale)    |
//|   • histogramme rouge = pression vendeuse  (≈ −200 = normale)    |
//|   • Fast Trend (ligne épaisse + halo), Core Trend (ligne fine)   |
//|   • Established Trend (carrés à ±120), Strong Trend (points)     |
//|   • Long / Short Covered (barres jaunes / cyan + losanges)       |
//|   • Pressure Cross (gros points ±450), Pre Signals (petits)      |
//|   • tableau Trend / Market State + force acheteurs / vendeurs    |
//| Inspiré de « Buying/Selling Pressure & Trend Strength/Direction  |
//| (Zeiierman) » : code d'origine protégé, calcul propre à CX.      |
//+------------------------------------------------------------------+
#property copyright   "CX Press"
#property version     "1.01"
#property description "CX Pression Achat / Vente : force et direction de la tendance, Long / Short Covered, Pressure Cross, Pre Signals."
#property indicator_separate_window
#property indicator_buffers 32
#property indicator_plots   10
#property indicator_level1  0
#property indicator_level2  400
#property indicator_level3  -400
#property indicator_levelcolor C'120,123,134'
#property indicator_levelstyle STYLE_DOT

#property indicator_label1  "Pression acheteuse"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_width1  3
#property indicator_label2  "Pression vendeuse"
#property indicator_type2   DRAW_COLOR_HISTOGRAM
#property indicator_width2  3
#property indicator_label3  "Core Trend"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_width3  1
#property indicator_label4  "Fast Trend (halo)"
#property indicator_type4   DRAW_COLOR_LINE
#property indicator_width4  6
#property indicator_label5  "Fast Trend"
#property indicator_type5   DRAW_COLOR_LINE
#property indicator_width5  2
#property indicator_label6  "Strong Trend"
#property indicator_type6   DRAW_COLOR_ARROW
#property indicator_width6  2
#property indicator_label7  "Established Trend"
#property indicator_type7   DRAW_COLOR_ARROW
#property indicator_width7  2
#property indicator_label8  "Pressure Cross"
#property indicator_type8   DRAW_COLOR_ARROW
#property indicator_width8  3
#property indicator_label9  "Pre Signal"
#property indicator_type9   DRAW_COLOR_ARROW
#property indicator_width9  1
#property indicator_label10 "Long / Short Covered"
#property indicator_type10  DRAW_COLOR_ARROW
#property indicator_width10 2

//--- réglages (mêmes noms et valeurs que la version TradingView)
input group "Calcul de la pression"
input int    InpCandleLen = 14;               // Candle Length (au-dessus de 30 : mouvements longs)
input int    InpSmooth    = 3;                // Smoothed (10 à 30 : lecture plus stable)
input int    InpNormLen   = 200;              // Historique de référence (200 = pression normale)
input bool   InpUseVol    = true;             // Pondérer par le volume relatif (tick volume)
input group "Tendance"
input int    InpFastLen   = 5;                // Fast Trend
input int    InpCoreLen   = 50;               // Core Trend
input int    InpEstBars   = 8;                // Established Trend : bougies d'accord
input double InpStrongSd  = 1.8;              // Strong Trend : écarts-types
input group "Signaux"
input bool   InpShowCover = true;             // Long / Short Covered
input double InpCoverZ    = 2.5;              // Seuil Covered (écarts-types)
input bool   InpShowCross = true;             // Pressure Cross
input bool   InpShowPre   = true;             // Pre Signals
input group "Affichage"
input bool   InpShowCols  = true;             // Colonnes de pression
input bool   InpShowFast  = true;             // Fast Trend
input bool   InpShowCore  = true;             // Core Trend
input bool   InpShowEst   = true;             // Established Trend
input bool   InpShowStrong = true;            // Strong Trend
input bool   InpShowTable = true;             // Tableau Trend / Market State / Force
input color  ColBull      = C'0,230,118';     // Haussier
input color  ColBear      = C'255,23,68';     // Baissier
input color  ColLc        = C'255,214,0';     // Long Covered
input color  ColSc        = C'0,229,255';     // Short Covered
input group "Alertes (à la clôture de la bougie)"
input bool   AlCross      = true;             // Pressure Cross
input bool   AlPre        = false;            // Pre Signals
input bool   AlCover      = true;             // Long / Short Covered
input bool   AlEst        = true;             // Established Trend (début)
input bool   AlCore       = true;             // Core Trend change de camp
input bool   AlPopup      = true;             // Fenêtre et son MT5
input bool   AlPush       = true;             // Notification mobile (MetaQuotes ID)
input group "MT5"
input int    InpMaxBars   = 5000;             // Bougies calculées

#define NSHADE 8                              // nuances d'intensité des colonnes

//--- tracés
double bBuy[], cBuy[], bSell[], cSell[], bCore[], cCore[], bHalo[], cHalo[], bFast[], cFast[];
double bStrong[], cStrong[], bEst[], cEst[], bCross[], cCross[], bPre[], cPre[], bCov[], cCov[];
//--- calculs
double kBuyP[], kFast[], kCore[], kBuyE[], kSellE[], kSellPos[], kNetRaw[], kNetP[], kBarNet[], kUpRun[], kDnRun[], kFastSig[];

string   gPfx;
datetime gLastAlert = 0;

//+------------------------------------------------------------------+
//| Couleurs                                                         |
//+------------------------------------------------------------------+
color Mix(color c, color bg, double a)        // a = opacité 0…1 sur le fond du graphique
  {
   uint cu = (uint)c, bu = (uint)bg;
   int r = (int)MathRound((cu & 0xFF) * a + (bu & 0xFF) * (1 - a));
   int g = (int)MathRound(((cu >> 8) & 0xFF) * a + ((bu >> 8) & 0xFF) * (1 - a));
   int b = (int)MathRound(((cu >> 16) & 0xFF) * a + ((bu >> 16) & 0xFF) * (1 - a));
   return (color)(r | (g << 8) | (b << 16));
  }

void SetPalette(int plot, const color &cols[])
  {
   int n = ArraySize(cols);
   PlotIndexSetInteger(plot, PLOT_COLOR_INDEXES, n);
   for(int i = 0; i < n; i++)
      PlotIndexSetInteger(plot, PLOT_LINE_COLOR, i, cols[i]);
  }

void ApplyColors()
  {
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   color pb[NSHADE + 1], ps[NSHADE + 1];
   //--- transparence de Pine 80 % → 10 % : opacité 0,2 → 0,9
   for(int i = 0; i < NSHADE; i++)
     {
      double a = 0.2 + 0.7 * i / (NSHADE - 1);
      pb[i] = Mix(ColBull, bg, a);
      ps[i] = Mix(ColBear, bg, a);
     }
   pb[NSHADE] = ColSc;                        // Short Covered
   ps[NSHADE] = ColLc;                        // Long Covered
   SetPalette(0, pb);
   SetPalette(1, ps);
   color two[2];
   two[0] = Mix(ColBull, bg, 0.6); two[1] = Mix(ColBear, bg, 0.6); SetPalette(2, two);
   two[0] = Mix(ColBull, bg, 0.2); two[1] = Mix(ColBear, bg, 0.2); SetPalette(3, two);
   two[0] = ColBull; two[1] = ColBear; SetPalette(4, two);
   SetPalette(5, two);
   SetPalette(6, two);
   SetPalette(7, two);
   two[0] = Mix(ColBull, bg, 0.55); two[1] = Mix(ColBear, bg, 0.55); SetPalette(8, two);
   two[0] = ColSc; two[1] = ColLc; SetPalette(9, two);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpCandleLen < 2 || InpSmooth < 1 || InpNormLen < 50 || InpFastLen < 1 || InpCoreLen < 2 || InpMaxBars < 500)
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0, bBuy, INDICATOR_DATA);     SetIndexBuffer(1, cBuy, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, bSell, INDICATOR_DATA);    SetIndexBuffer(3, cSell, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, bCore, INDICATOR_DATA);    SetIndexBuffer(5, cCore, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6, bHalo, INDICATOR_DATA);    SetIndexBuffer(7, cHalo, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(8, bFast, INDICATOR_DATA);    SetIndexBuffer(9, cFast, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(10, bStrong, INDICATOR_DATA); SetIndexBuffer(11, cStrong, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(12, bEst, INDICATOR_DATA);    SetIndexBuffer(13, cEst, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(14, bCross, INDICATOR_DATA);  SetIndexBuffer(15, cCross, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(16, bPre, INDICATOR_DATA);    SetIndexBuffer(17, cPre, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(18, bCov, INDICATOR_DATA);    SetIndexBuffer(19, cCov, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(20, kBuyE, INDICATOR_CALCULATIONS);
   SetIndexBuffer(21, kSellE, INDICATOR_CALCULATIONS);
   SetIndexBuffer(22, kSellPos, INDICATOR_CALCULATIONS);
   SetIndexBuffer(23, kNetRaw, INDICATOR_CALCULATIONS);
   SetIndexBuffer(24, kNetP, INDICATOR_CALCULATIONS);
   SetIndexBuffer(25, kBarNet, INDICATOR_CALCULATIONS);
   SetIndexBuffer(26, kUpRun, INDICATOR_CALCULATIONS);
   SetIndexBuffer(27, kDnRun, INDICATOR_CALCULATIONS);
   SetIndexBuffer(28, kFastSig, INDICATOR_CALCULATIONS);
   SetIndexBuffer(29, kBuyP, INDICATOR_CALCULATIONS);
   SetIndexBuffer(30, kFast, INDICATOR_CALCULATIONS);
   SetIndexBuffer(31, kCore, INDICATOR_CALCULATIONS);
   for(int p = 0; p < 10; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   //--- symboles Wingdings : ● gros point, · petit point, ▪ carré, ◆ losange
   PlotIndexSetInteger(5, PLOT_ARROW, 159);
   PlotIndexSetInteger(6, PLOT_ARROW, 167);
   PlotIndexSetInteger(7, PLOT_ARROW, 108);
   PlotIndexSetInteger(8, PLOT_ARROW, 159);
   PlotIndexSetInteger(9, PLOT_ARROW, 117);
   ApplyColors();
   IndicatorSetInteger(INDICATOR_DIGITS, 1);
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Press");
   gPfx = "CXPRESS_" + IntegerToString(ChartID()) + "_";
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, gPfx);
   ChartRedraw();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE) ApplyColors();    // fond du graphique changé
  }

//+------------------------------------------------------------------+
//| Outils (équivalents de ta.sma / ta.stdev / ta.ema de Pine)       |
//+------------------------------------------------------------------+
double Sma(const double &a[], int i, int len, int first)
  {
   if(i - len + 1 < first) return EMPTY_VALUE;
   double s = 0;
   for(int k = i - len + 1; k <= i; k++) s += a[k];
   return s / len;
  }

double Sd(const double &a[], int i, int len, int first)
  {
   double m = Sma(a, i, len, first);
   if(m == EMPTY_VALUE) return EMPTY_VALUE;
   double s = 0;
   for(int k = i - len + 1; k <= i; k++) s += (a[k] - m) * (a[k] - m);
   return MathSqrt(s / len);
  }

double Ema(double prev, double x, int len) { return prev == EMPTY_VALUE ? x : prev + (x - prev) * 2.0 / (len + 1); }

//--- ta.percentrank : part des « len » valeurs précédentes inférieures ou égales
double PercentRank(const double &a[], int i, int len, int first)
  {
   if(i - len < first) return 0;
   int c = 0;
   for(int k = i - len; k < i; k++) if(a[k] <= a[i]) c++;
   return 100.0 * c / len;
  }

//+------------------------------------------------------------------+
double gVol[], gBuyRaw[], gSellRaw[];

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < InpNormLen + 10) return 0;
   int first = MathMax(1, rates_total - InpMaxBars);     // première bougie calculée
   int start = prev_calculated > 0 ? prev_calculated - 1 : first;
   if(start <= first)
     {
      start = first;
      for(int i = 0; i < rates_total; i++)
        {
         bBuy[i] = bSell[i] = bCore[i] = bHalo[i] = bFast[i] = EMPTY_VALUE;
         bStrong[i] = bEst[i] = bCross[i] = bPre[i] = bCov[i] = EMPTY_VALUE;
         kBuyE[i] = kSellE[i] = kSellPos[i] = kNetRaw[i] = kNetP[i] = kFastSig[i] = EMPTY_VALUE;
         kBuyP[i] = kFast[i] = kCore[i] = EMPTY_VALUE;
         kBarNet[i] = 0; kUpRun[i] = kDnRun[i] = 0;
         cBuy[i] = cSell[i] = cCore[i] = cHalo[i] = cFast[i] = 0;
         cStrong[i] = cEst[i] = cCross[i] = cPre[i] = cCov[i] = 0;
        }
     }
   ArrayResize(gVol, rates_total); ArrayResize(gBuyRaw, rates_total); ArrayResize(gSellRaw, rates_total);
   int per = PeriodSeconds(PERIOD_CURRENT);

   for(int i = start; i < rates_total; i++)
     {
      bool live = i == rates_total - 1;
      //--- pression « vraie » de la bougie (gaps inclus)
      double prevC = close[i - 1];
      gBuyRaw[i]  = close[i] - MathMin(low[i], prevC);
      gSellRaw[i] = MathMax(high[i], prevC) - close[i];
      //--- bougie en cours : volume projeté sur sa durée complète
      double frac = 1.0;
      if(live)
         frac = MathMax(MathMin((double)(TimeCurrent() - time[i]) / MathMax(per, 1), 1.0), 0.15);
      gVol[i] = (double)tick_volume[i] / frac;
      double vm = Sma(gVol, i, InpCandleLen, first);
      double rv = InpUseVol && gVol[i] > 0 && vm != EMPTY_VALUE && vm > 0 ? MathMin(gVol[i] / vm, 5.0) : 1.0;

      kBuyE[i]  = Ema(i > first ? kBuyE[i - 1] : EMPTY_VALUE, gBuyRaw[i] * rv, InpCandleLen);
      kSellE[i] = Ema(i > first ? kSellE[i - 1] : EMPTY_VALUE, gSellRaw[i] * rv, InpCandleLen);
      double bb = Sma(kBuyE, i, InpNormLen, first), sb = Sma(kSellE, i, InpNormLen, first);
      double bp = Ema(i > first ? kBuyP[i - 1] : EMPTY_VALUE,
                      bb != EMPTY_VALUE && bb > 0 ? 200.0 * kBuyE[i] / bb : 0.0, InpSmooth);
      double sp = Ema(i > first ? kSellPos[i - 1] : EMPTY_VALUE,
                      sb != EMPTY_VALUE && sb > 0 ? 200.0 * kSellE[i] / sb : 0.0, InpSmooth);
      kSellPos[i] = sp;
      kBuyP[i] = bp;
      bBuy[i]  = bp;
      bSell[i] = -sp;

      //--- dominance nette rapportée à sa dispersion
      kNetRaw[i] = bp - sp;
      double nsd = Sd(kNetRaw, i, InpNormLen, first);
      kNetP[i] = nsd != EMPTY_VALUE && nsd > 0 ? kNetRaw[i] / nsd * 300.0 : 0.0;
      double fast = Ema(i > first ? kFast[i - 1] : EMPTY_VALUE, kNetP[i], InpFastLen);
      double core = Ema(i > first ? kCore[i - 1] : EMPTY_VALUE, kNetP[i], InpCoreLen);
      kFast[i] = fast; kCore[i] = core;
      bFast[i] = fast; bHalo[i] = fast; bCore[i] = core;
      double fastPrev = i > first ? kFast[i - 1] : fast;
      cFast[i] = fast >= fastPrev ? 0 : 1;
      cHalo[i] = cFast[i];
      cCore[i] = core >= 0 ? 0 : 1;
      kFastSig[i] = Ema(i > first ? kFastSig[i - 1] : EMPTY_VALUE, fast, 5);

      //--- force et état de la tendance
      double fm = Sma(kFast, i, InpNormLen, first), fsd = Sd(kFast, i, InpNormLen, first);
      bool strongUp = fm != EMPTY_VALUE && fast > 0 && core > 0 && fast > fm + InpStrongSd * fsd;
      bool strongDn = fm != EMPTY_VALUE && fast < 0 && core < 0 && fast < fm - InpStrongSd * fsd;
      kUpRun[i] = fast > 0 && core > 0 ? kUpRun[i - 1] + 1 : 0;
      kDnRun[i] = fast < 0 && core < 0 ? kDnRun[i - 1] + 1 : 0;
      bool estUp = kUpRun[i] >= InpEstBars, estDn = kDnRun[i] >= InpEstBars;

      //--- Long / Short Covered
      kBarNet[i] = (gBuyRaw[i] - gSellRaw[i]) * rv;
      double bm = Sma(kBarNet, i, 50, first), bs = Sd(kBarNet, i, 50, first);
      double z = bm != EMPTY_VALUE && bs > 0 ? (kBarNet[i] - bm) / bs : 0.0;
      bool shortCov = z >= InpCoverZ && core < 0;
      bool longCov  = z <= -InpCoverZ && core > 0;

      //--- Pressure Cross et Pre Signals
      bool crossUp = i > first && bp > sp && kBuyP[i - 1] != EMPTY_VALUE && kBuyP[i - 1] <= kSellPos[i - 1];
      bool crossDn = i > first && bp < sp && kBuyP[i - 1] != EMPTY_VALUE && kBuyP[i - 1] >= kSellPos[i - 1];
      double fsPrev = i > first ? kFastSig[i - 1] : kFastSig[i];
      bool preUp = fast > kFastSig[i] && fastPrev <= fsPrev && fast < 0 && !crossUp;
      bool preDn = fast < kFastSig[i] && fastPrev >= fsPrev && fast > 0 && !crossDn;

      //--- couleurs des colonnes : intensité = force relative (rang sur 100 bougies)
      double bullStr = PercentRank(kBuyP, i, 100, first);
      double bearStr = PercentRank(kSellPos, i, 100, first);
      cBuy[i]  = InpShowCover && shortCov ? NSHADE : MathMin(NSHADE - 1, (int)MathFloor(bullStr / 100.0 * NSHADE));
      cSell[i] = InpShowCover && longCov  ? NSHADE : MathMin(NSHADE - 1, (int)MathFloor(bearStr / 100.0 * NSHADE));
      if(!InpShowCols) { bBuy[i] = EMPTY_VALUE; bSell[i] = EMPTY_VALUE; }
      if(!InpShowFast) { bFast[i] = EMPTY_VALUE; bHalo[i] = EMPTY_VALUE; }
      if(!InpShowCore) bCore[i] = EMPTY_VALUE;

      bStrong[i] = InpShowStrong && (strongUp || strongDn) ? fast : EMPTY_VALUE;  cStrong[i] = strongUp ? 0 : 1;
      bEst[i]    = InpShowEst && estUp ? 120 : InpShowEst && estDn ? -120 : EMPTY_VALUE; cEst[i] = estUp ? 0 : 1;
      bCross[i]  = InpShowCross && crossUp ? 450 : InpShowCross && crossDn ? -450 : EMPTY_VALUE; cCross[i] = crossUp ? 0 : 1;
      bPre[i]    = InpShowPre && preUp ? 450 : InpShowPre && preDn ? -450 : EMPTY_VALUE; cPre[i] = preUp ? 0 : 1;
      bCov[i]    = InpShowCover && shortCov ? -650 : InpShowCover && longCov ? 650 : EMPTY_VALUE; cCov[i] = shortCov ? 0 : 1;

      //--- alertes : une fois par bougie clôturée, en direct uniquement
      if(i == rates_total - 2 && prev_calculated > 0 && time[i] != gLastAlert)
        {
         gLastAlert = time[i];
         string m = "";
         if(AlCross && crossUp) m += " · acheteurs passent devant (Pressure Cross)";
         if(AlCross && crossDn) m += " · vendeurs passent devant (Pressure Cross)";
         if(AlPre && preUp)     m += " · Pre Signal haussier";
         if(AlPre && preDn)     m += " · Pre Signal baissier";
         if(AlCover && shortCov) m += " · Short Covered";
         if(AlCover && longCov)  m += " · Long Covered";
         if(AlEst && estUp && kUpRun[i] == InpEstBars) m += " · tendance haussière installée";
         if(AlEst && estDn && kDnRun[i] == InpEstBars) m += " · tendance baissière installée";
         double cp = kCore[i - 1] == EMPTY_VALUE ? core : kCore[i - 1];
         if(AlCore && core > 0 && cp <= 0) m += " · régime de fond haussier";
         if(AlCore && core < 0 && cp >= 0) m += " · régime de fond baissier";
         if(m != "") SendAlert(StringSubstr(m, 3));
        }

      if(live) DrawTable(core, fast, strongUp, strongDn, estUp, estDn, bullStr, bearStr);
     }
   return rates_total;
  }

void SendAlert(string msg)
  {
   int p = PeriodSeconds(PERIOD_CURRENT);
   string tf = p < 3600 ? "M" + IntegerToString(p / 60) : p < 86400 ? "H" + IntegerToString(p / 3600) : "D1";
   string txt = "CX Press " + _Symbol + " " + tf + " : " + msg;
   if(AlPopup) Alert(txt);
   if(AlPush)  SendNotification(StringSubstr(txt, 0, 255));
  }

//+------------------------------------------------------------------+
//| Tableau dans le panneau (cellules MT5 natives)                   |
//+------------------------------------------------------------------+
void Cell(string id, int x, int y, int w, string txt, color bg, color fg)
  {
   string n = gPfx + id;
   int win = ChartWindowFind();
   if(win < 0) return;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_EDIT, win, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_READONLY, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, n, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, 18);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, fg);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
  }

void DrawTable(double core, double fast, bool strongUp, bool strongDn, bool estUp, bool estDn, double bullStr, double bearStr)
  {
   if(!InpShowTable) { ObjectsDeleteAll(0, gPfx); return; }
   color blue = C'41,98,255', grey = C'120,123,134', orange = C'255,152,0';
   string trend = core > 0 ? "Bullish" : core < 0 ? "Bearish" : "Neutral";
   color  tBg   = core > 0 ? ColBull : core < 0 ? ColBear : grey;
   string state = strongUp || strongDn ? "Strong · Stretched" : estUp || estDn ? "Trending" : MathAbs(core) < 60 ? "Ranging" : "Building";
   color  sBg   = strongUp || strongDn ? orange : estUp || estDn ? tBg : grey;
   int w1 = 100, w2 = 160, x2 = 10, x1 = x2 + w2;
   //--- coin haut droit : la distance x va du bord droit du panneau au bord gauche de la cellule
   Cell("h1", x1 + w1, 4, w1, "Trend", blue, clrWhite);
   Cell("h2", x2 + w2, 4, w2, "Market State", blue, clrWhite);
   Cell("v1", x1 + w1, 22, w1, trend, tBg, clrWhite);
   Cell("v2", x2 + w2, 22, w2, state, sBg, clrWhite);
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   Cell("f1", x1 + w1, 40, w1, "Bull " + DoubleToString(bullStr, 0) + "%", Mix(ColBull, bg, 0.25), ColBull);
   Cell("f2", x2 + w2, 40, w2, "Bear Strength " + DoubleToString(bearStr, 0) + "%", Mix(ColBear, bg, 0.25), ColBear);
  }
//+------------------------------------------------------------------+
