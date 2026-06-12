extends Control
## Menú principal: jugar la campaña o abrir el editor de niveles.


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiKit.COL_BG)
	LevelStore.ensure_loaded()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(360, 0)
	center.add_child(box)

	var title := UiKit.label(box, "Dungeon de Dados", 44, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UiKit.label(box, "Prototipo táctico por turnos", 14, UiKit.COL_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)

	var play := Button.new()
	play.text = "Jugar  (%d niveles)" % LevelStore.levels().size()
	UiKit.style_button(play, UiKit.COL_GOLD)
	play.pressed.connect(_on_play)
	box.add_child(play)

	var editor := Button.new()
	editor.text = "Editor de niveles"
	UiKit.style_button(editor, UiKit.COL_ENERGY)
	editor.pressed.connect(_on_editor)
	box.add_child(editor)

	var quit := Button.new()
	quit.text = "Salir"
	UiKit.style_button(quit, UiKit.COL_NEUTRAL)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)


func _on_play() -> void:
	LevelStore.test_level = -1
	get_tree().change_scene_to_file("res://main.tscn")


func _on_editor() -> void:
	get_tree().change_scene_to_file("res://editor.tscn")


func _on_quit() -> void:
	get_tree().quit()
