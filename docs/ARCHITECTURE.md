# Arquitectura, datos y tests

## Organización del código

Toda la UI se construye por código. Cada `.tscn` es un único nodo `Control` raíz
con su script; no hay árboles de nodos prediseñados.

```
just-a-card/
├── project.godot            # Godot 4.3, Forward Plus, escena inicial = menu.tscn
├── menu.tscn                # ─┐
├── main.tscn                #  │  cada .tscn = un Control raíz + script
├── editor.tscn              #  │
├── character_editor.tscn    #  │
├── character_gallery.tscn   # ─┘
├── scripts/
│   ├── ui_kit.gd            # paleta de colores + helpers de UI (botones, secciones, labels)
│   ├── menu.gd              # menú principal
│   │
│   ├── main.gd              # JUEGO: presentación (tablero, HUD, dados, animaciones, overlays)
│   ├── game_state.gd        # JUEGO: estado y reglas (RefCounted, sin UI)
│   ├── grid_logic.gd        # JUEGO: pathfinding (Dijkstra) y línea de visión (puro, estático)
│   ├── monster_ai.gd        # JUEGO: IA de movimiento de monstruos (estático)
│   ├── game_data.gd         # JUEGO: datos semilla (stats base, tipos, niveles iniciales)
│   │
│   ├── editor.gd            # EDITOR DE NIVELES
│   ├── level_store.gd       # campaña editable + persistencia (campaign.json)
│   │
│   ├── character_editor.gd  # EDITOR DE PERSONAJES
│   ├── character_renderer.gd# dibujo/animación de partes (compartido con la galería)
│   ├── character_gallery.gd # galería de personajes
│   └── character_store.gd   # colección + persistencia (characters.json)
│
├── sprites/                 # partes importadas: body, head, eyes, nose, mouth, hat (.png)
├── sprites_raw/             # PNG originales sin .import
└── tests/                   # chequeos end-to-end y de lógica (SceneTree)
```

### Clases con `class_name` (reutilizables globalmente)
`UiKit`, `GameState`, `GridLogic`, `MonsterAI`, `GameData`, `LevelStore`,
`CharacterStore`, `CharacterRenderer`.

### Principio de separación
La **lógica del juego no depende de la UI**: `GameState`, `GridLogic`,
`MonsterAI` y `GameData` son puros/testeables. `main.gd` solo presenta y anima.
De forma análoga, `LevelStore` y `CharacterStore` son el modelo+persistencia de
los editores, separados de su UI (`editor.gd`, `character_editor.gd`).

## Convención de coordenadas

- Internamente: `Vector2i(columna, fila)`, **0-indexado**.
- En UI y mensajes: *fila/columna* **1-indexadas**.
- `GameData.rc(fila, columna)` convierte 1-indexado → `Vector2i` 0-indexado.

## Persistencia (archivos en `user://`)

Ambos stores cargan perezosamente (`ensure_loaded`) y serializan a JSON
traduciendo tipos de Godot (`Vector2i ↔ [x,y]`, `Color ↔ html`).

### `user://campaign.json` — niveles (`level_store.gd`)
```json
{
  "levels": [
	{
	  "name": "Nivel 1",
	  "size": [5, 5],
	  "player_start": [0, 4],
	  "obstacles": [[3, 1], [1, 3], [3, 3]],
	  "monsters": [
		{ "type": "spider", "position": [3, 0], "overrides": {} },
		{ "type": "spider", "position": [4, 2], "overrides": { "health": 4 } }
	  ]
	}
  ],
  "monster_types": {
	"spider": { "name": "Araña", "health": 2, "speed": 5,
				"attack": 4, "defense": 4, "range": 3, "color": "c5453a" }
  }
}
```
Si no existe, se siembra desde `GameData.default_campaign()`.

### `user://characters.json` — personajes (`character_store.gd`)
```json
{
  "characters": [
	{
	  "name": "Personaje 1",
	  "voice": "pii",
	  "parts": [
		{ "part": "body", "path": "res://sprites/body.png", "pos": [0, 150], "scale": 0.30 }
	  ]
	}
  ]
}
```
- `parts` en orden de capas; `pos` relativo al centro del personaje.
- Migra automáticamente el formato viejo `user://character.json` (un solo personaje).

## Tests (`tests/`)

Chequeos basados en `SceneTree`, ejecutables por línea de comandos. Los que
capturan screenshots requieren ventana (no `--headless`); las imágenes van a
`tests/` y están en `.gitignore`.

| Test | Qué cubre | Cómo correr |
|------|-----------|-------------|
| `logic_check.gd` | Lógica central sin UI (grilla, reglas, IA). | `godot --headless -s tests/logic_check.gd` |
| `flow_check.gd` | Flujo recompensa → nivel 2 → victoria → reinicio. | `godot --headless -s tests/flow_check.gd` |
| `editor_check.gd` | Editor de niveles: CRUD, pintado, overrides, reordenado, persistencia. | `godot --headless -s tests/editor_check.gd` |
| `character_check.gd` | Editor de personajes: descubrimiento de sprites, colocado/reemplazo, hit-test, escala, borrado, persistencia. | `godot --headless -s tests/character_check.gd` |
| `menu_check.gd` | El menú compila, se construye y captura screenshot. | `godot -s tests/menu_check.gd` |
| `visual_check.gd` | Prueba visual end-to-end: simula un turno completo sobre la UI real y guarda screenshots. | `godot -s tests/visual_check.gd` (con ventana) |

> Antes de correr tests por primera vez puede hacer falta importar assets:
> `godot --headless --import`.

Varios tests usan `LevelStore.campaign = LevelStore.default_campaign()` para no
depender del `user://campaign.json` del usuario (resultados deterministas).

## Estilo y UI (`ui_kit.gd`)

Paleta central (fondo oscuro `#201d28`, dorado de acento `#e8b54d`, colores por
stat, etc.) y helpers: `style_button`, `style_tool_button` (toggle),
`section` (panel con título) y `label`. Reutilizados por menú, juego y ambos
editores para una estética consistente.
</content>
