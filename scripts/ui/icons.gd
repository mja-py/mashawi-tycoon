extends Node
## Renders 3D models into small textures for the UI (SubViewport per icon, rendered
## once) and draws simple weather glyphs procedurally.

var _cache := {}
var _weather := {}

func model_icon(model: String, size: int = 128, zoom: float = 1.0) -> Texture2D:
	if _cache.has(model):
		return _cache[model]
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var n := ModelLib.spawn(model, root)
	var tex: Texture2D
	if n:
		var aabb := _scene_aabb(n)
		var center := aabb.get_center()
		var extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = extent * 1.25 / zoom
		cam.rotation_degrees = Vector3(-28, 35, 0)
		root.add_child(cam)
		cam.position = center + cam.transform.basis.z * (extent * 4.0)
		cam.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -30, 0)
		light.light_energy = 1.2
		root.add_child(light)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.9, 0.9, 0.95)
		e.ambient_light_energy = 0.9
		env.environment = e
		root.add_child(env)
		tex = vp.get_texture()
		# stop re-rendering after a few frames
		get_tree().create_timer(0.5).timeout.connect(func(): vp.render_target_update_mode = SubViewport.UPDATE_DISABLED)
	else:
		tex = PlaceholderTexture2D.new()
	_cache[model] = tex
	return tex

func _scene_aabb(n: Node) -> AABB:
	var result := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (mi as Node3D).global_transform
		var t := xf * box
		if first:
			result = t
			first = false
		else:
			result = result.merge(t)
	if n is MeshInstance3D:
		result = n.global_transform * (n as MeshInstance3D).get_aabb()
	return result

func weather_icon(id: String, size: int = 64) -> Texture2D:
	if _weather.has(id):
		return _weather[id]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := size / 2.0
	match id:
		"sunny":
			_rays(img, c, c, size * 0.44, Color(1.0, 0.78, 0.2))
			_disc(img, c, c, size * 0.28, Color(1.0, 0.85, 0.25))
		"hot":
			_rays(img, c, c, size * 0.47, Color(1.0, 0.45, 0.15))
			_disc(img, c, c, size * 0.3, Color(1.0, 0.6, 0.2))
			_disc(img, c, c, size * 0.16, Color(1.0, 0.85, 0.4))
		"cloudy":
			_cloud(img, c, c + size * 0.05, size, Color(0.82, 0.84, 0.88))
		"sandstorm":
			_cloud(img, c, c - size * 0.05, size * 0.95, Color(0.82, 0.66, 0.42))
			for i in range(3):
				_rect_rot(img, c - size * 0.1 + i * size * 0.12, c + size * 0.3, size * 0.4, size * 0.06, -0.35, Color(0.9, 0.78, 0.55))
		"breeze":
			_disc(img, c - size * 0.12, c - size * 0.1, size * 0.22, Color(1.0, 0.85, 0.3))
			for i in range(3):
				_rect(img, c - size * 0.3 + i * size * 0.1, c + size * 0.12 + i * size * 0.13, size * 0.55, size * 0.07, Color(0.55, 0.8, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_weather[id] = tex
	return tex

func _disc(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	for y in range(maxi(0, int(cy - r)), mini(img.get_height(), int(cy + r) + 1)):
		for x in range(maxi(0, int(cx - r)), mini(img.get_width(), int(cx + r) + 1)):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= r:
				var a := clampf(r - d, 0.0, 1.0)
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(col.r, col.g, col.b, col.a * a)))

func _rect(img: Image, x: float, y: float, w: float, h: float, col: Color) -> void:
	for yy in range(maxi(0, int(y)), mini(img.get_height(), int(y + h))):
		for xx in range(maxi(0, int(x)), mini(img.get_width(), int(x + w))):
			img.set_pixel(xx, yy, col)

func _rect_rot(img: Image, cx: float, cy: float, length: float, thick: float, angle: float, col: Color) -> void:
	var d := Vector2(cos(angle), sin(angle))
	var steps := int(length)
	for i in range(-steps / 2, steps / 2):
		var p := Vector2(cx, cy) + d * i
		_disc(img, p.x, p.y, thick / 2.0, col)

func _rays(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	for i in range(8):
		var a := i * PI / 4.0
		var p := Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r * 0.8
		_disc(img, p.x, p.y, r * 0.13, col)

func _cloud(img: Image, cx: float, cy: float, size: float, col: Color) -> void:
	_disc(img, cx - size * 0.2, cy + size * 0.05, size * 0.18, col)
	_disc(img, cx + size * 0.18, cy + size * 0.05, size * 0.2, col)
	_disc(img, cx, cy - size * 0.08, size * 0.24, col)
	_rect(img, cx - size * 0.3, cy + size * 0.05, size * 0.6, size * 0.18, col)

var _stars := {}

## A star glyph; `fill` 0..1 is how much of it (left to right) is golden.
func star_icon(fill: float, size: int = 28) -> Texture2D:
	var key := "%d_%d" % [size, int(round(fill * 4.0))]
	if _stars.has(key):
		return _stars[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pts := PackedVector2Array()
	var c := Vector2(size / 2.0, size / 2.0 + size * 0.03)
	for i in range(10):
		var r := size * (0.48 if i % 2 == 0 else 0.2)
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var gold := Color(0.95, 0.75, 0.2)
	var grey := Color(0.55, 0.5, 0.45, 0.5)
	var split: float = size * roundf(fill * 4.0) / 4.0
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, pts):
				img.set_pixel(x, y, gold if p.x <= split else grey)
	var tex := ImageTexture.create_from_image(img)
	_stars[key] = tex
	return tex
