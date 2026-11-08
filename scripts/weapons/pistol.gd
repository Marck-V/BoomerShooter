extends BaseWeapon

# --- Upgrades ---
# 1 Dead Eye:      critical hits (heads, exposed weak points) do extra damage and refund ammo
# 2 Piercing Shot: shots pierce through enemies; after a successful parry the next shot is a Parry Round: double damage
# 3 Malware:       hits sometimes drop an orb; shooting it gives a decaying overshield above full health
var dead_eye = "pistol_dead_eye"
var piercing = "pistol_piercing"
var malware = "pistol_lifesteal"      # (the id predates the rework; kept so saves still match)

var has_dead_eye = false
var has_piercing = false
var has_malware = false

const DEAD_EYE_DAMAGE := 1.5           # extra on top of the hurtbox's own critical multiplier
const DEAD_EYE_REFUND := 2             # ammo back per critical hit
const DEAD_EYE_SOUND := "assets/audio/sfx/weapons/reload.mp3"
const PARRY_ROUND_WINDOW := 4.0        # seconds after a parry that the next shot is a Parry Round
const PARRY_ROUND_DAMAGE := 2.0
const PARRY_ROUND_SOUND := "assets/audio/sfx/impacts/metal_axe_hit.mp3"
const MALWARE_CHANCE := 0.20
var overshield_amount := 8
var malware_orb_scene = preload("res://scenes/weapons/lifesteal_orb.tscn")

const CHARGE_GLOW_SHADER: Shader = preload("res://shaders/player/pistol_charge_glow.gdshader")
const CHARGE_GLOW_RAMP := 0.12        # seconds for the glow to come up when a Parry Round becomes ready
const CHARGE_GLOW_BLINK_TIME := 0.9   # the glow blinks for this long before the window runs out
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh
var charge_glow_material: ShaderMaterial
var charge_fx: PistolChargeFx
var charge_glow_on := false
var charge_glow_tween: Tween

var parry_round_until := 0           # ticks (msec) until which the next shot is a Parry Round
var shot_scale := 1.0                # damage scale of the shot being fired (the Parry Round's double)

var max_pierces = 3
var max_distance = 300.0

# --- Recoil Animation Parameters ---
var recoil_angle := -32.0     # How far up the pistol tilts
var recoil_time := 0.07       # How long the kick up lasts
var return_time := 0.3        # How long it takes to settle back (slow and smooth so it doesn't snap)
var recoil_tween: Tween

func _ready() -> void:
	super._ready()
	_refresh_upgrades()
	GlobalVariables.parry_landed.connect(_on_parry_landed)
	charge_glow_material = ShaderMaterial.new()
	charge_glow_material.shader = CHARGE_GLOW_SHADER
	charge_glow_material.set_shader_parameter("intensity", 0.0)
	# The energy inside the muzzle (core, sparks, light), a little way back inside the barrel
	charge_fx = PistolChargeFx.new()
	charge_fx.position = Vector3(0.0, 0.0, -0.012)
	$MuzzleLocation.add_child(charge_fx)


# While a Parry Round is ready the top of the barrel glows white, blinking as the window runs out
func _process(delta: float) -> void:
	super(delta)
	var msec_left := parry_round_until - Time.get_ticks_msec()
	var round_ready := has_piercing and msec_left > 0
	if round_ready != charge_glow_on:
		charge_glow_on = round_ready
		if charge_glow_tween:
			charge_glow_tween.kill()
		if round_ready:
			weapon_mesh.material_overlay = charge_glow_material
			charge_glow_tween = create_tween()
			charge_glow_tween.tween_method(_set_charge_glow, 0.0, 1.0, CHARGE_GLOW_RAMP)
		else:
			weapon_mesh.material_overlay = null
			_set_charge_glow(0.0)
	if round_ready and msec_left < CHARGE_GLOW_BLINK_TIME * 1000.0:
		_set_charge_glow(0.35 + 0.65 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)))


func _set_charge_glow(value: float) -> void:
	charge_glow_material.set_shader_parameter("intensity", value)
	charge_fx.set_strength(value)


func _on_parry_landed() -> void:
	if has_piercing:
		parry_round_until = Time.get_ticks_msec() + int(PARRY_ROUND_WINDOW * 1000.0)


func fire(origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D) -> bool:
	var parry_round := has_piercing and Time.get_ticks_msec() < parry_round_until
	shot_scale = PARRY_ROUND_DAMAGE if parry_round else 1.0
	# An empty click is only the sound: no recoil or upgrades
	var went_off := super.fire(origin, _direction, camera, raycast)
	if not went_off:
		shot_scale = 1.0
		return false

	_play_recoil()

	if parry_round:
		parry_round_until = 0
		Audio.play(PARRY_ROUND_SOUND, 1.4)
		var player = GlobalVariables.player
		if player and is_instance_valid(player):
			player.add_camera_shake(0.1)

	if has_piercing:
		_do_piercing_hits(camera, raycast)
	shot_scale = 1.0

	if has_malware and randf() < MALWARE_CHANCE:
		_spawn_malware_orb(raycast)
	return true


# Every hit of a shot goes through here for its damage: the Parry Round's double, and Dead Eye's bonus on critical hits
func damage_hit(collider: Object, amount: float, point: Vector3) -> void:
	super.damage_hit(collider, _shot_damage(collider, amount), point)


func _shot_damage(collider: Object, amount: float) -> float:
	amount *= shot_scale
	if has_dead_eye and _is_critical(collider):
		amount *= DEAD_EYE_DAMAGE
		GlobalVariables.add_ammo("pistol", DEAD_EYE_REFUND)
		Audio.play(DEAD_EYE_SOUND, 1.5)
	return amount


# Heads, necks and exposed weak points are hurtboxes with a damage multiplier above 1; a shield in the way is not one
func _is_critical(collider: Object) -> bool:
	if not collider is Node or is_shield_hit(collider):
		return false
	return "multiplier" in collider and collider.multiplier > 1.0


func _spawn_malware_orb(raycast: RayCast3D) -> void:
	if not raycast.is_colliding():
		return

	var collider = raycast.get_collider()
	var hit_enemy = collider is Node and not is_shield_hit(collider) and (collider.is_in_group("Enemy") or ("owner_enemy" in collider and collider.owner_enemy))
	if not hit_enemy:
		return

	var orb = malware_orb_scene.instantiate()
	orb.overshield_amount = overshield_amount
	var enemy = get_hit_enemy(collider)
	if enemy is Node3D:
		orb.anchor = enemy.global_position + Vector3.UP * 1.0     # it flies out to a spot round the enemy's chest
		orb.has_anchor = true
	get_tree().current_scene.add_child(orb)
	orb.global_position = raycast.get_collision_point() + Vector3.UP * 0.5


func _refresh_upgrades() -> void:
	has_dead_eye = GlobalVariables.has_upgrade(dead_eye)
	has_piercing = GlobalVariables.has_upgrade(piercing)
	has_malware = GlobalVariables.has_upgrade(malware)


# Recoil Animation
func _play_recoil():
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()

	# Kicks up fast from wherever it currently is, then eases back down in one smooth motion
	recoil_tween = create_tween()
	recoil_tween.tween_property(self, "rotation_degrees:x", recoil_angle, recoil_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	recoil_tween.tween_property(self, "rotation_degrees:x", 0.0, return_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	if is_shield_hit(first_target):
		return  # shields stop the shot
	if first_target and not first_target.has_method("damage") and first_target.get_parent() and first_target.get_parent().has_method("damage"):
		first_target = first_target.get_parent()

	# The shot is stopped by anything that is not damageable (walls, shields), it only pierces through enemies
	if not first_target or not first_target.has_method("damage"):
		return

	# Tracks enemies, not colliders: one enemy has many hurtboxes and each shot may only hit it once
	var first_enemy = get_hit_enemy(first_target)
	var damaged = [first_enemy if first_enemy else first_target]

	var space_state = get_world_3d().direct_space_state
	var from = hit_pos + dir * 0.1
	var exclude = [first_collider]
	var hits = 0
	var steps = 0

	while hits < max_pierces and steps < 16:
		steps += 1
		var to = from + dir * remaining
		var params = PhysicsRayQueryParameters3D.create(from, to, raycast.collision_mask)
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

		# Walls and shields end the shot
		if not target or not target.has_method("damage") or is_shield_hit(target):
			break

		# A second hurtbox of an enemy that was already hit is skipped without using up a pierce
		var hit_enemy = get_hit_enemy(target)
		var hit_key = hit_enemy if hit_enemy else target
		if not damaged.has(hit_key):
			flash_hit_enemy(target, result["position"])
			target.damage(_shot_damage(collider, data.damage))
			damaged.append(hit_key)
			hits += 1

		exclude.append(collider)
		from = result["position"] + dir * 0.1
