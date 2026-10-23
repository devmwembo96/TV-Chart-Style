//+------------------------------------------------------------------+
//| TV_Chart_Style.mq5                                               |
//| Donne au graphique MT5 l'aspect du graphique clair TradingView.  |
//| Mêmes couleurs que l'option InpTVStyle de CarnetXAU.             |
//+------------------------------------------------------------------+
#property copyright   "devmwembo96"
#property version     "1.00"
#property description "Style de graphique TradingView (clair) : bougies vertes et rouges, fond blanc, sans grille ni volumes."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input bool InpShowVolumes = false;  // Afficher les volumes
input bool InpShowGrid    = false;  // Afficher la grille
input bool InpShowAsk     = false;  // Afficher la ligne Ask
input bool InpRestore     = true;   // Rétablir les couleurs d'origine au retrait

#define TV_BG    C'255,255,255'
#define TV_TEXT  C'19,23,34'
#define TV_GRAY  C'120,123,134'
#define TV_GRID  C'240,243,250'
#define TV_UP    C'8,153,129'
#define TV_DOWN  C'242,54,69'

ENUM_CHART_PROPERTY_INTEGER gProps[] =
  {
   CHART_COLOR_BACKGROUND, CHART_COLOR_FOREGROUND, CHART_COLOR_GRID, CHART_COLOR_CHART_UP, CHART_COLOR_CHART_DOWN,
   CHART_COLOR_CANDLE_BULL, CHART_COLOR_CANDLE_BEAR, CHART_COLOR_CHART_LINE, CHART_COLOR_BID, CHART_COLOR_ASK,
   CHART_COLOR_LAST, CHART_COLOR_STOP_LEVEL, CHART_COLOR_VOLUME, CHART_MODE, CHART_SHOW_GRID, CHART_SHOW_VOLUMES,
   CHART_SHOW_ASK_LINE, CHART_SHOW_PERIOD_SEP
  };
// Les couleurs d'origine sont gardées en variables globales du terminal :
// un changement d'unité de temps relance OnInit, qui ne doit pas les écraser.
string GvName(int i) { return "TVStyle_" + IntegerToString(ChartID()) + "_" + IntegerToString(i); }

int OnInit()
  {
   int n = ArraySize(gProps);
   if(!GlobalVariableCheck(GvName(0)))
      for(int i = 0; i < n; i++)
         GlobalVariableSet(GvName(i), (double)ChartGetInteger(0, gProps[i]));

   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, TV_BG);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, TV_TEXT);
   ChartSetInteger(0, CHART_COLOR_GRID, TV_GRID);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, TV_UP);       // mèche et contour haussiers
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, TV_DOWN);   // mèche et contour baissiers
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, TV_UP);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, TV_DOWN);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, TV_TEXT);
   ChartSetInteger(0, CHART_COLOR_BID, TV_GRAY);
   ChartSetInteger(0, CHART_COLOR_ASK, TV_DOWN);
   ChartSetInteger(0, CHART_COLOR_LAST, TV_GRAY);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, TV_DOWN);
   ChartSetInteger(0, CHART_COLOR_VOLUME, TV_GRAY);
   ChartSetInteger(0, CHART_SHOW_GRID, InpShowGrid);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, InpShowVolumes ? CHART_VOLUME_TICK : CHART_VOLUME_HIDE);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, InpShowAsk);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartRedraw();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
// on garde le style quand on change d'unité de temps ou de réglages
   if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS || reason == REASON_RECOMPILE)
      return;
   if(!InpRestore)
     {
      for(int i = 0; i < ArraySize(gProps); i++)
         GlobalVariableDel(GvName(i));
      return;
     }
   for(int i = 0; i < ArraySize(gProps); i++)
     {
      if(GlobalVariableCheck(GvName(i)))
         ChartSetInteger(0, gProps[i], (long)GlobalVariableGet(GvName(i)));
      GlobalVariableDel(GvName(i));
     }
   ChartRedraw();
  }

int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
  {
   return rates_total;
  }
//+------------------------------------------------------------------+
