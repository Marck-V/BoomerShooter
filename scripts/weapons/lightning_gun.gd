extends BaseWeapon

# Chain lightning gun: one shot hits what you aim at, then the lightning jumps from enemy to enemy.

const ElectricAura = preload("res://scripts/weapons/electric_aura.gd")

# --- Chain Lightning Parameters ---
var chain_radius = 8.0        # how far (meters) the lightning can jump to the next enemy
var max_targets = 8           # most enemies one shot can hit, including the one that was shot
var chain_damage = 50
const CHAIN_HOP_DELAY := 0.1  # seconds between jumps

const AMMO_PER_SHOT := 1

var glow_material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	muzzle_flash_size = 0.09
	muzzle_flash_time = 0.08
	muzzle_light_energy = 8.0

	# Placeholder model: the base blaster with a cool electric glow until it gets its own art
	glow_material = StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_color = Color(0.1, 0.35, 0.9, 0.35)
	$WeaponMesh.material_overlay = glow_material


# ---------------------------
# Firing
# ---------------------------
func fire(_origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	if !data or !raycast:
		return
	if not GlobalVariables.spend_ammo(GlobalVariables.current_weapon, AMMO_PER_SHOT):
		Audio.play("assets/sounds/empty_gun.mp3")
		return

	Audio.play(data.sound)
	muzzle.play("default")
	play_muzzle_flash(true)
	trigger_recoil()

	for i in range(data.shot_count):
		var x_spread = deg_to_rad(randf_range(-data.spread, data.spread))
		var y_spread = deg_to_rad(randf_range(-data.spread, data.spread))

		var base_dir = -camera.global_transform.basis.z.normalized()
		var dir = base_dir.rotated(camera.global_transform.basis.x, y_spread)
		dir = dir.rotated(camera.global_transform.basis.y, x_spread)

		raycast.target_position = raycast.to_local(raycast.global_transform.origin + dir * data.max_distance)
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collider = raycast.get_collider()

			if collider and collider.has_method("damage"):
				collider.damage(chain_damage)
				flash_hit_enemy(collider, raycast.get_collision_point())

				# The hit can be a hurtbox or a shield; the chain starts from the enemy it belongs to
				var chain_target = get_hit_enemy(collider)
				if chain_target:
					ElectricAura.apply(chain_target)
					_run_chain(chain_target)

			spawn_impact_particles(raycast, camera)

# ---------------------------
# Chain Lightning
# ---------------------------
# Everything a chained enemy shows when the lightning reaches it (all purely visual)
func _chain_hit_effects(target: Node3D, from_position: Vector3) -> void:
	var chest := target.global_position + Vector3.UP * 1.2
	var direction := target.global_position - from_position
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD

	flash_hit_enemy(target, chest)
	BloodParticles.spawn(get_tree(), chest, direction)
	ElectricAura.apply(target)


# Jumps from enemy to enemy, always to the nearest one not hit yet, until max_targets are hit or nobody is in range.
func _run_chain(first_enemy: Node3D) -> void:
	var visited: Array = [first_enemy]
	var from_position := first_enemy.global_position
	while visited.size() < max_targets:
		var next_enemy := _find_next_enemy(from_position, visited)
		if next_enemy == null:
			return
		visited.append(next_enemy)
		_spawn_lightning_arc(from_position, next_enemy.global_position)
		next_enemy.damage(chain_damage, 1)
		_chain_hit_effects(next_enemy, from_position)
		# Remembered now: the enemy may die and be freed before the next jump
		from_position = next_enemy.global_position
		await get_tree().create_timer(CHAIN_HOP_DELAY).timeout


# The nearest living enemy within chain_radius of a point that has not been hit by this chain yet.
# Looks through the Enemy group instead of running a physics query: an overlap query only returns a limited
# number of shapes, and every enemy has a dozen hurtbox and vision areas, so in a crowd it missed most enemies.
func _find_next_enemy(from_position: Vector3, visited: Array) -> Node3D:
	var best: Node3D = null
	var best_d2: float = chain_radius * chain_radius
	for candidate in get_tree().get_nodes_in_group("Enemy"):
		var enemy := candidate as Node3D
		if enemy == null or enemy in visited or not enemy.has_method("damage"):
			continue
		if enemy.get("destroyed") == true:
			continue
		var d2 := from_position.distance_squared_to(enemy.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = enemy
	return best


func _spawn_lightning_arc(start: Vector3, end: Vector3):
	var mesh_instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lightning.gdshader")
	mat.set_shader_parameter("glow_strength", 18.0)
	mesh_instance.material_override = mat
	get_tree().current_scene.add_child(mesh_instance)

	var height_offset := Vector3(0, 1.0, 0)
	start += height_offset
	end += height_offset

	
	var camera := get_viewport().get_camera_3d()
	var view_dir := Vector3.FORWARD
	if camera:
		view_dir = camera.global_transform.basis.z.normalized()

	var width := 0.08
	var segment_count := 10
	var points: Array[Vector3] = []
	for i in range(segment_count + 1):
		var t := float(i) / float(segment_count)
		var pos := start.lerp(end, t)
		var offset := Vector3(
			randf_range(-0.2, 0.2),
			randf_range(-0.2, 0.2),
			randf_range(-0.2, 0.2)
		)
		points.append(pos + offset)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(points.size()):
		var dir: Vector3
		if i == 0:
			dir = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			dir = (points[i] - points[i - 1]).normalized()
		else:
			dir = (points[i + 1] - points[i - 1]).normalized()
		var side := dir.cross(view_dir)
		if side.length_squared() < 0.0001:
			side = dir.cross(Vector3.UP)
		side = side.normalized() * width
		mesh.surface_add_vertex(points[i] - side)
		mesh.surface_add_vertex(points[i] + side)
	mesh.surface_end()

	var tween := create_tween()
	tween.tween_property(mat, "shader_parameter/glow_strength", 0.0, 0.2)
	tween.tween_callback(Callable(mesh_instance, "queue_free"))

