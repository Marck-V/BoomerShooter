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

# Pressure (flamethrower upgrade): the stream gets longer, bigger and whiter-blue the more pressure it has built
const PRESSURE_SPEED := 1.45          # the stream's speed, times this at full pressure
const PRESSURE_SIZE := 1.35
const PRESSURE_TINT := Color(0.78, 0.95, 1.5)   # multiplies the flame's colours: hotter, bluer
const PRESSURE_LIGHT := 0.6           # extra light at full pressure
var pressure := -1.0
var base_speeds := {}
var vent_burst: GPUParticles3D        # Backdraft: a big one-off blast out of the nozzle
var vent_flash := 0.0


func _ready() -> void:
	var texture := FlameParticles.make_texture()

	# Tint ramps multiply the multi-color sprite: it stays hot early and cools to deep red at the tip. Upright,
	# unrotated sprites keep the chunky pixels on one grid, and adding them together makes the overlaps blaze.
	flame = FlameParticles.make_emitter({
		"amount": 70, "lifetime": 0.45, "texture": texture, "additive": true,
		"size": 0.42, "speed": Vector2(13.0, 17.0), "damping": Vector2(3.0, 5.0),
		"spread": 8.5, "gravity": Vector3(0, 1.2, 0), "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.15), Vector2(0.4, 1.1), Vector2(1.0, 0.8)],
		"colors": [
			[0.0, Color(1.0, 0.85, 0.55, 0.45)],
			[0.35, Color(1.0, 0.6, 0.25, 0.45)],
			[0.62, Color(1.0, 0.38, 0.12, 0.45)],
			[0.8, Color(0.8, 0.16, 0.05, 0.4)],
			[0.92, Color(0.5, 0.08, 0.03, 0.25)],
		],
	})

	# Short, wide-angle puffs that fill the flanks so the stream reads as one fat flame, not a thin beam
	licks = FlameParticles.make_emitter({
		"amount": 32, "lifetime": 0.3, "texture": texture, "additive": true,
		"size": 0.3, "speed": Vector2(7.0, 11.0), "damping": Vector2(3.0, 5.0),
		"spread": 24.0, "gravity": Vector3(0, 0.8, 0), "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.3), Vector2(0.4, 1.0), Vector2(1.0, 0.6)],
		"colors": [
			[0.0, Color(1.0, 0.75, 0.42, 0.4)],
			[0.35, Color(1.0, 0.5, 0.18, 0.4)],
			[0.7, Color(0.8, 0.2, 0.07, 0.35)],
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
		"amount": 30, "lifetime": 0.9, "texture": null, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.045, "speed": Vector2(10.0, 17.0), "damping": Vector2(2.0, 5.0),
		"spread": 18.0, "gravity": Vector3(0, 2.0, 0),
		"scale_curve": [Vector2(0.0, 1.0), Vector2(1.0, 0.4)],
		"colors": [
			[0.0, Color(1.0, 0.95, 0.5, 1.0)],
			[0.45, Color(1.0, 0.55, 0.1, 1.0)],
			[0.8, Color(0.8, 0.2, 0.05, 1.0)],
		],
	})

	# Bright fireball bursting out of the nozzle
	flare = FlameParticles.make_emitter({
		"amount": 5, "lifetime": 0.15, "texture": texture, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.28, "speed": Vector2(1.0, 2.0), "damping": Vector2(0.0, 0.0),
		"spread": 20.0, "gravity": Vector3.ZERO, "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.7), Vector2(1.0, 1.1)],
		"colors": [[0.0, Color(1.0, 1.0, 1.0, 1.0)]],
	})

	pilot = FlameParticles.make_emitter({
		"amount": 5, "lifetime": 0.35, "texture": texture, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.04, "speed": Vector2(0.1, 0.25), "damping": Vector2(0.0, 0.0),
		"spread": 20.0, "gravity": Vector3(0, 0.3, 0), "direction": Vector3.UP,
		"scale_curve": [Vector2(0.0, 0.6), Vector2(0.4, 1.0), Vector2(1.0, 0.2)],
		"colors": [
			[0.0, Color(1.0, 1.0, 1.0, 1.0)],
			[0.5, Color(1.0, 0.8, 0.6, 0.9)],
		],
	})
	# Rides on the gun so it stays at the nozzle while walking and bobbing
	pilot.local_coords = true
	pilot.emitting = true

	# Backdraft's blast: a thick burst of white-hot fire thrown far out of the nozzle all at once
	vent_burst = FlameParticles.make_emitter({
		"amount": 90, "lifetime": 0.5, "texture": texture, "additive": true,
		"brightness": FlameParticles.HOT_BRIGHTNESS,
		"size": 0.75, "speed": Vector2(20.0, 30.0), "damping": Vector2(2.5, 4.0),
		"spread": 26.0, "gravity": Vector3(0, 0.8, 0), "fade_near": true,
		"scale_curve": [Vector2(0.0, 0.3), Vector2(0.3, 1.1), Vector2(1.0, 0.7)],
		"colors": [
			[0.0, Color(1.0, 1.0, 0.9, 0.7)],
			[0.3, Color(1.0, 0.8, 0.4, 0.6)],
			[0.6, Color(1.0, 0.45, 0.15, 0.55)],
			[0.85, Color(0.7, 0.15, 0.05, 0.35)],
		],
	})
	vent_burst.one_shot = true
	vent_burst.explosiveness = 0.9

	# Drawn back to front: smoke behind, flame over it, then the bright bits on top
	for emitter in [smoke, licks, flame, vent_burst, flare, embers, pilot]:
		add_child(emitter)

	base_speeds = {
		flame: Vector2(13.0, 17.0),
		licks: Vector2(7.0, 11.0),
	}

	# Lights along the stream so the room, floor and enemies pick up the glow
	for setup in [[0.9, 6.0, 7.0], [3.2, 9.0, 11.0], [6.0, 6.0, 11.0]]:
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


func set_pressure(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if absf(value - pressure) < 0.015 and not (value == 0.0 and pressure != 0.0):
		return
	pressure = value
	for emitter: GPUParticles3D in [flame, licks]:
		var process := emitter.process_material as ParticleProcessMaterial
		var speeds: Vector2 = base_speeds[emitter]
		process.initial_velocity_min = speeds.x * lerpf(1.0, PRESSURE_SPEED, value)
		process.initial_velocity_max = speeds.y * lerpf(1.0, PRESSURE_SPEED, value)
		process.scale_min = lerpf(1.0, PRESSURE_SIZE, value)
		process.scale_max = lerpf(1.0, PRESSURE_SIZE, value)
		var material := (emitter.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		var tint := Color.WHITE.lerp(PRESSURE_TINT, value)
		material.albedo_color = Color(tint.r, tint.g, tint.b)


# Backdraft: the held flame is let go and vents. strength 0..1 sizes the blast
func vent(strength: float) -> void:
	var process := vent_burst.process_material as ParticleProcessMaterial
	process.initial_velocity_min = lerpf(14.0, 20.0, strength)
	process.initial_velocity_max = lerpf(20.0, 30.0, strength)
	vent_burst.amount = int(lerpf(60.0, 110.0, strength))
	vent_burst.restart()
	vent_burst.emitting = true
	vent_flash = 1.0


func _process(delta: float) -> void:
	# Light flickers in steps instead of smoothly
	flicker_timer -= delta
	if flicker_timer <= 0.0:
		flicker_timer = 1.0 / LIGHT_FLICKER_FPS
		light_level = randf_range(0.65, 1.0) if burning else 0.0
	vent_flash = maxf(vent_flash - delta * 5.0, 0.0)
	var level := maxf(light_level, vent_flash)
	for i in lights.size():
		lights[i].light_energy = light_energies[i] * level * (1.0 + PRESSURE_LIGHT * maxf(pressure, 0.0) + vent_flash * 1.5)
		lights[i].visible = level > 0.01
