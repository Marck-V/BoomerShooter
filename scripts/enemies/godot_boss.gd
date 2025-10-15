extends CharacterBody3D

# --- Enemy properties ---
@export_category("Basic Attributes")
@export var movement_speed: float = 2.0
@export var health: float = 250.0
@export var target: Node3D                  # Player node to chase
@export var debug := false
@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.2

@export_category("Charge Attack Attributes")
@export var charge_speed: float = 10.0
@export var charge_damage: float = 100.0
@export var charge_duration: float = 0.8
@export var charge_cooldown: float = 4.0
@export var charge_windup_time: float = 1.3
@export var charge_recovery_time: float = 2.1

# --- State machine ---
var state = null
var states = {}

# --- General vars ---
var destroyed: bool = false
var original_material : Material
var shield_material : ShaderMaterial = preload("res://shaders/glass_shader.tres")
var animation_done := false
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


# ---------------------------
#  Lifecycle
# ---------------------------
func _ready():
	states = {
		"Idle": IdleState.new(self),
		"Chase": ChaseState.new(self),
		"Attack": AttackState.new(self),
		"Dead": DeadState.new(self),
		"Charge": ChargeState.new(self),
	}
	change_state("Idle")
	
	model.mesh = model.mesh.duplicate()
	make_mesh_materials_unique(model)
	if model.get_surface_override_material(0):
		original_material = model.get_surface_override_material(0)
	else:
		original_material = model.mesh.surface_get_material(0)

	if shield:
		shield.connect("shield_destroyed", Callable(self, "_on_shield_destroyed"))
		apply_shield_material()

	anim.connect("animation_finished", Callable(self, "_on_animation_finished"))

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

func _on_vision_area_body_entered(body: Node3D) -> void:
	if body == target and state != states["Dead"]:
		change_state("Chase")

func _on_vision_area_body_exited(body: Node3D) -> void:
	if body == target and state != states["Dead"]:
		change_state("Idle")

func apply_shield_material():
	$ShieldShader.visible = true
	model.set_surface_override_material(0, shield_material)
	
func remove_shield_material():
	$ShieldShader.visible = false
	model.set_surface_override_material(0, original_material)

func make_mesh_materials_unique(mesh_instance: MeshInstance3D):
	var mesh = mesh_instance.mesh.duplicate()
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		if mat:
			mesh.surface_set_material(i, mat.duplicate())
	mesh_instance.mesh = mesh

func _on_animation_finished(anim_name: String):
	# Only mark done for attack animation
	if anim_name == "attack":
		animation_done = true
		if debug:
			print("[Boss] Attack animation finished.")

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
		var format_debug = "State: " + state_name + "\nCharge Timer: %s"
		debug_label.text = format_debug % snappedf(charge_timer.time_left, 0.01)

func get_state_name(current_state):
	for state_name in states.keys():
		if states[state_name] == current_state:
			return state_name
	return "Unknown"

# ---------------------------
#  Combat + Damage
# ---------------------------
func damage(amount: float, multiplier : float):
	print("Received damage: ", amount)
	if shield:
		amount = shield.absorb_damage(amount)
	else:
		amount *= multiplier
	health -= amount
	if health <= 0 and not destroyed:
		change_state("Dead")

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
		# 	print("[Boss] Chase: charge timer stopped =", enemy.charge_timer.is_stopped())

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

		enemy.ray.force_raycast_update()
		if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
			enemy.change_state("Attack")


class AttackState:
	var enemy
	var damage_done = false

	func _init(e): enemy = e

	func enter():
		enemy.animation_done = false
		damage_done = false
		enemy.anim.play("attack")
		if enemy.debug:
			print("[Boss] Performing attack!")
		enemy.attack_timer.start(enemy.attack_cooldown)

	func update(_delta):
		if not enemy.target:
			enemy.change_state("Idle")
			return

		# Only deal damage once during the attack
		if not damage_done:
			enemy.ray.force_raycast_update()
			if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
				var col = enemy.ray.get_collider()
				if col and col.has_method("damage"):
					col.damage(enemy.damage_to_player)
					damage_done = true
					if enemy.debug:
						print("[Boss] Dealt", enemy.damage_to_player, "damage to player.")

		# Wait until the animation finishes before changing state
		if enemy.animation_done:
			if enemy.debug:
				print("[Boss] Attack animation complete — returning to Chase.")
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

		# --- WIND-UP PHASE ---
		# Temporarily use the idle animation to simulate the boss "preparing" to charge.
		# You can later replace this with a custom "charge_windup" or "roar" animation.
		enemy.anim.play("idle")
		enemy.anim.speed_scale = 0.8  # slightly slower to emphasize buildup

		# Start the cooldown so boss can’t charge again immediately after.
		enemy.charge_timer.start(enemy.charge_cooldown)

		# Save the direction towards the player now (so charge goes straight)
		if enemy.target:
			enemy.nav.set_target_position(enemy.target.global_position)
			direction = (enemy.target.global_position - enemy.global_position).normalized()

		if enemy.debug:
			print("[Boss] Entering Charge state — WIND-UP phase.")

	func update(delta):
		elapsed += delta

		match phase:
			"windup":
				# Wait during wind-up before starting the charge
				if elapsed >= enemy.charge_windup_time:
					enemy.anim.speed_scale = 1.0  # reset animation speed
					if enemy.debug:
						print("[Boss] Wind-up complete — CHARGING!")
					enemy.anim.play("run")
					phase = "charging"
					elapsed = 0.0

			"charging":
				enemy.velocity = direction * enemy.charge_speed
				enemy.move_and_slide()

				enemy.ray.force_raycast_update()
				if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
					if enemy.target.has_method("damage"):
						enemy.target.damage(enemy.charge_damage)
						if enemy.debug:
							print("[Boss] Charge hit player — dealt", enemy.charge_damage, "damage.")
					# Immediately follow up with an attack
					enemy.change_state("Attack")
					return

				if elapsed >= enemy.charge_duration:
					if enemy.debug:
						print("[Boss] Charge duration ended — follow-up attack next.")
					enemy.change_state("Attack")
					return

			"recovery":
				# Optional: Add recovery delay after charging (if you want a pause before resuming chase)
				if elapsed >= enemy.charge_recovery_time:
					if enemy.debug:
						print("[Boss] Charge recovery finished. Returning to Chase.")
					enemy.change_state("Chase")


class DeadState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.destroyed = true
		enemy.anim.play("die")
		if enemy.debug:
			print("[Boss] Died and despawned.")
		enemy.queue_free()
		
	func update(_delta):
		pass
