extends Node3D

# PSX-style flamethrower fire hanging off the muzzle (which points along +Z).
# Dense chunky puffs, hot yellow/white with orange edges, plus flickering lights that
# throw orange light on whatever the flame is pointed at.

const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")

const LIGHT_FLICKER_FPS := 12.0

var flame: GPUParticles3D
var licks: GPUParticles3D
var smoke: GPUParticles3D
var embers: GPUParticles3D
var flare: GPUParticles3D
var pilot: GPUParticles3D
var lights: Array[OmniLight3D] = []
var light_energies: Array[float] = []
var burning := false
var flicker_timer := 0.0
var light_level := 0.0


func _ready() -> void:
	var texture := FlameParticles.make_texture()

	# Tint ramps multiply the multi-color sprite: it stays hot early and cools to red/brown at the tip
	flame = FlameParticles.make_emitter({
		"amount": 100, "lifetime": 0.45, "texture": texture,
		"size": 0.55, "speed": Vector2(13.0, 17.0), "damping": Vector2(3.0, 5.0),
		"spread": 8.5, "gravity": Vector3(0, 0.8, 0), "rotate": true, "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.15), Vector2(0.4, 1.1), Vector2(1.0, 0.95)],
		"colors": [
			[0.0, Color(1.0, 1.0, 1.0, 1.0)],
			[0.4, Color(1.0, 0.85, 0.7, 1.0)],
			[0.62, Color(1.0, 0.62, 0.45, 1.0)],
			[0.8, Color(0.85, 0.4, 0.35, 0.85)],
			[0.92, Color(0.55, 0.22, 0.22, 0.5)],
		],
	})

	# Short, wide-angle puffs that fill the flanks so the stream reads as one fat flame, not a thin beam
	licks = FlameParticles.make_emitter({
		"amount": 48, "lifetime": 0.3, "texture": texture,
		"size": 0.4, "speed": Vector2(7.0, 11.0), "damping": Vector2(3.0, 5.0),
		"spread": 24.0, "gravity": Vector3(0, 0.5, 0), "rotate": true, "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.3), Vector2(0.4, 1.0), Vector2(1.0, 0.6)],
		"colors": [
			[0.0, Color(1.0, 0.95, 0.85, 1.0)],
			[0.35, Color(1.0, 0.75, 0.55, 1.0)],
			[0.7, Color(0.9, 0.48, 0.38, 0.85)],
		],
	})

	smoke = FlameParticles.make_emitter({
		"amount": 12, "lifetime": 0.8, "texture": texture,
		"size": 0.5, "speed": Vector2(10.0, 14.0), "damping": Vector2(5.0, 8.0),
		"spread": 14.0, "gravity": Vector3(0, 1.5, 0), "rotate": true, "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.5), Vector2(1.0, 1.4)],
		"colors": [
			[0.0, Color(0.1, 0.05, 0.05, 0.0)],
			[0.6, Color(0.14, 0.08, 0.08, 0.3)],
			[0.85, Color(0.1, 0.07, 0.08, 0.18)],
		],
	})

	embers = FlameParticles.make_emitter({
		"amount": 18, "lifetime": 0.8, "texture": null, "additive": true,
		"size": 0.03, "speed": Vector2(10.0, 17.0), "damping": Vector2(2.0, 5.0),
		"spread": 16.0, "gravity": Vector3(0, -5.0, 0),
		"scale_curve": [Vector2(0.0, 1.0), Vector2(1.0, 0.4)],
		"colors": [
			[0.0, Color(1.0, 0.95, 0.5, 1.0)],
			[0.45, Color(1.0, 0.55, 0.1, 1.0)],
			[0.8, Color(0.8, 0.2, 0.05, 1.0)],
		],
	})

	# Bright fireball bursting out of the nozzle
	flare = FlameParticles.make_emitter({
		"amount": 5, "lifetime": 0.15, "texture": texture,
		"size": 0.28, "speed": Vector2(1.0, 2.0), "damping": Vector2(0.0, 0.0),
		"spread": 20.0, "gravity": Vector3.ZERO, "rotate": true, "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.7), Vector2(1.0, 1.1)],
		"colors": [[0.0, Color(1.0, 1.0, 1.0, 1.0)]],
	})

	pilot = FlameParticles.make_emitter({
		"amount": 5, "lifetime": 0.35, "texture": texture,
		"size": 0.04, "speed": Vector2(0.1, 0.25), "damping": Vector2(0.0, 0.0),
		"spread": 20.0, "gravity": Vector3(0, 0.3, 0), "rotate": true, "direction": Vector3.UP,
		"scale_curve": [Vector2(0.0, 0.6), Vector2(0.4, 1.0), Vector2(1.0, 0.2)],
		"colors": [
			[0.0, Color(1.0, 1.0, 1.0, 1.0)],
			[0.5, Color(1.0, 0.8, 0.6, 0.9)],
		],
	})
	# Rides on the gun so it stays at the nozzle while walking and bobbing
	pilot.local_coords = true
	pilot.emitting = true

	# Drawn back to front: smoke behind, flame over it, then the bright bits on top
	for emitter in [smoke, licks, flame, flare, embers, pilot]:
		add_child(emitter)

	# Lights along the stream so the room, floor and enemies pick up the glow
	for setup in [[0.9, 4.0, 6.0], [3.2, 6.0, 10.0], [6.0, 4.0, 10.0]]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.58, 0.18)
		light.omni_range = setup[2]
		light.light_energy = 0.0
		light.visible = false
		light.position = Vector3(0, 0, setup[0])
		add_child(light)
		lights.append(light)
		light_energies.append(setup[1])


func set_burning(on: bool) -> void:
	if on == burning:
		return
	burning = on
	flame.emitting = on
	licks.emitting = on
	smoke.emitting = on
	embers.emitting = on
	flare.emitting = on
	# The idle pilot flame is hidden while the main flame is out
	pilot.visible = not on


func _process(delta: float) -> void:
	# Light flickers in steps instead of smoothly
	flicker_timer -= delta
	if flicker_timer <= 0.0:
		flicker_timer = 1.0 / LIGHT_FLICKER_FPS
		light_level = randf_range(0.65, 1.0) if burning else 0.0
	for i in lights.size():
		lights[i].light_energy = light_energies[i] * light_level
		lights[i].visible = light_level > 0.01
