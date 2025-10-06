extends CharacterBody3D

# --- Enemy properties ---
@export var movement_speed: float = 2.0
@export var shoot_range: float = 10.0
@export var firing_rate: float = 1.5  # seconds between shots
@export var health: int = 100
@export var target: Node3D
@export var firing_target_offset := -0.1

# --- Scene references ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"enemy-humanoid/AnimationPlayer"
@onready var raycast: RayCast3D = $RayCast
@onready var shoot_timer: Timer = $ShootTimer
@onready var spawn_marker: Marker3D = $EnergyBallSpawnMarker
@onready var vision_area: Area3D = $VisionArea

# --- State machine ---
var state = null
var states = {}

# --- General vars ---
var destroyed: bool = false
var energy_ball = load("res://scenes/enemies/energy_ball.tscn")
var death_sound: String = "assets/sounds/enemy_hurt.ogg"

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
	
	shoot_timer.wait_time = firing_rate

func _physics_process(delta):
	if state:
		state.update(delta)

func _on_vision_area_body_entered(body: Node3D) -> void:
	if body == target and state != states["Dead"]:
		change_state("Chase")

func _on_vision_area_body_exited(body: Node3D) -> void:
	if body == target and state != states["Dead"]:
		change_state("Idle")

# ---------------------------
#  State Management
# ---------------------------
func change_state(name: String):
	if not states.has(name): return
	if state and state.has_method("exit"):
		state.exit()
	state = states[name]
	if state and state.has_method("enter"):
		state.enter()

# ---------------------------
#  Combat + Damage
# ---------------------------
func damage(amount: int):
	health -= amount
	if health <= 0 and not destroyed:
		change_state("Dead")

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
		# Do nothing unless vision triggers Chase
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
		# enemy.anim.play("Shoot")  /// UPDATE WHEN SHOOT ANIMATION IS ADDED
		enemy.anim.play("Idle")
		enemy.velocity = Vector3.ZERO

	func update(_delta):
		if not enemy.target:
			enemy.change_state("Idle")
			return
		
		# Face target
		enemy.look_at(Vector3(enemy.target.global_position.x, enemy.global_position.y, enemy.target.global_position.z - enemy.firing_target_offset), Vector3.UP, true)
		
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
		enemy.anim.play("Death")
		enemy.queue_free()
