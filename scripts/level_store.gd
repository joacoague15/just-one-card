class_name LevelStore
## Campaña editable: lista ordenada de niveles + catálogo de tipos de monstruo.
## Persiste en user://campaign.json; la primera vez se siembra desde GameData.
##
## Formato runtime de un nivel:
##   {name: String, size: Vector2i, player_start: Vector2i,
##    obstacles: Array[Vector2i],
##    monsters: [{type: String, position: Vector2i, overrides: Dictionary}]}
## Tipo de monstruo: {name, health, speed, attack, defense, range, color: Color}

const SAVE_PATH := "user://campaign.json"
const MIN_DIM := 3
const MAX_DIM := 9

const DEFAULT_TYPE_COLORS := {"spider": "c5453a", "skeleton_archer": "ddd8c4"}
const NEW_TYPE_PALETTE := ["7bc96f", "e8a13d", "9b6fe8", "5cc8c8", "e86fa8", "c8b85c"]

static var campaign := {}
static var test_level := -1  # índice de nivel a probar desde el editor; -1 = campaña normal


static func ensure_loaded() -> void:
	if not campaign.is_empty():
		return
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and parsed.has("levels") and parsed.has("monster_types"):
			campaign = _campaign_from_json(parsed)
			return
	campaign = default_campaign()


static func levels() -> Array:
	ensure_loaded()
	return campaign.levels


static func monster_types() -> Dictionary:
	ensure_loaded()
	return campaign.monster_types


static func save() -> void:
	ensure_loaded()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_campaign_to_json(), "\t"))


static func type_color(type_id: String) -> Color:
	var types := monster_types()
	if types.has(type_id):
		return types[type_id].color
	return Color("c5453a")


static func type_letter(type_id: String) -> String:
	var types := monster_types()
	if types.has(type_id) and types[type_id].name.length() > 0:
		return types[type_id].name.substr(0, 1).to_upper()
	return "?"


static func next_palette_color() -> Color:
	return Color(NEW_TYPE_PALETTE[monster_types().size() % NEW_TYPE_PALETTE.size()])


## Campaña inicial: los 2 niveles y tipos del ticket (GameData).
static func default_campaign() -> Dictionary:
	var types := {}
	for id in GameData.MONSTER_TYPES:
		var t: Dictionary = GameData.MONSTER_TYPES[id].duplicate()
		t["color"] = Color(DEFAULT_TYPE_COLORS.get(id, "c5453a"))
		types[id] = t
	var lvls := []
	for data in GameData.levels():
		var monsters := []
		for md in data.monsters:
			monsters.append({"type": md.type, "position": md.position, "overrides": {}})
		lvls.append({
			"name": "Nivel %d" % data.level,
			"size": Vector2i(5, 5),
			"player_start": data.player_start,
			"obstacles": data.obstacles.duplicate(),
			"monsters": monsters,
		})
	return {"levels": lvls, "monster_types": types}


static func blank_level() -> Dictionary:
	return {
		"name": "Nivel nuevo",
		"size": Vector2i(5, 5),
		"player_start": Vector2i(0, 4),
		"obstacles": [],
		"monsters": [],
	}


## Stats efectivos de un monstruo colocado (tipo + overrides).
static func effective_stats(monster: Dictionary) -> Dictionary:
	var t: Dictionary = monster_types()[monster.type]
	var stats := {
		"name": t.name,
		"health": t.health,
		"speed": t.speed,
		"attack": t.attack,
		"defense": t.defense,
		"range": t.range,
	}
	for k in monster.get("overrides", {}):
		stats[k] = monster.overrides[k]
	return stats


## Advertencias de jugabilidad (no bloquean el guardado).
static func validate_level(level: Dictionary) -> Array:
	var warnings := []
	var size: Vector2i = level.size
	var obstacles := {}
	for o in level.obstacles:
		obstacles[o] = true
	if level.monsters.is_empty():
		warnings.append("El nivel no tiene enemigos: se completaría solo.")
	if obstacles.has(level.player_start):
		warnings.append("El jugador está sobre un obstáculo.")
	var seen := {}
	for m in level.monsters:
		if m.position == level.player_start:
			warnings.append("Un enemigo está sobre el jugador.")
		if obstacles.has(m.position):
			warnings.append("Un enemigo está sobre un obstáculo.")
		if seen.has(m.position):
			warnings.append("Hay enemigos superpuestos en %s." % str(m.position))
		seen[m.position] = true
	# Alcanzabilidad: con solo los obstáculos como bloqueo, cada enemigo
	# debería tener distancia finita al jugador.
	var dist := GridLogic.dijkstra(level.player_start, obstacles, size)
	for m in level.monsters:
		if not dist.has(m.position):
			var stats := effective_stats(m)
			warnings.append("%s en %s parece inalcanzable (encerrado por obstáculos)." % [
				stats.name, _cell_name(m.position)])
	return warnings


static func _cell_name(cell: Vector2i) -> String:
	return "fila %d, col %d" % [cell.y + 1, cell.x + 1]


# --- Conversión JSON (Vector2i <-> [x, y], Color <-> html) ---

static func _campaign_to_json() -> Dictionary:
	var types := {}
	for id in campaign.monster_types:
		var t: Dictionary = campaign.monster_types[id]
		types[id] = {
			"name": t.name, "health": t.health, "speed": t.speed,
			"attack": t.attack, "defense": t.defense, "range": t.range,
			"color": t.color.to_html(false),
		}
	var lvls := []
	for level in campaign.levels:
		var monsters := []
		for m in level.monsters:
			monsters.append({
				"type": m.type,
				"position": [m.position.x, m.position.y],
				"overrides": m.get("overrides", {}),
			})
		lvls.append({
			"name": level.name,
			"size": [level.size.x, level.size.y],
			"player_start": [level.player_start.x, level.player_start.y],
			"obstacles": level.obstacles.map(func(o): return [o.x, o.y]),
			"monsters": monsters,
		})
	return {"levels": lvls, "monster_types": types}


static func _campaign_from_json(data: Dictionary) -> Dictionary:
	var types := {}
	for id in data.monster_types:
		var t: Dictionary = data.monster_types[id]
		types[id] = {
			"name": str(t.name), "health": int(t.health), "speed": int(t.speed),
			"attack": int(t.attack), "defense": int(t.defense), "range": int(t.range),
			"color": Color(str(t.get("color", "c5453a"))),
		}
	var lvls := []
	for level in data.levels:
		var monsters := []
		for m in level.monsters:
			var overrides := {}
			for k in m.get("overrides", {}):
				overrides[k] = int(m.overrides[k])
			monsters.append({"type": str(m.type), "position": _vec(m.position), "overrides": overrides})
		lvls.append({
			"name": str(level.name),
			"size": _vec(level.size),
			"player_start": _vec(level.player_start),
			"obstacles": level.obstacles.map(func(o): return _vec(o)),
			"monsters": monsters,
		})
	return {"levels": lvls, "monster_types": types}


static func _vec(arr) -> Vector2i:
	return Vector2i(int(arr[0]), int(arr[1]))
