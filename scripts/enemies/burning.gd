extends Node3D

# Added to an enemy by the flamethrower. Burns for a few seconds after the last hit,
# dealing small damage ticks, with fire on the body and an orange glow. Purely additive:
# it never touches the enemy movement.

const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")

const TICK_TIME := 0.5
const LIGHT_FLICKER_FPS := 12.0
const NORMAL_HEIGHT := 1.75       # a normal enemy's height. Bigger enemies get more, bigger flames from it.
const MAX_FIRE_AMOUNT := 110

var enemy: Node3D
var time_left := 0.0
var damage_per_second := 0.0
var tick_left := TICK_TIME
var fire: GPUParticles3D
var embers: GPUParticles3D
var light: OmniLight3D
var flicker_timer := 0.0
var extinguished := false
var light_scale := 1.0


func _ready() -> void:
	enemy = get_parent() as Node3D
	var texture := FlameParticles.make_texture()

	# Undoes the enemy's own scale, so everything here is in metres. The fire is fitted to its body instead, and
	# wraps around the outside of it: a fire the body's size would be hidden inside the model.
	scale = Vector3.ONE / enemy.global_basis.get_scale()
	var body: Vector2 = enemy.body_size() if enemy.has_method("body_size") else Vector2(0.35, NORMAL_HEIGHT)
	var radius := body.x
	var height := body.y
	var size_scale := sqrt(height / NORMAL_HEIGHT)

	fire = FlameParticles.make_emitter({
		"amount": mini(int(36 * height / NORMAL_HEIGHT * size_scale), MAX_FIRE_AMOUNT),
		"lifetime": 0.6, "texture": texture, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.55 * size_scale, "speed": Vector2(1.2, 2.6), "damping": Vector2(0.0, 0.5),
		"spread": 18.0, "gravity": Vector3(0, 2.5, 0),
		"direction": Vector3.UP, "box": Vector3(radius * 0.9, height * 0.42, radius * 0.9),
		"scale_curve": [Vector2(0.0, 0.7), Vector2(0.3, 1.0), Vector2(1.0, 0.25)],
		"colors": [
			[0.0, Color(1.0, 0.95, 0.72, 0.95)],
			[0.3, Color(1.0, 0.7, 0.32, 0.85)],
			[0.58, Color(1.0, 0.4, 0.13, 0.75)],
			[0.82, Color(0.72, 0.14, 0.05, 0.5)],
		],
	})
	fire.position.y = height * 0.5
	add_child(fire)

	# Square sparks drifting up off the fire
	embers = FlameParticles.make_emitter({
		"amount": mini(int(16 * height / NORMAL_HEIGHT), 40), "lifetime": 1.2, "texture": null, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.045 * size_scale, "speed": Vector2(1.5, 3.2), "damping": Vector2(0.0, 0.5),
		"spread": 30.0, "gravity": Vector3(0, 1.0, 0),
		"direction": Vector3.UP, "box": Vector3(radius, height * 0.45, radius),
		"scale_curve": [Vector2(0.0, 1.0), Vector2(1.0, 0.5)],
		"colors": [
			[0.0, Color(1.0, 0.9, 0.4, 1.0)],
			[0.45, Color(1.0, 0.5, 0.1, 1.0)],
			[0.8, Color(0.8, 0.15, 0.04, 1.0)],
		],
	})
	embers.position.y = height * 0.5
	add_child(embers)

	light_scale = size_scale
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.omni_range = 6.0 * size_scale
	light.light_energy = 3.0 * light_scale
	light.position.y = height * 0.65
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
		light.light_energy = 0.0 if extinguished else randf_range(2.2, 3.8) * light_scale

	if extinguished:
		return

	time_left -= delta
	tick_left -= delta
	if tick_left <= 0.0:
		tick_left += TICK_TIME
		if enemy.has_method("damage_silently"):
			enemy.damage_silently(damage_per_second * TICK_TIME)
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
	get_tree().create_timer(1.0, false).timeout.connect(_finish_extinguish)


func _finish_extinguish() -> void:
	if extinguished and is_inside_tree():
		queue_free()
