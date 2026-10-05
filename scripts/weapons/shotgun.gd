extends BaseWeapon

@onready var glitch_glow: OmniLight3D = $GlitchGlow
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh
@onready var detach_mesh: MeshInstance3D = $"WeaponMesh/Shotgun-Detach"
var glow_material: StandardMaterial3D

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
	glow_material = StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_material.albedo_color = Color(1.0, 0.1, 0.1, 0.6)
	GlobalVariables.upgrade_purchased.connect(on_upgrade_purchased)
	base_dmg = data.damage
	_refresh_upgrades()


func get_shield_multiplier() -> float:
	if has_shield_break:
		return 1.5
	return 1.0


func fire(origin: Vector3, direction: Vector3, camera: Camera3D, raycast: RayCast3D):
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
	super.fire(origin, direction, camera, raycast)

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


func _reset_rotation():
	rotation_degrees.x = 0


func _refresh_upgrades() -> void:
	has_precision = GlobalVariables.has_upgrade(precision)
	has_shield_break = GlobalVariables.has_upgrade(shield_break)
	has_glitch_shot = GlobalVariables.has_upgrade(glitch_shot)
	_update_glitch_glow()


func on_upgrade_purchased(upgrade_id: String) -> void:
	if upgrade_id == precision:
		has_precision = true
	if upgrade_id == shield_break:
		has_shield_break = true
	if upgrade_id == glitch_shot:
		has_glitch_shot = true
	_update_glitch_glow()


func _update_glitch_glow() -> void:
	# Boosted shot is armed once two shots have landed; it fires (and the
	# glow clears) on the next shot, when shot_tracker rolls back to 0.
	var armed = has_glitch_shot and shot_tracker == 2
	glitch_glow.visible = armed
	var overlay = glow_material if armed else null
	weapon_mesh.material_overlay = overlay
	detach_mesh.material_overlay = overlay
