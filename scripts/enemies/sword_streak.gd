extends MeshInstance3D
class_name SwordStreak

# The motion streak behind a swinging blade: the band the blade swept through over the last `life` seconds, from
# partway up the blade to the tip, brightest at the tip and fading with age. While active it records the blade every
# frame; switched off it stops recording and the band it has fades out on its own.
#
# `blade` returns the blade as [guard, tip] in world space.

var blade: Callable
var active := false
var color := Color(1.0, 0.1, 0.04)
var brightness := 1.4         # added onto what is behind it: much brighter washes the red out towards pink
var life := 0.15              # seconds a piece of the band lasts
var start_along := 0.3        # the band starts this far up the blade (0 guard, 1 tip)

var ribbon := ImmediateMesh.new()
var samples: Array = []       # [inner point, tip, time], newest first
var material: StandardMaterial3D


func _ready() -> void:
	mesh = ribbon
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.disable_fog = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if active and blade.is_valid():
		var points: Array = blade.call()
		samples.push_front([points[0].lerp(points[1], start_along), points[1], now])
	while not samples.is_empty() and now - samples[samples.size() - 1][2] > life:
		samples.pop_back()
	_rebuild(now)


func _rebuild(now: float) -> void:
	ribbon.clear_surfaces()
	if samples.size() < 2:
		return
	material.albedo_color = Color(brightness, brightness, brightness)
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for sample in samples:
		var fade := clampf(1.0 - (now - sample[2]) / life, 0.0, 1.0)
		var inner := color
		inner.a = fade * fade * 0.25
		var outer := color
		outer.a = fade * fade
		ribbon.surface_set_color(inner)
		ribbon.surface_add_vertex(sample[0])
		ribbon.surface_set_color(outer)
		ribbon.surface_add_vertex(sample[1])
	ribbon.surface_end()
