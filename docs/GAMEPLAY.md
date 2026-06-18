# El juego — Combate táctico por turnos

Combate por turnos sobre una grilla. El jugador (un aventurero) avanza por una
campaña de niveles matando a todos los monstruos de cada mapa. **Cada turno** se
tiran **tres dados** y se asignan a las habilidades; esos valores definen la
economía de acciones (movimiento, ataque y defensa) de ese turno.

**Archivos**: `scripts/main.gd` (presentación + flujo, ~1050 líneas),
`scripts/game_state.gd` (estado y reglas, sin UI), `scripts/grid_logic.gd`
(pathfinding y visión), `scripts/monster_ai.gd` (IA). Escena: `main.tscn`.

> Separación clave: **`main.gd` es solo presentación** (tablero, HUD, dados,
> animaciones, overlays). **Las reglas viven en `GameState`, `GridLogic` y
> `MonsterAI`**, sin dependencias de UI — por eso son testeables de forma aislada.

## Diseño orientado a "intuitivo"

Dos decisiones de diseño guían el combate, pensadas para que sea legible y
amable sin perder profundidad táctica:

1. **Daño por división (bloques de defensa).** El daño es la cantidad de
   **bloques completos** de la defensa que entran en el ataque:
   `daño = floor(ataque / defensa)`. La UI lo explica paso a paso, p. ej.:

   ```
   Ataque 7 contra Defensa 3
   7 contiene 2 bloques completos de 3
   Daño final: 2
   ```
2. **Telegrafiado dinámico.** Durante tu turno se muestra la intención de cada
   monstruo (a dónde se moverá y a quién atacará) y el daño que recibirías. Se
   **recalcula en vivo** cada vez que te movés o atacás, porque los monstruos
   reaccionan a tu nueva posición.

## Fases del turno

`GameState.Phase = { ASSIGN_DICE, PLAYER, MONSTERS, REWARD, GAME_OVER, VICTORY }`

```
┌─ ASSIGN_DICE ─┐     ┌──── PLAYER ────┐     ┌──── MONSTERS ────┐
│ Tirar 3 dados │ ──► │ Mover y atacar │ ──► │ La IA se mueve   │ ──► siguiente turno
│ y asignarlos  │     │                │     │ y ataca; daño    │     o REWARD /
│ a habilidades │     │                │     │ por división     │     VICTORY / GAME_OVER
└───────────────┘     └────────────────┘     └──────────────────┘
```

### Fase de energía (`ASSIGN_DICE`, cada turno)
- Los **3 dados de 6 caras** se tiran **automáticamente** al empezar el turno
  (con animación). El jugador no aprieta ningún botón para tirar.
- Se asigna cada dado a una habilidad: **Velocidad**, **Ataque** o **Defensa**.
  Click en un dado y luego en una habilidad; reasignar mueve el dado.
- **Poder de re-roll (una vez por nivel)**: antes de terminar de asignar, el
  jugador puede volver a tirar los tres dados una sola vez por nivel
  (`GameState.reroll_dice()`). Consume el poder (`reroll_available`) y limpia la
  asignación en curso para reasignar los valores nuevos. Se renueva al empezar
  cada nivel.
- Al asignar los tres, empieza la fase del aventurero con los puntos del turno:
  - `speed_points  = base.speed   + dado(velocidad)`  → presupuesto de movimiento
  - `attack_points = base.attack  + dado(ataque)`     → potencia de tu ataque
  - `defense_total = base.defense + dado(defensa)`    → defensa del turno (divisor)

### Fase del aventurero (`PLAYER`)
- **Mover**: click en una casilla alcanzable (resaltada en verde con su costo).
  El costo se descuenta de `speed_points` (es un pool que se reparte por el turno).
- **Atacar**: **un ataque por turno** a un monstruo en alcance y con línea de
  visión.
  - `daño = floor(attack_points / defensa_del_monstruo)` (bloques completos).
  - Si tu ataque no llega ni a un bloque completo, no podés concretar el golpe
	(0 de daño).
  - Una vez usado el ataque, no podés volver a atacar hasta el próximo turno.
- **Deshacer**: el botón **"Deshacer"** revierte la última acción (movimiento o
  ataque) paso a paso, mientras siga siendo tu turno. Restaura tu posición y
  puntos, la vida de los monstruos heridos/muertos y tu ataque disponible. Al
  **terminar la fase del aventurero ya no se puede deshacer** (el historial se
  descarta al empezar cada turno). Implementado con una pila de snapshots en
  `GameState` (`push`/`undo`/`can_undo`).
- Botón **"Terminar fase del aventurero"** para pasar a los monstruos.

### Fase de monstruos (`MONSTERS`)
- Cada monstruo, en orden, decide su destino (ver IA) y se mueve (animado).
- Luego, todos los monstruos que pueden atacar al jugador atacan **juntos**:
  - `daño = floor(suma_de_ataques / defense_total)` (bloques completos).
  - Si la suma de ataques no llega ni a un bloque de tu defensa, **bloqueás**.
- Feedback: rayo de ataque, números flotantes, *flash*, viñeta roja y *shake*.

### Fin de nivel / partida
- **Jugador a 0 PV** → `GAME_OVER`.
- **Sin monstruos** → si quedan niveles, pantalla de **recompensa**; si era el
  último, **`VICTORY`**.
- **Recompensa** (`REWARD`): elegir entre *curarse a vida máxima* o **+1** a una
  stat base (Velocidad / Ataque / Defensa / Alcance), tope `STAT_MAX = 6`.

## Telegrafiado de la fase de monstruos

Durante `PLAYER`, `GameState.predict_monster_phase()` **simula** la fase de
monstruos sin ejecutarla y devuelve:

```gdscript
{
  moves: { id_monstruo: celda_destino, ... },   # a dónde piensa moverse cada uno
  attackers: [ id_monstruo, ... ],              # quiénes podrían atacarte
  total_attack: int,                            # suma de ataques de los atacantes
  predicted_damage: int,                        # floor(total_attack / defense_total)
}
```

`main.gd` lo usa para dibujar **flechas de intención** (movimiento previsto),
**líneas de amenaza** hacia el aventurero y el **daño previsto**. La predicción se
recalcula en cada `_refresh()` — es decir, **cada vez que te movés o atacás** —,
de modo que la intención enemiga se actualiza al instante según tu posición:
moverte fuera de la línea de visión de un arquero, por ejemplo, lo saca de la
lista de atacantes en el acto.

> La simulación respeta el orden real (`monster_turn_order`) y que los monstruos
> se mueven secuencialmente (uno reacciona a dónde quedaron los anteriores), así
> que el telegrafiado coincide con lo que pasará si terminás el turno tal cual.

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
desempatando por fila y columna. Esta misma función alimenta el telegrafiado.

## Stats base (defaults, `game_data.gd`)

**Aventurero**: `max_health 6`, `speed 1`, `attack 1`, `defense 1`, `range 2`.
(`defense` actúa como **divisor**: el daño recibido es `floor(ataques / defensa)`.)

**Tipos de monstruo de fábrica**:

| Tipo | Nombre | Vida | Vel | Atq | Def (divisor) | Alc |
|------|--------|------|-----|-----|---------------|-----|
| `spider` | Araña | 2 | 5 | 4 | 4 | 3 |
| `skeleton_archer` | Esqueleto arquero | 3 | 4 | 5 | 4 | 4 |

> Estos valores son solo la **semilla inicial**. La campaña real (niveles y
> tipos) es editable y se persiste; ver [LEVEL_EDITOR.md](LEVEL_EDITOR.md).

## HUD y presentación (`main.gd`)

Todo dibujado con `_draw()` en clases internas:

- **`BoardView`** — tablero: damero, obstáculos con piedritas, casillas
  alcanzables (verde + badge de costo), aura pulsante sobre objetivos atacables,
  **flechas de intención y líneas de amenaza** del telegrafiado, resaltado de hover.
- **`UnitView`** — ficha circular con letra y puntitos de PV encima.
- **`DieView`** / **`SlotView`** — dados del turno y casilleros de habilidad.
- **`HealthBar`** — barra de vida segmentada.
- Panel lateral: nivel/turno, vida, stats base, dados del turno, lista de
  monstruos con sus stats, panel de información contextual (hover, incluye el
  daño previsto) y registro con color (`RichTextLabel`).
- Animaciones: *pop-in* elástico, movimiento por camino, muerte (escala+fade),
  *flash*, texto flotante, rayo de ataque, viñeta de daño y *shake* de cámara.
- **Acompañante de esquina** (`_spawn_corner_wizard` + clase `WizardCorner`): al
  empezar cada nivel, el wizard (`sprites/player_wizard.png`) asoma de la cintura
  para arriba en la **esquina inferior izquierda** (con una breve animación de
  entrada) y **se queda ahí** todo el nivel. Tiene **dos pupilas negras** sobre
  sus ojos que **siguen al mouse**. No atenúa la pantalla ni bloquea los clics del
  tablero (`mouse_filter = IGNORE`). Las posiciones de los ojos están en
  `WIZARD_EYES` (fracción del tamaño de la imagen).
</content>
