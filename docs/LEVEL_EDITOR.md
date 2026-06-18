# Editor de niveles

Constructor visual de campañas. Permite armar una lista ordenada de niveles,
pintar cada mapa (jugador, obstáculos y enemigos), editar un catálogo de tipos
de monstruo con stats, ajustar stats por enemigo colocado y probar un nivel al
instante. Todo se guarda en `user://campaign.json`.

**Archivos**: `scripts/editor.gd` (~680 líneas), `scripts/level_store.gd`
(modelo + persistencia). Escena: `editor.tscn`. Se abre desde el menú principal.

## Layout (tres columnas)

```
┌─────────────────────┬──────────────────────────┬───────────────────────┐
│ NIVELES             │                          │ Guardar · Probar · Menú│
│  (lista ordenable)  │                          │ NIVEL (nombre, ancho,  │
│  Nuevo/Dup/Borrar   │        CANVAS            │   alto, advertencias)  │
│  ▲ Subir / ▼ Bajar  │   (pintado del mapa)     │ HERRAMIENTAS           │
│                     │                          │  Jugador/Obstáculo/    │
│ CATÁLOGO MONSTRUOS  │                          │  Goma/Seleccionar/     │
│  (tipos + stats)    │                          │  + un botón por tipo   │
│  Nuevo/Borrar tipo  │                          │ ENEMIGO SELECCIONADO   │
└─────────────────────┴──────────────────────────┴───────────────────────┘
```

## Funcionalidades

### Gestión de niveles (campaña)
- Lista ordenada = **orden de juego** de la campaña.
- Operaciones: **Nuevo**, **Duplicar** (`" (copia)"`), **Borrar** (mínimo 1
  nivel), **Renombrar**, **Subir/Bajar** para reordenar.
- Propiedades por nivel: **nombre** y **dimensiones** de la grilla
  (`MIN_DIM = 3` … `MAX_DIM = 9`). Al achicar la grilla se recortan
  obstáculos/enemigos fuera de rango y se reubica al jugador.

### Pintado del mapa (herramientas)
Herramienta activa en `tool`: `"player" | "obstacle" | "erase" | "select" | "monster:<id>"`.

- **Jugador**: fija la casilla de inicio (única; no sobre obstáculo/enemigo).
- **Obstáculo**: agrega roca (bloquea movimiento y visión).
- **Goma**: borra lo que haya en la celda.
- **Seleccionar**: elige un enemigo colocado para ajustarlo.
- **Un botón por tipo de monstruo**: coloca ese tipo en la celda.
- Soporta **arrastrar** para pintar/borrar en continuo. Click derecho = borrar.

### Catálogo de tipos de monstruo
- Catálogo **global** de arquetipos con stats editables: Vida, Velocidad,
  Ataque, Defensa, Alcance (rango 1–12) y **color**.
- **Nuevo tipo** (con color tomado de una paleta rotativa), **Borrar tipo**
  (mínimo 1; **no se puede borrar un tipo en uso** en algún nivel), **Renombrar**.
- Cambiar un tipo se refleja en los botones de herramienta y en los enemigos.

### Ajustes por enemigo (overrides)
- Cada enemigo colocado puede sobrescribir los stats de su tipo
  (`overrides: {stat: valor}`). Solo se guarda lo que difiere del tipo base.
- Panel **"Enemigo seleccionado"**: spin por stat, **Quitar ajustes** (resetea a
  los del tipo) y **Eliminar**. En el canvas, un punto dorado marca a los
  enemigos con ajustes.

### Validación (advertencias, no bloquean)
`LevelStore.validate_level()` avisa en tiempo real sobre:
- Nivel sin enemigos (se completaría solo).
- Jugador o enemigo sobre un obstáculo.
- Enemigo sobre el jugador o enemigos superpuestos.
- Enemigo **inalcanzable** (encerrado por obstáculos) — se chequea con Dijkstra.

### Canvas (`EditorCanvas`)
Dibuja damero, obstáculos con piedritas, jugador (círculo azul con "J"),
enemigos (círculo con la inicial del tipo y su color), coordenadas 1-indexadas
en los bordes, anillo dorado en el enemigo seleccionado y resaltado de hover.

## Guardar / probar / salir

- **Guardar**: `LevelStore.save()` → `user://campaign.json`. El botón muestra
  `Guardar *` cuando hay cambios sin guardar (`dirty`).
- **Probar nivel**: guarda, fija `LevelStore.test_level = level_index` y abre
  `main.tscn` para jugar **solo ese nivel**. Al terminar/morir, vuelve al editor.
- **Menú**: guarda y vuelve a `menu.tscn`.

## Modelo de datos (`level_store.gd`)

`LevelStore` mantiene la campaña en memoria (`static var campaign`) y la
persiste. La primera vez se **siembra** desde `GameData` (2 niveles + 2 tipos).

Formato runtime de un nivel:
```gdscript
{ name: String, size: Vector2i, player_start: Vector2i,
  obstacles: Array[Vector2i],
  monsters: [ {type: String, position: Vector2i, overrides: Dictionary} ] }
```
Tipo de monstruo:
```gdscript
{ name, health, speed, attack, defense, range, color: Color }
```

Helpers útiles: `effective_stats(monster)` (tipo + overrides), `type_color`,
`type_letter`, `validate_level`, `blank_level`, `default_campaign`. La
conversión a/desde JSON traduce `Vector2i ↔ [x,y]` y `Color ↔ html`. Ver el
formato en disco en [ARCHITECTURE.md](ARCHITECTURE.md).

`test_level` es el puente editor→juego: `-1` significa "campaña normal"; un
índice ≥ 0 significa "probar ese nivel suelto".
</content>
