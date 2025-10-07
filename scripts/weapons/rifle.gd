extends BaseWeapon

var firerate = "rifle_firerate"
var quickness = "rifle_quickness"
var chain_shot = "rifle_chain_shot"

var chain_radius = 8.0
var max_chains = 4
var chain_damage = 50
var chain_cooldown = 2.0


func alt_fire(origin: Vector3, direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	# Only allow alt fire if the player has unlocked the chain shot upgrade
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
			if collider and collider.is_in_group("Enemy") and collider.has_method("damage"):
				collider.damage(data.damage)
				_start_chain_lightning(collider, data.damage * 0.8, 1, [])
			else:
				print("Hit non-enemy:", collider)

			var impact = preload("res://scenes/weapons/impact.tscn").instantiate()
			impact.play("shot")
			get_tree().root.add_child(impact)
			impact.global_position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact.look_at(camera.global_transform.origin, Vector3.UP, true)


func _start_chain_lightning(first_target: Node3D, damage: float, depth: int, visited: Array):
	if depth >= max_chains:
		return
	if not first_target or not first_target.is_in_group("Enemy"):
		return

	var start_pos = first_target.global_position

	if first_target not in visited:
		visited.append(first_target)

	var next_target = _find_next_enemy_sphere(first_target, visited, chain_radius)

	if not next_target:
		return

	var end_pos = next_target.global_position
	_spawn_lightning_arc(start_pos, end_pos)

	if is_instance_valid(next_target) and next_target.has_method("damage") and next_target.is_in_group("Enemy"):
		next_target.damage(damage)

	await get_tree().create_timer(0.1).timeout

	if is_instance_valid(next_target):
		_start_chain_lightning(next_target, damage * 0.8, depth + 1, visited)
	else:
		_continue_chain_from_position(end_pos, damage * 0.8, depth + 1, visited)


func _continue_chain_from_position(position: Vector3, damage: float, depth: int, visited: Array):
	if depth >= max_chains:
		return
	var next_target = _find_next_enemy_from_position(position, visited, chain_radius)
	if next_target:
		_spawn_lightning_arc(position, next_target.global_position)
		if next_target.has_method("damage") and next_target.is_in_group("Enemy"):
			next_target.damage(damage)
		await get_tree().create_timer(0.1).timeout
		_start_chain_lightning(next_target, damage * 0.8, depth + 1, visited)


func _find_next_enemy_sphere(last_target: Node3D, visited: Array, radius: float) -> Node3D:
	var space = get_world_3d().direct_space_state
	var shape_params = PhysicsShapeQueryParameters3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = radius
	shape_params.shape = sphere_shape
	shape_params.transform.origin = last_target.global_position
	shape_params.collide_with_areas = true
	shape_params.collide_with_bodies = true

	var results = space.intersect_shape(shape_params)
	var best: Node3D = null
	var best_d2 := INF

	for r in results:
		var c = r["collider"]
		if not c or c == last_target or c in visited:
			continue
		if not c.is_in_group("Enemy"):
			continue
		if not c.has_method("damage"):
			continue

		var d2 = last_target.global_position.distance_squared_to(c.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = c

	return best


func _find_next_enemy_from_position(pos: Vector3, visited: Array, radius: float) -> Node3D:
	var space = get_world_3d().direct_space_state
	var shape_params = PhysicsShapeQueryParameters3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = radius
	shape_params.shape = sphere_shape
	shape_params.transform.origin = pos
	shape_params.collide_with_bodies = true

	var results = space.intersect_shape(shape_params)
	var best: Node3D = null
	var best_d2 := INF

	for r in results:
		var c = r["collider"]
		if not c or c in visited:
			continue
		if not c.is_in_group("Enemy"):
			continue
		if not c.has_method("damage"):
			continue

		var d2 = pos.distance_squared_to(c.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = c

	return best


func _spawn_lightning_arc(start: Vector3, end: Vector3):
	var mesh_instance = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	mesh_instance.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 1.0)
	mat.emission_energy = 100.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat

	var start_adj = start + Vector3.UP * 1.0
	var end_adj = end + Vector3.UP * 1.0

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start_adj)
	mesh.surface_add_vertex(end_adj)
	mesh.surface_end()

	get_tree().current_scene.add_child(mesh_instance)

	await get_tree().create_timer(0.12).timeout
	mesh_instance.queue_free()
