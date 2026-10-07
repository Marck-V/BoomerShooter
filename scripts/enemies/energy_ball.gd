extends Area3D

const BloodParticles = preload("res://scripts/weapons/blood_particles.gd")

@onready var mesh_instance_3d = $MeshInstance3D
@onready var collision_shape_3d = $CollisionShape3D
@onready var audio_player: Node3D = $AudioPlayer

@export var SPEED : float = 10.0
@export var damage : float = 10
@export var turn_rate : float = 2.0  # radians per second
@export var target_offset = Vector3(0.0, 1.0, 0.0)

@export var max_scale: float = 2.0
@export var scale_speed: float = 1.0

var scale_progress: float = 0.0
var target: Node3D
var velocity: Vector3


const REFLECT_SPEED_MULT := 1.6
const REFLECT_DAMAGE_MULT := 2.0
const REFLECT_MASK := 2 | 4          # environment + enemy bodies
const REFLECT_COLOR := Color(1.0, 0.85, 0.1)
const REFLECT_HIT_STRENGTH := 3.0     # flinch strength on the enemy a reflected ball lands on
const REFLECT_HIT_FLASH_RADIUS := 1.9 # hit flash radius multiplier
const TRAIL_POINTS := 14
const TRAIL_SPACING := 0.25
const TRAIL_WIDTH := 0.2

var reflected := false
var trail_mesh: ImmediateMesh
var trail_points: Array[Vector3] = []


func _ready():
	velocity = global_transform.basis.z * SPEED
	add_to_group("EnemyProjectile")


# Sends the ball back: it now ignores the player, homes on new_target and hurts enemies
func reflect(new_target: Node3D, direction: Vector3) -> void:
	if reflected:
		return
	reflected = true
	collision_mask = REFLECT_MASK
	SPEED *= REFLECT_SPEED_MULT
	damage *= REFLECT_DAMAGE_MULT
	velocity = direction.normalized() * SPEED
	target = new_target
	$SelfQueueTimer.start()

	var material: Material = mesh_instance_3d.get_active_material(0)
	if material is StandardMaterial3D:
		var tinted := material.duplicate() as StandardMaterial3D
		tinted.albedo_color = REFLECT_COLOR
		tinted.emission = REFLECT_COLOR
		tinted.emission_energy_multiplier = 2.5
		mesh_instance_3d.set_surface_override_material(0, tinted)
	_start_trail()


# Bright ribbon behind the reflected ball, built from its recent positions (world space)
func _start_trail() -> void:
	trail_mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(3.0, 2.4, 0.5)
	var trail := MeshInstance3D.new()
	trail.mesh = trail_mesh
	trail.material_override = material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.top_level = true
	add_child(trail)
	trail.global_transform = Transform3D.IDENTITY
	trail_points.append(global_position)


func _process(_delta: float) -> void:
	if not reflected or trail_mesh == null:
		return
	if trail_points.is_empty() or global_position.distance_to(trail_points[0]) >= TRAIL_SPACING:
		trail_points.push_front(global_position)
		if trail_points.size() > TRAIL_POINTS:
			trail_points.pop_back()
	_rebuild_trail()


func _rebuild_trail() -> void:
	trail_mesh.clear_surfaces()
	var count := trail_points.size()
	if count < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var head := global_position
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var point := head if i == 0 else trail_points[i]
		var next_point := trail_points[i + 1] if i < count - 1 else point
		var previous_point := head if i == 0 else trail_points[i - 1]
		var direction := (previous_point - next_point).normalized()
		if direction.length_squared() < 0.0001:
			direction = Vector3.FORWARD
		var to_camera := (camera.global_position - point).normalized() if camera else Vector3.UP
		var side := direction.cross(to_camera)
		if side.length_squared() < 0.0001:
			side = direction.cross(Vector3.UP)
		var fade := 1.0 - float(i) / float(count - 1)
		side = side.normalized() * TRAIL_WIDTH * fade
		trail_mesh.surface_set_color(Color(1.0, 0.95, 0.5, fade))
		trail_mesh.surface_add_vertex(point - side)
		trail_mesh.surface_set_color(Color(1.0, 0.95, 0.5, fade))
		trail_mesh.surface_add_vertex(point + side)
	trail_mesh.surface_end()


func _physics_process(delta):
	# ----- Projectile Scaling -----
	if scale_progress < 1.0:
		scale_progress = min(scale_progress + scale_speed * delta, 1.0)
		var scale_value = lerp(1.0, max_scale, scale_progress)
		scale = Vector3.ONE * scale_value

	if not is_instance_valid(target):
		global_position += velocity * delta
		return

	# Homing calculation
	var to_target = (target.global_position + target_offset - global_position).normalized()
	var turn_strength = clamp(turn_rate * delta / velocity.length(), 0, 1)
	velocity = velocity.slerp(to_target * SPEED, turn_strength)

	# Move projectile
	global_position += velocity * delta

	# Face direction of travel
	if velocity.length() > 0.01:
		look_at(global_position + velocity.normalized(), Vector3.UP)


func set_target(t: Node3D) -> void:
	target = t


func _on_body_entered(body):
	if reflected:
		if body.is_in_group("Enemy") and body.has_method("damage"):
			var shielded: bool = "shield" in body and body.shield != null and is_instance_valid(body.shield)
			body.damage(damage)
			if body.has_method("hit_flash"):
				body.hit_flash(global_position, REFLECT_HIT_STRENGTH, REFLECT_HIT_FLASH_RADIUS)
			if not shielded:
				BloodParticles.spawn(get_tree(), global_position, velocity, 1.3)
		queue_free()
		return

	if body.is_in_group("Player") and body.has_method("damage"):
		audio_player.play("assets/audio/sfx/enemies/Enemy_ProjectileHit1.wav,
						   assets/audio/sfx/enemies/Enemy_ProjectileHit2.wav")
		body.damage(damage)
	queue_free()


func _on_self_queue_timer_timeout():
	queue_free()
