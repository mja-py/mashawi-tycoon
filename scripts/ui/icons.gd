extends Node
## Renders 3D models into small textures for the UI (SubViewport per icon, rendered
## once) and draws simple weather glyphs procedurally.

var _cache := {}
var _weather := {}

func dish_icon(id: String) -> Texture2D:
	var locked := not bool(Game.menu.get(id, {}).get("unlocked", true))
	return model_icon(Data.MENU_ITEMS[id]["model"], 192, 1.0, true, locked)

func model_icon(model: String, size: int = 128, zoom: float = 1.0, plated: bool = false, locked: bool = false) -> Texture2D:
	var key := ("dish:" if plated else "model:") + model
	if plated and locked:
		key += ":locked"
	if _cache.has(key):
		return _cache[key]
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
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.rotation_degrees = Vector3(-32 if plated else -28, 35, 0)
		root.add_child(cam)
		if plated and model.ends_with("-skewer"):
			# Show both the grilled faces and the stick on a readable diagonal.
			n.rotation_degrees.y = -15
		var aabb := _scene_aabb(n)
		var center := aabb.get_center()
		var extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if plated:
			# Fit in camera space: long skewers must not shrink with foreshortening,
			# while upright cups/fries need headroom rather than an oversized plate.
			var projected := _projected_scene_bounds(n, cam.basis)
			var scale_factor := 0.78 / maxf(maxf(projected.size.x, projected.size.y), 0.01)
			n.scale = Vector3.ONE * scale_factor
			n.position = Vector3(-center.x, -aabb.position.y, -center.z) * scale_factor + Vector3(0, 0.035, 0)
			var vessel := model in ["food/cup", "food/soda-can", "food/karak-cup", "food/fries", "food/salad-bowl", "food/mashawi-platter", "food/sago-halwa", "food/omani-halwa"]
			var radius := 0.25 if vessel else 0.36
			# Layered translucent discs give a soft baked contact shadow.
			for i in range(5):
				var shadow := ModelLib.cylinder(root, radius + 0.032 - i * 0.018, 0.001, Vector3(0.008, -0.015 + i * 0.002, 0.012), Color("443526"))
				var mat := ModelLib.flat_material_unique(Color(0.18, 0.12, 0.08, 0.055))
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				shadow.material_override = mat
			if not vessel:
				ModelLib.cylinder(root, radius, 0.015, Vector3.ZERO, Color("b69970"))
				ModelLib.cylinder(root, radius - 0.014, 0.016, Vector3(0, 0.012, 0), Color("eedbb3"))
				ModelLib.cylinder(root, radius - 0.038, 0.003, Vector3(0, 0.022, 0), Color("e3cba0"))
				# Food rests directly above its shadow, not floating above the rim.
				var contact := ModelLib.cylinder(root, 0.23, 0.001, Vector3(0, 0.025, 0), Color("b89d74"))
				contact.scale.z = 0.55 if model.ends_with("-skewer") else 0.85
				contact.rotation.y = n.rotation.y
			var composition := _projected_scene_bounds(root, cam.basis)
			center = cam.basis.x * composition.get_center().x + cam.basis.y * composition.get_center().y
			# A tall wrap plus its plate can exceed the food silhouette alone.
			extent = maxf(1.0, maxf(composition.size.x, composition.size.y) / 0.94)
		cam.size = extent * (1.0 if plated else 1.25) / zoom
		cam.position = center + cam.transform.basis.z * (extent * 4.0)
		cam.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48, -25, 0) if plated else Vector3(-45, -30, 0)
		light.light_color = Color("ffead1") if plated else Color.WHITE
		light.light_energy = 0.9 if plated else 1.2
		root.add_child(light)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color("f4eee0") if plated else Color(0.9, 0.9, 0.95)
		e.ambient_light_energy = 0.7 if plated else 0.9
		env.environment = e
		root.add_child(env)
		# Keep a tiny bitmap, not a viewport + model + camera for every menu icon.
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		tex = ImageTexture.create_from_image(img)
		_finish_icon.call_deferred(vp, tex, plated and locked)
	else:
		tex = PlaceholderTexture2D.new()
		vp.queue_free()
	_cache[key] = tex
	return tex

func _finish_icon(vp: SubViewport, tex: ImageTexture, locked: bool = false) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty():
		if locked:
			# Bake the availability treatment too; no live shader or font glyphs.
			# One pass over 192x192 per locked dish, once per session.
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					var c := img.get_pixel(x, y)
					var grey := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
					var muted := c.lerp(Color(grey, grey, grey, c.a), 0.72)
					img.set_pixel(x, y, Color(muted.r * 0.78, muted.g * 0.78, muted.b * 0.78, c.a))
			var u := img.get_width() / 192.0
			_disc(img, 157 * u, 38 * u, 21 * u, Color("403e35"))
			_disc(img, 157 * u, 33 * u, 9 * u, Color("eddbb8"))
			_disc(img, 157 * u, 33 * u, 5 * u, Color("403e35"))
			_rect(img, 145 * u, 34 * u, 24 * u, 17 * u, Color("eddbb8"))
			_rect(img, 155 * u, 40 * u, 4 * u, 6 * u, Color("403e35"))
		tex.set_image(img)
	vp.queue_free()

func _projected_scene_bounds(n: Node3D, camera_basis: Basis) -> Rect2:
	# Fit the actual silhouette, not empty AABB corners around thin skewers.
	# These small food meshes are inspected only while baking the bitmap.
	var bounds := Rect2()
	var meshes := n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	var first := true
	for mi: MeshInstance3D in meshes:
		var xf := Transform3D(camera_basis.inverse(), Vector3.ZERO) * mi.global_transform
		for vertex in mi.mesh.get_faces():
			var p := xf * vertex
			var point := Vector2(p.x, p.y)
			bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
			first = false
	return bounds

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
