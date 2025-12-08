class_name EnemyStates

const DEATH_PARTICLES = preload("res://scenes/enemies/death_particles.tscn")

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
	var last_direction := Vector3.ZERO
	var path_update_timer := 0.0
	var stuck_timer := 0.0  # Track how long we've been chasing without attacking
	const PATH_UPDATE_INTERVAL := 0.2  # Update path every 0.2s instead of every frame
	const STUCK_TIMEOUT := 5.0  # Give up after 5 seconds of chasing
	
	func _init(e):
		enemy = e
	
	func enter():
		enemy.anim.play("Sprint")
		last_direction = Vector3.ZERO
		path_update_timer = 0.0
		stuck_timer = 0.0
	
	func update(_delta):
		if not is_instance_valid(enemy.target):
			return
		
		# For ranged enemies: detect if stuck chasing without being able to shoot
		if enemy.get("shoot_range") != null:  # Check if this is a ranged enemy
			stuck_timer += _delta
			if stuck_timer >= STUCK_TIMEOUT:
				# Been chasing too long, return to idle and wait for player to come closer
				enemy.change_state("Idle")
				return
		
		# --- Throttled Pathfinding (reduce recalculations) ---
		path_update_timer += _delta
		if path_update_timer >= PATH_UPDATE_INTERVAL:
			path_update_timer = 0.0
			enemy.nav.set_target_position(enemy.target.global_position)
		
		var next_pos = enemy.nav.get_next_path_position()
		var raw_dir = (next_pos - enemy.global_position).normalized()
		
		# --- Smooth direction changes (fixes jitter) ---
		if last_direction == Vector3.ZERO:
			last_direction = raw_dir
		else:
			last_direction = last_direction.lerp(raw_dir, _delta * 8.0)  # Smooth direction blend
		
		var dir = last_direction.normalized()
		
		# --- Distance-based speed reduction (stop jitter near waypoints) ---
		var distance_to_waypoint = enemy.global_position.distance_to(next_pos)
		var speed_multiplier = clamp(distance_to_waypoint / 2.0, 0.3, 1.0)  # Slow down when close
		
		enemy.velocity = dir * enemy.movement_speed * speed_multiplier
		
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
		
		# --- Smooth Horizontal rotation ---
		var enemy_pos = enemy.global_position
		enemy_pos.y = 0
		var target_pos = to_target
		target_pos.y = 0
		var forward_dir = (target_pos - enemy_pos)
		
		if forward_dir.length() > 0.001:
			forward_dir = forward_dir.normalized()
			var target_basis = Basis.looking_at(forward_dir, Vector3.UP)
			target_basis = target_basis.rotated(Vector3.UP, deg_to_rad(180))
			
			# Faster rotation - increase multiplier (10-15 for snappy turns)
			enemy.global_transform.basis = enemy.global_transform.basis.slerp(
				target_basis, 
				_delta * enemy.rotation_speed * 2.0  # Multiply by 2-3x for faster rotation
			)
		
		# --- Move enemy ---
		enemy.move_and_slide()
		
		# --- Attack check ---
		if enemy.is_in_attack_range():
			stuck_timer = 0.0  # Reset timer when successfully entering attack
			enemy.change_state("Attack")


# --- Attack (Melee enemies only) ---
class AttackState:
	var enemy
	var enter_animation_playing := false
	
	func _init(e):
		enemy = e
	
	func enter():
		enemy.velocity = Vector3.ZERO
		enter_animation_playing = false
		
		if enemy.attack_animation_enter != "":
			enemy.anim.play(enemy.attack_animation_enter)
			enter_animation_playing = true
	
	func update(_delta):
		if not enemy.target:
			enemy.change_state("Idle")
			return
		
		# Wait for enter animation to finish
		if enter_animation_playing:
			if not enemy.anim.is_playing():
				enter_animation_playing = false
			return
		
		# Don't allow state changes while attack is in progress
		if "is_attacking" in enemy and enemy.is_attacking:
			return
		
		# Player out of range → chase
		if not enemy.is_in_attack_range():
			enemy.change_state("Chase")
			return
		
		# Cooldown still running → wait
		if not enemy.can_attack():
			enemy.change_state("AttackIdle")
			return
		
		# Attack!
		enemy.perform_attack()
	
	func exit():
		enter_animation_playing = false
		if enemy.attack_animation_exit != "":
			enemy.anim.play(enemy.attack_animation_exit)


# --- Ranged Attack (Ranged enemies only) ---
class RangedAttackState:
	var enemy
	
	func _init(e):
		enemy = e
	
	func enter():
		enemy.velocity = Vector3.ZERO
		# Play enter animation and pause on last frame
		if enemy.attack_animation_enter != "":
			enemy.anim.play(enemy.attack_animation_enter)
			await enemy.anim.animation_finished
			# Stay on last frame of enter animation
	
	func update(_delta):
		if not is_instance_valid(enemy.target):
			enemy.change_state("Idle")
			return
		
		# Continuously aim at player (smooth rotation)
		var target_pos = enemy.target.global_position
		target_pos.y = enemy.global_position.y  # Keep horizontal
		var dir_to_player = (target_pos - enemy.global_position).normalized()
		
		if dir_to_player.length() > 0.001:
			var target_basis = Basis.looking_at(dir_to_player, Vector3.UP)
			target_basis = target_basis.rotated(Vector3.UP, deg_to_rad(180))
			enemy.global_transform.basis = enemy.global_transform.basis.slerp(
				target_basis,
				_delta * enemy.rotation_speed * 2.0
			)
		
		# Player left range/LOS → chase to reposition
		if not enemy.is_in_attack_range():
			enemy.change_state("Chase")
			return
		
		# Cooldown ready → shoot
		if enemy.can_attack():
			enemy.perform_attack()
			# Wait for shoot animation to finish, then pause on last frame
			await enemy.anim.animation_finished
	
	func exit():
		if enemy.attack_animation_exit != "":
			enemy.anim.play(enemy.attack_animation_exit)


class AttackIdleState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		if enemy.attack_idle_animation != "":
			enemy.anim.play(enemy.attack_idle_animation)

	func update(_delta):
		# Target lost → back to Idle
		if not enemy.target:
			enemy.change_state("Idle")
			return

		# If player moved out of melee range → Chase again
		if not enemy.is_in_attack_range():
			enemy.change_state("Chase")
			return

		# If cooldown finished → return to Attack state to actually attack again
		if enemy.can_attack():
			enemy.change_state("Attack")
			return


# --- Dead ---
class DeadState:
	var enemy

	func _init(e): enemy = e

	func enter():
		enemy.destroyed = true
		
		# Spawn glitchy particle explosion
		spawn_glitch_particles()
		
		Audio.play_at(enemy.global_position,
						"assets/audio/sfx/enemies/Enemy_Death1.wav,
						assets/audio/sfx/enemies/Enemy_Death2.wav")
		enemy.queue_free()

	func update(_delta):
		pass
	
	func spawn_glitch_particles():
		if !enemy.is_inside_tree():
			return
		
		var particles = DEATH_PARTICLES.instantiate()
		enemy.get_parent().add_child(particles)
		particles.global_position = enemy.global_position + Vector3(0, 1.0, 0)
		particles.emitting = true
