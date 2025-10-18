extends CharacterBody3D

# --- Enemy properties ---
@export var movement_speed: float = 2.0
@export var shoot_range: float = 10.0
@export var firing_rate: float = 1.5  # seconds between shots
@export var health: int = 100
@export var target: Node3D
@export var firing_target_offset := -0.1

# --- State machine ---
var state = null
var states = {}

# --- General vars ---
var destroyed: bool = false
var energy_ball = preload("res://scenes/enemies/energy_ball.tscn")
var death_sound: String = "assets/sounds/enemy_hurt.ogg"

# --- Shield System ---
var original_material : Material
var shield_material : ShaderMaterial = preload("res://shaders/glass_shader.tres")

# --- Scene references ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"enemy-humanoid/AnimationPlayer"
@onready var raycast: RayCast3D = $RayCast
@onready var shoot_timer: Timer = $ShootTimer
@onready var spawn_marker: Marker3D = $EnergyBallSpawnMarker
@onready var vision_area: Area3D = $VisionArea
@onready var model = $"enemy-humanoid/Armature/Skeleton3D/HumanoidBase_NotOverlapping"
@onready var shield = $Shield if has_node("Shield") else null

# Optional overlay mesh for the shield shader (if used)
@onready var shield_shader_overlay = $ShieldShader if has_node("ShieldShader") else null

# ---------------------------
#  Lifecycle
# ---------------------------
func _ready():
	states = {
		"Idle": IdleState.new(self),
		"Chase": ChaseState.new(self),
		"Shoot": ShootState.new(self),
		"Dead": DeadState.new(self),
	}
	change_state("Idle")
	
	# Initialize shooting
	shoot_timer.wait_time = firing_rate

	# Make mesh materials unique to avoid shared material side effects
	model.mesh = model.mesh.duplicate()
	make_mesh_materials_unique(model)
	
	# Cache original material
	if model.get_surface_override_material(0):
		original_material = model.get_surface_override_material(0)
	else:
		original_material = model.mesh.surface_get_material(0)

	# Initialize shield
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

# ---------------------------
#  Shield Visual Management
# ---------------------------
func apply_shield_material():
	if shield_shader_overlay:
		shield_shader_overlay.visible = true
	model.set_surface_override_material(0, shield_material)
	
func remove_shield_material():
	if shield_shader_overlay:
		shield_shader_overlay.visible = false
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
	if not states.has(state_name): return
	if state and state.has_method("exit"):
		state.exit()
	state = states[state_name]
	if state and state.has_method("enter"):
		state.enter()

# ---------------------------
#  Combat + Damage
# ---------------------------
func damage(amount: int, multiplier: float):
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

func shoot_energy_ball():
	var energy_ball_instance = energy_ball.instantiate() as Area3D
	energy_ball_instance.position = spawn_marker.global_position
	energy_ball_instance.transform.basis = spawn_marker.global_basis
	get_parent().add_child(energy_ball_instance)

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
		pass

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
			enemy.look_at(enemy.global_position + dir, Vector3.UP)
		
		enemy.move_and_slide()
		
		# If within shooting range, switch to Shoot state
		var dist = enemy.global_position.distance_to(enemy.target.global_position)
		if dist <= enemy.shoot_range:
			enemy.change_state("Shoot")

class ShootState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.anim.play("Idle")  # Update when shoot animation is available
		enemy.velocity = Vector3.ZERO

	func update(_delta):
		if not enemy.target:
			enemy.change_state("Idle")
			return
		
		# Face target
		enemy.look_at(
			Vector3(enemy.target.global_position.x, enemy.global_position.y, enemy.target.global_position.z - enemy.firing_target_offset),
			Vector3.UP,
			true
		)
		
		# Out of range? Chase again
		var dist = enemy.global_position.distance_to(enemy.target.global_position)
		if dist > enemy.shoot_range:
			enemy.change_state("Chase")
			return
		
		# Fire if cooldown finished
		if enemy.shoot_timer.is_stopped():
			enemy.shoot_energy_ball()
			enemy.shoot_timer.start()

class DeadState:
	var enemy
	func _init(e): enemy = e

	func enter():
		enemy.destroyed = true
		#enemy.anim.play("Death")
		enemy.queue_free()
		
	func update(_delta):
		pass
