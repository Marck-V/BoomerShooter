extends Node3D
class_name HandMortar

# One shell of the hand boss's mortar barrage. It leaves a fingertip straight up, vanishes into the sky, and a moment
# later drops onto the spot that was picked when it launched, where a red circle on the floor has been filling up.
# Landing splashes everyone inside the circle (the boss decides how hard, see HandBoss.splash). It is not an energy
# ball, so it can't be parried: the only answer is to be somewhere else. If the boss's action is interrupted while a
# shell is still in the air, the shell and its warning disappear with it.
#   HandMortar.launch(boss, from_point, land_point, radius, rise_time, fall_time)

const SHELL_COLOR := Color(1.0, 0.35, 0.08)
const SKY_HEIGHT := 30.0              # metres above the floor the shell vanishes to and drops from

var boss: HandBoss
var token := 0                        # the boss's action when it fired; a different one means the attack was cut short
var from_point := Vector3.ZERO
var land_point := Vector3.ZERO
var radius := 3.5
var rise_time := 0.5
var fall_time := 1.3
var warning: BossTelegraph
var age := 0.0
var landed := false
var shell: MeshInstance3D
var light: OmniLight3D


static func launch(owner_boss: HandBoss, start: Vector3, land: Vector3, blast_radius: float, rise: float, fall: float) -> HandMortar:
	var mortar := HandMortar.new()
	mortar.boss = owner_boss
	mortar.token = owner_boss.action_token
	mortar.from_point = start
	mortar.land_point = land
	mortar.radius = blast_radius
	mortar.rise_time = rise
	mortar.fall_time = fall
	owner_boss.get_tree().current_scene.add_child(mortar)
	mortar.global_position = start
	return mortar


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 0.9
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(SHELL_COLOR.r * 2.5, SHELL_COLOR.g * 2.5, SHELL_COLOR.b * 2.5)
	shell = MeshInstance3D.new()
	shell.mesh = mesh
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	light = OmniLight3D.new()
	light.light_color = SHELL_COLOR
	light.light_energy = 3.0
	light.omni_range = 7.0
	add_child(light)
	warning = boss.warn_circle(land_point, radius, HandBoss.DANGER_GLOW)
	warning.set_progress(0.0)


func _physics_process(delta: float) -> void:
	if landed:
		return
	if not is_instance_valid(boss) or boss.action_token != token or boss.destroyed:
		_vanish()
		return
	age += delta
	var sky := Vector3(land_point.x, land_point.y + SKY_HEIGHT, land_point.z)
	if age < rise_time:
		# Up out of the fingertip, speeding up as it goes
		var k := age / rise_time
		global_position = from_point.lerp(Vector3(from_point.x, land_point.y + SKY_HEIGHT, from_point.z), k * k)
		shell.scale = Vector3.ONE * lerpf(0.5, 1.0, k)
	else:
		var k := clampf((age - rise_time) / fall_time, 0.0, 1.0)
		global_position = sky.lerp(land_point, k * k)       # falls faster and faster
		shell.scale = Vector3.ONE * 1.2
		warning.set_progress(k)
		if k >= 1.0:
			_land()


func _land() -> void:
	landed = true
	var tree := get_tree()
	warning.finish(0.15)
	BomberExplosion.spawn(tree, land_point + Vector3.UP * 0.3, radius * 0.8)
	WaterRipple.spawn(tree, land_point, 0.5, radius)
	boss.splash(land_point, radius)
	queue_free()


func _vanish() -> void:
	landed = true
	if is_instance_valid(warning):
		warning.finish(0.15)
	queue_free()
