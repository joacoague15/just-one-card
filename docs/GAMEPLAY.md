# El juego — Combate táctico por turnos

Combate por turnos sobre una grilla. El jugador (un aventurero) avanza por una
campaña de niveles matando a todos los monstruos de cada mapa. La economía de
acciones de cada turno se decide tirando **tres dados** y asignándolos a las
habilidades.

**Archivos**: `scripts/main.gd` (presentación + flujo, ~1050 líneas),
`scripts/game_state.gd` (estado y reglas, sin UI), `scripts/grid_logic.gd`
(pathfinding y visión), `scripts/monster_ai.gd` (IA). Escena: `main.tscn`.

> Separación clave: **`main.gd` es solo presentación** (tablero, HUD, dados,
> animaciones, overlays). **Las reglas viven en `GameState`, `GridLogic` y
> `MonsterAI`**, sin dependencias de UI — por eso son testeables de forma aislada.

## Fases del turno

`GameState.Phase = { ASSIGN_DICE, PLAYER, MONSTERS, REWARD, GAME_OVER, VICTORY }`

```
┌─ ASSIGN_DICE ─┐     ┌──── PLAYER ────┐     ┌──── MONSTERS ────┐
│ Tirar 3 dados │ ──► │ Mover y atacar │ ──► │ La IA se mueve   │ ──► siguiente turno
│ y asignarlos  │     │ (gastando      │     │ y ataca; se      │     o REWARD /
│ a habilidades │     │  puntos)       │     │ resuelve el daño │     VICTORY / GAME_OVER
└───────────────┘     └────────────────┘     └──────────────────┘
```

### 1. Fase de energía (`ASSIGN_DICE`)
- Se tiran **3 dados de 6 caras** (con animación de ~7 cuadros).
- El jugador asigna cada dado a una de las tres habilidades: **Velocidad**,
  **Ataque** o **Defensa**. Click en un dado y luego en una habilidad.
- Reasignar mueve el dado; se puede desasignar.
- Al asignar los tres, se calculan los puntos del turno y pasa a `PLAYER`:
  - `speed_points  = base.speed   + dado(velocidad)`
  - `attack_points = base.attack  + dado(ataque)`
  - `defense_total = base.defense + dado(defensa)`

### 2. Fase del aventurero (`PLAYER`)
- **Mover**: click en una casilla alcanzable (resaltada en verde con su costo).
  El costo se descuenta de `speed_points`.
- **Atacar**: click en un monstruo en alcance y con línea de visión.
  - Cada golpe hace **1 de daño** y cuesta **la defensa del monstruo** en puntos
	de ataque. Se puede golpear varias veces al mismo objetivo mientras alcancen
	los puntos (`floor(attack / defensa)` golpes pagables por turno).
- Botón **"Terminar fase del aventurero"** para pasar a los monstruos.

### 3. Fase de monstruos (`MONSTERS`)
- Cada monstruo, en orden, decide su destino (ver IA) y se mueve (animado).
- Luego, todos los monstruos que pueden atacar al jugador atacan **juntos**:
  - `daño = floor( suma_de_ataques / defense_total )`.
  - Si `defense_total` es alto, el daño se reduce o se bloquea por completo.
- Feedback: rayo de ataque, números flotantes, *flash*, viñeta roja y *shake*.

### Fin de nivel / partida
- **Jugador a 0 PV** → `GAME_OVER`.
- **Sin monstruos** → si quedan niveles, pantalla de **recompensa**; si era el
  último, **`VICTORY`**.
- **Recompensa** (`REWARD`): elegir entre *curarse a vida máxima* o **+1** a una
  stat base (Velocidad / Ataque / Defensa / Alcance), tope `STAT_MAX = 6`.

## Reglas de la grilla (`grid_logic.gd`)

Lógica pura, sin estado; las dimensiones se pasan por parámetro.

- **Movimiento 8-direccional con Dijkstra**:
  - Costo ortogonal `ORTHO_COST = 2`, diagonal `DIAG_COST = 3`.
  - `dijkstra(start, blocked, size)` → mapa `celda → costo`.
  - `reconstruct_path(...)` reconstruye el camino para animar.
- **Distancia de ataque**: `attack_distance(...)` = costo de moverse hasta la
  celda objetivo ignorando que está ocupada (−1 si es inalcanzable).
- **Línea de visión**: `has_line_of_sight(...)` hace un raycast de centro a
  centro con *clipping* Liang–Barsky (segmento contra rectángulo). Rozar
  exactamente una esquina **no** bloquea (epsilon).

## Reglas de bloqueo

| Quién se mueve | Bloquea el paso | Se puede atravesar |
|----------------|-----------------|--------------------|
| Jugador | obstáculos + todos los monstruos | — |
| Monstruo | obstáculos + el jugador | otros monstruos (pero no terminar encima) |
| Visión (ataque) | obstáculos + monstruos intermedios (no el objetivo) | — |

## IA de monstruos (`monster_ai.gd`)

`choose_destination(m, state)` elige el destino con esta prioridad:

1. Llegar a una celda desde donde **pueda atacar** al jugador este turno.
2. Entre esas, preferir quedar **exactamente a su alcance máximo**.
3. Menor **costo de movimiento** desde la posición actual.
4. Celda más **cercana** al jugador.
5. Desempate: **fila menor**, luego **columna menor**.

Si no puede atacar este turno, avanza hacia la celda más cercana desde donde
*eventualmente* podría atacar; si tampoco existe, se acerca al jugador.

Orden de actuación (`monster_turn_order`): el más cercano al jugador primero,
desempatando por fila y columna.

## Stats base (defaults, `game_data.gd`)

**Aventurero**: `max_health 6`, `speed 1`, `attack 1`, `defense 1`, `range 2`.

**Tipos de monstruo de fábrica**:

| Tipo | Nombre | Vida | Vel | Atq | Def | Alc |
|------|--------|------|-----|-----|-----|-----|
| `spider` | Araña | 2 | 5 | 4 | 4 | 3 |
| `skeleton_archer` | Esqueleto arquero | 3 | 4 | 5 | 4 | 4 |

> Estos valores son solo la **semilla inicial**. La campaña real (niveles y
> tipos) es editable y se persiste; ver [LEVEL_EDITOR.md](LEVEL_EDITOR.md).

## HUD y presentación (`main.gd`)

Todo dibujado con `_draw()` en clases internas:

- **`BoardView`** — tablero: damero, obstáculos con piedritas, casillas
  alcanzables (verde + badge de costo), aura pulsante sobre objetivos atacables,
  resaltado de hover.
- **`UnitView`** — ficha circular con letra y puntitos de PV encima.
- **`DieView`** / **`SlotView`** — dados con pips y casilleros de habilidad.
- **`HealthBar`** — barra de vida segmentada.
- Panel lateral: nivel/turno, vida, stats base, dados, lista de monstruos con
  sus stats, panel de información contextual (hover) y registro con color
  (`RichTextLabel`).
- Animaciones: *pop-in* elástico, movimiento por camino, muerte (escala+fade),
  *flash*, texto flotante, rayo de ataque, viñeta de daño y *shake* de cámara.
</content>
