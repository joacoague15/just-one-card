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
	_check_reroll_power()
	_check_undo()
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
	# Daño por división: cuántos bloques completos de la defensa entran en el ataque.
	_expect(floori(7.0 / 3.0) == 2, "ataque 7 contra defensa 3 = 2 bloques = 2 de daño")
	_expect(floori(12.0 / 4.0) == 3, "ataque 12 contra defensa 4 = 3 de daño")
	_expect(floori(4.0 / 4.0) == 1, "ataque igual a la defensa = 1 bloque = 1 de daño")
	_expect(floori(3.0 / 4.0) == 0, "ataque menor que la defensa = 0 de daño")


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

	# Ataque por división: araña 2 en (4,2), jugador en (2,3): distancia > alcance 2.
	var spider2: Dictionary = s.monster_at(Vector2i(4, 2))
	var info := s.player_attack_info(spider2)
	_expect(not info.in_range, "alcance 2 no llega a distancia 3")
	# Acercamos al jugador de forma sintética: ortogonal adyacente.
	s.player_pos = Vector2i(4, 3)
	# attack_points = 4 (1 + dado 3), defensa 4 → floor(4/4) = 1 bloque = 1 de daño.
	info = s.player_attack_info(spider2)
	_expect(info.in_range and info.los and info.damage == 1,
		"ataque 4 contra defensa 4 = 1 bloque = 1 de daño")
	_expect(info.can_attack, "se puede atacar si hay al menos un bloque completo")
	_expect(s.player_attack(spider2), "ataque exitoso")
	_expect(spider2.hp == 1 and s.has_attacked, "1 de daño y el ataque se consume (una vez por turno)")

	# Ataque que no completa ni un bloque: 3 contra defensa 4 = 0 de daño.
	s.has_attacked = false
	s.attack_points = 3
	info = s.player_attack_info(spider2)
	_expect(info.damage == 0 and not info.can_attack, "ataque 3 contra defensa 4 = 0 de daño, no atacable")

	# Un ataque por turno: tras atacar, has_attacked bloquea más ataques.
	s.attack_points = 8  # floor(8/4) = 2 → remata a la araña (le quedaba 1 PV)
	_expect(s.player_attack(spider2) and not s.monsters.has(spider2),
		"ataque 8 contra defensa 4 = 2 de daño y la araña muere")
	var spider1: Dictionary = s.monster_at(Vector2i(3, 0))
	s.player_pos = Vector2i(4, 0)  # ortogonal adyacente a la araña 1
	s.attack_points = 9
	info = s.player_attack_info(spider1)
	_expect(info.already_attacked and not info.can_attack, "ya atacaste: no se puede volver a atacar")
	_expect(not s.player_attack(spider1), "player_attack falla si ya atacaste este turno")
	# El turno siguiente vuelve a tirar/asignar y rehabilita el ataque.
	s.new_turn()
	_expect(s.phase == GameState.Phase.ASSIGN_DICE and not s.has_attacked,
		"new_turn reinicia la fase de energía y rehabilita el ataque")
	s.dice = [6, 3, 2]; s.dice_rolled = true
	s.assign_die("speed", 0); s.assign_die("attack", 1); s.assign_die("defense", 2)
	_expect(s.phase == GameState.Phase.PLAYER, "al reasignar los dados arranca de nuevo la fase del aventurero")
	s.attack_points = 6
	info = s.player_attack_info(spider1)
	_expect(info.can_attack and info.damage == 1, "en el nuevo turno se puede atacar (floor(6/4) = 1)")


func _check_reroll_power() -> void:
	var s := GameState.new()
	s.start_level(0)
	_expect(s.reroll_available, "el poder de re-roll arranca disponible en cada nivel")
	s.new_turn()
	s.roll_dice()
	_expect(s.phase == GameState.Phase.ASSIGN_DICE, "tras new_turn estamos en la fase de energía")
	s.assign_die("speed", 0)
	_expect(s.reroll_dice(), "se puede usar el poder de re-roll una vez")
	_expect(s.assignment.is_empty(), "el re-roll limpia la asignación en curso")
	_expect(not s.reroll_available, "el poder se consume al usarlo")
	_expect(not s.reroll_dice(), "no se puede re-rollear dos veces en el mismo nivel")
	# Fuera de la fase de energía el poder no se puede usar.
	s.start_level(1)
	_expect(s.reroll_available, "al empezar otro nivel el poder vuelve a estar disponible")
	s.new_turn()
	s.roll_dice()
	s.assign_die("speed", 0)
	s.assign_die("attack", 1)
	s.assign_die("defense", 2)
	_expect(s.phase == GameState.Phase.PLAYER and not s.reroll_dice(),
		"en la fase del aventurero (dados ya asignados) no se puede re-rollear")


func _check_undo() -> void:
	var s := GameState.new()
	s.start_level(0)
	s.dice = [6, 3, 2]; s.dice_rolled = true
	s.assign_die("speed", 0); s.assign_die("attack", 1); s.assign_die("defense", 2)
	_expect(not s.can_undo(), "al empezar el turno no hay nada que deshacer")

	# Mover y deshacer: vuelven posición y puntos de velocidad.
	var start_pos := s.player_pos
	var start_speed := s.speed_points
	_expect(s.try_move_player(Vector2i(1, 4)), "mover una ortogonal")
	_expect(s.can_undo() and s.player_pos == Vector2i(1, 4) and s.speed_points == start_speed - 2,
		"tras mover hay algo que deshacer y se gastaron puntos")
	_expect(s.undo(), "deshacer el movimiento")
	_expect(s.player_pos == start_pos and s.speed_points == start_speed, "el movimiento se revierte")
	_expect(not s.can_undo(), "ya no queda nada que deshacer")

	# Atacar y deshacer: vuelven la vida del monstruo y el ataque del turno.
	s.player_pos = Vector2i(4, 3)  # adyacente a la araña 2 en (4,2)
	s.attack_points = 8  # floor(8/4) = 2 de daño → mata a la araña (2 PV)
	var spider2: Dictionary = s.monster_at(Vector2i(4, 2))
	var hp0: int = spider2.hp
	_expect(s.player_attack(spider2), "atacar a la araña")
	_expect(s.has_attacked and s.monster_at(Vector2i(4, 2)).is_empty(),
		"el ataque mata a la araña (2 de daño) y marca el ataque usado")
	_expect(s.undo(), "deshacer el ataque")
	var restored: Dictionary = s.monster_at(Vector2i(4, 2))
	_expect(not restored.is_empty() and restored.hp == hp0 and not s.has_attacked,
		"el ataque se revierte: la araña vuelve con su vida y el ataque queda disponible")

	# Un turno nuevo descarta el undo aunque haya acciones pendientes.
	s.try_move_player(Vector2i(4, 4))
	_expect(s.can_undo(), "hay una acción para deshacer")
	s.new_turn()
	_expect(not s.can_undo(), "un turno nuevo descarta el undo")


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
