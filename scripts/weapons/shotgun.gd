extends BaseWeapon

@onready var tween := create_tween()

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
	GlobalVariables.upgrade_purchased.connect(on_upgrade_purchased)
	base_dmg = data.damage
	_refresh_upgrades()

func get_shield_multiplier() -> float:
	if has_shield_break:
		return 1.5
	return 1.0

# TODO: Glitch shot damage multipler does NOT deal increased damage to shields.

func fire(origin: Vector3, direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	# Apply glitch shot before firing
	if has_glitch_shot:
		shot_tracker += 1
		if shot_tracker >= 3:
			data.damage *= dmg_multiplier
			print("Glitch Shot Activated! Damage:", data.damage)
			shot_tracker = 0
	else:
		data.damage = base_dmg

	# Now run the base firing logic
	super.fire(origin, direction, camera, raycast)
	
	# Reset rotation / recoil animation
	rotation_degrees.x = 0
	var tween = create_tween()
	tween.tween_property(self, "rotation_degrees:x", -360.0, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(self, "_reset_rotation"))

	# Reset damage after firing so next shot isn't permanently boosted
	data.damage = base_dmg

			
			

func _reset_rotation():
	rotation_degrees.x = 0  # Reset to avoid accumulation

func _refresh_upgrades() -> void:
	has_precision = GlobalVariables.has_upgrade(precision)
	has_shield_break = GlobalVariables.has_upgrade(shield_break)
	has_glitch_shot = GlobalVariables.has_upgrade(glitch_shot)

func on_upgrade_purchased(upgrade_id: String) -> void:
	if upgrade_id == precision:
		has_precision = true
	if upgrade_id == shield_break:
		has_shield_break = true
	if upgrade_id == glitch_shot:
		has_glitch_shot = true
