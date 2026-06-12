class_name GridLogic
## Lógica pura de grilla: costos de movimiento (Dijkstra) y línea de visión.
## Las dimensiones de la grilla se pasan por parámetro (ancho x alto en celdas).

const ORTHO_COST := 2
const DIAG_COST := 3


static func in_bounds(c: Vector2i, size: Vector2i) -> bool:
	return c.x >= 0 and c.x < size.x and c.y >= 0 and c.y < size.y


static func all_cells(size: Vector2i) -> Array:
	var cells := []
	for y in size.y:
		for x in size.x:
			cells.append(Vector2i(x, y))
	return cells


static func _steps() -> Array:
	return [
		[Vector2i(1, 0), ORTHO_COST], [Vector2i(-1, 0), ORTHO_COST],
		[Vector2i(0, 1), ORTHO_COST], [Vector2i(0, -1), ORTHO_COST],
		[Vector2i(1, 1), DIAG_COST], [Vector2i(1, -1), DIAG_COST],
		[Vector2i(-1, 1), DIAG_COST], [Vector2i(-1, -1), DIAG_COST],
	]


## Costo mínimo de movimiento desde start a cada celda alcanzable.
## `blocked` es un set (Dictionary celda -> true) de celdas intransitables.
static func dijkstra(start: Vector2i, blocked: Dictionary, size: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var best := 0
		for i in range(1, frontier.size()):
			if dist[frontier[i]] < dist[frontier[best]]:
				best = i
		var cur: Vector2i = frontier.pop_at(best)
		for step in _steps():
			var nxt: Vector2i = cur + step[0]
			if not in_bounds(nxt, size) or blocked.has(nxt):
				continue
			var nd: int = dist[cur] + step[1]
			if not dist.has(nxt) or nd < dist[nxt]:
				dist[nxt] = nd
				if not frontier.has(nxt):
					frontier.append(nxt)
	return dist


## Distancia de ataque: menor costo de movimiento hasta la celda objetivo,
## ignorando que el objetivo la ocupa. Devuelve -1 si es inalcanzable.
static func attack_distance(from: Vector2i, to: Vector2i, blocked: Dictionary, size: Vector2i) -> int:
	var b := blocked.duplicate()
	b.erase(to)
	var dist := dijkstra(from, b, size)
	return dist.get(to, -1)


## Reconstruye el camino de menor costo desde start hasta dest usando un mapa
## de distancias de dijkstra(). Devuelve las celdas intermedias y el destino
## (sin la celda inicial). Vacío si dest es inalcanzable.
static func reconstruct_path(start: Vector2i, dest: Vector2i, dist: Dictionary) -> Array:
	if not dist.has(dest) or start == dest:
		return []
	var path := [dest]
	var cur := dest
	var guard := dist.size() + 1
	while cur != start and guard > 0:
		guard -= 1
		var found := false
		for step in _steps():
			var n: Vector2i = cur + step[0]
			if dist.has(n) and dist[n] + step[1] == dist[cur]:
				cur = n
				found = true
				break
		if not found:
			break
		if cur != start:
			path.push_front(cur)
	return path


## Raycast centro a centro. `blockers` es un set de celdas que bloquean visión.
## Las celdas origen y destino nunca bloquean.
static func has_line_of_sight(from: Vector2i, to: Vector2i, blockers: Dictionary) -> bool:
	if from == to:
		return true
	var p0 := Vector2(from) + Vector2(0.5, 0.5)
	var p1 := Vector2(to) + Vector2(0.5, 0.5)
	const EPS := 0.001
	for cell in blockers:
		if cell == from or cell == to:
			continue
		# La celda se achica un epsilon: rozar exactamente una esquina no bloquea.
		var rmin := Vector2(cell) + Vector2(EPS, EPS)
		var rmax := Vector2(cell) + Vector2(1.0 - EPS, 1.0 - EPS)
		if _segment_hits_rect(p0, p1, rmin, rmax):
			return false
	return true


## Intersección segmento-rectángulo (clipping de Liang-Barsky).
static func _segment_hits_rect(p0: Vector2, p1: Vector2, rmin: Vector2, rmax: Vector2) -> bool:
	var d := p1 - p0
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [p0.x - rmin.x, rmax.x - p0.x, p0.y - rmin.y, rmax.y - p0.y]
	for i in 4:
		if absf(p[i]) < 1e-9:
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true
