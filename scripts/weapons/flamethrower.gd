extends BaseWeapon

const FlameEffect = preload("res://scripts/weapons/flame_effect.gd")
const Burning = preload("res://scripts/enemies/burning.gd")

const WORLD_MASK := 2
const FLAME_LINGER := 0.16        # seconds the flame keeps burning after the last trigger tick
const TICKS_PER_AMMO := 3         # one ammo unit buys this many damage ticks (10 ticks/sec)
const CONE_BASE_RADIUS := 0.5     # meters, flame width at the nozzle
const CONE_SPREAD := 0.17         # extra meters of width per meter of distance
const TARGET_HEIGHT := 1.0        # aim at the enemy chest, not its feet
const BURN_DURATION := 3.0        # seconds an enemy keeps burning after the flame leaves it
const BURN_DPS := 6.0             # damage per second while burning

var flame: Node3D
var last_fire_msec := -10000
var tick_count := 0
var out_of_fuel := false


func _ready() -> void:
	super._ready()
	flame = FlameEffect.new()
	muzzle_location.add_child(flame)
	_filter_model_nearest()


# PSX look: no texture smoothing on the gun model
func _filter_model_nearest() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if material == null:
				continue
			var copy := material.duplicate() as StandardMaterial3D
			copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh_instance.set_surface_override_material(i, copy)


func _process(delta: float) -> void:
	super._process(delta)
	var burning := (Time.get_ticks_msec() - last_fire_msec) < FLAME_LINGER * 1000.0
	flame.set_burning(burning)


func fire(_origin: Vector3, _direction: Vector3, camera: Camera3D, _raycast: RayCast3D) -> void:
	if !data:
		return

	# Fuel is drained every few ticks so a tank lasts a few seconds of continuous fire
	if tick_count % TICKS_PER_AMMO == 0:
		if not GlobalVariables.spend_ammo(GlobalVariables.current_weapon, 1):
			if not out_of_fuel:
				Audio.play("assets/sounds/empty_gun.mp3")
				out_of_fuel = true
			return
	out_of_fuel = false
	tick_count += 1
	last_fire_msec = Time.get_ticks_msec()
	trigger_recoil()

	_burn_enemies_in_cone(camera)


# The flame is a cone, not a ray: everything in front of the nozzle and in line of sight takes damage
func _burn_enemies_in_cone(camera: Camera3D) -> void:
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := camera.get_world_3d().direct_space_state

	for candidate in get_tree().get_nodes_in_group("Enemy"):
		var enemy := candidate as Node3D
		if enemy == null or not enemy.has_method("damage") or enemy.get("destroyed"):
			continue

		var target := enemy.global_position + Vector3.UP * TARGET_HEIGHT
		var to_target := target - origin
		var along := to_target.dot(forward)
		if along < 0.0 or along > data.max_distance:
			continue
		var off_axis := (to_target - forward * along).length()
		if off_axis > CONE_BASE_RADIUS + along * CONE_SPREAD:
			continue

		var query := PhysicsRayQueryParameters3D.create(origin, target, WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			continue

		enemy.damage(data.damage)
		_ignite(enemy)


# Sets the enemy on fire (or refreshes its burn). A live shield keeps the fire off.
func _ignite(enemy: Node3D) -> void:
	var shield = enemy.get("shield")
	if shield != null and is_instance_valid(shield):
		return
	if enemy.get("destroyed") == true:
		return
	var burning = enemy.get_node_or_null("Burning")
	if burning == null:
		burning = Burning.new()
		burning.name = "Burning"
		enemy.add_child(burning)
	burning.ignite(BURN_DURATION, BURN_DPS)
