# just-a-card — Estado del proyecto

Prototipo de **videojuego de estrategia táctica por turnos** hecho en **Godot 4.3**
(Forward Plus). Internamente lleva el nombre de trabajo *"Dungeon de Dados"*.

Toda la UI se construye por código (no hay escenas con nodos prediseñados: cada
`.tscn` es un único `Control` raíz con un script asociado). La paleta y los
helpers visuales están centralizados en `scripts/ui_kit.gd`.

## Qué hay hecho

El proyecto tiene tres piezas grandes, todas funcionales y conectadas entre sí
desde el menú principal:

| Pieza | Qué es | Docs |
|-------|--------|------|
| 🎲 **El juego** | Combate táctico por turnos sobre grilla, con dados, IA de monstruos y campaña de niveles. | [GAMEPLAY.md](GAMEPLAY.md) |
| 🗺️ **Editor de niveles** | Constructor visual de campañas: mapas, obstáculos, enemigos y catálogo de tipos de monstruo editable. | [LEVEL_EDITOR.md](LEVEL_EDITOR.md) |
| 🧸 **Editor de personajes** | Compositor de personajes a partir de sprites, con voz sintetizada y animación (ojos que siguen al mouse, pestañeo, boca que habla). | [CHARACTER_EDITOR.md](CHARACTER_EDITOR.md) |

Además:

- **Arquitectura, datos y tests**: cómo está organizado el código, los formatos
  de guardado en `user://` y la suite de chequeos. Ver [ARCHITECTURE.md](ARCHITECTURE.md).

## Flujo de pantallas

```
menu.tscn  ──"Jugar"────────────►  main.tscn         (campaña completa)
   │
   ├───────"Editor de niveles"──►  editor.tscn  ──"Probar nivel"──► main.tscn
   │                                                                  (un solo nivel)
   └───────"Personajes"─────────►  character_gallery.tscn
                                        │
                                        └──"Nuevo/editar"──► character_editor.tscn
```

- Escena inicial: `menu.tscn`.
- Resolución base: 1280×800, `stretch/mode = canvas_items`.

## Cómo correrlo

```bash
# Abrir el proyecto en el editor de Godot 4.3, o ejecutar directo:
godot                                  # corre menu.tscn (escena principal)

# Tests (ver ARCHITECTURE.md para el detalle):
godot --headless -s tests/logic_check.gd
```

## Estado y convenciones clave

- **Es un prototipo jugable de punta a punta**: se puede jugar la campaña,
  editar niveles, probarlos y crear personajes; todo persiste en disco.
- **Coordenadas**: internamente `Vector2i(columna, fila)`, 0-indexado. En la UI
  y los mensajes se muestran como *fila/columna 1-indexadas*.
- **Persistencia**: JSON en `user://` (`campaign.json`, `characters.json`).
- **Sin assets de audio**: las voces de los personajes se sintetizan en runtime.
</content>
</invoke>
