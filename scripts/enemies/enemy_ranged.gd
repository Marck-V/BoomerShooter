extends EnemyBase
class_name EnemyRanged

const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@export var shoot_range: float = 10.0
@export var firing_rate: float = 1.5
@export var energy_ball_scene: PackedScene = preload("res://scenes/enemies/energy_ball.tscn")
@export var firing_target_offset := -0.1

@onready var shoot_timer: Timer = $ShootTimer
@onready var spawn_marker: Marker3D = $EnergyBallSpawnMarker
@onready var vision_area: Area3D = $VisionArea

func _ready():
	super()
	shoot_timer.wait_time = firing_rate
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))	

	attack_animation = "Idle"

func get_state_definitions() -> Dictionary:
	return {
		"Idle": ENEMY_STATES.IdleState.new(self),
		"Chase": ENEMY_STATES.ChaseState.new(self),
		"Attack": ENEMY_STATES.AttackState.new(self),
		"Dead": ENEMY_STATES.DeadState.new(self),
	}

func _on_body_entered(body: Node3D):
	if body == target:
		change_state("Chase")

func _on_body_exited(body: Node3D):
	if body == target:
		change_state("Idle")

func can_attack() -> bool:
	var dist = global_position.distance_to(target.global_position)
	return dist <= shoot_range

func perform_attack():
	if not shoot_timer.is_stopped():
		return

	var energy_ball_instance = energy_ball_scene.instantiate() as Area3D
	energy_ball_instance.position = spawn_marker.global_position
	energy_ball_instance.transform.basis = spawn_marker.global_basis
	get_parent().add_child(energy_ball_instance)
	shoot_timer.start()
