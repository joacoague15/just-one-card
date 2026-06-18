# Editor de personajes (mecánica de generación de personajes)

Compositor de personajes: se arma un personaje arrastrando **partes** (sprites)
a un escenario, acomodándolas (mover / escalar / centrar), eligiéndole una
**voz** y dándole vida con animación (ojos que siguen al mouse, pestañeo, boca
que habla). Los personajes se guardan en una **galería** y se pueden reeditar.

Esta es la mecánica añadida en el commit *"New character generation mechanic"*.

**Archivos**:
- `scripts/character_editor.gd` (~780 líneas) — el editor.
- `scripts/character_renderer.gd` — dibujo y animación de partes, **compartido**
  con la galería (cache de sprites, ojos/pupilas, pestañeo, boca).
- `scripts/character_gallery.gd` — galería de personajes guardados.
- `scripts/character_store.gd` — colección + persistencia (`user://characters.json`).
- Escenas: `character_editor.tscn`, `character_gallery.tscn`.
- Sprites en `res://sprites/` (los originales sin importar están en `sprites_raw/`).

## Galería (`character_gallery.tscn`)

Punto de entrada desde el menú ("Personajes").

- Muestra cada personaje en un **marco** (`CharacterFrame`, 230×275) que encaja
  el personaje a su tamaño manteniendo proporción.
- Cada marco es **autónomo**: tiene su propio pestañeo y sus **ojos siguen al
  mouse**. Al hacer hover, borde dorado + nombre.
- **Click en un marco** → edita ese personaje. Botón **"Nuevo personaje"** →
  abre el editor en blanco. Estado vacío con mensaje si no hay personajes.

## Editor (`character_editor.tscn`)

Layout de tres columnas: **paleta** (izq.) · **escenario** (centro) · **panel de
propiedades** (der.).

### Partes y capas
Seis secciones anatómicas, dibujadas en orden de capa (de abajo hacia arriba):

```gdscript
const PARTS := [  # orden = capas (body abajo, hat arriba)
  {id:"body",  label:"Torso",    prefixes:["body","torso"]},
  {id:"head",  label:"Cabeza",   prefixes:["head","cabeza"]},
  {id:"eyes",  label:"Ojos",     prefixes:["eyes","ojos"]},
  {id:"nose",  label:"Nariz",    prefixes:["nose","nariz"]},
  {id:"mouth", label:"Boca",     prefixes:["mouth","boca"]},
  {id:"hat",   label:"Sombrero", prefixes:["hat","sombrero"]},
]
```
La paleta se muestra en orden anatómico (sombrero→torso), independiente de las capas.

### Descubrimiento de sprites
`_discover_sprites()` escanea `res://sprites` y agrupa los `.png` por **prefijo
de nombre de archivo**. Agregar p. ej. `hat_vikingo.png` suma automáticamente una
opción a la sección *Sombrero* — sin tocar código.

### Colocar y editar partes
- **Arrastrar y soltar** una miniatura (`PaletteThumb`) al escenario la coloca.
- **Mover**: arrastrar la parte. Al acercarse al centro horizontal aparece una
  **guía de centrado** y engancha (`SNAP_PX = 8`).
- **Escalar**: rueda del mouse sobre la parte, o el slider de Escala
  (`MIN_SCALE 0.08` … `MAX_SCALE 0.8`, default `0.26`).
- **Teclado**: flechas mueven ±1 px (Shift ±10 px); Supr/Retroceso elimina.
- **Botones**: *Centrar horizontalmente*, *Eliminar parte*.
- **Hit-test por píxel** (`_pixel_hit`): las zonas transparentes del sprite no
  cuentan al hacer click, así se selecciona la parte correcta aunque se superpongan.
- Marco de selección dibujado sobre el **contenido real** (sin márgenes
  transparentes), con tiradores en las esquinas.

### Personaje completo
- **Armar ejemplo**: arma un personaje completo con la primera variante de cada
  parte, en posiciones predefinidas (`EXAMPLE`).
- **Limpiar todo**: vacía el escenario.
- **Nombre** editable.

### Voz (balbuceo sintetizado)
Sin archivos de audio: el sonido se **genera en runtime**. Tres voces:

| id | Label | Tono | Onda |
|------|-------|------|------|
| `pii` | Pii | aguda (600 Hz) | seno con vibrato |
| `blub` | Blub | media (320 Hz) | cuadrada suave |
| `grr` | Grr | grave (150 Hz) | sierra |

- `_generate_babble(voice)` crea un `AudioStreamWAV` con sílabas cortas (cantidad
  y duración aleatorias por voz), pausas, *glide* de tono, envolvente y (en `pii`)
  vibrato. Registra los intervalos de cada sílaba.
- Botón **"Hablar"**: reproduce el balbuceo y **anima la boca** sincronizada
  (`is_talking()`, `mouth_pulse()`).

### Animación (vía `CharacterRenderer`, compartida con la galería)
- **Ojos**: `eye_info()` analiza el sprite para detectar los **dos ojos**
  (agrupa píxeles opacos izquierda/derecha; soporta sprites de un solo ojo).
  `draw_eyes()` dibuja pupilas que **siguen al mouse** (con tope de recorrido) y
  un párpado que **cae con el pestañeo**, recortando ojo y pupilas a la línea del
  párpado.
- **Pestañeo**: máquina de estados con espera aleatoria (`BLINK_MIN 2s` …
  `BLINK_MAX 5s`) y transición cerrar→mantener→abrir.
- **Boca**: `draw_mouth()` dibuja un círculo negro que pulsa al hablar; en reposo,
  el sprite normal.

### Guardado
- **Obligatorio tener las 6 partes** para guardar; si faltan, lo avisa.
- `_on_save()` guarda en `CharacterStore` (nuevo o sobrescribe `edit_index`) y
  persiste a `user://characters.json`. Las posiciones se guardan **relativas al
  centro** del escenario.
- Indicador `dirty` (`Guardar *`). Al salir con cambios sin guardar y partes
  faltantes, un `ConfirmationDialog` pregunta si salir igual.

## Persistencia (`character_store.gd`)

Colección de personajes en `user://characters.json`. Formato por personaje:
```gdscript
{ name: String, voice: String,
  parts: [ {part, path, pos: [x, y] relativo al centro, scale} ] }
```
- `edit_index` indica el personaje en edición (`-1` = nuevo).
- **Migración legacy**: si existe el viejo `user://character.json` (un solo
  personaje), se migra a la colección nueva. Ver el formato completo en
  [ARCHITECTURE.md](ARCHITECTURE.md).

## `CharacterRenderer` — utilidades de dibujo

Estático y cacheado, reusado por editor y galería:
- `sprite(path)` — carga/cachea textura + imagen (con `used_rect`).
- `eye_info(path)` — centros y radios de los ojos (cacheado).
- `draw_part / draw_eyes / draw_mouth` — dibujo de partes con animación.
- `blink_amount(blink_left)` — curva del párpado (0 abierto … 1 cerrado).
- `content_rect(path, pos, scale)` — caja del contenido visible (para encajar y
  para el marco de selección).
</content>
