# ChessMaterial

Material de ajedrez para búsquedas tipo ChessBase sobre bases grandes: firma de
material de 8 B, 57 **clases de material** para el prefiltro `materialVisited`,
clasificación del **final más largo** (`longestEnding`) y **consultas de material**
como las de la pestaña Material de ChessBase.

- SPM, Swift 6, iOS 18 / macOS 15.
- La librería no tiene dependencias. La herramienta de medida (`Tools/MaterialBench`)
  es un paquete aparte que usa [fischer-core](https://github.com/NSStudent/fischer-core) (0.4.0 o posterior).
- Pensado para el índice de búsquedas de una app de ajedrez: una firma por partida
  que se calcula en la misma pasada que el resto del índice y descarta partidas sin decodificarlas.

```sh
swift build
swift test
cd Tools/MaterialBench && swift run -c release material-bench ruta/a/LumbrasGigabase_OTB_2025.pgn 50000 4 medida.json
```

## Uso en la pasada de indexación

```swift
import ChessMaterial

var summary = GameMaterialSummary()
for ply in game {                       // posición inicial incluida
    // 12 bitboards del códec en orden Polyglot: 2·tipo + color (negro 0, blanco 1)
    summary.append(MaterialSignature(bitboards: codec.bitboards))
}
row.materialVisited = summary.visited                  // UInt64, 8 B
row.longestEnding = summary.longestEndingCode.rawValue // UInt16, 2 B

// Al buscar:
let query = MaterialQuery("TP-T", ignoreColors: true, minimumPlies: 6)!
let mask = query.classMask                             // una vez por búsqueda
if row.materialVisited & mask == 0 { /* descartada sin decodificar */ }
// Si no, se reproduce y se confirma con query.matchesGame(...) o MaterialQueryTracker.
```

El material solo cambia con capturas y coronaciones: `GameMaterialSummary` no reclasifica
si la firma no cambia, y el llamante puede rehacer la firma solo en esas jugadas.

## 1. `MaterialSignature`

Recuento por tipo y color a partir de los 12 bitboards `UInt64` en el orden de lanes de
Polyglot: `lane = 2·tipo + color`, negro 0, blanco 1; peón 0,
caballo 1, alfil 2, torre 3, dama 4, rey 5 (el rey no se cuenta).

| Bits del `UInt64` | Contenido |
|---|---|
| 0–39 | 10 nibbles, uno por lane (0 = peones negros, 1 = peones blancos … 9 = damas blancas). Saturan en 15 |
| 40–43 | Color de casilla de los alfiles: negro claro, negro oscuro, blanco claro, blanco oscuro |
| 44–63 | 0 |

- `value(_:)`, `balance` (blancas − negras, P 1, C/A 3, T 5, D 9), `difference(_:)` por tipo.
- `imbalance`: `.none`, `.pawns`, `.exchange` (calidad), `.minorPiece`, `.bishopForKnight`,
  `.queenForRooks`, `.queenForRookAndMinor`, `.other`, con la diferencia de peones
  vista desde el bando con ventaja de piezas.
- `hasOppositeColoredBishops` / `hasSameColoredBishops`: un alfil por bando, sale de los bitboards.
- Texto: `parse(_:notation:)` y `formatted(_:includePawns:)`.
  - Scoutfish: `KRBKRN` (rey blanco, piezas blancas, rey negro, piezas negras, peones como `P`).
  - ChessBase en español `TA-TC` (D T A C P, rey `R`: `T-R`, `R-R`) o en inglés `RB-RN`.
    Se aceptan `+`, espacios y `–`. Si el texto no nombra peones, `MaterialQuery` los deja libres.

## 2. Clases de material (`materialVisited`)

Partición de todas las firmas en **57 clases** (bits 0–56; 57–63 libres para el futuro).
Cada posición cae en una sola clase y la partida guarda el OR (`MaterialClass.visited`).

Reglas:

1. Las clases **no dependen del color** (`clase(s) == clase(s.colorSwapped)`), así que
   «ignorar colores» no cambia la máscara de una consulta.
2. Cada tipo de pieza se ve como (mínimo de los dos bandos saturado en 3, diferencia
   blancas − negras saturada en ±3), más la diferencia de menores (A+C) exacta hasta ±3.
   Así los recuentos por bando son exactos hasta 3 (lo que pide el criterio de final) y
   las diferencias pequeñas son exactas aunque haya muchas piezas (4 torres contra 3
   sigue siendo «calidad»). De los peones solo cuentan «hay alguno» y la diferencia
   saturada en ±2.
3. **Final** = cada bando tiene como mucho 2 piezas y, si hay damas, como mucho 3 piezas
   entre los dos (D-D, D-T, DT-D, D-TT… sí; DT-DT no). El resto es **medio juego**:
   «pleno» con 10 o más piezas en total, «reducido» con menos.
4. Los números forman parte del formato del índice: **no se renumeran**.

| # | Clase | # | Clase |
|--:|---|--:|---|
| 0 | R-R sin peones | 28 | D-D con peones de más |
| 1 | Solo peones, iguales | 29 | D-T |
| 2 | Solo peones, +1 (R+P contra R) | 30 | D contra piezas sin dama (D-A, D-TT, DT-C…) |
| 3 | Solo peones, +2 o más | 31 | D+pieza contra D (DT-D, DA-D, DD-D) |
| 4 | T(T) contra R | 32 | Con damas, pleno, igual |
| 5 | T-T, peones iguales | 33 | Con damas, pleno, calidad por peón(es) |
| 6 | T-T, +1 peón (T+P contra T) | 34 | Con damas, pleno, calidad |
| 7 | T-T, +2 peones o más | 35 | Con damas, pleno, pieza de más |
| 8 | TT-TT | 36 | Con damas, pleno, otro |
| 9 | TT-T | 37–41 | Con damas, reducido (igual, calidad por peón, calidad, pieza, otro) |
| 10 | Menor(es) contra R | 42–46 | Sin damas, pleno (ídem) |
| 11 | A-A mismo color | 47–51 | Sin damas, reducido (ídem) |
| 12 | A-A distinto color | 52 | Dama de más, resto igual (casi siempre el ply de un cambio de damas) |
| 13 | A-C | 53 | D contra compensación: el otro bando tiene al menos una torre más en piezas (TT, T+menor, tres menores…) |
| 14 | C-C | 54 | Con damas, resto igual, alfiles de distinto color |
| 15 | Dos menores contra una | 55 | Sin damas, resto igual, alfiles de distinto color |
| 16 | Dos menores por bando | 56 | Damas desiguales, otro |
| 17 | T contra menor, la menor con ≥ 1 peón más | | |
| 18 | T contra menor | | |
| 19 | T+menor contra T | | |
| 20 | TA-TA mismo color | | |
| 21 | TA-TA distinto color | | |
| 22 | TC-TC | | |
| 23 | TA-TC | | |
| 24 | T contra dos menores | | |
| 25 | Otros finales de torre y menor (TT-TA, TA-A, TT-C…) | | |
| 26 | D (+pieza) contra R | | |
| 27 | D-D, peones iguales | | |

En el medio juego «igual» = mismas torres y mismas menores; «calidad» = una torre más
y una menor menos; «calidad por peón» = además el bando de la menor tiene al menos un
peón más; «pieza» = mismas torres y una menor de diferencia. Con distinto número de
damas se mira desde el bando con más damas: 5·Δtorres + 3·Δmenores ≤ −5 es «compensación».

### Sobreaproximación segura

`MaterialClass.classesMatching(query)` devuelve las clases que contienen **alguna**
firma que cumple la consulta. La clasificación solo mira unos rasgos pequeños (pares de
códigos de D, T, A y C, diferencia de menores, alfiles de distinto color, diferencia de
peones saturada, «sin peones»), y la consulta se descompone por tipo (D, T, A+C juntos por la
fila «menores» y la condición de alfiles, P). Así se pueden enumerar **todos** los
recuentos 0…15 de cada bando que cumplen, llevarlos a rasgos y clasificar cada
combinación: la máscara es exacta respecto a la partición y nunca descarta una partida
que cumple. Lo comprueban las pruebas (firmas y consultas aleatorias en todo el rango de
los nibbles, con colores de alfil coherentes o libres) y la medida (columna «Falsos
negativos»).

## 3. Final más largo (`longestEnding`)

- Un final es una racha de posiciones **consecutivas** con las mismas piezas (D, T, A, C
  por bando, sin contar peones) que cumple el criterio de final de arriba. Los alfiles
  de distinto color forman racha aparte.
- `Endgame.longestEnding(in:minimumPlies:)` devuelve la racha más larga en plies
  (posiciones); en caso de empate, la **última**. Incluye nombre `TA-TC` (blancas-negras),
  `colorlessName()` (bando más fuerte primero), familia (peones, torres, menores, damas,
  mixto), ply de inicio, duración y la firma con peones al empezar.
- `EndingCode` (2 B): byte alto = `blancas << 4 | negras` (código de bando 0–14:
  ∅, D, T, A, C, DD, DT, DA, DC, TT, TA, TC, AA, AC, CC); byte bajo = bit 7 alfiles de
  distinto color + plies saturados en 127. `0xFFFF` = sin final. Ordenar por el valor
  agrupa por final y, dentro, por duración; `pieceKey` filtra por final.

Sin damas, el criterio de final coincide con uno más sencillo que usamos antes (sin
damas, ≤ 2 piezas por bando), pero allí ganaba la clave con más plies **en total**; aquí
gana la racha seguida más larga. En Lumbras 2025 coinciden en el 95,4 % de las partidas.

## 4. Consultas de material (`MaterialQuery`)

- `white` / `black`: mínimo y máximo por pieza (P, C, A, T, D y la fila «menores» A+C).
- `difference`: modo diferencia, rangos de blancas − negras por pieza.
- Se cumplen las tres a la vez, más `bishops` (`.any`, `.opposite`, `.same`).
- `ignoreColors`: vale también la posición con los colores cambiados.
- `minimumPlies`: duración mínima (estabilidad) en posiciones seguidas.
- `runs(in:)`, `firstMatch(in:)`, `matchesGame(_:)` sobre una secuencia de firmas, y
  `MaterialQueryTracker` para evaluarla durante la reproducción, sin guardar la secuencia.
- `MaterialQuery("TA-TC")`: material exacto desde texto (peones libres si no se nombran).

## 5. Medida

`Tools/MaterialBench` reproduce un PGN con fischer-core (12 bitboards por posición, en el
orden de lanes de arriba), calcula las firmas y lo compara todo con la reproducción
completa. Lumbras Gigabase OTB 2025, **492.182 partidas** (41,7 M posiciones; 2 con SAN
ilegal se saltan), 185 s con 4 hilos en un Mac con otras pruebas en marcha. Resultado
completo: [`Measurements/lumbras-2025.md`](Measurements/lumbras-2025.md) y `.json`.

- Clases distintas por partida: **6,93** de media.
- `classesMatching` (release): ~3 ms por consulta típica, ~35 ms la consulta vacía.
  Se calcula una vez por búsqueda.
- **Falsos negativos: 0** en todas las consultas (partidas que cumplen ≥ 1 ply y cuya
  máscara no corta).

### Qué descarta cada consulta típica

«Descarta» = partidas que `materialVisited & máscara == 0` quita sin decodificar.
«Cumplen» = partidas que de verdad tienen la posición, con duración ≥ 1 y ≥ 6 plies.
Las de material escrito como texto, con «ignorar colores».

| Consulta | Clases | Descarta | Candidatas | Cumplen (≥1 ply) | Cumplen (≥6 plies) | Falsos negativos |
|---|--:|--:|--:|--:|--:|--:|
| Final de peones (sin piezas) | 0 1 2 3 | 94.20 % | 28546 | 28546 | 19934 | 0 |
| R+P contra R | 2 | 95.80 % | 20692 | 4933 | 2220 | 0 |
| T-T (finales de torres) | 5 6 7 | 88.68 % | 55716 | 55716 | 46646 | 0 |
| T+P contra T | 6 | 90.94 % | 44612 | 7143 | 4123 | 0 |
| TT-TT | 8 | 95.15 % | 23847 | 23847 | 16601 | 0 |
| A-C | 13 | 96.36 % | 17937 | 17937 | 15115 | 0 |
| C-C | 14 | 98.15 % | 9129 | 9129 | 7790 | 0 |
| A-A de distinto color | 12 | 98.47 % | 7509 | 7509 | 6167 | 0 |
| TA-TA de distinto color | 21 | 97.47 % | 12443 | 12443 | 9122 | 0 |
| TA-TC | 23 | 91.87 % | 39990 | 39990 | 28972 | 0 |
| D-D | 27 28 | 97.42 % | 12716 | 12716 | 9798 | 0 |
| D-T | 29 | 98.77 % | 6072 | 6072 | 2752 | 0 |
| Calidad por peón(es) | 17 25 33 38 43 48 | 78.00 % | 108276 | 59460 | 27828 | 0 |
| D contra TT | 30 53 | 85.93 % | 69249 | 6314 | 3855 | 0 |
| Medio juego con damas (D, T y 2 menores por bando) | 32 33 34 35 36 37 40 41 52 53 54 56 | 0.00 % | 492182 | 492182 | 492176 | 0 |
| Medio juego sin damas (T y 2 menores por bando) | 42 43 44 45 46 47 48 49 50 51 55 | 59.82 % | 197752 | 132433 | 107258 | 0 |

Las consultas de final descartan entre el 88 y el 99 % de la base. Las de desequilibrio
en el medio juego descartan menos porque muchos cambios de piezas pasan un ply por
«pieza de más», «dama de más» o «calidad» antes de la recaptura; por eso esos casos
tienen clases propias («dama de más, resto igual», «calidad» frente a «calidad por
peón»). Una consulta que cumple la posición inicial (el medio juego con damas) no
puede descartar nada.

### Clases más y menos visitadas

- En todas las partidas: 32 «con damas, pleno, igual» (la posición inicial) y, en el
  93 %, 35 «con damas, pleno, pieza» (el ply entre una captura y su recaptura).
- «Dama de más, resto igual» (52) aparece en el 39 % de las partidas: el cambio de damas.
- Finales: T-T con un peón de diferencia (6) en el 9,1 %, T+menor contra T (19) en el
  11,6 %, A-A de distinto color (12) en el 1,5 %, D-T (29) en el 1,2 %.
- La menos visitada: 43 «sin damas, pleno, calidad por peón» (0,11 %).

### Final más largo

Partidas con final: 238472 (48.45 %) · mediana de duración 24 plies
Coincidencia con el criterio sencillo (sin damas, ≤ 2 piezas por bando, más plies en total): 95.42 % de 212218

| Familia | Partidas | % |
|---|--:|--:|
| Peones | 9226 | 1.87 % |
| Torres | 52040 | 10.57 % |
| Menores | 48401 | 9.83 % |
| Damas | 11077 | 2.25 % |
| Mixto | 117728 | 23.92 % |
| Sin final | 253710 | 51.55 % |

| Final (sin color) | Partidas | % |
|---|--:|--:|
| T-T | 36956 | 7.51 % |
| TA-TC | 20311 | 4.13 % |
| TA-TA | 17089 | 3.47 % |
| A-C | 11738 | 2.38 % |
| A-A | 10874 | 2.21 % |
| TC-TC | 10086 | 2.05 % |
| TT-TT | 9787 | 1.99 % |
| D-D | 9243 | 1.88 % |
| R-R | 9226 | 1.87 % |
| TA-T | 8756 | 1.78 % |
| TC-T | 6648 | 1.35 % |
| C-C | 6090 | 1.24 % |
| TT-TA | 5900 | 1.20 % |
| T-A | 5771 | 1.17 % |
| TT-TC | 4494 | 0.91 % |
