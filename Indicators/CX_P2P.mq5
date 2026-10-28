//+------------------------------------------------------------------+
//| CX_P2P.mq5                                                       |
//| « CX P2P » : retournements structurels sur la liquidité de       |
//| séance, recréés d'après la description publique (sans code       |
//| d'origine). Séquence stricte, bougie par bougie :                |
//|  1. Contexte : plus haut / bas d'Asie et de Londres, PDH, PDL,   |
//|     PD50 (milieu du jour précédent), True Day Open (00:00 NY).   |
//|  2. Zone testée : le prix touche un niveau -> état « amorcé »    |
//|     (niveau haut -> vente, niveau bas -> achat), durée limitée.  |
//|  3. Inversion : clôture franche à travers un FVG opposé formé    |
//|     pendant la poussée vers le niveau (iFVG).                    |
//|  4. MSS (optionnel) : clôture au-delà du dernier swing formé     |
//|     avant l'extrême, dans le nouveau sens.                       |
//|  5. Filtre ATR : corps de la bougie de signal (ou distance       |
//|     depuis l'extrême) >= X % de l'ATR.                           |
//| Cibles : extensions de Fibonacci de la plage de séance (Global   |
//| ou Pré-marché), liquidité opposée et FVG opposé.                 |
//| Dessin en CCanvas : transparence, police Trebuchet MS et limite  |
//| de 500 objets par type comme TradingView.                        |
//+------------------------------------------------------------------+
#property copyright   "CX P2P (réimplémentation d'après description)"
#property version     "1.00"
#property description "CX P2P : niveaux de séance et quotidiens, amorçage, inversion de FVG, MSS, filtre ATR, signaux BUY / SELL et cibles de Fibonacci."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

enum ENUM_LSTYLE   { sol = 0, dsh = 1, dot = 2 };
enum ENUM_TSIZE    { tiny = 0, small = 1, normal = 2 };
enum ENUM_SIZEMODE { Size_ATR = 0, Size_Price = 1 };           // filtre de taille des FVG
enum ENUM_ATRMODE  { Atr_Body = 0, Atr_Extreme = 1 };          // mesure du mouvement de reprise
enum ENUM_FIBRANGE { Range_Global = 0, Range_PreMarket = 1 };  // plage des projections
enum ENUM_ALTTGT   { Alt_None = 0, Alt_Liquidity = 1, Alt_Fvg = 2, Alt_Both = 3 };

input group "Séances (heure de New York)"
input bool   ShowAsia      = true;              // Asie : afficher
input string AsiaHours     = "20:00-00:00";     // Asie : heures (NY)
input color  AsiaColor     = C'41,98,255';      // Asie : couleur
input bool   ShowLondon    = true;              // Londres : afficher
input string LondonHours   = "02:00-05:00";     // Londres : heures (NY)
input color  LondonColor   = C'255,152,0';      // Londres : couleur
input int    SessBoxTransp = 92;                // Transparence des boîtes de séance
input bool   SrvUsDst      = true;              // Serveur à l'heure d'été américaine (FundedNext : UTC+2 / UTC+3)
input group "Références quotidiennes"
input bool   ShowPDH       = true;              // PDH (plus haut de la veille)
input bool   ShowPDL       = true;              // PDL (plus bas de la veille)
input bool   ShowPD50      = true;              // PD50 (milieu de la veille)
input bool   ShowTDO       = true;              // True Day Open (00:00 NY)
input color  DailyColor    = C'120,123,134';    // Couleur PDH / PDL / PD50
input color  TdoColor      = C'156,39,176';     // Couleur True Day Open
input ENUM_LSTYLE LevelStyle = dsh;             // Style des niveaux
input bool   LevelLabels   = true;              // Étiquettes des niveaux
input bool   HiddenPrime   = false;             // Niveaux masqués utilisés pour l'amorçage
input group "Amorçage (zone testée)"
input int    PrimeBars     = 30;                // Validité de l'état amorcé (bougies)
input int    PushBars      = 20;                // Poussée : bougies avant le contact où chercher le FVG
input bool   ShowPrime     = true;              // Marquer l'amorçage (▲ / ▼ gris)
input group "FVG (déclencheur)"
input bool          ShowFvg      = true;        // Afficher les FVG actifs
input bool          ShowMitig    = false;       // Afficher les FVG comblés
input ENUM_SIZEMODE FvgSizeMode  = Size_ATR;    // Unité du filtre de taille (ATR ou prix)
input double        FvgMin       = 0.10;        // Min Gap Size
input double        FvgMax       = 3.00;        // Max Gap Size (0 = sans maximum)
input color         FvgBullColor = C'8,153,129';  // FVG haussier
input color         FvgBearColor = C'242,54,69';  // FVG baissier
input int           FvgTransp    = 85;          // Transparence FVG actif
input int           FvgMitTransp = 94;          // Transparence FVG comblé
input group "Structure (MSS)"
input bool   UseMss        = true;              // MSS Confirmation
input int    PivotLen      = 3;                 // Pivot (bougies de chaque côté)
input bool   ShowMss       = true;              // Afficher la ligne MSS
input group "Filtre ATR"
input int          AtrLen  = 14;                // ATR Longueur
input ENUM_ATRMODE AtrMode = Atr_Body;          // Mesure : corps de la bougie ou distance depuis l'extrême
input double       AtrPct  = 50.0;              // ATR Percentage
input group "Signaux"
input bool       OnClose   = true;              // Signaux validés à la clôture de bougie (sans scintillement)
input ENUM_TSIZE SigSize   = small;             // Taille des étiquettes BUY / SELL
input color      BuyColor  = C'8,153,129';      // Couleur BUY
input color      SellColor = C'242,54,69';      // Couleur SELL
input group "Cibles Fibonacci"
input bool          ShowFib     = true;         // Afficher les cibles
input ENUM_FIBRANGE FibRange    = Range_Global; // Plage : Global ou Pré-marché
input string        GlobalStart = "18:00";      // Global : début du jour de trading (NY)
input string        PreHours    = "20:00-09:30";// Pré-marché : heures (NY)
input string        FibLevels   = "-0.236,-0.5,-0.786,-1"; // Niveaux (séparés par , ou ;)
input int           FibLen      = 40;           // Longueur des lignes (bougies)
input bool          FibKeep     = false;        // Garder les cibles des signaux précédents
input ENUM_ALTTGT   AltTarget   = Alt_Both;     // Cible alternative : liquidité / FVG opposés
input group "Alertes (à la clôture de la bougie)"
input bool   AlPopup     = true;   // Fenêtre et son MT5
input bool   AlPush      = true;   // Notification mobile (MetaQuotes ID)
input bool   AlSessions    = true;            // Alertes seulement pendant les séances ci-dessous
input bool   AlLondon      = true;            // Séance de Londres
input string AlLondonHours = "08:00-11:00";   // Heures de Londres (heure de Londres)
input bool   AlNewYork     = true;            // Séance de New York
input string AlNYHours     = "08:30-11:30";   // Heures de New York (heure de New York)
input bool   AlSignal    = true;   // Any Signal (BUY / SELL)
input bool   AlPrime     = false;  // État amorcé (niveau touché)
input group "MT5"
input int    InpMaxBars = 5000;               // Bougies calculées (TradingView : 5 000)
input string InpFont    = "Trebuchet MS";     // Police (celle de TradingView)

//--- Couleurs Pine v5
#define PC_GRAY   C'120,123,134'
#define PC_BLACK  C'54,58,69'
#define PC_WHITE  C'255,255,255'

#define NA     EMPTY_VALUE
#define NAI    -2147483647
#define MAX_OBJ 500
#define NLVL   8

enum ENUM_LBLSTYLE { LS_DOWN = 0, LS_UP = 1, LS_LEFT = 2 };
enum ENUM_LVKIND   { LK_HIGH = 0, LK_LOW = 1, LK_MID = 2 };
enum ENUM_LVID     { LV_ASH = 0, LV_ASL = 1, LV_LOH = 2, LV_LOL = 3, LV_PDH = 4, LV_PDL = 5, LV_PD50 = 6, LV_TDO = 7 };

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
//--- Niveau de liquidité (séance ou quotidien)
struct SLvl   { double price; int kind; int line; int lbl; bool valid; bool swept; int from; };
//--- FVG suivi : actif jusqu'à la clôture au-delà de son bord opposé (comblé)
struct SFvg   { int born; int x1; double top; double bot; int dir; bool active; bool inv; int box; };

template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
template<typename T> void PushV(T &a[], T v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
template<typename T> void RemoveAt(T &a[], int i)
  {
   int n = ArraySize(a);
   if(i < 0 || i >= n) return;
   for(int k = i; k < n - 1; k++) a[k] = a[k + 1];
   ArrayResize(a, n - 1, 64);
  }
template<typename T> void CopyArr(T &d[], const T &s[])
  {
   int n = ArraySize(s);
   ArrayResize(d, n, 64);
   for(int i = 0; i < n; i++) d[i] = s[i];
  }

//+------------------------------------------------------------------+
//| État complet du calcul (variables « var » et objets)             |
//+------------------------------------------------------------------+
class CState
  {
public:
   //--- objets
   DLine  lines[];  DBox boxes[];  DLabel labels[];
   int    liveL, oldL, liveB, oldB, liveT, oldT;
   //--- niveaux : Asie H/B, Londres H/B, PDH, PDL, PD50, TDO
   SLvl   lv[NLVL];
   //--- séances en cours (0 = Asie, 1 = Londres)
   bool   sesIn[2]; double sesH[2], sesL[2]; int sesHB[2], sesLB[2], sesStart[2], sesBox[2], sesLbl[2];
   int    curD1; long nyDay;
   //--- plages des projections
   long   glKey; double glH, glL;
   bool   pmIn;  double pmH, pmL;
   //--- FVG et pivots
   SFvg   fvg[];
   double phV[], plV[]; int phB[], plB[];
   //--- état amorcé (0 = achat, 1 = vente)
   bool   pr[2]; int prBar[2], prExp[2], prExtBar[2], prInv[2], prLvl[2]; double prExt[2];
   //--- objets des dernières cibles
   int    tgL[], tgT[];

   void Reset()
     {
      ArrayFree(lines); ArrayFree(boxes); ArrayFree(labels);
      liveL = oldL = liveB = oldB = liveT = oldT = 0;
      for(int i = 0; i < NLVL; i++)
        {
         lv[i].price = NA; lv[i].line = -1; lv[i].lbl = -1; lv[i].valid = false; lv[i].swept = false; lv[i].from = NAI;
         lv[i].kind = (i == LV_ASH || i == LV_LOH || i == LV_PDH) ? LK_HIGH : (i == LV_ASL || i == LV_LOL || i == LV_PDL) ? LK_LOW : LK_MID;
        }
      for(int k = 0; k < 2; k++)
        {
         sesIn[k] = false; sesH[k] = sesL[k] = NA; sesHB[k] = sesLB[k] = sesStart[k] = NAI; sesBox[k] = sesLbl[k] = -1;
         pr[k] = false; prBar[k] = prExp[k] = prExtBar[k] = NAI; prInv[k] = -1; prLvl[k] = -1; prExt[k] = NA;
        }
      curD1 = -1; nyDay = -1;
      glKey = -1; glH = glL = NA; pmIn = false; pmH = pmL = NA;
      ArrayFree(fvg); ArrayFree(phV); ArrayFree(plV); ArrayFree(phB); ArrayFree(plB);
      ArrayFree(tgL); ArrayFree(tgT);
     }

   void CopyFrom(const CState &o)
     {
      CopyArr(lines, o.lines); CopyArr(boxes, o.boxes); CopyArr(labels, o.labels);
      liveL = o.liveL; oldL = o.oldL; liveB = o.liveB; oldB = o.oldB; liveT = o.liveT; oldT = o.oldT;
      for(int i = 0; i < NLVL; i++) lv[i] = o.lv[i];
      for(int k = 0; k < 2; k++)
        {
         sesIn[k] = o.sesIn[k]; sesH[k] = o.sesH[k]; sesL[k] = o.sesL[k]; sesHB[k] = o.sesHB[k]; sesLB[k] = o.sesLB[k];
         sesStart[k] = o.sesStart[k]; sesBox[k] = o.sesBox[k]; sesLbl[k] = o.sesLbl[k];
         pr[k] = o.pr[k]; prBar[k] = o.prBar[k]; prExp[k] = o.prExp[k]; prExtBar[k] = o.prExtBar[k];
         prInv[k] = o.prInv[k]; prLvl[k] = o.prLvl[k]; prExt[k] = o.prExt[k];
        }
      curD1 = o.curD1; nyDay = o.nyDay;
      glKey = o.glKey; glH = o.glH; glL = o.glL; pmIn = o.pmIn; pmH = o.pmH; pmL = o.pmL;
      CopyArr(fvg, o.fvg); CopyArr(phV, o.phV); CopyArr(plV, o.plV); CopyArr(phB, o.phB); CopyArr(plB, o.plB);
      CopyArr(tgL, o.tgL); CopyArr(tgT, o.tgT);
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
  };

//+------------------------------------------------------------------+
//| Données des unités supérieures (ici : D1 pour PDH / PDL)         |
//+------------------------------------------------------------------+
class CHtf
  {
public:
   ENUM_TIMEFRAMES tf;
   datetime T[]; double O[], H[], L[], C[];
   int      n;
   bool     ok;
   //--- need : heure de la première bougie du graphique, que ces données doivent couvrir
   bool Load(datetime from, datetime need)
     {
      MqlRates r[];
      int k = CopyRates(_Symbol, tf, from, TimeCurrent() + PeriodSeconds(tf), r);
      if(k <= 0) return false;           // données pas prêtes : on garde les précédentes
      n = k;
      ArrayResize(T, n); ArrayResize(O, n); ArrayResize(H, n); ArrayResize(L, n); ArrayResize(C, n);
      for(int i = 0; i < n; i++) { T[i] = r[i].time; O[i] = r[i].open; H[i] = r[i].high; L[i] = r[i].low; C[i] = r[i].close; }
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
  };

//--- Données du graphique (fenêtre de InpMaxBars bougies, indice 0 = la plus ancienne)
double   gO[], gH[], gL[], gC[], gATR[];
datetime gT[];
int      gN = 0, gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
CState   gCommit, gWork;
CHtf     gD1;
double   gDpi = 1.0;
double   gFib[];
int      gSrvOff = 0;          // décalage serveur - UTC (secondes)
int      gNyNow  = -300;       // décalage New York - UTC actuel (minutes)
int      gGlobalStart = 1080;  // début du jour Global (minutes NY)

//--- Canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0, gLastWork = 0;
bool     gDirty = false;

//+------------------------------------------------------------------+
string LvName(int i)
  {
   return i == LV_ASH ? "Asia H" : i == LV_ASL ? "Asia L" : i == LV_LOH ? "London H" : i == LV_LOL ? "London L"
        : i == LV_PDH ? "PDH" : i == LV_PDL ? "PDL" : i == LV_PD50 ? "PD50" : "TDO";
  }
bool LvShow(int i)
  {
   return (i == LV_ASH || i == LV_ASL) ? ShowAsia : (i == LV_LOH || i == LV_LOL) ? ShowLondon
        : i == LV_PDH ? ShowPDH : i == LV_PDL ? ShowPDL : i == LV_PD50 ? ShowPD50 : ShowTDO;
  }
color LvColor(int i)
  {
   return (i == LV_ASH || i == LV_ASL) ? AsiaColor : (i == LV_LOH || i == LV_LOL) ? LondonColor : i == LV_TDO ? TdoColor : DailyColor;
  }

//--- « -0.236,-0.5 » ou « -0,236;-0,5 »
void ParseFib()
  {
   ArrayFree(gFib);
   string s = FibLevels;
   string p[];
   bool semi = StringFind(s, ";") >= 0;
   int n = StringSplit(s, semi ? ';' : ',', p);
   for(int i = 0; i < n; i++)
     {
      string v = p[i];
      StringTrimLeft(v); StringTrimRight(v);
      if(semi) StringReplace(v, ",", ".");
      if(v == "") continue;
      PushV(gFib, StringToDouble(v));
     }
  }

int HhMm(string s, int def)
  {
   string a[];
   if(StringSplit(s, ':', a) != 2) return def;
   return (int)StringToInteger(a[0]) * 60 + (int)StringToInteger(a[1]);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(PrimeBars < 1 || PushBars < 0 || PivotLen < 1 || AtrLen < 1 || FibLen < 1 || InpMaxBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXP2P_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX P2P");
   gD1.tf = PERIOD_D1;
   ParseFib();
   gGlobalStart = HhMm(GlobalStart, 1080);
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

//--- Séances de Londres et de New York, heure locale, changement d'heure compris
datetime NthSunday(int year, int mon, int nth)      // nth = 0 : dernier dimanche du mois
  {
   MqlDateTime d; d.year = year; d.mon = mon; d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
   datetime first = StructToTime(d);
   MqlDateTime f; TimeToStruct(first, f);
   int sun = (7 - f.day_of_week) % 7;                 // premier dimanche
   if(nth > 0) return first + (sun + 7 * (nth - 1)) * 86400;
   datetime t = first + sun * 86400;
   MqlDateTime n;
   while(true) { TimeToStruct(t + 7 * 86400, n); if(n.mon != mon) break; t += 7 * 86400; }
   return t;
  }
//--- décalage de Londres ou de New York par rapport à UTC (minutes)
int UtcOffsetMin(datetime utc, bool london)
  {
   MqlDateTime u; TimeToStruct(utc, u);
   if(london)
      return (utc >= NthSunday(u.year, 3, 0) + 3600 && utc < NthSunday(u.year, 10, 0) + 3600) ? 60 : 0;
   return (utc >= NthSunday(u.year, 3, 2) + 7 * 3600 && utc < NthSunday(u.year, 11, 1) + 6 * 3600) ? -240 : -300;
  }
//--- heure de Londres et de New York (minutes depuis minuit) d'une heure UTC
int LocalMinutes(datetime utc, bool london)
  {
   MqlDateTime u; TimeToStruct(utc, u);
   int m = u.hour * 60 + u.min + UtcOffsetMin(utc, london);
   return (m + 1440) % 1440;
  }
bool InHours(int m, string hours)                    // « 08:00-11:00 »
  {
   string p[];
   if(StringSplit(hours, '-', p) != 2) return true;
   string a[], b[];
   if(StringSplit(p[0], ':', a) != 2 || StringSplit(p[1], ':', b) != 2) return true;
   int s = (int)StringToInteger(a[0]) * 60 + (int)StringToInteger(a[1]);
   int e = (int)StringToInteger(b[0]) * 60 + (int)StringToInteger(b[1]);
   return s <= e ? (m >= s && m < e) : (m >= s || m < e);
  }
//--- barClose : heure du serveur de la clôture de la bougie
bool InSession(datetime barClose)
  {
   if(!AlSessions) return true;
   int offset = (int)MathRound((double)(TimeCurrent() - TimeGMT()) / 1800.0) * 1800;   // décalage du serveur
   datetime utc = barClose - offset;
   return (AlLondon && InHours(LocalMinutes(utc, true), AlLondonHours))
       || (AlNewYork && InHours(LocalMinutes(utc, false), AlNYHours));
  }

//--- heure de New York d'une heure du serveur. Serveur à l'heure d'été américaine (FundedNext :
//    UTC+2 l'hiver, UTC+3 l'été) : écart constant avec New York, mesuré maintenant. Sinon :
//    passage par UTC avec le décalage actuel du serveur.
datetime NyTime(datetime srv)
  {
   if(SrvUsDst) return srv - gSrvOff + gNyNow * 60;
   datetime utc = srv - gSrvOff;
   return utc + UtcOffsetMin(utc, false) * 60;
  }
int  NyMin(datetime ny) { return (int)(((long)ny % 86400) / 60); }

//+------------------------------------------------------------------+
//| 1. Contexte : niveaux de séance et quotidiens                    |
//+------------------------------------------------------------------+
//--- nouveau niveau i : l'ancien s'arrête là, le nouveau part de x1 et suit le prix
void SetLevel(CState &S, int i, double price, int x1, int t)
  {
   if(S.lv[i].valid && !S.lv[i].swept && S.LOk(S.lv[i].line)) S.lines[S.lv[i].line].x2 = t;
   S.LabelDel(S.lv[i].lbl);
   S.lv[i].price = price; S.lv[i].valid = true; S.lv[i].swept = false; S.lv[i].from = t;
   S.lv[i].line = -1; S.lv[i].lbl = -1;
   if(!LvShow(i)) return;
   uint c = A(LvColor(i), 0);
   S.lv[i].line = S.LineNew(x1, price, t, price, c, i <= LV_LOL ? (int)sol : (int)LevelStyle, false);
   if(LevelLabels)
      S.lv[i].lbl = S.LabelNew(t, price, LvName(i), 0, c, LS_LEFT, tiny, false, false);
  }

void DayRefs(CState &S, int t, datetime ny)
  {
   //--- PDH / PDL / PD50 : bougie D1 précédente, entièrement clôturée (pas de lookahead)
   int d = gD1.ok ? gD1.Find(gT[t]) : -1;
   if(d >= 1 && d != S.curD1)
     {
      S.curD1 = d;
      double ph = gD1.H[d - 1], pl = gD1.L[d - 1];
      SetLevel(S, LV_PDH, ph, t, t);
      SetLevel(S, LV_PDL, pl, t, t);
      SetLevel(S, LV_PD50, (ph + pl) / 2, t, t);
     }
   //--- True Day Open : ouverture de la première bougie après 00:00 NY
   long day = (long)(ny / 86400);
   if(day != S.nyDay)
     {
      if(S.nyDay >= 0 && NyMin(ny) < 360)          // pas l'ouverture du dimanche 18:00
         SetLevel(S, LV_TDO, gO[t], t, t);
      S.nyDay = day;
     }
  }

void Sessions(CState &S, int t, int m)
  {
   for(int k = 0; k < 2; k++)
     {
      bool inS = InHours(m, k == 0 ? AsiaHours : LondonHours);
      bool gap = t > 0 && gT[t] - gT[t - 1] > 4 * 3600;
      bool show = k == 0 ? ShowAsia : ShowLondon;
      color col = k == 0 ? AsiaColor : LondonColor;
      //--- fin de séance : ses extrêmes deviennent des niveaux de liquidité
      if(S.sesIn[k] && (!inS || gap))
        {
         SetLevel(S, k == 0 ? LV_ASH : LV_LOH, S.sesH[k], S.sesHB[k], t);
         SetLevel(S, k == 0 ? LV_ASL : LV_LOL, S.sesL[k], S.sesLB[k], t);
         S.sesIn[k] = false;
        }
      if(!inS) continue;
      if(!S.sesIn[k])
        {
         S.sesIn[k] = true; S.sesStart[k] = t;
         S.sesH[k] = gH[t]; S.sesL[k] = gL[t]; S.sesHB[k] = S.sesLB[k] = t;
         S.sesBox[k] = S.sesLbl[k] = -1;
         if(show)
           {
            S.sesBox[k] = S.BoxNew(t, gH[t], t, gL[t], A(col, SessBoxTransp), A(col, 60), 1, false, false);
            S.sesLbl[k] = S.LabelNew(t, gH[t], k == 0 ? "Asia" : "London", 0, A(col, 0), LS_DOWN, tiny, false, false);
           }
        }
      else
        {
         if(gH[t] > S.sesH[k]) { S.sesH[k] = gH[t]; S.sesHB[k] = t; }
         if(gL[t] < S.sesL[k]) { S.sesL[k] = gL[t]; S.sesLB[k] = t; }
        }
      if(S.BOk(S.sesBox[k])) { S.boxes[S.sesBox[k]].x2 = t; S.boxes[S.sesBox[k]].top = S.sesH[k]; S.boxes[S.sesBox[k]].bot = S.sesL[k]; }
      if(S.TOk(S.sesLbl[k])) { S.labels[S.sesLbl[k]].x = (S.sesStart[k] + t) / 2.0; S.labels[S.sesLbl[k]].y = S.sesH[k]; }
     }
  }

//--- Plages des projections : Global (depuis le début du jour de trading) et Pré-marché
void Ranges(CState &S, int t, datetime ny, int m)
  {
   long key = (long)((ny - gGlobalStart * 60) / 86400);
   if(key != S.glKey) { S.glKey = key; S.glH = gH[t]; S.glL = gL[t]; }
   else { S.glH = MathMax(S.glH, gH[t]); S.glL = MathMin(S.glL, gL[t]); }
   bool inP = InHours(m, PreHours);
   if(inP && !S.pmIn) { S.pmH = gH[t]; S.pmL = gL[t]; }
   else if(inP) { S.pmH = MathMax(S.pmH, gH[t]); S.pmL = MathMin(S.pmL, gL[t]); }
   S.pmIn = inP;
  }

//--- Prolonge les niveaux encore intacts jusqu'à la bougie en cours
void ExtendLevels(CState &S, int t)
  {
   for(int i = 0; i < NLVL; i++)
     {
      if(!S.lv[i].valid || S.lv[i].swept) continue;
      if(S.LOk(S.lv[i].line)) S.lines[S.lv[i].line].x2 = t;
      if(S.TOk(S.lv[i].lbl)) S.labels[S.lv[i].lbl].x = t;
     }
  }

//--- Pivots (swings) confirmés, pour le MSS
void Pivots(CState &S, int t)
  {
   if(PivotHigh(t, PivotLen)) { PushV(S.phV, gH[t - PivotLen]); PushV(S.phB, t - PivotLen); }
   if(PivotLow(t, PivotLen))  { PushV(S.plV, gL[t - PivotLen]); PushV(S.plB, t - PivotLen); }
   if(ArraySize(S.phV) > 100) { RemoveAt(S.phV, 0); RemoveAt(S.phB, 0); }
   if(ArraySize(S.plV) > 100) { RemoveAt(S.plV, 0); RemoveAt(S.plB, 0); }
  }
//--- dernier swing formé avant la bougie bar (l'extrême du balayage)
int LastPivotBefore(const int &b[], int bar)
  {
   for(int i = ArraySize(b) - 1; i >= 0; i--)
      if(b[i] < bar) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| 2. Zone testée : état amorcé                                     |
//+------------------------------------------------------------------+
void PrimeSide(CState &S, int d, int t, int i)
  {
   bool sell = d == 1;
   if(!S.pr[d])
     {
      S.pr[d] = true; S.prBar[d] = t; S.prInv[d] = -1;
      S.prExt[d] = sell ? gH[t] : gL[t]; S.prExtBar[d] = t;
      if(ShowPrime)
         S.LabelNew(t, sell ? gH[t] : gL[t], sell ? "▼" : "▲", 0, A(PC_GRAY, 0), sell ? LS_DOWN : LS_UP, tiny, false, true);
     }
   S.prExp[d] = t + PrimeBars;            // un nouveau contact prolonge l'état
   S.prLvl[d] = i;
   Ev(AlPrime, (sell ? "Amorcé vente : " : "Amorcé achat : ") + LvName(i) + " " + Px2(S.lv[i].price));
  }

void Primes(CState &S, int t)
  {
   //--- expiration
   for(int d = 0; d < 2; d++)
      if(S.pr[d] && t > S.prExp[d]) { S.pr[d] = false; S.prInv[d] = -1; }
   //--- contact avec un niveau intact : niveau haut -> vente, niveau bas -> achat,
   //    PD50 / TDO -> selon le côté d'où vient le prix
   for(int i = 0; i < NLVL; i++)
     {
      if(!S.lv[i].valid || S.lv[i].swept || S.lv[i].from >= t || t < 1) continue;
      if(!LvShow(i) && !HiddenPrime) continue;
      double p = S.lv[i].price;
      int d = -1;
      if(S.lv[i].kind == LK_HIGH && gH[t] >= p) d = 1;
      else if(S.lv[i].kind == LK_LOW && gL[t] <= p) d = 0;
      else if(S.lv[i].kind == LK_MID)
        {
         if(gC[t - 1] < p && gH[t] >= p) d = 1;
         else if(gC[t - 1] > p && gL[t] <= p) d = 0;
        }
      if(d < 0) continue;
      S.lv[i].swept = true;                // le niveau ne sert qu'une fois
      if(S.LOk(S.lv[i].line)) S.lines[S.lv[i].line].x2 = t;
      if(S.TOk(S.lv[i].lbl)) S.labels[S.lv[i].lbl].x = t;
      PrimeSide(S, d, t, i);
     }
   //--- extrême du balayage ; un nouvel extrême annule une inversion antérieure
   if(S.pr[1] && gH[t] > S.prExt[1]) { S.prExt[1] = gH[t]; S.prExtBar[1] = t; S.prInv[1] = -1; }
   if(S.pr[0] && gL[t] < S.prExt[0]) { S.prExt[0] = gL[t]; S.prExtBar[0] = t; S.prInv[0] = -1; }
  }

//+------------------------------------------------------------------+
//| 3. FVG : cycle de vie et inversion                               |
//+------------------------------------------------------------------+
bool SizeOk(double size, int t)
  {
   double k = 1.0;
   if(FvgSizeMode == Size_ATR)
     {
      if(gATR[t] == NA) return false;
      k = gATR[t];
     }
   if(size < FvgMin * k) return false;
   if(FvgMax > 0 && size > FvgMax * k) return false;
   return true;
  }

void Fvgs(CState &S, int t)
  {
   //--- comblé = clôture au-delà du bord opposé ; c'est aussi l'inversion
   for(int i = 0; i < ArraySize(S.fvg); i++)
     {
      if(!S.fvg[i].active) continue;
      bool bull = S.fvg[i].dir == 1;
      bool mit = bull ? gC[t] < S.fvg[i].bot : gC[t] > S.fvg[i].top;
      int  bx = S.fvg[i].box;
      if(!mit) { if(S.BOk(bx)) S.boxes[bx].x2 = t; continue; }
      S.fvg[i].active = false;
      //--- iFVG : FVG opposé formé pendant la poussée vers le niveau, clôture franche (bougie
      //    dans le sens du retournement)
      int d = bull ? 1 : 0;
      bool candle = bull ? gC[t] < gO[t] : gC[t] > gO[t];
      if(S.pr[d] && candle && S.fvg[i].born >= S.prBar[d] - PushBars && S.fvg[i].born <= S.prExtBar[d])
        {
         S.fvg[i].inv = true;
         S.prInv[d] = t;
        }
      if(S.BOk(bx))
        {
         S.boxes[bx].x2 = t;
         if(S.fvg[i].inv)
           { S.boxes[bx].bg = A(bull ? SellColor : BuyColor, FvgTransp - 10); S.boxes[bx].bd = A(bull ? SellColor : BuyColor, 40); S.boxes[bx].bw = 1; }
         else if(ShowMitig)
            S.boxes[bx].bg = A(bull ? FvgBullColor : FvgBearColor, FvgMitTransp);
         else
            S.BoxDel(bx);
        }
     }
   //--- nouveaux FVG (bougies t-2, t-1, t)
   if(t >= 2)
     {
      bool bull = gL[t] > gH[t - 2] && SizeOk(gL[t] - gH[t - 2], t);
      bool bear = gH[t] < gL[t - 2] && SizeOk(gL[t - 2] - gH[t], t);
      if(bull || bear)
        {
         SFvg f;
         f.born = t; f.x1 = t - 2; f.dir = bull ? 1 : -1; f.active = true; f.inv = false; f.box = -1;
         f.top = bull ? gL[t] : gL[t - 2];
         f.bot = bull ? gH[t - 2] : gH[t];
         if(ShowFvg)
            f.box = S.BoxNew(t - 2, f.top, t, f.bot, A(bull ? FvgBullColor : FvgBearColor, FvgTransp), 0, 0, false, false);
         Push(S.fvg, f);
        }
     }
   //--- ménage : FVG comblés anciens, et pas plus de 300 suivis
   for(int i = ArraySize(S.fvg) - 1; i >= 0; i--)
      if(!S.fvg[i].active && S.fvg[i].born < t - 300) RemoveAt(S.fvg, i);
   while(ArraySize(S.fvg) > 300) { S.BoxDel(S.fvg[0].box); RemoveAt(S.fvg, 0); }
  }

//+------------------------------------------------------------------+
//| 4-5. MSS, filtre ATR, signal et cibles                           |
//+------------------------------------------------------------------+
string FmtLvl(double v)
  {
   string s = DoubleToString(v, 3);
   while(StringLen(s) > 1 && StringSubstr(s, StringLen(s) - 1) == "0") s = StringSubstr(s, 0, StringLen(s) - 1);
   if(StringSubstr(s, StringLen(s) - 1) == ".") s = StringSubstr(s, 0, StringLen(s) - 1);
   return s;
  }

void TargetLine(CState &S, int t, double price, uint c, int style, string text)
  {
   PushV(S.tgL, S.LineNew(t, price, t + FibLen, price, c, style, false));
   PushV(S.tgT, S.LabelNew(t + FibLen, price, text, 0, c, LS_LEFT, tiny, false, false));
  }

void Targets(CState &S, int d, int t)
  {
   bool buy = d == 0;
   if(!FibKeep)
     {
      for(int i = 0; i < ArraySize(S.tgL); i++) S.LineDel(S.tgL[i]);
      for(int i = 0; i < ArraySize(S.tgT); i++) S.LabelDel(S.tgT[i]);
      ArrayFree(S.tgL); ArrayFree(S.tgT);
     }
   uint c = A(buy ? BuyColor : SellColor, 0);
   //--- extensions de Fibonacci : 0 = bord de la plage côté objectif, 1 = bord opposé
   double hi = FibRange == Range_Global ? S.glH : S.pmH;
   double lo = FibRange == Range_Global ? S.glL : S.pmL;
   if(ShowFib && hi != NA && lo != NA && hi > lo)
     {
      double a0 = buy ? hi : lo, a1 = buy ? lo : hi;
      for(int k = 0; k < ArraySize(gFib); k++)
        {
         double p = a0 + gFib[k] * (a1 - a0);
         TargetLine(S, t, p, c, dsh, FmtLvl(gFib[k]) + " (" + Px2(p) + ")");
        }
     }
   //--- cible alternative : liquidité opposée la plus proche
   if(AltTarget == Alt_Liquidity || AltTarget == Alt_Both)
     {
      int best = -1; double bd = 0;
      for(int i = 0; i < NLVL; i++)
        {
         if(!S.lv[i].valid || S.lv[i].swept) continue;
         if(S.lv[i].kind == (buy ? LK_LOW : LK_HIGH)) continue;
         double dist = buy ? S.lv[i].price - gC[t] : gC[t] - S.lv[i].price;
         if(dist <= 0) continue;
         if(best < 0 || dist < bd) { best = i; bd = dist; }
        }
      if(best >= 0) TargetLine(S, t, S.lv[best].price, A(LvColor(best), 0), dot, "TP " + LvName(best));
     }
   //--- cible alternative : FVG opposé actif le plus proche
   if(AltTarget == Alt_Fvg || AltTarget == Alt_Both)
     {
      int best = -1; double bd = 0;
      for(int i = 0; i < ArraySize(S.fvg); i++)
        {
         if(!S.fvg[i].active || S.fvg[i].dir != (buy ? -1 : 1)) continue;
         double dist = buy ? S.fvg[i].bot - gC[t] : gC[t] - S.fvg[i].top;
         if(dist <= 0) continue;
         if(best < 0 || dist < bd) { best = i; bd = dist; }
        }
      if(best >= 0) TargetLine(S, t, buy ? S.fvg[best].bot : S.fvg[best].top, A(buy ? FvgBearColor : FvgBullColor, 0), dot, "TP FVG");
     }
  }

void Signals(CState &S, int t, bool confirmed)
  {
   if(OnClose && !confirmed) return;
   double atr = gATR[t];
   for(int d = 0; d < 2; d++)
     {
      if(!S.pr[d] || S.prInv[d] < 0 || t > S.prExp[d]) continue;
      bool buy = d == 0;
      //--- MSS : clôture au-delà du dernier swing formé avant l'extrême
      double piv = NA; int pivB = NAI;
      if(UseMss)
        {
         int k = buy ? LastPivotBefore(S.phB, S.prExtBar[d]) : LastPivotBefore(S.plB, S.prExtBar[d]);
         if(k < 0) continue;
         piv = buy ? S.phV[k] : S.plV[k]; pivB = buy ? S.phB[k] : S.plB[k];
         if(buy ? gC[t] <= piv : gC[t] >= piv) continue;
        }
      //--- filtre ATR : ampleur de la reprise >= AtrPct % de l'ATR
      if(atr == NA) continue;
      double move = AtrMode == Atr_Body ? (buy ? gC[t] - gO[t] : gO[t] - gC[t])
                                        : (buy ? gC[t] - S.prExt[d] : S.prExt[d] - gC[t]);
      if(move < AtrPct / 100.0 * atr) continue;
      //--- signal
      if(UseMss && ShowMss)
        {
         uint mc = A(buy ? BuyColor : SellColor, 0);
         S.LineNew(pivB, piv, t, piv, mc, dsh, false);
         S.LabelNew((pivB + t) / 2.0, piv, "MSS", 0, mc, buy ? LS_DOWN : LS_UP, tiny, false, false);
        }
      S.LabelNew(t, buy ? gL[t] : gH[t], buy ? "BUY" : "SELL", A(buy ? BuyColor : SellColor, 0), A(PC_WHITE, 0),
                 buy ? LS_UP : LS_DOWN, SigSize, false, false);
      Targets(S, d, t);
      Ev(AlSignal, (buy ? "BUY" : "SELL") + string(" après ") + LvName(S.prLvl[d]) + " " + Px2(gC[t]));
      S.pr[d] = false; S.prInv[d] = -1;
     }
  }

//+------------------------------------------------------------------+
//| Une exécution du calcul sur la bougie t                          |
//+------------------------------------------------------------------+
void ProcessBar(CState &S, int t, bool confirmed)
  {
   gCurBar = t;
   datetime ny = NyTime(gT[t]);
   int m = NyMin(ny);
   DayRefs(S, t, ny);
   Sessions(S, t, m);
   Ranges(S, t, ny, m);
   Pivots(S, t);
   ExtendLevels(S, t);
   Primes(S, t);
   Fvgs(S, t);
   Signals(S, t, confirmed);
  }

//+------------------------------------------------------------------+
bool LoadHtf()
  {
   datetime from = gT[0];
   return gD1.Load(from - 10 * 86400, from);
  }

void ServerOffsets()
  {
   gSrvOff = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 1800.0) * 1800;
   gNyNow  = UtcOffsetMin(TimeGMT(), false);
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
      for(int i = 0; i < gN; i++)
        { gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i]; gT[i] = time[gBase + i]; }
      Atr(gATR, AtrLen, 0);
      gTotal = rates_total;
      ServerOffsets();
      if(!LoadHtf())
        {
         gProcessed = -2;              // D1 en téléchargement : la minuterie recommence
         if(gCvOk) { gCv.Erase(0); gCv.Update(true); }   // pas de dessin périmé en attendant
         return rates_total;
        }
      gCommit.Reset();
      gProcessed = 0;
     }
   else
     {
      int from = gN - 1;
      gN = rates_total - gBase;
      ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gT, gN);
      for(int i = from; i < gN; i++)
        { gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i]; gT[i] = time[gBase + i]; }
      Atr(gATR, AtrLen, from);
      if(gProcessed == -2)
        {
         gTotal = rates_total;
         return rates_total;           // calcul complet en attente des données (OnTimer)
        }
      if(gN - 1 > gProcessed)
         LoadHtf();                    // nouvelle bougie : D1 à jour
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
   if(!InSession(bar + gPer)) return;
   string tf = gPer < 3600 ? "M" + IntegerToString(gPer / 60) : gPer < 86400 ? "H" + IntegerToString(gPer / 3600)
               : gPer == 86400 ? "D1" : gPer == 604800 ? "W1" : "MN1";
   string txt = "CX P2P " + _Symbol + " " + tf + " " + TimeToString(bar, TIME_MINUTES) + " : " + msg;
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

//--- Données D1 arrivées après le premier calcul (week-end, premier lancement) :
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
   gCommit.Reset();
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
   gCv.Update(true);
   gLastRender = GetTickCount();
   gDirty = false;
  }
//+------------------------------------------------------------------+
