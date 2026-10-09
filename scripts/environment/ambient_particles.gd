extends Node3D

# Slow neon motes drifting around the player: tiny glowing diamonds that fade in and out,
# stepping through cyan, magenta and yellow. Adds depth and a sense of motion on open walkways.

const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")

const BOX := Vector3(26.0, 9.0, 26.0)

var enable_motes := true
var enable_streaks := true
var particles: GPUParticles3D
var streaks: GPUParticles3D
var outdoors := true
var check_timer := 0.0

# Indoors = most of the sky above the player is blocked. Rays go straight up and at an angle in
# four directions, so a ceiling or roof blocks nearly all of them while a skylight, doorway or an
# open walkway under a lone overhang leaves most of them clear.
const SKY_RAYS := [
	Vector3(0, 1, 0), Vector3(1, 1.4, 0), Vector3(-1, 1.4, 0), Vector3(0, 1.4, 1), Vector3(0, 1.4, -1)]
const SKY_RAY_LENGTH := 60.0
const WORLD_MASK := 2
const BLOCKED_TO_GO_INDOORS := 3     # of 5 rays
const BLOCKED_TO_GO_OUTDOORS := 1    # hysteresis, so standing near an edge doesn't flicker
const CHECK_INTERVAL := 0.2


func _ready() -> void:
	top_level = true
	if enable_motes:
		_build_motes()
	if enable_streaks:
		_build_streaks()


func _build_motes() -> void:
	particles = FlameParticles.make_emitter({
		"amount": 110, "lifetime": 7.0, "texture": null, "additive": true,
		"size": 0.14, "speed": Vector2(0.2, 0.9), "damping": Vector2(0.0, 0.0),
		"spread": 180.0, "gravity": Vector3(0, 0.12, 0),
		"direction": Vector3.UP, "box": BOX,
		"scale_curve": [Vector2(0.0, 0.0), Vector2(0.12, 1.0), Vector2(0.85, 1.0), Vector2(1.0, 0.0)],
		"colors": [
			[0.0, Color(0.3, 0.9, 1.0, 1.0)],
			[0.33, Color(1.0, 0.3, 0.85, 1.0)],
			[0.66, Color(1.0, 0.85, 0.3, 1.0)],
		],
	})
	var process := particles.process_material as ParticleProcessMaterial
	process.angle_min = 45.0       # squares turned into diamonds
	process.angle_max = 45.0
	particles.visibility_aabb = AABB(-BOX - Vector3(10, 10, 10), (BOX + Vector3(10, 10, 10)) * 2.0)
	particles.preprocess = 7.0     # already full of motes when the level starts
	particles.emitting = true
	add_child(particles)


# Thin wind streaks sweeping past, stretched along their direction of travel
func _build_streaks() -> void:
	streaks = FlameParticles.make_emitter({
		"amount": 45, "lifetime": 1.4, "texture": null, "additive": true,
		"size": 0.05, "speed": Vector2(20.0, 30.0), "damping": Vector2(0.0, 0.0),
		"spread": 2.0, "gravity": Vector3.ZERO,
		"direction": Vector3(1.0, 0.0, 0.0), "box": BOX,
		"scale_curve": [Vector2(0.0, 0.0), Vector2(0.15, 1.0), Vector2(0.8, 1.0), Vector2(1.0, 0.0)],
		"colors": [[0.0, Color(0.8, 0.95, 1.0, 0.55)]],
	})
	# A thin bar lying along X (the direction every streak travels) instead of a camera-facing quad
	var bar := BoxMesh.new()
	bar.size = Vector3(3.2, 0.04, 0.04)
	var quad := streaks.draw_pass_1 as QuadMesh
	var material := quad.material.duplicate() as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	bar.material = material
	streaks.draw_pass_1 = bar
	streaks.visibility_aabb = AABB(-BOX - Vector3(40, 10, 40), (BOX + Vector3(40, 10, 40)) * 2.0)
	streaks.preprocess = 1.4
	streaks.emitting = true
	add_child(streaks)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		global_position = camera.global_position
		check_timer -= delta
		if check_timer <= 0.0 and streaks:
			check_timer = CHECK_INTERVAL
			_update_outdoors(camera.global_position)


func _update_outdoors(origin: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var blocked := 0
	for direction: Vector3 in SKY_RAYS:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * SKY_RAY_LENGTH, WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			blocked += 1
	if outdoors and blocked >= BLOCKED_TO_GO_INDOORS:
		outdoors = false
	elif not outdoors and blocked <= BLOCKED_TO_GO_OUTDOORS:
		outdoors = true
	streaks.emitting = outdoors
