extends BaseWeapon

# --- Weapon Upgrades ---
var firerate = "rifle_firerate"
var quickness = "rifle_quickness"

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
	muzzle_flash_size = 0.05
	muzzle_flash_time = 0.06
	muzzle_light_energy = 6.0

	# Create and configure kill-streak timer
	expiration_timer = Timer.new()
	expiration_timer.wait_time = 5.0
	expiration_timer.one_shot = true
	expiration_timer.connect("timeout", Callable(self, "_on_expiration_timeout"))
	add_child(expiration_timer)

	# Listen for all enemy deaths globally
	GlobalVariables.enemy_died.connect(on_enemy_died)

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
