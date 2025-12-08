extends CharacterBody3D

# --- State machine ---
var state = null
var states = {}

# --- General vars ---
var destroyed: bool = false
var original_material : Material
var shield_material : ShaderMaterial = preload("res://shaders/glass_shader.tres")
var animation_done := false
var just_charged := false
var hit_done := false
var is_attacking := false

# --- Enemy properties ---
@export_category("Basic Attributes")
@export var movement_speed: float = 2.0
@export var health: float = 250.0
@export var target: Node3D                  # Player node to chase
@export var debug := false
@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.2
@export var health_bar : Control

@export_category("Hitbox")
@export var damage_window_start: float = 0.2
@export var damage_window_end: float = 1.2

@export_category("Charge Attack Attributes")
@export var charge_speed: float = 10.0
@export var charge_damage: float = 100.0
@export var charge_duration: float = 0.8
@export var charge_cooldown: float = 4.0
@export var charge_windup_time: float = 1.3
@export var charge_recovery_time: float = 2.1
@export var charge_material: StandardMaterial3D = preload("res://shaders/boss_charge_shader.tres")

# --- Scene references ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"godotman/AnimationPlayer"
@onready var ray: RayCast3D = $HitRaycast
@onready var model = $godotman/godot_rig/Skeleton3D/godot_mesh
@onready var shield = $Shield if has_node("Shield") else null
@onready var attack_timer = $AttackTimer
@onready var charge_timer = $ChargeTimer
@onready var debug_label: Label3D = $DebugLabel
@onready var vision_area = $VisionArea
@onready var footsteps: AudioStreamPlayer3D = $Footsteps
@onready var attack_hitbox: Area3D = $godotman/godot_rig/Skeleton3D/RightHandAttach/RightAttackHitbox


# ---------------------------
#  Lifecycle
# ---------------------------
func _ready():
	states = {
		"Idle": IdleState.new(self),
		"Chase": ChaseState.new(self),
		"Attack": AttackState.new(self),
		"Recovery": RecoveryState.new(self),
		"Dead": DeadState.new(self),
		"Charge": ChargeState.new(self),
	}
	change_state("Idle")
	
	# Init charge shader
	model.mesh = model.mesh.duplicate()
	make_mesh_materials_unique(model)
	if model.get_surface_override_material(0):
		original_material = model.get_surface_override_material(0)
	else:
		original_material = model.mesh.surface_get_material(0)

	model.set_surface_override_material(0, original_material)

	# Init shield
	if shield:
		shield.connect("shield_destroyed", Callable(self, "_on_shield_destroyed"))
		apply_shield_material()

	# Init charge animation logic
	anim.connect("animation_finished", Callable(self, "_on_animation_finished"))
	charge_timer.connect("timeout", Callable(self, "_on_charge_timer_timeout"))
	
	# --- Hitbox setup (NEW) ---
	if attack_hitbox:
		# ensure monitoring is off by default
		attack_hitbox.monitoring = false
		# connect to the body_entered signal so the boss can apply damage
		attack_hitbox.connect("body_entered", Callable(self, "_on_attack_hitbox_body_entered"))
	else:
		if debug:
			print("[Boss] No attack_hitbox found. Using raycast fallback for melee damage.")

	# Init health bar
	if health_bar:
		health_bar.set_max_health(health)
		health_bar.set_health(health)

	if debug_label:
		debug_label.visible = debug

func _physics_process(delta):
	if state and state.has_method("update"):
		state.update(delta)

	# Keep debug label above boss head
	if debug_label:
		var _viewport = get_viewport()
		if _viewport:
			debug_label.look_at(_viewport.get_camera_3d().global_position, Vector3.UP)

func _update_footsteps() -> void:
	# Horizontal movement speed (ignore vertical)
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()

	# Only play footsteps when grounded and moving above a small threshold
	var should_play = is_on_floor() and horizontal_speed > 0.1

	if should_play:
		# Start playing if not already playing
		if not footsteps.playing:
			# If a stream is assigned and it is a looping clip, play() will loop.
			# Otherwise it will play once — that's fine for short step loops.
			footsteps.play()
			if debug:
				print("[Boss] Footsteps started (speed=", horizontal_speed, ")")
	else:
		# Stop if currently playing
		if footsteps.playing:
			footsteps.stop()
			if debug:
				print("[Boss] Footsteps stopped (speed=", horizontal_speed, ")")
				
func _on_vision_area_body_entered(body: Node3D) -> void:
	if body == target and state != states["Dead"]:
		if health_bar:
			health_bar.show_bar()
		change_state("Chase")

func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	# only damage the target and only once per attack
	if body == target and not hit_done:
		if body.has_method("damage"):
			body.damage(damage_to_player)
			if debug:
				print("[Boss] Hitbox: dealt ", damage_to_player, " damage to target")
		hit_done = true

# ---------------------------
#  Attack window / hitbox handling (NEW)
# ---------------------------
func perform_attack() -> void:
	"""
	Performs the attack animation and enables the attack_hitbox only during
	the configured damage window. If no attack_hitbox exists, this function
	does not disable the raycast fallback — AttackState still has a fallback.
	"""
	is_attacking = true  # optional: for your logic if you track this

	# Play the attack animation
	anim.play("attack")
	animation_done = false

	# Optional: play audio similar to your other code
	Audio.play("assets/audio/sfx/boss/Boss_Hit1.wav, \
				assets/audio/sfx/boss/Boss_Hit2.wav, \
				assets/audio/sfx/boss/Boss_Hit3.wav")

	# Wait until window start
	await get_tree().create_timer(damage_window_start).timeout

	# Reset hit flag right before enabling hitbox
	hit_done = false
	if attack_hitbox:
		attack_hitbox.monitoring = true

	# Damage window duration
	var damage_duration = max(0.0, damage_window_end - damage_window_start)
	await get_tree().create_timer(damage_duration).timeout

	if attack_hitbox:
		attack_hitbox.monitoring = false

	# Wait until the animation finishes fully
	await anim.animation_finished

	# Start cooldown
	if attack_timer:
		attack_timer.start(attack_cooldown)

	# allow next attacks
	is_attacking = false


func apply_shield_material():
	$ShieldShader.visible = true
	model.set_surface_override_material(0, shield_material)
	
func remove_shield_material():
	$ShieldShader.visible = false
	model.set_surface_override_material(0, original_material)

func apply_charge_material():
	if model:
		model.set_surface_override_material(0, charge_material)

		if debug:
			print("[Boss] Charge material applied")

func remove_charge_material():
	if model:
		model.set_surface_override_material(0, original_material)

		if debug:
			print("[Boss] Charge material removed.")

func make_mesh_materials_unique(mesh_instance: MeshInstance3D):
	var mesh = mesh_instance.mesh.duplicate()
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		if mat:
			mesh.surface_set_material(i, mat.duplicate())
	mesh_instance.mesh = mesh

func set_charge_glow(active: bool, instant: bool = false):
	var mat = model.get_surface_override_material(0)
	if mat == null:
		return

	var target_emission := 3.0 if active else 0.0
	var target_color := Color(1.0, 0.4, 0.1) if active else Color(0, 0, 0)

	if instant:
		mat.emission_enabled = active
		mat.emission = target_color
		mat.emission_energy_multiplier = target_emission
	else:
		var tween = create_tween()
		tween.tween_property(mat, "emission_energy_multiplier", target_emission, 0.6)
		if active:
			mat.emission_enabled = true
			mat.emission = target_color
		else:
			tween.tween_callback(Callable(self, "_disable_emission_if_inactive"))

func _disable_emission_if_inactive():
	var mat = model.get_surface_override_material(0)
	if mat and mat.emission_energy_multiplier <= 0.1:
		mat.emission_enabled = false

func _on_animation_finished(anim_name: String):
	# Only mark done for attack animation
	if anim_name == "attack":
		animation_done = true
		if debug:
			print("[Boss] Attack animation finished.")

func _on_charge_timer_timeout():
	if debug:
		print("[Boss] Charge cooldown finished — ready to charge again.")

	if state == states["Chase"]:
		change_state("Charge")

# ---------------------------
#  State Management
# ---------------------------
func change_state(state_name: String):
	if not states.has(state_name):
		if debug:
			print("[Boss] Tried to change to unknown state:", state_name)
		return

	if state and state.has_method("exit"):
		state.exit()
		if debug:
			print("[Boss] Exiting state:", get_state_name(state))

	state = states[state_name]
	if state and state.has_method("enter"):
		state.enter()

	# Debug updates
	if debug:
		print("[Boss] Entering state:", state_name)
	if debug_label:
		debug_label.text = "State: %s\nCharge CD: %.2f" % [get_state_name(state), charge_timer.time_left]

func get_state_name(current_state):
	for state_name in states.keys():
		if states[state_name] == current_state:
			return state_name
	return "Unknown"

# ---------------------------
#  Combat + Damage
# ---------------------------
func damage(amount: float, multiplier : float = 1.0):
	print("Received damage: ", amount)
	if shield:
		amount = shield.absorb_damage(amount)
	else:
		amount *= multiplier
	health -= amount
	if health <= 0 and not destroyed:
		change_state("Dead")

	if health_bar:
		health_bar.set_health(health)

func add_shield():
	var shield_scene = preload("res://scenes/enemies/shield.tscn")
	var shield_instance = shield_scene.instantiate()
	add_child(shield_instance)

func _on_shield_destroyed():
	remove_shield_material()


# ---------------------------
#  States
# ---------------------------
class IdleState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.anim.play("idle")
		enemy.velocity = Vector3.ZERO
		if enemy.debug:
			print("[Boss] Idle: Waiting for target...")

	func update(_delta):
		if not enemy.target:
			return


class ChaseState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.anim.play("run")
		if enemy.debug:
			print("[Boss] Started chasing target.")

	func update(_delta):
		# if enemy.debug:
		# 	print("[Boss] Chase: charge timer stopped = %s, time left %s" 
		# 			% [enemy.charge_timer.is_stopped(), snappedf(enemy.charge_timer.time_left, 0.01)])

		if enemy.charge_timer.is_stopped():
			enemy.change_state("Charge")
			return

		enemy.nav.set_target_position(enemy.target.global_position)
		var next_pos = enemy.nav.get_next_path_position()
		var dir = (next_pos - enemy.global_position).normalized()
		enemy.velocity = dir * enemy.movement_speed

		if dir.length() > 0.01:
			var target_look_at = Vector3(enemy.target.global_position.x, enemy.global_position.y, enemy.target.global_position.z) + dir
			enemy.look_at(target_look_at, Vector3.UP, true)
		
		enemy.move_and_slide()
		
		enemy._update_footsteps()

		enemy.ray.force_raycast_update()
		if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
			enemy.change_state("Attack")


class AttackState:
	var enemy
	var used_ray_fallback := false

	func _init(e): enemy = e

	func enter():
		enemy.animation_done = false
		used_ray_fallback = false

		if enemy.debug:
			print("[Boss] Performing attack!")

		# start attack cooldown right away (prevents spam); perform_attack will restart timer once done as well
		if enemy.attack_timer:
			enemy.attack_timer.start(enemy.attack_cooldown)

		# Start the attack sequence (handles damage window if attack_hitbox exists)
		# We don't await here because we want the state update() to keep running while the sequence uses await internally.
		enemy.perform_attack()

	func update(_delta):
		# Fallback: if there's no attack_hitbox, do the raycast-based hit once per attack
		if not enemy.attack_hitbox and not used_ray_fallback:
			if not enemy.target:
				return
			enemy.ray.force_raycast_update()
			if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
				var col = enemy.ray.get_collider()
				if col and col.has_method("damage"):
					col.damage(enemy.damage_to_player)
					used_ray_fallback = true
					if enemy.debug:
						print("[Boss] Ray fallback: dealt", enemy.damage_to_player, "damage to player")

		# Transition out once animation completed (animation_done is set in _on_animation_finished)
		if enemy.animation_done:
			if enemy.debug:
				print("[Boss] Attack animation complete")

			if enemy.just_charged:
				enemy.just_charged = false
				# Remove the charge material when leaving the charge state
				enemy.remove_charge_material()
				# Fade glow down
				enemy.set_charge_glow(false)
				enemy.change_state("Recovery")
			else:
				enemy.change_state("Chase")


class ChargeState:
	var enemy
	var direction = Vector3.ZERO
	var elapsed = 0.0
	var phase = "windup"

	func _init(_enemy): enemy = _enemy

	func enter():
		phase = "windup"
		elapsed = 0.0
		enemy.velocity = Vector3.ZERO

		if enemy.target:
			enemy.nav.set_target_position(enemy.target.global_position)
			direction = (enemy.target.global_position - enemy.global_position).normalized()

		# Apply visual indicator
		enemy.apply_charge_material()

		# Turn on charge glow
		enemy.set_charge_glow(true)
		Audio.play("assets/audio/sfx/boss/Boss_Roar1.wav, \
						assets/audio/sfx/boss/Boss_Roar2.wav")

		# Wind-up animation (temp)
		enemy.anim.play("idle")
		enemy.anim.speed_scale = 0.7

		if enemy.debug:
			print("[Boss] Charge: WIND-UP started!")

	func update(delta):
		elapsed += delta

		match phase:
			"windup":
				# Wait during wind-up before starting the charge
				if elapsed >= enemy.charge_windup_time:
					enemy.anim.speed_scale = 1.0  # reset animation speed
					enemy.anim.play("run")
					phase = "charging"
					elapsed = 0.0

					if enemy.debug:
						print("[Boss] Wind-up complete — CHARGING!")

			"charging":
				enemy.just_charged = true

				# Charge "steering" logic, like Rein from OW
				if enemy.target:
					var to_target = (enemy.target.global_position - enemy.global_position).normalized()
					
					# Adjust how sharply boss turns (smaller = tighter turns)
					var turn_speed = 2.0  # radians per second — tweak to tune responsiveness
					
					# Smoothly rotate the direction vector toward the target
					direction = direction.slerp(to_target, turn_speed * delta).normalized()

				# Apply velocity and movement — KEEP ONLY THIS FOR LINEAR CHARGE
				enemy.velocity = direction * enemy.charge_speed
				enemy.move_and_slide()
				enemy._update_footsteps()

				# Make boss face movement direction — REMOVE TO REMOVE "STEERING"
				var look_point = enemy.global_position + direction
				enemy.look_at(look_point, Vector3.UP)
				enemy.rotate_y(deg_to_rad(180))
				
				# Collision Check
				enemy.ray.force_raycast_update()
				if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
					if enemy.target.has_method("damage"):
						enemy.target.damage(enemy.charge_damage)
						if enemy.debug:
							print("[Boss] Charge hit player — dealt", enemy.charge_damage, "damage.")
					enemy.change_state("Attack")
					return

				if elapsed >= enemy.charge_duration:
					if enemy.debug:
						print("[Boss] Charge duration ended — following up with Attack.")
					enemy.change_state("Attack")
					return
	
	""" If we want charge shader to end immediately after done charging,
		Uncomment this code and modifiy the just_charged logic in AttackState"""
	# func exit():
	# 	# Remove the charge material when leaving the charge state
	# 	enemy.remove_charge_material()

	# 	# Fade glow down
	# 	enemy.set_charge_glow(false)

class RecoveryState:
	var enemy
	var elapsed = 0.0

	func _init(e): enemy = e

	func enter():
		elapsed = 0.0
		enemy.velocity = Vector3.ZERO
		enemy.anim.play("idle") # for the time being

		if enemy.debug:
			print("[Boss] Entering recovery phase after attack.")

	func update(delta):
		elapsed += delta
		if elapsed >= enemy.charge_recovery_time:
			if enemy.debug:
				print("[Boss] Recovery done — starting charge cooldown.")
			
			# Start charge cooldown
			enemy.charge_timer.start(enemy.charge_cooldown)

			enemy.change_state("Chase")


class DeadState:
	var enemy
	func _init(e): enemy = e

	func enter():
		if enemy.debug:
			print("[Boss] Died.")

		Audio.play("assets/audio/sfx/boss/Boss_Death1.wav")
		enemy.destroyed = true
		enemy.velocity = Vector3.ZERO
		enemy.anim.play("die")
		enemy.health_bar.hide_bar()

		await enemy.anim.animation_finished

		GameManager.win()

		
