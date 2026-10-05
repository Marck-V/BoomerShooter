extends Node3D
class_name BaseWeapon

@onready var muzzle_location: Marker3D = $MuzzleLocation
@onready var muzzle: AnimatedSprite3D = $Muzzle

@export var data: Weapon
@export var rest_position := Vector3.ZERO
var recoil_offset := Vector3.ZERO
var recoil_timer := 0.0
var sway_time := 0.0
var walk_bob_speed := 7.0         # Slightly slower bobbing, less "jumpy"
var walk_bob_amount := 0.005      # Subtle vertical motion
var walk_sway_amount := 0.003     # Gentle left-right sway
var is_moving := false
var bob_offset := Vector3.ZERO

# --- Muzzle Flash (weapons tweak these in their own _ready) ---
var muzzle_flash_time := 0.1
var muzzle_flash_size := 0.07    # Glow quad size in meters
var muzzle_light_energy := 10.0
var muzzle_base_scale := Vector3.ONE
var muzzle_light: OmniLight3D
var muzzle_flash_mesh: MeshInstance3D
var muzzle_flash_material: StandardMaterial3D
var muzzle_flash_tween: Tween


func _ready():
	GlobalVariables.refill_all_ammo()
	rest_position = position
	muzzle.position = muzzle_location.position
	muzzle_base_scale = muzzle.scale
	_setup_muzzle_flash()

func _process(delta):
	if recoil_timer > 0:
		recoil_timer -= delta
		recoil_offset = recoil_offset.lerp(Vector3.ZERO, delta)
	else:
		recoil_offset = Vector3.ZERO

	if is_moving:
		sway_time += delta * walk_bob_speed
		bob_offset.y = sin(sway_time * 2.0) * walk_bob_amount
		bob_offset.x = sin(sway_time) * walk_sway_amount
	else:
		sway_time = 0.0  # Snap reset
		# No lerp, no residual offset

	position = rest_position + recoil_offset + bob_offset


func trigger_recoil():
	recoil_offset.z = -0.01 * data.recoil_strength # You can export this as a weapon stat if you want more control
	recoil_timer = 0.1
	
func get_shield_multiplier() -> float:
	return 1.0

func fire(origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	if !data or !raycast:
		return
	if not GlobalVariables.spend_ammo(GlobalVariables.current_weapon, 1):
		Audio.play("assets/sounds/empty_gun.mp3")
		return
		
	Audio.play(data.sound)
	muzzle.play("default")
	play_muzzle_flash()
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
				collider.damage(data.damage)

			# Flash before the shield absorbs the hit, since it may be destroyed by it.
			flash_hit_enemy(collider, raycast.get_collision_point())

			if collider.is_in_group("Shield"):
				var mult = get_shield_multiplier()
				collider.get_parent().absorb_damage(data.damage * mult)

			var impact = preload("res://scenes/weapons/impact.tscn").instantiate()
			impact.play("shot")
			get_tree().root.add_child(impact)
			impact.global_position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact.look_at(camera.global_transform.origin, Vector3.UP, true)
			
func flash_hit_enemy(collider: Object, point: Vector3) -> void:
	if not collider is Node:
		return
	var enemy = collider
	if collider.is_in_group("Shield"):
		# ShieldHitbox -> Shield -> enemy
		enemy = collider.get_parent().get_parent()
	elif not collider.is_in_group("Enemy"):
		enemy = collider.get("owner_enemy")
	if enemy and enemy.has_method("hit_flash"):
		enemy.hit_flash(point)


func _setup_muzzle_flash() -> void:
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.75, 0.35)
	muzzle_light.light_energy = muzzle_light_energy
	muzzle_light.omni_range = 4.0
	muzzle_light.visible = false
	muzzle_location.add_child(muzzle_light)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.75, 0.3, 0.75),
		Color(1.0, 0.4, 0.1, 0.0),
	])
	var glow := GradientTexture2D.new()
	glow.gradient = gradient
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 128
	glow.height = 128

	muzzle_flash_material = StandardMaterial3D.new()
	muzzle_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	muzzle_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	muzzle_flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	muzzle_flash_material.billboard_keep_scale = true
	muzzle_flash_material.no_depth_test = true
	muzzle_flash_material.albedo_texture = glow

	muzzle_flash_mesh = MeshInstance3D.new()
	muzzle_flash_mesh.mesh = QuadMesh.new()
	muzzle_flash_mesh.material_override = muzzle_flash_material
	muzzle_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle_flash_mesh.visible = false
	muzzle_location.add_child(muzzle_flash_mesh)


func play_muzzle_flash() -> void:
	# The flash rides on the weapon holder (camera-relative) rather than the gun,
	# so recoil animations like the shotgun's flip don't carry it away.
	var holder := get_parent() as Node3D
	if holder:
		if muzzle_flash_mesh.get_parent() != holder:
			muzzle_flash_mesh.reparent(holder, false)
			muzzle_light.reparent(holder, false)
		var flash_position := holder.to_local(muzzle_location.global_position)
		muzzle_flash_mesh.position = flash_position
		muzzle_light.position = flash_position

	muzzle.modulate = Color(3.0, 2.4, 1.4)
	muzzle.scale = muzzle_base_scale * 1.3
	muzzle_light.light_energy = muzzle_light_energy
	muzzle_light.visible = true
	muzzle_flash_mesh.visible = true

	var start_size := muzzle_flash_size * randf_range(0.85, 1.15)
	muzzle_flash_mesh.scale = Vector3.ONE * start_size
	muzzle_flash_material.albedo_color = Color(2.0, 1.6, 1.0)

	if muzzle_flash_tween:
		muzzle_flash_tween.kill()
	muzzle_flash_tween = create_tween().set_parallel(true)
	muzzle_flash_tween.tween_property(muzzle_flash_mesh, "scale", Vector3.ONE * start_size * 0.4, muzzle_flash_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	muzzle_flash_tween.tween_property(muzzle_flash_material, "albedo_color", Color(0.1, 0.05, 0.02), muzzle_flash_time)
	muzzle_flash_tween.chain().tween_callback(_end_muzzle_flash)


func _end_muzzle_flash() -> void:
	muzzle_light.visible = false
	muzzle_flash_mesh.visible = false

func set_movement_state(moving: bool):
	is_moving = moving
