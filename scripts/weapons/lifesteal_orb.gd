extends Area3D

@export var overshield_amount := 8    # overshield the orb gives when it is shot (above full health, it decays)
@export var lifespan := 3.0
@export var fade_time := 0.5
@export var burst_time := 0.4          # seconds it takes to fly out to its spot
@export var min_distance := 1.2        # its spot is somewhere in a sphere round the enemy, between these distances
@export var max_distance := 2.3
@export var clearance := 0.5           # how far it keeps off walls and the floor
@export var bob_height := 0.07

const WORLD_MASK := 2   # Environment: walls, floors and ceilings

var anchor := Vector3.ZERO        # the middle of the sphere (the enemy's chest); left unset, where the orb appears
var has_anchor := false

var age := 0.0
var collected := false
var start_point := Vector3.ZERO
var rest_point := Vector3.ZERO
var started := false


# The orb is the same blue as the enemies' blood: it uses the blood's own colours
const BloodParticles = preload("res://scripts/weapons/blood_particles.gd")

static var _drip_mesh: TubeTrailMesh


func _ready() -> void:
	add_to_group("LifestealOrb")
	_add_drips()


# Droplets fall off the orb and are left behind in the world as it rises, trailing short blue streaks
func _add_drips() -> void:
	if _drip_mesh == null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.use_particle_trails = true
		material.albedo_color = Color(BloodParticles.GLOW_BOOST, BloodParticles.GLOW_BOOST, BloodParticles.GLOW_BOOST)

		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 1.0))
		taper.add_point(Vector2(1.0, 0.0))

		_drip_mesh = TubeTrailMesh.new()
		_drip_mesh.radius = 0.04
		_drip_mesh.radial_steps = 4
		_drip_mesh.sections = 6
		_drip_mesh.section_length = 0.16
		_drip_mesh.section_rings = 2
		_drip_mesh.curve = taper
		_drip_mesh.material = material

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([
		BloodParticles.BLOOD_HEAD,
		BloodParticles.BLOOD_MID,
		BloodParticles.BLOOD_TAIL,
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.14
	process.direction = Vector3.DOWN
	process.spread = 35.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color_ramp = ramp

	var drips := GPUParticles3D.new()
	drips.amount = 18
	drips.lifetime = 0.7
	drips.explosiveness = 0.0
	drips.randomness = 0.6
	drips.fixed_fps = 60
	drips.local_coords = false
	drips.trail_enabled = true
	drips.trail_lifetime = 0.18
	drips.process_material = process
	drips.draw_pass_1 = _drip_mesh
	drips.visibility_aabb = AABB(Vector3(-2, -4, -2), Vector3(4, 5, 4))
	add_child(drips)
	drips.emitting = true


func _process(delta: float) -> void:
	# Its position is only set after it enters the tree, so the spot is picked on the first frame
	if not started:
		started = true
		start_point = global_position
		rest_point = _pick_spot(anchor if has_anchor else start_point)
	age += delta
	if age < burst_time:
		# Bursts out from the enemy, fast at first and settling into its spot
		var k := 1.0 - pow(1.0 - age / burst_time, 3.0)
		global_position = start_point.lerp(rest_point, k)
	else:
		# Then hangs there, bobbing gently
		global_position = rest_point + Vector3(0.0, sin(age * 5.0) * bob_height, 0.0)

	var remaining := lifespan - age
	if remaining <= 0.0:
		queue_free()
	elif remaining <= fade_time:
		scale = Vector3.ONE * (remaining / fade_time)


# A random spot in a sphere round `center` that is clear of walls and the floor: each try is a random direction and
# distance, the line out from the centre is cut short where it meets the level (keeping `clearance` off the surface), and
# a spot that ends up too close to the centre, or with the floor right under it, is dropped for another try
func _pick_spot(center: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for attempt in 10:
		var direction := Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized()
		var spot := center + direction * randf_range(min_distance, max_distance)
		var out := PhysicsRayQueryParameters3D.create(center, spot, WORLD_MASK)
		var hit := space.intersect_ray(out)
		if not hit.is_empty():
			spot = hit["position"] + hit["normal"] * clearance
			if spot.distance_to(center) < min_distance * 0.6:
				continue
		# Keep off the floor and the ceiling at the spot itself
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot, spot + Vector3.DOWN * clearance, WORLD_MASK))
		if not down.is_empty():
			spot.y = down["position"].y + clearance
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot, spot + Vector3.UP * clearance, WORLD_MASK))
		if not up.is_empty():
			continue
		# The way from the orb's start to the spot must be clear too (the lift above can have moved it)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(center, spot, WORLD_MASK)).is_empty():
			continue
		return spot
	# Nowhere good found (a tight corner): float just above the enemy if that is clear, otherwise stay put
	var above := center + Vector3.UP * min_distance
	if space.intersect_ray(PhysicsRayQueryParameters3D.create(center, above + Vector3.UP * clearance, WORLD_MASK)).is_empty():
		return above
	return start_point


func damage(_amount = 0, _multiplier = 1.0) -> void:
	if collected:
		return
	collected = true
	var player := get_tree().get_first_node_in_group("Player")
	if player and player.has_method("add_overshield"):
		player.add_overshield(overshield_amount)
		player.play_heal_flash()
	queue_free()
