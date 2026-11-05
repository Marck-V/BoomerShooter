extends EnemyHorde
class_name EnemyBomber

# A glowing runner that goes straight for the player and blows up beside them. It dies quickly and explodes when
# killed, so shooting it early keeps it away from you and can take its neighbours with it.

const BLOOD_PARTICLES = preload("res://scripts/weapons/blood_particles.gd")

@export var fuse_range := 3.5           # starts its fuse this close to the player
@export var fuse_time := 0.8
@export var fuse_move_scale := 0.6      # share of its speed while the fuse burns
@export var blast_radius := 6.0
@export var player_damage := 45.0       # at the centre; half of it at the edge of the blast
@export var enemy_damage := 150.0       # at the centre; half of it at the edge of the blast

const BODY_COLOR := Color(1.0, 0.02, 0.02)
const FLASH_COLOR := Color(2.5, 2.5, 2.5)   # over 1.0 so the glow picks it up
const FLASH_RANGE := 20.0                   # starts flashing this far from the player, faster and whiter as it nears
const FLASH_SPEED_FAR := 5.0
const FLASH_SPEED_NEAR := 16.0
const FLASH_SPEED_FUSE := 45.0
const FLASH_AMOUNT_FAR := 0.2
const LIGHT_ENERGY := 2.5
const LIGHT_RANGE := 6.0
const BEEP_SOUND: AudioStream = preload("res://assets/audio/sfx/enemies/bomber_beep.wav")
const BEEP_VOLUME_DB := -6.0
const BEEP_PITCH_FUSE := 1.25
const CHEST_HEIGHT := 1.0
const SHOCKWAVE_SPEED := 26.0
const MAX_CAMERA_SHAKE := 0.8

var pulse_time := 0.0
var flash_materials: Array[StandardMaterial3D] = []
var flash_light: OmniLight3D
var fuse_progress := 0.0
var beep: AudioStreamPlayer3D
var beep_cycle := 0
var exploded := false


func _ready():
	super()
	lunge_enabled = false
	for material in original_materials:
		if material is StandardMaterial3D:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # bright whatever the room's lighting
			material.albedo_color = BODY_COLOR
			flash_materials.append(material)
	flash_light = OmniLight3D.new()
	flash_light.light_color = BODY_COLOR
	flash_light.omni_range = LIGHT_RANGE
	flash_light.position.y = CHEST_HEIGHT
	add_child(flash_light)
	beep = AudioStreamPlayer3D.new()
	beep.stream = BEEP_SOUND
	beep.bus = &"SFX"
	beep.volume_db = BEEP_VOLUME_DB
	beep.unit_size = 6.0
	beep.max_distance = FLASH_RANGE * 2.0
	beep.attenuation_filter_db = 0.0
	add_child(beep)


func get_state_definitions() -> Dictionary:
	var definitions := super()
	definitions["Fuse"] = FuseState.new(self)
	definitions["Dead"] = BomberDeadState.new(self)
	return definitions


# It takes no attack turns and never circles: the fuse is its attack
func is_in_attack_range() -> bool:
	return false


func chase_destination() -> Vector3:
	return target.global_position


func chase_speed() -> float:
	return movement_speed


func chase_faces_target() -> bool:
	return false


func _is_committed() -> bool:
	return state == states.get("Fuse") or super()


func _update_attack_turn(_delta: float) -> void:
	if destroyed or state != states["Chase"] or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= fuse_range and _has_clear_line(target.global_position):
		change_state("Fuse")


func _process(delta: float) -> void:
	super(delta)
	_update_flash(delta)


# Flashes from red to white: faster and whiter the closer it is to the player, then frantic once the fuse is lit
func _update_flash(delta: float) -> void:
	var fuse_lit: bool = state == states.get("Fuse")
	var nearness := 0.0
	if is_instance_valid(target):
		nearness = 1.0 - clampf((global_position.distance_to(target.global_position) - fuse_range) / (FLASH_RANGE - fuse_range), 0.0, 1.0)
	var speed := lerpf(FLASH_SPEED_NEAR, FLASH_SPEED_FUSE, fuse_progress) if fuse_lit else lerpf(FLASH_SPEED_FAR, FLASH_SPEED_NEAR, nearness)
	var strength := 1.0 if fuse_lit else lerpf(FLASH_AMOUNT_FAR, 1.0, nearness)
	pulse_time += delta * speed
	var flash := strength * (0.5 + 0.5 * sin(pulse_time))
	var color := BODY_COLOR.lerp(FLASH_COLOR, flash)
	for material in flash_materials:
		material.albedo_color = color
	flash_light.light_color = color
	flash_light.light_energy = LIGHT_ENERGY * (1.0 + flash)
	_update_beep(fuse_lit)


# One beep at the top of each flash, so the sound speeds up with it. Only once it is after the player.
func _update_beep(fuse_lit: bool) -> void:
	var cycle := floori((pulse_time - PI / 2.0) / TAU)
	if cycle == beep_cycle:
		return
	beep_cycle = cycle
	if fuse_lit or state == states.get("Chase"):
		beep.pitch_scale = BEEP_PITCH_FUSE if fuse_lit else 1.0
		beep.play()


func _has_clear_line(point: Vector3) -> bool:
	var from := global_position + Vector3.UP * CHEST_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.UP * CHEST_HEIGHT, PhysicsLayers.ENVIRONMENT)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func floor_below() -> Vector3:
	var from := global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, PhysicsLayers.ENVIRONMENT)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else global_position


# Its own fuse ran out: the same end as being shot
func detonate() -> void:
	if destroyed:
		return
	grants_kill_heal = false
	GlobalVariables.enemy_died.emit(self)
	change_state("Dead")


func explode() -> void:
	if exploded or not is_inside_tree():
		return
	exploded = true
	var center := global_position
	_blast_enemies(center)
	_blast_player(center)

	var tree := get_tree()
	var ground := floor_below()
	BossShockwave.spawn(tree, ground, blast_radius, SHOCKWAVE_SPEED, 0.0)   # it does no damage, but throws the player back
	BomberExplosion.spawn(tree, center + Vector3.UP * CHEST_HEIGHT, blast_radius)
	BLOOD_PARTICLES.spawn_burst(tree, center + Vector3.UP * CHEST_HEIGHT, 0.6, BLOOD_PARTICLES.thickness_for(self))
	Audio.play_at(center, "assets/audio/sfx/boss/Boss_Hit1.wav, assets/audio/sfx/boss/Boss_Hit2.wav, assets/audio/sfx/boss/Boss_Hit3.wav")


# Nearer means harder, and walls stop it. Other bombers caught in it go off too.
func _blast_enemies(center: Vector3) -> void:
	for other in get_tree().get_nodes_in_group("Enemy"):
		if other == self or other.get("destroyed") or not other.has_method("damage_silently"):
			continue
		var distance: float = center.distance_to(other.global_position)
		if distance <= blast_radius and _has_clear_line(other.global_position):
			other.damage_silently(enemy_damage * _falloff(distance))


func _blast_player(center: Vector3) -> void:
	if not is_instance_valid(target):
		return
	var distance := center.distance_to(target.global_position)
	if distance > blast_radius * 2.0:
		return
	if target.has_method("add_camera_shake"):
		target.add_camera_shake(MAX_CAMERA_SHAKE * (1.0 - distance / (blast_radius * 2.0)))
	if distance <= blast_radius and _has_clear_line(target.global_position) and target.has_method("damage"):
		target.damage(player_damage * _falloff(distance))


func _falloff(distance: float) -> float:
	return lerpf(1.0, 0.5, clampf(distance / blast_radius, 0.0, 1.0))


# ---------------------------
# States
# ---------------------------
# Glows hard with a warning circle under it, still closing in, then goes off. Running from it works.
class FuseState:
	var enemy
	var time_left := 0.0
	var warning: BossTelegraph

	func _init(e):
		enemy = e

	func enter():
		time_left = enemy.fuse_time
		enemy.fuse_progress = 0.0
		enemy.should_move = false
		enemy.anim.speed_scale = 1.5
		warning = BossTelegraph.circle(enemy.get_tree(), enemy.floor_below(), enemy.blast_radius, BODY_COLOR)

	func update(delta):
		time_left -= delta
		if is_instance_valid(enemy.target):
			enemy.face_target(delta, 4.0)
			var to_target: Vector3 = enemy.target.global_position - enemy.global_position
			to_target.y = 0.0
			if to_target.length() > 1.2:
				enemy.velocity = to_target.normalized() * enemy.movement_speed * enemy.fuse_move_scale
				enemy.move_and_slide()
		warning.global_position = enemy.floor_below() + Vector3.UP * BossTelegraph.FLOOR_LIFT
		enemy.fuse_progress = 1.0 - time_left / enemy.fuse_time
		warning.set_progress(enemy.fuse_progress)
		if time_left <= 0.0:
			enemy.detonate()

	func exit():
		enemy.anim.speed_scale = 1.0
		enemy.velocity = Vector3.ZERO
		if is_instance_valid(warning):
			warning.finish(0.1)


class BomberDeadState:
	var enemy

	func _init(e):
		enemy = e

	func enter():
		enemy.destroyed = true
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		enemy.remove_from_group("Enemy")
		enemy.collision_layer = 0
		enemy.explode()
		enemy.queue_free()
