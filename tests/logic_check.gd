extends SceneTree
## Chequeos de la lógica central, sin UI. Correr desde la raíz del proyecto:
##   godot --headless --import
##   godot --headless -s tests/logic_check.gd

const S5 := Vector2i(5, 5)

var failures := 0


func _initialize() -> void:
	# Campaña por defecto en memoria: los chequeos no dependen de user://campaign.json.
	LevelStore.campaign = LevelStore.default_campaign()
	_check_movement_costs()
	_check_attack_distance()
	_check_line_of_sight()
	_check_damage_formula()
	_check_level_setup()
	_check_player_rules()
	_check_monster_ai()
	_check_level_store()
	_check_main_script_compiles()
	if failures == 0:
		print("OK: todos los chequeos pasaron")
		quit(0)
	else:
		print("FALLARON %d chequeos" % failures)
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FALLO: " + msg)


func _check_movement_costs() -> void:
	var d := GridLogic.dijkstra(Vector2i(0, 0), {}, S5)
	_expect(d[Vector2i(1, 0)] == 2, "ortogonal cuesta 2")
	_expect(d[Vector2i(1, 1)] == 3, "diagonal cuesta 3")
	_expect(d[Vector2i(2, 2)] == 6, "dos diagonales cuestan 6")
	_expect(d[Vector2i(4, 0)] == 8, "cuatro ortogonales cuestan 8")
	var blocked := {Vector2i(1, 0): true, Vector2i(0, 1): true, Vector2i(1, 1): true}
	var d2 := GridLogic.dijkstra(Vector2i(0, 0), blocked, S5)
	_expect(not d2.has(Vector2i(2, 0)), "el movimiento no atraviesa bloqueos")
	# Grilla rectangular: una celda fuera del alto no existe.
	var d3 := GridLogic.dijkstra(Vector2i(0, 0), {}, Vector2i(7, 3))
	_expect(d3.has(Vector2i(6, 2)) and not d3.has(Vector2i(0, 3)),
		"la grilla rectangular respeta ancho y alto")


func _check_attack_distance() -> void:
	# Alcance 2: ataca ortogonal adyacente, no diagonal adyacente (cuesta 3).
	_expect(GridLogic.attack_distance(Vector2i(0, 0), Vector2i(1, 0), {}, S5) == 2,
		"distancia ortogonal adyacente es 2")
	_expect(GridLogic.attack_distance(Vector2i(0, 0), Vector2i(1, 1), {}, S5) == 3,
		"distancia diagonal adyacente es 3")
	# La celda del objetivo se ignora como bloqueo.
	_expect(GridLogic.attack_distance(Vector2i(0, 0), Vector2i(1, 0), {Vector2i(1, 0): true}, S5) == 2,
		"el objetivo no bloquea su propia celda para la distancia")


func _check_line_of_sight() -> void:
	_expect(GridLogic.has_line_of_sight(Vector2i(0, 0), Vector2i(2, 0), {}),
		"sin bloqueos hay visión")
	_expect(not GridLogic.has_line_of_sight(Vector2i(0, 0), Vector2i(2, 0), {Vector2i(1, 0): true}),
		"celda intermedia ortogonal bloquea visión")
	_expect(not GridLogic.has_line_of_sight(Vector2i(0, 0), Vector2i(2, 2), {Vector2i(1, 1): true}),
		"celda intermedia diagonal bloquea visión")
	_expect(GridLogic.has_line_of_sight(Vector2i(0, 0), Vector2i(2, 2), {Vector2i(1, 0): true}),
		"rozar una esquina no bloquea visión")
	_expect(GridLogic.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 0), {Vector2i(1, 0): true}),
		"el objetivo no bloquea su propia visión")


func _check_damage_formula() -> void:
	_expect(floori(12.0 / 7.0) == 1, "floor(12/7) = 1")
	_expect(floori(12.0 / 4.0) == 3, "floor(12/4) = 3")
	_expect(floori(8.0 / 3.0) == 2, "floor(8/3) = 2")
	_expect(floori(3.0 / 4.0) == 0, "ataque menor que defensa hace 0 daño")


func _check_level_setup() -> void:
	var s := GameState.new()
	s.start_level(0)
	_expect(s.player_pos == Vector2i(0, 4), "nivel 1: jugador en fila 5, col 1")
	_expect(s.monsters.size() == 2, "nivel 1: 2 arañas")
	_expect(s.monsters[0].pos == Vector2i(3, 0), "araña 1 en fila 1, col 4")
	_expect(s.monsters[1].pos == Vector2i(4, 2), "araña 2 en fila 3, col 5")
	_expect(s.obstacles.has(Vector2i(3, 1)) and s.obstacles.has(Vector2i(1, 3)) and s.obstacles.has(Vector2i(3, 3)),
		"nivel 1: obstáculos correctos")
	_expect(s.health == 6 and s.base.speed == 1 and s.base.attack == 1
		and s.base.defense == 1 and s.base.range == 2, "stats iniciales del jugador")
	s.start_level(1)
	_expect(s.player_pos == Vector2i(4, 4), "nivel 2: jugador en fila 5, col 5")
	_expect(s.monsters[0].pos == Vector2i(2, 0) and s.monsters[1].pos == Vector2i(0, 1),
		"nivel 2: esqueletos en posición")
	_expect(s.obstacles.has(Vector2i(0, 2)) and s.obstacles.has(Vector2i(3, 2)) and s.obstacles.has(Vector2i(3, 3)),
		"nivel 2: obstáculos correctos")


func _check_player_rules() -> void:
	var s := GameState.new()
	s.start_level(0)
	s.dice = [6, 3, 2]
	s.dice_rolled = true
	s.assign_die("speed", 0)
	s.assign_die("attack", 1)
	s.assign_die("defense", 2)
	_expect(s.phase == GameState.Phase.PLAYER, "con 3 dados asignados empieza la fase del aventurero")
	_expect(s.speed_points == 7 and s.attack_points == 4 and s.defense_total == 3,
		"totales del turno: 1+6, 1+3, 1+2")

	var reachable := s.player_reachable()
	_expect(reachable[Vector2i(1, 4)] == 2, "mover una ortogonal cuesta 2")
	_expect(not reachable.has(Vector2i(1, 3)), "no puede entrar a un obstáculo")
	_expect(s.try_move_player(Vector2i(2, 3)), "mover ortogonal+diagonal (costo 5)")
	_expect(s.speed_points == 2, "se descuentan los puntos de velocidad")

	# Ataque: araña 2 en (4,2), jugador en (2,3): distancia 5 > alcance 2.
	var spider2: Dictionary = s.monster_at(Vector2i(4, 2))
	var info := s.player_attack_info(spider2)
	_expect(not info.in_range, "alcance 2 no llega a distancia 3")
	# Acercamos al jugador de forma sintética: ortogonal adyacente.
	s.player_pos = Vector2i(4, 3)
	info = s.player_attack_info(spider2)
	_expect(info.in_range and info.los and info.cost == 4, "araña adyacente ortogonal atacable, costo = defensa 4")
	_expect(info.hits_affordable == 1, "con 4 puntos y defensa 4 alcanza floor(4/4) = 1 golpe")
	_expect(s.player_attack(spider2), "primer golpe exitoso")
	_expect(spider2.hp == 1 and s.attack_points == 0, "1 daño y se descuenta el costo")
	info = s.player_attack_info(spider2)
	_expect(not info.can_attack and not info.enough_points, "sin puntos no se puede seguir golpeando")
	# Con 8 puntos se puede golpear dos veces al mismo monstruo: floor(8/4) = 2.
	s.attack_points = 8
	_expect(s.player_attack_info(spider2).hits_affordable == 2, "floor(8/4) = 2 golpes pagables")
	_expect(s.player_attack(spider2), "segundo golpe al mismo monstruo permitido")
	_expect(not s.monsters.has(spider2) and s.attack_points == 4,
		"la araña muere con el segundo golpe y quedan 8-4 = 4 puntos")


func _make_monster(id: int, pos: Vector2i, speed: int, atk: int, def: int, rng: int) -> Dictionary:
	return {"id": id, "type": "spider", "name": "Test", "hp": 2, "max_hp": 2,
		"speed": speed, "attack": atk, "defense": def, "range": rng, "pos": pos}


func _check_monster_ai() -> void:
	var s := GameState.new()
	s.start_level(0)
	s.obstacles = {}
	s.player_pos = Vector2i(0, 0)

	# Caso 1: puede atacar y prefiere quedar exactamente a alcance máximo.
	# Monstruo en (0,2), velocidad 5, alcance 3: (1,1) queda a distancia 3 exacta.
	s.monsters = [_make_monster(1, Vector2i(0, 2), 5, 4, 4, 3)]
	var dest := MonsterAI.choose_destination(s.monsters[0], s)
	_expect(dest == Vector2i(1, 1), "IA: prefiere alcance máximo exacto (esperaba (1,1), dio %s)" % str(dest))

	# Caso 2: no llega a atacar este turno; avanza hacia la celda de ataque más cercana.
	# Monstruo en (0,4): la celda de ataque más barata es (0,1) (costo 6); avanza a (0,2).
	s.monsters = [_make_monster(2, Vector2i(0, 4), 5, 4, 4, 3)]
	dest = MonsterAI.choose_destination(s.monsters[0], s)
	_expect(dest == Vector2i(0, 2), "IA: avanza hacia celda de ataque futura (esperaba (0,2), dio %s)" % str(dest))

	# Caso 3: atraviesa otros monstruos pero no termina sobre ellos.
	# Pasillo en columna 0 (obstáculos en columna 1, filas 1-4). El de adelante ya
	# está a alcance exacto y se queda; el de atrás solo puede atacar desde (1,0),
	# y para llegar debe atravesar al de adelante en (0,1).
	s.player_pos = Vector2i(0, 0)
	s.obstacles = {Vector2i(1, 1): true, Vector2i(1, 2): true,
		Vector2i(1, 3): true, Vector2i(1, 4): true}
	s.monsters = [
		_make_monster(3, Vector2i(0, 1), 4, 4, 4, 2),
		_make_monster(4, Vector2i(0, 2), 5, 4, 4, 2),
	]
	var front: Dictionary = s.monsters[0]
	var back: Dictionary = s.monsters[1]
	var front_dest := MonsterAI.choose_destination(front, s)
	_expect(front_dest == Vector2i(0, 1), "IA: ya está a alcance exacto, se queda (esperaba (0,1), dio %s)" % str(front_dest))
	var back_dest := MonsterAI.choose_destination(back, s)
	_expect(back_dest != front.pos and back_dest != s.player_pos,
		"IA: no termina sobre otro monstruo ni sobre el jugador")
	_expect(back_dest == Vector2i(1, 0), "IA: atraviesa al otro monstruo para atacar (esperaba (1,0), dio %s)" % str(back_dest))

	# Orden de turno: más cercano primero.
	s.obstacles = {}
	s.monsters = [
		_make_monster(5, Vector2i(4, 4), 4, 4, 4, 2),
		_make_monster(6, Vector2i(0, 2), 4, 4, 4, 2),
	]
	var order := s.monster_turn_order()
	_expect(order[0].id == 6, "el monstruo más cercano se mueve primero")

	# Suma de ataques de monstruos.
	s.monsters = [
		_make_monster(7, Vector2i(0, 1), 4, 4, 4, 2),
		_make_monster(8, Vector2i(1, 0), 4, 5, 4, 2),
		_make_monster(9, Vector2i(4, 4), 4, 9, 4, 2),  # lejos: no ataca
	]
	var attackers := s.monsters_attacking()
	var total := 0
	for m in attackers:
		total += m.attack
	_expect(attackers.size() == 2 and total == 9, "solo suman los monstruos con alcance y visión")


func _check_level_store() -> void:
	var camp := LevelStore.default_campaign()
	_expect(camp.levels.size() == 2 and camp.monster_types.size() == 2,
		"la campaña por defecto trae 2 niveles y 2 tipos")
	_expect(LevelStore.validate_level(camp.levels[0]).is_empty(),
		"el nivel 1 por defecto no tiene advertencias")

	# Overrides por instancia pisan los stats del tipo.
	var m := {"type": "spider", "position": Vector2i(0, 0), "overrides": {"health": 5}}
	var stats := LevelStore.effective_stats(m)
	_expect(stats.health == 5 and stats.attack == 4, "los ajustes pisan solo el stat indicado")

	# Validación: nivel roto (sin enemigos + jugador sobre obstáculo).
	var bad := LevelStore.blank_level()
	bad.obstacles = [bad.player_start]
	var warnings := LevelStore.validate_level(bad)
	_expect(warnings.size() >= 2, "nivel roto genera advertencias (sin enemigos + jugador en obstáculo)")

	# Validación: enemigo encerrado por obstáculos es advertido como inalcanzable.
	var walled := LevelStore.blank_level()
	walled.player_start = Vector2i(0, 0)
	walled.obstacles = [Vector2i(3, 0), Vector2i(3, 1), Vector2i(4, 1)]
	walled.monsters = [{"type": "spider", "position": Vector2i(4, 0), "overrides": {}}]
	var walled_warnings := LevelStore.validate_level(walled)
	var found := false
	for w in walled_warnings:
		if "inalcanzable" in w:
			found = true
	_expect(found, "enemigo encerrado genera advertencia de inalcanzable")


func _check_main_script_compiles() -> void:
	var script = load("res://scripts/main.gd")
	_expect(script != null and script.can_instantiate(), "main.gd compila")
