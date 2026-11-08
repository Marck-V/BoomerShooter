extends BaseWeapon

@onready var glitch_glow: OmniLight3D = $GlitchGlow
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh
@onready var detach_mesh: MeshInstance3D = $"WeaponMesh/Shotgun-Detach"
const GLITCH_SHADER: Shader = preload("res://shaders/player/glitch_shot_overheat.gdshader")
const GLITCH_RAMP_TIME := 0.3
const GLITCH_LIGHT_ENERGY := 6.0
var glow_material: ShaderMaterial          # on the gun's body
var detach_glow_material: ShaderMaterial   # on the pump, which sits offset from the body
var glow_intensity := 0.0
var glow_tween: Tween

var tween: Tween

var precision = "shotgun_precision"
var shield_break = "shotgun_shield_break"
var glitch_shot = "shotgun_glitch_shot"

var has_precision = false
var has_shield_break = false
var has_glitch_shot = false

var shot_tracker = 0
var dmg_multiplier = 1.25
var base_dmg

func _ready():
	super._ready()
	muzzle_flash_size = 0.1
	muzzle_flash_time = 0.12
	muzzle_light_energy = 14.0
	glow_material = ShaderMaterial.new()
	glow_material.shader = GLITCH_SHADER
	detach_glow_material = ShaderMaterial.new()
	detach_glow_material.shader = GLITCH_SHADER
	detach_glow_material.set_shader_parameter("local_offset", detach_mesh.position)   # the pump's place in the body's space
	_refresh_upgrades()


func get_shield_multiplier() -> float:
	if has_shield_break:
		return 1.5
	return 1.0


func fire(origin: Vector3, direction: Vector3, camera: Camera3D, raycast: RayCast3D) -> bool:
	# An empty click is not a shot: it must not advance the glitch shot counter
	if not GlobalVariables.can_spend_ammo("shotgun", 1):
		return super.fire(origin, direction, camera, raycast)

	# Glitch shot logic
	if has_glitch_shot:
		shot_tracker += 1
		if shot_tracker >= 3:
			data.damage *= dmg_multiplier
			print("Glitch Shot Activated! Damage:", data.damage)
			shot_tracker = 0
	else:
		data.damage = base_dmg

	_update_glitch_glow()

	# Base firing
	var fired := super.fire(origin, direction, camera, raycast)

	# Recoil animation
	if tween:
		tween.kill()

	rotation_degrees.x = 0
	tween = create_tween()
	tween.tween_property(self, "rotation_degrees:x", -360.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(self, "_reset_rotation"))

	# Reset damage for next shot
	data.damage = base_dmg
	return fired


func _reset_rotation():
	rotation_degrees.x = 0


func _refresh_upgrades() -> void:
	base_dmg = data.damage
	has_precision = GlobalVariables.has_upgrade(precision)
	has_shield_break = GlobalVariables.has_upgrade(shield_break)
	has_glitch_shot = GlobalVariables.has_upgrade(glitch_shot)
	if not has_glitch_shot:
		shot_tracker = 0
	_update_glitch_glow()


func _update_glitch_glow() -> void:
	# Boosted shot is armed once two shots have landed; it fires (and the
	# glow clears) on the next shot, when shot_tracker rolls back to 0.
	var armed = has_glitch_shot and shot_tracker == 2
	glitch_glow.visible = armed
	weapon_mesh.material_overlay = glow_material if armed else null
	detach_mesh.material_overlay = detach_glow_material if armed else null
	if armed:
		# Charges up fast: the heat surges in over a third of a second
		if glow_tween:
			glow_tween.kill()
		glow_tween = create_tween()
		glow_tween.tween_method(_set_glow_intensity, 0.0, 1.0, GLITCH_RAMP_TIME)


func _set_glow_intensity(value: float) -> void:
	glow_intensity = value
	glow_material.set_shader_parameter("intensity", value)
	detach_glow_material.set_shader_parameter("intensity", value)


# The light on the gun throbs with the heartbeat the shader draws
func _process(delta) -> void:
	super(delta)
	if not glitch_glow.visible:
		return
	var beat := fmod(Time.get_ticks_msec() / 1000.0 * 0.7, 1.0)
	glitch_glow.light_energy = GLITCH_LIGHT_ENERGY * glow_intensity * (0.55 + 0.9 * pow(1.0 - beat, 4.0))
