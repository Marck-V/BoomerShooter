extends Area3D
class_name GrapplePoint

# A small glowing green sphere the player can hit with the thrown shield to be pulled to it.
# Place it with the TrenchBroom "grapple_point" entity, or add this script to any Node3D/Area3D in a scene.
# The visuals are built in code; the hit area is bigger than the sphere so it is forgiving to hit.

const HIT_RADIUS := 0.9
const VISUAL_RADIUS := 0.26
const PULSE_FPS := 12.0
const CORE_COLOR := Color(0.35, 1.8, 0.6)

var core: MeshInstance3D
var halo: MeshInstance3D
var light: OmniLight3D
var pulse_clock := 0.0
var pulse_time := 0.0
var pop := 0.0          # extra size right after being grappled, fading out


func _ready() -> void:
	add_to_group("GrapplePoint")
	collision_layer = PhysicsLayers.GRAPPLE
	collision_mask = 0
	monitoring = false
	monitorable = true
	pulse_time = randf() * TAU

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = HIT_RADIUS
	shape.shape = sphere_shape
	add_child(shape)

	# Low-poly sphere, flat bright green
	var sphere := SphereMesh.new()
	sphere.radius = VISUAL_RADIUS
	sphere.height = VISUAL_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = CORE_COLOR
	core_material.disable_fog = true
	sphere.material = core_material
	core = MeshInstance3D.new()
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	# Soft glow around it so it reads from across the room
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	glow.colors = PackedColorArray([Color(0.8, 1.0, 0.85, 1.0), Color(0.2, 1.0, 0.4, 0.5), Color(0.0, 0.8, 0.2, 0.0)])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 64
	glow_texture.height = 64
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.albedo_texture = glow_texture
	halo_material.albedo_color = Color(1.4, 1.6, 1.4)
	halo_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	halo_material.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.6
	quad.material = halo_material
	halo = MeshInstance3D.new()
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	light = OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.45)
	light.light_energy = 1.5
	light.omni_range = 4.5
	add_child(light)


func _process(delta: float) -> void:
	# Pulse in steps, like the rest of the game's effects
	pulse_clock -= delta
	if pop > 0.0:
		pop = maxf(pop - delta * 3.0, 0.0)
	if pulse_clock > 0.0:
		return
	pulse_clock = 1.0 / PULSE_FPS
	pulse_time += 1.0 / PULSE_FPS
	var pulse := 1.0 + 0.18 * sin(pulse_time * 3.0) + pop
	core.scale = Vector3.ONE * pulse
	halo.scale = Vector3.ONE * (pulse + 0.1)
	light.light_energy = 1.5 + 0.5 * sin(pulse_time * 3.0) + pop * 3.0


# The shield stuck to this point and the player is on their way
func on_grappled() -> void:
	pop = 1.0
