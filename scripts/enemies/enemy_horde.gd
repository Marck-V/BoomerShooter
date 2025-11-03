extends EnemyBase
class_name EnemyHorde

const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.2
@export var vision_range: float = 10.0

@onready var ray: RayCast3D = $HitRaycast
@onready var bite_timer: Timer = $BiteTimer
@onready var vision_area: Area3D = $VisionArea

@onready var debug_sphere: MeshInstance3D = MeshInstance3D.new()

func _ready():
	super()
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))

	attack_animation = "Bite"
	
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
	if not ray.is_colliding() or ray.get_collider() != target:
		return false

	return true


func perform_attack():
	ray.force_raycast_update()

	# Perform bite if cooldown expired
	if bite_timer.is_stopped():
		var col = ray.get_collider()
		if col and col.has_method("damage"):
			col.damage(damage_to_player)
		bite_timer.start(attack_cooldown)


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
