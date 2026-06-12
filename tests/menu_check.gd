extends SceneTree
## Chequeo rápido del menú: compila, se construye y captura screenshot.
##   godot -s tests/menu_check.gd


func _initialize() -> void:
	LevelStore.campaign = LevelStore.default_campaign()
	var menu: Control = load("res://menu.tscn").instantiate()
	root.add_child(menu)
	_run()


func _run() -> void:
	for i in 10:
		await process_frame
	if DisplayServer.get_name() != "headless":
		var img := root.get_texture().get_image()
		img.save_png("res://tests/menu_01.png")
		print("screenshot: menu_01.png")
	print("MENU OK")
	quit(0)
