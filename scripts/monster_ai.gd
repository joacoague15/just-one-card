class_name MonsterAI
## IA de movimiento de monstruos, según las prioridades del ticket:
## 1. Llegar a una celda desde donde pueda atacar al jugador.
## 2. Entre esas, preferir quedar exactamente a su alcance máximo.
## 3. Menor costo de movimiento desde la posición actual.
## 4. Celda más cercana al jugador.
## 5. Fila menor, luego columna menor.
## Si no puede atacar este turno, avanza hacia la celda más cercana desde donde
## eventualmente podría atacar; si tampoco existe, se acerca al jugador.


static func choose_destination(m: Dictionary, state: GameState) -> Vector2i:
	# Movimiento de monstruo: los obstáculos y el jugador bloquean el paso;
	# otros monstruos se atraviesan pero no se puede terminar sobre ellos.
	var blocked_move: Dictionary = state.obstacles.duplicate()
	blocked_move[state.player_pos] = true
	var costs: Dictionary = GridLogic.dijkstra(m.pos, blocked_move, state.grid_size)
	var occupied: Dictionary = state.monster_cells(m.id)

	var ends: Array = []
	for cell in costs:
		if costs[cell] <= m.speed and not occupied.has(cell):
			ends.append(cell)

	var attack_ends: Array = ends.filter(func(c): return state.monster_can_attack_from(m, c))
	if not attack_ends.is_empty():
		var exact: Array = attack_ends.filter(
			func(c): return state.monster_distance_to_player(c) == m.range)
		var pool: Array = exact if not exact.is_empty() else attack_ends
		return _pick(pool, [
			func(c): return costs[c],
			func(c): return state.monster_distance_to_player(c),
		])

	var goal := _nearest_eventual_attack_cell(m, state, costs)
	if goal != Vector2i(-1, -1):
		var from_goal: Dictionary = GridLogic.dijkstra(goal, blocked_move, state.grid_size)
		var candidates: Array = ends.filter(func(c): return from_goal.has(c))
		if not candidates.is_empty():
			return _pick(candidates, [
				func(c): return from_goal[c],
				func(c): return costs[c],
			])

	return _pick(ends, [
		func(c): return _dist_key(state.monster_distance_to_player(c)),
		func(c): return costs[c],
	])


## Celda alcanzable (en cualquier cantidad de turnos) desde donde el monstruo
## podría atacar, la más barata desde su posición actual. (-1,-1) si no hay.
static func _nearest_eventual_attack_cell(m: Dictionary, state: GameState, costs: Dictionary) -> Vector2i:
	var cells: Array = []
	for cell in GridLogic.all_cells(state.grid_size):
		if not costs.has(cell):
			continue
		if state.monster_can_attack_from(m, cell):
			cells.append(cell)
	if cells.is_empty():
		return Vector2i(-1, -1)
	return _pick(cells, [func(c): return costs[c]])


static func _dist_key(d: int) -> int:
	return 9999 if d < 0 else d


## Elige la celda con menor tupla de claves; desempata por fila menor y columna menor.
static func _pick(pool: Array, keys: Array) -> Vector2i:
	var best: Vector2i = pool[0]
	for cell in pool:
		if cell != best and _better(cell, best, keys):
			best = cell
	return best


static func _better(a: Vector2i, b: Vector2i, keys: Array) -> bool:
	for k in keys:
		var ka = k.call(a)
		var kb = k.call(b)
		if ka != kb:
			return ka < kb
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
