extends SceneTree
## Chequeo end-to-end del editor: operaciones de niveles, pintado, ajustes,
## reordenado y persistencia. Correr:
##   godot -s tests/editor_check.gd          (con ventana, guarda screenshots)
##   godot --headless -s tests/editor_check.gd

var failures := 0
var _backup := ""
var _had_file := false


func _initialize() -> void:
	# El test escribe en el user://campaign.json real: respaldarlo y restaurarlo.
	if FileAccess.file_exists(LevelStore.SAVE_PATH):
		_had_file = true
		_backup = FileAccess.open(LevelStore.SAVE_PATH, FileAccess.READ).get_as_text()
	LevelStore.campaign = LevelStore.default_campaign()
	LevelStore.test_level = -1
	var editor: Control = load("res://editor.tscn").instantiate()
	root.add_child(editor)
	_run(editor)


func _restore_campaign_file() -> void:
	if _had_file:
		FileAccess.open(LevelStore.SAVE_PATH, FileAccess.WRITE).store_string(_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelStore.SAVE_PATH))


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FALLO: " + msg)


func _run(ed: Control) -> void:
	await _frames(10)
	await _shot("ed_01_inicio.png")

	# Crear un nivel nuevo y renombrarlo.
	ed._on_level_new()
	_expect(LevelStore.levels().size() == 3, "nuevo nivel agregado")
	_expect(ed.level_index == 2, "el nivel nuevo queda seleccionado")
	ed._on_level_renamed("Mi nivel")

	# Redimensionar a 7x4 (rectangular).
	ed.width_spin.value = 7
	ed.height_spin.value = 4
	_expect(ed.current_level().size == Vector2i(7, 4), "redimensionado a 7x4")

	# Pintar: jugador, obstáculos, enemigos.
	ed.tool = "player"
	ed.canvas_paint(Vector2i(6, 3), false)
	_expect(ed.current_level().player_start == Vector2i(6, 3), "jugador reubicado")
	ed.tool = "obstacle"
	ed.canvas_paint(Vector2i(2, 2), false)
	ed.canvas_paint(Vector2i(3, 2), false)
	_expect(ed.current_level().obstacles.size() == 2, "obstáculos pintados")
	ed.canvas_paint(Vector2i(6, 3), false)
	_expect(not ed.current_level().obstacles.has(Vector2i(6, 3)),
		"no se puede pintar obstáculo sobre el jugador")
	ed.tool = "monster:spider"
	ed.canvas_paint(Vector2i(0, 0), false)
	ed.tool = "monster:skeleton_archer"
	ed.canvas_paint(Vector2i(1, 0), false)
	_expect(ed.current_level().monsters.size() == 2, "dos enemigos colocados")
	_expect(ed.selected_monster == 1, "el último enemigo queda seleccionado")

	# Ajuste por instancia: vida del esqueleto 3 -> 5.
	ed.sel_spins["health"].value = 5
	_expect(ed.current_level().monsters[1].overrides.get("health", -1) == 5,
		"override de vida registrado")
	ed.sel_spins["health"].value = 3
	_expect(not ed.current_level().monsters[1].overrides.has("health"),
		"volver al valor base borra el override")
	ed.sel_spins["health"].value = 5

	# Goma: borrar un obstáculo y un enemigo.
	ed.tool = "erase"
	ed.canvas_paint(Vector2i(2, 2), false)
	_expect(ed.current_level().obstacles.size() == 1, "goma borra obstáculo")

	# Validación en vivo.
	_expect("Sin advertencias" in ed.warn_label.text or "⚠" in ed.warn_label.text,
		"el panel de validación muestra estado")

	await _frames(3)
	await _shot("ed_02_nivel_editado.png")

	# Reordenar: subirlo del puesto 3 al 2.
	ed._on_level_up()
	_expect(ed.level_index == 1 and LevelStore.levels()[1].name == "Mi nivel",
		"nivel reordenado hacia arriba")

	# Tipo nuevo en el catálogo.
	ed._on_type_new()
	_expect(LevelStore.monster_types().size() == 3, "tipo nuevo en el catálogo")
	ed._on_type_delete()
	_expect(LevelStore.monster_types().size() == 2, "tipo sin uso se puede borrar")

	# No se puede borrar un tipo en uso.
	ed.selected_type = "spider"
	ed._on_type_delete()
	_expect(LevelStore.monster_types().has("spider"), "tipo en uso no se borra")

	# Guardar, vaciar memoria y recargar desde disco.
	ed._on_save()
	LevelStore.campaign = {}
	LevelStore.ensure_loaded()
	_expect(LevelStore.levels().size() == 3, "persistencia: 3 niveles")
	_expect(LevelStore.levels()[1].name == "Mi nivel", "persistencia: orden y nombre")
	_expect(LevelStore.levels()[1].size == Vector2i(7, 4), "persistencia: dimensiones")
	_expect(LevelStore.levels()[1].monsters[1].overrides.get("health", -1) == 5,
		"persistencia: overrides")

	_restore_campaign_file()
	if failures == 0:
		print("EDITOR OK")
		quit(0)
	else:
		print("FALLARON %d chequeos del editor" % failures)
		quit(1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://tests/" + file_name)
	print("screenshot: ", file_name)
