# Indicateurs MT5 au style TradingView

Indicateurs TradingView réécrits en MQL5, avec le même calcul et le même rendu, pour tout faire sur MT5 avec les prix de la prop firm.

## Indicateurs

| Fichier | Indicateur TradingView |
|---|---|
| `Indicators/LGD_CSD_Fib.mq5` | Liquidity Grab, CSD & Focused Fibonacci (LGD+CSD+Fib) |

## Installation

1. MT5 : Fichier > Ouvrir le dossier des données > `MQL5/Indicators`.
2. Copier le fichier `.mq5`, l’ouvrir dans MetaEditor, compiler (F7).
3. Glisser l’indicateur sur le graphique. Il cohabite avec les EA CarnetXAU et CalculateurXAU.

## Notes

- Dessin en CCanvas (transparence ARGB, étiquettes arrondies), police Trebuchet MS.
- L’échelle d’affichage de Windows est prise en compte automatiquement.
- La bougie en cours est recalculée à chaque tick, comme sur TradingView.
