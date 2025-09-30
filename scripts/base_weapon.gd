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


func _ready():
	rest_position = position
	muzzle.position = muzzle_location.position

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
	

func fire(origin: Vector3, direction: Vector3, camera: Camera3D, raycast: RayCast3D):
	if !data or !raycast:
		return

	Audio.play(data.sound)
	muzzle.play("default")
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

			var impact = preload("res://scenes/impact.tscn").instantiate()
			impact.play("shot")
			get_tree().root.add_child(impact)
			impact.global_position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact.look_at(camera.global_transform.origin, Vector3.UP, true)
			
func set_movement_state(moving: bool):
	is_moving = moving
	
