//+------------------------------------------------------------------+
//| CX_Flow.mq5                                                      |
//| Système de sweep de liquidité structurel, écrit d'après une      |
//| description publique (aucun code d'origine).                     |
//| Machine à états stricte, bougie clôturée par bougie clôturée :   |
//|  1. Biais (gate) : clôtures au-delà de bornes de séances         |
//|     (veille, Asie, Londres, ouverture de minuit NY), verrouillé  |
//|     pour la journée ; gate du soir sur la plage NY AM.           |
//|  2. Sweep : mèche au-delà d'un pivot confirmé (tampon ATR) et    |
//|     clôture revenue en deçà.                                     |
//|  3. PDA : Order Block ou Breaker Block près du sweep.            |
//|  4. MSS : clôture au-delà du dernier pivot de swing opposé,      |
//|     dans la fenêtre de temps (et la macro si activée).           |
//| Puis signal BUY / SELL, lignes Entrée / SL / TP et suivi du      |
//| trade (en attente -> actif -> résolu). Checklist en haut à       |
//| droite. Dessin en CCanvas comme CX Exécution.                    |
//| Heures en heure de New York, changement d'heure compris.         |
//| Aucun volume n'est utilisé.                                      |
//+------------------------------------------------------------------+
#property copyright   "CX"
#property version     "1.00"
#property description "CX Flow : biais de séance, sweep de pivot, Order / Breaker Block, MSS, puis signal avec Entrée, SL et TP."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

enum ENUM_LSTYLE  { sol = 0, dsh = 1, dot = 2 };
enum ENUM_TSIZE   { tiny = 0, small = 1, normal = 2 };
enum ENUM_OBZONE  { ObBody = 0, ObWick = 1 };            // zone de l'Order Block
enum ENUM_SLMODE  { SlPda = 0, SlSweep = 1 };            // méthode du stop
enum ENUM_TPMODE  { TpSwing = 0, TpRR = 1 };             // méthode de l'objectif

input group "Biais directionnel (gate du jour)"
input int    InpGateN     = 2;               // Niveaux franchis requis (clôture au-delà)
input bool   InpLvlPD     = true;            // Plus haut / plus bas de la veille
input bool   InpLvlAsia   = true;            // Plus haut / plus bas d'Asie
input string InpAsiaHours = "20:00-00:00";   // Asie (heure de New York)
input bool   InpLvlLon    = true;            // Plus haut / plus bas de Londres
input string InpLonHours  = "02:00-05:00";   // Londres (heure de New York)
input bool   InpLvlMid    = true;            // Ouverture de minuit (New York)
input group "Fenêtre de jour (heure de New York)"
input string InpDayHours  = "09:30-12:00";   // Séance de jour (début-fin)
input bool   InpMac1On    = false;           // Macro 1
input string InpMac1      = "09:50-10:10";   // Macro 1 (heures)
input bool   InpMac2On    = false;           // Macro 2
input string InpMac2      = "10:50-11:10";   // Macro 2 (heures)
input bool   InpMac3On    = false;           // Macro 3
input string InpMac3      = "11:50-12:10";   // Macro 3 (heures)
input group "Mode soir (heure de New York)"
input bool   InpEvening   = true;            // Mode soir
input string InpAmRange   = "09:30-12:00";   // Plage NY AM (gate du soir)
input string InpEveHours  = "13:30-16:00";   // Séance du soir (début-fin)
input bool   InpEMac1On   = false;           // Macro soir 1
input string InpEMac1     = "13:10-13:40";   // Macro soir 1 (heures)
input bool   InpEMac2On   = false;           // Macro soir 2
input string InpEMac2     = "14:50-15:10";   // Macro soir 2 (heures)
input bool   InpEMac3On   = false;           // Macro soir 3
input string InpEMac3     = "15:15-15:45";   // Macro soir 3 (heures)
input group "Pivots et sweeps"
input int         InpPivLen   = 5;               // Longueur des pivots (bougies de chaque côté)
input double      InpSwAtr    = 0.10;            // Tampon minimum du sweep (× ATR 14)
input int         InpMaxPiv   = 30;              // Pivots suivis par côté
input color       InpSwColor  = C'255,152,0';    // Couleur du marqueur de sweep
input int         InpSwWidth  = 1;               // Épaisseur du marqueur
input ENUM_LSTYLE InpSwStyle  = dsh;             // Style du marqueur
input group "PDA (Order Blocks / Breaker Blocks)"
input bool        InpUseOB     = true;           // Order Blocks
input bool        InpUseBB     = true;           // Breaker Blocks
input ENUM_OBZONE InpObZone    = ObBody;         // Zone de l'OB : corps ou bougie entière
input int         InpObLook    = 20;             // Recherche de la bougie opposée (bougies)
input int         InpPdaBars   = 10;             // Distance max au sweep (bougies)
input double      InpPdaAtr    = 1.5;            // Distance max au sweep (× ATR 14)
input int         InpPdaLife   = 60;             // Durée active d'un PDA (bougies)
input color       InpPdaBull   = C'8,153,129';   // Couleur PDA haussier
input color       InpPdaBear   = C'242,54,69';   // Couleur PDA baissier
input int         InpPdaTransp = 85;             // Transparence des PDA (0-100)
input group "Niveaux de trade"
input ENUM_SLMODE InpSlMode   = SlPda;           // Stop : bord opposé du PDA le plus lointain / mèche du sweep
input ENUM_TPMODE InpTpMode   = TpSwing;         // Objectif : swing opposé le plus proche / R:R fixe
input double      InpRR       = 2.0;             // R:R fixe (0,5 à 20)
input int         InpExtend   = 5;               // Prolongement à droite (bougies)
input color       InpEnColor  = C'41,98,255';    // Couleur Entrée
input color       InpSlColor  = C'242,54,69';    // Couleur Stop
input color       InpTpColor  = C'8,153,129';    // Couleur Objectif
input group "Checklist"
input bool        InpPanel    = true;            // Checklist en haut à droite
input group "Alertes (à la clôture de la bougie)"
input bool   AlPopup       = true;            // Fenêtre et son MT5
input bool   AlPush        = true;            // Notification mobile (MetaQuotes ID)
input bool   AlSessions    = false;           // Alertes seulement pendant les séances ci-dessous
input bool   AlLondon      = true;            // Séance de Londres
input string AlLondonHours = "08:00-11:00";   // Heures de Londres (heure de Londres)
input bool   AlNewYork     = true;            // Séance de New York
input string AlNYHours     = "08:30-11:30";   // Heures de New York (heure de New York)
input bool   AlBuy         = true;            // Signal BUY
input bool   AlSell        = true;            // Signal SELL
input group "MT5"
input int    InpMaxBars   = 5000;             // Bougies calculées (TradingView : 5 000)
input string InpFont      = "Trebuchet MS";   // Police (celle de TradingView)
input bool   InpSrvUsDst  = true;             // Le serveur suit l'heure d'été américaine (FundedNext)

//--- Couleurs TradingView
#define PC_GREEN  C'8,153,129'
#define PC_RED    C'242,54,69'
#define PC_BLUE   C'41,98,255'
#define PC_GRAY   C'120,123,134'
#define PC_DARK   C'54,58,69'
#define PC_WHITE  C'255,255,255'
//--- Ticket du Calculateur
#define UI_BG      C'19,23,34'
#define UI_BORDER  C'54,58,69'
#define UI_TEXT    C'219,222,229'
#define UI_MUTED   C'134,139,152'
#define UI_ORANGE  C'238,164,52'
#define UI_INFO_BG C'30,34,45'
#define UI_TINT_G  C'16,48,42'
#define UI_TINT_R  C'64,24,30'
#define UI_TINT_O  C'60,46,22'
#define UI_TINT_N  C'30,34,45'
#define UI_BUY_TX  C'91,156,246'
#define UI_SELL_TX C'247,82,95'

#define NA      EMPTY_VALUE
#define MAX_OBJ 500
#define MAX_PDA 80

enum ENUM_LBLSTYLE { LS_DOWN = 0, LS_UP = 1, LS_LEFT = 2, LS_CENTER = 3 };
enum ENUM_TRSTATE  { TS_NONE = 0, TS_PENDING = 1, TS_ACTIVE = 2, TS_WIN = 3, TS_LOSS = 4, TS_MISSED = 5 };

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

//--- Objets dessinés (line, box, label de Pine), x en indice de bougie
struct DLine  { double x1; double y1; double x2; double y2; uint clr; int style; int w; bool alive; };
struct DBox   { double x1; double top; double x2; double bot; uint bg; uint bd; int bw; bool alive; };
struct DLabel { double x; double y; string text; uint bg; uint tc; int style; int size; bool sym; bool alive; };
//--- Pivot actif (ni balayé ni cassé)
struct SPiv   { double p; int bar; };
//--- PDA : dir 1 = haussier, -1 = baissier ; brk = Breaker Block
struct SPda   { double top; double bot; int anchor; int born; int dir; bool brk; int box; int lbl; };
//--- Trade suivi (un par sens)
struct STrade { int dir; int state; double en; double sl; double tp; int bar; int lE; int lS; int lT; int tE; int tS; int tT; string pda; };

template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }
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
//| État complet (variables « var » et objets)                       |
//+------------------------------------------------------------------+
class CState
  {
public:
   //--- objets
   DLine  lines[];  DBox boxes[];  DLabel labels[];
   int    liveL, oldL, liveB, oldB, liveT, oldT;
   //--- journée de trading (débute à 18:00 NY)
   long   tdKey, calKey;
   double curH, curL, pdh, pdl, aH, aL, lH, lL, amH, amL, mid;
   bool   aDone, lDone, amDone;
   int    bullBits, bearBits, bullCnt, bearCnt;
   int    dayGate, eveGate;
   //--- pivots
   SPiv   ph[], pl[];
   double lastPHv, lastPLv; int lastPHi, lastPLi;
   //--- PDA
   SPda   pda[];
   //--- machine à états du setup
   int    mode, gate, liveMode;
   int    swDir, swBar; double swExt, swLvl, mss;
   bool   pdaOk, pdaBrk; double pdaTop, pdaBot;
   string note;
   //--- trades (0 = achat, 1 = vente) et dernier signal
   STrade tr[2];
   int    lastTr;

   void Reset()
     {
      ArrayFree(lines); ArrayFree(boxes); ArrayFree(labels);
      liveL = oldL = liveB = oldB = liveT = oldT = 0;
      tdKey = -1; calKey = -1;
      curH = curL = pdh = pdl = aH = aL = lH = lL = amH = amL = mid = NA;
      aDone = lDone = amDone = false;
      bullBits = bearBits = bullCnt = bearCnt = 0;
      dayGate = eveGate = 0;
      ArrayFree(ph); ArrayFree(pl);
      lastPHv = lastPLv = NA; lastPHi = lastPLi = -1;
      ArrayFree(pda);
      mode = gate = liveMode = 0;
      swDir = 0; swBar = -1; swExt = swLvl = mss = NA;
      pdaOk = pdaBrk = false; pdaTop = pdaBot = NA;
      note = "";
      for(int k = 0; k < 2; k++)
        {
         tr[k].dir = k == 0 ? 1 : -1; tr[k].state = TS_NONE; tr[k].en = tr[k].sl = tr[k].tp = NA; tr[k].bar = -1;
         tr[k].lE = tr[k].lS = tr[k].lT = tr[k].tE = tr[k].tS = tr[k].tT = -1; tr[k].pda = "";
        }
      lastTr = -1;
     }

   void CopyFrom(const CState &o)
     {
      CopyArr(lines, o.lines); CopyArr(boxes, o.boxes); CopyArr(labels, o.labels);
      liveL = o.liveL; oldL = o.oldL; liveB = o.liveB; oldB = o.oldB; liveT = o.liveT; oldT = o.oldT;
      tdKey = o.tdKey; calKey = o.calKey;
      curH = o.curH; curL = o.curL; pdh = o.pdh; pdl = o.pdl; aH = o.aH; aL = o.aL; lH = o.lH; lL = o.lL;
      amH = o.amH; amL = o.amL; mid = o.mid;
      aDone = o.aDone; lDone = o.lDone; amDone = o.amDone;
      bullBits = o.bullBits; bearBits = o.bearBits; bullCnt = o.bullCnt; bearCnt = o.bearCnt;
      dayGate = o.dayGate; eveGate = o.eveGate;
      CopyArr(ph, o.ph); CopyArr(pl, o.pl);
      lastPHv = o.lastPHv; lastPLv = o.lastPLv; lastPHi = o.lastPHi; lastPLi = o.lastPLi;
      CopyArr(pda, o.pda);
      mode = o.mode; gate = o.gate; liveMode = o.liveMode;
      swDir = o.swDir; swBar = o.swBar; swExt = o.swExt; swLvl = o.swLvl; mss = o.mss;
      pdaOk = o.pdaOk; pdaBrk = o.pdaBrk; pdaTop = o.pdaTop; pdaBot = o.pdaBot;
      note = o.note;
      for(int k = 0; k < 2; k++) tr[k] = o.tr[k];
      lastTr = o.lastTr;
     }

   //--- TradingView efface le plus ancien objet au-delà de 500 par type
   int LineNew(double x1, double y1, double x2, double y2, uint clr, int style, int w)
     {
      DLine l; l.x1 = x1; l.y1 = y1; l.x2 = x2; l.y2 = y2; l.clr = clr; l.style = style; l.w = w; l.alive = true;
      Push(lines, l); liveL++;
      while(liveL > MAX_OBJ && oldL < ArraySize(lines)) { if(lines[oldL].alive) { lines[oldL].alive = false; liveL--; } oldL++; }
      return ArraySize(lines) - 1;
     }
   int BoxNew(double x1, double top, double x2, double bot, uint bg, uint bd, int bw)
     {
      DBox b; b.x1 = x1; b.top = top; b.x2 = x2; b.bot = bot; b.bg = bg; b.bd = bd; b.bw = bw; b.alive = true;
      Push(boxes, b); liveB++;
      while(liveB > MAX_OBJ && oldB < ArraySize(boxes)) { if(boxes[oldB].alive) { boxes[oldB].alive = false; liveB--; } oldB++; }
      return ArraySize(boxes) - 1;
     }
   int LabelNew(double x, double y, string text, uint bg, uint tc, int style, int size, bool sym)
     {
      DLabel t; t.x = x; t.y = y; t.text = text; t.bg = bg; t.tc = tc; t.style = style; t.size = size; t.sym = sym; t.alive = true;
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

//--- Données du graphique (fenêtre de InpMaxBars bougies, indice 0 = la plus ancienne)
double   gO[], gH[], gL[], gC[], gATR[];
datetime gT[];
int      gN = 0, gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
CState   gCommit, gWork;
double   gDpi = 1.0;

//--- Heures (minutes depuis minuit, heure de New York), lues une fois
int      gAsiaS, gAsiaE, gLonS, gLonE, gDayS, gDayE, gAmS, gAmE, gEveS, gEveE;
int      gMacS[6], gMacE[6];
bool     gMacOn[6];
int      gNLv = 0;
//--- Décalage du serveur
int      gSrvBase = 0;
bool     gSrvBaseDst = false;

//--- Canvas
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0, gLastWork = 0;
bool     gDirty = false;

//+------------------------------------------------------------------+
//| Heures                                                           |
//+------------------------------------------------------------------+
bool ParseHours(string hours, int &s, int &e)          // « 09:30-12:00 »
  {
   string p[];
   if(StringSplit(hours, '-', p) != 2) return false;
   string a[], b[];
   if(StringSplit(p[0], ':', a) != 2 || StringSplit(p[1], ':', b) != 2) return false;
   s = (int)StringToInteger(a[0]) * 60 + (int)StringToInteger(a[1]);
   e = (int)StringToInteger(b[0]) * 60 + (int)StringToInteger(b[1]);
   return s >= 0 && s < 1440 && e >= 0 && e <= 1440;
  }
bool InRange(int m, int s, int e) { return s <= e ? (m >= s && m < e) : (m >= s || m < e); }

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
//--- heure d'été de New York (2e dimanche de mars -> 1er dimanche de novembre)
bool NyDst(datetime utc)
  {
   MqlDateTime u; TimeToStruct(utc, u);
   return utc >= NthSunday(u.year, 3, 2) + 7 * 3600 && utc < NthSunday(u.year, 11, 1) + 6 * 3600;
  }
//--- heure de Londres et de New York (minutes depuis minuit) d'une heure UTC
int LocalMinutes(datetime utc, bool london)
  {
   MqlDateTime u; TimeToStruct(utc, u);
   int off;
   if(london)
      off = (utc >= NthSunday(u.year, 3, 0) + 3600 && utc < NthSunday(u.year, 10, 0) + 3600) ? 60 : 0;
   else
      off = NyDst(utc) ? -240 : -300;
   int m = u.hour * 60 + u.min + off;
   return (m + 1440) % 1440;
  }
bool InHours(int m, string hours)                    // « 08:00-11:00 »
  {
   int s = 0, e = 0;
   if(!ParseHours(hours, s, e)) return true;
   return InRange(m, s, e);
  }

//--- Décalage du serveur mesuré maintenant (TimeTradeServer reste juste le week-end, TimeCurrent
//    y vaut l'heure du dernier tick). Sur l'historique, un serveur UTC+2/+3 comme FundedNext
//    change d'heure avec New York : on corrige d'une heure selon l'heure d'été américaine.
void InitOffset()
  {
   datetime srv = TimeTradeServer();
   if(srv == 0) srv = TimeCurrent();
   datetime gmt = TimeGMT();
   gSrvBase = (int)MathRound((double)(srv - gmt) / 1800.0) * 1800;
   gSrvBaseDst = NyDst(gmt);
  }
int SrvOffset(datetime srv)
  {
   if(!InpSrvUsDst) return gSrvBase;
   bool d = NyDst(srv - gSrvBase);
   return gSrvBase + ((d ? 1 : 0) - (gSrvBaseDst ? 1 : 0)) * 3600;
  }
//--- heure de New York d'une bougie : minutes, journée de trading (18:00 -> 17:00), date civile
void NyClock(datetime srv, int &nyMin, long &tdKey, long &calKey)
  {
   datetime utc = srv - SrvOffset(srv);
   long ny = (long)utc + (NyDst(utc) ? -4 : -5) * 3600;
   nyMin  = (int)((ny % 86400) / 60);
   calKey = ny / 86400;
   tdKey  = (ny + 6 * 3600) / 86400;
  }

//--- 1 = fenêtre de jour, 2 = mode soir, 0 = hors fenêtre
int ModeAt(int nyMin)
  {
   if(InRange(nyMin, gDayS, gDayE)) return 1;
   if(InpEvening && InRange(nyMin, gEveS, gEveE)) return 2;
   return 0;
  }
//--- macros du mode : aucune activée = toute la fenêtre
bool AnyMacro(int mode)
  {
   int k0 = mode == 2 ? 3 : 0;
   for(int k = k0; k < k0 + 3; k++) if(gMacOn[k]) return true;
   return false;
  }
bool InMacro(int mode, int nyMin)
  {
   if(mode == 0) return false;
   if(!AnyMacro(mode)) return true;
   int k0 = mode == 2 ? 3 : 0;
   for(int k = k0; k < k0 + 3; k++)
      if(gMacOn[k] && InRange(nyMin, gMacS[k], gMacE[k])) return true;
   return false;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpPivLen < 1 || InpGateN < 1 || InpMaxPiv < 1 || InpObLook < 1 || InpPdaBars < 0 || InpPdaLife < 1
      || InpRR < 0.5 || InpRR > 20.0 || InpSwAtr < 0 || InpPdaAtr < 0 || InpMaxBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   gNLv = (InpLvlPD ? 1 : 0) + (InpLvlAsia ? 1 : 0) + (InpLvlLon ? 1 : 0) + (InpLvlMid ? 1 : 0);
   if(gNLv == 0)
     {
      Print("CX Flow : au moins un niveau du gate doit être activé");
      return INIT_PARAMETERS_INCORRECT;
     }
   bool ok = ParseHours(InpAsiaHours, gAsiaS, gAsiaE) && ParseHours(InpLonHours, gLonS, gLonE)
             && ParseHours(InpDayHours, gDayS, gDayE) && ParseHours(InpAmRange, gAmS, gAmE)
             && ParseHours(InpEveHours, gEveS, gEveE)
             && ParseHours(InpMac1, gMacS[0], gMacE[0]) && ParseHours(InpMac2, gMacS[1], gMacE[1])
             && ParseHours(InpMac3, gMacS[2], gMacE[2]) && ParseHours(InpEMac1, gMacS[3], gMacE[3])
             && ParseHours(InpEMac2, gMacS[4], gMacE[4]) && ParseHours(InpEMac3, gMacS[5], gMacE[5]);
   if(!ok)
     {
      Print("CX Flow : heures attendues au format 09:30-12:00");
      return INIT_PARAMETERS_INCORRECT;
     }
   gMacOn[0] = InpMac1On;  gMacOn[1] = InpMac2On;  gMacOn[2] = InpMac3On;
   gMacOn[3] = InpEMac1On; gMacOn[4] = InpEMac2On; gMacOn[5] = InpEMac3On;
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXFLOW_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Flow");
   InitOffset();
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

//+------------------------------------------------------------------+
//| 1. Contexte : bornes de séances et gates                         |
//+------------------------------------------------------------------+
void SessRange(int t, int nyMin, int s, int e, double &hi, double &lo, bool &done)
  {
   if(done) return;
   if(InRange(nyMin, s, e))
     {
      hi = hi == NA ? gH[t] : MathMax(hi, gH[t]);
      lo = lo == NA ? gL[t] : MathMin(lo, gL[t]);
     }
   else if(hi != NA)
      done = true;                     // séance terminée : la borne est connue
  }

void Context(CState &S, int t, int nyMin, long tdKey, long calKey)
  {
   if(tdKey != S.tdKey)
     {
      //--- nouvelle journée de trading (18:00 NY) : la journée finie devient la veille
      if(S.tdKey != -1 && S.curH != NA) { S.pdh = S.curH; S.pdl = S.curL; }
      S.tdKey = tdKey; S.calKey = calKey;
      S.curH = gH[t]; S.curL = gL[t];
      S.aH = S.aL = S.lH = S.lL = S.amH = S.amL = NA;
      S.aDone = S.lDone = S.amDone = false;
      S.mid = nyMin < 18 * 60 ? gO[t] : NA;   // journée qui commence après minuit (trou de données)
      S.bullBits = S.bearBits = 0;
      S.dayGate = S.eveGate = 0;
     }
   else
     {
      S.curH = MathMax(S.curH, gH[t]); S.curL = MathMin(S.curL, gL[t]);
      if(calKey != S.calKey) { S.mid = gO[t]; S.calKey = calKey; }   // ouverture de minuit
     }
   SessRange(t, nyMin, gAsiaS, gAsiaE, S.aH, S.aL, S.aDone);
   SessRange(t, nyMin, gLonS, gLonE, S.lH, S.lL, S.lDone);
   SessRange(t, nyMin, gAmS, gAmE, S.amH, S.amL, S.amDone);

   //--- bornes franchies en clôture (acquis pour la journée)
   double c = gC[t];
   if(InpLvlPD && S.pdh != NA) { if(c > S.pdh) S.bullBits |= 1; if(c < S.pdl) S.bearBits |= 1; }
   if(InpLvlAsia && S.aDone)   { if(c > S.aH)  S.bullBits |= 2; if(c < S.aL)  S.bearBits |= 2; }
   if(InpLvlLon && S.lDone)    { if(c > S.lH)  S.bullBits |= 4; if(c < S.lL)  S.bearBits |= 4; }
   int nb = 0, ns = 0;
   for(int b = 0; b < 3; b++) { if(((S.bullBits >> b) & 1) != 0) nb++; if(((S.bearBits >> b) & 1) != 0) ns++; }
   //--- ouverture de minuit : un seul prix, compté du côté où se trouve la clôture
   if(InpLvlMid && S.mid != NA) { if(c > S.mid) nb++; else if(c < S.mid) ns++; }
   S.bullCnt = nb; S.bearCnt = ns;
   int need = MathMin(InpGateN, gNLv);
   if(S.dayGate == 0)
     {
      if(nb >= need && nb > ns) S.dayGate = 1;
      else if(ns >= need && ns > nb) S.dayGate = -1;
     }
   //--- gate du soir : clôture hors de la plage NY AM terminée
   if(S.amDone && S.eveGate == 0)
     {
      if(c > S.amH) S.eveGate = 1;
      else if(c < S.amL) S.eveGate = -1;
     }
  }

//+------------------------------------------------------------------+
//| 2. Pivots : ruptures (Order Blocks) et sweeps                    |
//+------------------------------------------------------------------+
//--- dernière bougie opposée avant le déplacement (bull : dernière baissière)
int OppositeCandle(int t, int from, bool bull)
  {
   for(int k = t - 1; k >= MathMax(from, t - InpObLook) && k >= 0; k--)
     {
      if(bull && gC[k] < gO[k]) return k;
      if(!bull && gC[k] > gO[k]) return k;
     }
   return -1;
  }

void NewPda(CState &S, int t, int k, int dir)
  {
   for(int i = 0; i < ArraySize(S.pda); i++)
      if(S.pda[i].anchor == k && S.pda[i].dir == dir && !S.pda[i].brk) return;
   SPda p;
   p.top = InpObZone == ObBody ? MathMax(gO[k], gC[k]) : gH[k];
   p.bot = InpObZone == ObBody ? MathMin(gO[k], gC[k]) : gL[k];
   if(p.top - p.bot < _Point) { p.top = gH[k]; p.bot = gL[k]; }   // doji : bougie entière
   p.anchor = k; p.born = t; p.dir = dir; p.brk = false; p.box = -1; p.lbl = -1;
   Push(S.pda, p);
   if(ArraySize(S.pda) > MAX_PDA) RemoveAt(S.pda, 0);
  }

void Pivots(CState &S, int t, double &bullSw, int &bullPiv, double &bearSw, int &bearPiv)
  {
   double buf = gATR[t] == NA ? NA : InpSwAtr * gATR[t];
   int obBull = -1, obBear = -1;
   //--- pivots hauts : clôture au-dessus = rupture (OB haussier) ; mèche au-dessus + clôture dessous = sweep
   for(int i = ArraySize(S.ph) - 1; i >= 0; i--)
     {
      double p = S.ph[i].p;
      if(gC[t] > p)
        {
         int k = OppositeCandle(t, S.ph[i].bar, true);
         if(k > obBull) obBull = k;    // plusieurs ruptures : l'ancre la plus proche
         RemoveAt(S.ph, i);
        }
      else if(buf != NA && gH[t] >= p + buf && gC[t] < p)
        {
         if(bearSw == NA || p > bearSw) { bearSw = p; bearPiv = S.ph[i].bar; }   // le plus extrême
         RemoveAt(S.ph, i);
        }
     }
   //--- pivots bas
   for(int i = ArraySize(S.pl) - 1; i >= 0; i--)
     {
      double p = S.pl[i].p;
      if(gC[t] < p)
        {
         int k = OppositeCandle(t, S.pl[i].bar, false);
         if(k > obBear) obBear = k;
         RemoveAt(S.pl, i);
        }
      else if(buf != NA && gL[t] <= p - buf && gC[t] > p)
        {
         if(bullSw == NA || p < bullSw) { bullSw = p; bullPiv = S.pl[i].bar; }
         RemoveAt(S.pl, i);
        }
     }
   if(obBull >= 0) NewPda(S, t, obBull, 1);
   if(obBear >= 0) NewPda(S, t, obBear, -1);
   //--- nouveaux pivots confirmés
   int L = InpPivLen;
   if(PivotHigh(t, L))
     {
      SPiv v; v.p = gH[t - L]; v.bar = t - L;
      Push(S.ph, v);
      if(ArraySize(S.ph) > InpMaxPiv) RemoveAt(S.ph, 0);
      S.lastPHv = v.p; S.lastPHi = v.bar;
     }
   if(PivotLow(t, L))
     {
      SPiv v; v.p = gL[t - L]; v.bar = t - L;
      Push(S.pl, v);
      if(ArraySize(S.pl) > InpMaxPiv) RemoveAt(S.pl, 0);
      S.lastPLv = v.p; S.lastPLi = v.bar;
     }
  }

//+------------------------------------------------------------------+
//| 3. PDA : invalidation, Breaker Blocks, durée de vie              |
//+------------------------------------------------------------------+
void FreezePda(CState &S, int i, int t)
  {
   if(S.BOk(S.pda[i].box)) S.boxes[S.pda[i].box].x2 = t;
  }

void PdaUpdate(CState &S, int t)
  {
   double c = gC[t];
   for(int i = ArraySize(S.pda) - 1; i >= 0; i--)
     {
      if(t - S.pda[i].born > InpPdaLife) { FreezePda(S, i, t); RemoveAt(S.pda, i); continue; }
      bool through = (S.pda[i].dir == 1 && c < S.pda[i].bot) || (S.pda[i].dir == -1 && c > S.pda[i].top);
      if(through)
        {
         FreezePda(S, i, t);
         if(S.pda[i].brk) { RemoveAt(S.pda, i); continue; }
         //--- OB invalidé par une clôture : même zone, sens inversé
         S.pda[i].brk = true; S.pda[i].dir = -S.pda[i].dir; S.pda[i].born = t;
         S.pda[i].box = -1; S.pda[i].lbl = -1;
         continue;
        }
      if(S.BOk(S.pda[i].box)) S.boxes[S.pda[i].box].x2 = t;
     }
  }

//--- plusieurs PDA du même sens nés sur la même bougie : l'ancre la plus proche est gardée
void Prioritize(CState &S, int t)
  {
   for(int d = -1; d <= 1; d += 2)
     {
      int best = -1;
      for(int i = 0; i < ArraySize(S.pda); i++)
         if(S.pda[i].born == t && S.pda[i].dir == d && (best < 0 || S.pda[i].anchor > S.pda[best].anchor)) best = i;
      if(best < 0) continue;
      int keepAnchor = S.pda[best].anchor;
      bool kept = false;
      for(int i = 0; i < ArraySize(S.pda); i++)
        {
         if(S.pda[i].born != t || S.pda[i].dir != d) continue;
         if(S.pda[i].anchor == keepAnchor && !kept) { kept = true; continue; }
         RemoveAt(S.pda, i); i--;
        }
     }
  }

//--- bougie de référence pour la distance au sweep : ancre de l'OB, bougie de bascule du BB
int PdaRef(CState &S, int i) { return S.pda[i].brk ? S.pda[i].born : S.pda[i].anchor; }

void DrawPda(CState &S, int i, int t)
  {
   if(S.BOk(S.pda[i].box)) return;
   color c = S.pda[i].dir == 1 ? InpPdaBull : InpPdaBear;
   int x1 = PdaRef(S, i);
   S.pda[i].box = S.BoxNew(x1, S.pda[i].top, t, S.pda[i].bot, A(c, InpPdaTransp), A(c, 40), 1);
   S.pda[i].lbl = S.LabelNew(x1, (S.pda[i].top + S.pda[i].bot) / 2, S.pda[i].brk ? "BB" : "OB", 0, A(c, 0), LS_LEFT, tiny, false);
  }

//--- PDA qui qualifient le sweep : sens du setup, type activé, proche en bougies et en prix
void QualifyPdas(CState &S, int t, int &nearI, int &farI)
  {
   nearI = -1; farI = -1;
   double atr = gATR[S.swBar];
   if(atr == NA) return;
   int bestDb = 0;
   for(int i = 0; i < ArraySize(S.pda); i++)
     {
      if(S.pda[i].dir != S.swDir) continue;
      if(S.pda[i].brk ? !InpUseBB : !InpUseOB) continue;
      int db = (int)MathAbs(PdaRef(S, i) - S.swBar);
      if(db > InpPdaBars) continue;
      double dist = S.swExt < S.pda[i].bot ? S.pda[i].bot - S.swExt : S.swExt > S.pda[i].top ? S.swExt - S.pda[i].top : 0.0;
      if(dist > InpPdaAtr * atr) continue;
      DrawPda(S, i, t);                // dessiné dès l'alignement partiel (avant le MSS)
      if(nearI < 0 || db < bestDb || (db == bestDb && PdaRef(S, i) > PdaRef(S, nearI))) { nearI = i; bestDb = db; }
      if(farI < 0 || (S.swDir == 1 ? S.pda[i].bot < S.pda[farI].bot : S.pda[i].top > S.pda[farI].top)) farI = i;
     }
  }

//+------------------------------------------------------------------+
//| 4. Trades : en attente -> actif -> résolu                        |
//+------------------------------------------------------------------+
void TradeDel(CState &S, int k)
  {
   S.LineDel(S.tr[k].lE); S.LineDel(S.tr[k].lS); S.LineDel(S.tr[k].lT);
   S.LabelDel(S.tr[k].tE); S.LabelDel(S.tr[k].tS); S.LabelDel(S.tr[k].tT);
   S.tr[k].lE = S.tr[k].lS = S.tr[k].lT = S.tr[k].tE = S.tr[k].tS = S.tr[k].tT = -1;
  }

void TradeX2(CState &S, int k, double x2)
  {
   if(S.LOk(S.tr[k].lE)) S.lines[S.tr[k].lE].x2 = x2;
   if(S.LOk(S.tr[k].lS)) S.lines[S.tr[k].lS].x2 = x2;
   if(S.LOk(S.tr[k].lT)) S.lines[S.tr[k].lT].x2 = x2;
   if(S.TOk(S.tr[k].tE)) S.labels[S.tr[k].tE].x = x2;
   if(S.TOk(S.tr[k].tS)) S.labels[S.tr[k].tS].x = x2;
   if(S.TOk(S.tr[k].tT)) S.labels[S.tr[k].tT].x = x2;
  }

void Resolve(CState &S, int k, int t, int res)
  {
   S.tr[k].state = res;
   TradeX2(S, k, t);                   // lignes figées
   if(res == TS_WIN && S.TOk(S.tr[k].tT))  S.labels[S.tr[k].tT].text += " · atteint";
   if(res == TS_LOSS && S.TOk(S.tr[k].tS)) S.labels[S.tr[k].tS].text += " · touché";
   if(res == TS_MISSED && S.TOk(S.tr[k].tE)) S.labels[S.tr[k].tE].text += " · non rempli";
  }

void Trades(CState &S, int t)
  {
   for(int k = 0; k < 2; k++)
     {
      int st = S.tr[k].state;
      if(st != TS_PENDING && st != TS_ACTIVE) continue;
      if(t <= S.tr[k].bar) continue;
      int d = S.tr[k].dir;
      bool hitSl = d == 1 ? gL[t] <= S.tr[k].sl : gH[t] >= S.tr[k].sl;
      bool hitTp = d == 1 ? gH[t] >= S.tr[k].tp : gL[t] <= S.tr[k].tp;
      bool hitEn = d == 1 ? gL[t] <= S.tr[k].en : gH[t] >= S.tr[k].en;
      if(st == TS_PENDING)
        {
         if(hitEn)
           {
            S.tr[k].state = TS_ACTIVE;
            if(hitSl) { Resolve(S, k, t, TS_LOSS); continue; }   // même bougie : le stop d'abord
           }
         else if(hitTp) { Resolve(S, k, t, TS_MISSED); continue; }
        }
      else
        {
         if(hitSl) { Resolve(S, k, t, TS_LOSS); continue; }
         if(hitTp) { Resolve(S, k, t, TS_WIN); continue; }
        }
      TradeX2(S, k, t + InpExtend);    // lignes prolongées
     }
  }

//--- swing opposé le plus proche au-delà de ref (pivots encore actifs)
double NearestSwing(CState &S, int d, double ref)
  {
   double best = NA;
   if(d == 1)
     {
      for(int i = 0; i < ArraySize(S.ph); i++)
         if(S.ph[i].p > ref && (best == NA || S.ph[i].p < best)) best = S.ph[i].p;
     }
   else
     {
      for(int i = 0; i < ArraySize(S.pl); i++)
         if(S.pl[i].p < ref && (best == NA || S.pl[i].p > best)) best = S.pl[i].p;
     }
   return best;
  }

bool Signal(CState &S, int t, int nearI, int farI)
  {
   int d = S.swDir;
   double en = d == 1 ? S.pda[nearI].top : S.pda[nearI].bot;           // bord proximal
   double sl = InpSlMode == SlPda ? (d == 1 ? S.pda[farI].bot : S.pda[farI].top) : S.swExt;
   if(d == 1 ? sl >= en : sl <= en) sl = S.swExt;
   if(d == 1 ? sl >= en : sl <= en) return false;
   double risk = MathAbs(en - sl);
   double tp = NA;
   if(InpTpMode == TpSwing) tp = NearestSwing(S, d, d == 1 ? MathMax(en, gC[t]) : MathMin(en, gC[t]));
   if(tp == NA) tp = en + d * InpRR * risk;
   int k = d == 1 ? 0 : 1;
   TradeDel(S, k);                     // anciennes lignes du même sens effacées
   S.tr[k].dir = d; S.tr[k].en = en; S.tr[k].sl = sl; S.tr[k].tp = tp; S.tr[k].bar = t;
   S.tr[k].state = (d == 1 ? gC[t] <= en : gC[t] >= en) ? TS_ACTIVE : TS_PENDING;
   S.tr[k].pda = S.pda[nearI].brk ? "BB" : "OB";
   double x2 = t + InpExtend;
   S.tr[k].lE = S.LineNew(t, en, x2, en, A(InpEnColor, 0), sol, 1);
   S.tr[k].lS = S.LineNew(t, sl, x2, sl, A(InpSlColor, 0), sol, 1);
   S.tr[k].lT = S.LineNew(t, tp, x2, tp, A(InpTpColor, 0), sol, 1);
   S.tr[k].tE = S.LabelNew(x2, en, "Entrée " + Px2(en), A(InpEnColor, 0), A(PC_WHITE, 0), LS_LEFT, tiny, false);
   S.tr[k].tS = S.LabelNew(x2, sl, "SL " + Px2(sl), A(InpSlColor, 0), A(PC_WHITE, 0), LS_LEFT, tiny, false);
   S.tr[k].tT = S.LabelNew(x2, tp, "TP " + Px2(tp), A(InpTpColor, 0), A(PC_WHITE, 0), LS_LEFT, tiny, false);
   if(d == 1) S.LabelNew(t, gL[t], "BUY", A(PC_GREEN, 0), A(PC_WHITE, 0), LS_UP, small, false);
   else       S.LabelNew(t, gH[t], "SELL", A(PC_RED, 0), A(PC_WHITE, 0), LS_DOWN, small, false);
   S.lastTr = k;
   string txt = (d == 1 ? "BUY" : "SELL") + string(" · entrée ") + Px2(en) + " · SL " + Px2(sl) + " · TP " + Px2(tp)
                + " (" + S.tr[k].pda + ", " + (S.mode == 2 ? "soir" : "jour") + ")";
   Ev(d == 1 ? AlBuy : AlSell, txt);
   return true;
  }

//+------------------------------------------------------------------+
//| Machine à états : biais -> sweep -> PDA -> MSS                   |
//+------------------------------------------------------------------+
void ResetSetup(CState &S)
  {
   S.swDir = 0; S.swBar = -1; S.swExt = S.swLvl = S.mss = NA;
   S.pdaOk = S.pdaBrk = false; S.pdaTop = S.pdaBot = NA;
  }

void NewSweep(CState &S, int t, int d, double lvl, int piv)
  {
   S.swDir = d; S.swBar = t; S.swLvl = lvl;
   S.swExt = d == 1 ? gL[t] : gH[t];
   S.pdaOk = false; S.note = "";
   //--- niveau du MSS : le dernier swing opposé formé avant le sweep
   S.mss = NA;
   if(d == 1 && S.lastPHi >= 0 && S.lastPHi < t && S.lastPHv > gC[t]) S.mss = S.lastPHv;
   if(d == -1 && S.lastPLi >= 0 && S.lastPLi < t && S.lastPLv < gC[t]) S.mss = S.lastPLv;
   //--- marqueur unique sur le niveau le plus extrême balayé par la bougie
   uint c = A(InpSwColor, 0);
   S.LineNew(piv, lvl, t, lvl, c, (int)InpSwStyle, InpSwWidth);
   S.LabelNew(t, lvl, "✕", 0, c, LS_CENTER, normal, true);
  }

void Setup(CState &S, int t, int nyMin, int mode, double bullSw, int bullPiv, double bearSw, int bearPiv)
  {
   int gate = mode == 1 ? S.dayGate : mode == 2 ? S.eveGate : 0;
   if(mode != S.mode || gate != S.gate) ResetSetup(S);     // fenêtre ou biais changé : on repart
   S.mode = mode; S.gate = gate;
   if(gate == 0) return;                                   // pas de biais : aucun sweep suivi
   //--- sweep invalidé seulement par une clôture au-delà de sa mèche
   if(S.swDir == 1 && gC[t] < S.swExt) { ResetSetup(S); S.note = "Sweep invalidé"; }
   if(S.swDir == -1 && gC[t] > S.swExt) { ResetSetup(S); S.note = "Sweep invalidé"; }
   if(gate == 1 && bullSw != NA) NewSweep(S, t, 1, bullSw, bullPiv);
   if(gate == -1 && bearSw != NA) NewSweep(S, t, -1, bearSw, bearPiv);
   if(S.swDir == 0) return;
   //--- swing formé après le sweep si aucun n'existait avant
   if(S.mss == NA)
     {
      if(S.swDir == 1 && S.lastPHi > S.swBar) S.mss = S.lastPHv;
      if(S.swDir == -1 && S.lastPLi > S.swBar) S.mss = S.lastPLv;
     }
   int nearI = -1, farI = -1;
   QualifyPdas(S, t, nearI, farI);
   S.pdaOk = nearI >= 0;
   if(!S.pdaOk) return;
   S.pdaBrk = S.pda[nearI].brk; S.pdaTop = S.pda[nearI].top; S.pdaBot = S.pda[nearI].bot;
   //--- MSS : clôture confirmée au-delà du swing, après la bougie du sweep
   if(t <= S.swBar || S.mss == NA) return;
   bool mss = S.swDir == 1 ? gC[t] > S.mss : gC[t] < S.mss;
   if(!mss) return;
   if(!InMacro(mode, nyMin)) { ResetSetup(S); S.note = "MSS hors macro"; return; }
   S.note = Signal(S, t, nearI, farI) ? "" : "Stop incohérent";
   ResetSetup(S);
  }

//+------------------------------------------------------------------+
//| Une exécution sur la bougie t                                    |
//+------------------------------------------------------------------+
void ProcessBar(CState &S, int t, bool confirmed)
  {
   gCurBar = t;
   int nyMin = 0; long tdKey = 0, calKey = 0;
   NyClock(gT[t], nyMin, tdKey, calKey);
   int mode = ModeAt(nyMin);
   S.liveMode = mode;
   if(!confirmed)
     {
      //--- bougie en cours : suivi des trades et prolongement des zones seulement
      Trades(S, t);
      for(int i = 0; i < ArraySize(S.pda); i++)
         if(S.BOk(S.pda[i].box)) S.boxes[S.pda[i].box].x2 = t;
      return;
     }
   Context(S, t, nyMin, tdKey, calKey);
   Trades(S, t);
   PdaUpdate(S, t);
   double bullSw = NA, bearSw = NA;
   int bullPiv = -1, bearPiv = -1;
   Pivots(S, t, bullSw, bullPiv, bearSw, bearPiv);
   Prioritize(S, t);
   Setup(S, t, nyMin, mode, bullSw, bullPiv, bearSw, bearPiv);
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
   if(full)
     {
      InitOffset();
      gBase = MathMax(0, rates_total - InpMaxBars);
      gN = rates_total - gBase;
      ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gT, gN);
      for(int i = 0; i < gN; i++)
        { gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i]; gT[i] = time[gBase + i]; }
      Atr(gATR, 14, 0);
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
      Atr(gATR, 14, from);
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

//--- barClose : heure du serveur de la clôture de la bougie
bool InSession(datetime barClose)
  {
   if(!AlSessions) return true;
   datetime utc = barClose - SrvOffset(barClose);
   return (AlLondon && InHours(LocalMinutes(utc, true), AlLondonHours))
       || (AlNewYork && InHours(LocalMinutes(utc, false), AlNYHours));
  }

void SendAlert(string msg, datetime bar)
  {
   if(!InSession(bar + gPer)) return;
   string tf = gPer < 3600 ? "M" + IntegerToString(gPer / 60) : gPer < 86400 ? "H" + IntegerToString(gPer / 3600)
               : gPer == 86400 ? "D1" : gPer == 604800 ? "W1" : "MN1";
   string txt = "CX Flow " + _Symbol + " " + tf + " " + TimeToString(bar, TIME_MINUTES) + " : " + msg;
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
   if(gDirty && gProcessed >= 0)
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

//--- tailles de texte de TradingView, en dixièmes de point
void SetFont(int size, bool sym)
  {
   int s = size == tiny ? -45 : size == small ? -60 : -75;
   gCv.FontSet(sym ? "Arial" : InpFont, s);
  }

void DrawLabel(const DLabel &lb)
  {
   double ax = XofBar(lb.x);
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
   else if(lb.style == LS_CENTER)
     {
      x1 = (int)MathRound(ax - w / 2.0); top = iy - h / 2;
      if(bg) FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, lb.bg);
     }
   else
     {
      x1 = (int)MathRound(ax - w / 2.0);
      top = lb.style == LS_UP ? iy + ph : iy - ph - h;
      if(bg) { FillPointer(ax, iy, ph + 1, ph, lb.style == LS_UP ? 1 : -1, lb.bg); FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, lb.bg); }
     }
   gCv.TextOut(x1 + w / 2, top + h / 2, lb.text, lb.tc, TA_CENTER | TA_VCENTER);
  }

//+------------------------------------------------------------------+
//| Checklist (style du ticket du Calculateur)                       |
//+------------------------------------------------------------------+
string DirText(int d) { return d == 1 ? "Haussier" : d == -1 ? "Baissier" : "Aucun"; }

void DrawPanel(CState &S)
  {
   if(!InpPanel) return;
   int mode = S.liveMode;
   int gate = mode == 2 ? S.eveGate : S.dayGate;
   int need = MathMin(InpGateN, gNLv);
   bool look = S.swDir != 0 && S.pdaOk;
   string lab[7], val[7];
   uint   vc[7];
   uint   cText = A(UI_TEXT, 0), cMuted = A(UI_MUTED, 0), cGreen = A(PC_GREEN, 0), cRed = A(PC_RED, 0), cOr = A(UI_ORANGE, 0);
   //--- mode
   lab[0] = "Mode";
   val[0] = mode == 1 ? "Jour" : mode == 2 ? "Soir" : "Hors fenêtre";
   vc[0]  = mode != 0 ? cText : cMuted;
   //--- biais
   lab[1] = "Biais";
   if(mode == 2)
      val[1] = DirText(gate) + " · plage NY AM";
   else
      val[1] = DirText(gate) + " · " + IntegerToString(gate == -1 ? S.bearCnt : gate == 1 ? S.bullCnt : MathMax(S.bullCnt, S.bearCnt))
               + "/" + IntegerToString(need) + " niveaux";
   vc[1]  = gate == 1 ? A(UI_BUY_TX, 0) : gate == -1 ? A(UI_SELL_TX, 0) : cMuted;
   //--- fenêtre
   lab[2] = "Fenêtre";
   if(mode == 0) { val[2] = "Fermée"; vc[2] = cMuted; }
   else if(!AnyMacro(mode)) { val[2] = "Ouverte"; vc[2] = cGreen; }
   else
     {
      int nm = 0; long a = 0, b = 0;
      NyClock(gT[gN - 1], nm, a, b);
      bool inMac = InMacro(mode, nm);
      val[2] = inMac ? "Ouverte · macro" : "Ouverte · hors macro";
      vc[2]  = inMac ? cGreen : cOr;
     }
   //--- sweep
   lab[3] = "Sweep";
   if(S.swDir != 0) { val[3] = (S.swDir == 1 ? "Bas pris " : "Haut pris ") + Px2(S.swLvl); vc[3] = cGreen; }
   else { val[3] = gate != 0 && mode != 0 ? "En attente" : "-"; vc[3] = cMuted; }
   //--- PDA
   lab[4] = "PDA";
   if(look) { val[4] = (S.pdaBrk ? "BB " : "OB ") + Px2(S.pdaBot) + " - " + Px2(S.pdaTop); vc[4] = cGreen; }
   else { val[4] = S.swDir != 0 ? "En attente" : "-"; vc[4] = cMuted; }
   //--- MSS
   lab[5] = "MSS";
   if(look && S.mss != NA) { val[5] = "Clôture " + (S.swDir == 1 ? "> " : "< ") + Px2(S.mss); vc[5] = cOr; }
   else { val[5] = look ? "Swing en attente" : "-"; vc[5] = cMuted; }
   //--- dernier trade
   lab[6] = "Trade";
   val[6] = "-"; vc[6] = cMuted;
   if(S.lastTr >= 0)
     {
      int k = S.lastTr, st = S.tr[k].state;
      string side = S.tr[k].dir == 1 ? "BUY" : "SELL";
      val[6] = side + (st == TS_PENDING ? " · en attente" : st == TS_ACTIVE ? " · actif" : st == TS_WIN ? " · TP atteint"
                       : st == TS_LOSS ? " · SL touché" : " · non rempli");
      vc[6]  = st == TS_PENDING || st == TS_ACTIVE ? (S.tr[k].dir == 1 ? cGreen : cRed) : cMuted;
     }
   //--- statut
   string stt = "";
   color  stc = UI_MUTED, stb = UI_TINT_N;
   bool   opened = S.lastTr >= 0 && (S.tr[S.lastTr].state == TS_PENDING || S.tr[S.lastTr].state == TS_ACTIVE);
   if(look) { stt = (S.swDir == 1 ? "Look for Entry · achat" : "Look for Entry · vente"); stc = UI_ORANGE; stb = UI_TINT_O; }
   else if(opened)
     {
      int k = S.lastTr;
      stt = (S.tr[k].dir == 1 ? "BUY" : "SELL") + string(S.tr[k].state == TS_PENDING ? " · ordre à " : " · entré à ") + Px2(S.tr[k].en);
      stc = S.tr[k].dir == 1 ? PC_GREEN : PC_RED; stb = S.tr[k].dir == 1 ? UI_TINT_G : UI_TINT_R;
     }
   else if(mode == 0) stt = "Hors fenêtre de trading";
   else if(gate == 0) stt = "Biais non verrouillé";
   else if(S.swDir == 0) stt = S.note != "" ? S.note : (gate == 1 ? "Attente d'un sweep des bas" : "Attente d'un sweep des hauts");
   else stt = "Sweep sans PDA proche";

   int W = Px(250), pad = Px(10), rh = Px(18), n = 7;
   int x0 = gW - W - Px(12), y0 = Px(12);
   int xL = x0 + pad, xR = x0 + W - pad;
   int infoH = n * rh + Px(10), eh = Px(24);
   int H = Px(34) + infoH + Px(8) + eh + pad;
   FillRect(x0, y0, x0 + W - 1, y0 + H - 1, A(UI_BORDER, 0));
   FillRect(x0 + 1, y0 + 1, x0 + W - 2, y0 + H - 2, A(UI_BG, 0));
   //--- en-tête
   int y = y0 + Px(9);
   gCv.FontSet(InpFont, -90, FW_BOLD);
   gCv.TextOut(xL, y, "CX Flow", A(PC_WHITE, 0), TA_LEFT | TA_TOP);
   gCv.FontSet(InpFont, -70);
   gCv.TextOut(xR, y + Px(2), mode == 2 ? "séance du soir" : "séance de jour", cMuted, TA_RIGHT | TA_TOP);
   y += Px(25);
   //--- libellé à gauche, valeur à droite
   FillRect(xL, y, xR - 1, y + infoH - 1, A(UI_INFO_BG, 0));
   gCv.FontSet(InpFont, -75);
   for(int i = 0; i < n; i++)
     {
      int yy = y + Px(6) + i * rh;
      gCv.TextOut(xL + Px(10), yy, lab[i], cMuted, TA_LEFT | TA_TOP);
      gCv.TextOut(xR - Px(10), yy, val[i], vc[i], TA_RIGHT | TA_TOP);
     }
   y += infoH + Px(8);
   //--- statut
   FillRect(xL, y, xR - 1, y + eh - 1, A(stb, 0));
   gCv.TextOut(xL + Px(8), y + eh / 2, stt, A(stc, 0), TA_LEFT | TA_VCENTER);
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
     { DrawPanel(S); gCv.Update(true); return; }
   gT0 = (gN - 1) - firstShift;                   // indice local de la première bougie visible
   gX0 = xa;
   gSp = xb - xa;
   if(gSp <= 0) gSp = 1 << (int)ChartGetInteger(0, CHART_SCALE);
   gPMax = pMax; gY0 = ya; gKy = (double)(yb - ya) / (pMax - pMin);
   int lw = Wpx(1);

   //--- boîtes (PDA)
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
   //--- lignes (sweeps, Entrée / SL / TP)
   for(int i = 0; i < ArraySize(S.lines); i++)
     {
      if(!S.lines[i].alive) continue;
      double x1 = MathRound(XofBar(S.lines[i].x1)), x2 = MathRound(XofBar(S.lines[i].x2));
      double y1 = MathRound(YofPrice(S.lines[i].y1)), y2 = MathRound(YofPrice(S.lines[i].y2));
      if((y1 < -50 && y2 < -50) || (y1 > H + 50 && y2 > H + 50)) continue;
      DrawLine(x1, y1, x2, y2, S.lines[i].style, Wpx(S.lines[i].w), S.lines[i].clr);
     }
   //--- étiquettes
   for(int i = 0; i < ArraySize(S.labels); i++)
      if(S.labels[i].alive) DrawLabel(S.labels[i]);
   DrawPanel(S);
   gCv.Update(true);
   gLastRender = GetTickCount();
   gDirty = false;
  }
//+------------------------------------------------------------------+
