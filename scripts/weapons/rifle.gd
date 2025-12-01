extends BaseWeapon

# --- Weapon Upgrades ---
var firerate = "rifle_firerate"
var quickness = "rifle_quickness"
var chain_shot = "rifle_chain_shot"

# --- Chain Lightning Parameters ---
var chain_radius = 8.0
var max_chains = 4
var chain_damage = 50
var chain_cooldown = 2.0

# --- Quickness Buff Parameters ---
var enemies_killed: int = 0
var expiration_timer: Timer
var quickness_active: bool = false
var quickness_boost_mult: float = 2.0
var quickness_duration: float = 3.0

# ---------------------------
# Lifecycle
# ---------------------------
func _ready():
	super._ready()

	# Create and configure kill-streak timer
	expiration_timer = Timer.new()
	expiration_timer.wait_time = 5.0
	expiration_timer.one_shot = true
	expiration_timer.connect("timeout", Callable(self, "_on_expiration_timeout"))
	add_child(expiration_timer)

	# Listen for all enemy deaths globally
	GlobalVariables.enemy_died.connect(on_enemy_died)

# ---------------------------
# Alt Fire (Chain Lightning)
# ---------------------------
func alt_fire(origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	if not GlobalVariables.has_upgrade(chain_shot):
		print("Alt fire unavailable — upgrade not unlocked.")
		return
	if !data or !raycast:
		return
	if not GlobalVariables.spend_ammo(GlobalVariables.current_weapon, 10):
		return

	Audio.play(data.sound)
	muzzle.play("default")
	trigger_recoil()

	for i in range(data.shot_count):
		var x_spread = deg_to_rad(randf_range(-data.spread, data.spread))
		var y_spread = deg_to_rad(randf_range(-data.spread, data.spread))

		var base_dir = -camera.global_transform.basis.z.normalized()
		var dir = base_dir.rotated(camera.global_transform.basis.x, y_spread)
		dir = dir.rotated(camera.global_transform.basis.y, x_spread)

		raycast.target_position = raycast.to_local(raycast.global_transform.origin + dir * data.max_distance)
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collider = raycast.get_collider()

			if collider and collider.has_method("damage"):
				collider.damage(data.damage)

				var chain_target = collider
				if collider.owner_enemy:
					chain_target = collider.owner_enemy

				if chain_target:
					_start_chain_lightning(chain_target, data.damage * 0.8, 1, [])

			else:
				print("Hit non-enemy:", collider)

			var impact = preload("res://scenes/weapons/impact.tscn").instantiate()
			impact.play("shot")
			get_tree().root.add_child(impact)
			impact.global_position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact.look_at(camera.global_transform.origin, Vector3.UP, true)

# ---------------------------
# Chain Lightning
# ---------------------------
func _start_chain_lightning(first_target: Node3D, damage: float, depth: int, visited: Array):
	if depth >= max_chains:
		return
	if not first_target:
		return

	var enemy = first_target
	if "owner_enemy" in first_target and first_target.owner_enemy:
		enemy = first_target.owner_enemy
	if not is_instance_valid(enemy):
		return

	var start_pos = enemy.global_position
	if enemy not in visited:
		visited.append(enemy)

	var next_target = _find_next_enemy_sphere(enemy, visited, chain_radius)
	if not next_target:
		return

	var end_pos = next_target.global_position
	_spawn_lightning_arc(start_pos, end_pos)

	if is_instance_valid(next_target) and next_target.has_method("damage"):
		next_target.damage(damage, 1)

	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(next_target):
		print("Chaining to:", next_target.name, " | Depth:", depth, " | Damage:", damage * 0.8)
		_start_chain_lightning(next_target, damage * 0.8, depth + 1, visited)
	else:
		_continue_chain_from_position(end_pos, damage * 0.8, depth + 1, visited)

func _continue_chain_from_position(chain_position: Vector3, damage: float, depth: int, visited: Array):
	if depth >= max_chains:
		return
	var next_target = _find_next_enemy_from_position(chain_position, visited, chain_radius)
	if next_target:
		_spawn_lightning_arc(chain_position, next_target.global_position)
		if next_target.has_method("damage"):
			next_target.damage(damage, 1)
		await get_tree().create_timer(0.1).timeout
		_start_chain_lightning(next_target, damage * 0.8, depth + 1, visited)

func _find_next_enemy_sphere(last_target: Node3D, visited: Array, radius: float) -> Node3D:
	var space = get_world_3d().direct_space_state
	var params = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	params.shape = sphere
	params.transform.origin = last_target.global_position
	params.collide_with_areas = true
	params.collide_with_bodies = true

	var results = space.intersect_shape(params)
	var best: Node3D = null
	var best_d2 := INF

	for r in results:
		var c = r["collider"]
		if not c or c == last_target or c in visited:
			continue
		var target = c
		if "owner_enemy" in c and c.owner_enemy:
			target = c.owner_enemy
		if target in visited or not target.has_method("damage") or target.is_in_group("Player"):
			continue
		var d2 = last_target.global_position.distance_squared_to(target.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = target
	return best

func _find_next_enemy_from_position(pos: Vector3, visited: Array, radius: float) -> Node3D:
	var space = get_world_3d().direct_space_state
	var params = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	params.shape = sphere
	params.transform.origin = pos
	params.collide_with_bodies = true

	var results = space.intersect_shape(params)
	var best: Node3D = null
	var best_d2 := INF

	for r in results:
		var c = r["collider"]
		if not c or c in visited:
			continue
		var target = c
		if "owner_enemy" in c and c.owner_enemy:
			target = c.owner_enemy
		if target in visited or not target.has_method("damage"):
			continue
		var d2 = pos.distance_squared_to(target.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = target
	return best

func _spawn_lightning_arc(start: Vector3, end: Vector3):
	var mesh_instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh_instance.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lightning.gdshader")
	mat.set_shader_parameter("glow_strength", 60.0)
	mesh_instance.material_override = mat
	get_tree().current_scene.add_child(mesh_instance)

	var height_offset := Vector3(0, 1.0, 0)
	start += height_offset
	end += height_offset

	var segment_count := 10
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(segment_count + 1):
		var t := float(i) / float(segment_count)
		var pos := start.lerp(end, t)
		var offset := Vector3(
			randf_range(-0.2, 0.2),
			randf_range(-0.2, 0.2),
			randf_range(-0.2, 0.2)
		)
		mesh.surface_add_vertex(pos + offset)
	mesh.surface_end()

	var tween := create_tween()
	tween.tween_property(mat, "shader_parameter/glow_strength", 0.0, 0.2)
	tween.tween_callback(Callable(mesh_instance, "queue_free"))

# ---------------------------
# Quickness / Kill Streak
# ---------------------------
func on_enemy_died(enemy: Node3D):
	# Only count kills made with the rifle
	if GlobalVariables.current_weapon != "rifle":
		return

	enemies_killed += 1
	print("Enemy killed with rifle:", enemy.name, " | Total killed:", enemies_killed)

	expiration_timer.start()

	if enemies_killed >= 3 and not quickness_active:
		activate_quickness_boost()
		enemies_killed = 0
		expiration_timer.stop()


func _on_expiration_timeout():
	print("Kill streak expired — counter reset.")
	enemies_killed = 0
	
func activate_quickness_boost():
	if not GlobalVariables.has_upgrade(quickness):
		return
	if quickness_active:
		return

	print("Quickness boost activated!")
	Audio.play("assets/sounds/zoom.mp3")
	GlobalVariables.quickness_active.emit()
	quickness_active = true

	# Directly modify the player's base movement speed
	if GlobalVariables.player:
		GlobalVariables.player.current_movement_speed *= quickness_boost_mult

	print("Player speed increased to:", GlobalVariables.player.current_movement_speed)
	var timer := get_tree().create_timer(quickness_duration)
	timer.timeout.connect(func():
		if GlobalVariables.player:
			GlobalVariables.player.current_movement_speed /= quickness_boost_mult
		quickness_active = false
		GlobalVariables.quickness_ended.emit()
		print("Quickness boost ended.")
	)
