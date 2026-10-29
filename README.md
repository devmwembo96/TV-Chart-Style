# Indicateurs MT5 au style TradingView

Indicateurs TradingView réécrits en MQL5, avec le même calcul et le même rendu, pour tout faire sur MT5 avec les prix de la prop firm.

## Indicateurs

| Fichier | Indicateur TradingView |
|---|---|
| `Indicators/LGD_CSD_Fib.mq5` | Liquidity Grab, CSD & Focused Fibonacci (LGD+CSD+Fib) |
| `EA/CarnetXAU.mq5` | EA du Carnet XAU 2.16 : plan de Claude dessiné au style TradingView (base 2.14 du carnet) |
| `EA/CalculateurXAU.mq5` | Calculateur XAU 4.03 : outil position au style TradingView, mode sans restrictions (base 4.01 du carnet) |
| `Indicators/CX_Execution.mq5` | CX Écran 2 · Exécution : BoS/ChoCh, liquidité TFlab, EQH/EQL, IMFVG, LDZ, FVG Sessions, ICT HTF FVGs |
| `Indicators/TV_Chart_Style.mq5` | Style du graphique clair TradingView (bougies, fond, sans grille ni volumes) |
| `Indicators/CX_Gravity.mq5` | Recréation (code fermé) : ancre du jour COMEX, zones Repel et pics de volume Asie / New York |
| `Indicators/CX_Flow.mq5` | Recréation (code fermé) : biais directionnel, sweep, OB/BB, MSS, signal et checklist |
| `Indicators/CX_P2P.mq5` | Recréation (code fermé) : niveaux Asie / Londres / PDH / PDL / TDO, inversion de FVG, MSS, cibles Fibonacci |
| `Indicators/CX_RangeBreaker.mq5` | Recréation (code fermé) : compression, cassures et retournements de mèche |
| `Pine/CX_Setups.pine` | TradingView (Pine v6) : séances et liquidité ISLB, sweeps, premium / discount, biais, POI, FVG HTF, 4 setups avec tableaux, entrée / SL / TP |

## Installation

1. MT5 : Fichier > Ouvrir le dossier des données > `MQL5/Indicators`.
2. Copier le fichier `.mq5`, l’ouvrir dans MetaEditor, compiler (F7).
3. Glisser l’indicateur sur le graphique. Il cohabite avec les EA CarnetXAU et CalculateurXAU.

## Notes

- Dessin en CCanvas (transparence ARGB, étiquettes arrondies), police Trebuchet MS.
- L’échelle d’affichage de Windows est prise en compte automatiquement.
- La bougie en cours est recalculée à chaque tick, comme sur TradingView.

## CarnetXAU et CalculateurXAU

Les deux EA appartiennent au Carnet XAU. Les retouches d’affichage faites ici partent de la version livrée par le carnet ; chaque nouvelle version doit être transmise au carnet pour que les deux restent identiques.
