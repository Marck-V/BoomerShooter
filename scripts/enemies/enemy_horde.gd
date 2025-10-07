extends CharacterBody3D

# --- Enemy properties ---
@export var movement_speed: float = 2.0
@export var damage_to_player: float = 50
@export var health: int = 100
@export var target: Node3D                  # Player node to chase
@export var attack_cooldown: float = 1.2
@export var vision_range: float = 10.0      # Detection radius

# --- Scene references ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"enemy-humanoid/AnimationPlayer"
@onready var ray: RayCast3D = $HitRaycast
@onready var bite_timer: Timer = $BiteTimer
@onready var vision_area: Area3D = $VisionArea

# --- State machine ---
var state = null
var states = {}

# --- General vars ---
var destroyed: bool = false

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
	if not states.has(name):
		return
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
