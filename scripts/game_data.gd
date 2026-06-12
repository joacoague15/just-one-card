class_name GameData
## Datos de niveles y monstruos.
## Convención interna: Vector2i(columna, fila), 0-indexado.
## El ticket expresa posiciones como fila/columna 1-indexadas; rc() convierte.

const STAT_MAX := 6

const PLAYER_BASE := {
	"max_health": 6,
	"speed": 1,
	"attack": 1,
	"defense": 1,
	"range": 2,
}

const MONSTER_TYPES := {
	"spider": {
		"name": "Araña",
		"health": 2,
		"speed": 5,
		"attack": 4,
		"defense": 4,
		"range": 3,
	},
	"skeleton_archer": {
		"name": "Esqueleto arquero",
		"health": 3,
		"speed": 4,
		"attack": 5,
		"defense": 4,
		"range": 4,
	},
}


static func rc(fila: int, columna: int) -> Vector2i:
	return Vector2i(columna - 1, fila - 1)


static func levels() -> Array:
	return [
		{
			"level": 1,
			"player_start": rc(5, 1),
			"obstacles": [rc(2, 4), rc(4, 2), rc(4, 4)],
			"monsters": [
				{"type": "spider", "position": rc(1, 4)},
				{"type": "spider", "position": rc(3, 5)},
			],
		},
		{
			"level": 2,
			"player_start": rc(5, 5),
			"obstacles": [rc(3, 1), rc(3, 4), rc(4, 4)],
			"monsters": [
				{"type": "skeleton_archer", "position": rc(1, 3)},
				{"type": "skeleton_archer", "position": rc(2, 1)},
			],
		},
	]
