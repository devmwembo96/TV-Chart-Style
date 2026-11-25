//+------------------------------------------------------------------+
//| CX_Systeme.mq5                                                   |
//| CX Système NAS100 · version épurée                               |
//|  • Liquidity Grab (SFP) comme sur TradingView (CX LGrab) :       |
//|    swing de N bougies, mèche au-delà et clôture revenue dedans ; |
//|    trait du swing jusqu'au SFP, mèche en pointillés, « ✕ ».      |
//|    SFP invalidé (clôture au-delà de la mèche) : effacé ou pâle.  |
//|    Validation optionnelle par le volume de l'UT inférieure.      |
//|  • Carte de liquidité, heure de New York : PDH/PDL, PWH/PWL,     |
//|    sessions Asia, London, NY AM, Lunch, NY PM, opens.            |
//|  • FVG M15 / H1 non comblés (activables).                        |
//|  • Petit tableau comme sur TradingView.                          |
//| Indicateur seul : aucun ordre. Bougies clôturées uniquement.     |
//+------------------------------------------------------------------+
#property copyright   "CX Système"
#property version     "2.01"
#property description "CX Système NAS100 : Liquidity Grab (SFP) façon TradingView, carte de liquidité (heure de New York), FVG M15 / H1, petit tableau et alertes."
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
enum ENUM_LTF    { LtfAuto = 0,       // Auto
                   LtfM1 = 1,         // M1
                   LtfM5 = 5,         // M5
                   LtfM15 = 15        // M15
                 };

input group "Swing Failure Pattern"
input bool     InpShowSfp  = true;            // Show SFP
input int      InpSfpLen   = 5;               // Swings (bougies de chaque côté)
input group "Validation par le volume (UT inférieure)"
input bool     InpUseVal   = false;           // Valider les SFP par le volume
input ENUM_LTF InpLtf      = LtfAuto;         // UT inférieure
input double   InpValThr   = 10.0;            // Seuil de volume hors swing (%)
input group "Style"
input bool     InpShowLbl  = true;            // Show Label (✕)
input color    ColBull     = C'8,153,129';    // Lines / Labels haussier
input color    ColBear     = C'242,54,69';    // Lines / Labels baissier
input int      InpWickT    = 75;              // SFP Wicks : transparence (%)
input bool     InpSfpHist  = false;           // Show History (Invalidated SFPs)
input group "Market Structure (tendance du tableau)"
input int      InpPivLen   = 3;               // Pivot Strength
input group "Carte (niveaux, heure de New York)"
input bool     InpSrvUsDst = true;            // Le courtier suit l'heure d'été US (GMT+2 / GMT+3)
input bool     InpShowDay  = true;            // PDH / PDL
input bool     InpShowWeek = true;            // PWH / PWL
input bool     InpShowSess = true;            // Sessions : Asia, London, NY AM, Lunch, NY PM
input bool     InpShowOpen = true;            // Opens 00:00 / 08:30 / 09:30
input bool     InpShowTaken = true;           // Garder les niveaux pris (traits pâles)
input color    ColDay      = C'76,175,80';    // PDH / PDL
input color    ColWeek     = C'0,188,212';    // PWH / PWL
input color    ColSess     = C'120,123,134';  // Sessions
input color    ColOpen     = C'120,123,134';  // Opens
input group "FVG M15 / H1"
input bool     InpShowFvg  = true;            // Afficher les FVG M15 / H1
input bool     InpFvgM15   = true;            // FVG M15
input bool     InpFvgH1    = true;            // FVG H1
input int      InpFvgMax   = 2;               // FVG affichés de chaque côté du prix (les plus proches)
input double   InpFvgMaxAtr = 2.0;            // Taille max d'un FVG (× ATR H1) : ignore les gaps géants
input color    ColFvg      = C'41,98,255';    // Couleur des FVG
input group "Tableau et alertes"
input bool     InpShowDash = true;            // Afficher le tableau
input ENUM_PANPOS InpPanPos = PanTopRight;    // Position du tableau
input bool     AlSfp       = true;            // Alerte sur chaque SFP
input bool     AlPopup     = true;            // Alerte : fenêtre et son MT5
input bool     AlPush      = true;            // Alerte : notification mobile (MetaQuotes ID)
input group "MT5"
input int      InpMaxBars  = 5000;            // Bougies calculées
input string   InpFont     = "Trebuchet MS";  // Police

#define NA        EMPTY_VALUE
#define NAI       -1
#define NSLOT     17
#define MAX_SFP   150
#define S_PDH 0
#define S_PDL 1
#define S_PWH 2
#define S_PWL 3
#define S_SES 4
#define S_O00 14
#define S_O830 15
#define S_O930 16

//--- symboles construits à l'exécution : le fichier peut être enregistré en ANSI par MetaEditor
string gUp, gDn, gX;
string gSessName[5] = {"Asia", "London", "NY AM", "Lunch", "NY PM"};

template<typename T> void Push(T &a[], const T &v) { int n = ArraySize(a); ArrayResize(a, n + 1, 64); a[n] = v; }

struct Slot
  {
   string name;
   double price;
   int    x0;
   int    kind;                   // 1 haut, -1 bas, 0 open
   bool   taken;
   int    xTaken;
   int    grp;                    // 0 jour, 1 semaine, 2 session, 3 open
  };

struct HZone
  {
   datetime ts, tc, tf;
   double   top, bot;
   int      dir, tfMin;
  };

struct Mark                       // repère texte (✕ du SFP)
  {
   int    x;
   double y;
   string text;
   uint   tc;
   uint   bg;
   int    up;
   bool   sym;
  };

struct Sfp                        // un Liquidity Grab dessiné
  {
   int    dir;                    // 1 haussier (liquidité basse prise), -1 baissier
   double lvl, ext;
   int    xLvl, x;
   bool   alive;                  // false = invalidé
  };

class CState
  {
public:
   Slot   slot[NSLOT];
   Sfp    sfps[];
   long   curDay, curWeek;
   double dHi, dLo, wHi, wLo, sHi, sLo;
   int    dStart, wStart, sStart, curSess, prevMins;
   //--- swings du SFP
   double lvlH, lvlL;
   int    lvlHB, lvlLB;
   //--- structure (tendance du tableau)
   double msH, msL;
   int    trend;
   //--- dernier SFP
   int    lastDir;
   double lastVol;

   void Reset()
     {
      for(int i = 0; i < NSLOT; i++)
        {
         slot[i].name = ""; slot[i].price = NA; slot[i].x0 = NAI; slot[i].kind = 0;
         slot[i].taken = false; slot[i].xTaken = NAI; slot[i].grp = 0;
        }
      ArrayFree(sfps);
      curDay = curWeek = -1;
      dHi = wHi = sHi = -DBL_MAX; dLo = wLo = sLo = DBL_MAX;
      dStart = wStart = sStart = 0; curSess = -1; prevMins = -1;
      lvlH = lvlL = NA; lvlHB = lvlLB = NAI;
      msH = msL = NA; trend = 0;
      lastDir = 0; lastVol = NA;
     }
  };

double   gO[], gH[], gL[], gC[];
datetime gT[];
int      gN = 0, gBase = 0, gTotal = 0, gProcessed = -1, gPer = 60;
CState   gS;
double   gDpi = 1.0;
HZone    gHz[];
double   gH1Atr = 0;
long     gSrvOffNow = 0;
int      gLx[], gLy[];
string   gLt[];
uint     gLc[];
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0;
uint     gLastRender = 0;
bool     gDirty = false;
bool     gAlertLive = false;
string   gAlertBuf = "";
double   gX0 = 0, gSp = 1, gY0 = 0, gKy = 0, gPMax = 0;
int      gT0 = 0;

int    Px(double v)  { return (int)MathRound(v * gDpi); }
int    Wpx(int w)    { return MathMax(1, (int)MathFloor(w * gDpi)); }
double XofBar(double b) { return gX0 + (b - gT0) * gSp; }
double YofPrice(double p) { return gY0 + (gPMax - p) * gKy; }

uint A(const color c, const int transp)
  {
   return ColorToARGB(c, (uchar)MathRound(255.0 * (100 - MathMax(0, MathMin(100, transp))) / 100.0));
  }

datetime NthSunday(int y, int m, int n)
  {
   MqlDateTime d; ZeroMemory(d);
   d.year = y; d.mon = m; d.day = 1;
   datetime t = StructToTime(d);
   TimeToStruct(t, d);
   int first = (7 - d.day_of_week) % 7;            // jours jusqu'au 1er dimanche
   return t + (datetime)((first + 7 * (n - 1)) * 86400);
  }

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

void HtfFvg(const MqlRates &r[], int n, int per, int tfMin)
  {
   for(int k = 2; k < n; k++)
     {
      int dir = 0;
      double top = 0, bot = 0;
      if(r[k].low > r[k - 2].high && r[k - 1].close > r[k - 2].high) { dir = 1;  top = r[k].low;     bot = r[k - 2].high; }
      if(r[k].high < r[k - 2].low && r[k - 1].close < r[k - 2].low)  { dir = -1; top = r[k - 2].low; bot = r[k].high; }
      if(dir == 0) continue;
      if(gH1Atr > 0 && top - bot > InpFvgMaxAtr * gH1Atr) continue;
      HZone z;
      z.ts = r[k - 2].time; z.tc = r[k].time + per; z.tf = 0;
      z.top = top; z.bot = bot; z.dir = dir; z.tfMin = tfMin;
      for(int j = k + 1; j < n; j++)
         if(dir == 1 ? r[j].low <= bot : r[j].high >= top) { z.tf = r[j].time + per; break; }
      if(gN > 0 && z.tf != 0 && z.tf < gT[0]) continue;
      Push(gHz, z);
     }
  }

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

void SetSlot(CState &S, int k, string name, double price, int x0, int kind, int grp)
  {
   S.slot[k].name = name; S.slot[k].price = price; S.slot[k].x0 = x0; S.slot[k].kind = kind;
   S.slot[k].taken = false; S.slot[k].xTaken = NAI; S.slot[k].grp = grp;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(gCvOk) gCv.Destroy();
   gCvOk = false;
   ChartRedraw();
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

void HLevel(int x1, int x2, double y, uint c, int style, string txt, bool txtRight)
  {
   if(y == NA) return;
   double yy = MathRound(YofPrice(y));
   if(yy < -20 || yy > gHh + 20) return;
   double a = MathRound(XofBar(x1)), b = MathRound(XofBar(x2));
   if(b < 0 || a > gW) return;
   DrawLine(a, yy, b, yy, style, Wpx(1), c);
   if(txt != "" && txtRight)
      AddRightLabel((int)b + Px(4), (int)yy, txt, c);
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

void AddRightLabel(int x, int y, string txt, uint c)
  {
   int n = ArraySize(gLt);
   ArrayResize(gLx, n + 1); ArrayResize(gLy, n + 1); ArrayResize(gLt, n + 1); ArrayResize(gLc, n + 1);
   gLx[n] = x; gLy[n] = y; gLt[n] = txt; gLc[n] = c;
  }

void FlushRightLabels()
  {
   int n = ArraySize(gLt);
   for(int i = 0; i < n; i++)
      for(int j = i + 1; j < n; j++)
         if(gLy[j] < gLy[i])
           {
            int a = gLy[i]; gLy[i] = gLy[j]; gLy[j] = a;
            a = gLx[i]; gLx[i] = gLx[j]; gLx[j] = a;
            string b = gLt[i]; gLt[i] = gLt[j]; gLt[j] = b;
            uint c = gLc[i]; gLc[i] = gLc[j]; gLc[j] = c;
           }
   SetFont(tiny, true);
   int gap = Px(10);
   int i = 0;
   while(i < n)
     {
      string txt = gLt[i];
      int x = gLx[i], ySum = gLy[i], cnt = 1, j = i + 1;
      while(j < n && gLy[j] - gLy[j - 1] < gap)
        {
         if(StringFind(txt, gLt[j]) < 0) txt += " · " + gLt[j];
         x = MathMax(x, gLx[j]); ySum += gLy[j]; cnt++; j++;
        }
      gCv.TextOut(x, ySum / cnt, txt, gLc[i], TA_LEFT | TA_VCENTER);
      i = j;
     }
   ArrayFree(gLx); ArrayFree(gLy); ArrayFree(gLt); ArrayFree(gLc);
  }

color SlotColor(int grp) { return grp == 0 ? ColDay : grp == 1 ? ColWeek : grp == 2 ? ColSess : ColOpen; }

bool  SlotShown(int grp) { return grp == 0 ? InpShowDay : grp == 1 ? InpShowWeek : grp == 2 ? InpShowSess : InpShowOpen; }

//+------------------------------------------------------------------+
//| Unités supérieures : FVG M15 / H1                                |
//+------------------------------------------------------------------+
bool LoadHtf()
  {
   ArrayFree(gHz);
   if(!InpShowFvg) return true;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, PERIOD_H1, 0, 3000, r);
   if(n < 120) return false;
   double rs = 0; int rc = 0;
   for(int i = MathMax(0, n - 100); i < n; i++) { rs += r[i].high - r[i].low; rc++; }
   gH1Atr = rc > 0 ? rs / rc : 0;
   if(InpFvgH1) HtfFvg(r, n, 3600, 60);
   if(InpFvgM15)
     {
      n = CopyRates(_Symbol, PERIOD_M15, 0, 4000, r);
      if(n < 50) return false;
      HtfFvg(r, n, 900, 15);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Volume de l'UT inférieure traité au-delà du swing (%)            |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES LtfPeriod()
  {
   if(InpLtf == LtfM1) return PERIOD_M1;
   if(InpLtf == LtfM5) return PERIOD_M5;
   if(InpLtf == LtfM15) return PERIOD_M15;
   return gPer <= 900 ? PERIOD_M1 : gPer <= 3600 ? PERIOD_M5 : PERIOD_M15;
  }

string LtfName()
  {
   ENUM_TIMEFRAMES p = LtfPeriod();
   string s = p == PERIOD_M1 ? "M1" : p == PERIOD_M5 ? "M5" : "M15";
   return s + (InpLtf == LtfAuto ? " (auto)" : "");
  }

double OutVolPct(int t, double lvl, int dir)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, LtfPeriod(), gT[t], gT[t] + gPer - 1, r);
   if(n <= 0) return NA;
   double tot = 0, out = 0;
   for(int i = 0; i < n; i++)
     {
      double v = (double)r[i].tick_volume;
      tot += v;
      if(dir == 1 ? r[i].low < lvl : r[i].high > lvl) out += v;
     }
   return tot > 0 ? out / tot * 100.0 : NA;
  }

//+------------------------------------------------------------------+
//| Une bougie clôturée                                              |
//+------------------------------------------------------------------+
void ProcessBar(CState &S, int t)
  {
   //------------------------------------------------ carte (heure de New York)
   datetime ny = ToNy(gT[t]);
   MqlDateTime nd; TimeToStruct(ny, nd);
   int  mins = nd.hour * 60 + nd.min;
   long tday = (long)((ny + 6 * 3600) / 86400);
   long week = (tday + 3) / 7;
   if(t == 0) { S.curDay = tday; S.curWeek = week; }
   if(tday != S.curDay)
     {
      if(S.dHi > -DBL_MAX) { SetSlot(S, S_PDH, "PDH", S.dHi, S.dStart, 1, 0); SetSlot(S, S_PDL, "PDL", S.dLo, S.dStart, -1, 0); }
      S.curDay = tday; S.dStart = t; S.dHi = -DBL_MAX; S.dLo = DBL_MAX;
     }
   if(week != S.curWeek)
     {
      if(S.wHi > -DBL_MAX) { SetSlot(S, S_PWH, "PWH", S.wHi, S.wStart, 1, 1); SetSlot(S, S_PWL, "PWL", S.wLo, S.wStart, -1, 1); }
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
   //--- liquidité de la carte prise par une mèche
   for(int k = 0; k < NSLOT; k++)
     {
      if(S.slot[k].price == NA || S.slot[k].taken || S.slot[k].kind == 0 || S.slot[k].x0 >= t) continue;
      if((S.slot[k].kind == -1 && gL[t] < S.slot[k].price) || (S.slot[k].kind == 1 && gH[t] > S.slot[k].price))
        { S.slot[k].taken = true; S.slot[k].xTaken = t; }
     }

   //------------------------------------------------ Liquidity Grab (SFP), logique de CX LGrab
   if(PivotHigh(gH, t, InpSfpLen)) { S.lvlH = gH[t - InpSfpLen]; S.lvlHB = t - InpSfpLen; }
   if(PivotLow(gL, t, InpSfpLen))  { S.lvlL = gL[t - InpSfpLen]; S.lvlLB = t - InpSfpLen; }
   bool rawBear = S.lvlH != NA && gH[t] > S.lvlH && gC[t] < S.lvlH && gO[t] < S.lvlH;
   bool rawBull = S.lvlL != NA && gL[t] < S.lvlL && gC[t] > S.lvlL && gO[t] > S.lvlL;
   double bearVol = rawBear ? OutVolPct(t, S.lvlH, -1) : NA;
   double bullVol = rawBull ? OutVolPct(t, S.lvlL, 1) : NA;
   bool bearSfp = rawBear && (!InpUseVal || bearVol == NA || bearVol >= InpValThr);
   bool bullSfp = rawBull && (!InpUseVal || bullVol == NA || bullVol >= InpValThr);
   if(bearSfp)
     {
      Sfp s; s.dir = -1; s.lvl = S.lvlH; s.ext = gH[t]; s.xLvl = S.lvlHB; s.x = t; s.alive = true;
      Push(S.sfps, s);
      S.lastDir = -1; S.lastVol = bearVol;
      Ev(AlSfp, "Liquidity Grab baissier (SFP) " + Px2(S.lvlH));
      S.lvlH = NA;
     }
   if(bullSfp)
     {
      Sfp s; s.dir = 1; s.lvl = S.lvlL; s.ext = gL[t]; s.xLvl = S.lvlLB; s.x = t; s.alive = true;
      Push(S.sfps, s);
      S.lastDir = 1; S.lastVol = bullVol;
      Ev(AlSfp, "Liquidity Grab haussier (SFP) " + Px2(S.lvlL));
      S.lvlL = NA;
     }
   if(ArraySize(S.sfps) > MAX_SFP) ArrayRemove(S.sfps, 0, 1);
   //--- clôture au-delà du swing : vraie cassure, la liquidité est consommée
   if(S.lvlH != NA && gC[t] > S.lvlH) S.lvlH = NA;
   if(S.lvlL != NA && gC[t] < S.lvlL) S.lvlL = NA;
   //--- invalidation : clôture au-delà de la mèche du SFP
   for(int i = 0; i < ArraySize(S.sfps); i++)
      if(S.sfps[i].alive && S.sfps[i].x < t && (S.sfps[i].dir == 1 ? gC[t] < S.sfps[i].ext : gC[t] > S.sfps[i].ext))
         S.sfps[i].alive = false;

   //------------------------------------------------ tendance de structure (pour le tableau)
   if(PivotHigh(gH, t, InpPivLen)) S.msH = gH[t - InpPivLen];
   if(PivotLow(gL, t, InpPivLen))  S.msL = gL[t - InpPivLen];
   if(S.msH != NA && gC[t] > S.msH) { S.trend = 1;  S.msH = NA; }
   if(S.msL != NA && gC[t] < S.msL) { S.trend = -1; S.msL = NA; }

   //------------------------------------------------ hauts / bas en cours
   S.dHi = MathMax(S.dHi, gH[t]); S.dLo = MathMin(S.dLo, gL[t]);
   S.wHi = MathMax(S.wHi, gH[t]); S.wLo = MathMin(S.wLo, gL[t]);
   if(S.curSess >= 0) { S.sHi = MathMax(S.sHi, gH[t]); S.sLo = MathMin(S.sLo, gL[t]); }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpMaxBars < 500 || InpSfpLen < 2 || InpPivLen < 1)
      return INIT_PARAMETERS_INCORRECT;
   gUp = ShortToString(0x25B2); gDn = ShortToString(0x25BC); gX = ShortToString(0x2715);
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXSYS_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Système");
   gProcessed = -1;
   EventSetMillisecondTimer(100);
   return INIT_SUCCEEDED;
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
   if(full) { gBase = MathMax(0, rates_total - InpMaxBars); gN = rates_total - gBase; }
   else     { from = gN - 1; gN = rates_total - gBase; }
   ArrayResize(gO, gN); ArrayResize(gH, gN); ArrayResize(gL, gN); ArrayResize(gC, gN); ArrayResize(gT, gN);
   for(int i = from; i < gN; i++)
     {
      gO[i] = open[gBase + i]; gH[i] = high[gBase + i]; gL[i] = low[gBase + i]; gC[i] = close[gBase + i];
      gT[i] = time[gBase + i];
     }
   gTotal = rates_total;
   bool newBar = full || gProcessed < gN - 1;
   if(newBar)
     {
      gSrvOffNow = (long)MathRound((double)(TimeTradeServer() - TimeGMT()) / 1800.0) * 1800;
      if(!LoadHtf()) { gProcessed = -1; return 0; }
     }
   if(full) { gS.Reset(); gProcessed = 0; }
   while(gProcessed < gN - 1)
     {
      gAlertLive = !full && gProcessed >= gN - 3;
      gAlertBuf = "";
      ProcessBar(gS, gProcessed);
      gAlertLive = false;
      if(gAlertBuf != "") SendAlert(gAlertBuf, gT[gProcessed]);
      gProcessed++;
     }
   if(newBar || GetTickCount() - gLastRender >= 500)
      Render();
   return rates_total;
  }

//+------------------------------------------------------------------+
//| Dessin                                                           |
//+------------------------------------------------------------------+
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

   //--- FVG M15 / H1 : ceux qui contiennent le prix + les plus proches de chaque côté
   if(InpShowFvg)
     {
      datetime nowT = gT[last] + gPer;
      double px = gC[last];
      int cand[]; double dist[]; int side[];
      for(int i = 0; i < ArraySize(gHz); i++)
        {
         if(gHz[i].tf != 0 && gHz[i].tf <= nowT) continue;
         if(gHz[i].ts < gT[0] || gHz[i].tc > nowT) continue;
         int sd = gHz[i].bot > px ? 1 : gHz[i].top < px ? -1 : 0;
         int n = ArraySize(cand);
         ArrayResize(cand, n + 1); ArrayResize(dist, n + 1); ArrayResize(side, n + 1);
         cand[n] = i; side[n] = sd; dist[n] = sd == 1 ? gHz[i].bot - px : sd == -1 ? px - gHz[i].top : 0.0;
        }
      for(int sd = -1; sd <= 1; sd++)
        {
         int shown = 0;
         while(true)
           {
            int best = -1;
            for(int j = 0; j < ArraySize(cand); j++)
               if(cand[j] >= 0 && side[j] == sd && (best < 0 || dist[j] < dist[best])) best = j;
            if(best < 0 || (sd != 0 && shown >= InpFvgMax)) break;
            int i = cand[best];
            cand[best] = -1; shown++;
            DrawBox(BarAt(gHz[i].ts), ext, gHz[i].top, gHz[i].bot, A(ColFvg, gHz[i].tfMin == 60 ? 85 : 90), A(ColFvg, 70));
            AddRightLabel((int)MathRound(XofBar(ext)) + Px(4), (int)MathRound(YofPrice((gHz[i].top + gHz[i].bot) / 2.0)), gHz[i].tfMin == 60 ? "FVG H1" : "FVG M15", A(ColFvg, 30));
           }
        }
     }

   //--- carte
   for(int k = 0; k < NSLOT; k++)
     {
      Slot s = gS.slot[k];
      if(s.price == NA || !SlotShown(s.grp)) continue;
      color c = SlotColor(s.grp);
      if(s.taken)
        {
         if(InpShowTaken) HLevel(s.x0, s.xTaken, s.price, A(c, 65), sol, "", false);
         continue;
        }
      HLevel(s.x0, ext, s.price, A(c, s.grp == 3 ? 40 : 10), sol, s.name, true);
     }

   //--- Liquidity Grab : trait du swing, mèche en pointillés, ✕
   if(InpShowSfp)
      for(int i = 0; i < ArraySize(gS.sfps); i++)
        {
         Sfp f = gS.sfps[i];
         if(!f.alive && !InpSfpHist) continue;
         color c = f.dir == 1 ? ColBull : ColBear;
         int tl = f.alive ? 0 : 75;
         HLevel(f.xLvl, f.x, f.lvl, A(c, tl), sol, "", false);
         //--- mèche : boîte de x-1 à x+1, fond transparent, bord pointillé
         int bx1 = (int)MathRound(XofBar(f.x - 1)), bx2 = (int)MathRound(XofBar(f.x + 1));
         int by1 = (int)MathRound(YofPrice(MathMax(f.lvl, f.ext))), by2 = (int)MathRound(YofPrice(MathMin(f.lvl, f.ext)));
         if(bx2 >= 0 && bx1 <= W && by2 >= 0 && by1 <= H)
           {
            FillRect(bx1, by1, bx2, by2, A(c, f.alive ? InpWickT : 95));
            uint bc = A(c, f.alive ? 0 : 75);
            DrawLine(bx1, by1, bx2, by1, dot, 1, bc);
            DrawLine(bx1, by2, bx2, by2, dot, 1, bc);
            DrawLine(bx1, by1, bx1, by2, dot, 1, bc);
            DrawLine(bx2, by1, bx2, by2, dot, 1, bc);
           }
         if(InpShowLbl)
           {
            Mark m;
            m.x = f.x; m.text = gX; m.tc = A(c, tl); m.bg = 0; m.sym = true;
            m.up = f.dir == 1 ? 1 : 0;
            m.y = f.dir == 1 ? gL[f.x] : gH[f.x];
            DrawMark(m);
           }
        }

   FlushRightLabels();
   if(InpShowDash) DrawPanel();
   gCv.Update(true);
   gLastRender = GetTickCount();
   gDirty = false;
  }

//+------------------------------------------------------------------+
//| Petit tableau (comme CX LGrab sur TradingView)                   |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   long bgl = ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int lum = ((int)(bgl & 0xFF) * 299 + (int)((bgl >> 8) & 0xFF) * 587 + (int)((bgl >> 16) & 0xFF) * 114) / 1000;
   bool dark = lum < 128;
   uint bg  = dark ? A(C'19,23,34', 10) : A(C'255,255,255', 10);
   uint grid = dark ? A(C'255,255,255', 85) : A(C'19,23,34', 85);
   uint txt = dark ? A(C'209,212,220', 0) : A(C'19,23,34', 0);
   uint mut = dark ? A(C'209,212,220', 40) : A(C'19,23,34', 40);
   string k[4], v[4]; uint vc[4];
   k[0] = "Liquidity Grab";
   v[0] = gS.trend == 1 ? gUp + " Haussier" : gS.trend == -1 ? gDn + " Baissier" : "—";
   vc[0] = gS.trend == 1 ? A(ColBull, 0) : gS.trend == -1 ? A(ColBear, 0) : mut;
   k[1] = "UT inférieure";      v[1] = LtfName(); vc[1] = txt;
   k[2] = "Validation volume";  v[2] = InpUseVal ? "Active >= " + DoubleToString(InpValThr, 0) + " %" : "Désactivée"; vc[2] = InpUseVal ? txt : mut;
   k[3] = "Dernier SFP";
   v[3] = gS.lastDir == 0 ? "—" : (gS.lastDir == 1 ? gUp + " " : gDn + " ") + (gS.lastVol == NA ? "vol. n/d" : DoubleToString(gS.lastVol, 1) + " % hors swing");
   vc[3] = gS.lastDir == 1 ? A(ColBull, 0) : gS.lastDir == -1 ? A(ColBear, 0) : mut;
   gCv.FontSet("Segoe UI Symbol", -75);
   int kw = 0, vw = 0, th = 0, tw = 0, tth = 0;
   for(int i = 0; i < 4; i++)
     {
      gCv.TextSize(k[i], tw, tth); kw = MathMax(kw, tw); th = MathMax(th, tth);
      gCv.TextSize(v[i], tw, tth); vw = MathMax(vw, tw);
     }
   int pad = Px(6), rowH = th + Px(6);
   int c1 = kw + 2 * pad, c2 = vw + 2 * pad;
   int w = c1 + c2, h = 4 * rowH;
   int m = Px(8);
   int x0 = (InpPanPos == PanTopLeft || InpPanPos == PanBottomLeft) ? m : gW - w - m - Px(60);
   int y0 = (InpPanPos == PanBottomLeft || InpPanPos == PanBottomRight) ? gHh - h - m - Px(20) : m;
   FillRect(x0, y0, x0 + w, y0 + h, bg);
   //--- quadrillage de 1 px comme les tableaux TradingView
   for(int i = 0; i <= 4; i++) FillRect(x0, y0 + i * rowH, x0 + w, y0 + i * rowH, grid);
   FillRect(x0, y0, x0, y0 + h, grid);
   FillRect(x0 + c1, y0, x0 + c1, y0 + h, grid);
   FillRect(x0 + w, y0, x0 + w, y0 + h, grid);
   for(int i = 0; i < 4; i++)
     {
      int yy = y0 + i * rowH + rowH / 2;
      gCv.FontSet("Segoe UI Symbol", i == 0 ? -80 : -75, i == 0 ? FW_BOLD : FW_NORMAL);
      gCv.TextOut(x0 + pad, yy, k[i], i == 0 ? txt : mut, TA_LEFT | TA_VCENTER);
      gCv.TextOut(x0 + c1 + c2 / 2, yy, v[i], vc[i], TA_CENTER | TA_VCENTER);
     }
  }
//+------------------------------------------------------------------+
