class_name CharacterRenderer
## Carga y cache de sprites de partes + dibujo compartido entre el editor de
## personajes y la galería: ojos con pupilas que siguen al mouse, párpado de
## pestañeo y boca que habla.

const PUPIL_RATIO := 0.6  # tamaño de la pupila respecto del ojo
const BLINK_MIN := 2.0
const BLINK_MAX := 5.0
const BLINK_CLOSE := 0.07
const BLINK_HOLD := 0.06
const BLINK_OPEN := 0.07
const BLINK_TOTAL := BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN

static var _cache := {}  # path -> {tex, img, used, eyes_info?}


static func sprite(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var entry := {"tex": tex, "img": img, "used": img.get_used_rect()}
	_cache[path] = entry
	return entry


## Centros y radios de los ojos del sprite (en píxeles de la imagen original).
## Genérico: agrupa los píxeles opacos en mitad izquierda y derecha del
## contenido; sirve para cualquier sprite de ojos. Se cachea por path.
static func eye_info(path: String) -> Array:
	var entry := sprite(path)
	if not entry.has("eyes_info"):
		entry["eyes_info"] = _analyze_eyes(entry.img)
	return entry.eyes_info


static func _analyze_eyes(img: Image) -> Array:
	# Analizar a baja resolución: alcanza y es rápido.
	var factor := maxf(1.0, img.get_width() / 200.0)
	var small: Image = img.duplicate()
	small.resize(int(img.get_width() / factor), int(img.get_height() / factor),
		Image.INTERPOLATE_BILINEAR)
	var used := small.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return []
	var mid := used.position.x + used.size.x / 2.0
	var bounds: Array = [Rect2(), Rect2()]
	var counts := [0, 0]
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if small.get_pixel(x, y).a < 0.5:
				continue
			var i := 0 if x < mid else 1
			var px := Rect2(x, y, 1, 1)
			bounds[i] = px if counts[i] == 0 else (bounds[i] as Rect2).merge(px)
			counts[i] += 1
	var total: int = counts[0] + counts[1]
	var result := []
	for i in 2:
		# Un grupo despreciable (< 5% de los píxeles) no es un ojo: sprite de un solo ojo.
		if total == 0 or counts[i] < total * 0.05:
			continue
		var r: Rect2 = bounds[i]
		result.append({
			"center": r.get_center() * factor,
			"radius": minf(r.size.x, r.size.y) * 0.5 * factor,
		})
	return result


## Cuán cerrado está el párpado (0 = abierto, 1 = cerrado) según el tiempo
## restante del pestañeo en curso.
static func blink_amount(blink_left: float) -> float:
	if blink_left <= 0.0:
		return 0.0
	var elapsed := BLINK_TOTAL - blink_left
	if elapsed < BLINK_CLOSE:
		return elapsed / BLINK_CLOSE
	if elapsed < BLINK_CLOSE + BLINK_HOLD:
		return 1.0
	return blink_left / BLINK_OPEN


## Sprite completo centrado en `pos` con escala `scale`.
static func draw_part(c: CanvasItem, path: String, pos: Vector2, scale: float) -> void:
	var entry := sprite(path)
	var img_size := Vector2(entry.img.get_width(), entry.img.get_height())
	c.draw_texture_rect(entry.tex, Rect2(pos - img_size * scale * 0.5, img_size * scale), false)


## Ojos con pupilas que siguen a `mouse` y párpado que cae con `blink` (0..1):
## el sprite y las pupilas se recortan a la línea del párpado.
static func draw_eyes(c: CanvasItem, path: String, pos: Vector2, scale: float,
		mouse: Vector2, blink: float) -> void:
	var entry := sprite(path)
	var img_size := Vector2(entry.img.get_width(), entry.img.get_height())
	var top_left := pos - img_size * scale * 0.5
	if blink <= 0.0:
		c.draw_texture_rect(entry.tex, Rect2(top_left, img_size * scale), false)
		_draw_pupils(c, path, pos, scale, mouse, -1.0e9)
		return
	var used: Rect2i = entry.used
	var cut_img: float = used.position.y + blink * used.size.y
	if cut_img < img_size.y:
		var src := Rect2(0, cut_img, img_size.x, img_size.y - cut_img)
		var dst := Rect2(top_left + Vector2(0, cut_img * scale), src.size * scale)
		c.draw_texture_rect_region(entry.tex, dst, src)
	_draw_pupils(c, path, pos, scale, mouse, top_left.y + cut_img * scale)


static func _draw_pupils(c: CanvasItem, path: String, pos: Vector2, scale: float,
		mouse: Vector2, cut_y: float) -> void:
	var entry := sprite(path)
	var img_size := Vector2(entry.img.get_width(), entry.img.get_height())
	for eye in eye_info(path):
		var center: Vector2 = pos - img_size * scale * 0.5 + eye.center * scale
		var radius: float = eye.radius * scale
		var pupil_r := radius * PUPIL_RATIO
		var max_travel := maxf(radius - pupil_r, 0.0) * 0.85
		var offset := (mouse - center).limit_length(max_travel)
		_draw_circle_below(c, center + offset, pupil_r, cut_y)


## Dibuja la parte de un círculo que queda por debajo de la línea `cut_y`.
static func _draw_circle_below(c: CanvasItem, center: Vector2, r: float, cut_y: float) -> void:
	if cut_y <= center.y - r:
		c.draw_circle(center, r, Color.BLACK)
		return
	if cut_y >= center.y + r:
		return
	# Segmento circular: arco por debajo de la cuerda y = cut_y.
	var a1 := asin(clampf((cut_y - center.y) / r, -1.0, 1.0))
	var a2 := PI - a1
	var points := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var a := a1 + (a2 - a1) * i / float(steps)
		points.append(center + Vector2(cos(a), sin(a)) * r)
	c.draw_colored_polygon(points, Color.BLACK)


## Boca: si está hablando es un círculo negro que pulsa (pulse 0..1); si no,
## el sprite normal.
static func draw_mouth(c: CanvasItem, path: String, pos: Vector2, scale: float,
		talking: bool, pulse: float) -> void:
	var entry := sprite(path)
	var img_size := Vector2(entry.img.get_width(), entry.img.get_height())
	if not talking:
		c.draw_texture_rect(entry.tex, Rect2(pos - img_size * scale * 0.5, img_size * scale), false)
		return
	var used: Rect2i = entry.used
	var center: Vector2 = pos - img_size * scale * 0.5 + Vector2(used.get_center()) * scale
	var max_radius: float = Vector2(used.size).x * scale * 0.26
	var radius: float = max_radius * lerpf(0.45, 1.0, pulse)
	# La boca se abre hacia abajo desde la línea de la sonrisa (no tapa la nariz).
	c.draw_circle(center + Vector2(0, max_radius * 0.7), radius, Color.BLACK)


## Rectángulo del contenido visible (sin márgenes transparentes) de una parte.
static func content_rect(path: String, pos: Vector2, scale: float) -> Rect2:
	var entry := sprite(path)
	var img_size := Vector2(entry.img.get_width(), entry.img.get_height())
	var top_left: Vector2 = pos - img_size * 0.5 * scale + Vector2(entry.used.position) * scale
	return Rect2(top_left, Vector2(entry.used.size) * scale)
