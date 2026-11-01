extends Node3D
class_name BomberExplosion

# The bomber's blast: a white-hot flash, a fireball thrown outwards, embers and rising smoke. Purely visual; built in
# code and added to the level. Fire and smoke use the same chunky PSX sprites as the flamethrower.
#   BomberExplosion.spawn(tree, center, radius)

const FlameParticles = preload("res://scripts/weapons/flame_particles.gd")

const FLASH_GROW_TIME := 0.09
const FLASH_FADE_TIME := 0.22
const FLASH_SCALE := 2.2            # flash width, in blast radiuses
const LIGHT_COLOR := Color(1.0, 0.45, 0.15)
const LIGHT_ENERGY := 14.0
const LIGHT_FADE_TIME := 0.45
const LIFETIME := 2.4               # long enough for the last of the smoke

static var flash_texture: GradientTexture2D

var radius := 6.0


static func spawn(tree: SceneTree, center: Vector3, blast_radius: float) -> BomberExplosion:
	var explosion := BomberExplosion.new()
	explosion.radius = blast_radius
	tree.current_scene.add_child(explosion)
	explosion.global_position = center
	return explosion


func _ready() -> void:
	_add_flash()
	_add_light()
	_fire(_make_fireball())
	_fire(_make_embers())
	_fire(_make_smoke())
	get_tree().create_timer(LIFETIME, false).timeout.connect(queue_free)


func _fire(particles: GPUParticles3D) -> void:
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3.ONE * -radius * 3.0, Vector3.ONE * radius * 6.0)
	add_child(particles)
	particles.emitting = true


func _make_fireball() -> GPUParticles3D:
	return FlameParticles.make_emitter({
		"amount": 40, "lifetime": 0.6, "texture": FlameParticles.make_texture(), "fade_near": true,
		"size": radius * 0.42, "speed": Vector2(radius * 0.5, radius * 2.4), "damping": Vector2(radius * 1.5, radius * 3.0),
		"spread": 180.0, "gravity": Vector3(0, 4.0, 0), "rotate": true,
		"direction": Vector3.UP, "box": Vector3.ONE * radius * 0.12,
		"scale_curve": [Vector2(0.0, 0.5), Vector2(0.25, 1.0), Vector2(1.0, 0.55)],
		"colors": [
			[0.0, Color(1.0, 1.0, 1.0, 1.0)],
			[0.3, Color(1.0, 0.85, 0.5, 1.0)],
			[0.55, Color(1.0, 0.5, 0.25, 0.95)],
			[0.8, Color(0.7, 0.15, 0.1, 0.7)],
		],
	})


func _make_embers() -> GPUParticles3D:
	return FlameParticles.make_emitter({
		"amount": 36, "lifetime": 1.0, "texture": null, "additive": true,
		"size": 0.09, "speed": Vector2(radius * 1.2, radius * 3.5), "damping": Vector2(1.0, 4.0),
		"spread": 180.0, "gravity": Vector3(0, -12.0, 0),
		"direction": Vector3.UP,
		"scale_curve": [Vector2(0.0, 1.0), Vector2(1.0, 0.3)],
		"colors": [
			[0.0, Color(1.0, 0.95, 0.6, 1.0)],
			[0.5, Color(1.0, 0.55, 0.15, 1.0)],
			[0.8, Color(0.8, 0.15, 0.05, 1.0)],
		],
	})


func _make_smoke() -> GPUParticles3D:
	var smoke := FlameParticles.make_emitter({
		"amount": 14, "lifetime": 1.8, "texture": FlameParticles.make_texture(), "fade_near": true,
		"size": radius * 0.5, "speed": Vector2(radius * 0.2, radius * 0.7), "damping": Vector2(1.0, 2.0),
		"spread": 180.0, "gravity": Vector3(0, 1.6, 0), "rotate": true,
		"direction": Vector3.UP, "box": Vector3.ONE * radius * 0.2,
		"scale_curve": [Vector2(0.0, 0.5), Vector2(0.4, 1.0), Vector2(1.0, 0.8)],
		"colors": [
			[0.0, Color(0.0, 0.0, 0.0, 0.0)],     # hidden behind the fireball at first
			[0.2, Color(0.16, 0.12, 0.13, 0.75)],
			[0.6, Color(0.1, 0.08, 0.1, 0.5)],
			[0.85, Color(0.08, 0.07, 0.09, 0.2)],
		],
	})
	return smoke


func _add_flash() -> void:
	if flash_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 0.9, 0.55, 0.95), Color(1.0, 0.35, 0.1, 0.4), Color(1.0, 0.1, 0.0, 0.0)])
		flash_texture = GradientTexture2D.new()
		flash_texture.gradient = gradient
		flash_texture.fill = GradientTexture2D.FILL_RADIAL
		flash_texture.fill_from = Vector2(0.5, 0.5)
		flash_texture.fill_to = Vector2(1.0, 0.5)
		flash_texture.width = 128
		flash_texture.height = 128

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.albedo_texture = flash_texture
	material.albedo_color = Color(2.0, 2.0, 2.0)

	var flash := MeshInstance3D.new()
	flash.mesh = QuadMesh.new()
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.scale = Vector3.ONE * radius * 0.4
	add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * radius * FLASH_SCALE, FLASH_GROW_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color", Color(0.0, 0.0, 0.0), FLASH_FADE_TIME)
	tween.tween_callback(flash.queue_free)


func _add_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY
	light.omni_range = radius * 2.5
	add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, LIGHT_FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)
