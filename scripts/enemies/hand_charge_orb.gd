extends Node3D
class_name HandChargeOrb

# The ball of energy the hand boss gathers inside its clenched fist before the spoke burst. Energy is sucked into it:
# streaks of light fly in from all round, curving inwards and speeding up as they near the ball, getting longer and
# brighter as they go and vanishing into it; rings of light contract onto it; and the ball grows and heats from
# orange to white as it fills, its glow leaking out through the fingers. The more it has charged, the more streaks
# are in flight and the faster they come. Built in code and added to the level.
#   var orb := HandChargeOrb.spawn(get_tree(), world_position)   (move it each frame to keep it in the fist)
#   orb.set_progress(0.6) ... orb.release()

const CORE_COLOR := Color(1.0, 0.35, 0.1)
const HOT_COLOR := Color(1.0, 0.95, 0.85)
const MIN_RADIUS := 0.35
const MAX_RADIUS := 1.3
const STREAKS := 48
const STREAK_START := 7.0              # metres out that a streak begins
const STREAK_END := 0.5                # it vanishes this far from the centre
const STREAK_TIME := 0.75              # seconds for one streak to fall in at the start of the charge (faster later)
const RINGS := 3
const RING_START := 5.5
const RING_TIME := 0.9
const RELEASE_TIME := 0.22

var core: MeshInstance3D
var shell: MeshInstance3D
var core_material: StandardMaterial3D
var shell_material: StandardMaterial3D
var light: OmniLight3D
var streak_nodes: Array[MeshInstance3D] = []
var streak_state: Array[Dictionary] = []     # {dir, phase, curl}
var streak_material: StandardMaterial3D
var ring_nodes: Array[MeshInstance3D] = []
var ring_materials: Array[StandardMaterial3D] = []
var progress := 0.0
var released := false
var age := 0.0


static func spawn(tree: SceneTree, at: Vector3) -> HandChargeOrb:
	var orb := HandChargeOrb.new()
	tree.current_scene.add_child(orb)
	orb.global_position = at
	return orb


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 7
	core_material = _glow_material(CORE_COLOR, 1.0)
	core = MeshInstance3D.new()
	core.mesh = sphere
	core.material_override = core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	# The halo is drawn over everything, so the ball's light leaks out through the fingers round it
	shell_material = _glow_material(CORE_COLOR, 0.25)
	shell_material.no_depth_test = true
	shell_material.render_priority = 5
	shell = MeshInstance3D.new()
	shell.mesh = sphere
	shell.material_override = shell_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	light = OmniLight3D.new()
	light.light_color = CORE_COLOR
	light.omni_range = 14.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	_build_streaks()
	_build_rings()
	set_progress(0.0)


func _glow_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, alpha)
	return material


func _build_streaks() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 1.0)          # stretched along its length in code
	streak_material = StandardMaterial3D.new()
	streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	streak_material.no_depth_test = true
	streak_material.render_priority = 4
	streak_material.albedo_color = Color(2.0, 1.4, 0.8, 0.9)
	for i in STREAKS:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = streak_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		streak_nodes.append(node)
		streak_state.append({
			"dir": Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized(),
			"phase": randf(),
			"curl": randf_range(0.5, 1.4) * (1.0 if randf() < 0.5 else -1.0),   # how far it swirls sideways on the way in
		})


func _build_rings() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 36
	torus.ring_segments = 6
	for i in RINGS:
		var material := _glow_material(CORE_COLOR, 0.0)
		material.no_depth_test = true
		material.render_priority = 4
		var node := MeshInstance3D.new()
		node.mesh = torus
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(node)
		ring_nodes.append(node)
		ring_materials.append(material)


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	if released or core == null:
		return
	var radius := lerpf(MIN_RADIUS, MAX_RADIUS, progress * progress)
	core.scale = Vector3.ONE * radius
	shell.scale = Vector3.ONE * radius * (1.9 + 0.25 * sin(age * (6.0 + progress * 24.0)))
	var colour := CORE_COLOR.lerp(HOT_COLOR, smoothstep(0.5, 1.0, progress))
	core_material.albedo_color = Color(colour.r * 2.0, colour.g * 2.0, colour.b * 2.0, 1.0)
	shell_material.albedo_color = Color(colour.r * 2.0, colour.g * 2.0, colour.b * 2.0, 0.12 + 0.2 * progress)
	light.light_color = colour
	light.light_energy = (1.5 + 6.0 * progress) * (0.75 + 0.25 * sin(age * (8.0 + progress * 30.0)))


func _process(delta: float) -> void:
	age += delta
	if released:
		return
	set_progress(progress)
	_update_streaks()
	_update_rings()


# Every streak falls from far out to the ball along a curve: slow at first, accelerating as it nears, stretching into a
# line pointing at the ball and brightening, then gone. Later in the charge they come faster and more of them show.
func _update_streaks() -> void:
	var speed := lerpf(1.0, 2.6, progress)
	var visible_count := int(lerpf(STREAKS * 0.45, STREAKS, progress))
	for i in STREAKS:
		var node := streak_nodes[i]
		node.visible = i < visible_count
		if not node.visible:
			continue
		var state := streak_state[i]
		var t := fposmod(age * speed / STREAK_TIME + float(state.phase), 1.0)          # 0 far out -> 1 at the ball
		var fall := t * t                                                              # accelerates inwards
		var dir: Vector3 = state.dir
		var swirl := Vector3.UP.cross(dir).normalized() * float(state.curl) * (1.0 - fall) * 1.6
		var local_position := dir * lerpf(STREAK_START, STREAK_END, fall) + swirl * (1.0 - t)
		node.position = local_position
		node.scale = Vector3(1.0, 1.0, lerpf(0.3, 2.2, fall))
		if local_position.length() > 0.01:
			node.look_at(global_position, Vector3.UP)                                  # its long axis points at the ball


# Rings of light shrink onto the ball one after another, brightening as they close
func _update_rings() -> void:
	var speed := lerpf(1.0, 2.0, progress)
	for i in RINGS:
		var t := fposmod(age * speed / RING_TIME + float(i) / RINGS, 1.0)
		var radius := lerpf(RING_START, 0.6, t * t)
		ring_nodes[i].scale = Vector3.ONE * radius
		ring_nodes[i].rotate_y(0.02)
		var alpha := sin(t * PI) * (0.25 + 0.5 * progress)
		var colour := CORE_COLOR.lerp(HOT_COLOR, t)
		ring_materials[i].albedo_color = Color(colour.r * 2.0, colour.g * 2.0, colour.b * 2.0, alpha)


# The hand opened: the ball flashes and pops, and what was left of the suction goes
func release() -> void:
	if released:
		return
	released = true
	for node in streak_nodes:
		node.visible = false
	for node in ring_nodes:
		node.visible = false
	var tween := create_tween().set_parallel(true)
	tween.tween_property(core, "scale", Vector3.ONE * MAX_RADIUS * 2.0, RELEASE_TIME)
	tween.tween_property(shell, "scale", Vector3.ONE * MAX_RADIUS * 3.5, RELEASE_TIME)
	tween.tween_property(core_material, "albedo_color:a", 0.0, RELEASE_TIME)
	tween.tween_property(shell_material, "albedo_color:a", 0.0, RELEASE_TIME)
	tween.tween_property(light, "light_energy", 0.0, RELEASE_TIME)
	tween.chain().tween_callback(queue_free)


# The boss clears its action effects with finish(): the orb goes without a pop (the attack was cut short)
func finish(_seconds := 0.0) -> void:
	cancel()


func cancel() -> void:
	if released:
		return
	released = true
	queue_free()
