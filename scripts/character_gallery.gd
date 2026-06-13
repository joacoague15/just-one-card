extends Control
## Galería de creaciones: cada personaje vive en un marco; todos te siguen con
## los ojos (y pestañean). Click en un marco para editar ese personaje.


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiKit.COL_BG)
	CharacterStore.ensure_loaded()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)
	var title := UiKit.label(header, "GALERÍA DE PERSONAJES", 22, UiKit.COL_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "Nuevo personaje", UiKit.COL_HEAL, _on_new)
	_button(header, "Menú", UiKit.COL_NEUTRAL, _on_menu)

	if CharacterStore.characters.is_empty():
		var empty := UiKit.label(col, "Todavía no hay personajes.\nCreá el primero con \"Nuevo personaje\".",
			16, UiKit.COL_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	scroll.add_child(flow)
	for i in CharacterStore.characters.size():
		var frame := CharacterFrame.new()
		frame.main = self
		frame.index = i
		flow.add_child(frame)


func _button(parent: Control, text: String, accent: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UiKit.style_button(b, accent)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func open_editor(index: int) -> void:
	CharacterStore.edit_index = index
	get_tree().change_scene_to_file("res://character_editor.tscn")


func _on_new() -> void:
	CharacterStore.edit_index = -1
	get_tree().change_scene_to_file("res://character_editor.tscn")


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://menu.tscn")


## Un marco con el personaje adentro: lo encaja a su tamaño, le da ojos que
## siguen al mouse y pestañeo propio. Click para editar.
class CharacterFrame:
	extends Control

	var main
	var index := 0
	var hovering := false
	var blink_wait := 0.0
	var blink_left := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(230, 275)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		blink_wait = randf_range(CharacterRenderer.BLINK_MIN, CharacterRenderer.BLINK_MAX)

	func _ready() -> void:
		mouse_entered.connect(func():
			hovering = true)
		mouse_exited.connect(func():
			hovering = false)

	func _process(delta: float) -> void:
		if blink_left > 0.0:
			blink_left = maxf(blink_left - delta, 0.0)
			if blink_left == 0.0:
				blink_wait = randf_range(CharacterRenderer.BLINK_MIN, CharacterRenderer.BLINK_MAX)
		else:
			blink_wait -= delta
			if blink_wait <= 0.0:
				blink_left = CharacterRenderer.BLINK_TOTAL
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			main.open_editor(index)

	func _draw() -> void:
		var data: Dictionary = CharacterStore.characters[index]
		# Marco
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("262230")
		sb.set_corner_radius_all(14)
		sb.border_color = UiKit.COL_GOLD if hovering else Color("4a4458")
		sb.set_border_width_all(2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# Nombre
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, size.y - 14), str(data.get("name", "?")),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14,
			UiKit.COL_GOLD if hovering else UiKit.COL_DIM)
		# Personaje encajado en el área interior
		var parts: Array = data.get("parts", [])
		var bounds := _char_bounds(parts)
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			return
		var inner := Rect2(Vector2(14, 14), size - Vector2(28, 56))
		var s := minf(inner.size.x / bounds.size.x, inner.size.y / bounds.size.y)
		var origin := inner.get_center() - bounds.get_center() * s
		var mouse := get_local_mouse_position()
		for entry in parts:  # ya vienen en orden de capas
			var path := str(entry.path)
			if not ResourceLoader.exists(path):
				continue
			var pos := origin + Vector2(float(entry.pos[0]), float(entry.pos[1])) * s
			var eff_scale := float(entry.scale) * s
			match str(entry.part):
				"eyes":
					CharacterRenderer.draw_eyes(self, path, pos, eff_scale, mouse,
						CharacterRenderer.blink_amount(blink_left))
				"mouth":
					CharacterRenderer.draw_mouth(self, path, pos, eff_scale, false, 0.0)
				_:
					CharacterRenderer.draw_part(self, path, pos, eff_scale)

	## Caja que abarca el contenido de todas las partes, en coordenadas
	## relativas al centro del personaje (como se guardan).
	func _char_bounds(parts: Array) -> Rect2:
		var bounds := Rect2()
		var first := true
		for entry in parts:
			var path := str(entry.path)
			if not ResourceLoader.exists(path):
				continue
			var rect := CharacterRenderer.content_rect(path,
				Vector2(float(entry.pos[0]), float(entry.pos[1])), float(entry.scale))
			bounds = rect if first else bounds.merge(rect)
			first = false
		return bounds
