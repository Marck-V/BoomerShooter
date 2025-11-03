class_name EnemyStates

# --- Idle ---
class IdleState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.anim.play("Idle")
		enemy.velocity = Vector3.ZERO

	func update(_delta):
		pass


# --- Chase ---
class ChaseState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.anim.play("Run")

	func update(_delta):
		if not is_instance_valid(enemy.target):
			return

		# --- Pathfinding ---
		enemy.nav.set_target_position(enemy.target.global_position)
		var next_pos = enemy.nav.get_next_path_position()
		var dir = (next_pos - enemy.global_position).normalized()
		enemy.velocity = dir * enemy.movement_speed

		# --- Line-of-sight ---
		var space_state = enemy.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.new()
		query.from = enemy.global_position
		query.to = enemy.target.global_position
		query.collision_mask = 1
		query.exclude = [enemy]
		var ray_result = space_state.intersect_ray(query)

		# --- Vertical angle ---
		var to_player = enemy.target.global_position - enemy.global_position
		var horizontal_dist = Vector2(to_player.x, to_player.z).length()
		var vertical_angle = atan2(to_player.y, horizontal_dist)
		var max_vertical_angle = deg_to_rad(30)

		var to_target: Vector3
		if ray_result.size() == 0 and abs(vertical_angle) <= max_vertical_angle:
			to_target = enemy.target.global_position
		else:
			to_target = enemy.global_position + dir

		# --- Horizontal rotation only ---
		var enemy_pos = enemy.global_position
		enemy_pos.y = 0
		var target_pos = to_target
		target_pos.y = 0

		var forward_dir = (target_pos - enemy_pos)
		if forward_dir.length() > 0.001:  # avoid zero-length vector
			forward_dir = forward_dir.normalized()
			var target_basis = Basis.looking_at(forward_dir, Vector3.UP)
			target_basis = target_basis.rotated(Vector3.UP, deg_to_rad(180))  # optional
			enemy.global_transform.basis = enemy.global_transform.basis.slerp(target_basis, _delta * 5.0)

		# --- Move enemy ---
		enemy.move_and_slide()

		# --- Attack check ---
		if enemy.can_attack():
			enemy.change_state("Attack")


# --- Attack (Shared Across All Enemies) ---
class AttackState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		enemy.anim.play(enemy.attack_animation)

	func update(_delta):
		if not enemy.target:
			enemy.change_state("Idle")
			return

		# If target leaves range, go back to Chase
		if not enemy.can_attack():
			enemy.change_state("Chase")
			return

		# Perform attack
		enemy.perform_attack()

# --- Dead ---
class DeadState:
	var enemy

	func _init(e): enemy = e

	func enter():
		enemy.destroyed = true
		enemy.queue_free()

	func update(_delta):
		pass
