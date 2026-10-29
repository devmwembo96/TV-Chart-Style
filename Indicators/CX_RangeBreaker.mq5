//+------------------------------------------------------------------+
//| CX_RangeBreaker.mq5                                              |
//| CX Range Breaker : système de compression de volatilité.         |
//| Réalisation originale d'après une description publique (aucun   |
//| code d'origine). Détecte les ranges serrés par rapport à l'ATR,  |
//| les élargit tant que le prix ne clôture pas dehors avec élan,    |
//| puis signale les cassures (momentum) et les fausses cassures     |
//| (mèche hors de la boîte, clôture dedans, confirmées).            |
//| Volume : XAUUSD n'a pas de volume réel sur MT5 ; le filtre de    |
//| volume utilise le volume en ticks (tick_volume).                 |
//| Dessin en CCanvas : transparence, police Trebuchet MS et limite  |
//| de 500 objets par type comme TradingView.                        |
//| Alertes multi-unités : le même calcul tourne en arrière-plan sur |
//| chaque unité de la liste (M1 à D1 par défaut), à toute heure,    |
//| quelle que soit l'unité du graphique.                            |
//+------------------------------------------------------------------+
#property copyright   "CX Range Breaker"
#property version     "1.01"
#property description "CX Range Breaker : ranges de compression (ATR), boîte dynamique, cassures avec volume et retournements sur mèche."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

enum ENUM_LSTYLE { sol = 0, dsh = 1, dot = 2 };
enum ENUM_TSIZE  { tiny = 0, small = 1, normal = 2 };
enum ENUM_RBPRESET
  {
   Tight   = 0,   // Tight Ranges (scalping)
   Normal  = 1,   // Normal Ranges (intraday)
   Swing   = 2,   // Swing Trading (plusieurs jours)
   Options = 3,   // Options Selling (longs ranges)
   Custom  = 4    // Custom (réglages manuels ci-dessous)
  };

input group "Préréglage"
input ENUM_RBPRESET InpPreset = Normal;   // Préréglage
input group "Réglages manuels (préréglage Custom)"
input int    InpLen     = 20;     // Longueur du range (bougies)
input int    InpAtrLen  = 50;     // Longueur de l'ATR
input double InpThr     = 2.5;    // Seuil : (plus haut - plus bas) < ATR × seuil
input double InpBuf     = 0.15;   // Tampon de cassure (× ATR)
input group "Logique du range"
input double InpExpandMax = 1.75; // Élargissement maximal (× hauteur de détection maximale)
input double InpWickMin   = 0.50; // Mèche de rejet minimale (part de la bougie)
input bool   InpOnClose   = true; // Signaux validés à la clôture de bougie (sans scintillement)
input group "Volume (volume en ticks)"
input bool   InpVolFilter = false; // Confirmer les cassures par un pic de volume
input double InpVolMult   = 1.7;   // Pic : volume > moyenne × k
input int    InpVolLen    = 20;    // Longueur de la moyenne de volume
input group "Boîte"
input bool        ShowBox      = true;            // Afficher les boîtes
input color       BoxColor     = C'41,98,255';    // Couleur du fond
input int         BoxTransp    = 88;              // Transparence du fond
input color       BorderColor  = C'41,98,255';    // Couleur du bord
input int         BorderTransp = 40;              // Transparence du bord
input int         BorderWidth  = 1;               // Épaisseur du bord (0 = sans)
input bool        ShowMid      = true;            // Afficher le milieu
input color       MidColor     = C'120,123,134';  // Couleur du milieu
input ENUM_LSTYLE MidStyle     = dsh;             // Style du milieu
input bool        ColorBroken  = true;            // Colorer la boîte cassée (haussière / baissière)
input group "Signaux"
input bool       ShowBreak  = true;               // Afficher les cassures (Breakout / Vol Break)
input bool       ShowWick   = true;               // Afficher les retournements (Wick Rev)
input color      BullColor  = C'8,153,129';       // Couleur haussière
input color      BearColor  = C'242,54,69';       // Couleur baissière
input int        WickTransp = 30;                 // Transparence des étiquettes Wick Rev
input ENUM_TSIZE LabelSize  = small;              // Taille des étiquettes
input group "Alertes (à la clôture de la bougie)"
input bool   AlPopup       = true;            // Fenêtre et son MT5
input bool   AlPush        = true;            // Notification mobile (MetaQuotes ID)
input bool   AlMultiTf     = true;            // Alertes sur toutes les unités de la liste (pas seulement celle du graphique)
input string AlTfList      = "M1,M5,M15,M30,H1,H4,D1"; // Unités surveillées (séparées par des virgules)
input int    AlTfBars      = 1500;            // Bougies calculées par unité surveillée
input bool   AlRange       = true;            // Range détecté
input bool   AlBreak       = true;            // Cassure du range (clôture hors de la boîte + tampon)
input bool   AlBreakVol    = true;            // Cassure avec pic de volume
input bool   AlRev         = true;            // Retournement sur mèche confirmé (Wick Rev)
input group "MT5"
input int    InpMaxBars = 5000;               // Bougies calculées (TradingView : 5 000)
input string InpFont    = "Trebuchet MS";     // Police (celle de TradingView)

#define PC_WHITE  C'255,255,255'
#define NA        EMPTY_VALUE
#define MAX_OBJ   500

enum ENUM_LBLSTYLE { LS_DOWN = 0, LS_UP = 1 };

//--- Paramètres effectifs (préréglage ou réglages manuels)
int    gLen = 20, gAtrLen = 50;
double gThr = 2.5, gBuf = 0.15;

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

//--- Objets dessinés (line, box, label de Pine). x : indice local de bougie.
struct DLine  { double x1; double y1; double x2; double y2; uint clr; int style; bool alive; };
struct DBox   { double x1; double top; double x2; double bot; uint bg; uint bd; int bw; bool alive; };
struct DLabel { double x; double y; string text; string sym; uint bg; uint tc; int style; int size; bool alive; };

template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
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
   DLine  lines[];  DBox boxes[];  DLabel labels[];
   int    liveL, oldL, liveB, oldB, liveT, oldT;
   //--- range en cours
   bool   active;
   double top, bot;
   int    left, box, mid;
   int    pUp, pDn;        // bougie d'une mèche de rejet au-dessus / au-dessous, en attente de confirmation
   int    endBar;          // dernière bougie du range précédent (pas de chevauchement)

   void Reset()
     {
      ArrayFree(lines); ArrayFree(boxes); ArrayFree(labels);
      liveL = oldL = liveB = oldB = liveT = oldT = 0;
      active = false; top = bot = NA; left = 0; box = mid = -1; pUp = pDn = -1; endBar = -1;
     }

   void CopyFrom(const CState &o)
     {
      CopyArr(lines, o.lines); CopyArr(boxes, o.boxes); CopyArr(labels, o.labels);
      liveL = o.liveL; oldL = o.oldL; liveB = o.liveB; oldB = o.oldB; liveT = o.liveT; oldT = o.oldT;
      active = o.active; top = o.top; bot = o.bot; left = o.left; box = o.box; mid = o.mid;
      pUp = o.pUp; pDn = o.pDn; endBar = o.endBar;
     }

   //--- TradingView efface le plus ancien objet au-delà de 500 par type
   int LineNew(double x1, double y1, double x2, double y2, uint clr, int style)
     {
      DLine l; l.x1 = x1; l.y1 = y1; l.x2 = x2; l.y2 = y2; l.clr = clr; l.style = style; l.alive = true;
      Push(lines, l); liveL++;
      while(liveL > MAX_OBJ && oldL < ArraySize(lines)) { if(lines[oldL].alive) { lines[oldL].alive = false; liveL--; } oldL++; }
      return ArraySize(lines) - 1;
     }
   int BoxNew(double x1, double top_, double x2, double bot_, uint bg, uint bd, int bw)
     {
      DBox b; b.x1 = x1; b.top = top_; b.x2 = x2; b.bot = bot_; b.bg = bg; b.bd = bd; b.bw = bw; b.alive = true;
      Push(boxes, b); liveB++;
      while(liveB > MAX_OBJ && oldB < ArraySize(boxes)) { if(boxes[oldB].alive) { boxes[oldB].alive = false; liveB--; } oldB++; }
      return ArraySize(boxes) - 1;
     }
   int LabelNew(double x, double y, string text, string sym, uint bg, uint tc, int style, int size)
     {
      DLabel t; t.x = x; t.y = y; t.text = text; t.sym = sym; t.bg = bg; t.tc = tc; t.style = style; t.size = size; t.alive = true;
      Push(labels, t); liveT++;
      while(liveT > MAX_OBJ && oldT < ArraySize(labels)) { if(labels[oldT].alive) { labels[oldT].alive = false; liveT--; } oldT++; }
      return ArraySize(labels) - 1;
     }
   bool LOk(int id) { return id >= 0 && id < ArraySize(lines) && lines[id].alive; }
   bool BOk(int id) { return id >= 0 && id < ArraySize(boxes) && boxes[id].alive; }
  };

//--- Séries calculées : 0 = graphique (fenêtre de InpMaxBars bougies), puis les unités surveillées
//    pour les alertes. Indice local 0 = la plus ancienne bougie.
class CFeed
  {
public:
   double          o[], h[], l[], c[], v[], atr[];
   datetime        t[];
   int             n;
   ENUM_TIMEFRAMES tf;
   int             per;
   bool            ok;       // historique chargé et calculé
   datetime        seen;     // ouverture de la bougie en cours au dernier contrôle
   CState          st;       // état « commit » (unités surveillées)
   CFeed() { n = 0; tf = PERIOD_CURRENT; per = 60; ok = false; seen = 0; }
  };
CFeed    gF[];
int      gK = 0;                       // série en cours de calcul
#define  gO   gF[gK].o
#define  gH   gF[gK].h
#define  gL   gF[gK].l
#define  gC   gF[gK].c
#define  gV   gF[gK].v
#define  gATR gF[gK].atr
#define  gT   gF[gK].t
#define  gN   gF[gK].n
int      gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
uint     gLastFeeds = 0;
CState   gCommit, gWork;
double   gDpi = 1.0;

//--- Canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0, gLastWork = 0;
bool     gDirty = false;

//+------------------------------------------------------------------+
//| Préréglages : longueur, ATR, seuil, tampon                       |
//+------------------------------------------------------------------+
void ApplyPreset()
  {
   switch(InpPreset)
     {
      case Tight:   gLen = 12; gAtrLen = 30;  gThr = 2.0; gBuf = 0.10; break;
      case Normal:  gLen = 20; gAtrLen = 50;  gThr = 2.5; gBuf = 0.15; break;
      case Swing:   gLen = 30; gAtrLen = 100; gThr = 3.5; gBuf = 0.25; break;
      case Options: gLen = 50; gAtrLen = 100; gThr = 4.5; gBuf = 0.30; break;
      default:      gLen = InpLen; gAtrLen = InpAtrLen; gThr = InpThr; gBuf = InpBuf; break;
     }
  }

int OnInit()
  {
   if(InpLen < 3 || InpAtrLen < 1 || InpThr <= 0 || InpBuf < 0 || InpExpandMax < 1.0 || InpWickMin < 0 || InpWickMin > 1
      || InpVolMult <= 0 || InpVolLen < 1 || InpMaxBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   ApplyPreset();
   InitFeeds();
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXRB_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Range Breaker");
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

double Highest(int t, int n) { double v = gH[t]; for(int i = t - n + 1; i < t; i++) v = MathMax(v, gH[i]); return v; }
double Lowest(int t, int n)  { double v = gL[t]; for(int i = t - n + 1; i < t; i++) v = MathMin(v, gL[i]); return v; }

//--- pic de volume : volume de la bougie > k × moyenne des InpVolLen bougies précédentes
bool VolSpike(int t)
  {
   if(t < InpVolLen) return false;
   double s = 0;
   for(int i = t - InpVolLen; i < t; i++) s += gV[i];
   double avg = s / InpVolLen;
   return avg > 0 && gV[t] > avg * InpVolMult;
  }

//--- met à jour la boîte et le milieu du range en cours jusqu'à la bougie t
void UpdateBox(CState &S, int t)
  {
   double m = (S.top + S.bot) / 2.0;
   if(S.BOk(S.box)) { S.boxes[S.box].top = S.top; S.boxes[S.box].bot = S.bot; S.boxes[S.box].x2 = t; }
   if(S.LOk(S.mid)) { S.lines[S.mid].y1 = m; S.lines[S.mid].y2 = m; S.lines[S.mid].x2 = t; }
  }

void StartRange(CState &S, int t, double hh, double ll)
  {
   S.active = true;
   S.top = hh; S.bot = ll; S.left = t - gLen + 1;
   S.pUp = S.pDn = -1;
   S.box = ShowBox ? S.BoxNew(S.left, hh, t, ll, A(BoxColor, BoxTransp), A(BorderColor, BorderTransp), BorderWidth) : -1;
   S.mid = ShowMid ? S.LineNew(S.left, (hh + ll) / 2.0, t, (hh + ll) / 2.0, A(MidColor, 0), (int)MidStyle) : -1;
   Ev(AlRange, "Range détecté " + Px2(ll) + " - " + Px2(hh));
  }

//--- fin du range : dir = 1 cassure haussière, -1 baissière, 0 dissous (volatilité sans clôture décisive)
void EndRange(CState &S, int t, int dir)
  {
   UpdateBox(S, t);
   if(dir != 0 && ColorBroken && S.BOk(S.box))
     {
      color c = dir > 0 ? BullColor : BearColor;
      S.boxes[S.box].bg = A(c, BoxTransp);
      S.boxes[S.box].bd = A(c, BorderTransp);
     }
   S.active = false;
   S.endBar = t;
   S.pUp = S.pDn = -1;
  }

void Breakout(CState &S, int t, int dir)
  {
   bool vs = VolSpike(t);
   if(ShowBreak && (!InpVolFilter || vs))
     {
      color c = dir > 0 ? BullColor : BearColor;
      S.LabelNew(t, dir > 0 ? gL[t] : gH[t], vs ? "Vol Break" : "Breakout", dir > 0 ? "▲" : "▼",
                 A(c, 0), A(PC_WHITE, 0), dir > 0 ? LS_UP : LS_DOWN, (int)LabelSize);
     }
   string side = dir > 0 ? "haussière" : "baissière";
   string lvl  = Px2(dir > 0 ? S.top : S.bot);
   Ev(AlBreak, "Cassure " + side + " du range (" + lvl + ")");
   Ev(AlBreakVol && vs, "Cassure " + side + " avec volume (" + lvl + ")");
   EndRange(S, t, dir);
  }

void WickRev(CState &S, int t, int dir)
  {
   if(ShowWick)
     {
      color c = dir > 0 ? BullColor : BearColor;
      S.LabelNew(t, dir > 0 ? gL[t] : gH[t], "Wick Rev", dir > 0 ? "▲" : "▼",
                 A(c, WickTransp), A(PC_WHITE, 0), dir > 0 ? LS_UP : LS_DOWN, (int)LabelSize);
     }
   Ev(AlRev, "Retournement " + (dir > 0 ? "haussier" : "baissier") + " sur mèche, objectif milieu " + Px2((S.top + S.bot) / 2.0));
  }

//+------------------------------------------------------------------+
//| Une exécution du script sur la bougie t                          |
//+------------------------------------------------------------------+
void ProcessBar(CState &S, int t, bool confirmed)
  {
   gCurBar = t;
   if(t < 1 || gATR[t] == NA) return;
   double atr = gATR[t];
   bool live = !confirmed && InpOnClose;    // bougie en cours sans signal : la boîte s'allonge seulement

//--- 1. Filtre de compression : (plus haut - plus bas) sur gLen bougies < ATR × seuil
   if(!S.active)
     {
      if(live || t < gLen - 1 || t - gLen + 1 <= S.endBar) return;
      double hh = Highest(t, gLen), ll = Lowest(t, gLen);
      if(hh - ll < atr * gThr)
         StartRange(S, t, hh, ll);
      return;
     }
   if(live) { UpdateBox(S, t); return; }

   double buf = atr * gBuf;
//--- 2. Cassure de momentum : clôture hors de la boîte au-delà du tampon
   if(gC[t] > S.top + buf) { Breakout(S, t, 1);  return; }
   if(gC[t] < S.bot - buf) { Breakout(S, t, -1); return; }

   double nTop = S.top, nBot = S.bot;
//--- 3. Mèche de rejet de la bougie précédente : confirmée si la bougie suivante repart vers le milieu,
//       sinon la poussée est acceptée et la boîte s'élargit
   if(S.pUp == t - 1)
     {
      if(gC[t] < gO[t] && gC[t] < gC[t - 1]) WickRev(S, t, -1);
      else nTop = MathMax(nTop, gH[t - 1]);
     }
   if(S.pDn == t - 1)
     {
      if(gC[t] > gO[t] && gC[t] > gC[t - 1]) WickRev(S, t, 1);
      else nBot = MathMin(nBot, gL[t - 1]);
     }
   S.pUp = S.pDn = -1;

//--- 4. Poussée contre un bord sans élan : la boîte s'élargit (sauf mèche de rejet en attente)
   bool upP = gH[t] > S.top, dnP = gL[t] < S.bot;
   double rng = gH[t] - gL[t];
   if(upP)
     {
      bool rej = !dnP && gC[t] <= S.top && rng > 0 && gH[t] - MathMax(gO[t], gC[t]) >= InpWickMin * rng;
      if(rej) S.pUp = t; else nTop = MathMax(nTop, gH[t]);
     }
   if(dnP)
     {
      bool rej = !upP && gC[t] >= S.bot && rng > 0 && MathMin(gO[t], gC[t]) - gL[t] >= InpWickMin * rng;
      if(rej) S.pDn = t; else nBot = MathMin(nBot, gL[t]);
     }
//--- 5. Élargissement trop grand : ce n'est plus une compression, le range se dissout sans signal
   if(nTop - nBot > atr * gThr * InpExpandMax)
     {
      EndRange(S, t, 0);
      return;
     }
   S.top = nTop; S.bot = nBot;
   UpdateBox(S, t);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < 100)
      return 0;
   gK = 0;
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
   ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gV, gN); ArrayResize(gT, gN);
   for(int i = from; i < gN; i++)
     {
      gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i];
      gV[i] = (double)tick_volume[gBase + i]; gT[i] = time[gBase + i];
     }
   Atr(gATR, gAtrLen, from);
   gTotal = rates_total;
   if(full)
     {
      gCommit.Reset();
      gProcessed = 0;
     }
   bool newBar = false;
   while(gProcessed < gN - 1)
     {
      //--- alertes seulement pour les bougies qui clôturent en direct, pas pour l'historique
      gAlertLive = !full && gProcessed >= gN - 3;
      gAlertBuf = "";
      ProcessBar(gCommit, gProcessed, true);
      gAlertLive = false;
      if(gAlertBuf != "")
         SendAlert(gAlertBuf, gT[gProcessed], gPer);
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

string TfName(int per)
  {
   return per < 3600 ? "M" + IntegerToString(per / 60) : per < 86400 ? "H" + IntegerToString(per / 3600)
          : per == 86400 ? "D1" : per == 604800 ? "W1" : "MN1";
  }

void SendAlert(string msg, datetime bar, int per)
  {
   string txt = "CX Range Breaker " + _Symbol + " " + TfName(per) + " " + TimeToString(bar, TIME_MINUTES) + " : " + msg;
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

void OnTimer()
  {
   if(AlMultiTf && GetTickCount() - gLastFeeds >= 1000)
     {
      gLastFeeds = GetTickCount();
      for(int k = 1; k < ArraySize(gF); k++)
         UpdateFeed(k);
      gK = 0;
     }
   if(gDirty && gProcessed >= 0)
      Render(gWork);
  }

//+------------------------------------------------------------------+
//| Unités surveillées pour les alertes (calcul sans dessin)         |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES TfFromName(string name)
  {
   string n = name;
   StringTrimLeft(n); StringTrimRight(n); StringToUpper(n);
   if(n == "M1")  return PERIOD_M1;
   if(n == "M2")  return PERIOD_M2;
   if(n == "M3")  return PERIOD_M3;
   if(n == "M5")  return PERIOD_M5;
   if(n == "M10") return PERIOD_M10;
   if(n == "M15") return PERIOD_M15;
   if(n == "M30") return PERIOD_M30;
   if(n == "H1")  return PERIOD_H1;
   if(n == "H2")  return PERIOD_H2;
   if(n == "H4")  return PERIOD_H4;
   if(n == "H8")  return PERIOD_H8;
   if(n == "D1")  return PERIOD_D1;
   if(n == "W1")  return PERIOD_W1;
   if(n == "MN1") return PERIOD_MN1;
   return PERIOD_CURRENT;
  }

//--- série 0 = graphique ; les unités de la liste autres que celle du graphique s'ajoutent derrière
void InitFeeds()
  {
   ArrayResize(gF, 1);
   gK = 0;
   if(!AlMultiTf) return;
   int cur = PeriodSeconds(PERIOD_CURRENT);
   string parts[];
   int np = StringSplit(AlTfList, ',', parts);
   for(int i = 0; i < np; i++)
     {
      ENUM_TIMEFRAMES tf = TfFromName(parts[i]);
      if(tf == PERIOD_CURRENT) continue;
      int per = PeriodSeconds(tf);
      if(per == cur) continue;                        // l'unité du graphique a déjà ses alertes
      bool dup = false;
      for(int k = 1; k < ArraySize(gF); k++) if(gF[k].per == per) dup = true;
      if(dup) continue;
      int m = ArraySize(gF);
      ArrayResize(gF, m + 1);
      gF[m].tf = tf; gF[m].per = per; gF[m].ok = false; gF[m].seen = 0; gF[m].n = 0;
     }
  }

void SetBar(int i, const MqlRates &r)
  {
   gO[i] = r.open; gH[i] = r.high; gL[i] = r.low; gC[i] = r.close; gV[i] = (double)r.tick_volume; gT[i] = r.time;
  }

void ResizeFeed(int n)
  {
   ArrayResize(gO, n, 256); ArrayResize(gH, n, 256); ArrayResize(gL, n, 256); ArrayResize(gC, n, 256);
   ArrayResize(gV, n, 256); ArrayResize(gT, n, 256);
   gN = n;
  }

//--- historique complet des bougies clôturées, calculé sans alerte
bool LoadFeed(int k)
  {
   MqlRates r[];
   int got = CopyRates(_Symbol, gF[k].tf, 1, MathMax(300, AlTfBars), r);
   if(got < gAtrLen + gLen + 10) return false;
   gK = k;
   ResizeFeed(got);
   for(int i = 0; i < got; i++) SetBar(i, r[i]);
   Atr(gATR, gAtrLen, 0);
   gF[k].st.Reset();
   for(int t = 0; t < got; t++) ProcessBar(gF[k].st, t, true);
   gK = 0;
   return true;
  }

//--- nouvelle bougie sur l'unité k : calcule les bougies clôturées depuis le dernier contrôle
void UpdateFeed(int k)
  {
   ENUM_TIMEFRAMES tf = gF[k].tf;
   datetime cur = iTime(_Symbol, tf, 0);
   if(cur == 0 || cur == gF[k].seen) return;
   if(!gF[k].ok)
     {
      if(LoadFeed(k)) { gF[k].ok = true; gF[k].seen = cur; }
      return;
     }
   MqlRates r[];
   int got = CopyRates(_Symbol, tf, 1, 10, r);
   if(got <= 0) return;
   datetime last = gF[k].t[gF[k].n - 1];
   int first = -1;
   for(int i = 0; i < got; i++) if(r[i].time > last) { first = i; break; }
   gF[k].seen = cur;
   if(first < 0) return;
   if(first == 0 && got == 10)                       // trou dans l'historique : recalcul complet, sans alerte
     {
      gF[k].ok = LoadFeed(k);
      return;
     }
   gK = k;
   int from = gN;
   ResizeFeed(from + got - first);
   for(int i = first; i < got; i++) SetBar(from + i - first, r[i]);
   Atr(gATR, gAtrLen, from);
   for(int t = from; t < gN; t++)
     {
      gAlertLive = t >= gN - 2;                      // seulement les bougies qui viennent de clôturer
      gAlertBuf = "";
      ProcessBar(gF[k].st, t, true);
      gAlertLive = false;
      if(gAlertBuf != "")
         SendAlert(gAlertBuf, gT[t], gF[k].per);
     }
   gK = 0;
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

//--- étiquette à pointe : texte en Trebuchet MS suivi du symbole ▲ / ▼ en Arial
void DrawLabel(const DLabel &lb)
  {
   double ax = XofBar(lb.x);
   if(ax < -300 || ax > gW + 300) return;
   double ay = YofPrice(lb.y);
   if(ay < -100 || ay > gHh + 100) return;
   int tw = 0, th = 0, sw = 0, sh = 0;
   SetFont(lb.size, false);
   gCv.TextSize(lb.text, tw, th);
   if(lb.sym != "") { SetFont(lb.size, true); gCv.TextSize(lb.sym, sw, sh); }
   int gap = lb.sym != "" ? Px(3) : 0;
   int padX = Px(3), padY = Px(1), ph = Px(3);
   int w = tw + gap + sw + 2 * padX, h = MathMax(th, sh) + 2 * padY;
   int iy = (int)MathRound(ay);
   int x1 = (int)MathRound(ax - w / 2.0);
   int top = lb.style == LS_UP ? iy + ph : iy - ph - h;
   if(((lb.bg >> 24) & 0xFF) > 0)
     {
      FillPointer(ax, iy, ph + 1, ph, lb.style == LS_UP ? 1 : -1, lb.bg);
      FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, lb.bg);
     }
   SetFont(lb.size, false);
   gCv.TextOut(x1 + padX, top + h / 2, lb.text, lb.tc, TA_LEFT | TA_VCENTER);
   if(lb.sym != "")
     {
      SetFont(lb.size, true);
      gCv.TextOut(x1 + padX + tw + gap, top + h / 2, lb.sym, lb.tc, TA_LEFT | TA_VCENTER);
     }
  }

void Render(CState &S)
  {
   gK = 0;
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

   //--- boîtes (bord de BorderWidth px)
   for(int i = 0; i < ArraySize(S.boxes); i++)
     {
      if(!S.boxes[i].alive) continue;
      int x1 = (int)MathRound(XofBar(S.boxes[i].x1));
      int x2 = (int)MathRound(XofBar(S.boxes[i].x2));
      if(x2 < x1) { int s = x1; x1 = x2; x2 = s; }
      if(x2 < 0 || x1 > W) continue;
      int y1 = (int)MathRound(YofPrice(MathMax(S.boxes[i].top, S.boxes[i].bot)));
      int y2 = (int)MathRound(YofPrice(MathMin(S.boxes[i].top, S.boxes[i].bot)));
      if(y2 < 0 || y1 > H) continue;
      int bw = S.boxes[i].bw > 0 ? Wpx(S.boxes[i].bw) : 0;
      bool border = bw > 0 && ((S.boxes[i].bd >> 24) & 0xFF) > 0;
      if(border)
        {
         FillRect(x1 + bw, y1 + bw, x2 - bw, y2 - bw, S.boxes[i].bg);
         FillRect(x1, y1, x2, y1 + bw - 1, S.boxes[i].bd);
         FillRect(x1, y2 - bw + 1, x2, y2, S.boxes[i].bd);
         FillRect(x1, y1 + bw, x1 + bw - 1, y2 - bw, S.boxes[i].bd);
         FillRect(x2 - bw + 1, y1 + bw, x2, y2 - bw, S.boxes[i].bd);
        }
      else
         FillRect(x1, y1, x2, y2, S.boxes[i].bg);
     }
   //--- lignes (milieux)
   for(int i = 0; i < ArraySize(S.lines); i++)
     {
      if(!S.lines[i].alive) continue;
      double x1 = MathRound(XofBar(S.lines[i].x1)), x2 = MathRound(XofBar(S.lines[i].x2));
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
