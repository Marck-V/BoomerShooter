extends CharacterBody3D

# --- Enemy properties ---
@export var movement_speed: float = 2.0
@export var damage_to_player: float = 50
@export var health: int = 100
@export var target: Node3D                  # Player node to chase
@export var attack_cooldown: float = 1.2
@export var vision_range: float = 10.0      # Detection radius
@export var debug := false
@export var give_shield = false
var is_shielded = false
# --- State machine ---
var state = null
var states = {}

# --- General vars ---
var destroyed: bool = false
var original_material : Material
var shield_material : ShaderMaterial = preload("res://shaders/glass_shader.tres")


# --- Scene references ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"enemy-humanoid/AnimationPlayer"
@onready var ray: RayCast3D = $HitRaycast
@onready var bite_timer: Timer = $BiteTimer
@onready var vision_area: Area3D = $VisionArea
@onready var model = $"enemy-humanoid/Armature/Skeleton3D/HumanoidBase_NotOverlapping"

var shield

# ---------------------------
#  Lifecycle
# ---------------------------
func _ready():
	states = {
		"Idle": IdleState.new(self),
		"Chase": ChaseState.new(self),
		"Attack": AttackState.new(self),
		"Dead": DeadState.new(self),
	}
	change_state("Idle")
	
	model.mesh = model.mesh.duplicate()
	make_mesh_materials_unique(model)	
	if model.get_surface_override_material(0):
		original_material = model.get_surface_override_material(0)
	else:
		original_material = model.mesh.surface_get_material(0)

	if give_shield:
		shield = add_shield()
		is_shielded = true

	if shield:
		shield.connect("shield_destroyed", Callable(self, "_on_shield_destroyed"))
		apply_shield_material()

func _physics_process(delta):
	if state and state.has_method("update"):
		state.update(delta)

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

# ---------------------------
#  State Management
# ---------------------------
func change_state(state_name: String):
	if not states.has(state_name):
		return
	if state and state.has_method("exit"):
		state.exit()
	state = states[state_name]
	if state and state.has_method("enter"):
		state.enter()

# ---------------------------
#  Combat + Damage
# ---------------------------
func damage(amount: float, multiplier : float):
	if shield:
		amount = shield.absorb_damage(amount)
	else:
		amount *= multiplier
	health -= amount
	print("Enemy took ", amount, " damage. Remaining HP: ", health)
	if health <= 0 and not destroyed:
		change_state("Dead")

func add_shield():
	var shield_scene = preload("res://scenes/enemies/shield.tscn")
	var shield_instance = shield_scene.instantiate()
	add_child(shield_instance)
	return shield_instance

func _on_shield_destroyed():
	is_shielded = false
	remove_shield_material()

# ---------------------------
#  States
# ---------------------------
class IdleState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.anim.play("Idle")
		enemy.velocity = Vector3.ZERO

	func update(_delta):
		if not enemy.target: return
		var dist = enemy.global_position.distance_to(enemy.target.global_position)
		if dist <= enemy.vision_range:
			enemy.change_state("Chase")

class ChaseState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.anim.play("Run")

	func update(_delta):
		# Continuously update the chase target
		enemy.nav.set_target_position(enemy.target.global_position)
		
		# Get next path point from NavigationAgent
		var next_pos = enemy.nav.get_next_path_position()
		var dir = (next_pos - enemy.global_position).normalized()
		
		# Apply velocity
		enemy.velocity = dir * enemy.movement_speed
		
		# Rotate toward movement direction (if moving)
		if dir.length() > 0.01:
			var target_look_at = Vector3(enemy.target.global_position.x, enemy.global_position.y, enemy.target.global_position.z) + dir
			enemy.look_at(target_look_at, Vector3.UP, true)
		
		# Move
		enemy.move_and_slide()
		
		# Transition: if the raycast hits the player, switch to attack
		enemy.ray.force_raycast_update()
		if enemy.ray.is_colliding() and enemy.ray.get_collider() == enemy.target:
			enemy.change_state("Attack")

class AttackState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.anim.play("Bite")

	func update(_delta):
		if not enemy.target:
			enemy.change_state("Idle")
			return

		# If ray no longer hits, return to chase
		enemy.ray.force_raycast_update()
		if not enemy.ray.is_colliding() or enemy.ray.get_collider() != enemy.target:
			enemy.change_state("Chase")
			return

		# Perform bite if cooldown expired
		if enemy.bite_timer.is_stopped():
			var col = enemy.ray.get_collider()
			if col and col.has_method("damage"):
				col.damage(enemy.damage_to_player)
			enemy.bite_timer.start(enemy.attack_cooldown)

class DeadState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.destroyed = true
		#enemy.anim.play("Death")
		enemy.queue_free()
		
	func update(_delta):
		pass
