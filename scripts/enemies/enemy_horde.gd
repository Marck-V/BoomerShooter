extends EnemyBase
class_name EnemyHorde

const ENEMY_STATES = preload("res://scripts/enemies/enemy_states.gd")

@export var damage_to_player: float = 50
@export var attack_cooldown: float = 1.533
@export var melee_range: float = 1.0
# Delay damaging player till animation is at the right part
@export var damage_window_start: float = 0.2
@export var damage_window_end: float = 1.1
@export var vision_range: float = 10.0

@export_group("Lunge")
# While closing in from range the enemy sometimes crouches, dashes and punches. The fist glows yellow for
# the whole lunge, and a parry timed on that punch stuns the enemy. Close up it just uses the normal punch.
@export var lunge_enabled := true
@export var lunge_min_range := 4.0          # closer than this it uses the normal attack
@export var lunge_max_range := 9.0
@export var lunge_windup := 0.55            # crouch while the fist charges up
@export var lunge_dash_time := 0.45         # longest the dash can last
@export var lunge_speed := 15.0
@export var lunge_strike_range := 1.7       # the dash ends and the punch starts at this distance
@export var lunge_follow_through := 0.3     # seconds the punch keeps moving the enemy forward
@export var lunge_reach := 0.9              # ...until it is this close
@export var lunge_shove_speed := 22.0       # how hard a lunge shoves a blocking player aside
@export var lunge_shove_clearance := 2.5    # free space needed on the side the player is shoved towards
@export var lunge_cooldown_min := 3.0
@export var lunge_cooldown_max := 6.0
@export var lunge_windup_animation := "Crouch_Idle"
@export var parry_stun_time := 1.6
@export var parry_stun_damage_multiplier := 1.5

const MAX_SIMULTANEOUS_LUNGES := 2
const AURA_SHADER: Shader = preload("res://shaders/parry_aura.gdshader")
const AURA_COLOR := Color(1.0, 0.75, 0.15)
const GLOW_LIGHT_COLOR := Color(1.0, 0.8, 0.2)

var hit_done := false
var attack_token := 0                       # bumped when an attack is cancelled, so a running attack stops
var parryable := false                      # true while a parry would catch this enemy's punch
var is_stunned := false
var lunging := false
var next_lunge_msec := 0
var glow_root: Node3D                       # holds the aura shells and halo; hidden unless a parryable attack is coming
var glow_inner_material: ShaderMaterial
var glow_outer_material: ShaderMaterial
var glow_halo: MeshInstance3D
var glow_halo_material: StandardMaterial3D
var glow_light: OmniLight3D
var glow_time := 0.0
var glow_strength := 0.0                    # 0..1, ramps up through the wind-up

@onready var attack_timer: Timer = $AttackTimer
@onready var vision_area: Area3D = $VisionArea
@onready var attack_hitbox: Area3D = $Enemy_Model/Rig/Skeleton3D/RightHand/RightAttackHitbox
@onready var debug_sphere: MeshInstance3D = MeshInstance3D.new()


func _ready():
	super()
	vision_area.connect("body_entered", Callable(self, "_on_body_entered"))
	vision_area.connect("body_exited", Callable(self, "_on_body_exited"))
	attack_hitbox.connect("body_entered", Callable(self, "_on_attack_hitbox_body_entered"))

	attack_animation_action = "Sword_Attack"
	attack_idle_animation = "Sword_Idle"
	_build_parry_glow()
	_roll_lunge_cooldown(0.5)

	#draw_debug_gizmos()


func get_state_definitions() -> Dictionary:
	return {
		"Idle": ENEMY_STATES.IdleState.new(self),
		"Chase": ENEMY_STATES.ChaseState.new(self),
		"Attack": ENEMY_STATES.AttackState.new(self),
		"AttackIdle": ENEMY_STATES.AttackIdleState.new(self),
		"Lunge": LungeState.new(self),
		"Stunned": StunnedState.new(self),
		"Dead": ENEMY_STATES.DeadState.new(self),
	}


func _on_body_entered(body: Node3D):
	if body == target:
		change_state("Chase")


func _on_body_exited(body: Node3D):
	if body == target:
		change_state("Idle")


func is_in_attack_range() -> bool:
	if not target:
		return false
	return global_position.distance_to(target.global_position) <= melee_range


func can_attack() -> bool:
	# Ready to attack if cooldown finished
	return attack_timer.is_stopped()


func perform_attack() -> void:
	is_attacking = true
	var token := attack_token

	# Play the attack animation
	anim.play(attack_animation_action)

	# Play hit sounds
	audio_player.play("assets/audio/sfx/enemies/Enemy_Hit1.wav, \
					   assets/audio/sfx/enemies/Enemy_Hit2.wav, \
					   assets/audio/sfx/enemies/Enemy_Hit3.wav")

	# Wait until attack animation reaches "damage window start"
	await get_tree().create_timer(damage_window_start).timeout
	if token != attack_token:
		return  # parried (or otherwise cancelled) before the punch landed

	# Reset hit flag RIGHT before enabling hitbox (not at start of function)
	hit_done = false
	attack_hitbox.monitoring = true

	# Calculate damage window duration
	var damage_duration = max(0.0, damage_window_end - damage_window_start)
	await get_tree().create_timer(damage_duration).timeout
	attack_hitbox.monitoring = false
	if token != attack_token:
		return

	# Wait until the animation finishes fully
	await anim.animation_finished
	if token != attack_token:
		return

	# Start cooldown
	attack_timer.start(attack_cooldown)

	# Allow future attacks
	is_attacking = false


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if body == target and not hit_done:
		# A lunge is not stopped by a block: the player is shoved out of its way and takes the reduced damage
		if lunging and body.get("shield_blocking") == true:
			_shove_blocking_player(body)
		if body.has_method("damage"):
			body.damage(damage_to_player)

		hit_done = true


func _shove_blocking_player(player: Node3D) -> void:
	var heading := player.global_position - global_position
	heading.y = 0.0
	heading = heading.normalized() if heading.length() > 0.001 else -global_basis.z
	var side := heading.cross(Vector3.UP)
	if randf() < 0.5:
		side = -side
	# Prefer a side with room to be shoved into
	var chest := player.global_position + Vector3.UP
	for candidate in [side, -side]:
		var query := PhysicsRayQueryParameters3D.create(chest, chest + candidate * lunge_shove_clearance)
		query.exclude = [player, self]
		query.collision_mask = 1 | 2
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			side = candidate
			break
	if player.has_method("apply_push"):
		player.apply_push(side * lunge_shove_speed + heading * lunge_shove_speed * 0.2)
	if player.has_method("apply_camera_kick"):
		player.apply_camera_kick(0.05, randf_range(-0.03, 0.03))
	var player_shield = player.get("offhand_shield")
	if player_shield != null and player_shield.has_method("on_block_hit"):
		player_shield.on_block_hit(global_position.lerp(player.global_position, 0.7) + Vector3.UP * 1.2)


# ---------------------------
# Lunge
# ---------------------------
func _roll_lunge_cooldown(min_seconds := -1.0) -> void:
	var seconds := randf_range(lunge_cooldown_min, lunge_cooldown_max) if min_seconds < 0.0 else randf_range(min_seconds, lunge_cooldown_max)
	next_lunge_msec = Time.get_ticks_msec() + int(seconds * 1000.0)


# Asked by the chase state every frame: lunge when closing in from range, with a clear path and not too many at once
func should_lunge() -> bool:
	if not lunge_enabled or is_attacking or is_stunned or not is_instance_valid(target):
		return false
	if Time.get_ticks_msec() < next_lunge_msec:
		return false
	var distance := global_position.distance_to(target.global_position)
	if distance < lunge_min_range or distance > lunge_max_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP)
	query.exclude = [self]
	query.collision_mask = 1 | 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") != target:
		return false
	var active := 0
	for other in get_tree().get_nodes_in_group("Enemy"):
		if other != self and other.get("lunging") == true:
			active += 1
	return active < MAX_SIMULTANEOUS_LUNGES


# Turns towards the target on the spot (the model faces +Z, hence the extra half turn)
func face_target(delta: float, speed_multiplier := 2.0) -> void:
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return
	var target_basis := Basis.looking_at(to_target.normalized(), Vector3.UP).rotated(Vector3.UP, deg_to_rad(180))
	global_transform.basis = global_transform.basis.slerp(target_basis, clampf(delta * rotation_speed * speed_multiplier, 0.0, 1.0))


# Called by the player's shield when a parry catches the punch: cancels the attack and stuns the enemy
func on_parried() -> void:
	attack_token += 1
	parryable = false
	hit_done = true
	attack_hitbox.set_deferred("monitoring", false)
	is_attacking = false
	attack_timer.start(attack_cooldown)
	change_state("Stunned")


func damage(amount: float, multiplier: float = 1.0):
	super(amount, multiplier * (parry_stun_damage_multiplier if is_stunned else 1.0))


# ---------------------------
# Yellow fist aura: the sign that this punch can be parried
# ---------------------------
# Two rim-lit shells and a soft ring halo around the fist, so the hand itself stays visible inside the glow.
func _build_parry_glow() -> void:
	var hand := get_node_or_null("Enemy_Model/Rig/Skeleton3D/RightHand")
	if hand == null:
		return
	glow_root = Node3D.new()
	glow_root.visible = false
	hand.add_child(glow_root)

	glow_inner_material = _make_aura_material(2.0, 0.0)
	glow_outer_material = _make_aura_material(3.2, 1.7)
	glow_root.add_child(_make_aura_shell(0.13, glow_inner_material))
	glow_root.add_child(_make_aura_shell(0.21, glow_outer_material))

	# A soft ring that always faces the camera, with an empty centre so it never covers the fist
	var ring := Gradient.new()
	ring.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.8, 1.0])
	ring.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = ring
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	glow_halo_material = StandardMaterial3D.new()
	glow_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_halo_material.albedo_texture = texture
	glow_halo_material.albedo_color = Color(AURA_COLOR * 2.0, 0.0)
	glow_halo_material.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	glow_halo = MeshInstance3D.new()
	glow_halo.mesh = quad
	glow_halo.material_override = glow_halo_material
	glow_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_root.add_child(glow_halo)

	glow_light = OmniLight3D.new()
	glow_light.light_color = GLOW_LIGHT_COLOR
	glow_light.omni_range = 2.0
	glow_light.light_energy = 0.0
	glow_light.shadow_enabled = false
	glow_root.add_child(glow_light)


func _make_aura_material(rim_power: float, phase: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = AURA_SHADER
	material.set_shader_parameter("aura_color", AURA_COLOR)
	material.set_shader_parameter("rim_power", rim_power)
	material.set_shader_parameter("phase", phase)
	material.set_shader_parameter("intensity", 0.0)
	return material


func _make_aura_shell(radius: float, material: ShaderMaterial) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var shell := MeshInstance3D.new()
	shell.mesh = sphere
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shell


func set_parry_glow(enabled: bool) -> void:
	if glow_root == null:
		return
	glow_root.visible = enabled
	if not enabled:
		glow_strength = 0.0


func _process(delta: float) -> void:
	if glow_root == null or not glow_root.visible:
		return
	glow_time += delta
	# Builds up through the wind-up and pulses faster and brighter as the punch gets closer
	var pulse := 1.0 + 0.12 * sin(glow_time * (12.0 + glow_strength * 10.0))
	glow_root.scale = Vector3.ONE * (0.75 + 0.35 * glow_strength) * pulse
	glow_inner_material.set_shader_parameter("intensity", 0.3 + 0.9 * glow_strength)
	glow_outer_material.set_shader_parameter("intensity", 0.12 + 0.6 * glow_strength)
	glow_halo.scale = Vector3.ONE * (0.8 + 0.4 * glow_strength) * pulse
	glow_halo_material.albedo_color = Color(AURA_COLOR * 1.6, 0.1 + 0.4 * glow_strength)
	glow_light.light_energy = 1.0 * glow_strength


func draw_debug_gizmos():
	if OS.is_debug_build() and debug:  # only show in debug mode
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = vision_range
		sphere_mesh.radial_segments = 24
		sphere_mesh.rings = 16
		debug_sphere.mesh = sphere_mesh

		# Transparent material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 1, 0, 0.2)  # semi-transparent green
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_sphere.material_override = mat

		# Attach sphere to vision_area so it moves with the enemy
		vision_area.add_child(debug_sphere)
		debug_sphere.position = Vector3.ZERO


func _on_attack_cooldown_timeout() -> void:
	hit_done = false


# ---------------------------
# States
# ---------------------------
# Crouch with a charging fist, dash at the player, then the normal punch as the finishing blow.
class LungeState:
	enum Phase { WINDUP, DASH, STRIKE }

	var enemy
	var phase := Phase.WINDUP
	var timer := 0.0
	var phase_time := 0.0

	func _init(e):
		enemy = e

	func enter():
		enemy.velocity = Vector3.ZERO
		enemy.should_move = false
		enemy.lunging = true
		enemy.glow_time = 0.0
		enemy.glow_strength = 0.0
		enemy.set_parry_glow(true)
		phase = Phase.WINDUP
		timer = enemy.lunge_windup
		phase_time = 0.0
		var windup_animation: String = enemy.lunge_windup_animation
		enemy.anim.play(windup_animation if enemy.anim.has_animation(windup_animation) else "Idle")

	func update(delta):
		if not is_instance_valid(enemy.target):
			enemy.change_state("Idle")
			return
		match phase:
			Phase.WINDUP:
				enemy.face_target(delta, 4.0)
				timer -= delta
				enemy.glow_strength = clampf(1.0 - timer / maxf(enemy.lunge_windup, 0.01), 0.0, 1.0)
				if timer <= 0.0:
					phase = Phase.DASH
					timer = enemy.lunge_dash_time
					enemy.glow_strength = 1.0
					enemy.parryable = true
					enemy.anim.play("Sprint")
					enemy.anim.speed_scale = 1.4
			Phase.DASH:
				enemy.face_target(delta, 4.0)
				var to_target: Vector3 = enemy.target.global_position - enemy.global_position
				to_target.y = 0.0
				timer -= delta
				if to_target.length() <= enemy.lunge_strike_range or timer <= 0.0:
					enemy.anim.speed_scale = 1.0
					enemy.velocity = Vector3.ZERO
					phase = Phase.STRIKE
					enemy.perform_attack()  # the normal punch: its damage window is what a parry has to catch
					return
				enemy.velocity = to_target.normalized() * enemy.lunge_speed
				enemy.move_and_slide()
			Phase.STRIKE:
				enemy.face_target(delta, 2.0)
				# The punch carries the enemy the last bit of the way, so it actually connects
				phase_time += delta
				var to_target: Vector3 = enemy.target.global_position - enemy.global_position
				to_target.y = 0.0
				if phase_time < enemy.lunge_follow_through and to_target.length() > enemy.lunge_reach:
					enemy.velocity = to_target.normalized() * enemy.lunge_speed * 0.5
					enemy.move_and_slide()
				if not enemy.is_attacking:
					enemy.change_state("Chase")

	func exit():
		enemy.lunging = false
		enemy.parryable = false
		enemy.set_parry_glow(false)
		enemy.anim.speed_scale = 1.0
		enemy.velocity = Vector3.ZERO
		enemy._roll_lunge_cooldown()


# Dazed after a parry: knocked back, then stands up and carries on. Takes extra damage while dazed.
class StunnedState:
	var enemy
	var timer := 0.0
	var knockback := Vector3.ZERO

	func _init(e):
		enemy = e

	func enter():
		enemy.is_stunned = true
		enemy.should_move = false
		timer = enemy.parry_stun_time
		var away: Vector3 = enemy.global_position - enemy.target.global_position if is_instance_valid(enemy.target) else -enemy.global_basis.z
		away.y = 0.0
		knockback = away.normalized() * 7.0
		enemy.anim.play("Hit_Chest")
		enemy.anim.queue("Idle")

	func update(delta):
		timer -= delta
		knockback = knockback.move_toward(Vector3.ZERO, 22.0 * delta)
		enemy.velocity = knockback
		enemy.move_and_slide()
		if timer <= 0.0:
			enemy.change_state("Chase")

	func exit():
		enemy.is_stunned = false
		enemy.velocity = Vector3.ZERO
