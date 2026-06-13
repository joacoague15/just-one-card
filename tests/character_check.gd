extends SceneTree
## Chequeo end-to-end del editor de personajes: descubrimiento de sprites,
## colocado/reemplazo, hit-test por píxel, escala, borrado y persistencia.
##   godot -s tests/character_check.gd          (con ventana, guarda screenshots)
##   godot --headless -s tests/character_check.gd

const SAVE_PATH := "user://characters.json"
const LEGACY_PATH := "user://character.json"

var failures := 0
var _backups := {}


func _initialize() -> void:
	# El test escribe en los archivos reales del usuario: respaldar y restaurar.
	for p in [SAVE_PATH, LEGACY_PATH]:
		if FileAccess.file_exists(p):
			_backups[p] = FileAccess.open(p, FileAccess.READ).get_as_text()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	CharacterStore._loaded = false
	CharacterStore.characters = []
	CharacterStore.edit_index = -1
	var ed: Control = load("res://character_editor.tscn").instantiate()
	root.add_child(ed)
	_run(ed)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FALLO: " + msg)


func _run(ed: Control) -> void:
	await _frames(10)

	# Descubrimiento: una opción por sección con los sprites actuales.
	var sprites: Dictionary = ed._discover_sprites()
	for part in ["body", "head", "eyes", "nose", "mouth", "hat"]:
		_expect(sprites[part].size() == 1, "descubrió un sprite para %s" % part)

	# Los sprites procesados tienen alpha real (el damero se eliminó).
	var entry: Dictionary = ed._load_sprite("res://sprites/head.png")
	var used: Rect2i = entry.used
	_expect(used.size.x < entry.img.get_width() and used.size.y < entry.img.get_height(),
		"head.png tiene márgenes transparentes (alpha real)")

	await _shot(ed, "ch_01_vacio.png")

	# Colocar una parte en el centro.
	var center: Vector2 = ed.stage.size * 0.5
	ed.place_part("head", "res://sprites/head.png", center)
	_expect(ed.placed.has("head"), "cabeza colocada")
	_expect(ed.selected == "head", "la parte colocada queda seleccionada")

	# Hit-test por píxel: el centro de la cabeza pega, la esquina transparente no.
	_expect(ed.part_at(center) == "head", "hit en el centro del sprite")
	var corner: Vector2 = center - Vector2(entry.img.get_width(), entry.img.get_height()) * ed.placed.head.scale * 0.49
	_expect(ed.part_at(corner) == "", "la esquina transparente no captura clicks")

	# Reemplazo: colocar otra vez la misma parte no duplica.
	ed.place_part("head", "res://sprites/head.png", center + Vector2(10, 0))
	_expect(ed.placed.size() == 1, "recolocar la misma parte la reemplaza")

	# Escala con límites.
	ed.placed.head.scale = 0.3
	ed._scale_selected(100.0)
	_expect(ed.placed.head.scale <= ed.MAX_SCALE, "la escala respeta el máximo")

	# Armar ejemplo completo.
	ed._on_example()
	_expect(ed.placed.size() == 6, "el ejemplo coloca las 6 partes")
	await _frames(3)
	await _shot(ed, "ch_02_ejemplo.png")

	# Ojos: el análisis detecta dos ojos con centros y radios razonables.
	var eyes: Array = ed._eye_info("res://sprites/eyes.png")
	_expect(eyes.size() == 2, "se detectan 2 ojos")
	if eyes.size() == 2:
		_expect(eyes[0].center.x < eyes[1].center.x, "ojo izquierdo a la izquierda del derecho")
		_expect(eyes[0].radius > 20.0 and eyes[1].radius > 20.0, "radios de ojo plausibles")
		var dy: float = absf(eyes[0].center.y - eyes[1].center.y)
		_expect(dy < eyes[0].radius, "los ojos están a la misma altura")

	# Pestañeo: el párpado cae (0 -> 1), queda cerrado un instante y reabre.
	_expect(not ed.is_blinking(), "no pestañea apenas armado")
	_expect(ed.blink_amount() == 0.0, "párpado abierto fuera del pestañeo")
	ed._blink_wait = 0.01
	ed._process(0.02)
	_expect(ed.is_blinking(), "al vencer la espera, pestañea")
	ed.set_process(false)  # congelar para inspeccionar fases
	ed._process(ed.BLINK_CLOSE * 0.5)
	var mid: float = ed.blink_amount()
	_expect(mid > 0.3 and mid < 0.7, "a mitad del cierre el párpado va por la mitad")
	await _shot(ed, "ch_04_pestaneo.png")
	ed._process(ed.BLINK_CLOSE * 0.5 + ed.BLINK_HOLD * 0.5)
	_expect(ed.blink_amount() == 1.0, "fase de párpado cerrado")
	ed._process(ed.BLINK_HOLD * 0.5 + ed.BLINK_OPEN * 0.5)
	var opening: float = ed.blink_amount()
	_expect(opening > 0.3 and opening < 0.7, "al reabrir el párpado sube")
	ed._process(1.0)
	_expect(not ed.is_blinking() and ed.blink_amount() == 0.0, "el pestañeo termina")
	_expect(ed._blink_wait >= ed.BLINK_MIN and ed._blink_wait <= ed.BLINK_MAX,
		"la próxima espera queda entre 2 y 5 segundos")
	ed.set_process(true)

	# Voces: las 3 generan audio válido con sílabas registradas.
	for v in ed.VOICES:
		var wav: AudioStreamWAV = ed._generate_babble(v)
		var seconds: float = wav.data.size() / 2.0 / ed.AUDIO_RATE
		_expect(seconds > 0.4 and seconds < 4.0, "voz %s: duración razonable" % v.id)
		var count: int = ed._talk_syllables.size()
		_expect(count >= v.syl[0] and count <= v.syl[1], "voz %s: cantidad de sílabas" % v.id)
		var prev_end := 0.0
		var ordered := true
		for syl in ed._talk_syllables:
			if syl.x < prev_end or syl.y <= syl.x or syl.y > seconds:
				ordered = false
			prev_end = syl.y
		_expect(ordered, "voz %s: sílabas ordenadas dentro del audio" % v.id)

	# Boca: pulsa en loop mientras habla; la boca normal vuelve al terminar.
	_expect(not ed.is_talking(), "sin audio no está hablando")
	_expect(ed.mouth_pulse() == 0.0, "sin hablar el pulso es 0")
	ed._on_talk()
	_expect(ed.is_talking(), "al hablar entra en modo círculo")
	var pulse: float = ed.mouth_pulse()
	_expect(pulse >= 0.0 and pulse <= 1.0, "el pulso queda en rango 0..1")
	await create_timer(0.25).timeout
	ed._talk_player.stop()
	_expect(not ed.is_talking(), "al terminar el audio vuelve la boca normal")

	# Captura con la boca en su tamaño máximo.
	ed.force_mouth_open = 1.0
	_expect(ed.is_talking() and ed.mouth_pulse() == 1.0, "forzado para captura")
	await _frames(2)
	await _shot(ed, "ch_05_hablando.png")
	ed.force_mouth_open = 0.0

	# Selección + panel.
	ed.selected = "hat"
	ed._refresh_selection_panel()
	_expect(ed.scale_slider.editable, "el slider se habilita con selección")
	await _frames(2)
	await _shot(ed, "ch_03_seleccion.png")

	# Eliminar parte.
	ed._on_delete_selected()
	_expect(not ed.placed.has("hat") and ed.placed.size() == 5, "eliminar quita la parte")

	# Guardado: con partes faltantes NO se guarda.
	ed._on_save()
	_expect(CharacterStore.characters.is_empty(), "incompleto: no se guarda en la galería")
	_expect("faltan" in ed.status_label.text.to_lower(), "el estado explica qué partes faltan")
	_expect(ed.missing_parts() == ["Sombrero"], "falta exactamente el sombrero")

	# Completo: se guarda como personaje nuevo de la galería.
	ed._on_example()
	ed._on_save()
	_expect(CharacterStore.characters.size() == 1, "completo: se guarda")
	_expect(CharacterStore.edit_index == 0, "el personaje nuevo queda en edición")
	_expect(CharacterStore.characters[0].parts.size() == 6, "se guardan las 6 partes")

	# Persistencia real: vaciar memoria y recargar desde characters.json.
	CharacterStore._loaded = false
	CharacterStore.characters = []
	CharacterStore.ensure_loaded()
	_expect(CharacterStore.characters.size() == 1, "persistencia en characters.json")
	_expect(str(CharacterStore.characters[0].name) == "Personaje 1", "el nombre persiste")
	_expect(str(CharacterStore.characters[0].voice) == ed.selected_voice, "la voz persiste")

	# Editar desde la galería: el editor carga el personaje elegido.
	ed.queue_free()
	await _frames(2)
	CharacterStore.edit_index = 0
	var ed2: Control = load("res://character_editor.tscn").instantiate()
	root.add_child(ed2)
	await _frames(3)
	_expect(ed2.placed.size() == 6, "editar carga las 6 partes")
	_expect(ed2.char_name == "Personaje 1", "editar carga el nombre")
	ed2.queue_free()
	await _frames(2)

	# Galería: un marco por personaje.
	var gal: Control = load("res://character_gallery.tscn").instantiate()
	root.add_child(gal)
	await _frames(5)
	var flow := _find_flow(gal)
	_expect(flow != null and flow.get_child_count() == 1, "la galería muestra 1 marco")
	await _shot(gal, "ch_06_galeria.png")
	gal.queue_free()
	await _frames(2)

	_restore_save_files()
	if failures == 0:
		print("CHARACTER OK")
		quit(0)
	else:
		print("FALLARON %d chequeos del editor de personajes" % failures)
		quit(1)


func _restore_save_files() -> void:
	for p in [SAVE_PATH, LEGACY_PATH]:
		if _backups.has(p):
			FileAccess.open(p, FileAccess.WRITE).store_string(_backups[p])
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	CharacterStore._loaded = false
	CharacterStore.characters = []
	CharacterStore.edit_index = -1


func _find_flow(node: Node) -> HFlowContainer:
	if node is HFlowContainer:
		return node
	for child in node.get_children():
		var found := _find_flow(child)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(_ed: Control, file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_move_to_foreground()
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://tests/" + file_name)
	print("screenshot: ", file_name)
