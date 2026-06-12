extends SceneTree
## Chequeo del flujo recompensa -> nivel 2 -> victoria -> reinicio. Correr:
##   godot --headless -s tests/flow_check.gd

func _initialize() -> void:
	# Campaña por defecto en memoria: el chequeo no depende de user://campaign.json.
	LevelStore.campaign = LevelStore.default_campaign()
	LevelStore.test_level = -1
	var main: Control = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run(main)


func _run(main: Control) -> void:
	await process_frame
	var s: GameState = main.state

	# Fin de nivel 1: debe aparecer la pantalla de recompensa.
	s.monsters.clear()
	main._on_level_cleared()
	await process_frame
	assert(s.phase == GameState.Phase.REWARD, "fase REWARD")
	assert(main.reward_panel.visible, "panel de recompensa visible")

	# Elegir mejora de ataque: pasa a nivel 2 con +1 permanente.
	main._choose_reward("attack")
	await process_frame
	assert(s.base.attack == 2, "ataque base mejorado a 2")
	assert(s.level_index == 1, "nivel 2 cargado")
	assert(s.player_pos == Vector2i(4, 4), "jugador en fila 5, col 5")
	assert(s.monsters.size() == 2 and s.monsters[0].type == "skeleton_archer", "esqueletos cargados")
	assert(not main.reward_panel.visible, "panel de recompensa oculto")
	print("Nivel 2 OK: jugador ", s.player_pos, ", monstruos ", s.monsters.size(), ", ataque base ", s.base.attack)

	# Fin de nivel 2: victoria (no hay nivel 3).
	s.monsters.clear()
	main._on_level_cleared()
	await process_frame
	assert(s.phase == GameState.Phase.VICTORY, "fase VICTORY")
	assert(main.end_panel.visible, "panel final visible")

	# Reiniciar: vuelve al nivel 1 con stats base.
	main._restart()
	await process_frame
	assert(main.state.level_index == 0 and main.state.base.attack == 1, "reinicio limpio")
	print("FLOW OK")
	quit(0)
