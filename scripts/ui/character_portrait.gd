extends TextureRect
## Render at display-pixel density, independently of the street's quality setting.
## A small capped viewport and 30 Hz animation keep the close-up inexpensive.

const MAX_EDGE := 768
const SUPERSAMPLE := 2.0
const FRAME_SECONDS := 1.0 / 30.0
var actor: Node3D
var _viewport: SubViewport
var _animation: AnimationPlayer
var _elapsed := 0.0
var _frames := 0

func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 300)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.mesh_lod_threshold = 0.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	texture = _viewport.get_texture()
	actor = ModelLib.spawn_crew(true, _viewport, Vector3.ZERO, -5, 1.65)
	_animation = ModelLib.animation_player(actor)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ModelLib.play_loop(actor, "idle")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.22
	camera.position = Vector3(0, 1.14, 3)
	_viewport.add_child(camera)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -28, 0)
	light.light_energy = 1.1
	_viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff0df")
	environment.environment.ambient_light_energy = 0.8
	_viewport.add_child(environment)
	resized.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize.call_deferred()

func _resize() -> void:
	if not is_instance_valid(_viewport) or size.x < 1 or size.y < 1:
		return
	var display := Vector2(DisplayServer.window_get_size())
	var logical := get_viewport_rect().size
	var pixels := size * display / logical * SUPERSAMPLE
	# Never allocate a large Retina surface just because the device reports a high DPR.
	pixels *= minf(1.0, MAX_EDGE / maxf(pixels.x, pixels.y))
	_viewport.size = Vector2i(maxi(2, int(ceilf(pixels.x))), maxi(2, int(ceilf(pixels.y))))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func gesture() -> void:
	ModelLib.play_once(actor, "interact-right")

func _process(delta: float) -> void:
	# Fast-forward applies to the street, while our host speaks at a natural pace.
	_elapsed += delta / maxf(Engine.time_scale, 0.01)
	if _elapsed + 0.0001 < FRAME_SECONDS:
		return
	_animation.advance(minf(_elapsed, 0.1))
	_elapsed = fmod(_elapsed, FRAME_SECONDS)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_frames += 1

func test_view() -> Dictionary:
	return {"width": _viewport.size.x, "height": _viewport.size.y, "frames": _frames,
		"supersample": SUPERSAMPLE,
		"lod": _viewport.mesh_lod_threshold, "scale": _viewport.scaling_3d_scale,
		"bounds": {"x": get_global_rect().position.x, "y": get_global_rect().position.y,
			"width": size.x, "height": size.y}}
