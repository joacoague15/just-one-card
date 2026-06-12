class_name UiKit
## Paleta y helpers de UI compartidos entre menú, juego y editor.

const COL_BG := Color("201d28")
const COL_PANEL := Color("2b2735")
const COL_PANEL_LIGHT := Color("383344")
const COL_TILE_A := Color("4c4659")
const COL_TILE_B := Color("443e51")
const COL_OBSTACLE := Color("1a1622")
const COL_ROCK := Color("353044")
const COL_GOLD := Color("e8b54d")
const COL_TEXT := Color("ece8f4")
const COL_DIM := Color("9b94ae")
const COL_PLAYER := Color("4d8fe8")
const COL_SPEED := Color("57c878")
const COL_ATK := Color("ff7a5c")
const COL_DEF := Color("5cb8ff")
const COL_DANGER := Color("ff5a45")
const COL_HEAL := Color("6fdd8b")
const COL_ENERGY := Color("b08be8")
const COL_WARN := Color("f0a35e")
const COL_NEUTRAL := Color("8a82a3")


static func style_button(b: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", normal)
	var hov: StyleBoxFlat = normal.duplicate()
	hov.bg_color = accent.lightened(0.12)
	b.add_theme_stylebox_override("hover", hov)
	var pre: StyleBoxFlat = normal.duplicate()
	pre.bg_color = accent.darkened(0.15)
	b.add_theme_stylebox_override("pressed", pre)
	var dis: StyleBoxFlat = normal.duplicate()
	dis.bg_color = Color("353043")
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for cname in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(cname, Color("1d1a26"))
	b.add_theme_color_override("font_disabled_color", Color("716a85"))


## Botón con estilo "toggle" que conserva texto claro (para herramientas).
static func style_tool_button(b: Button, accent: Color) -> void:
	b.toggle_mode = true
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_PANEL_LIGHT
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", normal)
	var hov: StyleBoxFlat = normal.duplicate()
	hov.bg_color = COL_PANEL_LIGHT.lightened(0.08)
	b.add_theme_stylebox_override("hover", hov)
	var pre: StyleBoxFlat = normal.duplicate()
	pre.bg_color = accent
	b.add_theme_stylebox_override("pressed", pre)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_TEXT)
	b.add_theme_color_override("font_pressed_color", Color("1d1a26"))


static func section(parent: Control, title: String, expand: bool = false) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	if expand:
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	if title != "":
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", COL_DIM)
		box.add_child(t)
	return box


static func label(parent: Control, text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
