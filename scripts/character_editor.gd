extends Control
## Editor de personajes: paleta de partes por sección (sombrero, cabeza, ojos,
## nariz, boca, torso), arrastrar y soltar al escenario, mover / escalar /
## eliminar partes, y guardado en user://character.json.
##
## Los sprites se descubren en res://sprites por prefijo de nombre de archivo,
## así agregar p. ej. "hat_vikingo.png" suma una opción a la sección Sombrero.

const SPRITES_DIR := "res://sprites"
const DEFAULT_SCALE := 0.26
const MIN_SCALE := 0.08
const MAX_SCALE := 0.8
const SNAP_PX := 8.0

# Pupilas y pestañeo: la lógica de dibujo vive en CharacterRenderer
# (compartida con la galería); acá quedan alias para los tiempos.
const BLINK_MIN := CharacterRenderer.BLINK_MIN
const BLINK_MAX := CharacterRenderer.BLINK_MAX
const BLINK_CLOSE := CharacterRenderer.BLINK_CLOSE
const BLINK_HOLD := CharacterRenderer.BLINK_HOLD
const BLINK_OPEN := CharacterRenderer.BLINK_OPEN
const BLINK_TOTAL := CharacterRenderer.BLINK_TOTAL

# Voces de monstruo tierno: balbuceo sintetizado (sin archivos de audio).
const AUDIO_RATE := 22050
const VOICES := [
	{"id": "pii", "label": "Pii", "desc": "aguda", "base": 600.0, "wave": "sine_vib",
		"syl": [7, 12], "dur": [0.06, 0.11], "gap": [0.03, 0.07]},
	{"id": "blub", "label": "Blub", "desc": "media", "base": 320.0, "wave": "soft_square",
		"syl": [6, 10], "dur": [0.08, 0.13], "gap": [0.04, 0.08]},
	{"id": "grr", "label": "Grr", "desc": "grave", "base": 150.0, "wave": "saw",
		"syl": [5, 9], "dur": [0.10, 0.16], "gap": [0.05, 0.09]},
]

# Orden = capas: lo primero se dibuja abajo. `prefixes` mapea archivos a sección.
const PARTS := [
	{"id": "body", "label": "Torso", "prefixes": ["body", "torso"]},
	{"id": "head", "label": "Cabeza", "prefixes": ["head", "cabeza"]},
	{"id": "eyes", "label": "Ojos", "prefixes": ["eyes", "ojos"]},
	{"id": "nose", "label": "Nariz", "prefixes": ["nose", "nariz"]},
	{"id": "mouth", "label": "Boca", "prefixes": ["mouth", "boca"]},
	{"id": "hat", "label": "Sombrero", "prefixes": ["hat", "sombrero"]},
]

# Armado de ejemplo: [offset_x, offset_y, escala] relativo al centro del escenario.
# Cabeza/ojos/nariz/boca comparten centro: vienen co-dibujados en el mismo lienzo.
const EXAMPLE := {
	"body": [0.0, 150.0, 0.30],
	"head": [0.0, -60.0, 0.28],
	"eyes": [0.0, -60.0, 0.28],
	"nose": [0.0, -60.0, 0.28],
	"mouth": [0.0, -60.0, 0.28],
	"hat": [0.0, -190.0, 0.30],
}

var placed := {}  # part_id -> {part, path, pos: Vector2, scale: float}
var selected := ""
var hover_part := ""
var dragging := false
var drag_offset := Vector2.ZERO
var snap_guide := false
var dirty := false
var updating := false

var stage: Stage
var scale_slider: HSlider
var sel_name: Label
var sel_buttons: Array = []
var save_button: Button
var status_label: Label

var _stage_sb := StyleBoxFlat.new()
var _blink_wait := 0.0
var _blink_left := 0.0

var selected_voice := "pii"
var voice_buttons := {}
var force_mouth_open := 0.0  # para pruebas/capturas: fuerza la boca abierta
var _talk_player: AudioStreamPlayer
var _talk_syllables: Array = []  # Vector2(inicio, fin) en segundos

var char_name := "Personaje"
var name_edit: LineEdit
var exit_dialog: ConfirmationDialog


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiKit.COL_BG)
	CharacterStore.ensure_loaded()
	_stage_sb.bg_color = Color("262230")
	_stage_sb.set_corner_radius_all(16)
	_blink_wait = randf_range(BLINK_MIN, BLINK_MAX)
	_build_ui()
	await get_tree().process_frame  # esperar layout: las posiciones son relativas al centro
	_load_character()
	_refresh_selection_panel()


func _process(delta: float) -> void:
	if not placed.has("eyes"):
		_blink_left = 0.0
		return
	if _blink_left > 0.0:
		_blink_left = maxf(_blink_left - delta, 0.0)
		if _blink_left == 0.0:
			_blink_wait = randf_range(BLINK_MIN, BLINK_MAX)
	else:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_left = BLINK_TOTAL


func is_blinking() -> bool:
	return _blink_left > 0.0


## Cuán cerrado está el párpado: 0 = abierto, 1 = cerrado del todo.
func blink_amount() -> float:
	return CharacterRenderer.blink_amount(_blink_left)


# --- Sprites (delegado en CharacterRenderer, compartido con la galería) ---

func _load_sprite(path: String) -> Dictionary:
	return CharacterRenderer.sprite(path)


func _discover_sprites() -> Dictionary:
	var result := {}
	for p in PARTS:
		result[p.id] = []
	var dir := DirAccess.open(SPRITES_DIR)
	if dir == null:
		return result
	for file in dir.get_files():
		if not file.ends_with(".png"):
			continue
		for p in PARTS:
			for prefix in p.prefixes:
				if file.begins_with(prefix):
					result[p.id].append(SPRITES_DIR + "/" + file)
					break
	return result


# --- Construcción de UI ---

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	# --- Paleta (izquierda) ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	UiKit.label(left, "EDITOR DE PERSONAJES", 18, UiKit.COL_GOLD)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var palette := VBoxContainer.new()
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette.add_theme_constant_override("separation", 10)
	scroll.add_child(palette)

	var sprites := _discover_sprites()
	# Paleta en orden anatómico (de la cabeza al torso), independiente de las capas.
	for part_id in ["hat", "head", "eyes", "nose", "mouth", "body"]:
		var p := _part_def(part_id)
		var box := UiKit.section(palette, p.label.to_upper())
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		box.add_child(flow)
		if sprites[p.id].is_empty():
			UiKit.label(flow, "(sin sprites todavía)", 12, UiKit.COL_DIM)
		for path in sprites[p.id]:
			var thumb := PaletteThumb.new()
			thumb.main = self
			thumb.part = p.id
			thumb.path = path
			thumb.tooltip_text = path.get_file()
			flow.add_child(thumb)

	# --- Escenario (centro) ---
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", 8)
	root.add_child(center_col)

	stage = Stage.new()
	stage.main = self
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_exited.connect(func():
		hover_part = "")
	center_col.add_child(stage)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", UiKit.COL_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Arrastrá una parte de la izquierda al escenario."
	center_col.add_child(status_label)

	# --- Panel derecho ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(270, 0)
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	right.add_child(top_row)
	save_button = _small_button(top_row, "Guardar", UiKit.COL_GOLD, _on_save)
	_small_button(top_row, "Galería", UiKit.COL_NEUTRAL, _on_gallery)

	exit_dialog = ConfirmationDialog.new()
	exit_dialog.title = "Personaje incompleto"
	exit_dialog.ok_button_text = "Salir sin guardar"
	exit_dialog.cancel_button_text = "Seguir editando"
	exit_dialog.confirmed.connect(_go_gallery)
	add_child(exit_dialog)

	var sel_box := UiKit.section(right, "PARTE SELECCIONADA")
	sel_name = Label.new()
	sel_name.add_theme_font_size_override("font_size", 14)
	sel_name.add_theme_color_override("font_color", UiKit.COL_TEXT)
	sel_box.add_child(sel_name)
	UiKit.label(sel_box, "Escala", 11, UiKit.COL_DIM)
	scale_slider = HSlider.new()
	scale_slider.min_value = MIN_SCALE
	scale_slider.max_value = MAX_SCALE
	scale_slider.step = 0.005
	scale_slider.value_changed.connect(_on_scale_slider)
	sel_box.add_child(scale_slider)
	sel_buttons.append(_small_button(sel_box, "Centrar horizontalmente", UiKit.COL_DEF, _on_center_selected))
	sel_buttons.append(_small_button(sel_box, "Eliminar parte", UiKit.COL_DANGER, _on_delete_selected))

	var char_box := UiKit.section(right, "PERSONAJE")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nombre del personaje"
	name_edit.text_changed.connect(_on_name_changed)
	char_box.add_child(name_edit)
	_small_button(char_box, "Armar ejemplo", UiKit.COL_HEAL, _on_example)
	_small_button(char_box, "Limpiar todo", UiKit.COL_WARN, _on_clear)

	var voice_box := UiKit.section(right, "VOZ")
	var voice_row := HBoxContainer.new()
	voice_row.add_theme_constant_override("separation", 6)
	voice_box.add_child(voice_row)
	var voice_group := ButtonGroup.new()
	for v in VOICES:
		var b := Button.new()
		b.text = "%s (%s)" % [v.label, v.desc]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_tool_button(b, UiKit.COL_ENERGY)
		b.add_theme_font_size_override("font_size", 12)
		b.button_group = voice_group
		b.pressed.connect(_on_voice_picked.bind(v.id))
		voice_row.add_child(b)
		voice_buttons[v.id] = b
	_small_button(voice_box, "Hablar", UiKit.COL_GOLD, _on_talk)

	_talk_player = AudioStreamPlayer.new()
	add_child(_talk_player)
	_refresh_voice_buttons()

	var help := UiKit.section(right, "AYUDA")
	var h := UiKit.label(help,
		"· Arrastrá una miniatura al escenario.\n· Arrastrá una parte colocada para moverla.\n· Rueda del mouse sobre una parte: escala.\n· Supr / Retroceso: eliminar la selección.\n· Flechas: mover de a 1 px (Shift: 10 px).\n· Soltar cerca del centro la alinea (guía).",
		12, UiKit.COL_DIM)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _small_button(parent: Control, text: String, accent: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(b, accent)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


# --- Colocación y edición de partes ---

func place_part(part_id: String, path: String, pos: Vector2) -> void:
	var prev_scale: float = placed[part_id].scale if placed.has(part_id) else DEFAULT_SCALE
	placed[part_id] = {"part": part_id, "path": path, "pos": _snap_x(pos), "scale": prev_scale}
	selected = part_id
	_mark_dirty()
	_status("%s colocado. Arrastralo para acomodarlo." % _label_for(part_id))
	_refresh_selection_panel()


func _part_def(part_id: String) -> Dictionary:
	for p in PARTS:
		if p.id == part_id:
			return p
	return {}


func _label_for(part_id: String) -> String:
	var def := _part_def(part_id)
	return def.label if not def.is_empty() else part_id


func part_at(point: Vector2) -> String:
	for i in range(PARTS.size() - 1, -1, -1):
		var id: String = PARTS[i].id
		if placed.has(id) and _pixel_hit(placed[id], point):
			return id
	return ""


## Hit-test por píxel: las zonas transparentes del sprite no cuentan.
func _pixel_hit(part: Dictionary, point: Vector2) -> bool:
	var entry := _load_sprite(part.path)
	var img: Image = entry.img
	var img_size := Vector2(img.get_width(), img.get_height())
	var local: Vector2 = (point - part.pos) / part.scale + img_size * 0.5
	if local.x < 0 or local.y < 0 or local.x >= img_size.x or local.y >= img_size.y:
		return false
	return img.get_pixelv(Vector2i(local)).a > 0.05


func _snap_x(pos: Vector2) -> Vector2:
	var cx := stage.size.x * 0.5
	snap_guide = absf(pos.x - cx) < SNAP_PX
	if snap_guide:
		return Vector2(cx, pos.y)
	return pos


func stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := part_at(event.position)
				selected = hit
				if hit != "":
					dragging = true
					drag_offset = event.position - placed[hit].pos
				_refresh_selection_panel()
			else:
				dragging = false
				snap_guide = false
		elif event.pressed and selected != "" and placed.has(selected):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scale_selected(1.06)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scale_selected(1.0 / 1.06)
	elif event is InputEventMouseMotion:
		hover_part = part_at(event.position) if not dragging else selected
		stage.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_part != "" \
			else Control.CURSOR_ARROW
		if dragging and placed.has(selected):
			placed[selected].pos = _snap_x(event.position - drag_offset)
			_mark_dirty()


func _scale_selected(factor: float) -> void:
	if selected == "" or not placed.has(selected):
		return
	placed[selected].scale = clampf(placed[selected].scale * factor, MIN_SCALE, MAX_SCALE)
	_mark_dirty()
	_refresh_selection_panel()


func _unhandled_input(event: InputEvent) -> void:
	if selected == "" or not placed.has(selected):
		return
	if event is InputEventKey and event.pressed:
		var step := 10.0 if event.shift_pressed else 1.0
		match event.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				_on_delete_selected()
			KEY_LEFT:
				placed[selected].pos.x -= step
				_mark_dirty()
			KEY_RIGHT:
				placed[selected].pos.x += step
				_mark_dirty()
			KEY_UP:
				placed[selected].pos.y -= step
				_mark_dirty()
			KEY_DOWN:
				placed[selected].pos.y += step
				_mark_dirty()


# --- Panel de selección ---

func _refresh_selection_panel() -> void:
	updating = true
	var has_sel: bool = selected != "" and placed.has(selected)
	sel_name.text = _label_for(selected) if has_sel else "Nada seleccionado"
	scale_slider.editable = has_sel
	scale_slider.value = placed[selected].scale if has_sel else DEFAULT_SCALE
	for b in sel_buttons:
		b.disabled = not has_sel
	updating = false


func _on_scale_slider(value: float) -> void:
	if updating or selected == "" or not placed.has(selected):
		return
	placed[selected].scale = value
	_mark_dirty()


func _on_center_selected() -> void:
	if selected == "" or not placed.has(selected):
		return
	placed[selected].pos.x = stage.size.x * 0.5
	_mark_dirty()


func _on_delete_selected() -> void:
	if selected == "" or not placed.has(selected):
		return
	var label := _label_for(selected)
	placed.erase(selected)
	selected = ""
	_mark_dirty()
	_status("%s eliminado." % label)
	_refresh_selection_panel()


# --- Personaje completo ---

func _on_example() -> void:
	var sprites := _discover_sprites()
	var center := stage.size * 0.5
	placed = {}
	for p in PARTS:
		if sprites[p.id].is_empty() or not EXAMPLE.has(p.id):
			continue
		var e: Array = EXAMPLE[p.id]
		placed[p.id] = {"part": p.id, "path": sprites[p.id][0],
			"pos": center + Vector2(e[0], e[1]), "scale": e[2]}
	selected = ""
	snap_guide = false
	_mark_dirty()
	_status("Personaje de ejemplo armado.")
	_refresh_selection_panel()


func _on_clear() -> void:
	placed = {}
	selected = ""
	_mark_dirty()
	_status("Escenario limpio.")
	_refresh_selection_panel()


# --- Voz: balbuceo sintetizado y boca que habla ---

func _on_voice_picked(voice_id: String) -> void:
	selected_voice = voice_id
	_mark_dirty()
	_status("Voz elegida: %s." % _voice_def(voice_id).label)


func _refresh_voice_buttons() -> void:
	for id in voice_buttons:
		voice_buttons[id].button_pressed = id == selected_voice


func _voice_def(voice_id: String) -> Dictionary:
	for v in VOICES:
		if v.id == voice_id:
			return v
	return VOICES[0]


func _on_talk() -> void:
	var voice := _voice_def(selected_voice)
	_talk_player.stop()
	_talk_player.stream = _generate_babble(voice)
	_talk_player.play()
	_status("%s está hablando con voz %s..." % ["El personaje", voice.label.to_lower()])


## Genera un balbuceo aleatorio: sílabas cortas con tono, envolvente y pausas.
## Registra los intervalos de cada sílaba para sincronizar la boca.
func _generate_babble(voice: Dictionary) -> AudioStreamWAV:
	_talk_syllables = []
	var pcm := PackedFloat32Array()
	var phase := 0.0
	var n_syl := randi_range(voice.syl[0], voice.syl[1])
	for s in n_syl:
		# Pausa entre sílabas (también antes de la primera: arranque natural).
		var gap := randf_range(voice.gap[0], voice.gap[1])
		for i in int(gap * AUDIO_RATE):
			pcm.append(0.0)
		var dur := randf_range(voice.dur[0], voice.dur[1])
		var start := pcm.size() / float(AUDIO_RATE)
		_talk_syllables.append(Vector2(start, start + dur))
		var f0: float = voice.base * randf_range(0.85, 1.25)
		var glide := randf_range(0.90, 1.06)  # deriva de tono dentro de la sílaba
		var n := int(dur * AUDIO_RATE)
		for i in n:
			var prog := i / float(n)
			var freq := f0 * lerpf(1.0, glide, prog)
			if voice.wave == "sine_vib":
				freq *= 1.0 + 0.05 * sin(TAU * 7.0 * (pcm.size() / float(AUDIO_RATE)))
			phase = fmod(phase + freq / AUDIO_RATE, 1.0)
			var env := clampf(minf(prog / 0.18, (1.0 - prog) / 0.30), 0.0, 1.0)
			pcm.append(_wave_sample(voice.wave, phase) * env * 0.45)
	for i in int(0.08 * AUDIO_RATE):  # colita de silencio
		pcm.append(0.0)

	var data := PackedByteArray()
	data.resize(pcm.size() * 2)
	for i in pcm.size():
		data.encode_s16(i * 2, int(clampf(pcm[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _wave_sample(kind: String, phase: float) -> float:
	match kind:
		"sine_vib":
			return sin(TAU * phase)
		"soft_square":
			return clampf(sin(TAU * phase) * 3.0, -1.0, 1.0) * 0.8
		"saw":
			return (2.0 * phase - 1.0) * 0.7 + sin(TAU * phase) * 0.3
	return sin(TAU * phase)


func is_talking() -> bool:
	return force_mouth_open > 0.0 or (_talk_player != null and _talk_player.playing)


## Pulso de la boca mientras habla: 0..1 en loop (grande -> chico -> grande).
func mouth_pulse() -> float:
	if force_mouth_open > 0.0:
		return force_mouth_open
	if not is_talking():
		return 0.0
	var pos := _talk_player.get_playback_position() + AudioServer.get_time_since_last_mix()
	return 0.5 + 0.5 * sin(TAU * 7.0 * pos)


# --- Persistencia ---

func _on_name_changed(text: String) -> void:
	if updating:
		return
	char_name = text
	_mark_dirty()


## Partes que faltan para que el personaje esté completo (todas son obligatorias).
func missing_parts() -> Array:
	var missing := []
	for p in PARTS:
		if not placed.has(p.id):
			missing.append(p.label)
	return missing


func _on_save() -> void:
	var missing := missing_parts()
	if not missing.is_empty():
		_status("No se puede guardar: faltan %s." % ", ".join(PackedStringArray(missing)))
		return
	var center := stage.size * 0.5
	var parts := []
	for p in PARTS:
		var part: Dictionary = placed[p.id]
		parts.append({
			"part": p.id,
			"path": part.path,
			"pos": [part.pos.x - center.x, part.pos.y - center.y],
			"scale": part.scale,
		})
	var data := {"name": char_name, "voice": selected_voice, "parts": parts}
	if CharacterStore.edit_index >= 0 and CharacterStore.edit_index < CharacterStore.characters.size():
		CharacterStore.characters[CharacterStore.edit_index] = data
	else:
		CharacterStore.characters.append(data)
		CharacterStore.edit_index = CharacterStore.characters.size() - 1
	CharacterStore.save()
	dirty = false
	save_button.text = "Guardar"
	_status("Personaje guardado en la galería ✓")


func _on_gallery() -> void:
	if not dirty:
		_go_gallery()
		return
	if missing_parts().is_empty():
		_on_save()
		_go_gallery()
		return
	exit_dialog.dialog_text = "Faltan partes (%s), así que el personaje\nno se puede guardar. ¿Salir igual?" \
		% ", ".join(PackedStringArray(missing_parts()))
	exit_dialog.popup_centered()


func _go_gallery() -> void:
	get_tree().change_scene_to_file("res://character_gallery.tscn")


func _load_character() -> void:
	var center := stage.size * 0.5
	var index := CharacterStore.edit_index
	if index >= 0 and index < CharacterStore.characters.size():
		var data: Dictionary = CharacterStore.characters[index]
		char_name = str(data.get("name", "Personaje"))
		selected_voice = str(data.get("voice", "pii"))
		for entry in data.get("parts", []):
			var path := str(entry.path)
			if not ResourceLoader.exists(path):
				continue
			placed[str(entry.part)] = {
				"part": str(entry.part),
				"path": path,
				"pos": center + Vector2(float(entry.pos[0]), float(entry.pos[1])),
				"scale": clampf(float(entry.scale), MIN_SCALE, MAX_SCALE),
			}
	else:
		char_name = "Personaje %d" % (CharacterStore.characters.size() + 1)
	updating = true
	name_edit.text = char_name
	updating = false
	_refresh_voice_buttons()


func _mark_dirty() -> void:
	dirty = true
	save_button.text = "Guardar *"


func _status(text: String) -> void:
	status_label.text = text


# --- Dibujo del escenario ---

func draw_stage(c: Control) -> void:
	var font := c.get_theme_default_font()
	c.draw_style_box(_stage_sb, Rect2(Vector2.ZERO, c.size))

	# Piso (elipse suave)
	c.draw_set_transform(Vector2(c.size.x * 0.5, c.size.y * 0.84), 0.0, Vector2(1.0, 0.26))
	c.draw_circle(Vector2.ZERO, c.size.x * 0.21, Color(0, 0, 0, 0.22))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if placed.is_empty():
		c.draw_string(font, Vector2(0, c.size.y * 0.5), "Arrastrá partes desde la izquierda",
			HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 18, Color(1, 1, 1, 0.25))

	for p in PARTS:
		if not placed.has(p.id):
			continue
		var part: Dictionary = placed[p.id]
		if p.id == "eyes":
			CharacterRenderer.draw_eyes(c, part.path, part.pos, part.scale,
				stage.get_local_mouse_position(), blink_amount())
		elif p.id == "mouth":
			CharacterRenderer.draw_mouth(c, part.path, part.pos, part.scale,
				is_talking(), mouth_pulse())
		else:
			CharacterRenderer.draw_part(c, part.path, part.pos, part.scale)

	# Marco de selección sobre el contenido real (sin márgenes transparentes)
	if selected != "" and placed.has(selected):
		var rect := _content_rect(placed[selected])
		c.draw_rect(rect.grow(6), UiKit.COL_GOLD, false, 2.0)
		for corner in [rect.grow(6).position, rect.grow(6).position + Vector2(rect.grow(6).size.x, 0),
				rect.grow(6).position + Vector2(0, rect.grow(6).size.y), rect.grow(6).end]:
			c.draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), UiKit.COL_GOLD)

	# Guía de centrado mientras se arrastra
	if snap_guide and dragging:
		c.draw_line(Vector2(c.size.x * 0.5, 12), Vector2(c.size.x * 0.5, c.size.y - 12),
			Color(UiKit.COL_GOLD.r, UiKit.COL_GOLD.g, UiKit.COL_GOLD.b, 0.6), 2.0)


func _eye_info(path: String) -> Array:
	return CharacterRenderer.eye_info(path)


func _content_rect(part: Dictionary) -> Rect2:
	return CharacterRenderer.content_rect(part.path, part.pos, part.scale)


func make_drag_preview(path: String) -> Control:
	var entry := _load_sprite(path)
	var wrap := Control.new()
	var tr := TextureRect.new()
	tr.texture = entry.tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	var sz := Vector2(entry.img.get_width(), entry.img.get_height()) * DEFAULT_SCALE
	tr.custom_minimum_size = sz
	tr.size = sz
	tr.position = -sz * 0.5  # centrado bajo el cursor, igual que al soltar
	tr.modulate = Color(1, 1, 1, 0.65)
	wrap.add_child(tr)
	return wrap


# --- Vistas internas ---

class Stage:
	extends Control

	var main

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		main.draw_stage(self)

	func _gui_input(event: InputEvent) -> void:
		main.stage_input(event)

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.get("kind") == "part"

	func _drop_data(pos: Vector2, data) -> void:
		main.place_part(data.part, data.path, pos)


class PaletteThumb:
	extends Control

	var main
	var part := ""
	var path := ""
	var hovering := false

	func _init() -> void:
		custom_minimum_size = Vector2(118, 100)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _ready() -> void:
		mouse_entered.connect(func():
			hovering = true
			queue_redraw())
		mouse_exited.connect(func():
			hovering = false
			queue_redraw())

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.bg_color = Color("3f3950") if hovering else Color("383344")
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var entry: Dictionary = main._load_sprite(path)
		var used: Rect2i = entry.used
		var avail := size - Vector2(16, 16)
		var rs := Vector2(used.size)
		var s := minf(avail.x / rs.x, avail.y / rs.y)
		var dst := Rect2(size * 0.5 - rs * s * 0.5, rs * s)
		draw_texture_rect_region(entry.tex, dst, Rect2(used))

	func _get_drag_data(_pos: Vector2):
		set_drag_preview(main.make_drag_preview(path))
		return {"kind": "part", "part": part, "path": path}
