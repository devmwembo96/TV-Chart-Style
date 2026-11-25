//+------------------------------------------------------------------+
//| CX_Signal.mq5                                                    |
//| CX Signal · signaux BUY / SELL avec SL et TP                     |
//| Mélange retenu par l'étude CX Système + CX Press (notes/26) :    |
//|   1. CX Système : un niveau de la carte est pris par une mèche   |
//|      (PDH/PDL, PWH/PWL, haut / bas de session, heure de NY) ;    |
//|   2. CX Press : un Strong Trend démarre dans le sens de cette    |
//|      cassure, au plus 12 bougies après ;                         |
//|   3. en NY AM (07:00 – 11:30 New York) ; UT des signaux M15.     |
//|   Entrée à la clôture, SL = 2 ATR(14), TP = 1 × SL, pause 6.     |
//| + Signal « croix ratée » (notes/27), étiquette « BUY ✕ / SELL ✕ »:|
//|   croix ✕ (SFP de CX Système) contre le Core de CX Press, encore |
//|   valide à la clôture de la bougie suivante -> suivre le Core.   |
//|   Entrée à cette clôture, SL = 1 ATR(14), TP = 2 × SL, pause 6.  |
//| Calculs recopiés de CX_Press.mq5 1.01 et CX sys.mq5 2.01.        |
//| Dessin façon CX AVPT, épuré. Indicateur seul : aucun ordre.      |
//+------------------------------------------------------------------+
#property copyright   "CX Signal"
#property version     "1.10"
#property description "CX Signal : BUY / SELL quand un Strong Trend de CX Press suit une prise de liquidité de CX Système (NY AM), avec SL et TP."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas\Canvas.mqh>

input group "1. Signal (étude notes/26)"
input ENUM_TIMEFRAMES InpSigTf = PERIOD_M15;   // UT des signaux
input int    InpWindow    = 12;                // Prise de la carte : au plus N bougies avant le Strong
input bool   InpNyAmOnly  = true;              // Seulement en NY AM (07:00 – 11:30 New York)
input int    InpPause     = 6;                 // Bougies sans nouveau signal après un signal
input double InpSlAtr     = 2.0;               // SL (× ATR 14)
input double InpTpR       = 1.0;               // TP (× SL)
input int    InpHorizon   = 48;                // Fin du plan sans TP ni SL (bougies de l'UT des signaux)
input group "1b. Signal « croix ratée » (étude notes/27)"
input bool   InpUseCross  = true;              // Afficher les signaux « croix ratée » (✕)
input double InpSlAtr2    = 1.0;               // SL (× ATR 14)
input double InpTpR2      = 2.0;               // TP (× SL)
input group "2. CX Press (réglages de l'indicateur)"
input int    InpCandleLen = 14;                // Candle Length
input int    InpSmooth    = 3;                 // Smoothed
input int    InpNormLen   = 200;               // Historique de référence
input bool   InpUseVol    = true;              // Pondérer par le volume relatif
input int    InpFastLen   = 5;                 // Fast Trend
input int    InpCoreLen   = 50;                // Core Trend
input double InpStrongSd  = 1.8;               // Strong Trend : écarts-types
input group "3. CX Système (réglages de l'indicateur)"
input bool   InpSrvUsDst  = true;              // Le courtier suit l'heure d'été US (GMT+2 / GMT+3)
input int    InpSfpLen    = 5;                 // Swings des croix (bougies de chaque côté)
input group "4. Affichage"
input int    InpPlans     = 3;                 // Plans de trade dessinés (les derniers)
input int    InpTags      = 6;                 // Étiquettes BUY / SELL (les dernières)
input color  bullCol      = C'0,230,168';      // Haussier / TP
input color  bearCol      = C'255,59,105';     // Baissier / SL
input string InpFont      = "Trebuchet MS";    // Police
input group "5. Alertes (à la clôture de la bougie)"
input bool   AlEntry      = true;              // Nouveau signal BUY / SELL
input bool   AlTp         = true;              // TP atteint
input bool   AlSl         = true;              // SL touché
input bool   AlPopup      = true;              // Fenêtre et son MT5
input bool   AlPush       = false;             // Notification mobile (MetaQuotes ID)
input group "6. Calcul"
input int    InpMaxBars   = 5000;              // Bougies de l'UT des signaux calculées

#define NA    EMPTY_VALUE
#define NAI   -1
#define NSLOT 17
#define S_PDH 0
#define S_PDL 1
#define S_PWH 2
#define S_PWL 3
#define S_SES 4
#define S_O00 14
#define S_O830 15
#define S_O930 16

struct SPlan
  {
   int      dir, kind;              // kind 1 = Strong après prise de la carte, 2 = croix ratée
   datetime sigTime, entryTime, endTime;
   double   entry, sl, tp, tpR, sigY, res;
   int      status;                 // 0 en cours, 1 TP, 2 SL, 3 fin sans TP ni SL
  };
SPlan    gP[];
datetime gLastSigBar = 0;
bool     gReady = false, gLoaded = false;
int      gSigPer = 900;

//==================================================================== CX Press (recopié)
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

int pStr[], pCore[];
void CalcPress(const MqlRates &r[], int n)
  {
   double kBuyP[], kFast[], kCore[], kBuyE[], kSellE[], kSellPos[], kNetRaw[], kNetP[], gVol[], gBuyRaw[], gSellRaw[];
   ArrayResize(kBuyP, n); ArrayResize(kFast, n); ArrayResize(kCore, n); ArrayResize(kBuyE, n); ArrayResize(kSellE, n);
   ArrayResize(kSellPos, n); ArrayResize(kNetRaw, n); ArrayResize(kNetP, n);
   ArrayResize(gVol, n); ArrayResize(gBuyRaw, n); ArrayResize(gSellRaw, n); ArrayResize(pStr, n); ArrayResize(pCore, n);
   for(int i = 0; i < n; i++)
     {
      kBuyE[i] = kSellE[i] = kSellPos[i] = kNetRaw[i] = kNetP[i] = EMPTY_VALUE;
      kBuyP[i] = kFast[i] = kCore[i] = EMPTY_VALUE;
      gVol[i] = gBuyRaw[i] = gSellRaw[i] = 0; pStr[i] = 0; pCore[i] = 0;
     }
   int first = 1;
   for(int i = first; i < n; i++)
     {
      double prevC = r[i - 1].close;
      gBuyRaw[i]  = r[i].close - MathMin(r[i].low, prevC);
      gSellRaw[i] = MathMax(r[i].high, prevC) - r[i].close;
      gVol[i] = (double)r[i].tick_volume;
      double vm = Sma(gVol, i, InpCandleLen, first);
      double rv = InpUseVol && gVol[i] > 0 && vm != EMPTY_VALUE && vm > 0 ? MathMin(gVol[i] / vm, 5.0) : 1.0;
      kBuyE[i]  = Ema(i > first ? kBuyE[i - 1] : EMPTY_VALUE, gBuyRaw[i] * rv, InpCandleLen);
      kSellE[i] = Ema(i > first ? kSellE[i - 1] : EMPTY_VALUE, gSellRaw[i] * rv, InpCandleLen);
      double bb = Sma(kBuyE, i, InpNormLen, first), sb = Sma(kSellE, i, InpNormLen, first);
      double bp = Ema(i > first ? kBuyP[i - 1] : EMPTY_VALUE, bb != EMPTY_VALUE && bb > 0 ? 200.0 * kBuyE[i] / bb : 0.0, InpSmooth);
      double sp = Ema(i > first ? kSellPos[i - 1] : EMPTY_VALUE, sb != EMPTY_VALUE && sb > 0 ? 200.0 * kSellE[i] / sb : 0.0, InpSmooth);
      kSellPos[i] = sp; kBuyP[i] = bp;
      kNetRaw[i] = bp - sp;
      double nsd = Sd(kNetRaw, i, InpNormLen, first);
      kNetP[i] = nsd != EMPTY_VALUE && nsd > 0 ? kNetRaw[i] / nsd * 300.0 : 0.0;
      double fast = Ema(i > first ? kFast[i - 1] : EMPTY_VALUE, kNetP[i], InpFastLen);
      double core = Ema(i > first ? kCore[i - 1] : EMPTY_VALUE, kNetP[i], InpCoreLen);
      kFast[i] = fast; kCore[i] = core;
      double fm = Sma(kFast, i, InpNormLen, first), fsd = Sd(kFast, i, InpNormLen, first);
      bool strongUp = fm != EMPTY_VALUE && fast > 0 && core > 0 && fast > fm + InpStrongSd * fsd;
      bool strongDn = fm != EMPTY_VALUE && fast < 0 && core < 0 && fast < fm - InpStrongSd * fsd;
      pStr[i] = strongUp ? 1 : strongDn ? -1 : 0;
      pCore[i] = core > 0 ? 1 : core < 0 ? -1 : 0;
     }
  }

//==================================================================== CX Système : croix ✕ (SFP), recopié
int sSfp[];
bool PivotHigh(const MqlRates &r[], int t, int len)
  {
   int c = t - len;
   if(c - len < 0) return false;
   for(int i = 1; i <= len; i++)
      if(r[c - i].high >= r[c].high || r[c + i].high > r[c].high) return false;
   return true;
  }
bool PivotLow(const MqlRates &r[], int t, int len)
  {
   int c = t - len;
   if(c - len < 0) return false;
   for(int i = 1; i <= len; i++)
      if(r[c - i].low <= r[c].low || r[c + i].low < r[c].low) return false;
   return true;
  }
void CalcSfp(const MqlRates &r[], int n)
  {
   ArrayResize(sSfp, n);
   double lvlH = NA, lvlL = NA;
   for(int t = 0; t < n; t++)
     {
      if(PivotHigh(r, t, InpSfpLen)) lvlH = r[t - InpSfpLen].high;
      if(PivotLow(r, t, InpSfpLen))  lvlL = r[t - InpSfpLen].low;
      bool rawBear = lvlH != NA && r[t].high > lvlH && r[t].close < lvlH && r[t].open < lvlH;
      bool rawBull = lvlL != NA && r[t].low < lvlL && r[t].close > lvlL && r[t].open > lvlL;
      sSfp[t] = rawBear && rawBull ? 0 : rawBull ? 1 : rawBear ? -1 : 0;   // les deux à la fois : ignoré (comme l'étude)
      if(rawBear) lvlH = NA;
      if(rawBull) lvlL = NA;
      if(lvlH != NA && r[t].close > lvlH) lvlH = NA;
      if(lvlL != NA && r[t].close < lvlL) lvlL = NA;
     }
  }

//==================================================================== CX Système : carte de liquidité (recopié)
struct Slot { double price; int x0; int kind; bool taken; int grp; };
Slot   slot[NSLOT];
long   curDay, curWeek;
double dHi, dLo, wHi, wLo, sHi, sLo;
int    dStart, wStart, sStart, curSess, prevMins;
long   gSrvOffNow = 0;
int    sSweep[], sSess[];

datetime NthSunday(int y, int m, int n)
  {
   MqlDateTime d; ZeroMemory(d);
   d.year = y; d.mon = m; d.day = 1;
   datetime t = StructToTime(d);
   TimeToStruct(t, d);
   int first = (7 - d.day_of_week) % 7;
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
   if(InpSrvUsDst) off += (UsDst(srv) ? 3600 : 0) - (UsDst(TimeGMT()) ? 3600 : 0);
   return (datetime)(srv - off);
  }
datetime ToNy(datetime srv) { datetime u = ToUtc(srv); return u - (UsDst(u) ? 4 : 5) * 3600; }
int SessOf(int mins)
  {
   if(mins >= 1080 || mins < 150) return 0;
   if(mins < 420) return 1;
   if(mins < 690) return 2;
   if(mins < 780) return 3;
   if(mins < 960) return 4;
   return -1;
  }
void SetSlot(int k, double price, int x0, int kind, int grp) { slot[k].price = price; slot[k].x0 = x0; slot[k].kind = kind; slot[k].taken = false; slot[k].grp = grp; }

void CalcMap(const MqlRates &r[], int n)
  {
   ArrayResize(sSweep, n); ArrayResize(sSess, n);
   for(int i = 0; i < NSLOT; i++) { slot[i].price = NA; slot[i].x0 = NAI; slot[i].kind = 0; slot[i].taken = false; slot[i].grp = 0; }
   curDay = curWeek = -1;
   dHi = wHi = sHi = -DBL_MAX; dLo = wLo = sLo = DBL_MAX;
   dStart = wStart = sStart = 0; curSess = -1; prevMins = -1;
   for(int t = 0; t < n; t++)
     {
      datetime ny = ToNy(r[t].time);
      MqlDateTime nd; TimeToStruct(ny, nd);
      int  mins = nd.hour * 60 + nd.min;
      long tday = (long)((ny + 6 * 3600) / 86400);
      long week = (tday + 3) / 7;
      if(t == 0) { curDay = tday; curWeek = week; }
      if(tday != curDay)
        {
         if(dHi > -DBL_MAX) { SetSlot(S_PDH, dHi, dStart, 1, 0); SetSlot(S_PDL, dLo, dStart, -1, 0); }
         curDay = tday; dStart = t; dHi = -DBL_MAX; dLo = DBL_MAX;
        }
      if(week != curWeek)
        {
         if(wHi > -DBL_MAX) { SetSlot(S_PWH, wHi, wStart, 1, 1); SetSlot(S_PWL, wLo, wStart, -1, 1); }
         curWeek = week; wStart = t; wHi = -DBL_MAX; wLo = DBL_MAX;
        }
      int ses = SessOf(mins);
      if(ses != curSess)
        {
         if(curSess >= 0 && sHi > -DBL_MAX)
           {
            SetSlot(S_SES + curSess * 2, sHi, sStart, 1, 2);
            SetSlot(S_SES + curSess * 2 + 1, sLo, sStart, -1, 2);
           }
         curSess = ses; sStart = t; sHi = -DBL_MAX; sLo = DBL_MAX;
        }
      bool newCal = prevMins >= 0 && mins < prevMins;
      if(newCal) SetSlot(S_O00, r[t].open, t, 0, 3);
      if(prevMins >= 0 && prevMins < 510 && mins >= 510 && !newCal) SetSlot(S_O830, r[t].open, t, 0, 3);
      if(prevMins >= 0 && prevMins < 570 && mins >= 570 && !newCal) SetSlot(S_O930, r[t].open, t, 0, 3);
      prevMins = mins;
      int mLo = 0, mHi = 0;
      for(int k = 0; k < NSLOT; k++)
        {
         if(slot[k].price == NA || slot[k].taken || slot[k].kind == 0 || slot[k].x0 >= t) continue;
         if((slot[k].kind == -1 && r[t].low < slot[k].price) || (slot[k].kind == 1 && r[t].high > slot[k].price))
           {
            slot[k].taken = true;
            if(slot[k].kind == -1) mLo |= 1 << slot[k].grp; else mHi |= 1 << slot[k].grp;
           }
        }
      //--- +1 = un haut seulement est pris (cassure haussière), -1 = un bas seulement
      sSweep[t] = mHi > 0 && mLo == 0 ? 1 : mLo > 0 && mHi == 0 ? -1 : 0;
      sSess[t] = ses;
      dHi = MathMax(dHi, r[t].high); dLo = MathMin(dLo, r[t].low);
      wHi = MathMax(wHi, r[t].high); wLo = MathMin(wLo, r[t].low);
      if(curSess >= 0) { sHi = MathMax(sHi, r[t].high); sLo = MathMin(sLo, r[t].low); }
     }
  }

//==================================================================== signaux
bool Compute()
  {
   uint t0 = GetTickCount();
   MqlRates r[];
   int got = CopyRates(_Symbol, InpSigTf, 0, InpMaxBars + 1, r);
   if(got < InpNormLen * 3) return false;
   uint t1 = GetTickCount();
   int n = got - 1;                                   // la dernière bougie est en cours
   gSigPer = PeriodSeconds(InpSigTf);
   gSrvOffNow = (long)MathRound((double)(TimeTradeServer() - TimeGMT()) / 1800.0) * 1800;
   CalcPress(r, n);
   uint t2 = GetTickCount();
   CalcMap(r, n);
   CalcSfp(r, n);
   uint t3 = GetTickCount();
   double atr[]; ArrayResize(atr, n); atr[0] = r[0].high - r[0].low;
   for(int i = 1; i < n; i++)
     {
      double trv = MathMax(r[i].high, r[i - 1].close) - MathMin(r[i].low, r[i - 1].close);
      atr[i] = i < 14 ? (atr[i - 1] * i + trv) / (i + 1) : (atr[i - 1] * 13 + trv) / 14;
     }
   SPlan old[]; ArrayResize(old, ArraySize(gP));
   for(int j = 0; j < ArraySize(gP); j++) old[j] = gP[j];
   ArrayFree(gP);
   int lastUp = -100000, lastDn = -100000, lastSig = -100000, lastSig2 = -100000;
   for(int i = 1; i < n; i++)
     {
      if(sSweep[i] == 1) lastUp = i;
      if(sSweep[i] == -1) lastDn = i;
      //--- « croix ratée » : croix ✕ à la bougie i-1 contre le Core de Press, toujours valide à la clôture de i -> suivre le Core
      int s = sSfp[i - 1];
      if(InpUseCross && s != 0 && pCore[i - 1] == -s && (s == 1 ? r[i].close >= r[i - 1].low : r[i].close <= r[i - 1].high) && i - lastSig2 >= InpPause)
        {
         lastSig2 = i;
         SPlan q;
         q.kind = 2; q.dir = -s; q.sigTime = r[i].time; q.entryTime = r[i].time + gSigPer; q.endTime = q.entryTime + InpHorizon * gSigPer;
         q.entry = r[i].close;
         double rk = InpSlAtr2 * atr[i];
         q.sl = q.entry - q.dir * rk; q.tp = q.entry + q.dir * InpTpR2 * rk; q.tpR = InpTpR2;
         q.sigY = q.dir == 1 ? r[i].low : r[i].high; q.res = 0; q.status = 0;
         int mq = ArraySize(gP); ArrayResize(gP, mq + 1, 64); gP[mq] = q;
        }
      int v = pStr[i] != 0 && pStr[i - 1] != pStr[i] ? pStr[i] : 0;   // début de Strong Trend
      if(v == 0) continue;
      if(InpNyAmOnly && sSess[i] != 2) continue;
      if(i - (v == 1 ? lastUp : lastDn) > InpWindow) continue;
      if(i - lastSig < InpPause) continue;
      lastSig = i;
      SPlan p;
      p.kind = 1; p.tpR = InpTpR;
      p.dir = v; p.sigTime = r[i].time; p.entryTime = r[i].time + gSigPer; p.endTime = p.entryTime + InpHorizon * gSigPer;
      p.entry = r[i].close;
      double risk = InpSlAtr * atr[i];
      p.sl = p.entry - v * risk; p.tp = p.entry + v * InpTpR * risk;
      p.sigY = v == 1 ? r[i].low : r[i].high; p.res = 0; p.status = 0;
      int m = ArraySize(gP); ArrayResize(gP, m + 1, 64); gP[m] = p;
     }
   //--- états des derniers plans (minute par minute)
   int tot = ArraySize(gP), keep = MathMax(InpPlans, InpTags);
   for(int k = MathMax(0, tot - keep); k < tot; k++)
     {
      //--- reprendre l'état déjà connu (alertes une seule fois)
      for(int j = ArraySize(old) - 1; j >= 0; j--)
         if(old[j].sigTime == gP[k].sigTime && old[j].dir == gP[k].dir && old[j].kind == gP[k].kind) { gP[k].status = old[j].status; gP[k].res = old[j].res; break; }
      Resolve(gP[k], false);
     }
   //--- alerte d'un nouveau signal sur la bougie qui vient de se fermer
   for(int k = MathMax(0, tot - 2); k < tot && gLoaded && AlEntry; k++)
     {
      SPlan p = gP[k];
      if(p.sigTime != r[n - 1].time) continue;
      string why = p.kind == 2 ? (p.dir == 1 ? " (croix ✕ baissière ratée, Core haussier)" : " (croix ✕ haussière ratée, Core baissier)")
                               : (p.dir == 1 ? " (haut pris + Strong haussier)" : " (bas pris + Strong baissier)");
      SendAlert((p.dir == 1 ? "BUY " : "SELL ") + Pr(p.entry) + " · SL " + Pr(p.sl) + " · TP " + Pr(p.tp) + why);
     }
   gLastSigBar = r[got - 1].time;
   if(!gLoaded) PrintFormat("[CX Signal] calcul : historique %u ms, Press %u ms, carte + croix %u ms, plans %u ms ; %d signaux sur %d bougies",
                            t1 - t0, t2 - t1, t3 - t2, GetTickCount() - t3, ArraySize(gP), n);
   gLoaded = true;
   return true;
  }

//--- TP ou SL atteint ? (M1 ; si la même minute touche les deux : SL)
void Resolve(SPlan &p, bool alert)
  {
   if(p.status != 0) return;
   datetime now = TimeCurrent();
   if(now < p.entryTime) return;
   MqlRates m[];
   datetime upTo = (datetime)MathMin((long)p.endTime - 1, (long)now);
   int n = CopyRates(_Symbol, PERIOD_M1, p.entryTime, upTo, m);
   if(n <= 0) return;
   double risk = MathAbs(p.entry - p.sl);
   for(int k = 0; k < n; k++)
     {
      if(m[k].time >= p.endTime) break;
      bool hs = p.dir == 1 ? m[k].low <= p.sl : m[k].high >= p.sl;
      bool ht = p.dir == 1 ? m[k].high >= p.tp : m[k].low <= p.tp;
      if(hs) { p.status = 2; p.res = -1; p.endTime = m[k].time + 60; break; }
      if(ht) { p.status = 1; p.res = p.tpR; p.endTime = m[k].time + 60; break; }
     }
   if(p.status == 0 && now >= p.endTime)
     { p.status = 3; p.res = risk > 0 ? (m[n - 1].close - p.entry) * p.dir / risk : 0; }
   //--- alerte seulement pour une touche récente (pas pour un ancien trade découvert au chargement de l'historique)
   if(p.status == 1 || p.status == 2) alert = alert && p.endTime >= now - 120;
   if(alert && p.status == 1 && AlTp) SendAlert("TP atteint " + Pr(p.tp) + " (+" + F1(p.tpR) + "R)");
   if(alert && p.status == 2 && AlSl) SendAlert("SL touché " + Pr(p.sl) + " (-1R)");
  }

void SendAlert(string msg)
  {
   string tf = gSigPer < 3600 ? "M" + IntegerToString(gSigPer / 60) : "H" + IntegerToString(gSigPer / 3600);
   string txt = "CX Signal " + _Symbol + " " + tf + " : " + msg;
   if(AlPopup) Alert(txt);
   if(AlPush)  SendNotification(StringSubstr(txt, 0, 255));
  }

string Pr(double p) { return DoubleToString(p, _Digits); }
string F1(double v)
  {
   string s = DoubleToString(MathRound(v * 10.0) / 10.0, 1);
   if(StringLen(s) > 2 && StringSubstr(s, StringLen(s) - 2) == ".0") s = StringSubstr(s, 0, StringLen(s) - 2);
   return s;
  }
uint A(const color c, const int transp) { return ColorToARGB(c, (uchar)MathRound(255.0 * (100 - MathMax(0, MathMin(100, transp))) / 100.0)); }

//==================================================================== événements
CCanvas  gCv;
string   gName;
bool     gCvOk = false;
int      gW = 0, gHh = 0, gN = 0, gPer = 60;
datetime gCT[];
double   gDpi = 1.0;
uint     gLastRender = 0;
bool     gDirty = false;

int OnInit()
  {
   if(InpWindow < 0 || InpPause < 1 || InpSlAtr <= 0 || InpTpR <= 0 || InpHorizon < 1 || InpMaxBars < 1000 || PeriodSeconds(InpSigTf) < PeriodSeconds(PERIOD_M1))
      return INIT_PARAMETERS_INCORRECT;
   gDpi = MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0);
   gName = "CXSIG_" + IntegerToString(ChartID()) + "_" + IntegerToString(GetTickCount());
   IndicatorSetString(INDICATOR_SHORTNAME, "CX Signal");
   Print("[CX Signal] version 1.10 chargée (Strong après prise de la carte + croix ratée ✕)");
   EventSetMillisecondTimer(250);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(gCvOk) gCv.Destroy();
   gCvOk = false;
   ChartRedraw();
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < 10) return 0;
   gPer = PeriodSeconds(PERIOD_CURRENT);
   //--- heures des bougies du graphique (30 000 dernières) : tout recopier dès qu'une bougie s'ajoute
   static int lastTotal = 0;
   int keep = MathMin(rates_total, 30000), base = rates_total - keep;
   bool all = prev_calculated == 0 || rates_total != lastTotal || gN != keep;
   if(all) ArrayResize(gCT, keep);
   for(int i = all ? 0 : keep - 1; i < keep; i++) gCT[i] = time[base + i];
   gN = keep; lastTotal = rates_total;
   //--- le calcul se fait dans OnTimer (jamais ici, pour ne pas bloquer les autres indicateurs du symbole)
   if(GetTickCount() - gLastRender >= 250) Render(); else gDirty = true;
   return rates_total;
  }

void OnTimer()
  {
   static uint lastRes = 0;
   if(!gReady) { gReady = Compute(); if(gReady) gDirty = true; }
   else
     {
      datetime lt = iTime(_Symbol, InpSigTf, 0);
      if(lt > 0 && lt != gLastSigBar && Compute()) gDirty = true;
      if(GetTickCount() - lastRes >= 1000)
        {
         lastRes = GetTickCount();
         int tot = ArraySize(gP);
         for(int k = MathMax(0, tot - MathMax(InpPlans, InpTags)); k < tot; k++)
            if(gP[k].status == 0) { Resolve(gP[k], k == tot - 1); gDirty = true; }
        }
     }
   if(gDirty) Render();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_CHART_CHANGE || gN <= 0) return;
   gDirty = true;
   if(GetTickCount() - gLastRender >= 40) Render();
  }

//==================================================================== dessin (moteur de CX AVPT)
double gX0 = 0, gSp = 1, gY0 = 0, gKy = 0, gPMax = 0;
int    gT0 = 0;

int    Px(double v) { return (int)MathRound(v * gDpi); }
double XofBar(double b) { return gX0 + (b - gT0) * gSp; }
double YofPrice(double p) { return gY0 + (gPMax - p) * gKy; }
double XofTime(double tm)
  {
   if(gN <= 0) return 0;
   if(tm >= (double)gCT[gN - 1]) return XofBar(gN - 1 + (tm - (double)gCT[gN - 1]) / gPer);
   if(tm < (double)gCT[0]) return XofBar((tm - (double)gCT[0]) / gPer);
   int lo = 0, hi2 = gN - 1;
   while(lo < hi2) { int m = (lo + hi2 + 1) / 2; if((double)gCT[m] <= tm) lo = m; else hi2 = m - 1; }
   return XofBar(lo);
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
//--- style : 0 plein, 1 tirets, 2 points
void DrawLine(double x1, double y1, double x2, double y2, int style, int w, uint c)
  {
   double m = 2000;
   if(MathMax(x1, x2) < -m || MathMin(x1, x2) > gW + m) return;
   double len = MathSqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
   int on = 0, off = 0;
   if(style == 1) { on = Px(4); off = Px(4); }
   if(style == 2) { on = MathMax(w, 1); off = MathMax(w, 1) * 2; }
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
      if(style != 0 && ((int)s % (on + off)) >= on) continue;
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
void SetFont(bool bold) { gCv.FontSet(InpFont, -45, bold ? FW_BOLD : FW_NORMAL); }
//--- étiquette : 0 = pointe en haut, 1 = pointe en bas, 2 = pointe à gauche
void DrawTag(double ax, double ay, string txt, uint bg, uint tc, int style)
  {
   if(ax < -400 || ax > gW + 400 || ay < -100 || ay > gHh + 100) return;
   SetFont(true);
   int tw = 0, th = 0;
   gCv.TextSize(txt, tw, th);
   int padX = Px(3), padY = Px(1), ph = Px(3);
   int w = tw + 2 * padX, h = th + 2 * padY;
   int iy = (int)MathRound(ay), ix = (int)MathRound(ax);
   int x1, top;
   if(style == 2) { x1 = ix + ph; top = iy - h / 2; FillPointerH(ix, ay, ph + 1, ph, bg); }
   else
     {
      x1 = (int)MathRound(ax - w / 2.0);
      top = style == 0 ? iy + ph : iy - ph - h;
      FillPointer(ax, iy, ph + 1, ph, style == 0 ? 1 : -1, bg);
     }
   FillRoundRect(x1, top, x1 + w, top + h, 2.0 * gDpi, bg);
   gCv.TextOut(x1 + w / 2, top + h / 2, txt, tc, TA_CENTER | TA_VCENTER);
  }
void DrawBox(double x1, double x2, double pTop, double pBot, uint bg, uint bd)
  {
   int xa = (int)MathRound(MathMin(x1, x2)), xb = (int)MathRound(MathMax(x1, x2));
   int ya = (int)MathRound(YofPrice(MathMax(pTop, pBot))), yb = (int)MathRound(YofPrice(MathMin(pTop, pBot)));
   if(xb < 0 || xa > gW || yb < 0 || ya > gHh) return;
   FillRect(xa + 1, ya + 1, xb - 1, yb - 1, bg);
   DrawLine(xa, ya, xb, ya, 0, 1, bd);
   DrawLine(xa, yb, xb, yb, 0, 1, bd);
   DrawLine(xa, ya, xa, yb, 0, 1, bd);
   DrawLine(xb, ya, xb, yb, 0, 1, bd);
  }

void DrawPlans()
  {
   int tot = ArraySize(gP);
   if(tot == 0) return;
   uint fg = A((color)ChartGetInteger(0, CHART_COLOR_FOREGROUND), 0);
   color bgc = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   uint dark = A(C'11,14,20', 0);
   datetime proj = gCT[gN - 1] + 6 * gPer;
   //--- plans : boîte risque (rouge), boîte gain (verte), lignes entrée / SL / TP
   for(int ip = MathMax(0, tot - InpPlans); ip < tot; ip++)
     {
      SPlan p = gP[ip];
      datetime right = p.status == 0 ? (datetime)MathMax((long)proj, (long)p.entryTime + gPer) : p.endTime;
      double x1 = XofTime((double)p.entryTime), x2 = XofTime((double)right);
      if(x2 < x1 + 1) x2 = x1 + 1;
      DrawBox(x1, x2, MathMax(p.entry, p.sl), MathMin(p.entry, p.sl), A(bearCol, 90), A(bearCol, 70));
      DrawBox(x1, x2, MathMax(p.entry, p.tp), MathMin(p.entry, p.tp), A(bullCol, 92), A(bullCol, 70));
      DrawLine(x1, MathRound(YofPrice(p.entry)), x2, MathRound(YofPrice(p.entry)), 0, 1, A((color)ChartGetInteger(0, CHART_COLOR_FOREGROUND), 25));
      DrawLine(x1, MathRound(YofPrice(p.sl)),    x2, MathRound(YofPrice(p.sl)),    0, 1, A(bearCol, 20));
      DrawLine(x1, MathRound(YofPrice(p.tp)),    x2, MathRound(YofPrice(p.tp)),    0, 1, A(bullCol, 15));
      if(ip == tot - 1)
        {
         string fin = p.status == 3 ? "  FIN " + (p.res >= 0 ? "+" : "") + F1(p.res) + "R" : "";
         DrawTag(x2, YofPrice(p.entry), "ENTRY  " + Pr(p.entry) + fin, A(bgc, 20), fg, 2);
         DrawTag(x2, YofPrice(p.sl), "SL  " + Pr(p.sl) + (p.status == 2 ? " ✗" : " (-1R)"), A(bearCol, p.status == 2 ? 20 : 82), fg, 2);
         DrawTag(x2, YofPrice(p.tp), "TP  " + Pr(p.tp) + " (" + F1(p.tpR) + "R)" + (p.status == 1 ? " ✓" : ""), A(bullCol, p.status == 1 ? 20 : 84), fg, 2);
        }
     }
   //--- étiquettes BUY / SELL (résultat ✓ / ✗ une fois fini)
   for(int ip = MathMax(0, tot - InpTags); ip < tot; ip++)
     {
      SPlan p = gP[ip];
      string st = p.status == 1 ? " ✓" : p.status == 2 ? " ✗" : p.status == 3 ? " " + (p.res >= 0 ? "+" : "") + F1(p.res) + "R" : "";
      DrawTag(XofTime((double)p.entryTime - 1), YofPrice(p.sigY), (p.dir == 1 ? "BUY" : "SELL") + (p.kind == 2 ? " ✕" : "") + st,
              A(p.dir == 1 ? bullCol : bearCol, ip == tot - 1 ? 5 : 25), dark, p.dir == 1 ? 0 : 1);
     }
  }

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
   gLastRender = GetTickCount();
   gDirty = false;
   int firstShift = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   firstShift = MathMax(1, MathMin(firstShift, MathMin(bars - 1, gN - 1)));
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
   DrawPlans();
   gCv.Update(true);
  }
//+------------------------------------------------------------------+
