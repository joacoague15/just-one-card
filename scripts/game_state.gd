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
var has_attacked := false  # el aventurero ataca una vez por turno
var reroll_available := true  # poder: re-rollear los dados una vez por nivel
var _undo_stack: Array = []  # snapshots para deshacer acciones del turno actual


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
	reroll_available = true  # el poder de re-roll se renueva en cada nivel
	_undo_stack.clear()


# --- Fase de energía (cada turno) ---

## Inicio de cada turno: se vuelven a tirar y asignar los dados.
func new_turn() -> void:
	dice = [0, 0, 0]
	dice_rolled = false
	assignment = {}
	has_attacked = false
	speed_points = 0
	attack_points = 0
	defense_total = 0
	_undo_stack.clear()  # el undo no cruza de un turno a otro
	phase = Phase.ASSIGN_DICE


func roll_dice() -> void:
	for i in 3:
		dice[i] = randi_range(1, 6)
	dice_rolled = true


## Poder (una vez por nivel): vuelve a tirar los tres dados. Limpia la asignación
## en curso para reasignar los valores nuevos. Devuelve false si ya se usó o si no
## estamos en la fase de energía.
func reroll_dice() -> bool:
	if not reroll_available or phase != Phase.ASSIGN_DICE:
		return false
	reroll_available = false
	assignment = {}
	roll_dice()
	return true


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


## Calcula los puntos del turno a partir de los dados asignados y arranca la
## fase del aventurero (con su ataque disponible).
func _begin_player_phase() -> void:
	speed_points = base.speed + dice[assignment.speed]
	attack_points = base.attack + dice[assignment.attack]
	defense_total = base.defense + dice[assignment.defense]
	has_attacked = false
	_undo_stack.clear()  # el undo solo abarca las acciones de este turno
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
	_push_undo()
	speed_points -= reachable[cell]
	player_pos = cell
	return true


# --- Ataque del jugador ---
# Un ataque por turno a un objetivo, resuelto por división: el daño es la
# cantidad de "bloques" completos de la defensa que entran en el ataque,
# floor(ataque / defensa). Si el ataque no llega ni a un bloque, no hay daño.

func player_attack_info(m: Dictionary) -> Dictionary:
	# Para distancia y visión, los demás monstruos bloquean; el objetivo no.
	var blockers := obstacles.duplicate()
	blockers.merge(monster_cells(m.id))
	var dist := GridLogic.attack_distance(player_pos, m.pos, blockers, grid_size)
	var in_range: bool = dist >= 0 and dist <= base.range
	var los := GridLogic.has_line_of_sight(player_pos, m.pos, blockers)
	var damage: int = floori(float(attack_points) / float(m.defense))
	return {
		"dist": dist,
		"in_range": in_range,
		"los": los,
		"damage": damage,
		"already_attacked": has_attacked,
		"can_attack": in_range and los and not has_attacked and damage > 0,
	}


func player_attack(m: Dictionary) -> bool:
	var info := player_attack_info(m)
	if not info.can_attack:
		return false
	_push_undo()
	has_attacked = true
	m.hp -= info.damage
	if m.hp <= 0:
		monsters.erase(m)
	return true


# --- Deshacer (solo durante la fase del aventurero) ---

## Captura el estado reversible antes de una acción del jugador.
func _push_undo() -> void:
	var mon := []
	for m in monsters:
		mon.append(m.duplicate())
	_undo_stack.append({
		"player_pos": player_pos,
		"speed_points": speed_points,
		"attack_points": attack_points,
		"has_attacked": has_attacked,
		"health": health,
		"monsters": mon,
	})


func can_undo() -> bool:
	return not _undo_stack.is_empty()


## Revierte la última acción del turno (mover o atacar). Devuelve false si no hay
## nada que deshacer.
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var snap: Dictionary = _undo_stack.pop_back()
	player_pos = snap.player_pos
	speed_points = snap.speed_points
	attack_points = snap.attack_points
	has_attacked = snap.has_attacked
	health = snap.health
	monsters = snap.monsters
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


# --- Telegrafiado ---

## Simula la fase de monstruos SIN ejecutarla, para mostrar su intención durante
## el turno del jugador. Respeta el orden real y que los monstruos se mueven en
## secuencia (cada uno ve dónde quedaron los anteriores). Devuelve:
##   {moves: {id -> celda}, attackers: [id], total_attack: int, predicted_damage: int}
## Mueve posiciones de forma temporal y las restaura antes de retornar.
func predict_monster_phase() -> Dictionary:
	var original := {}
	for m in monsters:
		original[m.id] = m.pos
	var moves := {}
	for m in monster_turn_order():
		var dest: Vector2i = MonsterAI.choose_destination(m, self)
		m.pos = dest
		moves[m.id] = dest
	var attackers := []
	var total := 0
	for m in monsters:
		if monster_can_attack_from(m, m.pos):
			attackers.append(m.id)
			total += m.attack
	for m in monsters:
		m.pos = original[m.id]
	return {
		"moves": moves,
		"attackers": attackers,
		"total_attack": total,
		"predicted_damage": floori(float(total) / float(defense_total)) if defense_total > 0 else 0,
	}
