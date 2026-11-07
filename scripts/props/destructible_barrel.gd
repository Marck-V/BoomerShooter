extends StaticBody3D
class_name DestructibleBarrel

# A barrel that breaks when shot. Plain, it bursts into staves and hoops. Explosive (the red one with the hazard
# band), it goes off after a blink: hurting enemies and the player inside the blast, and setting off any barrel or
# window it reaches. Built in code (a low-poly cylinder, hoops, a lid), so placing one needs only the scene.
#   scenes/props/barrel.tscn, scenes/props/explosive_barrel.tscn  (TrenchBroom: barrel, explosive_barrel)

const ImpactParticles = preload("res://scripts/weapons/impact_particles.gd")

const HEIGHT := 1.05
const RADIUS := 0.42
const SIDES := 12                    # chunky on purpose, for the PSX look
const BREAK_SOUND := "assets/audio/sfx/impacts/metal_axe_hit.mp3"
const HIT_SOUND := "assets/audio/sfx/impacts/bullet_hit_metal.mp3"
const FUSE_BLINKS := 0.28            # seconds an explosive barrel flashes before it goes
const CHAIN_DELAY := 0.1             # a barrel set off by a blast goes this much later, plus a little per metre

@export var explosive := false
@export var health := 30.0
@export var blast_radius := 6.5
@export var player_damage := 40.0    # at the centre of the blast; half of it at the edge
@export var enemy_damage := 140.0

var body_mesh: MeshInstance3D
var visuals: Node3D
var igniting := false
var broken := false
var overlay: StandardMaterial3D

static var shared_materials := {}


func _ready() -> void:
	add_to_group("Blastable")
	collision_layer = PhysicsLayers.ENVIRONMENT
	collision_mask = 0
	_build_collision()
	_build_visuals()


func _build_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = HEIGHT * 0.5
	add_child(collider)


# ---------------------------
# Look
# ---------------------------
func _build_visuals() -> void:
	visuals = Node3D.new()
	add_child(visuals)
	var shell := _material("shell")
	var steel := _material("steel")

	body_mesh = _cylinder(RADIUS, HEIGHT, shell, Vector3(0, HEIGHT * 0.5, 0))
	for y in [0.14, 0.52, 0.91]:
		_cylinder(RADIUS * 1.035, 0.06, steel, Vector3(0, y * HEIGHT / 1.05, 0))
	_cylinder(RADIUS * 0.9, 0.03, steel, Vector3(0, HEIGHT - 0.005, 0))      # the lid, a little sunk
	if explosive:
		var band := _cylinder(RADIUS * 1.02, 0.24, _material("hazard"), Vector3(0, HEIGHT * 0.5, 0), false)
		band.rotate_y(0.2)


func _cylinder(radius: float, height: float, material: Material, at: Vector3, capped := true) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = SIDES
	mesh.rings = 1
	mesh.cap_top = capped
	mesh.cap_bottom = capped
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if height < 0.1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visuals.add_child(node)
	return node


func _material(kind: String) -> Material:
	var key := kind if kind != "shell" else ("shell_explosive" if explosive else "shell")
	if shared_materials.has(key):
		return shared_materials[key]
	var material := StandardMaterial3D.new()
	material.roughness = 0.65
	material.metallic = 0.35
	match key:
		"shell":
			material.albedo_color = Color(0.3, 0.36, 0.34)         # weathered green-grey steel
		"shell_explosive":
			material.albedo_color = Color(0.78, 0.08, 0.06)
			material.emission_enabled = true
			material.emission = Color(0.6, 0.02, 0.0)
			material.emission_energy_multiplier = 0.35
		"steel":
			material.albedo_color = Color(0.1, 0.1, 0.11)
			material.metallic = 0.7
		"hazard":
			material.albedo_texture = _hazard_texture()
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			material.uv1_scale = Vector3(4, 1, 1)
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.metallic = 0.1
	shared_materials[key] = material
	return material


# Yellow and black diagonal stripes
static func _hazard_texture() -> ImageTexture:
	var image := Image.create(32, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 32:
			var yellow := (x + y) % 16 < 8
			image.set_pixel(x, y, Color(0.95, 0.75, 0.05) if yellow else Color(0.06, 0.06, 0.06))
	return ImageTexture.create_from_image(image)


# ---------------------------
# Damage
# ---------------------------
func damage(amount: float, _multiplier: float = 1.0) -> void:
	if broken or igniting:
		return
	health -= amount
	if health <= 0.0:
		_destroyed(0.05)
	else:
		_flash(Color(1.0, 1.0, 1.0, 0.55), 0.12)
		_punch()
		Audio.play_at(global_position + Vector3.UP * 0.5, HIT_SOUND)


func on_blast(center: Vector3, radius: float) -> void:
	if broken or igniting:
		return
	var distance := center.distance_to(global_position + Vector3.UP * HEIGHT * 0.5)
	if distance <= radius:
		_destroyed(CHAIN_DELAY + distance * 0.03)


func _destroyed(delay: float) -> void:
	if explosive:
		igniting = true
		_blink(delay + FUSE_BLINKS)
		get_tree().create_timer(delay + FUSE_BLINKS, false).timeout.connect(_explode)
	elif delay > 0.06:
		get_tree().create_timer(delay, false).timeout.connect(_burst)
	else:
		_burst()


# A little jolt when a hit does not finish it
func _punch() -> void:
	var tween := create_tween()
	visuals.scale = Vector3(1.06, 0.95, 1.06)
	tween.tween_property(visuals, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash(color: Color, time: float) -> void:
	if overlay == null:
		overlay = StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.render_priority = 2
	overlay.albedo_color = color
	for node in visuals.get_children():
		(node as MeshInstance3D).material_overlay = overlay
	var tween := create_tween()
	tween.tween_property(overlay, "albedo_color:a", 0.0, time)


# The fuse: flashes red and white faster and faster until it goes
func _blink(time: float) -> void:
	if overlay == null:
		_flash(Color(1, 1, 1, 0), 0.01)
	var tween := create_tween().set_loops(roundi(time / 0.08))
	tween.tween_callback(func(): overlay.albedo_color = Color(1.0, 0.9, 0.7, 0.7))
	tween.tween_interval(0.04)
	tween.tween_callback(func(): overlay.albedo_color = Color(1.0, 0.1, 0.0, 0.35))
	tween.tween_interval(0.04)


# ---------------------------
# Going off
# ---------------------------
func _explode() -> void:
	if broken:
		return
	var centre := global_position + Vector3.UP * HEIGHT * 0.5
	_retire()
	_spawn_pieces(centre, 9.0)
	Blast.explode(get_tree(), centre, blast_radius, player_damage, enemy_damage, self)
	queue_free()


func _burst() -> void:
	if broken:
		return
	var centre := global_position + Vector3.UP * HEIGHT * 0.5
	_retire()
	_spawn_pieces(centre, 5.0)
	ImpactParticles.spawn(get_tree(), centre, Vector3.UP, 1.4)
	Audio.play_at(centre, BREAK_SOUND)
	queue_free()


# No longer there as far as the level is concerned, even before it is freed
func _retire() -> void:
	broken = true
	remove_from_group("Blastable")
	collision_layer = 0
	visuals.visible = false


# Staves, hoops and the lid, thrown outwards
func _spawn_pieces(centre: Vector3, speed: float) -> void:
	var shell := _material("shell")
	var steel := _material("steel")
	var stave := BoxMesh.new()
	stave.size = Vector3(0.2, 0.5, 0.05)
	var hoop := CylinderMesh.new()
	hoop.top_radius = RADIUS
	hoop.bottom_radius = RADIUS
	hoop.height = 0.05
	hoop.radial_segments = SIDES
	hoop.cap_top = false
	hoop.cap_bottom = false
	var lid := CylinderMesh.new()
	lid.top_radius = RADIUS * 0.9
	lid.bottom_radius = RADIUS * 0.9
	lid.height = 0.04
	lid.radial_segments = SIDES

	for i in 8:
		var angle := TAU * i / 8.0 + randf() * 0.4
		var outward := Vector3(cos(angle), 0, sin(angle))
		var velocity := outward * speed * randf_range(0.5, 1.0) + Vector3.UP * speed * randf_range(0.4, 1.0)
		Debris.spawn(get_tree(), stave, shell, Transform3D.IDENTITY, centre + outward * RADIUS * 0.8 + Vector3.UP * randf_range(-0.3, 0.3), Basis(Vector3.UP, -angle), velocity, _spin(), Vector3(0.2, 0.5, 0.08))
	for i in 2:
		var velocity := Vector3(randf_range(-1, 1), randf_range(0.3, 1.0), randf_range(-1, 1)).normalized() * speed * 0.7
		Debris.spawn(get_tree(), hoop, steel, Transform3D.IDENTITY, centre + Vector3.UP * randf_range(-0.3, 0.3), Basis.IDENTITY, velocity, _spin(), Vector3(0.7, 0.05, 0.7))
	Debris.spawn(get_tree(), lid, steel, Transform3D.IDENTITY, centre + Vector3.UP * 0.5, Basis.IDENTITY, Vector3(randf_range(-1, 1), speed * 1.2, randf_range(-1, 1)), _spin(), Vector3(0.7, 0.05, 0.7))


func _spin() -> Vector3:
	return Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
