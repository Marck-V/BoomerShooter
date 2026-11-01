extends GodotBoss
class_name EnemyBrute

# A big, slow, tough enemy: the boss's robot and its brawler moves (swing, charge, shockwave slam), without the fight
# around them. It has one phase and no entrance, and dying is an ordinary enemy's death. Its charge ignores ledges,
# since enemies have no gravity, so place it on floors with walls around them.

const BLOOD_BURST_SCALE := 1.2


func get_state_definitions() -> Dictionary:
	var definitions := super()
	definitions["Dead"] = BruteDeadState.new(self)
	return definitions


# Its roars come from where it stands, unlike the boss's, which fill the arena
func play_sfx(paths: String) -> void:
	Audio.play_at(global_position, paths)


# Not the boss's death: other enemies live on, the wave is told and the level goes on
func _die() -> void:
	if destroyed:
		return
	GlobalVariables.enemy_died.emit(self)
	change_state("Dead")


class BruteDeadState extends GodotBoss.BossState:
	func enter() -> void:
		enemy.destroyed = true
		enemy.invulnerable = true
		enemy.velocity = Vector3.ZERO
		enemy.is_attacking = false
		enemy.set_shake(0.0)
		enemy.set_glow(false)
		enemy.remove_charge_material()
		enemy.collision_layer = 0
		for area in enemy.find_children("*", "Area3D", true, false):
			area.set_deferred("collision_layer", 0)
			area.set_deferred("monitorable", false)
			area.set_deferred("monitoring", false)
		enemy.remove_from_group("Enemy")
		enemy.play_sfx("assets/audio/sfx/boss/Boss_Death1.wav")
		enemy.anim.speed_scale = 1.5
		enemy.anim.play("die")
		_finish()

	func _finish() -> void:
		await enemy.anim.animation_finished
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			return
		BLOOD_PARTICLES.spawn_burst(enemy.get_tree(), enemy.global_position + Vector3.UP * enemy.unit() * 0.5, BLOOD_BURST_SCALE, enemy.blood_scale)
		enemy.queue_free()
