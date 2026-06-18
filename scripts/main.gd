extends Control
## Presentación del prototipo: tablero, HUD, dados, animaciones y overlays.
## Las reglas viven en GameState / MonsterAI / GridLogic.

const STAT_NAMES := {"speed": "Velocidad", "attack": "Ataque", "defense": "Defensa", "range": "Alcance"}

# Paleta compartida (UiKit)
const COL_BG := UiKit.COL_BG
const COL_PANEL := UiKit.COL_PANEL
const COL_TILE_A := UiKit.COL_TILE_A
const COL_TILE_B := UiKit.COL_TILE_B
const COL_OBSTACLE := UiKit.COL_OBSTACLE
const COL_ROCK := UiKit.COL_ROCK
const COL_GOLD := UiKit.COL_GOLD
const COL_TEXT := UiKit.COL_TEXT
const COL_DIM := UiKit.COL_DIM
const COL_PLAYER := UiKit.COL_PLAYER
const COL_SPEED := UiKit.COL_SPEED
const COL_ATK := UiKit.COL_ATK
const COL_DEF := UiKit.COL_DEF
const COL_DANGER := UiKit.COL_DANGER
const COL_HEAL := UiKit.COL_HEAL
const COL_ENERGY := UiKit.COL_ENERGY
const COL_NEUTRAL := UiKit.COL_NEUTRAL

var state := GameState.new()
var turn_no := 0
var tile := 100  # px por celda; se recalcula según las dimensiones del nivel

var board: BoardView
var board_holder: Control
var player_unit: UnitView
var units := {}  # id de monstruo -> UnitView

var hud := {}
var die_views: Array = []
var slot_views := {}
var roll_button: Button
var end_button: Button
var undo_button: Button
var reward_panel: Control
var end_panel: Control
var vignette: ColorRect

var selected_die := -1
var hover_cell := Vector2i(-1, -1)
var telegraph := {}  # predicción de la fase de monstruos (intención enemiga)
var log_lines: Array = []
var busy := false
var rolling := false

var _tile_sb := StyleBoxFlat.new()
var _hover_sb := StyleBoxFlat.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(COL_BG)
	_tile_sb.set_corner_radius_all(10)
	_hover_sb.set_corner_radius_all(10)
	_hover_sb.bg_color = Color(1, 1, 0.6, 0.06)
	_hover_sb.border_color = COL_GOLD
	_hover_sb.set_border_width_all(2)
	_build_ui()
	LevelStore.ensure_loaded()
	_begin_level(maxi(LevelStore.test_level, 0))


# --- Construcción de UI ---

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	var board_wrap := CenterContainer.new()
	board_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(board_wrap)

	board_holder = Control.new()
	board_holder.custom_minimum_size = Vector2(500, 500)
	board_wrap.add_child(board_holder)

	board = BoardView.new()
	board.main = self
	board.size = Vector2(500, 500)
	board.mouse_exited.connect(func(): board_hovered(Vector2i(-1, -1)))
	board_holder.add_child(board)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_constant_override("separation", 10)
	root.add_child(panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	panel.add_child(header)
	hud.level = Label.new()
	hud.level.add_theme_font_size_override("font_size", 24)
	hud.level.add_theme_color_override("font_color", COL_GOLD)
	hud.level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hud.level)
	var exit_btn := Button.new()
	exit_btn.text = "Volver al editor" if LevelStore.test_level >= 0 else "Menú"
	UiKit.style_button(exit_btn, COL_NEUTRAL)
	exit_btn.pressed.connect(_exit_game)
	header.add_child(exit_btn)

	hud.banner = Label.new()
	hud.banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.banner.add_theme_font_size_override("font_size", 13)
	panel.add_child(hud.banner)

	var pbox := _section(panel, "AVENTURERO")
	var hprow := HBoxContainer.new()
	hprow.add_theme_constant_override("separation", 10)
	pbox.add_child(hprow)
	hud.hp_bar = HealthBar.new()
	hprow.add_child(hud.hp_bar)
	hud.hp_text = Label.new()
	hud.hp_text.add_theme_font_size_override("font_size", 14)
	hud.hp_text.add_theme_color_override("font_color", COL_TEXT)
	hprow.add_child(hud.hp_text)
	hud.basestats = Label.new()
	hud.basestats.add_theme_font_size_override("font_size", 13)
	hud.basestats.add_theme_color_override("font_color", COL_DIM)
	pbox.add_child(hud.basestats)

	var dbox := _section(panel, "DADOS DE ENERGÍA")
	var dice_row := HBoxContainer.new()
	dice_row.add_theme_constant_override("separation", 10)
	dbox.add_child(dice_row)
	roll_button = Button.new()
	roll_button.text = "Tirar dados"
	roll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_button.size_flags_vertical = Control.SIZE_FILL
	_style_button(roll_button, COL_ENERGY)
	roll_button.pressed.connect(_on_reroll_pressed)
	dice_row.add_child(roll_button)
	for i in 3:
		var d := DieView.new()
		d.main = self
		d.index = i
		dice_row.add_child(d)
		die_views.append(d)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 10)
	dbox.add_child(slot_row)
	var accents := {"speed": COL_SPEED, "attack": COL_ATK, "defense": COL_DEF}
	for stat in GameState.STATS:
		var s := SlotView.new()
		s.main = self
		s.stat = stat
		s.title = STAT_NAMES[stat].to_upper()
		s.accent = accents[stat]
		slot_row.add_child(s)
		slot_views[stat] = s

	hud.monsters_box = _section(panel, "MONSTRUOS")

	var ibox := _section(panel, "INFORMACIÓN")
	hud.hover = Label.new()
	hud.hover.add_theme_font_size_override("font_size", 13)
	hud.hover.add_theme_color_override("font_color", COL_TEXT)
	hud.hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.hover.custom_minimum_size = Vector2(0, 56)
	ibox.add_child(hud.hover)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	panel.add_child(action_row)
	undo_button = Button.new()
	undo_button.text = "Deshacer"
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(undo_button, COL_NEUTRAL)
	undo_button.pressed.connect(_on_undo_pressed)
	action_row.add_child(undo_button)
	end_button = Button.new()
	end_button.text = "Terminar fase del aventurero"
	end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(end_button, COL_GOLD)
	end_button.pressed.connect(_end_player_phase)
	action_row.add_child(end_button)

	var lbox := _section(panel, "REGISTRO", true)
	hud.log = RichTextLabel.new()
	hud.log.bbcode_enabled = true
	hud.log.scroll_following = true
	hud.log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.log.custom_minimum_size = Vector2(0, 100)
	hud.log.add_theme_font_size_override("normal_font_size", 12)
	lbox.add_child(hud.log)

	vignette = ColorRect.new()
	vignette.color = Color(0.85, 0.12, 0.12, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)

	reward_panel = _make_overlay()
	end_panel = _make_overlay()


func _section(parent: Control, title: String, expand: bool = false) -> VBoxContainer:
	return UiKit.section(parent, title, expand)


func _style_button(b: Button, accent: Color) -> void:
	UiKit.style_button(b, accent)


func _make_overlay() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.08, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.hide()
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(28)
	sb.border_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.35)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	return dim


func _fill_overlay(dim: Control, title: String, title_color: Color, lines: Array, buttons: Array) -> void:
	var panel: PanelContainer = dim.get_child(0).get_child(0)
	for child in panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(380, 0)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", title_color)
	box.add_child(t)
	for line in lines:
		var l := Label.new()
		l.text = line
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", COL_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	for bdef in buttons:  # [texto, callable, disabled, accent]
		var b := Button.new()
		b.text = bdef[0]
		b.pressed.connect(bdef[1])
		b.disabled = bdef[2]
		_style_button(b, bdef[3])
		box.add_child(b)
	dim.modulate.a = 0.0
	dim.show()
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.25)


# --- Niveles y turnos ---

func _begin_level(index: int) -> void:
	state.start_level(index)
	turn_no = 0
	tile = clampi(int(minf(620.0 / state.grid_size.x, 560.0 / state.grid_size.y)), 44, 100)
	var board_px := Vector2(state.grid_size.x * tile, state.grid_size.y * tile)
	board.size = board_px
	board_holder.custom_minimum_size = board_px
	_rebuild_units()
	var level_name: String = LevelStore.levels()[index].name
	_log("— %s —" % level_name, COL_GOLD.to_html(false))
	if state.monsters.is_empty():
		# Nivel sin enemigos (posible desde el editor): se completa solo.
		_on_level_cleared()
		_refresh()
		return
	_start_turn()


func _start_turn() -> void:
	turn_no += 1
	state.new_turn()
	selected_die = -1
	_refresh()
	_auto_roll()  # la tirada es automática (corre como corrutina)


## Tirada automática al empezar el turno: el jugador ya no aprieta un botón.
func _auto_roll() -> void:
	state.roll_dice()
	await _roll_animation()
	_log("Dados: %d, %d y %d. Asignalos a las habilidades." % state.dice, "#cfc8e0")
	_refresh()


## Poder de re-roll (una vez por nivel): vuelve a tirar y limpia la asignación.
func _on_reroll_pressed() -> void:
	if rolling or state.phase != GameState.Phase.ASSIGN_DICE or not state.reroll_available:
		return
	if not state.reroll_dice():
		return
	await _roll_animation()
	_log("¡Re-roll del poder! Nuevos dados: %d, %d y %d." % state.dice, "#b08be8")
	_refresh()


## Animación compartida: hace girar los dados; los valores finales ya están en
## state.dice (los pone _refresh al terminar).
func _roll_animation() -> void:
	rolling = true
	_refresh()
	for step in 7:
		for d in die_views:
			d.value = randi_range(1, 6)
			d.queue_redraw()
		await get_tree().create_timer(0.06).timeout
	rolling = false
	_select_next_free_die()
	_refresh()


func _on_die_pressed(i: int) -> void:
	if state.phase != GameState.Phase.ASSIGN_DICE or not state.dice_rolled or rolling:
		return
	selected_die = -1 if selected_die == i else i
	_refresh()


func _on_stat_pressed(stat: String) -> void:
	if state.phase != GameState.Phase.ASSIGN_DICE or not state.dice_rolled or rolling:
		return
	if selected_die < 0:
		state.unassign(stat)
	else:
		state.assign_die(stat, selected_die)
		_select_next_free_die()
	if state.phase == GameState.Phase.PLAYER:
		selected_die = -1
		_log("Turno listo — Velocidad %d, Ataque %d, Defensa %d." % [
			state.speed_points, state.attack_points, state.defense_total], COL_GOLD.to_html(false))
	_refresh()


func _select_next_free_die() -> void:
	selected_die = -1
	for i in 3:
		if not state.assignment.values().has(i):
			selected_die = i
			return


# --- Tablero: clicks y hover ---

func board_clicked(cell: Vector2i) -> void:
	if busy or state.phase != GameState.Phase.PLAYER or not GridLogic.in_bounds(cell, state.grid_size):
		return
	var m := state.monster_at(cell)
	if not m.is_empty():
		var info := state.player_attack_info(m)
		var atk := state.attack_points
		var def: int = m.defense
		if state.player_attack(m):
			_attack_beam(state.player_pos, cell, COL_GOLD)
			_float_text(cell, "-%d" % info.damage, COL_DANGER)
			_log(_division_breakdown(atk, def, info.damage), "#cfc8e0")
			if m.hp <= 0:
				_log("Atacaste a %s — Daño final: %d. ¡Muere!" % [m.name, info.damage], "#ffd28a")
				_kill_unit(m.id)
				if state.monsters.is_empty():
					_on_level_cleared()
			else:
				_log("Atacaste a %s — Daño final: %d. Le quedan %d PV." % [m.name, info.damage, m.hp], "#ffd28a")
				if units.has(m.id):
					units[m.id].hp = m.hp
					_flash_unit(units[m.id])
		else:
			_float_text(cell, _attack_short_reason(info), COL_DANGER)
			_log(_attack_block_reason(m, info), "#ff9d8a")
	else:
		var reachable := state.player_reachable()
		if reachable.has(cell):
			var blocked := state.obstacles.duplicate()
			blocked.merge(state.monster_cells())
			var dist := GridLogic.dijkstra(state.player_pos, blocked, state.grid_size)
			var path := GridLogic.reconstruct_path(state.player_pos, cell, dist)
			state.try_move_player(cell)
			busy = true
			_refresh()
			await _animate_unit_path(player_unit, path)
			busy = false
	_refresh()


func board_hovered(cell: Vector2i) -> void:
	if cell == hover_cell:
		return
	hover_cell = cell
	var pointer := false
	if not busy and state.phase == GameState.Phase.PLAYER and GridLogic.in_bounds(cell, state.grid_size):
		if not state.monster_at(cell).is_empty() or state.player_reachable().has(cell):
			pointer = true
	board.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if pointer else Control.CURSOR_ARROW
	_update_hover_label()


func _attack_short_reason(info: Dictionary) -> String:
	if info.already_attacked:
		return "Ya atacaste"
	if not info.in_range:
		return "Fuera de alcance"
	if not info.los:
		return "Sin visión"
	return "Sin bloque"


func _attack_block_reason(m: Dictionary, info: Dictionary) -> String:
	if info.already_attacked:
		return "Ya usaste tu ataque este turno."
	if not info.in_range:
		var d := "∞" if info.dist < 0 else str(info.dist)
		return "%s fuera de alcance (distancia %s, alcance %d)." % [m.name, d, state.base.range]
	if not info.los:
		return "No hay línea de visión hacia %s." % m.name
	return "Tu ataque (%d) no completa ni un bloque de la defensa de %s (defensa %d) → 0 de daño." % [
		state.attack_points, m.name, m.defense]


## Explica una resolución por división al estilo "bloques completos".
## Ej.: Ataque 7 contra Defensa 3 → 7 contiene 2 bloque(s) completo(s) de 3 → Daño final: 2.
func _division_breakdown(attack: int, defense: int, dmg: int) -> String:
	var bloques := "bloque completo" if dmg == 1 else "bloques completos"
	return "Ataque %d contra Defensa %d: %d contiene %d %s de %d." % [
		attack, defense, attack, dmg, bloques, defense]


# --- Deshacer ---

func _on_undo_pressed() -> void:
	if busy or state.phase != GameState.Phase.PLAYER or not state.can_undo():
		return
	state.undo()
	_rebuild_units(false)  # sin animación de aparición: el undo es instantáneo
	_log("Deshiciste tu última acción.", "#9b94ae")
	_refresh()


# --- Fase de monstruos ---

func _end_player_phase() -> void:
	if busy or state.phase != GameState.Phase.PLAYER:
		return
	busy = true
	state.phase = GameState.Phase.MONSTERS
	_refresh()
	await _run_monster_phase()
	busy = false
	if state.health <= 0:
		state.phase = GameState.Phase.GAME_OVER
		_refresh()
		_log("El aventurero ha muerto.", COL_DANGER.to_html(false))
		if LevelStore.test_level >= 0:
			_fill_overlay(end_panel, "Has muerto", COL_DANGER,
				["Prueba terminada."],
				[["Volver al editor", _back_to_editor, false, COL_GOLD]])
		else:
			_fill_overlay(end_panel, "Has muerto", COL_DANGER,
				["La partida terminó en el nivel %d." % (state.level_index + 1)],
				[["Reiniciar partida", _restart, false, COL_GOLD],
				["Menú principal", _back_to_menu, false, COL_NEUTRAL]])
		return
	_start_turn()


func _run_monster_phase() -> void:
	_log("— Fase de monstruos —", "#ff9d8a")
	for m in state.monster_turn_order():
		await get_tree().create_timer(0.2).timeout
		var blocked: Dictionary = state.obstacles.duplicate()
		blocked[state.player_pos] = true
		var dist := GridLogic.dijkstra(m.pos, blocked, state.grid_size)
		var dest: Vector2i = MonsterAI.choose_destination(m, state)
		if dest != m.pos:
			var path := GridLogic.reconstruct_path(m.pos, dest, dist)
			m.pos = dest
			_log("%s se mueve a %s." % [m.name, _cell_name(dest)], "#cfc8e0")
			if units.has(m.id):
				await _animate_unit_path(units[m.id], path)
		else:
			_log("%s no se mueve." % m.name, "#9b94ae")
	await get_tree().create_timer(0.25).timeout
	var attackers := state.monsters_attacking()
	if attackers.is_empty():
		_log("Ningún monstruo puede atacar este turno.", "#9b94ae")
		return
	var total := 0
	for m in attackers:
		total += m.attack
		_attack_beam(m.pos, state.player_pos, COL_DANGER)
		await get_tree().create_timer(0.12).timeout
	var dmg := floori(float(total) / float(state.defense_total))
	state.health = maxi(state.health - dmg, 0)
	if dmg > 0:
		_flash_unit(player_unit)
		_float_text(state.player_pos, "-%d" % dmg, COL_DANGER)
		_flash_vignette()
		_shake_board()
	else:
		_float_text(state.player_pos, "¡Bloqueado!", COL_DEF)
	var log_col := "#ff9d8a" if dmg > 0 else "#8fc7ff"
	_log("Atacan %d monstruo(s) por %d contra tu Defensa %d." % [
		attackers.size(), total, state.defense_total], log_col)
	_log(_division_breakdown(total, state.defense_total, dmg), log_col)
	_refresh()
	await get_tree().create_timer(0.6).timeout


# --- Fin de nivel / partida ---

func _on_level_cleared() -> void:
	if LevelStore.test_level >= 0:
		state.phase = GameState.Phase.VICTORY
		_log("¡Nivel superado!", COL_GOLD.to_html(false))
		_fill_overlay(end_panel, "¡Nivel superado!", COL_GOLD,
			["La prueba terminó: mataste a todos los monstruos."],
			[["Volver al editor", _back_to_editor, false, COL_GOLD]])
	elif state.level_index + 1 >= LevelStore.levels().size():
		state.phase = GameState.Phase.VICTORY
		_log("¡Victoria! Completaste todos los niveles.", COL_GOLD.to_html(false))
		_fill_overlay(end_panel, "¡Victoria!", COL_GOLD,
			["Completaste los %d niveles de la campaña." % LevelStore.levels().size()],
			[["Reiniciar partida", _restart, false, COL_GOLD],
			["Menú principal", _back_to_menu, false, COL_NEUTRAL]])
	else:
		state.phase = GameState.Phase.REWARD
		_show_reward()


func _show_reward() -> void:
	var buttons := [["Curarse a vida máxima (%d)" % state.max_health, _choose_reward.bind("heal"), false, COL_HEAL]]
	for stat in ["speed", "attack", "defense", "range"]:
		var v: int = state.base[stat]
		var maxed: bool = v >= GameData.STAT_MAX
		var text := "Mejorar %s: %d → %d" % [STAT_NAMES[stat], v, v + 1]
		if maxed:
			text = "%s al máximo (%d)" % [STAT_NAMES[stat], v]
		buttons.append([text, _choose_reward.bind(stat), maxed, Color("8a82a3")])
	_fill_overlay(reward_panel, "Nivel %d completado" % (state.level_index + 1), COL_GOLD,
		["Elegí una recompensa:"], buttons)


func _choose_reward(kind: String) -> void:
	if kind == "heal":
		state.health = state.max_health
		_log("Recompensa: vida restaurada a %d." % state.max_health, COL_HEAL.to_html(false))
	else:
		state.base[kind] += 1
		_log("Recompensa: %s mejorada a %d." % [STAT_NAMES[kind], state.base[kind]], COL_HEAL.to_html(false))
	reward_panel.hide()
	_begin_level(state.level_index + 1)


func _restart() -> void:
	end_panel.hide()
	reward_panel.hide()
	log_lines.clear()
	hud.log.clear()
	state = GameState.new()
	_begin_level(0)


func _exit_game() -> void:
	if LevelStore.test_level >= 0:
		_back_to_editor()
	else:
		_back_to_menu()


func _back_to_editor() -> void:
	LevelStore.test_level = -1
	get_tree().change_scene_to_file("res://editor.tscn")


func _back_to_menu() -> void:
	LevelStore.test_level = -1
	get_tree().change_scene_to_file("res://menu.tscn")


# --- Unidades y animaciones ---

func _rebuild_units(animate: bool = true) -> void:
	for u in units.values():
		u.queue_free()
	units.clear()
	if is_instance_valid(player_unit):
		player_unit.queue_free()

	player_unit = UnitView.new()
	player_unit.color = COL_PLAYER
	player_unit.letter = "J"
	player_unit.letter_color = Color.WHITE
	player_unit.max_hp = state.max_health
	player_unit.hp = state.health
	player_unit.radius = tile * 0.30
	player_unit.position = _cell_center(state.player_pos)
	board.add_child(player_unit)
	if animate:
		_pop_in(player_unit, 0.0)

	var delay := 0.08
	for m in state.monsters:
		var u := UnitView.new()
		u.color = LevelStore.type_color(m.type)
		u.letter = LevelStore.type_letter(m.type)
		u.letter_color = Color("2b2735") if u.color.get_luminance() > 0.55 else Color.WHITE
		u.max_hp = m.max_hp
		u.hp = m.hp
		u.radius = tile * 0.27
		u.position = _cell_center(m.pos)
		board.add_child(u)
		units[m.id] = u
		if animate:
			_pop_in(u, delay)
			delay += 0.08


func _pop_in(unit: Node2D, delay: float) -> void:
	unit.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(unit, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)


func _animate_unit_path(unit: Node2D, path: Array) -> void:
	if path.is_empty() or not is_instance_valid(unit):
		return
	var tw := create_tween()
	for cell in path:
		tw.tween_property(unit, "position", _cell_center(cell), 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _kill_unit(id: int) -> void:
	if not units.has(id):
		return
	var unit: UnitView = units[id]
	units.erase(id)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "scale", Vector2(0.05, 0.05), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(unit, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(unit.queue_free)


func _flash_unit(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var tw := create_tween()
	tw.tween_property(unit, "modulate", Color(2.5, 1.2, 1.2), 0.08)
	tw.tween_property(unit, "modulate", Color.WHITE, 0.3)


func _float_text(cell: Vector2i, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.z_index = 20
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.position = _cell_center(cell) + Vector2(-40, -16)
	l.custom_minimum_size = Vector2(80, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 40.0, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


func _attack_beam(from_cell: Vector2i, to_cell: Vector2i, color: Color) -> void:
	var line := Line2D.new()
	line.points = [_cell_center(from_cell), _cell_center(to_cell)]
	line.width = 5.0
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	board.add_child(line)
	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.45)
	tw.tween_callback(line.queue_free)


func _flash_vignette() -> void:
	var tw := create_tween()
	tw.tween_property(vignette, "color:a", 0.2, 0.07)
	tw.tween_property(vignette, "color:a", 0.0, 0.4)


func _shake_board() -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(board, "position", Vector2(randf_range(-6, 6), randf_range(-4, 4)), 0.05)
	tw.tween_property(board, "position", Vector2.ZERO, 0.06)


# --- HUD ---

func _refresh() -> void:
	hud.level.text = "Nivel %d  ·  Turno %d" % [state.level_index + 1, turn_no]
	_refresh_banner()

	hud.hp_bar.max_value = state.max_health
	hud.hp_bar.value = state.health
	hud.hp_bar.queue_redraw()
	hud.hp_text.text = "%d / %d" % [state.health, state.max_health]
	hud.basestats.text = "Base:  Velocidad %d   Ataque %d   Defensa %d   Alcance %d" % [
		state.base.speed, state.base.attack, state.base.defense, state.base.range]

	var assigning: bool = state.phase == GameState.Phase.ASSIGN_DICE
	# El botón es el poder de re-roll (una vez por nivel); la tirada normal es automática.
	roll_button.disabled = not assigning or rolling or not state.reroll_available
	roll_button.text = "Re-roll (poder · 1 por nivel)" if state.reroll_available else "Re-roll usado"

	for i in 3:
		var d: DieView = die_views[i]
		if not rolling:
			d.value = state.dice[i] if state.dice_rolled else 0
		d.selected = i == selected_die
		d.usable = assigning and state.dice_rolled and not rolling and not state.assignment.values().has(i)
		d.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if d.usable else Control.CURSOR_ARROW
		d.queue_redraw()

	for stat in GameState.STATS:
		var s: SlotView = slot_views[stat]
		s.usable = assigning and state.dice_rolled and not rolling
		s.hint = s.usable and selected_die >= 0
		s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if s.usable else Control.CURSOR_ARROW
		if assigning or not state.dice_rolled:
			if state.assignment.has(stat):
				var die: int = state.dice[state.assignment[stat]]
				s.big = str(state.base[stat] + die)
				s.small = "base %d + dado %d" % [state.base[stat], die]
			else:
				s.big = "—"
				s.small = "base %d" % state.base[stat]
		else:
			match stat:
				"speed":
					s.big = str(state.speed_points)
					s.small = "movimiento restante"
				"attack":
					if state.has_attacked:
						s.big = "✓"
						s.small = "ataque usado"
					else:
						s.big = str(state.attack_points)
						s.small = "daño = ataque ÷ def"
				"defense":
					s.big = str(state.defense_total)
					s.small = "defensa del turno"
		s.queue_redraw()

	_refresh_monster_rows()
	end_button.disabled = busy or state.phase != GameState.Phase.PLAYER
	undo_button.disabled = busy or state.phase != GameState.Phase.PLAYER or not state.can_undo()
	if is_instance_valid(player_unit):
		player_unit.hp = state.health
		player_unit.max_hp = state.max_health
		player_unit.queue_redraw()
	for m in state.monsters:
		if units.has(m.id):
			units[m.id].hp = m.hp
			units[m.id].queue_redraw()
	# Telegrafiado: se recalcula en cada refresco (tras moverte o atacar), así la
	# intención enemiga refleja siempre tu posición actual.
	telegraph = state.predict_monster_phase() if state.phase == GameState.Phase.PLAYER else {}
	_update_hover_label()


func _refresh_banner() -> void:
	match state.phase:
		GameState.Phase.ASSIGN_DICE:
			_set_banner("FASE DE ENERGÍA — asigná los dados", COL_ENERGY)
		GameState.Phase.PLAYER:
			_set_banner("FASE DEL AVENTURERO — movete y atacá", COL_GOLD)
		GameState.Phase.MONSTERS:
			_set_banner("FASE DE MONSTRUOS", COL_DANGER)
		GameState.Phase.REWARD:
			_set_banner("RECOMPENSA", COL_HEAL)
		GameState.Phase.GAME_OVER:
			_set_banner("DERROTA", COL_DANGER)
		GameState.Phase.VICTORY:
			_set_banner("VICTORIA", COL_GOLD)


func _set_banner(text: String, color: Color) -> void:
	hud.banner.text = text
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.bg_color = Color(color.r, color.g, color.b, 0.16)
	sb.set_content_margin_all(7)
	hud.banner.add_theme_stylebox_override("normal", sb)
	hud.banner.add_theme_color_override("font_color", color.lightened(0.15))


func _refresh_monster_rows() -> void:
	for child in hud.monsters_box.get_children():
		if child is Label and child.text.begins_with("MONSTRUOS"):
			continue
		child.queue_free()
	if state.monsters.is_empty():
		var l := Label.new()
		l.text = "Ninguno"
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", COL_DIM)
		hud.monsters_box.add_child(l)
		return
	for m in state.monsters:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = LevelStore.type_color(m.type)
		row.add_child(dot)
		var name_l := Label.new()
		name_l.text = "%s (%s)" % [m.name, _cell_name(m.pos)]
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.add_theme_color_override("font_color", COL_TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var hp_l := Label.new()
		hp_l.text = "PV %d/%d" % [m.hp, m.max_hp]
		hp_l.add_theme_font_size_override("font_size", 13)
		hp_l.add_theme_color_override("font_color", Color("ff8d8d"))
		row.add_child(hp_l)
		var stats_l := Label.new()
		stats_l.text = "Atq %d · Def %d · Alc %d" % [m.attack, m.defense, m.range]
		stats_l.add_theme_font_size_override("font_size", 12)
		stats_l.add_theme_color_override("font_color", COL_DIM)
		row.add_child(stats_l)
		hud.monsters_box.add_child(row)


func _update_hover_label() -> void:
	var text := ""
	if GridLogic.in_bounds(hover_cell, state.grid_size):
		if state.obstacles.has(hover_cell):
			text = "Obstáculo: bloquea movimiento y línea de visión."
		else:
			var m := state.monster_at(hover_cell)
			if not m.is_empty():
				text = "%s — PV %d/%d | Atq %d Def %d Alc %d" % [
					m.name, m.hp, m.max_hp, m.attack, m.defense, m.range]
				if state.phase == GameState.Phase.PLAYER and not busy:
					var info := state.player_attack_info(m)
					var status: String
					if info.can_attack:
						status = "click para atacar — %d ÷ %d = %d de daño" % [
							state.attack_points, m.defense, info.damage]
					elif info.already_attacked:
						status = "ya atacaste este turno"
					elif not info.in_range:
						status = "fuera de alcance"
					elif not info.los:
						status = "sin línea de visión"
					else:
						status = "tu ataque %d no completa un bloque de %d (0 de daño)" % [
							state.attack_points, m.defense]
					var in_range_txt := "sí" if info.in_range else "no"
					var los_txt := "sí" if info.los else "no"
					text += "\nEn alcance: %s | Visión: %s | Daño: %d — %s" % [
						in_range_txt, los_txt, info.damage, status]
			elif state.phase == GameState.Phase.PLAYER and not busy:
				var reachable := state.player_reachable()
				if reachable.has(hover_cell):
					text = "Mover aquí cuesta %d puntos de velocidad." % reachable[hover_cell]
	if text == "":
		text = _phase_hint()
	hud.hover.text = text


func _phase_hint() -> String:
	match state.phase:
		GameState.Phase.ASSIGN_DICE:
			if not state.dice_rolled or rolling:
				return "Tirando los dados..."
			var extra := "  Tenés un re-roll disponible (poder, 1 por nivel)." if state.reroll_available else ""
			return "Click en un dado y luego en una habilidad para asignarlo." + extra
		GameState.Phase.PLAYER:
			var pd: int = telegraph.get("predicted_damage", 0)
			if pd > 0:
				return "Si terminás el turno así, los monstruos te harán %d de daño. Las flechas muestran su intención." % pd
			return "Click para moverte o atacar. Las flechas muestran la intención enemiga (ahora no te alcanzan)."
		GameState.Phase.MONSTERS:
			return "Los monstruos se mueven y atacan..."
	return ""


func _log(msg: String, hex: String = "#cfc8e0") -> void:
	log_lines.append(msg)
	if hud.has("log"):
		hud.log.append_text("[color=%s]%s[/color]\n" % [hex, msg])


func _cell_name(cell: Vector2i) -> String:
	return "fila %d, col %d" % [cell.y + 1, cell.x + 1]


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * tile + tile * 0.5, cell.y * tile + tile * 0.5)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(cell.x * tile + 3, cell.y * tile + 3, tile - 6, tile - 6)


# --- Dibujo del tablero ---

func draw_board(c: Control) -> void:
	var font := get_theme_default_font()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)

	for cell in GridLogic.all_cells(state.grid_size):
		var rect := _cell_rect(cell)
		if state.obstacles.has(cell):
			_tile_sb.bg_color = COL_OBSTACLE
			c.draw_style_box(_tile_sb, rect)
			var cc := rect.get_center()
			var r := tile * 0.13
			c.draw_circle(cc + Vector2(-r, r * 0.6), r * 1.1, COL_ROCK)
			c.draw_circle(cc + Vector2(r, r * 0.3), r * 0.9, COL_ROCK.lightened(0.06))
			c.draw_circle(cc + Vector2(-r * 0.15, -r * 0.8), r, COL_ROCK.lightened(0.12))
		else:
			_tile_sb.bg_color = COL_TILE_A if (cell.x + cell.y) % 2 == 0 else COL_TILE_B
			c.draw_style_box(_tile_sb, rect)

	var show_player_ui: bool = state.phase == GameState.Phase.PLAYER and not busy
	if show_player_ui:
		var reachable := state.player_reachable()
		for cell in reachable:
			var rect := _cell_rect(cell)
			_tile_sb.bg_color = Color(0.28, 0.65, 0.38, 0.30)
			c.draw_style_box(_tile_sb, rect)
			var badge := rect.position + Vector2(tile * 0.15, tile * 0.15)
			c.draw_circle(badge, tile * 0.11, Color(0.07, 0.22, 0.11, 0.95))
			c.draw_string(font, badge + Vector2(-tile * 0.11, 5), str(reachable[cell]),
				HORIZONTAL_ALIGNMENT_CENTER, tile * 0.22, 13, Color("aef0c0"))
		for m in state.monsters:
			var info := state.player_attack_info(m)
			if info.can_attack:
				c.draw_arc(_cell_center(m.pos), tile * 0.4 + pulse * 3.0, 0, TAU, 40,
					Color(1.0, 0.32, 0.2, 0.55 + pulse * 0.35), 3.0)
		_draw_telegraph(c, font, pulse)

	if GridLogic.in_bounds(hover_cell, state.grid_size):
		c.draw_style_box(_hover_sb, _cell_rect(hover_cell))


# --- Telegrafiado de la fase de monstruos ---

## Dibuja la intención prevista de los monstruos: flecha de movimiento, línea de
## amenaza hacia el aventurero y el daño que recibiría si terminara el turno así.
func _draw_telegraph(c: Control, font: Font, pulse: float) -> void:
	if telegraph.is_empty():
		return
	var moves: Dictionary = telegraph.get("moves", {})
	var attackers: Array = telegraph.get("attackers", [])
	for m in state.monsters:
		var dest: Vector2i = moves.get(m.id, m.pos)
		if dest != m.pos:
			_draw_intent_arrow(c, m.pos, dest)
		if attackers.has(m.id):
			var threat := Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.30 + pulse * 0.2)
			c.draw_line(_cell_center(dest), _cell_center(state.player_pos), threat, 2.5)
	var pd: int = telegraph.get("predicted_damage", 0)
	var badge := _cell_center(state.player_pos) + Vector2(0, -tile * 0.46)
	if pd > 0:
		c.draw_string(font, badge + Vector2(-tile * 0.3, 0), "‼ -%d" % pd,
			HORIZONTAL_ALIGNMENT_CENTER, tile * 0.6, 15, COL_DANGER)
	elif not attackers.is_empty():
		c.draw_string(font, badge + Vector2(-tile * 0.3, 0), "✓ 0",
			HORIZONTAL_ALIGNMENT_CENTER, tile * 0.6, 15, COL_DEF)


func _draw_intent_arrow(c: Control, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var a := _cell_center(from_cell)
	var b := _cell_center(to_cell)
	var col := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.55)
	var dir := (b - a).normalized()
	var tip := b - dir * (tile * 0.30)  # se corta antes para no tapar la ficha
	c.draw_line(a, tip, col, 2.5)
	var perp := Vector2(-dir.y, dir.x)
	var head := tile * 0.10
	c.draw_colored_polygon(PackedVector2Array([
		tip + dir * head,
		tip + perp * head,
		tip - perp * head,
	]), col)


# --- Vistas con dibujo propio ---

class BoardView:
	extends Control

	var main

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		main.draw_board(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			main.board_clicked(_cell_at(event.position))
		elif event is InputEventMouseMotion:
			main.board_hovered(_cell_at(event.position))

	func _cell_at(pos: Vector2) -> Vector2i:
		return Vector2i(int(pos.x / main.tile), int(pos.y / main.tile))


class UnitView:
	extends Node2D

	var color := Color.WHITE
	var letter := "?"
	var letter_color := Color.WHITE
	var hp := 0
	var max_hp := 0
	var radius := 28.0

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		draw_circle(Vector2(0, 4), radius, Color(0, 0, 0, 0.35))
		draw_circle(Vector2.ZERO, radius, color)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color.darkened(0.35), 3.0)
		draw_string(font, Vector2(-radius, 9), letter,
			HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 25, letter_color)
		if max_hp > 0:
			var spacing := clampf(radius * 0.37, 6.0, 11.0)
			var start_x := -(max_hp - 1) * spacing * 0.5
			for i in max_hp:
				var p := Vector2(start_x + i * spacing, -radius - 10.0)
				if i < hp:
					draw_circle(p, 4.0, Color("ff6b6b"))
				else:
					draw_circle(p, 4.0, Color(0, 0, 0, 0.45))


class DieView:
	extends Control

	const PIPS := {
		1: [Vector2(0, 0)],
		2: [Vector2(-1, -1), Vector2(1, 1)],
		3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
	}

	var main
	var index := 0
	var value := 0
	var selected := false
	var usable := false

	func _init() -> void:
		custom_minimum_size = Vector2(58, 58)

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(11)
		if value > 0:
			sb.bg_color = Color("f2eee2") if usable or selected else Color("8f8a7c")
		else:
			sb.bg_color = Color("353043")
		if selected:
			sb.border_color = Color("e8b54d")
			sb.set_border_width_all(3)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if value <= 0:
			draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.5 + 8), "?",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color("9b94ae"))
			return
		for off in PIPS[value]:
			draw_circle(size * 0.5 + off * size.x * 0.22, size.x * 0.07, Color("2b2735"))

	func _gui_input(event: InputEvent) -> void:
		if usable and event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			main._on_die_pressed(index)


class SlotView:
	extends Control

	var main
	var stat := ""
	var title := ""
	var accent := Color.WHITE
	var big := "—"
	var small := ""
	var hint := false
	var usable := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 74)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.bg_color = Color("383344")
		if hint:
			sb.border_color = accent
			sb.set_border_width_all(2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_string(font, Vector2(0, 19), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, accent)
		draw_string(font, Vector2(0, 48), big, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color("ece8f4"))
		if small != "":
			draw_string(font, Vector2(0, 66), small, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color("9b94ae"))

	func _gui_input(event: InputEvent) -> void:
		if usable and event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			main._on_stat_pressed(stat)


class HealthBar:
	extends Control

	var value := 6
	var max_value := 6

	func _init() -> void:
		custom_minimum_size = Vector2(0, 20)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var gap := 4.0
		var w := (size.x - gap * (max_value - 1)) / max_value
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		for i in max_value:
			sb.bg_color = Color("e84d5f") if i < value else Color("221f2b")
			draw_style_box(sb, Rect2(i * (w + gap), 0, w, size.y))
