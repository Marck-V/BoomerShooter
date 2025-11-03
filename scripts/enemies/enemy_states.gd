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

	func _init(e): enemy = e

	func enter():
		enemy.anim.play("Run")

	func update(_delta):
		if not enemy.target: return

		# Pathfinding toward target
		enemy.nav.set_target_position(enemy.target.global_position)
		var next_pos = enemy.nav.get_next_path_position()
		var dir = (next_pos - enemy.global_position).normalized()
		enemy.velocity = dir * enemy.movement_speed

		if dir.length() > 0.01:
			var target_look_at = Vector3(enemy.target.global_position.x, 
							enemy.global_position.y, 
							enemy.target.global_position.z) + dir
			enemy.look_at(target_look_at, Vector3.UP, true)

		enemy.move_and_slide()

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

	func update(delta):
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
