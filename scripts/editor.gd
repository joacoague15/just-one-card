extends Control
## Editor de niveles: lista ordenable de niveles, pintado del mapa (jugador,
## obstáculos, enemigos), catálogo de tipos de monstruo con stats editables y
## ajustes por enemigo colocado. Guarda en user://campaign.json (LevelStore).

const STAT_KEYS := ["health", "speed", "attack", "defense", "range"]
const STAT_LABELS := {"health": "Vida", "speed": "Velocidad", "attack": "Ataque",
	"defense": "Defensa", "range": "Alcance"}

var level_index := 0
var tool := "player"  # "player" | "obstacle" | "erase" | "select" | "monster:<id>"
var selected_monster := -1  # índice dentro de current_level().monsters
var selected_type := ""  # id seleccionado en el catálogo
var dirty := false
var hover_cell := Vector2i(-1, -1)
var tile := 64
var updating := false  # evita bucles al refrescar widgets

var canvas: EditorCanvas
var canvas_holder: Control
var level_list: ItemList
var name_edit: LineEdit
var width_spin: SpinBox
var height_spin: SpinBox
var warn_label: Label
var tools_grid: GridContainer
var tool_group := ButtonGroup.new()
var sel_panel: VBoxContainer
var sel_title: Label
var sel_spins := {}
var type_list: ItemList
var type_name_edit: LineEdit
var type_spins := {}
var save_button: Button
var status_label: Label

var _tile_sb := StyleBoxFlat.new()
var _hover_sb := StyleBoxFlat.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiKit.COL_BG)
	LevelStore.ensure_loaded()
	_tile_sb.set_corner_radius_all(8)
	_hover_sb.set_corner_radius_all(8)
	_hover_sb.bg_color = Color(1, 1, 0.6, 0.06)
	_hover_sb.border_color = UiKit.COL_GOLD
	_hover_sb.set_border_width_all(2)
	selected_type = LevelStore.monster_types().keys()[0] if not LevelStore.monster_types().is_empty() else ""
	_build_ui()
	_select_level(0)
	_refresh_types()
	_rebuild_tool_buttons()


func current_level() -> Dictionary:
	return LevelStore.levels()[level_index]


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

	# --- Columna izquierda: niveles + catálogo ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(270, 0)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)

	UiKit.label(left, "EDITOR DE NIVELES", 18, UiKit.COL_GOLD)

	var lv_box := UiKit.section(left, "NIVELES (orden de juego)", true)
	level_list = ItemList.new()
	level_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_list.custom_minimum_size = Vector2(0, 140)
	level_list.item_selected.connect(_on_level_selected)
	lv_box.add_child(level_list)
	var lv_row1 := HBoxContainer.new()
	lv_row1.add_theme_constant_override("separation", 6)
	lv_box.add_child(lv_row1)
	_small_button(lv_row1, "Nuevo", UiKit.COL_HEAL, _on_level_new)
	_small_button(lv_row1, "Duplicar", UiKit.COL_NEUTRAL, _on_level_duplicate)
	_small_button(lv_row1, "Borrar", UiKit.COL_DANGER, _on_level_delete)
	var lv_row2 := HBoxContainer.new()
	lv_row2.add_theme_constant_override("separation", 6)
	lv_box.add_child(lv_row2)
	_small_button(lv_row2, "▲ Subir", UiKit.COL_NEUTRAL, _on_level_up)
	_small_button(lv_row2, "▼ Bajar", UiKit.COL_NEUTRAL, _on_level_down)

	var cat_box := UiKit.section(left, "CATÁLOGO DE MONSTRUOS", true)
	type_list = ItemList.new()
	type_list.custom_minimum_size = Vector2(0, 90)
	type_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	type_list.item_selected.connect(_on_type_selected)
	cat_box.add_child(type_list)
	type_name_edit = LineEdit.new()
	type_name_edit.placeholder_text = "Nombre del tipo"
	type_name_edit.text_changed.connect(_on_type_renamed)
	cat_box.add_child(type_name_edit)
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.add_theme_constant_override("h_separation", 8)
	cat_box.add_child(tgrid)
	for key in STAT_KEYS:
		var l := Label.new()
		l.text = STAT_LABELS[key]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UiKit.COL_DIM)
		tgrid.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 12
		sp.value_changed.connect(_on_type_stat_changed.bind(key))
		tgrid.add_child(sp)
		type_spins[key] = sp
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 6)
	cat_box.add_child(cat_row)
	_small_button(cat_row, "Nuevo tipo", UiKit.COL_HEAL, _on_type_new)
	_small_button(cat_row, "Borrar tipo", UiKit.COL_DANGER, _on_type_delete)

	# --- Centro: canvas ---
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", 8)
	root.add_child(center_col)

	var canvas_wrap := CenterContainer.new()
	canvas_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_col.add_child(canvas_wrap)
	canvas_holder = Control.new()
	canvas_wrap.add_child(canvas_holder)
	canvas = EditorCanvas.new()
	canvas.main = self
	canvas.mouse_exited.connect(func(): hover_cell = Vector2i(-1, -1))
	canvas_holder.add_child(canvas)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", UiKit.COL_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Click izquierdo: pintar con la herramienta · Click derecho: borrar"
	center_col.add_child(status_label)

	# --- Columna derecha: propiedades, herramientas, selección ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(310, 0)
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	right.add_child(top_row)
	save_button = _small_button(top_row, "Guardar", UiKit.COL_GOLD, _on_save)
	_small_button(top_row, "Probar nivel", UiKit.COL_HEAL, _on_test)
	_small_button(top_row, "Menú", UiKit.COL_NEUTRAL, _on_menu)

	var props := UiKit.section(right, "NIVEL")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nombre del nivel"
	name_edit.text_changed.connect(_on_level_renamed)
	props.add_child(name_edit)
	var dims := HBoxContainer.new()
	dims.add_theme_constant_override("separation", 8)
	props.add_child(dims)
	UiKit.label(dims, "Ancho", 12, UiKit.COL_DIM)
	width_spin = SpinBox.new()
	width_spin.min_value = LevelStore.MIN_DIM
	width_spin.max_value = LevelStore.MAX_DIM
	width_spin.value_changed.connect(_on_size_changed)
	dims.add_child(width_spin)
	UiKit.label(dims, "Alto", 12, UiKit.COL_DIM)
	height_spin = SpinBox.new()
	height_spin.min_value = LevelStore.MIN_DIM
	height_spin.max_value = LevelStore.MAX_DIM
	height_spin.value_changed.connect(_on_size_changed)
	dims.add_child(height_spin)
	warn_label = Label.new()
	warn_label.add_theme_font_size_override("font_size", 12)
	warn_label.add_theme_color_override("font_color", UiKit.COL_WARN)
	warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	props.add_child(warn_label)

	var tools_box := UiKit.section(right, "HERRAMIENTAS")
	tools_grid = GridContainer.new()
	tools_grid.columns = 2
	tools_grid.add_theme_constant_override("h_separation", 6)
	tools_grid.add_theme_constant_override("v_separation", 6)
	tools_box.add_child(tools_grid)

	sel_panel = UiKit.section(right, "ENEMIGO SELECCIONADO")
	sel_title = Label.new()
	sel_title.add_theme_font_size_override("font_size", 13)
	sel_title.add_theme_color_override("font_color", UiKit.COL_TEXT)
	sel_panel.add_child(sel_title)
	var sgrid := GridContainer.new()
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", 8)
	sel_panel.add_child(sgrid)
	for key in STAT_KEYS:
		var l := Label.new()
		l.text = STAT_LABELS[key]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UiKit.COL_DIM)
		sgrid.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 12
		sp.value_changed.connect(_on_sel_stat_changed.bind(key))
		sgrid.add_child(sp)
		sel_spins[key] = sp
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 6)
	sel_panel.add_child(sel_row)
	_small_button(sel_row, "Quitar ajustes", UiKit.COL_NEUTRAL, _on_sel_reset)
	_small_button(sel_row, "Eliminar", UiKit.COL_DANGER, _on_sel_delete)


func _small_button(parent: Control, text: String, accent: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(b, accent)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _rebuild_tool_buttons() -> void:
	for c in tools_grid.get_children():
		c.queue_free()
	_add_tool("player", "Jugador", UiKit.COL_PLAYER)
	_add_tool("obstacle", "Obstáculo", UiKit.COL_NEUTRAL)
	_add_tool("erase", "Goma", UiKit.COL_WARN)
	_add_tool("select", "Seleccionar", UiKit.COL_DEF)
	for id in LevelStore.monster_types():
		_add_tool("monster:" + id, LevelStore.monster_types()[id].name, LevelStore.type_color(id))


func _add_tool(id: String, text: String, accent: Color) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_tool_button(b, accent)
	b.add_theme_font_size_override("font_size", 13)
	b.button_group = tool_group
	b.button_pressed = id == tool
	b.pressed.connect(func(): tool = id)
	tools_grid.add_child(b)


# --- Niveles: selección y operaciones ---

func _select_level(index: int) -> void:
	level_index = clampi(index, 0, LevelStore.levels().size() - 1)
	selected_monster = -1
	_refresh_level_list()
	_refresh_level_fields()
	_refresh_selection()
	_resize_canvas()
	_validate()


func _on_level_selected(index: int) -> void:
	_select_level(index)


func _refresh_level_list() -> void:
	level_list.clear()
	for i in LevelStore.levels().size():
		level_list.add_item("%d.  %s" % [i + 1, LevelStore.levels()[i].name])
	level_list.select(level_index)


func _refresh_level_fields() -> void:
	updating = true
	var level := current_level()
	name_edit.text = level.name
	width_spin.value = level.size.x
	height_spin.value = level.size.y
	updating = false


func _on_level_renamed(text: String) -> void:
	if updating:
		return
	current_level().name = text
	level_list.set_item_text(level_index, "%d.  %s" % [level_index + 1, text])
	_mark_dirty()


func _on_size_changed(_value: float) -> void:
	if updating:
		return
	var level := current_level()
	level.size = Vector2i(int(width_spin.value), int(height_spin.value))
	level.player_start = level.player_start.clamp(Vector2i.ZERO, level.size - Vector2i.ONE)
	level.obstacles = level.obstacles.filter(func(o): return GridLogic.in_bounds(o, level.size))
	level.monsters = level.monsters.filter(func(m): return GridLogic.in_bounds(m.position, level.size))
	selected_monster = -1
	_refresh_selection()
	_resize_canvas()
	_validate()
	_mark_dirty()


func _on_level_new() -> void:
	LevelStore.levels().append(LevelStore.blank_level())
	_mark_dirty()
	_select_level(LevelStore.levels().size() - 1)


func _on_level_duplicate() -> void:
	var copy: Dictionary = current_level().duplicate(true)
	copy.name += " (copia)"
	LevelStore.levels().insert(level_index + 1, copy)
	_mark_dirty()
	_select_level(level_index + 1)


func _on_level_delete() -> void:
	if LevelStore.levels().size() <= 1:
		_status("La campaña necesita al menos un nivel.")
		return
	LevelStore.levels().remove_at(level_index)
	_mark_dirty()
	_select_level(mini(level_index, LevelStore.levels().size() - 1))


func _on_level_up() -> void:
	_move_level(-1)


func _on_level_down() -> void:
	_move_level(1)


func _move_level(delta: int) -> void:
	var target := level_index + delta
	if target < 0 or target >= LevelStore.levels().size():
		return
	var lvls: Array = LevelStore.levels()
	var tmp = lvls[level_index]
	lvls[level_index] = lvls[target]
	lvls[target] = tmp
	_mark_dirty()
	_select_level(target)


# --- Pintado del mapa ---

func canvas_paint(cell: Vector2i, erase: bool) -> void:
	var level := current_level()
	if not GridLogic.in_bounds(cell, level.size):
		return
	if erase or tool == "erase":
		_erase_at(cell)
	elif tool == "player":
		if not level.obstacles.has(cell) and _monster_index_at(cell) < 0:
			if level.player_start != cell:
				level.player_start = cell
				_mark_dirty()
	elif tool == "obstacle":
		if cell != level.player_start and _monster_index_at(cell) < 0 \
				and not level.obstacles.has(cell):
			level.obstacles.append(cell)
			_mark_dirty()
	elif tool == "select":
		selected_monster = _monster_index_at(cell)
		_refresh_selection()
	elif tool.begins_with("monster:"):
		var existing := _monster_index_at(cell)
		if existing >= 0:
			selected_monster = existing
			_refresh_selection()
		elif cell != level.player_start and not level.obstacles.has(cell):
			level.monsters.append({"type": tool.substr(8), "position": cell, "overrides": {}})
			selected_monster = level.monsters.size() - 1
			_refresh_selection()
			_mark_dirty()
	_validate()


func _erase_at(cell: Vector2i) -> void:
	var level := current_level()
	var mi := _monster_index_at(cell)
	if mi >= 0:
		level.monsters.remove_at(mi)
		if selected_monster == mi:
			selected_monster = -1
		elif selected_monster > mi:
			selected_monster -= 1
		_refresh_selection()
		_mark_dirty()
		return
	if level.obstacles.has(cell):
		level.obstacles.erase(cell)
		_mark_dirty()


func _monster_index_at(cell: Vector2i) -> int:
	var level := current_level()
	for i in level.monsters.size():
		if level.monsters[i].position == cell:
			return i
	return -1


# --- Selección de enemigo (ajustes por instancia) ---

func _refresh_selection() -> void:
	var has_sel: bool = selected_monster >= 0 and selected_monster < current_level().monsters.size()
	sel_panel.get_parent().visible = has_sel
	if not has_sel:
		return
	updating = true
	var m: Dictionary = current_level().monsters[selected_monster]
	var stats := LevelStore.effective_stats(m)
	var marks := " (con ajustes)" if not m.get("overrides", {}).is_empty() else ""
	sel_title.text = "%s — %s%s" % [stats.name, _cell_name(m.position), marks]
	for key in STAT_KEYS:
		sel_spins[key].value = stats[key]
	updating = false


func _on_sel_stat_changed(value: float, key: String) -> void:
	if updating or selected_monster < 0:
		return
	var m: Dictionary = current_level().monsters[selected_monster]
	var base: int = LevelStore.monster_types()[m.type][key]
	if int(value) == base:
		m.overrides.erase(key)
	else:
		m.overrides[key] = int(value)
	_refresh_selection()
	_mark_dirty()


func _on_sel_reset() -> void:
	if selected_monster < 0:
		return
	current_level().monsters[selected_monster].overrides = {}
	_refresh_selection()
	_mark_dirty()


func _on_sel_delete() -> void:
	if selected_monster < 0:
		return
	current_level().monsters.remove_at(selected_monster)
	selected_monster = -1
	_refresh_selection()
	_validate()
	_mark_dirty()


# --- Catálogo de tipos ---

func _refresh_types() -> void:
	updating = true
	type_list.clear()
	var ids := LevelStore.monster_types().keys()
	for id in ids:
		type_list.add_item(LevelStore.monster_types()[id].name)
		type_list.set_item_custom_fg_color(type_list.item_count - 1, LevelStore.type_color(id))
	var idx := ids.find(selected_type)
	if idx < 0 and not ids.is_empty():
		selected_type = ids[0]
		idx = 0
	if idx >= 0:
		type_list.select(idx)
		var t: Dictionary = LevelStore.monster_types()[selected_type]
		type_name_edit.text = t.name
		for key in STAT_KEYS:
			type_spins[key].value = t[key]
	updating = false


func _on_type_selected(index: int) -> void:
	selected_type = LevelStore.monster_types().keys()[index]
	_refresh_types()


func _on_type_renamed(text: String) -> void:
	if updating or selected_type == "":
		return
	LevelStore.monster_types()[selected_type].name = text
	var idx := LevelStore.monster_types().keys().find(selected_type)
	if idx >= 0:
		type_list.set_item_text(idx, text)
	_rebuild_tool_buttons()
	_refresh_selection()
	_mark_dirty()


func _on_type_stat_changed(value: float, key: String) -> void:
	if updating or selected_type == "":
		return
	LevelStore.monster_types()[selected_type][key] = int(value)
	_refresh_selection()
	_mark_dirty()


func _on_type_new() -> void:
	var n := 1
	while LevelStore.monster_types().has("tipo_%d" % n):
		n += 1
	var id := "tipo_%d" % n
	LevelStore.monster_types()[id] = {
		"name": "Nuevo tipo %d" % n,
		"health": 2, "speed": 4, "attack": 3, "defense": 3, "range": 2,
		"color": LevelStore.next_palette_color(),
	}
	selected_type = id
	_refresh_types()
	_rebuild_tool_buttons()
	_mark_dirty()


func _on_type_delete() -> void:
	if selected_type == "":
		return
	if LevelStore.monster_types().size() <= 1:
		_status("El catálogo necesita al menos un tipo.")
		return
	for level in LevelStore.levels():
		for m in level.monsters:
			if m.type == selected_type:
				_status("No se puede borrar: '%s' se usa en \"%s\"." % [
					LevelStore.monster_types()[selected_type].name, level.name])
				return
	LevelStore.monster_types().erase(selected_type)
	selected_type = ""
	if tool.begins_with("monster:"):
		tool = "player"
	_refresh_types()
	_rebuild_tool_buttons()
	_mark_dirty()


# --- Guardar / probar / salir ---

func _on_save() -> void:
	LevelStore.save()
	dirty = false
	save_button.text = "Guardar"
	_status("Campaña guardada ✓")


func _on_test() -> void:
	LevelStore.save()
	dirty = false
	LevelStore.test_level = level_index
	get_tree().change_scene_to_file("res://main.tscn")


func _on_menu() -> void:
	LevelStore.save()
	get_tree().change_scene_to_file("res://menu.tscn")


func _mark_dirty() -> void:
	dirty = true
	save_button.text = "Guardar *"


func _status(text: String) -> void:
	status_label.text = text


func _validate() -> void:
	var warnings := LevelStore.validate_level(current_level())
	if warnings.is_empty():
		warn_label.text = "Sin advertencias."
		warn_label.add_theme_color_override("font_color", UiKit.COL_HEAL)
	else:
		warn_label.text = "⚠ " + "\n⚠ ".join(PackedStringArray(warnings))
		warn_label.add_theme_color_override("font_color", UiKit.COL_WARN)


# --- Canvas ---

func _resize_canvas() -> void:
	var size: Vector2i = current_level().size
	tile = clampi(int(minf(560.0 / size.x, 600.0 / size.y)), 40, 96)
	var px := Vector2(size.x * tile, size.y * tile)
	canvas.size = px
	canvas_holder.custom_minimum_size = px


func _cell_name(cell: Vector2i) -> String:
	return "fila %d, col %d" % [cell.y + 1, cell.x + 1]


func draw_canvas(c: Control) -> void:
	var font := get_theme_default_font()
	var level := current_level()

	for cell in GridLogic.all_cells(level.size):
		var rect := Rect2(cell.x * tile + 2, cell.y * tile + 2, tile - 4, tile - 4)
		if level.obstacles.has(cell):
			_tile_sb.bg_color = UiKit.COL_OBSTACLE
			c.draw_style_box(_tile_sb, rect)
			var cc := rect.get_center()
			var r := tile * 0.13
			c.draw_circle(cc + Vector2(-r, r * 0.6), r * 1.1, UiKit.COL_ROCK)
			c.draw_circle(cc + Vector2(r, r * 0.3), r * 0.9, UiKit.COL_ROCK.lightened(0.06))
			c.draw_circle(cc + Vector2(-r * 0.15, -r * 0.8), r, UiKit.COL_ROCK.lightened(0.12))
		else:
			_tile_sb.bg_color = UiKit.COL_TILE_A if (cell.x + cell.y) % 2 == 0 else UiKit.COL_TILE_B
			c.draw_style_box(_tile_sb, rect)

	# Coordenadas (fila/columna 1-indexadas) en los bordes.
	for x in level.size.x:
		c.draw_string(font, Vector2(x * tile, 14), str(x + 1),
			HORIZONTAL_ALIGNMENT_CENTER, tile, 10, Color(1, 1, 1, 0.35))
	for y in level.size.y:
		c.draw_string(font, Vector2(4, y * tile + 16), str(y + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.35))

	# Jugador
	var pc := Vector2(level.player_start) * tile + Vector2(tile, tile) * 0.5
	c.draw_circle(pc, tile * 0.3, UiKit.COL_PLAYER)
	c.draw_string(font, pc + Vector2(-tile * 0.3, 7), "J",
		HORIZONTAL_ALIGNMENT_CENTER, tile * 0.6, 18, Color.WHITE)

	# Enemigos
	for i in level.monsters.size():
		var m: Dictionary = level.monsters[i]
		var mc := Vector2(m.position) * tile + Vector2(tile, tile) * 0.5
		var col := LevelStore.type_color(m.type)
		c.draw_circle(mc, tile * 0.27, col)
		var letter_col := Color("2b2735") if col.get_luminance() > 0.55 else Color.WHITE
		c.draw_string(font, mc + Vector2(-tile * 0.27, 6), LevelStore.type_letter(m.type),
			HORIZONTAL_ALIGNMENT_CENTER, tile * 0.54, 16, letter_col)
		if not m.get("overrides", {}).is_empty():
			c.draw_circle(mc + Vector2(tile * 0.22, -tile * 0.22), 5, UiKit.COL_GOLD)
		if i == selected_monster:
			c.draw_arc(mc, tile * 0.38, 0, TAU, 40, UiKit.COL_GOLD, 3.0)

	if GridLogic.in_bounds(hover_cell, level.size):
		c.draw_style_box(_hover_sb,
			Rect2(hover_cell.x * tile + 2, hover_cell.y * tile + 2, tile - 4, tile - 4))


class EditorCanvas:
	extends Control

	var main
	var dragging := false
	var erase_drag := false

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		main.draw_canvas(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				dragging = event.pressed
				erase_drag = event.button_index == MOUSE_BUTTON_RIGHT
				if event.pressed:
					main.canvas_paint(_cell_at(event.position), erase_drag)
		elif event is InputEventMouseMotion:
			main.hover_cell = _cell_at(event.position)
			if dragging:
				main.canvas_paint(_cell_at(event.position), erase_drag)

	func _cell_at(pos: Vector2) -> Vector2i:
		return Vector2i(int(pos.x / main.tile), int(pos.y / main.tile))
