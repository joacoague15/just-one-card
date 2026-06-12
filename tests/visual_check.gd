extends SceneTree
## Prueba visual end-to-end: simula un turno completo sobre la UI real y guarda
## screenshots en tests/. Correr (con ventana, no headless):
##   godot -s tests/visual_check.gd


func _initialize() -> void:
	# Campaña por defecto en memoria: capturas deterministas.
	LevelStore.campaign = LevelStore.default_campaign()
	LevelStore.test_level = -1
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(main: Control) -> void:
	await _frames(15)
	await _shot("01_inicio.png")

	# Fase de energía: tirar (con animación) y asignar dados.
	main._on_roll_pressed()
	await create_timer(0.9).timeout
	await _shot("02_dados.png")
	for pair in [[0, "speed"], [1, "attack"], [2, "defense"]]:
		main.selected_die = pair[0]
		main._on_stat_pressed(pair[1])
	await _frames(3)
	print("Fase: ", main.state.phase, " | Vel ", main.state.speed_points,
		" Atq ", main.state.attack_points, " Def ", main.state.defense_total)
	await _shot("03_fase_aventurero.png")

	# Mover a la celda alcanzable más cara (anima el camino).
	var reachable: Dictionary = main.state.player_reachable()
	if not reachable.is_empty():
		var cells: Array = reachable.keys()
		cells.sort_custom(func(a, b): return reachable[a] > reachable[b])
		main.board_clicked(cells[0])
		await create_timer(1.2).timeout
		print("Jugador movido a ", main.state.player_pos, " | Vel restante ", main.state.speed_points)

	# Intentar atacar a cada monstruo (los fallidos muestran motivo flotante).
	for m in main.state.monsters.duplicate():
		main.board_clicked(m.pos)
		await create_timer(0.5).timeout
	await _shot("04_tras_acciones.png")

	# Fase de monstruos completa (movimientos animados + ataques).
	main._end_player_phase()
	await create_timer(4.5).timeout
	print("Tras fase de monstruos: vida jugador ", main.state.health,
		" | fase ", main.state.phase)
	await _shot("05_nuevo_turno.png")

	# Pantalla de recompensa (forzada para verla).
	main.state.monsters.clear()
	main._on_level_cleared()
	await create_timer(0.5).timeout
	await _shot("06_recompensa.png")

	print("VISUAL OK")
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(file_name: String) -> void:
	# La ventana en segundo plano puede dejar de renderizar: traerla al frente
	# y esperar un draw real antes de capturar.
	DisplayServer.window_move_to_foreground()
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://tests/" + file_name)
	print("screenshot: ", file_name)
