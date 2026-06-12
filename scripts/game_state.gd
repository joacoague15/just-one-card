class_name GameState
extends RefCounted
## Estado y reglas del juego, sin UI.

enum Phase { ASSIGN_DICE, PLAYER, MONSTERS, REWARD, GAME_OVER, VICTORY }

const STATS := ["speed", "attack", "defense"]

var phase := Phase.ASSIGN_DICE
var level_index := 0
var grid_size := Vector2i(5, 5)

var player_pos := Vector2i.ZERO
var max_health: int = GameData.PLAYER_BASE.max_health
var health: int = GameData.PLAYER_BASE.max_health
var base := {
	"speed": GameData.PLAYER_BASE.speed,
	"attack": GameData.PLAYER_BASE.attack,
	"defense": GameData.PLAYER_BASE.defense,
	"range": GameData.PLAYER_BASE.range,
}

var obstacles := {}  # set de Vector2i
var monsters: Array = []  # dicts: id, type, name, hp, max_hp, speed, attack, defense, range, pos
var _next_id := 1

var dice: Array = [0, 0, 0]
var dice_rolled := false
var assignment := {}  # stat -> índice de dado
var speed_points := 0
var attack_points := 0
var defense_total := 0


func start_level(index: int) -> void:
	level_index = index
	var data: Dictionary = LevelStore.levels()[index]
	grid_size = data.size
	player_pos = data.player_start
	obstacles = {}
	for o in data.obstacles:
		obstacles[o] = true
	monsters = []
	var ordinal := 0
	for md in data.monsters:
		ordinal += 1
		var t := LevelStore.effective_stats(md)
		monsters.append({
			"id": _next_id,
			"type": md.type,
			"name": "%s %d" % [t.name, ordinal],
			"hp": t.health,
			"max_hp": t.health,
			"speed": t.speed,
			"attack": t.attack,
			"defense": t.defense,
			"range": t.range,
			"pos": md.position,
		})
		_next_id += 1


# --- Fase de energía ---

func new_turn() -> void:
	dice = [0, 0, 0]
	dice_rolled = false
	assignment = {}
	speed_points = 0
	attack_points = 0
	defense_total = 0
	phase = Phase.ASSIGN_DICE


func roll_dice() -> void:
	for i in 3:
		dice[i] = randi_range(1, 6)
	dice_rolled = true


## Asigna un dado a una habilidad. Si el dado estaba en otra habilidad, se mueve.
## Cuando los tres dados están asignados, comienza la fase del aventurero.
func assign_die(stat: String, die_index: int) -> void:
	for s in assignment.keys():
		if assignment[s] == die_index:
			assignment.erase(s)
	assignment[stat] = die_index
	if assignment.size() == 3:
		_begin_player_phase()


func unassign(stat: String) -> void:
	assignment.erase(stat)


func _begin_player_phase() -> void:
	speed_points = base.speed + dice[assignment.speed]
	attack_points = base.attack + dice[assignment.attack]
	defense_total = base.defense + dice[assignment.defense]
	phase = Phase.PLAYER


# --- Consultas de tablero ---

func monster_at(cell: Vector2i) -> Dictionary:
	for m in monsters:
		if m.pos == cell:
			return m
	return {}


func monster_cells(exclude_id: int = -1) -> Dictionary:
	var cells := {}
	for m in monsters:
		if m.id != exclude_id:
			cells[m.pos] = true
	return cells


# --- Movimiento del jugador ---

## Celdas a las que el jugador puede moverse este turno (celda -> costo).
func player_reachable() -> Dictionary:
	var blocked := obstacles.duplicate()
	blocked.merge(monster_cells())
	var costs := GridLogic.dijkstra(player_pos, blocked, grid_size)
	var result := {}
	for cell in costs:
		if cell != player_pos and costs[cell] <= speed_points:
			result[cell] = costs[cell]
	return result


func try_move_player(cell: Vector2i) -> bool:
	var reachable := player_reachable()
	if not reachable.has(cell):
		return false
	speed_points -= reachable[cell]
	player_pos = cell
	return true


# --- Ataque del jugador ---
# Cada golpe cuesta la defensa del monstruo y hace 1 de daño. Se puede golpear
# al mismo monstruo varias veces por turno mientras alcancen los puntos:
# floor(ataque / defensa) es la cantidad de golpes que el turno permite pagar.

func player_attack_info(m: Dictionary) -> Dictionary:
	# Para distancia y visión, los demás monstruos bloquean; el objetivo no.
	var blockers := obstacles.duplicate()
	blockers.merge(monster_cells(m.id))
	var dist := GridLogic.attack_distance(player_pos, m.pos, blockers, grid_size)
	var in_range: bool = dist >= 0 and dist <= base.range
	var los := GridLogic.has_line_of_sight(player_pos, m.pos, blockers)
	var cost: int = m.defense
	return {
		"dist": dist,
		"in_range": in_range,
		"los": los,
		"cost": cost,
		"hits_affordable": int(float(attack_points) / float(cost)),
		"enough_points": attack_points >= cost,
		"can_attack": in_range and los and attack_points >= cost,
	}


func player_attack(m: Dictionary) -> bool:
	var info := player_attack_info(m)
	if not info.can_attack:
		return false
	attack_points -= info.cost
	m.hp -= 1
	if m.hp <= 0:
		monsters.erase(m)
	return true


# --- Monstruos ---

## Distancia por costo de movimiento desde una celda hasta el jugador,
## con reglas de monstruo: atraviesa monstruos, no obstáculos.
func monster_distance_to_player(from: Vector2i) -> int:
	return GridLogic.attack_distance(from, player_pos, obstacles, grid_size)


## ¿Podría el monstruo m atacar al jugador parado en `from`?
func monster_can_attack_from(m: Dictionary, from: Vector2i) -> bool:
	var d := monster_distance_to_player(from)
	if d < 0 or d > m.range:
		return false
	var blockers := obstacles.duplicate()
	blockers.merge(monster_cells(m.id))
	return GridLogic.has_line_of_sight(from, player_pos, blockers)


## Orden de actuación: el más cercano al jugador primero; empate por fila y columna menor.
func monster_turn_order() -> Array:
	var order := monsters.duplicate()
	order.sort_custom(func(a, b):
		var da: int = monster_distance_to_player(a.pos)
		var db: int = monster_distance_to_player(b.pos)
		if da != db:
			if da < 0:
				return false
			if db < 0:
				return true
			return da < db
		if a.pos.y != b.pos.y:
			return a.pos.y < b.pos.y
		return a.pos.x < b.pos.x
	)
	return order


## Monstruos que pueden atacar al jugador desde su posición actual.
func monsters_attacking() -> Array:
	var result := []
	for m in monsters:
		if monster_can_attack_from(m, m.pos):
			result.append(m)
	return result
