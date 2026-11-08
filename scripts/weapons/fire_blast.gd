extends RefCounted
class_name FireBlast

# The fireball an enemy goes up in when its burn stacks fill (see enemies/burning.gd): a burst of fire and sparks
# with a flash of light, damage to every other enemy in range (less towards the edge, walls stop it), and burn
# stacks handed to each of them so the fire spreads and they can blow up in turn. It never hurts the player.
#   FireBlast.explode(tree, centre, radius, damage, stacks, source)

const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")

const SOUND := "assets/audio/sfx/impacts/Balloon Explosion B.wav"
const SOUND_PITCH := 0.8
const MAX_CAMERA_SHAKE := 0.25
const BURN_DURATION := 3.0
const BURN_DPS := 6.0
const LIGHT_TIME := 0.3


static func explode(tree: SceneTree, centre: Vector3, radius: float, damage: float, stacks: float, source: Node3D = null) -> void:
	_spawn_effect(tree, centre, radius)
	Audio.play_at(centre, SOUND, SOUND_PITCH)

	var burning_script := load("res://scripts/enemies/burning.gd") as GDScript
	for candidate in tree.get_nodes_in_group("Enemy"):
		var enemy := candidate as Node3D
		if enemy == null or enemy == source or enemy.get("destroyed") == true or not enemy.has_method("damage_silently"):
			continue
		var half_height: float = enemy.body_size().y * 0.5 if enemy.has_method("body_size") else 0.9
		var chest: Vector3 = enemy.global_position + Vector3.UP * half_height
		var distance := centre.distance_to(chest)
		if distance > radius or not _has_clear_line(tree, centre, chest):
			continue
		enemy.damage_silently(damage * Blast.falloff(distance, radius))
		burning_script.apply(enemy, BURN_DURATION, BURN_DPS, stacks)

	var player = GlobalVariables.player
	if is_instance_valid(player) and player.has_method("add_camera_shake"):
		var distance := centre.distance_to(player.global_position + Vector3.UP)
		if distance < radius * 4.0:
			player.add_camera_shake(MAX_CAMERA_SHAKE * (1.0 - distance / (radius * 4.0)))


static func _has_clear_line(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.ENVIRONMENT)
	return tree.root.world_3d.direct_space_state.intersect_ray(query).is_empty()


# A ball of fire pushed out in every direction, a spray of sparks, and a flash of orange-white light
static func _spawn_effect(tree: SceneTree, centre: Vector3, radius: float) -> void:
	var holder := Node3D.new()
	tree.current_scene.add_child(holder)
	holder.global_position = centre
	var texture := FlameParticles.make_texture()

	var fire := FlameParticles.make_emitter({
		"amount": 64, "lifetime": 0.55, "texture": texture, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 1.0, "speed": Vector2(radius * 1.2, radius * 2.4), "damping": Vector2(3.0, 5.0),
		"spread": 180.0, "gravity": Vector3(0, 1.5, 0), "direction": Vector3.UP, "rotate": false,
		"scale_curve": [Vector2(0.0, 0.5), Vector2(0.3, 1.1), Vector2(1.0, 0.3)],
		"colors": [
			[0.0, Color(1.0, 1.0, 0.85, 0.9)],
			[0.25, Color(1.0, 0.75, 0.35, 0.85)],
			[0.55, Color(1.0, 0.4, 0.12, 0.75)],
			[0.8, Color(0.7, 0.13, 0.05, 0.45)],
		],
	})
	var sparks := FlameParticles.make_emitter({
		"amount": 40, "lifetime": 0.9, "texture": null, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.07, "speed": Vector2(radius * 1.5, radius * 3.5), "damping": Vector2(1.0, 3.0),
		"spread": 180.0, "gravity": Vector3(0, -4.0, 0), "direction": Vector3.UP,
		"scale_curve": [Vector2(0.0, 1.0), Vector2(1.0, 0.3)],
		"colors": [
			[0.0, Color(1.0, 0.95, 0.5, 1.0)],
			[0.5, Color(1.0, 0.55, 0.1, 1.0)],
			[0.85, Color(0.8, 0.2, 0.05, 1.0)],
		],
	})
	for emitter in [fire, sparks]:
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		holder.add_child(emitter)
		emitter.emitting = true

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.omni_range = radius * 2.5
	light.light_energy = 10.0
	holder.add_child(light)
	var tween := holder.create_tween()
	tween.tween_property(light, "light_energy", 0.0, LIGHT_TIME)
	tween.tween_interval(1.0)
	tween.tween_callback(holder.queue_free)
