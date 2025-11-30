extends EnemyBase
class_name EnemyRanged

const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@export var shoot_range: float = 10.0
@export var attack_hysteresis: float = 1.5  # buffer distance before switching back to chase
@export var firing_rate: float = 1.5
@export var energy_ball_scene: PackedScene = preload("res://scenes/enemies/energy_ball.tscn")
@export var firing_target_offset := -0.1

@onready var shoot_timer: Timer = $ShootTimer
@onready var spawn_marker: Marker3D = $EnergyBallSpawnMarker
@onready var vision_area: Area3D = $VisionArea
@onready var debug_sphere := MeshInstance3D.new()


func _ready():
	super()
	shoot_timer.wait_time = firing_rate
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))    
	attack_animation_enter = "Spell_Simple_Enter"
	attack_animation_action = "Spell_Simple_Shoot"
	attack_animation_exit = "Spell_Simple_Exit"

	# Optional — draw sphere only if debug mode is on
	draw_debug_gizmos()


func get_state_definitions() -> Dictionary:
	return {
		"Idle": ENEMY_STATES.IdleState.new(self),
		"Chase": ENEMY_STATES.ChaseState.new(self),
		"Attack": ENEMY_STATES.AttackState.new(self),
		"AttackIdle": ENEMY_STATES.AttackIdleState.new(self),
		"Dead": ENEMY_STATES.DeadState.new(self),
	}


func _on_body_entered(body: Node3D):
	if body == target:
		change_state("Chase")


func _on_body_exited(body: Node3D):
	if body == target:
		change_state("Idle")


func is_in_attack_range() -> bool:
	# Distance check
	if global_position.distance_to(target.global_position) > shoot_range:
		return false
	# LOS check
	return has_line_of_sight_to_player()


func can_attack() -> bool:
	# Distance check
	var dist = global_position.distance_to(target.global_position)
	if dist > shoot_range:
		return false
	# LOS check
	return has_line_of_sight_to_player()


func has_line_of_sight_to_player() -> bool:
	if not is_instance_valid(target):
		return false
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3(0, 1.5, 0)  # eye height
	query.to = target.global_position + Vector3(0, 1.0, 0)  # approximate player center
	query.exclude = [self]
	query.collision_mask = 1  # adjust for walls/obstacles layer
	var result = space_state.intersect_ray(query)
	if not result:
		return true  # nothing in the way
	if result.collider == target:
		return true  # directly hit player
	return false
	
	
func perform_attack():
	var target_pos = target.global_position
	# Keep enemy’s current height (Y)
	target_pos.y = global_position.y
	look_at(target_pos, Vector3.UP, true)

	if not shoot_timer.is_stopped():
		return
	if not attack_start_cooldown.is_stopped():
		return

	anim.play(attack_animation_action)
	var energy_ball_instance = energy_ball_scene.instantiate() as Area3D
	energy_ball_instance.position = spawn_marker.global_position
	energy_ball_instance.transform.basis = spawn_marker.global_basis

	audio_player.play_at(global_position, 
				"assets/audio/sfx/enemies/Enemy_Shoot1_PitchedUp.wav, \
				 assets/audio/sfx/enemies/Enemy_Shoot2_PitchedUp.wav")

	# Set the target for the projectile
	if energy_ball_instance.has_method("set_target"):
		energy_ball_instance.set_target(target)

	get_parent().add_child(energy_ball_instance)
	shoot_timer.start()
	
	
func _on_attack_start_cooldown_timeout() -> void:
	pass
	
	
func draw_debug_gizmos():
	if OS.is_debug_build() and debug:
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = shoot_range
			sphere_mesh.height = shoot_range * 2.0
			sphere_mesh.radial_segments = 24
			sphere_mesh.rings = 16
			debug_sphere.mesh = sphere_mesh

			# Transparent material
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1, 0, 0, 0.1)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			debug_sphere.material_override = mat

			add_child(debug_sphere)
