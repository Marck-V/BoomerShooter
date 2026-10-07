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
var lifesteal_orb_scene = preload("res://scenes/weapons/lifesteal_orb.tscn")

var max_pierces = 3
var max_distance = 300.0

# --- Shot Feel ---
var kick_pitch := 0.02          # Camera kick upward (radians, ~1.1 degrees)
var kick_yaw := 0.006           # Max random sideways kick (radians)

# --- Recoil Animation Parameters ---
var recoil_angle := -45.0     # How far up the pistol tilts
var recoil_time := 0.1        # How long the kick lasts
var return_time := 0.01       # How long to return to normal

func _ready() -> void:
	super._ready()
	GlobalVariables.upgrade_purchased.connect(on_upgrade_purchased)
	_refresh_upgrades()

func fire(origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	var ammo_before = GlobalVariables.get_ammo("pistol")
	super.fire(origin, _direction, camera, raycast)
	var shot_fired = GlobalVariables.get_ammo("pistol") < ammo_before

	_play_recoil()

	if shot_fired and raycast.is_colliding() and get_hit_enemy(raycast.get_collider()):
		_apply_camera_kick()

	# Handle Upgrades
	if has_piercing:
		_do_piercing_hits(camera, raycast)

	if has_ammo_refund and randf() < refund_chance:
		GlobalVariables.add_ammo("pistol", 10)
		Audio.play("assets/sounds/reload.mp3")
		print("Pistol Ammo Refunded")
	
	if has_lifesteal and randf() < 0.20:
		_spawn_lifesteal_orb(raycast)

func _apply_camera_kick() -> void:
	var player = GlobalVariables.player
	if player and is_instance_valid(player):
		player.apply_camera_kick(kick_pitch, randf_range(-kick_yaw, kick_yaw))


func _spawn_lifesteal_orb(raycast: RayCast3D) -> void:
	if not raycast.is_colliding():
		return

	var collider = raycast.get_collider()
	var hit_enemy = collider is Node and (collider.is_in_group("Enemy") or ("owner_enemy" in collider and collider.owner_enemy))
	if not hit_enemy:
		return

	var orb = lifesteal_orb_scene.instantiate()
	orb.heal_amount = health_amount
	get_tree().current_scene.add_child(orb)
	orb.global_position = raycast.get_collision_point() + Vector3.UP * 0.5


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
			flash_hit_enemy(target, result["position"])
			#print("Pierced enemy: ", target.name)
			damaged.append(target)

		exclude.append(collider)
		hits += 1
		from = result["position"] + dir * 0.1
