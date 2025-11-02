extends BaseWeapon

# --- Upgrades ---
var refund = "pistol_ammo_refund"
var piercing = "pistol_piercing"
var lifesteal = "pistol_lifesteal"

var has_ammo_refund = false
var has_piercing = false
var has_lifesteal = false

var refund_chance = 0.10
var health_amount = 5

# --- Recoil Animation Parameters ---
var recoil_angle := -45.0     # How far up the pistol tilts
var recoil_time := 0.1        # How long the kick lasts
var return_time := 0.01       # How long to return to normal

func _ready() -> void:
	super._ready()
	GlobalVariables.upgrade_purchased.connect(on_upgrade_purchased)
	_refresh_upgrades()

func fire(origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	super.fire(origin, _direction, camera, raycast)

	_play_recoil()

	if has_ammo_refund and randf() < refund_chance:
		GlobalVariables.add_ammo("pistol", 10)
		Audio.play("assets/sounds/reload.mp3")
		print("Pistol Ammo Refunded")
	
	if has_lifesteal and randf() < 0.20:
		GlobalVariables.add_health(health_amount)
		print("Pistol Lifesteal Activated: Healed 5 HP")

func _refresh_upgrades() -> void:
	has_ammo_refund = GlobalVariables.has_upgrade(refund)
	has_piercing = GlobalVariables.has_upgrade(piercing)
	has_lifesteal = GlobalVariables.has_upgrade(lifesteal)
	
func on_upgrade_purchased(upgrade_id: String) -> void:
	if upgrade_id == refund:
		has_ammo_refund = true
		print("Pistol Ammo Refund Active")    
	elif upgrade_id == piercing:
		has_piercing = true
		print("Pistol Piercing Active")
	elif upgrade_id == lifesteal:
		has_lifesteal = true
		print("Pistol Lifesteal Active")

# ---------------------------
# Recoil Animation
# ---------------------------
func _play_recoil():
	# Stop any existing recoil tween so rapid shots don’t stack
	if has_node("RecoilTween"):
		get_node("RecoilTween").kill()

	var t := create_tween()

	# Kick upward and move slightly backward using base recoil_offset
	t.tween_property(self, "rotation_degrees:x", recoil_angle, recoil_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "recoil_offset:z", recoil_offset.z - 0.02, recoil_time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Smooth return to neutral
	t.tween_property(self, "rotation_degrees:x", 0.0, return_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "recoil_offset:z", 0.0, return_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
