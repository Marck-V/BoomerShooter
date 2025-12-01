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

var max_pierces = 3
var max_distance = 300.0

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

	# Handle Upgrades
	if has_piercing:
		_do_piercing_hits(camera, raycast)

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


# Recoil Animation
func _play_recoil():
	if has_node("RecoilTween"):
		get_node("RecoilTween").kill()

	var t := create_tween()

	t.tween_property(self, "rotation_degrees:x", recoil_angle, recoil_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "recoil_offset:z", recoil_offset.z - 0.02, recoil_time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	t.tween_property(self, "rotation_degrees:x", 0.0, return_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "recoil_offset:z", 0.0, return_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _do_piercing_hits(camera: Camera3D, raycast: RayCast3D) -> void:
	if not raycast.is_colliding():
		return

	var first_collider = raycast.get_collider()
	var hit_pos = raycast.get_collision_point()
	var cam_origin = camera.global_transform.origin
	var dir = (hit_pos - cam_origin).normalized()

	var traveled = cam_origin.distance_to(hit_pos)
	var remaining = data.max_distance - traveled
	if remaining <= 0:
		return

	var first_target = first_collider
	if first_target and not first_target.has_method("damage") and first_target.get_parent() and first_target.get_parent().has_method("damage"):
		first_target = first_target.get_parent()

	var damaged = []
	if first_target:
		damaged.append(first_target)

	var space_state = get_world_3d().direct_space_state
	var from = hit_pos + dir * 0.1
	var exclude = [first_collider]
	var hits = 0

	while hits < max_pierces:
		var to = from + dir * remaining
		var params = PhysicsRayQueryParameters3D.create(from, to)
		params.exclude = exclude
		params.collide_with_areas = true
		params.collide_with_bodies = true

		var result = space_state.intersect_ray(params)
		if result.is_empty():
			break

		var collider = result["collider"]
		var target = collider

		if target and not target.has_method("damage") and target.get_parent() and target.get_parent().has_method("damage"):
			target = target.get_parent()

		if target and target.has_method("damage") and not damaged.has(target):
			target.damage(data.damage)
			print("Pierced enemy: ", target.name)
			damaged.append(target)

		exclude.append(collider)
		hits += 1
		from = result["position"] + dir * 0.1
