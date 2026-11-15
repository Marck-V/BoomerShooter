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
		if is_instance_valid(enemy.target) and (enemy.sees_target() or enemy.keeps_fighting()):
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
		# Every other state stops the enemy: a smooth chase starts from standing, facing the way the enemy faces
		heading = Vector3.ZERO
		planned = Vector3.ZERO
		path_size = -1
		# ...and asks for its path straight away, not after the first PATH_UPDATE_INTERVAL spent standing in the sprint
		if enemy.has_method("smooth_chase") and enemy.smooth_chase():
			path_update_timer = PATH_UPDATE_INTERVAL
	
	func update(_delta):
		if not is_instance_valid(enemy.target):
			enemy.change_state("Idle")
			return

		# For ranged enemies: detect if stuck chasing without being able to shoot
		if enemy.get("shoot_range") != null:  # Check if this is a ranged enemy
			stuck_timer += _delta
			if stuck_timer >= STUCK_TIMEOUT:
				if enemy.keeps_fighting():
					stuck_timer = 0.0   # no shot yet, but the fight is on: keep closing in
				else:
					# Been chasing too long with the player out of reach, return to idle and wait for them to come closer
					enemy.change_state("Idle")
					return
		
		# --- Throttled Pathfinding (reduce recalculations) ---
		path_update_timer += _delta
		if path_update_timer >= PATH_UPDATE_INTERVAL:
			path_update_timer = 0.0
			enemy.nav.set_target_position(enemy.chase_destination())
		
		var smooth: bool = enemy.has_method("smooth_chase") and enemy.smooth_chase()
		var dir: Vector3
		if smooth:
			dir = _steer(_delta)
		else:
			var next_pos = enemy.nav.get_next_path_position()
			var raw_dir = (next_pos - enemy.global_position).normalized()

			# --- Smooth direction changes (fixes jitter) ---
			if last_direction == Vector3.ZERO:
				last_direction = raw_dir
			else:
				last_direction = last_direction.lerp(raw_dir, _delta * 8.0)  # Smooth direction blend

			dir = last_direction.normalized()

			# --- Distance-based speed reduction (stop jitter near waypoints) ---
			var distance_to_waypoint = enemy.global_position.distance_to(next_pos)
			var speed_multiplier = clamp(distance_to_waypoint / 2.0, 0.3, 1.0)  # Slow down when close
			# Enemies that pace their own arrival (melee enemies walking to a waiting spot) opt out of the slowdown
			if enemy.has_method("chase_eases_into_waypoints") and not enemy.chase_eases_into_waypoints():
				speed_multiplier = 1.0

			enemy.velocity = dir * enemy.chase_speed() * speed_multiplier
		enemy.should_move = true
		
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
		
		if enemy.chase_faces_target() or (ray_result.size() == 0 and abs(vertical_angle) <= max_vertical_angle):
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
			
			# Faster rotation - increase multiplier (10-15 for snappy turns). The smooth chase uses the frame-rate
			# independent form of the same blend.
			var turn_weight: float = _delta * enemy.rotation_speed * 2.0
			if smooth:
				turn_weight = 1.0 - exp(-_delta * enemy.rotation_speed * 2.0)
			enemy.global_transform.basis = enemy.global_transform.basis.slerp(target_basis, turn_weight)
		
		# Once the agent counts its path as finished (a metre short of the target) avoidance hands back no velocity
		# at all, so the smooth chase moves the last bit itself; avoidance is still told where it is going, so the
		# others keep steering round it
		var last_stretch: bool = smooth and enemy.nav.is_navigation_finished()
		if enemy.nav.avoidance_enabled and not last_stretch:
			enemy.nav.set_velocity(enemy.velocity)
		else:
			if enemy.nav.avoidance_enabled:
				enemy.nav.set_velocity_forced(enemy.velocity)
			enemy._on_velocity_computed(enemy.velocity)
		
		# --- Lunge: enemies that have one use it while closing in from range ---
		if enemy.has_method("should_lunge") and enemy.should_lunge():
			enemy.change_state("Lunge")
			return

		# --- Attack check ---
		if enemy.is_in_attack_range() and enemy.can_start_attack():
			stuck_timer = 0.0  # Reset timer when successfully entering attack
			enemy.change_state("Attack")

	# --- Smooth chase ---
	# Enemies that have smooth_chase() (and its chase_* settings) run like this instead: they speed up and slow down at
	# a set rate rather than going from standing to full speed in one frame, turn along an arc at a set rate (slowing a
	# little in a sharp turn) instead of blending straight to each new direction, and only ease off at the end of the
	# path, not at every corner of it. Returns the direction it is running in, for facing.
	const SMOOTH_SNAP_SPEED := 2.0   # slower than this it turns on the spot: there is no arc to run yet
	const SMOOTH_REACHED := 1.0      # a path point this close (flat) counts as reached
	const SMOOTH_SETTLE_SPEED := 3.0 # m/s it is always pushed down onto the floor with
	const SMOOTH_LIVE_AIM_DISTANCE := 4.0   # this close, the last stretch runs at where the target is now
	var path_index := 0              # the point of the agent's current path it is heading for
	var path_size := -1              # the path it was following (a new one starts again from its first point)
	var path_start := Vector3.ZERO
	var heading := Vector3.ZERO      # flat unit vector: the way it is running
	var planned := Vector3.ZERO      # flat velocity it wants this frame, before crowd avoidance

	func _steer(delta: float) -> Vector3:
		var nav: NavigationAgent3D = enemy.nav
		var aim: Vector3 = nav.get_next_path_position()
		# It keeps its own place on the path, measured flat. The agent only moves on to the next point within a metre
		# of it in 3D, so an enemy standing a little high (just spawned, after a shove) never moves on and runs back
		# to points it has passed.
		var path := nav.get_current_navigation_path()
		if path.size() != path_size or (path.size() > 0 and path[0] != path_start):
			path_size = path.size()
			path_start = path[0] if path.size() > 0 else Vector3.ZERO
			path_index = 0
		var here := Vector2(enemy.global_position.x, enemy.global_position.z)
		while path_index < path.size() - 1:
			var point := Vector2(path[path_index].x, path[path_index].z)
			var after := Vector2(path[path_index + 1].x, path[path_index + 1].z)
			# Close to the point, or already past it along the path
			if here.distance_to(point) < SMOOTH_REACHED or (here - point).dot(after - point) > 0.0:
				path_index += 1
			else:
				break
		if path_index < path.size():
			aim = path[path_index]
		# On the last straight stretch it runs at where it is going now, not where that was when the path was last
		# worked out (up to PATH_UPDATE_INTERVAL ago: a couple of metres behind a running player, which it would slow
		# down for as if it had arrived). That also covers the last metre, which the agent counts as reached early.
		# Only close in: further out the path is followed, so it doesn't cut the corner the last stretch starts at.
		var last_leg := nav.is_navigation_finished()
		if not last_leg and path_index >= path.size() - 1:
			var live: Vector3 = enemy.chase_destination()
			if Vector2(live.x - enemy.global_position.x, live.z - enemy.global_position.z).length() < SMOOTH_LIVE_AIM_DISTANCE:
				last_leg = true
		if last_leg:
			aim = enemy.chase_destination()
		var to_aim: Vector3 = aim - enemy.global_position
		var flat := Vector3(to_aim.x, 0.0, to_aim.z)
		var target_speed: float = enemy.chase_speed()

		if heading == Vector3.ZERO:
			var facing: Vector3 = enemy.global_basis.z   # the enemies' models face +Z
			heading = Vector3(facing.x, 0.0, facing.z).normalized() if Vector2(facing.x, facing.z).length() > 0.01 else Vector3.FORWARD
		if flat.length() < 0.05:
			target_speed = 0.0
		else:
			var desired := flat.normalized()
			# Stepping round something it got stuck on (see EnemyHorde._update_stuck)
			if enemy.has_method("chase_detour") and enemy.chase_detour() != Vector3.ZERO:
				desired = enemy.chase_detour()
			var angle := heading.signed_angle_to(desired, Vector3.UP)
			if planned.length() < SMOOTH_SNAP_SPEED:
				heading = desired
			else:
				var max_turn := deg_to_rad(enemy.chase_turn_rate) * delta
				heading = heading.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn)).normalized()
				target_speed *= lerpf(1.0, enemy.chase_turn_slowdown, clampf(absf(angle) / PI, 0.0, 1.0))

		# Eases off over the last stretch of the whole path (enemies that pace their own arrival opt out)
		if not (enemy.has_method("chase_eases_into_waypoints") and not enemy.chase_eases_into_waypoints()):
			var remaining: float = flat.length() if last_leg else nav.distance_to_target()
			target_speed *= clampf(remaining / enemy.chase_arrive_distance, 0.3, 1.0)

		var wanted := heading * target_speed
		var rate: float = enemy.chase_acceleration if wanted.length() > planned.length() else enemy.chase_deceleration
		planned = planned.move_toward(wanted, rate * delta)
		# Up and down: it follows the rise and fall of the path ahead (measured on the navigation mesh, which sits a little
		# above the floor, so only the difference counts) and is pushed down onto the floor all the time, since enemies
		# have no gravity. Without the push one that started a bit high (spawned, shoved) would stay floating there.
		var map := nav.get_navigation_map()
		var mesh_here := NavigationServer3D.map_get_closest_point(map, enemy.global_position).y
		var grade := clampf((aim.y - mesh_here) / maxf(flat.length(), 0.5), -1.5, 1.5)
		enemy.velocity = planned + Vector3.UP * (grade * planned.length() - SMOOTH_SETTLE_SPEED)
		return heading


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
		
		# Its turn is over: back to the chase, which keeps it near until the next one
		if not enemy.can_start_attack():
			enemy.change_state("Chase")
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
	const DEATH_SPEED := 2.6
	const TOUCHDOWN_TIME := 0.95       # seconds into Death01 when the body reaches the floor
	const HIT_SPRAY_SCALE := 1.0       # blood at the moment of the kill
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
		await enemy.get_tree().create_timer(TOUCHDOWN_TIME / DEATH_SPEED, false).timeout
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
