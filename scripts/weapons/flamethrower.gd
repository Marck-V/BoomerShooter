extends BaseWeapon

const FlameEffect = preload("res://scripts/weapons/flame_effect.gd")
const Burning = preload("res://scripts/enemies/burning.gd")

const WORLD_MASK := 2
const FLAME_LINGER := 0.16        # seconds the flame keeps burning after the last trigger tick
const TICKS_PER_AMMO := 3         # one ammo unit buys this many damage ticks (10 ticks/sec)
const CONE_BASE_RADIUS := 0.5     # meters, flame width at the nozzle
const CONE_SPREAD := 0.17         # extra meters of width per meter of distance
const TARGET_HEIGHT := 1.0        # aim at the enemy chest, not its feet
const BURN_DURATION := 3.0        # seconds an enemy keeps burning after the flame leaves it
const BURN_DPS := 6.0             # damage per second while burning

# Flame audio. The clip is a quiet lead-in, an ignition swell, a steady burn, a second flare, more steady
# burn and then the ending. Firing starts it just before the ignition, repeats a steady stretch of the burn
# for as long as the trigger is held, and jumps to the ending when it is released. Times are in seconds.
const FLAME_SOUND: AudioStream = preload("res://assets/sounds/flamethrower.mp3")
const SOUND_INTRO_START := 0.72   # skips the silent lead-in so the sound answers the click straight away
const SOUND_INTRO_MIN := 1.3      # a quick tap still plays the whole ignition swell before the ending
const SOUND_LOOP_START := 1.55    # the steady burn that repeats while firing...
const SOUND_LOOP_END := 3.55      # ...and where it wraps back to the start
const SOUND_TAIL_START := 5.8     # the ending, played when the trigger is released
const SOUND_CROSSFADE := 0.08     # blend time at every jump, so the loop and the ending don't click
const SOUND_TAIL_FADE := 0.4      # the ending fades out over its last stretch instead of cutting off
const SOUND_VOLUME_DB := -8.0
const SOUND_SILENT_DB := -60.0

enum SoundState { IDLE, ACTIVE, TAIL }

var flame: Node3D
var last_fire_msec := -10000
var tick_count := 0
var out_of_fuel := false

var sound_state := SoundState.IDLE
var sound_players: Array[AudioStreamPlayer] = []
var sound_current := 0
var sound_tweens := {}   # player -> its running fade
var sound_tail_tween: Tween


func _ready() -> void:
	super._ready()
	flame = FlameEffect.new()
	muzzle_location.add_child(flame)
	_filter_model_nearest()
	_build_sound()


# ---------------------------------------------------------------- flame audio

# Two players: every jump (loop wrap, the ending) starts the new part on the idle one and crossfades into it
func _build_sound() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.stream = FLAME_SOUND
		player.bus = &"SFX"
		player.volume_db = SOUND_SILENT_DB
		add_child(player)
		sound_players.append(player)


func _update_sound(burning: bool) -> void:
	match sound_state:
		SoundState.IDLE:
			if burning:
				_start_sound()
		SoundState.ACTIVE:
			if not sound_players[sound_current].playing:
				sound_state = SoundState.IDLE   # stopped from outside (tree paused, node freed...): start over next time
				return
			var playhead := _sound_position(sound_players[sound_current])
			# Released: go to the ending, but only after the ignition swell has had its moment
			if not burning and playhead >= SOUND_INTRO_MIN:
				_end_sound()
			elif playhead >= SOUND_LOOP_END:
				_jump_sound(SOUND_LOOP_START)
		SoundState.TAIL:
			if burning:
				_start_sound()   # fired again while the ending was still playing
			elif not sound_players[sound_current].playing:
				sound_state = SoundState.IDLE


func _start_sound() -> void:
	sound_state = SoundState.ACTIVE
	_jump_sound(SOUND_INTRO_START)


func _end_sound() -> void:
	sound_state = SoundState.TAIL
	var player := _jump_sound(SOUND_TAIL_START)
	# Fade the ending out over its last stretch instead of cutting off
	var remaining := FLAME_SOUND.get_length() - SOUND_TAIL_START
	sound_tail_tween = create_tween()
	sound_tail_tween.tween_interval(maxf(remaining - SOUND_TAIL_FADE, SOUND_CROSSFADE))
	sound_tail_tween.tween_property(player, "volume_db", SOUND_SILENT_DB, SOUND_TAIL_FADE)
	sound_tail_tween.tween_callback(player.stop)


# Starts the clip at `from` on the idle player, fading it in while the one that was playing fades out
func _jump_sound(from: float) -> AudioStreamPlayer:
	if sound_tail_tween != null and sound_tail_tween.is_valid():
		sound_tail_tween.kill()   # it belongs to the player that is about to be reused
	var outgoing := sound_players[sound_current]
	sound_current = 1 - sound_current
	var incoming := sound_players[sound_current]
	incoming.volume_db = SOUND_SILENT_DB
	incoming.play(from)
	_fade_sound(incoming, SOUND_VOLUME_DB, SOUND_CROSSFADE, false)
	if outgoing.playing:
		_fade_sound(outgoing, SOUND_SILENT_DB, SOUND_CROSSFADE, true)
	return incoming


# Only one fade per player at a time: a new one cancels the old
func _fade_sound(player: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool) -> void:
	if sound_tweens.has(player) and sound_tweens[player].is_valid():
		sound_tweens[player].kill()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, seconds)
	if stop_after:
		tween.tween_callback(player.stop)
	sound_tweens[player] = tween


# Switching weapons hides this one and stops its processing, so nothing would loop or end the sound any more
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_silence_sound()


func _silence_sound() -> void:
	if sound_players.is_empty():
		return
	if sound_tail_tween != null and sound_tail_tween.is_valid():
		sound_tail_tween.kill()
	for player in sound_players:
		if player.playing:
			_fade_sound(player, SOUND_SILENT_DB, 0.1, true)
	sound_state = SoundState.IDLE


func _sound_position(player: AudioStreamPlayer) -> float:
	if not player.playing:
		return 0.0
	return player.get_playback_position() + AudioServer.get_time_since_last_mix()


# PSX look: no texture smoothing on the gun model
func _filter_model_nearest() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if material == null:
				continue
			var copy := material.duplicate() as StandardMaterial3D
			copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh_instance.set_surface_override_material(i, copy)


func _process(delta: float) -> void:
	super._process(delta)
	var burning := (Time.get_ticks_msec() - last_fire_msec) < FLAME_LINGER * 1000.0
	flame.set_burning(burning)
	_update_sound(burning)


func fire(_origin: Vector3, _direction: Vector3, camera: Camera3D, _raycast: RayCast3D) -> void:
	if !data:
		return

	# Fuel is drained every few ticks so a tank lasts a few seconds of continuous fire
	if tick_count % TICKS_PER_AMMO == 0:
		if not GlobalVariables.spend_ammo(GlobalVariables.current_weapon, 1):
			if not out_of_fuel:
				Audio.play("assets/sounds/empty_gun.mp3")
				out_of_fuel = true
			return
	out_of_fuel = false
	tick_count += 1
	last_fire_msec = Time.get_ticks_msec()
	trigger_recoil()

	_burn_enemies_in_cone(camera)


# The flame is a cone, not a ray: everything in front of the nozzle and in line of sight takes damage
func _burn_enemies_in_cone(camera: Camera3D) -> void:
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := camera.get_world_3d().direct_space_state

	for candidate in get_tree().get_nodes_in_group("Enemy"):
		var enemy := candidate as Node3D
		if enemy == null or not enemy.has_method("damage") or enemy.get("destroyed"):
			continue

		var target := enemy.global_position + Vector3.UP * TARGET_HEIGHT
		var to_target := target - origin
		var along := to_target.dot(forward)
		if along < 0.0 or along > data.max_distance:
			continue
		var off_axis := (to_target - forward * along).length()
		if off_axis > CONE_BASE_RADIUS + along * CONE_SPREAD:
			continue

		var query := PhysicsRayQueryParameters3D.create(origin, target, WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			continue

		enemy.damage(data.damage)
		_ignite(enemy)


# Sets the enemy on fire (or refreshes its burn). A live shield keeps the fire off.
func _ignite(enemy: Node3D) -> void:
	var shield = enemy.get("shield")
	if shield != null and is_instance_valid(shield):
		return
	if enemy.get("destroyed") == true:
		return
	var burning = enemy.get_node_or_null("Burning")
	if burning == null:
		burning = Burning.new()
		burning.name = "Burning"
		enemy.add_child(burning)
	burning.ignite(BURN_DURATION, BURN_DPS)
