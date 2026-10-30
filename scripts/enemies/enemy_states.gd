class_name EnemyStates

const BLOOD_PARTICLES = preload("res://scripts/weapons/blood_particles.gd")

# --- Idle ---
class IdleState:
	const VISION_CHECK_INTERVAL := 0.25

	var enemy
	var vision_check_timer := 0.0

	func _init(e):
		enemy = e

	func enter():
		enemy.anim.play("Idle")
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		vision_check_timer = 0.0

	func update(delta):
		# body_entered only fires once, so an enemy that went idle with the player already in its vision
		# (a ranged enemy that gave up chasing, or one that was stunned) has to look again
		vision_check_timer += delta
		if vision_check_timer < VISION_CHECK_INTERVAL:
			return
		vision_check_timer = 0.0
		if is_instance_valid(enemy.target) and enemy.sees_target():
			enemy.change_state("Chase")


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
			enemy.change_state("Idle")
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
		
		enemy.should_move = true
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
		
		if enemy.nav.avoidance_enabled:
			enemy.nav.set_velocity(enemy.velocity)
		else:
			enemy._on_velocity_computed(enemy.velocity)
		
		# --- Lunge: enemies that have one use it while closing in from range ---
		if enemy.has_method("should_lunge") and enemy.should_lunge():
			enemy.change_state("Lunge")
			return

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
		enemy.should_move = false
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
		enemy.should_move = false
		# Play the enter animation: it stays on its last frame until the first shot
		if enemy.attack_animation_enter != "":
			enemy.anim.play(enemy.attack_animation_enter)
	
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
			enemy.perform_attack()  # the shoot animation ends on its last frame
	
	func exit():
		if enemy.attack_animation_exit != "":
			enemy.anim.play(enemy.attack_animation_exit)


class AttackIdleState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
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


# --- Dodge (Dodger enemies only): a quick sidestep, perpendicular to the line to the target ---
class DodgeState:
	var enemy
	var dodge_velocity := Vector3.ZERO
	var time_left := 0.0

	func _init(e):
		enemy = e

	func enter():
		time_left = enemy.dodge_duration
		dodge_velocity = enemy.pick_dodge_direction() * enemy.dodge_speed
		DodgeSmear.vanish(enemy, dodge_velocity)
		enemy.should_move = false  # nav avoidance is bypassed: the sidestep moves the body directly

	func update(delta):
		time_left -= delta
		# Keep facing the target while sliding sideways
		if is_instance_valid(enemy.target):
			var to_target: Vector3 = enemy.target.global_position - enemy.global_position
			to_target.y = 0.0
			if to_target.length() > 0.001:
				var target_basis := Basis.looking_at(to_target.normalized(), Vector3.UP).rotated(Vector3.UP, deg_to_rad(180))
				enemy.global_transform.basis = enemy.global_transform.basis.slerp(target_basis, delta * enemy.rotation_speed * 2.0)

		# Ease out over the last part of the step so it doesn't stop dead
		var ease_factor := clampf(time_left / maxf(enemy.dodge_duration * 0.4, 0.001), 0.0, 1.0)
		enemy.velocity = dodge_velocity * ease_factor
		enemy.move_and_slide()

		if time_left <= 0.0:
			enemy.velocity = Vector3.ZERO
			enemy.finish_dodge()

	func exit():
		enemy.velocity = Vector3.ZERO
		enemy.is_dodging = false
		enemy.set_dodge_vanished(false)


# --- Dead ---
# Falls over with Death01 (sped up so a fight keeps its pace). A small spray marks the kill, and when the body
# hits the floor it bursts into a big explosion of blood and is gone. The corpse can't be hit, can't hurt
# anyone and no longer counts as an enemy while it falls. Models without a death clip (the flyer) burst
# straight away.
class DeadState:
	const DEATH_ANIMATION := "Death01"
	const DEATH_SPEED := 1.6
	const TOUCHDOWN_TIME := 0.95       # seconds into Death01 when the body reaches the floor
	const HIT_SPRAY_SCALE := 0.45      # blood at the moment of the kill
	const LANDING_BURST_SCALE := 1.4   # the big explosion when the body lands

	var enemy

	func _init(e): enemy = e

	func enter():
		enemy.destroyed = true
		_stop_fighting()

		if enemy.anim != null and enemy.anim.has_animation(DEATH_ANIMATION) and enemy.is_inside_tree():
			_burst(enemy.global_position + Vector3(0, 1.0, 0), HIT_SPRAY_SCALE)
			_play_death()
		else:
			_burst(enemy.global_position + Vector3(0, 1.0, 0), 1.0)
			_death_sound()
			enemy.queue_free()

	func update(_delta):
		pass

	# The enemy keeps existing for the animation, so it must stop being a target, an attacker or an obstacle
	func _stop_fighting() -> void:
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		enemy.is_attacking = false
		enemy.is_dodging = false
		enemy.set_dodge_vanished(false)  # a dodger that dies mid-dodge reappears as it falls
		if "attack_token" in enemy:
			enemy.attack_token += 1  # cancels a punch or combo that is still running
		enemy.collision_layer = 0
		if enemy.nav != null:
			enemy.nav.avoidance_enabled = false
		for area in enemy.find_children("*", "Area3D", true, false):
			area.set_deferred("collision_layer", 0)
			area.set_deferred("monitorable", false)
			area.set_deferred("monitoring", false)
		enemy.remove_from_group("Enemy")

	func _play_death() -> void:
		_death_sound()
		enemy.anim.speed_scale = DEATH_SPEED
		enemy.anim.play(DEATH_ANIMATION)
		await enemy.get_tree().create_timer(TOUCHDOWN_TIME / DEATH_SPEED).timeout
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			return
		# The body hits the floor and bursts
		_burst(enemy.global_position + Vector3(0, 0.3, 0), LANDING_BURST_SCALE)
		_death_sound()
		enemy.queue_free()

	func _death_sound() -> void:
		if enemy.is_inside_tree():
			Audio.play_at(enemy.global_position,
							"assets/audio/sfx/enemies/Enemy_Death1.wav,
							assets/audio/sfx/enemies/Enemy_Death2.wav")

	func _burst(point: Vector3, amount_scale: float) -> void:
		if enemy.is_inside_tree():
			BLOOD_PARTICLES.spawn_burst(enemy.get_tree(), point, amount_scale, BLOOD_PARTICLES.thickness_for(enemy))
