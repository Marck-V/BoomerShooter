extends Node3D
class_name KillHealPack

# A small health pack that pops out of a killed enemy. The kill itself heals nothing: the pack does.
#  - HOMING (the player killed it from really close): it flies at the player and heals on arrival.
#  - DROP (the player is further away): it falls to the floor and waits to be walked over, like any other pickup. It can
#    be collected the whole time, in the air too (running through the burst picks it up), and when the player who needs
#    the health comes near it is drawn to them. If it is not picked up it blinks and goes away after DROP_LIFETIME, so
#    packs left behind don't pile up in the level.
# Use: KillHealPack.spawn(tree, from_point, player, amount, homing)

enum Mode { HOMING, DROP }

const MEDKIT_SCENE := "res://scenes/props/medkit.tscn"
const GLOW_SHADER := "res://shaders/pickups/pickup_glow.gdshader"
const GLOW_COLOR := Color(0.2, 1.0, 0.35)
const HEAL_SOUND := "assets/audio/sfx/pickups/health_pickup.mp3"

const MODEL_SCALE := 0.16            # the medkit model is ~2 m across: about 0.3 m here
const POP_TIME := 0.28               # it bursts out of the enemy for this long (homing packs then start flying)
const POP_SPEED := 3.2               # horizontal burst speed
const POP_LIFT := 3.4                # upward burst speed
const GRAVITY := 11.0
const START_SPEED := 5.0             # homing speed when the pull starts...
const ACCELERATION := 70.0           # ...and how fast it picks up
const MAX_SPEED := 30.0
const ARRIVE_DISTANCE := 0.7
const MAX_LIFE := 3.0                # a homing pack delivers its heal by now whatever happens
const HEAL_PER_PACK := 5             # a kill that heals more than this sends several packs
const REST_HEIGHT := 0.45            # a dropped pack floats this far above the floor
const PICKUP_RADIUS := 1.3           # a dropped pack is collected when the player's body is this close
const FALL_LIMIT := 6.0              # a drop that finds no floor for this long (over a pit) is removed
const MAGNET_RADIUS := 3.0           # a dropped pack this close to a player who needs health flies to them
const MAGNET_START_SPEED := 6.0
const MAGNET_ACCELERATION := 60.0
const MAGNET_MAX_SPEED := 22.0
const DROP_LIFETIME := 30.0          # seconds from the kill until a dropped pack nobody picked up goes away
const DROP_WARNING := 4.0            # it blinks for the last few seconds of that

var mode := Mode.HOMING
var player: Node3D
var amount := 5
var velocity := Vector3.ZERO
var age := 0.0
var speed := START_SPEED
var model: Node3D
var landed := false
var rest_y := 0.0
var bob_time := randf() * TAU
var last_position := Vector3.ZERO    # where it was last frame: the stretch it travelled is checked for the player too
var magnet_speed := 0.0


# Sends out the packs for a heal of `total`: one per HEAL_PER_PACK, the heal shared between them
static func spawn(tree: SceneTree, from_point: Vector3, target: Node3D, total: int, homing: bool) -> void:
	var packs := clampi(ceili(total / float(HEAL_PER_PACK)), 1, 5)
	var left := total
	for i in packs:
		var share := left / (packs - i)
		left -= share
		var pack := KillHealPack.new()
		pack.player = target
		pack.amount = share
		pack.mode = Mode.HOMING if homing else Mode.DROP
		tree.current_scene.add_child(pack)
		pack.global_position = from_point
		pack.last_position = from_point


func _ready() -> void:
	var angle := randf() * TAU
	var spread := POP_SPEED * (0.4 if mode == Mode.HOMING else 0.9)
	velocity = Vector3(cos(angle) * spread * randf_range(0.4, 1.0), POP_LIFT * randf_range(0.8, 1.2), sin(angle) * spread * randf_range(0.4, 1.0))
	model = (load(MEDKIT_SCENE) as PackedScene).instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
	_add_glow()


# The same soft green halo the floor medkits have, so it reads as a health pickup
func _add_glow() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(GLOW_SHADER)
	material.set_shader_parameter("glow_color", GLOW_COLOR)
	material.render_priority = -1
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = material
	var glow := MeshInstance3D.new()
	glow.mesh = quad
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _process(delta: float) -> void:
	age += delta
	if not is_instance_valid(player):
		queue_free()
		return
	if mode == Mode.HOMING:
		_process_homing(delta)
	else:
		_process_drop(delta)


func _process_homing(delta: float) -> void:
	var camera: Camera3D = player.get("camera")
	var target := (camera.global_position if camera else player.global_position + Vector3.UP * 1.4) + Vector3.DOWN * 0.25
	if age >= MAX_LIFE or global_position.distance_to(target) <= ARRIVE_DISTANCE and age > POP_TIME:
		_deliver()
		return
	if age < POP_TIME:
		velocity.y -= GRAVITY * delta
		velocity *= 1.0 - 2.0 * delta
	else:
		speed = minf(speed + ACCELERATION * delta, MAX_SPEED)
		velocity = velocity.lerp((target - global_position).normalized() * speed, minf(delta * 14.0, 1.0))
	global_position += velocity * delta
	model.rotate_y(7.0 * delta)


# Falls to the floor, then bobs and spins in place until the player walks into it
func _process_drop(delta: float) -> void:
	if _collect_or_pull(delta):
		return
	if landed:
		var time_left := DROP_LIFETIME - age
		if time_left <= 0.0:
			queue_free()
			return
		visible = time_left > DROP_WARNING or int(age * 6.0) % 2 == 0
		bob_time += delta
		global_position.y = rest_y + sin(bob_time * 2.0) * 0.08
		model.rotate_y(1.5 * delta)
		return
	if age > FALL_LIMIT:
		queue_free()
		return
	velocity.y -= GRAVITY * delta
	velocity.x *= 1.0 - 2.0 * delta
	velocity.z *= 1.0 - 2.0 * delta
	var next := global_position + velocity * delta
	if velocity.y < 0.0:
		var query := PhysicsRayQueryParameters3D.create(global_position, next + Vector3.DOWN * REST_HEIGHT, PhysicsLayers.ENVIRONMENT)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			landed = true
			rest_y = hit["position"].y + REST_HEIGHT
			global_position = Vector3(next.x, rest_y, next.z)
			return
	global_position = next
	model.rotate_y(7.0 * delta)


# Collected when the player's body touches it (also in the air, and anywhere along the way it moved since last frame, so
# neither a fast pack nor a fast player slips past), and drawn to a player who needs health once they are close and
# nothing solid is between them. Returns whether it did either this frame. A player at full health leaves it alone.
func _collect_or_pull(delta: float) -> bool:
	var swept_from := last_position
	last_position = global_position
	if player.get("health") == null or player.health >= 100:
		magnet_speed = 0.0
		return false
	var body := player.global_position + Vector3.UP * 0.9
	var closest := Geometry3D.get_closest_point_to_segment(body, swept_from, global_position)
	if closest.distance_to(body) <= PICKUP_RADIUS:
		_deliver()
		return true
	if global_position.distance_to(body) <= MAGNET_RADIUS and _clear_path_to(body):
		magnet_speed = clampf(maxf(magnet_speed, MAGNET_START_SPEED) + MAGNET_ACCELERATION * delta, MAGNET_START_SPEED, MAGNET_MAX_SPEED)
		global_position += (body - global_position).normalized() * magnet_speed * delta
		model.rotate_y(7.0 * delta)
		return true
	magnet_speed = 0.0
	return false


func _clear_path_to(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, point, PhysicsLayers.ENVIRONMENT)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _deliver() -> void:
	if is_instance_valid(player) and player.get("health") != null and player.health > 0:
		GlobalVariables.add_health(amount)
		if player.has_method("play_heal_flash"):
			player.play_heal_flash()
		Audio.play(HEAL_SOUND)
	queue_free()
