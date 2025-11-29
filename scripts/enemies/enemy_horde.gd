extends EnemyBase
class_name EnemyHorde

const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@onready var ray: RayCast3D = $HitRaycast
@onready var attack_timer: Timer = $AttackCooldown
@onready var vision_area: Area3D = $VisionArea
@onready var attack_hitbox: Area3D = $Enemy_Model/Rig/Skeleton3D/RightHand/RightAttackHitbox
@onready var debug_sphere: MeshInstance3D = MeshInstance3D.new()

@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.533
# Delay damaging player till animation is at the right part
@export var damage_window_start: float = 0
@export var damage_window_end: float = 0
@export var vision_range: float = 10.0

var hit_done := false

func _ready():
	super()
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))
	attack_hitbox.connect("body_entered", Callable(self, "_on_attack_hitbox_body_entered"))

	attack_animation_action = "Sword_Attack"
	
	draw_debug_gizmos()


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
	# Ready to attack if cooldown finished and ray hits player
	ray.force_raycast_update()
	if not ray.is_colliding() or ray.get_collider() != target or not attack_timer.is_stopped():
		return false

	return true


func perform_attack() -> void:
	is_attacking = true

	# Play the attack animation
	anim.play(attack_animation_action)
	
	# Play hit sounds
	audio_player.play("assets/audio/sfx/enemies/Enemy_Hit1.wav, \
					   assets/audio/sfx/enemies/Enemy_Hit2.wav, \
					   assets/audio/sfx/enemies/Enemy_Hit3.wav")

	# Wait until attack animation reaches "hit interval"
	await get_tree().create_timer(damage_window_start).timeout
	attack_hitbox.monitoring = true
	
	# Disable enemy hitbox after "hit interval"
	await get_tree().create_timer(damage_window_start - damage_window_end).timeout
	#

	# Wait until the animation finishes fully
	await anim.animation_finished
	attack_hitbox.monitoring = false
	
	# Start cooldown
	attack_timer.start(attack_cooldown)

	# Allow future attacks
	is_attacking = false


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if body == target and not hit_done:
		if body.has_method("damage"):
			body.damage(damage_to_player)
			
		hit_done = true


func draw_debug_gizmos():
	if OS.is_debug_build() and debug:  # only show in debug mode
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = vision_range
		sphere_mesh.radial_segments = 24
		sphere_mesh.rings = 16
		debug_sphere.mesh = sphere_mesh
		
		# Transparent material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 1, 0, 0.2)  # semi-transparent green
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_sphere.material_override = mat
		
		# Attach sphere to vision_area so it moves with the enemy
		vision_area.add_child(debug_sphere)
		debug_sphere.position = Vector3.ZERO


func _on_attack_cooldown_timeout() -> void:
	hit_done = false
