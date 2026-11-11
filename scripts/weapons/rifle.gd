extends BaseWeapon

# --- Weapon Upgrades ---
var firerate = "rifle_firerate"
var quickness = "rifle_quickness"
var conductor = "rifle_conductor"

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
# Conductor Rounds: every rifle hit plants a spike (see EnemyBase.add_spike); other weapons set them off
# ---------------------------
func damage_hit(collider: Object, amount: float, point: Vector3) -> void:
	var enemy = get_hit_enemy(collider)
	if enemy == null or is_shield_hit(collider) or not GlobalVariables.has_upgrade(conductor) \
			or not enemy.has_method("add_spike"):
		super.damage_hit(collider, amount, point)
		return
	enemy.spiking = true
	super.damage_hit(collider, amount, point)
	enemy.spiking = false
	enemy.add_spike(point)


# ---------------------------
# Quickness / Kill Streak
# ---------------------------
func on_enemy_died(enemy: Node3D):
	# Only count kills made with the rifle
	if GlobalVariables.current_weapon != "rifle":
		return
	# Kills during a boost don't count toward the next one
	if quickness_active:
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
	Audio.play("assets/audio/sfx/weapons/zoom.mp3")
	GlobalVariables.quickness_active.emit()
	quickness_active = true

	if GlobalVariables.player:
		GlobalVariables.player.speed_multiplier = quickness_boost_mult

	var timer := get_tree().create_timer(quickness_duration, false)
	timer.timeout.connect(func():
		if GlobalVariables.player:
			GlobalVariables.player.speed_multiplier = 1.0
		quickness_active = false
		GlobalVariables.quickness_ended.emit()
		print("Quickness boost ended.")
	)
