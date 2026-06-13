class_name CharacterStore
## Colección de personajes creados. Persiste en user://characters.json.
## Si existe el viejo user://character.json (un solo personaje), se migra.
##
## Formato de cada personaje:
##   {name: String, voice: String,
##    parts: [{part, path, pos: [x, y] relativo al centro, scale}]}

const SAVE_PATH := "user://characters.json"
const LEGACY_PATH := "user://character.json"

static var characters: Array = []
static var edit_index := -1  # personaje en edición; -1 = personaje nuevo
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	characters = []
	if FileAccess.file_exists(SAVE_PATH):
		var parsed = JSON.parse_string(FileAccess.open(SAVE_PATH, FileAccess.READ).get_as_text())
		if parsed is Dictionary and parsed.get("characters") is Array:
			characters = parsed.characters
		return
	if FileAccess.file_exists(LEGACY_PATH):
		var old = JSON.parse_string(FileAccess.open(LEGACY_PATH, FileAccess.READ).get_as_text())
		if old is Dictionary and old.get("parts") is Array and not old.parts.is_empty():
			characters = [{
				"name": "Personaje 1",
				"voice": str(old.get("voice", "pii")),
				"parts": old.parts,
			}]
			save()


static func save() -> void:
	FileAccess.open(SAVE_PATH, FileAccess.WRITE).store_string(
		JSON.stringify({"characters": characters}, "\t"))
