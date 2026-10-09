extends Node3D

# Added to an enemy by the flamethrower. Burns for a few seconds after the last hit,
# dealing small damage ticks, with fire on the body and an orange glow. Purely additive:
# it never touches the enemy movement.

const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")

const TICK_TIME := 0.5
const BODY_HEIGHT := 0.9
const LIGHT_FLICKER_FPS := 12.0

var enemy: Node3D
var time_left := 0.0
var damage_per_second := 0.0
var tick_left := TICK_TIME
var fire: GPUParticles3D
var embers: GPUParticles3D
var light: OmniLight3D
var flicker_timer := 0.0
var extinguished := false


func _ready() -> void:
	enemy = get_parent() as Node3D
	var texture := FlameParticles.make_texture()

	fire = FlameParticles.make_emitter({
		"amount": 32, "lifetime": 0.55, "texture": texture,
		"size": 0.5, "speed": Vector2(1.0, 2.2), "damping": Vector2(0.0, 0.5),
		"spread": 25.0, "gravity": Vector3(0, 1.5, 0), "rotate": true,
		"direction": Vector3.UP, "box": Vector3(0.28, 0.7, 0.18),
		"scale_curve": [Vector2(0.0, 0.5), Vector2(0.35, 1.0), Vector2(1.0, 0.3)],
		"colors": [
			[0.0, Color(1.0, 1.0, 1.0, 1.0)],
			[0.35, Color(1.0, 0.85, 0.7, 1.0)],
			[0.6, Color(1.0, 0.62, 0.45, 0.95)],
			[0.82, Color(0.8, 0.38, 0.32, 0.7)],
		],
	})
	fire.position.y = BODY_HEIGHT
	add_child(fire)

	embers = FlameParticles.make_emitter({
		"amount": 8, "lifetime": 0.9, "texture": null, "additive": true,
		"size": 0.03, "speed": Vector2(1.5, 3.0), "damping": Vector2(0.0, 0.0),
		"spread": 35.0, "gravity": Vector3(0, 1.0, 0),
		"direction": Vector3.UP, "box": Vector3(0.25, 0.6, 0.15),
		"scale_curve": [Vector2(0.0, 1.0), Vector2(1.0, 0.3)],
		"colors": [
			[0.0, Color(1.0, 0.9, 0.4, 1.0)],
			[0.5, Color(1.0, 0.5, 0.1, 1.0)],
		],
	})
	embers.position.y = BODY_HEIGHT
	add_child(embers)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.omni_range = 4.5
	light.light_energy = 1.8
	light.position.y = 1.2
	add_child(light)

	fire.emitting = true
	embers.emitting = true


# Called while the flame is on the enemy; keeps it burning and keeps the strongest burn
func ignite(duration: float, dps: float) -> void:
	time_left = maxf(time_left, duration)
	damage_per_second = maxf(damage_per_second, dps)
	if extinguished:
		extinguished = false
		fire.emitting = true
		embers.emitting = true
		light.visible = true


func _process(delta: float) -> void:
	if not is_instance_valid(enemy) or enemy.get("destroyed") == true:
		_extinguish()
		return

	flicker_timer -= delta
	if flicker_timer <= 0.0:
		flicker_timer = 1.0 / LIGHT_FLICKER_FPS
		light.light_energy = 0.0 if extinguished else randf_range(1.2, 2.0)

	if extinguished:
		return

	time_left -= delta
	tick_left -= delta
	if tick_left <= 0.0:
		tick_left += TICK_TIME
		if enemy.has_method("damage"):
			enemy.damage(damage_per_second * TICK_TIME)
	if time_left <= 0.0:
		_extinguish()


func _extinguish() -> void:
	if extinguished:
		return
	extinguished = true
	damage_per_second = 0.0
	fire.emitting = false
	embers.emitting = false
	light.visible = false
	# Stay in the tree briefly so remaining sparks finish; re-igniting cancels the cleanup
	get_tree().create_timer(1.0).timeout.connect(_finish_extinguish)


func _finish_extinguish() -> void:
	if extinguished and is_inside_tree():
		queue_free()
