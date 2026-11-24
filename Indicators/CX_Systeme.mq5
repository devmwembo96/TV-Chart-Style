//+------------------------------------------------------------------+
//| CX_Systeme.mq5                                                   |
//| CX Système NAS100 : un seul indicateur, cinq étages.             |
//|  1. BIAIS       structure D1 / H4 / H1 + pression de fond H1     |
//|                 → score −100 … +100, verdict ▲ / ▼ / neutre      |
//|  2. CARTE       niveaux de liquidité à l'heure de New York :     |
//|                 PDH/PDL, PWH/PWL, Asia, London, NY AM, Lunch,    |
//|                 NY PM, opens 00:00 / 08:30 / 09:30, FVG M15 / H1 |
//|  3. DÉCLENCHEUR SFP sur un niveau de la carte → FVG → MSS        |
//|                 + filtre d'épuisement (interrupteur) :           |
//|                 compteur 9 / 13 et Long / Short Covered          |
//|  4. GESTION     entrée, SL derrière la mèche du SFP, TP1/TP2/TP3 |
//|                 sur les niveaux suivants de la carte, SL à       |
//|                 l'entrée après TP1, taille du lot selon le risque|
//|  5. AFFICHAGE   dessin CCanvas façon TradingView, tableau unique,|
//|                 alertes MT5 + téléphone à la clôture             |
//| Indicateur seul : aucun ordre n'est passé.                       |
//| Calcul sur bougies clôturées uniquement (pas de repeinture).     |
//+------------------------------------------------------------------+
#property copyright   "CX Système"
#property version     "1.00"
#property description "CX Système NAS100 : biais multi-UT, carte de liquidité (heure de New York), SFP → FVG → MSS avec filtre d'épuisement, gestion sur niveaux, tableau et alertes."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

enum ENUM_LSTYLE { sol = 0, dsh = 1, dot = 2 };
enum ENUM_TSIZE  { tiny = 0, small = 1, normal = 2 };
enum ENUM_PANPOS { PanTopRight = 0,   // En haut à droite
                   PanTopLeft = 1,    // En haut à gauche
                   PanBottomRight = 2,// En bas à droite
                   PanBottomLeft = 3  // En bas à gauche
                 };

//--- 1. Biais
input group "1. Biais (unités supérieures)"
input bool   InpBiasReq  = true;              // Signaux uniquement dans le sens du biais
input int    InpBiasMin  = 40;                // Score minimal du biais (0–100)
input int    InpBiasPiv  = 3;                 // Force des pivots de structure D1 / H4 / H1
//--- 2. Carte
input group "2. Carte (niveaux, heure de New York)"
input bool   InpSrvUsDst = true;              // Le courtier suit l'heure d'été US (GMT+2 / GMT+3)
input bool   InpShowDay  = true;              // PDH / PDL
input bool   InpShowWeek = true;              // PWH / PWL
input bool   InpShowSess = true;              // Sessions : Asia, London, NY AM, Lunch, NY PM
input bool   InpShowOpen = true;              // Opens 00:00 / 08:30 / 09:30
input bool   InpShowTaken = true;             // Garder les niveaux pris (pointillés pâles)
input bool   InpFvgM15   = true;              // FVG M15 non comblés
input bool   InpFvgH1    = true;              // FVG H1 non comblés
//--- 3. Déclencheur
input group "3. Déclencheur (SFP → FVG → MSS)"
input int    InpMssPiv   = 3;                 // Force des pivots du MSS (graphique)
input int    InpWindow   = 30;                // Bougies max entre le SFP et le MSS
input bool   InpReqExh   = true;              // Exiger l'épuisement (9 / 13 ou Covered)
input int    InpExhLook  = 5;                 // Épuisement : bougies avant le SFP prises en compte
input double InpCovZ     = 2.5;               // Seuil Long / Short Covered (écarts-types)
input bool   InpReqHtfFvg = false;            // Exiger un FVG M15 / H1 sous le SFP
//--- 4. Gestion
input group "4. Gestion (entrée, SL, TP sur niveaux)"
input double InpSlBufAtr = 0.10;              // Marge du SL derrière la mèche (× ATR 14)
input double InpMinTpR   = 0.5;               // Distance minimale du TP1 (en R)
input double InpRiskPct  = 1.0;               // Risque par trade (% du solde)
input int    InpKeepTrades = 5;               // Trades passés affichés
//--- 5. Affichage et alertes
input group "5. Affichage et alertes"
input color  ColBull     = C'8,153,129';      // Haussier
input color  ColBear     = C'242,54,69';      // Baissier
input color  ColDay      = C'76,175,80';      // PDH / PDL
input color  ColWeek     = C'0,188,212';      // PWH / PWL
input color  ColSess     = C'120,123,134';    // Sessions
input color  ColOpen     = C'120,123,134';    // Opens
input color  ColFvg      = C'41,98,255';      // FVG M15 / H1
input ENUM_PANPOS InpPanPos = PanTopRight;    // Position du tableau
input bool   AlPopup     = true;              // Alerte : fenêtre et son MT5
input bool   AlPush      = true;              // Alerte : notification mobile (MetaQuotes ID)
input bool   AlSfp       = false;             // Alerte sur chaque SFP de la carte
input int    InpMaxBars  = 5000;              // Bougies calculées
input string InpFont     = "Trebuchet MS";    // Police

#define NA        EMPTY_VALUE
#define NAI       -1
#define NSLOT     17
#define MAX_MARK  300
#define MAX_HZ    400

//--- emplacements fixes de la carte
#define S_PDH 0
#define S_PDL 1
#define S_PWH 2
#define S_PWL 3
#define S_SES 4       // 4..13 : sessions (haut, bas) × 5
#define S_O00 14
#define S_O830 15
#define S_O930 16

string gSessName[5] = {"Asia", "London", "NY AM", "Lunch", "NY PM"};

uint A(const color c, const int transp)
  {
   return ColorToARGB(c, (uchar)MathRound(255.0 * (100 - MathMax(0, MathMin(100, transp))) / 100.0));
  }
template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
//--- versions par valeur : acceptent une expression (MQL5 refuse un résultat de calcul en référence)
void PushS(string &a[], string v) { int n = ArraySize(a); ArrayResize(a, n + 1, 16); a[n] = v; }
void PushD(double &a[], double v) { int n = ArraySize(a); ArrayResize(a, n + 1, 16); a[n] = v; }
void PushU(uint &a[], uint v)     { int n = ArraySize(a); ArrayResize(a, n + 1, 16); a[n] = v; }

//+------------------------------------------------------------------+
//| Structures                                                       |
//+------------------------------------------------------------------+
struct Slot                       // un niveau de la carte
  {
   string name;
   double price;
   int    x0;                     // bougie de départ (indice local)
   int    kind;                   // 1 = haut (liquidité au-dessus), -1 = bas, 0 = open (cible seulement)
   bool   taken;                  // liquidité prise
   int    xTaken;
   int    grp;                    // 0 jour, 1 semaine, 2 session, 3 open
  };

struct HZone                      // FVG M15 / H1
  {
   datetime ts;                   // ouverture de la 1re bougie
   datetime tc;                   // connu à la clôture de la 3e bougie
   datetime tf;                   // comblé à la clôture de cette bougie (0 = jamais)
   double   top, bot;
   int      dir;
   int      tfMin;
  };

struct Mark                       // repère : ✕ du SFP, texte du MSS, BUY / SELL
  {
   int    x;
   double y;
   string text;
   uint   tc;
   uint   bg;
   int    up;                     // 1 = sous la bougie (pointe vers le haut), 0 = au-dessus
   bool   sym;
  };

struct Seg                        // trait : ligne du MSS
  {
   int    x1, x2;
   double y;
   uint   c;
   int    style;
  };

struct Trade
  {
   int    dir;
   int    x0, x1;                 // bougie du signal, bougie de fin (NAI = en cours)
   double entry, sl, sl0, risk;
   double tp1, tp2, tp3;
   string n1, n2, n3;             // nom du niveau visé
   bool   h1, h2, h3;
   int    status;                 // 0 en cours, 1 TP3, -1 SL, 2 SL à l'entrée, 3 remplacé
   string why;                    // résumé du setup
  };

struct Setup                      // séquence SFP → FVG → MSS d'un côté
  {
   bool   on;
   int    sfpBar;
   double ext;
   string lvl;
   bool   fvg;
   bool   htfFvg;
  };

//+------------------------------------------------------------------+
//| État (bougies clôturées)                                         |
//+------------------------------------------------------------------+
class CState
  {
public:
   Slot   slot[NSLOT];
   Mark   marks[];
   Seg    segs[];
   Trade  trades[];
   Setup  bull, bear;
   //--- jour, semaine, sessions (heure de New York)
   long   curDay, curWeek;
   double dHi, dLo, wHi, wLo;
   int    dStart, wStart;
   int    curSess, sStart, prevMins;
   double sHi, sLo;
   //--- structure du graphique (MSS)
   double swH, swL;
   int    swHB, swLB, trend;
   //--- épuisement
   int    cntDn, cntUp;            // compteur 9 (clôtures plus basses / plus hautes qu'il y a 4 bougies)
   int    cdDn, cdUp;              // compte à rebours 13
   bool   cdDnOn, cdUpOn;
   int    lastBull9, lastBull13, lastBear9, lastBear13, lastShortCov, lastLongCov;
   //--- résumé pour le tableau
   string lastEvent;
   int    lastSigBar;

   void Reset()
     {
      for(int i = 0; i < NSLOT; i++)
        {
         slot[i].name = ""; slot[i].price = NA; slot[i].x0 = NAI; slot[i].kind = 0;
         slot[i].taken = false; slot[i].xTaken = NAI; slot[i].grp = 0;
        }
      ArrayFree(marks); ArrayFree(segs); ArrayFree(trades);
      bull.on = false; bear.on = false;
      curDay = -1; curWeek = -1;
      dHi = wHi = sHi = -DBL_MAX; dLo = wLo = sLo = DBL_MAX;
      dStart = wStart = sStart = 0;
      curSess = -1; prevMins = -1;
      swH = swL = NA; swHB = swLB = NAI; trend = 0;
      cntDn = cntUp = cdDn = cdUp = 0; cdDnOn = cdUpOn = false;
      lastBull9 = lastBull13 = lastBear9 = lastBear13 = lastShortCov = lastLongCov = -100000;
      lastEvent = "—"; lastSigBar = NAI;
     }
  };

//--- données du graphique (indice 0 = la plus ancienne)
double   gO[], gH[], gL[], gC[], gV[];
datetime gT[];
int      gN = 0, gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
CState   gS;
double   gDpi = 1.0;

//--- séries calculées bougie par bougie
double   gAtr[], gBuyE[], gSellE[], gBuyP[], gSellP[], gNetR[], gNetP[], gCore[], gBarNet[];

//--- unités supérieures
datetime gDT[], gH4T[], gH1T[];
int      gDTr[], gH4Tr[], gH1Tr[];
double   gH1Core[];
HZone    gHz[];
bool     gHtfOk = false;
long     gSrvOffNow = 0;

//--- canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0;
bool     gDirty = false;
bool     gAlertLive = false;
string   gAlertBuf = "";

//+------------------------------------------------------------------+
//| Heure de New York                                                |
//+------------------------------------------------------------------+
datetime NthSunday(int y, int m, int n)
  {
   MqlDateTime d; ZeroMemory(d);
   d.year = y; d.mon = m; d.day = 1;
   datetime t = StructToTime(d);
   TimeToStruct(t, d);
   int first = (7 - d.day_of_week) % 7;            // jours jusqu'au 1er dimanche
   return t + (datetime)((first + 7 * (n - 1)) * 86400);
  }

//--- heure d'été US : du 2e dimanche de mars 07:00 UTC au 1er dimanche de novembre 06:00 UTC
bool UsDst(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc, d);
   datetime s = NthSunday(d.year, 3, 2) + 7 * 3600;
   datetime e = NthSunday(d.year, 11, 1) + 6 * 3600;
   return utc >= s && utc < e;
  }

datetime ToUtc(datetime srv)
  {
   long off = gSrvOffNow;
   if(InpSrvUsDst)
      off += (UsDst(srv) ? 3600 : 0) - (UsDst(TimeGMT()) ? 3600 : 0);
   return (datetime)(srv - off);
  }

datetime ToNy(datetime srv)
  {
   datetime u = ToUtc(srv);
   return u - (UsDst(u) ? 4 : 5) * 3600;
  }

string LubTime(datetime srv, bool withDate)
  {
   datetime l = ToUtc(srv) + 2 * 3600;               // Lubumbashi = UTC+2
   return withDate ? TimeToString(l, TIME_DATE | TIME_MINUTES) : TimeToString(l, TIME_MINUTES);
  }

int SessOf(int mins)
  {
   if(mins >= 1080 || mins < 150) return 0;          // Asia 18:00–02:30
   if(mins < 420) return 1;                          // London 02:30–07:00
   if(mins < 690) return 2;                          // NY AM 07:00–11:30
   if(mins < 780) return 3;                          // Lunch 11:30–13:00
   if(mins < 960) return 4;                          // NY PM 13:00–16:00
   return -1;
  }

//+------------------------------------------------------------------+
//| Outils de calcul                                                 |
//+------------------------------------------------------------------+
double Ema(double prev, double x, int len) { return prev == NA ? x : prev + (x - prev) * 2.0 / (len + 1); }

double SmaArr(const double &a[], int t, int len)
  {
   if(t - len + 1 < 0) return NA;
   double s = 0; int n = 0;
   for(int i = t - len + 1; i <= t; i++) { if(a[i] == NA) continue; s += a[i]; n++; }
   return n > 0 ? s / n : NA;
  }

double SdArr(const double &a[], int t, int len)
  {
   if(t - len + 1 < 0) return NA;
   double m = SmaArr(a, t, len);
   if(m == NA) return NA;
   double s = 0; int n = 0;
   for(int i = t - len + 1; i <= t; i++) { if(a[i] == NA) continue; s += (a[i] - m) * (a[i] - m); n++; }
   return n > 1 ? MathSqrt(s / n) : NA;
  }

bool PivotHigh(const double &h[], int t, int len)
  {
   int c = t - len;
   if(c - len < 0) return false;
   for(int i = 1; i <= len; i++)
      if(h[c - i] >= h[c] || h[c + i] > h[c]) return false;
   return true;
  }

bool PivotLow(const double &l[], int t, int len)
  {
   int c = t - len;
   if(c - len < 0) return false;
   for(int i = 1; i <= len; i++)
      if(l[c - i] <= l[c] || l[c + i] < l[c]) return false;
   return true;
  }

//--- dernière bougie d'unité supérieure clôturée à l'instant T
int HtfIdx(const datetime &ts[], int per, datetime T)
  {
   int lo = 0, hi = ArraySize(ts) - 1, r = -1;
   while(lo <= hi)
     {
      int m = (lo + hi) / 2;
      if(ts[m] + per <= T) { r = m; lo = m + 1; }
      else hi = m - 1;
     }
   return r;
  }

//--- indice local de la bougie du graphique qui contient l'instant t
int BarAt(datetime t)
  {
   int lo = 0, hi = gN - 1, r = 0;
   while(lo <= hi)
     {
      int m = (lo + hi) / 2;
      if(gT[m] <= t) { r = m; lo = m + 1; }
      else hi = m - 1;
     }
   return r;
  }

//+------------------------------------------------------------------+
//| Étage 1 : unités supérieures                                     |
//+------------------------------------------------------------------+
//--- tendance de structure (BOS / CHoCH à la clôture) après chaque bougie
void HtfTrend(const MqlRates &r[], int n, int len, int &tr[])
  {
   ArrayResize(tr, n);
   double h[], l[];
   ArrayResize(h, n); ArrayResize(l, n);
   for(int i = 0; i < n; i++) { h[i] = r[i].high; l[i] = r[i].low; }
   double sh = NA, sl = NA;
   int trend = 0;
   for(int t = 0; t < n; t++)
     {
      if(PivotHigh(h, t, len)) sh = h[t - len];
      if(PivotLow(l, t, len))  sl = l[t - len];
      if(sh != NA && r[t].close > sh) { trend = 1;  sh = NA; }
      if(sl != NA && r[t].close < sl) { trend = -1; sl = NA; }
      tr[t] = trend;
     }
  }

//--- pression de fond (Core Trend de CX Press) après chaque bougie
void HtfCore(const MqlRates &r[], int n, double &core[])
  {
   ArrayResize(core, n);
   double v[], bE[], sE[], bP[], sP[], net[];
   ArrayResize(v, n); ArrayResize(bE, n); ArrayResize(sE, n); ArrayResize(bP, n); ArrayResize(sP, n); ArrayResize(net, n);
   double eb = NA, es = NA, pb = NA, ps = NA, cr = NA;
   for(int t = 0; t < n; t++)
     {
      v[t] = (double)r[t].tick_volume;
      double pc = t > 0 ? r[t - 1].close : r[t].open;
      double br = r[t].close - MathMin(r[t].low, pc);
      double sr = MathMax(r[t].high, pc) - r[t].close;
      double vm = SmaArr(v, t, 14);
      double rv = vm != NA && vm > 0 && v[t] > 0 ? MathMin(v[t] / vm, 5.0) : 1.0;
      eb = Ema(eb, br * rv, 14); es = Ema(es, sr * rv, 14);
      bE[t] = eb; sE[t] = es;
      double bb = SmaArr(bE, t, 200), sb = SmaArr(sE, t, 200);
      pb = Ema(pb, bb != NA && bb > 0 ? 200.0 * eb / bb : 0.0, 3);
      ps = Ema(ps, sb != NA && sb > 0 ? 200.0 * es / sb : 0.0, 3);
      bP[t] = pb; sP[t] = ps;
      net[t] = pb - ps;
      double sd = SdArr(net, t, 200);
      double np = sd != NA && sd > 0 ? net[t] / sd * 300.0 : 0.0;
      cr = Ema(cr, np, 50);
      core[t] = cr;
     }
  }

//--- FVG d'une unité supérieure, avec l'instant où ils sont comblés
void HtfFvg(const MqlRates &r[], int n, int per, int tfMin)
  {
   for(int k = 2; k < n; k++)
     {
      int dir = 0;
      double top = 0, bot = 0;
      if(r[k].low > r[k - 2].high && r[k - 1].close > r[k - 2].high) { dir = 1;  top = r[k].low;     bot = r[k - 2].high; }
      if(r[k].high < r[k - 2].low && r[k - 1].close < r[k - 2].low)  { dir = -1; top = r[k - 2].low; bot = r[k].high; }
      if(dir == 0) continue;
      HZone z;
      z.ts = r[k - 2].time; z.tc = r[k].time + per; z.tf = 0;
      z.top = top; z.bot = bot; z.dir = dir; z.tfMin = tfMin;
      for(int j = k + 1; j < n; j++)
         if(dir == 1 ? r[j].low <= bot : r[j].high >= top) { z.tf = r[j].time + per; break; }
      if(gN > 0 && z.tf != 0 && z.tf < gT[0]) continue;
      Push(gHz, z);
     }
  }

bool LoadHtf()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n;
   n = CopyRates(_Symbol, PERIOD_D1, 0, 400, r);
   if(n < 50) return false;
   ArrayResize(gDT, n); for(int i = 0; i < n; i++) gDT[i] = r[i].time;
   HtfTrend(r, n, InpBiasPiv, gDTr);
   n = CopyRates(_Symbol, PERIOD_H4, 0, 1200, r);
   if(n < 50) return false;
   ArrayResize(gH4T, n); for(int i = 0; i < n; i++) gH4T[i] = r[i].time;
   HtfTrend(r, n, InpBiasPiv, gH4Tr);
   ArrayFree(gHz);
   n = CopyRates(_Symbol, PERIOD_H1, 0, 3000, r);
   if(n < 300) return false;
   ArrayResize(gH1T, n); for(int i = 0; i < n; i++) gH1T[i] = r[i].time;
   HtfTrend(r, n, InpBiasPiv, gH1Tr);
   HtfCore(r, n, gH1Core);
   if(InpFvgH1) HtfFvg(r, n, 3600, 60);
   if(InpFvgM15)
     {
      n = CopyRates(_Symbol, PERIOD_M15, 0, 4000, r);
      if(n < 50) return false;
      HtfFvg(r, n, 900, 15);
     }
   return true;
  }

//--- score du biais à l'instant T : D1 30, H4 30, H1 20, pression H1 20
int BiasScore(datetime T, int &d1, int &h4, int &h1, double &core)
  {
   int i;
   i = HtfIdx(gDT, 86400, T);    d1 = i >= 0 ? gDTr[i] : 0;
   i = HtfIdx(gH4T, 14400, T);   h4 = i >= 0 ? gH4Tr[i] : 0;
   i = HtfIdx(gH1T, 3600, T);    h1 = i >= 0 ? gH1Tr[i] : 0;
   core = i >= 0 ? gH1Core[i] : 0.0;
   int p = core > 0 ? 1 : core < 0 ? -1 : 0;
   return d1 * 30 + h4 * 30 + h1 * 20 + p * 20;
  }

//--- FVG M15 / H1 actif qui contient le prix p à l'instant T
string HtfFvgAt(datetime T, double lo, double hi, int dir)
  {
   for(int i = ArraySize(gHz) - 1; i >= 0; i--)
     {
      if(gHz[i].dir != dir || gHz[i].tc > T) continue;
      if(gHz[i].tf != 0 && gHz[i].tf <= T) continue;
      if(hi >= gHz[i].bot && lo <= gHz[i].top) return "FVG " + (gHz[i].tfMin == 60 ? "H1" : "M15");
     }
   return "";
  }

//+------------------------------------------------------------------+
//| Alertes                                                          |
//+------------------------------------------------------------------+
string Px2(double p) { return DoubleToString(p, _Digits); }
void Ev(bool on, string msg)
  {
   if(!on || !gAlertLive) return;
   if(StringFind(gAlertBuf, msg) >= 0) return;
   gAlertBuf += (gAlertBuf == "" ? "" : " · ") + msg;
  }

void SendAlert(string msg, datetime bar)
  {
   string tf = gPer < 3600 ? "M" + IntegerToString(gPer / 60) : "H" + IntegerToString(gPer / 3600);
   string txt = "CX Système " + _Symbol + " " + tf + " " + LubTime(bar, false) + " : " + msg;
   if(AlPopup) Alert(txt);
   if(AlPush)  SendNotification(StringSubstr(txt, 0, 255));
  }

//+------------------------------------------------------------------+
//| Repères dessinés                                                 |
//+------------------------------------------------------------------+
void AddMark(CState &S, int x, double y, string text, uint tc, uint bg, int up, bool sym)
  {
   Mark m; m.x = x; m.y = y; m.text = text; m.tc = tc; m.bg = bg; m.up = up; m.sym = sym;
   Push(S.marks, m);
   if(ArraySize(S.marks) > MAX_MARK) ArrayRemove(S.marks, 0, 1);
  }

void AddSeg(CState &S, int x1, int x2, double y, uint c, int style)
  {
   Seg s; s.x1 = x1; s.x2 = x2; s.y = y; s.c = c; s.style = style;
   Push(S.segs, s);
   if(ArraySize(S.segs) > MAX_MARK) ArrayRemove(S.segs, 0, 1);
  }

void SetSlot(CState &S, int k, string name, double price, int x0, int kind, int grp)
  {
   S.slot[k].name = name; S.slot[k].price = price; S.slot[k].x0 = x0; S.slot[k].kind = kind;
   S.slot[k].taken = false; S.slot[k].xTaken = NAI; S.slot[k].grp = grp;
  }

//+------------------------------------------------------------------+
//| Étage 4 : cibles sur les niveaux de la carte                     |
//+------------------------------------------------------------------+
void PickTargets(CState &S, Trade &tr)
  {
   double p[]; string nm[];
   double minD = tr.risk * InpMinTpR;
   for(int k = 0; k < NSLOT; k++)
     {
      if(S.slot[k].price == NA || S.slot[k].taken) continue;
      double d = (S.slot[k].price - tr.entry) * tr.dir;
      if(d < minD) continue;
      PushD(p, S.slot[k].price); PushS(nm, S.slot[k].name);
     }
   //--- tri du plus proche au plus lointain
   int n = ArraySize(p);
   for(int i = 0; i < n; i++)
      for(int j = i + 1; j < n; j++)
         if((p[j] - p[i]) * tr.dir < 0) { double a = p[i]; p[i] = p[j]; p[j] = a; string b = nm[i]; nm[i] = nm[j]; nm[j] = b; }
   double tp[3]; string tn[3];
   int got = 0;
   for(int i = 0; i < n && got < 3; i++)
     {
      if(got > 0 && MathAbs(p[i] - tp[got - 1]) < tr.risk * 0.25) { tn[got - 1] += "+" + nm[i]; continue; }
      tp[got] = p[i]; tn[got] = nm[i]; got++;
     }
   //--- pas assez de niveaux : complément en R, après le dernier niveau trouvé
   for(int i = got; i < 3; i++)
     {
      double base = i == 0 ? tr.entry : tp[i - 1];
      tp[i] = base + tr.dir * tr.risk;
      tn[i] = "+1R";
     }
   tr.tp1 = tp[0]; tr.tp2 = tp[1]; tr.tp3 = tp[2];
   tr.n1 = tn[0]; tr.n2 = tn[1]; tr.n3 = tn[2];
  }

//+------------------------------------------------------------------+
//| Une bougie clôturée                                              |
//+------------------------------------------------------------------+
void ProcessBar(CState &S, int t)
  {
   //------------------------------------------------ temps de New York
   datetime ny = ToNy(gT[t]);
   MqlDateTime nd; TimeToStruct(ny, nd);
   int  mins = nd.hour * 60 + nd.min;
   long tday = (long)((ny + 6 * 3600) / 86400);         // la journée commence à 18:00
   long week = (tday + 3) / 7;                           // semaine du lundi (dimanche 18:00)
   T_Series(t);

   //------------------------------------------------ ÉTAGE 2 : carte
   if(t == 0) { S.curDay = tday; S.curWeek = week; S.dStart = 0; S.wStart = 0; }
   if(tday != S.curDay)
     {
      if(S.dHi > -DBL_MAX)
        {
         SetSlot(S, S_PDH, "PDH", S.dHi, S.dStart, 1, 0);
         SetSlot(S, S_PDL, "PDL", S.dLo, S.dStart, -1, 0);
        }
      S.curDay = tday; S.dStart = t; S.dHi = -DBL_MAX; S.dLo = DBL_MAX;
     }
   if(week != S.curWeek)
     {
      if(S.wHi > -DBL_MAX)
        {
         SetSlot(S, S_PWH, "PWH", S.wHi, S.wStart, 1, 1);
         SetSlot(S, S_PWL, "PWL", S.wLo, S.wStart, -1, 1);
        }
      S.curWeek = week; S.wStart = t; S.wHi = -DBL_MAX; S.wLo = DBL_MAX;
     }
   int ses = SessOf(mins);
   if(ses != S.curSess)
     {
      if(S.curSess >= 0 && S.sHi > -DBL_MAX)
        {
         SetSlot(S, S_SES + S.curSess * 2,     gSessName[S.curSess] + " H", S.sHi, S.sStart, 1, 2);
         SetSlot(S, S_SES + S.curSess * 2 + 1, gSessName[S.curSess] + " L", S.sLo, S.sStart, -1, 2);
        }
      S.curSess = ses; S.sStart = t; S.sHi = -DBL_MAX; S.sLo = DBL_MAX;
     }
   bool newCal = S.prevMins >= 0 && mins < S.prevMins;
   if(newCal) SetSlot(S, S_O00, "00:00", gO[t], t, 0, 3);
   if(S.prevMins >= 0 && S.prevMins < 510 && mins >= 510 && !newCal) SetSlot(S, S_O830, "08:30", gO[t], t, 0, 3);
   if(S.prevMins >= 0 && S.prevMins < 570 && mins >= 570 && !newCal) SetSlot(S, S_O930, "09:30", gO[t], t, 0, 3);
   S.prevMins = mins;

   //------------------------------------------------ épuisement : compteurs 9 / 13
   if(t >= 4)
     {
      S.cntDn = gC[t] < gC[t - 4] ? S.cntDn + 1 : 0;
      S.cntUp = gC[t] > gC[t - 4] ? S.cntUp + 1 : 0;
      if(S.cntDn == 9) { S.lastBull9 = t; S.cdDnOn = true; S.cdDn = 0; S.cdUpOn = false; }
      if(S.cntUp == 9) { S.lastBear9 = t; S.cdUpOn = true; S.cdUp = 0; S.cdDnOn = false; }
      if(S.cdDnOn && t >= 2 && gC[t] <= gL[t - 2]) { S.cdDn++; if(S.cdDn == 13) { S.lastBull13 = t; S.cdDnOn = false; } }
      if(S.cdUpOn && t >= 2 && gC[t] >= gH[t - 2]) { S.cdUp++; if(S.cdUp == 13) { S.lastBear13 = t; S.cdUpOn = false; } }
     }
   //------------------------------------------------ Long / Short Covered (pression de la bougie anormale)
   double bm = SmaArr(gBarNet, t, 50), bs = SdArr(gBarNet, t, 50);
   double z = bm != NA && bs != NA && bs > 0 ? (gBarNet[t] - bm) / bs : 0.0;
   if(z >= InpCovZ && gCore[t] < 0)  S.lastShortCov = t;    // vendeurs forcés de racheter
   if(z <= -InpCovZ && gCore[t] > 0) S.lastLongCov = t;     // acheteurs forcés de vendre

   //------------------------------------------------ structure du graphique (MSS)
   if(PivotHigh(gH, t, InpMssPiv)) { S.swH = gH[t - InpMssPiv]; S.swHB = t - InpMssPiv; }
   if(PivotLow(gL, t, InpMssPiv))  { S.swL = gL[t - InpMssPiv]; S.swLB = t - InpMssPiv; }
   bool bullMss = false, bearMss = false;
   if(S.swH != NA && gC[t] > S.swH)
     {
      bullMss = S.trend == -1;
      if(bullMss) AddSeg(S, S.swHB, t, S.swH, A(ColBull, 0), sol);
      S.trend = 1; S.swH = NA;
     }
   if(S.swL != NA && gC[t] < S.swL)
     {
      bearMss = S.trend == 1;
      if(bearMss) AddSeg(S, S.swLB, t, S.swL, A(ColBear, 0), sol);
      S.trend = -1; S.swL = NA;
     }
   bool bullFvg = t >= 2 && gL[t] > gH[t - 2] && gC[t - 1] > gH[t - 2];
   bool bearFvg = t >= 2 && gH[t] < gL[t - 2] && gC[t - 1] < gL[t - 2];

   //------------------------------------------------ ÉTAGE 3 : SFP sur la carte
   int    sfpDir = 0;
   string sfpName = "";
   int    bestPrio = -1;
   for(int k = 0; k < NSLOT; k++)
     {
      if(S.slot[k].price == NA || S.slot[k].taken || S.slot[k].kind == 0 || S.slot[k].x0 >= t) continue;
      double p = S.slot[k].price;
      int prio = S.slot[k].grp == 1 ? 3 : S.slot[k].grp == 0 ? 2 : 1;
      if(S.slot[k].kind == -1 && gL[t] < p)
        {
         S.slot[k].taken = true; S.slot[k].xTaken = t;
         if(gC[t] > p && prio > bestPrio) { sfpDir = 1; sfpName = S.slot[k].name; bestPrio = prio; }
        }
      if(S.slot[k].kind == 1 && gH[t] > p)
        {
         S.slot[k].taken = true; S.slot[k].xTaken = t;
         if(gC[t] < p && prio > bestPrio) { sfpDir = -1; sfpName = S.slot[k].name; bestPrio = prio; }
        }
     }
   datetime T = gT[t] + gPer;
   if(sfpDir == 1)
     {
      S.bull.on = true; S.bull.sfpBar = t; S.bull.ext = gL[t]; S.bull.lvl = sfpName; S.bull.fvg = false;
      S.bull.htfFvg = HtfFvgAt(T, gL[t], gH[t], 1) != "";
      AddMark(S, t, gL[t], "✕", A(ColBull, 0), 0, 1, true);
      S.lastEvent = "SFP ▲ " + sfpName + " " + LubTime(gT[t], false);
      Ev(AlSfp, "SFP haussier sous " + sfpName);
     }
   if(sfpDir == -1)
     {
      S.bear.on = true; S.bear.sfpBar = t; S.bear.ext = gH[t]; S.bear.lvl = sfpName; S.bear.fvg = false;
      S.bear.htfFvg = HtfFvgAt(T, gL[t], gH[t], -1) != "";
      AddMark(S, t, gH[t], "✕", A(ColBear, 0), 0, 0, true);
      S.lastEvent = "SFP ▼ " + sfpName + " " + LubTime(gT[t], false);
      Ev(AlSfp, "SFP baissier au-dessus de " + sfpName);
     }

   //------------------------------------------------ séquence FVG → MSS, filtres
   int d1, h4, h1; double core;
   int score = BiasScore(T, d1, h4, h1, core);
   int sig = 0;
   string why = "";
   for(int side = 1; side >= -1; side -= 2)
     {
      Setup st;
      if(side == 1) st = S.bull; else st = S.bear;
      if(!st.on) continue;
      bool brk = side == 1 ? gC[t] < st.ext : gC[t] > st.ext;
      if(brk || t - st.sfpBar > InpWindow)
        {
         st.on = false;
        }
      else
        {
         if(t > st.sfpBar && (side == 1 ? bullFvg : bearFvg)) st.fvg = true;
         bool mss = side == 1 ? bullMss : bearMss;
         if(mss && st.fvg)
           {
            int from = st.sfpBar - InpExhLook;
            bool e9  = (side == 1 ? S.lastBull9  : S.lastBear9)  >= from;
            bool e13 = (side == 1 ? S.lastBull13 : S.lastBear13) >= from;
            bool cov = (side == 1 ? S.lastShortCov : S.lastLongCov) >= from;
            bool exhOk  = !InpReqExh || e9 || e13 || cov;
            bool biasOk = !InpBiasReq || score * side >= InpBiasMin;
            bool zoneOk = !InpReqHtfFvg || st.htfFvg;
            string ex = (e13 ? "13" : e9 ? "9" : "") + (cov ? ((e9 || e13) ? "+" : "") + (side == 1 ? "SC" : "LC") : "");
            if(exhOk && biasOk && zoneOk)
              {
               sig = side;
               why = "SFP " + st.lvl + " · FVG · MSS" + (ex != "" ? " · épuis. " + ex : "") + (st.htfFvg ? " · FVG HTF" : "") + " · biais " + IntegerToString(score);
              }
            else
               S.lastEvent = (side == 1 ? "MSS ▲" : "MSS ▼") + " refusé : " + (!biasOk ? "biais " + IntegerToString(score) : !exhOk ? "pas d'épuisement" : "pas de FVG HTF");
            st.on = false;
           }
        }
      if(side == 1) S.bull = st; else S.bear = st;
     }

   //------------------------------------------------ ÉTAGE 4 : suivi du trade en cours
   int nt = ArraySize(S.trades);
   if(nt > 0 && S.trades[nt - 1].status == 0 && t > S.trades[nt - 1].x0)
     {
      Trade tr = S.trades[nt - 1];
      bool slHit = tr.dir == 1 ? gL[t] <= tr.sl : gH[t] >= tr.sl;
      if(slHit)
        {
         tr.status = tr.h1 ? 2 : -1; tr.x1 = t;
         Ev(true, tr.h1 ? "SL à l'entrée touché" : "SL touché " + Px2(tr.sl));
        }
      else
        {
         if(!tr.h1 && (tr.dir == 1 ? gH[t] >= tr.tp1 : gL[t] <= tr.tp1)) { tr.h1 = true; tr.sl = tr.entry; Ev(true, "TP1 " + tr.n1 + " atteint, SL à l'entrée"); }
         if(!tr.h2 && (tr.dir == 1 ? gH[t] >= tr.tp2 : gL[t] <= tr.tp2)) { tr.h2 = true; Ev(true, "TP2 " + tr.n2 + " atteint"); }
         if(!tr.h3 && (tr.dir == 1 ? gH[t] >= tr.tp3 : gL[t] <= tr.tp3)) { tr.h3 = true; tr.status = 1; tr.x1 = t; Ev(true, "TP3 " + tr.n3 + " atteint"); }
        }
      S.trades[nt - 1] = tr;
     }

   //------------------------------------------------ nouveau signal
   if(sig != 0)
     {
      if(nt > 0 && S.trades[nt - 1].status == 0) { S.trades[nt - 1].status = 3; S.trades[nt - 1].x1 = t; }
      Trade tr;
      tr.dir = sig; tr.x0 = t; tr.x1 = NAI;
      tr.entry = gC[t];
      double ext = sig == 1 ? S.bull.ext : S.bear.ext;
      double buf = InpSlBufAtr * (gAtr[t] != NA ? gAtr[t] : 0.0);
      tr.sl = sig == 1 ? ext - buf : ext + buf;
      tr.sl0 = tr.sl;
      tr.risk = MathMax(MathAbs(tr.entry - tr.sl), _Point);
      tr.h1 = tr.h2 = tr.h3 = false; tr.status = 0; tr.why = why;
      PickTargets(S, tr);
      Push(S.trades, tr);
      if(ArraySize(S.trades) > 50) ArrayRemove(S.trades, 0, 1);
      AddMark(S, t, sig == 1 ? gL[t] : gH[t], sig == 1 ? "BUY" : "SELL", A(clrWhite, 0), A(sig == 1 ? ColBull : ColBear, 0), sig == 1 ? 1 : 0, false);
      S.lastSigBar = t;
      S.lastEvent = (sig == 1 ? "BUY " : "SELL ") + LubTime(gT[t], false);
      Ev(true, (sig == 1 ? "BUY " : "SELL ") + Px2(tr.entry) + " SL " + Px2(tr.sl) + " TP1 " + tr.n1 + " " + Px2(tr.tp1) + " · " + why);
     }

   //------------------------------------------------ hauts / bas en cours (après les contrôles)
   S.dHi = MathMax(S.dHi, gH[t]); S.dLo = MathMin(S.dLo, gL[t]);
   S.wHi = MathMax(S.wHi, gH[t]); S.wLo = MathMin(S.wLo, gL[t]);
   if(S.curSess >= 0) { S.sHi = MathMax(S.sHi, gH[t]); S.sLo = MathMin(S.sLo, gL[t]); }
  }

//--- séries de la bougie t : ATR 14 et pression (logique de CX Press)
void T_Series(int t)
  {
   double pc = t > 0 ? gC[t - 1] : gO[t];
   double tr = MathMax(gH[t], pc) - MathMin(gL[t], pc);
   gAtr[t] = t > 0 && gAtr[t - 1] != NA ? (gAtr[t - 1] * 13 + tr) / 14.0 : tr;
   double br = gC[t] - MathMin(gL[t], pc);
   double sr = MathMax(gH[t], pc) - gC[t];
   double vm = SmaArr(gV, t, 14);
   double rv = vm != NA && vm > 0 && gV[t] > 0 ? MathMin(gV[t] / vm, 5.0) : 1.0;
   gBuyE[t]  = Ema(t > 0 ? gBuyE[t - 1] : NA, br * rv, 14);
   gSellE[t] = Ema(t > 0 ? gSellE[t - 1] : NA, sr * rv, 14);
   double bb = SmaArr(gBuyE, t, 200), sb = SmaArr(gSellE, t, 200);
   gBuyP[t]  = Ema(t > 0 ? gBuyP[t - 1] : NA, bb != NA && bb > 0 ? 200.0 * gBuyE[t] / bb : 0.0, 3);
   gSellP[t] = Ema(t > 0 ? gSellP[t - 1] : NA, sb != NA && sb > 0 ? 200.0 * gSellE[t] / sb : 0.0, 3);
   gNetR[t]  = gBuyP[t] - gSellP[t];
   double sd = SdArr(gNetR, t, 200);
   gNetP[t]  = sd != NA && sd > 0 ? gNetR[t] / sd * 300.0 : 0.0;
   gCore[t]  = Ema(t > 0 ? gCore[t - 1] : NA, gNetP[t], 50);
   gBarNet[t] = (br - sr) * rv;
  }

//+------------------------------------------------------------------+
//| Cycle MT5                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpMaxBars < 500 || InpMssPiv < 1 || InpBiasPiv < 1 || InpWindow < 2)
      return INIT_PARAMETERS_INCORRECT;
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXSYS_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Système");
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

void ResizeSeries()
  {
   ArrayResize(gAtr, gN); ArrayResize(gBuyE, gN); ArrayResize(gSellE, gN); ArrayResize(gBuyP, gN);
   ArrayResize(gSellP, gN); ArrayResize(gNetR, gN); ArrayResize(gNetP, gN); ArrayResize(gCore, gN); ArrayResize(gBarNet, gN);
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < 300 || PeriodSeconds(PERIOD_CURRENT) > 3600)
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
   ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gV, gN); ArrayResize(gT, gN);
   ResizeSeries();
   for(int i = from; i < gN; i++)
     {
      gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i];
      gV[i] = (double)tick_volume[gBase + i]; gT[i] = time[gBase + i];
     }
   gTotal = rates_total;

   bool newBar = full || gProcessed < gN - 1;
   if(newBar)
     {
      gSrvOffNow = (long)MathRound((double)(TimeTradeServer() - TimeGMT()) / 1800.0) * 1800;
      gHtfOk = LoadHtf();
      if(!gHtfOk) { gProcessed = -1; return 0; }     // historique des unités supérieures pas encore chargé
     }
   if(full)
     {
      gS.Reset();
      gProcessed = 0;
     }
   while(gProcessed < gN - 1)
     {
      gAlertLive = !full && gProcessed >= gN - 3;
      gAlertBuf = "";
      ProcessBar(gS, gProcessed);
      gAlertLive = false;
      if(gAlertBuf != "")
         SendAlert(gAlertBuf, gT[gProcessed]);
      gProcessed++;
     }
   uint now = GetTickCount();
   if(newBar || now - gLastRender >= 500)
      Render();
   return rates_total;
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_CHART_CHANGE || gN <= 0 || gProcessed < 0)
      return;
   gDirty = true;
   if(GetTickCount() - gLastRender >= 40)
      Render();
  }

void OnTimer()
  {
   if(gDirty && gProcessed >= 0)
      Render();
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

void SetFont(int size, bool sym)
  {
   int s = size == tiny ? -45 : size == small ? -60 : -75;
   gCv.FontSet(sym ? "Segoe UI Symbol" : InpFont, s);
  }

//--- étiquette : bulle colorée (BUY / SELL) ou texte seul (✕)
void DrawMark(const Mark &m)
  {
   double ax = XofBar(m.x);
   if(ax < -300 || ax > gW + 300) return;
   double ay = YofPrice(m.y);
   if(ay < -100 || ay > gHh + 100) return;
   int tw = 0, th = 0;
   SetFont(m.sym ? small : tiny, m.sym);
   gCv.TextSize(m.text, tw, th);
   int padX = Px(4), padY = Px(2), ph = Px(4);
   int w = tw + 2 * padX, h = th + 2 * padY;
   int iy = (int)MathRound(ay);
   int x1 = (int)MathRound(ax - w / 2.0);
   int top = m.up == 1 ? iy + ph : iy - ph - h;
   if(((m.bg >> 24) & 0xFF) > 0)
     {
      FillPointer(ax, iy, ph + 1, ph, m.up == 1 ? 1 : -1, m.bg);
      FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, m.bg);
     }
   gCv.TextOut(x1 + padX, top + h / 2, m.text, m.tc, TA_LEFT | TA_VCENTER);
  }

//--- ligne horizontale + texte à droite
void HLevel(int x1, int x2, double y, uint c, int style, string txt, bool txtRight)
  {
   if(y == NA) return;
   double yy = MathRound(YofPrice(y));
   if(yy < -20 || yy > gHh + 20) return;
   double a = MathRound(XofBar(x1)), b = MathRound(XofBar(x2));
   if(b < 0 || a > gW) return;
   DrawLine(a, yy, b, yy, style, Wpx(1), c);
   if(txt != "" && txtRight)
     {
      SetFont(tiny, false);
      gCv.TextOut((int)b + Px(4), (int)yy, txt, c, TA_LEFT | TA_VCENTER);
     }
  }

void DrawBox(int x1, int x2, double top, double bot, uint bg, uint bd)
  {
   int a = (int)MathRound(XofBar(x1)), b = (int)MathRound(XofBar(x2));
   if(b < a) { int s = a; a = b; b = s; }
   if(b < 0 || a > gW) return;
   int y1 = (int)MathRound(YofPrice(MathMax(top, bot))), y2 = (int)MathRound(YofPrice(MathMin(top, bot)));
   if(y2 < 0 || y1 > gHh) return;
   FillRect(a, y1, b, y2, bg);
   if(((bd >> 24) & 0xFF) > 0)
     {
      FillRect(a, y1, b, y1, bd);
      FillRect(a, y2, b, y2, bd);
     }
  }

color SlotColor(int grp) { return grp == 0 ? ColDay : grp == 1 ? ColWeek : grp == 2 ? ColSess : ColOpen; }
bool  SlotShown(int grp) { return grp == 0 ? InpShowDay : grp == 1 ? InpShowWeek : grp == 2 ? InpShowSess : InpShowOpen; }

void Render()
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

   int firstShift = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   firstShift = MathMax(1, MathMin(firstShift, bars - 1));
   double pMax = ChartGetDouble(0, CHART_PRICE_MAX, 0), pMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   int xa, ya, xb, yb;
   if(pMax <= pMin || !ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, firstShift), pMax, xa, ya)
      || !ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, firstShift - 1), pMin, xb, yb))
     { gCv.Update(true); return; }
   gT0 = (gN - 1) - firstShift;
   gX0 = xa;
   gSp = xb - xa;
   if(gSp <= 0) gSp = 1 << (int)ChartGetInteger(0, CHART_SCALE);
   gPMax = pMax; gY0 = ya; gKy = (double)(yb - ya) / (pMax - pMin);
   int last = gN - 1, ext = last + 6;

   //--- FVG M15 / H1 encore ouverts
   datetime nowT = gT[last] + gPer;
   for(int i = 0; i < ArraySize(gHz); i++)
     {
      if((gHz[i].tfMin == 15 && !InpFvgM15) || (gHz[i].tfMin == 60 && !InpFvgH1)) continue;
      if(gHz[i].tf != 0 && gHz[i].tf <= nowT) continue;
      if(gHz[i].ts < gT[0]) continue;
      int x1 = BarAt(gHz[i].ts);
      DrawBox(x1, ext, gHz[i].top, gHz[i].bot, A(ColFvg, gHz[i].tfMin == 60 ? 85 : 90), A(ColFvg, 70));
      double yy = YofPrice((gHz[i].top + gHz[i].bot) / 2.0);
      SetFont(tiny, false);
      gCv.TextOut((int)MathRound(XofBar(ext)) - Px(4), (int)yy, gHz[i].tfMin == 60 ? "FVG H1" : "FVG M15", A(ColFvg, 30), TA_RIGHT | TA_VCENTER);
     }

   //--- carte
   for(int k = 0; k < NSLOT; k++)
     {
      Slot s = gS.slot[k];
      if(s.price == NA || !SlotShown(s.grp)) continue;
      color c = SlotColor(s.grp);
      if(s.taken)
        {
         if(InpShowTaken) HLevel(s.x0, s.xTaken, s.price, A(c, 65), dot, "", false);
         continue;
        }
      HLevel(s.x0, ext, s.price, A(c, s.grp == 3 ? 40 : 10), s.grp == 3 ? dot : (s.grp == 2 ? dsh : sol), s.name, true);
     }

   //--- lignes de MSS et repères
   for(int i = 0; i < ArraySize(gS.segs); i++)
      HLevel(gS.segs[i].x1, gS.segs[i].x2, gS.segs[i].y, gS.segs[i].c, gS.segs[i].style, "", false);
   for(int i = 0; i < ArraySize(gS.segs); i++)
     {
      double mx = XofBar((gS.segs[i].x1 + gS.segs[i].x2) / 2.0), my = YofPrice(gS.segs[i].y);
      if(mx < 0 || mx > W || my < 0 || my > H) continue;
      SetFont(tiny, false);
      gCv.TextOut((int)mx, (int)my - Px(2), "MSS", gS.segs[i].c, TA_CENTER | TA_BOTTOM);
     }
   for(int i = 0; i < ArraySize(gS.marks); i++)
      DrawMark(gS.marks[i]);

   //--- trades : zones de risque / gain, lignes, textes du dernier
   int nt = ArraySize(gS.trades);
   for(int i = MathMax(0, nt - InpKeepTrades); i < nt; i++)
     {
      Trade tr = gS.trades[i];
      int x2 = tr.x1 == NAI ? ext : tr.x1;
      DrawBox(tr.x0, x2, tr.entry, tr.sl0, A(ColBear, 88), 0);
      DrawBox(tr.x0, x2, tr.entry, tr.tp3, A(ColBull, 90), 0);
      bool lastOne = i == nt - 1;
      string st = tr.status == 1 ? " ✓" : tr.status == -1 ? " ✗" : tr.status == 2 ? " BE" : "";
      HLevel(tr.x0, x2, tr.entry, A(clrGray, 20), sol, lastOne ? "Entrée " + Px2(tr.entry) : "", lastOne);
      HLevel(tr.x0, x2, tr.sl,    A(ColBear, 10), sol, lastOne ? (tr.h1 ? "SL (entrée) " : "SL ") + Px2(tr.sl) + st : "", lastOne);
      HLevel(tr.x0, x2, tr.tp1,   A(ColBull, 30), dot, lastOne ? "TP1 " + tr.n1 + " " + Px2(tr.tp1) + (tr.h1 ? " ✓" : "") : "", lastOne);
      HLevel(tr.x0, x2, tr.tp2,   A(ColBull, 20), dsh, lastOne ? "TP2 " + tr.n2 + " " + Px2(tr.tp2) + (tr.h2 ? " ✓" : "") : "", lastOne);
      HLevel(tr.x0, x2, tr.tp3,   A(ColBull, 10), sol, lastOne ? "TP3 " + tr.n3 + " " + Px2(tr.tp3) + (tr.h3 ? " ✓" : "") : "", lastOne);
     }

   DrawPanel();
   gCv.Update(true);
   gLastRender = GetTickCount();
   gDirty = false;
  }

//+------------------------------------------------------------------+
//| Tableau                                                          |
//+------------------------------------------------------------------+
string Arrow(int d) { return d > 0 ? "▲" : d < 0 ? "▼" : "—"; }

void DrawPanel()
  {
   //--- couleurs selon le fond du graphique
   long bgl = ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int lum = ((int)(bgl & 0xFF) * 299 + (int)((bgl >> 8) & 0xFF) * 587 + (int)((bgl >> 16) & 0xFF) * 114) / 1000;
   bool dark = lum < 128;
   uint bg  = dark ? A(C'30,34,45', 8) : A(C'255,255,255', 6);
   uint bd  = dark ? A(C'80,85,100', 40) : A(C'200,200,210', 20);
   uint txt = dark ? A(C'220,222,230', 0) : A(C'19,23,34', 0);
   uint mut = dark ? A(C'140,145,160', 0) : A(C'110,115,130', 0);
   uint bu = A(ColBull, 0), be = A(ColBear, 0);

   string k[]; string v[]; uint vc[];
   datetime T = TimeCurrent();
   int d1, h4, h1; double core;
   int score = BiasScore(T, d1, h4, h1, core);
   int bias = score >= InpBiasMin ? 1 : score <= -InpBiasMin ? -1 : 0;
   PushS(k, "BIAIS");       PushS(v, Arrow(bias) + " " + (bias > 0 ? "Haussier" : bias < 0 ? "Baissier" : "Neutre") + "  (" + IntegerToString(score) + ")"); PushU(vc, bias > 0 ? bu : bias < 0 ? be : mut);
   PushS(k, "D1 · H4 · H1"); PushS(v, Arrow(d1) + "  " + Arrow(h4) + "  " + Arrow(h1)); PushU(vc, txt);
   PushS(k, "Pression H1"); PushS(v, core > 0 ? "▲ acheteurs" : core < 0 ? "▼ vendeurs" : "—"); PushU(vc, core > 0 ? bu : core < 0 ? be : mut);

   //--- niveaux les plus proches au-dessus / au-dessous
   double px = gC[gN - 1];
   double up = DBL_MAX, dn = -DBL_MAX; string nu = "—", ndn = "—";
   for(int i = 0; i < NSLOT; i++)
     {
      if(gS.slot[i].price == NA || gS.slot[i].taken) continue;
      double p = gS.slot[i].price;
      if(p > px && p < up) { up = p; nu = gS.slot[i].name; }
      if(p < px && p > dn) { dn = p; ndn = gS.slot[i].name; }
     }
   PushS(k, "Niveau au-dessus"); PushS(v, up < DBL_MAX ? nu + " " + Px2(up) : "—"); PushU(vc, txt);
   PushS(k, "Niveau au-dessous"); PushS(v, dn > -DBL_MAX ? ndn + " " + Px2(dn) : "—"); PushU(vc, txt);
   string fz = HtfFvgAt(T, gL[gN - 1], gH[gN - 1], 1);
   string fzb = HtfFvgAt(T, gL[gN - 1], gH[gN - 1], -1);
   PushS(k, "Zone FVG HTF"); PushS(v, fz != "" ? fz + " ▲" : fzb != "" ? fzb + " ▼" : "—"); PushU(vc, fz != "" ? bu : fzb != "" ? be : mut);

   //--- setup en cours
   string su = "—"; uint suc = mut;
   if(gS.bull.on) { su = "▲ SFP " + gS.bull.lvl + (gS.bull.fvg ? " → FVG ✓ → MSS …" : " → FVG …"); suc = bu; }
   else if(gS.bear.on) { su = "▼ SFP " + gS.bear.lvl + (gS.bear.fvg ? " → FVG ✓ → MSS …" : " → FVG …"); suc = be; }
   PushS(k, "Setup"); PushS(v, su); PushU(vc, suc);
   int lt = gN - 2, from = lt - InpExhLook;
   string ex = "9 " + (gS.lastBull9 >= from ? "▲" : gS.lastBear9 >= from ? "▼" : "—")
               + " · 13 " + (gS.lastBull13 >= from ? "▲" : gS.lastBear13 >= from ? "▼" : "—")
               + " · Cov " + (gS.lastShortCov >= from ? "SC" : gS.lastLongCov >= from ? "LC" : "—");
   PushS(k, InpReqExh ? "Épuisement (exigé)" : "Épuisement (info)"); PushS(v, ex); PushU(vc, txt);
   PushS(k, "Dernier événement"); PushS(v, gS.lastEvent); PushU(vc, mut);

   //--- trade
   int nt = ArraySize(gS.trades);
   if(nt > 0)
     {
      Trade tr = gS.trades[nt - 1];
      string ts = tr.status == 0 ? (tr.h2 ? "TP2 ✓ → TP3" : tr.h1 ? "TP1 ✓ → TP2" : "en cours")
                  : tr.status == 1 ? "TP3 ✓ terminé" : tr.status == -1 ? "SL ✗" : tr.status == 2 ? "SL à l'entrée" : "remplacé";
      double rNow = tr.dir * (px - tr.entry) / tr.risk;
      PushS(k, "Trade"); PushS(v, (tr.dir == 1 ? "BUY " : "SELL ") + Px2(tr.entry) + " · " + ts); PushU(vc, tr.dir == 1 ? bu : be);
      if(tr.status == 0) { PushS(k, "Progression"); PushS(v, (rNow >= 0 ? "+" : "") + DoubleToString(rNow, 1) + "R · SL " + Px2(tr.sl)); PushU(vc, rNow >= 0 ? bu : be); }
      //--- taille du lot pour le risque choisi
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), tsz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double money = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
      double perLot = tsz > 0 ? MathAbs(tr.entry - tr.sl0) / tsz * tv : 0;
      double lots = perLot > 0 && step > 0 ? MathFloor(money / perLot / step) * step : 0;
      PushS(k, "Lot (" + DoubleToString(InpRiskPct, 1) + " %)"); PushS(v, lots >= vmin ? DoubleToString(lots, 2) : "< " + DoubleToString(vmin, 2)); PushU(vc, txt);
     }
   else { PushS(k, "Trade"); PushS(v, "aucun"); PushU(vc, mut); }

   //--- mise en page
   int n = ArraySize(k);
   int kw = 0, vw = 0, th = 0, tw = 0, tth = 0;
   gCv.FontSet("Segoe UI Symbol", -80);
   for(int i = 0; i < n; i++)
     {
      gCv.TextSize(k[i], tw, tth); kw = MathMax(kw, tw); th = MathMax(th, tth);
      gCv.TextSize(v[i], tw, tth); vw = MathMax(vw, tw);
     }
   int pad = Px(6), rowH = th + Px(5);
   int w = kw + vw + 3 * pad, h = n * rowH + 2 * pad + rowH;
   int mx = Px(8), my = Px(8);
   int x0 = (InpPanPos == PanTopLeft || InpPanPos == PanBottomLeft) ? mx : gW - w - mx - Px(60);
   int y0 = (InpPanPos == PanBottomLeft || InpPanPos == PanBottomRight) ? gHh - h - my - Px(20) : my;
   FillRoundRect(x0, y0, x0 + w, y0 + h, 4.0 * gDpi, bd);
   FillRoundRect(x0 + 1, y0 + 1, x0 + w - 1, y0 + h - 1, 4.0 * gDpi, bg);
   gCv.FontSet("Segoe UI Symbol", -85);
   gCv.TextOut(x0 + pad, y0 + pad + rowH / 2, "CX Système · NAS100", txt, TA_LEFT | TA_VCENTER);
   gCv.FontSet("Segoe UI Symbol", -80);
   for(int i = 0; i < n; i++)
     {
      int yy = y0 + pad + rowH * (i + 1) + rowH / 2;
      gCv.TextOut(x0 + pad, yy, k[i], mut, TA_LEFT | TA_VCENTER);
      gCv.TextOut(x0 + w - pad, yy, v[i], vc[i], TA_RIGHT | TA_VCENTER);
     }
  }
//+------------------------------------------------------------------+
