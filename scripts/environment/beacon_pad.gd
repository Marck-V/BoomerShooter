extends Node3D
class_name BeaconPad

# A marker on the ground: a disc of glowing rings with a column of light rising out of it and a soft light, in an
# idle colour that can switch to an active one. Not used anywhere yet; built for checkpoints and kept for something
# else (a respawn point, an objective, an exit...). Place it with its origin on the floor.
#
#   set_active(1.0)    show it as active straight away
#   play_activate()    flash, surge up the beam, and blend to the active colour

const PAD_SHADER: Shader = preload("res://shaders/beacon_pad.gdshader")
const BEAM_SHADER: Shader = preload("res://shaders/launch_portal_beam.gdshader")

@export var radius := 0.8
@export var beam_height := 3.0
@export var idle_color := Color(0.2, 0.9, 1.0)
@export var active_color := Color(0.3, 1.0, 0.4)

const BEAM_IDLE := 0.7
const BEAM_ACTIVE := 0.3
const LIGHT_IDLE := 0.8
const LIGHT_ACTIVE := 0.35
const ACTIVATE_TIME := 0.9

var pad_material: ShaderMaterial
var beam_material: ShaderMaterial
var light: OmniLight3D
var tween: Tween


func _ready() -> void:
	_build_pad()
	_build_beam()
	_build_light()


# 0 = idle, 1 = active: blends the colour and brightness of every part
func set_active(amount: float) -> void:
	var color := idle_color.lerp(active_color, amount)
	pad_material.set_shader_parameter("active", amount)
	beam_material.set_shader_parameter("beam_color", color)
	light.light_color = color
	if tween == null or not tween.is_running():
		beam_material.set_shader_parameter("intensity", lerpf(BEAM_IDLE, BEAM_ACTIVE, amount))
		light.light_energy = lerpf(LIGHT_IDLE, LIGHT_ACTIVE, amount)


func play_activate() -> void:
	if tween:
		tween.kill()
	tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(set_active, 0.0, 1.0, ACTIVATE_TIME)
	tween.tween_method(func(f: float): pad_material.set_shader_parameter("flash", f), 2.0, 0.0, ACTIVATE_TIME * 0.7)
	tween.tween_method(func(i: float): beam_material.set_shader_parameter("intensity", i),
		3.5, BEAM_ACTIVE, ACTIVATE_TIME * 1.5)
	tween.tween_property(light, "light_energy", LIGHT_ACTIVE, ACTIVATE_TIME * 1.5).from(4.0)


func _build_pad() -> void:
	pad_material = ShaderMaterial.new()
	pad_material.shader = PAD_SHADER
	pad_material.set_shader_parameter("idle_color", idle_color)
	pad_material.set_shader_parameter("active_color", active_color)
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var pad := MeshInstance3D.new()
	pad.mesh = plane
	pad.material_override = pad_material
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.position.y = 0.02
	add_child(pad)


func _build_beam() -> void:
	beam_material = ShaderMaterial.new()
	beam_material.shader = BEAM_SHADER
	beam_material.set_shader_parameter("height", beam_height)
	beam_material.set_shader_parameter("beam_color", idle_color)
	beam_material.set_shader_parameter("intensity", BEAM_IDLE)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.9
	cylinder.bottom_radius = radius * 0.9
	cylinder.height = beam_height
	cylinder.radial_segments = 24
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = cylinder
	beam.material_override = beam_material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = beam_height * 0.5 + 0.02
	add_child(beam)


func _build_light() -> void:
	light = OmniLight3D.new()
	light.light_color = idle_color
	light.light_energy = LIGHT_IDLE
	light.omni_range = 5.0
	light.position.y = 0.6
	add_child(light)
